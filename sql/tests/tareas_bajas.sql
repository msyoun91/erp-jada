-- Verificación de sql/114: baja, cambio de equipo y entrada desde
-- independiente. NO es una migración: todo corre dentro de una transacción
-- que termina en ROLLBACK. Correr después de aplicar sql/112 a sql/114.
--
-- Mundo: G admin de usuarios; equipo T con D delegador, M1 y M2; equipo U con
-- E delegador y N1 (con tareas_pedir); equipo V sin delegador, con V1 y V2;
-- I1 e I2 independientes. Nada depende de los datos reales.
--
-- `intentar` y `paso` como en `tareas_reglas.sql`.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.nombre(p_id uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT nombre FROM ids WHERE id = p_id;
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text DEFAULT NULL) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
BEGIN
  IF p_como IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
    PERFORM set_config('role', 'authenticated', true);
  ELSE
    PERFORM set_config('role', 'service_role', true);
  END IF;
  EXECUTE p_sql;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.hilo(p_hilo text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('INSERT INTO tareas_hilos (id, titulo, responsable_id) VALUES (%L, %L, %L)',
    pg_temp.id(p_hilo), p_hilo, pg_temp.id(p_como)), p_como);
$f$;

CREATE FUNCTION pg_temp.sumar(p_hilo text, p_paso text, p_asignado text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('INSERT INTO tareas (id, hilo_id, titulo, asignado_id) VALUES (%L, %L, %L, %L)',
    pg_temp.id(p_paso), pg_temp.id(p_hilo), p_paso, pg_temp.id(p_asignado)), p_como);
$f$;

CREATE FUNCTION pg_temp.editar(p_paso text, p_set text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE tareas SET %s WHERE id = %L', p_set, pg_temp.id(p_paso)), p_como);
$f$;

CREATE FUNCTION pg_temp.baja(p_usuario text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id(p_usuario)));
$f$;

CREATE FUNCTION pg_temp.mover(p_usuario text, p_equipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, %L)',
    pg_temp.id('G'), pg_temp.id(p_usuario), pg_temp.id(p_equipo)));
$f$;

-- 'pendiente:M1:T' — estado, asignado y equipo guardado.
CREATE FUNCTION pg_temp.paso(p_paso text) RETURNS text LANGUAGE sql AS $f$
  SELECT t.estado || ':' || pg_temp.nombre(t.asignado_id) || ':' || coalesce(pg_temp.nombre(t.equipo_id), '-')
  FROM tareas t WHERE t.id = pg_temp.id(p_paso);
$f$;

-- 'abierto:M1:T' — estado, responsable y equipo guardado.
CREATE FUNCTION pg_temp.hilo_de(p_hilo text) RETURNS text LANGUAGE sql AS $f$
  SELECT h.estado || ':' || pg_temp.nombre(h.responsable_id) || ':' || coalesce(pg_temp.nombre(h.equipo_id), '-')
  FROM tareas_hilos h WHERE h.id = pg_temp.id(p_hilo);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','D','M1','M2','E','N1','V1','V2','I1','I2','T','U','V',
                  'H1','H2','H3','H4','H5','H6','H7','H8','H9',
                  'P1','P2','P3','P4','P5','P6','P7','P8','P9','P10','Q1','Q2','Q3']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','tareas_ver','tareas_pedir');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test114.local', jsonb_build_object('nombre', 'test114 ' || nombre)
FROM ids WHERE nombre IN ('G','D','M1','M2','E','N1','V1','V2','I1','I2');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test114 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['T','U','V']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('T','D'),('T','M1'),('T','M2'),('U','E'),('U','N1'),('V','V1'),('V','V2')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('D','tareas_ver'), ('M1','tareas_ver'), ('M2','tareas_ver'),
  ('E','tareas_ver'), ('N1','tareas_ver'), ('N1','tareas_pedir'),
  ('V1','tareas_ver'), ('V2','tareas_ver'), ('I1','tareas_ver'), ('I2','tareas_ver')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: D delegador de T', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('D'))));
SELECT pg_temp.caso('00 montaje: E delegador de U', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('E'))));

