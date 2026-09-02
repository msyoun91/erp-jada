-- Verificación de las cuatro funciones de sql/024.
-- NO es una migración: todo corre dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción entera se revierte — no persiste ningún
-- dato. Los resultados salen en el mensaje del error (ese es el reporte).
--
-- Mismo andamiaje que atomicidad_tareas.sql: el rol se mueve en los dos
-- sentidos dentro del mismo DO — `authenticated` + `request.jwt.claims` para
-- llamar las funciones (sin eso corren como superusuario y RLS no aplica),
-- `role = none` para contar (la inconsistencia que se busca puede estar
-- escondida detrás de una policy).
--
-- Lo que estas tres funciones evitan no es una fila invisible sino una fila
-- **a medio guardar**: el título cambiado con los asignados viejos. Por eso
-- los casos de rechazo comparan el estado posterior contra el previo.
--
-- Volver a correrlo entero después de tocar sql/024.
--
-- Último resultado: 18/18. Los casos 03 y 09 rechazan con 42501 — es la
-- policy de tareas_asignados cortando el INSERT del asignado no miembro; lo
-- que se verifica es lo de al lado, que nada quedó a medio guardar.

DO $test$
DECLARE
  v_admin    uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester   uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER, no miembro
  v_fantasma uuid := '00000000-0000-4000-8000-0000000000ff';  -- no existe en usuarios
  v_proy     uuid;
  v_proy_b   uuid;
  v_tarea    uuid;
  v_suelta   uuid;
  v_n        int;
  v_txt      text;
  r          text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- Setup, como usuario de sesión ----------
  INSERT INTO tareas_proyectos (nombre, visibilidad, creado_por)
    VALUES ('P edicion', 'privado', v_admin) RETURNING id INTO v_proy;
  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES (v_proy, v_admin);

  -- Segundo proyecto sin TESTER: mover una tarea acá con TESTER asignado
  -- dispara validar_proyecto_tarea (TA002).
  INSERT INTO tareas_proyectos (nombre, visibilidad, creado_por)
    VALUES ('P destino', 'privado', v_admin) RETURNING id INTO v_proy_b;
  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES (v_proy_b, v_admin);

  INSERT INTO tareas (proyecto_id, titulo, responsable_id, creado_por)
    VALUES (v_proy, 'T original', v_admin, v_admin) RETURNING id INTO v_tarea;
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (v_tarea, v_admin);

  -- Tarea sin proyecto: cualquiera puede estar asignado (es_miembro_proyecto_de_tarea
  -- devuelve true si la tarea no tiene proyecto), así que sirve para probar el
  -- camino feliz de reasignar_tarea hacia otro usuario.
  INSERT INTO tareas (titulo, responsable_id, creado_por, visibilidad)
    VALUES ('T suelta', v_admin, v_admin, 'publico') RETURNING id INTO v_suelta;
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (v_suelta, v_admin);

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
  -- editar_tarea
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM editar_tarea(v_tarea, 'T editada', 'desc nueva', v_proy, 'publico',
                       v_admin, ARRAY[v_admin], NULL, 70, NULL, NULL);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas
   WHERE id = v_tarea AND titulo = 'T editada' AND descripcion = 'desc nueva'
     AND visibilidad = 'publico' AND temperatura = 70;
  r := r || E'\n01 editar_tarea: campos guardados: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_tarea AND activo;
  r := r || E'\n02 el conjunto igual no reescribe asignados: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' activos)' END;

  -- Mover al proyecto destino con TESTER asignado: el UPDATE de la tarea pasa,
  -- el INSERT de asignados lo rechaza es_miembro_proyecto_de_tarea. Antes de
  -- 024 el título quedaba cambiado con los asignados viejos.
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM editar_tarea(v_tarea, 'T a medias', NULL, v_proy_b, 'publico',
                         v_admin, ARRAY[v_admin, v_tester], NULL, 70, NULL, NULL);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n03 editar_tarea con asignado no miembro: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n03 editar_tarea con asignado no miembro: rechazo ' || SQLSTATE;
  END;

  SELECT titulo INTO v_txt FROM tareas WHERE id = v_tarea;
  r := r || E'\n04 el rechazo no dejó la tarea a medio editar: ' ||
    CASE WHEN v_txt = 'T editada' THEN 'OK' ELSE 'FALLO (título = ' || v_txt || ')' END;

  SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_tarea AND activo;
  r := r || E'\n05 ni los asignados a medio sincronizar: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' activos)' END;

  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM editar_tarea(v_fantasma, 'T inexistente', NULL, NULL, 'privado',
                         v_admin, ARRAY[v_admin], NULL, 50, NULL, NULL);
    r := r || E'\n06 editar una tarea que no existe: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n06 editar una tarea que no existe: ' ||
      CASE WHEN SQLSTATE = 'TA008' THEN 'OK (TA008)' ELSE 'FALLO (' || SQLSTATE || ')' END;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- reasignar_tarea
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM reasignar_tarea(v_suelta, v_tester, ARRAY[v_tester]);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas t
   WHERE t.id = v_suelta AND t.responsable_id = v_tester
     AND (SELECT count(*) FROM tareas_asignados a
           WHERE a.tarea_id = t.id AND a.activo AND a.usuario_id = v_tester) = 1
     AND NOT EXISTS (SELECT 1 FROM tareas_asignados a
                      WHERE a.tarea_id = t.id AND a.activo AND a.usuario_id = v_admin);
  r := r || E'\n07 reasignar_tarea: responsable y asignados juntos: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas_asignados
   WHERE tarea_id = v_suelta AND usuario_id = v_admin AND NOT activo;
  r := r || E'\n08 el asignado anterior queda desactivado, no borrado: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' filas)' END;

  -- La tarea del proyecto con un asignado que no es miembro: el UPDATE del
  -- responsable pasa, el INSERT no. Ninguno debe sobrevivir.
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM reasignar_tarea(v_tarea, v_admin, ARRAY[v_admin, v_tester]);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n09 reasignar con asignado no miembro: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n09 reasignar con asignado no miembro: rechazo ' || SQLSTATE;
  END;

  SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_tarea AND activo;
  r := r || E'\n10 la tarea rechazada conserva su asignado: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' activos)' END;

  -- ============================================================
  -- editar_proyecto
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM editar_proyecto(v_proy, 'P renombrado', 'desc', 'publico',
                          ARRAY[v_admin, v_tester]);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_proyectos
   WHERE id = v_proy AND nombre = 'P renombrado' AND visibilidad = 'publico';
  r := r || E'\n11 editar_proyecto: campos guardados: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros
   WHERE proyecto_id = v_proy AND activo;
  r := r || E'\n12 miembro agregado sin tocar al que ya estaba: ' ||
    CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ' miembros)' END;

  -- Quitar a TESTER: no tiene tareas en el proyecto, así que validar_quitar_miembro
  -- lo deja pasar y ADMIN, que sí tiene, no se toca porque el diff no lo incluye.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM editar_proyecto(v_proy, 'P renombrado', 'desc', 'publico', ARRAY[v_admin]);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros
   WHERE proyecto_id = v_proy AND activo AND usuario_id = v_admin;
  r := r || E'\n13 el diff no barre al miembro con tareas activas: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  -- Quitar a ADMIN, que tiene una tarea activa en el proyecto: TA001. El
  -- nombre no puede quedar cambiado por un guardado que falló.
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM editar_proyecto(v_proy, 'P a medias', 'desc', 'publico', ARRAY[v_tester]);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n14 quitar un miembro con tareas activas: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n14 quitar un miembro con tareas activas: ' ||
      CASE WHEN SQLSTATE = 'TA001' THEN 'OK (TA001)' ELSE 'rechazo ' || SQLSTATE END;
  END;

  SELECT nombre INTO v_txt FROM tareas_proyectos WHERE id = v_proy;
  r := r || E'\n15 el rechazo no dejó el proyecto a medio editar: ' ||
    CASE WHEN v_txt = 'P renombrado' THEN 'OK' ELSE 'FALLO (nombre = ' || v_txt || ')' END;

  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM editar_proyecto(v_fantasma, 'P inexistente', NULL, 'privado', ARRAY[v_admin]);
    r := r || E'\n16 editar un proyecto que no existe: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n16 editar un proyecto que no existe: ' ||
      CASE WHEN SQLSTATE = 'TA008' THEN 'OK (TA008)' ELSE 'FALLO (' || SQLSTATE || ')' END;
  END;
  PERFORM set_config('role', 'none', true);

  RAISE EXCEPTION E'RESULTADO:%\n', r;
END;
$test$;
