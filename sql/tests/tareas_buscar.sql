-- Verificación de sql/124: `buscar_registros` y la rama de tareas.
-- NO es una migración: todo corre dentro de una transacción que termina en
-- ROLLBACK. Correr después de aplicar sql/112 a sql/124.
--
-- Mundo: M1 y M2, independientes con tareas_ver; N sin tareas_ver. M1 lleva
-- H1 (pasos p1 abierto y p2 completado); M2 lleva H2. Los títulos llevan
-- "Zqx124" para no cruzarse con los datos reales.

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

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  RETURN SQLSTATE;
END;
$f$;

-- Lo que encuentra `p_como`, como "ente:nombre" en el orden de la función.
-- Solo lo del montaje: la base es la real.
CREATE FUNCTION pg_temp.busca(p_modulo text, p_texto text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT string_agg(b.ente || ':' || i.nombre, ' ' ORDER BY b.n)
    INTO v_out
    FROM buscar_registros(p_modulo, p_texto) WITH ORDINALITY b(ente, registro_id, etiqueta, detalle, href, n)
    JOIN ids i ON i.id = b.registro_id;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_out;
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['M1','M2','N','H1','H2','p1','p2']) AS n;
INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo = 'tareas_ver';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test124.local', jsonb_build_object('nombre', 'test124 ' || nombre)
FROM ids WHERE nombre IN ('M1','M2','N');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id('tareas_ver') FROM unnest(ARRAY['M1','M2']) AS u;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: H1, p1 y p2 de M1', 'ok', pg_temp.intentar(format($s$
  INSERT INTO tareas_hilos (id, titulo) VALUES (%L, 'Zqx124 hilo uno');
  INSERT INTO tareas (id, hilo_id, titulo, asignado_id) VALUES (%L, %L, 'Paso Zqx124 abierto', %L);
  INSERT INTO tareas (id, hilo_id, titulo, asignado_id) VALUES (%L, %L, 'Zqx124 hecho', %L);
  UPDATE tareas SET estado = 'completada' WHERE id = %5$L;
  $s$, pg_temp.id('H1'), pg_temp.id('p1'), pg_temp.id('H1'), pg_temp.id('M1'),
       pg_temp.id('p2'), pg_temp.id('H1'), pg_temp.id('M1')), 'M1'));
SELECT pg_temp.caso('00 montaje: H2 de M2', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO tareas_hilos (id, titulo) VALUES (%L, 'Zqx124 hilo dos')$s$, pg_temp.id('H2')), 'M2'));

-- ============================================================
-- Lo que ve quien busca, en orden
-- ============================================================
SELECT pg_temp.caso('01 M1: abierto, prefijo primero; lo completado al final', 'hilo:H1 tarea:p1 tarea:p2',
  pg_temp.busca('tareas', 'zqx124', 'M1'));
SELECT pg_temp.caso('02 M2 solo ve su hilo', 'hilo:H2', pg_temp.busca('tareas', 'ZQX124', 'M2'));
SELECT pg_temp.caso('03 sin tareas_ver, nada', NULL, pg_temp.busca('tareas', 'zqx124', 'N'));
SELECT pg_temp.caso('04 menos de dos letras, nada', NULL, pg_temp.busca('tareas', ' z ', 'M1'));
SELECT pg_temp.caso('05 módulo sin rama, nada', NULL, pg_temp.busca('obras', 'zqx124', 'M1'));
SELECT pg_temp.caso('06 % no es comodín', NULL, pg_temp.busca('tareas', 'zqx%', 'M1'));
SELECT pg_temp.caso('07 href y detalle del paso', '/tareas/paso/' || pg_temp.id('p1') || ' · Zqx124 hilo uno',
  (SELECT href || ' · ' || detalle FROM buscar_registros('tareas', 'paso zqx124')
   WHERE registro_id = pg_temp.id('p1')));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
