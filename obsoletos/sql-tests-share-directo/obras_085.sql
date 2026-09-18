-- Verificación de sql/085: la empresa compartida también es contextual.
-- Lo que llega arrastrado por una obra se ve solo dentro de esa obra, y el
-- contacto sale únicamente por obras_ficha_empresa().
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_082.sql.
--
-- Afirma:
--   A las columnas de contacto no salen por select directo (42501)
--   B tildar la empresa al compartir la obra → contextual, NO completo
--   C la empresa NO entra a la agenda del receptor (obras_puede_ver_empresa false)
--   D el receptor ve el vínculo de la empresa en obras_vinculos_de_obra
--   E el contacto abre con ctx=obra y NO abre sin contexto (OB030)
--   F el grant contextual no cuenta como directo (no habilita vincular)
--   G destildar apaga el grant de ESA obra sin revocar la obra
--   H revocar la obra apaga el grant contextual
--   I obras_compartir_registros: empresa con obra compartida → contextual anclado
--   J obras_compartir_registros: empresa sin ancla → OB029
--   K compartir la empresa desde su ficha sigue siendo grant COMPLETO
--   L transferir la obra sin tildar la empresa → contextual, NO agenda
--
-- El caso L es el que motivó la migración: antes de sql/085 la empresa
-- destildada entraba a la agenda del receptor.
--
-- Último resultado: 12/12 (2026-09-17).

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_obra2 uuid; v_e uuid; v_e2 uuid; v_p uuid;
  v_n int; v_tel text; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- Permisos explícitos: el test no puede leer el estado de producción.
  -- (Lección de obras_model_a: con los submódulos puestos a mano desde la app,
  --  un caso que afirma "no puede" pasa a poder y el siguiente muere.)
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas','obras_compartido',
    'obras_transferir')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN ('obras_ver','obras_empresas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- Nombres sin tokens en común entre sí: el detector de duplicados difuso
  -- congela (`pendiente`) la segunda entidad parecida, y las funciones de
  -- compartir exigen `NOT pendiente` — el caso J moría con OB020, no OB029.
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Zjfk Mrqn 085', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, telefono, email, creado_por)
  VALUES ('Kdlm Trqz SA', '1140000085', 'kdlm085@test.local', v_admin) RETURNING id INTO v_e;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_e, ARRAY['constructora']::rol_empresa[]);

  -- A — la trampa que sql/085 casi deja pasar: un REVOKE SELECT (columna) no
  -- recorta un GRANT SELECT de tabla entera. Acá se comprueba el resultado.
  BEGIN
    EXECUTE 'SELECT telefono FROM obras_empresas WHERE id = $1' INTO v_tel USING v_e;
    RAISE EXCEPTION 'A FALLA: el teléfono salió por select directo';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    EXECUTE 'SELECT direccion FROM obras_empresas WHERE id = $1' INTO v_tel USING v_e;
    RAISE EXCEPTION 'A FALLA: la dirección salió por select directo';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  -- La razón social sí tiene que salir, o el revoke se llevó de más.
  EXECUTE 'SELECT razon_social FROM obras_empresas WHERE id = $1' INTO v_tel USING v_e;
  IF v_tel <> 'Kdlm Trqz SA' THEN
    RAISE EXCEPTION 'A FALLA: el revoke se llevó la razón social';
  END IF;
  r := r || E'\nA OK  contacto sin GRANT SELECT; razón social sigue saliendo';

  -- B
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_e], ARRAY[]::uuid[]);
  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_e AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'B FALLA: no se otorgó el grant contextual'; END IF;
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_e AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'B FALLA: se otorgó un grant completo'; END IF;
  r := r || E'\nB OK  tildar en la obra → contextual, no completo';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  -- C
  IF obras_puede_ver_empresa(v_e) THEN
    RAISE EXCEPTION 'C FALLA: la empresa entró a la agenda del receptor';
  END IF;
  r := r || E'\nC OK  no entra a la agenda del receptor';

  -- D
  SELECT count(*) INTO v_n FROM obras_vinculos_de_obra(v_obra)
   WHERE tipo = 'empresa' AND entidad_id = v_e;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: el receptor no ve el vínculo de la empresa'; END IF;
  r := r || E'\nD OK  el vínculo se ve en la ficha de la obra';

  -- E
  SELECT telefono INTO v_tel FROM obras_ficha_empresa(v_e, v_obra);
  IF v_tel <> '1140000085' THEN RAISE EXCEPTION 'E FALLA: no abrió el contacto con ctx'; END IF;
  BEGIN
    PERFORM obras_ficha_empresa(v_e);
    RAISE EXCEPTION 'E FALLA: abrió el contacto sin contexto';
  EXCEPTION WHEN sqlstate 'OB030' THEN NULL;
  END;
  r := r || E'\nE OK  contacto con ctx=obra, cerrado sin contexto';

  -- F
  IF obras_empresa_grant_directo(v_e) THEN
    RAISE EXCEPTION 'F FALLA: el grant contextual cuenta como directo';
  END IF;
  r := r || E'\nF OK  el contextual no habilita vincular';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- G
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_e AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'G FALLA: destildar no apagó el grant'; END IF;
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra AND usuario_id = v_tester AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'G FALLA: se revocó la obra entera'; END IF;
  r := r || E'\nG OK  destildar apaga solo el grant del padre';

  -- H
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_e], ARRAY[]::uuid[]);
  PERFORM obras_revocar_obra(v_obra, v_tester);
  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_e AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'H FALLA: revocar la obra dejó vivo el grant'; END IF;
  r := r || E'\nH OK  revocar la obra apaga el grant';

  -- I
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  PERFORM obras_compartir_registros(
    v_tester, jsonb_build_array(jsonb_build_object('ente', 'empresa', 'registro_id', v_e)));
  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_e AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'I FALLA: compartir_registros no ancló en la obra'; END IF;
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_e AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'I FALLA: compartir_registros otorgó grant completo'; END IF;
  r := r || E'\nI OK  compartir_registros ancla en la obra compartida';

  -- J — una empresa que no cuelga de ninguna obra compartida no tiene ancla.
  PERFORM obras_revocar_obra(v_obra, v_tester);
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Wxyv Plqm SRL', v_admin) RETURNING id INTO v_e2;
  BEGIN
    PERFORM obras_compartir_registros(
      v_tester, jsonb_build_array(jsonb_build_object('ente', 'empresa', 'registro_id', v_e2)));
    RAISE EXCEPTION 'J FALLA: compartió una empresa sin ancla';
  EXCEPTION WHEN sqlstate 'OB029' THEN NULL;
  END;
  r := r || E'\nJ OK  sin ancla corta con OB029';

  -- K — compartir desde la ficha de la empresa NO cambió: es acto directo del
  -- dueño sobre su agenda, no cascada de una obra.
  PERFORM obras_compartir_empresa(v_e2, v_tester, ARRAY[]::uuid[]);
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_e2 AND usuario_id = v_tester AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'K FALLA: compartir directo no otorgó grant completo'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  IF NOT obras_puede_ver_empresa(v_e2) THEN
    RAISE EXCEPTION 'K FALLA: el share directo no entró a la agenda';
  END IF;
  IF NOT obras_empresa_grant_directo(v_e2) THEN
    RAISE EXCEPTION 'K FALLA: el share directo no cuenta como directo';
  END IF;
  r := r || E'\nK OK  compartir desde la ficha sigue siendo grant completo';

  -- L — el caso que motivó sql/085. Va último: mueve responsable_id.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Bvxt Wlpd 085', 'casa', v_admin) RETURNING id INTO v_obra2;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra2, v_e, ARRAY['desarrolladora']::rol_empresa[]);

  PERFORM obras_transferir(v_obra2, v_tester, ARRAY[]::uuid[]);

  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_e AND usuario_id = v_tester AND obra_id = v_obra2 AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'L FALLA: transferir no dejó grant contextual'; END IF;
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_e AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'L FALLA: la empresa destildada entró a la agenda'; END IF;
  -- La empresa no tildada sigue siendo del saliente.
  SELECT count(*) INTO v_n FROM obras_empresas
   WHERE id = v_e AND creado_por = v_admin;
  IF v_n <> 1 THEN RAISE EXCEPTION 'L FALLA: la empresa destildada cambió de dueño'; END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  IF obras_puede_ver_empresa(v_e) THEN
    RAISE EXCEPTION 'L FALLA: el nuevo dueño ve la empresa en su agenda';
  END IF;
  SELECT count(*) INTO v_n FROM obras_vinculos_de_obra(v_obra2)
   WHERE tipo = 'empresa' AND entidad_id = v_e;
  IF v_n <> 1 THEN RAISE EXCEPTION 'L FALLA: el nuevo dueño no ve el vínculo'; END IF;
  r := r || E'\nL OK  transferir sin tildar → contextual, no agenda';

  RAISE EXCEPTION E'--- obras_085: 12/12 ---%', r;
END;
$test$;
