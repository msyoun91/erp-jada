-- Verificación de los triggers de pasos de sql/017.
-- NO es una migración: todo corre dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción entera se revierte — no persiste ningún
-- dato. Los resultados salen en el mensaje del error (ese es el reporte).
--
-- Va como DO y no como `BEGIN; ... ROLLBACK;` (el estilo de
-- rls_miembros_asignables.sql) porque cada llamada del MCP de Supabase es su
-- propia transacción: un ROLLBACK explícito no se puede encadenar con los
-- SELECT que leen el resultado.
--
-- `SET CONSTRAINTS ALL IMMEDIATE` al principio es lo que hace observable a
-- trg_validar_desactivar_paso: siendo DEFERRABLE INITIALLY DEFERRED correría
-- recién al COMMIT, que acá nunca llega.
--
-- Volver a correrlo entero después de tocar validar_paso_tarea,
-- validar_paso_previo, validar_desactivar_paso o los CHECK de paso_anterior_id.
--
-- Último resultado: 14/14.

DO $test$
DECLARE
  v_user uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_hilo uuid; v_hilo2 uuid;
  t1 uuid; t2 uuid;
  r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO tareas_hilos (titulo, responsable_id, creado_por)
    VALUES ('H1 test pasos', v_user, v_user) RETURNING id INTO v_hilo;
  INSERT INTO tareas_hilos (titulo, responsable_id, creado_por)
    VALUES ('H2 test pasos', v_user, v_user) RETURNING id INTO v_hilo2;

  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por)
    VALUES (v_hilo, 'Paso 1', v_user, v_user) RETURNING id INTO t1;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por, paso_anterior_id)
    VALUES (v_hilo, 'Paso 2', v_user, v_user, t1) RETURNING id INTO t2;
  r := r || E'\n01 crear cadena: OK';

  BEGIN
    UPDATE tareas SET estado = 'en_progreso' WHERE id = t2;
    r := r || E'\n02 avanzar con previo pendiente: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n02 avanzar con previo pendiente: ' || CASE WHEN SQLSTATE='TA004' THEN 'OK (TA004)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  -- La unique parcial, no un trigger: la cadena no bifurca.
  BEGIN
    INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por, paso_anterior_id)
      VALUES (v_hilo, 'Bifurca', v_user, v_user, t1);
    r := r || E'\n03 bifurcar la cadena: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n03 bifurcar la cadena: ' || CASE WHEN SQLSTATE='23505' THEN 'OK (23505 unique)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  BEGIN
    INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por, paso_anterior_id)
      VALUES (v_hilo2, 'Otro hilo', v_user, v_user, t1);
    r := r || E'\n04 previo en otro hilo: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n04 previo en otro hilo: ' || CASE WHEN SQLSTATE='TA005' THEN 'OK (TA005)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  -- La inmutabilidad es lo que vuelve imposible un ciclo: si este caso deja de
  -- rechazar, hay que agregar detección de ciclos en su lugar.
  BEGIN
    UPDATE tareas SET paso_anterior_id = NULL WHERE id = t2;
    r := r || E'\n05 cambiar el previo: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n05 cambiar el previo: ' || CASE WHEN SQLSTATE='TA005' THEN 'OK (TA005)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  BEGIN
    UPDATE tareas SET hilo_id = v_hilo2 WHERE id = t2;
    r := r || E'\n06 mover de hilo un paso: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n06 mover de hilo un paso: ' || CASE WHEN SQLSTATE='TA006' THEN 'OK (TA006)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  BEGIN
    UPDATE tareas SET recurrencia_cantidad = 1, recurrencia_unidad = 'dia' WHERE id = t1;
    r := r || E'\n07 recurrencia en tarea con siguiente: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n07 recurrencia en tarea con siguiente: ' || CASE WHEN SQLSTATE='TA005' THEN 'OK (TA005)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  BEGIN
    INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por, paso_anterior_id, recurrencia_cantidad, recurrencia_unidad)
      VALUES (v_hilo, 'Paso recurrente', v_user, v_user, t2, 1, 'dia');
    r := r || E'\n08 paso recurrente: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n08 paso recurrente: ' || CASE WHEN SQLSTATE='23514' THEN 'OK (23514 check)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  -- TA005 y no el CHECK tareas_paso_exige_hilo (23514): el trigger corre antes
  -- y frena por "el previo está en otro hilo" (hilo_id NULL es otro hilo). El
  -- CHECK queda de red, pero el mensaje que ve el usuario es el del trigger.
  BEGIN
    INSERT INTO tareas (titulo, responsable_id, creado_por, paso_anterior_id)
      VALUES ('Paso suelto', v_user, v_user, t2);
    r := r || E'\n09 paso sin hilo: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n09 paso sin hilo: ' || CASE WHEN SQLSTATE='TA005' THEN 'OK (TA005)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  -- Si esto rechazara, una cadena con un paso cancelado no se podría terminar
  -- nunca y su hilo no cerraría más.
  BEGIN
    UPDATE tareas SET estado = 'cancelada' WHERE id = t2;
    UPDATE tareas SET estado = 'pendiente' WHERE id = t2;
    r := r || E'\n10 cancelar con previo pendiente: OK (no bloquea)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n10 cancelar con previo pendiente: FALLO ('||SQLSTATE||')';
  END;

  BEGIN
    UPDATE tareas SET estado = 'completada' WHERE id = t1;
    UPDATE tareas SET estado = 'en_progreso' WHERE id = t2;
    r := r || E'\n11 avanzar con previo completado: OK';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n11 avanzar con previo completado: FALLO ('||SQLSTATE||')';
  END;

  BEGIN
    UPDATE tareas SET activo = false WHERE id = t1;
    r := r || E'\n12 desactivar paso del medio: FALLO (no rechazo)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n12 desactivar paso del medio: ' || CASE WHEN SQLSTATE='TA007' THEN 'OK (TA007)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  -- El par de 12: los AFTER ROW corren al final de la sentencia, así que el
  -- batch ve la cadena entera ya desactivada. Esto es lo que deja pasar a
  -- deshacerConversionHilo, que borra con un solo `.in(...)`.
  BEGIN
    UPDATE tareas SET activo = false WHERE id IN (t1, t2);
    r := r || E'\n13 desactivar la cadena entera en un UPDATE: OK';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n13 desactivar la cadena entera en un UPDATE: FALLO ('||SQLSTATE||')';
  END;

  -- Camino de `agregarTareasDesdePlantilla`: N pasos encadenados en un solo
  -- INSERT multi-fila. Depende de que el BEFORE ROW de la fila 2 vea la fila 1
  -- de la MISMA sentencia. Si esto deja de pasar, la plantilla tiene que
  -- insertar de a una fila por vez.
  DECLARE
    p1 uuid := gen_random_uuid();
    p2 uuid := gen_random_uuid();
    p3 uuid := gen_random_uuid();
  BEGIN
    INSERT INTO tareas (id, hilo_id, titulo, responsable_id, creado_por, paso_anterior_id) VALUES
      (p1, v_hilo2, 'Plantilla 1', v_user, v_user, NULL),
      (p2, v_hilo2, 'Plantilla 2', v_user, v_user, p1),
      (p3, v_hilo2, 'Plantilla 3', v_user, v_user, p2);
    r := r || E'\n14 cadena de plantilla en un INSERT multi-fila: OK';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n14 cadena de plantilla en un INSERT multi-fila: FALLO ('||SQLSTATE||')';
  END;

  RAISE EXCEPTION E'RESULTADOS:%', r;
