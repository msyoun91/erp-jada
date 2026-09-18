-- Verificación de sql/098: congelada quiere decir congelada.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_097.sql.
--
-- Reparto: A carga una obra, una empresa y una persona de control, y una de
-- cada una congelada. `pendiente` se prende sin RLS (`role none`): el trigger
-- que lo decide por parecido no es lo que se prueba acá, y con nombres
-- impronunciables no lo prendería. B tiene `obras_aprobar` y nada más.
--
-- Afirma:
--   A la obra congelada no acepta empresa, persona ni referente (OB011), y la
--     de control sí acepta la misma empresa — el corte es el estado, no la RLS
--   B la empresa congelada no se vincula ni a una obra ni a una persona (OB012)
--   C la persona congelada no se vincula a una obra, a una empresa ni como
--     referente (OB012)
--   D aprobada, se vincula normal
--   E rechazada, el rechazo no se traba: no tiene vínculos que OB002 cuente
--
-- Último resultado: 5/5 (2026-09-18). Antes de aplicar sql/098 fallaba en A.

DO $test$
DECLARE
  v_a uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';  -- carga
  v_b uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- aprueba
  v_o uuid; v_oc uuid; v_e uuid; v_ec uuid; v_p uuid; v_pc uuid;
  v_n int; r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ── Permisos ─────────────────────────────────────────────────────────────
  -- Sin `_todas` ni `obras_transferir`: abrirían vías laterales.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_a, v_b)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_a, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_referentes',
    'obras_empresas','obras_empresas_crear','obras_personas','obras_personas_crear',
    'obras_personas_empresas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_b, id FROM submodulos WHERE codigo IN ('obras_ver','obras_aprobar')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- ── A carga control y congeladas ─────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Qzmv Tkrd 098', 'edificio', v_a) RETURNING id INTO v_o;
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Wvxj Plqn 098', 'edificio', v_a) RETURNING id INTO v_oc;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Jwlf Bnxc SA 098', v_a) RETURNING id INTO v_e;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Hkzq Drvm SA 098', v_a) RETURNING id INTO v_ec;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Pvqz', 'Hdlm', '1145690981', v_a) RETURNING id INTO v_p;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Skrw', 'Fjtn', '1145690982', v_a) RETURNING id INTO v_pc;

  PERFORM set_config('role', 'none', true);
  UPDATE obras          SET pendiente = true WHERE id = v_oc;
  UPDATE obras_empresas SET pendiente = true WHERE id = v_ec;
  UPDATE obras_personas SET pendiente = true WHERE id = v_pc;
  SELECT count(*) INTO v_n FROM obras WHERE id = v_o AND pendiente;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'MONTAJE: la obra de control nació pendiente — cambiar el nombre';
  END IF;
  PERFORM set_config('role', 'authenticated', true);

  -- ── A · obra congelada ───────────────────────────────────────────────────
  BEGIN
    INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
    VALUES (v_oc, v_e, ARRAY['constructora']::rol_empresa[]);
    RAISE EXCEPTION 'A FALLA: la obra congelada aceptó una empresa';
  EXCEPTION WHEN SQLSTATE 'OB011' THEN NULL;
  END;
  BEGIN
    INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
    VALUES (v_oc, v_p, ARRAY['arquitecto']::rol_persona[]);
    RAISE EXCEPTION 'A FALLA: la obra congelada aceptó una persona';
  EXCEPTION WHEN SQLSTATE 'OB011' THEN NULL;
  END;
  BEGIN
    INSERT INTO obras_obra_referente (obra_id, persona_id, porcentaje_comision)
    VALUES (v_oc, v_p, 5);
    RAISE EXCEPTION 'A FALLA: la obra congelada aceptó un referente';
  EXCEPTION WHEN SQLSTATE 'OB011' THEN NULL;
  END;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_e, ARRAY['constructora']::rol_empresa[]);
  r := r || E'\nA OK  la obra congelada no acepta vinculos, la de control si';

  -- ── B · empresa congelada ────────────────────────────────────────────────
  BEGIN
    INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
    VALUES (v_o, v_ec, ARRAY['constructora']::rol_empresa[]);
    RAISE EXCEPTION 'B FALLA: la empresa congelada se vinculó a una obra';
  EXCEPTION WHEN SQLSTATE 'OB012' THEN NULL;
  END;
  BEGIN
    INSERT INTO obras_persona_empresa (persona_id, empresa_id)
    VALUES (v_p, v_ec);
    RAISE EXCEPTION 'B FALLA: la empresa congelada se vinculó a una persona';
  EXCEPTION WHEN SQLSTATE 'OB012' THEN NULL;
  END;
  r := r || E'\nB OK  la empresa congelada no se vincula a obras ni a personas';

  -- ── C · persona congelada ────────────────────────────────────────────────
  BEGIN
    INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
    VALUES (v_o, v_pc, ARRAY['arquitecto']::rol_persona[]);
    RAISE EXCEPTION 'C FALLA: la persona congelada se vinculó a una obra';
  EXCEPTION WHEN SQLSTATE 'OB012' THEN NULL;
  END;
  BEGIN
    INSERT INTO obras_persona_empresa (persona_id, empresa_id)
    VALUES (v_pc, v_e);
    RAISE EXCEPTION 'C FALLA: la persona congelada se vinculó a una empresa';
  EXCEPTION WHEN SQLSTATE 'OB012' THEN NULL;
  END;
  BEGIN
    INSERT INTO obras_obra_referente (obra_id, persona_id, porcentaje_comision)
    VALUES (v_o, v_pc, 5);
    RAISE EXCEPTION 'C FALLA: la persona congelada quedó de referente';
  EXCEPTION WHEN SQLSTATE 'OB012' THEN NULL;
  END;
  r := r || E'\nC OK  la persona congelada no se vincula a obras, empresas ni como referente';

  -- ── D · aprobada, se vincula ─────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_resolver_pendiente('empresa', v_ec, true, NULL);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a)::text, true);
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_o, v_ec, ARRAY['constructora']::rol_empresa[]);
  r := r || E'\nD OK  aprobada, la empresa se vincula normal';

  -- ── E · rechazada, el rechazo no se traba ────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b)::text, true);
  PERFORM obras_resolver_pendiente('persona', v_pc, false, 'Ya existe la misma persona');

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_personas WHERE id = v_pc AND NOT activo AND NOT pendiente;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'E FALLA: el rechazo no dejó la persona desactivada';
  END IF;
  r := r || E'\nE OK  rechazada sin vinculos, el rechazo pasa';

  RAISE EXCEPTION E'obras_098 — 5/5\n%', r;
END;
$test$;
