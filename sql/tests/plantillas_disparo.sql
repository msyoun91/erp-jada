-- Verificación de sql/055 (plantillas disparadas por el estado de una obra).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que plantillas.sql: `authenticated` +
-- `request.jwt.claims` para actuar, `role = none` para contar sin RLS.
--
-- Dentro de la transacción TESTER queda con la vista `tareas_plantillas` y
-- obras_ver/crear/editar, y sin tareas_asignar, tareas_proyectos_crear ni
-- tareas_plantillas_sistema. ADMIN tiene todo.
--
-- Volver a correrlo entero después de tocar sql/055.
--
-- Último resultado: 29/29.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_sis    uuid;
  v_priv   uuid;
  v_proy   uuid;
  v_aviso  uuid;
  v_obra   uuid;
  v_obra_a uuid;
  v_t      uuid;
  v_n      int;
  r        text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos
     WHERE activo AND codigo IN ('tareas_plantillas', 'obras_ver', 'obras_crear', 'obras_editar')
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (SELECT id FROM submodulos
                           WHERE codigo IN ('tareas_asignar', 'tareas_proyectos_crear', 'tareas_plantillas_sistema',
                                            'tareas_gestionar_ajenas', 'obras_transferir'));

  SELECT id INTO v_t FROM tareas LIMIT 1;

  -- ============================================================
  -- Armado y visibilidad
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_sis := guardar_plantilla(NULL, 'ZZ Cobrar', NULL, 'sistema', 'tarea', 'privado', '{}', '[]'::jsonb,
    format('[{"titulo":"Cobrar obra {nombre}","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]', v_admin, v_admin)::jsonb,
    'obra', 'en_ejecucion');

  BEGIN
    PERFORM guardar_plantilla(NULL, 'ZZ estado malo', NULL, 'sistema', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X"}]'::jsonb, 'obra', 'volando');
    r := r || E'\n01 estado que no existe en estado_obra: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n01 estado que no existe en estado_obra: ' || CASE WHEN SQLSTATE = 'TA012' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  BEGIN
    PERFORM usar_plantilla(v_sis, NULL, NULL, NULL);
    r := r || E'\n02 usar a mano una plantilla con disparador: FALLO (usó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n02 usar a mano una plantilla con disparador: ' || CASE WHEN SQLSTATE = 'TA013' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_plantillas_activaciones WHERE plantilla_id = v_sis;
  r := r || E'\n03 la de sistema arranca apagada, también para quien la crea: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO' END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM tareas_plantillas WHERE id = v_sis;
  r := r || E'\n04 con obras_ver ve la de sistema con disparador de obra: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;
  PERFORM set_config('role', 'none', true);

  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester AND submodulo_id = (SELECT id FROM submodulos WHERE codigo = 'obras_ver' AND activo);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM tareas_plantillas WHERE id = v_sis;
  r := r || E'\n05 sin obras_ver no la ve: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO' END;
  BEGIN
    PERFORM guardar_plantilla(NULL, 'ZZ sin obras', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X"}]'::jsonb, 'obra', 'en_ejecucion');
    r := r || E'\n06 sin obras_ver no arma una con disparador de obra: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n06 sin obras_ver no arma una con disparador de obra: rechazo ' || SQLSTATE;
  END;
  PERFORM set_config('role', 'none', true);
  UPDATE usuario_submodulos SET activo = true
   WHERE usuario_id = v_tester AND submodulo_id = (SELECT id FROM submodulos WHERE codigo = 'obras_ver' AND activo);

  PERFORM set_config('role', 'authenticated', true);
  v_priv := guardar_plantilla(NULL, 'ZZ Visitar {nombre}', NULL, 'privada', 'hilo', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"Visitar {nombre}"}]'::jsonb, 'obra', 'en_ejecucion');

  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id, plantilla_id)
    VALUES (v_t, 'obra', gen_random_uuid(), v_sis);
    r := r || E'\n07 vínculo insertado directo por el cliente: FALLO (insertó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n07 vínculo insertado directo por el cliente: ' || CASE WHEN SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  INSERT INTO tareas_plantillas_activaciones (plantilla_id, usuario_id) VALUES (v_sis, v_tester);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_plantillas_activaciones
   WHERE plantilla_id = v_priv AND usuario_id = v_tester AND activo;
  r := r || E'\n08 la privada arranca prendida para su dueño: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- Disparo
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras (nombre, tipo, estado, responsable_id)
  VALUES ('ZZ Disparo 4821', 'casa', 'en_ejecucion', v_tester)
  RETURNING id INTO v_obra;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas
   WHERE activo AND titulo = 'Cobrar obra ZZ Disparo 4821'
     AND origen_app = 'obras' AND origen_punto = '/obras/' || v_obra;
  r := r || E'\n09 crear la obra ya en ejecución dispara, con el texto relleno y el origen: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas t
   WHERE t.activo AND t.titulo = 'Cobrar obra ZZ Disparo 4821' AND t.responsable_id = v_tester
     AND EXISTS (SELECT 1 FROM tareas_notas n WHERE n.tarea_id = t.id);
  r := r || E'\n10 sin tareas_asignar, el paso de ADMIN queda para quien dispara, con la nota: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas t JOIN tareas_hilos h ON h.id = t.hilo_id
   WHERE t.activo AND t.titulo = 'Visitar ZZ Disparo 4821' AND h.titulo = 'ZZ Visitar ZZ Disparo 4821';
  r := r || E'\n11 la privada crea su hilo con el nombre relleno: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas_vinculos WHERE ente = 'obra' AND registro_id = v_obra;
  r := r || E'\n12 un vínculo por tarea generada: ' || CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  PERFORM set_config('role', 'authenticated', true);
  UPDATE obras SET estado = 'en_ejecucion', observaciones = 'x' WHERE id = v_obra;
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'Cobrar obra ZZ Disparo 4821';
  r := r || E'\n13 editar sin cambiar el estado no dispara: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  UPDATE tareas SET estado = 'completada' WHERE titulo = 'Cobrar obra ZZ Disparo 4821';
  PERFORM set_config('role', 'authenticated', true);
  UPDATE obras SET estado = 'en_postventa' WHERE id = v_obra;
  UPDATE obras SET estado = 'en_ejecucion' WHERE id = v_obra;
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'Cobrar obra ZZ Disparo 4821';
  r := r || E'\n14 completada no se duplica al ir y volver de estado: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  UPDATE tareas SET activo = false WHERE titulo = 'Cobrar obra ZZ Disparo 4821';
  PERFORM set_config('role', 'authenticated', true);
  UPDATE obras SET estado = 'en_postventa' WHERE id = v_obra;
  UPDATE obras SET estado = 'en_ejecucion' WHERE id = v_obra;
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'Cobrar obra ZZ Disparo 4821' AND activo;
  r := r || E'\n15 archivado lo que generó, vuelve a disparar: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'Visitar ZZ Disparo 4821';
  r := r || E'\n16 la otra plantilla, con su tarea activa, no se repite: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- No puede correr: el estado cambia igual y avisa
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_proy := guardar_plantilla(NULL, 'ZZ Proyecto {nombre}', NULL, 'sistema', 'proyecto', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"Arrancar {nombre}"}]'::jsonb, 'obra', 'en_cotizacion');
  PERFORM set_config('role', 'none', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO tareas_plantillas_activaciones (plantilla_id, usuario_id) VALUES (v_proy, v_tester);
  UPDATE obras SET estado = 'en_cotizacion' WHERE id = v_obra;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM obras WHERE id = v_obra AND estado = 'en_cotizacion';
  r := r || E'\n17 sin tareas_proyectos_crear el cambio de estado pasa igual: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;
  SELECT count(*) INTO v_n FROM usuario_notificaciones
   WHERE usuario_id = v_tester AND tipo = 'plantilla_fallida' AND entidad = 'plantilla' AND entidad_id = v_proy;
  r := r || E'\n18 ... y a quien la activó le llega el aviso: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  SELECT count(*) INTO v_n FROM tareas_proyectos WHERE nombre = 'ZZ Proyecto ZZ Disparo 4821';
  r := r || E'\n19 ... sin dejar nada a medias: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- Quien sí puede asignar: la tarea le llega al asignado, con aviso
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_aviso := guardar_plantilla(NULL, 'ZZ Avisar', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    format('[{"titulo":"Avisar {nombre}","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]', v_tester, v_tester)::jsonb,
    'obra', 'idea');
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('ZZ Disparo admin 7730', 'casa', v_admin)
  RETURNING id INTO v_obra_a;
  UPDATE obras SET estado = 'en_ejecucion' WHERE id = v_obra_a;
  PERFORM set_config('role', 'none', true);

  SELECT id INTO v_t FROM tareas WHERE titulo = 'Avisar ZZ Disparo admin 7730' AND activo AND responsable_id = v_tester;
  SELECT count(*) INTO v_n FROM usuario_notificaciones
   WHERE usuario_id = v_tester AND tipo = 'tarea_asignada' AND entidad_id = v_t AND actor_id = v_admin;
  r := r || E'\n20 la tarea de un disparo le avisa a su asignado: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'Cobrar obra ZZ Disparo admin 7730';
  r := r || E'\n21 la de sistema no corre para quien no la activó: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  UPDATE tareas SET activo = false WHERE id = v_t;
  UPDATE obras SET estado = 'terminada' WHERE id = v_obra_a;
  UPDATE obras SET estado = 'idea' WHERE id = v_obra_a;
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'Avisar ZZ Disparo admin 7730' AND activo;
  r := r || E'\n22 un cambio de estado fuera de authenticated no dispara: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- Campanita: guardar y archivar
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  PERFORM guardar_plantilla(v_sis, 'ZZ Cobrar', NULL, 'sistema', 'tarea', 'privado', '{}', '[]'::jsonb,
    format('[{"titulo":"Cobrar obra {nombre}","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]', v_admin, v_admin)::jsonb,
    'obra', 'en_ejecucion');
  UPDATE tareas_plantillas SET activo = false WHERE id = v_sis;
  PERFORM guardar_plantilla(v_aviso, 'ZZ Avisar', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"Avisar {nombre}"}]'::jsonb, 'obra', 'idea');
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM usuario_notificaciones
   WHERE usuario_id = v_tester AND entidad_id = v_sis AND tipo IN ('plantilla_modificada', 'plantilla_archivada');
  r := r || E'\n23 guardar y archivar una de sistema le avisa a quien la activó: ' || CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  SELECT count(*) INTO v_n FROM usuario_notificaciones WHERE entidad_id = v_sis AND usuario_id = v_admin;
  r := r || E'\n24 ... y no a quien la guardó: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  SELECT count(*) INTO v_n FROM usuario_notificaciones WHERE entidad_id = v_aviso;
  r := r || E'\n25 una privada no avisa: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM notificaciones_listar(200) l
   WHERE l.destino_id = v_sis AND l.destino IS NULL AND l.tipo IN ('plantilla_modificada', 'plantilla_archivada');
  r := r || E'\n26 la bandeja muestra los dos avisos, sin destino porque está archivada: ' || CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  SELECT count(*) INTO v_n FROM notificaciones_listar(200) l
   WHERE l.destino_id = v_proy AND l.destino = 'plantilla' AND l.tipo = 'plantilla_fallida';
  r := r || E'\n27 el aviso de fallo lleva a la plantilla: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- Las dos DEFINER que llama el disparo tienen EXECUTE para `authenticated`:
  -- fuera de un trigger no hacen nada.
  SELECT count(*) INTO v_n FROM usuario_notificaciones WHERE usuario_id = v_tester;
  PERFORM notificar_plantilla_fallida(v_sis);
  SELECT count(*) - v_n INTO v_n FROM usuario_notificaciones WHERE usuario_id = v_tester;
  r := r || E'\n28 por RPC, notificar_plantilla_fallida no escribe nada: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  r := r || E'\n29 por RPC, plantilla_disparada contesta false: ' ||
    CASE WHEN NOT plantilla_disparada(v_priv, 'obra', v_obra) THEN 'OK' ELSE 'FALLO' END;
  PERFORM set_config('role', 'none', true);

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
