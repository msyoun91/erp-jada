-- Verificación de sql/163: el precio de un paquete, el detalle del gerente, los mínimos por presupuesto y los precios de
-- referencia. NO es una migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y
-- los casos que fallan.
--
-- Mundo: Lucia (Técnica: Paquetes con armar, Insumos con cargar), Ana (Administración: costos, fijos y servicios en %), Carlos
-- (gerente: Paquetes con aprobar), Rodrigo (solo Paquetes) y Juan (nada). Lo creado lleva Zqx163. Los ejemplos son los de
-- decisiones/catalogo/precio.md.

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

-- Un número, sin mirar la escala: 3000.0000 es 3000. Lo que no es un número (un código de error) se compara como vino.
CREATE FUNCTION pg_temp.n(p_caso text, p_esperado numeric, p_obtenido text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := p_obtenido;
BEGIN
  BEGIN
    v := trim_scale(round(p_obtenido::numeric, 6))::text;
  EXCEPTION WHEN invalid_text_representation THEN NULL;
  END;
  PERFORM pg_temp.caso(p_caso, trim_scale(round(p_esperado, 6))::text, v);
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
  SELECT pg_temp.crear(p_v, format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx163 ' || p_v, pg_temp.l('Ventanas')));
$f$;

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.en(p_v text, p_nombre text, p_orden int, p_min numeric, p_max numeric) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_variables', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden, 'ingresa_vendedor', true, 'minimo', p_min, 'maximo', p_max));
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

CREATE FUNCTION pg_temp.color_base(p_v text, p_color text, p_base boolean) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(NULL, 'catalogo_versiones_colores', p_v, jsonb_build_object('color_id', pg_temp.id(p_color), 'base', p_base));
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)',
    'Zqx163 ' || p_nombre, pg_temp.l(p_categoria), p_unidad));
$f$;

-- Un costo con su fecha. Directo: la carga ya se prueba en sql/tests/catalogo_registros.sql.
CREATE FUNCTION pg_temp.costo(p_insumo text, p_color text, p_costo numeric, p_moneda text, p_desde timestamptz) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, p_costo, p_moneda::moneda, pg_temp.id('Ana'), p_desde
  FROM catalogo_variantes va
  WHERE va.insumo_id = pg_temp.id(p_insumo) AND va.color_id IS NOT DISTINCT FROM pg_temp.id(p_color);
$f$;

CREATE FUNCTION pg_temp.hace(p_dias int) RETURNS timestamptz LANGUAGE sql AS $f$
  SELECT now() - p_dias * interval '1 day';
$f$;

CREATE FUNCTION pg_temp.sin_servicios() RETURNS void LANGUAGE sql AS $f$
  UPDATE catalogo_porcentajes_valores SET activo = false WHERE activo;
$f$;

-- Un servicio en % con su fecha. Directo, como los costos. La misma clave suma un valor nuevo al mismo servicio.
CREATE FUNCTION pg_temp.serv(p_clave text, p_pct numeric, p_paso int, p_cats text[] DEFAULT '{}', p_min numeric DEFAULT NULL,
  p_mon text DEFAULT NULL, p_por text DEFAULT NULL, p_opc boolean DEFAULT false, p_desde timestamptz DEFAULT now() - interval '100 days',
  p_de_baja boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := pg_temp.id(p_clave);
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO catalogo_porcentajes DEFAULT VALUES RETURNING id INTO v_id;
    INSERT INTO ids VALUES (p_clave, v_id);
  END IF;
  INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda,
    minimo_por, opcional, de_baja, creado_por, created_at)
  VALUES (v_id, 'Zqx163 ' || p_clave, p_pct, p_paso, ARRAY(SELECT pg_temp.id(c) FROM unnest(p_cats) c), p_min,
    p_mon::moneda, p_por::alcance_minimo, p_opc, p_de_baja, pg_temp.id('Ana'),
    p_desde - nextval('pasos') * interval '1 second');
END;
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

CREATE FUNCTION pg_temp.fn(p_fn text, p_v text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT catalogo_version_%s(%s)', p_fn, pg_temp.l(p_v)), p_como);
$f$;

CREATE FUNCTION pg_temp.publicar(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso('enviar ' || p_v, 'ok', pg_temp.fn('enviar', p_v, 'Lucia'));
  SELECT pg_temp.caso('aprobar ' || p_v, 'ok', pg_temp.fn('aprobar', p_v, 'Carlos'));
$f$;

CREATE FUNCTION pg_temp.chico(p_v text, p_insumo text, p_cantidad text DEFAULT '1') RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.ver(p_v);
  PERFORM pg_temp.pz(p_v, 'Unica', 1);
  PERFORM pg_temp.un(p_v, 'Unica', 1, p_insumo, jsonb_build_object('cantidad', p_cantidad));
  PERFORM pg_temp.mete(p_v || '.caso', 'catalogo_casos', p_v, '{"nombre": "base"}');
END;
$f$;

-- Lo que recibe el vendedor. p_ruta es un camino de jsonb, como '{precio}'.
CREATE FUNCTION pg_temp.pr(p_v text, p_ruta text DEFAULT '{precio}', p_entrada jsonb DEFAULT '{"variables":{"ancho":1000,"alto":1000}}',
  p_moneda text DEFAULT 'ARS', p_opc text[] DEFAULT '{}', p_como text DEFAULT 'Carlos') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT catalogo_precio(%L, %L::jsonb, %L::uuid[], %L::moneda) #>> %L::text[]',
    pg_temp.paquete(p_v), p_entrada, ARRAY(SELECT pg_temp.id(o) FROM unnest(p_opc) o), p_moneda, p_ruta), p_como);
$f$;

-- El detalle de una versión.
CREATE FUNCTION pg_temp.de(p_v text, p_ruta text, p_entrada jsonb DEFAULT '{"variables":{"ancho":1000,"alto":1000}}',
  p_moneda text DEFAULT 'ARS', p_opc text[] DEFAULT '{}', p_en timestamptz DEFAULT now(), p_como text DEFAULT 'Carlos') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT catalogo_precio_detalle(%L, %L::jsonb, %L::uuid[], %L::moneda, %L::timestamptz) #>> %L::text[]',
    pg_temp.id(p_v), p_entrada, ARRAY(SELECT pg_temp.id(o) FROM unnest(p_opc) o), p_moneda, p_en, p_ruta), p_como);
$f$;

-- Una entrada con medidas y lo que se le sume.
CREATE FUNCTION pg_temp.e(p_extra jsonb, p_ancho numeric DEFAULT 1000, p_alto numeric DEFAULT 1000) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('variables', jsonb_build_object('ancho', p_ancho, 'alto', p_alto)) || p_extra;
$f$;

