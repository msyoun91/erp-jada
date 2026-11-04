-- Verificación de sql/160: paquetes, versiones y su contenido. NO es una migración: todo corre dentro de una
-- transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Lucia (Técnica: Paquetes con armar, Insumos con cargar), Ana (Administración: Insumos con costos,
-- Servicios fijos con editar), Carlos (gerente: Paquetes con aprobar), Marta (Insumos con cargar, sin Paquetes),
-- Rodrigo (solo Paquetes, revisa cortes) y Juan (nada). Lo creado lleva Zqx160.
--
-- Las funciones que cambian el estado de una versión están en sql/162, con su test: acá lo cambia el dueño, con pg_temp.a.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.l(p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT quote_literal(pg_temp.id(p_nombre));
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

CREATE FUNCTION pg_temp.consultar(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql INTO v_out;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_out;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT count(*)::text FROM (%s) x', p_sql), p_como);
$f$;

-- Corre como p_como, guarda el uuid que devuelve p_sql con el nombre p_nombre y anota si salió.
CREATE FUNCTION pg_temp.crear(p_nombre text, p_sql text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.consultar(p_sql, p_como);
BEGIN
  PERFORM pg_temp.caso('crear ' || p_nombre, 'uuid',
    CASE WHEN v ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE v END);
  IF v ~ '^[0-9a-f-]{36}$' THEN
    INSERT INTO ids VALUES (p_nombre, v::uuid);
  END IF;
END;
$f$;

CREATE FUNCTION pg_temp.ins(p_tabla text, p_version text, p_cols text, p_vals text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('INSERT INTO %I (version_id, %s) VALUES (%s, %s) RETURNING id', p_tabla, p_cols, pg_temp.l(p_version), p_vals);
$f$;

CREATE FUNCTION pg_temp.upd(p_tabla text, p_nombre text, p_set text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('UPDATE %I SET %s WHERE id = %s', p_tabla, p_set, pg_temp.l(p_nombre));
$f$;

CREATE FUNCTION pg_temp.alta(p_nombre text, p_categoria text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('SELECT catalogo_paquete_alta(%L, %s)', p_nombre, pg_temp.l(p_categoria));
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text, p_peso text DEFAULT 'NULL', p_espesor text DEFAULT 'NULL')
RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, %s, %s)',
    'Zqx160 ' || p_nombre, pg_temp.l(p_categoria), p_unidad, p_peso, p_espesor));
$f$;

CREATE FUNCTION pg_temp.categoria(p_nombre text, p_tipo text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('INSERT INTO catalogo_categorias (tipo, nombre) VALUES (%L, %L) RETURNING id',
    p_tipo, 'Zqx160 ' || p_nombre), p_como);
$f$;

-- El estado lo cambia el dueño: los errores que vienen de los índices se devuelven.
CREATE FUNCTION pg_temp.estado(p_version text, p_estado text) RETURNS text LANGUAGE plpgsql AS $f$
BEGIN
  UPDATE catalogo_versiones SET estado = p_estado::estado_version_catalogo WHERE id = pg_temp.id(p_version);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.a(p_version text, p_estado text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso('pasar ' || p_version || ' a ' || p_estado, 'ok', pg_temp.estado(p_version, p_estado));
$f$;

CREATE FUNCTION pg_temp.activo(p_tabla text, p_nombre text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v text;
BEGIN
  EXECUTE format('SELECT activo::text FROM %I WHERE id = %s', p_tabla, pg_temp.l(p_nombre)) INTO v;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.cuenta(p_tabla text, p_version text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v text;
BEGIN
  EXECUTE format('SELECT count(*)::text FROM %I WHERE version_id = %s AND activo', p_tabla, pg_temp.l(p_version)) INTO v;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.campo(p_tabla text, p_nombre text, p_expr text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v text;
BEGIN
  EXECUTE format('SELECT (%s)::text FROM %I WHERE id = %s', p_expr, p_tabla, pg_temp.l(p_nombre)) INTO v;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.variante(p_insumo text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT v.id FROM catalogo_variantes v WHERE v.insumo_id = pg_temp.id(p_insumo) AND v.color_id IS NULL;
$f$;

CREATE FUNCTION pg_temp.paquete(p_version text, p_nombre text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO ids SELECT p_nombre, v.paquete_id FROM catalogo_versiones v WHERE v.id = pg_temp.id(p_version);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Lucia','Ana','Carlos','Marta','Rodrigo','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND modulo = 'catalogo';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test160.local', jsonb_build_object('nombre', 'test160 ' || nombre)
FROM ids WHERE nombre IN ('Lucia','Ana','Carlos','Marta','Rodrigo','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Ana','catalogo_insumos'), ('Ana','catalogo_costos'), ('Ana','catalogo_fijos'), ('Ana','catalogo_fijos_editar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar'),
  ('Marta','catalogo_insumos'), ('Marta','catalogo_cargar'),
  ('Rodrigo','catalogo_paquetes')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.categoria('Perfiles', 'insumo');
SELECT pg_temp.categoria('Vidrios', 'insumo');
SELECT pg_temp.categoria('Ventanas', 'paquete');
SELECT pg_temp.categoria('Puertas', 'paquete');
SELECT pg_temp.categoria('Manos', 'servicio', 'Ana');

SELECT pg_temp.crear('Blanco', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx160 Blanco') RETURNING id$q$);
SELECT pg_temp.crear('Negro', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx160 Negro') RETURNING id$q$);

SELECT pg_temp.crear('Perfil', format($q$SELECT catalogo_insumo_alta('Zqx160 Perfil', %s, 'mm', 0.7, NULL, ARRAY[%s, %s]::uuid[])$q$,
  pg_temp.l('Perfiles'), pg_temp.l('Blanco'), pg_temp.l('Negro')));
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2', '10', '4');
SELECT pg_temp.insumo('Laminado', 'Vidrios', 'm2', '15', '6');
SELECT pg_temp.insumo('DVH', 'Vidrios', 'm2');
SELECT pg_temp.insumo('Contra4', 'Perfiles', 'mm', '0.2');
SELECT pg_temp.insumo('Contra6', 'Perfiles', 'mm', '0.2');
SELECT pg_temp.insumo('RuedaA', 'Perfiles', 'u', '0.05');
SELECT pg_temp.insumo('RuedaB', 'Perfiles', 'u', '0.05');
SELECT pg_temp.crear('Soldado', format($q$SELECT catalogo_fijo_alta('Zqx160 Soldado', %s, 'u', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');

-- ============================================================
-- 01. Alta: el paquete con su v1 en borrador
-- ============================================================
SELECT pg_temp.crear('V1', pg_temp.alta('Zqx160 Ventana', 'Ventanas'));
SELECT pg_temp.paquete('V1', 'P1');
SELECT pg_temp.caso('01 nace v1', '1', pg_temp.campo('catalogo_versiones', 'V1', 'numero'));
SELECT pg_temp.caso('01 nace en borrador', 'borrador', pg_temp.campo('catalogo_versiones', 'V1', 'estado'));
SELECT pg_temp.caso('01 un borrador no cuenta como enviada', 'false', pg_temp.campo('catalogo_versiones', 'V1', 'enviada'));
SELECT pg_temp.caso('01 el paquete nace activo', 'true', pg_temp.activo('catalogo_paquetes', 'P1'));
SELECT pg_temp.caso('01 nace vacío', '0', pg_temp.cuenta('catalogo_piezas', 'V1'));

SELECT pg_temp.caso('01 Rodrigo no da de alta', '42501', pg_temp.intentar(pg_temp.alta('Zqx160 No', 'Ventanas'), 'Rodrigo'));
SELECT pg_temp.caso('01 Carlos no da de alta', '42501', pg_temp.intentar(pg_temp.alta('Zqx160 No', 'Ventanas'), 'Carlos'));
SELECT pg_temp.caso('01 Ana no da de alta', '42501', pg_temp.intentar(pg_temp.alta('Zqx160 No', 'Ventanas'), 'Ana'));
SELECT pg_temp.caso('01 Juan no da de alta', '42501', pg_temp.intentar(pg_temp.alta('Zqx160 No', 'Ventanas'), 'Juan'));
SELECT pg_temp.caso('01 no entra en una categoría de insumo', '23503', pg_temp.intentar(pg_temp.alta('Zqx160 No', 'Vidrios'), 'Lucia'));
SELECT pg_temp.caso('01 nombre con espacios sobrantes', '23514', pg_temp.intentar(pg_temp.alta(' Zqx160 No', 'Ventanas'), 'Lucia'));
SELECT pg_temp.caso('01 nombre vacío', '23514', pg_temp.intentar(pg_temp.alta('', 'Ventanas'), 'Lucia'));

SELECT pg_temp.caso('01 Lucia no elige el estado al insertar', '42501', pg_temp.intentar(format(
  $q$INSERT INTO catalogo_versiones (paquete_id, nombre, categoria_id, estado) VALUES (%s, 'Zqx160 No', %s, 'publicado')$q$,
  pg_temp.l('P1'), pg_temp.l('Ventanas')), 'Lucia'));
SELECT pg_temp.caso('01 Lucia no elige el número', '42501', pg_temp.intentar(format(
  $q$INSERT INTO catalogo_versiones (paquete_id, nombre, categoria_id, numero) VALUES (%s, 'Zqx160 No', %s, 9)$q$,
  pg_temp.l('P1'), pg_temp.l('Ventanas')), 'Lucia'));
SELECT pg_temp.caso('01 Lucia no cambia el estado', '42501', pg_temp.intentar(
  pg_temp.upd('catalogo_versiones', 'V1', $q$estado = 'publicado'$q$), 'Lucia'));
SELECT pg_temp.caso('01 Lucia no cambia el número', '42501', pg_temp.intentar(
  pg_temp.upd('catalogo_versiones', 'V1', 'numero = 9'), 'Lucia'));
SELECT pg_temp.caso('01 Lucia no cambia el paquete', '42501', pg_temp.intentar(
  pg_temp.upd('catalogo_versiones', 'V1', format('paquete_id = %s', pg_temp.l('P1'))), 'Lucia'));
SELECT pg_temp.caso('01 una sola abierta, también directo', '23505', pg_temp.intentar(format(
  $q$INSERT INTO catalogo_versiones (paquete_id, nombre, categoria_id) VALUES (%s, 'Zqx160 Otra', %s)$q$,
  pg_temp.l('P1'), pg_temp.l('Ventanas')), 'Lucia'));

SELECT pg_temp.crear('VOtra', pg_temp.alta('Zqx160 Otra', 'Puertas'));
SELECT pg_temp.paquete('VOtra', 'POtraPaq');

-- ============================================================
-- 02. El contenido, con sus fórmulas
-- ============================================================
SELECT pg_temp.crear('Marco', pg_temp.ins('catalogo_piezas', 'V1', 'nombre, orden', $q$'Marco', 1$q$));
SELECT pg_temp.crear('Hoja', pg_temp.ins('catalogo_piezas', 'V1', 'nombre, cantidad, calcula_espesor', $q$'Hoja', '2', true$q$));
SELECT pg_temp.crear('Mosquitero', pg_temp.ins('catalogo_piezas', 'V1', 'nombre, opcional', $q$'Mosquitero', true$q$));
SELECT pg_temp.crear('Cajon', pg_temp.ins('catalogo_piezas', 'V1', 'nombre, opcional', $q$'Cajon', true$q$));
SELECT pg_temp.crear('Cortina', pg_temp.ins('catalogo_piezas', 'V1', 'nombre, opcional, incluida, requiere_pieza_id, secundario',
  format($q$'Cortina', true, true, %s, true$q$, pg_temp.l('Cajon'))));

SELECT pg_temp.crear('ancho', pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, minimo, maximo', $q$'ancho', true, 300, 3000$q$));
SELECT pg_temp.crear('alto', pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, minimo, maximo', $q$'alto', true, 300, 3000$q$));
SELECT pg_temp.crear('mano', pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, es_lista, valores, valor_predeterminado',
  $q$'mano', true, true, ARRAY['Izquierda','Derecha'], 'Izquierda'$q$));
SELECT pg_temp.crear('travesanos', pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, es_cantidad, minimo, maximo',
  $q$'travesanos', true, true, 0, 3$q$));
SELECT pg_temp.crear('radio', pg_temp.ins('catalogo_variables', 'V1', 'nombre, formula, a_produccion', $q$'radio', 'ancho / 2', false$q$));
SELECT pg_temp.crear('hoja1', pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, formula, secundario',
  $q$'ancho_hoja_1', true, '(ancho + 50) / 2', true$q$));
SELECT pg_temp.crear('ancho_hoja', pg_temp.ins('catalogo_variables', 'V1', 'nombre, pieza_id, formula',
  format($q$'ancho_hoja', %s, 'ancho / 2'$q$, pg_temp.l('Hoja'))));

SELECT pg_temp.crear('MPerfil1', pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, insumo_id, medida, cantidad',
  format($q$%s, %s, 'ancho - 2', '2'$q$, pg_temp.l('Marco'), pg_temp.l('Perfil'))));
SELECT pg_temp.crear('MPerfil2', pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, insumo_id, medida, cantidad',
  format($q$%s, %s, 'alto - 2', '2'$q$, pg_temp.l('Marco'), pg_temp.l('Perfil'))));
SELECT pg_temp.crear('MSoldado', pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, insumo_id, cantidad, cuenta_peso',
  format($q$%s, %s, '4', false$q$, pg_temp.l('Marco'), pg_temp.l('Soldado'))));
SELECT pg_temp.crear('MVidrio', pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, ancho, alto, cuenta_espesor',
  format($q$%s, 'elige_vendedor', 'Vidrio', 'ancho_hoja - 48', 'alto - 48', true$q$, pg_temp.l('Hoja'))));
SELECT pg_temp.crear('MContra', pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, sigue_material_id, medida',
  format($q$%s, 'sigue', 'Contravidrio', %s, '2 * ancho_hoja'$q$, pg_temp.l('Hoja'), pg_temp.l('MVidrio'))));
SELECT pg_temp.crear('MRueda', pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, eleccion, cantidad',
  format($q$%s, 'elige_sistema', 'Rueda', 'si [peso Hoja] > 40 entonces [Zqx160 RuedaB] si no [Zqx160 RuedaA]', '2'$q$, pg_temp.l('Hoja'))));

SELECT pg_temp.crear('OFloat', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id, predeterminada',
  format('%s, %s, true', pg_temp.l('MVidrio'), pg_temp.l('Float'))));
SELECT pg_temp.crear('OLam', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id, cantidad',
  format($q$%s, %s, '2'$q$, pg_temp.l('MVidrio'), pg_temp.l('Laminado'))));
SELECT pg_temp.crear('ODvh', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id',
  format('%s, %s', pg_temp.l('MVidrio'), pg_temp.l('DVH'))));
SELECT pg_temp.crear('OC4', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id, sigue_opcion_id',
  format('%s, %s, %s', pg_temp.l('MContra'), pg_temp.l('Contra4'), pg_temp.l('OFloat'))));
SELECT pg_temp.crear('OC6', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id, sigue_opcion_id',
  format('%s, %s, %s', pg_temp.l('MContra'), pg_temp.l('Contra6'), pg_temp.l('OLam'))));
SELECT pg_temp.crear('ONinguna', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, sigue_opcion_id',
  format('%s, %s', pg_temp.l('MContra'), pg_temp.l('ODvh'))));
