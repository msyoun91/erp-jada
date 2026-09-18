-- Verificación de sql/097: el dueño del contacto lo ve en la obra que le comparten.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_095.sql.
--
-- Reparto: A arma la obra con contactos suyos y se la comparte a B tildando
-- solo PS; B suma PB, suyo. A le transfiere la obra a B: PS se va, PA y EA no
-- se van. B le devuelve la obra compartida a A sin tildar nada.
--
-- Afirma:
--   A el receptor ve en la obra sus propios contactos, persona y empresa, por
--     la función de la ficha y por la tabla
--   B no ensancha: lo de B (PB) y lo que dejó de ser de A (PS) siguen afuera
--   C solo lectura: A no edita ni quita el vínculo de su contacto
--   D dura lo que dura el compartir: revocado, A no ve nada
--
-- Último resultado: 4/4 (2026-09-18, revalidado tras sql/099).

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- dueño original
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- recibe la obra
  v_o uuid; v_pa uuid; v_ps uuid; v_pb uuid; v_ea uuid; v_vpa uuid; v_vea uuid;
  v_n int; v_s text; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ── Permisos ─────────────────────────────────────────────────────────────
  -- Ninguno con `_todas` ni `obras_transferir` global: abrirían vías laterales
  -- y los casos pasarían sin ejercitar nada.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_compartido',
    'obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_transferir_propias')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_vincular','obras_compartido','obras_empresas',
    'obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- ── A arma su obra y se la comparte a B tildando solo PS ─────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Qzmv Tkrd 097', 'edificio', v_a) RETURNING id INTO v_o;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Jwlf Bnxc SA 097', v_a) RETURNING id INTO v_ea;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Pvqz', 'Hdlm', '1145690971', v_a) RETURNING id INTO v_pa;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Skrw', 'Fjtn', '1145690972', v_a) RETURNING id INTO v_ps;

  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_ea, ARRAY['constructora']::rol_empresa[]) RETURNING id INTO v_vea;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_pa, ARRAY['arquitecto']::rol_persona[]) RETURNING id INTO v_vpa;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_ps, ARRAY['compras']::rol_persona[]);

  PERFORM obras_compartir_obra(v_o, v_b, '{}', ARRAY[v_ps]);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Bgxn', 'Wqlr', '1145690973', v_b) RETURNING id INTO v_pb;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_pb, ARRAY['decisor']::rol_persona[]);

  -- ── A transfiere a B: PS se va; PA y EA no se van ────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  PERFORM obras_transferir(v_o, v_b, ARRAY[v_ps], '{}');

  -- ── Y B le devuelve la obra compartida, sin tildar nada ──────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_compartir_obra(v_o, v_a, '{}', '{}');

  -- ── A · el receptor ve sus propios contactos ─────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  SELECT count(*) INTO v_n FROM obras_vinculos_de_obra(v_o)
  WHERE entidad_id IN (v_pa, v_ea);
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'A FALLA: la ficha de la obra no le muestra a A sus contactos (% de 2)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona WHERE id = v_vpa;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A FALLA: A no lee por RLS el vínculo de su persona';
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_empresa WHERE id = v_vea;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A FALLA: A no lee por RLS el vínculo de su empresa';
  END IF;
  r := r || E'\nA OK  el receptor ve en la obra sus propios contactos, persona y empresa';

  -- ── B · no ensancha ──────────────────────────────────────────────────────
  SELECT string_agg(nombre, ', ') INTO v_s FROM obras_vinculos_de_obra(v_o)
  WHERE entidad_id IN (v_ps, v_pb);
  IF v_s IS NOT NULL THEN
    RAISE EXCEPTION 'B FALLA: A ve en la función contactos que no son suyos: %', v_s;
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona
  WHERE obra_id = v_o AND persona_id IN (v_ps, v_pb);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'B FALLA: A lee por RLS % vínculos de contactos que no son suyos', v_n;
  END IF;
  r := r || E'\nB OK  lo de B y lo que dejo de ser de A siguen afuera';

  -- ── C · solo lectura ─────────────────────────────────────────────────────
  UPDATE obras_obra_persona SET roles = ARRAY['otro']::rol_persona[] WHERE id = v_vpa;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'C FALLA: A editó el vínculo de su contacto en la obra de B';
  END IF;
  UPDATE obras_obra_empresa SET activo = false WHERE id = v_vea;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'C FALLA: A quitó su empresa de la obra de B';
  END IF;
  r := r || E'\nC OK  ver su contacto en la obra no es editar ni quitar el vinculo';

  -- ── D · dura lo que dura el compartir ────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_revocar_obra(v_o, v_a);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  BEGIN
    PERFORM * FROM obras_vinculos_de_obra(v_o);
    RAISE EXCEPTION 'D FALLA: revocado, A sigue abriendo la obra';
  EXCEPTION WHEN SQLSTATE 'OB022' THEN NULL;
  END;
  SELECT count(*) INTO v_n FROM obras_obra_persona WHERE id = v_vpa;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'D FALLA: revocado, A sigue leyendo el vínculo de su persona';
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_empresa WHERE id = v_vea;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'D FALLA: revocado, A sigue leyendo el vínculo de su empresa';
  END IF;
  r := r || E'\nD OK  revocada la obra, el dueno del contacto deja de verlo en ella';

  RAISE EXCEPTION E'obras_097 — 4/4\n%', r;
END;
$test$;
