-- Verificación de sql/037: el buscador global.
--
-- NO es una migración: todo corre dentro de un DO que termina en RAISE
-- EXCEPTION, así que la transacción entera se revierte — no persiste ningún
-- dato ni permiso. Los resultados salen en el mensaje del error.
--
-- Mismo andamiaje que rls_obras.sql: `authenticated` + `request.jwt.claims`
-- para ejercer RLS, `role = none` para preparar datos sin RLS de por medio.
--
-- Lo que se afirma no es que el buscador encuentre —eso se ve en pantalla—
-- sino que no encuentre de más: que la obra de otro no aparezca, que la
-- persona fuera de alcance salga con identidad mínima y `visible = false`, que
-- la congelada ajena no salga en absoluto, y que buscar no deje al usuario
-- adentro de `obras_accesos_persona` sin haber abierto ninguna ficha.
--
-- Último resultado: 15/15.

DO $test$
DECLARE
  v_admin    uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester   uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra     uuid;
  v_empresa  uuid;
  v_congelada uuid;
  v_persona  uuid;
  v_oculta   uuid;
  v_n        int;
  v_bool     boolean;
  v_txt      text;
  r          text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- Setup de permisos ----------
  -- Admin carga todo; Tester es el vendedor de al lado: ve el módulo y la
  -- agenda, y nada de lo que Admin cargó.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_crear','obras_empresas','obras_empresas_crear',
                   'obras_personas','obras_personas_crear','obras_personas_empresas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos
  WHERE codigo IN ('obras_ver','obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  -- ---------- Datos, como Admin autenticado ----------
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  INSERT INTO obras (nombre, tipo, estado, direccion, localidad, responsable_id)
  VALUES ('Torre Zumaya 037', 'edificio', 'en_construccion', 'Colon 2450', 'Mar del Plata', v_admin)
  RETURNING id INTO v_obra;

  INSERT INTO obras_empresas (razon_social, nombre_comercial, localidad, creado_por)
  VALUES ('Zumaya Construcciones S.A.', 'Zumaya', 'Tandil', v_admin)
  RETURNING id INTO v_empresa;

  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Zumaya Congelada S.R.L.', v_admin)
  RETURNING id INTO v_congelada;

  INSERT INTO obras_personas (nombre, apellido, telefono, email, creado_por)
  VALUES ('Zumaya', 'Visible', '11 5555-0037', 'zumaya@test.com', v_admin)
  RETURNING id INTO v_persona;

  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Zumaya', 'Congelada', v_admin)
  RETURNING id INTO v_oculta;

  -- Lo que se parece a algo ya cargado nace congelado (sql/033). Se destraba
  -- sin RLS de por medio, menos las dos que el test quiere congeladas.
  PERFORM set_config('role', 'none', true);
  UPDATE obras          SET pendiente = false WHERE id = v_obra;
  UPDATE obras_empresas SET pendiente = false WHERE id = v_empresa;
  UPDATE obras_empresas SET pendiente = true  WHERE id = v_congelada;
  UPDATE obras_personas SET pendiente = false WHERE id = v_persona;
  UPDATE obras_personas SET pendiente = true  WHERE id = v_oculta;
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO obras_persona_empresa (persona_id, empresa_id, cargo, es_principal)
  VALUES (v_persona, v_empresa, 'Compras', true);

  -- ---------- Admin: encuentra lo suyo ----------
  SELECT count(*) INTO v_n FROM obras_buscar('zumaya') WHERE tipo = 'obra';
  r := r || E'\n01 la obra propia por nombre: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  SELECT count(*) INTO v_n FROM obras_buscar('colon') WHERE tipo = 'obra';
  r := r || E'\n02 la obra propia por direccion: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  SELECT visible INTO v_bool FROM obras_buscar('zumaya')
  WHERE tipo = 'persona' AND titulo = 'Zumaya Visible';
  r := r || E'\n03 la persona propia es visible: ' || coalesce(v_bool::text, 'sin fila') ||
       CASE WHEN v_bool THEN ' OK' ELSE ' *** FALLA' END;

  -- La congelada la ve quien la cargó: es la regla de sql/033, no una
  -- excepción del buscador.
  SELECT count(*) INTO v_n FROM obras_buscar('zumaya')
  WHERE tipo = 'persona' AND titulo = 'Zumaya Congelada';
  r := r || E'\n04 la congelada propia aparece: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- Tester: el vendedor de al lado ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);

  SELECT count(*) INTO v_n FROM obras_buscar('zumaya') WHERE tipo = 'obra';
  r := r || E'\n05 la obra ajena no aparece: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — cartera ajena en el buscador' END;

  SELECT count(*) INTO v_n FROM obras_buscar('zumaya')
  WHERE tipo = 'empresa' AND titulo = 'Zumaya Construcciones S.A.';
  r := r || E'\n06 la empresa es compartida: ' || v_n ||
       CASE WHEN v_n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  SELECT count(*) INTO v_n FROM obras_buscar('zumaya')
  WHERE tipo = 'empresa' AND titulo = 'Zumaya Congelada S.R.L.';
  r := r || E'\n07 la empresa congelada ajena no aparece: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA' END;

  SELECT visible INTO v_bool FROM obras_buscar('zumaya')
  WHERE tipo = 'persona' AND titulo = 'Zumaya Visible';
  r := r || E'\n08 la persona ajena sale con visible=false: ' || coalesce(v_bool::text, 'sin fila') ||
       CASE WHEN v_bool IS false THEN ' OK' ELSE ' *** FALLA — alcance ignorado' END;

  SELECT subtitulo INTO v_txt FROM obras_buscar('zumaya')
  WHERE tipo = 'persona' AND titulo = 'Zumaya Visible';
  r := r || E'\n09 identidad minima: empresa=' || coalesce(v_txt, 'NULL') ||
       CASE WHEN v_txt = 'Zumaya Construcciones S.A.' THEN ' OK' ELSE ' *** FALLA' END;

  SELECT cargada_por INTO v_txt FROM obras_buscar('zumaya')
  WHERE tipo = 'persona' AND titulo = 'Zumaya Visible';
  r := r || E'\n10 dice a quien preguntarle: ' || coalesce(v_txt, 'NULL') ||
       CASE WHEN v_txt IS NOT NULL THEN ' OK' ELSE ' *** FALLA' END;

  SELECT count(*) INTO v_n FROM obras_buscar('zumaya')
  WHERE tipo = 'persona' AND titulo = 'Zumaya Congelada';
  r := r || E'\n11 la congelada ajena no aparece: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — la cola no congela nada' END;

  -- Buscar no es abrir la ficha: el contacto sigue saliendo solo por
  -- obras_ficha_persona(), que es la que escribe el log. Se cuenta sin RLS: la
  -- policy del log exige `obras_personas_todas`, que Tester no tiene, así que
  -- como Tester el 0 saldría igual aunque el buscador estuviera escribiendo.
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_n FROM obras_accesos_persona
  WHERE usuario_id = v_tester AND persona_id = v_persona;
  PERFORM set_config('role', 'authenticated', true);
  r := r || E'\n12 buscar no registra acceso: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- Sin acceso al módulo no hay buscador ----------
  PERFORM set_config('role', 'none', true);
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id = v_tester
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*) INTO v_n FROM obras_buscar('zumaya');
  r := r || E'\n13 sin permisos del modulo: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA' END;

  -- ---------- El piso y el tope, de vuelta como Admin ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- La normalización come la puntuación, así que un comodín tipeado en la
  -- barra queda en nada y el piso de 2 lo corta.
  SELECT count(*) INTO v_n FROM obras_buscar('%');
  r := r || E'\n14 el comodin no es comodin: ' || v_n ||
       CASE WHEN v_n = 0 THEN ' OK' ELSE ' *** FALLA — LIKE sin escapar' END;

  INSERT INTO obras (nombre, tipo, estado, localidad, responsable_id)
  SELECT 'Zumaya Tope ' || i, 'edificio', 'idea', 'CABA', v_admin
  FROM generate_series(1, 6) i;

  PERFORM set_config('role', 'none', true);
  UPDATE obras SET pendiente = false WHERE responsable_id = v_admin AND nombre LIKE 'Zumaya Tope%';
  PERFORM set_config('role', 'authenticated', true);

  SELECT count(*) INTO v_n FROM obras_buscar('zumaya') WHERE tipo = 'obra';
  r := r || E'\n15 tope de 5 por tipo: ' || v_n ||
       CASE WHEN v_n = 5 THEN ' OK' ELSE ' *** FALLA' END;

  RAISE EXCEPTION E'RESULTADO obras_037:%', r;
END;
$test$;
