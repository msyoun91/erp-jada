-- Verificación de sql/033 y sql/034: autorizaciones pendientes, congelado y
-- vinculación de una empresa con su gente.
--
-- NO es una migración: corre entero dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción se revierte y no persiste ningún dato ni
-- permiso. Mismo andamiaje que rls_obras.sql — el rol se mueve en los dos
-- sentidos (`authenticated` + `request.jwt.claims` para ejercer RLS, `none`
-- para mirar sin RLS de por medio).
--
-- Lo que afirma este archivo:
--   · que el trigger marca pendiente lo que se parece, y NO lo que no;
--   · que un vínculo pendiente no abre la ficha de contacto — que es el
--     motivo entero por el que el pedido existe;
--   · que la fila congelada no acepta vínculos;
--   · que `pendiente` no se puede tocar por UPDATE directo, y que el GRANT
--     por columna no rompió los UPDATE que la app sí hace;
--   · que aprobar y rechazar dejan rastro.
--
-- Último resultado: 33/33.
--
-- Encontró tres agujeros, todos anotados en `decisiones/obras.md`: el guard de
-- congelado explotaba con 42703 sobre `obras_persona_empresa`, `obras_aprobar`
-- daba acceso a la agenda entera por dentro de `obras_puede_ver_persona`, y
-- marcar referente era un atajo para saltear la autorización.
--
-- Los nombres de prueba son deliberadamente impronunciables: el test corre
-- contra la base con datos de `obras_dummy.sql`, y un "Edificio Libertador"
-- se parecería a los del seed y marcaría pendiente el caso de control.

