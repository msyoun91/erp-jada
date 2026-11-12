-- Verificación de sql/205 y sql/206: términos generales en bloques en la configuración, la versión elige cuáles van, condiciones
-- particulares en la versión, todo congelado al publicar. NO es una migración: todo corre dentro de una transacción que revierte.
-- Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Juan responsable de Belgrano y vendedor, G gerencia (configura). P1 con un renglón a mano. Lo creado lleva Zqx205.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

-- Como alguien: lo que devuelve (o "ok" si no devuelve nada), o el SQLSTATE.
CREATE FUNCTION pg_temp.como(p_sql text, p_quien text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_quien)), true);
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

CREATE FUNCTION pg_temp.configurar(p_terminos jsonb, p_quien text DEFAULT 'G') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.como(format($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, %L)$s$, p_terminos), p_quien);
$f$;

-- El id del bloque vigente con ese título.
CREATE FUNCTION pg_temp.bloque(p_titulo text) RETURNS text LANGUAGE sql AS $f$
  SELECT b->>'id' FROM presupuestos_configuracion c, jsonb_array_elements(c.terminos) b WHERE c.activo AND b->>'titulo' = p_titulo;
$f$;

-- Los bloques de una versión como los ve Juan: "Título" o "-Título" si está fuera.
CREATE FUNCTION pg_temp.de_version(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.como(format($s$SELECT string_agg(CASE WHEN (b->>'incluido')::boolean THEN '' ELSE '-' END || (b->>'titulo'), ',' ORDER BY n)
    FROM jsonb_array_elements(presupuestos_version_terminos(%L)) WITH ORDINALITY t(b, n)$s$, pg_temp.id(p_version)), 'Juan');
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;

INSERT INTO ids (nombre, id) SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','G','Belgrano']) AS n;
INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo = 'presupuestos' OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test205.local', jsonb_build_object('nombre', 'test205 ' || nombre)
FROM ids WHERE nombre IN ('Juan','G');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx205 Torre Belgrano', 'Zqx205 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));

