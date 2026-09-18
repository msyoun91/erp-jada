-- Compartir una obra: lo que ningún otro test cubre.
--
-- No verifica una migración sino el acto, tal como quedó después de `sql/086`
-- (la obra es el único acto de compartir) y `sql/092`. Recoge los casos que
-- seguían valiendo de `obras_047`, `obras_049` y `obras_082`, retirados a
-- `obsoletos/` porque su sujeto —el share directo de persona y empresa, con
-- `origen_obra_id`— ya no existe.
--
-- Lo vecino vive en otro lado, y acá no se repite: el checklist que otorga
-- contextual y no reparte agenda, en `obras_086`; la vigencia del grant
-- —vínculo vivo y ancla visible—, en `obras_090` y `obras_092`; transferir,
-- en `obras_087`–`089`; la rama de Tareas (`obras_compartir_registros`), en
-- `acceso_registros` y `obras_086` I.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_086.sql.
--
-- Afirma:
--   A ver ≠ editar: el receptor de una obra compartida no la puede UPDATE
--   B compartir una obra ajena → OB026
--   C obras_relaciones_compartibles_obra devuelve el checklist con
--     `ya_compartida` marcada en lo tildado y no en lo demás
--   D obras_compartidos_por_mi lista la obra y el contextual bajo su origen
--   E estado deseado (sql/049): re-tildar reactiva el grant que se destildó
--   F el contacto tildado no abre sin contexto → OB022
--
-- Último resultado: 6/6 (2026-09-18, revalidado tras sql/093).

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_e uuid; v_p uuid;
  v_n int; v_ya boolean; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- Permisos explícitos: el test no puede leer el estado de producción.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_personas_empresas','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- Nombres sin tokens en común entre sí: el detector difuso congela la segunda
  -- entidad parecida y compartir exige `NOT pendiente` (lección de obras_085).
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Jbtx Nqrv 093', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, telefono, creado_por)
  VALUES ('Fzmk Wlpd 093 SA', '1155550093', v_admin) RETURNING id INTO v_e;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Cgsy', 'Hvtn 093', '1155550193', v_admin) RETURNING id INTO v_p;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_e, ARRAY['desarrolladora']::rol_empresa[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_p, ARRAY['arquitecto']::rol_persona[]);

  IF (SELECT pendiente FROM obras WHERE id = v_obra)
     OR (SELECT pendiente FROM obras_empresas WHERE id = v_e)
     OR (SELECT pendiente FROM obras_personas WHERE id = v_p) THEN
    RAISE EXCEPTION 'setup: una entidad de control entró pendiente';
  END IF;

  -- Se comparte la obra tildando SOLO la persona: la empresa queda para el
  -- caso C, que necesita una fila del checklist sin compartir.
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[v_p]);

  -- A — ver no es editar.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras WHERE id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: el receptor no ve la obra compartida'; END IF;
  UPDATE obras SET nombre = 'hackeado' WHERE id = v_obra;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN RAISE EXCEPTION 'A FALLA: el receptor editó la obra compartida'; END IF;
  r := r || E'\nA OK  el receptor ve la obra y no la edita';

  -- B — y no la comparte.
  BEGIN
    PERFORM obras_compartir_obra(v_obra, v_admin, ARRAY[]::uuid[], ARRAY[]::uuid[]);
    RAISE EXCEPTION 'B FALLA: un no-responsable compartió la obra';
  EXCEPTION WHEN sqlstate 'OB026' THEN NULL;
  END;
  r := r || E'\nB OK  compartir una obra ajena → OB026';

  -- F — el contacto tildado abre con su ancla y no sin ella. Va antes de que
  -- los casos siguientes muevan el reparto.
  IF (SELECT telefono FROM obras_ficha_persona(v_p, 'obra', v_obra)) <> '1155550193' THEN
    RAISE EXCEPTION 'F FALLA: el contacto no abrió con ctx=obra';
  END IF;
  BEGIN
    PERFORM obras_ficha_persona(v_p);
    RAISE EXCEPTION 'F FALLA: el contacto abrió sin contexto';
  EXCEPTION WHEN sqlstate 'OB022' THEN NULL;
  END;
  r := r || E'\nF OK  el contacto abre con ctx=obra y no sin contexto';

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- C — el checklist del panel: las dos filas, una tildada.
  SELECT count(*) INTO v_n FROM obras_relaciones_compartibles_obra(v_obra, v_tester);
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'C FALLA: el checklist trae % filas, esperaba empresa + persona', v_n;
  END IF;
  SELECT ya_compartida INTO v_ya FROM obras_relaciones_compartibles_obra(v_obra, v_tester)
   WHERE tipo = 'persona' AND id = v_p;
  IF NOT v_ya THEN RAISE EXCEPTION 'C FALLA: la persona tildada no figura como ya_compartida'; END IF;
  SELECT ya_compartida INTO v_ya FROM obras_relaciones_compartibles_obra(v_obra, v_tester)
   WHERE tipo = 'empresa' AND id = v_e;
  IF v_ya THEN RAISE EXCEPTION 'C FALLA: la empresa sin tildar figura como ya_compartida'; END IF;
  r := r || E'\nC OK  el checklist trae las dos filas y marca solo lo tildado';

  -- D — la vista Compartido: la obra, y la persona colgando de ella.
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
   WHERE tipo = 'obra' AND entidad_id = v_obra AND usuario_id = v_tester
     AND origen_tipo IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: la obra compartida no está en la vista'; END IF;
  SELECT count(*) INTO v_n FROM obras_compartidos_por_mi()
   WHERE tipo = 'persona' AND entidad_id = v_p AND usuario_id = v_tester
     AND origen_tipo = 'obra' AND origen_id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION 'D FALLA: el contextual no cuelga de su obra en la vista'; END IF;
  r := r || E'\nD OK  Compartido lista la obra y el contextual bajo su origen';

  -- E — estado deseado: destildar apaga, re-tildar revive la misma fila.
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 0 THEN RAISE EXCEPTION 'E FALLA: destildar no apagó el grant'; END IF;
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[v_p]);
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra AND activo;
  IF v_n <> 1 THEN RAISE EXCEPTION 'E FALLA: re-tildar no reactivó el grant'; END IF;
  SELECT count(*) INTO v_n FROM obras_persona_grant_contextual
   WHERE persona_id = v_p AND usuario_id = v_tester AND obra_id = v_obra;
  IF v_n <> 1 THEN RAISE EXCEPTION 'E FALLA: re-tildar insertó una fila nueva en vez de revivir la vieja'; END IF;
  r := r || E'\nE OK  destildar apaga y re-tildar revive la misma fila';

  RAISE EXCEPTION E'--- obras_compartir: 6/6 ---%', r;
END;
$test$;