DO $test$
DECLARE
  v_admin     uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester    uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra      uuid;
  v_obra_dup  uuid;
  v_empresa   uuid;
  v_mia       uuid;
  v_ajena     uuid;
  v_vinculo   uuid;
  v_n         int;
  v_b         boolean;
  v_txt       text;
  r           text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- Setup de permisos ----------
  -- Admin aprueba; Tester no. Se apaga todo `obras` de los dos antes de
  -- prender lo que el test quiere: leer los permisos de producción es lo que
  -- rompió rls_obras.sql en su momento.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_editar','obras_vincular',
                   'obras_empresas','obras_empresas_crear','obras_empresas_editar',
                   'obras_personas','obras_personas_crear','obras_personas_editar',
                   'obras_personas_empresas','obras_pendientes','obras_aprobar')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_vincular','obras_empresas',
                   'obras_personas','obras_personas_crear','obras_personas_empresas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  -- ---------- Datos base ----------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, estado, localidad, responsable_id)
  VALUES ('Zzqx Torre Kwvn 9911', 'edificio', 'idea', 'Vzzt', v_admin)
  RETURNING id, pendiente INTO v_obra, v_b;
  r := r || E'\n01 obra sin parecido nace libre: pendiente=' || v_b ||
       CASE WHEN v_b THEN ' *** FALLA' ELSE ' OK' END;

  -- ---------- El trigger marca lo que se parece ----------
  INSERT INTO obras (nombre, tipo, estado, localidad, responsable_id)
  VALUES ('Zzqx Torre Kwvn 9911', 'edificio', 'idea', 'Otra', v_admin)
  RETURNING id, pendiente INTO v_obra_dup, v_b;
  r := r || E'\n02 obra duplicada nace pendiente: ' || v_b ||
       CASE WHEN v_b THEN ' OK' ELSE ' *** FALLA — el duplicado entra solo' END;

  -- El cliente no decide: aunque mande la fila ya aprobada, el trigger la pisa.
  INSERT INTO obras (nombre, tipo, estado, responsable_id, pendiente)
  VALUES ('Zzqx Torre Kwvn 9911', 'edificio', 'idea', v_admin, false)
  RETURNING pendiente INTO v_b;
  r := r || E'\n03 el cliente no se auto-aprueba en el INSERT: ' || v_b ||
       CASE WHEN v_b THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- Personas: propia y ajena ----------
  INSERT INTO obras_personas (nombre, apellido, telefono, email, creado_por)
  VALUES ('Kwvn', 'Zzqxelli', '11 5555-0001', 'kwvn@zzqx.test', v_admin)
  RETURNING id INTO v_mia;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  INSERT INTO obras_personas (nombre, apellido, telefono, email, creado_por)
  VALUES ('Ppwlt', 'Grrmnd', '11 5555-0002', 'ppwlt@zzqx.test', v_tester)
  RETURNING id INTO v_ajena;

  -- ---------- Vincular lo propio no molesta a nadie ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_mia, ARRAY['compras']::rol_persona[])
  RETURNING pendiente INTO v_b;
  r := r || E'\n04 vincular persona propia: pendiente=' || v_b ||
       CASE WHEN v_b THEN ' *** FALLA — friccion de mas' ELSE ' OK' END;

  -- ---------- ...vincular lo ajeno espera autorización ----------
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_ajena, ARRAY['decisor']::rol_persona[])
  RETURNING id, pendiente INTO v_vinculo, v_b;
  r := r || E'\n05 vincular persona ajena: pendiente=' || v_b ||
       CASE WHEN v_b THEN ' OK' ELSE ' *** FALLA — la puerta sigue abierta' END;

  -- ---------- Y el vínculo pendiente NO abre el contacto ----------
  -- Es el punto entero del pedido: si acá diera true, el vendedor vincularía,
  -- leería el teléfono y esperaría el rechazo sentado.
  SELECT obras_puede_ver_persona(v_ajena) INTO v_b;
  r := r || E'\n06 vinculo pendiente da acceso a la persona: ' || v_b ||
       CASE WHEN v_b THEN ' *** FALLA — autorizacion decorativa' ELSE ' OK' END;

  BEGIN
    PERFORM * FROM obras_ficha_persona(v_ajena);
    r := r || E'\n07 ficha con vinculo pendiente: *** FALLA — la sirvio';
  EXCEPTION WHEN others THEN
    r := r || E'\n07 ficha con vinculo pendiente: cortado (' || SQLSTATE || ') OK';
  END;

  -- ---------- Congelado ----------
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Zzqx Kwvn Vzzt SRL', v_admin) RETURNING id INTO v_empresa;

  BEGIN
    INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
    VALUES (v_obra_dup, v_empresa, ARRAY['constructora']::rol_empresa[]);
    r := r || E'\n08 vincular a obra congelada: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n08 vincular a obra congelada: cortado (' || SQLSTATE || ') OK';
  END;

  DECLARE
    v_persona_congelada uuid;
  BEGIN
    -- Misma identidad que v_mia: el trigger la marca por parecido.
    INSERT INTO obras_personas (nombre, apellido, email, creado_por)
    VALUES ('Kwvn', 'Zzqxelli', 'kwvn@zzqx.test', v_admin)
    RETURNING id, pendiente INTO v_persona_congelada, v_b;
    r := r || E'\n09 persona duplicada nace pendiente: ' || v_b ||
         CASE WHEN v_b THEN ' OK' ELSE ' *** FALLA' END;

    BEGIN
      INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
      VALUES (v_obra, v_persona_congelada, ARRAY['compras']::rol_persona[]);
      r := r || E'\n10 vincular persona congelada: *** FALLA — paso';
    EXCEPTION WHEN others THEN
      r := r || E'\n10 vincular persona congelada: cortado (' || SQLSTATE || ') OK';
    END;
  END;

  -- ---------- `pendiente` no se toca por UPDATE directo ----------
  BEGIN
    UPDATE obras SET pendiente = false WHERE id = v_obra_dup;
    r := r || E'\n11 auto-aprobarse por UPDATE (obras): *** FALLA — paso';
  EXCEPTION WHEN insufficient_privilege THEN
    r := r || E'\n11 auto-aprobarse por UPDATE (obras): 42501 OK';
  END;

  BEGIN
    UPDATE obras_personas SET pendiente = false WHERE id = v_mia;
    r := r || E'\n12 auto-aprobarse por UPDATE (personas): *** FALLA — paso';
  EXCEPTION WHEN insufficient_privilege THEN
    r := r || E'\n12 auto-aprobarse por UPDATE (personas): 42501 OK';
  END;

  -- ...pero los UPDATE que la app sí hace siguen andando. El GRANT por
  -- columna es fácil de dejar corto y romper editar o desactivar.
  UPDATE obras_personas SET nombre = 'Kwvn2', activo = true WHERE id = v_mia;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  r := r || E'\n13 editar persona sigue andando: ' || v_n || ' fila(s)' ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA — GRANT corto' END;

  UPDATE obras_empresas SET razon_social = 'Zzqx Kwvn Vzzt SRL 2', activo = true
  WHERE id = v_empresa;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  r := r || E'\n14 editar empresa sigue andando: ' || v_n || ' fila(s)' ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA — GRANT corto' END;

  UPDATE obras_obra_persona SET roles = ARRAY['inversor']::rol_persona[], activo = false
  WHERE id = v_vinculo;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  r := r || E'\n15 editar/desvincular sigue andando: ' || v_n || ' fila(s)' ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA — GRANT corto' END;

  -- ---------- La cola y sus guards ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  BEGIN
    PERFORM * FROM obras_pendientes();
    r := r || E'\n16 cola sin permiso: *** FALLA — la sirvio';
  EXCEPTION WHEN others THEN
    r := r || E'\n16 cola sin permiso: cortado (' || SQLSTATE || ') OK';
  END;

  BEGIN
    PERFORM obras_resolver_pendiente('obra', v_obra_dup, true, NULL);
    r := r || E'\n17 aprobar sin permiso: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n17 aprobar sin permiso: cortado (' || SQLSTATE || ') OK';
  END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  SELECT count(*) INTO v_n FROM obras_pendientes() WHERE registro_id = v_obra_dup;
  r := r || E'\n18 la obra congelada esta en la cola: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  SELECT count(*) INTO v_n FROM obras_pendiente_similares('obra', v_obra_dup);
  r := r || E'\n19 contra que se parece: ' || v_n || ' fila(s)' ||
       CASE WHEN v_n >= 1 THEN ' OK' ELSE ' *** FALLA — aprobaria a ciegas' END;

  -- ---------- Rechazo sin motivo ----------
  BEGIN
    PERFORM obras_resolver_pendiente('obra', v_obra_dup, false, '   ');
    r := r || E'\n20 rechazo sin motivo: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n20 rechazo sin motivo: cortado (' || SQLSTATE || ') OK';
  END;

  -- ---------- Rechazo con motivo ----------
  PERFORM obras_resolver_pendiente('obra', v_obra_dup, false, 'Ya existe la misma obra');

  PERFORM set_config('role', 'none', true);
  SELECT activo::text || '/' || pendiente::text || '/' || coalesce(motivo_rechazo, '-')
  INTO v_txt FROM obras WHERE id = v_obra_dup;
  r := r || E'\n21 rechazada = desactivada con motivo: ' || quote_literal(v_txt) ||
       CASE WHEN v_txt = 'false/false/Ya existe la misma obra' THEN ' OK' ELSE ' *** FALLA' END;

  SELECT count(*) INTO v_n FROM obras_aprobaciones
  WHERE registro_id = v_obra_dup AND NOT aprobada AND decidido_por = v_admin;
  r := r || E'\n22 el rechazo quedo en el log: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- Resolver dos veces ----------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  BEGIN
    PERFORM obras_resolver_pendiente('obra', v_obra_dup, true, NULL);
    r := r || E'\n23 resolver dos veces: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n23 resolver dos veces: cortado (' || SQLSTATE || ') OK';
  END;

  -- ---------- Aprobar libera el vínculo ----------
  PERFORM obras_resolver_pendiente('obra_persona', v_vinculo, true, NULL);

  PERFORM set_config('role', 'none', true);
  SELECT pendiente INTO v_b FROM obras_obra_persona WHERE id = v_vinculo;
  r := r || E'\n24 aprobado deja de estar pendiente: ' || v_b ||
       CASE WHEN v_b THEN ' *** FALLA' ELSE ' OK' END;

  -- El vínculo aprobado sí da acceso — pero se desactivó en el caso 15, así
  -- que se reactiva para probar lo que importa.
  UPDATE obras_obra_persona SET activo = true WHERE id = v_vinculo;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT obras_puede_ver_persona(v_ajena) INTO v_b;
  r := r || E'\n25 vinculo aprobado da acceso: ' || v_b ||
       CASE WHEN v_b THEN ' OK' ELSE ' *** FALLA — no sirve para nada' END;

  -- ---------- Empresa congelada, invisible para el resto ----------
  DECLARE
    v_emp_dup uuid;
  BEGIN
    INSERT INTO obras_empresas (razon_social, creado_por)
    VALUES ('Zzqx Kwvn Vzzt SRL 2', v_admin) RETURNING id, pendiente INTO v_emp_dup, v_b;
    r := r || E'\n26 empresa duplicada nace pendiente: ' || v_b ||
         CASE WHEN v_b THEN ' OK' ELSE ' *** FALLA' END;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
    SELECT count(*) INTO v_n FROM obras_empresas WHERE id = v_emp_dup;
    r := r || E'\n27 otro ve la empresa congelada: ' || v_n ||
         CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — no estaba congelada' END;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
    SELECT count(*) INTO v_n FROM obras_empresas WHERE id = v_emp_dup;
    r := r || E'\n28 quien la cargo la sigue viendo: ' || v_n ||
         CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;
  END;

  -- ---------- sql/034: la empresa entra con su gente ----------
  DECLARE
    v_obra2 uuid;
    v_res   record;
  BEGIN
    INSERT INTO obras (nombre, tipo, estado, responsable_id)
    VALUES ('Wrrjt Plaza Mmndk 7722', 'oficina', 'idea', v_admin)
    RETURNING id INTO v_obra2;

    INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
    VALUES (v_mia, v_empresa, 'Compras');
    INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
    VALUES (v_ajena, v_empresa, 'Direccion');

    SELECT count(*) INTO v_n FROM obras_personas_de_empresa(v_empresa, v_obra2);
    r := r || E'\n29 la gente de la empresa se lista entera: ' || v_n ||
         CASE WHEN v_n = 2 THEN ' OK' ELSE ' *** FALLA — solo las propias' END;

    SELECT pg_get_function_result(p.oid) INTO v_txt
    FROM pg_proc p WHERE p.proname = 'obras_personas_de_empresa';
    r := r || E'\n30 esa lista no devuelve contacto: ' ||
         CASE WHEN v_txt NOT ILIKE '%telefono%' AND v_txt NOT ILIKE '%email%'
              THEN 'OK' ELSE '*** FALLA — ' || v_txt END;

    SELECT * INTO v_res FROM obras_vincular_empresa(
      v_obra2, v_empresa, ARRAY['constructora']::rol_empresa[], NULL,
      jsonb_build_array(
        jsonb_build_object('persona_id', v_mia,   'roles', jsonb_build_array('compras')),
        jsonb_build_object('persona_id', v_ajena, 'roles', jsonb_build_array('decisor'))
      )
    );
    r := r || E'\n31 vinculo empresa + gente: ' || v_res.personas_agregadas || ' agregadas, ' ||
         v_res.personas_pendientes || ' pendientes' ||
         CASE WHEN v_res.personas_agregadas = 2 AND v_res.personas_pendientes = 1
              THEN ' OK' ELSE ' *** FALLA' END;

    SELECT count(*) INTO v_n FROM obras_obra_persona
    WHERE obra_id = v_obra2 AND activo AND empresa_id = v_empresa;
    r := r || E'\n32 quedaron escritas con su empresa: ' || v_n ||
         CASE WHEN v_n = 2 THEN ' OK' ELSE ' *** FALLA' END;
  END;

  -- ---------- Marcar referente no es un atajo ----------
  -- La fila de obras_obra_referente también da acceso al contacto y no tiene
  -- `pendiente`: sin el guard, alcanzaba con marcar referente a alguien ajeno
  -- para saltear la autorización entera.
  DECLARE
    v_obra3   uuid;
    v_extrana uuid;
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
    INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
    VALUES ('Xnnbv', 'Qqrtz', '11 5555-0003', v_tester)
    RETURNING id INTO v_extrana;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
    INSERT INTO obras (nombre, tipo, estado, responsable_id)
    VALUES ('Ttrrb Casa Nnkkp 5533', 'casa', 'idea', v_admin)
    RETURNING id INTO v_obra3;

    PERFORM set_config('role', 'none', true);
    INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
    SELECT v_admin, id FROM submodulos WHERE codigo = 'obras_referentes'
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
    PERFORM set_config('role', 'authenticated', true);

    BEGIN
      INSERT INTO obras_obra_referente (obra_id, persona_id, porcentaje_comision)
      VALUES (v_obra3, v_extrana, 3.00);
      r := r || E'\n33 referente sobre persona ajena: *** FALLA — atajo abierto';
    EXCEPTION WHEN others THEN
      r := r || E'\n33 referente sobre persona ajena: cortado (' || SQLSTATE || ') OK';
    END;
  END;

  RAISE EXCEPTION E'RESULTADO obras_033:%', r;
END;
$test$;