CREATE FUNCTION pg_temp.vidrio(p_insumo text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.e(jsonb_build_object('elecciones', jsonb_build_object('Hoja', jsonb_build_object('Vidrio', pg_temp.id(p_insumo)))));
$f$;

CREATE FUNCTION pg_temp.color(p_color text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.e(jsonb_build_object('color', pg_temp.id(p_color)));
$f$;

-- Un ítem de un presupuesto, y los renglones de varios: "Servicio=monto | Otro=monto", o "nada".
CREATE FUNCTION pg_temp.it(p_v text, p_cant numeric, p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('paquete_id', pg_temp.paquete(p_v), 'cantidad', p_cant, 'entrada', pg_temp.e('{}')) || p_extra;
$f$;

CREATE FUNCTION pg_temp.con_opc(VARIADIC p_claves text[]) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('opcionales', to_jsonb(ARRAY(SELECT pg_temp.id(c) FROM unnest(p_claves) c)));
$f$;

CREATE FUNCTION pg_temp.mi(p_items jsonb, p_moneda text DEFAULT 'ARS', p_como text DEFAULT 'Carlos') RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format(
    $q$SELECT string_agg(replace(m.nombre, 'Zqx163 ', '') || '=' || trim_scale(m.monto), ' | ') FROM catalogo_precio_minimos(%L::jsonb, %L::moneda) m$q$,
    p_items, p_moneda), p_como), 'nada');
$f$;

CREATE FUNCTION pg_temp.re(p_v text, p_caso text, p_col text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format(
    $q$SELECT x.%I::text FROM catalogo_precios_referencia('ARS'::moneda, now() - interval '30 days', now()) x WHERE x.version_id = %L AND x.caso = %L$q$,
    p_col, pg_temp.id(p_v), p_caso), 'Carlos');
$f$;

-- ============================================================
-- Montaje
-- ============================================================
SELECT pg_temp.sin_servicios();
UPDATE monedas_tipos_cambio SET activo = false WHERE activo;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Lucia','Ana','Carlos','Rodrigo','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND modulo = 'catalogo';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test163.local', jsonb_build_object('nombre', 'test163 ' || nombre)
FROM ids WHERE nombre IN ('Lucia','Ana','Carlos','Rodrigo','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Ana','catalogo_insumos'), ('Ana','catalogo_costos'), ('Ana','catalogo_fijos'), ('Ana','catalogo_fijos_editar'),
  ('Ana','catalogo_porcentajes'), ('Ana','catalogo_porcentajes_editar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar'),
  ('Rodrigo','catalogo_paquetes')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde) VALUES
  ('USD_OFICIAL', 1000, pg_temp.hace(50), 'monedapi', pg_temp.hace(50)),
  ('USD_BLUE',    1100, pg_temp.hace(50), 'monedapi', pg_temp.hace(50)),
  ('EUR',         1200, pg_temp.hace(50), 'monedapi', pg_temp.hace(50)),
  ('USD_OFICIAL', 1450, now(), 'monedapi', now()),
  ('USD_BLUE',    1500, now(), 'monedapi', now()),
  ('EUR',         1700, now(), 'monedapi', now());

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx163 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx163 Vidrios') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx163 Ventanas') RETURNING id$q$);
SELECT pg_temp.crear('Manos', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('servicio', 'Zqx163 Manos') RETURNING id$q$, 'Ana');
SELECT pg_temp.crear('Blanco', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx163 Blanco') RETURNING id$q$);
SELECT pg_temp.crear('Negro', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx163 Negro') RETURNING id$q$);

SELECT pg_temp.crear('PerfilMarco', format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL, ARRAY[%s, %s]::uuid[])',
  'Zqx163 PerfilMarco', pg_temp.l('Perfiles'), 'mm', pg_temp.l('Blanco'), pg_temp.l('Negro')));
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2');
SELECT pg_temp.insumo('Float2', 'Vidrios', 'm2');
SELECT pg_temp.insumo('DVH', 'Vidrios', 'm2');
SELECT pg_temp.insumo('Manija', 'Perfiles', 'u');
SELECT pg_temp.insumo('Tela', 'Perfiles', 'm2');
SELECT pg_temp.insumo('PerfilLibre', 'Perfiles', 'mm');
SELECT pg_temp.insumo('Nuevo', 'Perfiles', 'u');
SELECT pg_temp.insumo('Antiguo', 'Perfiles', 'u');
SELECT pg_temp.insumo('Antiguo2', 'Perfiles', 'u');
SELECT pg_temp.crear('Soldado', format($q$SELECT catalogo_fijo_alta('Zqx163 Soldado', %s, 'u', 500, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');

SELECT pg_temp.costo('PerfilMarco', 'Blanco', 70000, 'ARS', pg_temp.hace(100));
SELECT pg_temp.costo('PerfilMarco', 'Negro', 50, 'USD_OFICIAL', pg_temp.hace(100));
SELECT pg_temp.costo('Float', NULL, 60000, 'ARS', pg_temp.hace(100));
SELECT pg_temp.costo('Float2', NULL, 20000, 'ARS', pg_temp.hace(100));
SELECT pg_temp.costo('DVH', NULL, 100000, 'ARS', pg_temp.hace(100));
SELECT pg_temp.costo('Manija', NULL, 1000, 'ARS', pg_temp.hace(100));
SELECT pg_temp.costo('Tela', NULL, 5000, 'ARS', pg_temp.hace(100));
SELECT pg_temp.costo('PerfilLibre', NULL, 1000, 'ARS', pg_temp.hace(100));
SELECT pg_temp.costo('Nuevo', NULL, 1000, 'ARS', pg_temp.hace(10));
SELECT pg_temp.costo('Antiguo', NULL, 10, 'USD_BLUE', '1999-01-01');
SELECT pg_temp.costo('Antiguo2', NULL, 1000, 'ARS', '1999-01-01');

-- Ej: la ventana de $200.000 con 1000 × 1000, $140.000 de perfil y $60.000 de vidrio.
SELECT pg_temp.ver('Ej');
SELECT pg_temp.color_base('Ej', 'Blanco', true);
SELECT pg_temp.color_base('Ej', 'Negro', false);
SELECT pg_temp.en('Ej', 'ancho', 1, 100, 5000);
SELECT pg_temp.en('Ej', 'alto', 2, 100, 5000);
SELECT pg_temp.pz('Ej', 'Marco', 1);
SELECT pg_temp.un('Ej', 'Marco', 1, 'PerfilMarco', '{"medida": "ancho", "cantidad": "2"}');
SELECT pg_temp.pz('Ej', 'Hoja', 2);
SELECT pg_temp.mu('Ej', 'Hoja', 1, 'elige_vendedor', 'Vidrio', '{"ancho": "ancho", "alto": "alto"}');
SELECT pg_temp.op('Ej', 'Ej.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.op('Ej', 'Ej.Hoja.Vidrio', 2, 'DVH');
SELECT pg_temp.pz('Ej', 'Mosquitero', 3, '{"opcional": true}');
SELECT pg_temp.un('Ej', 'Mosquitero', 1, 'Tela', '{"ancho": "ancho", "alto": "alto"}');
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'Ej', jsonb_build_object(
  'variable_id', pg_temp.id('Ej.ancho'), 'condicion', 'ancho > 4000', 'mensaje', 'Demasiado ancho', 'bloquea', true));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Ej', jsonb_build_object('nombre', 'base', 'entrada', pg_temp.e('{}')));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Ej', jsonb_build_object('nombre', 'negro', 'entrada', pg_temp.color('Negro')));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Ej', jsonb_build_object('nombre', 'grande', 'entrada', pg_temp.e('{}', 4500)));
SELECT pg_temp.publicar('Ej');

-- Pano: $20.000 de vidrio. Puerta: $10.000 sin vidrio. Hecho: $1.000 de manija y $1.000 de un servicio fijo.
SELECT pg_temp.ver('Pano');
SELECT pg_temp.pz('Pano', 'Unica', 1);
SELECT pg_temp.un('Pano', 'Unica', 1, 'Float2', '{"ancho": "1000", "alto": "1000"}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Pano', '{"nombre": "base"}');
SELECT pg_temp.publicar('Pano');

SELECT pg_temp.chico('Puerta', 'Manija', '10');
SELECT pg_temp.publicar('Puerta');

SELECT pg_temp.chico('Hecho', 'Manija');
SELECT pg_temp.un('Hecho', 'Unica', 2, 'Soldado', '{"cantidad": "2"}');
SELECT pg_temp.publicar('Hecho');

-- Neg: con ancho 1000 la medida da −200 mm. El caso prueba con 2000, así que se puede enviar.
SELECT pg_temp.ver('Neg');
SELECT pg_temp.en('Neg', 'ancho', 1, 100, 5000);
SELECT pg_temp.pz('Neg', 'Unica', 1);
SELECT pg_temp.un('Neg', 'Unica', 1, 'PerfilLibre', '{"medida": "ancho − 1200"}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Neg', '{"nombre": "base", "entrada": {"variables": {"ancho": 2000}}}');
SELECT pg_temp.publicar('Neg');

SELECT pg_temp.chico('Nuevo1', 'Nuevo');
SELECT pg_temp.publicar('Nuevo1');
SELECT pg_temp.chico('Viejo', 'Antiguo');
SELECT pg_temp.publicar('Viejo');
SELECT pg_temp.chico('Viejo2', 'Antiguo2');
SELECT pg_temp.publicar('Viejo2');

-- ============================================================
-- 1. Quién puede pedirlo
-- ============================================================
SELECT pg_temp.n('01 precio: Carlos', 200000, pg_temp.pr('Ej'));
SELECT pg_temp.caso('01 precio: ' || u, '42501', pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'ARS', '{}', u))
FROM unnest(ARRAY['Lucia','Ana','Rodrigo','Juan']) AS u;
SELECT pg_temp.caso('01 detalle: ' || u, '42501', pg_temp.de('Ej', '{precio}', pg_temp.e('{}'), 'ARS', '{}', now(), u))
FROM unnest(ARRAY['Lucia','Ana','Rodrigo','Juan']) AS u;
SELECT pg_temp.caso('01 mínimos: ' || u, '42501', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 1)), 'ARS', u))
FROM unnest(ARRAY['Lucia','Ana','Rodrigo','Juan']) AS u;
SELECT pg_temp.caso('01 referencia: ' || u, '42501',
  pg_temp.consultar('SELECT count(*)::text FROM catalogo_precios_referencia()', u))
