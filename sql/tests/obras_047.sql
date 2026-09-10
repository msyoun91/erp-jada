-- Verificación de sql/047: compartir obra con checklist, cascada de revocación
-- por origen, "última escritura gana", y la vista Compartido.
--
-- NO es una migración: corre entero dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción se revierte. Mismo andamiaje que
-- obras_model_a.sql.
--
-- Afirma:
--   1 compartir_obra: el receptor ve la obra
--   2 checklist tildado → el receptor ve la empresa; su grant lleva origen_obra_id
--   3 checklist NO tildado → el receptor NO ve la persona
--   4 ver ≠ editar: el receptor no puede UPDATE la obra compartida
--   5 revocar_obra → cascada: la empresa tildada deja de verse
--   6 última escritura gana: compartir la empresa directo después limpia el
--     origen, y entonces revocar la obra ya no la arrastra
--   7 compartir_empresa con checklist de personas + cascada al revocar
--   8 guard: quien no es responsable no puede compartir la obra (OB026)
--   9 obras_compartidos_por_mi() lista lo que compartí
--  10 obras_relaciones_compartibles_obra() devuelve el checklist (empresa+persona)
--  11 obras_relaciones_compartibles_empresa() devuelve el checklist (persona)
--
-- Último resultado: 11/11.

