-- Verificación de sql/186: el precio para quien arma, el formulario de venta, los renglones de Catálogo y a mano, el
-- descuento y los totales. NO es una migración: todo corre dentro de una transacción que revierte. Termina en un DO que
-- lanza "N / M ok" y los casos que fallan.
--
-- Mundo: el de presupuestos_registros.sql (Juan responsable de Belgrano y vendedor, Pedro participante, Ana vendedora sin
-- la obra, JN jefe sin armar, G gerencia, T Técnica), más Lucia (Técnica de Catálogo) y Carlos (gerente de Catálogo, sin
-- Presupuestos). V es la ventana de $200.000 con 1000 × 1000 ($140.000 de perfil y $60.000 de Float), Viejo un paquete de
-- $1.000 que sale de la venta. Dólar oficial a $1.000. Lo creado lleva Zqx186.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE pasos;
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

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT count(*)::text FROM (%s) x', p_sql), p_como);
$f$;

-- ---------- Catálogo, como en sql/tests/catalogo_precio.sql ----------
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

CREATE FUNCTION pg_temp.mete(p_clave text, p_tabla text, p_version text, p_j jsonb) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_cols text;
BEGIN
  SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p_j) k;
  PERFORM pg_temp.crear(coalesce(p_clave, p_tabla || ' ' || gen_random_uuid()), format(
    'INSERT INTO %1$I (version_id, %2$s) SELECT %3$s::uuid, %2$s FROM jsonb_populate_record(NULL::%1$I, %4$L) RETURNING id',
    p_tabla, v_cols, pg_temp.l(p_version), p_j::text));
END;
$f$;

CREATE FUNCTION pg_temp.ver(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_v, format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx186 ' || p_v, pg_temp.l('Ventanas')));
$f$;

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.un(p_v text, p_pieza text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_insumo, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', 'unico',
                       'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.op(p_v text, p_material text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_insumo, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden, 'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)',
    'Zqx186 ' || p_nombre, pg_temp.l(p_categoria), p_unidad));
$f$;

CREATE FUNCTION pg_temp.costo(p_insumo text, p_costo numeric) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, p_costo, 'ARS', pg_temp.id('Carlos'), now() - interval '10 days'
  FROM catalogo_variantes va WHERE va.insumo_id = pg_temp.id(p_insumo) AND va.color_id IS NULL;
$f$;

