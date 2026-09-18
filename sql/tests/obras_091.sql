-- Verificación de sql/091: el receptor sin Obras, el array NULL y el gate.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_090.sql.
--
-- Reparto: A es el dueño y quien comparte; B el receptor legítimo (tiene
-- `obras_ver`); C un usuario activo SIN ningún submódulo de Obras — es el que
-- hace visibles los dos gates.
--
-- Afirma:
--   A compartir una obra con un usuario sin `obras_ver` → OB006, en vez de un
--     grant que no abre nada
--   B compartir con los arrays en `null` destilda lo tildado, en vez de dejar
--     el reparto congelado (`NOT (x = ANY(NULL))` es NULL, no true)
--   C transferir con `p_migran: null` deja al receptor los contextuales de lo
--     que no migra, en vez de la obra pelada
--   D transferir con `p_migran: null` y `p_sacar` no vacío → OB032: la
--     validación vuelve a correr en vez de pasar en silencio
--   E `obras_migrar_agenda` sigue cortando con OB006 después de cambiar el
--     EXISTS copiado por `usuario_tiene_permiso` — la cuarta copia
--
-- Último resultado: 5/5 (2026-09-18, revalidado tras sql/093).

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- dueño
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- receptor con obras_ver
  v_c uuid := gen_random_uuid();                       -- usuario sin Obras
  v_obra uuid; v_obra2 uuid;
  v_p uuid; v_p2 uuid;
  v_n int; v_activo boolean; r text := '';
  v_rol text := current_setting('role', true);
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          created_at, updated_at)
  VALUES (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'sin-obras-091@example.invalid', '', now(), now());

  -- ── Permisos ─────────────────────────────────────────────────────────────
  -- C no recibe ninguno: es el punto del test. A y B arrancan limpios para que
  -- ningún `_todas` heredado abra una vía lateral.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b, v_c)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_compartido',
    'obras_empresas','obras_personas','obras_personas_crear',
    'obras_transferir_propias','obras_migrar')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_personas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);

  -- ── Datos de A ───────────────────────────────────────────────────────────
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Krtl Vbmn 091', 'edificio', v_a) RETURNING id INTO v_obra;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Sdrm', 'Qlfvz', '1144332211', v_a) RETURNING id INTO v_p;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p, ARRAY['compras']::rol_persona[]);

  -- ── A · compartir con quien no tiene acceso al módulo ────────────────────
  BEGIN
    PERFORM obras_compartir_obra(v_obra, v_c, ARRAY[]::uuid[], ARRAY[v_p]);
    RAISE EXCEPTION 'A FALLA: compartió con un usuario sin obras_ver';
  EXCEPTION WHEN SQLSTATE 'OB006' THEN NULL;
  END;

  -- Y no dejó nada escrito antes de cortar.
  SELECT count(*) INTO v_n FROM obras_obra_compartida
  WHERE obra_id = v_obra AND usuario_id = v_c;
  IF v_n <> 0 THEN RAISE EXCEPTION 'A FALLA: quedó fila de compartido (%)', v_n; END IF;
  r := r || E'\nA OK  compartir con un usuario sin obras_ver → OB006';

  -- ── B · los arrays en null no congelan el reparto ────────────────────────
  PERFORM obras_compartir_obra(v_obra, v_b, ARRAY[]::uuid[], ARRAY[v_p]);

  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_b AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'B FALLA: el checklist no otorgó (%)', v_n; END IF;

  -- Estado deseado vacío, escrito como `null`: tiene que destildar.
  PERFORM obras_compartir_obra(v_obra, v_b, NULL::uuid[], NULL::uuid[]);

  SELECT activo INTO v_activo FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_b AND obra_id = v_obra;
  IF v_activo THEN
    RAISE EXCEPTION 'B FALLA: con null no destildó — el reparto quedó congelado';
  END IF;
  r := r || E'\nB OK  compartir con arrays null destilda lo tildado';

  -- ── C · transferir con p_migran null deja los contextuales ───────────────
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Mzfq Trwd 091', 'casa', v_a) RETURNING id INTO v_obra2;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Nvbk', 'Zthpr', '1166554433', v_a) RETURNING id INTO v_p2;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra2, v_p2, ARRAY['decisor']::rol_persona[]);

  -- ── D · y antes: null en migran con sacar no vacío sigue siendo OB032 ────
  BEGIN
    PERFORM obras_transferir(v_obra2, v_b, NULL::uuid[], ARRAY[v_p2]);
    RAISE EXCEPTION 'D FALLA: aceptó sacar algo que no migra';
  EXCEPTION WHEN SQLSTATE 'OB032' THEN NULL;
  END;
  r := r || E'\nD OK  p_migran null con p_sacar cargado → OB032';

  PERFORM obras_transferir(v_obra2, v_b, NULL::uuid[], NULL::uuid[]);

  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
  WHERE persona_id = v_p2 AND usuario_id = v_b AND obra_id = v_obra2 AND activo;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'C FALLA: el receptor quedó sin el contextual de lo que no migra (%)', v_n;
  END IF;

  -- La persona no se movió: `p_migran` vacío es vacío, no "todo".
  SELECT count(*) INTO v_n FROM obras_personas
  WHERE id = v_p2 AND creado_por = v_a;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: migró una persona que no estaba en p_migran'; END IF;
  r := r || E'\nC OK  transferir con p_migran null deja los contextuales';

  -- ── E · el gate de migrar agenda, ya sin la copia del EXISTS ─────────────
  BEGIN
    PERFORM obras_migrar_agenda(v_b, v_c);
    RAISE EXCEPTION 'E FALLA: migró la agenda a un usuario sin obras_ver';
  EXCEPTION WHEN SQLSTATE 'OB006' THEN NULL;
  END;
  r := r || E'\nE OK  migrar agenda a quien no tiene obras_ver → OB006';

  RAISE EXCEPTION E'obras_091 — 5/5\n%', r;
END;
$test$;
