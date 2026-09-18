-- Verificación de sql/099: sacar un contacto de la obra corta, desactivar la
-- obra archiva.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_093.sql.
--
-- Reparto: A responsable de todo; C el receptor (usuario creado acá); B hace
-- de dueño nuevo de un contacto de A en el caso I.
--
-- A arma la obra O con sus personas P y Q y su empresa E, R es empleado de E,
-- y le comparte O a C tildando P, Q y E. R le llega a C anclado en E (el
-- recíproco del estado 2 de transferir, montado a mano).
--
-- Afirma:
--   A sacar a P de la obra apaga el grant de C sobre P
--   B volver a vincular a P no se lo devuelve
--   C volver a tildarlo sí
--   D lo mismo para empresa en obra y persona en empresa
--   E desactivada, C sigue viendo la fila (identidad) pero no abre nada: ni la
--     ficha, ni los teléfonos, ni el chip, ni puede sumarle vínculos
--   F a C le llega el aviso, y se resuelve bajo su RLS; a A no
--   G la vista Compartido de A no lista lo de la obra desactivada
--   H reactivar devuelve todo, con lo tildado
--   I la vista Compartido no nombra un ancla que quien mira no puede abrir
--   J una obra rechazada no se reactiva (OB035)
--
-- Último resultado: 10/10 (2026-09-18). Corrido antes de aplicar sql/099:
-- fallaba en A.

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- responsable
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- dueño nuevo de Q (I)
  v_c uuid := gen_random_uuid();                       -- receptor
  v_o uuid; v_o2 uuid; v_p uuid; v_q uuid; v_r uuid; v_s uuid; v_e uuid;
  v_vp uuid; v_ve uuid; v_re uuid;
  v_n int; v_b1 boolean; v_t text; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          created_at, updated_at)
  VALUES (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'receptor-099@example.invalid', '', now(), now());

  -- ── Permisos ─────────────────────────────────────────────────────────────
  -- Ninguno con `_todas` ni `obras_transferir` global: abrirían vías laterales
  -- y los casos pasarían sin ejercitar nada.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b, v_c)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_compartido','obras_desactivar',
    'obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_compartido','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_c, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_vincular','obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- ── A arma O y se la comparte a C tildando P, Q y E ──────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Wbzq Klmt 099', 'edificio', v_a) RETURNING id INTO v_o;
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Hjxv Rdpn 099', 'casa', v_a) RETURNING id INTO v_o2;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Yvkn Dqtz SA 099', v_a) RETURNING id INTO v_e;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Tqlz', 'Mvrk', '1145690991', v_a) RETURNING id INTO v_p;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Gnwd', 'Pxhs', '1145690992', v_a) RETURNING id INTO v_q;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Zfyl', 'Crbq', '1145690993', v_a) RETURNING id INTO v_r;

  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_p, ARRAY['arquitecto']::rol_persona[]) RETURNING id INTO v_vp;
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_q, ARRAY['compras']::rol_persona[]);
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_e, ARRAY['constructora']::rol_empresa[]) RETURNING id INTO v_ve;
  INSERT INTO obras_persona_empresa (persona_id, empresa_id)
  VALUES (v_r, v_e) RETURNING id INTO v_re;

  PERFORM obras_compartir_obra(v_o, v_c, ARRAY[v_e], ARRAY[v_p, v_q]);

  PERFORM set_config('role', 'none', true);
  INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, empresa_id, otorgada_por)
  VALUES (v_r, v_c, v_e, v_a);
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Kbmx', 'Lwqd', '1145690994', v_c) RETURNING id INTO v_s;

  IF NOT obras_ctx_vigente('persona', v_p, 'obra', v_o)
     OR NOT obras_ctx_vigente('persona', v_r, 'empresa', v_e) THEN
    RAISE EXCEPTION 'MONTAJE FALLA: C no abre lo que le tildaron';
  END IF;

  -- ── A · sacar a P de la obra apaga el grant ──────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  UPDATE obras_obra_persona SET activo = false WHERE id = v_vp;

  PERFORM set_config('role', 'none', true);
  SELECT activo INTO v_b1 FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_c AND obra_id = v_o;
  PERFORM set_config('role', 'authenticated', true);
  IF v_b1 THEN
    RAISE EXCEPTION 'A FALLA: P salió de la obra y el grant de C sigue activo';
  END IF;
  r := r || E'\nA OK  sacar a P de la obra apaga el grant de C';

  -- ── B · volver a vincularlo no lo devuelve ───────────────────────────────
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_p, ARRAY['arquitecto']::rol_persona[]);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  IF obras_ctx_vigente('persona', v_p, 'obra', v_o) THEN
    RAISE EXCEPTION 'B FALLA: re-vincular a P le devolvió el acceso a C';
  END IF;
  BEGIN
    PERFORM * FROM obras_ficha_persona(v_p, 'obra', v_o);
    RAISE EXCEPTION 'B FALLA: C abre la ficha de P sin que nadie la haya tildado';
  EXCEPTION WHEN SQLSTATE 'OB009' THEN NULL;
  END;
  r := r || E'\nB OK  volver a vincular a P no se lo devuelve';

  -- ── C · volver a tildarlo sí ─────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  PERFORM obras_compartir_obra(v_o, v_c, ARRAY[v_e], ARRAY[v_p, v_q]);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  IF NOT obras_ctx_vigente('persona', v_p, 'obra', v_o) THEN
    RAISE EXCEPTION 'C FALLA: re-tildado, C no abre a P';
  END IF;
  r := r || E'\nC OK  volver a tildarlo si';

  -- ── D · empresa en obra y persona en empresa ─────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  UPDATE obras_persona_empresa SET activo = false WHERE id = v_re;
  UPDATE obras_obra_empresa SET activo = false WHERE id = v_ve;

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
  WHERE persona_id = v_r AND usuario_id = v_c AND empresa_id = v_e AND activo;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'D FALLA: R dejó la empresa y el grant anclado en ella sigue activo';
  END IF;
  SELECT count(*) INTO v_n FROM obras_empresa_grant_contextual
  WHERE empresa_id = v_e AND usuario_id = v_c AND obra_id = v_o AND activo;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'D FALLA: E salió de la obra y el grant de C sigue activo';
  END IF;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\nD OK  lo mismo para empresa en obra y persona en empresa';

  -- ── E · desactivada, C ve la fila y no abre nada ─────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  PERFORM obras_set_activo(v_o, false);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  SELECT count(*) INTO v_n FROM obras WHERE id = v_o;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'E FALLA: C dejó de ver la fila; el aviso no se resolvería';
  END IF;
  IF obras_puede_ver_obra(v_o) THEN
    RAISE EXCEPTION 'E FALLA: C sigue pudiendo abrir la obra desactivada';
  END IF;
  BEGIN
    PERFORM * FROM obras_vinculos_de_obra(v_o);
    RAISE EXCEPTION 'E FALLA: C lee los vínculos de la obra desactivada';
  EXCEPTION WHEN SQLSTATE 'OB022' THEN NULL;
  END;
  BEGIN
    PERFORM * FROM obras_ficha_persona(v_q, 'obra', v_o);
    RAISE EXCEPTION 'E FALLA: C abre el teléfono de Q desde la obra desactivada';
  EXCEPTION WHEN SQLSTATE 'OB009' THEN NULL;
  END;
  -- Sin EXECUTE para authenticated: la llaman funciones DEFINER con el usuario
  -- como parámetro.
  PERFORM set_config('role', 'none', true);
  IF puede_abrir_registro('obra', v_o, v_c) THEN
    RAISE EXCEPTION 'E FALLA: el chip de tarea le sigue abriendo la obra a C';
  END IF;
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
    VALUES (v_o, v_s, ARRAY['decisor']::rol_persona[]);
    RAISE EXCEPTION 'E FALLA: C le sumó un vínculo a la obra desactivada';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  r := r || E'\nE OK  desactivada, C ve la fila y no abre nada';

  -- ── F · el aviso ─────────────────────────────────────────────────────────
  SELECT etiqueta INTO v_t FROM notificaciones_listar(50)
  WHERE tipo = 'obra_desactivada' AND destino_id = v_o;
  IF v_t IS DISTINCT FROM 'Wbzq Klmt 099' THEN
    RAISE EXCEPTION 'F FALLA: C no ve el aviso, o no se resuelve (etiqueta %)', v_t;
  END IF;

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM usuario_notificaciones
  WHERE usuario_id = v_a AND entidad_id = v_o AND tipo = 'obra_desactivada';
  PERFORM set_config('role', 'authenticated', true);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'F FALLA: A se avisó a sí mismo';
  END IF;
  r := r || E'\nF OK  a C le llega el aviso y se resuelve bajo su RLS; a A no';

  -- ── G · la vista Compartido no lista lo de la obra desactivada ───────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE entidad_id = v_o OR origen_id = v_o;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'G FALLA: la vista Compartido lista % filas de la obra desactivada', v_n;
  END IF;
  r := r || E'\nG OK  la vista Compartido no lista lo de la obra desactivada';

  -- ── H · reactivar devuelve todo ──────────────────────────────────────────
  PERFORM obras_set_activo(v_o, true);

  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE entidad_id = v_o OR origen_id = v_o;
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'H FALLA: reactivada, la vista Compartido lista % filas (esperaba O, P y Q)', v_n;
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  IF NOT obras_puede_ver_obra(v_o) OR NOT obras_ctx_vigente('persona', v_q, 'obra', v_o) THEN
    RAISE EXCEPTION 'H FALLA: reactivada, C no recupera la obra o lo tildado';
  END IF;
  r := r || E'\nH OK  reactivar devuelve todo, con lo tildado';

  -- ── I · no nombra un ancla que quien mira no puede abrir ─────────────────
  PERFORM set_config('role', 'none', true);
  UPDATE obras_personas SET creado_por = v_b WHERE id = v_q;
  PERFORM set_config('role', 'authenticated', true);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  SELECT count(*), max(origen_nombre) INTO v_n, v_t FROM obras_compartidos_por_mi()
  WHERE entidad_id = v_q AND usuario_id = v_c;
  IF v_n <> 1 OR v_t IS NOT NULL THEN
    RAISE EXCEPTION 'I FALLA: el dueño de Q ve % filas, ancla nombrada como %', v_n, v_t;
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  SELECT max(origen_nombre) INTO v_t FROM obras_compartidos_por_mi()
  WHERE entidad_id = v_q AND usuario_id = v_c;
  IF v_t IS DISTINCT FROM 'Wbzq Klmt 099' THEN
    RAISE EXCEPTION 'I FALLA: el dueño del ancla no ve su nombre (%)', v_t;
  END IF;
  r := r || E'\nI OK  la vista Compartido no nombra un ancla que no se puede abrir';

  -- ── J · una obra rechazada no se reactiva ────────────────────────────────
  PERFORM set_config('role', 'none', true);
  UPDATE obras SET activo = false, motivo_rechazo = 'Duplicada 099' WHERE id = v_o2;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM obras_set_activo(v_o2, true);
    RAISE EXCEPTION 'J FALLA: A reactivó una obra rechazada';
  EXCEPTION WHEN SQLSTATE 'OB035' THEN NULL;
  END;
  r := r || E'\nJ OK  una obra rechazada no se reactiva';

  RAISE EXCEPTION E'obras_099 — 10/10\n%', r;
END;
$test$;
