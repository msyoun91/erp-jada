-- Verificación de sql/052: un contacto compartido VÍA obra (checklist) no se
-- puede colgar de las obras propias del receptor; el share DIRECTO sí, y al
-- revocarlo la cascada arrastra esos vínculos.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_051.sql.
--
-- Afirma:
--   A  persona compartida por CHECKLIST de obra → el receptor NO puede
--      vincularla a una obra propia (RLS corta el INSERT)
--   B  persona compartida DIRECTO → el receptor SÍ puede vincularla
--   C  obras_contar_vinculos_persona_receptor cuenta ese vínculo para el dueño,
--      y devuelve NULL para quien no es dueño
--   D  obras_revocar_persona (share directo) desactiva el vínculo del receptor
--   E  empresa: mismo patrón (checklist bloquea, directo permite, revocar arrastra)
--
-- Último resultado: 5/5.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra_t uuid; v_obra_a uuid;
  v_p_dir uuid; v_p_chk uuid; v_e_dir uuid; v_e_chk uuid;
  v_n int; v_bloqueado boolean;
  r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- Admin: una obra con su gente, y contactos sueltos para el share directo.
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Mnbv del test 052', 'edificio', v_admin) RETURNING id INTO v_obra_a;

  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Pdir', 'Zxc', '1140000521', v_admin) RETURNING id INTO v_p_dir;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Pchk', 'Zxc', '1140000522', v_admin) RETURNING id INTO v_p_chk;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Edir Empresa 052', v_admin) RETURNING id INTO v_e_dir;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Echk Empresa 052', v_admin) RETURNING id INTO v_e_chk;

  -- Lo "chk" tiene que estar vinculado a la obra para poder tildarse.
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra_a, v_p_chk, ARRAY['compras']::rol_persona[]);
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra_a, v_e_chk, ARRAY['constructora']::rol_empresa[]);

  -- Share directo de Pdir / Edir; y la obra con Pchk/Echk tildados en checklist.
  PERFORM obras_compartir_persona(v_p_dir, v_tester);
  PERFORM obras_compartir_empresa(v_e_dir, v_tester, ARRAY[]::uuid[]);
  PERFORM obras_compartir_obra(v_obra_a, v_tester, ARRAY[v_e_chk], ARRAY[v_p_chk]);

  -- Ahora soy el receptor, con una obra propia.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Qazwsx del receptor 052', 'edificio', v_tester) RETURNING id INTO v_obra_t;

  -- A: Pchk (compartida vía checklist) NO entra a mi obra
  v_bloqueado := false;
  BEGIN
    INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
    VALUES (v_obra_t, v_p_chk, ARRAY['compras']::rol_persona[]);
  EXCEPTION WHEN insufficient_privilege THEN v_bloqueado := true;
  END;
  IF NOT v_bloqueado THEN RAISE EXCEPTION 'A FALLA: el receptor colgó de su obra una persona compartida por checklist'; END IF;
  r := r || E'\nA OK  persona compartida por checklist no se vincula a obra propia';

  -- B: Pdir (compartida directo) SÍ entra
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra_t, v_p_dir, ARRAY['compras']::rol_persona[]);
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE obra_id = v_obra_t AND persona_id = v_p_dir AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'B FALLA: el receptor no pudo vincular la persona compartida directo'; END IF;
  r := r || E'\nB OK  persona compartida directo se vincula a obra propia';

  -- C: el contador — NULL para el receptor (no es dueño), 1 para el dueño
  IF obras_contar_vinculos_persona_receptor(v_p_dir, v_tester) IS NOT NULL THEN
    RAISE EXCEPTION 'C FALLA: el contador respondió a quien no es dueño de la persona';
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT obras_contar_vinculos_persona_receptor(v_p_dir, v_tester) INTO v_n;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: el contador dio % (esperaba 1)', v_n; END IF;
  r := r || E'\nC OK  obras_contar_vinculos_persona_receptor: 1 para el dueño, NULL para el resto';

  -- D: revocar el share directo desactiva el vínculo del receptor
  PERFORM obras_revocar_persona(v_p_dir, v_tester);
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE obra_id = v_obra_t AND persona_id = v_p_dir AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'D FALLA: el vínculo del receptor sobrevivió a la revocación'; END IF;
  r := r || E'\nD OK  revocar la persona arrastra el vínculo del receptor';

  -- E: empresa, mismo patrón
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  v_bloqueado := false;
  BEGIN
    INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
    VALUES (v_obra_t, v_e_chk, ARRAY['constructora']::rol_empresa[]);
  EXCEPTION WHEN insufficient_privilege THEN v_bloqueado := true;
  END;
  IF NOT v_bloqueado THEN RAISE EXCEPTION 'E FALLA: el receptor colgó de su obra una empresa compartida por checklist'; END IF;

  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra_t, v_e_dir, ARRAY['constructora']::rol_empresa[]);
  SELECT count(*) INTO v_n FROM obras_obra_empresa
   WHERE obra_id = v_obra_t AND empresa_id = v_e_dir AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'E FALLA: el receptor no pudo vincular la empresa compartida directo'; END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT obras_contar_vinculos_empresa_receptor(v_e_dir, v_tester) INTO v_n;
  IF v_n <> 1 THEN RAISE EXCEPTION 'E FALLA: el contador de empresa dio % (esperaba 1)', v_n; END IF;
  PERFORM obras_revocar_empresa(v_e_dir, v_tester);
  SELECT count(*) INTO v_n FROM obras_obra_empresa
   WHERE obra_id = v_obra_t AND empresa_id = v_e_dir AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'E FALLA: el vínculo de empresa del receptor sobrevivió a la revocación'; END IF;
  r := r || E'\nE OK  empresa: checklist bloquea, directo permite, revocar arrastra';

  RAISE EXCEPTION E'--- obras_052: 5/5 ---%', r;
END;
$test$;
