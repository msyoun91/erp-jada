-- Verificación de sql/115: los avisos de tareas. NO es una migración: todo
-- corre dentro de una transacción que termina en ROLLBACK. Correr después de
-- aplicar sql/112 a sql/115.
--
-- Mundo: G admin de usuarios; A admin de tareas (sin equipo); equipo T con D
-- delegador, M1 y M2; equipo U con E delegador y N1 (con tareas_pedir); I1
-- independiente. Nada depende de los datos reales.
--
-- `avisos(X)`: los avisos activos de X, 'tipo:registro' ordenados. `limpiar()`
-- los apaga entre casos. `intentar` y `paso` como en `tareas_reglas.sql`.

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

CREATE FUNCTION pg_temp.sumar(p_hilo text, p_paso text, p_asignado text, p_como text, p_previo text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO tareas (id, hilo_id, titulo, asignado_id, paso_anterior_id) VALUES (%L, %L, %L, %L, %L)',
    pg_temp.id(p_paso), pg_temp.id(p_hilo), p_paso, pg_temp.id(p_asignado), pg_temp.id(p_previo)), p_como);
$f$;

CREATE FUNCTION pg_temp.editar(p_paso text, p_set text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE tareas SET %s WHERE id = %L', p_set, pg_temp.id(p_paso)), p_como);
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

-- La bandeja como la ve X: 'etiqueta|motivo|destino' del aviso de ese tipo.
CREATE FUNCTION pg_temp.bandeja(p_como text, p_tipo text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT string_agg(coalesce(l.etiqueta, '?') || '|' || coalesce(l.motivo, '') || '|' || coalesce(l.destino, '-'), ' ')
  INTO v
  FROM notificaciones_listar(100) l WHERE l.tipo::text = p_tipo;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v;
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','A','D','M1','M2','E','N1','I1','T','U',
                  'H1','H2','H3','H4','H5','H6','P1','P2','P3','P4','P5','P6','P7','P8','Q1']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','tareas_ver','tareas_pedir',
                            'tareas_todas','tareas_administrar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test115.local', jsonb_build_object('nombre', 'test115 ' || nombre)
FROM ids WHERE nombre IN ('G','A','D','M1','M2','E','N1','I1');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test115 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['T','U']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('T','D'),('T','M1'),('T','M2'),('U','E'),('U','N1')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('A','tareas_ver'), ('A','tareas_pedir'), ('A','tareas_todas'), ('A','tareas_administrar'),
  ('D','tareas_ver'), ('M1','tareas_ver'), ('M2','tareas_ver'),
  ('E','tareas_ver'), ('N1','tareas_ver'), ('N1','tareas_pedir'), ('I1','tareas_ver')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: D delegador de T', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('D'))));
SELECT pg_temp.caso('00 montaje: E delegador de U', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('E'))));

