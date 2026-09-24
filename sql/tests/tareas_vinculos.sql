-- Verificación de sql/119: referencias en la descripción y `tareas_vinculos`.
-- NO es una migración: todo corre dentro de una transacción que termina en
-- ROLLBACK. Correr después de aplicar sql/112 a sql/119.
--
-- Mundo: M1 y M2, independientes con tareas_ver. M1 lleva H1 (paso p1) y H3
-- (recurrente, paso r1); M2 lleva H2. Nada depende de los datos reales.

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

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_n int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE format('SELECT count(*) FROM (%s) x', p_sql) INTO v_n;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_n::text;
END;
$f$;

-- `{ente:uuid|nombre}` con el id de `ids`.
CREATE FUNCTION pg_temp.ref(p_ente text, p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('{%s:%s|%s}', p_ente, coalesce(pg_temp.id(p_nombre), gen_random_uuid()), p_nombre);
$f$;

CREATE FUNCTION pg_temp.describir(p_paso text, p_texto text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE tareas SET descripcion = %L WHERE id = %L',
    p_texto, pg_temp.id(p_paso)), p_como);
$f$;

-- Los vínculos activos de un paso, por nombre, ordenados.
CREATE FUNCTION pg_temp.vinculos(p_paso uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(v.ente || ':' || coalesce(i.nombre, '?'), ' ' ORDER BY v.ente, i.nombre)
  FROM tareas_vinculos v LEFT JOIN ids i ON i.id = v.registro_id
  WHERE v.tarea_id = p_paso AND v.activo;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['M1','M2','H1','H2','H3','p1','p2','r1']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo = 'tareas_ver';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test119.local', jsonb_build_object('nombre', 'test119 ' || nombre)
FROM ids WHERE nombre IN ('M1','M2');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id('tareas_ver') FROM unnest(ARRAY['M1','M2']) AS u;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: H1 y p1 de M1', 'ok', pg_temp.intentar(format($s$
  INSERT INTO tareas_hilos (id, titulo) VALUES (%L, 'H1');
  INSERT INTO tareas (id, hilo_id, titulo, asignado_id) VALUES (%L, %L, 'p1', %L);
  $s$, pg_temp.id('H1'), pg_temp.id('p1'), pg_temp.id('H1'), pg_temp.id('M1')), 'M1'));
SELECT pg_temp.caso('00 montaje: H2 de M2', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO tareas_hilos (id, titulo) VALUES (%L, 'H2')$s$, pg_temp.id('H2')), 'M2'));

-- ============================================================
-- Derivar de la descripción
-- ============================================================
SELECT pg_temp.caso('01 al crear un paso, su referencia es vínculo', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO tareas (id, hilo_id, titulo, descripcion, asignado_id) VALUES (%L, %L, 'p2', %L, %L)$s$,
  pg_temp.id('p2'), pg_temp.id('H1'), 'ver ' || pg_temp.ref('hilo', 'H1'), pg_temp.id('M1')), 'M1'));
SELECT pg_temp.caso('01 p2 → H1', 'hilo:H1', pg_temp.vinculos(pg_temp.id('p2')));

SELECT pg_temp.caso('02 editar suma y repetir no duplica', 'ok',
  pg_temp.describir('p1', pg_temp.ref('hilo', 'H1') || ' y ' || pg_temp.ref('tarea', 'p2')
                          || ' otra vez ' || pg_temp.ref('hilo', 'H1'), 'M1'));
SELECT pg_temp.caso('02 p1 → H1, p2', 'hilo:H1 tarea:p2', pg_temp.vinculos(pg_temp.id('p1')));

SELECT pg_temp.caso('03 sacar una la apaga', 'ok', pg_temp.describir('p1', pg_temp.ref('tarea', 'p2'), 'M1'));
SELECT pg_temp.caso('03 p1 → p2', 'tarea:p2', pg_temp.vinculos(pg_temp.id('p1')));
SELECT pg_temp.caso('03 la apagada queda, no se borra', '1',
  (SELECT count(*)::text FROM tareas_vinculos WHERE tarea_id = pg_temp.id('p1') AND NOT activo));

SELECT pg_temp.caso('04 sin nombre no es referencia', 'ok',
  pg_temp.describir('p1', format('{hilo:%s}', pg_temp.id('H2')), 'M1'));
SELECT pg_temp.caso('04 p1 sin vínculos', NULL, pg_temp.vinculos(pg_temp.id('p1')));

-- ============================================================
-- Solo se referencia lo que se ve
-- ============================================================
SELECT pg_temp.caso('05 M1 no referencia H2, que no ve', 'TA021',
  pg_temp.describir('p1', pg_temp.ref('hilo', 'H2'), 'M1'));
SELECT pg_temp.caso('05 ni un id que no existe', 'TA021',
  pg_temp.describir('p1', pg_temp.ref('hilo', 'nadie'), 'M1'));
SELECT pg_temp.caso('05 ni un ente que no existe', 'TA021',
  pg_temp.describir('p1', pg_temp.ref('obra', 'H1'), 'M1'));
SELECT pg_temp.caso('05 ni insertar a mano', '42501', pg_temp.intentar(format(
  $s$INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES (%L, 'hilo', %L)$s$,
  pg_temp.id('p1'), pg_temp.id('H1')), 'M1'));
SELECT pg_temp.caso('05 apagar a mano no toca filas', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas_vinculos SET activo = false WHERE tarea_id = %L$s$, pg_temp.id('p2')), 'M1'));
SELECT pg_temp.caso('05 p2 sigue → H1', 'hilo:H1', pg_temp.vinculos(pg_temp.id('p2')));

-- ============================================================
-- Lo ve quien ve el paso
-- ============================================================
SELECT pg_temp.caso('06 M1 ve el vínculo de p2', '1',
  pg_temp.ve(format('SELECT 1 FROM tareas_vinculos WHERE tarea_id = %L', pg_temp.id('p2')), 'M1'));
SELECT pg_temp.caso('06 M2 no', '0',
  pg_temp.ve(format('SELECT 1 FROM tareas_vinculos WHERE tarea_id = %L', pg_temp.id('p2')), 'M2'));

-- ============================================================
-- La recurrencia copia la descripción, y sus vínculos
-- ============================================================
SELECT pg_temp.caso('07 H3 recurrente con r1 → H1, completado y cerrado', 'ok', pg_temp.intentar(format($s$
  INSERT INTO tareas_hilos (id, titulo, recurrencia_cantidad, recurrencia_unidad) VALUES (%L, 'H3', 1, 'dia');
  INSERT INTO tareas (id, hilo_id, titulo, descripcion, asignado_id) VALUES (%L, %L, 'r1', %L, %L);
  UPDATE tareas SET estado = 'completada' WHERE id = %L;
  UPDATE tareas_hilos SET estado = 'cerrado' WHERE id = %L;
  $s$, pg_temp.id('H3'), pg_temp.id('r1'), pg_temp.id('H3'), pg_temp.ref('hilo', 'H1'), pg_temp.id('M1'),
  pg_temp.id('r1'), pg_temp.id('H3')), 'M1'));
SELECT pg_temp.caso('07 el paso del hilo siguiente → H1', 'hilo:H1', pg_temp.vinculos(
  (SELECT t.id FROM tareas t JOIN tareas_hilos h ON h.id = t.hilo_id WHERE h.recurrencia_de = pg_temp.id('H3'))));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
