-- Verificación de sql/053 (plantillas de sistema y privadas, vencimiento tras
-- el paso previo, siembra de asignados).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que atomicidad_tareas.sql: `authenticated`
-- + `request.jwt.claims` para actuar, `role = none` para contar sin RLS.
--
-- TESTER arranca sin `tareas_asignar`, sin `tareas_gestionar_ajenas` y sin
-- `tareas_plantillas_sistema`; dentro de la transacción recibe la vista
-- `tareas_plantillas` y, en el bloque de siembra, `tareas_asignar`.
--
-- Volver a correrlo entero después de tocar sql/053.
--
-- Último resultado: 22/22.

DO $test$
DECLARE
  v_admin   uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester  uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_pl      uuid;
  v_sis     uuid;
  v_proy    uuid;
  v_hilo    uuid;
  v_t1      uuid;
  v_t2      uuid;
  v_id      uuid;
  v_n       int;
  v_d       date;
  r         text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- TESTER recibe la vista de plantillas; `tareas_asignar` se le da y se le
  -- saca por bloque.
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos WHERE codigo = 'tareas_plantillas'
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (SELECT id FROM submodulos
                           WHERE codigo IN ('tareas_asignar', 'tareas_gestionar_ajenas', 'tareas_plantillas_sistema'));

  -- ============================================================
  -- Siembra de asignados (fix)
  -- ============================================================
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos WHERE codigo = 'tareas_asignar'
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    v_t1 := crear_tarea('S responsable ajeno', NULL, NULL, NULL, NULL, 'privado', v_admin,
                        ARRAY[v_admin, v_tester], NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
    r := r || E'\n01 con tareas_asignar, crear con responsable ajeno y 2 asignados: OK';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n01 con tareas_asignar, crear con responsable ajeno y 2 asignados: FALLO ' || SQLSTATE;
  END;

  -- TESTER se saca solo; ya hubo asignados, así que la siembra no lo deja volver.
  UPDATE tareas_asignados SET activo = false WHERE tarea_id = v_t1 AND usuario_id = v_tester;
  BEGIN
    INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (v_t1, v_tester);
    r := r || E'\n02 el creador que se sacó no vuelve a entrar por la siembra: FALLO (entró)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n02 el creador que se sacó no vuelve a entrar por la siembra: rechazo ' || SQLSTATE;
  END;
  PERFORM set_config('role', 'none', true);

  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id = (SELECT id FROM submodulos WHERE codigo = 'tareas_asignar');

  -- ============================================================
  -- Alcance: privada y sistema
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  v_pl := guardar_plantilla(NULL, 'PL privada tester', NULL, 'privada', 'hilo', 'privado', '{}',
    '[]'::jsonb,
    '[{"titulo":"A","vence_dias":2},{"titulo":"B","vence_dias":3,"vence_tras_previo":true}]'::jsonb);
  PERFORM set_config('role', 'none', true);
  r := r || E'\n03 TESTER crea una privada: OK';

  BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM guardar_plantilla(NULL, 'PL sistema tester', NULL, 'sistema', 'hilo', 'privado', '{}',
      '[]'::jsonb, '[{"titulo":"X"}]'::jsonb);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n04 sin la función no crea de sistema: FALLO (creó)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n04 sin la función no crea de sistema: rechazo ' || SQLSTATE;
  END;

  BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM guardar_plantilla(NULL, 'PL asigna a otro', NULL, 'privada', 'tarea', 'privado', '{}',
      '[]'::jsonb, format('[{"titulo":"X","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]', v_admin, v_admin)::jsonb);
    PERFORM set_config('role', 'none', true);
    r := r || E'\n05 sin tareas_asignar no guarda un paso asignado a otro: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'none', true);
    r := r || E'\n05 sin tareas_asignar no guarda un paso asignado a otro: rechazo ' || SQLSTATE;
  END;

  -- ADMIN (backfill de la función) crea una de sistema que asigna a ADMIN solo.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_sis := guardar_plantilla(NULL, 'PL sistema admin', NULL, 'sistema', 'hilo', 'privado', '{}',
    '[]'::jsonb, format('[{"titulo":"S1","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]', v_admin, v_admin)::jsonb);

  SELECT count(*) INTO v_n FROM tareas_plantillas WHERE id = v_pl;
  r := r || E'\n06 ADMIN no ve la privada de TESTER: ' ||
    CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO' END;
  PERFORM set_config('role', 'none', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM tareas_plantillas WHERE id = v_sis;
  r := r || E'\n07 TESTER ve la de sistema: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  BEGIN
    PERFORM guardar_plantilla(v_sis, 'PL sistema pisada', NULL, 'sistema', 'hilo', 'privado', '{}',
      '[]'::jsonb, '[{"titulo":"Z"}]'::jsonb);
    r := r || E'\n08 sin la función no edita una de sistema: FALLO (editó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n08 sin la función no edita una de sistema: rechazo ' || SQLSTATE;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- Forma de la plantilla
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM guardar_plantilla(NULL, 'PL tarea doble', NULL, 'privada', 'tarea', 'privado', '{}',
      '[]'::jsonb, '[{"titulo":"1"},{"titulo":"2"}]'::jsonb);
    r := r || E'\n09 tipo tarea con 2 pasos: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n09 tipo tarea con 2 pasos: ' || CASE WHEN SQLSTATE = 'TA010' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  BEGIN
    PERFORM guardar_plantilla(NULL, 'PL proyecto hilo vacío', NULL, 'privada', 'proyecto', 'privado', '{}',
      '[{"titulo":"H vacío","pasos":[]}]'::jsonb, '[{"titulo":"suelta"}]'::jsonb);
    r := r || E'\n10 hilo de plantilla sin pasos: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n10 hilo de plantilla sin pasos: ' || CASE WHEN SQLSTATE = 'TA009' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  -- Editar reemplaza los pasos.
  PERFORM guardar_plantilla(v_pl, 'PL privada tester', NULL, 'privada', 'hilo', 'privado', '{}',
    '[]'::jsonb,
    '[{"titulo":"A","vence_dias":2},{"titulo":"B","vence_dias":3,"vence_tras_previo":true},{"titulo":"C"}]'::jsonb);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_plantillas_items WHERE plantilla_id = v_pl AND activo;
  r := r || E'\n11 editar deja solo los pasos nuevos activos: ' ||
    CASE WHEN v_n = 3 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- usar_plantilla: hilo encadenado + vencimiento tras el previo
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM usar_plantilla(v_pl, 'Hilo desde plantilla', NULL, NULL);
  PERFORM set_config('role', 'none', true);

  SELECT id INTO v_hilo FROM tareas_hilos WHERE titulo = 'Hilo desde plantilla';
  SELECT id INTO v_t1 FROM tareas WHERE hilo_id = v_hilo AND titulo = 'A';
  SELECT id INTO v_t2 FROM tareas WHERE hilo_id = v_hilo AND titulo = 'B';

  SELECT count(*) INTO v_n FROM tareas WHERE hilo_id = v_hilo AND activo
     AND (titulo = 'A' AND paso_anterior_id IS NULL
       OR titulo = 'B' AND paso_anterior_id = v_t1
       OR titulo = 'C' AND paso_anterior_id = v_t2);
  r := r || E'\n12 usar tipo hilo: hilo nuevo con 3 pasos encadenados: ' ||
    CASE WHEN v_n = 3 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas a JOIN tareas b ON b.paso_anterior_id = a.id
   WHERE a.hilo_id = v_hilo AND b.created_at > a.created_at;
  r := r || E'\n12b created_at sigue el orden de la cadena: ' ||
    CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ' de 2)' END;

  SELECT fecha_vencimiento INTO v_d FROM tareas WHERE id = v_t1;
  r := r || E'\n13 paso 1 vence a 2 días de hoy: ' ||
    CASE WHEN v_d = current_date + 2 THEN 'OK' ELSE 'FALLO (' || COALESCE(v_d::text, 'null') || ')' END;

  SELECT count(*) INTO v_n FROM tareas
   WHERE id = v_t2 AND fecha_vencimiento IS NULL AND vence_dias_tras_previo = 3;
  r := r || E'\n14 paso 2 sin fecha mientras el previo no se completa: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas SET estado = 'completada' WHERE id = v_t1;
  PERFORM set_config('role', 'none', true);
  SELECT fecha_vencimiento INTO v_d FROM tareas WHERE id = v_t2;
  r := r || E'\n15 completar el paso 1 arranca el plazo del 2: ' ||
    CASE WHEN v_d = current_date + 3 THEN 'OK' ELSE 'FALLO (' || COALESCE(v_d::text, 'null') || ')' END;

  -- Editar el paso 2 con el mismo plazo: la fecha que manda el form se ignora.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM editar_tarea(v_t2, 'B editada', NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                       '2000-01-01', 50, NULL, NULL, 3);
  PERFORM set_config('role', 'none', true);
  SELECT fecha_vencimiento INTO v_d FROM tareas WHERE id = v_t2;
  r := r || E'\n15b editar con plazo tras el previo no pisa la fecha derivada: ' ||
    CASE WHEN v_d = current_date + 3 THEN 'OK' ELSE 'FALLO (' || COALESCE(v_d::text, 'null') || ')' END;

  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas SET estado = 'pendiente' WHERE id = v_t1;
  PERFORM set_config('role', 'none', true);
  SELECT fecha_vencimiento INTO v_d FROM tareas WHERE id = v_t2;
  r := r || E'\n16 reabrir el paso 1 vuelve a dejar sin fecha al 2: ' ||
    CASE WHEN v_d IS NULL THEN 'OK' ELSE 'FALLO (' || v_d || ')' END;

  -- ============================================================
  -- usar_plantilla: asignado que no puede recibir → queda para quien la usa
  -- ============================================================
  -- La de sistema asigna solo a ADMIN; TESTER no tiene tareas_asignar.
  PERFORM set_config('role', 'authenticated', true);
  v_n := usar_plantilla(v_sis, 'Hilo derivado', NULL, NULL);
  PERFORM set_config('role', 'none', true);

  SELECT id INTO v_t1 FROM tareas
   WHERE titulo = 'S1' AND hilo_id = (SELECT id FROM tareas_hilos WHERE titulo = 'Hilo derivado');
  SELECT count(*) INTO v_n FROM tareas t
   WHERE t.id = v_t1 AND t.responsable_id = v_tester
     AND (SELECT array_agg(usuario_id) FROM tareas_asignados WHERE tarea_id = t.id AND activo) = ARRAY[v_tester]
     AND EXISTS (SELECT 1 FROM tareas_notas WHERE tarea_id = t.id AND nota LIKE 'Quedó asignada a vos%');
  r := r || E'\n17 sin poder asignar a ADMIN, el paso queda para TESTER con nota: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- usar_plantilla: proyecto
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_id := guardar_plantilla(NULL, 'PL proyecto', NULL, 'privada', 'proyecto', 'privado', ARRAY[v_tester],
    format('[{"titulo":"H1","pasos":[{"titulo":"H1-a"},{"titulo":"H1-b","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]}]', v_tester, v_tester)::jsonb,
    '[{"titulo":"Suelta"}]'::jsonb);
  PERFORM usar_plantilla(v_id, 'Proyecto desde plantilla', NULL, NULL);

  BEGIN
    PERFORM usar_plantilla(v_id, NULL, NULL, v_hilo);
    r := r || E'\n18 plantilla de proyecto con destino: FALLO (usó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n18 plantilla de proyecto con destino: ' || CASE WHEN SQLSTATE = 'TA011' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT id INTO v_proy FROM tareas_proyectos WHERE nombre = 'Proyecto desde plantilla';
  SELECT count(*) INTO v_n FROM tareas_proyectos_miembros WHERE proyecto_id = v_proy AND activo
     AND usuario_id IN (v_admin, v_tester);
  r := r || E'\n19 proyecto con sus miembros + quien la usa: ' ||
    CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas t
    LEFT JOIN tareas_hilos h ON h.id = t.hilo_id
   WHERE t.activo AND (
         (t.titulo = 'H1-a' AND h.proyecto_id = v_proy AND h.titulo = 'H1' AND t.paso_anterior_id IS NULL)
      OR (t.titulo = 'H1-b' AND h.proyecto_id = v_proy AND t.paso_anterior_id IS NOT NULL AND t.responsable_id = v_tester)
      OR (t.titulo = 'Suelta' AND t.proyecto_id = v_proy AND t.hilo_id IS NULL));
  r := r || E'\n20 hilo con cadena (paso 2 para TESTER) + tarea suelta en el proyecto: ' ||
    CASE WHEN v_n = 3 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