-- ============================================================
-- Baja de M1: sus hilos, abiertos y cerrados, y sus pasos abiertos, a D
-- ============================================================
SELECT pg_temp.caso('01 M1 crea H1', 'ok', pg_temp.hilo('H1', 'M1'));
SELECT pg_temp.caso('01 P1 para M1', 'ok', pg_temp.sumar('H1', 'P1', 'M1', 'M1'));
SELECT pg_temp.caso('01 P2 para M1', 'ok', pg_temp.sumar('H1', 'P2', 'M1', 'M1'));
SELECT pg_temp.caso('01 M1 completa P2', 'ok', pg_temp.editar('P2', 'estado = ''completada''', 'M1'));
SELECT pg_temp.caso('01 P3 para M2', 'ok', pg_temp.sumar('H1', 'P3', 'M2', 'M1'));
SELECT pg_temp.caso('02 M1 crea H2', 'ok', pg_temp.hilo('H2', 'M1'));
SELECT pg_temp.caso('02 P4 para M1', 'ok', pg_temp.sumar('H2', 'P4', 'M1', 'M1'));
SELECT pg_temp.caso('02 M1 completa P4', 'ok', pg_temp.editar('P4', 'estado = ''completada''', 'M1'));
SELECT pg_temp.caso('02 M1 cierra H2', 'ok',
  pg_temp.intentar(format('UPDATE tareas_hilos SET estado = ''cerrado'' WHERE id = %L', pg_temp.id('H2')), 'M1'));
SELECT pg_temp.caso('03 N1 crea H3', 'ok', pg_temp.hilo('H3', 'N1'));
SELECT pg_temp.caso('03 N1 pide Q1 a M1', 'ok', pg_temp.sumar('H3', 'Q1', 'M1', 'N1'));
SELECT pg_temp.caso('03 N1 pide Q2 a M1', 'ok', pg_temp.sumar('H3', 'Q2', 'M1', 'N1'));
SELECT pg_temp.caso('03 M1 acepta Q2', 'ok', pg_temp.editar('Q2', 'estado = ''pendiente''', 'M1'));

SELECT pg_temp.caso('04 baja de M1', 'ok', pg_temp.baja('M1'));
SELECT pg_temp.caso('04 H1 pasa a D', 'abierto:D:T', pg_temp.hilo_de('H1'));
SELECT pg_temp.caso('04 H2, cerrado, también', 'cerrado:D:T', pg_temp.hilo_de('H2'));
SELECT pg_temp.caso('04 P1 pasa a D', 'pendiente:D:T', pg_temp.paso('P1'));
SELECT pg_temp.caso('04 P2, completado, no se toca', 'completada:M1:T', pg_temp.paso('P2'));
SELECT pg_temp.caso('04 P3, de M2, no se toca', 'pendiente:M2:T', pg_temp.paso('P3'));
SELECT pg_temp.caso('04 H3, de N1, no se toca', 'abierto:N1:U', pg_temp.hilo_de('H3'));
SELECT pg_temp.caso('04 Q1, pedido sin aceptar, lo decide D', 'solicitada:D:T', pg_temp.paso('Q1'));
SELECT pg_temp.caso('04 Q2, pedido aceptado, sigue aceptado', 'pendiente:D:T', pg_temp.paso('Q2'));

-- ============================================================
-- M2 cambia de T a U: todo lo abierto queda en T, con D
-- ============================================================
SELECT pg_temp.caso('05 M2 crea H4', 'ok', pg_temp.hilo('H4', 'M2'));
SELECT pg_temp.caso('05 P5 para M2', 'ok', pg_temp.sumar('H4', 'P5', 'M2', 'M2'));
SELECT pg_temp.caso('05 N1 pide Q3 a M2', 'ok', pg_temp.sumar('H3', 'Q3', 'M2', 'N1'));
SELECT pg_temp.caso('05 M2 acepta Q3', 'ok', pg_temp.editar('Q3', 'estado = ''pendiente''', 'M2'));

SELECT pg_temp.caso('06 M2 pasa a U', 'ok', pg_temp.mover('M2', 'U'));
SELECT pg_temp.caso('06 H4 queda en T, con D', 'abierto:D:T', pg_temp.hilo_de('H4'));
SELECT pg_temp.caso('06 P5 pasa a D', 'pendiente:D:T', pg_temp.paso('P5'));
SELECT pg_temp.caso('06 P3 (en H1) pasa a D', 'pendiente:D:T', pg_temp.paso('P3'));
SELECT pg_temp.caso('06 Q3, aceptado como miembro de T, a D aunque M2 esté en U', 'pendiente:D:T', pg_temp.paso('Q3'));