SELECT pg_temp.crear('ORA', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id',
  format('%s, %s', pg_temp.l('MRueda'), pg_temp.l('RuedaA'))));
SELECT pg_temp.crear('ORB', pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id',
  format('%s, %s', pg_temp.l('MRueda'), pg_temp.l('RuedaB'))));

SELECT pg_temp.crear('CVar', pg_temp.ins('catalogo_condiciones', 'V1', 'variable_id, condicion, mensaje',
  format($q$%s, 'ancho > 2000', 'Ancho grande'$q$, pg_temp.l('ancho'))));
SELECT pg_temp.crear('CMat', pg_temp.ins('catalogo_condiciones', 'V1', 'material_id, condicion, mensaje, bloquea',
  format($q$%s, 'alto > ancho * 2', 'Muy alto', true$q$, pg_temp.l('MVidrio'))));
SELECT pg_temp.crear('COpc', pg_temp.ins('catalogo_condiciones', 'V1', 'opcion_id, condicion, mensaje, bloquea',
  format($q$%s, 'ancho * alto > 2000000', 'Float hasta 2 m2', true$q$, pg_temp.l('OFloat'))));

SELECT pg_temp.crear('Chica', pg_temp.ins('catalogo_casos', 'V1', 'nombre, entrada', $q$'Chica', '{"variables":{"ancho":600,"alto":600}}'$q$));
SELECT pg_temp.crear('CBlanco', pg_temp.ins('catalogo_versiones_colores', 'V1', 'color_id, base', format('%s, true', pg_temp.l('Blanco'))));
SELECT pg_temp.crear('CNegro', pg_temp.ins('catalogo_versiones_colores', 'V1', 'color_id', pg_temp.l('Negro')));

SELECT pg_temp.caso('02 la cantidad de la pieza es 1 por defecto', '1', pg_temp.campo('catalogo_piezas', 'Marco', 'cantidad'));
SELECT pg_temp.caso('02 y tiene su árbol', 'num', pg_temp.campo('catalogo_piezas', 'Marco', $q$cantidad_arbol ->> 'op'$q$));
SELECT pg_temp.caso('02 la cantidad del material es 1 por defecto', '1', pg_temp.campo('catalogo_materiales', 'MVidrio', 'cantidad'));
SELECT pg_temp.caso('02 la medida se calcula desde su árbol', '1498', pg_temp.campo('catalogo_materiales', 'MPerfil1',
  $q$catalogo_formula_evaluar(medida_arbol, '{"ancho":1500}')$q$));
SELECT pg_temp.caso('02 sin fórmula no hay árbol', 'true', pg_temp.campo('catalogo_materiales', 'MPerfil1', 'ancho_arbol IS NULL'));
SELECT pg_temp.caso('02 la fórmula de la variable', '/', pg_temp.campo('catalogo_variables', 'radio', $q$formula_arbol ->> 'op'$q$));
SELECT pg_temp.caso('02 la elección se guarda como elección', 'si', pg_temp.campo('catalogo_materiales', 'MRueda', $q$eleccion_arbol ->> 'op'$q$));
SELECT pg_temp.caso('02 la elección termina en opciones', 'Zqx160 RuedaB', pg_temp.campo('catalogo_materiales', 'MRueda', $q$eleccion_arbol #>> '{a,v}'$q$));
SELECT pg_temp.caso('02 la condición se guarda como condición', 'cmp', pg_temp.campo('catalogo_condiciones', 'CVar', $q$condicion_arbol ->> 'op'$q$));
SELECT pg_temp.caso('02 la opción lleva su cantidad', 'num', pg_temp.campo('catalogo_opciones', 'OLam', $q$cantidad_arbol ->> 'op'$q$));
SELECT pg_temp.caso('02 lo que no trae, lo hereda', 'true', pg_temp.campo('catalogo_opciones', 'OFloat', 'cantidad IS NULL AND cantidad_arbol IS NULL'));

SELECT pg_temp.caso('02 cambiar la fórmula', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = 'ancho - 20'$q$), 'Lucia'));
SELECT pg_temp.caso('02 cambia el árbol', '1480', pg_temp.campo('catalogo_materiales', 'MPerfil1', $q$catalogo_formula_evaluar(medida_arbol, '{"ancho":1500}')$q$));
SELECT pg_temp.caso('02 volverla', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = 'ancho - 2'$q$), 'Lucia'));

SELECT pg_temp.caso('02 fórmula que no se entiende', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = 'ancho +'$q$), 'Lucia'));
SELECT pg_temp.caso('02 no se guardó', 'ancho - 2', pg_temp.campo('catalogo_materiales', 'MPerfil1', 'medida'));
SELECT pg_temp.caso('02 SQL en la fórmula', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = '1; drop table usuarios'$q$), 'Lucia'));
SELECT pg_temp.caso('02 una subconsulta', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = '(select 1)'$q$), 'Lucia'));
SELECT pg_temp.caso('02 una función de SQL', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = 'pg_sleep(10)'$q$), 'Lucia'));
SELECT pg_temp.caso('02 el punto decimal', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = '1.500'$q$), 'Lucia'));
SELECT pg_temp.caso('02 más de 2.000 caracteres', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1',
  format('medida = %L', repeat('1+', 1001) || '1')), 'Lucia'));
