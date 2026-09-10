-- Verificación de sql/051: el receptor de una obra compartida vincula sus
-- propios contactos; el responsable los ve (con nombre y "lo agregó X"), los
-- puede quitar pero no reescribir; el receptor no ve el interior que no se le
-- compartió; revocar arrastra todo.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_049.sql.
--
-- Afirma:
--   A  el receptor vincula una empresa + personas suyas a la obra compartida
--   B  el trigger set_creado_por pisa el valor que manda el cliente
--   C  el receptor NO puede vincular una empresa ajena (RLS corta el INSERT)
--   D  el responsable ve el vínculo del receptor; obras_vinculos_de_obra le
--      resuelve el nombre y marca es_de_receptor + creado_por
--   E  el receptor NO ve por obras_vinculos_de_obra el interior no compartido;
--      sí lo ve cuando el responsable lo tilda al compartir
--   F  el responsable puede QUITAR (activo=false) el vínculo del receptor, pero
--      NO editarle roles/observaciones (OB028)
--   G  obras_contar_vinculos_receptor cuenta lo que agregó el receptor
--   H  revocar la obra desactiva esos vínculos
--
-- Último resultado: 8/8.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_ae uuid; v_te uuid; v_tp uuid; v_tp2 uuid; v_ve_vinc uuid;
  v_n int; v_creador uuid; v_nombre text; v_esrec boolean; v_bloqueado boolean;
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
   ('obras_ver','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Kqwz del test 051', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Aei Empresa del dueño 051', v_admin) RETURNING id INTO v_ae;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_ae, ARRAY['constructora']::rol_empresa[]);

  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);

  -- Cambio de identidad: ahora soy el receptor.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Tqr Empresa del receptor 051', v_tester) RETURNING id INTO v_te;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Rcv', 'Tqr', '1140000051', v_tester) RETURNING id INTO v_tp;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Wsx', 'Tqr', v_tester) RETURNING id INTO v_tp2;

  -- A
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_te, ARRAY['constructora']::rol_empresa[]) RETURNING id INTO v_ve_vinc;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_tp, ARRAY['compras']::rol_persona[]);
  SELECT count(*) INTO v_n FROM obras_obra_empresa
   WHERE obra_id = v_obra AND empresa_id = v_te AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: el receptor no pudo vincular su empresa'; END IF;
  r := r || E'\nA OK  el receptor vincula empresa + persona suyas';

  -- B
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles, creado_por)
  VALUES (v_obra, v_tp2, ARRAY['compras']::rol_persona[], v_admin);
  SELECT creado_por INTO v_creador FROM obras_obra_persona
   WHERE obra_id = v_obra AND persona_id = v_tp2 AND activo;
  IF v_creador <> v_tester THEN RAISE EXCEPTION 'B FALLA: creado_por no lo pisó el trigger (%)', v_creador; END IF;
  r := r || E'\nB OK  el trigger pisa el creado_por del cliente';

  -- C
  v_bloqueado := false;
  BEGIN
    INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
    VALUES (v_obra, v_ae, ARRAY['desarrolladora']::rol_empresa[]);
  EXCEPTION WHEN insufficient_privilege THEN v_bloqueado := true;
  END;
  IF NOT v_bloqueado THEN RAISE EXCEPTION 'C FALLA: el receptor vinculó una empresa ajena'; END IF;
  r := r || E'\nC OK  RLS corta vincular lo ajeno';

  -- E (parte 1): el interior no compartido no vuelve para el receptor
  SELECT count(*) INTO v_n FROM obras_vinculos_de_obra(v_obra) WHERE entidad_id = v_ae;
  IF v_n <> 0 THEN RAISE EXCEPTION 'E FALLA: el receptor ve el interior no compartido'; END IF;

  -- D: el responsable ve el vínculo del receptor, con nombre resuelto
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT count(*) INTO v_n FROM obras_obra_empresa
   WHERE obra_id = v_obra AND empresa_id = v_te AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: el responsable no ve el vínculo del receptor'; END IF;
  SELECT nombre, es_de_receptor, creado_por
    INTO v_nombre, v_esrec, v_creador
    FROM obras_vinculos_de_obra(v_obra) WHERE entidad_id = v_te;
  IF v_nombre <> 'Tqr Empresa del receptor 051' OR NOT v_esrec OR v_creador <> v_tester THEN
    RAISE EXCEPTION 'D FALLA: obras_vinculos_de_obra no resolvió bien (%, %, %)', v_nombre, v_esrec, v_creador;
  END IF;
  r := r || E'\nD OK  el responsable ve el vínculo del receptor con nombre + "lo agregó"';

  -- E (parte 2): al tildarlo en el checklist, el receptor sí lo ve
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_ae], ARRAY[]::uuid[]);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_vinculos_de_obra(v_obra) WHERE entidad_id = v_ae;
  IF v_n <> 1 THEN RAISE EXCEPTION 'E FALLA: el interior compartido por checklist no aparece'; END IF;
  r := r || E'\nE OK  el interior aparece solo si lo tildan al compartir';

  -- F: el responsable puede quitar el vínculo del receptor, no editarlo
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  v_bloqueado := false;
  BEGIN
    UPDATE obras_obra_empresa SET roles = ARRAY['desarrolladora']::rol_empresa[]
     WHERE id = v_ve_vinc;
  EXCEPTION WHEN SQLSTATE 'OB028' THEN v_bloqueado := true;
  END;
  IF NOT v_bloqueado THEN RAISE EXCEPTION 'F FALLA: el responsable reescribió el vínculo del receptor'; END IF;

  UPDATE obras_obra_empresa SET activo = false WHERE id = v_ve_vinc;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'F FALLA: el responsable no pudo quitar el vínculo del receptor'; END IF;
  UPDATE obras_obra_empresa SET activo = true WHERE id = v_ve_vinc;   -- restaurar para F/G
  r := r || E'\nF OK  el responsable quita pero no edita el vínculo del receptor';

  -- G
  SELECT obras_contar_vinculos_receptor(v_obra, v_tester) INTO v_n;
  IF v_n <> 3 THEN RAISE EXCEPTION 'G FALLA: contar_vinculos_receptor dio % (esperaba 3)', v_n; END IF;
  r := r || E'\nG OK  obras_contar_vinculos_receptor = 3';

  -- H
  PERFORM obras_revocar_obra(v_obra, v_tester);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_obra_empresa
   WHERE obra_id = v_obra AND creado_por = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'H FALLA: quedaron vínculos activos del receptor tras revocar'; END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE obra_id = v_obra AND creado_por = v_tester AND NOT activo;
  IF v_n <> 2 THEN RAISE EXCEPTION 'H FALLA: las personas del receptor no se desactivaron (%)', v_n; END IF;
  r := r || E'\nH OK  revocar la obra arrastra los vínculos del receptor';

  RAISE EXCEPTION E'--- obras_051: 8/8 ---%', r;
END;
$test$;
