-- Verificación de sql/205: términos generales en la configuración, condiciones particulares en la versión, congelados al
-- publicar. NO es una migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y
-- los casos que fallan.
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
-- 01 Configurar los términos generales
-- ============================================================
SELECT pg_temp.caso('01 Juan no configura', '42501',
  pg_temp.como($s$SELECT presupuestos_configurar(10, 15, 'Seña 50 %')::text$s$, 'Juan'));
SELECT pg_temp.caso('01 G configura con términos', 'ok',
  pg_temp.como($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, '  Seña 50 %  ')$s$, 'G'));
SELECT pg_temp.caso('01 se guardan sin espacios a los lados', 'Seña 50 %',
  (SELECT terminos FROM presupuestos_configuracion WHERE activo));
SELECT pg_temp.caso('01 de más de 5000, no', '23514',
  pg_temp.como(format('SELECT presupuestos_configurar(10, 15, %L)::text', repeat('x', 5001)), 'G'));
SELECT pg_temp.como($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, '   ')$s$, 'G');
SELECT pg_temp.caso('01 vacío queda sin términos', 'NULL',
  (SELECT coalesce(terminos, 'NULL') FROM presupuestos_configuracion WHERE activo));
SELECT pg_temp.como($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, 'Seña 50 %')$s$, 'G');
INSERT INTO ids VALUES ('C50', (SELECT id FROM presupuestos_configuracion WHERE activo));

-- ============================================================
-- 02 Condiciones particulares en el borrador
-- ============================================================
SELECT pg_temp.caso('02 Juan escribe las particulares', 'ok', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET condiciones = 'Entrega en 60 días' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('02 con espacios a los lados, no', '23514', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET condiciones = ' x' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('02 Juan no escribe configuracion_id', '42501', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET configuracion_id = %L WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('C50'), pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('02 el borrador no tiene configuración', 'NULL',
  (SELECT coalesce(configuracion_id::text, 'NULL') FROM presupuestos_versiones WHERE id = pg_temp.id('V1')));

-- ============================================================
-- 03 Publicar congela la configuración
-- ============================================================
SELECT pg_temp.caso('03 Juan publica', 'ok', pg_temp.como(format('SELECT presupuestos_version_publicar(%L)', pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('03 guarda la vigente y el vencimiento', 'true/true', (
  SELECT (configuracion_id = pg_temp.id('C50'))::text || '/'
         || (vence = (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date + 15)::text
  FROM presupuestos_versiones WHERE id = pg_temp.id('V1')));
SELECT pg_temp.caso('03 publicada, las particulares no cambian', 'PR005', pg_temp.como(format(
  $s$UPDATE presupuestos_versiones SET condiciones = 'Otra' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('V1')), 'Juan'));

-- G cambia los generales: lo publicado sigue con los de antes.
SELECT pg_temp.como($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, 'Seña 60 %')$s$, 'G');
INSERT INTO ids VALUES ('L1', (SELECT id FROM presupuestos_links WHERE presupuesto_id = pg_temp.id('P1') AND activo));
SELECT pg_temp.caso('03 el portal copia los de cuando se publicó', 'Entrega en 60 días/Seña 50 %', (
  SELECT (x->>'condiciones') || '/' || (x->>'terminos')
  FROM jsonb_array_elements(presupuestos_portal_copia(pg_temp.id('L1'))->'versiones') x));

-- ============================================================
-- 04 Copiar lleva las particulares; publicar la copia toma los generales nuevos
-- ============================================================
CREATE TEMP TABLE copia ON COMMIT DROP AS
SELECT pg_temp.como(format('SELECT presupuestos_version_copiar(%L)::text', pg_temp.id('V1')), 'Juan') AS x;
SELECT pg_temp.caso('04 Juan copia la v1', 'uuid', (SELECT CASE WHEN x ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE x END FROM copia));
INSERT INTO ids SELECT 'V2', x::uuid FROM copia WHERE x ~ '^[0-9a-f-]{36}$';
SELECT pg_temp.caso('04 la copia lleva las particulares', 'Entrega en 60 días',
  (SELECT condiciones FROM presupuestos_versiones WHERE id = pg_temp.id('V2')));
SELECT pg_temp.caso('04 la copia no lleva configuración', 'NULL',
  (SELECT coalesce(configuracion_id::text, 'NULL') FROM presupuestos_versiones WHERE id = pg_temp.id('V2')));
SELECT pg_temp.caso('04 Juan publica la copia', 'ok', pg_temp.como(format('SELECT presupuestos_version_publicar(%L)', pg_temp.id('V2')), 'Juan'));
SELECT pg_temp.caso('04 el portal copia los nuevos', 'Seña 60 %', (
  SELECT string_agg(x->>'terminos', ',')
  FROM jsonb_array_elements(presupuestos_portal_copia(pg_temp.id('L1'))->'versiones') x));
SELECT pg_temp.caso('04 la v1 sigue con los de antes', 'Seña 50 %', (
  SELECT c.terminos FROM presupuestos_versiones v JOIN presupuestos_configuracion c ON c.id = v.configuracion_id
  WHERE v.id = pg_temp.id('V1')));

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