FROM unnest(ARRAY['Lucia','Ana','Rodrigo','Juan']) AS u;
SELECT pg_temp.caso('01 sin EXECUTE: ' || f, 'false',
  has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_precio_redondear(numeric,moneda)',
  'catalogo_precio_calcular(uuid,jsonb,uuid[],moneda,timestamptz)', 'catalogo_precio_venta(uuid,jsonb,uuid[],moneda)']) AS f;
SELECT pg_temp.caso('01 con EXECUTE: ' || f, 'true',
  has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_precio(uuid,jsonb,uuid[],moneda)', 'catalogo_precio_detalle(uuid,jsonb,uuid[],moneda,timestamptz)',
  'catalogo_precio_minimos(jsonb,moneda)', 'catalogo_precios_referencia(moneda,timestamptz,timestamptz)',
  'catalogo_precio_convertir(numeric,moneda,moneda,timestamptz)']) AS f;
SELECT pg_temp.caso('01 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_precio(uuid,jsonb,uuid[],moneda)', 'catalogo_precio_detalle(uuid,jsonb,uuid[],moneda,timestamptz)',
  'catalogo_precio_minimos(jsonb,moneda)', 'catalogo_precios_referencia(moneda,timestamptz,timestamptz)',
  'catalogo_precio_calcular(uuid,jsonb,uuid[],moneda,timestamptz)', 'catalogo_precio_venta(uuid,jsonb,uuid[],moneda)']) AS f;

-- ============================================================
-- 2. El costo del despiece y la moneda
-- ============================================================
SELECT pg_temp.caso('02 el vendedor recibe solo esto', 'mensaje,mensajes,precio', pg_temp.consultar(format(
  $q$SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(catalogo_precio(%L, %L::jsonb)) k$q$,
  pg_temp.paquete('Ej'), pg_temp.e('{}')), 'Carlos'));
SELECT pg_temp.caso('02 sin mensaje', NULL, pg_temp.pr('Ej', '{mensaje}'));
SELECT pg_temp.caso('02 sin mensajes', '[]', pg_temp.pr('Ej', '{mensajes}'));

SELECT pg_temp.n('02 mm por metro y m2: 2 m × $70.000 + 1 m2 × $60.000', 200000, pg_temp.pr('Ej'));
SELECT pg_temp.n('02 otras medidas: 3 m y 1,8 m2', 318000, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}', 1500, 1200)));
SELECT pg_temp.n('02 otra opción', 240000, pg_temp.pr('Ej', '{precio}', pg_temp.vidrio('DVH')));
SELECT pg_temp.n('02 con la pieza opcional', 205000, pg_temp.pr('Ej', '{precio}', pg_temp.e('{"piezas": {"Mosquitero": true}}')));
SELECT pg_temp.n('02 en u', 10000, pg_temp.pr('Puerta'));
SELECT pg_temp.n('02 con un servicio fijo', 2000, pg_temp.pr('Hecho'));
SELECT pg_temp.n('02 otro color, con su costo en USD', 205000, pg_temp.pr('Ej', '{precio}', pg_temp.color('Negro')));

SELECT pg_temp.n('02 en USD, a 2 decimales', 137.93, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'USD_OFICIAL'));
SELECT pg_temp.n('02 en blue, con su dólar', 133.33, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'USD_BLUE'));
SELECT pg_temp.n('02 en EUR, a 2 decimales', 117.65, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'EUR'));
SELECT pg_temp.n('02 USD a USD no cambia', 141.38, pg_temp.pr('Ej', '{precio}', pg_temp.color('Negro'), 'USD_OFICIAL'));
SELECT pg_temp.n('02 USD a blue pasa por el peso', 136.67, pg_temp.pr('Ej', '{precio}', pg_temp.color('Negro'), 'USD_BLUE'));
SELECT pg_temp.caso('02 sin moneda, la principal', monedas_principal_actual()::text, pg_temp.consultar(format(
  $q$SELECT catalogo_precio_detalle(%L, %L::jsonb)->>'moneda'$q$, pg_temp.id('Ej'), pg_temp.e('{}')), 'Carlos'));
SELECT pg_temp.caso('02 sin moneda, también da número', 'true', pg_temp.consultar(format(
  $q$SELECT (catalogo_precio(%L, %L::jsonb)->>'precio' IS NOT NULL)::text$q$, pg_temp.paquete('Ej'), pg_temp.e('{}')), 'Carlos'));

-- ============================================================
-- 3. Los servicios en %: el ejemplo de decisiones/catalogo/precio.md
-- ============================================================
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY['Vidrios']);
SELECT pg_temp.serv('Manipulacion', 5, 1, ARRAY['Vidrios']);
SELECT pg_temp.serv('Comercializacion', 10, 1, '{}', 15000, 'ARS', 'paquete');
SELECT pg_temp.serv('Transicion', 4, 2);
SELECT pg_temp.serv('IIBB', 3, 3);

SELECT pg_temp.n('03 costo del despiece', 200000, pg_temp.de('Ej', '{costo_despiece}'));
SELECT pg_temp.caso('03 primero el paso, después el nombre', 'Comercializacion,Garantia,Manipulacion,Transicion,IIBB', pg_temp.consultar(format(
  $q$SELECT string_agg(replace(s.x->>'nombre', 'Zqx163 ', ''), ',' ORDER BY s.i)
     FROM jsonb_array_elements(catalogo_precio_detalle(%L, %L::jsonb, '{}', 'ARS')->'servicios') WITH ORDINALITY s(x, i)$q$,
  pg_temp.id('Ej'), pg_temp.e('{}')), 'Carlos'));
SELECT pg_temp.n('03 comercialización: base', 200000, pg_temp.de('Ej', '{servicios,0,base}'));
SELECT pg_temp.n('03 comercialización: monto', 20000, pg_temp.de('Ej', '{servicios,0,monto}'));
SELECT pg_temp.n('03 garantía: base, solo los vidrios', 60000, pg_temp.de('Ej', '{servicios,1,base}'));
SELECT pg_temp.n('03 garantía: monto', 3000, pg_temp.de('Ej', '{servicios,1,monto}'));
SELECT pg_temp.caso('03 garantía: nombre de sus categorías', '["Zqx163 Vidrios"]', pg_temp.de('Ej', '{servicios,1,categorias}'));
SELECT pg_temp.n('03 manipulación: monto', 3000, pg_temp.de('Ej', '{servicios,2,monto}'));
SELECT pg_temp.n('03 subtotal', 226000, pg_temp.de('Ej', '{subtotal}'));
SELECT pg_temp.n('03 transición: base', 226000, pg_temp.de('Ej', '{servicios,3,base}'));
SELECT pg_temp.n('03 transición: monto', 9040, pg_temp.de('Ej', '{servicios,3,monto}'));
SELECT pg_temp.n('03 IIBB: base, el precio', 235040 / 0.97, pg_temp.de('Ej', '{servicios,4,base}'));
SELECT pg_temp.n('03 IIBB: monto', 235040 / 0.97 * 0.03, pg_temp.de('Ej', '{servicios,4,monto}'));
SELECT pg_temp.n('03 precio exacto', 235040 / 0.97, pg_temp.de('Ej', '{precio_exacto}'));
SELECT pg_temp.n('03 precio de venta, redondeado', 242309, pg_temp.de('Ej', '{precio}'));
SELECT pg_temp.n('03 lo mismo para el vendedor', 242309, pg_temp.pr('Ej'));
SELECT pg_temp.n('03 en USD, los mínimos también', 167.11, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'USD_OFICIAL'));
SELECT pg_temp.caso('03 sin razones', '[]', pg_temp.de('Ej', '{sin_precio}'));

