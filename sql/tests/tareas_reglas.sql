-- Verificación de sql/113: quién escribe qué, transiciones, pedidos, cadena,
-- cierre, desactivación, notas e historial. NO es una migración: todo corre
-- dentro de una transacción que termina en ROLLBACK. Correr después de
-- aplicar sql/112 y sql/113.
--
-- Arma su propio mundo: G admin de usuarios; A admin de tareas (sin equipo);
-- equipo T con D delegador, M1 (sin tareas_pedir), M2 (con tareas_pedir) y X
-- (sin tareas_ver); equipo U con E delegador y N1; I independiente con
-- tareas_pedir. Nada depende de los datos reales.
--
-- `intentar` como en `usuarios_equipos.sql`: corre un statement con la sesión
-- de ese usuario, fuerza los chequeos diferidos y devuelve 'ok' o el SQLSTATE.
-- `paso` resume un paso como 'pendiente:M2' (estado y asignado, persona o
-- equipo).

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

-- Un hilo nuevo, con `p_como` de responsable.
CREATE FUNCTION pg_temp.hilo(p_hilo text, p_como text, p_responsable text DEFAULT NULL) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('INSERT INTO tareas_hilos (id, titulo, responsable_id) VALUES (%L, %L, %L)',
    pg_temp.id(p_hilo), p_hilo, coalesce(pg_temp.id(p_responsable), pg_temp.id(p_como))), p_como);
$f$;

-- Un paso nuevo; el asignado es persona o equipo (T, U) según el nombre.
CREATE FUNCTION pg_temp.sumar(p_hilo text, p_paso text, p_asignado text, p_como text,
                              p_previo text DEFAULT NULL, p_dias int DEFAULT NULL) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO tareas (id, hilo_id, paso_anterior_id, titulo, asignado_id, asignado_equipo_id, vence_dias)
     VALUES (%L, %L, %L, %L, %L, %L, %L)',
    pg_temp.id(p_paso), pg_temp.id(p_hilo), pg_temp.id(p_previo), p_paso,
    CASE WHEN p_asignado NOT IN ('T', 'U') THEN pg_temp.id(p_asignado) END,
    CASE WHEN p_asignado IN ('T', 'U') THEN pg_temp.id(p_asignado) END,
    p_dias), p_como);
$f$;

CREATE FUNCTION pg_temp.editar(p_paso text, p_set text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE tareas SET %s WHERE id = %L', p_set, pg_temp.id(p_paso)), p_como);
$f$;

CREATE FUNCTION pg_temp.paso(p_paso text) RETURNS text LANGUAGE sql AS $f$
  SELECT t.estado || ':' || pg_temp.nombre(coalesce(t.asignado_id, t.asignado_equipo_id))
  FROM tareas t WHERE t.id = pg_temp.id(p_paso);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','A','D','M1','M2','X','E','N1','I','T','U',
                  'H1','H2','H3','H4','H5','P1','P2','P3','P4','P5','P6','P7','P8','P9',
                  'Q1','Q2','C1','C2','C3','S1','S2','Z1']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','tareas_ver','tareas_pedir',
                            'tareas_todas','tareas_administrar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test113.local', jsonb_build_object('nombre', 'test113 ' || nombre)
FROM ids WHERE nombre IN ('G','A','D','M1','M2','X','E','N1','I');

INSERT INTO equipos (id, nombre) VALUES
  (pg_temp.id('T'), 'test113 T ' || pg_temp.id('T')),
  (pg_temp.id('U'), 'test113 U ' || pg_temp.id('U'));
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('T','D'),('T','M1'),('T','M2'),('T','X'),('U','E'),('U','N1')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('A','tareas_ver'), ('A','tareas_pedir'), ('A','tareas_todas'), ('A','tareas_administrar'),
  ('D','tareas_ver'), ('M1','tareas_ver'), ('M2','tareas_ver'), ('M2','tareas_pedir'),
  ('E','tareas_ver'), ('N1','tareas_ver'), ('I','tareas_ver'), ('I','tareas_pedir')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: D delegador de T', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('D'))));
