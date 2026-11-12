-- Verificación de sql/201: lo que se copia de cada link (combinaciones, casillas, piso) y las monedas de referencia. NO es una
-- migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Juan responsable de Belgrano y vendedor (teléfono 1155550201), Ana vendedora sin la obra, G gerencia, T Técnica, Lucia
-- y Carlos de Catálogo. V es la ventana de $200.000 con 1000 × 1000 y Mosquitero opcional de $5.000; desde 3000 de ancho da la
-- alerta "Ancho grande". Servicios opcionales: Colocacion (10 %, paso 1, mínimo de $100.000 por presupuesto), Recargo (10 %,
-- paso 2) y Blindaje (5 % de Herrajes, que V no lleva: nunca aplica). Dólar a $1.000. Lo creado lleva Zqx201.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE TEMP TABLE copias (nombre text PRIMARY KEY, j jsonb) ON COMMIT DROP;
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

-- Como alguien: lo que devuelve (o "ok" si no devuelve nada), o el SQLSTATE.
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
  RETURN coalesce(nullif(v_out, ''), 'ok');
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

-- ---------- Catálogo, como en sql/tests/presupuestos_opcionales.sql ----------
CREATE FUNCTION pg_temp.crear(p_nombre text, p_sql text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.consultar(p_sql, p_como);
BEGIN
  PERFORM pg_temp.caso('crear ' || p_nombre, 'uuid', CASE WHEN v ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE v END);
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

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text, p_costo numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)',
    'Zqx201 ' || p_nombre, pg_temp.l(p_categoria), p_unidad));
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, p_costo, 'ARS', pg_temp.id('Carlos'), now() - interval '10 days'
  FROM catalogo_variantes va WHERE va.insumo_id = pg_temp.id(p_nombre) AND va.color_id IS NULL;
END;
$f$;

CREATE FUNCTION pg_temp.serv(p_clave text, p_pct numeric, p_paso int, p_cats uuid[], p_min numeric DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO catalogo_porcentajes DEFAULT VALUES RETURNING id INTO v_id;
  INSERT INTO ids VALUES (p_clave, v_id);
  INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda,
    minimo_por, opcional, de_baja, creado_por, created_at)
  VALUES (v_id, 'Zqx201 ' || p_clave, p_pct, p_paso, p_cats, p_min, CASE WHEN p_min IS NOT NULL THEN 'ARS'::moneda END,
    CASE WHEN p_min IS NOT NULL THEN 'presupuesto'::alcance_minimo END, true, false, pg_temp.id('Carlos'), now() - interval '10 days');
END;
$f$;

-- ---------- Presupuestos ----------
CREATE FUNCTION pg_temp.alta(p_nombre text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO ids VALUES (p_nombre, pg_temp.consultar(format(
    $s$SELECT presupuestos_alta(%L, %L, 'ARS', 21)::text$s$, pg_temp.id('Belgrano'), 'Zqx201 ' || p_nombre), 'Juan')::uuid);
  INSERT INTO ids VALUES (p_nombre || 'v', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id(p_nombre)));
  INSERT INTO ids VALUES (p_nombre || 's', (SELECT id FROM presupuestos_secciones WHERE version_id = pg_temp.id(p_nombre || 'v')));
END;
$f$;

-- Una fila nueva en una tabla de la versión, como Juan. Guarda el id con su nombre.
CREATE FUNCTION pg_temp.fila(p_tabla text, p_nombre text, p_version text, p_j jsonb) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := gen_random_uuid();
  v_cols text;
  v text;
