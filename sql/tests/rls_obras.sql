-- Verificación del modelo de seguridad de Agenda de Obras (sql/027 a sql/030).
-- NO es una migración: todo corre dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción entera se revierte — no persiste ningún
-- dato ni permiso. Los resultados salen en el mensaje del error.
--
-- Mismo andamiaje que atomicidad_tareas.sql: el rol se mueve en los dos
-- sentidos dentro del mismo DO — `authenticated` + `request.jwt.claims` para
-- ejercer RLS (sin eso corre como superusuario y el test no prueba nada),
-- `role = none` para contar sin RLS de por medio.
--
-- Lo que se verifica acá no es que las queries anden, sino que NO anden las
-- que no deben: que un vendedor no vea la obra del otro, que quien transfiere
-- no pueda editar, y que el teléfono de un contacto no salga por ningún
-- camino que no deje rastro.
--
-- Volver a correrlo entero después de tocar 027, 028, 029 o 030.
--
-- Último resultado: 29/29.
--
-- El caso 01 no es decorativo: la primera corrida falló ahí con 42501. La
-- policy de SELECT resolvía todo por `obras_puede_ver_persona(id)`, que relee
-- la fila, y en un INSERT ... RETURNING (lo que hace .insert().select() de
-- Supabase) la fila nueva todavía no está en el snapshot de una función
-- STABLE. Crear una persona habría fallado siempre en la app. Arreglado
-- probando `creado_por` como columna directa.