INSERT INTO ids VALUES ('P1', pg_temp.como(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx205 P1', 'ARS', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('V1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1')));
SELECT pg_temp.caso('montaje: a mano', 'ok', pg_temp.como(format(
  $s$INSERT INTO presupuestos_renglones (version_id, seccion_id, tipo, descripcion, precio)
     SELECT %1$L, s.id, 'mano', 'Zqx205 Flete', 50000 FROM presupuestos_secciones s WHERE s.version_id = %1$L RETURNING 'ok'$s$,
  pg_temp.id('V1')), 'Juan'));

-- ============================================================
-- 01 Configurar los bloques
-- ============================================================
SELECT pg_temp.caso('01 Juan no configura', '42501', pg_temp.configurar('[]', 'Juan'));
SELECT pg_temp.caso('01 los términos van en una lista', '22023', pg_temp.configurar('{"titulo": "x"}'));
SELECT pg_temp.caso('01 sin título, no', '23514', pg_temp.configurar('[{"titulo": " ", "texto": "x"}]'));
SELECT pg_temp.caso('01 títulos repetidos, no', '23514',
  pg_temp.configurar('[{"titulo": "Pago", "texto": "x"}, {"titulo": "pago", "texto": "y"}]'));
SELECT pg_temp.caso('01 más de 30, no', '23514', pg_temp.configurar(
  (SELECT jsonb_agg(jsonb_build_object('titulo', 'B' || i, 'texto', 'x')) FROM generate_series(1, 31) i)));
SELECT pg_temp.caso('01 G configura dos bloques', 'ok', pg_temp.configurar(
  '[{"titulo": " Colocación ", "texto": "Vano terminado"}, {"titulo": "Forma de pago", "texto": "Seña 50 %"}]'));
SELECT pg_temp.caso('01 en orden, sin espacios, con id', 'Colocación,Forma de pago/2', (
  SELECT string_agg(b->>'titulo', ',' ORDER BY n) || '/' || count(b->>'id')
  FROM presupuestos_configuracion c, jsonb_array_elements(c.terminos) WITH ORDINALITY t(b, n) WHERE c.activo));
INSERT INTO ids VALUES ('Colocación', pg_temp.bloque('Colocación')::uuid), ('Pago', pg_temp.bloque('Forma de pago')::uuid);
INSERT INTO ids VALUES ('C1', (SELECT id FROM presupuestos_configuracion WHERE activo));

-- ============================================================
-- 02 La versión en borrador: los vigentes, y elige cuáles
-- ============================================================
SELECT pg_temp.caso('02 el borrador ve los vigentes, todos', 'Colocación,Forma de pago', pg_temp.de_version('V1'));
SELECT pg_temp.caso('02 Juan saca Colocación y escribe las particulares', 'ok', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET terminos_fuera = ARRAY[%L]::uuid[], condiciones = 'Entrega en 60 días' WHERE id = %L RETURNING 'ok'$s$,
  pg_temp.id('Colocación'), pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('02 Colocación queda fuera', '-Colocación,Forma de pago', pg_temp.de_version('V1'));
SELECT pg_temp.caso('02 particulares con espacios a los lados, no', '23514', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET condiciones = ' x' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('02 Juan no escribe configuracion_id', '42501', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET configuracion_id = %L WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('C1'), pg_temp.id('V1')), 'Juan'));

-- ============================================================
-- 03 Publicar congela la configuración
-- ============================================================
SELECT pg_temp.caso('03 Juan publica', 'ok', pg_temp.como(format('SELECT presupuestos_version_publicar(%L)', pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('03 guarda la vigente y el vencimiento', 'true/true', (
  SELECT (configuracion_id = pg_temp.id('C1'))::text || '/'
         || (vence = (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date + 15)::text
  FROM presupuestos_versiones WHERE id = pg_temp.id('V1')));
SELECT pg_temp.caso('03 publicada, no cambia qué bloques van', 'PR005', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET terminos_fuera = '{}' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('03 publicada, no cambian las particulares', 'PR005', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET condiciones = 'Otra' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('V1')), 'Juan'));

-- G conserva Colocación (mismo id), cambia la seña y suma Otros: lo publicado sigue con los de antes.
SELECT pg_temp.caso('03 G cambia los bloques', 'ok', pg_temp.configurar(jsonb_build_array(
  jsonb_build_object('id', pg_temp.id('Colocación'), 'titulo', 'Colocación', 'texto', 'Vano terminado'),
  jsonb_build_object('id', pg_temp.id('Pago'), 'titulo', 'Forma de pago', 'texto', 'Seña 60 %'),
  jsonb_build_object('titulo', 'Otros', 'texto', 'Garantía 1 año'))));
SELECT pg_temp.caso('03 la publicada sigue con los de cuando se publicó', '-Colocación,Forma de pago', pg_temp.de_version('V1'));
INSERT INTO ids VALUES ('L1', (SELECT id FROM presupuestos_links WHERE presupuesto_id = pg_temp.id('P1') AND activo));
SELECT pg_temp.caso('03 el portal copia solo los incluidos, sin la marca', 'Entrega en 60 días/Forma de pago: Seña 50 %/false', (
  SELECT (x->>'condiciones') || '/'
         || (SELECT string_agg((b->>'titulo') || ': ' || (b->>'texto'), ',') FROM jsonb_array_elements(x->'terminos') b) || '/'
         || (x->'terminos'->0 ? 'incluido')::text
  FROM jsonb_array_elements(presupuestos_portal_copia(pg_temp.id('L1'))->'versiones') x));

-- ============================================================
-- 04 Copiar lleva lo elegido; publicar la copia toma los bloques nuevos
-- ============================================================
CREATE TEMP TABLE copia ON COMMIT DROP AS
SELECT pg_temp.como(format('SELECT presupuestos_version_copiar(%L)::text', pg_temp.id('V1')), 'Juan') AS x;
SELECT pg_temp.caso('04 Juan copia la v1', 'uuid', (SELECT CASE WHEN x ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE x END FROM copia));
INSERT INTO ids SELECT 'V2', x::uuid FROM copia WHERE x ~ '^[0-9a-f-]{36}$';
SELECT pg_temp.caso('04 la copia lleva las particulares, sin configuración', 'Entrega en 60 días/NULL', (
  SELECT condiciones || '/' || coalesce(configuracion_id::text, 'NULL') FROM presupuestos_versiones WHERE id = pg_temp.id('V2')));
SELECT pg_temp.caso('04 la copia ve los vigentes, Colocación sigue fuera', '-Colocación,Forma de pago,Otros', pg_temp.de_version('V2'));
SELECT pg_temp.caso('04 Juan publica la copia', 'ok', pg_temp.como(format('SELECT presupuestos_version_publicar(%L)', pg_temp.id('V2')), 'Juan'));
SELECT pg_temp.caso('04 el portal copia los nuevos', 'Forma de pago: Seña 60 %,Otros: Garantía 1 año', (
  SELECT string_agg((b->>'titulo') || ': ' || (b->>'texto'), ',')
  FROM jsonb_array_elements(presupuestos_portal_copia(pg_temp.id('L1'))->'versiones') x, jsonb_array_elements(x->'terminos') b));

-- ============================================================
-- 05 Permisos
-- ============================================================
SELECT pg_temp.caso('05 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_version_terminos(uuid)', 'presupuestos_terminos_validos(jsonb)',
  'presupuestos_configurar(numeric,integer,jsonb,moneda[])']) AS f;
SELECT pg_temp.caso('05 el CHECK corre como quien escribe: valida', 'true',
  has_function_privilege('authenticated', 'public.presupuestos_terminos_validos(jsonb)', 'EXECUTE')::text);

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
