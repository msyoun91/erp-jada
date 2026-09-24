-- Verificación de sql/117: la recurrencia y "paso a reasignar". NO es una
-- migración: todo corre dentro de una transacción que termina en ROLLBACK.
-- Correr después de aplicar sql/112 a sql/117.
--
-- Mundo: G admin de usuarios; A admin de tareas (sin equipo); equipo T con D
-- delegador, M1 (con tareas_pedir), M2 y M3; equipo U con E delegador y N1.
-- Nada depende de los datos reales.
--
-- `copia(H, P)`: el paso P del siguiente ciclo de H, 'estado:asignado:vence:
-- vence_dias:título del previo'. `intentar`, `avisos` y `limpiar` como en
-- `tareas_avisos.sql`.

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

CREATE FUNCTION pg_temp.hilo(p_hilo text, p_como text, p_cantidad int, p_unidad text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO tareas_hilos (id, titulo, responsable_id, recurrencia_cantidad, recurrencia_unidad)
     VALUES (%L, %L, %L, %L, %L)',
    pg_temp.id(p_hilo), p_hilo, pg_temp.id(p_como), p_cantidad, p_unidad), p_como);
$f$;

CREATE FUNCTION pg_temp.sumar(p_hilo text, p_paso text, p_asignado text, p_como text,
                              p_previo text DEFAULT NULL, p_vence date DEFAULT NULL, p_dias int DEFAULT NULL)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO tareas (id, hilo_id, paso_anterior_id, titulo, asignado_id, vence, vence_dias)
     VALUES (%L, %L, %L, %L, %L, %L, %L)',
    pg_temp.id(p_paso), pg_temp.id(p_hilo), pg_temp.id(p_previo), p_paso, pg_temp.id(p_asignado),
    p_vence, p_dias), p_como);
$f$;

CREATE FUNCTION pg_temp.editar(p_paso text, p_set text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE tareas SET %s WHERE id = %L', p_set, pg_temp.id(p_paso)), p_como);
$f$;

CREATE FUNCTION pg_temp.cerrar(p_hilo text, p_como text, p_set text DEFAULT '') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE tareas_hilos SET estado = ''cerrado''%s WHERE id = %L',
    p_set, pg_temp.id(p_hilo)), p_como);
$f$;

CREATE FUNCTION pg_temp.siguientes(p_hilo text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(h.titulo || ':' || pg_temp.nombre(h.responsable_id) || ':' || h.estado || ':'
                    || coalesce(h.recurrencia_cantidad || ' ' || h.recurrencia_unidad, '-'), ' '
                    ORDER BY h.created_at)
  FROM tareas_hilos h WHERE h.recurrencia_de = pg_temp.id(p_hilo);
$f$;

CREATE FUNCTION pg_temp.copia(p_hilo text, p_paso text) RETURNS text LANGUAGE sql AS $f$
  SELECT t.estado || ':' || pg_temp.nombre(t.asignado_id) || ':' || coalesce(t.vence::text, '') || ':'
         || coalesce(t.vence_dias::text, '') || ':' || coalesce(p.titulo, '')
  FROM tareas t
  LEFT JOIN tareas p ON p.id = t.paso_anterior_id
  WHERE t.titulo = p_paso
    AND t.hilo_id = (SELECT id FROM tareas_hilos WHERE recurrencia_de = pg_temp.id(p_hilo)
                     ORDER BY created_at DESC LIMIT 1);
$f$;

CREATE FUNCTION pg_temp.avisos(p_usuario text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(string_agg(n.tipo || ':' || coalesce(pg_temp.nombre(n.entidad_id), '?'), ' '
                             ORDER BY n.tipo::text, pg_temp.nombre(n.entidad_id)), '')
  FROM usuario_notificaciones n
  WHERE n.usuario_id = pg_temp.id(p_usuario) AND n.activo;
$f$;

CREATE FUNCTION pg_temp.limpiar() RETURNS void LANGUAGE sql AS $f$
  UPDATE usuario_notificaciones SET activo = false
  WHERE activo AND usuario_id IN (SELECT id FROM ids);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','A','D','M1','M2','M3','E','N1','T','U',
                  'H1','H2','H3','H4','H5','R1','R2','R3','R4','S1','S2','S3','S4','S5']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','tareas_ver','tareas_pedir',
                            'tareas_todas','tareas_administrar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test117.local', jsonb_build_object('nombre', 'test117 ' || nombre)
FROM ids WHERE nombre IN ('G','A','D','M1','M2','M3','E','N1');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test117 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['T','U']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('T','D'),('T','M1'),('T','M2'),('T','M3'),('U','E'),('U','N1')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('A','tareas_ver'), ('A','tareas_pedir'), ('A','tareas_todas'), ('A','tareas_administrar'),
  ('D','tareas_ver'), ('M1','tareas_ver'), ('M1','tareas_pedir'), ('M2','tareas_ver'), ('M3','tareas_ver'),
  ('E','tareas_ver'), ('N1','tareas_ver')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: D delegador de T', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('D'))));
SELECT pg_temp.caso('00 montaje: E delegador de U', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('E'))));