SELECT pg_temp.caso('03 sin vidrios la garantía no aplica', 'false', pg_temp.de('Puerta', '{servicios,1,aplica}'));
SELECT pg_temp.n('03 sin vidrios la garantía da 0', 0, pg_temp.de('Puerta', '{servicios,1,monto}'));
SELECT pg_temp.n('03 mínimo por paquete: pisa el %', 15000, pg_temp.de('Puerta', '{servicios,0,monto}'));
SELECT pg_temp.n('03 mínimo por paquete: entra al subtotal', 25000, pg_temp.de('Puerta', '{subtotal}'));
SELECT pg_temp.n('03 mínimo por paquete: precio', 26804, pg_temp.pr('Puerta'));
SELECT pg_temp.n('03 mínimo por encima: no lo pisa', 20000, pg_temp.de('Ej', '{servicios,0,monto}'));
SELECT pg_temp.caso('03 mínimo como se cargó', 'ARS', pg_temp.de('Ej', '{servicios,0,minimo_moneda}'));

-- Lo que cada pieza suma y lo que cada fila cuesta.
SELECT pg_temp.n('03 subtotal de la pieza Marco', 140000, pg_temp.de('Ej', '{piezas,0,subtotal}'));
SELECT pg_temp.n('03 subtotal de la pieza Hoja', 60000, pg_temp.de('Ej', '{piezas,1,subtotal}'));
SELECT pg_temp.n('03 fila: costo como se cargó', 70000, pg_temp.de('Ej', '{filas,0,costo}'));
SELECT pg_temp.caso('03 fila: su moneda', 'ARS', pg_temp.de('Ej', '{filas,0,costo_moneda}'));
SELECT pg_temp.n('03 fila: importe', 140000, pg_temp.de('Ej', '{filas,0,importe}'));
SELECT pg_temp.caso('03 fila: desde cuándo', 'true', (pg_temp.de('Ej', '{filas,0,costo_desde}')::timestamptz = pg_temp.hace(100))::text);
SELECT pg_temp.n('03 fila en USD: como se cargó', 50, pg_temp.de('Ej', '{filas,0,costo}', pg_temp.color('Negro')));
SELECT pg_temp.caso('03 fila en USD: su moneda', 'USD_OFICIAL', pg_temp.de('Ej', '{filas,0,costo_moneda}', pg_temp.color('Negro')));
SELECT pg_temp.n('03 fila en USD: importe en pesos', 145000, pg_temp.de('Ej', '{filas,0,importe}', pg_temp.color('Negro')));
SELECT pg_temp.caso('03 el detalle sigue trayendo el despiece', 'Zqx163 PerfilMarco', pg_temp.de('Ej', '{filas,0,insumo}'));

-- Una categoría se cobra en toda pieza donde esté, y también las de servicio.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('SobrePerfiles', 10, 1, ARRAY['Perfiles']);
SELECT pg_temp.n('03 categoría en dos piezas', 145000, pg_temp.de('Ej', '{servicios,0,base}', pg_temp.e('{"piezas": {"Mosquitero": true}}')));
SELECT pg_temp.n('03 categoría en otra moneda, convertida', 145000, pg_temp.de('Ej', '{servicios,0,base}', pg_temp.color('Negro')));
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('SobreManos', 10, 1, ARRAY['Manos']);
SELECT pg_temp.n('03 categoría de servicio: base', 1000, pg_temp.de('Hecho', '{servicios,0,base}'));
SELECT pg_temp.n('03 categoría de servicio: precio', 2100, pg_temp.pr('Hecho'));

-- Los opcionales: sin elegir no cuentan, y sacarlos solo cambia lo que se calcula después.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Transicion', 4, 2);
SELECT pg_temp.serv('IIBB', 3, 3);
SELECT pg_temp.serv('Seguro', 2, 1, '{}', NULL, NULL, NULL, true);
SELECT pg_temp.serv('Recargo', 5, 2, '{}', NULL, NULL, NULL, true);
SELECT pg_temp.serv('Tasa', 1, 3, '{}', NULL, NULL, NULL, true);
SELECT pg_temp.n('03 sin elegir ninguno', 208000 / 0.97, pg_temp.de('Ej', '{precio_exacto}'));
SELECT pg_temp.caso('03 sin elegir: se lista y no aplica', 'false', pg_temp.de('Ej', '{servicios,0,aplica}'));
SELECT pg_temp.caso('03 sin elegir: dice que es opcional', 'true', pg_temp.de('Ej', '{servicios,0,opcional}'));
SELECT pg_temp.n('03 opcional del paso 1', 204000 * 1.04 / 0.97, pg_temp.de('Ej', '{precio_exacto}', pg_temp.e('{}'), 'ARS', ARRAY['Seguro']));
SELECT pg_temp.n('03 opcional del paso 2', 218000 / 0.97, pg_temp.de('Ej', '{precio_exacto}', pg_temp.e('{}'), 'ARS', ARRAY['Recargo']));
SELECT pg_temp.n('03 opcional del paso 3: se despejan juntos', 208000 / 0.96, pg_temp.de('Ej', '{precio_exacto}', pg_temp.e('{}'), 'ARS', ARRAY['Tasa']));
SELECT pg_temp.n('03 los tres', (204000 + 204000 * 0.09) / 0.96, pg_temp.de('Ej', '{precio_exacto}', pg_temp.e('{}'), 'ARS', ARRAY['Seguro', 'Recargo', 'Tasa']));
SELECT pg_temp.n('03 para el vendedor también', 214433, pg_temp.pr('Ej'));
SELECT pg_temp.n('03 para el vendedor, elegido', 218722, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'ARS', ARRAY['Seguro']));

-- Los mínimos: en otra moneda, en el paso 2, y el de presupuesto que no entra al precio.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('MinUsd', 10, 1, '{}', 20, 'USD_OFICIAL', 'paquete');
SELECT pg_temp.n('03 mínimo en USD: convertido', 29000, pg_temp.de('Puerta', '{servicios,0,minimo_convertido}'));
SELECT pg_temp.n('03 mínimo en USD: como se cargó', 20, pg_temp.de('Puerta', '{servicios,0,minimo}'));
SELECT pg_temp.n('03 mínimo en USD: precio', 39000, pg_temp.pr('Puerta'));
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('MinPaso2', 4, 2, '{}', 9000, 'ARS', 'paquete');
SELECT pg_temp.n('03 mínimo del paso 2', 209000, pg_temp.pr('Ej'));
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('MinPresu', 10, 1, '{}', 50000, 'ARS', 'presupuesto');
SELECT pg_temp.n('03 mínimo por presupuesto: el ítem no lo paga', 11000, pg_temp.pr('Puerta'));
SELECT pg_temp.n('03 mínimo por presupuesto: se informa', 50000, pg_temp.de('Puerta', '{servicios,0,minimo_convertido}'));
SELECT pg_temp.caso('03 mínimo por presupuesto: dice cómo', 'presupuesto', pg_temp.de('Puerta', '{servicios,0,minimo_por}'));

