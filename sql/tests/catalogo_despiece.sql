-- Verificación de sql/161: el cálculo del despiece. NO es una migración: todo corre dentro de una transacción que
-- revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Lucia (Técnica: Paquetes con armar, Insumos con cargar), Ana (Administración: Insumos con costos, Servicios
-- fijos con editar), Carlos (gerente: Paquetes con aprobar), Rodrigo (solo Paquetes, revisa cortes) y Juan (nada). Lo
-- creado lleva Zqx161. Cada tema arma su propia versión: en un borrador se puede dejar a medias a propósito.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE TEMP TABLE res (clave text PRIMARY KEY, j jsonb) ON COMMIT DROP;
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

-- Mete una fila con Lucia. Las columnas son las claves del JSON.
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
  SELECT pg_temp.crear(p_v, format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx161 ' || p_v, pg_temp.l('Ventanas')));
$f$;

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.en_pieza(p_v text, p_pieza text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza));
$f$;

-- Una variable calculada.
CREATE FUNCTION pg_temp.vr(p_v text, p_nombre text, p_orden int, p_formula text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_variables', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden, 'formula', p_formula) || p_extra);
$f$;

-- Una variable que ingresa el vendedor.
CREATE FUNCTION pg_temp.en(p_v text, p_nombre text, p_orden int, p_min numeric, p_max numeric, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_variables', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden, 'ingresa_vendedor', true, 'minimo', p_min, 'maximo', p_max) || p_extra);
$f$;

CREATE FUNCTION pg_temp.un(p_v text, p_pieza text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_insumo || '.' || p_orden, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', 'unico',
                       'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.mu(p_v text, p_pieza text, p_orden int, p_tipo text, p_nombre text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_nombre, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', p_tipo, 'nombre', p_nombre) || p_extra);
$f$;

CREATE FUNCTION pg_temp.op(p_v text, p_material text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || coalesce(p_insumo, 'ninguna'), 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden, 'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.pareja(p_v text, p_material text, p_orden int, p_de text, p_insumo text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_de, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden,
                       'sigue_opcion_id', pg_temp.id(p_de), 'insumo_id', pg_temp.id(p_insumo)));
$f$;

CREATE FUNCTION pg_temp.co(p_v text, p_col text, p_clave text, p_condicion text, p_mensaje text, p_bloquea boolean DEFAULT false) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(NULL, 'catalogo_condiciones', p_v, jsonb_build_object(
    p_col, pg_temp.id(p_clave), 'condicion', p_condicion, 'mensaje', p_mensaje, 'bloquea', p_bloquea));
$f$;

CREATE FUNCTION pg_temp.calc(p_clave text, p_version text, p_entrada jsonb DEFAULT '{}', p_como text DEFAULT 'Rodrigo') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text;
BEGIN
  v := pg_temp.consultar(format('SELECT catalogo_despiece(%s, %L)', pg_temp.l(p_version), p_entrada::text), p_como);
  INSERT INTO res VALUES (p_clave, CASE WHEN v ~ '^\{' THEN v::jsonb ELSE to_jsonb(v) END);
END;
$f$;

