-- Verificación de MODEL A (sql/039–044): privacidad por dueño, contacto
-- protegido a nivel columna, buscador enmascarado.
--
-- NO es una migración: corre entero dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción se revierte. Mismo andamiaje que
-- obras_033.sql: `set_config('role', ...)` + `request.jwt.claims` para ejercer
-- RLS, `'none'` para mirar sin RLS.
--
-- Afirma:
--   · el contacto (telefono/whatsapp/email) NO se lee por select directo aunque
--     se vea la fila — solo por obras_ficha_persona();
--   · una persona/empresa ajena no se ve;
--   · no se vincula a una obra propia una persona que no se ve (WITH CHECK);
--   · obras_buscar devuelve la empresa ajena con es_ajeno = true e id = NULL.
--
-- Los casos 6-8 originales —compartir/revocar una persona suelta desde su
-- ficha, y la transferencia que apagaba ese grant— se cayeron con `sql/086`,
-- que dejó a la obra como único acto de compartir. Lo que sigue valiendo de
-- ese terreno vive en `obras_compartir.sql` y en `obras_087.sql`.
--
-- El setup insertaba los permisos sin `ON CONFLICT` y chocaba con el UNIQUE
-- (usuario, submodulo): fallaba antes del primer caso, sin relación con
-- `sql/086`. Corregido al portarlo.
--
-- Último resultado: 6/6 (2026-09-18).
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

  -- ON CONFLICT y no INSERT pelado: los usuarios reales ya tienen filas de
  -- usuario_submodulos (desactivadas arriba), y hay UNIQUE (usuario, submodulo).
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_personas','obras_personas_crear',
                   'obras_empresas','obras_empresas_crear','obras_vincular','obras_personas_todas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_personas','obras_personas_crear',
                   'obras_empresas','obras_empresas_crear','obras_vincular')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

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

  -- ========== buscador enmascarado ==========
  -- la empresa 'Zxqwvmnbplk...' sigue siendo de admin
  PERFORM 1 FROM obras_buscar('zxqwvmnbplk') WHERE tipo = 'empresa' AND es_ajeno AND id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION '6 FALLA: la empresa ajena no volvió enmascarada (es_ajeno + id NULL)';
  END IF;
  r := r || E'\n6 OK  obras_buscar devuelve la empresa ajena enmascarada';

  RAISE EXCEPTION E'--- obras_model_a: 6/6 ---%', r;
END;
$test$;