DO $test$
DECLARE
  v_admin   uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester  uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra    uuid;
  v_empresa uuid;
  v_persona uuid;
  v_n       int;
  v_txt     text;
  r         text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- permisos ----------
  -- ON CONFLICT y no INSERT pelado: los usuarios reales ya tienen filas de
  -- usuario_submodulos (desactivadas arriba), y hay UNIQUE (usuario, submodulo).
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_vincular','obras_empresas',
                   'obras_empresas_crear','obras_personas','obras_personas_crear',
                   'obras_personas_empresas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo = 'obras_ver'
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- ========== admin arma obra + empresa + persona vinculadas ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Wzxqpt del test 047', 'edificio', v_admin) RETURNING id INTO v_obra;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Kqwzxpmnbvlk Empresa 047', v_admin) RETURNING id INTO v_empresa;

  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Pzxqwt', 'Mnbvlk', '1140000047', v_admin) RETURNING id INTO v_persona;

  IF (SELECT pendiente FROM obras_empresas WHERE id = v_empresa)
     OR (SELECT pendiente FROM obras_personas WHERE id = v_persona) THEN
    RAISE EXCEPTION 'setup: una entidad de control entró pendiente';
  END IF;

  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_empresa, ARRAY['constructora']::rol_empresa[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_persona, ARRAY['compras']::rol_persona[]);

  -- vínculo persona↔empresa para el checklist del punto 7
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_persona, v_empresa, 'Compras');

  -- ========== 1-3 · compartir obra: empresa tildada, persona no ==========
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_empresa], ARRAY[]::uuid[]);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  SELECT count(*) INTO v_n FROM obras WHERE id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION '1 FALLA: el receptor no ve la obra compartida'; END IF;
  r := r || E'\n1 OK  compartir_obra → el receptor ve la obra';

  SELECT count(*) INTO v_n FROM obras_empresas WHERE id = v_empresa;
  IF v_n <> 1 THEN RAISE EXCEPTION '2 FALLA: la empresa tildada no se ve'; END IF;
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
  WHERE empresa_id = v_empresa AND usuario_id = v_tester AND activo
    AND origen_obra_id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION '2 FALLA: el grant de empresa no lleva origen_obra_id'; END IF;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\n2 OK  empresa tildada → grant con origen_obra_id';

  SELECT count(*) INTO v_n FROM obras_personas WHERE id = v_persona;
  IF v_n <> 0 THEN RAISE EXCEPTION '3 FALLA: la persona NO tildada se ve igual'; END IF;
  r := r || E'\n3 OK  persona no tildada → el receptor no la ve';

  -- ========== 4 · ver ≠ editar ==========
  UPDATE obras SET nombre = 'hackeado' WHERE id = v_obra;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN RAISE EXCEPTION '4 FALLA: el receptor pudo editar la obra compartida'; END IF;
  r := r || E'\n4 OK  el receptor no puede editar la obra compartida';

  -- ========== 5 · revocar_obra → cascada ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_revocar_obra(v_obra, v_tester);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras WHERE id = v_obra;
  IF v_n <> 0 THEN RAISE EXCEPTION '5 FALLA: tras revocar, el receptor sigue viendo la obra'; END IF;
  SELECT count(*) INTO v_n FROM obras_empresas WHERE id = v_empresa;
  IF v_n <> 0 THEN RAISE EXCEPTION '5 FALLA: la empresa tildada no cayó con la obra'; END IF;
  r := r || E'\n5 OK  revocar_obra → la empresa tildada también se revoca';

  -- ========== 6 · última escritura gana ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_empresa], ARRAY[]::uuid[]); -- origen = obra
  PERFORM obras_compartir_empresa(v_empresa, v_tester, ARRAY[]::uuid[]);             -- directo → origen NULL
  PERFORM obras_revocar_obra(v_obra, v_tester);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_empresas WHERE id = v_empresa;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '6 FALLA: el grant directo de empresa cayó con la obra (origen no se limpió)';
  END IF;
  r := r || E'\n6 OK  compartir directo limpia el origen → sobrevive al revocar del padre';

  -- limpieza para el 7
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_revocar_empresa(v_empresa, v_tester);

  -- ========== 7 · compartir_empresa con checklist de personas ==========
  PERFORM obras_compartir_empresa(v_empresa, v_tester, ARRAY[v_persona]);

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_persona_compartida
  WHERE persona_id = v_persona AND usuario_id = v_tester AND activo
    AND origen_empresa_id = v_empresa;
  IF v_n <> 1 THEN RAISE EXCEPTION '7 FALLA: la persona tildada no recibió grant con origen_empresa_id'; END IF;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_revocar_empresa(v_empresa, v_tester);

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_persona_compartida
  WHERE persona_id = v_persona AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION '7 FALLA: revocar_empresa no arrastró la persona tildada'; END IF;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\n7 OK  compartir_empresa + checklist de personas + cascada al revocar';

  -- ========== 8 · guard OB026 ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  BEGIN
    PERFORM obras_compartir_obra(v_obra, v_admin, ARRAY[]::uuid[], ARRAY[]::uuid[]);
    RAISE EXCEPTION '8 FALLA: un no-responsable pudo compartir la obra';
  EXCEPTION
    WHEN sqlstate 'OB026' THEN
      r := r || E'\n8 OK  no-responsable → OB026';
  END;

  -- ========== 9 · vista Compartido ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE tipo = 'obra' AND entidad_id = v_obra AND usuario_id = v_tester;
  IF v_n <> 1 THEN RAISE EXCEPTION '9 FALLA: obras_compartidos_por_mi no lista la obra compartida'; END IF;
  r := r || E'\n9 OK  obras_compartidos_por_mi lista lo compartido';

  -- ========== 10-11 · checklists del panel (regresión 48: `id` ambiguo) ==========
  SELECT count(*) INTO v_n FROM obras_relaciones_compartibles_obra(v_obra, v_tester);
  IF v_n <> 2 THEN RAISE EXCEPTION '10 FALLA: el checklist de obra no trae empresa+persona (v_n=%)', v_n; END IF;
  r := r || E'\n10 OK obras_relaciones_compartibles_obra devuelve el checklist';

  SELECT count(*) INTO v_n FROM obras_relaciones_compartibles_empresa(v_empresa, v_tester);
  IF v_n <> 1 THEN RAISE EXCEPTION '11 FALLA: el checklist de empresa no trae la persona (v_n=%)', v_n; END IF;
  r := r || E'\n11 OK obras_relaciones_compartibles_empresa devuelve el checklist';

  RAISE EXCEPTION E'--- obras_047: 11/11 ---%', r;
END;
$test$;