SELECT pg_temp.caso('00 montaje: E delegador de U', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('E'))));

-- ============================================================
-- Hilos: crear
-- ============================================================
SELECT pg_temp.caso('01 M1 crea H1', 'ok', pg_temp.hilo('H1', 'M1'));
SELECT pg_temp.caso('01 H1 es del equipo T', 'T',
  (SELECT pg_temp.nombre(equipo_id) FROM tareas_hilos WHERE id = pg_temp.id('H1')));
SELECT pg_temp.caso('02 M1 crea un hilo para M2', 'TA002', pg_temp.hilo('H5', 'M1', 'M2'));
SELECT pg_temp.caso('03 X sin tareas_ver no crea hilos', 'TA003', pg_temp.hilo('H5', 'X'));
SELECT pg_temp.caso('04 A crea un hilo para X, que no ve Tareas', 'TA003', pg_temp.hilo('H5', 'A', 'X'));

-- ============================================================
-- Pasos: asignar y pedir
-- ============================================================
SELECT pg_temp.caso('05 M1 asigna a M2', 'ok', pg_temp.sumar('H1', 'P1', 'M2', 'M1'));
SELECT pg_temp.caso('05 P1 pendiente', 'pendiente:M2', pg_temp.paso('P1'));
SELECT pg_temp.caso('06 M1 pide a N1 sin tareas_pedir', 'TA010', pg_temp.sumar('H1', 'P2', 'N1', 'M1'));
SELECT pg_temp.caso('07 M1 asigna a X, que no ve Tareas', 'TA003', pg_temp.sumar('H1', 'P2', 'X', 'M1'));
SELECT pg_temp.caso('08 M1 asigna al equipo T', 'ok', pg_temp.sumar('H1', 'P2', 'T', 'M1'));
SELECT pg_temp.caso('08 P2 pendiente, del equipo', 'pendiente:T', pg_temp.paso('P2'));
SELECT pg_temp.caso('09 N1 no participa de H1: no suma pasos', 'TA001', pg_temp.sumar('H1', 'P9', 'N1', 'N1'));
SELECT pg_temp.caso('10 M2 (asignado) suma un paso para sí, en paralelo', 'ok', pg_temp.sumar('H1', 'P3', 'M2', 'M2'));
SELECT pg_temp.caso('10 M2 suma para M1', 'TA001', pg_temp.sumar('H1', 'P9', 'M1', 'M2'));
SELECT pg_temp.caso('10 M2 suma para sí con previo', 'TA001', pg_temp.sumar('H1', 'P9', 'M2', 'M2', 'P1'));
SELECT pg_temp.caso('11 M2 edita el título de un paso de H1', 'TA001', pg_temp.editar('P3', 'titulo = ''otro''', 'M2'));

SELECT pg_temp.caso('12 M2 crea H2', 'ok', pg_temp.hilo('H2', 'M2'));
SELECT pg_temp.caso('12 M2 pide a N1', 'ok', pg_temp.sumar('H2', 'Q1', 'N1', 'M2'));
SELECT pg_temp.caso('12 Q1 solicitada', 'solicitada:N1', pg_temp.paso('Q1'));
SELECT pg_temp.caso('13 M2 acepta su propio pedido', 'TA011', pg_temp.editar('Q1', 'estado = ''pendiente''', 'M2'));
SELECT pg_temp.caso('13 N1 acepta', 'ok', pg_temp.editar('Q1', 'estado = ''pendiente''', 'N1'));
SELECT pg_temp.caso('14 M2 edita el título: vuelve a solicitada', 'ok', pg_temp.editar('Q1', 'titulo = ''Q1 bis''', 'M2'));
SELECT pg_temp.caso('14 Q1 solicitada', 'solicitada:N1', pg_temp.paso('Q1'));
SELECT pg_temp.caso('14 queda en el historial', 'Q1', (SELECT anterior FROM tareas_ediciones
  WHERE tarea_id = pg_temp.id('Q1') AND campo = 'titulo'));
