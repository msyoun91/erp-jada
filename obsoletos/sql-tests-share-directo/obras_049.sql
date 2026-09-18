-- Verificación de sql/049: el checklist de compartir es "estado deseado".
-- Re-compartir con un usuario que ya lo tiene ajusta la cascada sin revocar
-- la obra/empresa entera. Grant directo (origen NULL) no se toca.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_047.sql.
--
-- Afirma:
--   A reparto inicial: empresa + persona tildadas → sus grants con origen_obra_id
--   B editar: destildar la persona la revoca; obra y empresa quedan intactas
--   C editar: re-tildar la persona la reactiva
--   D grant directo de la empresa (origen NULL) sobrevive al destildado del padre
--
-- Último resultado: 4/4.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_e uuid; v_p uuid; v_n int; r text := '';
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
  SELECT v_tester, id FROM submodulos WHERE codigo = 'obras_ver'
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Zxqw del test 049', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Mnbv Empresa 049', v_admin) RETURNING id INTO v_e;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Pzxq', 'Mnbv', '1140000049', v_admin) RETURNING id INTO v_p;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_e, ARRAY['constructora']::rol_empresa[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p, ARRAY['compras']::rol_persona[]);

  -- A
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_e], ARRAY[v_p]);
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_e AND usuario_id = v_tester AND activo AND origen_obra_id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: empresa sin grant de cascada'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_compartida
   WHERE persona_id = v_p AND usuario_id = v_tester AND activo AND origen_obra_id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: persona sin grant de cascada'; END IF;
  r := r || E'\nA OK  reparto inicial: empresa + persona';

  -- B
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_e], ARRAY[]::uuid[]);
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra AND usuario_id = v_tester AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'B FALLA: se revocó la obra'; END IF;
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_e AND usuario_id = v_tester AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'B FALLA: cayó la empresa que seguía tildada'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_compartida
   WHERE persona_id = v_p AND usuario_id = v_tester AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'B FALLA: la persona destildada sigue activa'; END IF;
  r := r || E'\nB OK  destildar la persona la revoca; obra + empresa intactas';

  -- C
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_e], ARRAY[v_p]);
  SELECT count(*) INTO v_n FROM obras_persona_compartida
   WHERE persona_id = v_p AND usuario_id = v_tester AND activo AND origen_obra_id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: re-tildar no reactivó la persona'; END IF;
  r := r || E'\nC OK  re-tildar la persona la reactiva';

  -- D
  PERFORM obras_compartir_empresa(v_e, v_tester, ARRAY[]::uuid[]);          -- directo, origen NULL
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[v_p]); -- destilda la empresa
  SELECT count(*) INTO v_n FROM obras_empresa_compartida
   WHERE empresa_id = v_e AND usuario_id = v_tester AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: el grant directo cayó con el destildado del padre'; END IF;
  r := r || E'\nD OK  grant directo (origen NULL) sobrevive';

  RAISE EXCEPTION E'--- obras_049: 4/4 ---%', r;
END;
$test$;
