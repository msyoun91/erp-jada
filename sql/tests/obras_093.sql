-- Verificación de sql/093: otorgada_por es historia, no autoridad.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_092.sql.
--
-- Reparto: A dueño de todo y quien comparte; C el tercero; B el que recibe la
-- obra por transferencia.
--
-- El montaje es el que separa al otorgante de la propiedad, que es el único
-- estado donde las dos reglas dan distinto: A comparte su obra O con C tildando
-- su persona P y su empresa E, y después **transfiere O a B sin migrar nada**.
-- Queda una obra de B con dos contactos de A adentro, vistos por C.
--
-- Afirma:
--   A la policy de `obras_obra_compartida` sigue al responsable: B lee con
--     quién está compartida su obra nueva, A ya no. Antes lo resolvía
--     `otorgada_por`, que transferir reescribía; sin la sección 7 el panel
--     "compartida con" de la ficha quedaba vacío para el nuevo responsable
--   B la vista Compartido lista lo que cada uno puede revocar: la obra la ve B,
--     los contactos los ven A (su dueño) y B (dueño del ancla), y ninguno se ve
--     a sí mismo como receptor. Antes de sql/093 los contactos de A se le iban
--   C el checklist de B no apaga los grants de A: destildar todo sobre C deja
--     vivo lo que B no puede ofrecer porque no es suyo
--   D revoca el dueño del contacto, aunque el ancla ya no sea suya
--   E revoca el dueño del ancla, aunque el contacto no sea suyo
--   F sin ninguna de las dos autoridades, OB026 — y revocar dos veces con
--     autoridad es idempotente, no OB026 (el gate salió del WHERE)
--
-- Último resultado: 6/6 (2026-09-18, revalidado tras sql/099).

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- dueño / saliente
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- recibe la obra
  v_c uuid := gen_random_uuid();                       -- tercero
  v_o uuid; v_p uuid; v_e uuid;
  v_n int; v_activo boolean; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          created_at, updated_at)
  VALUES (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'tercero-093@example.invalid', '', now(), now());

  -- ── Permisos ─────────────────────────────────────────────────────────────
  -- Ninguno con `_todas` ni `obras_transferir` global: abrirían vías laterales
  -- y los casos pasarían sin ejercitar nada.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b, v_c)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_compartido',
    'obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas',
    'obras_transferir_propias')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_compartido','obras_empresas','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_c, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_compartido','obras_empresas','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);

  -- ── Datos de A, compartidos con C ────────────────────────────────────────
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Krtz Mvlp 093', 'edificio', v_a) RETURNING id INTO v_o;

  INSERT INTO obras_empresas (razon_social, telefono, creado_por)
  VALUES ('Jbnq Wtsr SA 093', '1145680001', v_a) RETURNING id INTO v_e;

  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Fdlm', 'Xrgzb', '1145680002', v_a) RETURNING id INTO v_p;

  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_e, ARRAY['constructora']::rol_empresa[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_p, ARRAY['decisor']::rol_persona[]);

  PERFORM obras_compartir_obra(v_o, v_c, ARRAY[v_e], ARRAY[v_p]);

  -- ── Y la obra cambia de mano sin llevarse los contactos ──────────────────
  PERFORM obras_transferir(v_o, v_b, '{}', '{}');

  -- ── A · la policy sigue al responsable ───────────────────────────────────
  SELECT count(*) INTO v_n FROM obras_obra_compartida
  WHERE obra_id = v_o AND usuario_id = v_c AND activo;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A FALLA: A sigue leyendo los compartidos de una obra que ya no es suya (%)', v_n;
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  SELECT count(*) INTO v_n FROM obras_obra_compartida
  WHERE obra_id = v_o AND usuario_id = v_c AND activo;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A FALLA: el nuevo responsable no ve con quién está compartida su obra (%)', v_n;
  END IF;
  r := r || E'\nA OK  el panel "compartida con" sigue al responsable, no al otorgante';

  -- ── B · la vista Compartido lista lo que cada uno puede revocar ──────────
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE tipo = 'obra' AND entidad_id = v_o AND usuario_id = v_c;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'B FALLA: B no ve en Compartido la obra que recibió (%)', v_n;
  END IF;

  -- Los dos contactos de A que C ve DENTRO de la obra de B: B los lista porque
  -- es el dueño del ancla, y son los hijos que se anidan bajo la fila de arriba.
  -- Acotado al montaje: la base tiene grants reales de estos mismos usuarios, y
  -- un count sin filtro los cuenta a ellos.
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE tipo <> 'obra' AND entidad_id IN (v_p, v_e) AND usuario_id = v_c
    AND origen_id = v_o;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'B FALLA: el dueño del ancla no ve lo que su obra muestra (%)', v_n;
  END IF;

  -- Pero NO los suyos: la cascada de la transferencia le otorgó a él esos dos
  -- contactos sobre la misma obra, y una fila que me otorgaron no es algo que
  -- compartí.
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE tipo <> 'obra' AND usuario_id = v_b;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'B FALLA: B se ve a sí mismo como receptor en su propia vista (%)', v_n;
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE tipo = 'obra' AND entidad_id = v_o;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A FALLA: A sigue viendo en Compartido una obra que transfirió (%)', v_n;
  END IF;

  -- Sus dos contactos, con C por el checklist y con B por la cascada.
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
  WHERE entidad_id IN (v_p, v_e) AND usuario_id IN (v_b, v_c) AND origen_id = v_o;
  IF v_n <> 4 THEN
    RAISE EXCEPTION 'B FALLA: A no ve sus dos contactos expuestos a los dos usuarios (%)', v_n;
  END IF;
  r := r || E'\nB OK  la obra la ve quien la recibio; los contactos, su dueno y el del ancla';

  -- ── C · el checklist no apaga lo que no puede ofrecer ────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_compartir_obra(v_o, v_c, '{}', '{}');

  PERFORM set_config('role', 'none', true);
  SELECT activo INTO v_activo FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_c AND obra_id = v_o;
  IF NOT v_activo THEN
    RAISE EXCEPTION 'C FALLA: el checklist de B apagó un grant sobre un contacto de A';
  END IF;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\nC OK  destildar todo no toca lo que la pantalla no ofrece';

  -- ── D · revoca el dueño del contacto, sin ser dueño del ancla ────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  PERFORM obras_revocar_contextual('persona', v_p, v_c, 'obra', v_o);

  PERFORM set_config('role', 'none', true);
  SELECT activo INTO v_activo FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_c AND obra_id = v_o;
  PERFORM set_config('role', 'authenticated', true);
  IF v_activo THEN
    RAISE EXCEPTION 'D FALLA: el dueño del contacto no pudo revocar su propia exposición';
  END IF;

  -- Y de nuevo: con autoridad, cero filas es idempotencia y no OB026.
  PERFORM obras_revocar_contextual('persona', v_p, v_c, 'obra', v_o);
  r := r || E'\nD OK  revoca el dueno del contacto, y revocar dos veces no falla';

  -- ── E · revoca el dueño del ancla, sin ser dueño del contacto ────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_revocar_contextual('empresa', v_e, v_c, 'obra', v_o);

  PERFORM set_config('role', 'none', true);
  SELECT activo INTO v_activo FROM obras_empresa_grant_contextual
  WHERE empresa_id = v_e AND usuario_id = v_c AND obra_id = v_o;
  PERFORM set_config('role', 'authenticated', true);
  IF v_activo THEN
    RAISE EXCEPTION 'E FALLA: el dueño del ancla no pudo revocar un contacto ajeno que su obra muestra';
  END IF;
  r := r || E'\nE OK  revoca el dueno del ancla, aunque el contacto sea de otro';

  -- ── F · sin ninguna de las dos autoridades ───────────────────────────────
  -- C es el receptor del grant, no es dueño de la persona ni de la obra.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c)::text, true);
  BEGIN
    PERFORM obras_revocar_contextual('persona', v_p, v_b, 'obra', v_o);
    RAISE EXCEPTION 'F FALLA: revocó sin ser dueño del contacto ni del ancla';
  EXCEPTION WHEN SQLSTATE 'OB026' THEN NULL;
  END;

  PERFORM set_config('role', 'none', true);
  SELECT activo INTO v_activo FROM obras_persona_grant_contextual
  WHERE persona_id = v_p AND usuario_id = v_b AND obra_id = v_o;
  PERFORM set_config('role', 'authenticated', true);
  IF NOT v_activo THEN
    RAISE EXCEPTION 'F FALLA: el grant se apagó igual';
  END IF;
  r := r || E'\nF OK  sin autoridad, OB026 y la fila intacta';

  RAISE EXCEPTION E'obras_093 — 6/6\n%', r;
END;
$test$;