SELECT pg_temp.caso('15 E, delegador de U, acepta por N1', 'ok', pg_temp.editar('Q1', 'estado = ''pendiente''', 'E'));
SELECT pg_temp.caso('16 M2 cambia la prioridad', 'ok', pg_temp.editar('Q1', 'prioridad = ''alta''', 'M2'));
SELECT pg_temp.caso('16 no lo devuelve', 'pendiente:N1', pg_temp.paso('Q1'));
SELECT pg_temp.caso('17 N1 pone en espera', 'ok', pg_temp.editar('Q1', 'espera_hasta = current_date + 5, espera_motivo = ''falta material''', 'N1'));
SELECT pg_temp.caso('18 N1 devuelve sin motivo', '23514', pg_temp.editar('Q1', 'estado = ''rechazada''', 'N1'));
SELECT pg_temp.caso('18 N1 devuelve con motivo', 'ok', pg_temp.editar('Q1', 'estado = ''rechazada'', motivo_rechazo = ''no llego''', 'N1'));
SELECT pg_temp.caso('18 la espera se limpió', NULL,
  (SELECT espera_hasta::text FROM tareas WHERE id = pg_temp.id('Q1')));
SELECT pg_temp.caso('19 M2 vuelve a pedir', 'ok', pg_temp.editar('Q1', 'estado = ''solicitada''', 'M2'));
SELECT pg_temp.caso('19 Q1 solicitada, sin motivo', 'solicitada:N1:',
  (SELECT pg_temp.paso('Q1') || ':' || coalesce(motivo_rechazo, '') FROM tareas WHERE id = pg_temp.id('Q1')));
SELECT pg_temp.caso('20 N1 rechaza', 'ok', pg_temp.editar('Q1', 'estado = ''rechazada'', motivo_rechazo = ''no''', 'N1'));
SELECT pg_temp.caso('20 M2 lo reasigna adentro, a M1', 'ok', pg_temp.editar('Q1', format('asignado_id = %L', pg_temp.id('M1')), 'M2'));
SELECT pg_temp.caso('20 Q1 pendiente', 'pendiente:M1', pg_temp.paso('Q1'));
SELECT pg_temp.caso('21 M2 completa el paso de M1', 'TA011', pg_temp.editar('Q1', 'estado = ''completada''', 'M2'));
SELECT pg_temp.caso('21 M1 completa', 'ok', pg_temp.editar('Q1', 'estado = ''completada'', resultado = ''listo''', 'M1'));
SELECT pg_temp.caso('22 M1 edita su completado', 'TA007', pg_temp.editar('Q1', 'resultado = ''otro''', 'M1'));

SELECT pg_temp.caso('23 A asigna afuera', 'ok', pg_temp.sumar('H1', 'P4', 'N1', 'A'));
SELECT pg_temp.caso('23 nace aceptado', 'pendiente:N1', pg_temp.paso('P4'));
SELECT pg_temp.caso('24 N1 devuelve lo que asignó A', 'ok', pg_temp.editar('P4', 'estado = ''rechazada'', motivo_rechazo = ''no es mío''', 'N1'));
SELECT pg_temp.caso('24 M1 cancela el rechazado', 'ok', pg_temp.editar('P4', 'estado = ''cancelada''', 'M1'));
SELECT pg_temp.caso('24 M1 lo reabre sin tareas_pedir', 'TA010', pg_temp.editar('P4', 'estado = ''pendiente''', 'M1'));

-- ============================================================
-- Delegador: repartir
-- ============================================================
SELECT pg_temp.caso('25 D reparte P2 (del equipo) a M1', 'ok', pg_temp.editar('P2', format('asignado_equipo_id = NULL, asignado_id = %L', pg_temp.id('M1')), 'D'));
SELECT pg_temp.caso('25 P2 pendiente', 'pendiente:M1', pg_temp.paso('P2'));
SELECT pg_temp.caso('26 D reparte a N1, de otro equipo', 'TA014', pg_temp.editar('P2', format('asignado_id = %L', pg_temp.id('N1')), 'D'));
SELECT pg_temp.caso('27 M1 (no delegador) reasigna P1', 'ok', pg_temp.editar('P1', format('asignado_id = %L', pg_temp.id('D')), 'M1'));
SELECT pg_temp.caso('27 M2 reasigna un paso del hilo de M1', 'TA014', pg_temp.editar('P1', format('asignado_id = %L', pg_temp.id('M2')), 'M2'));

