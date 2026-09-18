-- Verificación de sql/092: la vigencia del grant contextual, una sola vez.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_091.sql.
--
-- Reparto: A es el dueño de todo y quien comparte; B el receptor.
--
-- El montaje es el del agujero. A tiene una empresa E con una persona P
-- adentro, y una obra O vinculada a E. A comparte O con B tildando **solo** E:
-- B recibe un grant contextual de empresa anclado en O. Aparte, B tiene un
-- grant contextual de persona sobre P anclado en **E** — el que escribe el
-- estado 2 de `obras_transferir_resolver_vinculos`; se inserta directo porque
-- esa es la única vía que lo produce y montarla entera no agrega nada al test.
--
-- Afirma:
--   A con el ancla viva, B lee la fila persona↔empresa (no rompimos el camino
--     feliz) — y de paso ejercita la recursión: para autorizar a P hay que
--     resolver si E está vigente, que es `obras_ctx_vigente` llamándose a sí
--     misma con tipo `empresa`
--   B **el agujero**: al morir el ancla —se apaga el vínculo O↔E, así que el
--     grant de E deja de estar vigente— B deja de leer la fila persona↔empresa.
--     Antes de sql/092 seguía leyéndola: `obras_persona_grant_ctx_empresa_
--     conmigo` chequeaba solo que existiera la fila de grant
--   C un grant anclado en una obra no abre desde otra obra
--   D una empresa anclada en una empresa da false, sin `RAISE`
--   E la ficha de persona sigue abriendo con el ancla viva, y deja de abrir
--     cuando el vínculo obra↔persona se apaga
--   F un vínculo obra↔persona desactivado deja de leerse por grant contextual
--
-- Último resultado: 6/6 (2026-09-18).

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- dueño
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- receptor
  v_o uuid; v_o2 uuid;
  v_e uuid;
  v_p uuid; v_p2 uuid;
  v_n int; v_ok boolean; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ── Permisos ─────────────────────────────────────────────────────────────
  -- Los dos arrancan limpios: un `_todas` heredado abriría vías laterales y el
  -- test diría que pasa sin ejercitar nada.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas',
    'obras_empresas_crear','obras_personas','obras_personas_crear',
    'obras_personas_empresas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_empresas','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);

  -- ── Datos de A ───────────────────────────────────────────────────────────
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Zrqm Blkt 092', 'edificio', v_a) RETURNING id INTO v_o;
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Fdws Nptr 092', 'casa', v_a) RETURNING id INTO v_o2;

  INSERT INTO obras_empresas (razon_social, telefono, creado_por)
  VALUES ('Vxnq Hrtl SA 092', '1145670001', v_a) RETURNING id INTO v_e;

  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Tmjk', 'Wrbdz', '1145670002', v_a) RETURNING id INTO v_p;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Glpn', 'Yszfc', '1145670003', v_a) RETURNING id INTO v_p2;

  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_e, ARRAY['constructora']::rol_empresa[]);
  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_p, v_e, 'Jefe de compras');
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_o, v_p2, ARRAY['decisor']::rol_persona[]);

  -- Solo E va tildada: P no entra por el checklist, entra por el grant de abajo.
  PERFORM obras_compartir_obra(v_o, v_b, ARRAY[v_e], ARRAY[v_p2]);

  -- El grant que escribe el estado 2 de transferir: persona anclada en empresa.
  PERFORM set_config('role', 'none', true);
  INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, empresa_id, otorgada_por)
  VALUES (v_p, v_b, v_e, v_a);
  PERFORM set_config('role', 'authenticated', true);

  -- ── Ahora habla B ────────────────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);

  -- ── A · el camino feliz, y la recursión ──────────────────────────────────
  v_ok := obras_ctx_vigente('persona', v_p, 'empresa', v_e);
  IF NOT v_ok THEN
    RAISE EXCEPTION 'A FALLA: el grant anclado en empresa no vale con el ancla viva';
  END IF;

  SELECT count(*) INTO v_n FROM obras_persona_empresa
  WHERE persona_id = v_p AND empresa_id = v_e;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A FALLA: B no lee la fila persona↔empresa con el ancla viva (%)', v_n;
  END IF;
  r := r || E'\nA OK  con el ancla viva B lee la fila, y la recursion persona→empresa resuelve';

  -- ── C · ancla equivocada (antes de matar nada) ───────────────────────────
  -- P2 tiene grant anclado en O. Preguntado por O2 tiene que dar false aunque
  -- el grant exista y esté activo.
  IF NOT obras_ctx_vigente('persona', v_p2, 'obra', v_o) THEN
    RAISE EXCEPTION 'C FALLA: el grant anclado en su propia obra no vale';
  END IF;
  IF obras_ctx_vigente('persona', v_p2, 'obra', v_o2) THEN
    RAISE EXCEPTION 'C FALLA: un grant anclado en una obra abrió desde otra';
  END IF;
  r := r || E'\nC OK  el grant anclado en una obra no abre desde otra';

  -- ── D · empresa anclada en empresa ───────────────────────────────────────
  IF obras_ctx_vigente('empresa', v_e, 'empresa', v_e) THEN
    RAISE EXCEPTION 'D FALLA: aceptó una empresa anclada en una empresa';
  END IF;
  IF obras_ctx_vigente('marciano', v_p, 'obra', v_o) THEN
    RAISE EXCEPTION 'D FALLA: un tipo desconocido no dio false';
  END IF;
  r := r || E'\nD OK  empresa anclada en empresa y tipo desconocido dan false';

  -- ── E · la ficha de persona con ancla viva ───────────────────────────────
  PERFORM * FROM obras_ficha_persona(v_p, 'empresa', v_e);
  PERFORM * FROM obras_ficha_persona(v_p2, 'obra', v_o);
  r := r || E'\nE OK  las dos fichas abren con su ancla viva';

  -- ── B · el agujero: muere el ancla ───────────────────────────────────────
  -- A apaga el vínculo O↔E. El grant de E sobre B sigue `activo = true` —eso es
  -- la entrada "grants activos que ya no abren nada" del BACKLOG— pero deja de
  -- estar vigente, y con él tiene que caerse el grant de P que colgaba de E.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  UPDATE obras_obra_empresa SET activo = false
  WHERE obra_id = v_o AND empresa_id = v_e;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);

  IF obras_ctx_vigente('empresa', v_e) THEN
    RAISE EXCEPTION 'B FALLA: el grant de la empresa sigue vigente sin vínculo';
  END IF;
  IF obras_ctx_vigente('persona', v_p, 'empresa', v_e) THEN
    RAISE EXCEPTION 'B FALLA: el grant anclado en una empresa que ya no se ve sigue valiendo';
  END IF;

  SELECT count(*) INTO v_n FROM obras_persona_empresa
  WHERE persona_id = v_p AND empresa_id = v_e;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'B FALLA: B todavía lee la fila persona↔empresa con el ancla muerta (%)', v_n;
  END IF;

  BEGIN
    PERFORM * FROM obras_ficha_persona(v_p, 'empresa', v_e);
    RAISE EXCEPTION 'B FALLA: la ficha abrió con el ancla muerta';
  EXCEPTION WHEN SQLSTATE 'OB022' THEN NULL;
  END;
  r := r || E'\nB OK  muerto el ancla, la fila persona↔empresa deja de leerse';

  -- ── F · vínculo obra↔persona desactivado ─────────────────────────────────
  SELECT count(*) INTO v_n FROM obras_obra_persona
  WHERE obra_id = v_o AND persona_id = v_p2;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'F FALLA: B no lee el vínculo vivo de la obra compartida (%)', v_n;
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  UPDATE obras_obra_persona SET activo = false
  WHERE obra_id = v_o AND persona_id = v_p2;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);

  SELECT count(*) INTO v_n FROM obras_obra_persona
  WHERE obra_id = v_o AND persona_id = v_p2;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'F FALLA: el vínculo desactivado se sigue leyendo por grant contextual (%)', v_n;
  END IF;
  r := r || E'\nF OK  el vinculo desactivado deja de leerse por grant contextual';

  RAISE EXCEPTION E'obras_092 — 6/6\n%', r;
END;
$test$;
