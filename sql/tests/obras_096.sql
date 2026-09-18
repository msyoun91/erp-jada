-- Verificación de sql/096: sacar es de lo que se fue, y persona↔empresa no
-- cambia de punta.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_095.sql.
--
-- Reparto: A dueño de todo y saliente; B destino; D admin con los permisos
-- globales de transferir (el que podía llamar por PostgREST con cualquier id).
--
-- Afirma:
--   A transferir una obra pasando en p_sacar a alguien que no está en ella →
--     OB032, y no se movió nada: ni la obra ni sus vínculos en otra obra
--   B lo mismo al transferir una empresa, con alguien que no pertenece a ella
--   C el estado 3 legítimo de una obra sigue andando: migra y sale de las
--     otras obras del saliente, pero no de la que se transfiere
--   D el estado 3 legítimo de una empresa sigue andando
--   E persona↔empresa: cambiar empresa_id → 42501; activo y cargo, sí
--
-- Último resultado: 5/5 (2026-09-18, revalidado tras sql/099).

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- dueño, saliente
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- destino
  v_d uuid := gen_random_uuid();                       -- admin global
  v_o uuid; v_y uuid; v_e uuid; v_e2 uuid;
  v_p uuid; v_x uuid; v_z uuid; v_m uuid;
  v_py uuid; v_xy uuid; v_zy uuid; v_my uuid; v_po uuid; v_pe uuid;
  v_n int; v_duenio uuid; v_activo boolean; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          created_at, updated_at)
  VALUES (v_d, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'admin-096@example.invalid', '', now(), now());

  -- ── Permisos ─────────────────────────────────────────────────────────────
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b, v_d)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular',
    'obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas',
    'obras_transferir_propias','obras_empresas_transferir_propias')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN ('obras_ver')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_d, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_transferir','obras_empresas_todas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- ── La agenda de A ───────────────────────────────────────────────────────
  -- O se transfiere; Y es la otra obra de A, donde el estado 3 saca. X y Z no
  -- están en O ni en E: son los ids que el admin cuela en p_sacar.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Qmvz Trkl 096', 'edificio', v_a) RETURNING id INTO v_o;
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Wbnd Hpfx 096', 'casa', v_a) RETURNING id INTO v_y;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Jxrq Lmvt SA 096', v_a) RETURNING id INTO v_e;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Nczp Gwdh SA 096', v_a) RETURNING id INTO v_e2;

  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Fvlk', 'Dmrq', v_a) RETURNING id INTO v_p;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Hztw', 'Kpsn', v_a) RETURNING id INTO v_x;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Rqdm', 'Vylt', v_a) RETURNING id INTO v_z;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Ckbx', 'Wnfj', v_a) RETURNING id INTO v_m;

  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_p, ARRAY['arquitecto']::rol_persona[]) RETURNING id INTO v_po;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_y, v_p, ARRAY['arquitecto']::rol_persona[]) RETURNING id INTO v_py;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_y, v_x, ARRAY['compras']::rol_persona[]) RETURNING id INTO v_xy;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_y, v_z, ARRAY['compras']::rol_persona[]) RETURNING id INTO v_zy;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_y, v_m, ARRAY['decisor']::rol_persona[]) RETURNING id INTO v_my;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_e, ARRAY['constructora']::rol_empresa[]);
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_m, v_e, 'compras');
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_x, v_e2, 'jefe de obra') RETURNING id INTO v_pe;

  -- ── A · obra: sacar a quien no está en ella ──────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_d)::text, true);
  BEGIN
    PERFORM obras_transferir(v_o, v_b, ARRAY[v_x], ARRAY[v_x]);
    RAISE EXCEPTION 'A FALLA: transfirió sacando a alguien que no estaba en la obra';
  EXCEPTION WHEN SQLSTATE 'OB032' THEN NULL;
  END;

  PERFORM set_config('role', 'none', true);
  SELECT responsable_id INTO v_duenio FROM obras WHERE id = v_o;
  SELECT activo INTO v_activo FROM obras_obra_persona WHERE id = v_xy;
  PERFORM set_config('role', 'authenticated', true);
  IF v_duenio <> v_a THEN
    RAISE EXCEPTION 'A FALLA: el OB032 no revirtió la transferencia de la obra';
  END IF;
  IF NOT v_activo THEN
    RAISE EXCEPTION 'A FALLA: se desactivó el vínculo de X en otra obra del saliente';
  END IF;
  r := r || E'\nA OK  obra: sacar lo que no se va es OB032, y no se mueve nada';

  -- ── B · empresa: sacar a quien no pertenece a ella ───────────────────────
  BEGIN
    PERFORM obras_transferir_empresa(v_e, v_b, ARRAY[v_z], ARRAY[v_z], false);
    RAISE EXCEPTION 'B FALLA: transfirió sacando a alguien que no pertenecía a la empresa';
  EXCEPTION WHEN SQLSTATE 'OB032' THEN NULL;
  END;

  PERFORM set_config('role', 'none', true);
  SELECT creado_por INTO v_duenio FROM obras_empresas WHERE id = v_e;
  SELECT activo INTO v_activo FROM obras_obra_persona WHERE id = v_zy;
  PERFORM set_config('role', 'authenticated', true);
  IF v_duenio <> v_a THEN
    RAISE EXCEPTION 'B FALLA: el OB032 no revirtió la transferencia de la empresa';
  END IF;
  IF NOT v_activo THEN
    RAISE EXCEPTION 'B FALLA: se desactivó el vínculo de Z en una obra del saliente';
  END IF;
  r := r || E'\nB OK  empresa: sacar lo que no se va es OB032, y no se mueve nada';

  -- ── C · el estado 3 legítimo de una obra ─────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  PERFORM obras_transferir(v_o, v_b, ARRAY[v_p], ARRAY[v_p]);

  PERFORM set_config('role', 'none', true);
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_p;
  IF v_duenio <> v_b THEN RAISE EXCEPTION 'C FALLA: P no migró'; END IF;
  SELECT activo INTO v_activo FROM obras_obra_persona WHERE id = v_py;
  IF v_activo THEN RAISE EXCEPTION 'C FALLA: P sigue en la otra obra del saliente'; END IF;
  SELECT activo INTO v_activo FROM obras_obra_persona WHERE id = v_po;
  IF NOT v_activo THEN RAISE EXCEPTION 'C FALLA: P salió de la obra que se transfería'; END IF;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\nC OK  obra: el estado 3 legitimo migra y saca de lo del saliente';

  -- ── D · el estado 3 legítimo de una empresa ──────────────────────────────
  PERFORM obras_transferir_empresa(v_e, v_b, ARRAY[v_m], ARRAY[v_m], false);

  PERFORM set_config('role', 'none', true);
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_m;
  IF v_duenio <> v_b THEN RAISE EXCEPTION 'D FALLA: M no migró con la empresa'; END IF;
  SELECT activo INTO v_activo FROM obras_obra_persona WHERE id = v_my;
  IF v_activo THEN RAISE EXCEPTION 'D FALLA: M sigue en la obra del saliente'; END IF;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\nD OK  empresa: el estado 3 legitimo migra y saca de lo del saliente';

  -- ── E · persona↔empresa no cambia de punta ───────────────────────────────
  BEGIN
    UPDATE obras_persona_empresa SET empresa_id = v_e WHERE id = v_pe;
    RAISE EXCEPTION 'E FALLA: se pudo mover empresa_id por UPDATE';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  UPDATE obras_persona_empresa SET cargo = 'director 096', activo = false WHERE id = v_pe;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'E FALLA: el recorte rompió editar la pertenencia (%)', v_n;
  END IF;
  r := r || E'\nE OK  empresa_id no se mueve por UPDATE; activo y cargo, si';

  RAISE EXCEPTION E'obras_096 — 5/5\n%', r;
END;
$test$;