END;
$test$;

-- ============================================================
-- Bloque 2 — con RLS real, no como owner
-- ============================================================
-- El bloque de arriba corre como `postgres`: ejercita los triggers pero
-- bypasea RLS. Este cambia a rol `authenticated` y setea request.jwt.claims
-- para que auth.uid() devuelva TESTER (mismo mecanismo que
-- rls_miembros_asignables.sql).
--
-- Lo que prueba es la premisa que sostiene todo el diseño: la cadena vive
-- dentro de un hilo, así que `puede_ver_hilo` cascadea y quien ve un paso ve
-- los previos SIN estar asignado a ellos. Si el caso 01 dejara de pasar, "ver
-- las tareas previas" necesitaría una función SECURITY DEFINER que devuelva
-- stubs, y habría que replantear la decisión de sql/017.
--
-- Los casos 03 y 05 distinguen "el trigger rechazó" de "RLS se lo comió en
-- silencio" mirando ROW_COUNT: un UPDATE denegado por RLS afecta 0 filas y no
-- tira error, y eso se leería como si el trigger estuviera funcionando.
--
-- TESTER no tiene tareas_gestionar_ajenas ni tareas_asignar — es el caso base
-- de un usuario común.
--
-- Último resultado: 5/5.

DO $test$
DECLARE
  admin_id  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  tester_id uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_hilo uuid; p1 uuid; p2 uuid; p3 uuid := gen_random_uuid();
  n int; r text := '';
