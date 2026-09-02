-- Verificación de las seis funciones de sql/023.
-- NO es una migración: todo corre dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción entera se revierte — no persiste ningún
-- dato. Los resultados salen en el mensaje del error (ese es el reporte).
--
-- Va como DO y no como `BEGIN; ... ROLLBACK;` por el mismo motivo que
-- pasos_tarea.sql: cada llamada del MCP de Supabase es su propia transacción.
--
-- El rol se mueve en los dos sentidos dentro del mismo DO:
--   * `authenticated` + `request.jwt.claims` para llamar las funciones — sin
--     eso corren como superusuario, RLS no aplica y el test no prueba nada.
--   * `role = none` (vuelve al usuario de sesión) para **contar**. Las filas
--     huérfanas que el punto 2 buscaba evitar son justamente invisibles bajo
--     RLS: contarlas como `authenticated` daría 0 aunque existieran, y todos
--     los casos de atomicidad pasarían en falso. El caso 00b verifica que ese
--     regreso realmente ocurre.
--
-- `SET CONSTRAINTS ALL IMMEDIATE` al principio hace observable a
-- trg_validar_desactivar_paso, que es DEFERRABLE INITIALLY DEFERRED y de otro
-- modo correría recién en un COMMIT que acá nunca llega.
--
-- Volver a correrlo entero después de tocar sql/023.
--
-- Último resultado: 15/15.

