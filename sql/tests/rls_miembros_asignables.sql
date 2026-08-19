-- Verificación de las policies de sql/009 con dos usuarios reales.
-- NO es una migración: todo corre dentro de una transacción que termina en
-- ROLLBACK — no persiste ningún dato ni cambio de permisos. Volver a correrlo
-- entero después de tocar tareas_asignados_insert/update o
-- tareas_proyectos_miembros_select. Desde sql/013 esas policies usan
-- es_responsable_tarea (sin la rama del creador): acá TESTER es responsable de
-- las tareas que creó, así que ningún caso cambia de resultado.
--
-- Por qué existe: como `postgres` las policies no se ejercitan (el owner
-- bypasea RLS). Acá se cambia a rol `authenticated` y se setea
-- request.jwt.claims para que auth.uid() devuelva cada usuario.
--
-- ADMIN  015fa985-fe21-4434-b3c5-7ac78732d765 — creador de P y Q, miembro de ambos
-- TESTER 48b90421-a639-4637-b361-501fa7e1a1a0 — miembro de P, NO miembro de Q
-- A TESTER se le desactiva tareas_gestionar_ajenas dentro de la tx: con el
-- bypass activo las policies se cortan en la primera rama y no se prueba nada.

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
  AND s.codigo = 'tareas_gestionar_ajenas'
  AND us.usuario_id = '48b90421-a639-4637-b361-501fa7e1a1a0';

DO $$
DECLARE
  v_n int;
  v_err text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"48b90421-a639-4637-b361-501fa7e1a1a0","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO r VALUES ('00 rol/uid/bypass', 'authenticated + uid TESTER + sin gestionar_ajenas',
    current_user || ' / ' || COALESCE(auth.uid()::text, 'null') || ' / ' || tiene_permiso('tareas_gestionar_ajenas')::text,
    current_user = 'authenticated'
      AND auth.uid() = '48b90421-a639-4637-b361-501fa7e1a1a0'
      AND NOT tiene_permiso('tareas_gestionar_ajenas'));

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

  BEGIN
    UPDATE tareas_asignados SET activo = true
     WHERE id = 'dddd0000-0000-4000-8000-000000000004';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('11 update reactivar miembro (T1/P)', '1 fila', v_n::text || ' fila(s)', v_n = 1);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('11 update reactivar miembro (T1/P)', '1 fila', SQLSTATE || ' ' || v_err, false);
  END;

  -- La membresía se evalúa sobre el asignado, no sobre quien actúa: TESTER no es
  -- miembro de Q pero creó T2, y ADMIN sí es miembro.
  BEGIN
    UPDATE tareas_asignados SET activo = true
     WHERE id = 'dddd0000-0000-4000-8000-000000000002';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('12 update reactivar a ADMIN en Q (asignado miembro)', '1 fila',
      v_n::text || ' fila(s)', v_n = 1);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('12 update reactivar a ADMIN en Q (asignado miembro)', '1 fila',
      SQLSTATE || ' ' || v_err, false);
  END;

  PERFORM set_config('request.jwt.claims',
    '{"sub":"015fa985-fe21-4434-b3c5-7ac78732d765","role":"authenticated"}', true);

  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id, activo)
    VALUES ('cccc0000-0000-4000-8000-000000000002', '48b90421-a639-4637-b361-501fa7e1a1a0', true);
    INSERT INTO r VALUES ('13 ADMIN (gestionar_ajenas) asigna a NO miembro en Q', 'RECHAZO', 'paso', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('13 ADMIN (gestionar_ajenas) asigna a NO miembro en Q', 'RECHAZO',
      SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros
   WHERE proyecto_id = 'aaaa0000-0000-4000-8000-000000000002';
  INSERT INTO r VALUES ('14 ADMIN select miembros de Q (miembro)', '1', v_n::text, v_n = 1);
END $$;

RESET ROLE;

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