-- Un servicio de baja no se cobra.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Baja', 10, 1);
SELECT pg_temp.serv('Baja', 10, 1, '{}', NULL, NULL, NULL, false, pg_temp.hace(5), true);
SELECT pg_temp.n('03 de baja hoy', 200000, pg_temp.pr('Ej'));
SELECT pg_temp.n('03 pero antes de la baja sí', 220000, pg_temp.de('Ej', '{precio}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50)));
SELECT pg_temp.sin_servicios();

-- ============================================================
-- 4. Cuando no da número
-- ============================================================
SELECT pg_temp.caso('04 bloqueo: sin precio', NULL, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}', 4500)));
SELECT pg_temp.caso('04 bloqueo: sin mensaje general', NULL, pg_temp.pr('Ej', '{mensaje}', pg_temp.e('{}', 4500)));
SELECT pg_temp.caso('04 bloqueo: el vendedor lee por qué', 'Demasiado ancho', pg_temp.pr('Ej', '{mensajes,0,mensaje}', pg_temp.e('{}', 4500)));
SELECT pg_temp.caso('04 bloqueo: detalle sin precio', NULL, pg_temp.de('Ej', '{precio}', pg_temp.e('{}', 4500)));
SELECT pg_temp.caso('04 bloqueo: detalle sin exacto', NULL, pg_temp.de('Ej', '{precio_exacto}', pg_temp.e('{}', 4500)));
SELECT pg_temp.caso('04 bloqueo: dice por qué', 'Demasiado ancho', pg_temp.de('Ej', '{sin_precio,0}', pg_temp.e('{}', 4500)));
SELECT pg_temp.n('04 bloqueo: el importe sale igual', 630000, pg_temp.de('Ej', '{filas,0,importe}', pg_temp.e('{}', 4500)));

SELECT pg_temp.caso('04 no se puede calcular: sin precio', NULL, pg_temp.pr('Neg'));
SELECT pg_temp.caso('04 no se puede calcular: el vendedor', 'No se puede calcular con estas medidas', pg_temp.pr('Neg', '{mensaje}'));
SELECT pg_temp.caso('04 no se puede calcular: nunca los errores', NULL, pg_temp.pr('Neg', '{errores}'));
SELECT pg_temp.caso('04 no se puede calcular: el gerente lee cuál', 'Zqx163 PerfilLibre: la medida dio −200 mm', pg_temp.de('Neg', '{sin_precio,0}'));
SELECT pg_temp.caso('04 no se puede calcular: sin servicios', '[]', pg_temp.de('Neg', '{servicios}'));
SELECT pg_temp.n('04 con otra medida sí', 800, pg_temp.pr('Neg', '{precio}', pg_temp.e('{}', 2000)));

SELECT pg_temp.caso('04 un color que no está: mensaje', 'No se puede calcular con estas medidas', pg_temp.pr('Ej', '{mensaje}',
  pg_temp.e(jsonb_build_object('color', gen_random_uuid()))));
SELECT pg_temp.caso('04 entrada con otra forma', 'CA017', pg_temp.pr('Ej', '{precio}', '{"otra": 1}'));
SELECT pg_temp.caso('04 detalle: entrada con otra forma', 'CA017', pg_temp.de('Ej', '{precio}', '{"otra": 1}'));
SELECT pg_temp.caso('04 detalle: versión que no existe', 'CA016', pg_temp.consultar(format(
  $q$SELECT catalogo_precio_detalle(%L)::text$q$, gen_random_uuid()), 'Carlos'));

-- Lo que no está a la venta.
SELECT pg_temp.caso('04 paquete que no existe: sin precio', NULL, pg_temp.consultar(format(
  $q$SELECT catalogo_precio(%L)->>'precio'$q$, gen_random_uuid()), 'Carlos'));
SELECT pg_temp.caso('04 paquete que no existe: mensaje', 'Este paquete no está a la venta', pg_temp.consultar(format(
  $q$SELECT catalogo_precio(%L)->>'mensaje'$q$, gen_random_uuid()), 'Carlos'));

SELECT pg_temp.chico('Borrador', 'Manija');
SELECT pg_temp.caso('04 borrador: no está a la venta', 'Este paquete no está a la venta', pg_temp.pr('Borrador', '{mensaje}'));
SELECT pg_temp.n('04 borrador: el gerente lo ve', 1000, pg_temp.de('Borrador', '{precio}'));

SELECT pg_temp.caso('04 baja del paquete', 'ok', pg_temp.intentar(format('UPDATE catalogo_paquetes SET activo = false WHERE id = %L', pg_temp.paquete('Puerta')), 'Lucia'));
SELECT pg_temp.caso('04 de baja: no está a la venta', 'Este paquete no está a la venta', pg_temp.pr('Puerta', '{mensaje}'));
SELECT pg_temp.n('04 de baja: el gerente lo ve', 10000, pg_temp.de('Puerta', '{precio}'));
SELECT pg_temp.caso('04 reactivar el paquete', 'ok', pg_temp.intentar(format('UPDATE catalogo_paquetes SET activo = true WHERE id = %L', pg_temp.paquete('Puerta')), 'Lucia'));
SELECT pg_temp.n('04 reactivado', 10000, pg_temp.pr('Puerta'));

-- La versión no la elige quien llama: la publicada, también con otra en revisión.
SELECT pg_temp.chico('Versiones', 'Manija');
SELECT pg_temp.publicar('Versiones');
SELECT pg_temp.crear('Versiones2', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('Versiones')));
UPDATE catalogo_materiales SET cantidad = '3' WHERE version_id = pg_temp.id('Versiones2');
SELECT pg_temp.n('04 con un borrador: la publicada', 1000, pg_temp.pr('Versiones'));
SELECT pg_temp.caso('04 enviar la nueva', 'ok', pg_temp.fn('enviar', 'Versiones2', 'Lucia'));
SELECT pg_temp.n('04 en revisión: la publicada', 1000, pg_temp.pr('Versiones'));
SELECT pg_temp.n('04 en revisión: el gerente ve la nueva', 3000, pg_temp.de('Versiones2', '{precio}'));
SELECT pg_temp.caso('04 aprobar la nueva', 'ok', pg_temp.fn('aprobar', 'Versiones2', 'Carlos'));
SELECT pg_temp.n('04 aprobada: la nueva', 3000, pg_temp.pr('Versiones'));
SELECT pg_temp.n('04 obsoleta: el gerente ve la vieja', 1000, pg_temp.de('Versiones', '{precio}'));

-- Lo que ya no se ofrece no da número ni se saca solo.
SELECT pg_temp.caso('04 baja del DVH', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = false WHERE id = %s', pg_temp.l('DVH')), 'Lucia'));
SELECT pg_temp.caso('04 opción fuera: sin precio', NULL, pg_temp.pr('Ej', '{precio}', pg_temp.vidrio('DVH')));
SELECT pg_temp.caso('04 opción fuera: dice cuál', 'Ya no se ofrece: Zqx163 DVH', pg_temp.pr('Ej', '{mensaje}', pg_temp.vidrio('DVH')));
SELECT pg_temp.n('04 opción fuera: las otras sí', 200000, pg_temp.pr('Ej', '{precio}', pg_temp.vidrio('Float')));
SELECT pg_temp.n('04 opción fuera: el gerente la ve', 240000, pg_temp.de('Ej', '{precio}', pg_temp.vidrio('DVH')));
SELECT pg_temp.caso('04 reactivar el DVH', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = true WHERE id = %s', pg_temp.l('DVH')), 'Lucia'));
SELECT pg_temp.n('04 opción de vuelta', 240000, pg_temp.pr('Ej', '{precio}', pg_temp.vidrio('DVH')));

SELECT pg_temp.caso('04 baja de la Tela', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = false WHERE id = %s', pg_temp.l('Tela')), 'Lucia'));
SELECT pg_temp.caso('04 pieza fuera: dice cuál', 'Ya no se ofrece: Mosquitero', pg_temp.pr('Ej', '{mensaje}', pg_temp.e('{"piezas": {"Mosquitero": true}}')));
SELECT pg_temp.n('04 pieza fuera: sin ella sí', 200000, pg_temp.pr('Ej', '{precio}', pg_temp.e('{"piezas": {"Mosquitero": false}}')));
SELECT pg_temp.caso('04 reactivar la Tela', 'ok', pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = true WHERE id = %s', pg_temp.l('Tela')), 'Lucia'));

SELECT pg_temp.caso('04 baja del Negro del perfil', 'ok', pg_temp.intentar(format(
  'UPDATE catalogo_variantes SET activo = false WHERE insumo_id = %s AND color_id = %s', pg_temp.l('PerfilMarco'), pg_temp.l('Negro')), 'Lucia'));
SELECT pg_temp.caso('04 color fuera: sin precio', NULL, pg_temp.pr('Ej', '{precio}', pg_temp.color('Negro')));
SELECT pg_temp.caso('04 color fuera: mensaje', 'Este paquete no se ofrece en este color', pg_temp.pr('Ej', '{mensaje}', pg_temp.color('Negro')));
SELECT pg_temp.n('04 color fuera: el otro sí', 200000, pg_temp.pr('Ej', '{precio}', pg_temp.color('Blanco')));
SELECT pg_temp.caso('04 reactivar el Negro', 'ok', pg_temp.intentar(format(
  'UPDATE catalogo_variantes SET activo = true WHERE insumo_id = %s AND color_id = %s', pg_temp.l('PerfilMarco'), pg_temp.l('Negro')), 'Lucia'));

-- Un opcional elegido que ya no está no se saca solo.
SELECT pg_temp.serv('NoOpcional', 10, 1);
SELECT pg_temp.serv('OpcBaja', 10, 1, '{}', NULL, NULL, NULL, true);
SELECT pg_temp.serv('OpcBaja', 10, 1, '{}', NULL, NULL, NULL, true, pg_temp.hace(5), true);
SELECT pg_temp.caso('04 elegir uno que no es opcional: sin precio', NULL, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'ARS', ARRAY['NoOpcional']));
SELECT pg_temp.caso('04 elegir uno que no es opcional: mensaje', 'Un servicio opcional elegido ya no está', pg_temp.pr('Ej', '{mensaje}', pg_temp.e('{}'), 'ARS', ARRAY['NoOpcional']));
SELECT pg_temp.caso('04 elegir uno de baja: sin precio', NULL, pg_temp.pr('Ej', '{precio}', pg_temp.e('{}'), 'ARS', ARRAY['OpcBaja']));
SELECT pg_temp.caso('04 elegir uno de baja: el gerente', 'Un servicio opcional elegido no está a esa fecha', pg_temp.de('Ej', '{sin_precio,0}', pg_temp.e('{}'), 'ARS', ARRAY['OpcBaja']));
SELECT pg_temp.n('04 elegir uno de baja: antes de la baja sí', 240000, pg_temp.de('Ej', '{precio}', pg_temp.e('{}'), 'ARS', ARRAY['OpcBaja'], pg_temp.hace(50)));
SELECT pg_temp.caso('04 opcional que no existe', 'Un servicio opcional elegido ya no está', pg_temp.consultar(format(
  $q$SELECT catalogo_precio(%L, %L::jsonb, ARRAY[%L]::uuid[], 'ARS')->>'mensaje'$q$, pg_temp.paquete('Ej'), pg_temp.e('{}'), gen_random_uuid()), 'Carlos'));
SELECT pg_temp.sin_servicios();

-- sql/172: sin ninguna fila no hay precio, ni 0.
SELECT pg_temp.ver('Cond');
SELECT pg_temp.en('Cond', 'ancho', 1, 100, 5000);
SELECT pg_temp.pz('Cond', 'Unica', 1);
SELECT pg_temp.un('Cond', 'Unica', 1, 'Manija', '{"cantidad": "si ancho > 1000 entonces 1 si no 0"}');
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'Cond', jsonb_build_object(
  'variable_id', pg_temp.id('Cond.ancho'), 'condicion', 'ancho < 200', 'mensaje', 'Muy angosto', 'bloquea', true));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Cond', '{"nombre": "base", "entrada": {"variables": {"ancho": 1500}}}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'Cond', '{"nombre": "angosto", "entrada": {"variables": {"ancho": 500}}}');
SELECT pg_temp.publicar('Cond');
SELECT pg_temp.caso('04 sin filas: sin precio', NULL, pg_temp.pr('Cond', '{precio}', pg_temp.e('{}', 500)));
SELECT pg_temp.caso('04 sin filas: el vendedor lee por qué', 'Con estas medidas y elecciones el paquete no lleva nada', pg_temp.pr('Cond', '{mensaje}', pg_temp.e('{}', 500)));
SELECT pg_temp.caso('04 sin filas: el gerente también', 'Con estas medidas y elecciones el paquete no lleva nada', pg_temp.de('Cond', '{sin_precio,0}', pg_temp.e('{}', 500)));
SELECT pg_temp.caso('04 sin filas: sin exacto', NULL, pg_temp.de('Cond', '{precio_exacto}', pg_temp.e('{}', 500)));
SELECT pg_temp.caso('04 sin filas: el despiece se pudo calcular', 'true', pg_temp.de('Cond', '{calculable}', pg_temp.e('{}', 500)));
SELECT pg_temp.n('04 con otra medida sí', 1000, pg_temp.pr('Cond', '{precio}', pg_temp.e('{}', 1500)));
SELECT pg_temp.caso('04 sin filas y con bloqueo: sin mensaje general', NULL, pg_temp.pr('Cond', '{mensaje}', pg_temp.e('{}', 150)));
SELECT pg_temp.caso('04 sin filas y con bloqueo: solo el bloqueo', '["Muy angosto"]', pg_temp.de('Cond', '{sin_precio}', pg_temp.e('{}', 150)));

SELECT pg_temp.ver('SoloOpc');
SELECT pg_temp.pz('SoloOpc', 'Opc', 1, '{"opcional": true}');
SELECT pg_temp.un('SoloOpc', 'Opc', 1, 'Manija');
SELECT pg_temp.caso('04 solo una pieza sin elegir: sin precio', 'Con estas medidas y elecciones el paquete no lleva nada', pg_temp.de('SoloOpc', '{mensaje}'));
SELECT pg_temp.n('04 con la pieza elegida sí', 1000, pg_temp.de('SoloOpc', '{precio}', pg_temp.e('{"piezas": {"Opc": true}}')));

-- ============================================================
-- 5. Los mínimos por presupuesto: el ejemplo de decisiones/catalogo/precio.md
-- ============================================================
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY['Vidrios'], 10000, 'ARS', 'presupuesto');

SELECT pg_temp.caso('05 no se alcanza: $10.000 − $9.000', 'Garantia=1000', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 2), pg_temp.it('Pano', 3), pg_temp.it('Puerta', 1))));
SELECT pg_temp.caso('05 el renglón dice qué servicio', pg_temp.id('Garantia')::text, pg_temp.consultar(format(
  'SELECT m.porcentaje_id::text FROM catalogo_precio_minimos(%L::jsonb, %L::moneda) m',
  jsonb_build_array(pg_temp.it('Ej', 2), pg_temp.it('Pano', 3)), 'ARS'), 'Carlos'));