-- ============================================================
-- Asignar y pedir
-- ============================================================
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('01 M1 crea H1', 'ok', pg_temp.hilo('H1', 'M1'));
SELECT pg_temp.caso('01 P1 para M2', 'ok', pg_temp.sumar('H1', 'P1', 'M2', 'M1'));
SELECT pg_temp.caso('01 M2: tarea asignada', 'tarea_asignada:P1', pg_temp.avisos('M2'));
SELECT pg_temp.caso('01 M1, que la hizo, nada', '', pg_temp.avisos('M1'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('02 N1 crea H2', 'ok', pg_temp.hilo('H2', 'N1'));
SELECT pg_temp.caso('02 N1 pide Q1 a M1', 'ok', pg_temp.sumar('H2', 'Q1', 'M1', 'N1'));
SELECT pg_temp.caso('02 M1: pedido recibido', 'pedido_recibido:Q1', pg_temp.avisos('M1'));
SELECT pg_temp.caso('02 D, delegador de M1, también', 'pedido_recibido:Q1', pg_temp.avisos('D'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('03 M1 acepta Q1', 'ok', pg_temp.editar('Q1', 'estado = ''pendiente''', 'M1'));
SELECT pg_temp.caso('03 N1: pedido aceptado', 'pedido_aceptado:Q1', pg_temp.avisos('N1'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('04 N1 edita el título de Q1', 'ok', pg_temp.editar('Q1', 'titulo = ''Q1 bis''', 'N1'));
SELECT pg_temp.caso('04 vuelve a pedido: M1 pedido recibido, no editado', 'pedido_recibido:Q1', pg_temp.avisos('M1'));
SELECT pg_temp.caso('04 D igual', 'pedido_recibido:Q1', pg_temp.avisos('D'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('05 M1 rechaza Q1', 'ok',
  pg_temp.editar('Q1', 'estado = ''rechazada'', motivo_rechazo = ''falta la medida''', 'M1'));
SELECT pg_temp.caso('05 N1: pedido rechazado', 'pedido_rechazado:Q1', pg_temp.avisos('N1'));
SELECT pg_temp.caso('05 la bandeja de N1 trae el motivo', 'Q1 bis|falta la medida|tarea',
  pg_temp.bandeja('N1', 'pedido_rechazado'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('06 N1 vuelve a pedir Q1', 'ok', pg_temp.editar('Q1', 'estado = ''solicitada''', 'N1'));
SELECT pg_temp.caso('06 M1: pedido recibido', 'pedido_recibido:Q1', pg_temp.avisos('M1'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('07 D reparte Q1 a M2', 'ok', pg_temp.editar('Q1', format('asignado_id = %L', pg_temp.id('M2')), 'D'));
SELECT pg_temp.caso('07 M2: pedido recibido', 'pedido_recibido:Q1', pg_temp.avisos('M2'));
SELECT pg_temp.caso('07 M1: paso quitado', 'paso_quitado:Q1', pg_temp.avisos('M1'));
SELECT pg_temp.caso('07 N1: paso reasignado', 'paso_reasignado:Q1', pg_temp.avisos('N1'));
SELECT pg_temp.caso('07 D, que lo hizo, nada', '', pg_temp.avisos('D'));
SELECT pg_temp.caso('07 M1 ya no ve Q1: título sin link', 'Q1 bis||-', pg_temp.bandeja('M1', 'paso_quitado'));

-- ============================================================
-- Editar y la cadena
-- ============================================================
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('08 M1 edita la descripción de P1', 'ok', pg_temp.editar('P1', 'descripcion = ''con cuidado''', 'M1'));
SELECT pg_temp.caso('08 M2: paso editado', 'paso_editado:P1', pg_temp.avisos('M2'));
SELECT pg_temp.caso('08 la prioridad no avisa', 'ok', pg_temp.editar('P1', 'prioridad = ''alta''', 'M1'));
SELECT pg_temp.caso('08 M2 sigue con uno', 'paso_editado:P1', pg_temp.avisos('M2'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('09 P2 para D después de P1', 'ok', pg_temp.sumar('H1', 'P2', 'D', 'M1', 'P1'));
SELECT pg_temp.caso('09 D: tarea asignada', 'tarea_asignada:P2', pg_temp.avisos('D'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('09 M2 completa P1', 'ok', pg_temp.editar('P1', 'estado = ''completada''', 'M2'));
SELECT pg_temp.caso('09 M1: paso completado', 'paso_completado:P1', pg_temp.avisos('M1'));
SELECT pg_temp.caso('09 D: paso habilitado', 'paso_habilitado:P2', pg_temp.avisos('D'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('10 M1 inserta P3 (de M2) antes de P2', 'ok',
  pg_temp.intentar(format('SELECT tareas_insertar_antes(%L, ''P3'', NULL, %L, NULL)',
    pg_temp.id('P2'), pg_temp.id('M2')), 'M1'));
UPDATE ids SET id = (SELECT t.id FROM tareas t WHERE t.titulo = 'P3' AND t.hilo_id = pg_temp.id('H1'))
WHERE nombre = 'P3';
SELECT pg_temp.caso('10 D: paso bloqueado', 'paso_bloqueado:P2', pg_temp.avisos('D'));
SELECT pg_temp.caso('10 M2: tarea asignada', 'tarea_asignada:P3', pg_temp.avisos('M2'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('11 M1 reabre P1', 'ok', pg_temp.editar('P1', 'estado = ''pendiente''', 'M1'));
SELECT pg_temp.caso('11 M2: paso reabierto', 'paso_reabierto:P1', pg_temp.avisos('M2'));
SELECT pg_temp.caso('11 D, con P2 ya bloqueado, nada', '', pg_temp.avisos('D'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('12 M2 suma P4 para sí', 'ok', pg_temp.sumar('H1', 'P4', 'M2', 'M2'));
SELECT pg_temp.caso('12 M1: paso sumado', 'paso_sumado:P4', pg_temp.avisos('M1'));
SELECT pg_temp.caso('12 M2, que lo sumó, nada', '', pg_temp.avisos('M2'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('13 M1 cancela P4', 'ok', pg_temp.editar('P4', 'estado = ''cancelada''', 'M1'));
SELECT pg_temp.caso('13 M2: paso cancelado', 'paso_cancelado:P4', pg_temp.avisos('M2'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('14 M1 reasigna P3 de M2 a D', 'ok', pg_temp.editar('P3', format('asignado_id = %L', pg_temp.id('D')), 'M1'));
SELECT pg_temp.caso('14 D: tarea asignada', 'tarea_asignada:P3', pg_temp.avisos('D'));
SELECT pg_temp.caso('14 M2: paso quitado', 'paso_quitado:P3', pg_temp.avisos('M2'));
SELECT pg_temp.caso('14 eventos: se va M2, llega D', 'relacion_baja:M2 relacion_alta:D',
  (SELECT string_agg(x.evento || ':' || pg_temp.nombre(x.registro), ' ' ORDER BY x.created_at)
   FROM (
     SELECT e.evento, (e.detalle->>'registro_id')::uuid AS registro, e.created_at
     FROM eventos e
     WHERE e.ente = 'tarea' AND e.registro_id = pg_temp.id('P3') AND e.evento IN ('relacion_alta', 'relacion_baja')
     ORDER BY e.created_at DESC LIMIT 2
   ) x));

-- ============================================================
-- Bajas de paso e hilo
-- ============================================================
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('15 M1 desactiva P2', 'ok',
  pg_temp.intentar(format('SELECT tareas_desactivar_paso(%L)', pg_temp.id('P2')), 'M1'));
SELECT pg_temp.caso('15 D: paso dado de baja', 'paso_dado_de_baja:P2', pg_temp.avisos('D'));
SELECT pg_temp.caso('15 D ya no lo ve: título sin link', 'P2||-', pg_temp.bandeja('D', 'paso_dado_de_baja'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('16 N1 transfiere H2 a D', 'ok',
  pg_temp.intentar(format('SELECT tareas_transferir_hilo(%L, %L)', pg_temp.id('H2'), pg_temp.id('D')), 'N1'));
SELECT pg_temp.caso('16 D: hilo transferido', 'hilo_transferido:H2', pg_temp.avisos('D'));
SELECT pg_temp.caso('16 evento transferencia de N1 a D', 'N1>D',
  (SELECT pg_temp.nombre((e.detalle->>'de')::uuid) || '>' || pg_temp.nombre((e.detalle->>'a')::uuid)
   FROM eventos e WHERE e.ente = 'hilo' AND e.registro_id = pg_temp.id('H2') AND e.evento = 'transferencia'));
SELECT pg_temp.caso('16 la bandeja de D lleva al hilo', 'H2||hilo', pg_temp.bandeja('D', 'hilo_transferido'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('17 M1 crea H3 con P5 para M2', 'ok', pg_temp.hilo('H3', 'M1'));
SELECT pg_temp.caso('17 P5', 'ok', pg_temp.sumar('H3', 'P5', 'M2', 'M1'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('17 M1 desactiva H3', 'ok',
  pg_temp.intentar(format('SELECT tareas_desactivar_hilo(%L)', pg_temp.id('H3')), 'M1'));
SELECT pg_temp.caso('17 M2: hilo dado de baja', 'hilo_dado_de_baja:H3', pg_temp.avisos('M2'));
SELECT pg_temp.caso('17 M2 ya no lo ve: título sin link', 'H3||-', pg_temp.bandeja('M2', 'hilo_dado_de_baja'));

-- ============================================================
-- Huérfanos
-- ============================================================
SELECT pg_temp.caso('18 I1 crea H4', 'ok', pg_temp.hilo('H4', 'I1'));
SELECT pg_temp.caso('18 N1 crea H5 y pide P7 a I1', 'ok', pg_temp.hilo('H5', 'N1'));
SELECT pg_temp.caso('18 P7', 'ok', pg_temp.sumar('H5', 'P7', 'I1', 'N1'));
SELECT pg_temp.caso('18 I1 acepta P7', 'ok', pg_temp.editar('P7', 'estado = ''pendiente''', 'I1'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('18 baja de I1', 'ok',
  pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id('I1'))));
SELECT pg_temp.caso('18 N1: paso huérfano', 'paso_huerfano:P7', pg_temp.avisos('N1'));
SELECT pg_temp.caso('18 A: hilos huérfanos de I1', 'hilos_huerfanos:I1', pg_temp.avisos('A'));
SELECT pg_temp.caso('18 la bandeja de A', 'test115 I1|1 hilo abierto|tareas_todas', pg_temp.bandeja('A', 'hilos_huerfanos'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('19 M2 pierde tareas_ver', 'ok',
  pg_temp.intentar(format('UPDATE usuario_submodulos SET activo = false WHERE usuario_id = %L AND submodulo_id = %L',
    pg_temp.id('M2'), pg_temp.id('tareas_ver'))));
SELECT pg_temp.caso('19 M1: paso huérfano (P1)', 'paso_huerfano:P1', pg_temp.avisos('M1'));
SELECT pg_temp.caso('19 D: paso huérfano (Q1, en H2)', 'paso_huerfano:Q1', pg_temp.avisos('D'));
SELECT pg_temp.caso('19 A: M2 no lleva hilos', '', pg_temp.avisos('A'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('20 A completa P1 con nota', 'ok',
  pg_temp.intentar(format('SELECT tareas_completar_con_nota(%L, ''lo cerré yo'')', pg_temp.id('P1')), 'A'));
SELECT pg_temp.caso('20 M1: paso completado', 'paso_completado:P1', pg_temp.avisos('M1'));
SELECT pg_temp.caso('20 D: P3 habilitado', 'paso_habilitado:P3', pg_temp.avisos('D'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('20 A reabre P1: M2 no puede recibir', 'ok', pg_temp.editar('P1', 'estado = ''pendiente''', 'A'));
SELECT pg_temp.caso('20 P1 queda en M1', 'M1', (SELECT pg_temp.nombre(asignado_id) FROM tareas WHERE id = pg_temp.id('P1')));
SELECT pg_temp.caso('20 M1: paso a reasignar', 'paso_a_reasignar:P1', pg_temp.avisos('M1'));
SELECT pg_temp.caso('20 M2, sin tareas_ver, nada', '', pg_temp.avisos('M2'));

-- ============================================================
-- Baja con destino: todo al delegador, sin avisos de más
-- ============================================================
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('21 M1 crea H6 con P8 para sí', 'ok', pg_temp.hilo('H6', 'M1'));
SELECT pg_temp.caso('21 P8', 'ok', pg_temp.sumar('H6', 'P8', 'M1', 'M1'));
SELECT pg_temp.caso('21 M1, todo suyo, nada', '', pg_temp.avisos('M1'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('21 baja de M1', 'ok',
  pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id('M1'))));
SELECT pg_temp.caso('21 D: los hilos abiertos y los pasos', 'hilo_transferido:H1 hilo_transferido:H6 tarea_asignada:P1 tarea_asignada:P8',
  pg_temp.avisos('D'));
SELECT pg_temp.caso('21 A: nada quedó huérfano', '', pg_temp.avisos('A'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
