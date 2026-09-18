-- Verificación de sql/062 (acceso a un registro por usuario explícito, base
-- de "compartir al asignar" — PLAN_TAREAS_VINCULOS.md, Fase C).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que vinculos_tareas.sql.
--
-- Esta base solo tiene dos usuarios reales (ADMIN, TESTER), así que algunos
-- casos activan/desactivan un submódulo de uno de los dos DENTRO de la
-- transacción para simular a alguien sin acceso, y lo restauran después.
-- ADMIN arranca con todos los submódulos de obras (incluidos obras_personas,
-- obras_empresas, obras_personas_todas, obras_empresas_todas,
-- obras_transferir); TESTER solo con obras_ver — sin obras_personas ni
-- obras_empresas, a propósito (caso 01).
--
-- Correrlo entero después de tocar sql/062.
--
-- Los casos 09-11 y 13b se portaron el 2026-09-18: hablaban de `origen_obra_id`
-- y de `obras_*_compartida`, que `sql/086` dropeó. El 05 esperaba lo contrario
-- de lo que la base contesta desde `sql/082` — ver su comentario.
--
-- Último resultado: 19/19 (2026-09-18, revalidado tras sql/099).

DO $test$
DECLARE
  v_admin       uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_tester      uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- TESTER
  v_obra        uuid;
  v_obra3       uuid;
  v_obra4       uuid;
  v_persona     uuid;
  v_persona2    uuid;
  v_persona3    uuid;
  v_persona4    uuid;
  v_persona_t   uuid;
  v_empresa     uuid;
  v_empresa2    uuid;
  v_origen_obra uuid;
  v_asignados   uuid[];
  v_n           int;
  v_ok          boolean;
  v_etiqueta    text;
  r             text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ============================================================
  -- Setup de permisos
  -- ============================================================
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_admin, id FROM submodulos WHERE activo AND modulo = 'obras'
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_tester, id FROM submodulos
     WHERE activo AND codigo IN ('obras_ver', 'obras_personas_crear')
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester
     AND submodulo_id IN (
       SELECT id FROM submodulos
        WHERE codigo IN ('obras_personas', 'obras_empresas', 'obras_personas_todas',
                          'obras_empresas_todas', 'obras_transferir')
     );

  -- ============================================================
  -- Datos: todo de ADMIN salvo v_persona_t (de TESTER)
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  -- Nombres bien distintos entre sí: parecidos, el aviso de duplicados
  -- congelaría el alta (pendiente = true) y falsearía casi todos los casos.
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('Xilofono Insua Norte 4471', 'casa', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Baldomero', 'Insua', v_admin) RETURNING id INTO v_persona;
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Casimiro', 'Etchegoyen', v_admin) RETURNING id INTO v_persona2;
  INSERT INTO obras_empresas (razon_social, creado_por) VALUES ('Robledal Construcciones SRL', v_admin) RETURNING id INTO v_empresa;
  INSERT INTO obras_empresas (razon_social, creado_por) VALUES ('Tungsteno Ingenieria SA', v_admin) RETURNING id INTO v_empresa2;

  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra, v_persona, '{otro}');
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra, v_persona2, '{otro}');
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles) VALUES (v_obra, v_empresa, '{otro}');

  PERFORM set_config('role', 'none', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Deodoro', 'Bramanti', v_tester) RETURNING id INTO v_persona_t;
  PERFORM set_config('role', 'none', true);

  IF EXISTS (
    SELECT 1 FROM obras WHERE id IN (v_obra) AND pendiente
    UNION ALL
    SELECT 1 FROM obras_personas WHERE id IN (v_persona, v_persona2, v_persona_t) AND pendiente
    UNION ALL
    SELECT 1 FROM obras_empresas WHERE id IN (v_empresa, v_empresa2) AND pendiente
  ) THEN
    RAISE EXCEPTION 'setup: alguna entidad de control entró pendiente (nombre demasiado parecido)';
  END IF;

  -- ============================================================
  -- 01 — tiene_permiso responde igual que antes
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT tiene_permiso('obras_ver') INTO v_ok;
  PERFORM set_config('role', 'none', true);
  r := r || E'\n01a ADMIN tiene obras_ver: ' || CASE WHEN v_ok THEN 'OK' ELSE 'FALLO' END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT tiene_permiso('obras_personas') INTO v_ok;
  PERFORM set_config('role', 'none', true);
  r := r || E'\n01b TESTER sin obras_personas: ' || CASE WHEN NOT v_ok THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- 02 — puede_abrir_registro: obra de ADMIN
  -- ============================================================
  SELECT puede_abrir_registro('obra', v_obra, v_admin) INTO v_ok;
  r := r || E'\n02a ADMIN abre su obra: ' || CASE WHEN v_ok THEN 'OK' ELSE 'FALLO' END;
  SELECT puede_abrir_registro('obra', v_obra, v_tester) INTO v_ok;
  r := r || E'\n02b TESTER no la abre (sin compartir): ' || CASE WHEN NOT v_ok THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- 03 — tras obras_compartir_obra a TESTER, true
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  PERFORM obras_compartir_registros(v_tester, jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra)));
  PERFORM set_config('role', 'none', true);
  SELECT puede_abrir_registro('obra', v_obra, v_tester) INTO v_ok;
  r := r || E'\n03 tras compartir la obra, TESTER la abre: ' || CASE WHEN v_ok THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- 04 — compartida pero TESTER sin obras_ver: false y compartible false
  -- ============================================================
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_ver');

  SELECT puede_abrir_registro('obra', v_obra, v_tester) INTO v_ok;
  r := r || E'\n04a sin obras_ver, ya no la abre aunque esté compartida: ' || CASE WHEN NOT v_ok THEN 'OK' ELSE 'FALLO' END;
  SELECT puede_compartir_registro('obra', v_obra, v_tester) INTO v_ok;
  r := r || E'\n04b ... y tampoco es compartible para ella: ' || CASE WHEN NOT v_ok THEN 'OK' ELSE 'FALLO' END;

  UPDATE usuario_submodulos SET activo = true
   WHERE usuario_id = v_tester AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_ver');

  -- ============================================================
  -- 05 — persona tildada en el checklist de la obra: NO la abre
  --
  -- Esperaba `true` y venía de antes de `sql/082`, cuando tildar en el
  -- checklist otorgaba grant completo. Hoy otorga contextual, y
  -- `puede_abrir_registro` no cuenta contextuales, así que dice lo mismo que
  -- el 06: son el mismo montaje por dos caminos. Nadie lo vio porque el
  -- archivo moría en el 09 con `42P01`.
  --
  -- Es la mitad de Tareas de la reparación pendiente del chip `?ctx=`
  -- (`BACKLOG.md`): cuando se haga, este caso vuelve a esperar `true`.
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  PERFORM obras_compartir_obra(v_obra, v_tester, '{}'::uuid[], ARRAY[v_persona]);
  PERFORM set_config('role', 'none', true);

  -- Le hace falta a TESTER el submódulo de Personas para que el `false` sea
  -- por el grant y no por el permiso.
  UPDATE usuario_submodulos SET activo = true
   WHERE usuario_id = v_tester AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas');

  SELECT puede_abrir_registro('persona', v_persona, v_tester) INTO v_ok;
  r := r || E'\n05 persona tildada en el checklist: no la abre desde la tarea: ' || CASE WHEN NOT v_ok THEN 'OK' ELSE 'FALLO' END;

  -- ============================================================
  -- 06 — lo mismo con un grant contextual suelto, sin pasar por el checklist
  -- ============================================================
  PERFORM set_config('role', 'none', true);
  INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, obra_id, otorgada_por)
  VALUES (v_persona2, v_tester, v_obra, v_admin);

  SELECT puede_abrir_registro('persona', v_persona2, v_tester) INTO v_ok;
  r := r || E'\n06 grant contextual solo no alcanza para abrir: ' || CASE WHEN NOT v_ok THEN 'OK' ELSE 'FALLO' END;

  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_tester AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas');

  -- ============================================================
  -- 07 y 08b — con ADMIN momentáneamente sin obras_personas
  -- ============================================================
  UPDATE usuario_submodulos SET activo = false
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas');

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*), max(etiqueta) INTO v_n, v_etiqueta FROM sin_acceso(
    jsonb_build_array(jsonb_build_object('usuario_id', v_admin, 'ente', 'persona', 'registro_id', v_persona_t))
  );
  PERFORM set_config('role', 'none', true);
  r := r || E'\n07 sin_acceso: ADMIN queda afuera de la persona de TESTER y sin nombre: ' ||
    CASE WHEN v_n = 1 AND v_etiqueta IS NULL THEN 'OK' ELSE 'FALLO (' || v_n || ', ' || coalesce(v_etiqueta, '<null>') || ')' END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT asignados_con_acceso(ARRAY[v_admin], jsonb_build_array(jsonb_build_object('ente', 'persona', 'registro_id', v_persona_t)))
    INTO v_asignados;
  PERFORM set_config('role', 'none', true);
  r := r || E'\n08b quien llama nunca queda afuera, aunque no abra el vínculo: ' ||
    CASE WHEN v_asignados = ARRAY[v_admin] THEN 'OK' ELSE 'FALLO (' || array_to_string(v_asignados, ',') || ')' END;

  UPDATE usuario_submodulos SET activo = true
   WHERE usuario_id = v_admin AND submodulo_id IN (SELECT id FROM submodulos WHERE codigo = 'obras_personas');

  -- ============================================================
  -- 08a — asignados_con_acceso conserva el orden
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT asignados_con_acceso(ARRAY[v_tester, v_admin], jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra)))
    INTO v_asignados;
  PERFORM set_config('role', 'none', true);
  r := r || E'\n08a orden conservado (ambos abren la obra compartida): ' ||
    CASE WHEN v_asignados = ARRAY[v_tester, v_admin] THEN 'OK' ELSE 'FALLO (' || array_to_string(v_asignados, ',') || ')' END;

  -- ============================================================
  -- 09 — una empresa que no cuelga de ninguna obra compartida: OB029
  --
  -- Era «el grant directo sigue con origen NULL». `sql/085` cerró el grant
  -- directo de empresa: la rama exige ancla y v_empresa2 no está vinculada a
  -- ninguna obra. Es la gemela de `obras_086` I, que cubre la rama persona.
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM obras_compartir_registros(v_tester, jsonb_build_array(jsonb_build_object('ente', 'empresa', 'registro_id', v_empresa2)));
    r := r || E'\n09 empresa sin obra compartida detrás: FALLO (la compartió igual)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n09 empresa sin obra compartida detrás → OB029: ' ||
      CASE WHEN SQLSTATE = 'OB029' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- 10 — obra ya compartida con la empresa tildada: la función aditiva no la pisa
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_empresa], '{}'::uuid[]);
  PERFORM obras_compartir_registros(v_tester, jsonb_build_array(jsonb_build_object('ente', 'empresa', 'registro_id', v_empresa)));
  PERFORM set_config('role', 'none', true);
  SELECT obra_id INTO v_origen_obra FROM obras_empresa_grant_contextual WHERE empresa_id = v_empresa AND usuario_id = v_tester AND activo;
  r := r || E'\n10 el grant contextual de la empresa sigue anclado en la obra tras la función aditiva: ' ||
    CASE WHEN v_origen_obra = v_obra THEN 'OK' ELSE 'FALLO (' || coalesce(v_origen_obra::text, '<null>') || ')' END;

  -- ============================================================
  -- 11 — persona vinculada a una obra que se comparte en la misma llamada
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('Membrillo Otamendi Sur 9902', 'casa', v_admin) RETURNING id INTO v_obra3;
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Eleuterio', 'Manzanares', v_admin) RETURNING id INTO v_persona3;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra3, v_persona3, '{otro}');

  IF (SELECT pendiente FROM obras WHERE id = v_obra3) OR (SELECT pendiente FROM obras_personas WHERE id = v_persona3) THEN
    RAISE EXCEPTION 'setup: v_obra3/v_persona3 entraron pendientes';
  END IF;

  PERFORM obras_compartir_registros(v_tester, jsonb_build_array(
    jsonb_build_object('ente', 'obra', 'registro_id', v_obra3),
    jsonb_build_object('ente', 'persona', 'registro_id', v_persona3)
  ));
  PERFORM set_config('role', 'none', true);
  SELECT obra_id INTO v_origen_obra FROM obras_persona_grant_contextual WHERE persona_id = v_persona3 AND usuario_id = v_tester AND activo;
  r := r || E'\n11 persona anclada en la obra compartida en la misma llamada: ' ||
    CASE WHEN v_origen_obra = v_obra3 THEN 'OK' ELSE 'FALLO (' || coalesce(v_origen_obra::text, '<null>') || ')' END;

  -- ============================================================
  -- 12 — no dueño → OB026 / OB020
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM obras_compartir_registros(v_admin, jsonb_build_array(jsonb_build_object('ente', 'obra', 'registro_id', v_obra)));
    r := r || E'\n12a no dueño de la obra: FALLO (compartió)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n12a no dueño de la obra: ' || CASE WHEN SQLSTATE = 'OB026' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  BEGIN
    PERFORM obras_compartir_registros(v_admin, jsonb_build_array(jsonb_build_object('ente', 'empresa', 'registro_id', v_empresa)));
    r := r || E'\n12b no dueño de la empresa: FALLO (compartió)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n12b no dueño de la empresa: ' || CASE WHEN SQLSTATE = 'OB020' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  -- ============================================================
  -- 13 — compartir_registros reparte (por usuario y por módulo)
  --
  -- La base de test solo tiene dos usuarios reales: no hay forma de probar
  -- el split entre DOS receptores distintos. Lo que se verifica es que el
  -- agrupado por usuario+módulo dispara obras_compartir_registros con el
  -- batch completo (obra + persona) para el único receptor disponible.
  -- ============================================================
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('Cuarzo Vallejos Este 2210', 'casa', v_admin) RETURNING id INTO v_obra4;
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Fulgencio', 'Zaracho', v_admin) RETURNING id INTO v_persona4;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra4, v_persona4, '{otro}');

  IF (SELECT pendiente FROM obras WHERE id = v_obra4) OR (SELECT pendiente FROM obras_personas WHERE id = v_persona4) THEN
    RAISE EXCEPTION 'setup: v_obra4/v_persona4 entraron pendientes';
  END IF;

  PERFORM compartir_registros(jsonb_build_array(
    jsonb_build_object('usuario_id', v_tester, 'ente', 'obra', 'registro_id', v_obra4),
    jsonb_build_object('usuario_id', v_tester, 'ente', 'persona', 'registro_id', v_persona4)
  ));
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_obra_compartida WHERE obra_id = v_obra4 AND usuario_id = v_tester AND activo;
  r := r || E'\n13a compartir_registros comparte la obra: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_persona4 AND usuario_id = v_tester AND activo AND obra_id = v_obra4;
  r := r || E'\n13b ... y la persona, anclada en esa obra: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