-- ============================================================
-- El siguiente copia los pasos
-- ============================================================
SELECT pg_temp.caso('01 M1 crea H1, mensual', 'ok', pg_temp.hilo('H1', 'M1', 1, 'mes'));
SELECT pg_temp.caso('01 R1 a M2, vence fin de enero', 'ok', pg_temp.sumar('H1', 'R1', 'M2', 'M1', NULL, '2026-01-31'));
SELECT pg_temp.caso('01 R1 → R2, 3 días', 'ok', pg_temp.sumar('H1', 'R2', 'M1', 'M1', 'R1', NULL, 3));
SELECT pg_temp.caso('01 R2 → R4, a M2', 'ok', pg_temp.sumar('H1', 'R4', 'M2', 'M1', 'R2', '2026-01-20'));
SELECT pg_temp.caso('01 R3 pedido a N1, vence el 30', 'ok', pg_temp.sumar('H1', 'R3', 'N1', 'M1', NULL, '2026-01-30'));
SELECT pg_temp.caso('02 N1 acepta y completa R3', 'ok', pg_temp.editar('R3', 'estado = ''pendiente''', 'N1'));
SELECT pg_temp.caso('02 N1 completa R3', 'ok', pg_temp.editar('R3', 'estado = ''completada''', 'N1'));
SELECT pg_temp.caso('02 M2 completa R1', 'ok', pg_temp.editar('R1', 'estado = ''completada''', 'M2'));
SELECT pg_temp.caso('02 M1 completa R2', 'ok', pg_temp.editar('R2', 'estado = ''completada'', resultado = ''hecho''', 'M1'));
SELECT pg_temp.caso('02 M1 cancela R4', 'ok', pg_temp.editar('R4', 'estado = ''cancelada''', 'M1'));
SELECT pg_temp.caso('03 M1 cierra H1', 'ok', pg_temp.cerrar('H1', 'M1'));
SELECT pg_temp.caso('03 nace el siguiente', 'H1:M1:abierto:1 mes', pg_temp.siguientes('H1'));
SELECT pg_temp.caso('03 H1 conserva su recurrencia', 'cerrado:1',
  (SELECT estado || ':' || recurrencia_cantidad FROM tareas_hilos WHERE id = pg_temp.id('H1')));
SELECT pg_temp.caso('04 R1: fin de mes sigue fin de mes', 'pendiente:M2:2026-02-28::', pg_temp.copia('H1', 'R1'));
SELECT pg_temp.caso('04 R2: relativo tal cual, bloqueado', 'pendiente:M1::3:R1', pg_temp.copia('H1', 'R2'));
SELECT pg_temp.caso('04 R2: sin resultado', NULL,
  (SELECT resultado FROM tareas t WHERE titulo = 'R2' AND hilo_id <> pg_temp.id('H1')));
SELECT pg_temp.caso('04 R4: el cancelado vuelve', 'pendiente:M2:2026-02-20::R2', pg_temp.copia('H1', 'R4'));
SELECT pg_temp.caso('04 R3: el 30 cae en el último de febrero; pedido de nuevo',
  'solicitada:N1:2026-02-28::', pg_temp.copia('H1', 'R3'));

-- ============================================================
-- Terminar la recurrencia
-- ============================================================
SELECT pg_temp.caso('05 M1 crea H2, semanal', 'ok', pg_temp.hilo('H2', 'M1', 7, 'dia'));
SELECT pg_temp.caso('05 S1', 'ok', pg_temp.sumar('H2', 'S1', 'M1', 'M1'));
SELECT pg_temp.caso('05 S1 completa', 'ok', pg_temp.editar('S1', 'estado = ''completada''', 'M1'));
SELECT pg_temp.caso('05 cierra terminando la recurrencia', 'ok',
  pg_temp.cerrar('H2', 'M1', ', recurrencia_cantidad = NULL, recurrencia_unidad = NULL'));
