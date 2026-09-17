-- Verificación de la auditoría de tareas (PLAN_AUDITORIA_TAREAS.md), un bloque
-- por fase. NO es una migración: cada bloque es un DO que termina en RAISE
-- EXCEPTION, así que todo se revierte. El reporte sale en el mensaje del error.
--
-- ADMIN  015fa985-fe21-4434-b3c5-7ac78732d765 — tareas_gestionar_ajenas + tareas_asignar
-- TESTER 48b90421-a639-4637-b361-501fa7e1a1a0 — dentro del bloque queda solo con
--        tareas_lista, tareas_proyectos y tareas_proyectos_miembros
--
-- Volver a correr el bloque de una fase después de tocar lo que nombra su cabecera.

-- ─── F1 (sql/076): dónde se puede escribir ───────────────────────────────────
-- validar_destino_tarea, tareas_hilos_insert, grants de tareas_hilos,
-- tareas_proyectos_miembros_insert/update, tareas_sumar_miembros_admin,
-- validar_proyecto_tarea_miembros, crear_tarea, sincronizar_asignados.
-- Último resultado: 17/17.
DO $t$
DECLARE
  a uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  t uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  h_a uuid := gen_random_uuid(); h_t uuid := gen_random_uuid();
  p_priv uuid := gen_random_uuid(); p_pub uuid := gen_random_uuid(); p_pub2 uuid := gen_random_uuid();
  p_t uuid := gen_random_uuid(); p_a2 uuid := gen_random_uuid(); p_a3 uuid := gen_random_uuid();
  t_t uuid := gen_random_uuid(); t_suelta uuid := gen_random_uuid(); t_p2 uuid := gen_random_uuid();
  v uuid; n int; ok int := 0; total int := 0;
  r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- Fixtures como postgres
  INSERT INTO tareas_hilos (id, titulo, responsable_id, creado_por) VALUES
    (h_a, 'Hilo privado de ADMIN', a, a),
    (h_t, 'Hilo de TESTER', t, t);
  INSERT INTO tareas_proyectos (id, nombre, creado_por, visibilidad) VALUES
    (p_priv, 'Privado de ADMIN', a, 'privado'),
    (p_pub,  'Público de ADMIN', a, 'publico'),
    (p_pub2, 'Público 2 de ADMIN', a, 'publico'),
    (p_t,    'Privado con TESTER', a, 'privado'),
    (p_a2,   'Privado 2 de ADMIN', a, 'privado'),
    (p_a3,   'Privado 3 de ADMIN', a, 'privado');
  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES
    (p_priv, a), (p_pub, a), (p_pub2, a), (p_t, t), (p_a2, a), (p_a3, a);
  INSERT INTO tareas (id, titulo, responsable_id, creado_por) VALUES (t_t, 'Suelta de TESTER', t, t);
  INSERT INTO tareas (id, titulo, responsable_id, creado_por) VALUES (t_suelta, 'Suelta de ADMIN para TESTER', a, a);
  INSERT INTO tareas (id, titulo, responsable_id, creado_por, proyecto_id) VALUES (t_p2, 'En P2', a, a, p_a2);
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (t_t, t), (t_suelta, t), (t_p2, a);

  UPDATE usuario_submodulos us
     SET activo = (s.codigo IN ('tareas_lista', 'tareas_proyectos', 'tareas_proyectos_miembros'))
    FROM submodulos s
   WHERE s.id = us.submodulo_id AND us.usuario_id = t AND s.modulo = 'tareas';
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT t, s.id FROM submodulos s
   WHERE s.codigo IN ('tareas_lista', 'tareas_proyectos', 'tareas_proyectos_miembros')
     AND NOT EXISTS (SELECT 1 FROM usuario_submodulos us WHERE us.usuario_id = t AND us.submodulo_id = s.id);

  -- ── TESTER ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  total := total + 1;
  BEGIN
    INSERT INTO tareas (titulo, hilo_id, responsable_id, creado_por) VALUES ('intrusa', h_a, t, t);
    r := r || E'\nFALLO 01 tarea en hilo ajeno: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'TA017' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 01: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas SET hilo_id = h_a WHERE id = t_t;
    r := r || E'\nFALLO 02 mover tarea a hilo ajeno: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'TA017' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 02: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas (titulo, proyecto_id, responsable_id, creado_por) VALUES ('intrusa', p_priv, t, t);
    r := r || E'\nFALLO 03 tarea en proyecto privado ajeno: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'TA017' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 03: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_hilos (titulo, proyecto_id, visibilidad, responsable_id, creado_por)
      VALUES ('intruso', p_priv, 'publico', t, t);
    r := r || E'\nFALLO 04 hilo en proyecto privado ajeno: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 04: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas_hilos SET proyecto_id = p_t WHERE id = h_t;
    r := r || E'\nFALLO 05 mover hilo de proyecto: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 05: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas_hilos SET creado_por = a WHERE id = h_t;
    r := r || E'\nFALLO 06 falsear creado_por del hilo: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 06: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES (p_priv, t);
    r := r || E'\nFALLO 07 sumarse a proyecto privado ajeno: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 07: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES (p_t, a);
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 08 sumar miembro en proyecto propio: ' || SQLSTATE;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas (titulo, hilo_id, responsable_id, creado_por) VALUES ('en hilo propio', h_t, t, t);
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 09 tarea en hilo propio: ' || SQLSTATE;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas (titulo, proyecto_id, visibilidad, responsable_id, creado_por) VALUES ('en público', p_pub, 'publico', t, t);
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 10 tarea en proyecto público: ' || SQLSTATE;
  END;

  total := total + 1;
  BEGIN
    v := convertir_tarea_en_hilo(t_t);
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 11 convertir tarea propia en hilo: ' || SQLSTATE || ' ' || SQLERRM;
  END;

  -- ── ADMIN ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);

  total := total + 1;
  BEGIN
    INSERT INTO tareas (titulo, hilo_id, responsable_id, creado_por) VALUES ('admin en hilo ajeno', h_t, a, a);
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 12 admin tarea en hilo ajeno: ' || SQLSTATE;
  END;

  total := total + 1;
  BEGIN
    v := crear_tarea('para TESTER', NULL, NULL, p_priv, NULL, 'privado', t, ARRAY[t], NULL, 50,
                     NULL, NULL, 'manual', NULL, NULL, NULL, '[]'::jsonb);
    IF es_miembro_proyecto(p_priv, t) THEN ok := ok + 1;
    ELSE r := r || E'\nFALLO 13 admin asigna no miembro: no lo sumó al proyecto'; END IF;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 13 admin asigna no miembro: ' || SQLSTATE || ' ' || SQLERRM;
  END;

  total := total + 1;
  BEGIN
    PERFORM reasignar_tarea(t_p2, t, ARRAY[t]);
    SELECT count(*) INTO n FROM tareas_asignados WHERE tarea_id = t_p2 AND usuario_id = t AND activo;
    IF es_miembro_proyecto(p_a2, t) AND n = 1 THEN ok := ok + 1;
    ELSE r := r || E'\nFALLO 14 admin reasigna a no miembro: miembro=' || es_miembro_proyecto(p_a2, t) || ' asignado=' || n; END IF;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 14 admin reasigna a no miembro: ' || SQLSTATE || ' ' || SQLERRM;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas SET proyecto_id = p_a3 WHERE id = t_suelta;
    IF es_miembro_proyecto(p_a3, t) THEN ok := ok + 1;
    ELSE r := r || E'\nFALLO 15 admin mueve tarea a proyecto: no sumó al asignado'; END IF;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 15 admin mueve tarea a proyecto: ' || SQLSTATE || ' ' || SQLERRM;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
    SELECT p_pub, t WHERE NOT es_miembro_proyecto(p_pub, t);
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 16 admin suma miembro en cualquier proyecto: ' || SQLSTATE;
  END;

  -- ── TESTER sin la función admin: mover a un proyecto donde no es miembro sigue en TA002 ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t, 'role', 'authenticated')::text, true);
  total := total + 1;
  v := gen_random_uuid();
  INSERT INTO tareas (id, titulo, responsable_id, creado_por) VALUES (v, 'x', t, t);
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (v, t);
  BEGIN
    UPDATE tareas SET proyecto_id = p_pub2 WHERE id = v;
    r := r || E'\nFALLO 17 no miembro mueve a proyecto público: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'TA002' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 17: ' || SQLSTATE; END IF;
  END;

  RAISE EXCEPTION 'F1: %/% %', ok, total, r;
END $t$;
