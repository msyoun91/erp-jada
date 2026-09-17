-- Verificación de sql/086: la obra es el único acto de compartir.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_085.sql.
--
-- Afirma:
--   A las funciones de share directo ya no existen
--   B las tablas de share directo ya no existen
--   C compartir la obra + checklist → contextual, y el receptor ve el vínculo
--   D el receptor NO tiene la empresa ni la persona en su agenda
--   E el receptor no puede colgar el contacto ajeno de una obra suya
--   F obras_revocar_contextual destilda una fila sin revocar la obra
--   G obras_revocar_contextual sin ser responsable → OB026
--   H revocar la obra apaga todo lo que la acompaña
--   I obras_compartir_registros: persona sin obra compartida → OB029
--
-- Último resultado: 9/9 (2026-09-17).

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_obra_suya uuid; v_e uuid; v_p uuid;
  v_n int; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- A — la segunda puerta no existe más.
  SELECT count(*) INTO v_n FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('obras_compartir_persona','obras_compartir_empresa',
                       'obras_revocar_persona','obras_revocar_empresa',
                       'obras_persona_grant_directo','obras_empresa_grant_directo',
                       'obras_persona_compartida_conmigo','obras_empresa_compartida_conmigo',
                       'obras_relaciones_compartibles_empresa');
  IF v_n <> 0 THEN RAISE EXCEPTION 'A FALLA: quedaron % funciones de share directo', v_n; END IF;
  r := r || E'\nA OK  las funciones de share directo no existen';

  -- B — ni sus tablas.
  SELECT count(*) INTO v_n FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relname IN ('obras_persona_compartida','obras_empresa_compartida');
  IF v_n <> 0 THEN RAISE EXCEPTION 'B FALLA: quedaron % tablas de share directo', v_n; END IF;
  r := r || E'\nB OK  las tablas de share directo no existen';

  -- Permisos explícitos: el test no puede leer el estado de producción.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- Nombres sin tokens en común entre sí: el detector difuso congela la segunda
  -- entidad parecida y las funciones de compartir exigen `NOT pendiente`
  -- (lección de obras_085).
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Qhvz Tmrl 086', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, telefono, creado_por)
  VALUES ('Nkbw Gxsd 086 SA', '1155550086', v_admin) RETURNING id INTO v_e;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Pfjr', 'Ldqx 086', '1155550186', v_admin) RETURNING id INTO v_p;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_e, ARRAY['desarrolladora']::rol_empresa[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p, ARRAY['arquitecto']::rol_persona[]);

  -- C — compartir la obra tildando los dos.
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_e], ARRAY[v_p]);

  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_e AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: la empresa no quedó contextual'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: la persona no quedó contextual'; END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_vinculos_de_obra(v_obra);
  IF v_n <> 2 THEN RAISE EXCEPTION 'C FALLA: el receptor ve % vínculos, esperaba 2', v_n; END IF;
  -- La policy también deja leer la fila directo, no solo la DEFINER.
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE obra_id = v_obra AND persona_id = v_p AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: el receptor no lee la fila de vínculo'; END IF;
  r := r || E'\nC OK  checklist → contextual, y el receptor ve el vínculo';

  -- D — nada de eso entra a su agenda.
  IF obras_puede_ver_empresa(v_e) THEN
    RAISE EXCEPTION 'D FALLA: la empresa entró a la agenda del receptor';
  END IF;
  IF obras_puede_ver_persona(v_p) THEN
    RAISE EXCEPTION 'D FALLA: la persona entró a la agenda del receptor';
  END IF;
  r := r || E'\nD OK  lo tildado no entra a la agenda del receptor';

  -- E — y no puede colgarlo de una obra suya.
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Yscp Rwkn 086', 'casa', v_tester) RETURNING id INTO v_obra_suya;
  BEGIN
    INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
    VALUES (v_obra_suya, v_p, ARRAY['arquitecto']::rol_persona[]);
    RAISE EXCEPTION 'E FALLA: colgó la persona ajena de su obra';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  r := r || E'\nE OK  el receptor no cuelga el contacto ajeno de su obra';

  -- F — destildar una fila sin revocar la obra.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_revocar_contextual('empresa', v_e, v_tester, v_obra);
  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_e AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'F FALLA: el grant de la empresa sigue activo'; END IF;
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra AND usuario_id = v_tester AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'F FALLA: destildar revocó la obra'; END IF;
  r := r || E'\nF OK  destildar una fila no revoca la obra';

  -- G — no lo hace cualquiera.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  BEGIN
    PERFORM obras_revocar_contextual('persona', v_p, v_tester, v_obra);
    RAISE EXCEPTION 'G FALLA: un no-responsable revocó';
  EXCEPTION WHEN sqlstate 'OB026' THEN NULL;
  END;
  r := r || E'\nG OK  revocar contextual exige ser el responsable';

  -- H — revocar la obra apaga lo que la acompaña.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_revocar_obra(v_obra, v_tester);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'H FALLA: quedó vivo el grant de la persona'; END IF;
  r := r || E'\nH OK  revocar la obra apaga la cascada contextual';

  -- I — sin obra compartida no hay ancla (rama de tareas).
  BEGIN
    PERFORM obras_compartir_registros(
      v_tester,
      jsonb_build_array(jsonb_build_object('ente', 'persona', 'registro_id', v_p))
    );
    RAISE EXCEPTION 'I FALLA: compartió la persona sin ancla';
  EXCEPTION WHEN sqlstate 'OB029' THEN NULL;
  END;
  r := r || E'\nI OK  sin obra compartida, compartir_registros corta con OB029';

  RAISE EXCEPTION E'--- obras_086: 9/9 ---%', r;
END;
$test$;