BEGIN
  -- Setup como owner: cadena de 2 pasos en un hilo personal de ADMIN.
  -- TESTER queda asignado SOLO al paso 2.
  INSERT INTO tareas_hilos (titulo, responsable_id, creado_por)
    VALUES ('H rls pasos', admin_id, admin_id) RETURNING id INTO v_hilo;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por)
    VALUES (v_hilo, 'Paso 1 (de ADMIN)', admin_id, admin_id) RETURNING id INTO p1;
  INSERT INTO tareas (hilo_id, titulo, responsable_id, creado_por, paso_anterior_id)
    VALUES (v_hilo, 'Paso 2 (de TESTER)', tester_id, admin_id, p1) RETURNING id INTO p2;
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (p1, admin_id), (p2, tester_id);

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', tester_id, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';

  SELECT count(*) INTO n FROM tareas WHERE id = p1;
  r := r || E'\n01 TESTER ve el paso previo sin estar asignado: '
    || CASE WHEN n = 1 THEN 'OK (premisa del diseno)' ELSE 'FALLO (no lo ve)' END;

  SELECT count(*) INTO n FROM tareas WHERE hilo_id = v_hilo;
  r := r || E'\n02 TESTER ve la cadena entera: ' || n::text || ' de 2 '
    || CASE WHEN n = 2 THEN '(OK)' ELSE '(FALLO)' END;

  BEGIN
    UPDATE tareas SET estado = 'completada' WHERE id = p2;
    GET DIAGNOSTICS n = ROW_COUNT;
    r := r || E'\n03 TESTER completa el paso 2 con el previo pendiente: '
      || CASE WHEN n = 0 THEN 'FALLO (RLS lo comio en silencio)' ELSE 'FALLO (no rechazo)' END;
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n03 TESTER completa el paso 2 con el previo pendiente: '
      || CASE WHEN SQLSTATE='TA004' THEN 'OK (TA004)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  BEGIN
    INSERT INTO tareas (id, hilo_id, titulo, responsable_id, creado_por, paso_anterior_id)
      VALUES (p3, v_hilo, 'Paso 3 (creado por TESTER)', tester_id, tester_id, p2);
    INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (p3, tester_id);
    r := r || E'\n04 TESTER crea el siguiente paso y se asigna: OK';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n04 TESTER crea el siguiente paso y se asigna: FALLO ('||SQLSTATE||' - '||SQLERRM||')';
  END;

  BEGIN
    UPDATE tareas SET activo = false WHERE id = p2;
    GET DIAGNOSTICS n = ROW_COUNT;
    SET CONSTRAINTS ALL IMMEDIATE;
    r := r || E'\n05 TESTER desactiva un paso con siguiente activo: '
      || CASE WHEN n = 0 THEN 'FALLO (RLS lo comio en silencio)' ELSE 'FALLO (no rechazo)' END;
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n05 TESTER desactiva un paso con siguiente activo: '
      || CASE WHEN SQLSTATE='TA007' THEN 'OK (TA007)' ELSE 'FALLO ('||SQLSTATE||')' END;
  END;

  EXECUTE 'RESET ROLE';
  RAISE EXCEPTION E'RESULTADOS:%', r;
END;
$test$;
