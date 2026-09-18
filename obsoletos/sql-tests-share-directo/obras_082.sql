-- Verificación de sql/082: compartir una obra/empresa no reparte contactos.
-- El checklist otorga grant CONTEXTUAL anclado al padre, no grant completo.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_049.sql.
--
-- Afirma:
--   A tildar la persona al compartir la obra → grant contextual, NO completo
--   B la persona NO entra a la agenda del receptor (obras_puede_ver_persona false)
--   C el receptor ve el vínculo de la persona en obras_vinculos_de_obra
--   D el contacto abre con ctx=obra y NO abre sin contexto
--   E el grant contextual no habilita vincular (obras_persona_grant_directo false)
--   F destildar apaga el grant contextual de ESE padre
--   G revocar la obra apaga el grant contextual
--   H checklist de empresa → grant contextual anclado a la empresa
--   I el receptor ve la fila de obras_persona_empresa dentro de esa empresa
--   J revocar la empresa apaga el grant (cascada perdida en sql/052, restituida)
--   K obras_compartir_registros: persona con obra compartida → contextual anclado
--   L obras_compartir_registros: persona sin ancla → OB029
--
-- Último resultado: pendiente de correr.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_e uuid; v_p uuid; v_p2 uuid; v_n int; v_tel text; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN ('obras_ver','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Kdlm del test 082', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Kdlm Empresa 082', v_admin) RETURNING id INTO v_e;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Kdlm', 'Trqz', '1140000082', v_admin) RETURNING id INTO v_p;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p, ARRAY['compras']::rol_persona[]);
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p, v_e, 'Jefe de compras');

  -- A
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[v_p]);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: no se otorgó el grant contextual'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_compartida
   WHERE persona_id = v_p AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'A FALLA: se otorgó un grant completo'; END IF;
  r := r || E'\nA OK  tildar en la obra → contextual, no completo';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  -- B
  IF obras_puede_ver_persona(v_p) THEN
    RAISE EXCEPTION 'B FALLA: la persona entró a la agenda del receptor';
  END IF;
  r := r || E'\nB OK  no entra a la agenda del receptor';

  -- C
  SELECT count(*) INTO v_n FROM obras_vinculos_de_obra(v_obra)
   WHERE tipo = 'persona' AND entidad_id = v_p;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: el receptor no ve el vínculo de la persona'; END IF;
  r := r || E'\nC OK  el vínculo se ve en la ficha de la obra';

  -- D
  SELECT telefono INTO v_tel FROM obras_ficha_persona(v_p, 'obra', v_obra);
  IF v_tel <> '1140000082' THEN RAISE EXCEPTION 'D FALLA: no abrió el contacto con ctx'; END IF;
  BEGIN
    PERFORM obras_ficha_persona(v_p);
    RAISE EXCEPTION 'D FALLA: abrió el contacto sin contexto';
  EXCEPTION WHEN sqlstate 'OB022' THEN NULL;
  END;
  r := r || E'\nD OK  contacto con ctx=obra, cerrado sin contexto';

  -- E
  IF obras_persona_grant_directo(v_p) THEN
    RAISE EXCEPTION 'E FALLA: el grant contextual cuenta como directo';
  END IF;
  r := r || E'\nE OK  el contextual no habilita vincular';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- F
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'F FALLA: destildar no apagó el grant'; END IF;
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra AND usuario_id = v_tester AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'F FALLA: se revocó la obra entera'; END IF;
  r := r || E'\nF OK  destildar apaga solo el grant del padre';

  -- G
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[v_p]);
  PERFORM obras_revocar_obra(v_obra, v_tester);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'G FALLA: revocar la obra dejó vivo el grant'; END IF;
  r := r || E'\nG OK  revocar la obra apaga el grant';

  -- H
  PERFORM obras_compartir_empresa(v_e, v_tester, ARRAY[v_p]);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND empresa_id = v_e AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'H FALLA: el checklist de empresa no otorgó contextual'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_compartida
   WHERE persona_id = v_p AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'H FALLA: el checklist de empresa otorgó grant completo'; END IF;
  r := r || E'\nH OK  tildar en la empresa → contextual anclado a la empresa';

  -- I
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_persona_empresa
   WHERE persona_id = v_p AND empresa_id = v_e AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'I FALLA: el receptor no ve el empleado de la empresa'; END IF;
  r := r || E'\nI OK  la fila de empleado sale con grant contextual';

  -- J
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_revocar_empresa(v_e, v_tester);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND empresa_id = v_e AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'J FALLA: revocar la empresa dejó vivo el grant'; END IF;
  r := r || E'\nJ OK  revocar la empresa apaga el grant (cascada restituida)';

  -- K
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  PERFORM obras_compartir_registros(
    v_tester, jsonb_build_array(jsonb_build_object('ente', 'persona', 'registro_id', v_p)));
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'K FALLA: compartir_registros no ancló en la obra'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_compartida
   WHERE persona_id = v_p AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'K FALLA: compartir_registros otorgó grant completo'; END IF;
  r := r || E'
K OK  compartir_registros ancla en la obra compartida';

  -- L
  PERFORM obras_revocar_obra(v_obra, v_tester);
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Wxyv', 'Plqm', '1140000182', v_admin) RETURNING id INTO v_p2;
  BEGIN
    PERFORM obras_compartir_registros(
      v_tester, jsonb_build_array(jsonb_build_object('ente', 'persona', 'registro_id', v_p2)));
    RAISE EXCEPTION 'L FALLA: compartió una persona sin ancla';
  EXCEPTION WHEN sqlstate 'OB029' THEN NULL;
  END;
  r := r || E'
L OK  sin ancla corta con OB029';

  RAISE EXCEPTION E'--- obras_082: 12/12 ---%', r;
END;
$test$;