-- ============================================================
-- Sin destino: equipo sin delegador, independiente
-- ============================================================
SELECT pg_temp.caso('07 V1 crea H5 con P6 para sí', 'ok', pg_temp.hilo('H5', 'V1'));
SELECT pg_temp.caso('07 P6', 'ok', pg_temp.sumar('H5', 'P6', 'V1', 'V1'));
SELECT pg_temp.caso('07 baja de V1', 'ok', pg_temp.baja('V1'));
SELECT pg_temp.caso('07 H5 queda con V1', 'abierto:V1:V', pg_temp.hilo_de('H5'));
SELECT pg_temp.caso('07 P6 queda con V1', 'pendiente:V1:V', pg_temp.paso('P6'));

SELECT pg_temp.caso('08 V2 crea H6 con P7 para sí', 'ok', pg_temp.hilo('H6', 'V2'));
SELECT pg_temp.caso('08 P7', 'ok', pg_temp.sumar('H6', 'P7', 'V2', 'V2'));
SELECT pg_temp.caso('08 V2 pasa a T', 'ok', pg_temp.mover('V2', 'T'));
SELECT pg_temp.caso('08 H6 queda con V2, huérfano de V', 'abierto:V2:V', pg_temp.hilo_de('H6'));
SELECT pg_temp.caso('08 P7 igual', 'pendiente:V2:V', pg_temp.paso('P7'));

SELECT pg_temp.caso('09 I1 crea H7 con P8 para sí', 'ok', pg_temp.hilo('H7', 'I1'));
SELECT pg_temp.caso('09 P8', 'ok', pg_temp.sumar('H7', 'P8', 'I1', 'I1'));
SELECT pg_temp.caso('09 baja de I1', 'ok', pg_temp.baja('I1'));
SELECT pg_temp.caso('09 H7 queda con I1', 'abierto:I1:-', pg_temp.hilo_de('H7'));

-- ============================================================
-- I2 entra a T desde independiente: lo abierto toma T, lo cerrado no
-- ============================================================
SELECT pg_temp.caso('10 I2 crea H8 con P9 para sí', 'ok', pg_temp.hilo('H8', 'I2'));
SELECT pg_temp.caso('10 P9', 'ok', pg_temp.sumar('H8', 'P9', 'I2', 'I2'));
SELECT pg_temp.caso('10 I2 completa P9 y cierra H8', 'ok',
  pg_temp.intentar(format('UPDATE tareas SET estado = ''completada'' WHERE id = %L;
                           UPDATE tareas_hilos SET estado = ''cerrado'' WHERE id = %L',
    pg_temp.id('P9'), pg_temp.id('H8')), 'I2'));
SELECT pg_temp.caso('10 I2 crea H9 con P10 para sí', 'ok', pg_temp.hilo('H9', 'I2'));
SELECT pg_temp.caso('10 P10', 'ok', pg_temp.sumar('H9', 'P10', 'I2', 'I2'));

SELECT pg_temp.caso('11 I2 entra a T', 'ok', pg_temp.mover('I2', 'T'));
SELECT pg_temp.caso('11 H9, abierto, toma T', 'abierto:I2:T', pg_temp.hilo_de('H9'));
SELECT pg_temp.caso('11 P10, abierto, toma T', 'pendiente:I2:T', pg_temp.paso('P10'));
SELECT pg_temp.caso('11 H8, cerrado, sin equipo', 'cerrado:I2:-', pg_temp.hilo_de('H8'));
SELECT pg_temp.caso('11 P9, completado, sin equipo', 'completada:I2:-', pg_temp.paso('P9'));
SELECT pg_temp.caso('11 D ve H9', 'true',
  (SELECT tareas_puede_ver_hilo_de(h.id, h.responsable_id, h.equipo_id, h.activo, pg_temp.id('D'))::text
   FROM tareas_hilos h WHERE h.id = pg_temp.id('H9')));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
