-- Verificación de sql/067 (`tarea` entra a `entes`).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que vinculos_tareas.sql: `authenticated`
-- + `request.jwt.claims` para actuar, `role = none` para contar sin RLS.
--
-- Dentro de la transacción TESTER queda con tareas_lista y tareas_asignar, y
-- sin tareas_gestionar_ajenas: ve lo suyo y lo público, no lo privado de
-- ADMIN. ADMIN tiene todo.
--
-- Volver a correrlo entero después de tocar sql/067.
--
-- Último resultado: 16/16.

DO $test$
DECLARE
  v_admin    uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester   uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_privada  uuid;
  v_publica  uuid;
  v_propia   uuid;
  v_resp     uuid;
  v_dos      uuid;
  v_n        int;
  v_m        int;
  v_b        boolean;
  v_b2       boolean;
  v_texto    text;
  v_texto2   text;
  r          text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos
     WHERE activo AND codigo IN ('tareas_lista', 'tareas_asignar')
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'tareas_gestionar_ajenas');

  -- ADMIN: una privada suya, una pública suelta, y una pública de la que
  -- TESTER va a ser responsable sin estar asignado.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_privada := crear_tarea('ZZE privada de admin', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                           NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
  v_publica := crear_tarea('ZZE pública de admin', NULL, NULL, NULL, NULL, 'publico', v_admin, ARRAY[v_admin],
                           NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
  v_resp := crear_tarea('ZZE responsable sin asignar', NULL, NULL, NULL, NULL, 'publico', v_admin, ARRAY[v_admin],
                        NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);
  PERFORM set_config('role', 'none', true);
  UPDATE tareas SET responsable_id = v_tester WHERE id = v_resp;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_propia := crear_tarea('ZZE propia de tester', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                          NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL);

  -- ============================================================
  -- El catálogo y la etiqueta
  -- ============================================================
  SELECT count(*) INTO v_n FROM entes WHERE codigo = 'tarea' AND estados IS NULL AND ruta = '/tareas?tarea={id}';
  r := r || E'\n01 tarea está en entes, sin estados, para quien tiene tareas_lista: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  v_texto := etiqueta_registro('tarea', v_propia);
  v_texto2 := etiqueta_registro('tarea', v_publica);
  r := r || E'\n02 etiqueta de la propia y de la pública: ' ||
    CASE WHEN v_texto = 'ZZE propia de tester' AND v_texto2 = 'ZZE pública de admin' THEN 'OK'
         ELSE 'FALLO (' || coalesce(v_texto, 'NULL') || ', ' || coalesce(v_texto2, 'NULL') || ')' END;

  v_texto := etiqueta_registro('tarea', v_privada);
  r := r || E'\n03 la privada ajena no tiene etiqueta: ' ||
    CASE WHEN v_texto IS NULL THEN 'OK' ELSE 'FALLO (' || v_texto || ')' END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- Quién la puede abrir
  -- ============================================================
  v_b := puede_abrir_registro('tarea', v_privada, v_tester);
  v_b2 := puede_abrir_registro('tarea', v_privada, v_admin);
  r := r || E'\n04 la privada de ADMIN la abre ADMIN y no TESTER: ' ||
    CASE WHEN NOT v_b AND v_b2 THEN 'OK' ELSE 'FALLO (' || v_b || ', ' || v_b2 || ')' END;

  v_b := puede_abrir_registro('tarea', v_publica, v_tester);
  r := r || E'\n05 la pública la abre TESTER: ' || CASE WHEN v_b THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- Buscar
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) FILTER (WHERE b.registro_id IN (v_propia, v_publica)),
         count(*) FILTER (WHERE b.registro_id = v_privada)
    INTO v_n, v_m
    FROM buscar_registros('tareas', 'zze') b;
  SELECT b.href INTO v_texto FROM buscar_registros('tareas', 'ZZE propia') b WHERE b.registro_id = v_propia;
  r := r || E'\n06 buscar trae la propia y la pública, no la privada ajena, con su ruta: ' ||
    CASE WHEN v_n = 2 AND v_m = 0 AND v_texto = '/tareas?tarea=' || v_propia THEN 'OK'
         ELSE 'FALLO (' || v_n || ', ' || v_m || ', ' || coalesce(v_texto, 'NULL') || ')' END;

  SELECT count(*) INTO v_n FROM buscar_registros('tareas', 'z');
  SELECT count(*) INTO v_m FROM buscar_registros('tareas', 'publica de');
  r := r || E'\n07 con menos de dos letras no busca; sin tilde encuentra: ' ||
    CASE WHEN v_n = 0 AND v_m >= 1 THEN 'OK' ELSE 'FALLO (' || v_n || ', ' || v_m || ')' END;

  -- ============================================================
  -- Relacionar una tarea con otra
  -- ============================================================
  PERFORM vincular_tarea(v_propia, 'tarea', v_publica);
  SELECT count(*) INTO v_n FROM vinculos_de_tareas() v
   WHERE v.tarea_id = v_propia AND v.ente = 'tarea' AND v.registro_id = v_publica
     AND v.etiqueta = 'ZZE pública de admin' AND v.href = '/tareas?tarea=' || v_publica;
  r := r || E'\n08 relaciona una tarea que ve, con chip y ruta: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  BEGIN
    PERFORM vincular_tarea(v_propia, 'tarea', v_privada);
    r := r || E'\n09 relacionar una tarea que no ve: FALLO (vinculó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n09 relacionar una tarea que no ve: ' || CASE WHEN SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES (v_propia, 'tarea', v_propia);
    r := r || E'\n10 relacionar una tarea consigo misma: FALLO (vinculó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n10 relacionar una tarea consigo misma: ' || CASE WHEN SQLSTATE = '23514' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  -- ============================================================
  -- La policy decide sobre la fila nueva (tareas_select por columnas)
  -- ============================================================
  UPDATE tareas SET temperatura = 60 WHERE id = v_resp;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  BEGIN
    UPDATE tareas SET visibilidad = 'privado' WHERE id = v_resp;
    r := r || E'\n11 el responsable sin asignar no la vuelve privada para dejar de verla: FALLO (actualizó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n11 el responsable sin asignar no la vuelve privada para dejar de verla: ' ||
      CASE WHEN v_n = 1 AND SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO (' || v_n || ', ' || SQLSTATE || ')' END;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- Asignar con una tarea relacionada que el asignado no ve
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*), bool_or(s.compartible), max(s.etiqueta) INTO v_n, v_b, v_texto
    FROM sin_acceso(jsonb_build_array(jsonb_build_object('usuario_id', v_tester, 'ente', 'tarea', 'registro_id', v_privada))) s;
  r := r || E'\n12 la pregunta la muestra con nombre y no compartible: ' ||
    CASE WHEN v_n = 1 AND NOT v_b AND v_texto = 'ZZE privada de admin' THEN 'OK'
         ELSE 'FALLO (' || v_n || ', ' || coalesce(v_b::text, 'NULL') || ', ' || coalesce(v_texto, 'NULL') || ')' END;

  v_dos := crear_tarea('ZZE para los dos', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin, v_tester],
                       NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                       jsonb_build_array(jsonb_build_object('ente', 'tarea', 'registro_id', v_privada)));

  PERFORM compartir_registros(jsonb_build_array(jsonb_build_object('usuario_id', v_tester, 'ente', 'tarea', 'registro_id', v_privada)));
  PERFORM set_config('role', 'none', true);

  SELECT count(*) FILTER (WHERE usuario_id = v_tester), count(*) FILTER (WHERE usuario_id = v_admin)
    INTO v_n, v_m
    FROM tareas_asignados WHERE tarea_id = v_dos AND activo;
  r := r || E'\n13 quien no ve la tarea relacionada no queda asignado: ' ||
    CASE WHEN v_n = 0 AND v_m = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ', ' || v_m || ')' END;

  v_b := puede_abrir_registro('tarea', v_privada, v_tester);
  r := r || E'\n14 compartir una tarea no le da acceso a nadie: ' || CASE WHEN NOT v_b THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- Desactivada no existe; sin la vista, tampoco
  -- ============================================================
  UPDATE tareas SET activo = false WHERE id = v_publica;
  v_b := puede_abrir_registro('tarea', v_publica, v_admin);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_texto := etiqueta_registro('tarea', v_publica);
  SELECT count(*) INTO v_n FROM vinculos_de_tareas() v WHERE v.registro_id = v_publica;
  PERFORM set_config('role', 'none', true);
  r := r || E'\n15 una tarea desactivada no se abre, no tiene etiqueta ni chip: ' ||
    CASE WHEN NOT v_b AND v_texto IS NULL AND v_n = 0 THEN 'OK'
         ELSE 'FALLO (' || v_b || ', ' || coalesce(v_texto, 'NULL') || ', ' || v_n || ')' END;

  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'tareas_lista');
  v_b := puede_abrir_registro('tarea', v_propia, v_tester);
  r := r || E'\n16 sin tareas_lista no abre ni su propia tarea como registro: ' || CASE WHEN NOT v_b THEN 'OK' ELSE 'FALLO' END;

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
