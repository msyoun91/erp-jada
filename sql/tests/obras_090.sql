-- Verificación de sql/090: el grant contextual muere con el ancla.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_088.sql.
--
-- Hacen falta TRES usuarios y no dos. El grant huérfano de V1 aparece cuando el
-- otorgante, el receptor y el destino de la transferencia son distintos: con dos
-- usuarios, transferir la persona al mismo que tiene el grant lo apaga por la
-- regla "nadie se comparte consigo mismo" y el caso se cae solo.
--
-- Reparto: A es el dueño (y el saliente), B el tercero que recibe la obra
-- compartida, C el destino de la transferencia de contactos.
--
-- Afirma:
--   A transferir una persona NO mueve el otorgante de los grants anclados en
--     obras que no participan de la transferencia (V1, la causa del huérfano)
--   B revocar la obra apaga el grant contextual aunque el otorgante no sea
--     quien revoca (V1, el filtro `otorgada_por = auth.uid()` que se fue)
--   C con el grant activo pero sin la obra, la ficha se cierra igual: el grant
--     vale mientras se vea el ancla (V1, regla 1 aislada)
--   D el grant de persona anclado en una EMPRESA se revoca (V2) — antes la
--     firma solo aceptaba anclas obra y devolvía OB026 siempre
--   E tipo o ancla inválidos → OB031 en vez de éxito silencioso (V3)
--   F sin ser dueño del ancla ni del contacto → OB026, tampoco silencio (V3)
--   G el admin que se transfiere una obra a sí mismo recibe los grants
--     contextuales de los contactos que no migran (V4)
--
-- Último resultado: 7/7 (2026-09-18, revalidado tras sql/094).

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- dueño / saliente
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- tercero receptor
  v_c uuid := gen_random_uuid();                       -- destino
  v_obra uuid; v_obra3 uuid;
  v_p uuid; v_p2 uuid; v_p3 uuid; v_emp uuid;
  v_n int; v_otorgante uuid; v_activo boolean; r text := '';
  v_rol text := current_setting('role', true);
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          created_at, updated_at)
  VALUES (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'destino-090@example.invalid', '', now(), now());

  -- ── Permisos ─────────────────────────────────────────────────────────────
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b, v_c)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  -- Ninguno de los tres tiene `_todas` ni `obras_transferir`: si los tuvieran,
  -- `obras_puede_ver_persona` y `obras_puede_ver_obra` darían true por otra vía
  -- y los casos pasarían sin ejercitar el grant contextual. `obras_transferir`
  -- entra al final, solo para el caso G.
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_compartido',
    'obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas',
    'obras_transferir_propias','obras_personas_transferir_propias')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_compartido',
    'obras_empresas','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_c, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_personas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);

  -- ── Datos de A ───────────────────────────────────────────────────────────
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Qbvx Lmnt 090', 'edificio', v_a) RETURNING id INTO v_obra;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Zrkt', 'Pmwld', '1145678900', v_a) RETURNING id INTO v_p;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p, ARRAY['compras']::rol_persona[]);

  -- A comparte la obra con B y tilda a la persona.
  PERFORM obras_compartir_obra(v_obra, v_b, ARRAY[]::uuid[], ARRAY[v_p]);

  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_b AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'setup FALLA: el checklist no otorgó (%)', v_n; END IF;

  -- ── A · el otorgante no se mueve al transferir la persona ────────────────
  PERFORM obras_transferir_persona(v_p, v_c, false);

  SELECT otorgada_por, activo INTO v_otorgante, v_activo
  FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_b AND obra_id = v_obra;

  IF v_otorgante IS DISTINCT FROM v_a THEN
    RAISE EXCEPTION 'A FALLA: el otorgante pasó a % (la obra sigue siendo de A)', v_otorgante;
  END IF;
  IF NOT v_activo THEN RAISE EXCEPTION 'A FALLA: el grant se apagó solo'; END IF;
  r := r || E'\nA OK  transferir la persona no mueve el otorgante del ancla ajena';

  -- ── B · revocar la obra apaga el grant ───────────────────────────────────
  PERFORM obras_revocar_obra(v_obra, v_b);

  SELECT activo INTO v_activo FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_b AND obra_id = v_obra;
  IF v_activo THEN
    RAISE EXCEPTION 'B FALLA: el grant sobrevivió a la revocación de la obra';
  END IF;
  r := r || E'\nB OK  revocar la obra apaga el grant contextual';

  -- ── C · el grant no alcanza sin el ancla ─────────────────────────────────
  -- Se revive a mano: la tabla no tiene policy de UPDATE para `authenticated`,
  -- así que el UPDATE hay que hacerlo con el rol de la sesión o no toca nada
  -- (y el caso pasaría por la razón equivocada).
  PERFORM set_config('role', COALESCE(v_rol, 'none'), true);
  UPDATE obras_persona_grant_contextual SET activo = true
  WHERE persona_id = v_p AND usuario_id = v_b AND obra_id = v_obra;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  BEGIN
    PERFORM obras_ficha_persona(v_p, 'obra', v_obra);
    RAISE EXCEPTION 'C FALLA: la ficha se abrió con la obra revocada';
  EXCEPTION WHEN SQLSTATE 'OB009' THEN NULL;
  END;
  r := r || E'\nC OK  grant activo sin acceso al ancla no abre la ficha';

  -- ── D · el grant anclado en empresa se revoca ────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Nvkr Tzql SA 090', v_a) RETURNING id INTO v_emp;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Hqdm', 'Wbcxs', v_a) RETURNING id INTO v_p2;
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p2, v_emp, 'Compras');

  -- Estado 2 (el default): la persona se va, A conserva grant anclado en su
  -- empresa. El otorgante es C, que no es dueño del ancla.
  PERFORM obras_transferir_persona(v_p2, v_c, false);

  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
  WHERE persona_id = v_p2 AND usuario_id = v_a AND empresa_id = v_emp AND activo;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'D FALLA: el estado 2 no dejó el grant recíproco (%)', v_n;
  END IF;

  -- Lo revoca C: es el dueño del contacto —la persona migró a él— y no el de la
  -- empresa ancla. Hasta sql/093 lo autorizaba como otorgante, que en los flujos
  -- reales es la misma persona: `otorgada_por` nace siempre con el dueño.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  PERFORM obras_revocar_contextual('persona', v_p2, v_a, 'empresa', v_emp);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  SELECT activo INTO v_activo FROM obras_persona_grant_contextual
  WHERE persona_id = v_p2 AND usuario_id = v_a AND empresa_id = v_emp;
  IF v_activo THEN RAISE EXCEPTION 'D FALLA: el grant anclado en empresa no se revocó'; END IF;
  r := r || E'\nD OK  grant anclado en empresa: revocable por el dueno del contacto';

  -- ── E · tipo o ancla inválidos ───────────────────────────────────────────
  BEGIN
    PERFORM obras_revocar_contextual('empresa', v_emp, v_b, 'empresa', v_emp);
    RAISE EXCEPTION 'E FALLA: aceptó una empresa anclada en empresa';
  EXCEPTION WHEN SQLSTATE 'OB031' THEN NULL;
  END;
  BEGIN
    PERFORM obras_revocar_contextual('obra', v_obra, v_b, 'obra', v_obra);
    RAISE EXCEPTION 'E FALLA: aceptó un tipo inválido';
  EXCEPTION WHEN SQLSTATE 'OB031' THEN NULL;
  END;
  r := r || E'\nE OK  tipo o ancla inválidos → OB031';

  -- ── F · sin autoridad, error y no silencio ───────────────────────────────
  PERFORM set_config('role', COALESCE(v_rol, 'none'), true);
  UPDATE obras_persona_grant_contextual SET activo = true
  WHERE persona_id = v_p2 AND usuario_id = v_a AND empresa_id = v_emp;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  BEGIN
    PERFORM obras_revocar_contextual('persona', v_p2, v_a, 'empresa', v_emp);
    RAISE EXCEPTION 'F FALLA: revocó sin ser dueño del ancla ni del contacto';
  EXCEPTION WHEN SQLSTATE 'OB026' THEN NULL;
  END;
  r := r || E'\nF OK  sin autoridad → OB026';

  -- ── G · el admin que se transfiere la obra a sí mismo ────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Fxwd Jmbr 090', 'casa', v_a) RETURNING id INTO v_obra3;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Tlvz', 'Gkrnp', '1199887766', v_a) RETURNING id INTO v_p3;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra3, v_p3, ARRAY['decisor']::rol_persona[]);

  PERFORM set_config('role', COALESCE(v_rol, 'none'), true);
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo = 'obras_transferir'
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_transferir(v_obra3, v_b, ARRAY[]::uuid[], ARRAY[]::uuid[]);

  SELECT otorgada_por INTO v_otorgante FROM obras_persona_grant_contextual
  WHERE persona_id = v_p3 AND usuario_id = v_b AND obra_id = v_obra3 AND activo;
  IF v_otorgante IS DISTINCT FROM v_a THEN
    RAISE EXCEPTION 'G FALLA: transferirse la obra a sí mismo no dejó grant (otorgante %)',
      v_otorgante;
  END IF;

  SELECT count(*) INTO v_n FROM obras_ficha_persona(v_p3, 'obra', v_obra3);
  IF v_n <> 1 THEN RAISE EXCEPTION 'G FALLA: la ficha no abre (%)', v_n; END IF;
  r := r || E'\nG OK  transferirse la obra a sí mismo otorga los contextuales';

  RAISE EXCEPTION E'obras_090 — 7/7\n%', r;
END;
$test$;
