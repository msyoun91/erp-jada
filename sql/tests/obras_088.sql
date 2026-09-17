-- Verificación de sql/088: migrar toda la agenda de un usuario a otro.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_087.sql.
--
-- La base tiene dos usuarios y el caso necesita tres: el tercero se crea en
-- `auth.users` y el trigger `on_auth_user_created` le arma su fila en
-- `usuarios`. Sin un tercero no hay forma de probar la decisión central —
-- "lo que el saliente RECIBIÓ pasa al entrante" — porque con dos usuarios el
-- otorgante siempre es el entrante y la fila se apaga en vez de moverse.
--
-- Reparto: admin ejecuta y recibe, Tester es el saliente, el tercero es quien
-- no participa y cuyas fichas no se pueden romper.
--
-- Afirma:
--   A las obras del saliente cambian de responsable y dejan una fila de log
--   B empresas y personas cambian de dueño y dejan su fila de log
--   C el vínculo que el saliente creó en la obra del TERCERO cambia de creador
--     (lo que `obras_transferir` deja a propósito y acá descongela)
--   D lo desactivado también cambia de dueño, pero NO entra al log
--   E lo que el saliente otorgó cuelga del entrante (`otorgada_por`)
--   F lo que el saliente recibió del tercero pasa al entrante (`usuario_id`)
--   G colisión: si el entrante ya tenía la misma llave, se revive la suya y la
--     del saliente se apaga — el UNIQUE no admite dos
--   H lo que el ENTRANTE le había otorgado al saliente se apaga, no se mueve
--     (violaría el CHECK `usuario_id <> otorgada_por`)
--   I el entrante no queda con grant sobre lo que ahora es suyo
--   J migrar a sí mismo → OB005; destino sin `obras_ver` → OB006
--   K sin `obras_migrar` → OB033
--   L la auditoría muestra las tres clases de transferencia (el fix de §4:
--     el INNER JOIN con `obras` escondía persona y empresa desde sql/041)
--
-- Último resultado: 12/12 (2026-09-17).

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ejecuta y recibe
  v_sale   uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- el que se va
  v_terc   uuid := gen_random_uuid();                       -- no participa
  v_nadie  uuid := gen_random_uuid();                       -- sin permisos
  v_obra_s uuid; v_obra_t uuid; v_obra_col uuid;
  v_emp uuid; v_per uuid; v_per_off uuid;
  v_n int; v_duenio uuid; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ── Tercero, y un cuarto sin ningún permiso para el caso J ──────────────
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          created_at, updated_at)
  VALUES (v_terc,  '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'tercero-088@example.invalid', '', now(), now()),
         (v_nadie, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'nadie-088@example.invalid', '', now(), now());

  -- ── Permisos ─────────────────────────────────────────────────────────────
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_sale, v_terc)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas','obras_compartido',
    'obras_auditoria','obras_migrar')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  -- `obras_personas_editar` está porque el saliente desactiva un contacto
  -- suyo (caso D): sin ese permiso la policy de UPDATE filtra la fila y el
  -- UPDATE no toca nada, en silencio.
  SELECT u.id, s.id FROM (VALUES (v_sale), (v_terc)) u(id), submodulos s
   WHERE s.codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_editar',
    'obras_personas_empresas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- ── El tercero: su obra, compartida con el saliente Y con el entrante ────
  -- Compartirla con los dos es lo que arma la colisión del caso G.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_terc)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Kvrtz Mblng 088', 'hotel', v_terc) RETURNING id INTO v_obra_t;
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Zjfhw Pdlqs 088', 'local', v_terc) RETURNING id INTO v_obra_col;

  PERFORM obras_compartir_obra(v_obra_t,   v_sale,  ARRAY[]::uuid[], ARRAY[]::uuid[]);
  PERFORM obras_compartir_obra(v_obra_col, v_sale,  ARRAY[]::uuid[], ARRAY[]::uuid[]);
  PERFORM obras_compartir_obra(v_obra_col, v_admin, ARRAY[]::uuid[], ARRAY[]::uuid[]);

  -- ── El entrante le comparte una obra suya al saliente (caso H) ───────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Xnbqr Cwtjy 088', 'oficina', v_admin) RETURNING id INTO v_obra_s;
  PERFORM obras_compartir_obra(v_obra_s, v_sale, ARRAY[]::uuid[], ARRAY[]::uuid[]);

  -- ── El saliente: su agenda ──────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sale)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Gtlmd Qsvxk 088', 'edificio', v_sale) RETURNING id INTO v_obra_s;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Hnzpb Rfwcg 088', v_sale) RETURNING id INTO v_emp;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Vqkdz', 'Tsmhr', v_sale) RETURNING id INTO v_per;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Ldwxf', 'Bnpqj', v_sale) RETURNING id INTO v_per_off;

  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra_s, v_per, ARRAY['arquitecto']::rol_persona[]);
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra_s, v_emp, ARRAY['constructora']::rol_empresa[]);

  -- El vínculo en la obra del TERCERO: el caso C.
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra_t, v_per, ARRAY['arquitecto']::rol_persona[]);

  -- Un contacto desactivado: el caso D. El chequeo está porque la policy de
  -- UPDATE filtra en silencio: sin permiso el statement toca cero filas y el
  -- caso pasaría a probar lo contrario de lo que dice.
  UPDATE obras_personas SET activo = false WHERE id = v_per_off;
  IF EXISTS (SELECT 1 FROM obras_personas WHERE id = v_per_off AND activo) THEN
    RAISE EXCEPTION 'SETUP FALLA: no se desactivó el contacto del caso D';
  END IF;

  -- ── Migrar ──────────────────────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- K y J antes de migrar: después el saliente no tiene nada.
  BEGIN
    PERFORM obras_migrar_agenda(v_sale, v_sale);
    RAISE EXCEPTION 'J FALLA: aceptó migrar a sí mismo';
  EXCEPTION WHEN sqlstate 'OB005' THEN NULL;
  END;

  BEGIN
    PERFORM obras_migrar_agenda(v_sale, v_nadie);
    RAISE EXCEPTION 'J FALLA: aceptó un destino sin obras_ver';
  EXCEPTION WHEN sqlstate 'OB006' THEN NULL;
  END;
  r := r || E'\nJ OK  mismo usuario → OB005; destino sin acceso → OB006';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sale)::text, true);
  BEGIN
    PERFORM obras_migrar_agenda(v_terc, v_sale);
    RAISE EXCEPTION 'K FALLA: migró sin el permiso';
  EXCEPTION WHEN sqlstate 'OB033' THEN NULL;
  END;
  r := r || E'\nK OK  sin obras_migrar → OB033';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_migrar_agenda(v_sale, v_admin);

  -- ── A ───────────────────────────────────────────────────────────────────
  SELECT responsable_id INTO v_duenio FROM obras WHERE id = v_obra_s;
  IF v_duenio <> v_admin THEN RAISE EXCEPTION 'A FALLA: la obra no cambió de responsable'; END IF;
  SELECT count(*) INTO v_n FROM obras_transferencias
   WHERE tipo = 'obra' AND obra_id = v_obra_s
     AND de_usuario_id = v_sale AND a_usuario_id = v_admin;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: la obra no dejó fila de log (%)', v_n; END IF;
  r := r || E'\nA OK  las obras cambian de responsable y quedan en el log';

  -- ── B ───────────────────────────────────────────────────────────────────
  SELECT creado_por INTO v_duenio FROM obras_empresas WHERE id = v_emp;
  IF v_duenio <> v_admin THEN RAISE EXCEPTION 'B FALLA: la empresa no cambió de dueño'; END IF;
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_per;
  IF v_duenio <> v_admin THEN RAISE EXCEPTION 'B FALLA: la persona no cambió de dueño'; END IF;
  SELECT count(*) INTO v_n FROM obras_transferencias
   WHERE (tipo = 'empresa' AND empresa_id = v_emp)
      OR (tipo = 'persona' AND persona_id = v_per);
  IF v_n <> 2 THEN RAISE EXCEPTION 'B FALLA: faltan filas de log (%)', v_n; END IF;
  r := r || E'\nB OK  empresas y personas cambian de dueño y quedan en el log';

  -- ── C — el vínculo en la obra del tercero ───────────────────────────────
  SELECT creado_por INTO v_duenio FROM obras_obra_persona
   WHERE obra_id = v_obra_t AND persona_id = v_per;
  IF v_duenio <> v_admin THEN
    RAISE EXCEPTION 'C FALLA: el vínculo en la obra ajena quedó con el saliente (%)', v_duenio;
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_persona
   WHERE obra_id = v_obra_t AND persona_id = v_per AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'C FALLA: se desactivó el vínculo de un tercero'; END IF;
  r := r || E'\nC OK  el vínculo creado en la obra del tercero cambia de creador';

  -- ── D — lo desactivado migra pero no se loguea ──────────────────────────
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_per_off;
  IF v_duenio <> v_admin THEN
    RAISE EXCEPTION 'D FALLA: el contacto desactivado quedó sin dueño';
  END IF;
  SELECT count(*) INTO v_n FROM obras_transferencias WHERE persona_id = v_per_off;
  IF v_n <> 0 THEN RAISE EXCEPTION 'D FALLA: lo desactivado ensució el log (%)', v_n; END IF;
  r := r || E'\nD OK  lo desactivado cambia de dueño sin entrar al log';

  -- ── E — lo que el saliente otorgó ───────────────────────────────────────
  -- Compartió su obra con nadie, así que se prueba con el grant que arrastra
  -- la transferencia: el tercero no recibió nada del saliente. Lo que sí hay
  -- es el revés (F, G, H). Se verifica que no quedó ningún grant colgando del
  -- saliente en ninguna de las tres tablas.
  SELECT (SELECT count(*) FROM obras_obra_compartida WHERE otorgada_por = v_sale)
       + (SELECT count(*) FROM obras_persona_grant_contextual WHERE otorgada_por = v_sale)
       + (SELECT count(*) FROM obras_empresa_grant_contextual WHERE otorgada_por = v_sale)
    INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'E FALLA: quedaron grants colgando del saliente (%)', v_n;
  END IF;
  r := r || E'\nE OK  no queda ningún grant colgando del saliente';

  -- ── F — lo recibido del tercero pasa al entrante ────────────────────────
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra_t AND usuario_id = v_admin AND otorgada_por = v_terc AND activo;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'F FALLA: la obra del tercero no pasó al entrante (%)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra_t AND usuario_id = v_sale AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'F FALLA: el saliente conservó el acceso'; END IF;
  r := r || E'\nF OK  lo que el tercero le compartió al saliente pasa al entrante';

  -- ── G — colisión: el entrante ya tenía esa obra ─────────────────────────
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra_col AND usuario_id = v_admin AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'G FALLA: el entrante perdió o duplicó su acceso (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE obra_id = v_obra_col AND usuario_id = v_sale AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'G FALLA: el saliente conservó el acceso duplicado'; END IF;
  r := r || E'\nG OK  la llave ya ocupada por el entrante no duplica ni rompe el UNIQUE';

  -- ── H — lo que el entrante le había compartido al saliente ──────────────
  SELECT count(*) INTO v_n FROM obras_obra_compartida
   WHERE usuario_id = v_admin AND otorgada_por = v_admin;
  IF v_n <> 0 THEN RAISE EXCEPTION 'H FALLA: alguien quedó compartiéndose algo a sí mismo'; END IF;
  r := r || E'\nH OK  lo que otorgó el entrante se apaga, no se mueve';

  -- ── I — el entrante no recibe grant sobre lo suyo ───────────────────────
  SELECT (SELECT count(*) FROM obras_persona_grant_contextual g
            JOIN obras_personas p ON p.id = g.persona_id AND p.creado_por = v_admin
           WHERE g.usuario_id = v_admin AND g.activo)
       + (SELECT count(*) FROM obras_empresa_grant_contextual g
            JOIN obras_empresas e ON e.id = g.empresa_id AND e.creado_por = v_admin
           WHERE g.usuario_id = v_admin AND g.activo)
       + (SELECT count(*) FROM obras_obra_compartida c
            JOIN obras o ON o.id = c.obra_id AND o.responsable_id = v_admin
           WHERE c.usuario_id = v_admin AND c.activo)
    INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'I FALLA: el entrante quedó con grant sobre lo propio (%)', v_n;
  END IF;
  r := r || E'\nI OK  el entrante no recibe grant sobre lo que ahora es suyo';

  -- ── L — la auditoría ve las tres clases ─────────────────────────────────
  SELECT count(DISTINCT a.tipo) INTO v_n
    FROM obras_auditoria_transferencias(1) a
   WHERE a.entidad_id IN (v_obra_s, v_emp, v_per);
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'L FALLA: la auditoría muestra % de 3 clases', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM obras_auditoria_transferencias(1) a
   WHERE a.entidad_id = v_per AND a.entidad IS NOT NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'L FALLA: la fila de persona salió sin etiqueta'; END IF;
  r := r || E'\nL OK  la auditoría muestra obra, empresa y persona con su nombre';

  RAISE EXCEPTION E'obras_088 — 12/12\n%', r;
END;
$test$;