-- ============================================================
-- Cadena
-- ============================================================
SELECT pg_temp.caso('30 M1 crea H3', 'ok', pg_temp.hilo('H3', 'M1'));
SELECT pg_temp.caso('30 C1', 'ok', pg_temp.sumar('H3', 'C1', 'M2', 'M1'));
SELECT pg_temp.caso('30 C1 → C2', 'ok', pg_temp.sumar('H3', 'C2', 'M2', 'M1', 'C1'));
SELECT pg_temp.caso('30 C2 → C3, plazo de 3 días', 'ok', pg_temp.sumar('H3', 'C3', 'M1', 'M1', 'C2', 3));
SELECT pg_temp.caso('30 C3 bloqueado: sin vencimiento', NULL,
  (SELECT vence::text FROM tareas WHERE id = pg_temp.id('C3')));
SELECT pg_temp.caso('31 no bifurca', '23505', pg_temp.sumar('H3', 'P9', 'M1', 'M1', 'C1'));
SELECT pg_temp.caso('32 M2 completa C2 bloqueado', 'TA004', pg_temp.editar('C2', 'estado = ''completada''', 'M2'));
SELECT pg_temp.caso('33 M1 cancela C2', 'ok', pg_temp.editar('C2', 'estado = ''cancelada''', 'M1'));
SELECT pg_temp.caso('33 C3 sigue bloqueado por C1 (cancelado transparente)', 'TA004', pg_temp.editar('C3', 'estado = ''completada''', 'M1'));
SELECT pg_temp.caso('34 M2 completa C1', 'ok', pg_temp.editar('C1', 'estado = ''completada''', 'M2'));
SELECT pg_temp.caso('34 C3 se habilita: vence en 3 días', 'true',
  (SELECT (vence = tareas_hoy() + 3)::text FROM tareas WHERE id = pg_temp.id('C3')));
SELECT pg_temp.caso('35 M1 completa C3', 'ok', pg_temp.editar('C3', 'estado = ''completada''', 'M1'));
SELECT pg_temp.caso('36 M2 reabre C1: cascada a C3 a través del cancelado', 'ok', pg_temp.editar('C1', 'estado = ''pendiente''', 'M2'));
SELECT pg_temp.caso('36 C2 sigue cancelado', 'cancelada:M2', pg_temp.paso('C2'));
SELECT pg_temp.caso('36 C3 reabierto, sin vencimiento', 'pendiente:M1:',
  (SELECT pg_temp.paso('C3') || ':' || coalesce(vence::text, '') FROM tareas WHERE id = pg_temp.id('C3')));
SELECT pg_temp.caso('37 M1 encadena P3 (paralelo) detrás de P1', 'TA005', pg_temp.editar('P3', format('paso_anterior_id = %L', pg_temp.id('P1')), 'M1'));
SELECT pg_temp.caso('38 M1 inserta S1 antes de C3', 'ok', pg_temp.intentar(format(
  'SELECT tareas_insertar_antes(%L, %L, NULL, %L, NULL)', pg_temp.id('C3'), 'S1', pg_temp.id('M2')), 'M1'));
UPDATE ids SET id = (SELECT id FROM tareas WHERE titulo = 'S1') WHERE nombre = 'S1';
SELECT pg_temp.caso('38 la cadena: C2 → S1 → C3', 'true',
  (SELECT (s.paso_anterior_id = pg_temp.id('C2') AND c.paso_anterior_id = s.id)::text
   FROM tareas c JOIN tareas s ON s.id = c.paso_anterior_id WHERE c.id = pg_temp.id('C3')));
SELECT pg_temp.caso('39 M2 inserta antes (no es responsable)', 'TA001', pg_temp.intentar(format(
  'SELECT tareas_insertar_antes(%L, %L, NULL, %L, NULL)', pg_temp.id('C3'), 'S2', pg_temp.id('M2')), 'M2'));
