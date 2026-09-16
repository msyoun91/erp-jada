-- Verificación de sql/063 (la regla al asignar, relacionar y disparar —
-- PLAN_TAREAS_VINCULOS.md, Fase D) y de sql/064 (casos 13–16).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que plantillas_disparo.sql y
-- acceso_registros.sql: `authenticated` + `request.jwt.claims` para actuar,
-- `role = none` para leer/escribir sin RLS.
--
-- ADMIN arranca con TODOS los submódulos de obras y tareas (como en
-- plantillas_disparo.sql / acceso_registros.sql), así que ve y comparte todo
-- por default — algunos casos le sacan una función puntual (obras_ver,
-- obras_personas_todas) DENTRO de la transacción para simular que pierde
-- acceso a algo, y la restauran después. TESTER solo con tareas_lista,
-- tareas_plantillas, obras_ver, obras_crear: sin tareas_asignar ni
-- tareas_gestionar_ajenas, y sin ver la obra privada de ADMIN.
--
-- Correrlo entero después de tocar sql/063 o sql/064.

DO $test$
DECLARE
  v_admin      uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester     uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_obra_a     uuid;  -- privada de ADMIN, TESTER no la ve
  v_persona_t  uuid;  -- privada de TESTER, ADMIN la ve por "todas" hasta que se la sacamos
  v_persona_x  uuid;  -- privada de TESTER
  v_obra_b     uuid;  -- de ADMIN, para 15 y 16
  v_empresa    uuid;  -- de ADMIN, vinculada a v_obra_b en 16
  v_t          uuid;
  v_pl         uuid;
  v_n          int;
  v_m          int;
  v_etiqueta   text;
  v_asignados  uuid[];
  v_resp       uuid;
  r            text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos
     WHERE activo AND codigo IN ('tareas_lista', 'tareas_plantillas', 'obras_ver', 'obras_crear')
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (SELECT id FROM submodulos
                           WHERE codigo IN ('tareas_asignar', 'tareas_gestionar_ajenas', 'obras_transferir',
                                            'obras_personas_todas', 'obras_empresas_todas'));

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_admin, id FROM submodulos WHERE activo AND modulo IN ('obras', 'tareas')
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  -- ============================================================
  -- Datos
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('ZZD Obra Privada Norte 4471', 'casa', v_admin)
  RETURNING id INTO v_obra_a;
  PERFORM set_config('role', 'none', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('ZZD Baldomero', 'Insua', v_tester)
  RETURNING id INTO v_persona_t;
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('ZZD Casimiro', 'Etchegoyen', v_tester)
  RETURNING id INTO v_persona_x;
  PERFORM set_config('role', 'none', true);

  IF EXISTS (
    SELECT 1 FROM obras WHERE id = v_obra_a AND pendiente
    UNION ALL SELECT 1 FROM obras_personas WHERE id IN (v_persona_t, v_persona_x) AND pendiente
  ) THEN
    RAISE EXCEPTION 'setup: alguna entidad de control entró pendiente (nombre demasiado parecido)';
  END IF;

  -- ============================================================
  -- 01 — crear_tarea: el que no abre la obra queda afuera, el que sí queda
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD01', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin, v_tester],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                     jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_a)));
  PERFORM set_config('role', 'none', true);

  SELECT array_agg(usuario_id ORDER BY usuario_id) INTO v_asignados
    FROM tareas_asignados WHERE tarea_id = v_t AND activo;
  r := r || E'\n01 TESTER (no abre la obra) queda afuera, ADMIN (la abre) queda: ' ||
    CASE WHEN v_asignados = ARRAY[v_admin] THEN 'OK' ELSE 'FALLO (' || array_to_string(v_asignados, ',') || ')' END;

  -- ============================================================
  -- 02 — nadie la abre: queda quien crea, como responsable y con nota
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD02', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                     jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_a)));
  PERFORM set_config('role', 'none', true);

  SELECT array_agg(usuario_id) INTO v_asignados FROM tareas_asignados WHERE tarea_id = v_t AND activo;
  SELECT count(*) INTO v_n FROM tareas t
   WHERE t.id = v_t AND t.responsable_id = v_admin
     AND EXISTS (SELECT 1 FROM tareas_notas n WHERE n.tarea_id = t.id);
  r := r || E'\n02 sin nadie que la abra, queda ADMIN de responsable, con nota: ' ||
    CASE WHEN v_asignados = ARRAY[v_admin] AND v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- 03 — quien crea nunca queda afuera, ni por un vínculo adjunto que él
  -- mismo no puede abrir (rol de la obra, sql/060)
  -- ============================================================
  -- TESTER (dueño de la persona) se la comparte a ADMIN para que la pueda
  -- colgar como rol de su obra...
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  PERFORM obras_compartir_registros(v_admin, jsonb_build_array(jsonb_build_object('ente', 'persona', 'registro_id', v_persona_x)));
  PERFORM set_config('role', 'none', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra_a, v_persona_x, '{arquitecto}');
  PERFORM set_config('role', 'none', true);

  -- ... y después se la revocan: ADMIN ya no puede abrir esa persona.
  UPDATE obras_persona_compartida SET activo = false WHERE persona_id = v_persona_x AND usuario_id = v_admin;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  -- La privada arranca prendida para su dueño (guardar_plantilla, sql/060):
  -- sin INSERT explícito a tareas_plantillas_activaciones.
  v_pl := guardar_plantilla(NULL, 'ZZD Rol', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"ZZD rol {nombre}","adjuntos":["persona:arquitecto"]}]'::jsonb, 'obra', 'en_cotizacion');
  UPDATE obras SET estado = 'en_cotizacion' WHERE id = v_obra_a;
  PERFORM set_config('role', 'none', true);

  SELECT id INTO v_t FROM tareas WHERE titulo = 'ZZD rol ZZD Obra Privada Norte 4471' AND activo;
  SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_t AND usuario_id = v_admin AND activo;
  r := r || E'\n03 quien dispara queda aunque no pueda abrir un adjunto del paso: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- 04 — un vínculo con plantilla_id fuera de un trigger falla
  -- ============================================================
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id, plantilla_id) VALUES (v_t, 'obra', gen_random_uuid(), v_pl);
    r := r || E'\n04 vínculo con plantilla_id insertado directo por el cliente: FALLO (insertó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n04 vínculo con plantilla_id insertado directo por el cliente: ' ||
      CASE WHEN SQLSTATE = '42501' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- 05 — editar_tarea sumando a alguien sin acceso: no queda, sin error
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD05', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                     jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_a)));
  PERFORM editar_tarea(v_t, 'ZZD05 editada', NULL, NULL, 'privado', v_admin, ARRAY[v_admin, v_tester],
                       NULL, 50, NULL, NULL, NULL);
  PERFORM set_config('role', 'none', true);

  SELECT array_agg(usuario_id) INTO v_asignados FROM tareas_asignados WHERE tarea_id = v_t AND activo;
  r := r || E'\n05 sumar a alguien sin acceso al editar: no queda, sin error: ' ||
    CASE WHEN v_asignados = ARRAY[v_admin] THEN 'OK' ELSE 'FALLO (' || array_to_string(v_asignados, ',') || ')' END;

  -- ============================================================
  -- 06 — editar_tarea sin cambiar asignados, con uno que perdió el acceso:
  -- ADMIN crea (tiene tareas_asignar) y asigna a los dos; TESTER (sin
  -- tareas_asignar, pero ya asignado) edita después, cuando ADMIN (co-
  -- asignado) ya perdió el acceso a una persona vinculada -> TA016, no toca
  -- nada (ni el título)
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD06', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester, v_admin],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                     jsonb_build_array(jsonb_build_object('ente', 'persona', 'registro_id', v_persona_t)));
  PERFORM set_config('role', 'none', true);

  -- Al crearla ADMIN todavía tiene obras_personas_todas: queda asignado.
  SELECT array_agg(usuario_id ORDER BY usuario_id) INTO v_asignados FROM tareas_asignados WHERE tarea_id = v_t AND activo;
  r := r || E'\n06a al crear, ADMIN (con "todas") queda junto a TESTER: ' ||
    CASE WHEN v_asignados = ARRAY[LEAST(v_admin, v_tester), GREATEST(v_admin, v_tester)] THEN 'OK'
         ELSE 'FALLO (' || array_to_string(v_asignados, ',') || ')' END;

  -- ADMIN "pierde" el acceso a la persona de TESTER (nunca fue suya ni se la compartieron).
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas_todas');

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM editar_tarea(v_t, 'ZZD06 no debería quedar', NULL, NULL, 'privado', v_tester, ARRAY[v_tester, v_admin],
                         NULL, 50, NULL, NULL, NULL);
    r := r || E'\n06b TESTER (sin tareas_asignar) edita sin tocar asignados: FALLO (no rechazó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n06b TESTER (sin tareas_asignar) edita sin tocar asignados: ' ||
      CASE WHEN SQLSTATE = 'TA016' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas WHERE id = v_t AND titulo = 'ZZD06';
  r := r || E'\n06c ... y no toca nada, ni el título: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  UPDATE usuario_submodulos SET activo = true
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas_todas');

  -- ============================================================
  -- 07 — vincular_tarea: el asignado sin acceso sale y el responsable se corrige
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD07', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_admin, v_tester],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL, '[]'::jsonb);
  -- Sin vínculos todavía, los dos entraron. Ahora se relaciona la obra privada de ADMIN.
  PERFORM vincular_tarea(v_t, 'obra', v_obra_a);
  PERFORM set_config('role', 'none', true);

  SELECT array_agg(usuario_id) INTO v_asignados FROM tareas_asignados WHERE tarea_id = v_t AND activo;
  SELECT responsable_id INTO v_resp FROM tareas WHERE id = v_t;
  r := r || E'\n07 relacionar saca a TESTER y corrige el responsable: ' ||
    CASE WHEN v_asignados = ARRAY[v_admin] AND v_resp = v_admin THEN 'OK'
         ELSE 'FALLO (asignados ' || array_to_string(v_asignados, ',') || ', resp ' || v_resp || ')' END;

  -- ============================================================
  -- 08 — vincular_tarea sin tareas_asignar dejando a alguien afuera: TA016
  --
  -- ADMIN crea (tiene tareas_asignar); TESTER (sin la función, pero ya
  -- asignado) es quien relaciona después. Se le saca a ADMIN
  -- obras_personas_todas para que la persona de TESTER (no compartida,
  -- sql/060 ya se la revocó) también le sea ajena.
  -- ============================================================
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas_todas');

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD08', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester, v_admin],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL, '[]'::jsonb);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM vincular_tarea(v_t, 'persona', v_persona_x);
    r := r || E'\n08 TESTER sin tareas_asignar relaciona algo que deja a ADMIN afuera: FALLO (no rechazó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n08 TESTER sin tareas_asignar relaciona algo que deja a ADMIN afuera: ' ||
      CASE WHEN SQLSTATE = 'TA016' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_vinculos WHERE tarea_id = v_t AND ente = 'persona' AND registro_id = v_persona_x AND activo;
  r := r || E'\n08b ... y el vínculo no queda: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO' END;

  UPDATE usuario_submodulos SET activo = true
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas_todas');

  -- ============================================================
  -- 09/10 — disparo con un paso para alguien sin acceso: no queda, aviso
  -- plantilla_sin_acceso, y el vínculo con plantilla_id + los asignados están
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_pl := guardar_plantilla(NULL, 'ZZD Disparo', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    format('[{"titulo":"ZZD disparo {nombre}","asignados":["%s"],"incluir_ejecutor":true}]', v_tester)::jsonb,
    'obra', 'en_ejecucion');
  UPDATE obras SET estado = 'en_ejecucion' WHERE id = v_obra_a;
  PERFORM set_config('role', 'none', true);

  SELECT id INTO v_t FROM tareas WHERE titulo = 'ZZD disparo ZZD Obra Privada Norte 4471' AND activo;
  SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_t AND usuario_id = v_tester AND activo;
  r := r || E'\n09a TESTER (asignado fijo sin acceso a la obra) no queda: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO' END;
  SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_t AND usuario_id = v_admin AND activo;
  r := r || E'\n09b ... y ADMIN (ejecutor, exento) sí: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;
  SELECT count(*) INTO v_n FROM usuario_notificaciones
   WHERE usuario_id = v_admin AND tipo = 'plantilla_sin_acceso' AND entidad_id = v_pl;
  r := r || E'\n09c quien disparó recibe plantilla_sin_acceso: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas_vinculos
   WHERE tarea_id = v_t AND ente = 'obra' AND registro_id = v_obra_a AND plantilla_id = v_pl AND activo;
  r := r || E'\n10 el vínculo del disparo queda con plantilla_id, aunque el paso haya recortado asignados: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- 11 — obras_ensayar_estado: devuelve el par y no deja nada
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  UPDATE obras SET estado = 'idea' WHERE id = v_obra_a;  -- vuelve a un estado que no dispara nada más
  UPDATE tareas_plantillas SET activo = false WHERE id = v_pl;  -- no vuelva a disparar en el ensayo
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas WHERE activo;
  SELECT count(*) INTO v_m FROM usuario_notificaciones;

  PERFORM set_config('role', 'authenticated', true);
  v_pl := guardar_plantilla(NULL, 'ZZD Ensayo', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    format('[{"titulo":"ZZD ensayo {nombre}","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]', v_tester, v_tester)::jsonb,
    'obra', 'en_postventa');

  SELECT count(*), max(usuario) FILTER (WHERE usuario_id = v_tester)
    INTO v_m, v_etiqueta
    FROM obras_ensayar_estado(v_obra_a, 'en_postventa', NULL, NULL);
  PERFORM set_config('role', 'none', true);

  r := r || E'\n11a el ensayo devuelve el par excluido (TESTER, obra): ' ||
    CASE WHEN v_m = 1 AND v_etiqueta = (SELECT nombre FROM usuarios WHERE id = v_tester) THEN 'OK'
         ELSE 'FALLO (' || v_m || ', ' || coalesce(v_etiqueta, '<null>') || ')' END;

  SELECT count(*) INTO v_m FROM tareas WHERE activo;
  r := r || E'\n11b ... y no deja tareas nuevas: ' || CASE WHEN v_m = v_n THEN 'OK' ELSE 'FALLO' END;
  SELECT count(*) INTO v_m FROM obras WHERE id = v_obra_a AND estado = 'idea';
  r := r || E'\n11c ... ni cambia el estado de verdad: ' || CASE WHEN v_m = 1 THEN 'OK' ELSE 'FALLO' END;

  PERFORM set_config('role', 'authenticated', true);
  UPDATE tareas_plantillas SET activo = false WHERE id = v_pl;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- 12 — tras compartir_registros, el cambio de estado real deja al asignado
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_pl := guardar_plantilla(NULL, 'ZZD Ensayo Real', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
    format('[{"titulo":"ZZD ensayo real {nombre}","asignados":["%s"],"incluir_ejecutor":false,"responsable_id":"%s"}]', v_tester, v_tester)::jsonb,
    'obra', 'terminada');
  PERFORM compartir_registros(jsonb_build_array(
    jsonb_build_object('usuario_id', v_tester, 'ente', 'obra', 'registro_id', v_obra_a)
  ));
  UPDATE obras SET estado = 'terminada' WHERE id = v_obra_a;
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM tareas_asignados a
    JOIN tareas t ON t.id = a.tarea_id
   WHERE t.titulo = 'ZZD ensayo real ZZD Obra Privada Norte 4471' AND a.usuario_id = v_tester AND a.activo;
  r := r || E'\n12 tras compartir la obra, el cambio de estado real deja a TESTER asignado: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  -- ============================================================
  -- 13 — sql/064: sacar a uno no le re-avisa «te asignaron» al que se queda
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD13', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin, v_tester],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL, '[]'::jsonb);
  PERFORM reasignar_tarea(v_t, v_tester, ARRAY[v_tester]);
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM usuario_notificaciones
   WHERE usuario_id = v_tester AND tipo = 'tarea_asignada' AND entidad_id = v_t;
  SELECT array_agg(usuario_id) INTO v_asignados FROM tareas_asignados WHERE tarea_id = v_t AND activo;
  SELECT responsable_id INTO v_resp FROM tareas WHERE id = v_t;
  r := r || E'\n13 ADMIN se saca: TESTER queda de responsable con un solo aviso: ' ||
    CASE WHEN v_n = 1 AND v_asignados = ARRAY[v_tester] AND v_resp = v_tester THEN 'OK'
         ELSE 'FALLO (avisos ' || v_n || ', asignados ' || coalesce(array_to_string(v_asignados, ','), '-') || ')' END;

  -- ============================================================
  -- 14 — sql/064: traspasar con tareas_asignar y sin tareas_gestionar_ajenas
  -- (sql/063 escribía el responsable antes que los asignados: 42501)
  -- ============================================================
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos WHERE activo AND codigo = 'tareas_asignar'
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_t := crear_tarea('ZZD14a', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL, '[]'::jsonb);
  BEGIN
    PERFORM reasignar_tarea(v_t, v_admin, ARRAY[v_admin]);
    -- TESTER ya no la ve: se cuenta sin RLS.
    PERFORM set_config('role', 'none', true);
    SELECT array_agg(usuario_id) INTO v_asignados FROM tareas_asignados WHERE tarea_id = v_t AND activo;
    SELECT responsable_id INTO v_resp FROM tareas WHERE id = v_t;
    r := r || E'\n14a TESTER le pasa la tarea entera a ADMIN: ' ||
      CASE WHEN v_asignados = ARRAY[v_admin] AND v_resp = v_admin THEN 'OK' ELSE 'FALLO (quedó mal)' END;
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n14a TESTER le pasa la tarea entera a ADMIN: FALLO ' || SQLSTATE;
  END;
  PERFORM set_config('role', 'authenticated', true);

  v_t := crear_tarea('ZZD14b', NULL, NULL, NULL, NULL, 'privado', v_tester, ARRAY[v_tester],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL, '[]'::jsonb);
  BEGIN
    PERFORM editar_tarea(v_t, 'ZZD14b', NULL, NULL, 'privado', v_admin, ARRAY[v_tester, v_admin],
                         NULL, 50, NULL, NULL, NULL);
    SELECT responsable_id INTO v_resp FROM tareas WHERE id = v_t;
    SELECT count(*) INTO v_n FROM tareas_asignados WHERE tarea_id = v_t AND activo;
    r := r || E'\n14b TESTER edita: suma a ADMIN como responsable y se queda: ' ||
      CASE WHEN v_n = 2 AND v_resp = v_admin THEN 'OK' ELSE 'FALLO (quedó mal)' END;
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n14b TESTER edita: suma a ADMIN como responsable y se queda: FALLO ' || SQLSTATE;
  END;
  PERFORM set_config('role', 'none', true);

  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'tareas_asignar');

  -- ============================================================
  -- 15 — sql/064: sin_acceso_tarea pregunta también por el vínculo que
  -- quien edita no ve (vinculos_de_tareas, de donde lee la UI, lo recorta)
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('ZZD Galpón Quebracho 5820', 'casa', v_admin)
  RETURNING id INTO v_obra_b;
  INSERT INTO obras_empresas (razon_social, creado_por) VALUES ('ZZD Hormigones Tacuarí 3317', v_admin)
  RETURNING id INTO v_empresa;
  v_t := crear_tarea('ZZD15', NULL, NULL, NULL, NULL, 'privado', v_admin, ARRAY[v_admin],
                     NULL, 50, NULL, NULL, 'manual', NULL, NULL, NULL,
                     jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra_b)));
  PERFORM set_config('role', 'none', true);

  IF EXISTS (
    SELECT 1 FROM obras WHERE id = v_obra_b AND pendiente
    UNION ALL SELECT 1 FROM obras_empresas WHERE id = v_empresa AND pendiente
  ) THEN
    RAISE EXCEPTION 'setup 15: alguna entidad de control entró pendiente (nombre demasiado parecido)';
  END IF;

  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_ver');

  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM vinculos_de_tareas() WHERE tarea_id = v_t;
  -- Sin `compartible`: ADMIN sigue siendo el responsable, y compartir exige
  -- ser dueño, no obras_ver.
  SELECT count(*), bool_and(etiqueta IS NULL)
    INTO v_m, v_etiqueta
    FROM sin_acceso_tarea(v_t, ARRAY[v_tester]);
  PERFORM set_config('role', 'none', true);

  r := r || E'\n15 ADMIN sin obras_ver: la UI no ve el vínculo, sin_acceso_tarea lo pregunta sin nombre: ' ||
    CASE WHEN v_n = 0 AND v_m = 1 AND v_etiqueta = 'true' THEN 'OK'
         ELSE 'FALLO (visibles ' || v_n || ', filas ' || v_m || ', sin nombre ' || coalesce(v_etiqueta, '-') || ')' END;

  UPDATE usuario_submodulos SET activo = true
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_ver');

  -- ============================================================
  -- 16 — sql/064: compartir empresa antes que la obra en el array igual
  -- deja la cascada con origen en la obra
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles) VALUES (v_obra_b, v_empresa, '{constructora}');
  PERFORM obras_compartir_registros(v_tester, jsonb_build_array(
    jsonb_build_object('ente', 'empresa', 'registro_id', v_empresa),
    jsonb_build_object('ente', 'obra', 'registro_id', v_obra_b)
  ));
  PERFORM set_config('role', 'none', true);

  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_empresa AND usuario_id = v_tester AND activo AND origen_obra_id = v_obra_b;
  r := r || E'\n16 empresa antes que obra en el array: el grant de la empresa sale de la obra: ' ||
    CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
