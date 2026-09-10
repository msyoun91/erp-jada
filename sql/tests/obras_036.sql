-- Verificación de sql/036: el referente se cae con el vínculo.
--
-- NO es una migración: todo corre dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción entera se revierte — no persiste ningún
-- dato ni permiso. Los resultados salen en el mensaje del error.
--
-- Mismo andamiaje que rls_obras.sql: `authenticated` + `request.jwt.claims`
-- para ejercer RLS, `role = none` para contar sin RLS de por medio.
--
-- El caso 05 es el que justifica que la función siga siendo SECURITY DEFINER:
-- desvincula con el permiso `obras_referentes` apagado. Como INVOKER la
-- policy de UPDATE de `obras_obra_referente` filtraría la fila —sin error— y
-- la cascada no haría nada.
--
-- Los casos 07 y 08 no son de sql/036: cubren la cascada que ya existía
-- —entidad desactivada → sus `obras_persona_empresa` caen—, que hasta ahora no
-- tenía test. Los agrega esta migración porque su `ELSE` implícito pasó a dos
-- ramas explícitas. Corren sin RLS: son triggers, no dependen de permisos.
--
-- Último resultado: 8/8.

DO $test$
DECLARE
  v_admin    uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_obra     uuid;
  v_persona_a uuid;
  v_persona_b uuid;
  v_persona_c uuid;
  v_persona_d uuid;
  v_empresa  uuid;
  v_n        int;
  r          text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- Setup de permisos (como usuario de sesión) ----------
  -- El test afirma en el caso 05 que la cascada corre sin `obras_referentes`,
  -- así que no puede depender de lo que Admin tenga asignado hoy.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id = v_admin
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_editar','obras_vincular',
                   'obras_referentes','obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  -- ---------- Datos, como Admin autenticado ----------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, estado, localidad, responsable_id)
  VALUES ('Torre Cascada 036', 'edificio', 'en_ejecucion', 'CABA', v_admin)
  RETURNING id INTO v_obra;

  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Ana', 'Referente', v_admin) RETURNING id INTO v_persona_a;

  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Beto', 'Referente', v_admin) RETURNING id INTO v_persona_b;

  -- sql/033: lo que se parece a algo ya cargado nace congelado, y una fila
  -- congelada no acepta vínculos (OB012). Se destraba sin RLS de por medio.
  PERFORM set_config('role', 'none', true);
  UPDATE obras          SET pendiente = false WHERE id = v_obra;
  UPDATE obras_personas SET pendiente = false WHERE id IN (v_persona_a, v_persona_b);
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_persona_a, ARRAY['compras']::rol_persona[]),
         (v_obra, v_persona_b, ARRAY['decisor']::rol_persona[]);

  INSERT INTO obras_obra_referente (obra_id, persona_id, porcentaje_comision)
  VALUES (v_obra, v_persona_a, 3.50),
         (v_obra, v_persona_b, 2.00);

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_obra_referente
  WHERE obra_id = v_obra AND activo;
  r := r || E'\n01 setup: ' || v_n || ' referentes activos' ||
       CASE WHEN v_n = 2 THEN ' OK' ELSE ' *** FALLA' END;
  PERFORM set_config('role', 'authenticated', true);

  -- ---------- La desvinculación arrastra al referente ----------
  UPDATE obras_obra_persona SET activo = false
  WHERE obra_id = v_obra AND persona_id = v_persona_a;

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_obra_referente
  WHERE obra_id = v_obra AND persona_id = v_persona_a AND activo;
  r := r || E'\n02 referente de la desvinculada: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — sobrevive al vinculo' END;

  SELECT count(*) INTO v_n FROM obras_obra_referente
  WHERE obra_id = v_obra AND persona_id = v_persona_b AND activo;
  r := r || E'\n03 referente del otro vinculo: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA — cascada de mas' END;
  PERFORM set_config('role', 'authenticated', true);

  -- ---------- Volver a vincular no revive la comisión vieja ----------
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles)
  VALUES (v_obra, v_persona_a, ARRAY['compras']::rol_persona[]);

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_obra_referente
  WHERE obra_id = v_obra AND persona_id = v_persona_a AND activo;
  r := r || E'\n04 revinculada: ' || v_n || ' referentes activos' ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — revivio la comision' END;
  PERFORM set_config('role', 'authenticated', true);

  -- ---------- La cascada no depende del permiso de quien desvincula ----------
  PERFORM set_config('role', 'none', true);
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id = v_admin
    AND submodulo_id = (SELECT id FROM submodulos WHERE codigo = 'obras_referentes');
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*) INTO v_n FROM obras_obra_referente WHERE obra_id = v_obra;
  r := r || E'\n05 sin obras_referentes, Admin ve la tabla: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — la policy no filtra' END;

  UPDATE obras_obra_persona SET activo = false
  WHERE obra_id = v_obra AND persona_id = v_persona_b;

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_obra_referente
  WHERE obra_id = v_obra AND persona_id = v_persona_b AND activo;
  r := r || E'\n06 cascada sin el permiso: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — RLS frena la invariante' END;

  -- ---------- La cascada que ya existía sigue en pie ----------
  -- Sin RLS: lo que se mide es el trigger. La persona y la empresa de acá no
  -- participan en ninguna obra, así que los guards de desactivación
  -- (`OB001`/`OB002`) las dejan pasar.
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Cascada 036 SRL', v_admin) RETURNING id INTO v_empresa;

  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Caro', 'SinObra', v_admin) RETURNING id INTO v_persona_c;

  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Dario', 'SinObra', v_admin) RETURNING id INTO v_persona_d;

  UPDATE obras_empresas SET pendiente = false WHERE id = v_empresa;
  UPDATE obras_personas SET pendiente = false WHERE id IN (v_persona_c, v_persona_d);

  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
  VALUES (v_persona_c, v_empresa, 'Compras'),
         (v_persona_d, v_empresa, 'Obra');

  UPDATE obras_personas SET activo = false WHERE id = v_persona_c;

  SELECT count(*) INTO v_n FROM obras_persona_empresa
  WHERE persona_id = v_persona_c AND activo;
  r := r || E'\n07 persona desactivada arrastra su empresa: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — cargo colgado' END;

  UPDATE obras_empresas SET activo = false WHERE id = v_empresa;

  SELECT count(*) INTO v_n FROM obras_persona_empresa
  WHERE empresa_id = v_empresa AND activo;
  r := r || E'\n08 empresa desactivada arrastra su gente: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — cargo colgado' END;

  RAISE EXCEPTION E'RESULTADO obras_036:%', r;
END;
$test$;