BEGIN
  SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p_j) k;
  v := pg_temp.consultar(format(
    $s$INSERT INTO %1$I (id, version_id, %2$s) SELECT %3$L, %4$L, %2$s FROM jsonb_populate_record(NULL::%1$I, %5$L) RETURNING 'ok'$s$,
    p_tabla, v_cols, v_id, pg_temp.id(p_version), p_j), 'Juan');
  IF v = 'ok' THEN INSERT INTO ids VALUES (p_nombre, v_id); END IF;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.ventana(p_seccion text, p_ancho numeric, p_piezas jsonb, p_opcionales text[], p_extra jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('seccion_id', pg_temp.id(p_seccion), 'tipo', 'catalogo',
    'paquete_id', (SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id('V')),
    'entrada', jsonb_build_object('variables', jsonb_build_object('ancho', p_ancho, 'alto', 1000)) || p_piezas,
    'opcionales', ARRAY(SELECT pg_temp.id(o) FROM unnest(p_opcionales) o)) || p_extra;
$f$;

CREATE FUNCTION pg_temp.llamar(p_funcion text, p_nombre text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT %I(%L)::text', p_funcion, pg_temp.id(p_nombre)), p_como);
$f$;

-- La copia del link vigente de un presupuesto, guardada con un nombre.
CREATE FUNCTION pg_temp.copiar(p_nombre text, p_presupuesto text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO copias
  SELECT p_nombre, presupuestos_portal_copia(l.id) FROM presupuestos_links l
  WHERE l.presupuesto_id = pg_temp.id(p_presupuesto) AND l.activo;
$f$;

CREATE FUNCTION pg_temp.renglon(p_copia text, p_renglon text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT x FROM copias c, jsonb_array_elements(c.j->'versiones'->0->'renglones') x
  WHERE c.nombre = p_copia AND x->>'id' = pg_temp.id(p_renglon)::text;
$f$;

-- Los nombres sin el prefijo del test, y las claves de servicio por el nombre con que se guardó el id.
CREATE FUNCTION pg_temp.corto(p_texto text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce((SELECT i.nombre FROM ids i WHERE 'servicio:' || i.id = p_texto), replace(replace(p_texto, 'Zqx201 ', ''), 'pieza:', ''));
$f$;

-- Una combinación de un renglón, por sus casillas ("" ninguna; la pieza, en minúscula como su clave): "importe/debajo=…/aparte=…".
CREATE FUNCTION pg_temp.combo(p_copia text, p_renglon text, p_casillas text) RETURNS text LANGUAGE sql AS $f$
  SELECT (c->>'importe') || '/' ||
         coalesce((SELECT string_agg(pg_temp.corto(d->>'nombre') || '=' || (d->>'importe'), ',') FROM jsonb_array_elements(c->'debajo') d), '') || '/' ||
         coalesce((SELECT string_agg(pg_temp.corto(a->>'nombre') || '=' || (a->>'importe'), ',') FROM jsonb_array_elements(c->'aparte') a), '')
  FROM jsonb_array_elements(pg_temp.renglon(p_copia, p_renglon)->'combinaciones') c
  WHERE coalesce((SELECT string_agg(pg_temp.corto(k), ',') FROM jsonb_array_elements_text(c->'casillas') k), '') = p_casillas;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;
UPDATE catalogo_porcentajes_valores SET activo = false WHERE activo;
UPDATE monedas_tipos_cambio SET activo = false WHERE activo;
INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde) VALUES
  ('USD_OFICIAL', 1000, now(), 'monedapi', now() - interval '20 days'),
  ('USD_BLUE',    2000, now(), 'monedapi', now() - interval '20 days'),
  ('EUR',         1200, now(), 'monedapi', now() - interval '20 days');

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','Ana','G','T','Lucia','Carlos','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo IN ('catalogo', 'presupuestos') OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test201.local', jsonb_build_object('nombre', 'test201 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Ana','G','T','Lucia','Carlos');
UPDATE usuarios SET telefono = '1155550201' WHERE id = pg_temp.id('Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion'),
  ('T','presupuestos_revision'), ('T','presupuestos_autorizar_tecnica'),
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx201 Torre Belgrano', 'Zqx201 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx201 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx201 Vidrios') RETURNING id$q$);
SELECT pg_temp.crear('Herrajes', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx201 Herrajes') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx201 Ventanas') RETURNING id$q$);
SELECT pg_temp.insumo('Perfil', 'Perfiles', 'mm', 70000);
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2', 60000);
SELECT pg_temp.insumo('Tela', 'Perfiles', 'm2', 5000);

SELECT pg_temp.serv('Colocacion', 10, 1, '{}', 100000);
SELECT pg_temp.serv('Recargo', 10, 2, '{}');
SELECT pg_temp.serv('Blindaje', 5, 1, ARRAY[pg_temp.id('Herrajes')]);

SELECT pg_temp.crear('V', format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx201 V', pg_temp.l('Ventanas')));
SELECT pg_temp.mete('V.ancho', 'catalogo_variables', 'V', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1200"}');
SELECT pg_temp.mete('V.alto', 'catalogo_variables', 'V', '{"nombre": "alto", "orden": 2, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1000"}');
SELECT pg_temp.mete('V.Marco', 'catalogo_piezas', 'V', '{"nombre": "Marco", "orden": 1}');
SELECT pg_temp.mete(NULL, 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Marco'), 'orden', 1,
  'tipo', 'unico', 'insumo_id', pg_temp.id('Perfil'), 'medida', 'ancho', 'cantidad', '2'));
SELECT pg_temp.mete('V.Hoja', 'catalogo_piezas', 'V', '{"nombre": "Hoja", "orden": 2}');
SELECT pg_temp.mete(NULL, 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Hoja'), 'orden', 1,
  'tipo', 'unico', 'insumo_id', pg_temp.id('Float'), 'ancho', 'ancho', 'alto', 'alto'));
SELECT pg_temp.mete('V.Mosquitero', 'catalogo_piezas', 'V', '{"nombre": "Mosquitero", "orden": 3, "opcional": true}');
SELECT pg_temp.mete(NULL, 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Mosquitero'), 'orden', 1,
  'tipo', 'unico', 'insumo_id', pg_temp.id('Tela'), 'ancho', 'ancho', 'alto', 'alto'));
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.ancho'), 'condicion', 'ancho > 3000', 'mensaje', 'Ancho grande', 'bloquea', false));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'V', '{"nombre": "base", "entrada": {"variables": {"ancho": 1000, "alto": 1000}}}');
SELECT pg_temp.caso('enviar V', 'ok', pg_temp.llamar('catalogo_version_enviar', 'V', 'Lucia'));
SELECT pg_temp.caso('aprobar V', 'ok', pg_temp.llamar('catalogo_version_aprobar', 'V', 'Carlos'));

-- ============================================================
-- 00. Las monedas de referencia
-- ============================================================
-- La vigente: "tope/monedas"; con más de una, falla.
CREATE FUNCTION pg_temp.config() RETURNS text LANGUAGE sql AS $f$
  SELECT (SELECT trim_scale(c.tope_descuento) || '/' || c.monedas_referencia::text FROM presupuestos_configuracion c WHERE c.activo);
$f$;

SELECT pg_temp.consultar('SELECT presupuestos_configurar(10, 15)::text', 'G');
SELECT pg_temp.caso('00 gerencia configura: arrancan pesos y dólar oficial', '10/{ARS,USD_OFICIAL}', pg_temp.config());
SELECT pg_temp.consultar($s$SELECT presupuestos_configurar(10, 15, '{EUR}')::text$s$, 'G');
SELECT pg_temp.caso('00 gerencia las elige', '10/{EUR}', pg_temp.config());
SELECT pg_temp.consultar('SELECT presupuestos_configurar(5, 15)::text', 'G');
SELECT pg_temp.caso('00 cambiar el tope no las toca', '5/{EUR}', pg_temp.config());
SELECT pg_temp.caso('00 quien no configura', '42501', pg_temp.consultar($s$SELECT presupuestos_configurar(10, 15, '{EUR}')::text$s$, 'Juan'));
SELECT pg_temp.caso('00 una moneda vacía no entra', '23514', pg_temp.consultar(
  'SELECT presupuestos_configurar(10, 15, ARRAY[NULL]::moneda[])::text', 'G'));

-- ============================================================
-- 01. Publicado: renglones, casillas y combinaciones
-- ============================================================
-- L1: dos ventanas con Mosquitero (debajo), Colocacion (en el precio) y Recargo (aparte, en Extras al 10,5). $248.050 cada una:
-- Mosquitero 5.000, Colocacion 20.500, Recargo 22.550. La Colocacion aporta 41.000: el mínimo pone 59.000 × 1,1 = 64.900.
SELECT pg_temp.alta('P1');
SELECT pg_temp.caso('01 sección Extras', 'ok', pg_temp.fila('presupuestos_secciones', 'Extras', 'P1v',
  '{"nombre": "Zqx201 Extras", "moneda": "ARS", "alicuota": 10.5}'));
SELECT pg_temp.caso('01 el Mosquitero, debajo', 'ok', pg_temp.fila('presupuestos_opcionales', 'oM', 'P1v',
  '{"pieza": "Mosquitero", "forma": "debajo"}'));
SELECT pg_temp.caso('01 el Recargo, aparte', 'ok', pg_temp.fila('presupuestos_opcionales', 'oR', 'P1v',
  jsonb_build_object('porcentaje_id', pg_temp.id('Recargo'), 'forma', 'aparte', 'seccion_id', pg_temp.id('Extras'))));
SELECT pg_temp.caso('01 L1', 'ok', pg_temp.fila('presupuestos_renglones', 'L1', 'P1v', pg_temp.ventana('P1s', 1000,
  '{"piezas": {"Mosquitero": true}}', ARRAY['Colocacion','Recargo'], '{"cantidad": 2, "designacion": "V1", "orden": 1}')));
SELECT pg_temp.caso('01 L3, sin opcionales', 'ok', pg_temp.fila('presupuestos_renglones', 'L3', 'P1v',
  pg_temp.ventana('P1s', 1000, '{}', '{}', '{"orden": 2}')));
SELECT pg_temp.caso('01 el flete, a mano', 'ok', pg_temp.fila('presupuestos_renglones', 'F', 'P1v',
  jsonb_build_object('seccion_id', pg_temp.id('P1s'), 'tipo', 'mano', 'descripcion', 'Flete', 'precio', 1000, 'orden', 3)));
SELECT pg_temp.caso('01 L1 quedó como se esperaba', '248050', (SELECT trim_scale(precio)::text FROM presupuestos_renglones WHERE id = pg_temp.id('L1')));
SELECT pg_temp.caso('01 publicar', 'ok', pg_temp.llamar('presupuestos_version_publicar', 'P1v'));
SELECT pg_temp.copiar('P1', 'P1');

SELECT pg_temp.caso('01 publicado, con su código, su revisión y una versión', 'publicado/true/true/1', (
  SELECT concat_ws('/', c.j->>'estado', (c.j->>'codigo' = p.codigo)::text, ((c.j->>'revision')::int = l.revision)::text,
                   jsonb_array_length(c.j->'versiones'))
  FROM copias c, presupuestos p JOIN presupuestos_links l ON l.presupuesto_id = p.id AND l.activo
  WHERE c.nombre = 'P1' AND p.id = pg_temp.id('P1')));
SELECT pg_temp.caso('01 el WhatsApp es el del responsable de la obra', '1155550201', (SELECT j->>'whatsapp' FROM copias WHERE nombre = 'P1'));
SELECT pg_temp.caso('01 la versión: número, IVA, descuento y vencimiento', '1/true/0.00/true', (
  SELECT concat_ws('/', v->>'numero', v->>'iva_discriminado', v->>'descuento', (v->>'vence' IS NOT NULL)::text)
  FROM copias c, LATERAL (SELECT c.j->'versiones'->0 AS v) x WHERE c.nombre = 'P1'));
SELECT pg_temp.caso('01 las secciones, en orden', 'General 21.0,Extras 10.5', (
  SELECT string_agg(pg_temp.corto(s->>'nombre') || ' ' || (s->>'alicuota'), ',' ORDER BY i)
  FROM copias c, jsonb_array_elements(c.j->'versiones'->0->'secciones') WITH ORDINALITY t(s, i) WHERE c.nombre = 'P1'));
SELECT pg_temp.caso('01 los renglones, en el orden del editor', 'minimo,catalogo,catalogo,mano', (
  SELECT string_agg(x->>'tipo', ',' ORDER BY i)
  FROM copias c, jsonb_array_elements(c.j->'versiones'->0->'renglones') WITH ORDINALITY t(x, i) WHERE c.nombre = 'P1'));
SELECT pg_temp.caso('01 las casillas, en orden: piezas y después servicios por paso; el que no aplica no está',
  'Mosquitero,Colocacion,Recargo', (
  SELECT string_agg(pg_temp.corto(k->>'nombre'), ',' ORDER BY i)
  FROM jsonb_array_elements(pg_temp.renglon('P1', 'L1')->'casillas') WITH ORDINALITY t(k, i)));
SELECT pg_temp.caso('01 la casilla lleva la clave de las líneas', 'pieza:mosquitero/true', (
  SELECT (x->'casillas'->0->>'clave') || '/' || (x->'casillas'->1->>'clave' = 'servicio:' || pg_temp.id('Colocacion'))
  FROM pg_temp.renglon('P1', 'L1') x));
SELECT pg_temp.caso('01 ocho combinaciones, la publicada primero', '8/true/mosquitero,Colocacion,Recargo', (
  SELECT concat_ws('/', jsonb_array_length(x->'combinaciones'), x->'combinaciones'->0->>'publicada',
    (SELECT string_agg(pg_temp.corto(k), ',') FROM jsonb_array_elements_text(x->'combinaciones'->0->'casillas') k))
  FROM pg_temp.renglon('P1', 'L1') x));
SELECT pg_temp.caso('01 una sola publicada', '1', (SELECT count(*)::text
  FROM jsonb_array_elements(pg_temp.renglon('P1', 'L1')->'combinaciones') c WHERE (c->>'publicada')::boolean));
SELECT pg_temp.caso('01 lo publicado: la ventana sin lo aparte, el Mosquitero debajo y el Recargo a su renglón',
  '451000/Mosquitero=10000/Recargo=45100', pg_temp.combo('P1', 'L1', 'mosquitero,Colocacion,Recargo'));
SELECT pg_temp.caso('01 con IVA, cada uno con la alícuota de su sección', '545710/49836', (
  SELECT (c->>'importe_con_iva') || '/' || (c->'aparte'->0->>'importe_con_iva')
  FROM jsonb_array_elements(pg_temp.renglon('P1', 'L1')->'combinaciones') c WHERE (c->>'publicada')::boolean));
SELECT pg_temp.caso('01 sin nada', '400000//', pg_temp.combo('P1', 'L1', ''));
SELECT pg_temp.caso('01 solo el Recargo: baja el renglón aparte, no la ventana', '400000//Recargo=40000', pg_temp.combo('P1', 'L1', 'Recargo'));
SELECT pg_temp.caso('01 sin el Recargo, lo demás queda en la ventana', '451000/Mosquitero=10000/', pg_temp.combo('P1', 'L1', 'mosquitero,Colocacion'));
SELECT pg_temp.caso('01 el Recargo se cobra sobre lo anterior', '440000//Recargo=44000', pg_temp.combo('P1', 'L1', 'Colocacion,Recargo'));
SELECT pg_temp.caso('01 la ventana sin opcionales ofrece los mismos', '8/200000///205000/Mosquitero=5000/', (
  SELECT jsonb_array_length(x->'combinaciones') || '/' || pg_temp.combo('P1', 'L3', '') || '/' || pg_temp.combo('P1', 'L3', 'mosquitero')
  FROM pg_temp.renglon('P1', 'L3') x));
SELECT pg_temp.caso('01 y lo suyo publicado es sin casillas', 'true/', (
  SELECT (c->>'publicada') || '/' || coalesce((SELECT string_agg(k, ',') FROM jsonb_array_elements_text(c->'casillas') k), '')
  FROM jsonb_array_elements(pg_temp.renglon('P1', 'L3')->'combinaciones') WITH ORDINALITY t(c, i) WHERE i = 1));
SELECT pg_temp.caso('01 el renglón a mano: una combinación, sin casillas', '1/0/1000//', (
  SELECT concat_ws('/', jsonb_array_length(x->'combinaciones'), jsonb_array_length(x->'casillas')) || '/' || pg_temp.combo('P1', 'F', '')
  FROM pg_temp.renglon('P1', 'F') x));
SELECT pg_temp.caso('01 el mínimo, con el servicio del que es', 'Colocacion/Colocacion/64900', (
  SELECT concat_ws('/', pg_temp.corto(x->>'nombre'), pg_temp.corto(x->>'minimo_de'), x->'combinaciones'->0->>'importe')
  FROM copias c, jsonb_array_elements(c.j->'versiones'->0->'renglones') x WHERE c.nombre = 'P1' AND x->>'tipo' = 'minimo'));
SELECT pg_temp.caso('01 lo cargado va sin las piezas: son casillas', 'false/1000', (
  SELECT (x->'entrada' ? 'piezas')::text || '/' || (x->'entrada'->'variables'->>'ancho') FROM pg_temp.renglon('P1', 'L1') x));
SELECT pg_temp.caso('01 el orden de las medidas, para el texto', '1', (
  SELECT c.j->'versiones'->0->'orden'->>(pg_temp.id('V') || ':ancho') FROM copias c WHERE c.nombre = 'P1'));
SELECT pg_temp.caso('01 el renglón aparte sin mínimo no tiene piso', 'Recargo/Extras/null', (
  SELECT concat_ws('/', pg_temp.corto(a->>'clave'), (SELECT nombre FROM ids WHERE id = (a->>'seccion_id')::uuid), coalesce(a->>'piso', 'null'))
  FROM copias c, jsonb_array_elements(c.j->'versiones'->0->'aparte') a WHERE c.nombre = 'P1'));
SELECT pg_temp.caso('01 lo publicado suma lo mismo que ve Juan en el ERP', 'true', (
  SELECT ((SELECT sum((c->>'importe')::numeric) + coalesce(sum((SELECT sum((a->>'importe')::numeric) FROM jsonb_array_elements(c->'aparte') a)), 0)
           FROM copias k, jsonb_array_elements(k.j->'versiones'->0->'renglones') x, jsonb_array_elements(x->'combinaciones') c
           WHERE k.nombre = 'P1' AND (c->>'publicada')::boolean)::text
          = pg_temp.consultar(format('SELECT sum(importe)::text FROM presupuestos_version_importes(%L)', pg_temp.id('P1v')), 'Juan'))::text));

-- ============================================================
-- 02. El piso del renglón aparte
-- ============================================================
-- La Colocacion aparte, en una sección en dólares: la ventana aporta US$ 20 y el mínimo es de $100.000, US$ 100.
SELECT pg_temp.alta('P2');
SELECT pg_temp.caso('02 sección en dólares', 'ok', pg_temp.fila('presupuestos_secciones', 'Dolares', 'P2v',
  '{"nombre": "Zqx201 Dolares", "moneda": "USD_OFICIAL", "alicuota": 10.5}'));
SELECT pg_temp.caso('02 la Colocacion, aparte', 'ok', pg_temp.fila('presupuestos_opcionales', 'oC', 'P2v',
  jsonb_build_object('porcentaje_id', pg_temp.id('Colocacion'), 'forma', 'aparte', 'seccion_id', pg_temp.id('Dolares'))));
SELECT pg_temp.caso('02 M1', 'ok', pg_temp.fila('presupuestos_renglones', 'M1', 'P2v',
  pg_temp.ventana('P2s', 1000, '{}', ARRAY['Colocacion'])));
SELECT pg_temp.caso('02 publicar', 'ok', pg_temp.llamar('presupuestos_version_publicar', 'P2v'));
SELECT pg_temp.copiar('P2', 'P2');
SELECT pg_temp.caso('02 el piso, en la moneda del renglón aparte', 'Colocacion/Dolares/100.00', (
  SELECT concat_ws('/', pg_temp.corto(a->>'clave'), (SELECT nombre FROM ids WHERE id = (a->>'seccion_id')::uuid), a->>'piso')
  FROM copias c, jsonb_array_elements(c.j->'versiones'->0->'aparte') a WHERE c.nombre = 'P2'));
SELECT pg_temp.caso('02 la ventana en pesos, su colocación en dólares', '200000//Colocacion=20.00', pg_temp.combo('P2', 'M1', 'Colocacion'));
SELECT pg_temp.caso('02 el mínimo va en la sección del renglón aparte, y dice de quién es', 'Dolares/Colocacion/80.00', (
  SELECT concat_ws('/', (SELECT nombre FROM ids WHERE id = (x->>'seccion_id')::uuid), pg_temp.corto(x->>'minimo_de'),
                   x->'combinaciones'->0->>'importe')
  FROM copias c, jsonb_array_elements(c.j->'versiones'->0->'renglones') x WHERE c.nombre = 'P2' AND x->>'tipo' = 'minimo'));

-- ============================================================
-- 03. Una alerta: solo lo que cubre Técnica
-- ============================================================
-- W1 mide 3500 de ancho: alerta. Técnica la autoriza sin Mosquitero; con Mosquitero es otra ventana, que nadie vio.
SELECT pg_temp.alta('P3');
SELECT pg_temp.caso('03 W1', 'ok', pg_temp.fila('presupuestos_renglones', 'W1', 'P3v',
  pg_temp.ventana('P3s', 3500, '{}', ARRAY['Colocacion'])));
SELECT pg_temp.caso('03 con la alerta, espera a Técnica', 'en_revision', pg_temp.llamar('presupuestos_version_pedir', 'P3v'));
SELECT pg_temp.caso('03 Técnica autoriza', 'ok', pg_temp.consultar(format('SELECT presupuestos_pedido_resolver(%L, true)',
  (SELECT a.id FROM presupuestos_autorizaciones a WHERE a.version_id = pg_temp.id('P3v') AND a.tipo = 'tecnica')), 'T'));
SELECT pg_temp.caso('03 publicar', 'ok', pg_temp.llamar('presupuestos_version_publicar', 'P3v'));
SELECT pg_temp.copiar('P3', 'P3');
SELECT pg_temp.caso('03 se ofrecen los servicios, no el Mosquitero', '4/Colocacion,Recargo', (
  SELECT jsonb_array_length(x->'combinaciones') || '/' ||
         (SELECT string_agg(pg_temp.corto(k->>'nombre'), ',' ORDER BY i) FROM jsonb_array_elements(x->'casillas') WITH ORDINALITY t(k, i))
  FROM pg_temp.renglon('P3', 'W1') x));

-- ============================================================
-- 04. Según el estado
-- ============================================================
SELECT pg_temp.caso('04 aprobar', 'ok', pg_temp.llamar('presupuestos_aprobar', 'P2v'));
SELECT pg_temp.copiar('P2 aprobado', 'P2');
SELECT pg_temp.caso('04 aprobado: la elegida, con su fecha y sin casillas', 'aprobado/true/1/1/0', (
  SELECT concat_ws('/', c.j->>'estado', (c.j->>'aprobado_en' IS NOT NULL)::text, jsonb_array_length(c.j->'versiones'),
    (SELECT max(jsonb_array_length(x->'combinaciones')) FROM jsonb_array_elements(c.j->'versiones'->0->'renglones') x),
    (SELECT sum(jsonb_array_length(x->'casillas')) FROM jsonb_array_elements(c.j->'versiones'->0->'renglones') x))
  FROM copias c WHERE c.nombre = 'P2 aprobado'));
SELECT pg_temp.caso('04 y sigue mostrando lo aprobado', '200000//Colocacion=20.00', pg_temp.combo('P2 aprobado', 'M1', ''));
SELECT pg_temp.caso('04 publicado no trae fecha de aprobación', 'true', (SELECT (j->>'aprobado_en' IS NULL)::text FROM copias WHERE nombre = 'P1'));

SELECT pg_temp.caso('04 rechazar', 'ok', pg_temp.consultar(format($s$SELECT presupuestos_rechazar(%L, 'precio')$s$, pg_temp.id('P3')), 'Juan'));
SELECT pg_temp.copiar('P3 rechazado', 'P3');
SELECT pg_temp.caso('04 rechazado: no disponible, sin nada más', 'no_disponible/true/2', (
  SELECT concat_ws('/', c.j->>'estado', ((c.j->>'revision')::int = l.revision)::text, (SELECT count(*) FROM jsonb_object_keys(c.j)))
  FROM copias c, presupuestos_links l WHERE c.nombre = 'P3 rechazado' AND l.presupuesto_id = pg_temp.id('P3') AND l.activo));

INSERT INTO ids SELECT 'viejo', l.id FROM presupuestos_links l WHERE l.presupuesto_id = pg_temp.id('P1') AND l.activo;
SELECT pg_temp.caso('04 anular', 'ok', pg_temp.llamar('presupuestos_link_anular', 'P1'));
SELECT pg_temp.caso('04 el link anulado: cortado', '{"estado": "cortado", "revision": 2}',
  presupuestos_portal_copia(pg_temp.id('viejo'))::text);
SELECT pg_temp.copiar('P1 nuevo', 'P1');
SELECT pg_temp.caso('04 el nuevo muestra lo mismo', 'publicado/1/8', (
  SELECT concat_ws('/', c.j->>'estado', c.j->>'revision', jsonb_array_length(pg_temp.renglon('P1 nuevo', 'L1')->'combinaciones'))
  FROM copias c WHERE c.nombre = 'P1 nuevo'));
SELECT pg_temp.caso('04 un link que no existe', NULL, presupuestos_portal_copia(gen_random_uuid())::text);

-- ============================================================
-- 05. Privilegios, y lo que ya había sigue igual
-- ============================================================
SELECT pg_temp.caso('05 un usuario no pide la copia', '42501', pg_temp.consultar(format(
  'SELECT presupuestos_portal_copia(%L)::text', pg_temp.id('viejo')), 'G'));
SELECT pg_temp.caso('05 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_portal_copia(uuid)', 'presupuestos_portal_version(uuid,boolean)',
  'presupuestos_portal_combinaciones(uuid,uuid,timestamptz,jsonb,uuid[],moneda[])', 'presupuestos_importes_de(uuid,jsonb)',
  'presupuestos_nombres_de(uuid)', 'presupuestos_configurar(numeric,integer,moneda[])']) AS f;
SELECT pg_temp.caso('05 un usuario no llama: ' || f, 'false', has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_portal_copia(uuid)', 'presupuestos_portal_version(uuid,boolean)',
  'presupuestos_portal_combinaciones(uuid,uuid,timestamptz,jsonb,uuid[],moneda[])', 'presupuestos_importes_de(uuid,jsonb)',
  'presupuestos_nombres_de(uuid)']) AS f;
SELECT pg_temp.caso('05 el servidor pide la copia', 'true',
  has_function_privilege('service_role', 'public.presupuestos_portal_copia(uuid)', 'EXECUTE')::text);
SELECT pg_temp.caso('05 quien no ve la obra no lee importes ni nombres', '0/{"orden": {}, "nombres": {}}', pg_temp.consultar(format(
  $s$SELECT (SELECT count(*) FROM presupuestos_version_importes(%1$L)) || '/' || presupuestos_version_nombres(%1$L)::text$s$,
  pg_temp.id('P1v')), 'Ana'));
SELECT pg_temp.caso('05 quien la ve, sí: renglones, lo aparte y el orden de las medidas', '5/true', pg_temp.consultar(format(
  $s$SELECT (SELECT count(*) FROM presupuestos_version_importes(%1$L)) || '/' || (presupuestos_version_nombres(%1$L)->'orden' <> '{}')::text$s$,
  pg_temp.id('P1v')), 'Juan'));

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