SELECT pg_temp.caso('05 se alcanza justo', 'nada', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 2), pg_temp.it('Pano', 4))));
SELECT pg_temp.caso('05 se pasa', 'nada', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 4))));
SELECT pg_temp.caso('05 no aplica: no hay mínimo', 'nada', pg_temp.mi(jsonb_build_array(pg_temp.it('Puerta', 5))));
SELECT pg_temp.caso('05 sin ítems', 'nada', pg_temp.mi('[]'));
SELECT pg_temp.caso('05 cantidad con decimales', 'Garantia=5500', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 1.5))));
SELECT pg_temp.caso('05 un ítem sin precio no cuenta', 'Garantia=7000', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 1), pg_temp.it('Ej', 1, jsonb_build_object('entrada', pg_temp.e('{}', 4500))))));
SELECT pg_temp.caso('05 un ítem sin filas tampoco', 'Garantia=7000', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 1), pg_temp.it('Cond', 1, jsonb_build_object('entrada', pg_temp.e('{}', 500))))));
SELECT pg_temp.caso('05 uno que no está a la venta no cuenta', 'Garantia=7000', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 1), jsonb_build_object('paquete_id', gen_random_uuid(), 'cantidad', 1))));
SELECT pg_temp.caso('05 sin entrada ni opcionales', 'nada', pg_temp.mi(jsonb_build_array(
  jsonb_build_object('paquete_id', pg_temp.paquete('Puerta'), 'cantidad', 1))));
SELECT pg_temp.caso('05 ítem sin cantidad', 'CA017', pg_temp.mi(jsonb_build_array(jsonb_build_object('paquete_id', pg_temp.paquete('Ej')))));
SELECT pg_temp.caso('05 ítem con cantidad 0', 'CA017', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 0))));
SELECT pg_temp.caso('05 ítem sin paquete', 'CA017', pg_temp.mi('[{"cantidad": 1}]'));
SELECT pg_temp.caso('05 ítems que no son una lista', '22023', pg_temp.mi('{"cantidad": 1}'));

SELECT pg_temp.caso('05 en otra moneda, redondeado', 'Garantia=0.69', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 2), pg_temp.it('Pano', 3)), 'USD_OFICIAL'));

-- Una diferencia que redondeada es 0 no es un renglón.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Justo', 5, 1, ARRAY['Vidrios'], 10000.4, 'ARS', 'presupuesto');
SELECT pg_temp.caso('05 redondeado da 0: sin renglón', 'nada', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 2), pg_temp.it('Pano', 4))));

