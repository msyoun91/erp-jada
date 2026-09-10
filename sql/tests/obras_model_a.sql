-- Verificación de MODEL A (sql/039–044): privacidad por dueño, contacto
-- protegido a nivel columna, grants (completo y contextual), transferencia de
-- personas/empresas, buscador enmascarado.
--
-- NO es una migración: corre entero dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción se revierte. Mismo andamiaje que
-- obras_033.sql: `set_config('role', ...)` + `request.jwt.claims` para ejercer
-- RLS, `'none'` para mirar sin RLS.
--
-- Afirma:
--   · el contacto (telefono/whatsapp/email) NO se lee por select directo aunque
--     se vea la fila — solo por obras_ficha_persona();
--   · una persona/empresa ajena no se ve; obras_compartir_* la abre y
--     obras_revocar_* la vuelve a cerrar;
--   · no se vincula a una obra propia una persona que no se ve (WITH CHECK);
--   · obras_transferir_persona mueve creado_por y revoca los grants viejos;
--   · obras_buscar devuelve la empresa ajena con es_ajeno = true e id = NULL.
--
-- Último resultado: 9/9.
--
-- Encontró un agujero: `obras_empresas_select` (sql/039) hacía un EXISTS inline
-- contra `obras_empresa_compartida`, cuya policy a su vez leía `obras_empresas`
-- → recursión infinita (42P17) en cualquier lectura, incluido un
-- `INSERT ... RETURNING`. Lo arregló `sql/045`: las tres policies de las tablas
-- de grant se acotan a `usuario_id` / `otorgada_por` sin tocar la tabla madre.

DO $test$
DECLARE
  v_admin   uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester  uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_persona uuid;
  v_empresa uuid;
  v_obra    uuid;
  v_n       int;
  v_txt     text;
  v_bool    boolean;
  r         text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- permisos ----------
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_personas','obras_personas_crear',
                   'obras_empresas','obras_empresas_crear','obras_vincular','obras_personas_todas');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_personas','obras_personas_crear',
                   'obras_empresas','obras_empresas_crear','obras_vincular');

  PERFORM set_config('role', 'authenticated', true);

  -- ========== admin crea persona + empresa + obra ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras_personas (nombre, apellido, telefono, whatsapp, email, creado_por)
  VALUES ('Qwzxpt', 'Vbnmlk', '1140000001', '1140000001', 'qwz@ej.test', v_admin)
  RETURNING id INTO v_persona;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Zxqwvmnbplk Qwrtypfghj', v_admin) RETURNING id INTO v_empresa;

  IF (SELECT pendiente FROM obras_personas WHERE id = v_persona)
     OR (SELECT pendiente FROM obras_empresas WHERE id = v_empresa) THEN
    RAISE EXCEPTION 'setup: la entidad de control entró pendiente (nombre demasiado parecido al seed)';
  END IF;

  -- 1 · el dueño lee el contacto por la función
  SELECT telefono INTO v_txt FROM obras_ficha_persona(v_persona);
  IF v_txt IS DISTINCT FROM '1140000001' THEN
    RAISE EXCEPTION '1 FALLA: el dueño no recuperó el contacto por obras_ficha_persona (%))', v_txt;
  END IF;
  r := r || E'\n1 OK  dueño lee contacto por obras_ficha_persona';

  -- 2 · el dueño NO lee el contacto por select directo (GRANT por columna)
  BEGIN
    EXECUTE format('SELECT telefono FROM obras_personas WHERE id = %L', v_persona) INTO v_txt;
    RAISE EXCEPTION '2 FALLA: select directo de telefono no fue rechazado';
  EXCEPTION
    WHEN insufficient_privilege THEN
      r := r || E'\n2 OK  select directo de telefono → insufficient_privilege';
  END;

  -- ========== tester: privacidad ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  -- 3 · no ve la persona ajena
  SELECT count(*) INTO v_n FROM obras_personas WHERE id = v_persona;
  IF v_n <> 0 THEN RAISE EXCEPTION '3 FALLA: tester ve la persona ajena'; END IF;
  r := r || E'\n3 OK  tester no ve la persona ajena';

  -- 4 · no ve la empresa ajena
  SELECT count(*) INTO v_n FROM obras_empresas WHERE id = v_empresa;
  IF v_n <> 0 THEN RAISE EXCEPTION '4 FALLA: tester ve la empresa ajena'; END IF;
  r := r || E'\n4 OK  tester no ve la empresa ajena';

  -- 5 · no puede vincular a su obra una persona que no ve
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Kjhgfd del test', 'edificio', v_tester) RETURNING id INTO v_obra;
  BEGIN
    INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
    VALUES (v_obra, v_persona, ARRAY['compras']::rol_persona[]);
    RAISE EXCEPTION '5 FALLA: tester vinculó una persona que no ve';
  EXCEPTION
    WHEN insufficient_privilege THEN
      r := r || E'\n5 OK  vincular persona invisible → rechazado por WITH CHECK';
  END;

  -- ========== compartir / revocar ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_compartir_persona(v_persona, v_tester);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_personas WHERE id = v_persona;
  IF v_n <> 1 THEN RAISE EXCEPTION '6 FALLA: tras compartir, tester no ve la persona'; END IF;
  SELECT telefono INTO v_txt FROM obras_ficha_persona(v_persona);
  IF v_txt IS DISTINCT FROM '1140000001' THEN
    RAISE EXCEPTION '6 FALLA: tras compartir, tester no lee el contacto';
  END IF;
  r := r || E'\n6 OK  compartir → tester ve la persona y su contacto';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_revocar_persona(v_persona, v_tester);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_personas WHERE id = v_persona;
  IF v_n <> 0 THEN RAISE EXCEPTION '7 FALLA: tras revocar, tester sigue viendo la persona'; END IF;
  r := r || E'\n7 OK  revocar → tester deja de ver la persona';

  -- ========== transferir persona ==========
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_compartir_persona(v_persona, v_tester);          -- grant que la transferencia debe revocar
  PERFORM obras_transferir_persona(v_persona, v_tester);

  PERFORM set_config('role', 'none', true);
  SELECT creado_por INTO v_txt FROM obras_personas WHERE id = v_persona;
  IF v_txt <> v_tester::text THEN
    RAISE EXCEPTION '8 FALLA: transferir_persona no movió creado_por';
  END IF;
  SELECT count(*) INTO v_n FROM obras_persona_compartida
  WHERE persona_id = v_persona AND activo;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '8 FALLA: transferir_persona no revocó los grants del dueño viejo (% activos)', v_n;
  END IF;
  r := r || E'\n8 OK  transferir_persona movió creado_por y revocó grants';

  -- ========== buscador enmascarado ==========
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  -- la empresa 'Zxqwvmnbplk...' sigue siendo de admin
  PERFORM 1 FROM obras_buscar('zxqwvmnbplk') WHERE tipo = 'empresa' AND es_ajeno AND id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION '9 FALLA: la empresa ajena no volvió enmascarada (es_ajeno + id NULL)';
  END IF;
  r := r || E'\n9 OK  obras_buscar devuelve la empresa ajena enmascarada';

  RAISE EXCEPTION E'--- obras_model_a: 9/9 ---%', r;
END;
$test$;
