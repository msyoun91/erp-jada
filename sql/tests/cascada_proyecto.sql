-- Verificación del trigger de sql/025 — archivar un proyecto se lleva sus
-- hilos, las tareas de esos hilos y sus tareas sueltas.
--
-- NO es una migración: todo corre dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción entera se revierte — no persiste ningún
-- dato. Los resultados salen en el mensaje del error (ese es el reporte).
--
-- Mismo andamiaje que atomicidad_tareas.sql: el rol se mueve en los dos
-- sentidos dentro del mismo DO. `authenticated` + `request.jwt.claims` para
-- disparar el UPDATE (sin eso corre como superusuario, RLS no aplica y el test
-- no prueba nada); `role = none` para contar, porque una fila desactivada bajo
-- RLS deja de verse y todos los conteos darían 0 en falso.
--
-- `SET CONSTRAINTS ALL IMMEDIATE` hace observable a trg_validar_desactivar_paso
-- (DEFERRABLE INITIALLY DEFERRED), que de otro modo correría recién en un
-- COMMIT que acá nunca llega: el caso 04 depende de que la cadena entera caiga
-- en una sola sentencia.
--
-- TESTER no tiene `tareas_gestionar_ajenas` ni `tareas_asignar` — de eso vive
-- el caso 08.
--
-- Volver a correrlo entero después de tocar sql/025.
--
-- Último resultado: 10/10.

DO $test$
DECLARE
  v_admin       uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester      uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_proy        uuid;   -- proyecto de ADMIN
  v_hilo        uuid;   -- hilo dentro del proyecto, con cadena de dos pasos
  v_paso1       uuid;
  v_hilo_fuera  uuid;   -- hilo sin proyecto: no lo tiene que tocar la cascada
  v_proy_t      uuid;   -- proyecto de TESTER
  v_hilo_t      uuid;   -- hilo de ese proyecto, con ADMIN de responsable
  v_n           int;
  r             text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- Setup, como usuario de sesión ----------
  INSERT INTO tareas_proyectos (nombre, visibilidad, creado_por)
    VALUES ('P cascada', 'privado', v_admin) RETURNING id INTO v_proy;
  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES (v_proy, v_admin);

  INSERT INTO tareas_hilos (proyecto_id, titulo, responsable_id, creado_por)
    VALUES (v_proy, 'H en cascada', v_admin, v_admin) RETURNING id INTO v_hilo;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por)
    VALUES (v_hilo, 'CP paso 1', v_admin, v_admin) RETURNING id INTO v_paso1;
  INSERT INTO tareas (hilo_id, paso_anterior_id, titulo, responsable_id, creado_por)
    VALUES (v_hilo, v_paso1, 'CP paso 2', v_admin, v_admin);

  INSERT INTO tareas (proyecto_id, titulo, responsable_id, creado_por)
    VALUES (v_proy, 'CP suelta', v_admin, v_admin);

  INSERT INTO tareas_hilos (titulo, responsable_id, creado_por)
    VALUES ('H fuera', v_admin, v_admin) RETURNING id INTO v_hilo_fuera;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por)
    VALUES (v_hilo_fuera, 'CP ajena', v_admin, v_admin);

  INSERT INTO tareas_proyectos (nombre, visibilidad, creado_por)
    VALUES ('P de tester', 'privado', v_tester) RETURNING id INTO v_proy_t;
  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id) VALUES (v_proy_t, v_tester);
  -- Responsable ADMIN a propósito: TESTER no puede tocar este hilo por RLS.
  INSERT INTO tareas_hilos (proyecto_id, titulo, responsable_id, creado_por)
    VALUES (v_proy_t, 'H de admin', v_admin, v_tester) RETURNING id INTO v_hilo_t;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por)
    VALUES (v_hilo_t, 'CP de admin', v_admin, v_admin);

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
  -- El trigger solo mira el paso de activo a inactivo
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas_proyectos SET nombre = 'P cascada (renombrado)' WHERE id = v_proy;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_hilos WHERE id = v_hilo AND activo;
  r := r || E'\n01 renombrar el proyecto no cascadea: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (el hilo cayó sin motivo)' END;

  -- ============================================================
  -- Archivar el proyecto
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas_proyectos SET activo = false WHERE id = v_proy;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM set_config('role', 'none', true);

  r := r || E'\n02 ADMIN archiva su proyecto: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' filas — RLS lo rechazó)' END;

  SELECT count(*) INTO v_n FROM tareas_hilos WHERE id = v_hilo AND NOT activo;
  r := r || E'\n03 el hilo del proyecto cae: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas WHERE hilo_id = v_hilo AND NOT activo;
  r := r || E'\n04 la cadena de dos pasos cae entera: ' ||
    CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ' de 2)' END;

  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'CP suelta' AND NOT activo;
  r := r || E'\n05 la tarea suelta del proyecto cae: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas_hilos h
   WHERE h.id = v_hilo_fuera AND h.activo
     AND EXISTS (SELECT 1 FROM tareas t WHERE t.hilo_id = h.id AND t.activo);
  r := r || E'\n06 lo que está fuera del proyecto no se toca: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros
   WHERE proyecto_id = v_proy AND activo;
  r := r || E'\n07 los miembros quedan (no son trabajo): ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- La cascada no se frena en la RLS de quien archiva
  -- ============================================================
  PERFORM set_config('request.jwt.claims',
    '{"sub":"48b90421-a639-4637-b361-501fa7e1a1a0","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);

  UPDATE tareas_hilos SET titulo = 'intento directo' WHERE id = v_hilo_t;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  r := r || E'\n08 TESTER no puede tocar ese hilo de frente: ' ||
    CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ' filas — la RLS lo dejó pasar)' END;

  UPDATE tareas_proyectos SET activo = false WHERE id = v_proy_t;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_hilos h
   WHERE h.id = v_hilo_t AND NOT h.activo
     AND NOT EXISTS (SELECT 1 FROM tareas t WHERE t.hilo_id = h.id AND t.activo);
  r := r || E'\n09 pero archivar el proyecto se lo lleva igual: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- Archivar es de ida
  -- ============================================================
  PERFORM set_config('request.jwt.claims',
    '{"sub":"015fa985-fe21-4434-b3c5-7ac78732d765","role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas_proyectos SET activo = true WHERE id = v_proy;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_hilos WHERE id = v_hilo AND NOT activo;
  r := r || E'\n10 reactivar el proyecto no revive lo de adentro: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  RAISE EXCEPTION E'RESULTADO:%\n', r;
END;
$test$;
