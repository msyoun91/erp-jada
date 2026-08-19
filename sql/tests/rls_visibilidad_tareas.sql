-- Verificación de sql/013 con dos usuarios reales: ser creador dejó de dar
-- visibilidad. NO es una migración: todo corre dentro de una transacción que
-- termina en ROLLBACK. Correr después de aplicar sql/013.
--
-- Mismo mecanismo que rls_miembros_asignables.sql: se cambia a rol
-- `authenticated` y se setea request.jwt.claims para mover auth.uid().
--
-- ADMIN  015fa985-fe21-4434-b3c5-7ac78732d765
-- TESTER 48b90421-a639-4637-b361-501fa7e1a1a0 — el "creador sin asignación"
-- A TESTER se le desactivan tareas_gestionar_ajenas y tareas_proyectos_miembros
-- dentro de la tx: con cualquiera de los dos las policies se cortan antes.

BEGIN;

CREATE TEMP TABLE r (
  caso text,
  esperado text,
  obtenido text,
  ok boolean
) ON COMMIT DROP;
GRANT ALL ON r TO authenticated;

-- PV privado, creado por TESTER, que NO es miembro. PP público, con hilo público.
INSERT INTO tareas_proyectos (id, nombre, visibilidad, creado_por) VALUES
  ('eeee0000-0000-4000-8000-000000000001', 'RLS vis PV', 'privado', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('eeee0000-0000-4000-8000-000000000002', 'RLS vis PP', 'publico', '015fa985-fe21-4434-b3c5-7ac78732d765');

INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES
  ('eeee0000-0000-4000-8000-000000000001', '015fa985-fe21-4434-b3c5-7ac78732d765'),
  ('eeee0000-0000-4000-8000-000000000002', '015fa985-fe21-4434-b3c5-7ac78732d765');

-- H1: creado por TESTER, responsable ADMIN, sin proyecto -> TESTER no debería verlo.
-- H2: responsable TESTER sin asignación en sus tareas -> dueño, sí lo ve.
-- H3: público en PP -> lo ve cualquiera que vea el proyecto.
INSERT INTO tareas_hilos (id, proyecto_id, titulo, visibilidad, responsable_id, creado_por) VALUES
  ('ffff0000-0000-4000-8000-000000000001', NULL, 'H1 creado por TESTER', 'privado',
   '015fa985-fe21-4434-b3c5-7ac78732d765', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('ffff0000-0000-4000-8000-000000000002', NULL, 'H2 responsable TESTER', 'privado',
   '48b90421-a639-4637-b361-501fa7e1a1a0', '015fa985-fe21-4434-b3c5-7ac78732d765'),
  ('ffff0000-0000-4000-8000-000000000003', 'eeee0000-0000-4000-8000-000000000002', 'H3 público en PP', 'publico',
   '015fa985-fe21-4434-b3c5-7ac78732d765', '015fa985-fe21-4434-b3c5-7ac78732d765');

-- T1: la creó TESTER y le sacaron la asignación (fila inactiva).
-- T2: suelta pública sin proyecto — visible para todos.
-- T3: suelta privada en PV, creada por TESTER que no es miembro del proyecto.
-- T4: dentro de H3 (hilo público) — visible por cascada, sin asignación.
INSERT INTO tareas (id, proyecto_id, hilo_id, titulo, visibilidad, responsable_id, creado_por) VALUES
  ('eeee0000-0000-4000-8000-000000000101', NULL, NULL, 'T1 creada por TESTER', 'privado',
   '015fa985-fe21-4434-b3c5-7ac78732d765', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('eeee0000-0000-4000-8000-000000000102', NULL, NULL, 'T2 suelta pública', 'publico',
   '015fa985-fe21-4434-b3c5-7ac78732d765', '015fa985-fe21-4434-b3c5-7ac78732d765'),
  ('eeee0000-0000-4000-8000-000000000103', 'eeee0000-0000-4000-8000-000000000001', NULL, 'T3 en PV', 'privado',
   '015fa985-fe21-4434-b3c5-7ac78732d765', '48b90421-a639-4637-b361-501fa7e1a1a0'),
  ('eeee0000-0000-4000-8000-000000000104', NULL, 'ffff0000-0000-4000-8000-000000000003', 'T4 en H3', 'publico',
   '015fa985-fe21-4434-b3c5-7ac78732d765', '015fa985-fe21-4434-b3c5-7ac78732d765');

INSERT INTO tareas_asignados (id, tarea_id, usuario_id, activo) VALUES
  ('eeee0000-0000-4000-8000-000000000201', 'eeee0000-0000-4000-8000-000000000101',
   '48b90421-a639-4637-b361-501fa7e1a1a0', false),
  ('eeee0000-0000-4000-8000-000000000202', 'eeee0000-0000-4000-8000-000000000101',
   '015fa985-fe21-4434-b3c5-7ac78732d765', true);

UPDATE usuario_submodulos us SET activo = false
FROM submodulos s
WHERE s.id = us.submodulo_id
  AND s.codigo IN ('tareas_gestionar_ajenas', 'tareas_proyectos_miembros')
  AND us.usuario_id = '48b90421-a639-4637-b361-501fa7e1a1a0';

-- El caso 14 necesita crear un proyecto: TESTER hoy no tiene la función.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT '48b90421-a639-4637-b361-501fa7e1a1a0', id FROM submodulos WHERE codigo = 'tareas_proyectos_crear'
ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

DO $$
DECLARE
  v_n int;
  v_err text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"48b90421-a639-4637-b361-501fa7e1a1a0","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO r VALUES ('00 rol/uid/bypass', 'authenticated + uid TESTER + sin ajenas ni miembros',
    current_user || ' / ' || COALESCE(auth.uid()::text, 'null') || ' / ' ||
      tiene_permiso('tareas_gestionar_ajenas')::text || ' / ' || tiene_permiso('tareas_proyectos_miembros')::text,
    current_user = 'authenticated'
      AND auth.uid() = '48b90421-a639-4637-b361-501fa7e1a1a0'
      AND NOT tiene_permiso('tareas_gestionar_ajenas')
      AND NOT tiene_permiso('tareas_proyectos_miembros'));

  SELECT count(*) INTO v_n FROM tareas WHERE id = 'eeee0000-0000-4000-8000-000000000101';
  INSERT INTO r VALUES ('01 tarea propia con asignación quitada', '0', v_n::text, v_n = 0);

  SELECT count(*) INTO v_n FROM tareas WHERE id = 'eeee0000-0000-4000-8000-000000000102';
  INSERT INTO r VALUES ('02 tarea suelta pública sin proyecto', '1', v_n::text, v_n = 1);

  SELECT count(*) INTO v_n FROM tareas WHERE id = 'eeee0000-0000-4000-8000-000000000103';
  INSERT INTO r VALUES ('03 tarea privada en proyecto que creó (no miembro)', '0', v_n::text, v_n = 0);

  SELECT count(*) INTO v_n FROM tareas WHERE id = 'eeee0000-0000-4000-8000-000000000104';
  INSERT INTO r VALUES ('04 tarea en hilo público de proyecto público', '1', v_n::text, v_n = 1);

  SELECT count(*) INTO v_n FROM tareas_hilos WHERE id = 'ffff0000-0000-4000-8000-000000000001';
  INSERT INTO r VALUES ('05 hilo que creó, sin ser responsable ni asignado', '0', v_n::text, v_n = 0);

  SELECT count(*) INTO v_n FROM tareas_hilos WHERE id = 'ffff0000-0000-4000-8000-000000000002';
  INSERT INTO r VALUES ('06 hilo del que es responsable (dueño)', '1', v_n::text, v_n = 1);

  SELECT count(*) INTO v_n FROM tareas_proyectos WHERE id = 'eeee0000-0000-4000-8000-000000000001';
  INSERT INTO r VALUES ('07 proyecto privado que creó, sin ser miembro', '0', v_n::text, v_n = 0);

  SELECT count(*) INTO v_n FROM tareas_proyectos WHERE id = 'eeee0000-0000-4000-8000-000000000002';
  INSERT INTO r VALUES ('08 proyecto público del que no es miembro', '1', v_n::text, v_n = 1);

  -- UPDATE denegado no tira error: filtra filas. Por eso se cuenta ROW_COUNT.
  UPDATE tareas SET titulo = 'pisada' WHERE id = 'eeee0000-0000-4000-8000-000000000101';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO r VALUES ('09 update de la tarea que creó', '0 filas', v_n::text || ' fila(s)', v_n = 0);

  UPDATE tareas_hilos SET titulo = 'pisado' WHERE id = 'ffff0000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO r VALUES ('10 update del hilo que creó', '0 filas', v_n::text || ' fila(s)', v_n = 0);

  UPDATE tareas_proyectos SET nombre = 'pisado' WHERE id = 'eeee0000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO r VALUES ('11 update del proyecto que creó (no miembro)', '0 filas', v_n::text || ' fila(s)', v_n = 0);

  -- Sin esto el creador se re-asigna por API y recupera lo que 01 le quitó.
  BEGIN
    UPDATE tareas_asignados SET activo = true WHERE id = 'eeee0000-0000-4000-8000-000000000201';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    INSERT INTO r VALUES ('12 re-asignarse a la tarea que creó', 'RECHAZO o 0 filas',
      v_n::text || ' fila(s)', v_n = 0);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('12 re-asignarse a la tarea que creó', 'RECHAZO o 0 filas',
      SQLSTATE || ' ' || v_err, SQLSTATE = '42501');
  END;

  BEGIN
    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
    VALUES ('eeee0000-0000-4000-8000-000000000001', '48b90421-a639-4637-b361-501fa7e1a1a0');
    INSERT INTO r VALUES ('13 agregar miembro sin la función', 'RECHAZO', 'paso', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('13 agregar miembro sin la función', 'RECHAZO', SQLSTATE || ' ' || v_err,
      SQLSTATE = '42501');
  END;

  -- Siembra: un proyecto recién creado todavía no tiene miembros, y sin esta
  -- rama tareas_proyectos_crear no alcanzaría para crear nada.
  BEGIN
    INSERT INTO tareas_proyectos (id, nombre, visibilidad, creado_por)
    VALUES ('eeee0000-0000-4000-8000-000000000003', 'RLS vis nuevo', 'privado',
            '48b90421-a639-4637-b361-501fa7e1a1a0');
    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
    VALUES ('eeee0000-0000-4000-8000-000000000003', '48b90421-a639-4637-b361-501fa7e1a1a0');
    INSERT INTO r VALUES ('14 sembrar miembros de un proyecto nuevo', 'OK', 'OK', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('14 sembrar miembros de un proyecto nuevo', 'OK', SQLSTATE || ' ' || v_err, false);
  END;

  BEGIN
    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
    VALUES ('eeee0000-0000-4000-8000-000000000003', '015fa985-fe21-4434-b3c5-7ac78732d765');
    INSERT INTO r VALUES ('15 segundo miembro sin la función', 'RECHAZO', 'paso', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('15 segundo miembro sin la función', 'RECHAZO', SQLSTATE || ' ' || v_err,
      SQLSTATE = '42501');
  END;
END $$;

RESET ROLE;

-- Con la función activada, lo que 13 rechazó pasa.
UPDATE usuario_submodulos us SET activo = true
FROM submodulos s
WHERE s.id = us.submodulo_id
  AND s.codigo = 'tareas_proyectos_miembros'
  AND us.usuario_id = '48b90421-a639-4637-b361-501fa7e1a1a0';

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT '48b90421-a639-4637-b361-501fa7e1a1a0', id FROM submodulos WHERE codigo = 'tareas_proyectos_miembros'
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_err text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"48b90421-a639-4637-b361-501fa7e1a1a0","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
    VALUES ('eeee0000-0000-4000-8000-000000000001', '48b90421-a639-4637-b361-501fa7e1a1a0');
    INSERT INTO r VALUES ('16 agregar miembro con la función', 'OK', 'OK', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('16 agregar miembro con la función', 'OK', SQLSTATE || ' ' || v_err, false);
  END;
END $$;

RESET ROLE;

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