CREATE FUNCTION pg_temp.publicar(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso('enviar ' || p_v, 'ok', pg_temp.intentar(format('SELECT catalogo_version_enviar(%s)', pg_temp.l(p_v)), 'Lucia'));
  SELECT pg_temp.caso('aprobar ' || p_v, 'ok', pg_temp.intentar(format('SELECT catalogo_version_aprobar(%s)', pg_temp.l(p_v)), 'Carlos'));
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

-- ---------- Presupuestos ----------
-- Una entrada con medidas y lo que se le sume.
CREATE FUNCTION pg_temp.e(p_ancho numeric DEFAULT 1000, p_alto numeric DEFAULT 1000, p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('variables', jsonb_build_object('ancho', p_ancho, 'alto', p_alto)) || p_extra;
$f$;

CREATE FUNCTION pg_temp.seccion(p_nombre text, p_version text, p_moneda text, p_alicuota numeric, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := gen_random_uuid();
  v text;
BEGIN
  v := pg_temp.intentar(format(
    'INSERT INTO presupuestos_secciones (id, version_id, nombre, moneda, alicuota) VALUES (%L, %s, %L, %L, %s)',
    v_id, pg_temp.l(p_version), 'Zqx186 ' || p_nombre, p_moneda, p_alicuota), p_como);
  IF v = 'ok' THEN INSERT INTO ids VALUES (p_nombre, v_id); END IF;
  RETURN v;
END;
$f$;

-- Un renglón en una sección (de la versión de esa sección, salvo que se diga otra). Guarda el id con su nombre.
CREATE FUNCTION pg_temp.renglon(p_nombre text, p_seccion text, p_j jsonb, p_como text DEFAULT 'Juan', p_version text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := gen_random_uuid();
  v_version uuid := coalesce(pg_temp.id(p_version), (SELECT version_id FROM presupuestos_secciones WHERE id = pg_temp.id(p_seccion)));
  v_cols text;
  v text;
BEGIN
  SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p_j) k;
  v := pg_temp.intentar(format(
    'INSERT INTO presupuestos_renglones (id, version_id, seccion_id, %1$s) SELECT %2$L, %3$L, %4$L, %1$s FROM jsonb_populate_record(NULL::presupuestos_renglones, %5$L)',
    v_cols, v_id, v_version, pg_temp.id(p_seccion), p_j), p_como);
  IF v = 'ok' THEN INSERT INTO ids VALUES (p_nombre, v_id); END IF;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.ventana(p_entrada jsonb DEFAULT pg_temp.e(), p_extra jsonb DEFAULT '{}', p_paquete text DEFAULT 'V') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('tipo', 'catalogo', 'paquete_id', pg_temp.paquete(p_paquete), 'entrada', p_entrada) || p_extra;
$f$;

CREATE FUNCTION pg_temp.dato(p_renglon text, p_col text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v text;
BEGIN
  EXECUTE format('SELECT %s::text FROM presupuestos_renglones WHERE id = %L', p_col, pg_temp.id(p_renglon)) INTO v;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.precio(p_renglon text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.dato(p_renglon, 'trim_scale(precio) || '' '' || moneda');
$f$;

CREATE FUNCTION pg_temp.cambia(p_renglon text, p_set text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE presupuestos_renglones SET %s WHERE id = %L', p_set, pg_temp.id(p_renglon)), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE catalogo_porcentajes_valores SET activo = false WHERE activo;
UPDATE monedas_tipos_cambio SET activo = false WHERE activo;
INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde) VALUES
  ('USD_OFICIAL', 1000, now(), 'monedapi', now() - interval '20 days'),
  ('USD_BLUE',    2000, now(), 'monedapi', now() - interval '20 days'),
  ('EUR',         1200, now(), 'monedapi', now() - interval '20 days');

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','JN','Vero','Pedro','Ana','G','T','Lucia','Carlos','Norte','Sur','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo IN ('catalogo', 'presupuestos') OR codigo IN
  ('contactos_ver','obras_ver','obras_equipo','obras_todas','obras_administrar','usuarios_delegar','usuarios_equipo',
   'tareas_ver','tareas_equipo'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test186.local', jsonb_build_object('nombre', 'test186 ' || nombre)
FROM ids WHERE nombre IN ('Juan','JN','Vero','Pedro','Ana','G','T','Lucia','Carlos');

INSERT INTO equipos (id, nombre)
SELECT id, 'test186 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('Norte','Juan'),('Norte','JN'),('Norte','Vero'),('Sur','Pedro'),('Sur','Ana')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','presupuestos_ver'), ('Pedro','presupuestos_armar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('Vero','contactos_ver'), ('Vero','obras_ver'),
  ('JN','contactos_ver'), ('JN','obras_ver'), ('JN','usuarios_equipo'), ('JN','usuarios_delegar'), ('JN','obras_equipo'),
    ('JN','tareas_ver'), ('JN','tareas_equipo'), ('JN','presupuestos_ver'), ('JN','presupuestos_autorizar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion'),
  ('T','presupuestos_revision'), ('T','presupuestos_autorizar_tecnica'),
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx186 Torre Belgrano', 'Zqx186 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Pedro'), pg_temp.id('Juan'));

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx186 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx186 Vidrios') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx186 Ventanas') RETURNING id$q$);
SELECT pg_temp.insumo('Perfil', 'Perfiles', 'mm');
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2');
SELECT pg_temp.insumo('DVH', 'Vidrios', 'm2');
SELECT pg_temp.insumo('Tela', 'Perfiles', 'm2');
SELECT pg_temp.insumo('Manija', 'Perfiles', 'u');
SELECT pg_temp.costo('Perfil', 70000);
SELECT pg_temp.costo('Float', 60000);
SELECT pg_temp.costo('DVH', 100000);
SELECT pg_temp.costo('Tela', 5000);
SELECT pg_temp.costo('Manija', 1000);

-- Garantía de vidrio: 5 % de los Vidrios, opcional.
INSERT INTO ids VALUES ('Garantia', gen_random_uuid());
INSERT INTO catalogo_porcentajes (id) VALUES (pg_temp.id('Garantia'));
INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, opcional, de_baja, creado_por, created_at)
VALUES (pg_temp.id('Garantia'), 'Zqx186 Garantia', 5, 1, ARRAY[pg_temp.id('Vidrios')], true, false, pg_temp.id('Carlos'),
        now() - interval '10 days');

SELECT pg_temp.ver('V');
SELECT pg_temp.mete('V.ancho', 'catalogo_variables', 'V', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1200"}');
SELECT pg_temp.mete('V.alto', 'catalogo_variables', 'V', '{"nombre": "alto", "orden": 2, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1000"}');
SELECT pg_temp.pz('V', 'Marco', 1);
SELECT pg_temp.un('V', 'Marco', 1, 'Perfil', '{"medida": "ancho", "cantidad": "2"}');
SELECT pg_temp.pz('V', 'Hoja', 2);
SELECT pg_temp.mete('V.Hoja.Vidrio', 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Hoja'),
  'orden', 1, 'tipo', 'elige_vendedor', 'nombre', 'Vidrio', 'ancho', 'ancho', 'alto', 'alto'));
SELECT pg_temp.op('V', 'V.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('V', 'V.Hoja.Vidrio', 2, 'DVH');
SELECT pg_temp.pz('V', 'Mosquitero', 3, '{"opcional": true}');
SELECT pg_temp.un('V', 'Mosquitero', 1, 'Tela', '{"ancho": "ancho", "alto": "alto"}');
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.ancho'), 'condicion', 'ancho > 4000', 'mensaje', 'Demasiado ancho', 'bloquea', true));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'V', jsonb_build_object('nombre', 'base', 'entrada', pg_temp.e()));
SELECT pg_temp.publicar('V');

SELECT pg_temp.ver('Viejo');
SELECT pg_temp.pz('Viejo', 'Unica', 1);
SELECT pg_temp.un('Viejo', 'Unica', 1, 'Manija', '{"cantidad": "1"}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Viejo', '{"nombre": "base"}');
SELECT pg_temp.publicar('Viejo');

INSERT INTO ids VALUES ('P1', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx186 Ventanas', 'ARS', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('V1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1')));
INSERT INTO ids VALUES ('S1', (SELECT id FROM presupuestos_secciones WHERE version_id = pg_temp.id('V1')));
INSERT INTO ids VALUES ('P2', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx186 Puertas', 'ARS', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('S2otro', (SELECT s.id FROM presupuestos_secciones s JOIN presupuestos_versiones v ON v.id = s.version_id
                                   WHERE v.presupuesto_id = pg_temp.id('P2')));
SELECT pg_temp.caso('montaje: sección en dólares', 'ok', pg_temp.seccion('Dolares', 'V1', 'USD_OFICIAL', 21));

-- ============================================================
-- 00. El precio, la venta y el formulario: quien arma
-- ============================================================
SELECT pg_temp.caso('00 precio: ' || u, x, pg_temp.consultar(format(
  'SELECT catalogo_precio(%L, %L::jsonb, ''{}''::uuid[], ''ARS'') ->> ''precio''', pg_temp.paquete('V'), pg_temp.e()), u))
FROM (VALUES ('Juan', '200000'), ('G', '200000'), ('Carlos', '42501'), ('JN', '42501'), ('T', '42501'), ('Lucia', '42501'))
  AS c (u, x);
SELECT pg_temp.caso('00 precio trae la versión', 'true', pg_temp.consultar(format(
  'SELECT (catalogo_precio(%L, %L::jsonb) ->> ''version_id'' = %L)::text', pg_temp.paquete('V'), pg_temp.e(), pg_temp.id('V')), 'Juan'));
SELECT pg_temp.caso('00 mínimos: Carlos ya no', '42501', pg_temp.intentar(format(
  'SELECT * FROM catalogo_precio_minimos(%L::jsonb)', jsonb_build_array(jsonb_build_object('paquete_id', pg_temp.paquete('V'), 'cantidad', 1))),
  'Carlos'));
SELECT pg_temp.caso('00 mínimos: Juan sí', 'ok', pg_temp.intentar(format(
  'SELECT * FROM catalogo_precio_minimos(%L::jsonb)', jsonb_build_array(jsonb_build_object('paquete_id', pg_temp.paquete('V'), 'cantidad', 1))),
  'Juan'));
SELECT pg_temp.caso('00 venta: Juan ve V y Viejo', '2', pg_temp.ve(format(
  'SELECT 1 FROM catalogo_venta() WHERE paquete_id IN (%L, %L)', pg_temp.paquete('V'), pg_temp.paquete('Viejo')), 'Juan'));
SELECT pg_temp.caso('00 venta: con su categoría', 'Zqx186 Ventanas', pg_temp.consultar(format(
  'SELECT categoria FROM catalogo_venta() WHERE paquete_id = %L', pg_temp.paquete('V')), 'Juan'));
SELECT pg_temp.caso('00 venta: Carlos no', '42501', pg_temp.intentar('SELECT * FROM catalogo_venta()', 'Carlos'));

CREATE FUNCTION pg_temp.form(p_ruta text, p_como text DEFAULT 'Juan', p_v text DEFAULT 'V') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT %s FROM catalogo_venta_formulario(%L) f', p_ruta, pg_temp.paquete(p_v)), p_como);
$f$;
SELECT pg_temp.caso('00 formulario: la versión publicada', 'true', pg_temp.form(format('(f->>''version_id'' = %L)::text', pg_temp.id('V'))));
SELECT pg_temp.caso('00 formulario: las variables del vendedor, en orden', 'ancho,alto', pg_temp.form(
  $q$(SELECT string_agg(x->>'nombre', ',') FROM jsonb_array_elements(f->'variables') x)$q$));
SELECT pg_temp.caso('00 formulario: predeterminado calculado', '1200', pg_temp.form(
  $q$(SELECT x->>'predeterminado' FROM jsonb_array_elements(f->'variables') x WHERE x->>'nombre' = 'ancho')$q$));
SELECT pg_temp.caso('00 formulario: solo las piezas opcionales', 'Mosquitero/false', pg_temp.form(
  $q$(SELECT string_agg((x->>'nombre') || '/' || (x->>'incluida'), ',') FROM jsonb_array_elements(f->'piezas') x)$q$));
SELECT pg_temp.caso('00 formulario: lo que elige el vendedor', 'Vidrio', pg_temp.form(
  $q$(SELECT string_agg(x->>'nombre', ',') FROM jsonb_array_elements(f->'materiales') x)$q$));
SELECT pg_temp.caso('00 formulario: sus opciones, la predeterminada primero', 'Zqx186 Float/true,Zqx186 DVH/false', pg_temp.form(
  $q$(SELECT string_agg((x->>'nombre') || '/' || (x->>'predeterminada'), ',') FROM jsonb_array_elements(f->'opciones') x)$q$));
SELECT pg_temp.caso('00 formulario: sin colores, una fila sin color', '1/null', pg_temp.form(
  $q$jsonb_array_length(f->'colores') || '/' || coalesce(f->'colores'->0->>'id', 'null')$q$));
SELECT pg_temp.caso('00 formulario: los servicios opcionales', 'Zqx186 Garantia', pg_temp.form(
  $q$(SELECT string_agg(x->>'nombre', ',') FROM jsonb_array_elements(f->'servicios') x WHERE x->>'nombre' LIKE 'Zqx186%')$q$));
SELECT pg_temp.caso('00 formulario: sin fórmulas ni costos', 'false', pg_temp.form(
  $q$(f::text LIKE '%formula%' OR f::text LIKE '%costo%')::text$q$));
SELECT pg_temp.caso('00 formulario: Carlos no', '42501', pg_temp.form('f::text', 'Carlos'));

-- ============================================================
-- 01. Renglón de Catálogo: se calcula a hoy al crearlo
-- ============================================================
SELECT pg_temp.caso('01 alta', 'ok', pg_temp.renglon('R1', 'S1', pg_temp.ventana(pg_temp.e(), '{"cantidad": 2, "designacion": "V1", "ubicacion": "Living"}')));
SELECT pg_temp.caso('01 precio de Catálogo, en la moneda de la sección', '200000 ARS', pg_temp.precio('R1'));
SELECT pg_temp.caso('01 guarda la versión, las condiciones y lo cargado', 'true/true/true', pg_temp.dato('R1', format(
  $q$(catalogo_version_id = %L) || '/' || (condiciones_en = now()) || '/' || (entrada = %L::jsonb)$q$, pg_temp.id('V'), pg_temp.e())));
SELECT pg_temp.caso('01 sin opcionales ni mensajes', '{}/[]', pg_temp.dato('R1', $q$opcionales::text || '/' || mensajes::text$q$));
SELECT pg_temp.caso('01 en dólares, con DVH', 'ok', pg_temp.renglon('R2', 'Dolares', pg_temp.ventana(pg_temp.e(1000, 1000, jsonb_build_object(
  'elecciones', jsonb_build_object('Hoja', jsonb_build_object('Vidrio', pg_temp.id('DVH'))))))));
SELECT pg_temp.caso('01 DVH en dólares', '240 USD_OFICIAL', pg_temp.precio('R2'));
SELECT pg_temp.caso('01 el precio escrito no se toma', 'ok', pg_temp.renglon('R3', 'S1', pg_temp.ventana(pg_temp.e(), '{"precio": 1}')));
SELECT pg_temp.caso('01 el precio escrito no se toma: precio', '200000 ARS', pg_temp.precio('R3'));
SELECT pg_temp.caso('01 con la garantía opcional', 'ok', pg_temp.renglon('R4', 'S1', pg_temp.ventana(pg_temp.e(),
  jsonb_build_object('opcionales', ARRAY[pg_temp.id('Garantia')]))));
SELECT pg_temp.caso('01 la garantía suma 5 % del Float', '203000 ARS', pg_temp.precio('R4'));
SELECT pg_temp.caso('01 con el mosquitero', 'ok', pg_temp.renglon('R5', 'S1', pg_temp.ventana(pg_temp.e(1000, 1000, '{"piezas": {"Mosquitero": true}}'))));
SELECT pg_temp.caso('01 el mosquitero suma la tela', '205000 ARS', pg_temp.precio('R5'));
SELECT pg_temp.caso('01 un bloqueo se guarda sin precio', 'ok', pg_temp.renglon('Rbloq', 'S1', pg_temp.ventana(pg_temp.e(4500, 1000))));
SELECT pg_temp.caso('01 sin precio, con el bloqueo en mensajes', 'null/Demasiado ancho', pg_temp.dato('Rbloq',
  $q$coalesce(precio::text, 'null') || '/' || (SELECT string_agg(m->>'mensaje', ',') FROM jsonb_array_elements(mensajes) m WHERE (m->>'bloquea')::boolean)$q$));
SELECT pg_temp.caso('01 entrada con otra forma', 'CA017', pg_temp.renglon('X', 'S1', pg_temp.ventana('{"variables": 5}')));
SELECT pg_temp.caso('01 Pedro (participante) arma', 'ok', pg_temp.renglon('RP', 'S1', pg_temp.ventana(), 'Pedro'));
SELECT pg_temp.caso('01 G (administrar) arma', 'ok', pg_temp.renglon('RG', 'S1', pg_temp.ventana(), 'G'));
SELECT pg_temp.caso('01 Ana (no trabaja la obra) no', '42501', pg_temp.renglon('X', 'S1', pg_temp.ventana(), 'Ana'));
SELECT pg_temp.caso('01 JN (sin armar) no', '42501', pg_temp.renglon('X', 'S1', pg_temp.ventana(), 'JN'));
SELECT pg_temp.caso('01 T no', '42501', pg_temp.renglon('X', 'S1', pg_temp.ventana(), 'T'));
SELECT pg_temp.caso('01 con descripción no', '23514', pg_temp.renglon('X', 'S1', pg_temp.ventana(pg_temp.e(), '{"descripcion": "x"}')));
SELECT pg_temp.caso('01 sección de otra versión no', '23503', pg_temp.renglon('X', 'S2otro', pg_temp.ventana(), 'Juan', 'V1'));
SELECT pg_temp.caso('01 cantidad 0 no', '23514', pg_temp.renglon('X', 'S1', pg_temp.ventana(pg_temp.e(), '{"cantidad": 0}')));
SELECT pg_temp.caso('01 la condición de Catálogo no se escribe', '42501', pg_temp.renglon('X', 'S1', pg_temp.ventana(pg_temp.e(),
  '{"condiciones_en": "2020-01-01"}')));

-- ============================================================
-- 02. Renglón a mano
-- ============================================================
SELECT pg_temp.caso('02 alta', 'ok', pg_temp.renglon('M1', 'S1', '{"tipo": "mano", "descripcion": "Flete cerrado", "precio": 50000}'));
SELECT pg_temp.caso('02 en la moneda de la sección', '50000 ARS', pg_temp.precio('M1'));
SELECT pg_temp.caso('02 sin precio no', '23514', pg_temp.renglon('X', 'S1', '{"tipo": "mano", "descripcion": "x"}'));
SELECT pg_temp.caso('02 sin descripción no', '23514', pg_temp.renglon('X', 'S1', '{"tipo": "mano", "precio": 1}'));
SELECT pg_temp.caso('02 negativo no', '23514', pg_temp.renglon('X', 'S1', '{"tipo": "mano", "descripcion": "x", "precio": -1}'));
SELECT pg_temp.caso('02 con paquete no', '23514', pg_temp.renglon('X', 'S1', jsonb_build_object(
  'tipo', 'mano', 'descripcion', 'x', 'precio', 1, 'paquete_id', pg_temp.paquete('V'))));
SELECT pg_temp.caso('02 cambia su precio', 'ok', pg_temp.cambia('M1', 'precio = 60000'));
SELECT pg_temp.caso('02 cambia su precio: precio', '60000 ARS', pg_temp.precio('M1'));

-- ============================================================
-- 03. Editar: lo cargado y la moneda recalculan; lo demás, no
-- ============================================================
SELECT pg_temp.caso('03 cantidad, designación y orden no recalculan', 'ok',
  pg_temp.cambia('R1', $q$cantidad = 3, designacion = 'V9', orden = 4$q$));
SELECT pg_temp.caso('03 cantidad: el precio es por unidad', '200000 ARS/3', pg_temp.dato('R1', $q$trim_scale(precio) || ' ' || moneda || '/' || cantidad$q$));
SELECT pg_temp.caso('03 el precio de Catálogo no se escribe', 'ok', pg_temp.cambia('R1', 'precio = 1'));
SELECT pg_temp.caso('03 el precio de Catálogo no se escribe: precio', '200000 ARS', pg_temp.precio('R1'));
SELECT pg_temp.caso('03 lo cargado recalcula', 'ok', pg_temp.cambia('R1', format('entrada = %L', pg_temp.e(2000, 1000))));
SELECT pg_temp.caso('03 lo cargado recalcula: precio', '400000 ARS', pg_temp.precio('R1'));
SELECT pg_temp.caso('03 sumar la garantía recalcula', 'ok', pg_temp.cambia('R3', format('opcionales = ARRAY[%L]::uuid[]', pg_temp.id('Garantia'))));
SELECT pg_temp.caso('03 sumar la garantía recalcula: precio', '203000 ARS', pg_temp.precio('R3'));
SELECT pg_temp.caso('03 pasar a la sección en dólares recalcula', 'ok', pg_temp.cambia('R1', format('seccion_id = %L', pg_temp.id('Dolares'))));
SELECT pg_temp.caso('03 pasar a la sección en dólares recalcula: precio', '400 USD_OFICIAL', pg_temp.precio('R1'));
SELECT pg_temp.caso('03 el a mano no pasa a dólares', 'PR009', pg_temp.cambia('M1', format('seccion_id = %L', pg_temp.id('Dolares'))));
SELECT pg_temp.caso('03 la sección con un a mano no cambia de moneda', 'PR009', pg_temp.intentar(format(
  $q$UPDATE presupuestos_secciones SET moneda = 'USD_BLUE' WHERE id = %L$q$, pg_temp.id('S1')), 'Juan'));
SELECT pg_temp.caso('03 y nada cambió', '203000 ARS', pg_temp.precio('R4'));
SELECT pg_temp.caso('03 cambiar la moneda de la sección recalcula', 'ok', pg_temp.intentar(format(
  $q$UPDATE presupuestos_secciones SET moneda = 'USD_BLUE' WHERE id = %L$q$, pg_temp.id('Dolares')), 'Juan'));
SELECT pg_temp.caso('03 cambiar la moneda de la sección recalcula: precios', '200 USD_BLUE/120 USD_BLUE',
  pg_temp.precio('R1') || '/' || pg_temp.precio('R2'));
SELECT pg_temp.caso('03 Ana no edita', '0', pg_temp.consultar(format(
  'WITH u AS (UPDATE presupuestos_renglones SET cantidad = 9 WHERE id = %L RETURNING 1) SELECT count(*)::text FROM u', pg_temp.id('R2')), 'Ana'));

-- Un paquete que sale de la venta: lo que ya estaba queda sin precio; no se elige de nuevo.
SELECT pg_temp.caso('03 renglón de Viejo', 'ok', pg_temp.renglon('RV', 'S1', pg_temp.ventana('{}', '{}', 'Viejo')));
SELECT pg_temp.caso('03 renglón de Viejo: precio', '1000 ARS', pg_temp.precio('RV'));
SELECT pg_temp.caso('03 Viejo sale de la venta', 'ok', pg_temp.intentar(format(
  'UPDATE catalogo_paquetes SET activo = false WHERE id = %L', pg_temp.paquete('Viejo')), 'Lucia'));
SELECT pg_temp.caso('03 sin la venta, no se crea', 'PR010', pg_temp.renglon('X', 'S1', pg_temp.ventana('{}', '{}', 'Viejo')));
SELECT pg_temp.caso('03 sin la venta, no se cambia a él', 'PR010', pg_temp.cambia('R3', format('paquete_id = %L', pg_temp.paquete('Viejo'))));
SELECT pg_temp.caso('03 el que estaba se recalcula', 'ok', pg_temp.cambia('RV', $q$entrada = '{"variables": {}}'$q$));
SELECT pg_temp.caso('03 el que estaba queda sin precio, con su versión y el porqué', 'null/true/Este paquete no está a la venta',
  pg_temp.dato('RV', format($q$coalesce(precio::text, 'null') || '/' || (catalogo_version_id = %L) || '/' || mensaje$q$, pg_temp.id('Viejo'))));
SELECT pg_temp.caso('03 formulario de Viejo: nada', 'null', coalesce(pg_temp.form('f::text', 'Juan', 'Viejo'), 'null'));

-- ============================================================
-- 04. Secciones y lo sacado
-- ============================================================
SELECT pg_temp.caso('04 la sección con renglones no se saca', 'PR011', pg_temp.intentar(format(
  'UPDATE presupuestos_secciones SET activo = false WHERE id = %L', pg_temp.id('Dolares')), 'Juan'));
SELECT pg_temp.caso('04 sacar sus renglones', 'ok', pg_temp.intentar(format(
  'UPDATE presupuestos_renglones SET activo = false WHERE seccion_id = %L', pg_temp.id('Dolares')), 'Juan'));
SELECT pg_temp.caso('04 sacado, conserva su precio', '200 USD_BLUE', pg_temp.precio('R1'));
SELECT pg_temp.caso('04 ahora se saca', 'ok', pg_temp.intentar(format(
  'UPDATE presupuestos_secciones SET activo = false WHERE id = %L', pg_temp.id('Dolares')), 'Juan'));
SELECT pg_temp.caso('04 nada entra en la sacada', 'PR008', pg_temp.renglon('X', 'Dolares', pg_temp.ventana()));
SELECT pg_temp.caso('04 el renglón sacado no vuelve', 'PR002', pg_temp.cambia('R2', 'activo = true'));

-- ============================================================
-- 05. Fuera de borrador nada se edita
-- ============================================================
UPDATE presupuestos_versiones SET estado = 'en_revision' WHERE id = pg_temp.id('V1');
SELECT pg_temp.caso('05 en revisión: alta', 'PR005', pg_temp.renglon('X', 'S1', pg_temp.ventana()));
SELECT pg_temp.caso('05 en revisión: editar', 'PR005', pg_temp.cambia('R4', 'cantidad = 5'));
SELECT pg_temp.caso('05 en revisión: descuento', 'PR005', pg_temp.intentar(format(
  'UPDATE presupuestos_versiones SET descuento = 5 WHERE id = %L', pg_temp.id('V1')), 'Juan'));
UPDATE presupuestos_versiones SET estado = 'borrador' WHERE id = pg_temp.id('V1');

-- ============================================================
-- 06. Descuento y totales
-- ============================================================
-- P3: ventanas al 21 % (2 × $200.000), colocación a mano al 10,5 % ($100.000), una ventana en dólares (US$ 200) y una
-- bloqueada. Con 10 % de descuento: ARS 500.000 − 50.000, IVA 75.600 + 9.450, total 535.050; USD 200 − 20, IVA 37,80.
INSERT INTO ids VALUES ('P3', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx186 Totales', 'ARS', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('V3', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P3')));
INSERT INTO ids VALUES ('A', (SELECT id FROM presupuestos_secciones WHERE version_id = pg_temp.id('V3')));
SELECT pg_temp.caso('06 secciones', 'ok/ok', pg_temp.seccion('Deptos', 'V3', 'ARS', 10.5) || '/' || pg_temp.seccion('USD', 'V3', 'USD_OFICIAL', 21));
SELECT pg_temp.caso('06 renglones', 'ok/ok/ok/ok',
  pg_temp.renglon('T1', 'A', pg_temp.ventana(pg_temp.e(), '{"cantidad": 2}')) || '/' ||
  pg_temp.renglon('T2', 'Deptos', '{"tipo": "mano", "descripcion": "Colocación", "precio": 100000}') || '/' ||
  pg_temp.renglon('T3', 'USD', pg_temp.ventana()) || '/' ||
  pg_temp.renglon('T4', 'A', pg_temp.ventana(pg_temp.e(4500, 1000))));
SELECT pg_temp.caso('06 descuento', 'ok', pg_temp.intentar(format(
  'UPDATE presupuestos_versiones SET descuento = 10 WHERE id = %L', pg_temp.id('V3')), 'Juan'));
SELECT pg_temp.caso('06 descuento de más de 100 no', '23514', pg_temp.intentar(format(
  'UPDATE presupuestos_versiones SET descuento = 101 WHERE id = %L', pg_temp.id('V3')), 'Juan'));

CREATE FUNCTION pg_temp.tot(p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format($q$
    SELECT string_agg(t.moneda || ' ' || trim_scale(t.subtotal) || '/' || trim_scale(t.descuento) || '/' ||
      (SELECT string_agg((i->>'alicuota') || '=' || (i->>'monto'), ',') FROM jsonb_array_elements(t.iva) i) || '/' ||
      trim_scale(t.total) || '/' || t.sin_precio, ' | ')
    FROM presupuestos_version_totales(%L) t$q$, pg_temp.id('V3')), p_como), 'nada');
$f$;
SELECT pg_temp.caso('06 totales por moneda', 'ARS 500000/50000/21.0=75600,10.5=9450/535050/1 | USD_OFICIAL 200/20/21.0=37.80/217.8/0', pg_temp.tot());
SELECT pg_temp.caso('06 JN (ve la obra) los ve', 'true', (SELECT (pg_temp.tot('JN') = pg_temp.tot())::text));
SELECT pg_temp.caso('06 Ana no', 'nada', pg_temp.tot('Ana'));

-- ============================================================
-- 07. Quién ve los renglones
-- ============================================================
SELECT pg_temp.caso('07 ve: ' || u, x, pg_temp.ve(format('SELECT 1 FROM presupuestos_renglones WHERE version_id = %L', pg_temp.id('V3')), u))
FROM (VALUES ('Juan', '4'), ('JN', '4'), ('G', '4'), ('Ana', '0'), ('T', '0'), ('Carlos', '0')) AS c (u, x);

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
