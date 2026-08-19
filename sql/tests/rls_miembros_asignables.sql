-- Verificación de las policies de sql/009 y sql/014 con dos usuarios reales.
-- NO es una migración: todo corre dentro de una transacción que termina en
-- ROLLBACK — no persiste ningún dato ni cambio de permisos. Volver a correrlo
-- entero después de tocar tareas_asignados_insert/update, tareas_insert,
-- validar_responsable_tarea o tareas_proyectos_miembros_select. Desde sql/013
-- esas policies usan es_responsable_tarea (sin la rama del creador): acá TESTER
-- es responsable de las tareas que creó, así que ningún caso cambia por eso.
--
-- Dos reglas distintas, probadas juntas porque comparten policy:
--   membresía (sql/009) — quién puede recibir una tarea del proyecto
--   tareas_asignar (sql/014) — quién puede poner a OTRO en una tarea
--
-- Por qué existe: como `postgres` las policies no se ejercitan (el owner
-- bypasea RLS). Acá se cambia a rol `authenticated` y se setea
-- request.jwt.claims para que auth.uid() devuelva cada usuario.
--
-- ADMIN  015fa985-fe21-4434-b3c5-7ac78732d765 — creador de P y Q, miembro de ambos
-- TESTER 48b90421-a639-4637-b361-501fa7e1a1a0 — miembro de P, NO miembro de Q
-- A TESTER se le desactivan tareas_gestionar_ajenas y tareas_asignar dentro de
-- la tx: con el bypass activo las policies se cortan en la primera rama y no se
-- prueba nada. El segundo bloque le devuelve tareas_asignar para probar la otra
-- mitad de la regla — los mismos casos tienen que pasar de RECHAZO a OK.

BEGIN;

CREATE TEMP TABLE r (
  caso text,
  esperado text,
  obtenido text,
  ok boolean
) ON COMMIT DROP;
GRANT ALL ON r TO authenticated;

INSERT INTO tareas_proyectos (id, nombre, visibilidad, creado_por) VALUES
  ('aaaa0000-0000-4000-8000-000000000001', 'RLS test P', 'publico', '015fa985-fe21-4434-b3c5-7ac78732d765'),
  ('aaaa0000-0000-4000-8000-000000000002', 'RLS test Q', 'publico', '015fa985-fe21-4434-b3c5-7ac78732d765');

INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES
  ('aaaa0000-0000-4000-8000-000000000001', '015fa985-fe21-4434-b3c5-7ac78732d765'),
  ('aaaa0000-0000-4000-8000-000000000001', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('aaaa0000-0000-4000-8000-000000000002', '015fa985-fe21-4434-b3c5-7ac78732d765');

INSERT INTO tareas_hilos (id, proyecto_id, titulo, visibilidad, responsable_id, creado_por) VALUES
  ('bbbb0000-0000-4000-8000-000000000001', 'aaaa0000-0000-4000-8000-000000000002', 'Hilo en Q', 'publico',
   '48b90421-a639-4637-b361-501fa7e1a1a0', '48b90421-a639-4637-b361-501fa7e1a1a0');

INSERT INTO tareas (id, proyecto_id, hilo_id, titulo, visibilidad, responsable_id, creado_por) VALUES
  ('cccc0000-0000-4000-8000-000000000001', 'aaaa0000-0000-4000-8000-000000000001', NULL, 'T1 en P', 'publico',
   '48b90421-a639-4637-b361-501fa7e1a1a0', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('cccc0000-0000-4000-8000-000000000002', 'aaaa0000-0000-4000-8000-000000000002', NULL, 'T2 en Q', 'publico',
   '48b90421-a639-4637-b361-501fa7e1a1a0', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('cccc0000-0000-4000-8000-000000000003', NULL, NULL, 'T3 suelta', 'publico',
   '48b90421-a639-4637-b361-501fa7e1a1a0', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('cccc0000-0000-4000-8000-000000000004', NULL, 'bbbb0000-0000-4000-8000-000000000001', 'T4 en hilo de Q', 'publico',
   '48b90421-a639-4637-b361-501fa7e1a1a0', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('cccc0000-0000-4000-8000-000000000005', 'aaaa0000-0000-4000-8000-000000000001', NULL, 'T5 en P, ajena', 'publico',
   '015fa985-fe21-4434-b3c5-7ac78732d765', '015fa985-fe21-4434-b3c5-7ac78732d765');

-- Filas preexistentes para los casos de UPDATE (insertadas como postgres: la
-- 0001 simula una asignación activa de alguien que ya perdió la membresía).
INSERT INTO tareas_asignados (id, tarea_id, usuario_id, activo) VALUES
  ('dddd0000-0000-4000-8000-000000000001', 'cccc0000-0000-4000-8000-000000000002', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('dddd0000-0000-4000-8000-000000000002', 'cccc0000-0000-4000-8000-000000000002', '015fa985-fe21-4434-b3c5-7ac78732d765', false),
  ('dddd0000-0000-4000-8000-000000000003', 'cccc0000-0000-4000-8000-000000000001', '48b90421-a639-4637-b361-501fa7e1a1a0', false),
  ('dddd0000-0000-4000-8000-000000000004', 'cccc0000-0000-4000-8000-000000000001', '015fa985-fe21-4434-b3c5-7ac78732d765', false);

UPDATE usuario_submodulos us SET activo = false
FROM submodulos s
WHERE s.id = us.submodulo_id
  AND s.codigo IN ('tareas_gestionar_ajenas', 'tareas_asignar')
  AND us.usuario_id = '48b90421-a639-4637-b361-501fa7e1a1a0';

DO $$
DECLARE
  v_n int;
  v_err text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"48b90421-a639-4637-b361-501fa7e1a1a0","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO r VALUES ('00 rol/uid/bypass', 'authenticated + uid TESTER + sin gestionar_ajenas ni asignar',
    current_user || ' / ' || COALESCE(auth.uid()::text, 'null')
      || ' / ' || tiene_permiso('tareas_gestionar_ajenas')::text
      || ' / ' || tiene_permiso('tareas_asignar')::text,
    current_user = 'authenticated'
      AND auth.uid() = '48b90421-a639-4637-b361-501fa7e1a1a0'
      AND NOT tiene_permiso('tareas_gestionar_ajenas')
      AND NOT tiene_permiso('tareas_asignar'));

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros
   WHERE proyecto_id = 'aaaa0000-0000-4000-8000-000000000001';
  INSERT INTO r VALUES ('01 select miembros de P (es miembro)', '2', v_n::text, v_n = 2);

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros
   WHERE proyecto_id = 'aaaa0000-0000-4000-8000-000000000002';
  INSERT INTO r VALUES ('02 select miembros de Q (no miembro)', '0', v_n::text, v_n = 0);

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000001', '48b90421-a639-4637-b361-501fa7e1a1a0', true);
    INSERT INTO r VALUES ('03 insert asignado miembro (T1/P)', 'OK', 'OK', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('03 insert asignado miembro (T1/P)', 'OK', SQLSTATE || ' ' || v_err, false);
  END;

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000002', '48b90421-a639-4637-b361-501fa7e1a1a0', true);
    INSERT INTO r VALUES ('04 insert asignado NO miembro (T2/Q)', 'RECHAZO', 'paso', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('04 insert asignado NO miembro (T2/Q)', 'RECHAZO', SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000002', '48b90421-a639-4637-b361-501fa7e1a1a0', false);
    INSERT INTO r VALUES ('05 insert asignado inactivo NO miembro', 'OK', 'OK', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('05 insert asignado inactivo NO miembro', 'OK', SQLSTATE || ' ' || v_err, false);
  END;

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000003', '48b90421-a639-4637-b361-501fa7e1a1a0', true);
    INSERT INTO r VALUES ('06 insert asignado tarea suelta', 'OK', 'OK', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('06 insert asignado tarea suelta', 'OK', SQLSTATE || ' ' || v_err, false);
  END;

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000004', '48b90421-a639-4637-b361-501fa7e1a1a0', true);
    INSERT INTO r VALUES ('07 insert asignado via hilo de Q', 'RECHAZO', 'paso', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('07 insert asignado via hilo de Q', 'RECHAZO', SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000005', '48b90421-a639-4637-b361-501fa7e1a1a0', true);
    INSERT INTO r VALUES ('08 insert en tarea ajena (T5/P)', 'RECHAZO', 'paso', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('08 insert en tarea ajena (T5/P)', 'RECHAZO', SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  BEGIN
    UPDATE tareas_asignados SET activo = false
     WHERE id = 'dddd0000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('09 update desactivar NO miembro', '1 fila', v_n::text || ' fila(s)', v_n = 1);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('09 update desactivar NO miembro', '1 fila', SQLSTATE || ' ' || v_err, false);
  END;

  BEGIN
    UPDATE tareas_asignados SET activo = true
     WHERE id = 'dddd0000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('10 update reactivar NO miembro', 'RECHAZO', v_n::text || ' fila(s) actualizadas', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('10 update reactivar NO miembro', 'RECHAZO', SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  -- sql/014: ADMIN es miembro de P, así que acá solo puede fallar por la
  -- función que falta — aísla la regla nueva de la de membresía. El caso
  -- espejo (mismo UPDATE con la función puesta) es el 16.
  BEGIN
    UPDATE tareas_asignados SET activo = true
     WHERE id = 'dddd0000-0000-4000-8000-000000000004';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('11 reactivar a ADMIN sin tareas_asignar (T1/P)', 'RECHAZO',
      v_n::text || ' fila(s) actualizadas', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('11 reactivar a ADMIN sin tareas_asignar (T1/P)', 'RECHAZO',
      SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  -- sql/014: el traspaso del responsable lo corta el trigger, no la policy —
  -- de ahí TA003 y no 42501.
  BEGIN
    UPDATE tareas SET responsable_id = '015fa985-fe21-4434-b3c5-7ac78732d765'
     WHERE id = 'cccc0000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('12 traspasar responsable sin tareas_asignar', 'RECHAZO TA003',
      v_n::text || ' fila(s) actualizadas', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('12 traspasar responsable sin tareas_asignar', 'RECHAZO TA003',
      SQLSTATE || ' ' || v_err, SQLSTATE = 'TA003');
  END;

  PERFORM set_config('request.jwt.claims',
    '{"sub":"015fa985-fe21-4434-b3c5-7ac78732d765","role":"authenticated"}', true);

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000002', '48b90421-a639-4637-b361-501fa7e1a1a0', true);
    INSERT INTO r VALUES ('13 ADMIN (con ambas funciones) asigna a NO miembro en Q', 'RECHAZO', 'paso', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('13 ADMIN (con ambas funciones) asigna a NO miembro en Q', 'RECHAZO',
      SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros
   WHERE proyecto_id = 'aaaa0000-0000-4000-8000-000000000002';
  INSERT INTO r VALUES ('14 ADMIN select miembros de Q (miembro)', '1', v_n::text, v_n = 1);
END $$;

RESET ROLE;

-- Segunda mitad: se le da tareas_asignar a TESTER y se repiten los casos que
-- arriba dieron RECHAZO. Tienen que pasar a OK — si no, la policy está
-- cortando por otra razón y el caso de arriba no probaba lo que dice.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT '48b90421-a639-4637-b361-501fa7e1a1a0', id FROM submodulos WHERE codigo = 'tareas_asignar'
ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

DO $$
DECLARE
  v_n int;
  v_err text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"48b90421-a639-4637-b361-501fa7e1a1a0","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO r VALUES ('15 rol/uid/permiso', 'authenticated + uid TESTER + tareas_asignar sin gestionar_ajenas',
    current_user || ' / ' || COALESCE(auth.uid()::text, 'null')
      || ' / ' || tiene_permiso('tareas_asignar')::text
      || ' / ' || tiene_permiso('tareas_gestionar_ajenas')::text,
    current_user = 'authenticated'
      AND auth.uid() = '48b90421-a639-4637-b361-501fa7e1a1a0'
      AND tiene_permiso('tareas_asignar')
      AND NOT tiene_permiso('tareas_gestionar_ajenas'));

  -- Espejo del caso 11.
  BEGIN
    UPDATE tareas_asignados SET activo = true
     WHERE id = 'dddd0000-0000-4000-8000-000000000004';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('16 reactivar a ADMIN con tareas_asignar (T1/P)', '1 fila',
      v_n::text || ' fila(s)', v_n = 1);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('16 reactivar a ADMIN con tareas_asignar (T1/P)', '1 fila',
      SQLSTATE || ' ' || v_err, false);
  END;

  -- La membresía se evalúa sobre el asignado, no sobre quien actúa: TESTER no es
  -- miembro de Q pero creó T2, y ADMIN sí es miembro.
  BEGIN
    UPDATE tareas_asignados SET activo = true
     WHERE id = 'dddd0000-0000-4000-8000-000000000002';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('17 reactivar a ADMIN en Q (asignado miembro)', '1 fila',
      v_n::text || ' fila(s)', v_n = 1);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('17 reactivar a ADMIN en Q (asignado miembro)', '1 fila',
      SQLSTATE || ' ' || v_err, false);
  END;

  -- Espejo del caso 12: el trigger deja pasar el traspaso. El WITH CHECK de
  -- tareas_update lo permite porque TESTER queda asignado a T1 (caso 03).
  BEGIN
    UPDATE tareas SET responsable_id = '015fa985-fe21-4434-b3c5-7ac78732d765'
     WHERE id = 'cccc0000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('18 traspasar responsable con tareas_asignar', '1 fila',
      v_n::text || ' fila(s)', v_n = 1);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('18 traspasar responsable con tareas_asignar', '1 fila',
      SQLSTATE || ' ' || v_err, false);
  END;
END $$;

RESET ROLE;

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
