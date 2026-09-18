-- Verificación de sql/087: transferir con tres estados por contacto.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_085.sql.
--
-- Afirma:
--   A el checklist ofrece la persona que llega SOLO por una empresa de la obra
--   A2 la entidad que se transfiere trae su propia fila ('si_mismo')
--   B `vinculos` marca `mio` según el dueño saliente, no según auth.uid()
--   C estado 1 (no migra) → sigue siendo del saliente, contextual al receptor
--   D estado 2 (migra, contextual) → cambia de dueño y el saliente conserva
--     grant anclado a su otra obra Y a su empresa
--   E estado 3 (migra, sacar) → cambia de dueño, los vínculos del saliente se
--     desactivan (obras Y empresas) y no queda grant recíproco
--   F el vínculo que migra con la obra NO se desactiva aunque esté en p_sacar
--   G sacar algo que no migra → OB032
--   H el receptor no queda con grant contextual sobre lo que ahora es propio
--     (la rama de persona que sql/086 perdió)
--   I transferir_persona ya no deja fantasmas: con p_sacar=false el saliente
--     conserva el grant; con true se va el vínculo
--   J transferir_empresa arrastra a su gente tildada y suelta la propia
--
-- El caso A es el que motivó la migración: `obras_contactos_exclusivos_de_obra`
-- ignoraba `obras_persona_empresa` a propósito y esa persona no se ofrecía.
--
-- Último resultado: 11/11 (2026-09-18, revalidado tras sql/099).

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_obra2 uuid; v_ajena uuid;
  v_emp uuid; v_p_via uuid; v_p_ctx uuid; v_p_sacar uuid; v_p_sola uuid;
  v_n int; v_duenio uuid; v_mio bool; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas','obras_compartido',
    'obras_transferir','obras_personas_todas','obras_empresas_todas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_personas','obras_empresas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- Nombres sin tokens en común: el detector difuso congela lo parecido y las
  -- entidades `pendiente` cambian el resultado de otras funciones.
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Wprz Klnt 087', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Bxqm Jdvh 087', 'casa', v_admin) RETURNING id INTO v_obra2;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Nmkd Vxpl SA', v_admin) RETURNING id INTO v_emp;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_emp, ARRAY['constructora']::rol_empresa[]);
  -- La empresa también está en la otra obra del saliente: eso le da ancla al
  -- grant recíproco cuando la empresa migre (caso J).
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra2, v_emp, ARRAY['constructora']::rol_empresa[]);

  -- Persona que llega SOLO por la empresa: sin fila en obras_obra_persona.
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Qvlt', 'Zmrbk', v_admin) RETURNING id INTO v_p_via;
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p_via, v_emp, 'jefe de obra');

  -- Persona en la obra que se transfiere + otra obra mía + mi empresa.
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Hdsw', 'Prgnx', v_admin) RETURNING id INTO v_p_ctx;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p_ctx, ARRAY['arquitecto']::rol_persona[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra2, v_p_ctx, ARRAY['arquitecto']::rol_persona[]);
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p_ctx, v_emp, 'proyectista');

  -- Igual que la anterior, pero se va a sacar. Y además está en la obra AJENA:
  -- ese vínculo no se toca (decisión del usuario).
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Ycbm', 'Lkfqt', v_admin) RETURNING id INTO v_p_sacar;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p_sacar, ARRAY['arquitecto']::rol_persona[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra2, v_p_sacar, ARRAY['arquitecto']::rol_persona[]);
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p_sacar, v_emp, 'calculista');

  -- La obra ajena la crea su dueño y la comparte con el admin: recién ahí el
  -- admin puede colgarle su contacto (sql/051). Ese vínculo es el que no se
  -- toca ni en el estado 3.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Gftn Rzwc 087', 'casa', v_tester) RETURNING id INTO v_ajena;
  PERFORM obras_compartir_obra(v_ajena, v_admin, ARRAY[]::uuid[], ARRAY[]::uuid[]);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_ajena, v_p_sacar, ARRAY['arquitecto']::rol_persona[]);

  -- Persona que se queda (estado 1).
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Tjvn', 'Wshdz', v_admin) RETURNING id INTO v_p_sola;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p_sola, ARRAY['compras']::rol_persona[]);

  -- A — el caso que motivó la migración
  SELECT count(*) INTO v_n FROM obras_transferir_candidatos('obra', v_obra)
   WHERE id = v_p_via AND origen = 'via_empresa' AND via_empresa_id = v_emp;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A FALLA: la persona que llega por la empresa no se ofrece (%)', v_n;
  END IF;
  -- Y la que está en las dos puntas sale una sola vez, como 'directo'.
  SELECT count(*) INTO v_n FROM obras_transferir_candidatos('obra', v_obra)
   WHERE id = v_p_ctx;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: candidato duplicado (%)', v_n; END IF;
  r := r || E'\nA OK  la persona vía empresa entra al checklist, sin duplicar';

  -- A2 — sin la fila propia, `p_sacar_empresa` no se podría elegir del panel
  SELECT count(*) INTO v_n FROM obras_transferir_candidatos('empresa', v_emp)
   WHERE id = v_emp AND tipo = 'empresa' AND origen = 'si_mismo';
  IF v_n <> 1 THEN RAISE EXCEPTION 'A2 FALLA: la empresa no trae fila propia (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM obras_transferir_candidatos('persona', v_p_ctx)
   WHERE id = v_p_ctx AND origen = 'si_mismo';
  IF v_n <> 1 THEN RAISE EXCEPTION 'A2 FALLA: la persona no trae fila propia (%)', v_n; END IF;
  r := r || E'\nA2 OK la entidad transferida trae su fila (sacar_empresa elegible)';

  -- B
  SELECT bool_and((x->>'mio')::bool) INTO v_mio
  FROM obras_transferir_candidatos('obra', v_obra) c,
       jsonb_array_elements(c.vinculos) x
  WHERE c.id = v_p_ctx;
  IF v_mio IS NOT TRUE THEN
    RAISE EXCEPTION 'B FALLA: vínculos del saliente marcados como ajenos';
  END IF;
  SELECT bool_or(NOT (x->>'mio')::bool) INTO v_mio
  FROM obras_transferir_candidatos('obra', v_obra) c,
       jsonb_array_elements(c.vinculos) x
  WHERE c.id = v_p_sacar;
  IF v_mio IS NOT TRUE THEN
    RAISE EXCEPTION 'B FALLA: la obra ajena no se marcó como no-mía';
  END IF;
  r := r || E'\nB OK  `mio` distingue lo del saliente de lo de terceros';

  -- Transferencia: migran v_p_ctx (estado 2), v_p_sacar (estado 3) y v_p_via
  -- (estado 2, llega por la empresa). v_p_sola se queda. La empresa no migra.
  PERFORM obras_transferir(
    v_obra, v_tester,
    ARRAY[v_p_ctx, v_p_sacar, v_p_via],
    ARRAY[v_p_sacar]
  );

  -- C — estado 1
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_p_sola;
  IF v_duenio <> v_admin THEN RAISE EXCEPTION 'C FALLA: se movió lo que no migraba'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p_sola AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: el receptor no la ve contextual (%)', v_n; END IF;
  r := r || E'\nC OK  lo que no migra queda del saliente, contextual al receptor';

  -- D — estado 2
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_p_ctx;
  IF v_duenio <> v_tester THEN RAISE EXCEPTION 'D FALLA: no cambió de dueño'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p_ctx AND usuario_id = v_admin AND obra_id = v_obra2 AND activo
     AND otorgada_por = v_tester;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: sin grant recíproco en la otra obra (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p_ctx AND usuario_id = v_admin AND empresa_id = v_emp AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: sin grant recíproco en la empresa (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE persona_id = v_p_ctx AND obra_id = v_obra2 AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: se desactivó un vínculo que quedaba'; END IF;
  r := r || E'\nD OK  estado 2: cambia de dueño y el saliente lo sigue viendo';

  -- E — estado 3
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_p_sacar;
  IF v_duenio <> v_tester THEN RAISE EXCEPTION 'E FALLA: no cambió de dueño'; END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE persona_id = v_p_sacar AND obra_id = v_obra2 AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'E FALLA: sigue vinculada a la obra del saliente'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_empresa
   WHERE persona_id = v_p_sacar AND empresa_id = v_emp AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'E FALLA: sigue en la empresa del saliente'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p_sacar AND usuario_id = v_admin AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'E FALLA: quedó grant recíproco de algo que se sacó (%)', v_n; END IF;
  -- La obra ajena no se toca: queda a decisión del nuevo dueño.
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE persona_id = v_p_sacar AND obra_id = v_ajena AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'E FALLA: se desvinculó de la obra de un tercero'; END IF;
  r := r || E'\nE OK  estado 3: sale de lo del saliente, la obra ajena intacta';

  -- F
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE persona_id = v_p_sacar AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'F FALLA: se cortó el vínculo con la obra transferida'; END IF;
  r := r || E'\nF OK  el vínculo con la obra que se transfiere sobrevive';

  -- H — la rama que sql/086 perdió
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id IN (v_p_ctx, v_p_sacar, v_p_via) AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'H FALLA: el receptor quedó con grant sobre lo propio (%)', v_n;
  END IF;
  r := r || E'\nH OK  el receptor no recibe grant sobre lo que ahora es suyo';

  -- G
  BEGIN
    PERFORM obras_transferir(v_obra2, v_tester, ARRAY[]::uuid[], ARRAY[v_p_ctx]);
    RAISE EXCEPTION 'G FALLA: aceptó sacar algo que no migra';
  EXCEPTION WHEN sqlstate 'OB032' THEN NULL;
  END;
  r := r || E'\nG OK  sacar sin migrar → OB032';

  -- I — transferir_persona sin fantasma. v_p_sola está en v_obra (ya del
  -- tester) y en ninguna obra del admin, así que el ancla es la empresa.
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p_sola, v_emp, 'topógrafo');
  PERFORM obras_transferir_persona(v_p_sola, v_tester, false);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p_sola AND usuario_id = v_admin AND empresa_id = v_emp AND activo;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'I FALLA: transferir la persona dejó el vínculo sin grant (%)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM obras_persona_empresa
   WHERE persona_id = v_p_sola AND empresa_id = v_emp AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'I FALLA: se cortó el vínculo sin pedirlo'; END IF;
  r := r || E'\nI OK  transferir persona: el saliente conserva lo que veía';

  -- J — la empresa migra y arrastra a v_p_via, que sigue siendo del admin
  -- porque ya se la llevó la obra... se usa una persona nueva del admin.
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Fmzx', 'Qtblr', v_admin) RETURNING id INTO v_p_sola;
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p_sola, v_emp, 'administrativo');
  PERFORM obras_transferir_empresa(v_emp, v_tester, ARRAY[v_p_sola], ARRAY[]::uuid[], false);
  SELECT creado_por INTO v_duenio FROM obras_empresas WHERE id = v_emp;
  IF v_duenio <> v_tester THEN RAISE EXCEPTION 'J FALLA: la empresa no cambió de dueño'; END IF;
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_p_sola;
  IF v_duenio <> v_tester THEN RAISE EXCEPTION 'J FALLA: la persona tildada no migró'; END IF;
  -- El saliente todavía tiene v_obra2 con la empresa: ahí está su ancla.
  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
   WHERE empresa_id = v_emp AND usuario_id = v_admin AND obra_id = v_obra2 AND activo;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'J FALLA: el saliente perdió la empresa de su propia obra (%)', v_n;
  END IF;
  r := r || E'\nJ OK  transferir empresa: arrastra lo tildado, deja ancla al saliente';

  RAISE EXCEPTION E'obras_087 — 11/11\n%', r;
END;
$test$;