SELECT pg_temp.caso('40 M1 desactiva C1 (no es el último)', 'TA006', pg_temp.intentar(format('SELECT tareas_desactivar_paso(%L)', pg_temp.id('C1')), 'M1'));
SELECT pg_temp.caso('41 M1 desactiva C2, cancelado', 'TA007', pg_temp.intentar(format('SELECT tareas_desactivar_paso(%L)', pg_temp.id('C2')), 'M1'));
SELECT pg_temp.caso('42 por PostgREST: la fila nueva no pasa la policy de SELECT', '42501', pg_temp.editar('C3', 'activo = false', 'M1'));
SELECT pg_temp.caso('42 M1 desactiva C3, el último', 'ok', pg_temp.intentar(format('SELECT tareas_desactivar_paso(%L)', pg_temp.id('C3')), 'M1'));
SELECT pg_temp.caso('43 A reactiva C3', 'ok', pg_temp.editar('C3', 'activo = true', 'A'));

-- ============================================================
-- Admin: completar lo ajeno
-- ============================================================
SELECT pg_temp.caso('44 A completa C1 sin nota', 'TA012', pg_temp.editar('C1', 'estado = ''completada''', 'A'));
SELECT pg_temp.caso('44 A completa C1 con nota', 'ok', pg_temp.intentar(format(
  'SELECT tareas_completar_con_nota(%L, %L)', pg_temp.id('C1'), 'M2 de licencia'), 'A'));
SELECT pg_temp.caso('44 C1 completada', 'completada:M2', pg_temp.paso('C1'));

-- ============================================================
-- Cerrar, reabrir, desactivar
-- ============================================================
SELECT pg_temp.caso('45 M1 cierra H3 con pasos abiertos', 'TA008',
  pg_temp.intentar(format('UPDATE tareas_hilos SET estado = ''cerrado'' WHERE id = %L', pg_temp.id('H3')), 'M1'));
SELECT pg_temp.caso('46 M1 cancela pendientes y cierra', 'ok',
  pg_temp.intentar(format('SELECT tareas_cancelar_y_cerrar(%L, %L)', pg_temp.id('H3'), 'no va'), 'M1'));
SELECT pg_temp.caso('46 S1 cancelado', 'cancelada:M2', pg_temp.paso('S1'));
SELECT pg_temp.caso('47 M1 edita el título del cerrado', 'TA007',
  pg_temp.intentar(format('UPDATE tareas_hilos SET titulo = ''otro'' WHERE id = %L', pg_temp.id('H3')), 'M1'));
SELECT pg_temp.caso('48 M1 suma un paso al cerrado', 'ok', pg_temp.sumar('H3', 'Z1', 'M1', 'M1'));
SELECT pg_temp.caso('48 el hilo se reabre', 'abierto', (SELECT estado::text FROM tareas_hilos WHERE id = pg_temp.id('H3')));
SELECT pg_temp.caso('49 M1 desactiva H3, con completados', 'TA009',
  pg_temp.intentar(format('SELECT tareas_desactivar_hilo(%L)', pg_temp.id('H3')), 'M1'));
SELECT pg_temp.caso('50 M1 crea H4', 'ok', pg_temp.hilo('H4', 'M1'));
SELECT pg_temp.caso('50 con un paso de M2', 'ok', pg_temp.sumar('H4', 'P5', 'M2', 'M1'));
SELECT pg_temp.caso('50 M1 desactiva H4, sin completados', 'ok',
  pg_temp.intentar(format('SELECT tareas_desactivar_hilo(%L)', pg_temp.id('H4')), 'M1'));
SELECT pg_temp.caso('50 H4 desactivado', 'false', (SELECT activo::text FROM tareas_hilos WHERE id = pg_temp.id('H4')));
SELECT pg_temp.caso('51 M1 lo reactiva', 'ok',
  pg_temp.intentar(format('UPDATE tareas_hilos SET activo = true WHERE id = %L', pg_temp.id('H4')), 'M1'));
