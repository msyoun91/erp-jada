-- Verificación de sql/095: el vínculo se va con la obra.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_093.sql.
--
-- Reparto: A dueño original y saliente; B recibe la obra por transferencia;
-- C receptor de la obra compartida, que le suma un contacto suyo (sql/051).
--
-- Afirma:
--   A transferir pasa al entrante los vínculos que el saliente cargó en la
--     obra —activos e inactivos— y no toca el que sumó el receptor
--   B el saliente ya no lee ni toca los vínculos de la obra que transfirió
--   C el dueño nuevo decide: quita un vínculo que cargó el anterior y el
--     anterior no lo repone
--   D devolverle la obra compartida al anterior no traba ni borra: el dueño
--     nuevo edita sus contactos (sin OB028) y revocarlo no los desactiva
--   E el receptor revocado no repone su vínculo ni lo lee
--   F el receptor vigente conserva lo suyo: repone y edita su vínculo, y el
--     responsable sigue sin poder reescribirlo (OB028) pero sí quitarlo
--
-- Último resultado: 6/6 (2026-09-18).

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- dueño original
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- recibe la obra
  v_c uuid := gen_random_uuid();                       -- receptor de la obra
  v_o uuid; v_p uuid; v_p2 uuid; v_q uuid; v_e uuid;
  v_vp uuid; v_vp2 uuid; v_ve uuid; v_vq uuid;
  v_n int; v_activo boolean; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          created_at, updated_at)
  VALUES (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'receptor-095@example.invalid', '', now(), now());

  -- ── Permisos ─────────────────────────────────────────────────────────────
  -- Ninguno con `_todas` ni `obras_transferir` global: abrirían vías laterales
  -- y los casos pasarían sin ejercitar nada.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b, v_c)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_compartido',
    'obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_transferir_propias')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_vincular','obras_compartido','obras_empresas','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_c, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_vincular','obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- ── A arma su obra y se la comparte a C ──────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Vlkz Pqtr 095', 'edificio', v_a) RETURNING id INTO v_o;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Hmzr Dwkb SA 095', v_a) RETURNING id INTO v_e;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Tfqn', 'Zxlj', '1145690951', v_a) RETURNING id INTO v_p;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Rbwp', 'Kgvm', '1145690952', v_a) RETURNING id INTO v_p2;

  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_e, ARRAY['constructora']::rol_empresa[]) RETURNING id INTO v_ve;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_p, ARRAY['arquitecto']::rol_persona[]) RETURNING id INTO v_vp;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_p2, ARRAY['compras']::rol_persona[]) RETURNING id INTO v_vp2;
  -- Uno inactivo: si quedara a nombre de A, el día que alguien lo reactive
  -- vuelve a colgar de quien ya no es parte.
  UPDATE obras_obra_persona SET activo = false WHERE id = v_vp2;

  PERFORM obras_compartir_obra(v_o, v_c, '{}', '{}');

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Nczd', 'Yplh', '1145690953', v_c) RETURNING id INTO v_q;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_q, ARRAY['decisor']::rol_persona[]) RETURNING id INTO v_vq;

  -- ── Y A transfiere la obra a B sin llevarse contactos ────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  PERFORM obras_transferir(v_o, v_b, '{}', '{}');

  -- ── A · los vínculos del saliente se van con la obra ─────────────────────
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_obra_persona
  WHERE id IN (v_vp, v_vp2) AND creado_por = v_b;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'A FALLA: los vínculos de persona de A no pasaron a B (% de 2)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_empresa WHERE id = v_ve AND creado_por = v_b;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A FALLA: el vínculo de empresa de A no pasó a B';
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona WHERE id = v_vq AND creado_por = v_c;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A FALLA: transferir le sacó a C el vínculo que sumó como receptor';
  END IF;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\nA OK  lo que cargo el saliente se va con la obra; lo del receptor queda suyo';

  -- ── B · el saliente ya no lee ni toca ────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  UPDATE obras_obra_persona SET observaciones = 'nota de B 095' WHERE id = v_vp;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  SELECT count(*) INTO v_n FROM obras_obra_persona WHERE id IN (v_vp, v_vp2);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'B FALLA: A sigue leyendo los vínculos de una obra que transfirió (%)', v_n;
  END IF;
  UPDATE obras_obra_persona SET roles = ARRAY['otro']::rol_persona[] WHERE id = v_vp;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'B FALLA: A editó un vínculo de la obra de B';
  END IF;
  r := r || E'\nB OK  el saliente no lee ni edita los vinculos de la obra que transfirio';

  -- ── C · el dueño nuevo quita y el anterior no repone ─────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  UPDATE obras_obra_persona SET activo = false WHERE id = v_vp;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'C FALLA: el dueño nuevo no pudo quitar un vínculo de su obra';
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  UPDATE obras_obra_persona SET activo = true WHERE id = v_vp;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'C FALLA: el saliente repuso un vínculo que el dueño nuevo quitó';
  END IF;
  r := r || E'\nC OK  lo que quita el dueno nuevo queda quitado';

  -- ── D · compartirle la obra al anterior no traba ni borra ────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  UPDATE obras_obra_persona SET activo = true WHERE id = v_vp;
  PERFORM obras_compartir_obra(v_o, v_a, '{}', '{}');

  UPDATE obras_obra_persona SET roles = ARRAY['decisor']::rol_persona[] WHERE id = v_vp;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'D FALLA: el dueño nuevo no pudo editar un contacto de su obra';
  END IF;

  PERFORM obras_revocar_obra(v_o, v_a);
  PERFORM set_config('role', 'none', true);
  SELECT activo INTO v_activo FROM obras_obra_persona WHERE id = v_vp;
  PERFORM set_config('role', 'authenticated', true);
  IF NOT v_activo THEN
    RAISE EXCEPTION 'D FALLA: revocar al dueño anterior desactivó lo que cargó cuando era suya';
  END IF;
  r := r || E'\nD OK  devolverle la obra al anterior no traba (OB028) ni borra al revocarlo';

  -- ── E · el receptor revocado no repone ───────────────────────────────────
  PERFORM obras_revocar_obra(v_o, v_c);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  UPDATE obras_obra_persona SET activo = true WHERE id = v_vq;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'E FALLA: el receptor revocado repuso su vínculo en la obra ajena';
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona WHERE id = v_vq;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'E FALLA: el receptor revocado sigue leyendo su vínculo';
  END IF;
  r := r || E'\nE OK  revocado, el receptor no repone ni lee lo que sumo';

  -- ── F · el receptor vigente conserva lo suyo ─────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_compartir_obra(v_o, v_c, '{}', '{}');

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  UPDATE obras_obra_persona
  SET activo = true, observaciones = 'lo sume yo 095' WHERE id = v_vq;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'F FALLA: el receptor vigente no pudo reponer ni editar su vínculo';
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  BEGIN
    UPDATE obras_obra_persona SET roles = ARRAY['otro']::rol_persona[] WHERE id = v_vq;
    RAISE EXCEPTION 'F FALLA: el responsable reescribió el vínculo de un receptor';
  EXCEPTION WHEN SQLSTATE 'OB028' THEN NULL;
  END;

  UPDATE obras_obra_persona SET activo = false WHERE id = v_vq;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'F FALLA: el responsable no pudo quitar el vínculo de un receptor';
  END IF;
  r := r || E'\nF OK  el receptor vigente repone y edita lo suyo; el responsable lo quita, no lo reescribe';

  RAISE EXCEPTION E'obras_095 — 6/6\n%', r;
END;
$test$;