-- El mínimo en otra moneda.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY['Vidrios'], 10, 'USD_OFICIAL', 'presupuesto');
SELECT pg_temp.caso('05 mínimo en USD, en pesos', 'Garantia=5500', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 3))));

-- La diferencia pasa por los pasos siguientes.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY['Vidrios'], 10000, 'ARS', 'presupuesto');
SELECT pg_temp.serv('Transicion', 4, 2);
SELECT pg_temp.serv('IIBB', 3, 3);
SELECT pg_temp.caso('05 con los pasos siguientes: 1.000 × 1,04 / 0,97', 'Garantia=1072', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 2), pg_temp.it('Pano', 3))));
SELECT pg_temp.caso('05 con los pasos siguientes, en USD', 'Garantia=0.74', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 2), pg_temp.it('Pano', 3)), 'USD_OFICIAL'));

-- De los opcionales, lo que eligieron todos los ítems que cuentan para ese mínimo.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY['Vidrios'], 10000, 'ARS', 'presupuesto');
SELECT pg_temp.serv('Recargo', 10, 2, '{}', NULL, NULL, NULL, true);
SELECT pg_temp.caso('05 opcional que no eligió nadie', 'Garantia=1000', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 2), pg_temp.it('Pano', 3))));
SELECT pg_temp.caso('05 opcional que eligió uno solo', 'Garantia=1000', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 2, pg_temp.con_opc('Recargo')), pg_temp.it('Pano', 3))));
SELECT pg_temp.caso('05 opcional que eligieron todos', 'Garantia=1100', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 2, pg_temp.con_opc('Recargo')), pg_temp.it('Pano', 3, pg_temp.con_opc('Recargo')))));
SELECT pg_temp.caso('05 quien no cuenta para el mínimo no importa', 'Garantia=1100', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 2, pg_temp.con_opc('Recargo')), pg_temp.it('Pano', 3, pg_temp.con_opc('Recargo')), pg_temp.it('Puerta', 1))));

SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('GarantiaOpc', 5, 1, ARRAY['Vidrios'], 10000, 'ARS', 'presupuesto', true);
SELECT pg_temp.caso('05 el mínimo de un opcional sin elegir', 'nada', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 2))));
SELECT pg_temp.caso('05 solo cuenta donde se eligió', 'GarantiaOpc=7000', pg_temp.mi(jsonb_build_array(
  pg_temp.it('Ej', 1, pg_temp.con_opc('GarantiaOpc')), pg_temp.it('Ej', 3))));

-- El mínimo del paso 2, y lo que le deja el renglón de un paso 1.
SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Transicion', 4, 2, '{}', 50000, 'ARS', 'presupuesto');
SELECT pg_temp.serv('IIBB', 3, 3);
SELECT pg_temp.caso('05 mínimo del paso 2: solo le queda el 3', 'Transicion=43299', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 1))));

SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY['Vidrios'], 10000, 'ARS', 'presupuesto');
SELECT pg_temp.serv('Transicion', 4, 2, '{}', 8300, 'ARS', 'presupuesto');
SELECT pg_temp.caso('05 el renglón del paso 1 alcanza para el mínimo del 2', 'Garantia=7280', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 1))));

SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY['Vidrios'], 10000, 'ARS', 'presupuesto');
SELECT pg_temp.serv('Transicion', 4, 2, '{}', 8500, 'ARS', 'presupuesto');
SELECT pg_temp.caso('05 no alcanza: dos renglones, el paso primero', 'Garantia=7280 | Transicion=100', pg_temp.mi(jsonb_build_array(pg_temp.it('Ej', 1))));

SELECT pg_temp.sin_servicios();
SELECT pg_temp.serv('Comercial', 10, 1, '{}', 50000, 'ARS', 'paquete');
SELECT pg_temp.caso('05 un mínimo por paquete no es un renglón', 'nada', pg_temp.mi(jsonb_build_array(pg_temp.it('Puerta', 1))));
SELECT pg_temp.sin_servicios();