CREATE FUNCTION pg_temp.el(p_pieza text, p_material text, p_insumo text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('elecciones', jsonb_build_object(p_pieza, jsonb_build_object(p_material, pg_temp.id(p_insumo))));
$f$;

CREATE FUNCTION pg_temp.g(p_clave text, p_ruta text) RETURNS text LANGUAGE sql AS $f$
  SELECT j #>> p_ruta::text[] FROM res WHERE clave = p_clave;
$f$;

CREATE FUNCTION pg_temp.n(p_x text) RETURNS text LANGUAGE sql AS $f$
  SELECT CASE WHEN p_x ~ '^-?[0-9.]+(e-?[0-9]+)?$' THEN trim_scale(round(p_x::numeric, 3))::text ELSE p_x END;
$f$;

-- Un campo de la fila número p_n de ese material. El único se llama como su insumo.
CREATE FUNCTION pg_temp.f(p_clave text, p_material text, p_campo text, p_n int DEFAULT 1) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.n(x.fila->>p_campo)
  FROM (
    SELECT e.fila, row_number() OVER (ORDER BY e.i) AS n
    FROM res, jsonb_array_elements(j->'filas') WITH ORDINALITY e(fila, i)
    WHERE clave = p_clave AND e.fila->>'material' IN (p_material, 'Zqx161 ' || p_material)
  ) x
  WHERE x.n = p_n;
$f$;

CREATE FUNCTION pg_temp.pie(p_clave text, p_pieza text, p_campo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.n(e->>p_campo) FROM res, jsonb_array_elements(j->'piezas') e WHERE clave = p_clave AND e->>'nombre' = p_pieza;
$f$;

CREATE FUNCTION pg_temp.var(p_clave text, p_nombre text, p_campo text DEFAULT 'valor') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.n(e->>p_campo) FROM res, jsonb_array_elements(j->'variables') e WHERE clave = p_clave AND e->>'nombre' = p_nombre;
$f$;

CREATE FUNCTION pg_temp.filas(p_clave text) RETURNS text LANGUAGE sql AS $f$
  SELECT jsonb_array_length(j->'filas')::text FROM res WHERE clave = p_clave;
$f$;

CREATE FUNCTION pg_temp.err(p_clave text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(e, ' | ' ORDER BY e) FROM res, jsonb_array_elements_text(j->'errores') e WHERE clave = p_clave;
$f$;

CREATE FUNCTION pg_temp.men(p_clave text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(e->>'mensaje', ' | ' ORDER BY e->>'mensaje') FROM res, jsonb_array_elements(j->'mensajes') e WHERE clave = p_clave;
$f$;

CREATE FUNCTION pg_temp.tiene(p_clave text, p_texto text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso(p_clave || ' dice: ' || p_texto, 'true', (position(p_texto IN coalesce(pg_temp.err(p_clave), '')) > 0)::text);
$f$;

-- Salió, sin filas y con el mensaje de siempre: un borrador a medias no es un error de la base.
CREATE FUNCTION pg_temp.no_sale(p_clave text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso(p_clave || ' no se puede calcular', 'false', pg_temp.g(p_clave, '{calculable}'));
  SELECT pg_temp.caso(p_clave || ' el mensaje', 'No se puede calcular con estas medidas', pg_temp.g(p_clave, '{mensaje}'));
  SELECT pg_temp.caso(p_clave || ' sin filas', '0', pg_temp.filas(p_clave));
  SELECT pg_temp.caso(p_clave || ' sin piezas', '0', (SELECT jsonb_array_length(j->'piezas')::text FROM res WHERE clave = p_clave));
$f$;

CREATE FUNCTION pg_temp.sale(p_clave text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso(p_clave || ' se calcula', 'true', pg_temp.g(p_clave, '{calculable}'));
  SELECT pg_temp.caso(p_clave || ' sin errores', NULL, pg_temp.err(p_clave));
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text, p_peso text DEFAULT 'NULL', p_espesor text DEFAULT 'NULL')
RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, %s, %s)',
    'Zqx161 ' || p_nombre, pg_temp.l(p_categoria), p_unidad, p_peso, p_espesor));
$f$;

CREATE FUNCTION pg_temp.categoria(p_nombre text, p_tipo text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('INSERT INTO catalogo_categorias (tipo, nombre) VALUES (%L, %L) RETURNING id',
    p_tipo, 'Zqx161 ' || p_nombre), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Lucia','Ana','Carlos','Rodrigo','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND modulo = 'catalogo';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test161.local', jsonb_build_object('nombre', 'test161 ' || nombre)
FROM ids WHERE nombre IN ('Lucia','Ana','Carlos','Rodrigo','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Ana','catalogo_insumos'), ('Ana','catalogo_costos'), ('Ana','catalogo_fijos'), ('Ana','catalogo_fijos_editar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar'),
  ('Rodrigo','catalogo_paquetes')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.categoria('Perfiles', 'insumo');
SELECT pg_temp.categoria('Vidrios', 'insumo');
SELECT pg_temp.categoria('Ventanas', 'paquete');
SELECT pg_temp.categoria('Manos', 'servicio', 'Ana');

SELECT pg_temp.crear('Blanco', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx161 Blanco') RETURNING id$q$);
SELECT pg_temp.crear('Negro', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx161 Negro') RETURNING id$q$);
SELECT pg_temp.crear('Rojo', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx161 Rojo') RETURNING id$q$);

SELECT pg_temp.crear('PerfilMarco', format($q$SELECT catalogo_insumo_alta('Zqx161 PerfilMarco', %s, 'mm', 0.9, NULL, ARRAY[%s, %s]::uuid[])$q$,
  pg_temp.l('Perfiles'), pg_temp.l('Blanco'), pg_temp.l('Negro')));
SELECT pg_temp.crear('PerfilHoja', format($q$SELECT catalogo_insumo_alta('Zqx161 PerfilHoja', %s, 'mm', 0.7, NULL, ARRAY[%s, %s]::uuid[])$q$,
  pg_temp.l('Perfiles'), pg_temp.l('Blanco'), pg_temp.l('Negro')));
SELECT pg_temp.insumo('Felpa', 'Perfiles', 'mm', '0');
SELECT pg_temp.insumo('Sellador', 'Perfiles', 'mm', '0');
SELECT pg_temp.insumo('Curvo', 'Perfiles', 'mm', '0.9');
SELECT pg_temp.insumo('Contra4', 'Perfiles', 'mm', '0.2');
SELECT pg_temp.insumo('Contra6', 'Perfiles', 'mm', '0.2');
SELECT pg_temp.insumo('Escuadra', 'Perfiles', 'u', '0.02');
SELECT pg_temp.insumo('Rueda40', 'Perfiles', 'u', '0.05');
SELECT pg_temp.insumo('Rueda80', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('Enrollable', 'Perfiles', 'u', '2');
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2', '10', '4');
SELECT pg_temp.insumo('Laminado', 'Vidrios', 'm2', '15', '6');
SELECT pg_temp.insumo('Tela', 'Vidrios', 'm2', '1');
SELECT pg_temp.insumo('DVH', 'Vidrios', 'm2');
SELECT pg_temp.crear('Soldado', format($q$SELECT catalogo_fijo_alta('Zqx161 Soldado', %s, 'u', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');
SELECT pg_temp.crear('Instalacion', format($q$SELECT catalogo_fijo_alta('Zqx161 Instalacion', %s, 'u', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');

-- ============================================================
-- 01. La ventana corrediza: 1.500 × 1.200, Hoja × 2
-- ============================================================
SELECT pg_temp.ver('V1');
SELECT pg_temp.mete(NULL, 'catalogo_versiones_colores', 'V1', jsonb_build_object('color_id', pg_temp.id('Blanco'), 'base', true));
SELECT pg_temp.mete(NULL, 'catalogo_versiones_colores', 'V1', jsonb_build_object('color_id', pg_temp.id('Negro')));
SELECT pg_temp.vr('V1', 'ancho_hoja', 1, '(ancho + solape) / 2');
SELECT pg_temp.en('V1', 'ancho', 2, 300, 3000);
SELECT pg_temp.en('V1', 'alto', 3, 300, 3000);
SELECT pg_temp.vr('V1', 'solape', 4, '50', '{"a_produccion": false}');
SELECT pg_temp.mete('V1.mano', 'catalogo_variables', 'V1',
  '{"nombre": "mano", "orden": 5, "ingresa_vendedor": true, "es_lista": true, "valores": ["Izquierda", "Derecha"], "valor_predeterminado": "Izquierda"}');
SELECT pg_temp.pz('V1', 'Marco', 1);
SELECT pg_temp.pz('V1', 'Hoja', 2, '{"cantidad": "2", "calcula_espesor": true, "espesor_a_produccion": false}');
SELECT pg_temp.pz('V1', 'Colocacion', 3);
SELECT pg_temp.un('V1', 'Marco', 1, 'PerfilMarco', '{"medida": "ancho - 2", "cantidad": "2"}');
SELECT pg_temp.un('V1', 'Marco', 2, 'PerfilMarco', '{"medida": "alto − 2", "cantidad": "2"}');
SELECT pg_temp.un('V1', 'Marco', 3, 'Escuadra', '{"cantidad": "4"}');
SELECT pg_temp.un('V1', 'Marco', 4, 'Soldado', '{"cantidad": "4"}');
SELECT pg_temp.un('V1', 'Hoja', 1, 'PerfilHoja', '{"medida": "ancho_hoja", "cantidad": "2"}');
SELECT pg_temp.un('V1', 'Hoja', 2, 'PerfilHoja', '{"medida": "alto", "cantidad": "2"}');
SELECT pg_temp.un('V1', 'Hoja', 3, 'Felpa', '{"medida": "[Zqx161 PerfilHoja]"}');
SELECT pg_temp.mu('V1', 'Hoja', 4, 'elige_vendedor', 'Vidrio', '{"ancho": "ancho_hoja − 48", "alto": "alto − 48", "cuenta_espesor": true}');
SELECT pg_temp.op('V1', 'V1.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('V1', 'V1.Hoja.Vidrio', 2, 'Laminado');
SELECT pg_temp.mu('V1', 'Hoja', 5, 'sigue', 'Contravidrio',
  jsonb_build_object('sigue_material_id', pg_temp.id('V1.Hoja.Vidrio'), 'medida', '(ancho_hoja − 48 + alto − 48) × 2'));
SELECT pg_temp.pareja('V1', 'V1.Hoja.Contravidrio', 1, 'V1.Hoja.Vidrio.Float', 'Contra4');
SELECT pg_temp.pareja('V1', 'V1.Hoja.Contravidrio', 2, 'V1.Hoja.Vidrio.Laminado', 'Contra6');
SELECT pg_temp.mu('V1', 'Hoja', 6, 'elige_sistema', 'Rueda',
  '{"eleccion": "si [peso Hoja] > 40 entonces [Zqx161 Rueda80] si no [Zqx161 Rueda40]", "cantidad": "2", "cuenta_peso": false}');
SELECT pg_temp.op('V1', 'V1.Hoja.Rueda', 1, 'Rueda40');
SELECT pg_temp.op('V1', 'V1.Hoja.Rueda', 2, 'Rueda80');
SELECT pg_temp.un('V1', 'Colocacion', 1, 'Sellador', '{"medida": "[Zqx161 PerfilHoja]"}');
SELECT pg_temp.un('V1', 'Colocacion', 2, 'Instalacion');
SELECT pg_temp.co('V1', 'variable_id', 'V1.alto', 'alto > 2200', 'Revisar el refuerzo');
SELECT pg_temp.co('V1', 'variable_id', 'V1.ancho', 'ancho > 2800', 'Hasta 2.800 de ancho', true);
SELECT pg_temp.co('V1', 'opcion_id', 'V1.Hoja.Vidrio.Float', '[Vidrio] > 2000000', 'El Float llega hasta 2 m2', true);
SELECT pg_temp.co('V1', 'opcion_id', 'V1.Hoja.Vidrio.Laminado', '[Vidrio] > 3500000', 'El Laminado llega hasta 3,5 m2', true);

SELECT pg_temp.calc('R1', 'V1', '{"variables": {"ancho": 1500, "alto": 1200}}');
SELECT pg_temp.sale('R1');
SELECT pg_temp.caso('01 sin bloqueo', 'false', pg_temp.g('R1', '{bloqueado}'));
SELECT pg_temp.caso('01 sin mensaje', NULL, pg_temp.g('R1', '{mensaje}'));
SELECT pg_temp.caso('01 sin alertas', NULL, pg_temp.men('R1'));
SELECT pg_temp.caso('01 doce filas', '12', pg_temp.filas('R1'));
SELECT pg_temp.caso('01 ancho de hoja', '775', pg_temp.var('R1', 'ancho_hoja'));
SELECT pg_temp.caso('01 cinco variables', '5', (SELECT jsonb_array_length(j->'variables')::text FROM res WHERE clave = 'R1'));
SELECT pg_temp.caso('01 la lista sale con su valor', 'Izquierda', pg_temp.var('R1', 'mano'));
SELECT pg_temp.caso('01 solape no pasa a Producción', 'false', pg_temp.var('R1', 'solape', 'a_produccion'));
SELECT pg_temp.caso('01 ancho pasa a Producción', 'true', pg_temp.var('R1', 'ancho', 'a_produccion'));
SELECT pg_temp.caso('01 marco, primer corte', '1498', pg_temp.f('R1', 'PerfilMarco', 'medida'));
SELECT pg_temp.caso('01 marco, total del primero', '2996', pg_temp.f('R1', 'PerfilMarco', 'total'));
SELECT pg_temp.caso('01 marco, segundo corte', '1198', pg_temp.f('R1', 'PerfilMarco', 'medida', 2));
SELECT pg_temp.caso('01 marco, total del segundo', '2396', pg_temp.f('R1', 'PerfilMarco', 'total', 2));
SELECT pg_temp.caso('01 escuadra sin medida', NULL, pg_temp.f('R1', 'Escuadra', 'medida'));
SELECT pg_temp.caso('01 escuadra, total en u', '4', pg_temp.f('R1', 'Escuadra', 'total'));
SELECT pg_temp.caso('01 el soldado es un servicio', 'servicio', pg_temp.f('R1', 'Soldado', 'tipo'));
SELECT pg_temp.caso('01 hoja: la cantidad multiplica la de la pieza', '4', pg_temp.f('R1', 'PerfilHoja', 'cantidad'));
SELECT pg_temp.caso('01 hoja, primer corte', '775', pg_temp.f('R1', 'PerfilHoja', 'medida'));
SELECT pg_temp.caso('01 hoja, total del primero', '3100', pg_temp.f('R1', 'PerfilHoja', 'total'));
SELECT pg_temp.caso('01 felpa, dentro de la pieza: lo de una', '3950', pg_temp.f('R1', 'Felpa', 'medida'));
SELECT pg_temp.caso('01 felpa, total', '7900', pg_temp.f('R1', 'Felpa', 'total'));
SELECT pg_temp.caso('01 sellador, desde otra pieza: lo de todo', '7900', pg_temp.f('R1', 'Sellador', 'medida'));
SELECT pg_temp.caso('01 vidrio predeterminado', 'Zqx161 Float', pg_temp.f('R1', 'Vidrio', 'insumo'));
SELECT pg_temp.caso('01 vidrio, ancho', '727', pg_temp.f('R1', 'Vidrio', 'ancho'));
SELECT pg_temp.caso('01 vidrio, alto', '1152', pg_temp.f('R1', 'Vidrio', 'alto'));
SELECT pg_temp.caso('01 vidrio, cantidad', '2', pg_temp.f('R1', 'Vidrio', 'cantidad'));
SELECT pg_temp.caso('01 vidrio, área de uno en m2', '0.838', pg_temp.f('R1', 'Vidrio', 'area'));
SELECT pg_temp.caso('01 vidrio, total en m2', '1.675', pg_temp.f('R1', 'Vidrio', 'total'));
SELECT pg_temp.caso('01 contravidrio, en combo', 'Zqx161 Contra4', pg_temp.f('R1', 'Contravidrio', 'insumo'));
SELECT pg_temp.caso('01 contravidrio, medida', '3758', pg_temp.f('R1', 'Contravidrio', 'medida'));
SELECT pg_temp.caso('01 rueda, la elige el sistema por el peso', 'Zqx161 Rueda40', pg_temp.f('R1', 'Rueda', 'insumo'));
SELECT pg_temp.caso('01 rueda, cantidad', '4', pg_temp.f('R1', 'Rueda', 'cantidad'));
SELECT pg_temp.caso('01 hoja × 2', '2', pg_temp.pie('R1', 'Hoja', 'cantidad'));
SELECT pg_temp.caso('01 peso de una hoja, sin la rueda', '11.892', pg_temp.pie('R1', 'Hoja', 'peso'));
SELECT pg_temp.caso('01 espesor de una hoja', '4', pg_temp.pie('R1', 'Hoja', 'espesor'));
SELECT pg_temp.caso('01 el espesor no pasa a Producción', 'false', pg_temp.pie('R1', 'Hoja', 'espesor_a_produccion'));
SELECT pg_temp.caso('01 peso del marco, sin el soldado', '4.933', pg_temp.pie('R1', 'Marco', 'peso'));
SELECT pg_temp.caso('01 el marco no calcula espesor', NULL, pg_temp.pie('R1', 'Marco', 'espesor'));
SELECT pg_temp.caso('01 un peso de 0 es un dato', '0', pg_temp.pie('R1', 'Colocacion', 'peso'));
SELECT pg_temp.caso('01 no trae costos', 'false', (SELECT (j::text ILIKE '%costo%')::text FROM res WHERE clave = 'R1'));

SELECT pg_temp.calc('R1l', 'V1', '{"variables": {"ancho": 1500, "alto": 1200}}'::jsonb || pg_temp.el('Hoja', 'Vidrio', 'Laminado'));
SELECT pg_temp.caso('01 elegir el laminado', 'Zqx161 Laminado', pg_temp.f('R1l', 'Vidrio', 'insumo'));
SELECT pg_temp.caso('01 su pareja', 'Zqx161 Contra6', pg_temp.f('R1l', 'Contravidrio', 'insumo'));
SELECT pg_temp.caso('01 su espesor', '6', pg_temp.pie('R1l', 'Hoja', 'espesor'));
SELECT pg_temp.caso('01 su peso', '16.079', pg_temp.pie('R1l', 'Hoja', 'peso'));
SELECT pg_temp.calc('R1g', 'V1', '{"variables": {"ancho": 3000, "alto": 3000}}'::jsonb || pg_temp.el('Hoja', 'Vidrio', 'Laminado'));
SELECT pg_temp.caso('01 con más peso, otra rueda', 'Zqx161 Rueda80', pg_temp.f('R1g', 'Rueda', 'insumo'));
SELECT pg_temp.calc('R1c', 'V1', '{"variables": {"ancho": 1500, "alto": 1200, "ancho_hoja": 9999, "solape": 1}}');
SELECT pg_temp.caso('01 lo calculado no se pisa desde la entrada', '775', pg_temp.var('R1c', 'ancho_hoja'));

-- ============================================================
-- 02. Orden libre entre fórmulas
-- ============================================================
SELECT pg_temp.ver('VO');
SELECT pg_temp.vr('VO', 'a', 1, 'b + 1');
SELECT pg_temp.vr('VO', 'b', 2, 'c × 2');
SELECT pg_temp.vr('VO', 'c', 3, '[Zqx161 Felpa] / 1000');
SELECT pg_temp.vr('VO', 'd', 4, '5000');
SELECT pg_temp.vr('VO', 'e', 5, '3');
SELECT pg_temp.pz('VO', 'P', 1, '{"cantidad": "e"}');
SELECT pg_temp.un('VO', 'P', 1, 'Sellador', '{"medida": "[Zqx161 Felpa]"}');
SELECT pg_temp.un('VO', 'P', 2, 'Felpa', '{"medida": "d"}');
SELECT pg_temp.calc('RO', 'VO');
SELECT pg_temp.sale('RO');
SELECT pg_temp.caso('02 una variable antes de la que usa', '31', pg_temp.var('RO', 'a'));
SELECT pg_temp.caso('02 un material antes del que usa', '5000', pg_temp.f('RO', 'Sellador', 'medida'));
SELECT pg_temp.caso('02 la cantidad de la pieza sale de una variable', '15000', pg_temp.f('RO', 'Sellador', 'total'));

-- ============================================================
-- 03. Lo circular no rompe: dice qué pasa
-- ============================================================
SELECT pg_temp.ver('VC1');
SELECT pg_temp.vr('VC1', 'a', 1, 'b');
SELECT pg_temp.vr('VC1', 'b', 2, 'a');
SELECT pg_temp.calc('RC1', 'VC1');
SELECT pg_temp.no_sale('RC1');
SELECT pg_temp.caso('03 dos variables', 'Referencia circular entre a, b', pg_temp.err('RC1'));

SELECT pg_temp.ver('VC2');
SELECT pg_temp.pz('VC2', 'P', 1);
SELECT pg_temp.un('VC2', 'P', 1, 'Felpa', '{"medida": "[Zqx161 Felpa] + 1"}');
SELECT pg_temp.calc('RC2', 'VC2');
SELECT pg_temp.no_sale('RC2');
SELECT pg_temp.caso('03 un material que se usa a sí mismo', 'Referencia circular entre Zqx161 Felpa', pg_temp.err('RC2'));

SELECT pg_temp.ver('VC3');
SELECT pg_temp.pz('VC3', 'Hoja', 1);
SELECT pg_temp.mu('VC3', 'Hoja', 1, 'elige_sistema', 'Rueda', '{"eleccion": "si [peso Hoja] > 40 entonces [Zqx161 Rueda80] si no [Zqx161 Rueda40]"}');
SELECT pg_temp.op('VC3', 'VC3.Hoja.Rueda', 1, 'Rueda40');
SELECT pg_temp.op('VC3', 'VC3.Hoja.Rueda', 2, 'Rueda80');
SELECT pg_temp.calc('RC3', 'VC3');
SELECT pg_temp.no_sale('RC3');
SELECT pg_temp.tiene('RC3', 'Referencia circular entre');
SELECT pg_temp.tiene('RC3', 'peso Hoja');
SELECT pg_temp.tiene('RC3', 'Rueda');

SELECT pg_temp.ver('VC4');
SELECT pg_temp.pz('VC4', 'P', 1, '{"cantidad": "[Zqx161 Felpa]"}');
SELECT pg_temp.un('VC4', 'P', 1, 'Felpa', '{"medida": "1"}');
SELECT pg_temp.calc('RC4', 'VC4');
SELECT pg_temp.no_sale('RC4');
SELECT pg_temp.tiene('RC4', 'Referencia circular entre');
SELECT pg_temp.tiene('RC4', 'cantidad de P');
SELECT pg_temp.caso('03 el peso que nadie usa no se nombra', 'false', (position('peso P' IN pg_temp.err('RC4')) > 0)::text);

-- La rama que no se toma no se calcula: acá no frena, y al enviar la frena la revisión de lo circular (sql/162).
SELECT pg_temp.ver('VC5');
SELECT pg_temp.vr('VC5', 'x', 1, '1');
SELECT pg_temp.vr('VC5', 'a', 2, 'si x > 0 entonces 1 si no b');
SELECT pg_temp.vr('VC5', 'b', 3, 'a');
SELECT pg_temp.calc('RC5', 'VC5');
SELECT pg_temp.sale('RC5');
SELECT pg_temp.caso('03 la rama que no se toma', '1', pg_temp.var('RC5', 'b'));

SELECT pg_temp.ver('VC6');
SELECT pg_temp.pz('VC6', 'A', 1, '{"opcional": true}');
SELECT pg_temp.pz('VC6', 'B', 2, jsonb_build_object('opcional', true, 'requiere_pieza_id', pg_temp.id('VC6.A')));
SELECT pg_temp.caso('03 cerrar el círculo de requisitos', 'ok', pg_temp.consultar(format(
  $q$WITH u AS (UPDATE catalogo_piezas SET requiere_pieza_id = %s WHERE id = %s RETURNING 1) SELECT 'ok' FROM u$q$,
  pg_temp.l('VC6.B'), pg_temp.l('VC6.A')), 'Lucia'));
SELECT pg_temp.un('VC6', 'A', 1, 'Escuadra');
SELECT pg_temp.un('VC6', 'B', 1, 'Rueda40');
SELECT pg_temp.calc('RC6a', 'VC6');
SELECT pg_temp.caso('03 requisito circular, sin elegir', '0', pg_temp.filas('RC6a'));
SELECT pg_temp.calc('RC6b', 'VC6', '{"piezas": {"A": true}}');
SELECT pg_temp.caso('03 requisito circular, elegida una trae la otra', '2', pg_temp.filas('RC6b'));
SELECT pg_temp.calc('RC6c', 'VC6', '{"piezas": {"A": true, "B": false}}');
SELECT pg_temp.caso('03 requisito circular, destildar saca las dos', '0', pg_temp.filas('RC6c'));

-- ============================================================
-- 04. Un borrador a medias: "no se puede calcular", no un error de la base
-- ============================================================
SELECT pg_temp.ver('VM');
SELECT pg_temp.en('VM', 'ancho', 1, NULL, NULL);
SELECT pg_temp.mete('VM.mano', 'catalogo_variables', 'VM',
  '{"nombre": "mano", "orden": 2, "ingresa_vendedor": true, "es_lista": true, "valores": ["Izquierda", "Derecha"]}');
SELECT pg_temp.vr('VM', 'z', 3, 'arcoseno(ancho)');
SELECT pg_temp.vr('VM', 'w', 4, '1 / (ancho − ancho)');
SELECT pg_temp.pz('VM', 'P', 1);
SELECT pg_temp.mete('VM.sin', 'catalogo_materiales', 'VM', jsonb_build_object('pieza_id', pg_temp.id('VM.P'), 'orden', 1));
SELECT pg_temp.mu('VM', 'P', 2, 'elige_vendedor', 'Manija');
SELECT pg_temp.mu('VM', 'P', 3, 'elige_sistema', 'Regla');
SELECT pg_temp.mu('VM', 'P', 4, 'sigue', 'Sombra');
SELECT pg_temp.un('VM', 'P', 5, 'Felpa');
SELECT pg_temp.un('VM', 'P', 6, 'Float', '{"ancho": "100"}');
SELECT pg_temp.un('VM', 'P', 7, 'Sellador', '{"medida": "nada + 1"}');
SELECT pg_temp.un('VM', 'P', 8, 'Contra4', '{"medida": "mano + 1"}');

SELECT pg_temp.calc('RM', 'VM', '{"variables": {"ancho": 1200, "mano": "Izquierda"}}');
SELECT pg_temp.no_sale('RM');
SELECT pg_temp.tiene('RM', 'Un material de P: falta el insumo');
SELECT pg_temp.tiene('RM', 'Manija: falta elegir una opción');
SELECT pg_temp.tiene('RM', 'Regla: falta la regla que elige');
SELECT pg_temp.tiene('RM', 'Sombra: no tiene a quién seguir');
SELECT pg_temp.tiene('RM', 'Zqx161 Felpa: falta la medida');
SELECT pg_temp.tiene('RM', 'Zqx161 Float: falta el ancho o el alto');
SELECT pg_temp.tiene('RM', 'Zqx161 Sellador: usa nada, que no existe o no se pudo calcular');
SELECT pg_temp.tiene('RM', 'Zqx161 Contra4: usa mano, que no existe o no se pudo calcular');
SELECT pg_temp.tiene('RM', 'z: una cuenta da fuera de rango');
SELECT pg_temp.tiene('RM', 'w: una cuenta divide por cero');
SELECT pg_temp.caso('04 las variables que salieron quedan', '1200', pg_temp.var('RM', 'ancho'));

SELECT pg_temp.calc('RMa', 'VM', '{}');
SELECT pg_temp.tiene('RMa', 'ancho: falta el valor');
SELECT pg_temp.tiene('RMa', 'mano: falta elegir un valor');
SELECT pg_temp.calc('RMb', 'VM', '{"variables": {"ancho": "abc", "mano": "Arriba"}}');
SELECT pg_temp.tiene('RMb', 'ancho: no es un número');
SELECT pg_temp.tiene('RMb', 'mano: el valor Arriba no está en la lista');
SELECT pg_temp.calc('RMc', 'VM', '{"variables": {"mano": 5}}');
SELECT pg_temp.tiene('RMc', 'mano: el valor 5 no está en la lista');

SELECT pg_temp.ver('VV');
SELECT pg_temp.calc('RV', 'VV');
SELECT pg_temp.sale('RV');
SELECT pg_temp.caso('04 vacío, sin filas: lo frena el envío', '0', pg_temp.filas('RV'));

-- ============================================================
-- 05. Medidas y cantidades
-- ============================================================
SELECT pg_temp.ver('VK');
SELECT pg_temp.en('VK', 'ancho', 1, 300, 3000);
SELECT pg_temp.en('VK', 'alto', 2, 300, 3000);
SELECT pg_temp.pz('VK', 'P', 1);
SELECT pg_temp.un('VK', 'P', 1, 'Float', '{"ancho": "ancho − 48", "alto": "alto − 48"}');
SELECT pg_temp.un('VK', 'P', 2, 'PerfilHoja', '{"medida": "ancho − 100"}');
SELECT pg_temp.un('VK', 'P', 3, 'Escuadra', '{"cantidad": "si ancho = 999 entonces -1 si no si ancho = 998 entonces 0 si no 1"}');
SELECT pg_temp.un('VK', 'P', 4, 'Rueda40', '{"cantidad": "0,5"}');
SELECT pg_temp.un('VK', 'P', 5, 'Rueda80', '{"cantidad": "redondear_arriba(alto / 700)"}');
SELECT pg_temp.un('VK', 'P', 6, 'Felpa', '{"medida": "2000 / 3"}');

SELECT pg_temp.calc('RK', 'VK', '{"variables": {"ancho": 1200, "alto": 1200}}');
SELECT pg_temp.sale('RK');
SELECT pg_temp.caso('05 el medio pomo se puede cobrar', '0.5', pg_temp.f('RK', 'Rueda40', 'total'));
SELECT pg_temp.caso('05 redondear_arriba', '2', pg_temp.f('RK', 'Rueda80', 'total'));
SELECT pg_temp.caso('05 la cuenta no se redondea', '666.667', pg_temp.f('RK', 'Felpa', 'total'));

SELECT pg_temp.calc('RKa', 'VK', '{"variables": {"ancho": 1200, "alto": 30}}');
SELECT pg_temp.no_sale('RKa');
SELECT pg_temp.caso('05 el alto de 30', 'Zqx161 Float: el alto dio −18 mm', pg_temp.err('RKa'));
SELECT pg_temp.caso('05 el rango igual se dice', 'Alto va de 300 a 3.000 mm', pg_temp.men('RKa'));
SELECT pg_temp.caso('05 el rango bloquea', 'true', pg_temp.g('RKa', '{bloqueado}'));

SELECT pg_temp.calc('RKb', 'VK', '{"variables": {"ancho": 100, "alto": 1200}}');
SELECT pg_temp.no_sale('RKb');
SELECT pg_temp.tiene('RKb', 'Zqx161 PerfilHoja: la medida dio 0 mm');
SELECT pg_temp.calc('RKc', 'VK', '{"variables": {"ancho": 999, "alto": 1200}}');
SELECT pg_temp.no_sale('RKc');
SELECT pg_temp.caso('05 cantidad negativa', 'Zqx161 Escuadra: la cantidad dio −1', pg_temp.err('RKc'));
SELECT pg_temp.calc('RKd', 'VK', '{"variables": {"ancho": 998, "alto": 1200}}');
SELECT pg_temp.sale('RKd');
SELECT pg_temp.caso('05 cantidad 0: no lleva', NULL, pg_temp.f('RKd', 'Escuadra', 'total'));

SELECT pg_temp.ver('VQ');
SELECT pg_temp.en('VQ', 'ancho', 1, 300, 3000);
SELECT pg_temp.en('VQ', 'alto', 2, 300, 3000);
SELECT pg_temp.pz('VQ', 'P', 1);
SELECT pg_temp.un('VQ', 'P', 1, 'Float', '{"cantidad": "si alto > 2100 entonces 1 si no 0", "ancho": "ancho", "alto": "alto − 2100"}');
SELECT pg_temp.un('VQ', 'P', 2, 'Contra4', '{"cantidad": "si alto > 2100 entonces 1 si no 0", "medida": "[Zqx161 Float]"}');
SELECT pg_temp.un('VQ', 'P', 3, 'Felpa', '{"medida": "1000 + [Zqx161 Float]"}');
SELECT pg_temp.co('VQ', 'material_id', 'VQ.P.Float.1', 'alto > 0', 'El vidrio superior bloquea', true);
SELECT pg_temp.calc('RQa', 'VQ', '{"variables": {"ancho": 1000, "alto": 2000}}');
SELECT pg_temp.sale('RQa');
SELECT pg_temp.caso('05 vidrio superior: sin fila', NULL, pg_temp.f('RQa', 'Float', 'total'));
SELECT pg_temp.caso('05 contravidrio superior: sin fila', NULL, pg_temp.f('RQa', 'Contra4', 'total'));
SELECT pg_temp.caso('05 quien lo usa recibe 0', '1000', pg_temp.f('RQa', 'Felpa', 'medida'));
SELECT pg_temp.caso('05 su condición no se evalúa', 'false', pg_temp.g('RQa', '{bloqueado}'));
SELECT pg_temp.calc('RQb', 'VQ', '{"variables": {"ancho": 1000, "alto": 2500}}');
SELECT pg_temp.sale('RQb');
SELECT pg_temp.caso('05 con cantidad, su alto', '400', pg_temp.f('RQb', 'Float', 'alto'));
SELECT pg_temp.caso('05 con cantidad, la referencia da mm²', '400000', pg_temp.f('RQb', 'Contra4', 'medida'));
SELECT pg_temp.caso('05 con cantidad, su condición', 'El vidrio superior bloquea', pg_temp.men('RQb'));
SELECT pg_temp.caso('05 con un bloqueo el despiece sale igual', '3', pg_temp.filas('RQb'));

SELECT pg_temp.ver('VQ2');
SELECT pg_temp.pz('VQ2', 'P', 1);
SELECT pg_temp.un('VQ2', 'P', 1, 'Float', '{"cantidad": "0", "ancho": "100", "alto": "100"}');
SELECT pg_temp.un('VQ2', 'P', 2, 'Sellador', '{"medida": "[Zqx161 Float]"}');
SELECT pg_temp.calc('RQ2', 'VQ2');
SELECT pg_temp.caso('05 si el 0 deja otra medida en 0, no se puede', 'Zqx161 Sellador: la medida dio 0 mm', pg_temp.err('RQ2'));

-- Una pieza con cantidad 0 y lo que tiene adentro.
SELECT pg_temp.ver('VZ');
SELECT pg_temp.en('VZ', 'ancho', 1, 300, 3000);
SELECT pg_temp.en('VZ', 'alto', 2, 300, 3000);
SELECT pg_temp.vr('VZ', 'y', 3, 'h + 1');
SELECT pg_temp.pz('VZ', 'Sup', 1, '{"cantidad": "si alto > 2100 entonces 1 si no 0"}');
SELECT pg_temp.vr('VZ', 'h', 1, 'alto − 2100', pg_temp.en_pieza('VZ', 'Sup'));
SELECT pg_temp.vr('VZ', 'k', 2, '1 / (alto − 2000)', pg_temp.en_pieza('VZ', 'Sup'));
SELECT pg_temp.en('VZ', 'x', 3, NULL, NULL, pg_temp.en_pieza('VZ', 'Sup'));
SELECT pg_temp.un('VZ', 'Sup', 1, 'Float', '{"ancho": "ancho", "alto": "h"}');
SELECT pg_temp.co('VZ', 'variable_id', 'VZ.h', 'h < 100', 'Muy bajo', true);
SELECT pg_temp.pz('VZ', 'Base', 2);
SELECT pg_temp.un('VZ', 'Base', 1, 'Felpa', '{"medida": "1000 + [Zqx161 Float]"}');
SELECT pg_temp.un('VZ', 'Base', 2, 'Sellador', '{"medida": "[peso Sup] + 1"}');

SELECT pg_temp.calc('RZa', 'VZ', '{"variables": {"ancho": 1000, "alto": 2000}}');
SELECT pg_temp.sale('RZa');
SELECT pg_temp.caso('05 la pieza en 0 no sale', NULL, pg_temp.pie('RZa', 'Sup', 'cantidad'));
SELECT pg_temp.caso('05 su material no tiene fila', NULL, pg_temp.f('RZa', 'Float', 'total'));
SELECT pg_temp.caso('05 su variable no sale', NULL, pg_temp.var('RZa', 'h'));
SELECT pg_temp.caso('05 su condición no se evalúa', 'false', pg_temp.g('RZa', '{bloqueado}'));
SELECT pg_temp.caso('05 su variable vale su cuenta para quien la usa', '-99', pg_temp.var('RZa', 'y'));
SELECT pg_temp.caso('05 su material vale 0 para quien lo usa', '1000', pg_temp.f('RZa', 'Felpa', 'medida'));
SELECT pg_temp.caso('05 su peso vale 0', '1', pg_temp.f('RZa', 'Sellador', 'medida'));
SELECT pg_temp.calc('RZb', 'VZ', '{"variables": {"ancho": 1000, "alto": 2500}}');
SELECT pg_temp.caso('05 con cantidad, su variable obligatoria se pide', 'x: falta el valor', pg_temp.err('RZb'));
SELECT pg_temp.calc('RZc', 'VZ', '{"variables": {"ancho": 1000, "alto": 2500, "x": 5}}');
SELECT pg_temp.sale('RZc');
SELECT pg_temp.caso('05 con cantidad, su material', '401000', pg_temp.f('RZc', 'Felpa', 'medida'));
SELECT pg_temp.caso('05 con cantidad, su peso', '5', pg_temp.f('RZc', 'Sellador', 'medida'));
SELECT pg_temp.caso('05 con cantidad, su variable sale', '400', pg_temp.var('RZc', 'h'));

-- La variable que define la cantidad de su propia pieza.
SELECT pg_temp.ver('VT');
SELECT pg_temp.pz('VT', 'Trav', 1, '{"cantidad": "trav"}');
SELECT pg_temp.en('VT', 'trav', 1, 0, 3, pg_temp.en_pieza('VT', 'Trav') || '{"es_cantidad": true}');
SELECT pg_temp.un('VT', 'Trav', 1, 'Escuadra', '{"cantidad": "2"}');
SELECT pg_temp.calc('RTa', 'VT', '{"variables": {"trav": 0}}');
SELECT pg_temp.sale('RTa');
SELECT pg_temp.caso('05 cero travesaños', '0', pg_temp.filas('RTa'));
SELECT pg_temp.calc('RTb', 'VT', '{"variables": {"trav": 2}}');
SELECT pg_temp.sale('RTb');
SELECT pg_temp.caso('05 dos travesaños', '4', pg_temp.f('RTb', 'Escuadra', 'cantidad'));
SELECT pg_temp.calc('RTc', 'VT', '{"variables": {"trav": 5}}');
SELECT pg_temp.sale('RTc');
SELECT pg_temp.caso('05 una cantidad se lee sin mm', 'Trav va de 0 a 3', pg_temp.men('RTc'));
SELECT pg_temp.calc('RTd', 'VT', '{"variables": {"trav": -1}}');
SELECT pg_temp.no_sale('RTd');
SELECT pg_temp.caso('05 la cantidad de una pieza negativa', 'cantidad de Trav: dio −1', pg_temp.err('RTd'));

-- ============================================================
-- 06. Predeterminados, opciones y herencia
-- ============================================================
SELECT pg_temp.ver('VD');
SELECT pg_temp.en('VD', 'ancho', 1, 300, 3000);
SELECT pg_temp.en('VD', 'hoja1', 2, 300, 1000, '{"formula": "(ancho + 50) / 2"}');
SELECT pg_temp.pz('VD', 'P', 1);
SELECT pg_temp.un('VD', 'P', 1, 'Felpa', '{"medida": "hoja1"}');
SELECT pg_temp.calc('RDa', 'VD', '{"variables": {"ancho": 1000}}');
SELECT pg_temp.caso('06 sin tocar, el predeterminado', '525', pg_temp.f('RDa', 'Felpa', 'medida'));
SELECT pg_temp.calc('RDb', 'VD', '{"variables": {"ancho": 1000, "hoja1": 600}}');
SELECT pg_temp.caso('06 lo escrito queda', '600', pg_temp.f('RDb', 'Felpa', 'medida'));
SELECT pg_temp.calc('RDc', 'VD', '{"variables": {"ancho": 3000}}');
SELECT pg_temp.caso('06 el rango vale también si sale del predeterminado', 'Hoja1 va de 300 a 1.000 mm', pg_temp.men('RDc'));

SELECT pg_temp.ver('VE');
SELECT pg_temp.pz('VE', 'P', 1);
SELECT pg_temp.mu('VE', 'P', 1, 'elige_vendedor', 'Mosq', '{"sin_eleccion": true, "ancho": "1500", "alto": "1200", "cantidad": "2"}');
SELECT pg_temp.op('VE', 'VE.P.Mosq', 1, 'Tela');
SELECT pg_temp.op('VE', 'VE.P.Mosq', 2, 'Enrollable');
SELECT pg_temp.op('VE', 'VE.P.Mosq', 3, 'Laminado', '{"ancho": "100", "cantidad": "1"}');
SELECT pg_temp.op('VE', 'VE.P.Mosq', 4, 'PerfilHoja');
SELECT pg_temp.un('VE', 'P', 2, 'Felpa', '{"medida": "[Mosq] + 1"}');

SELECT pg_temp.calc('REa', 'VE');
SELECT pg_temp.sale('REa');
SELECT pg_temp.caso('06 sin elegir, si lo permite: sin fila', NULL, pg_temp.f('REa', 'Mosq', 'total'));
SELECT pg_temp.caso('06 sin elección vale 0', '1', pg_temp.f('REa', 'Felpa', 'medida'));
SELECT pg_temp.calc('REb', 'VE', '{"elecciones": {"P": {"Mosq": null}}}');
SELECT pg_temp.sale('REb');
SELECT pg_temp.caso('06 null es sin elección', NULL, pg_temp.f('REb', 'Mosq', 'total'));
SELECT pg_temp.calc('REc', 'VE', pg_temp.el('P', 'Mosq', 'Tela'));
SELECT pg_temp.caso('06 la tela hereda el ancho', '1500', pg_temp.f('REc', 'Mosq', 'ancho'));
SELECT pg_temp.caso('06 y la cantidad', '3.6', pg_temp.f('REc', 'Mosq', 'total'));
SELECT pg_temp.caso('06 vale lo de la opción elegida, en mm²', '3600001', pg_temp.f('REc', 'Felpa', 'medida'));
SELECT pg_temp.calc('REd', 'VE', pg_temp.el('P', 'Mosq', 'Enrollable'));
SELECT pg_temp.sale('REd');
SELECT pg_temp.caso('06 el enrollable no hereda el ancho', NULL, pg_temp.f('REd', 'Mosq', 'ancho'));
SELECT pg_temp.caso('06 y se cobra por unidad', '2', pg_temp.f('REd', 'Mosq', 'total'));
SELECT pg_temp.caso('06 en u vale la cantidad', '3', pg_temp.f('REd', 'Felpa', 'medida'));
SELECT pg_temp.calc('REe', 'VE', pg_temp.el('P', 'Mosq', 'Laminado'));
SELECT pg_temp.caso('06 su propio ancho', '100', pg_temp.f('REe', 'Mosq', 'ancho'));
SELECT pg_temp.caso('06 hereda el alto', '1200', pg_temp.f('REe', 'Mosq', 'alto'));
SELECT pg_temp.caso('06 su propia cantidad', '0.12', pg_temp.f('REe', 'Mosq', 'total'));
SELECT pg_temp.calc('REf', 'VE', pg_temp.el('P', 'Mosq', 'PerfilHoja'));
SELECT pg_temp.caso('06 otra unidad sin su medida', 'Mosq: falta la medida', pg_temp.err('REf'));
SELECT pg_temp.calc('REg', 'VE', pg_temp.el('P', 'Mosq', 'Float'));
SELECT pg_temp.caso('06 una opción que no está', 'Mosq: esa opción ya no existe', pg_temp.err('REg'));
SELECT pg_temp.calc('REh', 'VE', '{"elecciones": {"P": {"Otra": null}}}');
SELECT pg_temp.caso('06 un material que no está', 'Otra: esa elección ya no existe', pg_temp.err('REh'));

SELECT pg_temp.ver('VF');
SELECT pg_temp.pz('VF', 'P', 1);
SELECT pg_temp.mu('VF', 'P', 1, 'elige_vendedor', 'Vidrio', '{"ancho": "100", "alto": "100"}');
SELECT pg_temp.op('VF', 'VF.P.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('VF', 'VF.P.Vidrio', 2, 'Laminado');
SELECT pg_temp.mu('VF', 'P', 2, 'elige_vendedor', 'Manija');
SELECT pg_temp.op('VF', 'VF.P.Manija', 1, 'Rueda40');
SELECT pg_temp.calc('RFa', 'VF');
SELECT pg_temp.caso('06 sin predeterminada es obligatoria', 'Manija: falta elegir una opción', pg_temp.err('RFa'));
SELECT pg_temp.calc('RFb', 'VF', pg_temp.el('P', 'Manija', 'Rueda40'));
SELECT pg_temp.sale('RFb');
SELECT pg_temp.caso('06 el predeterminado', 'Zqx161 Float', pg_temp.f('RFb', 'Vidrio', 'insumo'));
SELECT pg_temp.calc('RFc', 'VF', jsonb_build_object('elecciones', jsonb_build_object('P',
  jsonb_build_object('Manija', pg_temp.id('Rueda40'), 'Vidrio', NULL::uuid))));
SELECT pg_temp.caso('06 null donde no se permite', 'Vidrio: falta elegir una opción', pg_temp.err('RFc'));

SELECT pg_temp.ver('VS');
SELECT pg_temp.pz('VS', 'H1', 1);
SELECT pg_temp.pz('VS', 'H2', 2);
SELECT pg_temp.mu('VS', 'H1', 1, 'elige_vendedor', 'Vidrio', '{"ancho": "100", "alto": "100"}');
SELECT pg_temp.op('VS', 'VS.H1.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('VS', 'VS.H1.Vidrio', 2, 'Laminado');
SELECT pg_temp.op('VS', 'VS.H1.Vidrio', 3, 'DVH');
SELECT pg_temp.mu('VS', 'H1', 2, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('VS.H1.Vidrio'), 'medida', '400'));
SELECT pg_temp.pareja('VS', 'VS.H1.Contra', 1, 'VS.H1.Vidrio.Float', 'Contra4');
SELECT pg_temp.mete('VS.ninguna', 'catalogo_opciones', 'VS', jsonb_build_object('material_id', pg_temp.id('VS.H1.Contra'), 'orden', 3,
  'sigue_opcion_id', pg_temp.id('VS.H1.Vidrio.DVH')));
SELECT pg_temp.mu('VS', 'H2', 1, 'sigue', 'Vidrio', jsonb_build_object('sigue_material_id', pg_temp.id('VS.H1.Vidrio'), 'ancho', '200', 'alto', '200'));
SELECT pg_temp.pareja('VS', 'VS.H2.Vidrio', 1, 'VS.H1.Vidrio.Float', 'Float');
SELECT pg_temp.pareja('VS', 'VS.H2.Vidrio', 2, 'VS.H1.Vidrio.Laminado', 'Laminado');
SELECT pg_temp.pareja('VS', 'VS.H2.Vidrio', 3, 'VS.H1.Vidrio.DVH', 'DVH');
SELECT pg_temp.calc('RSa', 'VS');
SELECT pg_temp.sale('RSa');
SELECT pg_temp.caso('06 en combo', 'Zqx161 Contra4', pg_temp.f('RSa', 'Contra', 'insumo'));
SELECT pg_temp.caso('06 sincronizado, en otra pieza', 'Zqx161 Float', pg_temp.f('RSa', 'Vidrio', 'insumo', 2));
SELECT pg_temp.caso('06 sincronizado, con su medida', '200', pg_temp.f('RSa', 'Vidrio', 'ancho', 2));
SELECT pg_temp.calc('RSb', 'VS', pg_temp.el('H1', 'Vidrio', 'Laminado'));
SELECT pg_temp.caso('06 sin pareja', 'Contra: falta la pareja de la opción elegida', pg_temp.err('RSb'));
SELECT pg_temp.calc('RSc', 'VS', pg_temp.el('H1', 'Vidrio', 'DVH'));
SELECT pg_temp.sale('RSc');
SELECT pg_temp.caso('06 pareja "ninguna": sin fila', NULL, pg_temp.f('RSc', 'Contra', 'total'));
SELECT pg_temp.caso('06 el sincronizado sigue', 'Zqx161 DVH', pg_temp.f('RSc', 'Vidrio', 'insumo', 2));

SELECT pg_temp.ver('VS2');
SELECT pg_temp.pz('VS2', 'P', 1);
SELECT pg_temp.mu('VS2', 'P', 1, 'elige_vendedor', 'A');
SELECT pg_temp.op('VS2', 'VS2.P.A', 1, 'Rueda40', '{"predeterminada": true}');
SELECT pg_temp.mu('VS2', 'P', 2, 'sigue', 'B', jsonb_build_object('sigue_material_id', pg_temp.id('VS2.P.A')));
SELECT pg_temp.pareja('VS2', 'VS2.P.B', 1, 'VS2.P.A.Rueda40', 'Rueda80');
SELECT pg_temp.mu('VS2', 'P', 3, 'sigue', 'C', jsonb_build_object('sigue_material_id', pg_temp.id('VS2.P.B')));
SELECT pg_temp.calc('RS2', 'VS2');
SELECT pg_temp.caso('06 seguir a uno que sigue', 'C: sigue a un material que no elige', pg_temp.err('RS2'));

SELECT pg_temp.ver('VR');
SELECT pg_temp.en('VR', 'ancho', 1, NULL, NULL);
SELECT pg_temp.pz('VR', 'P', 1);
SELECT pg_temp.mu('VR', 'P', 2, 'elige_sistema', 'Rueda',
  '{"eleccion": "si ancho > 1000 entonces [Zqx161 Rueda80] si no si ancho > 500 entonces [Zqx161 Rueda40] si no ninguno"}');
SELECT pg_temp.op('VR', 'VR.P.Rueda', 1, 'Rueda40');
SELECT pg_temp.op('VR', 'VR.P.Rueda', 2, 'Rueda80');
SELECT pg_temp.mu('VR', 'P', 1, 'sigue', 'Eje', jsonb_build_object('sigue_material_id', pg_temp.id('VR.P.Rueda'), 'medida', '100'));
SELECT pg_temp.pareja('VR', 'VR.P.Eje', 1, 'VR.P.Rueda.Rueda40', 'Contra4');
SELECT pg_temp.pareja('VR', 'VR.P.Eje', 2, 'VR.P.Rueda.Rueda80', 'Contra6');
SELECT pg_temp.calc('RRa', 'VR', '{"variables": {"ancho": 1200}}');
SELECT pg_temp.sale('RRa');
SELECT pg_temp.caso('06 el sistema elige', 'Zqx161 Rueda80', pg_temp.f('RRa', 'Rueda', 'insumo'));
SELECT pg_temp.caso('06 quien lo sigue, aunque esté antes', 'Zqx161 Contra6', pg_temp.f('RRa', 'Eje', 'insumo'));
SELECT pg_temp.calc('RRb', 'VR', '{"variables": {"ancho": 800}}');
SELECT pg_temp.caso('06 otra rama', 'Zqx161 Rueda40', pg_temp.f('RRb', 'Rueda', 'insumo'));
SELECT pg_temp.calc('RRc', 'VR', '{"variables": {"ancho": 100}}');
SELECT pg_temp.sale('RRc');
SELECT pg_temp.caso('06 ninguno: sin filas, ni el que lo sigue', '0', pg_temp.filas('RRc'));

SELECT pg_temp.ver('VR2');
SELECT pg_temp.pz('VR2', 'P', 1);
SELECT pg_temp.mu('VR2', 'P', 1, 'elige_sistema', 'Rueda', '{"eleccion": "si 1 > 0 entonces [Zqx161 Felpa] si no ninguno"}');
SELECT pg_temp.op('VR2', 'VR2.P.Rueda', 1, 'Rueda40');
SELECT pg_temp.calc('RR2', 'VR2');
SELECT pg_temp.caso('06 la regla nombra algo que no es opción', 'Rueda: la regla eligió Zqx161 Felpa, que no es una de sus opciones', pg_temp.err('RR2'));

SELECT pg_temp.ver('VX');
SELECT pg_temp.pz('VX', 'Fija', 1);
SELECT pg_temp.pz('VX', 'Opc', 2, '{"opcional": true}');
SELECT pg_temp.mu('VX', 'Opc', 1, 'elige_sistema', 'Regla', '{"eleccion": "si 1 > 0 entonces [Zqx161 Rueda40] si no ninguno"}');
SELECT pg_temp.op('VX', 'VX.Opc.Regla', 1, 'Rueda40');
SELECT pg_temp.mu('VX', 'Fija', 1, 'sigue', 'Sombra', jsonb_build_object('sigue_material_id', pg_temp.id('VX.Opc.Regla')));
SELECT pg_temp.pareja('VX', 'VX.Fija.Sombra', 1, 'VX.Opc.Regla.Rueda40', 'Rueda80');
SELECT pg_temp.calc('RXa', 'VX');
SELECT pg_temp.sale('RXa');
SELECT pg_temp.caso('06 seguir a uno de una pieza que no está: no espera', '0', pg_temp.filas('RXa'));
SELECT pg_temp.calc('RXb', 'VX', '{"piezas": {"Opc": true}}');
SELECT pg_temp.sale('RXb');
SELECT pg_temp.caso('06 con la pieza, los dos', '2', pg_temp.filas('RXb'));

-- ============================================================
-- 07. Piezas opcionales
-- ============================================================
SELECT pg_temp.ver('VP');
SELECT pg_temp.pz('VP', 'Fija', 1);
SELECT pg_temp.pz('VP', 'Mosq', 2, '{"opcional": true}');
SELECT pg_temp.pz('VP', 'Burlete', 3, '{"opcional": true, "incluida": true}');
SELECT pg_temp.pz('VP', 'Cajon', 4, '{"opcional": true}');
SELECT pg_temp.pz('VP', 'Cortina', 5, jsonb_build_object('opcional', true, 'requiere_pieza_id', pg_temp.id('VP.Cajon')));
SELECT pg_temp.en('VP', 'mos_h', 1, NULL, NULL, pg_temp.en_pieza('VP', 'Mosq'));
SELECT pg_temp.un('VP', 'Fija', 1, 'Escuadra');
SELECT pg_temp.un('VP', 'Mosq', 1, 'Felpa', '{"medida": "mos_h"}');
SELECT pg_temp.un('VP', 'Burlete', 1, 'Sellador', '{"medida": "100"}');
SELECT pg_temp.un('VP', 'Cajon', 1, 'Rueda40');
SELECT pg_temp.un('VP', 'Cortina', 1, 'Rueda80');

SELECT pg_temp.calc('RPa', 'VP');
SELECT pg_temp.sale('RPa');
SELECT pg_temp.caso('07 la fija y la incluida', '2', pg_temp.filas('RPa'));
SELECT pg_temp.caso('07 lo de una pieza que no está no se pide', NULL, pg_temp.var('RPa', 'mos_h'));
SELECT pg_temp.calc('RPb', 'VP', '{"piezas": {"Mosq": true}}');
SELECT pg_temp.caso('07 con la pieza, se pide', 'mos_h: falta el valor', pg_temp.err('RPb'));
SELECT pg_temp.calc('RPc', 'VP', '{"piezas": {"Mosq": true}, "variables": {"mos_h": 900}}');
SELECT pg_temp.caso('07 con su valor', '900', pg_temp.f('RPc', 'Felpa', 'medida'));
SELECT pg_temp.calc('RPd', 'VP', '{"piezas": {"Burlete": false}}');
SELECT pg_temp.caso('07 sacar la incluida', '1', pg_temp.filas('RPd'));
SELECT pg_temp.calc('RPe', 'VP', '{"piezas": {"Cortina": true}}');
SELECT pg_temp.caso('07 la cortina trae el cajón', 'Zqx161 Rueda40', pg_temp.f('RPe', 'Rueda40', 'insumo'));
SELECT pg_temp.caso('07 las dos filas más', '4', pg_temp.filas('RPe'));
SELECT pg_temp.calc('RPf', 'VP', '{"piezas": {"Cortina": true, "Cajon": false}}');
SELECT pg_temp.caso('07 destildar el cajón destilda la cortina', '2', pg_temp.filas('RPf'));
SELECT pg_temp.calc('RPg', 'VP', '{"piezas": {"Cajon": true}}');
SELECT pg_temp.caso('07 el cajón solo', '3', pg_temp.filas('RPg'));
SELECT pg_temp.calc('RPh', 'VP', '{"piezas": {"Nada": true}}');
SELECT pg_temp.caso('07 una pieza que no está', 'Nada: esa pieza ya no se puede elegir', pg_temp.err('RPh'));
SELECT pg_temp.calc('RPi', 'VP', '{"piezas": {"Fija": false}}');
SELECT pg_temp.caso('07 una fija no se elige', 'Fija: esa pieza ya no se puede elegir', pg_temp.err('RPi'));

SELECT pg_temp.ver('VP2');
SELECT pg_temp.pz('VP2', 'Cajon', 1, '{"opcional": true}');
SELECT pg_temp.pz('VP2', 'Cortina', 2, jsonb_build_object('opcional', true, 'incluida', true, 'requiere_pieza_id', pg_temp.id('VP2.Cajon')));
SELECT pg_temp.un('VP2', 'Cajon', 1, 'Rueda40');
SELECT pg_temp.un('VP2', 'Cortina', 1, 'Rueda80');
SELECT pg_temp.calc('RP2a', 'VP2');
SELECT pg_temp.caso('07 incluida, trae el cajón', '2', pg_temp.filas('RP2a'));
SELECT pg_temp.calc('RP2b', 'VP2', '{"piezas": {"Cajon": false}}');
SELECT pg_temp.caso('07 sacar el cajón saca la incluida', '0', pg_temp.filas('RP2b'));

SELECT pg_temp.ver('VP3');
SELECT pg_temp.pz('VP3', 'Fija', 1);
SELECT pg_temp.pz('VP3', 'Opc', 2, '{"opcional": true}');
SELECT pg_temp.un('VP3', 'Opc', 1, 'Tela', '{"ancho": "100", "alto": "100"}');
SELECT pg_temp.un('VP3', 'Fija', 1, 'Felpa', '{"medida": "[Zqx161 Tela]"}');
SELECT pg_temp.calc('RP3a', 'VP3');
SELECT pg_temp.caso('07 una fija que usa lo de una opcional que no está',
  'Zqx161 Felpa: usa Zqx161 Tela, que no existe o no se pudo calcular', pg_temp.err('RP3a'));
SELECT pg_temp.calc('RP3b', 'VP3', '{"piezas": {"Opc": true}}');
SELECT pg_temp.caso('07 con la pieza sí', '10000', pg_temp.f('RP3b', 'Felpa', 'medida'));

-- ============================================================
-- 08. Color
-- ============================================================
SELECT pg_temp.caso('08 sin elegir, el base', 'Zqx161 Blanco', pg_temp.g('R1', '{color,nombre}'));
SELECT pg_temp.caso('08 la fila lleva el color', 'Zqx161 Blanco', pg_temp.f('R1', 'PerfilMarco', 'color'));
SELECT pg_temp.caso('08 lo indistinto no', NULL, pg_temp.f('R1', 'Vidrio', 'color'));
SELECT pg_temp.calc('R8a', 'V1', jsonb_build_object('variables', '{"ancho": 1500, "alto": 1200}'::jsonb, 'color', pg_temp.id('Negro')));
SELECT pg_temp.caso('08 elegido', 'Zqx161 Negro', pg_temp.f('R8a', 'PerfilHoja', 'color'));
SELECT pg_temp.calc('R8b', 'V1', jsonb_build_object('variables', '{"ancho": 1500, "alto": 1200}'::jsonb, 'color', pg_temp.id('Rojo')));
SELECT pg_temp.caso('08 uno que la versión no ofrece', 'El color elegido no está en esta versión', pg_temp.err('R8b'));
SELECT pg_temp.ver('VNC');
SELECT pg_temp.pz('VNC', 'P', 1);
SELECT pg_temp.un('VNC', 'P', 1, 'PerfilHoja', '{"medida": "100"}');
SELECT pg_temp.calc('R8c', 'VNC');
SELECT pg_temp.sale('R8c');
SELECT pg_temp.caso('08 sin colores en la versión: sale sin color', NULL, pg_temp.f('R8c', 'PerfilHoja', 'color'));

-- ============================================================
-- 09. Alertas y bloqueos
-- ============================================================
SELECT pg_temp.calc('R9a', 'V1', '{"variables": {"ancho": 1500, "alto": 2300}}');
SELECT pg_temp.caso('09 una alerta', 'Revisar el refuerzo', pg_temp.men('R9a'));
SELECT pg_temp.caso('09 no bloquea', 'false', pg_temp.g('R9a', '{bloqueado}'));
SELECT pg_temp.caso('09 dice de quién es', pg_temp.id('V1.alto')::text, pg_temp.g('R9a', '{mensajes,0,variable_id}'));
SELECT pg_temp.calc('R9b', 'V1', '{"variables": {"ancho": 2900, "alto": 1000}}');
SELECT pg_temp.caso('09 un bloqueo', 'Hasta 2.800 de ancho', pg_temp.men('R9b'));
SELECT pg_temp.caso('09 bloquea', 'true', pg_temp.g('R9b', '{bloqueado}'));
SELECT pg_temp.sale('R9b');
SELECT pg_temp.caso('09 el despiece sale igual', '12', pg_temp.filas('R9b'));
SELECT pg_temp.calc('R9c', 'V1', '{"variables": {"ancho": 200, "alto": 1200}}');
SELECT pg_temp.caso('09 fuera de rango', 'Ancho va de 300 a 3.000 mm', pg_temp.men('R9c'));
SELECT pg_temp.caso('09 fuera de rango bloquea', 'true', pg_temp.g('R9c', '{bloqueado}'));
SELECT pg_temp.calc('R9d', 'V1', '{"variables": {"ancho": 2500, "alto": 1800}}');
SELECT pg_temp.caso('09 la condición de la opción elegida', 'El Float llega hasta 2 m2', pg_temp.men('R9d'));
SELECT pg_temp.caso('09 dice de qué opción', pg_temp.id('V1.Hoja.Vidrio.Float')::text, pg_temp.g('R9d', '{mensajes,0,opcion_id}'));
SELECT pg_temp.calc('R9e', 'V1', '{"variables": {"ancho": 2500, "alto": 1800}}'::jsonb || pg_temp.el('Hoja', 'Vidrio', 'Laminado'));
SELECT pg_temp.caso('09 con otra opción no salta', NULL, pg_temp.men('R9e'));
SELECT pg_temp.caso('09 con otra opción no bloquea', 'false', pg_temp.g('R9e', '{bloqueado}'));

SELECT pg_temp.ver('VRg');
SELECT pg_temp.en('VRg', 'a', 1, 10, NULL);
SELECT pg_temp.en('VRg', 'b', 2, NULL, 20);
SELECT pg_temp.calc('R9f', 'VRg', '{"variables": {"a": 5, "b": 25}}');
SELECT pg_temp.caso('09 en un borrador puede faltar un tope', 'A va desde 10 mm | B va hasta 20 mm', pg_temp.men('R9f'));

SELECT pg_temp.ver('VCd');
SELECT pg_temp.vr('VCd', 'a', 1, '0');
SELECT pg_temp.co('VCd', 'variable_id', 'VCd.a', '1 / a > 1', 'Nunca');
SELECT pg_temp.calc('R9g', 'VCd');
SELECT pg_temp.no_sale('R9g');
SELECT pg_temp.caso('09 una condición que no se puede hacer', 'a: una condición no se puede hacer', pg_temp.err('R9g'));

-- ============================================================
-- 10. Peso, espesor y referencias
-- ============================================================
SELECT pg_temp.ver('VPe');
SELECT pg_temp.pz('VPe', 'H', 1, '{"cantidad": "3", "calcula_espesor": true}');
SELECT pg_temp.un('VPe', 'H', 1, 'Float', '{"ancho": "1000", "alto": "1000", "cantidad": "2", "cuenta_espesor": true}');
SELECT pg_temp.pz('VPe', 'Sin', 2);
SELECT pg_temp.un('VPe', 'Sin', 1, 'Soldado', '{"cantidad": "4"}');
SELECT pg_temp.vr('VPe', 'ph', 1, '[peso H]');
SELECT pg_temp.vr('VPe', 'eh', 2, '[espesor H]');
SELECT pg_temp.calc('R10', 'VPe');
SELECT pg_temp.sale('R10');
SELECT pg_temp.caso('10 el peso es de una sola pieza', '20', pg_temp.pie('R10', 'H', 'peso'));
SELECT pg_temp.caso('10 el espesor lo multiplica el material y no la pieza', '8', pg_temp.pie('R10', 'H', 'espesor'));
SELECT pg_temp.caso('10 el total sí lleva la pieza', '6', pg_temp.f('R10', 'Float', 'total'));
SELECT pg_temp.caso('10 [peso H] en una fórmula', '20', pg_temp.var('R10', 'ph'));
SELECT pg_temp.caso('10 [espesor H] en una fórmula', '8', pg_temp.var('R10', 'eh'));
SELECT pg_temp.caso('10 el servicio fijo no pesa', '0', pg_temp.pie('R10', 'Sin', 'peso'));

SELECT pg_temp.ver('VPe2');
SELECT pg_temp.pz('VPe2', 'Sin', 1);
SELECT pg_temp.vr('VPe2', 'q', 1, '[espesor Sin]');
SELECT pg_temp.calc('R10b', 'VPe2');
SELECT pg_temp.caso('10 sin calcular espesor, no existe', 'q: usa espesor Sin, que no existe o no se pudo calcular', pg_temp.err('R10b'));

SELECT pg_temp.ver('VPe3');
SELECT pg_temp.pz('VPe3', 'H', 1, '{"calcula_espesor": true}');
SELECT pg_temp.un('VPe3', 'H', 1, 'DVH', '{"ancho": "100", "alto": "100", "cuenta_espesor": true}');
SELECT pg_temp.calc('R10c', 'VPe3');
SELECT pg_temp.sale('R10c');
SELECT pg_temp.caso('10 peso vacío: no es 0', NULL, pg_temp.pie('R10c', 'H', 'peso'));
SELECT pg_temp.caso('10 espesor vacío: no es 0', NULL, pg_temp.pie('R10c', 'H', 'espesor'));
SELECT pg_temp.vr('VPe3', 'q', 1, '[peso H]');
SELECT pg_temp.calc('R10d', 'VPe3');
SELECT pg_temp.caso('10 usarlo sí frena', 'q: usa peso H, que no existe o no se pudo calcular', pg_temp.err('R10d'));

SELECT pg_temp.ver('VPe4');
SELECT pg_temp.pz('VPe4', 'H', 1);
SELECT pg_temp.un('VPe4', 'H', 1, 'DVH', '{"ancho": "100", "alto": "100", "cuenta_peso": false}');
SELECT pg_temp.calc('R10e', 'VPe4');
SELECT pg_temp.caso('10 si no cuenta, no hace falta', '0', pg_temp.pie('R10e', 'H', 'peso'));

SELECT pg_temp.ver('VPe5');
SELECT pg_temp.pz('VPe5', 'H', 1);
SELECT pg_temp.mu('VPe5', 'H', 1, 'elige_vendedor', 'X', '{"ancho": "1000", "alto": "1000"}');
SELECT pg_temp.op('VPe5', 'VPe5.H.X', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('VPe5', 'VPe5.H.X', 2, 'Soldado');
SELECT pg_temp.calc('R10f', 'VPe5');
SELECT pg_temp.caso('10 opción de insumo, pesa', '10', pg_temp.pie('R10f', 'H', 'peso'));
SELECT pg_temp.calc('R10g', 'VPe5', pg_temp.el('H', 'X', 'Soldado'));
SELECT pg_temp.caso('10 opción de servicio, no', '0', pg_temp.pie('R10g', 'H', 'peso'));

SELECT pg_temp.ver('VN');
SELECT pg_temp.pz('VN', 'H1', 1, '{"cantidad": "2"}');
SELECT pg_temp.pz('VN', 'H2', 2);
SELECT pg_temp.pz('VN', 'Base', 3);
SELECT pg_temp.un('VN', 'H1', 1, 'PerfilHoja', '{"medida": "100"}');
SELECT pg_temp.un('VN', 'H1', 2, 'Felpa', '{"medida": "[Zqx161 PerfilHoja]"}');
SELECT pg_temp.un('VN', 'H1', 3, 'Escuadra', '{"medida": "300", "cantidad": "3"}');
SELECT pg_temp.un('VN', 'H2', 1, 'PerfilHoja', '{"medida": "300"}');
SELECT pg_temp.un('VN', 'Base', 1, 'Sellador', '{"medida": "[Zqx161 PerfilHoja]"}');
SELECT pg_temp.un('VN', 'Base', 2, 'Curvo', '{"medida": "[Zqx161 Escuadra] × 1000"}');
SELECT pg_temp.calc('R10h', 'VN');
SELECT pg_temp.sale('R10h');
SELECT pg_temp.caso('10 mismo nombre, dentro de la pieza', '100', pg_temp.f('R10h', 'Felpa', 'medida'));
SELECT pg_temp.caso('10 mismo nombre, desde otra: la suma', '500', pg_temp.f('R10h', 'Sellador', 'medida'));
SELECT pg_temp.caso('10 en u, la medida solo es para cortar', '300', pg_temp.f('R10h', 'Escuadra', 'medida'));
SELECT pg_temp.caso('10 en u, se cobra la cantidad', '6', pg_temp.f('R10h', 'Escuadra', 'total'));
SELECT pg_temp.caso('10 en u, vale la cantidad', '6000', pg_temp.f('R10h', 'Curvo', 'medida'));

-- ============================================================
-- 11. El arco rebajado
-- ============================================================
SELECT pg_temp.ver('VA');
SELECT pg_temp.en('VA', 'ancho', 1, 300, 3000);
SELECT pg_temp.en('VA', 'flecha', 2, NULL, NULL);
SELECT pg_temp.vr('VA', 'radio', 3, 'flecha / 2 + ancho × ancho / (8 × flecha)');
SELECT pg_temp.pz('VA', 'Arco', 1);
SELECT pg_temp.un('VA', 'Arco', 1, 'Curvo', '{"medida": "2 × radio × arcoseno(ancho / (2 × radio))"}');
SELECT pg_temp.un('VA', 'Arco', 2, 'Float', '{"ancho": "ancho", "alto": "flecha", "area": "radio × radio × arcoseno(ancho / (2 × radio)) − ancho / 2 × (radio − flecha)"}');
SELECT pg_temp.calc('RA', 'VA', '{"variables": {"ancho": 1200, "flecha": 200}}');
SELECT pg_temp.sale('RA');
SELECT pg_temp.caso('11 el radio', '1000', pg_temp.var('RA', 'radio'));
SELECT pg_temp.caso('11 el perfil curvo', '1287.002', pg_temp.f('RA', 'Curvo', 'medida'));
SELECT pg_temp.caso('11 el corte del rectángulo', '200', pg_temp.f('RA', 'Float', 'alto'));
SELECT pg_temp.caso('11 el área propia en m2', '0.164', pg_temp.f('RA', 'Float', 'area'));
SELECT pg_temp.calc('RAb', 'VA', '{"variables": {"ancho": 1200, "flecha": 0}}');
SELECT pg_temp.no_sale('RAb');
SELECT pg_temp.tiene('RAb', 'radio: una cuenta divide por cero');

-- ============================================================
-- 12. Casos de prueba
-- ============================================================
SELECT pg_temp.ver('VCh');
SELECT pg_temp.en('VCh', 'ancho', 1, 300, 3000);
SELECT pg_temp.en('VCh', 'alto', 2, 300, 3000);
SELECT pg_temp.pz('VCh', 'P', 1);
SELECT pg_temp.un('VCh', 'P', 1, 'Float', '{"ancho": "ancho", "alto": "alto − 1200"}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'VCh', '{"nombre": "Chica", "entrada": {"variables": {"ancho": 600, "alto": 600}}}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'VCh', '{"nombre": "Grande", "entrada": {"variables": {"ancho": 2000, "alto": 2500}}}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'VCh', '{"nombre": "Fuera de rango", "entrada": {"variables": {"ancho": 5000, "alto": 2500}}}');
SELECT pg_temp.mete('VCh.saco', 'catalogo_casos', 'VCh', '{"nombre": "Sacado", "entrada": {"variables": {"ancho": 1, "alto": 1}}}');
SELECT pg_temp.caso('12 sacar un caso', 'false', pg_temp.consultar(format(
  $q$WITH u AS (UPDATE catalogo_casos SET activo = false WHERE id = %s RETURNING activo) SELECT activo::text FROM u$q$, pg_temp.l('VCh.saco')), 'Lucia'));
SELECT pg_temp.caso('12 cada caso, con lo suyo', 'Chica: false | Fuera de rango: true | Grande: true', pg_temp.consultar(format(
  $q$SELECT string_agg(nombre || ': ' || (resultado->>'calculable'), ' | ' ORDER BY nombre) FROM catalogo_casos_calcular(%s)$q$, pg_temp.l('VCh')), 'Lucia'));
SELECT pg_temp.caso('12 el caso chica dice qué pasó', 'Zqx161 Float: el alto dio −600 mm', pg_temp.consultar(format(
  $q$SELECT resultado#>>'{errores,0}' FROM catalogo_casos_calcular(%s) WHERE nombre = 'Chica'$q$, pg_temp.l('VCh')), 'Lucia'));
SELECT pg_temp.caso('12 fuera de rango no impide calcular, y bloquea', 'true', pg_temp.consultar(format(
  $q$SELECT resultado->>'bloqueado' FROM catalogo_casos_calcular(%s) WHERE nombre = 'Fuera de rango'$q$, pg_temp.l('VCh')), 'Lucia'));

-- Un caso se copia y sigue valiendo, porque apunta por nombre y por insumo; lo que cambia en la versión nueva lo frena.
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'V1', jsonb_build_object('nombre', 'Con laminado', 'entrada',
  '{"variables": {"ancho": 1500, "alto": 1200}}'::jsonb || pg_temp.el('Hoja', 'Vidrio', 'Laminado')));
SELECT pg_temp.crear('V1c', format('SELECT catalogo_paquete_duplicar(%s, %L)', pg_temp.l('V1'), 'Zqx161 V1 copia'));
SELECT pg_temp.caso('12 copiado, sigue eligiendo lo mismo', 'Zqx161 Laminado', pg_temp.consultar(format(
  $q$SELECT f->>'insumo' FROM catalogo_casos_calcular(%s) c, jsonb_array_elements(c.resultado->'filas') f WHERE f->>'material' = 'Vidrio'$q$,
  pg_temp.l('V1c')), 'Lucia'));
SELECT pg_temp.en('V1c', 'nueva', 9, NULL, NULL);
SELECT pg_temp.caso('12 una obligatoria nueva lo frena', 'nueva: falta el valor', pg_temp.consultar(format(
  $q$SELECT resultado#>>'{errores,0}' FROM catalogo_casos_calcular(%s)$q$, pg_temp.l('V1c')), 'Lucia'));
SELECT pg_temp.caso('12 sacar la opción', 'ok', pg_temp.consultar(format(
  $q$WITH u AS (UPDATE catalogo_opciones SET activo = false WHERE version_id = %s AND insumo_id = %s AND sigue_opcion_id IS NULL RETURNING 1) SELECT 'ok' FROM u$q$,
  pg_temp.l('V1c'), pg_temp.l('Laminado')), 'Lucia'));
SELECT pg_temp.caso('12 una opción sacada lo frena', 'Vidrio: esa opción ya no existe', pg_temp.consultar(format(
  $q$SELECT resultado#>>'{errores,0}' FROM catalogo_casos_calcular(%s)$q$, pg_temp.l('V1c')), 'Lucia'));
SELECT pg_temp.caso('12 sacar el material', 'ok', pg_temp.consultar(format(
  $q$WITH u AS (UPDATE catalogo_materiales SET activo = false WHERE version_id = %s AND nombre = 'Vidrio' RETURNING 1) SELECT 'ok' FROM u$q$,
  pg_temp.l('V1c')), 'Lucia'));
SELECT pg_temp.caso('12 un material sacado lo frena', 'Vidrio: esa elección ya no existe', pg_temp.consultar(format(
  $q$SELECT resultado#>>'{errores,0}' FROM catalogo_casos_calcular(%s)$q$, pg_temp.l('V1c')), 'Lucia'));

-- La forma de la entrada.
SELECT pg_temp.caso('12 entrada ' || e, '23514', pg_temp.consultar(format(
  $q$INSERT INTO catalogo_casos (version_id, nombre, entrada) VALUES (%s, 'X', %L) RETURNING 'ok'$q$, pg_temp.l('VV'), e), 'Lucia'))
FROM unnest(ARRAY['[]', '{"medidas": {}}', '{"variables": []}', '{"variables": {"a": null}}', '{"variables": {"a": true}}',
                  '{"piezas": {"a": 1}}', '{"piezas": []}', '{"elecciones": {"a": 1}}', '{"elecciones": {"a": {"b": 1}}}',
                  '{"color": 1}', '{"color": null}']) AS e;
SELECT pg_temp.caso('12 la forma entera', 'true', catalogo_entrada_valida(
  '{"variables": {"a": 1, "b": "x"}, "elecciones": {"p": {"m": "i", "n": null}}, "piezas": {"q": true}, "color": "c"}')::text);
SELECT pg_temp.caso('12 vacía', 'true', catalogo_entrada_valida('{}')::text);
SELECT pg_temp.caso('12 el cálculo con otra forma', 'CA017', pg_temp.consultar(format(
  $q$SELECT catalogo_despiece(%s, '{"medidas": {}}')$q$, pg_temp.l('VV')), 'Rodrigo'));
SELECT pg_temp.caso('12 el cálculo con NULL', 'CA017', pg_temp.consultar(format(
  $q$SELECT catalogo_despiece(%s, NULL)$q$, pg_temp.l('VV')), 'Rodrigo'));
SELECT pg_temp.caso('12 sin entrada, como vacía', 'true', pg_temp.consultar(format(
  $q$SELECT catalogo_despiece(%s)->>'calculable'$q$, pg_temp.l('VV')), 'Rodrigo'));

SELECT pg_temp.caso('12 número, miles', '1.500', catalogo_numero_texto(1500));
SELECT pg_temp.caso('12 número, negativo', '−18', catalogo_numero_texto(-18));
SELECT pg_temp.caso('12 número, decimales', '666,67', catalogo_numero_texto(666.666));
SELECT pg_temp.caso('12 número, cero', '0', catalogo_numero_texto(0));
SELECT pg_temp.caso('12 número, millones', '1.234.567,5', catalogo_numero_texto(1234567.5));

-- ============================================================
-- 13. No depende de lo que hoy se vende ni del estado
-- ============================================================
SELECT pg_temp.caso('13 dar de baja el Float', 'ok', pg_temp.consultar(format(
  $q$WITH u AS (UPDATE catalogo_insumos SET activo = false WHERE id = %s RETURNING 1) SELECT 'ok' FROM u$q$, pg_temp.l('Float')), 'Lucia'));
SELECT pg_temp.calc('R13a', 'V1', '{"variables": {"ancho": 1500, "alto": 1200}}');
SELECT pg_temp.sale('R13a');
SELECT pg_temp.caso('13 la baja no borra el despiece', 'Zqx161 Float', pg_temp.f('R13a', 'Vidrio', 'insumo'));
UPDATE catalogo_versiones SET estado = 'publicado' WHERE id = pg_temp.id('V1');
SELECT pg_temp.calc('R13b', 'V1', '{"variables": {"ancho": 1500, "alto": 1200}}');
SELECT pg_temp.caso('13 publicada da lo mismo', (SELECT j::text FROM res WHERE clave = 'R13a'), (SELECT j::text FROM res WHERE clave = 'R13b'));
UPDATE catalogo_versiones SET estado = 'obsoleto' WHERE id = pg_temp.id('V1');
SELECT pg_temp.calc('R13c', 'V1', '{"variables": {"ancho": 1500, "alto": 1200}}');
SELECT pg_temp.caso('13 obsoleta da lo mismo', (SELECT j::text FROM res WHERE clave = 'R13a'), (SELECT j::text FROM res WHERE clave = 'R13c'));

-- Lo sacado de un borrador no cuenta.
SELECT pg_temp.un('VNC', 'P', 2, 'Felpa', '{"medida": "100"}');
SELECT pg_temp.caso('13 sacar una fila', 'ok', pg_temp.consultar(format(
  $q$WITH u AS (UPDATE catalogo_materiales SET activo = false WHERE id = %s RETURNING 1) SELECT 'ok' FROM u$q$, pg_temp.l('VNC.P.Felpa.2')), 'Lucia'));
SELECT pg_temp.calc('R13d', 'VNC');
SELECT pg_temp.caso('13 lo sacado no sale', '1', pg_temp.filas('R13d'));

-- ============================================================
-- 14. Permisos
-- ============================================================
SELECT pg_temp.calc('R14l', 'V1', '{"variables": {"ancho": 1500, "alto": 1200}}', 'Lucia');
SELECT pg_temp.caso('14 Lucia ve el despiece', 'true', pg_temp.g('R14l', '{calculable}'));
SELECT pg_temp.calc('R14c', 'V1', '{"variables": {"ancho": 1500, "alto": 1200}}', 'Carlos');
SELECT pg_temp.caso('14 Carlos ve el despiece', 'true', pg_temp.g('R14c', '{calculable}'));
SELECT pg_temp.caso('14 Ana no: Administración no ve paquetes', 'CA016', pg_temp.consultar(format(
  $q$SELECT catalogo_despiece(%s)$q$, pg_temp.l('V1')), 'Ana'));
SELECT pg_temp.caso('14 Juan no', 'CA016', pg_temp.consultar(format(
  $q$SELECT catalogo_despiece(%s)$q$, pg_temp.l('V1')), 'Juan'));
SELECT pg_temp.caso('14 una versión que no está', 'CA016', pg_temp.consultar(format(
  $q$SELECT catalogo_despiece(%L)$q$, gen_random_uuid()), 'Rodrigo'));
SELECT pg_temp.caso('14 Juan no ve los casos', '0', pg_temp.consultar(format(
  $q$SELECT count(*)::text FROM catalogo_casos_calcular(%s)$q$, pg_temp.l('VCh')), 'Juan'));
SELECT pg_temp.caso('14 anon no llama ' || f, 'false', has_function_privilege('anon', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_entrada_valida(jsonb)', 'catalogo_despiece_entrada(uuid,jsonb)', 'catalogo_numero_texto(numeric)',
                  'catalogo_despiece_medida(jsonb,jsonb,text,text)', 'catalogo_despiece_elegir(jsonb,jsonb,text[],jsonb)',
                  'catalogo_despiece_fila(jsonb,jsonb,numeric,jsonb,jsonb)', 'catalogo_despiece_sumas(jsonb,jsonb,jsonb,jsonb)',
                  'catalogo_despiece(uuid,jsonb)', 'catalogo_casos_calcular(uuid)']) AS f;
SELECT pg_temp.caso('14 son INVOKER', '0', (
  SELECT count(*)::text FROM pg_proc WHERE prosecdef AND pronamespace = 'public'::regnamespace
    AND (proname LIKE 'catalogo_despiece%' OR proname IN ('catalogo_casos_calcular', 'catalogo_entrada_valida', 'catalogo_numero_texto'))));

-- ============================================================
-- Resultado
-- ============================================================
DO $$
DECLARE
  v_ok int;
  v_total int;
  v_fallan text;
  v_desde timestamptz;
  v_entrada jsonb := '{"variables": {"ancho": 1500, "alto": 1200}}';
BEGIN
  -- La ventana: 12 filas y unas 30 fórmulas. Es el tiempo que anota decisiones/catalogo/despiece.md.
  v_desde := clock_timestamp();
  PERFORM catalogo_despiece(pg_temp.id('V1'), v_entrada) FROM generate_series(1, 20);
  PERFORM pg_temp.caso('14 tiempo de un cálculo: ' || round(extract(epoch FROM clock_timestamp() - v_desde) * 1000 / 20, 1) || ' ms', 'x', 'x');

  SELECT count(*) FILTER (WHERE ok), count(*),
         string_agg(caso || ' → esperado ' || coalesce(esperado, 'NULL') || ', obtenido ' || coalesce(obtenido, 'NULL'),
                    E'\n' ORDER BY caso) FILTER (WHERE NOT ok)
  INTO v_ok, v_total, v_fallan
  FROM r;
  RAISE EXCEPTION '% / % ok · % %', v_ok, v_total,
    (SELECT caso FROM r WHERE caso LIKE '14 tiempo%'), coalesce(E'\n' || v_fallan, '');
END;
$$;

ROLLBACK;