DO $test$
DECLARE
  v_admin   uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester  uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra    uuid;
  v_persona uuid;
  v_empresa uuid;
  v_n       int;
  v_txt     text;
  r         text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- Setup de permisos (como usuario de sesión) ----------
  -- Admin: vendedor completo. Tester: vendedor pelado.
  --
  -- Se apaga primero todo `obras` de los dos: el test afirma cosas sobre lo
  -- que NO se puede hacer (el caso 16 necesita a Admin sin `obras_transferir`)
  -- y no puede depender de lo que el usuario real tenga asignado hoy. Sin
  -- esto, el 16 transfiere de verdad y el 17 muere con "la obra ya es de ese
  -- usuario". Vuelve todo atrás con el rollback del final.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_editar','obras_vincular',
                   'obras_referentes','obras_desactivar','obras_empresas',
                   'obras_empresas_crear','obras_personas','obras_personas_crear',
                   'obras_personas_empresas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  -- ---------- Datos, como Admin autenticado ----------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, estado, localidad, responsable_id)
  VALUES ('Edificio Libertador 2450', 'edificio', 'en_construccion', 'CABA', v_admin)
  RETURNING id INTO v_obra;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Constructora XYZ S.A.', v_admin) RETURNING id INTO v_empresa;

  INSERT INTO obras_personas (nombre, apellido, telefono, email, creado_por)
  VALUES ('Juan', 'Perez', '11 4567-8900', 'JUAN@abc.com', v_admin)
  RETURNING id INTO v_persona;

  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_empresa, ARRAY['constructora','desarrolladora']::rol_empresa[]);

  INSERT INTO obras_obra_persona (obra_id, persona_id, empresa_id, roles)
  VALUES (v_obra, v_persona, v_empresa, ARRAY['compras','decisor']::rol_persona[]);

  INSERT INTO obras_obra_referente (obra_id, persona_id, porcentaje_comision)
  VALUES (v_obra, v_persona, 3.50);

  r := r || E'\n01 setup como Admin: OK';

  -- ---------- Normalización ----------
  PERFORM set_config('role', 'none', true);
  SELECT nombre_norm INTO v_txt FROM obras WHERE id = v_obra;
  r := r || E'\n02 nombre_norm = ' || quote_literal(v_txt) ||
       CASE WHEN v_txt = 'edificio libertador 2450' THEN ' OK' ELSE ' *** FALLA' END;

  SELECT telefono_norm || ' / ' || email_norm INTO v_txt FROM obras_personas WHERE id = v_persona;
  r := r || E'\n03 persona norm = ' || quote_literal(v_txt) ||
       CASE WHEN v_txt = '1145678900 / juan@abc.com' THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- La obra es privada del responsable ----------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  SELECT count(*) INTO v_n FROM obras WHERE id = v_obra;
  r := r || E'\n04 Tester ve la obra de Admin: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — fuga de obra' END;

  SELECT count(*) INTO v_n FROM obras_obra_empresa WHERE obra_id = v_obra;
  r := r || E'\n05 Tester ve los vinculos de esa obra: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA' END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT count(*) INTO v_n FROM obras WHERE id = v_obra;
  r := r || E'\n06 Admin ve su propia obra: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- La persona no es global ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*) INTO v_n FROM obras_personas WHERE id = v_persona;
  r := r || E'\n07 Tester ve la persona de la obra ajena: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — fuga de agenda' END;

  -- ...pero la busca y la encuentra, sin datos de contacto.
  SELECT count(*) INTO v_n FROM obras_buscar_duplicados_persona('Juan', 'Perez');
  r := r || E'\n08 Tester encuentra identidad minima: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA — no puede evitar el duplicado' END;

  -- El teléfono no sale por ahí: la firma de la función no lo devuelve.
  SELECT pg_get_function_result(p.oid) INTO v_txt
  FROM pg_proc p WHERE p.proname = 'obras_buscar_duplicados_persona';
  r := r || E'\n09 la busqueda no devuelve contacto: ' ||
       CASE WHEN v_txt NOT ILIKE '%telefono%' AND v_txt NOT ILIKE '%email%'
            THEN 'OK' ELSE '*** FALLA — ' || v_txt END;

  -- ---------- Aviso ciego de duplicados de obra ----------
  SELECT count(*) INTO v_n
  FROM obras_buscar_duplicados_obra('Edificio Libertador 2450', NULL, 'CABA')
  WHERE es_mia = false AND obra_id IS NULL AND nombre IS NULL
    AND direccion IS NULL AND localidad IS NULL AND responsable = 'Admin';
  r := r || E'\n10 aviso ciego (avisa, no muestra): ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- La ficha de persona exige acceso ----------
  BEGIN
    PERFORM * FROM obras_ficha_persona(v_persona);
    r := r || E'\n11 Tester abre ficha ajena: *** FALLA — no la corto';
  EXCEPTION WHEN others THEN
    r := r || E'\n11 Tester abre ficha ajena: cortado (' || SQLERRM || ') OK';
  END;

  -- ---------- ...y deja rastro cuando sí corresponde ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT telefono INTO v_txt FROM obras_ficha_persona(v_persona);
  r := r || E'\n12 Admin abre ficha propia: ' || quote_literal(v_txt) ||
       CASE WHEN v_txt = '11 4567-8900' THEN ' OK' ELSE ' *** FALLA' END;

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_accesos_persona
  WHERE usuario_id = v_admin AND persona_id = v_persona;
  r := r || E'\n13 el acceso quedo registrado: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA — robo silencioso' END;

  -- ---------- responsable_id y activo no se tocan por UPDATE directo ----------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  BEGIN
    UPDATE obras SET responsable_id = v_tester WHERE id = v_obra;
    r := r || E'\n14 UPDATE directo de responsable_id: *** FALLA — paso';
  EXCEPTION WHEN insufficient_privilege THEN
    r := r || E'\n14 UPDATE directo de responsable_id: 42501 OK';
  END;

  BEGIN
    UPDATE obras SET activo = false WHERE id = v_obra;
    r := r || E'\n15 UPDATE directo de activo: *** FALLA — paso';
  EXCEPTION WHEN insufficient_privilege THEN
    r := r || E'\n15 UPDATE directo de activo: 42501 OK';
  END;

  -- ---------- Transferir ----------
  BEGIN
    PERFORM obras_transferir(v_obra, v_tester);
    r := r || E'\n16 transferir sin permiso: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n16 transferir sin permiso: cortado OK';
  END;

  PERFORM set_config('role', 'none', true);
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo = 'obras_transferir'
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_transferir(v_obra, v_tester);

  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras
  WHERE id = v_obra AND responsable_id = v_tester;
  r := r || E'\n17 transferencia aplicada: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  SELECT count(*) INTO v_n FROM obras_transferencias
  WHERE obra_id = v_obra AND de_usuario_id = v_admin AND a_usuario_id = v_tester;
  r := r || E'\n18 transferencia registrada: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  -- Ahora Admin la ve (tiene obras_transferir) pero ya no la edita.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT count(*) INTO v_n FROM obras WHERE id = v_obra;
  r := r || E'\n19 quien transfiere ve la obra ajena: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA — no podria reasignarla' END;

  UPDATE obras SET nombre = 'Editado por quien no es responsable' WHERE id = v_obra;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  r := r || E'\n20 quien transfiere edita la obra ajena: ' || v_n || ' filas' ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — ver no es editar' END;

  -- ---------- Destino sin acceso ----------
  BEGIN
    PERFORM set_config('role', 'none', true);
    UPDATE usuario_submodulos SET activo = false
    WHERE usuario_id = v_tester
      AND submodulo_id = (SELECT id FROM submodulos WHERE codigo = 'obras_ver');
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
    PERFORM obras_transferir(v_obra, v_admin);
    PERFORM obras_transferir(v_obra, v_tester);
    r := r || E'\n21 transferir a alguien sin acceso: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n21 transferir a alguien sin acceso: cortado OK';
  END;

  -- ---------- Constraints de negocio ----------
  PERFORM set_config('role', 'none', true);

  BEGIN
    INSERT INTO obras (nombre, tipo, estado, responsable_id)
    VALUES ('Perdida sin motivo', 'casa', 'perdida', v_admin);
    r := r || E'\n22 perdida sin motivo: *** FALLA — paso';
  EXCEPTION WHEN check_violation THEN
    r := r || E'\n22 perdida sin motivo: rechazado OK';
  END;

  BEGIN
    INSERT INTO obras (nombre, tipo, estado, motivo_perdida, responsable_id)
    VALUES ('Otro sin detalle', 'casa', 'perdida', 'otro', v_admin);
    r := r || E'\n23 motivo otro sin detalle: *** FALLA — paso';
  EXCEPTION WHEN check_violation THEN
    r := r || E'\n23 motivo otro sin detalle: rechazado OK';
  END;

  BEGIN
    INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
    VALUES (v_obra, v_empresa, ARRAY['constructora','constructora']::rol_empresa[]);
    r := r || E'\n24 roles repetidos: *** FALLA — paso';
  EXCEPTION WHEN check_violation THEN
    r := r || E'\n24 roles repetidos: rechazado OK';
  END;

  BEGIN
    INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
    VALUES (v_obra, v_empresa, ARRAY['inmobiliaria']::rol_empresa[]);
    r := r || E'\n25 relacion obra-empresa duplicada: *** FALLA — paso';
  EXCEPTION WHEN unique_violation THEN
    r := r || E'\n25 relacion obra-empresa duplicada: rechazado OK';
  END;

  BEGIN
    INSERT INTO obras_obra_referente (obra_id, persona_id, porcentaje_comision)
    VALUES (v_obra, v_persona, 150.00);
    r := r || E'\n26 comision 150%: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n26 comision 150%: rechazado OK';
  END;

  -- ---------- Desactivar una entidad compartida ----------
  BEGIN
    UPDATE obras_empresas SET activo = false WHERE id = v_empresa;
    r := r || E'\n27 desactivar empresa con obras: *** FALLA — paso';
  EXCEPTION WHEN others THEN
    r := r || E'\n27 desactivar empresa con obras: cortado (' || SQLERRM || ') OK';
  END;

  -- Sin obras de por medio sí se puede, y la relación con personas se va con ella.
  DECLARE
    v_suelta uuid;
  BEGIN
    INSERT INTO obras_empresas (razon_social, creado_por)
    VALUES ('Empresa suelta', v_admin) RETURNING id INTO v_suelta;
    INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo)
    VALUES (v_persona, v_suelta, 'Socio');
    UPDATE obras_empresas SET activo = false WHERE id = v_suelta;
    SELECT count(*) INTO v_n FROM obras_persona_empresa
    WHERE empresa_id = v_suelta AND activo;
    r := r || E'\n28 cascada persona_empresa al desactivar: ' || v_n ||
         CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA' END;
  END;

  -- ---------- Una sola empresa principal ----------
  BEGIN
    INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo, es_principal)
    VALUES (v_persona, v_empresa, 'Arquitecto', true);
    INSERT INTO obras_empresas (razon_social, creado_por)
    VALUES ('Otra SA', v_admin) RETURNING id INTO v_empresa;
    INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo, es_principal)
    VALUES (v_persona, v_empresa, 'Socio', true);
    r := r || E'\n29 segunda empresa principal: *** FALLA — paso';
  EXCEPTION WHEN unique_violation THEN
    r := r || E'\n29 segunda empresa principal: rechazado OK';
  END;

  RAISE EXCEPTION E'RESULTADO rls_obras:%', r;
END;
$test$;
