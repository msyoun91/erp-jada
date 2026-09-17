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

-- ─── F2 (sql/077): columnas, reactivar, vínculos y acceso de asignados ───────
-- grants por columna, validar_reactivar_tarea, tareas_puede_gestionar_tarea,
-- tareas_vinculos_insert/update, tareas_asignado_puede_abrir,
-- tareas_asignados_insert/update.
-- Último resultado: 14/14.
DO $t$
DECLARE
  a uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  t uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  t_hib uuid := gen_random_uuid(); t_arch uuid := gen_random_uuid(); t_pub uuid := gen_random_uuid();
  t_mia uuid := gen_random_uuid(); t_priv uuid := gen_random_uuid(); t_vinc uuid := gen_random_uuid();
  v_nota uuid := gen_random_uuid();
  n int; ok int := 0; total int := 0; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO tareas (id, titulo, responsable_id, creado_por, modo_completado) VALUES (t_hib, 'Híbrida de ADMIN', a, a, 'hibrido');
  INSERT INTO tareas (id, titulo, responsable_id, creado_por, activo) VALUES (t_arch, 'Archivada', a, a, false);
  INSERT INTO tareas (id, titulo, responsable_id, creado_por, visibilidad) VALUES (t_pub, 'Pública de ADMIN', a, a, 'publico');
  INSERT INTO tareas (id, titulo, responsable_id, creado_por) VALUES (t_mia, 'De TESTER', t, t);
  INSERT INTO tareas (id, titulo, responsable_id, creado_por) VALUES (t_priv, 'Privada de ADMIN', a, a);
  INSERT INTO tareas (id, titulo, responsable_id, creado_por) VALUES (t_vinc, 'Relacionada con la privada', a, a);
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES
    (t_hib, t), (t_arch, t), (t_pub, a), (t_mia, t), (t_priv, a), (t_vinc, a);
  INSERT INTO tareas_notas (id, tarea_id, usuario_id, nota) VALUES (v_nota, t_mia, t, 'original');
  INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES
    (t_pub, 'tarea', t_mia), (t_mia, 'tarea', t_pub), (t_vinc, 'tarea', t_priv);

  UPDATE usuario_submodulos us SET activo = (s.codigo = 'tareas_lista')
    FROM submodulos s WHERE s.id = us.submodulo_id AND us.usuario_id = t AND s.modulo = 'tareas';
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT t, s.id FROM submodulos s WHERE s.codigo = 'tareas_lista'
     AND NOT EXISTS (SELECT 1 FROM usuario_submodulos us WHERE us.usuario_id = t AND us.submodulo_id = s.id);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', t, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  total := total + 1;
  BEGIN
    UPDATE tareas SET estado = 'completada', modo_completado = 'manual' WHERE id = t_hib;
    r := r || E'\nFALLO 01 completar híbrida pasándola a manual: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 01: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas SET creado_por = a WHERE id = t_mia;
    r := r || E'\nFALLO 02 falsear creado_por: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 02: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas SET origen_punto = '//fuera' WHERE id = t_mia;
    r := r || E'\nFALLO 03 cambiar origen_punto: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 03: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas_notas SET nota = 'reescrita' WHERE id = v_nota;
    r := r || E'\nFALLO 04 reescribir una nota: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 04: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas SET activo = true WHERE id = t_arch;
    r := r || E'\nFALLO 05 asignado revive archivada: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'TA018' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 05: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  UPDATE tareas_vinculos SET activo = false WHERE tarea_id = t_pub;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 07 quien solo ve apaga un vínculo: ' || n || ' filas'; END IF;

  total := total + 1;
  UPDATE tareas_vinculos SET activo = false WHERE tarea_id = t_mia;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 1 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 08 asignado apaga vínculo propio: ' || n || ' filas'; END IF;

  total := total + 1;
  BEGIN
    UPDATE tareas_vinculos SET activo = true WHERE tarea_id = t_mia;
    r := r || E'\nFALLO 09 reactivar un vínculo por UPDATE: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 09: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES (t_pub, 'tarea', t_hib);
    r := r || E'\nFALLO 10 relacionar en tarea que solo ve: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 10: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas SET temperatura = 85 WHERE id = t_mia;
    UPDATE tareas_notas SET activo = false WHERE id = v_nota;
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 11 temperatura y ocultar nota propia: ' || SQLSTATE;
  END;

  -- ── ADMIN ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);

  total := total + 1;
  BEGIN
    UPDATE tareas SET activo = true WHERE id = t_arch;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 1 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 06 admin revive: ' || n || ' filas'; END IF;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 06 admin revive: ' || SQLSTATE;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (t_vinc, t);
    r := r || E'\nFALLO 12 asignado directo sin acceso a lo relacionado: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 12: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    PERFORM reasignar_tarea(t_vinc, a, ARRAY[a, t]);
    SELECT count(*) INTO n FROM tareas_asignados WHERE tarea_id = t_vinc AND usuario_id = t AND activo;
    IF n = 0 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 13 reasignar filtra al que no puede abrir: quedó asignado'; END IF;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 13 reasignar: ' || SQLSTATE || ' ' || SQLERRM;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES (t_pub, 'tarea', t_hib);
    ok := ok + 1;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 14 admin relaciona en cualquier tarea: ' || SQLSTATE;
  END;

  RAISE EXCEPTION 'F2: %/% %', ok, total, r;
