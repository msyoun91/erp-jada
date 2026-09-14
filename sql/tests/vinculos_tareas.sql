-- Verificación de sql/059 (tareas relacionadas con obras, empresas y personas).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que plantillas.sql: `authenticated` +
-- `request.jwt.claims` para actuar, `role = none` para contar sin RLS.
--
-- Dentro de la transacción TESTER queda con tareas_lista, tareas_asignar,
-- tareas_plantillas, obras_ver y obras_crear, y sin tareas_gestionar_ajenas ni
-- obras_transferir: ve sus obras y no las de ADMIN. ADMIN tiene todo.
-- Nombres de obra bien distintos entre sí: parecidos, el aviso de duplicados
-- congelaría el alta.
--
-- Volver a correrlo entero después de tocar sql/059.
--
-- Último resultado: 15/15 (sql/061 suma 08b).

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_obra_t uuid;
  v_obra_a uuid;
  v_obra_d uuid;
  v_pl     uuid;
  v_t      uuid;
  v_t2     uuid;
  v_n      int;
  v_m      int;
  r        text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos
     WHERE activo AND codigo IN ('tareas_lista', 'tareas_asignar', 'tareas_plantillas', 'obras_ver', 'obras_crear')
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (SELECT id FROM submodulos
                           WHERE codigo IN ('tareas_gestionar_ajenas', 'obras_transferir'));

  -- ADMIN: una obra suya y una tarea para TESTER vinculada a ella.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('Alfa Vinculo Norte 5512', 'casa', v_admin)
  RETURNING id INTO v_obra_a;
  PERFORM crear_tarea('ZZV de admin para tester', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                      NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                      jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_a)));
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- Crear con vínculos
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('Quebracho Sur 8841', 'casa', v_tester)
  RETURNING id INTO v_obra_t;

  v_t := crear_tarea('ZZV propia', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                     jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_t)));
  -- Solo para ADMIN: TESTER no la va a ver, pero la vincula al crearla.
  v_t2 := crear_tarea('ZZV para admin', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                      NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                      jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_t)));
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_vinculos
   WHERE registro_id = v_obra_t AND tarea_id IN (v_t, v_t2) AND activo AND plantilla_id IS NULL;
  r := r || E'\n01 crear_tarea vincula, también la tarea que quien crea no va a ver: ' ||
    CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM crear_tarea('ZZV obra ajena', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                        NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                        jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_a)));
    r := r || E'\n02 vincular una obra que no ve: FALLO (vinculó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n02 vincular una obra que no ve: ' || CASE WHEN SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'ZZV obra ajena';
  r := r || E'\n03 ... y la tarea no queda a medias: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- Lecturas
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM vinculos_de_tareas() v
   WHERE v.tarea_id = v_t AND v.etiqueta = 'Quebracho Sur 8841' AND v.href = '/obras/' || v_obra_t AND NOT v.de_plantilla;
  r := r || E'\n04 vinculos_de_tareas trae el nombre y la ruta del registro: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM vinculos_de_tareas() v WHERE v.registro_id = v_obra_a;
  r := r || E'\n05 ... y no el de una tarea que ve con una obra que no ve: ' ||
    CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas_de_registro('obra', v_obra_t);
  r := r || E'\n06 la ficha lista solo las tareas que ve (la de ADMIN no): ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas_de_registro('obra', v_obra_a);
  r := r || E'\n07 la ficha de una obra que no ve no lista nada, aunque vea la tarea: ' ||
    CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM buscar_registros('obras', 'Quebracho Sur') b WHERE b.registro_id = v_obra_t;
  SELECT count(*) INTO v_m FROM buscar_registros('obras', 'Alfa Vinculo Norte') b WHERE b.etiqueta = 'Alfa Vinculo Norte 5512';
  r := r || E'\n08 buscar_registros trae la obra propia y no la ajena: ' ||
    CASE WHEN v_n = 1 AND v_m = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ', ' || v_m || ')' END;

  SELECT count(*) INTO v_n FROM buscar_registros('otro', 'Quebracho Sur');
  r := r || E'\n08b un módulo que no registra entes no devuelve nada: ' ||
    CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- Vincular y desvincular desde el cliente
  -- ============================================================
  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES (v_t, 'obra', v_obra_t);
    r := r || E'\n09 el mismo vínculo dos veces: FALLO (duplicó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n09 el mismo vínculo dos veces: ' || CASE WHEN SQLSTATE = '23505' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  v_pl := guardar_plantilla(NULL, 'ZZV disparo', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"ZZV disparada {nombre}"}]'::jsonb, 'obra', 'en_postventa');
  INSERT INTO obras (nombre, tipo, estado, responsable_id) VALUES ('Omega Disparo Lejano 3307', 'casa', 'en_postventa', v_tester)
  RETURNING id INTO v_obra_d;

  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id, plantilla_id) VALUES (v_t, 'obra', v_obra_d, v_pl);
    r := r || E'\n10 un vínculo con plantilla desde el cliente: FALLO (insertó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n10 un vínculo con plantilla desde el cliente: ' || CASE WHEN SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  UPDATE tareas_vinculos SET activo = false WHERE registro_id = v_obra_d AND plantilla_id = v_pl;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_m FROM tareas_vinculos WHERE registro_id = v_obra_d AND plantilla_id = v_pl AND activo;
  r := r || E'\n11 no desvincula lo que vinculó un disparo: ' ||
    CASE WHEN v_n = 0 AND v_m = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ' tocadas, ' || v_m || ' activas)' END;

  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas_vinculos SET activo = false WHERE tarea_id = v_t AND registro_id = v_obra_t;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  r := r || E'\n12 desvincula lo vinculado a mano: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES (v_t, 'obra', v_obra_t);
    r := r || E'\n13 ... y lo vuelve a vincular: OK';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n13 ... y lo vuelve a vincular: FALLO ' || SQLSTATE;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- Empresa y persona no disparan
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM guardar_plantilla(NULL, 'ZZV empresa', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X"}]'::jsonb, 'empresa', 'idea');
    r := r || E'\n14 una empresa no dispara: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n14 una empresa no dispara: ' || CASE WHEN SQLSTATE = 'TA012' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