-- ============================================================
-- 6. A una fecha: lo que valía entonces
-- ============================================================
SELECT pg_temp.costo('Float', NULL, 66000, 'ARS', pg_temp.hace(10));
SELECT pg_temp.n('06 el vendedor, hoy', 206000, pg_temp.pr('Ej'));
SELECT pg_temp.n('06 el detalle de hoy', 206000, pg_temp.de('Ej', '{precio}'));
SELECT pg_temp.n('06 el detalle de antes', 200000, pg_temp.de('Ej', '{precio}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50)));
SELECT pg_temp.caso('06 el detalle dice de cuándo es el costo', 'true', (pg_temp.de('Ej', '{filas,1,costo_desde}')::timestamptz = pg_temp.hace(10))::text);
SELECT pg_temp.caso('06 el detalle dice de qué fecha es', 'true', (pg_temp.de('Ej', '{fecha}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50))::timestamptz = pg_temp.hace(50))::text);
SELECT pg_temp.n('06 el tipo de cambio de entonces', 160000, pg_temp.de('Ej', '{precio}', pg_temp.color('Negro'), 'ARS', '{}', pg_temp.hace(40)));

-- Sin costo a esa fecha, no hay precio: ni 0, ni el más cercano.
SELECT pg_temp.n('06 con costo: hoy', 1000, pg_temp.pr('Nuevo1'));
SELECT pg_temp.caso('06 sin costo a esa fecha: sin precio', NULL, pg_temp.de('Nuevo1', '{precio}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50)));
SELECT pg_temp.caso('06 sin costo a esa fecha: el gerente lee cuál', 'Zqx163 Nuevo: sin costo a esa fecha', pg_temp.de('Nuevo1', '{sin_precio,0}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50)));
SELECT pg_temp.caso('06 sin costo a esa fecha: el vendedor leería esto', 'Este paquete no tiene precio a la fecha del presupuesto', pg_temp.de('Nuevo1', '{mensaje}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50)));
SELECT pg_temp.caso('06 sin costo a esa fecha: no toma 0', NULL, pg_temp.de('Nuevo1', '{costo_despiece}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50)));
SELECT pg_temp.caso('06 sin costo a esa fecha: nombra el color', 'Zqx163 PerfilMarco · Zqx163 Negro: sin costo a esa fecha', pg_temp.de('Ej', '{sin_precio,1}', pg_temp.color('Negro'), 'ARS', '{}', pg_temp.hace(200)));

-- Sin tipo de cambio a esa fecha, tampoco.
SELECT pg_temp.caso('06 sin tipo de cambio: sin precio', NULL, pg_temp.de('Viejo', '{precio}', pg_temp.e('{}'), 'ARS', '{}', '2000-01-01'));
SELECT pg_temp.caso('06 sin tipo de cambio: dice cuál', 'Zqx163 Antiguo: sin tipo de cambio de USD_BLUE a ARS a esa fecha', pg_temp.de('Viejo', '{sin_precio,0}', pg_temp.e('{}'), 'ARS', '{}', '2000-01-01'));
SELECT pg_temp.caso('06 sin tipo de cambio: el vendedor leería esto', 'Este paquete no tiene precio a la fecha del presupuesto', pg_temp.de('Viejo', '{mensaje}', pg_temp.e('{}'), 'ARS', '{}', '2000-01-01'));
SELECT pg_temp.n('06 sin tipo de cambio: el costo se ve como se cargó', 10, pg_temp.de('Viejo', '{filas,0,costo}', pg_temp.e('{}'), 'ARS', '{}', '2000-01-01'));
SELECT pg_temp.caso('06 sin tipo de cambio: sin importe', NULL, pg_temp.de('Viejo', '{filas,0,importe}', pg_temp.e('{}'), 'ARS', '{}', '2000-01-01'));
SELECT pg_temp.n('06 en la misma moneda no hace falta', 10, pg_temp.de('Viejo', '{precio}', pg_temp.e('{}'), 'USD_BLUE', '{}', '2000-01-01'));
SELECT pg_temp.caso('06 pedirlo en una moneda sin cambio', 'Zqx163 Antiguo2: sin tipo de cambio de ARS a USD_OFICIAL a esa fecha', pg_temp.de('Viejo2', '{sin_precio,0}', pg_temp.e('{}'), 'USD_OFICIAL', '{}', '2000-01-01'));

SELECT pg_temp.serv('MinViejo', 10, 1, '{}', 5, 'USD_BLUE', 'paquete', false, '1999-01-01');
SELECT pg_temp.caso('06 el mínimo sin tipo de cambio: sin precio', NULL, pg_temp.de('Viejo2', '{precio}', pg_temp.e('{}'), 'ARS', '{}', '2000-01-01'));
SELECT pg_temp.caso('06 el mínimo sin tipo de cambio: dice cuál', 'Zqx163 MinViejo: sin tipo de cambio de USD_BLUE a ARS a esa fecha', pg_temp.de('Viejo2', '{sin_precio,0}', pg_temp.e('{}'), 'ARS', '{}', '2000-01-01'));
SELECT pg_temp.sin_servicios();

SELECT pg_temp.serv('Cambia', 5, 1, '{}', NULL, NULL, NULL, false, pg_temp.hace(100));
SELECT pg_temp.serv('Cambia', 10, 1, '{}', NULL, NULL, NULL, false, pg_temp.hace(10));
SELECT pg_temp.n('06 un % cambiado: hoy', 226600, pg_temp.pr('Ej'));
SELECT pg_temp.n('06 un % cambiado: antes', 210000, pg_temp.de('Ej', '{precio}', pg_temp.e('{}'), 'ARS', '{}', pg_temp.hace(50)));
SELECT pg_temp.sin_servicios();

-- ============================================================
-- 7. Precios de referencia
-- ============================================================
SELECT pg_temp.costo('Manija', NULL, 1500, 'ARS', pg_temp.hace(5));

SELECT pg_temp.n('07 precio de hace 30 días', 200000, pg_temp.re('Ej', 'base', 'precio_desde'));
SELECT pg_temp.n('07 precio de hoy', 206000, pg_temp.re('Ej', 'base', 'precio_hasta'));
SELECT pg_temp.n('07 cuánto cambió', 3, pg_temp.re('Ej', 'base', 'cambio'));
SELECT pg_temp.n('07 sin cambios', 0, pg_temp.re('Pano', 'base', 'cambio'));
SELECT pg_temp.n('07 el tipo de cambio también mueve', 31.875, pg_temp.re('Ej', 'negro', 'cambio'));
SELECT pg_temp.caso('07 dice de qué paquete es', pg_temp.paquete('Ej')::text, pg_temp.re('Ej', 'base', 'paquete_id'));
SELECT pg_temp.caso('07 dice qué versión', '1', pg_temp.re('Ej', 'base', 'numero'));
SELECT pg_temp.caso('07 dice el nombre', 'Zqx163 Ej', pg_temp.re('Ej', 'base', 'nombre'));

SELECT pg_temp.caso('07 primero lo que más cambió', 'Puerta,Ej,Pano', pg_temp.consultar(
  $q$SELECT string_agg(replace(x.nombre, 'Zqx163 ', ''), ',' ORDER BY x.ordinality)
     FROM catalogo_precios_referencia('ARS'::moneda, now() - interval '30 days', now()) WITH ORDINALITY x
     WHERE x.caso = 'base' AND x.nombre IN ('Zqx163 Puerta', 'Zqx163 Ej', 'Zqx163 Pano')$q$, 'Carlos'));
SELECT pg_temp.caso('07 lo que no se compara, al final', 'Nuevo1', pg_temp.consultar(
  $q$SELECT replace(x.nombre, 'Zqx163 ', '')
     FROM catalogo_precios_referencia('ARS'::moneda, now() - interval '30 days', now()) WITH ORDINALITY x
     WHERE x.nombre IN ('Zqx163 Nuevo1', 'Zqx163 Pano', 'Zqx163 Puerta')
     ORDER BY x.ordinality DESC LIMIT 1$q$, 'Carlos'));

SELECT pg_temp.caso('07 sin costo entonces: sin precio', NULL, pg_temp.re('Nuevo1', 'base', 'precio_desde'));
SELECT pg_temp.n('07 sin costo entonces: hoy sí', 1000, pg_temp.re('Nuevo1', 'base', 'precio_hasta'));
SELECT pg_temp.caso('07 sin costo entonces: sin cambio', NULL, pg_temp.re('Nuevo1', 'base', 'cambio'));
SELECT pg_temp.caso('07 sin costo entonces: dice por qué', '{"Zqx163 Nuevo: sin costo a esa fecha"}', pg_temp.re('Nuevo1', 'base', 'sin_precio_desde'));
SELECT pg_temp.caso('07 sin costo entonces: hoy nada', '{}', pg_temp.re('Nuevo1', 'base', 'sin_precio_hasta'));
SELECT pg_temp.caso('07 un caso bloqueado: sin precio', NULL, pg_temp.re('Ej', 'grande', 'precio_hasta'));
SELECT pg_temp.caso('07 un caso bloqueado: dice por qué', '{"Demasiado ancho"}', pg_temp.re('Ej', 'grande', 'sin_precio_hasta'));
SELECT pg_temp.caso('07 un caso sin filas: sin precio', NULL, pg_temp.re('Cond', 'angosto', 'precio_hasta'));
SELECT pg_temp.caso('07 un caso sin filas: dice por qué', '{"Con estas medidas y elecciones el paquete no lleva nada"}', pg_temp.re('Cond', 'angosto', 'sin_precio_hasta'));

SELECT pg_temp.caso('07 solo la publicada: la vieja no', NULL, pg_temp.re('Versiones', 'base', 'version_id'));
SELECT pg_temp.caso('07 solo la publicada: la nueva sí', pg_temp.id('Versiones2')::text, pg_temp.re('Versiones2', 'base', 'version_id'));
SELECT pg_temp.caso('07 un borrador no', NULL, pg_temp.re('Borrador', 'base', 'version_id'));
UPDATE catalogo_paquetes SET activo = false WHERE id = pg_temp.paquete('Pano');
SELECT pg_temp.caso('07 un paquete de baja no', NULL, pg_temp.re('Pano', 'base', 'version_id'));
UPDATE catalogo_paquetes SET activo = true WHERE id = pg_temp.paquete('Pano');

SELECT pg_temp.serv('OpcRef', 50, 1, '{}', NULL, NULL, NULL, true);
SELECT pg_temp.n('07 sin opcionales', 206000, pg_temp.re('Ej', 'base', 'precio_hasta'));
SELECT pg_temp.sin_servicios();

SELECT pg_temp.n('07 por defecto: hoy y hace 30 días', 3, pg_temp.consultar(format(
  $q$SELECT x.cambio::text FROM catalogo_precios_referencia('ARS') x WHERE x.version_id = %L AND x.caso = 'base'$q$, pg_temp.id('Ej')), 'Carlos'));
SELECT pg_temp.caso('07 sin moneda, la principal', 'true', pg_temp.consultar(format(
  $q$SELECT (x.precio_hasta IS NOT NULL)::text FROM catalogo_precios_referencia() x WHERE x.version_id = %L AND x.caso = 'base'$q$, pg_temp.id('Ej')), 'Carlos'));
SELECT pg_temp.n('07 otras fechas', 0, pg_temp.consultar(format(
  $q$SELECT x.cambio::text FROM catalogo_precios_referencia('ARS', now() - interval '90 days', now() - interval '60 days') x WHERE x.version_id = %L AND x.caso = 'base'$q$, pg_temp.id('Ej')), 'Carlos'));

-- ============================================================
-- Resultado
-- ============================================================
DO $$
DECLARE
  v_ok int;
  v_total int;
  v_fallan text;
  v_t timestamptz := clock_timestamp();
  v_ms numeric;
BEGIN
  FOR i IN 1..20 LOOP
    PERFORM catalogo_precio_calcular(pg_temp.id('Ej'), pg_temp.e('{}'), '{}', 'ARS', now());
  END LOOP;
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t) * 1000 / 20, 1);

  SELECT count(*) FILTER (WHERE ok), count(*),
         string_agg(caso || ' → esperado ' || coalesce(esperado, 'NULL') || ', obtenido ' || coalesce(obtenido, 'NULL'),
                    E'\n' ORDER BY caso) FILTER (WHERE NOT ok)
  INTO v_ok, v_total, v_fallan
  FROM r;
  RAISE EXCEPTION '% / % ok · % ms por precio%', v_ok, v_total, v_ms, coalesce(E'\n' || v_fallan, '');
END;
$$;