END $t$;

-- ─── F3 (sql/078): deshacer con pasos, fecha de Argentina, largos ────────────
-- deshacer_conversion_hilo, SET timezone de las funciones con fechas, CHECK de
-- largos. El 06 confirma que asignados NULL ya caían en quien crea (el punto 16
-- de la auditoría no era bug).
-- Último resultado: 6/6.
DO $t$
DECLARE
  a uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  h uuid := gen_random_uuid(); p1 uuid := gen_random_uuid(); p2 uuid := gen_random_uuid(); p3 uuid := gen_random_uuid();
  v uuid; n int; ok int := 0; total int := 0; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;
  INSERT INTO tareas_hilos (id, titulo, responsable_id, creado_por) VALUES (h, 'Cadena a deshacer', a, a);
  INSERT INTO tareas (id, hilo_id, titulo, responsable_id, creado_por, created_at) VALUES (p1, h, 'p1', a, a, now() - interval '2 min');
  INSERT INTO tareas (id, hilo_id, titulo, responsable_id, creado_por, paso_anterior_id, created_at) VALUES (p2, h, 'p2', a, a, p1, now() - interval '1 min');
  INSERT INTO tareas (id, hilo_id, titulo, responsable_id, creado_por, paso_anterior_id) VALUES (p3, h, 'p3', a, a, p2);
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (p1, a), (p2, a), (p3, a);

  total := total + 1;
  SELECT count(*) INTO n FROM pg_proc
   WHERE proname IN ('reactivar_posponer_vencidos', 'fijar_vencimiento_tras_previo', 'arrancar_vencimiento_siguiente',
                     'generar_recurrencia', 'usar_plantilla', 'notificaciones_avisos')
     AND 'TimeZone=America/Argentina/Buenos_Aires' = ANY(proconfig);
  IF n = 6 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 02 funciones con zona AR: ' || n || ' de 6'; END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  total := total + 1;
  BEGIN
    PERFORM deshacer_conversion_hilo(h);
    PERFORM set_config('role', 'none', true);
    SELECT count(*) INTO n FROM tareas WHERE id = p1 AND hilo_id IS NULL AND activo;
    SELECT n + count(*) INTO n FROM tareas WHERE id IN (p2, p3) AND NOT activo;
    IF n = 3 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 01 deshacer con pasos: ' || n || ' de 3'; END IF;
    PERFORM set_config('role', 'authenticated', true);
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 01 deshacer con pasos: ' || SQLSTATE || ' ' || SQLERRM;
  END;

  total := total + 1;
  BEGIN
    PERFORM crear_tarea(repeat('x', 501), NULL, NULL, NULL, NULL, 'privado', a, ARRAY[a], NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
    r := r || E'\nFALLO 03 título de 501: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '23514' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 03: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    PERFORM crear_tarea('origen afuera', NULL, NULL, NULL, NULL, 'privado', a, ARRAY[a], NULL, 50, NULL, NULL, 'manual', 'x', '//evil.example', NULL);
    r := r || E'\nFALLO 04 origen_punto externo: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '23514' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 04: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_notas (tarea_id, usuario_id, nota) VALUES (p1, a, repeat('x', 5001));
    r := r || E'\nFALLO 05 nota de 5001: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '23514' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 05: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    v := crear_tarea('sin asignados', NULL, NULL, NULL, NULL, 'privado', a, NULL, NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
    PERFORM set_config('role', 'none', true);
    SELECT count(*) INTO n FROM tareas_asignados WHERE tarea_id = v AND usuario_id = a AND activo;
    IF n = 1 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 06 asignados NULL: ' || n || ' asignados'; END IF;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 06 asignados NULL: ' || SQLSTATE || ' ' || SQLERRM;
  END;

  RAISE EXCEPTION 'F3: %/% %', ok, total, r;
END $t$;

-- ─── F4 (sql/079): plantillas ────────────────────────────────────────────────
-- tareas_plantillas_select, tareas_plantillas_activaciones_insert/update,
-- tareas_plantillas_items_update.
-- Último resultado: 7/7.
DO $t$
DECLARE
  a uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  t uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  pl_t uuid := gen_random_uuid(); pl_a uuid := gen_random_uuid(); it uuid := gen_random_uuid();
  n int; ok int := 0; total int := 0; r text := '';
BEGIN
  INSERT INTO tareas_plantillas (id, nombre, creado_por, alcance, tipo, disparo_ente, disparo_evento)
    VALUES (pl_t, 'Privada de TESTER', t, 'privada', 'tarea', 'obra', 'alta');
  INSERT INTO tareas_plantillas_items (id, plantilla_id, titulo, asignados, incluir_ejecutor, responsable_id)
    VALUES (it, pl_t, 'Paso para ADMIN', ARRAY[a], false, a);
  INSERT INTO tareas_plantillas (id, nombre, creado_por, alcance, tipo) VALUES (pl_a, 'Privada de ADMIN', a, 'privada', 'tarea');

  UPDATE usuario_submodulos us SET activo = (s.codigo IN ('tareas_lista', 'tareas_plantillas'))
    FROM submodulos s WHERE s.id = us.submodulo_id AND us.usuario_id = t AND s.modulo = 'tareas';
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT t, s.id FROM submodulos s WHERE s.codigo IN ('tareas_lista', 'tareas_plantillas')
     AND NOT EXISTS (SELECT 1 FROM usuario_submodulos us WHERE us.usuario_id = t AND us.submodulo_id = s.id);

  -- ── ADMIN ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  total := total + 1;
  SELECT count(*) INTO n FROM tareas_plantillas WHERE id = pl_t;
  IF n = 1 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 01 admin ve la privada ajena'; END IF;

  total := total + 1;
  SELECT count(*) INTO n FROM tareas_plantillas_items WHERE plantilla_id = pl_t;
  IF n = 1 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 02 admin ve sus pasos'; END IF;

  total := total + 1;
  UPDATE tareas_plantillas SET nombre = 'pisada' WHERE id = pl_t;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 03 admin edita la privada ajena: ' || n || ' filas'; END IF;

  total := total + 1;
  BEGIN
    INSERT INTO tareas_plantillas_activaciones (plantilla_id, usuario_id) VALUES (pl_t, a);
    r := r || E'\nFALLO 04 admin activa el disparador de una privada ajena: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 04: ' || SQLSTATE; END IF;
  END;

  -- ── TESTER, dueño, sin tareas_asignar ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t, 'role', 'authenticated')::text, true);

  total := total + 1;
  BEGIN
    UPDATE tareas_plantillas_items SET titulo = 'retocado' WHERE id = it;
    r := r || E'\nFALLO 05 sin asignar, dejar un paso activo con asignado ajeno: no rechazó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN ok := ok + 1; ELSE r := r || E'\nFALLO 05: ' || SQLSTATE; END IF;
  END;

  total := total + 1;
  BEGIN
    UPDATE tareas_plantillas_items SET activo = false WHERE id = it;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 1 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 06 apagar el paso: ' || n || ' filas'; END IF;
  EXCEPTION WHEN OTHERS THEN r := r || E'\nFALLO 06 apagar el paso: ' || SQLSTATE;
  END;

  total := total + 1;
  SELECT count(*) INTO n FROM tareas_plantillas WHERE id = pl_a;
  IF n = 0 THEN ok := ok + 1; ELSE r := r || E'\nFALLO 07 sin la función ve una privada ajena'; END IF;

  RAISE EXCEPTION 'F4: %/% %', ok, total, r;
END $t$;