SELECT pg_temp.caso('51 no pasó nada (M1 no lo ve)', 'false', (SELECT activo::text FROM tareas_hilos WHERE id = pg_temp.id('H4')));

-- ============================================================
-- Transferir
-- ============================================================
SELECT pg_temp.caso('52 M1 transfiere H1 a N1, sin tareas_pedir', 'TA010',
  pg_temp.intentar(format('SELECT tareas_transferir_hilo(%L, %L)', pg_temp.id('H1'), pg_temp.id('N1')), 'M1'));
SELECT pg_temp.caso('53 M2 transfiere H2 a N1 (no es delegador)', 'TA015',
  pg_temp.intentar(format('SELECT tareas_transferir_hilo(%L, %L)', pg_temp.id('H2'), pg_temp.id('N1')), 'M2'));
SELECT pg_temp.caso('54 M2 suma Q2 para sí en H2', 'ok', pg_temp.sumar('H2', 'Q2', 'M2', 'M2'));
SELECT pg_temp.caso('54 M2 transfiere H2 a E', 'ok',
  pg_temp.intentar(format('SELECT tareas_transferir_hilo(%L, %L)', pg_temp.id('H2'), pg_temp.id('E')), 'M2'));
SELECT pg_temp.caso('54 H2 es de U', 'U', (SELECT pg_temp.nombre(equipo_id) FROM tareas_hilos WHERE id = pg_temp.id('H2')));
SELECT pg_temp.caso('54 Q2, abierto de T, pasa a E', 'pendiente:E', pg_temp.paso('Q2'));
SELECT pg_temp.caso('54 Q1, completado, no se toca', 'completada:M1', pg_temp.paso('Q1'));
SELECT pg_temp.caso('55 M1 transfiere H1 a M2, del mismo equipo', 'ok',
  pg_temp.intentar(format('SELECT tareas_transferir_hilo(%L, %L)', pg_temp.id('H1'), pg_temp.id('M2')), 'M1'));

-- ============================================================
-- Notas
-- ============================================================
SELECT pg_temp.caso('56 D (asignado de P1) anota en H1', 'ok',
  pg_temp.intentar(format('INSERT INTO tareas_notas (hilo_id, tarea_id, texto) VALUES (%L, %L, %L)',
    pg_temp.id('H1'), pg_temp.id('P1'), 'nota de D'), 'D'));
SELECT pg_temp.caso('57 I no ve H1: no anota', '42501',
  pg_temp.intentar(format('INSERT INTO tareas_notas (hilo_id, texto) VALUES (%L, %L)', pg_temp.id('H1'), 'x'), 'I'));
SELECT pg_temp.caso('58 M2 intenta ocultar la nota', 'ok',
  pg_temp.intentar(format('UPDATE tareas_notas SET activo = false WHERE texto = %L', 'nota de D'), 'M2'));
SELECT pg_temp.caso('58 sigue visible', 'true', (SELECT activo::text FROM tareas_notas WHERE texto = 'nota de D'));
SELECT pg_temp.caso('59 A la oculta', 'ok',
  pg_temp.intentar(format('UPDATE tareas_notas SET activo = false WHERE texto = %L', 'nota de D'), 'A'));
SELECT pg_temp.caso('59 firmada por A', 'A', pg_temp.nombre((SELECT ocultada_por FROM tareas_notas WHERE texto = 'nota de D')));

-- ============================================================
-- Independiente
-- ============================================================
SELECT pg_temp.caso('60 I crea H5', 'ok', pg_temp.hilo('H5', 'I'));
SELECT pg_temp.caso('60 I pide a M1', 'ok', pg_temp.sumar('H5', 'P6', 'M1', 'I'));
SELECT pg_temp.caso('60 P6 solicitada', 'solicitada:M1', pg_temp.paso('P6'));
SELECT pg_temp.caso('61 I se asigna a sí mismo', 'ok', pg_temp.sumar('H5', 'P7', 'I', 'I'));
SELECT pg_temp.caso('61 P7 pendiente', 'pendiente:I', pg_temp.paso('P7'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