SELECT pg_temp.caso('05 sin siguiente', NULL, pg_temp.siguientes('H2'));

-- ============================================================
-- Paso a reasignar: asignado que no puede recibir, pedido sin tareas_pedir
-- ============================================================
SELECT pg_temp.caso('06 M2 crea H3, semanal', 'ok', pg_temp.hilo('H3', 'M2', 7, 'dia'));
SELECT pg_temp.caso('06 A le suma S2 a N1, afuera', 'ok', pg_temp.sumar('H3', 'S2', 'N1', 'A', NULL, '2026-03-01'));
SELECT pg_temp.caso('06 S3 a M3', 'ok', pg_temp.sumar('H3', 'S3', 'M3', 'M2'));
SELECT pg_temp.caso('06 N1 completa S2', 'ok', pg_temp.editar('S2', 'estado = ''completada''', 'N1'));
SELECT pg_temp.caso('06 M3 completa S3', 'ok', pg_temp.editar('S3', 'estado = ''completada''', 'M3'));
SELECT pg_temp.caso('06 baja de M3', 'ok',
  pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id('M3'))));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('07 M2 cierra H3', 'ok', pg_temp.cerrar('H3', 'M2'));
SELECT pg_temp.caso('07 S2: pedido sin tareas_pedir, queda en M2', 'pendiente:M2:2026-03-08::', pg_temp.copia('H3', 'S2'));
SELECT pg_temp.caso('07 S3: M3 no puede recibir, queda en M2', 'pendiente:M2:::', pg_temp.copia('H3', 'S3'));
SELECT pg_temp.caso('07 M2 recibe los dos avisos, aunque cerró él', 'paso_a_reasignar:? paso_a_reasignar:?',
  pg_temp.avisos('M2'));
SELECT pg_temp.caso('07 N1 no recibe nada', '', pg_temp.avisos('N1'));

-- ============================================================
-- Cancelar pendientes y cerrar
-- ============================================================
SELECT pg_temp.caso('08 M1 crea H4, mensual', 'ok', pg_temp.hilo('H4', 'M1', 1, 'mes'));
SELECT pg_temp.caso('08 S4', 'ok', pg_temp.sumar('H4', 'S4', 'M2', 'M1'));
SELECT pg_temp.caso('08 cancela y cierra: termina por defecto', 'ok',
  pg_temp.intentar(format('SELECT tareas_cancelar_y_cerrar(%L, %L)', pg_temp.id('H4'), 'no va'), 'M1'));
SELECT pg_temp.caso('08 sin siguiente ni recurrencia', 'cerrado:-',
  (SELECT estado || ':' || coalesce(recurrencia_unidad::text, '-') FROM tareas_hilos WHERE id = pg_temp.id('H4'))
  || coalesce(pg_temp.siguientes('H4'), ''));

SELECT pg_temp.caso('09 M1 crea H5, semanal', 'ok', pg_temp.hilo('H5', 'M1', 7, 'dia'));
SELECT pg_temp.caso('09 S5', 'ok', pg_temp.sumar('H5', 'S5', 'M2', 'M1'));
SELECT pg_temp.caso('09 cancela y cierra generando', 'ok',
  pg_temp.intentar(format('SELECT tareas_cancelar_y_cerrar(%L, NULL, true)', pg_temp.id('H5')), 'M1'));
SELECT pg_temp.caso('09 S5 vuelve, pendiente', 'pendiente:M2:::', pg_temp.copia('H5', 'S5'));

-- ============================================================
-- Cada cierre genera, también tras reabrir
-- ============================================================
SELECT pg_temp.caso('10 M1 reabre S5: reabre H5', 'ok', pg_temp.editar('S5', 'estado = ''pendiente''', 'M1'));
SELECT pg_temp.caso('10 M1 lo cancela', 'ok', pg_temp.editar('S5', 'estado = ''cancelada''', 'M1'));
SELECT pg_temp.caso('10 M1 cierra de nuevo', 'ok', pg_temp.cerrar('H5', 'M1'));
SELECT pg_temp.caso('10 dos siguientes', 'H5:M1:abierto:7 dia H5:M1:abierto:7 dia', pg_temp.siguientes('H5'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
