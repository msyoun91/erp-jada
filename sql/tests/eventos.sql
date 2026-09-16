-- Verificación de sql/068 (el bus de eventos: emisores, RLS, tareas_eventos
-- mudada y plantillas que escuchan un evento).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que plantillas_disparo.sql.
--
-- ADMIN actúa como `authenticated` (tiene todo). TESTER queda sin
-- obras_transferir, que le dejaría ver todas las obras.
--
-- Volver a correrlo entero después de tocar sql/068.
--
-- Último resultado: 25/25.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_obra   uuid;
  v_obra_b uuid;
  v_per    uuid;
  v_per2   uuid;
  v_vin    uuid;
  v_tarea  uuid;
  v_pl     uuid;
  v_alta   uuid;
  v_n      int;
  v_m      int;
  v_txt    text;
  r        text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo IN ('obras_transferir', 'tareas_gestionar_ajenas'));

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Eulalia', 'Brandsen9317', v_admin)
  RETURNING id INTO v_per;
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Fermín', 'Quiroga5520', v_admin)
  RETURNING id INTO v_per2;

  -- ============================================================
  -- La tabla
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    INSERT INTO eventos (ente, registro_id, evento) VALUES ('obra', gen_random_uuid(), 'alta');
    r := r || E'\n01 insertar un evento directo: FALLO (insertó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n01 insertar un evento directo: ' || CASE WHEN SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  -- ============================================================
  -- El ente
  -- ============================================================
  INSERT INTO obras (nombre, tipo, estado, responsable_id)
  VALUES ('Algarrobo Evento 9317', 'casa', 'idea', v_admin)
  RETURNING id INTO v_obra;

  SELECT string_agg(evento::text || COALESCE(':' || (detalle->>'estado'), ''), ',' ORDER BY created_at)
    INTO v_txt FROM eventos WHERE ente = 'obra' AND registro_id = v_obra AND actor_id = v_admin;
  r := r || E'\n02 crear la obra emite alta y después estado, con actor: ' ||
    CASE WHEN v_txt = 'alta,estado:idea' THEN 'OK' ELSE 'FALLO (' || COALESCE(v_txt, 'NULL') || ')' END;

  SELECT count(*) INTO v_n FROM eventos
   WHERE registro_id = v_obra AND evento = 'estado' AND detalle ? 'anterior' AND detalle->'anterior' = 'null'::jsonb;
  r := r || E'\n03 el estado al nacer no tiene anterior: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  UPDATE obras SET nombre = 'Algarrobo Evento 9317 bis' WHERE id = v_obra;
  UPDATE obras SET estado = 'idea' WHERE id = v_obra;
  SELECT count(*) INTO v_n FROM eventos WHERE registro_id = v_obra;
  r := r || E'\n04 editar el nombre o repetir el estado no emite: ' || CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  UPDATE obras SET estado = 'en_cotizacion' WHERE id = v_obra;
  SELECT count(*) INTO v_n FROM eventos
   WHERE registro_id = v_obra AND evento = 'estado'
     AND detalle = '{"estado":"en_cotizacion","anterior":"idea"}'::jsonb;
  r := r || E'\n05 cambiar el estado emite estado con el anterior: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  PERFORM obras_set_activo(v_obra, false);
  PERFORM obras_set_activo(v_obra, true);
  SELECT string_agg(evento::text, ',' ORDER BY created_at) INTO v_txt
    FROM eventos WHERE registro_id = v_obra AND evento IN ('baja', 'reactivacion') AND actor_id = v_admin;
  r := r || E'\n06 desactivar y reactivar desde la función DEFINER quedan logueados con actor: ' ||
    CASE WHEN v_txt = 'baja,reactivacion' THEN 'OK' ELSE 'FALLO (' || COALESCE(v_txt, 'NULL') || ')' END;

  -- ============================================================
  -- La relación
  -- ============================================================
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra, v_per, '{arquitecto,decisor}')
  RETURNING id INTO v_vin;
  SELECT count(*) INTO v_n FROM eventos
   WHERE registro_id = v_obra AND evento = 'relacion_alta'
     AND detalle->>'ente' = 'persona' AND (detalle->>'registro_id')::uuid = v_per
     AND detalle->>'rol' IN ('arquitecto', 'decisor');
  r := r || E'\n07 vincular con dos roles son dos altas, en la obra: ' || CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  UPDATE obras_obra_persona SET observaciones = 'nada' WHERE id = v_vin;
  UPDATE obras_obra_persona SET roles = '{arquitecto}' WHERE id = v_vin;
  SELECT string_agg(evento::text || ':' || (detalle->>'rol'), ',') INTO v_txt
    FROM eventos WHERE registro_id = v_obra AND evento IN ('relacion_alta', 'relacion_baja')
     AND created_at > (SELECT max(created_at) FROM eventos WHERE registro_id = v_obra AND evento = 'relacion_alta');
  r := r || E'\n08 sacar un rol es una baja; las observaciones no emiten: ' ||
    CASE WHEN v_txt = 'relacion_baja:decisor' THEN 'OK' ELSE 'FALLO (' || COALESCE(v_txt, 'NULL') || ')' END;

  UPDATE obras_obra_persona SET activo = false WHERE id = v_vin;
  SELECT count(*) INTO v_n FROM eventos
   WHERE registro_id = v_obra AND evento = 'relacion_baja' AND detalle->>'rol' = 'arquitecto';
  r := r || E'\n09 desactivar el vínculo da de baja los roles que le quedaban: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- Quién los ve
  -- ============================================================
  SELECT count(*) INTO v_n FROM eventos WHERE registro_id = v_obra;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_m FROM eventos WHERE registro_id = v_obra;
  r := r || E'\n10 el responsable ve los de su obra, otro sin acceso no ve ninguno: ' ||
    CASE WHEN v_n >= 9 AND v_m = 0 THEN 'OK' ELSE 'FALLO (' || v_n || '/' || v_m || ')' END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- ============================================================
  -- La tarea: tareas_eventos mudada
  -- ============================================================
  r := r || E'\n11 tareas_eventos ya no existe: ' || CASE WHEN to_regclass('public.tareas_eventos') IS NULL THEN 'OK' ELSE 'FALLO' END;

  PERFORM set_config('role', 'none', true);
  INSERT INTO tareas (titulo, responsable_id, creado_por) VALUES ('Eventobus tarea 9317', v_admin, v_admin)
  RETURNING id INTO v_tarea;
  INSERT INTO tareas_asignados (tarea_id, usuario_id) VALUES (v_tarea, v_admin);
  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas SET estado = 'completada' WHERE id = v_tarea;

  SELECT string_agg(evento::text || COALESCE(':' || (detalle->>'estado'), ''), ',' ORDER BY created_at)
    INTO v_txt FROM eventos WHERE ente = 'tarea' AND registro_id = v_tarea;
  r := r || E'\n12 la tarea emite alta, estado al nacer y completada: ' ||
    CASE WHEN v_txt = 'alta,estado:pendiente,estado:completada' THEN 'OK' ELSE 'FALLO (' || COALESCE(v_txt, 'NULL') || ')' END;

  SELECT count(*) INTO v_n FROM eventos
   WHERE ente = 'tarea' AND registro_id = v_tarea AND detalle->>'estado' = 'completada'
     AND detalle->>'anterior' = 'pendiente' AND actor_id = v_admin;
  r := r || E'\n13 completar guarda anterior y actor, como la auditoría: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- Plantillas: qué disparador se guarda
  -- ============================================================
  BEGIN
    PERFORM guardar_plantilla(NULL, 'EV tarea', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X"}]'::jsonb, 'tarea', NULL, NULL, true, 'alta');
    r := r || E'\n14 disparar con el alta de una tarea: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n14 disparar con el alta de una tarea: ' || CASE WHEN SQLSTATE = 'TA012' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  BEGIN
    PERFORM guardar_plantilla(NULL, 'EV baja', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X"}]'::jsonb, 'obra', NULL, NULL, true, 'baja');
    r := r || E'\n15 disparar con la baja de una obra (DEFINER, nunca corre): FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n15 disparar con la baja de una obra (DEFINER, nunca corre): ' || CASE WHEN SQLSTATE = 'TA012' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  BEGIN
    PERFORM guardar_plantilla(NULL, 'EV sin rol', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X"}]'::jsonb, 'obra', NULL, NULL, true, 'relacion_alta');
    r := r || E'\n16 una relación sin rol: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n16 una relación sin rol: ' || CASE WHEN SQLSTATE = 'TA012' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  v_pl := guardar_plantilla(NULL, 'EV legado', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"X"}]'::jsonb, 'obra', 'terminada');
  SELECT count(*) INTO v_n FROM tareas_plantillas
   WHERE id = v_pl AND disparo_evento = 'estado' AND disparo_estado = 'terminada' AND disparo_rol IS NULL;
  r := r || E'\n17 sin evento, el disparador es el estado de antes: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  BEGIN
    UPDATE tareas_plantillas SET disparo_ente = 'tarea', disparo_evento = 'alta', disparo_estado = NULL WHERE id = v_pl;
    r := r || E'\n18 PATCH directo a un disparador de tarea: FALLO (actualizó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n18 PATCH directo a un disparador de tarea: ' || CASE WHEN SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  UPDATE tareas_plantillas SET activo = false WHERE id = v_pl;

  -- ============================================================
  -- Plantillas: el disparo
  -- ============================================================
  v_pl := guardar_plantilla(NULL, 'EV arquitecto', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"EV hablar con el arquitecto de {nombre}"}]'::jsonb, 'obra', 'idea', NULL, true, 'relacion_alta', 'persona:arquitecto');
  SELECT count(*) INTO v_n FROM tareas_plantillas
   WHERE id = v_pl AND disparo_evento = 'relacion_alta' AND disparo_rol = 'persona:arquitecto' AND disparo_estado IS NULL;
  r := r || E'\n19 con relación se guarda el rol y se descarta el estado: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  INSERT INTO obras (nombre, tipo, estado, responsable_id)
  VALUES ('Quebracho Norte 5520', 'casa', 'idea', v_admin)
  RETURNING id INTO v_obra_b;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra_b, v_per, '{decisor}')
  RETURNING id INTO v_vin;
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'EV hablar con el arquitecto de Quebracho Norte 5520';
  r := r || E'\n20 otro rol no dispara: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  UPDATE obras_obra_persona SET roles = '{decisor,arquitecto}' WHERE id = v_vin;
  SELECT count(*) INTO v_n FROM tareas t
    JOIN tareas_vinculos v ON v.tarea_id = t.id AND v.plantilla_id = v_pl AND v.ente = 'obra' AND v.registro_id = v_obra_b
   WHERE t.activo AND t.titulo = 'EV hablar con el arquitecto de Quebracho Norte 5520';
  r := r || E'\n21 sumarle el rol a un vínculo dispara, con el dato de la obra: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  r := r || E'\n22 el disparo deja tareas.disparo como estaba: ' ||
    CASE WHEN COALESCE(current_setting('tareas.disparo', true), '') = '' THEN 'OK' ELSE 'FALLO' END;

  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra_b, v_per2, '{arquitecto}');
  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'EV hablar con el arquitecto de Quebracho Norte 5520';
  r := r || E'\n23 un segundo arquitecto en la misma obra no vuelve a disparar: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  v_alta := guardar_plantilla(NULL, 'EV alta', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"EV presentarse en {nombre}"}]'::jsonb, 'obra', NULL, NULL, true, 'alta');
  INSERT INTO obras (nombre, tipo, estado, responsable_id) VALUES ('Lapacho Sur 7702', 'casa', 'idea', v_admin);
  SELECT count(*) INTO v_n FROM tareas WHERE activo AND titulo = 'EV presentarse en Lapacho Sur 7702';
  r := r || E'\n24 crear una obra dispara la plantilla de alta: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM eventos WHERE registro_id = v_obra_b;
  PERFORM obras_ensayar_estado(v_obra_b, 'en_cotizacion', NULL, NULL);
  SELECT count(*) INTO v_m FROM eventos WHERE registro_id = v_obra_b;
  r := r || E'\n25 ensayar un estado no deja eventos: ' || CASE WHEN v_n = v_m THEN 'OK' ELSE 'FALLO (' || v_n || '→' || v_m || ')' END;

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