DO $test$
DECLARE
  v_admin   uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester  uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER, no miembro
  v_fantasma uuid := '00000000-0000-4000-8000-0000000000ff'; -- no existe en usuarios
  v_proy    uuid;
  v_plant   uuid;
  v_vacia   uuid;
  v_hilo_p  uuid;   -- hilo dentro del proyecto
  v_hilo_d  uuid;   -- hilo para deshacer
  v_hilo_x  uuid;   -- hilo para desactivar
  v_tarea   uuid;
  v_id      uuid;
  v_n       int;
  r         text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- Setup, como usuario de sesión ----------
  INSERT INTO tareas_proyectos (nombre, visibilidad, creado_por)
    VALUES ('P atomicidad', 'privado', v_admin) RETURNING id INTO v_proy;
  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES (v_proy, v_admin);

  INSERT INTO tareas_plantillas (nombre, creado_por)
    VALUES ('PL atomicidad', v_admin) RETURNING id INTO v_plant;
  INSERT INTO tareas_plantillas_items (plantilla_id, titulo, orden) VALUES
    (v_plant, 'Paso A', 1), (v_plant, 'Paso B', 2), (v_plant, 'Paso C', 3);

  INSERT INTO tareas_plantillas (nombre, creado_por)
    VALUES ('PL vacia', v_admin) RETURNING id INTO v_vacia;

  INSERT INTO tareas_hilos (proyecto_id, titulo, responsable_id, creado_por)
    VALUES (v_proy, 'H en proyecto', v_admin, v_admin) RETURNING id INTO v_hilo_p;

  INSERT INTO tareas_hilos (proyecto_id, titulo, responsable_id, creado_por)
    VALUES (v_proy, 'H deshacer', v_admin, v_admin) RETURNING id INTO v_hilo_d;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por, created_at)
    VALUES (v_hilo_d, 'D primera', v_admin, v_admin, now() - interval '2 hour');
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por, created_at)
    VALUES (v_hilo_d, 'D segunda', v_admin, v_admin, now() - interval '1 hour');

  INSERT INTO tareas_hilos (titulo, responsable_id, creado_por)
    VALUES ('H desactivar', v_admin, v_admin) RETURNING id INTO v_hilo_x;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por)
    VALUES (v_hilo_x, 'X tarea', v_admin, v_admin);

  INSERT INTO tareas (proyecto_id, titulo, responsable_id, creado_por)
    VALUES (v_proy, 'C convertible', v_admin, v_admin) RETURNING id INTO v_tarea;
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (v_tarea, v_admin);

  -- ---------- Chequeo del andamiaje ----------
  PERFORM set_config('request.jwt.claims',
    '{"sub":"015fa985-fe21-4434-b3c5-7ac78732d765","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);

  r := r || E'\n00a rol authenticated + uid ADMIN: ' ||
    CASE WHEN current_user = 'authenticated' AND auth.uid() = v_admin
         THEN 'OK' ELSE 'FALLO (' || current_user || ')' END;

  PERFORM set_config('role', 'none', true);
  r := r || E'\n00b vuelta al usuario de sesión: ' ||
    CASE WHEN current_user = session_user THEN 'OK'
         ELSE 'FALLO (' || current_user || ') — los conteos de abajo no valen' END;

  -- ============================================================
  -- crear_tarea
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  v_id := crear_tarea('T feliz', NULL, NULL, v_proy, NULL, 'privado', v_admin,
                      ARRAY[v_admin], NULL, 50, NULL, NULL, 'manual', NULL, NULL);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_id AND activo;
  r := r || E'\n01 crear_tarea: tarea + 1 asignado: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' asignados)' END;

  -- TESTER no es miembro del proyecto: el INSERT de asignados lo rechaza
  -- (es_miembro_proyecto_de_tarea). La tarea no puede sobrevivir a eso.
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    v_id := crear_tarea('T huerfana', NULL, NULL, v_proy, NULL, 'privado', v_admin,
                        ARRAY[v_admin, v_tester], NULL, 50, NULL, NULL, 'manual', NULL, NULL);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n02 crear_tarea con asignado no miembro: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n02 crear_tarea con asignado no miembro: rechazo ' || SQLSTATE;
  END;

  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'T huerfana';
  r := r || E'\n03 la tarea rechazada no quedó huérfana: ' ||
    CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ' filas invisibles)' END;

  -- ============================================================
  -- crear_proyecto
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  v_id := crear_proyecto('P feliz', NULL, 'privado', ARRAY[v_admin]);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros WHERE proyecto_id = v_id AND activo;
  r := r || E'\n04 crear_proyecto: proyecto + 1 miembro: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' miembros)' END;

  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    v_id := crear_proyecto('P huerfano', NULL, 'privado', ARRAY[v_admin, v_fantasma]);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n05 crear_proyecto con miembro inexistente: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n05 crear_proyecto con miembro inexistente: rechazo ' || SQLSTATE;
  END;

  SELECT count(*) INTO v_n FROM tareas_proyectos WHERE nombre = 'P huerfano';
  r := r || E'\n06 el proyecto rechazado no quedó sin miembros: ' ||
    CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ' filas)' END;

  -- ============================================================
  -- convertir_tarea_en_hilo
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  v_id := convertir_tarea_en_hilo(v_tarea);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas
   WHERE id = v_tarea AND hilo_id = v_id AND proyecto_id IS NULL;
  r := r || E'\n07 convertir_tarea_en_hilo: hilo nuevo + tarea movida: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    v_id := convertir_tarea_en_hilo(v_fantasma);
    r := r || E'\n08 convertir una tarea que no existe: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n08 convertir una tarea que no existe: ' ||
      CASE WHEN SQLSTATE = 'TA008' THEN 'OK (TA008)' ELSE 'FALLO (' || SQLSTATE || ')' END;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- agregar_tareas_desde_plantilla
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM agregar_tareas_desde_plantilla(v_plant, v_hilo_p, v_admin, ARRAY[v_admin]);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas WHERE hilo_id = v_hilo_p AND activo;
  r := r || E'\n09 plantilla de 3 items: ' ||
    CASE WHEN v_n = 3 THEN 'OK' ELSE 'FALLO (' || v_n || ' tareas)' END;

  SELECT count(*) INTO v_n FROM tareas WHERE hilo_id = v_hilo_p AND paso_anterior_id IS NOT NULL;
  r := r || E'\n10 los items quedaron encadenados: ' ||
    CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ' con previo)' END;

  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM agregar_tareas_desde_plantilla(v_vacia, v_hilo_p, v_admin, ARRAY[v_admin]);
    r := r || E'\n11 plantilla sin pasos: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n11 plantilla sin pasos: ' ||
      CASE WHEN SQLSTATE = 'TA009' THEN 'OK (TA009)' ELSE 'FALLO (' || SQLSTATE || ')' END;
  END;

  -- Un asignado que no es miembro corta en el primer paso: la cadena no puede
  -- quedar a medio crear.
  BEGIN
    PERFORM agregar_tareas_desde_plantilla(v_plant, v_hilo_p, v_admin, ARRAY[v_admin, v_tester]);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n12 plantilla con asignado no miembro: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n12 plantilla con asignado no miembro: rechazo ' || SQLSTATE;
  END;

  SELECT count(*) INTO v_n FROM tareas WHERE hilo_id = v_hilo_p AND activo;
  r := r || E'\n13 la cadena rechazada no dejó pasos sueltos: ' ||
    CASE WHEN v_n = 3 THEN 'OK' ELSE 'FALLO (' || v_n || ' tareas, esperaba 3)' END;

  -- ============================================================
  -- desactivar_hilo
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM desactivar_hilo(v_hilo_x);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_hilos h
   WHERE h.id = v_hilo_x AND NOT h.activo
     AND NOT EXISTS (SELECT 1 FROM tareas t WHERE t.hilo_id = h.id AND t.activo);
  r := r || E'\n14 desactivar_hilo: hilo y tareas abajo: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- deshacer_conversion_hilo
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM deshacer_conversion_hilo(v_hilo_d);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas
   WHERE titulo = 'D primera' AND hilo_id IS NULL AND proyecto_id = v_proy AND activo;
  r := r || E'\n15 deshacer_conversion_hilo: la más antigua vuelve al proyecto: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  RAISE EXCEPTION E'RESULTADO:%\n', r;
END;
$test$;