SELECT pg_temp.caso('02 una condición sin comparador', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_condiciones', 'CVar', $q$condicion = 'ancho'$q$), 'Lucia'));
SELECT pg_temp.caso('02 una fórmula con comparador suelto', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_variables', 'radio', $q$formula = 'ancho > 1'$q$), 'Lucia'));
SELECT pg_temp.caso('02 el árbol no se escribe', '428C9', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre, cantidad_arbol', $q$'X', '{}'$q$), 'Lucia'));

-- ============================================================
-- 03. Lo que no tiene sentido, ni en un borrador
-- ============================================================
SELECT pg_temp.caso('03 pieza fija incluida', '23514', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre, incluida', $q$'X', true$q$), 'Lucia'));
SELECT pg_temp.caso('03 pieza fija secundaria', '23514', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre, secundario', $q$'X', true$q$), 'Lucia'));
SELECT pg_temp.caso('03 pieza fija que requiere', '23514', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre, requiere_pieza_id',
  format($q$'X', %s$q$, pg_temp.l('Mosquitero'))), 'Lucia'));
SELECT pg_temp.caso('03 pieza que se requiere a sí misma', '23514', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Cortina',
  format('requiere_pieza_id = %s', pg_temp.l('Cortina'))), 'Lucia'));
SELECT pg_temp.caso('03 pieza sin nombre', '23514', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre', $q$''$q$), 'Lucia'));

SELECT pg_temp.caso('03 variable sin fórmula que no ingresa nadie', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre', $q$'x'$q$), 'Lucia'));
SELECT pg_temp.caso('03 mínimo en una que no ingresa el vendedor', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, formula, minimo', $q$'x', '1', 0$q$), 'Lucia'));
SELECT pg_temp.caso('03 cantidad en una que no ingresa el vendedor', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, formula, es_cantidad', $q$'x', '1', true$q$), 'Lucia'));
SELECT pg_temp.caso('03 secundaria que no ingresa el vendedor', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, formula, secundario', $q$'x', '1', true$q$), 'Lucia'));
SELECT pg_temp.caso('03 lista que no ingresa el vendedor', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, formula, es_lista, valores', $q$'x', '1', true, ARRAY['a']$q$), 'Lucia'));
SELECT pg_temp.caso('03 lista con fórmula', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, es_lista, formula, valores', $q$'x', true, true, '1', ARRAY['a']$q$), 'Lucia'));
SELECT pg_temp.caso('03 lista con mínimo', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, es_lista, minimo, valores', $q$'x', true, true, 0, ARRAY['a']$q$), 'Lucia'));
SELECT pg_temp.caso('03 lista que es cantidad', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, es_lista, es_cantidad, valores', $q$'x', true, true, true, ARRAY['a']$q$), 'Lucia'));
SELECT pg_temp.caso('03 predeterminado fuera de la lista', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, es_lista, valores, valor_predeterminado', $q$'x', true, true, ARRAY['a'], 'b'$q$), 'Lucia'));
SELECT pg_temp.caso('03 número con valores', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, valores', $q$'x', true, ARRAY['a']$q$), 'Lucia'));
SELECT pg_temp.caso('03 número con valor de lista', '23514', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor, valor_predeterminado', $q$'x', true, 'a'$q$), 'Lucia'));

SELECT pg_temp.caso('03 único con nombre', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, nombre', format($q$%s, 'X'$q$, pg_temp.l('Marco'))), 'Lucia'));
SELECT pg_temp.caso('03 múltiple sin nombre', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo', format($q$%s, 'elige_vendedor'$q$, pg_temp.l('Marco'))), 'Lucia'));
SELECT pg_temp.caso('03 múltiple con insumo', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, insumo_id', format($q$%s, 'elige_vendedor', 'X', %s$q$, pg_temp.l('Marco'), pg_temp.l('Float'))), 'Lucia'));
SELECT pg_temp.caso('03 único con elección', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, eleccion', format($q$%s, 'si a > 1 entonces b si no c'$q$, pg_temp.l('Marco'))), 'Lucia'));
SELECT pg_temp.caso('03 único que sigue', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, sigue_material_id', format('%s, %s', pg_temp.l('Marco'), pg_temp.l('MVidrio'))), 'Lucia'));
SELECT pg_temp.caso('03 lo elige el vendedor, con elección', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, eleccion', format($q$%s, 'elige_vendedor', 'X', 'si a > 1 entonces b si no c'$q$, pg_temp.l('Marco'))), 'Lucia'));
SELECT pg_temp.caso('03 lo elige el sistema, con sin elección', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, sin_eleccion', format($q$%s, 'elige_sistema', 'X', true$q$, pg_temp.l('Marco'))), 'Lucia'));
SELECT pg_temp.caso('03 lo elige el sistema, secundario', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, secundario', format($q$%s, 'elige_sistema', 'X', true$q$, pg_temp.l('Marco'))), 'Lucia'));
SELECT pg_temp.caso('03 sigue a otro, con sin elección', '23514', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre, sin_eleccion', format($q$%s, 'sigue', 'X', true$q$, pg_temp.l('Marco'))), 'Lucia'));
SELECT pg_temp.caso('03 se sigue a sí mismo', '23514', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MContra', format('sigue_material_id = %s', pg_temp.l('MContra'))), 'Lucia'));

SELECT pg_temp.caso('03 opción sin insumo ni pareja', '23514', pg_temp.intentar(pg_temp.ins('catalogo_opciones', 'V1', 'material_id', pg_temp.l('MVidrio')), 'Lucia'));
SELECT pg_temp.caso('03 la pareja no es predeterminada', '23514', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OC4', 'predeterminada = true'), 'Lucia'));

SELECT pg_temp.caso('03 condición de nadie', '23514', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'V1', 'condicion, mensaje', $q$'ancho > 1', 'X'$q$), 'Lucia'));
SELECT pg_temp.caso('03 condición de dos', '23514', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'V1', 'variable_id, material_id, condicion, mensaje',
  format($q$%s, %s, 'ancho > 1', 'X'$q$, pg_temp.l('ancho'), pg_temp.l('MVidrio'))), 'Lucia'));
SELECT pg_temp.caso('03 condición sin mensaje', '23514', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'V1', 'variable_id, condicion, mensaje',
  format($q$%s, 'ancho > 1', ''$q$, pg_temp.l('ancho'))), 'Lucia'));
SELECT pg_temp.caso('03 un caso que no es objeto', '23514', pg_temp.intentar(pg_temp.ins('catalogo_casos', 'V1', 'nombre, entrada', $q$'X', '[]'$q$), 'Lucia'));

-- Un borrador sí puede estar a medias: esto lo frena el envío.
SELECT pg_temp.crear('POtra', pg_temp.ins('catalogo_piezas', 'VOtra', 'nombre', $q$'Pieza otra'$q$));
SELECT pg_temp.crear('VaOtra', pg_temp.ins('catalogo_variables', 'VOtra', 'nombre, formula', $q$'x', '1'$q$));
SELECT pg_temp.crear('Sin minimo', pg_temp.ins('catalogo_variables', 'VOtra', 'nombre, ingresa_vendedor', $q$'sin minimo', true$q$));
SELECT pg_temp.crear('Lista vacia', pg_temp.ins('catalogo_variables', 'VOtra', 'nombre, ingresa_vendedor, es_lista', $q$'lista vacia', true, true$q$));
SELECT pg_temp.crear('Sin insumo', pg_temp.ins('catalogo_materiales', 'VOtra', 'pieza_id', pg_temp.l('POtra')));
SELECT pg_temp.crear('MOtra', pg_temp.ins('catalogo_materiales', 'VOtra', 'pieza_id, tipo, nombre', format($q$%s, 'elige_vendedor', 'Otro'$q$, pg_temp.l('POtra'))));
SELECT pg_temp.crear('Sin lider', pg_temp.ins('catalogo_materiales', 'VOtra', 'pieza_id, tipo, nombre', format($q$%s, 'sigue', 'Sin lider'$q$, pg_temp.l('POtra'))));
SELECT pg_temp.crear('OOtra', pg_temp.ins('catalogo_opciones', 'VOtra', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MOtra'), pg_temp.l('Float'))));

-- Lo que se apunta adentro de una versión no puede ser de otra.
SELECT pg_temp.caso('03 variable en una pieza de otra versión', '23503', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, pieza_id, formula',
  format($q$'x', %s, '1'$q$, pg_temp.l('POtra'))), 'Lucia'));
SELECT pg_temp.caso('03 material en una pieza de otra versión', '23503', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id', pg_temp.l('POtra')), 'Lucia'));
SELECT pg_temp.caso('03 requiere una pieza de otra versión', '23503', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Cortina', format('requiere_pieza_id = %s', pg_temp.l('POtra'))), 'Lucia'));
SELECT pg_temp.caso('03 sigue a un material de otra versión', '23503', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MContra', format('sigue_material_id = %s', pg_temp.l('MOtra'))), 'Lucia'));
SELECT pg_temp.caso('03 opción de un material de otra versión', '23503', pg_temp.intentar(pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MOtra'), pg_temp.l('Laminado'))), 'Lucia'));
SELECT pg_temp.caso('03 pareja de una opción de otra versión', '23503', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OC4', format('sigue_opcion_id = %s', pg_temp.l('OOtra'))), 'Lucia'));
SELECT pg_temp.caso('03 condición de una variable de otra versión', '23503', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'V1', 'variable_id, condicion, mensaje',
  format($q$%s, 'x > 1', 'X'$q$, pg_temp.l('VaOtra'))), 'Lucia'));
SELECT pg_temp.caso('03 condición de un material de otra versión', '23503', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'V1', 'material_id, condicion, mensaje',
  format($q$%s, 'x > 1', 'X'$q$, pg_temp.l('MOtra'))), 'Lucia'));
SELECT pg_temp.caso('03 condición de una opción de otra versión', '23503', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'V1', 'opcion_id, condicion, mensaje',
  format($q$%s, 'x > 1', 'X'$q$, pg_temp.l('OOtra'))), 'Lucia'));

-- ============================================================
-- 04. Nombres que no se repiten
-- ============================================================
SELECT pg_temp.caso('04 pieza repetida', '23505', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre', $q$'Marco'$q$), 'Lucia'));
SELECT pg_temp.caso('04 pieza repetida con mayúsculas', '23505', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre', $q$'MARCO'$q$), 'Lucia'));
SELECT pg_temp.crear('Marco otra', pg_temp.ins('catalogo_piezas', 'VOtra', 'nombre', $q$'Marco'$q$));
SELECT pg_temp.caso('04 variable repetida', '23505', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor', $q$'ancho', true$q$), 'Lucia'));
SELECT pg_temp.caso('04 variable repetida con mayúsculas', '23505', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, ingresa_vendedor', $q$'ANCHO', true$q$), 'Lucia'));
SELECT pg_temp.caso('04 múltiple repetido en la pieza', '23505', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre', format($q$%s, 'elige_vendedor', 'Vidrio'$q$, pg_temp.l('Hoja'))), 'Lucia'));
SELECT pg_temp.caso('04 múltiple repetido con mayúsculas', '23505', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre', format($q$%s, 'elige_vendedor', 'VIDRIO'$q$, pg_temp.l('Hoja'))), 'Lucia'));
SELECT pg_temp.crear('Vidrio en Marco', pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id, tipo, nombre', format($q$%s, 'elige_vendedor', 'Vidrio'$q$, pg_temp.l('Marco'))));
SELECT pg_temp.caso('04 sacarlo', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'Vidrio en Marco', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('04 un mismo insumo, dos filas en la pieza', '2', (SELECT count(*)::text FROM catalogo_materiales
  WHERE pieza_id = pg_temp.id('Marco') AND insumo_id = pg_temp.id('Perfil') AND activo));
SELECT pg_temp.caso('04 opción repetida en el material', '23505', pg_temp.intentar(pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MVidrio'), pg_temp.l('Float'))), 'Lucia'));
SELECT pg_temp.caso('04 marcar otra predeterminada', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OLam', 'predeterminada = true'), 'Lucia'));
SELECT pg_temp.caso('04 apaga la anterior', 'false', pg_temp.campo('catalogo_opciones', 'OFloat', 'predeterminada::text'));
SELECT pg_temp.caso('04 si la nueva no se guarda', 'CA001', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OFloat', $q$predeterminada = true, cantidad = '('$q$), 'Lucia'));
SELECT pg_temp.caso('04 la anterior sigue marcada', 'true', pg_temp.campo('catalogo_opciones', 'OLam', 'predeterminada::text'));
SELECT pg_temp.caso('04 volver a la primera', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OFloat', 'predeterminada = true'), 'Lucia'));
SELECT pg_temp.caso('04 dos parejas para una opción', '23505', pg_temp.intentar(pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id, sigue_opcion_id',
  format('%s, %s, %s', pg_temp.l('MContra'), pg_temp.l('Contra6'), pg_temp.l('OFloat'))), 'Lucia'));
SELECT pg_temp.caso('04 un insumo puede ser pareja de dos', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OC6', format('insumo_id = %s', pg_temp.l('Contra4'))), 'Lucia'));
SELECT pg_temp.caso('04 volverla', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OC6', format('insumo_id = %s', pg_temp.l('Contra6'))), 'Lucia'));
SELECT pg_temp.caso('04 color repetido', '23505', pg_temp.intentar(pg_temp.ins('catalogo_versiones_colores', 'V1', 'color_id', pg_temp.l('Blanco')), 'Lucia'));
SELECT pg_temp.caso('04 marcar otro color base', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_versiones_colores', 'CNegro', 'base = true'), 'Lucia'));
SELECT pg_temp.caso('04 apaga el anterior', 'false', pg_temp.campo('catalogo_versiones_colores', 'CBlanco', 'base::text'));
SELECT pg_temp.caso('04 volver al primero', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_versiones_colores', 'CBlanco', 'base = true'), 'Lucia'));
SELECT pg_temp.caso('04 el otro ya no es base', 'false', pg_temp.campo('catalogo_versiones_colores', 'CNegro', 'base::text'));
SELECT pg_temp.caso('04 caso repetido', '23505', pg_temp.intentar(pg_temp.ins('catalogo_casos', 'V1', 'nombre', $q$'Chica'$q$), 'Lucia'));
SELECT pg_temp.caso('04 caso repetido con mayúsculas', '23505', pg_temp.intentar(pg_temp.ins('catalogo_casos', 'V1', 'nombre', $q$'CHICA'$q$), 'Lucia'));

SELECT pg_temp.crear('Temporal', pg_temp.ins('catalogo_piezas', 'V1', 'nombre', $q$'Temporal'$q$));
SELECT pg_temp.caso('04 sacar una pieza', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Temporal', 'activo = false'), 'Lucia'));
SELECT pg_temp.crear('Temporal 2', pg_temp.ins('catalogo_piezas', 'V1', 'nombre', $q$'Temporal'$q$));
SELECT pg_temp.caso('04 sacar la nueva', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Temporal 2', 'activo = false'), 'Lucia'));

-- ============================================================
-- 05. Sacar algo saca lo que depende de ello
-- ============================================================
SELECT pg_temp.crear('VB', pg_temp.alta('Zqx160 Bajas', 'Puertas'));
SELECT pg_temp.crear('PA', pg_temp.ins('catalogo_piezas', 'VB', 'nombre', $q$'A'$q$));
SELECT pg_temp.crear('PB', pg_temp.ins('catalogo_piezas', 'VB', 'nombre, opcional', $q$'B', true$q$));
SELECT pg_temp.crear('PR', pg_temp.ins('catalogo_piezas', 'VB', 'nombre, opcional, requiere_pieza_id', format($q$'R', true, %s$q$, pg_temp.l('PB'))));
SELECT pg_temp.crear('VA', pg_temp.ins('catalogo_variables', 'VB', 'nombre, pieza_id, formula', format($q$'va', %s, '1'$q$, pg_temp.l('PA'))));
SELECT pg_temp.crear('VS', pg_temp.ins('catalogo_variables', 'VB', 'nombre, formula', $q$'vs', '1'$q$));
SELECT pg_temp.crear('MU', pg_temp.ins('catalogo_materiales', 'VB', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PA'), pg_temp.l('Perfil'))));
SELECT pg_temp.crear('MM', pg_temp.ins('catalogo_materiales', 'VB', 'pieza_id, tipo, nombre', format($q$%s, 'elige_vendedor', 'Multi'$q$, pg_temp.l('PA'))));
SELECT pg_temp.crear('OM1', pg_temp.ins('catalogo_opciones', 'VB', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MM'), pg_temp.l('Float'))));
SELECT pg_temp.crear('OM2', pg_temp.ins('catalogo_opciones', 'VB', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MM'), pg_temp.l('Laminado'))));
SELECT pg_temp.crear('MS', pg_temp.ins('catalogo_materiales', 'VB', 'pieza_id, tipo, nombre, sigue_material_id', format($q$%s, 'sigue', 'Sigue', %s$q$, pg_temp.l('PB'), pg_temp.l('MM'))));
SELECT pg_temp.crear('OS1', pg_temp.ins('catalogo_opciones', 'VB', 'material_id, insumo_id, sigue_opcion_id', format('%s, %s, %s', pg_temp.l('MS'), pg_temp.l('Contra4'), pg_temp.l('OM1'))));
SELECT pg_temp.crear('OS2', pg_temp.ins('catalogo_opciones', 'VB', 'material_id, insumo_id, sigue_opcion_id', format('%s, %s, %s', pg_temp.l('MS'), pg_temp.l('Contra6'), pg_temp.l('OM2'))));
SELECT pg_temp.crear('CA', pg_temp.ins('catalogo_condiciones', 'VB', 'variable_id, condicion, mensaje', format($q$%s, 'va > 1', 'X'$q$, pg_temp.l('VA'))));
SELECT pg_temp.crear('CM', pg_temp.ins('catalogo_condiciones', 'VB', 'material_id, condicion, mensaje', format($q$%s, 'va > 1', 'X'$q$, pg_temp.l('MM'))));
SELECT pg_temp.crear('CO1', pg_temp.ins('catalogo_condiciones', 'VB', 'opcion_id, condicion, mensaje', format($q$%s, 'va > 1', 'X'$q$, pg_temp.l('OM1'))));
SELECT pg_temp.crear('CS1', pg_temp.ins('catalogo_condiciones', 'VB', 'opcion_id, condicion, mensaje', format($q$%s, 'va > 1', 'X'$q$, pg_temp.l('OS1'))));

SELECT pg_temp.caso('05 sacar una opción', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OM2', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('05 se va su pareja', 'false', pg_temp.activo('catalogo_opciones', 'OS2'));
SELECT pg_temp.caso('05 la otra pareja sigue', 'true', pg_temp.activo('catalogo_opciones', 'OS1'));
SELECT pg_temp.caso('05 sacar la otra opción', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OM1', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('05 se va su pareja, también', 'false', pg_temp.activo('catalogo_opciones', 'OS1'));
SELECT pg_temp.caso('05 se van las condiciones de la opción', 'false', pg_temp.activo('catalogo_condiciones', 'CO1'));
SELECT pg_temp.caso('05 y las de su pareja', 'false', pg_temp.activo('catalogo_condiciones', 'CS1'));
SELECT pg_temp.caso('05 las del material siguen', 'true', pg_temp.activo('catalogo_condiciones', 'CM'));

SELECT pg_temp.caso('05 sacar el material', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MM', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('05 se van sus condiciones', 'false', pg_temp.activo('catalogo_condiciones', 'CM'));
SELECT pg_temp.caso('05 el que lo sigue queda', 'true', pg_temp.activo('catalogo_materiales', 'MS'));
SELECT pg_temp.caso('05 sin nadie a quien seguir', 'true', pg_temp.campo('catalogo_materiales', 'MS', 'sigue_material_id IS NULL'));
SELECT pg_temp.caso('05 los demás materiales siguen', 'true', pg_temp.activo('catalogo_materiales', 'MU'));

SELECT pg_temp.caso('05 sacar la pieza requerida', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'PB', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('05 se van sus materiales', 'false', pg_temp.activo('catalogo_materiales', 'MS'));
SELECT pg_temp.caso('05 la que la requería queda', 'true', pg_temp.activo('catalogo_piezas', 'PR'));
SELECT pg_temp.caso('05 sin requisito', 'true', pg_temp.campo('catalogo_piezas', 'PR', 'requiere_pieza_id IS NULL'));

SELECT pg_temp.caso('05 sacar la pieza', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'PA', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('05 se van sus variables', 'false', pg_temp.activo('catalogo_variables', 'VA'));
SELECT pg_temp.caso('05 y las condiciones de esas', 'false', pg_temp.activo('catalogo_condiciones', 'CA'));
SELECT pg_temp.caso('05 y sus materiales', 'false', pg_temp.activo('catalogo_materiales', 'MU'));
SELECT pg_temp.caso('05 las variables sueltas siguen', 'true', pg_temp.activo('catalogo_variables', 'VS'));

SELECT pg_temp.caso('05 una pieza sacada no vuelve', 'CA015', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'PA', 'activo = true'), 'Lucia'));
SELECT pg_temp.caso('05 un material sacado no vuelve', 'CA015', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MU', 'activo = true'), 'Lucia'));
SELECT pg_temp.caso('05 una opción sacada no vuelve', 'CA015', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OM1', 'activo = true'), 'Lucia'));
SELECT pg_temp.caso('05 una variable sacada no vuelve', 'CA015', pg_temp.intentar(pg_temp.upd('catalogo_variables', 'VA', 'activo = true'), 'Lucia'));
SELECT pg_temp.caso('05 una condición sacada no vuelve', 'CA015', pg_temp.intentar(pg_temp.upd('catalogo_condiciones', 'CA', 'activo = true'), 'Lucia'));

-- sql/171: nada entra ni se apunta a lo sacado. PA, MM, OM1 y VA ya salieron; PV, MV, OV y VV siguen.
SELECT pg_temp.crear('PV', pg_temp.ins('catalogo_piezas', 'VB', 'nombre', $q$'Viva'$q$));
SELECT pg_temp.crear('MV', pg_temp.ins('catalogo_materiales', 'VB', 'pieza_id, tipo, nombre', format($q$%s, 'elige_vendedor', 'Viva'$q$, pg_temp.l('PV'))));
SELECT pg_temp.crear('OV', pg_temp.ins('catalogo_opciones', 'VB', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MV'), pg_temp.l('Float'))));
SELECT pg_temp.crear('VV', pg_temp.ins('catalogo_variables', 'VB', 'nombre, segun_material_id', format($q$'vv', %s$q$, pg_temp.l('MV'))));

SELECT pg_temp.caso('05 material en pieza sacada', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'VB', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PA'), pg_temp.l('Perfil'))), 'Lucia'));
SELECT pg_temp.caso('05 mover un material a pieza sacada', 'CA025', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MV', format('pieza_id = %s', pg_temp.l('PA'))), 'Lucia'));
SELECT pg_temp.caso('05 variable en pieza sacada', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'VB', 'nombre, pieza_id, formula', format($q$'vz', %s, '1'$q$, pg_temp.l('PA'))), 'Lucia'));
SELECT pg_temp.caso('05 mover una variable a pieza sacada', 'CA025', pg_temp.intentar(pg_temp.upd('catalogo_variables', 'VV', format('pieza_id = %s', pg_temp.l('PA'))), 'Lucia'));
SELECT pg_temp.caso('05 requerir una pieza sacada', 'CA025', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'PR', format('requiere_pieza_id = %s', pg_temp.l('PB'))), 'Lucia'));
SELECT pg_temp.caso('05 opción en material sacado', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_opciones', 'VB', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MM'), pg_temp.l('Float'))), 'Lucia'));
SELECT pg_temp.caso('05 pareja de una opción sacada', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_opciones', 'VB', 'material_id, insumo_id, sigue_opcion_id', format('%s, %s, %s', pg_temp.l('MV'), pg_temp.l('Laminado'), pg_temp.l('OM1'))), 'Lucia'));
SELECT pg_temp.caso('05 seguir a un material sacado', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'VB', 'pieza_id, tipo, nombre, sigue_material_id', format($q$%s, 'sigue', 'S2', %s$q$, pg_temp.l('PV'), pg_temp.l('MM'))), 'Lucia'));
SELECT pg_temp.caso('05 variable según material sacado', 'CA025', pg_temp.intentar(pg_temp.upd('catalogo_variables', 'VV', format('segun_material_id = %s', pg_temp.l('MM'))), 'Lucia'));
SELECT pg_temp.caso('05 condición de variable sacada', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'VB', 'variable_id, condicion, mensaje', format($q$%s, 'vs > 1', 'X'$q$, pg_temp.l('VA'))), 'Lucia'));
SELECT pg_temp.caso('05 condición de material sacado', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'VB', 'material_id, condicion, mensaje', format($q$%s, 'vs > 1', 'X'$q$, pg_temp.l('MM'))), 'Lucia'));
SELECT pg_temp.caso('05 condición de opción sacada', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'VB', 'opcion_id, condicion, mensaje', format($q$%s, 'vs > 1', 'X'$q$, pg_temp.l('OM1'))), 'Lucia'));
SELECT pg_temp.caso('05 valor de variable sacada', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_variables_valores', 'VB', 'variable_id, opcion_id, formula', format($q$%s, %s, '1'$q$, pg_temp.l('VA'), pg_temp.l('OV'))), 'Lucia'));
SELECT pg_temp.caso('05 valor de opción sacada', 'CA025', pg_temp.intentar(pg_temp.ins('catalogo_variables_valores', 'VB', 'variable_id, opcion_id, formula', format($q$%s, %s, '1'$q$, pg_temp.l('VV'), pg_temp.l('OM1'))), 'Lucia'));
SELECT pg_temp.caso('05 sin permiso sigue siendo 42501', '42501', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'VB', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PA'), pg_temp.l('Perfil'))), 'Juan'));

SELECT pg_temp.caso('05 en lo que sigue se suma', 'ok', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'VB', 'material_id, condicion, mensaje', format($q$%s, 'vs > 1', 'X'$q$, pg_temp.l('MV'))), 'Lucia'));
SELECT pg_temp.caso('05 mover a una pieza que sigue', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_variables', 'VV', format('pieza_id = %s', pg_temp.l('PV'))), 'Lucia'));
SELECT pg_temp.caso('05 editar lo que sigue', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MV', $q$cantidad = '2'$q$), 'Lucia'));
SELECT pg_temp.caso('05 sacar lo que sigue', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'PV', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('05 la cascada se lleva el material', 'false', pg_temp.activo('catalogo_materiales', 'MV'));
SELECT pg_temp.caso('05 y la variable según él', 'false', pg_temp.activo('catalogo_variables', 'VV'));

-- ============================================================
-- 06. Solo se edita en borrador
-- ============================================================
SELECT pg_temp.caso('06 en borrador se edita', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'V1', $q$nombre = 'Zqx160 Ventana'$q$), 'Lucia'));
SELECT pg_temp.a('V1', 'en_revision');
SELECT pg_temp.caso('06 en revisión cuenta como enviada', 'true', pg_temp.campo('catalogo_versiones', 'V1', 'enviada'));

SELECT pg_temp.caso('06 pieza nueva', 'CA012', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre', $q$'X'$q$), 'Lucia'));
SELECT pg_temp.caso('06 variable nueva', 'CA012', pg_temp.intentar(pg_temp.ins('catalogo_variables', 'V1', 'nombre, formula', $q$'x', '1'$q$), 'Lucia'));
SELECT pg_temp.caso('06 material nuevo', 'CA012', pg_temp.intentar(pg_temp.ins('catalogo_materiales', 'V1', 'pieza_id', pg_temp.l('Marco')), 'Lucia'));
SELECT pg_temp.caso('06 opción nueva', 'CA012', pg_temp.intentar(pg_temp.ins('catalogo_opciones', 'V1', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MRueda'), pg_temp.l('Float'))), 'Lucia'));
SELECT pg_temp.caso('06 condición nueva', 'CA012', pg_temp.intentar(pg_temp.ins('catalogo_condiciones', 'V1', 'variable_id, condicion, mensaje', format($q$%s, 'x > 1', 'X'$q$, pg_temp.l('ancho'))), 'Lucia'));
SELECT pg_temp.caso('06 caso nuevo', 'CA012', pg_temp.intentar(pg_temp.ins('catalogo_casos', 'V1', 'nombre', $q$'X'$q$), 'Lucia'));
SELECT pg_temp.caso('06 color nuevo', 'CA012', pg_temp.intentar(pg_temp.ins('catalogo_versiones_colores', 'V1', 'color_id', pg_temp.l('Blanco')), 'Lucia'));
SELECT pg_temp.caso('06 cambiar un color', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_versiones_colores', 'CNegro', 'base = false'), 'Lucia'));

SELECT pg_temp.caso('06 cambiar una pieza', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Marco', $q$cantidad = '3'$q$), 'Lucia'));
SELECT pg_temp.caso('06 cambiar una variable', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_variables', 'radio', $q$formula = '3'$q$), 'Lucia'));
SELECT pg_temp.caso('06 cambiar un material', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MPerfil1', $q$medida = '3'$q$), 'Lucia'));
SELECT pg_temp.caso('06 cambiar una opción', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_opciones', 'OLam', $q$cantidad = '3'$q$), 'Lucia'));
SELECT pg_temp.caso('06 cambiar una condición', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_condiciones', 'CVar', $q$mensaje = 'Y'$q$), 'Lucia'));
SELECT pg_temp.caso('06 cambiar un caso', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_casos', 'Chica', $q$nombre = 'Y'$q$), 'Lucia'));
SELECT pg_temp.caso('06 sacar una pieza', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Marco', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('06 el nombre de la versión', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'V1', $q$nombre = 'Zqx160 Y'$q$), 'Lucia'));
SELECT pg_temp.caso('06 la categoría de la versión', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'V1', format('categoria_id = %s', pg_temp.l('Puertas'))), 'Lucia'));
SELECT pg_temp.caso('06 Rodrigo sigue chocando con los permisos', '42501', pg_temp.intentar(pg_temp.ins('catalogo_piezas', 'V1', 'nombre', $q$'X'$q$), 'Rodrigo'));

SELECT pg_temp.a('V1', 'publicado');
SELECT pg_temp.caso('06 publicada cuenta como enviada', 'true', pg_temp.campo('catalogo_versiones', 'V1', 'enviada'));
SELECT pg_temp.caso('06 publicada no se edita', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Marco', $q$cantidad = '3'$q$), 'Lucia'));
SELECT pg_temp.caso('06 publicada no cambia de nombre', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'V1', $q$nombre = 'Zqx160 Y'$q$), 'Lucia'));
SELECT pg_temp.a('V1', 'obsoleto');
SELECT pg_temp.caso('06 obsoleta cuenta como enviada', 'true', pg_temp.campo('catalogo_versiones', 'V1', 'enviada'));
SELECT pg_temp.caso('06 obsoleta no se edita', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Marco', $q$cantidad = '3'$q$), 'Lucia'));
SELECT pg_temp.a('V1', 'descartado');
SELECT pg_temp.caso('06 descartada no cuenta como enviada', 'false', pg_temp.campo('catalogo_versiones', 'V1', 'enviada'));
SELECT pg_temp.caso('06 descartada no se edita', 'CA012', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Marco', $q$cantidad = '3'$q$), 'Lucia'));

SELECT pg_temp.a('V1', 'borrador');
SELECT pg_temp.caso('06 de vuelta en borrador se edita', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'Marco', 'orden = 1'), 'Lucia'));

-- ============================================================
-- 07. Versión nueva
-- ============================================================
SELECT pg_temp.caso('07 con un borrador abierto', 'CA013', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Lucia'));
SELECT pg_temp.a('V1', 'en_revision');
SELECT pg_temp.caso('07 con una en revisión', 'CA013', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Lucia'));
SELECT pg_temp.a('V1', 'obsoleto');
SELECT pg_temp.caso('07 sin origen y sin publicada', 'CA014', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Lucia'));
SELECT pg_temp.a('V1', 'publicado');

SELECT pg_temp.crear('V2', format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')));
SELECT pg_temp.caso('07 es la v2', '2', pg_temp.campo('catalogo_versiones', 'V2', 'numero'));
SELECT pg_temp.caso('07 en borrador', 'borrador', pg_temp.campo('catalogo_versiones', 'V2', 'estado'));
SELECT pg_temp.caso('07 del mismo paquete', pg_temp.id('P1')::text, pg_temp.campo('catalogo_versiones', 'V2', 'paquete_id'));
SELECT pg_temp.caso('07 con su nombre', 'Zqx160 Ventana', pg_temp.campo('catalogo_versiones', 'V2', 'nombre'));
SELECT pg_temp.caso('07 con su categoría', pg_temp.id('Ventanas')::text, pg_temp.campo('catalogo_versiones', 'V2', 'categoria_id'));
SELECT pg_temp.caso('07 la publicada no cambia', 'publicado', pg_temp.campo('catalogo_versiones', 'V1', 'estado'));

SELECT pg_temp.caso('07 las piezas, sin las sacadas', '5', pg_temp.cuenta('catalogo_piezas', 'V2'));
SELECT pg_temp.caso('07 las variables', '7', pg_temp.cuenta('catalogo_variables', 'V2'));
SELECT pg_temp.caso('07 los materiales, sin los sacados', '6', pg_temp.cuenta('catalogo_materiales', 'V2'));
SELECT pg_temp.caso('07 las opciones', '8', pg_temp.cuenta('catalogo_opciones', 'V2'));
SELECT pg_temp.caso('07 las condiciones', '3', pg_temp.cuenta('catalogo_condiciones', 'V2'));
SELECT pg_temp.caso('07 los casos', '1', pg_temp.cuenta('catalogo_casos', 'V2'));
SELECT pg_temp.caso('07 los colores', '2', pg_temp.cuenta('catalogo_versiones_colores', 'V2'));
SELECT pg_temp.caso('07 no copia lo sacado, ni como inactivo', '0', (SELECT count(*)::text FROM catalogo_piezas
  WHERE version_id = pg_temp.id('V2') AND nombre = 'Temporal'));

SELECT pg_temp.caso('07 requiere apunta adentro de la copia', 'Cajon', (SELECT r.nombre FROM catalogo_piezas p
  JOIN catalogo_piezas r ON r.id = p.requiere_pieza_id AND r.version_id = p.version_id
  WHERE p.version_id = pg_temp.id('V2') AND p.nombre = 'Cortina'));
SELECT pg_temp.caso('07 la variable sigue en su pieza', 'Hoja', (SELECT p.nombre FROM catalogo_variables v
  JOIN catalogo_piezas p ON p.id = v.pieza_id AND p.version_id = v.version_id
  WHERE v.version_id = pg_temp.id('V2') AND v.nombre = 'ancho_hoja'));
SELECT pg_temp.caso('07 sigue apunta adentro de la copia', 'Vidrio', (SELECT l.nombre FROM catalogo_materiales m
  JOIN catalogo_materiales l ON l.id = m.sigue_material_id AND l.version_id = m.version_id
  WHERE m.version_id = pg_temp.id('V2') AND m.nombre = 'Contravidrio'));
SELECT pg_temp.caso('07 las parejas, "ninguna" incluida',
  'ninguna de Zqx160 DVH, Zqx160 Contra4 de Zqx160 Float, Zqx160 Contra6 de Zqx160 Laminado',
  (SELECT string_agg(coalesce(fi.nombre, 'ninguna') || ' de ' || li.nombre, ', ' ORDER BY li.nombre)
   FROM catalogo_opciones f
   JOIN catalogo_opciones l ON l.id = f.sigue_opcion_id AND l.version_id = f.version_id
   JOIN catalogo_insumos li ON li.id = l.insumo_id
   LEFT JOIN catalogo_insumos fi ON fi.id = f.insumo_id
   WHERE f.version_id = pg_temp.id('V2')));
SELECT pg_temp.caso('07 la predeterminada', 'Zqx160 Float', (SELECT i.nombre FROM catalogo_opciones o
  JOIN catalogo_insumos i ON i.id = o.insumo_id WHERE o.version_id = pg_temp.id('V2') AND o.predeterminada));
SELECT pg_temp.caso('07 la condición de la variable', 'Ancho grande', (SELECT c.mensaje FROM catalogo_condiciones c
  JOIN catalogo_variables v ON v.id = c.variable_id AND v.version_id = c.version_id
  WHERE c.version_id = pg_temp.id('V2') AND v.nombre = 'ancho'));
SELECT pg_temp.caso('07 la condición del material', 'Muy alto', (SELECT c.mensaje FROM catalogo_condiciones c
  JOIN catalogo_materiales m ON m.id = c.material_id AND m.version_id = c.version_id
  WHERE c.version_id = pg_temp.id('V2') AND m.nombre = 'Vidrio' AND c.bloquea));
SELECT pg_temp.caso('07 la condición de la opción', 'Float hasta 2 m2', (SELECT c.mensaje FROM catalogo_condiciones c
  JOIN catalogo_opciones o ON o.id = c.opcion_id AND o.version_id = c.version_id
  WHERE c.version_id = pg_temp.id('V2') AND o.insumo_id = pg_temp.id('Float') AND c.bloquea));
SELECT pg_temp.caso('07 la fórmula y su árbol', '998', (SELECT catalogo_formula_evaluar(medida_arbol, '{"alto":1000}')::text
  FROM catalogo_materiales WHERE version_id = pg_temp.id('V2') AND medida = 'alto - 2'));
SELECT pg_temp.caso('07 ancho y alto del material', 'ancho_hoja - 48 / alto - 48', (SELECT ancho || ' / ' || alto
  FROM catalogo_materiales WHERE version_id = pg_temp.id('V2') AND nombre = 'Vidrio'));
SELECT pg_temp.caso('07 la elección', 'si', (SELECT eleccion_arbol ->> 'op'
  FROM catalogo_materiales WHERE version_id = pg_temp.id('V2') AND nombre = 'Rueda'));
SELECT pg_temp.caso('07 la cantidad de la opción', '2', (SELECT o.cantidad FROM catalogo_opciones o
  WHERE o.version_id = pg_temp.id('V2') AND o.insumo_id = pg_temp.id('Laminado')));
SELECT pg_temp.caso('07 la lista', 'Izquierda,Derecha / Izquierda', (SELECT array_to_string(valores, ',') || ' / ' || valor_predeterminado
  FROM catalogo_variables WHERE version_id = pg_temp.id('V2') AND nombre = 'mano'));
SELECT pg_temp.caso('07 mínimo y máximo', '300 - 3000', (SELECT minimo || ' - ' || maximo
  FROM catalogo_variables WHERE version_id = pg_temp.id('V2') AND nombre = 'ancho'));
SELECT pg_temp.caso('07 medida o cantidad', 'true', (SELECT es_cantidad::text
  FROM catalogo_variables WHERE version_id = pg_temp.id('V2') AND nombre = 'travesanos'));
SELECT pg_temp.caso('07 pasa a Producción', 'false', (SELECT a_produccion::text
  FROM catalogo_variables WHERE version_id = pg_temp.id('V2') AND nombre = 'radio'));
SELECT pg_temp.caso('07 lo de la pieza opcional', 'true', (SELECT (opcional AND incluida AND secundario)::text
  FROM catalogo_piezas WHERE version_id = pg_temp.id('V2') AND nombre = 'Cortina'));
SELECT pg_temp.caso('07 cantidad y espesor de la pieza', '2 true', (SELECT cantidad || ' ' || calcula_espesor
  FROM catalogo_piezas WHERE version_id = pg_temp.id('V2') AND nombre = 'Hoja'));
SELECT pg_temp.caso('07 el orden de la pieza', '1', (SELECT orden::text
  FROM catalogo_piezas WHERE version_id = pg_temp.id('V2') AND nombre = 'Marco'));
SELECT pg_temp.caso('07 no cuenta para el peso', 'false', (SELECT cuenta_peso::text
  FROM catalogo_materiales WHERE version_id = pg_temp.id('V2') AND insumo_id = pg_temp.id('Soldado')));
SELECT pg_temp.caso('07 cuenta para el espesor', 'true', (SELECT cuenta_espesor::text
  FROM catalogo_materiales WHERE version_id = pg_temp.id('V2') AND nombre = 'Vidrio'));
SELECT pg_temp.caso('07 lo que cargaría el vendedor', '600', (SELECT entrada #>> '{variables,ancho}'
  FROM catalogo_casos WHERE version_id = pg_temp.id('V2') AND nombre = 'Chica'));
SELECT pg_temp.caso('07 el color base', 'Zqx160 Blanco', (SELECT c.nombre FROM catalogo_versiones_colores vc
  JOIN catalogo_colores c ON c.id = vc.color_id WHERE vc.version_id = pg_temp.id('V2') AND vc.base));

INSERT INTO ids SELECT 'V2 Marco', id FROM catalogo_piezas WHERE version_id = pg_temp.id('V2') AND nombre = 'Marco';
SELECT pg_temp.caso('07 la copia se edita', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'V2 Marco', $q$nombre = 'Marco nuevo'$q$), 'Lucia'));
SELECT pg_temp.caso('07 sin tocar la original', 'Marco', pg_temp.campo('catalogo_piezas', 'Marco', 'nombre'));
SELECT pg_temp.caso('07 otra, con la v2 abierta', 'CA013', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Lucia'));

SELECT pg_temp.a('V2', 'descartado');
SELECT pg_temp.crear('V3', format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')));
SELECT pg_temp.caso('07 la descartada cuenta el número', '3', pg_temp.campo('catalogo_versiones', 'V3', 'numero'));
SELECT pg_temp.caso('07 por defecto sale de la publicada', '1', (SELECT count(*)::text FROM catalogo_piezas
  WHERE version_id = pg_temp.id('V3') AND nombre = 'Marco'));

SELECT pg_temp.a('V3', 'descartado');
SELECT pg_temp.crear('V4', format('SELECT catalogo_version_nueva(%s, %s)', pg_temp.l('P1'), pg_temp.l('V2')));
SELECT pg_temp.caso('07 desde una descartada: número', '4', pg_temp.campo('catalogo_versiones', 'V4', 'numero'));
SELECT pg_temp.caso('07 desde una descartada: contenido', '1', (SELECT count(*)::text FROM catalogo_piezas
  WHERE version_id = pg_temp.id('V4') AND nombre = 'Marco nuevo'));

SELECT pg_temp.a('V1', 'obsoleto');
SELECT pg_temp.a('V4', 'publicado');
SELECT pg_temp.crear('V5', format('SELECT catalogo_version_nueva(%s, %s)', pg_temp.l('P1'), pg_temp.l('V1')));
SELECT pg_temp.caso('07 desde una obsoleta: contenido', '1', (SELECT count(*)::text FROM catalogo_piezas
  WHERE version_id = pg_temp.id('V5') AND nombre = 'Marco'));
SELECT pg_temp.a('V5', 'descartado');

SELECT pg_temp.caso('07 origen de otro paquete', 'CA014', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s, %s)', pg_temp.l('P1'), pg_temp.l('VOtra')), 'Lucia'));
SELECT pg_temp.caso('07 origen que no existe', 'CA014', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s, %L)', pg_temp.l('P1'), gen_random_uuid()), 'Lucia'));
SELECT pg_temp.caso('07 Rodrigo no la saca', '42501', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Rodrigo'));
SELECT pg_temp.caso('07 Carlos no la saca', '42501', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Carlos'));
SELECT pg_temp.caso('07 Ana no ve el origen', 'CA014', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Ana'));
SELECT pg_temp.caso('07 Juan no ve el origen', 'CA014', pg_temp.intentar(format('SELECT catalogo_version_nueva(%s)', pg_temp.l('P1')), 'Juan'));

-- ============================================================
-- 08. Duplicar
-- ============================================================
SELECT pg_temp.crear('VD', format($q$SELECT catalogo_paquete_duplicar(%s, 'Zqx160 Ventana 3 hojas')$q$, pg_temp.l('V4')));
SELECT pg_temp.paquete('VD', 'PD');
SELECT pg_temp.caso('08 es otro paquete', 'true', (SELECT (pg_temp.id('PD') <> pg_temp.id('P1'))::text));
SELECT pg_temp.caso('08 v1', '1', pg_temp.campo('catalogo_versiones', 'VD', 'numero'));
SELECT pg_temp.caso('08 en borrador', 'borrador', pg_temp.campo('catalogo_versiones', 'VD', 'estado'));
SELECT pg_temp.caso('08 con el nombre nuevo', 'Zqx160 Ventana 3 hojas', pg_temp.campo('catalogo_versiones', 'VD', 'nombre'));
SELECT pg_temp.caso('08 con la misma categoría', pg_temp.id('Ventanas')::text, pg_temp.campo('catalogo_versiones', 'VD', 'categoria_id'));
SELECT pg_temp.caso('08 copia las piezas', '5', pg_temp.cuenta('catalogo_piezas', 'VD'));
SELECT pg_temp.caso('08 copia las opciones', '8', pg_temp.cuenta('catalogo_opciones', 'VD'));
SELECT pg_temp.caso('08 requiere apunta adentro de la copia', 'Cajon', (SELECT r.nombre FROM catalogo_piezas p
  JOIN catalogo_piezas r ON r.id = p.requiere_pieza_id AND r.version_id = p.version_id
  WHERE p.version_id = pg_temp.id('VD') AND p.nombre = 'Cortina'));
SELECT pg_temp.caso('08 la original no cambia', 'publicado', pg_temp.campo('catalogo_versiones', 'V4', 'estado'));
SELECT pg_temp.caso('08 el original sigue sin abierta', '0', (SELECT count(*)::text FROM catalogo_versiones
  WHERE paquete_id = pg_temp.id('P1') AND estado IN ('borrador', 'en_revision')));

SELECT pg_temp.crear('VD2', format($q$SELECT catalogo_paquete_duplicar(%s, 'Zqx160 Otra copia')$q$, pg_temp.l('VOtra')));
SELECT pg_temp.caso('08 desde un borrador, a medias', '3', pg_temp.cuenta('catalogo_materiales', 'VD2'));
SELECT pg_temp.crear('VD3', format($q$SELECT catalogo_paquete_duplicar(%s, 'Zqx160 Ventana')$q$, pg_temp.l('V4')));
SELECT pg_temp.caso('08 un nombre tomado no frena el borrador', 'Zqx160 Ventana', pg_temp.campo('catalogo_versiones', 'VD3', 'nombre'));
SELECT pg_temp.caso('08 Rodrigo no duplica', '42501', pg_temp.intentar(format($q$SELECT catalogo_paquete_duplicar(%s, 'X')$q$, pg_temp.l('V4')), 'Rodrigo'));
SELECT pg_temp.caso('08 Juan no duplica', '42501', pg_temp.intentar(format($q$SELECT catalogo_paquete_duplicar(%s, 'X')$q$, pg_temp.l('V4')), 'Juan'));
SELECT pg_temp.caso('08 versión que no existe', 'CA014', pg_temp.intentar(format($q$SELECT catalogo_paquete_duplicar(%L, 'X')$q$, gen_random_uuid()), 'Lucia'));

-- ============================================================
-- 09. Los datos del insumo que una versión enviada deja fijos
-- ============================================================
SELECT pg_temp.insumo('FA', 'Perfiles', 'mm', '1', '2');
SELECT pg_temp.insumo('FB', 'Vidrios', 'm2', '10', '4');
SELECT pg_temp.insumo('FC', 'Vidrios', 'u');
SELECT pg_temp.insumo('FV', 'Perfiles', 'u');
SELECT pg_temp.insumo('FR', 'Perfiles', 'u');
SELECT pg_temp.crear('FK', format($q$SELECT catalogo_insumo_alta('Zqx160 FK', %s, 'mm', 1, NULL, ARRAY[%s]::uuid[])$q$, pg_temp.l('Perfiles'), pg_temp.l('Blanco')));
SELECT pg_temp.crear('FS', format($q$SELECT catalogo_fijo_alta('Zqx160 FS', %s, 'u', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');

SELECT pg_temp.crear('VF', pg_temp.alta('Zqx160 Fijos', 'Ventanas'));
SELECT pg_temp.crear('PF', pg_temp.ins('catalogo_piezas', 'VF', 'nombre', $q$'Pieza'$q$));
SELECT pg_temp.crear('MFA', pg_temp.ins('catalogo_materiales', 'VF', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PF'), pg_temp.l('FA'))));
SELECT pg_temp.crear('MFK', pg_temp.ins('catalogo_materiales', 'VF', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PF'), pg_temp.l('FK'))));
SELECT pg_temp.crear('MFS', pg_temp.ins('catalogo_materiales', 'VF', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PF'), pg_temp.l('FS'))));
SELECT pg_temp.crear('MFV', pg_temp.ins('catalogo_materiales', 'VF', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PF'), pg_temp.l('FV'))));
SELECT pg_temp.crear('MFR', pg_temp.ins('catalogo_materiales', 'VF', 'pieza_id, insumo_id', format('%s, %s', pg_temp.l('PF'), pg_temp.l('FR'))));
SELECT pg_temp.crear('MFM', pg_temp.ins('catalogo_materiales', 'VF', 'pieza_id, tipo, nombre', format($q$%s, 'elige_vendedor', 'Multi'$q$, pg_temp.l('PF'))));
SELECT pg_temp.crear('OFB', pg_temp.ins('catalogo_opciones', 'VF', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MFM'), pg_temp.l('FB'))));

SELECT pg_temp.caso('09 en borrador: nombre', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA2'$q$), 'Lucia'));
SELECT pg_temp.caso('09 en borrador: categoría', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', format('categoria_id = %s', pg_temp.l('Vidrios'))), 'Lucia'));
SELECT pg_temp.caso('09 en borrador: unidad', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$unidad = 'u'$q$), 'Lucia'));
SELECT pg_temp.caso('09 en borrador: peso', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'peso = 3'), 'Lucia'));
SELECT pg_temp.caso('09 en borrador: espesor', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'espesor = 3'), 'Lucia'));
SELECT pg_temp.caso('09 en borrador: color', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'con_color = true'), 'Lucia'));
SELECT pg_temp.caso('09 en borrador: color, de vuelta', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'con_color = false'), 'Lucia'));
SELECT pg_temp.caso('09 en borrador: Marta, sin Paquetes', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA'$q$), 'Marta'));
SELECT pg_temp.caso('09 en borrador: una opción', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FB', $q$nombre = 'Zqx160 FB2'$q$), 'Lucia'));
SELECT pg_temp.caso('09 sacar un material', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MFR', 'activo = false'), 'Lucia'));

SELECT pg_temp.a('VF', 'en_revision');
SELECT pg_temp.caso('09 enviada: nombre', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA3'$q$), 'Lucia'));
SELECT pg_temp.caso('09 enviada: categoría', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', format('categoria_id = %s', pg_temp.l('Perfiles'))), 'Lucia'));
SELECT pg_temp.caso('09 enviada: unidad', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$unidad = 'mm'$q$), 'Lucia'));
SELECT pg_temp.caso('09 enviada: con_color', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'con_color = true'), 'Lucia'));
SELECT pg_temp.caso('09 enviada: indistinto, desde con color', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FK', 'con_color = false'), 'Lucia'));
SELECT pg_temp.caso('09 enviada: otro peso', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'peso = 5'), 'Lucia'));
SELECT pg_temp.caso('09 enviada: vaciar el peso', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'peso = NULL'), 'Lucia'));
SELECT pg_temp.caso('09 enviada: otro espesor', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'espesor = 5'), 'Lucia'));
SELECT pg_temp.caso('09 enviada: Marta, sin Paquetes, también', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA3'$q$), 'Marta'));
SELECT pg_temp.caso('09 enviada: una opción también', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FB', $q$nombre = 'Zqx160 FB3'$q$), 'Lucia'));
SELECT pg_temp.caso('09 enviada: Ana, sin Paquetes, con un servicio', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FS', $q$nombre = 'Zqx160 FS3'$q$), 'Ana'));
SELECT pg_temp.caso('09 enviada: la unidad del servicio', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FS', $q$unidad = 'mm'$q$), 'Ana'));

SELECT pg_temp.caso('09 completar un peso vacío', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FV', 'peso = 5'), 'Lucia'));
SELECT pg_temp.caso('09 pero una sola vez', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FV', 'peso = 6'), 'Lucia'));
SELECT pg_temp.caso('09 completar un espesor vacío', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FV', 'espesor = 3'), 'Lucia'));
SELECT pg_temp.caso('09 y no se vuelve a vaciar', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FV', 'espesor = NULL'), 'Lucia'));

SELECT pg_temp.caso('09 dar de baja sigue', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('09 reactivar sigue', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', 'activo = true'), 'Lucia'));
SELECT pg_temp.caso('09 sumar un color sigue', 'ok', pg_temp.intentar(format('SELECT catalogo_variante_sumar(%s, %s)', pg_temp.l('FK'), pg_temp.l('Negro')), 'Lucia'));
SELECT pg_temp.caso('09 cargar un costo sigue', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":10,"moneda":"ARS"}]'::jsonb)$q$, pg_temp.variante('FA')), 'Ana'));
SELECT pg_temp.caso('09 un insumo sin usar se edita', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FC', $q$nombre = 'Zqx160 FC2'$q$), 'Lucia'));
SELECT pg_temp.caso('09 uno sacado del borrador antes de enviar se edita', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FR', $q$nombre = 'Zqx160 FR2'$q$), 'Lucia'));

SELECT pg_temp.a('VF', 'borrador');
SELECT pg_temp.caso('09 retirada o devuelta, se edita', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA4'$q$), 'Lucia'));
SELECT pg_temp.a('VF', 'publicado');
SELECT pg_temp.caso('09 publicada: fijo', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA5'$q$), 'Lucia'));
SELECT pg_temp.a('VF', 'obsoleto');
SELECT pg_temp.caso('09 obsoleta: fijo', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA5'$q$), 'Lucia'));
SELECT pg_temp.a('VF', 'descartado');
SELECT pg_temp.caso('09 descartada: se edita', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_insumos', 'FA', $q$nombre = 'Zqx160 FA5'$q$), 'Lucia'));

-- ============================================================
-- 10. La categoría de paquete, con versiones adentro
-- ============================================================
SELECT pg_temp.categoria('CK', 'paquete');
SELECT pg_temp.categoria('CL', 'paquete');
SELECT pg_temp.categoria('CM de baja', 'paquete');
SELECT pg_temp.crear('VK', pg_temp.alta('Zqx160 K', 'CK'));
SELECT pg_temp.paquete('VK', 'PK');

SELECT pg_temp.caso('10 en borrador: se renombra', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', $q$nombre = 'Zqx160 CK2'$q$), 'Lucia'));
SELECT pg_temp.caso('10 en borrador: se da de baja', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('10 se reactiva', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = true'), 'Lucia'));

SELECT pg_temp.a('VK', 'en_revision');
SELECT pg_temp.caso('10 en revisión: nombre fijo', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', $q$nombre = 'Zqx160 CK3'$q$), 'Lucia'));
SELECT pg_temp.caso('10 en revisión: se da de baja', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('10 se reactiva', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = true'), 'Lucia'));

SELECT pg_temp.a('VK', 'borrador');
SELECT pg_temp.caso('10 retirada: se renombra de nuevo', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', $q$nombre = 'Zqx160 CK3'$q$), 'Lucia'));

SELECT pg_temp.a('VK', 'publicado');
SELECT pg_temp.caso('10 publicada: nombre fijo', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', $q$nombre = 'Zqx160 CK4'$q$), 'Lucia'));
SELECT pg_temp.caso('10 publicada de un paquete activo: no se da de baja', 'CA007', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = false'), 'Lucia'));
UPDATE catalogo_paquetes SET activo = false WHERE id = pg_temp.id('PK');
SELECT pg_temp.caso('10 publicada de un paquete de baja: se da de baja', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('10 se reactiva', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = true'), 'Lucia'));
UPDATE catalogo_paquetes SET activo = true WHERE id = pg_temp.id('PK');

SELECT pg_temp.a('VK', 'obsoleto');
SELECT pg_temp.caso('10 obsoleta: nombre fijo', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', $q$nombre = 'Zqx160 CK4'$q$), 'Lucia'));
SELECT pg_temp.caso('10 obsoleta: se da de baja', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('10 se reactiva', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = true'), 'Lucia'));

SELECT pg_temp.a('VK', 'descartado');
SELECT pg_temp.caso('10 descartada: se renombra', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', $q$nombre = 'Zqx160 CK4'$q$), 'Lucia'));
SELECT pg_temp.caso('10 descartada: se da de baja', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CK', 'activo = false'), 'Lucia'));

SELECT pg_temp.crear('VL', pg_temp.alta('Zqx160 L', 'CL'));
SELECT pg_temp.caso('10 un borrador cambia de categoría', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'VL', format('categoria_id = %s', pg_temp.l('Puertas'))), 'Lucia'));
SELECT pg_temp.caso('10 no a una de insumo', '23503', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'VL', format('categoria_id = %s', pg_temp.l('Vidrios'))), 'Lucia'));
SELECT pg_temp.caso('10 baja de una categoría vacía', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'CM de baja', 'activo = false'), 'Lucia'));
SELECT pg_temp.caso('10 a una de baja sí: lo frena el envío', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'VL', format('categoria_id = %s', pg_temp.l('CM de baja'))), 'Lucia'));

SELECT pg_temp.caso('10 las de insumo: nombre fijo con algo adentro', 'CA006', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'Perfiles', $q$nombre = 'Zqx160 Otro'$q$), 'Lucia'));
SELECT pg_temp.caso('10 las de insumo: no se bajan con algo activo', 'CA007', pg_temp.intentar(pg_temp.upd('catalogo_categorias', 'Perfiles', 'activo = false'), 'Lucia'));

-- ============================================================
-- 11. Publicadas: una por paquete, con nombres que no se repiten
-- ============================================================
SELECT pg_temp.crear('VP1', pg_temp.alta('Zqx160 Repetido', 'Ventanas'));
SELECT pg_temp.paquete('VP1', 'PP1');
SELECT pg_temp.crear('VP2', pg_temp.alta('ZQX160 REPETIDO', 'Ventanas'));
SELECT pg_temp.paquete('VP2', 'PP2');
SELECT pg_temp.a('VP1', 'en_revision');
SELECT pg_temp.a('VP2', 'en_revision');
SELECT pg_temp.a('VP1', 'publicado');
SELECT pg_temp.caso('11 el mismo nombre publicado', '23505', pg_temp.estado('VP2', 'publicado'));
UPDATE catalogo_paquetes SET activo = false WHERE id = pg_temp.id('PP1');
SELECT pg_temp.caso('11 aunque el otro esté de baja', '23505', pg_temp.estado('VP2', 'publicado'));
SELECT pg_temp.a('VP1', 'obsoleto');
SELECT pg_temp.caso('11 una obsoleta no retiene el nombre', 'ok', pg_temp.estado('VP2', 'publicado'));

SELECT pg_temp.crear('VP3', format('SELECT catalogo_version_nueva(%s)', pg_temp.l('PP2')));
SELECT pg_temp.caso('11 renombrar el borrador', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'VP3', $q$nombre = 'Zqx160 Otro nombre'$q$), 'Lucia'));
SELECT pg_temp.a('VP3', 'en_revision');
SELECT pg_temp.caso('11 dos publicadas en un paquete', '23505', pg_temp.estado('VP3', 'publicado'));
SELECT pg_temp.a('VP2', 'obsoleto');
SELECT pg_temp.caso('11 primero pasa a obsoleta', 'ok', pg_temp.estado('VP3', 'publicado'));

-- ============================================================
-- 12. Quién ve y quién escribe
-- ============================================================
DO $$
DECLARE
  t text;
  u text;
BEGIN
  FOREACH t IN ARRAY ARRAY['catalogo_versiones_colores', 'catalogo_piezas', 'catalogo_variables', 'catalogo_materiales',
                           'catalogo_opciones', 'catalogo_condiciones', 'catalogo_casos'] LOOP
    FOREACH u IN ARRAY ARRAY['Rodrigo', 'Carlos', 'Ana', 'Marta', 'Juan'] LOOP
      PERFORM pg_temp.caso('12 ' || u || ' en ' || t,
        CASE WHEN u IN ('Rodrigo', 'Carlos') THEN pg_temp.cuenta(t, 'V1') ELSE '0' END,
        pg_temp.ve(format('SELECT 1 FROM %I WHERE version_id = %s AND activo', t, pg_temp.l('V1')), u));
    END LOOP;
  END LOOP;
END;
$$;

SELECT pg_temp.caso('12 Rodrigo ve el paquete', '1', pg_temp.ve(format('SELECT 1 FROM catalogo_paquetes WHERE id = %s', pg_temp.l('P1')), 'Rodrigo'));
SELECT pg_temp.caso('12 Rodrigo ve las versiones', '5', pg_temp.ve(format('SELECT 1 FROM catalogo_versiones WHERE paquete_id = %s', pg_temp.l('P1')), 'Rodrigo'));
SELECT pg_temp.caso('12 Ana no ve el paquete', '0', pg_temp.ve(format('SELECT 1 FROM catalogo_paquetes WHERE id = %s', pg_temp.l('P1')), 'Ana'));
SELECT pg_temp.caso('12 Ana no ve las versiones', '0', pg_temp.ve(format('SELECT 1 FROM catalogo_versiones WHERE paquete_id = %s', pg_temp.l('P1')), 'Ana'));
SELECT pg_temp.caso('12 Juan no ve el paquete', '0', pg_temp.ve(format('SELECT 1 FROM catalogo_paquetes WHERE id = %s', pg_temp.l('P1')), 'Juan'));
SELECT pg_temp.caso('12 Juan no ve las versiones', '0', pg_temp.ve(format('SELECT 1 FROM catalogo_versiones WHERE paquete_id = %s', pg_temp.l('P1')), 'Juan'));

SELECT pg_temp.caso('12 ' || u || ' no escribe en ' || t, '42501', pg_temp.intentar(pg_temp.ins(t, 'VOtra', c, v), u))
FROM (VALUES
  ('catalogo_piezas', 'nombre', $q$'X'$q$),
  ('catalogo_variables', 'nombre, formula', $q$'y', '1'$q$),
  ('catalogo_materiales', 'pieza_id', pg_temp.l('POtra')),
  ('catalogo_opciones', 'material_id, insumo_id', format('%s, %s', pg_temp.l('MOtra'), pg_temp.l('Laminado'))),
  ('catalogo_condiciones', 'variable_id, condicion, mensaje', format($q$%s, 'x > 1', 'X'$q$, pg_temp.l('VaOtra'))),
  ('catalogo_casos', 'nombre', $q$'X'$q$),
  ('catalogo_versiones_colores', 'color_id', pg_temp.l('Negro'))
) AS x (t, c, v), unnest(ARRAY['Rodrigo', 'Carlos', 'Ana', 'Juan']) AS u;

SELECT pg_temp.caso('12 Rodrigo no renombra una pieza: 0 filas', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'POtra', $q$nombre = 'Hack'$q$), 'Rodrigo'));
SELECT pg_temp.caso('12 sigue igual', 'Pieza otra', pg_temp.campo('catalogo_piezas', 'POtra', 'nombre'));
SELECT pg_temp.caso('12 Carlos no renombra la versión: 0 filas', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_versiones', 'VOtra', $q$nombre = 'Zqx160 Hack'$q$), 'Carlos'));
SELECT pg_temp.caso('12 la versión sigue igual', 'Zqx160 Otra', pg_temp.campo('catalogo_versiones', 'VOtra', 'nombre'));

SELECT pg_temp.caso('12 version_id no se cambia en una pieza', '42501', pg_temp.intentar(pg_temp.upd('catalogo_piezas', 'POtra', format('version_id = %s', pg_temp.l('V1'))), 'Lucia'));
SELECT pg_temp.caso('12 version_id no se cambia en un material', '42501', pg_temp.intentar(pg_temp.upd('catalogo_materiales', 'MOtra', format('version_id = %s', pg_temp.l('V1'))), 'Lucia'));
SELECT pg_temp.caso('12 Lucia da de baja el paquete (sql/162)', 'ok', pg_temp.intentar(pg_temp.upd('catalogo_paquetes', 'P1', 'activo = false'), 'Lucia'));

SELECT pg_temp.caso('12 RLS en las nueve tablas', '9', (SELECT count(*)::text FROM pg_class c
  WHERE c.relnamespace = 'public'::regnamespace AND c.relrowsecurity AND c.relname = ANY (ARRAY[
    'catalogo_paquetes', 'catalogo_versiones', 'catalogo_versiones_colores', 'catalogo_piezas', 'catalogo_variables',
    'catalogo_materiales', 'catalogo_opciones', 'catalogo_condiciones', 'catalogo_casos'])));
SELECT pg_temp.caso('12 anon no llama ' || f, 'false', has_function_privilege('anon', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_paquete_alta(text,uuid)', 'catalogo_version_copiar(uuid,uuid,text)',
                  'catalogo_version_nueva(uuid,uuid)', 'catalogo_paquete_duplicar(uuid,text)']) AS f;
SELECT pg_temp.caso('12 authenticated no llama ' || f, 'false', has_function_privilege('authenticated', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_versiones_validar()', 'catalogo_contenido_validar()', 'catalogo_contenido_baja()',
                  'catalogo_categorias_validar()', 'catalogo_insumos_validar()', 'catalogo_predeterminada_apagar()',
                  'catalogo_color_base_apagar()']) AS f;

-- ============================================================
-- 13. Sumar colores y ordenar (sql/173)
-- ============================================================
SELECT pg_temp.crear('VEsc', pg_temp.alta('Zqx160 Escrituras', 'Puertas'));
SELECT pg_temp.crear('Pz1', pg_temp.ins('catalogo_piezas', 'VEsc', 'nombre, orden', $q$'Pz1', 0$q$));
SELECT pg_temp.crear('Pz2', pg_temp.ins('catalogo_piezas', 'VEsc', 'nombre, orden', $q$'Pz2', 1$q$));

CREATE FUNCTION pg_temp.sumar_color(p_color text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('SELECT catalogo_version_color_sumar(%s, %s)', pg_temp.l('VEsc'), pg_temp.l(p_color));
$f$;

CREATE FUNCTION pg_temp.ordenar(p_tabla text, p_ids text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('SELECT catalogo_contenido_ordenar(%L, ARRAY[%s]::uuid[])', p_tabla, p_ids);
$f$;

CREATE FUNCTION pg_temp.ordenes() RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(nombre || '=' || orden, ' ' ORDER BY nombre) FROM catalogo_piezas WHERE version_id = pg_temp.id('VEsc');
$f$;

CREATE FUNCTION pg_temp.colores() RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(k.nombre || '=' || c.base, ' ' ORDER BY k.nombre) FROM catalogo_versiones_colores c
  JOIN catalogo_colores k ON k.id = c.color_id WHERE c.version_id = pg_temp.id('VEsc');
$f$;

SELECT pg_temp.caso('13 Rodrigo no suma un color', '42501', pg_temp.intentar(pg_temp.sumar_color('Blanco'), 'Rodrigo'));
SELECT pg_temp.caso('13 sumar el primer color', 'ok', pg_temp.intentar(pg_temp.sumar_color('Blanco'), 'Lucia'));
SELECT pg_temp.caso('13 sumar el segundo', 'ok', pg_temp.intentar(pg_temp.sumar_color('Negro'), 'Lucia'));
SELECT pg_temp.caso('13 solo el primero es base', 'Zqx160 Blanco=true Zqx160 Negro=false', pg_temp.colores());
SELECT pg_temp.caso('13 color repetido', '23505', pg_temp.intentar(pg_temp.sumar_color('Blanco'), 'Lucia'));

SELECT pg_temp.crear('VEscCopia', format('SELECT catalogo_paquete_duplicar(%s, %L)', pg_temp.l('VEsc'), 'Zqx160 Escrituras copia'));
SELECT pg_temp.caso('13 la copia conserva el base', '1 de 2', (SELECT count(*) FILTER (WHERE base) || ' de ' || count(*)
  FROM catalogo_versiones_colores WHERE version_id = pg_temp.id('VEscCopia')));
SELECT pg_temp.crear('VOpcCopia', format('SELECT catalogo_paquete_duplicar(%s, %L)', pg_temp.l('V1'), 'Zqx160 Opciones copia'));
SELECT pg_temp.caso('13 la copia conserva la predeterminada', 'Zqx160 Float', (SELECT i.nombre FROM catalogo_opciones o
  JOIN catalogo_insumos i ON i.id = o.insumo_id WHERE o.version_id = pg_temp.id('VOpcCopia') AND o.predeterminada));

SELECT pg_temp.caso('13 ordenar', 'ok', pg_temp.intentar(pg_temp.ordenar('catalogo_piezas', pg_temp.l('Pz2') || ',' || pg_temp.l('Pz1')), 'Lucia'));
SELECT pg_temp.caso('13 quedan invertidas', 'Pz1=1 Pz2=0', pg_temp.ordenes());
SELECT pg_temp.caso('13 Rodrigo no ordena', '42501', pg_temp.intentar(pg_temp.ordenar('catalogo_piezas', pg_temp.l('Pz1') || ',' || pg_temp.l('Pz2')), 'Rodrigo'));
SELECT pg_temp.caso('13 un id que no está', '42501', pg_temp.intentar(pg_temp.ordenar('catalogo_piezas', pg_temp.l('Pz1') || ',' || quote_literal(gen_random_uuid())), 'Lucia'));
SELECT pg_temp.caso('13 no quedó a medias', 'Pz1=1 Pz2=0', pg_temp.ordenes());
SELECT pg_temp.caso('13 otra tabla', '22023', pg_temp.intentar(pg_temp.ordenar('catalogo_casos', pg_temp.l('Pz1')), 'Lucia'));
SELECT pg_temp.caso('13 anon no llama ' || f, 'false', has_function_privilege('anon', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_version_color_sumar(uuid,uuid)', 'catalogo_contenido_ordenar(text,uuid[])']) AS f;

-- ============================================================
-- Resultado
-- ============================================================
DO $$
DECLARE
  v_ok int;
  v_total int;
  v_fallan text;
BEGIN
  SELECT count(*) FILTER (WHERE ok), count(*),
         string_agg(caso || ' → esperado ' || coalesce(esperado, 'NULL') || ', obtenido ' || coalesce(obtenido, 'NULL'),
                    E'\n' ORDER BY caso) FILTER (WHERE NOT ok)
  INTO v_ok, v_total, v_fallan
  FROM r;
  RAISE EXCEPTION '% / % ok%', v_ok, v_total, coalesce(E'\n' || v_fallan, '');
END;
$$;

ROLLBACK;
