-- Verificación de sql/167: la variable según un material y el vendedor que cambia lo que sigue a otro. NO es una migración:
-- todo corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Lucia (Técnica: Paquetes con armar, Insumos con cargar), Carlos (gerente: Paquetes con aprobar), Rodrigo (solo
-- Paquetes) y Juan (nada). Lo creado lleva Zqx167.

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

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE plpgsql AS $f$
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
  SELECT pg_temp.crear(p_v, format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx167 ' || p_v, pg_temp.l('Ventanas')));
$f$;

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.vr(p_v text, p_nombre text, p_orden int, p_formula text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_variables', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden, 'formula', p_formula));
$f$;

CREATE FUNCTION pg_temp.un(p_v text, p_pieza text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_insumo, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', 'unico',
                       'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.mu(p_v text, p_pieza text, p_orden int, p_tipo text, p_nombre text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_nombre, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', p_tipo, 'nombre', p_nombre) || p_extra);
$f$;

CREATE FUNCTION pg_temp.op(p_v text, p_material text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_insumo, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden, 'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.pareja(p_v text, p_material text, p_orden int, p_de text, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_de, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden,
                       'sigue_opcion_id', pg_temp.id(p_de), 'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

-- La variable según un material, y el valor de una opción.
CREATE FUNCTION pg_temp.segun(p_v text, p_nombre text, p_material text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_variables', p_v,
    jsonb_build_object('nombre', p_nombre, 'segun_material_id', pg_temp.id(p_material)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.va(p_v text, p_variable text, p_opcion text, p_formula text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_variable || '=' || p_opcion, 'catalogo_variables_valores', p_v,
    jsonb_build_object('variable_id', pg_temp.id(p_variable), 'opcion_id', pg_temp.id(p_opcion), 'formula', p_formula));
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_unidad text, p_costo numeric DEFAULT 100) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)', 'Zqx167 ' || p_nombre, pg_temp.l('Perfiles'), p_unidad));
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por)
  SELECT va.id, p_costo, 'ARS'::moneda, pg_temp.id('Lucia') FROM catalogo_variantes va WHERE va.insumo_id = pg_temp.id(p_nombre);
END;
$f$;

-- Lo mínimo que se puede enviar: ancho, una Hoja con el Perfil y un caso.
CREATE FUNCTION pg_temp.base(p_v text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.ver(p_v);
  PERFORM pg_temp.mete(p_v || '.ancho', 'catalogo_variables', p_v,
    '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 300, "maximo": 3000}');
  PERFORM pg_temp.pz(p_v, 'Hoja', 1);
  PERFORM pg_temp.un(p_v, 'Hoja', 1, 'Perfil', '{"medida": "ancho"}');
  PERFORM pg_temp.mete(p_v || '.caso', 'catalogo_casos', p_v, '{"nombre": "base", "entrada": {"variables": {"ancho": 1000}}}');
END;
$f$;

-- Lo que cargaría el vendedor con ancho 1000: pares material, insumo de la Hoja. 'ninguna' es null.
CREATE FUNCTION pg_temp.e(VARIADIC p text[] DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  o jsonb := '{}';
BEGIN
  FOR i IN 1 .. coalesce(array_length(p, 1), 0) / 2 LOOP
    o := o || jsonb_build_object(p[2 * i - 1], CASE WHEN p[2 * i] = 'ninguna' THEN 'null'::jsonb ELSE to_jsonb(pg_temp.id(p[2 * i])) END);
  END LOOP;
  RETURN jsonb_build_object('variables', jsonb_build_object('ancho', 1000), 'elecciones', jsonb_build_object('Hoja', o));
END;
$f$;

CREATE FUNCTION pg_temp.n(p text) RETURNS text LANGUAGE sql AS $f$
  SELECT CASE WHEN p ~ '^-?[0-9.]+$' THEN trim_scale(p::numeric)::text ELSE p END;
$f$;

-- Un dato de la fila de un material, sin fila '-'.
CREATE FUNCTION pg_temp.fila(p_v text, p_entrada jsonb, p_material text, p_dato text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.n(pg_temp.consultar(format(
    $q$SELECT coalesce((SELECT string_agg(f->>%L, ',') FROM jsonb_array_elements(catalogo_despiece(%s, %L)->'filas') f WHERE f->>'material' = %L), '-')$q$,
    p_dato, pg_temp.l(p_v), p_entrada::text, p_material), 'Rodrigo'));
$f$;

CREATE FUNCTION pg_temp.errores(p_v text, p_entrada jsonb) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format(
    $q$SELECT coalesce((SELECT string_agg(e, ' | ' ORDER BY e) FROM jsonb_array_elements_text(catalogo_despiece(%s, %L)->'errores') e), 'ninguno')$q$,
    pg_temp.l(p_v), p_entrada::text), 'Rodrigo');
$f$;

CREATE FUNCTION pg_temp.valor(p_v text, p_entrada jsonb, p_variable text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.n(pg_temp.consultar(format(
    $q$SELECT coalesce((SELECT x->>'valor' FROM jsonb_array_elements(catalogo_despiece(%s, %L)->'variables') x WHERE x->>'nombre' = %L), '-')$q$,
    pg_temp.l(p_v), p_entrada::text, p_variable), 'Rodrigo'));
$f$;

CREATE FUNCTION pg_temp.frena(p_v text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT array_to_string(catalogo_version_revisar(%s), %L)', pg_temp.l(p_v), ' | '), 'Rodrigo');
$f$;

CREATE FUNCTION pg_temp.dice(p_v text, p_texto text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.frena(p_v);
BEGIN
  PERFORM pg_temp.caso(p_v || ' dice: ' || p_texto, 'sí', CASE WHEN position(p_texto IN v) > 0 THEN 'sí' ELSE v END);
END;
$f$;

CREATE FUNCTION pg_temp.no_dice(p_v text, p_texto text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.frena(p_v);
BEGIN
  PERFORM pg_temp.caso(p_v || ' no dice: ' || p_texto, 'no', CASE WHEN position(p_texto IN v) > 0 THEN v ELSE 'no' END);
END;
$f$;

CREATE FUNCTION pg_temp.limpia(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso(p_v || ' no frena', '', pg_temp.frena(p_v));
$f$;

CREATE FUNCTION pg_temp.publicar(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso('enviar ' || p_v, 'ok', pg_temp.intentar(format('SELECT catalogo_version_enviar(%s)', pg_temp.l(p_v))));
  SELECT pg_temp.caso('aprobar ' || p_v, 'ok', pg_temp.intentar(format('SELECT catalogo_version_aprobar(%s)', pg_temp.l(p_v)), 'Carlos'));
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

CREATE FUNCTION pg_temp.sacar(p_tabla text, p_clave text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE %I SET activo = false WHERE id = %s', p_tabla, pg_temp.l(p_clave)));
$f$;

CREATE FUNCTION pg_temp.valores_activos(p_variable uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT count(*)::text FROM catalogo_variables_valores WHERE variable_id = p_variable AND activo;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Lucia','Carlos','Rodrigo','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND modulo = 'catalogo';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test167.local', jsonb_build_object('nombre', 'test167 ' || nombre)
FROM ids WHERE nombre IN ('Lucia','Carlos','Rodrigo','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar'),
  ('Rodrigo','catalogo_paquetes')
) AS p (u, s);

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx167 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx167 Ventanas') RETURNING id$q$);

SELECT pg_temp.insumo('Perfil', 'mm');
SELECT pg_temp.insumo(n, 'u') FROM unnest(ARRAY['Simple','Oculta','Elevable','Float','Laminado','Templado','DVH','Contra4','Contra6','R1','R2']) AS n;
SELECT pg_temp.insumo('Contra10', 'u', 1000);

-- ============================================================
-- 1. La variable: Corredera simple 20, oculta 35, elevable 50
-- ============================================================
SELECT pg_temp.ver('S1');
SELECT pg_temp.mete('S1.ancho', 'catalogo_variables', 'S1', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 300, "maximo": 3000}');
SELECT pg_temp.pz('S1', 'Hoja', 1);
SELECT pg_temp.un('S1', 'Hoja', 1, 'Perfil', '{"medida": "ancho_hoja"}');
SELECT pg_temp.mu('S1', 'Hoja', 2, 'elige_vendedor', 'Herraje');
SELECT pg_temp.op('S1', 'S1.Hoja.Herraje', 1, 'Simple', '{"predeterminada": true}');
SELECT pg_temp.op('S1', 'S1.Hoja.Herraje', 2, 'Oculta');
SELECT pg_temp.op('S1', 'S1.Hoja.Herraje', 3, 'Elevable');
SELECT pg_temp.segun('S1', 'descuento_hoja', 'S1.Hoja.Herraje');
SELECT pg_temp.vr('S1', 'ancho_hoja', 3, '(ancho − descuento_hoja) / 2');
SELECT pg_temp.va('S1', 'S1.descuento_hoja', 'S1.Hoja.Herraje.Simple', '20');
SELECT pg_temp.va('S1', 'S1.descuento_hoja', 'S1.Hoja.Herraje.Oculta', '35');
SELECT pg_temp.va('S1', 'S1.descuento_hoja', 'S1.Hoja.Herraje.Elevable', '25 + 25');
SELECT pg_temp.mete('S1.caso', 'catalogo_casos', 'S1', '{"nombre": "base", "entrada": {"variables": {"ancho": 1000}}}');

SELECT pg_temp.limpia('S1');
SELECT pg_temp.caso('01 predeterminada: 20', '20', pg_temp.valor('S1', pg_temp.e(), 'descuento_hoja'));
SELECT pg_temp.caso('01 el Perfil la usa', '490', pg_temp.fila('S1', pg_temp.e(), 'Zqx167 Perfil', 'medida'));
SELECT pg_temp.caso('01 oculta: 35', '35', pg_temp.valor('S1', pg_temp.e('Herraje', 'Oculta'), 'descuento_hoja'));
SELECT pg_temp.caso('01 oculta: el Perfil', '482.5', pg_temp.fila('S1', pg_temp.e('Herraje', 'Oculta'), 'Zqx167 Perfil', 'medida'));
SELECT pg_temp.caso('01 elevable: una fórmula', '475', pg_temp.fila('S1', pg_temp.e('Herraje', 'Elevable'), 'Zqx167 Perfil', 'medida'));

-- Solo se calcula el valor de la opción elegida
SELECT pg_temp.caso('01 elevable divide por cero', 'ok', pg_temp.intentar(format('UPDATE catalogo_variables_valores SET formula = %L WHERE id = %s', '1 / 0', pg_temp.l('S1.descuento_hoja=S1.Hoja.Herraje.Elevable'))));
SELECT pg_temp.caso('01 con la simple no molesta', 'ninguno', pg_temp.errores('S1', pg_temp.e()));
SELECT pg_temp.caso('01 con la elevable sí', 'descuento_hoja: una cuenta divide por cero', pg_temp.errores('S1', pg_temp.e('Herraje', 'Elevable')));
SELECT pg_temp.caso('01 vuelve', 'ok', pg_temp.intentar(format('UPDATE catalogo_variables_valores SET formula = %L WHERE id = %s', '25 + 25', pg_temp.l('S1.descuento_hoja=S1.Hoja.Herraje.Elevable'))));

-- Lo que no se puede guardar
SELECT pg_temp.caso('02 la ingresa el vendedor', '23514', pg_temp.intentar(format('INSERT INTO catalogo_variables (version_id, nombre, ingresa_vendedor, minimo, maximo, segun_material_id) VALUES (%s, %L, true, 1, 2, %s)', pg_temp.l('S1'), 'x', pg_temp.l('S1.Hoja.Herraje'))));
SELECT pg_temp.caso('02 sin fórmula ni material', '23514', pg_temp.intentar(format('INSERT INTO catalogo_variables (version_id, nombre) VALUES (%s, %L)', pg_temp.l('S1'), 'x')));
SELECT pg_temp.caso('02 valor que no se entiende', 'CA001', pg_temp.intentar(format('INSERT INTO catalogo_variables_valores (version_id, variable_id, opcion_id, formula) VALUES (%s, %s, %s, %L)', pg_temp.l('S1'), pg_temp.l('S1.descuento_hoja'), pg_temp.l('S1.Hoja.Herraje.Simple'), '1 +')));
SELECT pg_temp.caso('02 valor repetido', '23505', pg_temp.intentar(format('INSERT INTO catalogo_variables_valores (version_id, variable_id, opcion_id, formula) VALUES (%s, %s, %s, %L)', pg_temp.l('S1'), pg_temp.l('S1.descuento_hoja'), pg_temp.l('S1.Hoja.Herraje.Simple'), '1')));
SELECT pg_temp.caso('02 Rodrigo no carga', '42501', pg_temp.intentar(format('INSERT INTO catalogo_variables_valores (version_id, variable_id, opcion_id, formula) VALUES (%s, %s, %s, %L)', pg_temp.l('S1'), pg_temp.l('S1.descuento_hoja'), pg_temp.l('S1.Hoja.Herraje.Simple'), '1'), 'Rodrigo'));
SELECT pg_temp.caso('02 Rodrigo lee', '3', pg_temp.consultar(format('SELECT count(*)::text FROM catalogo_variables_valores WHERE version_id = %s', pg_temp.l('S1')), 'Rodrigo'));
SELECT pg_temp.caso('02 Juan no lee', '0', pg_temp.consultar(format('SELECT count(*)::text FROM catalogo_variables_valores WHERE version_id = %s', pg_temp.l('S1')), 'Juan'));

-- Falta elegir: un solo error, el del material
SELECT pg_temp.base('S2');
SELECT pg_temp.mu('S2', 'Hoja', 2, 'elige_vendedor', 'Herraje');
SELECT pg_temp.op('S2', 'S2.Hoja.Herraje', 1, 'Simple');
SELECT pg_temp.segun('S2', 'd', 'S2.Hoja.Herraje');
SELECT pg_temp.va('S2', 'S2.d', 'S2.Hoja.Herraje.Simple', '5');
SELECT pg_temp.vr('S2', 'e', 3, 'd + 1');
SELECT pg_temp.caso('02 falta elegir', 'Herraje: falta elegir una opción', pg_temp.errores('S2', pg_temp.e()));

-- ============================================================
-- 3. Según lo que define el sistema, y según lo que sigue a otro
-- ============================================================
-- La regla no usa nada del material y su cantidad usa la variable: no es circular.
SELECT pg_temp.ver('Z1');
SELECT pg_temp.mete('Z1.ancho', 'catalogo_variables', 'Z1', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 300, "maximo": 3000}');
SELECT pg_temp.pz('Z1', 'Hoja', 1);
SELECT pg_temp.un('Z1', 'Hoja', 1, 'Perfil', '{"medida": "ancho − d"}');
SELECT pg_temp.mu('Z1', 'Hoja', 2, 'elige_sistema', 'Rueda', '{"eleccion": "si ancho > 1000 entonces [Zqx167 R2] si no [Zqx167 R1]", "cantidad": "d"}');
SELECT pg_temp.op('Z1', 'Z1.Hoja.Rueda', 1, 'R1');
SELECT pg_temp.op('Z1', 'Z1.Hoja.Rueda', 2, 'R2');
SELECT pg_temp.segun('Z1', 'd', 'Z1.Hoja.Rueda');
SELECT pg_temp.va('Z1', 'Z1.d', 'Z1.Hoja.Rueda.R1', '5');
SELECT pg_temp.va('Z1', 'Z1.d', 'Z1.Hoja.Rueda.R2', '7');
SELECT pg_temp.mete('Z1.caso', 'catalogo_casos', 'Z1', '{"nombre": "base", "entrada": {"variables": {"ancho": 1000}}}');
SELECT pg_temp.limpia('Z1');
SELECT pg_temp.caso('03 sistema, ancho 1000', '995', pg_temp.fila('Z1', pg_temp.e(), 'Zqx167 Perfil', 'medida'));
SELECT pg_temp.caso('03 sistema, su cantidad usa la variable', '5', pg_temp.fila('Z1', pg_temp.e(), 'Rueda', 'cantidad'));
SELECT pg_temp.caso('03 sistema, ancho 2000', '1993', pg_temp.fila('Z1', '{"variables": {"ancho": 2000}}', 'Zqx167 Perfil', 'medida'));

SELECT pg_temp.base('T1');
SELECT pg_temp.mu('T1', 'Hoja', 2, 'elige_sistema', 'Rueda', '{"eleccion": "si d > 1 entonces [Zqx167 R2] si no [Zqx167 R1]"}');
SELECT pg_temp.op('T1', 'T1.Hoja.Rueda', 1, 'R1');
SELECT pg_temp.op('T1', 'T1.Hoja.Rueda', 2, 'R2');
SELECT pg_temp.segun('T1', 'd', 'T1.Hoja.Rueda');
SELECT pg_temp.va('T1', 'T1.d', 'T1.Hoja.Rueda.R1', '5');
SELECT pg_temp.va('T1', 'T1.d', 'T1.Hoja.Rueda.R2', '7');
SELECT pg_temp.dice('T1', 'Referencia circular entre');

SELECT pg_temp.base('T2');
SELECT pg_temp.mu('T2', 'Hoja', 2, 'elige_sistema', 'Rueda', '{"eleccion": "si d > 1 entonces [Zqx167 R2] si no [Zqx167 R1]"}');
SELECT pg_temp.op('T2', 'T2.Hoja.Rueda', 1, 'R1');
SELECT pg_temp.op('T2', 'T2.Hoja.Rueda', 2, 'R2');
SELECT pg_temp.mu('T2', 'Hoja', 3, 'sigue', 'Eje', jsonb_build_object('sigue_material_id', pg_temp.id('T2.Hoja.Rueda')));
SELECT pg_temp.pareja('T2', 'T2.Hoja.Eje', 1, 'T2.Hoja.Rueda.R1', 'Simple');
SELECT pg_temp.pareja('T2', 'T2.Hoja.Eje', 2, 'T2.Hoja.Rueda.R2', 'Oculta');
SELECT pg_temp.segun('T2', 'd', 'T2.Hoja.Eje');
SELECT pg_temp.va('T2', 'T2.d', 'T2.Hoja.Eje.T2.Hoja.Rueda.R1', '5');
SELECT pg_temp.va('T2', 'T2.d', 'T2.Hoja.Eje.T2.Hoja.Rueda.R2', '7');
SELECT pg_temp.dice('T2', 'Referencia circular entre');

-- Según lo que sigue a otro, sueltas incluidas
SELECT pg_temp.ver('G1');
SELECT pg_temp.mete('G1.ancho', 'catalogo_variables', 'G1', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 300, "maximo": 3000}');
SELECT pg_temp.pz('G1', 'Hoja', 1);
SELECT pg_temp.un('G1', 'Hoja', 1, 'Perfil', '{"medida": "ancho − d"}');
SELECT pg_temp.mu('G1', 'Hoja', 2, 'elige_vendedor', 'Vidrio');
SELECT pg_temp.op('G1', 'G1.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('G1', 'G1.Hoja.Vidrio', 2, 'Laminado');
SELECT pg_temp.mu('G1', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('G1.Hoja.Vidrio')));
SELECT pg_temp.pareja('G1', 'G1.Hoja.Contra', 1, 'G1.Hoja.Vidrio.Float', 'Contra4');
SELECT pg_temp.pareja('G1', 'G1.Hoja.Contra', 2, 'G1.Hoja.Vidrio.Laminado', 'Contra6');
SELECT pg_temp.op('G1', 'G1.Hoja.Contra', 3, 'Contra10');
SELECT pg_temp.segun('G1', 'd', 'G1.Hoja.Contra');
SELECT pg_temp.va('G1', 'G1.d', 'G1.Hoja.Contra.G1.Hoja.Vidrio.Float', '4');
SELECT pg_temp.va('G1', 'G1.d', 'G1.Hoja.Contra.G1.Hoja.Vidrio.Laminado', '6');
SELECT pg_temp.mete('G1.caso', 'catalogo_casos', 'G1', '{"nombre": "base", "entrada": {"variables": {"ancho": 1000}}}');
SELECT pg_temp.dice('G1', 'd: falta el valor de Zqx167 Contra10');
SELECT pg_temp.va('G1', 'G1.d', 'G1.Hoja.Contra.Contra10', '10');
SELECT pg_temp.limpia('G1');
SELECT pg_temp.caso('03 sigue, la pareja', '996', pg_temp.fila('G1', pg_temp.e(), 'Zqx167 Perfil', 'medida'));
SELECT pg_temp.caso('03 sigue, otra pareja', '994', pg_temp.fila('G1', pg_temp.e('Vidrio', 'Laminado'), 'Zqx167 Perfil', 'medida'));
SELECT pg_temp.caso('03 sigue, a mano', '990', pg_temp.fila('G1', pg_temp.e('Contra', 'Contra10'), 'Zqx167 Perfil', 'medida'));

-- ============================================================
-- 4. Lo que frena la variable
-- ============================================================
SELECT pg_temp.base('F1');
SELECT pg_temp.mu('F1', 'Hoja', 2, 'elige_vendedor', 'Tir', '{"sin_eleccion": true}');
SELECT pg_temp.op('F1', 'F1.Hoja.Tir', 1, 'Simple');
SELECT pg_temp.segun('F1', 'd', 'F1.Hoja.Tir');
SELECT pg_temp.va('F1', 'F1.d', 'F1.Hoja.Tir.Simple', '1');
SELECT pg_temp.dice('F1', 'd: falta el valor para cuando Tir queda sin elección');

SELECT pg_temp.base('F2');
SELECT pg_temp.mu('F2', 'Hoja', 2, 'elige_sistema', 'Rueda', '{"eleccion": "si ancho > 1 entonces [Zqx167 R1] si no ninguno"}');
SELECT pg_temp.op('F2', 'F2.Hoja.Rueda', 1, 'R1');
SELECT pg_temp.segun('F2', 'd', 'F2.Hoja.Rueda');
SELECT pg_temp.va('F2', 'F2.d', 'F2.Hoja.Rueda.R1', '1');
SELECT pg_temp.dice('F2', 'd: falta el valor para cuando Rueda queda sin elección');

SELECT pg_temp.base('F3');
SELECT pg_temp.mu('F3', 'Hoja', 2, 'elige_vendedor', 'Vidrio');
SELECT pg_temp.op('F3', 'F3.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('F3', 'F3.Hoja.Vidrio', 2, 'DVH');
SELECT pg_temp.mu('F3', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('F3.Hoja.Vidrio')));
SELECT pg_temp.pareja('F3', 'F3.Hoja.Contra', 1, 'F3.Hoja.Vidrio.Float', 'Contra4');
SELECT pg_temp.pareja('F3', 'F3.Hoja.Contra', 2, 'F3.Hoja.Vidrio.DVH', NULL);
SELECT pg_temp.segun('F3', 'd', 'F3.Hoja.Contra');
SELECT pg_temp.va('F3', 'F3.d', 'F3.Hoja.Contra.F3.Hoja.Vidrio.Float', '1');
SELECT pg_temp.dice('F3', 'd: falta el valor para cuando Contra queda sin elección');

SELECT pg_temp.base('F4');
SELECT pg_temp.segun('F4', 'd', 'F4.Hoja.Perfil');
SELECT pg_temp.dice('F4', 'd: depende de Zqx167 Perfil, que no se elige');

-- Lo fijo no depende de lo opcional; lo de adentro de esa pieza, sí
SELECT pg_temp.base('F5');
SELECT pg_temp.pz('F5', 'Op', 2, '{"opcional": true}');
SELECT pg_temp.mu('F5', 'Op', 1, 'elige_vendedor', 'Herr');
SELECT pg_temp.op('F5', 'F5.Op.Herr', 1, 'Simple', '{"predeterminada": true}');
SELECT pg_temp.segun('F5', 'suelta', 'F5.Op.Herr');
SELECT pg_temp.va('F5', 'F5.suelta', 'F5.Op.Herr.Simple', '1');
SELECT pg_temp.segun('F5', 'adentro', 'F5.Op.Herr', jsonb_build_object('pieza_id', pg_temp.id('F5.Op')));
SELECT pg_temp.va('F5', 'F5.adentro', 'F5.Op.Herr.Simple', '1');
SELECT pg_temp.dice('F5', 'suelta: depende de Herr, que puede no estar');
SELECT pg_temp.no_dice('F5', 'adentro: depende');
SELECT pg_temp.caso('04 sin la pieza no se puede calcular', true::text, (pg_temp.errores('F5', pg_temp.e()) LIKE 'suelta: usa Herr%')::text);

-- Cuentan todos los valores, no solo el que se elija
SELECT pg_temp.base('F6');
SELECT pg_temp.mete('F6.mano', 'catalogo_variables', 'F6', '{"nombre": "mano", "ingresa_vendedor": true, "es_lista": true, "valores": ["I", "D"], "valor_predeterminado": "I"}');
SELECT pg_temp.mu('F6', 'Hoja', 2, 'elige_vendedor', 'Herr');
SELECT pg_temp.op('F6', 'F6.Hoja.Herr', 1, 'Simple', '{"predeterminada": true}');
SELECT pg_temp.op('F6', 'F6.Hoja.Herr', 2, 'Oculta');
SELECT pg_temp.segun('F6', 'd', 'F6.Hoja.Herr');
SELECT pg_temp.va('F6', 'F6.d', 'F6.Hoja.Herr.Simple', 'zz + 1');
SELECT pg_temp.va('F6', 'F6.d', 'F6.Hoja.Herr.Oculta', 'mano');
SELECT pg_temp.dice('F6', 'd: usa zz, que no existe');
SELECT pg_temp.dice('F6', 'd: usa mano, que es una lista de valores');

-- Un valor de otro material no cuenta: al cambiar de material, pide los del nuevo
SELECT pg_temp.base('M1');
SELECT pg_temp.mu('M1', 'Hoja', 2, 'elige_vendedor', 'A');
SELECT pg_temp.op('M1', 'M1.Hoja.A', 1, 'Simple', '{"predeterminada": true}');
SELECT pg_temp.mu('M1', 'Hoja', 3, 'elige_vendedor', 'B');
SELECT pg_temp.op('M1', 'M1.Hoja.B', 1, 'Oculta', '{"predeterminada": true}');
SELECT pg_temp.segun('M1', 'd', 'M1.Hoja.A');
SELECT pg_temp.va('M1', 'M1.d', 'M1.Hoja.A.Simple', 'zz');
SELECT pg_temp.dice('M1', 'd: usa zz, que no existe');
SELECT pg_temp.caso('04 cambia de material', 'ok', pg_temp.intentar(format('UPDATE catalogo_variables SET segun_material_id = %s WHERE id = %s', pg_temp.l('M1.Hoja.B'), pg_temp.l('M1.d'))));
SELECT pg_temp.no_dice('M1', 'd: usa zz');
SELECT pg_temp.dice('M1', 'd: falta el valor de Zqx167 Oculta');
SELECT pg_temp.va('M1', 'M1.d', 'M1.Hoja.B.Oculta', '3');
SELECT pg_temp.limpia('M1');
SELECT pg_temp.caso('04 usa el nuevo', '3', pg_temp.valor('M1', pg_temp.e(), 'd'));

-- ============================================================
-- 5. Enviada no se edita, se copia, y lo que se saca
-- ============================================================
SELECT pg_temp.publicar('S1');
SELECT pg_temp.caso('05 enviada no se edita', 'CA012', pg_temp.intentar(format('UPDATE catalogo_variables_valores SET formula = %L WHERE id = %s', '9', pg_temp.l('S1.descuento_hoja=S1.Hoja.Herraje.Simple'))));

SELECT pg_temp.crear('S1v2', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('S1')));
SELECT pg_temp.limpia('S1v2');
SELECT pg_temp.caso('05 la copia da lo mismo', '482.5', pg_temp.fila('S1v2', pg_temp.e('Herraje', 'Oculta'), 'Zqx167 Perfil', 'medida'));
SELECT pg_temp.caso('05 la copia apunta a su material', 'true', (
  SELECT (m.version_id = pg_temp.id('S1v2'))::text FROM catalogo_variables x JOIN catalogo_materiales m ON m.id = x.segun_material_id
  WHERE x.version_id = pg_temp.id('S1v2') AND x.nombre = 'descuento_hoja'));
SELECT pg_temp.caso('05 la copia apunta a sus opciones', '3', (
  SELECT count(*)::text FROM catalogo_variables_valores vv JOIN catalogo_opciones o ON o.id = vv.opcion_id
  WHERE vv.version_id = pg_temp.id('S1v2') AND o.version_id = pg_temp.id('S1v2') AND vv.activo));
SELECT pg_temp.crear('S1dup', format('SELECT catalogo_paquete_duplicar(%s, %L)', pg_temp.l('S1'), 'Zqx167 S1dup'));
SELECT pg_temp.caso('05 duplicar también', '475', pg_temp.fila('S1dup', pg_temp.e('Herraje', 'Elevable'), 'Zqx167 Perfil', 'medida'));

INSERT INTO ids (nombre, id) SELECT 'S1v2.d', id FROM catalogo_variables WHERE version_id = pg_temp.id('S1v2') AND nombre = 'descuento_hoja';
INSERT INTO ids (nombre, id) SELECT 'S1v2.Herraje', id FROM catalogo_materiales WHERE version_id = pg_temp.id('S1v2') AND nombre = 'Herraje';
INSERT INTO ids (nombre, id) SELECT 'S1v2.Oculta', o.id FROM catalogo_opciones o WHERE o.version_id = pg_temp.id('S1v2') AND o.insumo_id = pg_temp.id('Oculta');
INSERT INTO ids (nombre, id) SELECT 'S1v2=Simple', vv.id FROM catalogo_variables_valores vv JOIN catalogo_opciones o ON o.id = vv.opcion_id
  WHERE vv.version_id = pg_temp.id('S1v2') AND o.insumo_id = pg_temp.id('Simple');
INSERT INTO ids (nombre, id) SELECT 'S1dup.d', id FROM catalogo_variables WHERE version_id = pg_temp.id('S1dup') AND nombre = 'descuento_hoja';

SELECT pg_temp.caso('05 saco un valor', 'ok', pg_temp.sacar('catalogo_variables_valores', 'S1v2=Simple'));
SELECT pg_temp.dice('S1v2', 'descuento_hoja: falta el valor de Zqx167 Simple');
SELECT pg_temp.caso('05 no vuelve', 'CA015', pg_temp.intentar(format('UPDATE catalogo_variables_valores SET activo = true WHERE id = %s', pg_temp.l('S1v2=Simple'))));
SELECT pg_temp.caso('05 sacar una opción saca su valor', 'ok', pg_temp.sacar('catalogo_opciones', 'S1v2.Oculta'));
SELECT pg_temp.caso('05 queda uno', '1', pg_temp.valores_activos(pg_temp.id('S1v2.d')));
SELECT pg_temp.no_dice('S1v2', 'falta el valor de Zqx167 Oculta');
SELECT pg_temp.caso('05 sacar el material saca la variable', 'ok', pg_temp.sacar('catalogo_materiales', 'S1v2.Herraje'));
SELECT pg_temp.caso('05 la variable salió', 'false', (SELECT activo::text FROM catalogo_variables WHERE id = pg_temp.id('S1v2.d')));
SELECT pg_temp.caso('05 sin valores', '0', pg_temp.valores_activos(pg_temp.id('S1v2.d')));
SELECT pg_temp.dice('S1v2', 'ancho_hoja: usa descuento_hoja, que no existe');
SELECT pg_temp.caso('05 sacar la variable saca sus valores', 'ok', pg_temp.sacar('catalogo_variables', 'S1dup.d'));
SELECT pg_temp.caso('05 sin valores tampoco', '0', pg_temp.valores_activos(pg_temp.id('S1dup.d')));

-- ============================================================
-- 6. El vendedor cambia lo que sigue a otro
-- ============================================================
SELECT pg_temp.base('C1');
SELECT pg_temp.mu('C1', 'Hoja', 2, 'elige_vendedor', 'Vidrio');
SELECT pg_temp.op('C1', 'C1.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('C1', 'C1.Hoja.Vidrio', 2, 'Laminado');
SELECT pg_temp.op('C1', 'C1.Hoja.Vidrio', 3, 'Templado');
SELECT pg_temp.op('C1', 'C1.Hoja.Vidrio', 4, 'DVH');
SELECT pg_temp.mu('C1', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('C1.Hoja.Vidrio'), 'secundario', true));
SELECT pg_temp.pareja('C1', 'C1.Hoja.Contra', 1, 'C1.Hoja.Vidrio.Float', 'Contra4');
SELECT pg_temp.pareja('C1', 'C1.Hoja.Contra', 2, 'C1.Hoja.Vidrio.Laminado', 'Contra6', '{"cantidad": "3"}');
SELECT pg_temp.pareja('C1', 'C1.Hoja.Contra', 3, 'C1.Hoja.Vidrio.Templado', 'Contra6', '{"cantidad": "5"}');
SELECT pg_temp.pareja('C1', 'C1.Hoja.Contra', 4, 'C1.Hoja.Vidrio.DVH', NULL);
SELECT pg_temp.op('C1', 'C1.Hoja.Contra', 5, 'Contra10');
SELECT pg_temp.mete('C1.manual', 'catalogo_casos', 'C1', jsonb_build_object('nombre', 'a mano', 'entrada', pg_temp.e('Contra', 'Contra10')));
SELECT pg_temp.limpia('C1');

SELECT pg_temp.caso('06 sin tocar', 'Zqx167 Contra4', pg_temp.fila('C1', pg_temp.e(), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 sin tocar, otra', 'Zqx167 Contra6', pg_temp.fila('C1', pg_temp.e('Vidrio', 'Laminado'), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 sin tocar, ninguna', '-', pg_temp.fila('C1', pg_temp.e('Vidrio', 'DVH'), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 una suelta', 'Zqx167 Contra10', pg_temp.fila('C1', pg_temp.e('Contra', 'Contra10'), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 la pareja de otro', 'Zqx167 Contra6', pg_temp.fila('C1', pg_temp.e('Contra', 'Contra6'), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 lo cambiado queda aunque cambie el que elige', 'Zqx167 Contra4', pg_temp.fila('C1', pg_temp.e('Vidrio', 'Laminado', 'Contra', 'Contra4'), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 con ninguna se puede sumar', 'Zqx167 Contra10', pg_temp.fila('C1', pg_temp.e('Vidrio', 'DVH', 'Contra', 'Contra10'), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 elegir ninguna', '-', pg_temp.fila('C1', pg_temp.e('Contra', 'ninguna'), 'Contra', 'insumo'));
SELECT pg_temp.caso('06 elegir ninguna no es error', 'ninguno', pg_temp.errores('C1', pg_temp.e('Contra', 'ninguna')));
SELECT pg_temp.caso('06 dos filas del mismo insumo: la de lo elegido', '5', pg_temp.fila('C1', pg_temp.e('Vidrio', 'Templado', 'Contra', 'Contra6'), 'Contra', 'cantidad'));
SELECT pg_temp.caso('06 igual que no tocarlo', '3', pg_temp.fila('C1', pg_temp.e('Vidrio', 'Laminado', 'Contra', 'Contra6'), 'Contra', 'cantidad'));
SELECT pg_temp.caso('06 una que no está', 'Contra: esa opción ya no existe', pg_temp.errores('C1', pg_temp.e('Contra', 'Oculta')));

-- Sin "ninguna" no se puede dejar vacío
SELECT pg_temp.base('C2');
SELECT pg_temp.mu('C2', 'Hoja', 2, 'elige_vendedor', 'Vidrio');
SELECT pg_temp.op('C2', 'C2.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.mu('C2', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('C2.Hoja.Vidrio')));
SELECT pg_temp.pareja('C2', 'C2.Hoja.Contra', 1, 'C2.Hoja.Vidrio.Float', 'Contra4');
SELECT pg_temp.caso('06 ninguna sin esa pareja', 'Contra: esa opción ya no existe', pg_temp.errores('C2', pg_temp.e('Contra', 'ninguna')));

-- También se cambia lo que sigue a lo que define el sistema, y se puede plegar
SELECT pg_temp.base('C3');
SELECT pg_temp.mu('C3', 'Hoja', 2, 'elige_sistema', 'Rueda', '{"eleccion": "si ancho > 1 entonces [Zqx167 R1] si no [Zqx167 R2]"}');
SELECT pg_temp.op('C3', 'C3.Hoja.Rueda', 1, 'R1');
SELECT pg_temp.op('C3', 'C3.Hoja.Rueda', 2, 'R2');
SELECT pg_temp.mu('C3', 'Hoja', 3, 'sigue', 'Eje', jsonb_build_object('sigue_material_id', pg_temp.id('C3.Hoja.Rueda'), 'secundario', true));
SELECT pg_temp.pareja('C3', 'C3.Hoja.Eje', 1, 'C3.Hoja.Rueda.R1', 'Simple');
SELECT pg_temp.pareja('C3', 'C3.Hoja.Eje', 2, 'C3.Hoja.Rueda.R2', 'Oculta');
SELECT pg_temp.limpia('C3');
SELECT pg_temp.caso('06 sigue al sistema', 'Zqx167 Simple', pg_temp.fila('C3', pg_temp.e(), 'Eje', 'insumo'));
SELECT pg_temp.caso('06 sigue al sistema, a mano', 'Zqx167 Oculta', pg_temp.fila('C3', pg_temp.e('Eje', 'Oculta'), 'Eje', 'insumo'));
SELECT pg_temp.caso('06 el sistema no se elige a mano', 'Rueda: esa elección ya no existe', pg_temp.errores('C3', pg_temp.e('Rueda', 'R1')));

-- Plegado sin nada propuesto, y una suelta igual a una pareja
SELECT pg_temp.base('C4');
SELECT pg_temp.mu('C4', 'Hoja', 2, 'elige_vendedor', 'Vidrio');
SELECT pg_temp.op('C4', 'C4.Hoja.Vidrio', 1, 'Float');
SELECT pg_temp.mu('C4', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('C4.Hoja.Vidrio'), 'secundario', true));
SELECT pg_temp.pareja('C4', 'C4.Hoja.Contra', 1, 'C4.Hoja.Vidrio.Float', 'Contra4');
SELECT pg_temp.op('C4', 'C4.Hoja.Contra', 2, 'Contra4');
SELECT pg_temp.dice('C4', 'Contra: es secundario y Vidrio no tiene predeterminada');
SELECT pg_temp.dice('C4', 'Contra: Zqx167 Contra4 ya es la pareja de otra opción');
SELECT pg_temp.no_dice('C4', 'Contra: es secundario y no tiene predeterminado');

-- ============================================================
-- 7. El precio y la oferta
-- ============================================================
SELECT pg_temp.publicar('C1');

CREATE FUNCTION pg_temp.costo(p_entrada jsonb) RETURNS numeric LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$SELECT catalogo_precio_detalle(%s, %L, '{}'::uuid[], 'ARS'::moneda)->>'costo_despiece'$q$, pg_temp.l('C1'), p_entrada::text), 'Carlos')::numeric;
$f$;

CREATE FUNCTION pg_temp.precio(p_entrada jsonb, p_dato text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$SELECT catalogo_precio(%L::uuid, %L::jsonb, '{}'::uuid[], 'ARS'::moneda)->>%L$q$, pg_temp.paquete('C1'), p_entrada::text, p_dato), 'Carlos');
$f$;

CREATE FUNCTION pg_temp.ofrece(p_v text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$
    SELECT o.armable::text || ' | ' || coalesce((SELECT string_agg(i.nombre, ',' ORDER BY i.nombre) FROM catalogo_opciones x
      JOIN catalogo_insumos i ON i.id = x.insumo_id WHERE x.id = ANY (o.opciones_fuera)), '-')
    FROM catalogo_version_oferta(%s) o$q$, pg_temp.l(p_v)), 'Rodrigo');
$f$;

SELECT pg_temp.caso('07 a mano cambia el costo', '900', trim_scale(pg_temp.costo(pg_temp.e('Contra', 'Contra10')) - pg_temp.costo(pg_temp.e()))::text);
SELECT pg_temp.caso('07 ninguna saca su costo', '-100', trim_scale(pg_temp.costo(pg_temp.e('Contra', 'ninguna')) - pg_temp.costo(pg_temp.e()))::text);
SELECT pg_temp.caso('07 tiene precio', 'true', (pg_temp.precio(pg_temp.e('Contra', 'Contra10'), 'precio') IS NOT NULL)::text);
SELECT pg_temp.caso('07 todo se ofrece', 'true | -', pg_temp.ofrece('C1'));

SELECT pg_temp.caso('07 baja la suelta', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = false WHERE id = %s', pg_temp.l('Contra10'))));
SELECT pg_temp.caso('07 el paquete sigue', 'true', (SELECT activo::text FROM catalogo_paquetes WHERE id = pg_temp.paquete('C1')));
SELECT pg_temp.caso('07 sale solo la suelta', 'true | Zqx167 Contra10', pg_temp.ofrece('C1'));
SELECT pg_temp.caso('07 elegida a mano, no se ofrece', 'Ya no se ofrece: Zqx167 Contra10', pg_temp.precio(pg_temp.e('Contra', 'Contra10'), 'mensaje'));
SELECT pg_temp.caso('07 sin elegirla, hay precio', 'true', (pg_temp.precio(pg_temp.e(), 'precio') IS NOT NULL)::text);
SELECT pg_temp.caso('07 vuelve la suelta', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = true WHERE id = %s', pg_temp.l('Contra10'))));

-- Sin su pareja, la opción sale aunque se elija otra a mano
SELECT pg_temp.caso('07 baja una pareja', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = false WHERE id = %s', pg_temp.l('Contra4'))));
SELECT pg_temp.caso('07 el Float no se ofrece', 'Ya no se ofrece: Zqx167 Float', pg_temp.precio(pg_temp.e('Contra', 'Contra10'), 'mensaje'));

-- ============================================================
-- 7b. Cambiar el tipo de un material o a quién sigue (sql/176)
-- ============================================================
SELECT pg_temp.insumo('Viejo', 'u');
SELECT pg_temp.insumo('Nuevo', 'u');
SELECT pg_temp.insumo('Metro2', 'm2');
SELECT pg_temp.insumo('Fijado', 'u');
SELECT pg_temp.insumo('Suelto', 'u');

-- A quién sigue: la pareja vieja sale, la suelta queda, y lo vivo de la pareja vieja sale con ella
SELECT pg_temp.base('K1');
SELECT pg_temp.mu('K1', 'Hoja', 2, 'elige_vendedor', 'A', '{"medida": "ancho"}');
SELECT pg_temp.op('K1', 'K1.Hoja.A', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.mu('K1', 'Hoja', 3, 'elige_vendedor', 'B', '{"medida": "ancho"}');
SELECT pg_temp.op('K1', 'K1.Hoja.B', 1, 'Laminado', '{"predeterminada": true}');
SELECT pg_temp.mu('K1', 'Hoja', 4, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('K1.Hoja.A'), 'medida', 'ancho'));
SELECT pg_temp.pareja('K1', 'K1.Hoja.Contra', 1, 'K1.Hoja.A.Float', 'Viejo');
SELECT pg_temp.op('K1', 'K1.Hoja.Contra', 2, 'Suelto');
SELECT pg_temp.segun('K1', 'dc', 'K1.Hoja.Contra');
SELECT pg_temp.va('K1', 'K1.dc', 'K1.Hoja.Contra.K1.Hoja.A.Float', '7');
SELECT pg_temp.caso('07b cambia a quién sigue', 'ok', pg_temp.intentar(format('UPDATE catalogo_materiales SET sigue_material_id = %s WHERE id = %s', pg_temp.l('K1.Hoja.B'), pg_temp.l('K1.Hoja.Contra'))));
SELECT pg_temp.caso('07b la pareja vieja sale', 'false', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K1.Hoja.Contra.K1.Hoja.A.Float')));
SELECT pg_temp.caso('07b la suelta queda', 'true', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K1.Hoja.Contra.Suelto')));
SELECT pg_temp.caso('07b su valor sale', '0', pg_temp.valores_activos(pg_temp.id('K1.dc')));
SELECT pg_temp.dice('K1', 'Contra: falta la pareja de Zqx167 Laminado');
SELECT pg_temp.pareja('K1', 'K1.Hoja.Contra', 3, 'K1.Hoja.B.Laminado', 'Nuevo');
SELECT pg_temp.caso('07b la pareja vieja no se elige', 'Contra: esa opción ya no existe | dc: falta el valor de la opción elegida en Contra', pg_temp.errores('K1', pg_temp.e('Contra', 'Viejo')));
SELECT pg_temp.caso('07b la pareja vieja no frena de baja', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = false WHERE id = %s', pg_temp.l('Viejo'))));
SELECT pg_temp.no_dice('K1', 'Zqx167 Viejo');
SELECT pg_temp.caso('07b la pareja vieja no se fija', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_insumos SET activo = true, unidad = 'mm' WHERE id = %s$q$, pg_temp.l('Viejo'))));

-- La pareja vieja tampoco fija la unidad de las nuevas
SELECT pg_temp.base('K2');
SELECT pg_temp.mu('K2', 'Hoja', 2, 'elige_vendedor', 'A');
SELECT pg_temp.op('K2', 'K2.Hoja.A', 1, 'Float');
SELECT pg_temp.mu('K2', 'Hoja', 3, 'elige_vendedor', 'B');
SELECT pg_temp.op('K2', 'K2.Hoja.B', 1, 'Laminado');
SELECT pg_temp.mu('K2', 'Hoja', 4, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('K2.Hoja.A')));
SELECT pg_temp.pareja('K2', 'K2.Hoja.Contra', 1, 'K2.Hoja.A.Float', 'Nuevo');
SELECT pg_temp.intentar(format('UPDATE catalogo_materiales SET sigue_material_id = %s WHERE id = %s', pg_temp.l('K2.Hoja.B'), pg_temp.l('K2.Hoja.Contra')));
SELECT pg_temp.pareja('K2', 'K2.Hoja.Contra', 2, 'K2.Hoja.B.Laminado', 'Metro2');
SELECT pg_temp.caso('07b otra unidad en la pareja nueva', 'true', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K2.Hoja.Contra.K2.Hoja.B.Laminado')));

-- Deja de seguir: las parejas salen, las sueltas son sus opciones
SELECT pg_temp.base('K3');
SELECT pg_temp.mu('K3', 'Hoja', 2, 'elige_vendedor', 'A');
SELECT pg_temp.op('K3', 'K3.Hoja.A', 1, 'Float');
SELECT pg_temp.mu('K3', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('K3.Hoja.A')));
SELECT pg_temp.pareja('K3', 'K3.Hoja.Contra', 1, 'K3.Hoja.A.Float', 'Nuevo');
SELECT pg_temp.op('K3', 'K3.Hoja.Contra', 2, 'Suelto');
SELECT pg_temp.caso('07b deja de seguir', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_materiales SET tipo = 'elige_vendedor', sigue_material_id = NULL WHERE id = %s$q$, pg_temp.l('K3.Hoja.Contra'))));
SELECT pg_temp.caso('07b sin parejas', 'Zqx167 Suelto', (SELECT string_agg(i.nombre, ',') FROM catalogo_opciones o JOIN catalogo_insumos i ON i.id = o.insumo_id WHERE o.material_id = pg_temp.id('K3.Hoja.Contra') AND o.activo));

-- Entre los que eligen no cambia nada, y empezar a seguir deja las opciones como sueltas
SELECT pg_temp.base('K4');
SELECT pg_temp.mu('K4', 'Hoja', 2, 'elige_vendedor', 'A');
SELECT pg_temp.op('K4', 'K4.Hoja.A', 1, 'Float');
SELECT pg_temp.mu('K4', 'Hoja', 3, 'elige_vendedor', 'B');
SELECT pg_temp.op('K4', 'K4.Hoja.B', 1, 'Laminado');
SELECT pg_temp.caso('07b a lo define el sistema', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_materiales SET tipo = 'elige_sistema', eleccion = '[Zqx167 Laminado]' WHERE id = %s$q$, pg_temp.l('K4.Hoja.B'))));
SELECT pg_temp.caso('07b conserva su opción', 'true', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K4.Hoja.B.Laminado')));
SELECT pg_temp.caso('07b empieza a seguir', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_materiales SET tipo = 'sigue', eleccion = NULL, sigue_material_id = %s WHERE id = %s$q$, pg_temp.l('K4.Hoja.A'), pg_temp.l('K4.Hoja.B'))));
SELECT pg_temp.caso('07b queda como suelta', 'true', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K4.Hoja.B.Laminado')));

-- A único: salen sus opciones, las parejas de quien lo sigue y sus valores; lo que apuntaba a él sigue frenando. El insumo no queda fijo ni se copia.
SELECT pg_temp.base('K5');
SELECT pg_temp.mu('K5', 'Hoja', 2, 'elige_vendedor', 'M', '{"medida": "ancho"}');
SELECT pg_temp.op('K5', 'K5.Hoja.M', 1, 'Fijado', '{"predeterminada": true}');
SELECT pg_temp.mu('K5', 'Hoja', 3, 'sigue', 'S', jsonb_build_object('sigue_material_id', pg_temp.id('K5.Hoja.M'), 'medida', 'ancho'));
SELECT pg_temp.pareja('K5', 'K5.Hoja.S', 1, 'K5.Hoja.M.Fijado', 'Nuevo');
SELECT pg_temp.segun('K5', 'dd', 'K5.Hoja.M');
SELECT pg_temp.va('K5', 'K5.dd', 'K5.Hoja.M.Fijado', '5');
SELECT pg_temp.caso('07b pasa a único', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_materiales SET tipo = 'unico', nombre = NULL, insumo_id = %s WHERE id = %s$q$, pg_temp.l('Nuevo'), pg_temp.l('K5.Hoja.M'))));
SELECT pg_temp.caso('07b sin su opción', 'false', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K5.Hoja.M.Fijado')));
SELECT pg_temp.caso('07b sin la pareja', 'false', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K5.Hoja.S.K5.Hoja.M.Fijado')));
SELECT pg_temp.caso('07b sin su valor', '0', pg_temp.valores_activos(pg_temp.id('K5.dd')));
SELECT pg_temp.dice('K5', 'S: sigue a Zqx167 Nuevo, que no elige');
SELECT pg_temp.dice('K5', 'dd: depende de Zqx167 Nuevo, que no se elige');
SELECT pg_temp.caso('07b saca el que seguía', 'ok', pg_temp.sacar('catalogo_materiales', 'K5.Hoja.S'));
SELECT pg_temp.caso('07b saca la variable', 'ok', pg_temp.sacar('catalogo_variables', 'K5.dd'));
SELECT pg_temp.limpia('K5');
SELECT pg_temp.publicar('K5');
SELECT pg_temp.caso('07b el insumo no queda fijo', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_insumos SET nombre = 'Zqx167 Fijado 2' WHERE id = %s$q$, pg_temp.l('Fijado'))));
SELECT pg_temp.crear('K5v2', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('K5')));
SELECT pg_temp.caso('07b no se copia', '0', (SELECT count(*)::text FROM catalogo_opciones WHERE version_id = pg_temp.id('K5v2')));

-- Sacar lo que se sigue deja sin a quién seguir: las sueltas quedan
SELECT pg_temp.base('K6');
SELECT pg_temp.mu('K6', 'Hoja', 2, 'elige_vendedor', 'A');
SELECT pg_temp.op('K6', 'K6.Hoja.A', 1, 'Float');
SELECT pg_temp.mu('K6', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('K6.Hoja.A')));
SELECT pg_temp.op('K6', 'K6.Hoja.Contra', 1, 'Suelto');
SELECT pg_temp.caso('07b saca lo que se sigue', 'ok', pg_temp.sacar('catalogo_materiales', 'K6.Hoja.A'));
SELECT pg_temp.caso('07b la suelta sigue ahí', 'true', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K6.Hoja.Contra.Suelto')));

-- Editar otra cosa no saca nada, y sin permiso no se cambia
SELECT pg_temp.base('K7');
SELECT pg_temp.mu('K7', 'Hoja', 2, 'elige_vendedor', 'A');
SELECT pg_temp.op('K7', 'K7.Hoja.A', 1, 'Float');
SELECT pg_temp.mu('K7', 'Hoja', 3, 'sigue', 'Contra', jsonb_build_object('sigue_material_id', pg_temp.id('K7.Hoja.A')));
SELECT pg_temp.pareja('K7', 'K7.Hoja.Contra', 1, 'K7.Hoja.A.Float', 'Nuevo');
SELECT pg_temp.caso('07b guarda igual', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_materiales SET tipo = 'sigue', sigue_material_id = %s, nombre = 'Contra 2' WHERE id = %s$q$, pg_temp.l('K7.Hoja.A'), pg_temp.l('K7.Hoja.Contra'))));
SELECT pg_temp.caso('07b la pareja queda', 'true', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K7.Hoja.Contra.K7.Hoja.A.Float')));
SELECT pg_temp.intentar(format($q$UPDATE catalogo_materiales SET tipo = 'unico', nombre = NULL, sigue_material_id = NULL, insumo_id = %s WHERE id = %s$q$, pg_temp.l('Nuevo'), pg_temp.l('K7.Hoja.Contra')), 'Rodrigo');
SELECT pg_temp.caso('07b sin armar no saca', 'true', (SELECT activo::text FROM catalogo_opciones WHERE id = pg_temp.id('K7.Hoja.Contra.K7.Hoja.A.Float')));

-- ============================================================
-- 8. Privilegios
-- ============================================================
SELECT pg_temp.caso('08 el trigger no se llama', 'false', has_function_privilege('authenticated', 'catalogo_material_cambia()', 'EXECUTE')::text);
SELECT pg_temp.caso('08 anon no llama el trigger', 'false', has_function_privilege('anon', 'catalogo_material_cambia()', 'EXECUTE')::text);
SELECT pg_temp.caso('08 RLS', 'true', (SELECT c.relrowsecurity::text FROM pg_class c WHERE c.relname = 'catalogo_variables_valores'));
SELECT pg_temp.caso('08 anon no llama', 'false', has_function_privilege('anon', 'catalogo_despiece_segun(jsonb,jsonb,jsonb,text[],jsonb)', 'EXECUTE')::text);
SELECT pg_temp.caso('08 anon no lee', 'false', has_table_privilege('anon', 'catalogo_variables_valores', 'SELECT')::text);
SELECT pg_temp.caso('08 authenticated llama', 'true', has_function_privilege('authenticated', 'catalogo_despiece_segun(jsonb,jsonb,jsonb,text[],jsonb)', 'EXECUTE')::text);

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
