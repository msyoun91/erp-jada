-- Verificación de sql/060 (roles de la obra en los pasos de una plantilla) y
-- sql/065 (condición negada y texto que depende de un rol).
-- NO es una migración: corre dentro de un DO que termina en RAISE EXCEPTION,
-- así que la transacción entera se revierte. Los resultados salen en el
-- mensaje del error. Mismo andamiaje que plantillas_disparo.sql.
--
-- La obra, la empresa, la persona y sus vínculos se cargan como usuario de
-- sesión (sin RLS y sin disparo); el cambio de estado lo hace ADMIN como
-- `authenticated`, que es lo que dispara.
--
-- Volver a correrlo entero después de tocar sql/060 o sql/065.
--
-- Último resultado: 13/13.

DO $test$
DECLARE
  v_admin uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';  -- ADMIN
  v_obra  uuid;
  v_emp   uuid;
  v_per   uuid;
  v_pl    uuid;
  v_vacia uuid;
  v_p1    uuid;
  v_p3    uuid;
  v_p4    uuid;
  v_txt   text;
  v_n     int;
  r       text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- Una obra con una constructora y una persona que es arquitecta y decisora.
  INSERT INTO obras (nombre, tipo, responsable_id) VALUES ('Roble Plantilla Roles 7421', 'casa', v_admin)
  RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, creado_por) VALUES ('Zeta Construcciones Prueba 7421', v_admin)
  RETURNING id INTO v_emp;
  INSERT INTO obras_personas (nombre, apellido, creado_por) VALUES ('Ramiro', 'Prueba7421', v_admin)
  RETURNING id INTO v_per;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles) VALUES (v_obra, v_emp, '{constructora}');
  INSERT INTO obras_obra_persona (obra_id, persona_id, roles) VALUES (v_obra, v_per, '{arquitecto,decisor}');

  PERFORM set_config('role', 'authenticated', true);
  v_pl := guardar_plantilla(NULL, 'RP roles', NULL, 'privada', 'hilo', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"RP pedir planos","condicion":"persona:arquitecto","adjuntos":["persona:arquitecto"]},
      {"titulo":"RP llamar inmobiliaria","condicion":"empresa:inmobiliaria"},
      {"titulo":"RP coordinar","adjuntos":["empresa:constructora","persona:decisor","persona:arquitecto"]},
      {"titulo":"RP sin inmobiliaria {si hay persona:arquitecto}con arq{fin}{si no hay persona:arquitecto}sin arq{fin}",
       "descripcion":"{si no hay empresa:inmobiliaria}Buscar para {nombre}{fin}{si hay empresa:inmobiliaria}nunca{fin}",
       "condicion":"!empresa:inmobiliaria"},
      {"titulo":"RP sin arquitecto","condicion":"!persona:arquitecto"}]'::jsonb,
    'obra', 'en_cotizacion', 'RP hilo{si hay empresa:constructora} con constructora{fin}');
  v_vacia := guardar_plantilla(NULL, 'RP vacia', NULL, 'privada', 'hilo', 'privado', '{}', '[]'::jsonb,
    '[{"titulo":"RP solo con inmobiliaria","condicion":"empresa:inmobiliaria"}]'::jsonb,
    'obra', 'en_cotizacion');
  UPDATE obras SET estado = 'en_cotizacion' WHERE id = v_obra;

  BEGIN
    PERFORM guardar_plantilla(NULL, 'RP a mano', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X","condicion":"persona:arquitecto"}]'::jsonb);
    r := r || E'\n06 una plantilla a mano no lleva roles: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n06 una plantilla a mano no lleva roles: ' || CASE WHEN SQLSTATE = 'TA015' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  BEGIN
    PERFORM guardar_plantilla(NULL, 'RP formato', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X","condicion":"arquitecto"}]'::jsonb, 'obra', 'idea');
    r := r || E'\n07 un rol sin ente no pasa el CHECK: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n07 un rol sin ente no pasa el CHECK: ' || CASE WHEN SQLSTATE = '23514' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;

  BEGIN
    PERFORM guardar_plantilla(NULL, 'RP negado en adjuntos', NULL, 'privada', 'tarea', 'privado', '{}', '[]'::jsonb,
      '[{"titulo":"X","adjuntos":["!persona:arquitecto"]}]'::jsonb, 'obra', 'idea');
    r := r || E'\n11 la negación no vale en adjuntos: FALLO (guardó)';
  EXCEPTION WHEN OTHERS THEN
    r := r || E'\n11 la negación no vale en adjuntos: ' || CASE WHEN SQLSTATE = '23514' THEN 'OK' ELSE 'FALLO ' || SQLSTATE END;
  END;
  PERFORM set_config('role', 'none', true);

  SELECT id INTO v_p1 FROM tareas WHERE titulo = 'RP pedir planos' AND activo;
  SELECT id INTO v_p3 FROM tareas WHERE titulo = 'RP coordinar' AND activo;

  SELECT count(*) INTO v_n FROM tareas_vinculos
   WHERE tarea_id = v_p1 AND ente = 'persona' AND registro_id = v_per AND activo AND plantilla_id = v_pl;
  r := r || E'\n01 el paso con su rol presente se crea y adjunta a la persona: ' ||
    CASE WHEN v_p1 IS NOT NULL AND v_n = 1 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'RP llamar inmobiliaria';
  r := r || E'\n02 el paso cuyo rol falta no se crea: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT count(*) INTO v_n FROM tareas WHERE id = v_p3 AND paso_anterior_id = v_p1;
  r := r || E'\n03 el paso siguiente encadena al último que se creó: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas_vinculos WHERE tarea_id = v_p3 AND activo;
  r := r || E'\n04 adjuntos: la obra, la constructora y la persona una vez aunque tenga dos roles adjuntos: ' ||
    CASE WHEN v_n = 3 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT id INTO v_p4 FROM tareas WHERE titulo LIKE 'RP sin inmobiliaria%' AND activo;
  r := r || E'\n08 «solo si no hay» crea el paso cuando el rol falta, y encadena: ' ||
    CASE WHEN EXISTS (SELECT 1 FROM tareas WHERE id = v_p4 AND paso_anterior_id = v_p3) THEN 'OK' ELSE 'FALLO' END;

  SELECT count(*) INTO v_n FROM tareas WHERE titulo = 'RP sin arquitecto';
  r := r || E'\n09 «solo si no hay» no crea el paso cuando el rol está: ' || CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLO (' || v_n || ')' END;

  SELECT titulo || ' | ' || descripcion INTO v_txt FROM tareas WHERE id = v_p4;
  r := r || E'\n10 bloques en título y descripción, con dato adentro: ' ||
    CASE WHEN v_txt = 'RP sin inmobiliaria con arq | Buscar para Roble Plantilla Roles 7421' THEN 'OK' ELSE 'FALLO (' || COALESCE(v_txt, 'NULL') || ')' END;

  SELECT count(*) INTO v_n FROM tareas_hilos h JOIN tareas t ON t.hilo_id = h.id
   WHERE t.id = v_p1 AND h.titulo = 'RP hilo con constructora';
  r := r || E'\n12 bloques en el nombre de lo que crea: ' || CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLO' END;

  v_txt := rellenar_datos('{si hay a:b}x{fin}{si no hay a:b}y{fin}', NULL, NULL)
    || '|' || rellenar_datos('{si hay Arquitecto}x{fin}', '{}', '{a:b}')
    || '|' || rellenar_datos('{si hay a:b}Q{si hay a:b}X{fin}', '{}', '{a:b}')
    || '|' || rellenar_datos('{si hay a:b}sin fin', '{}', '{a:b}');
  r := r || E'\n13 sin roles, cabecera rara, anidado y sin {fin}: ' ||
    CASE WHEN v_txt = 'y|{si hay Arquitecto}x{fin}|{si hay a:b}QX|{si hay a:b}sin fin' THEN 'OK' ELSE 'FALLO (' || v_txt || ')' END;

  SELECT count(*) INTO v_n FROM tareas_hilos WHERE titulo = 'RP vacia';
  r := r || E'\n05 sin ningún paso que corresponda no queda nada ni avisa fallo: ' ||
    CASE WHEN v_n = 0 AND NOT EXISTS (SELECT 1 FROM usuario_notificaciones WHERE entidad_id = v_vacia)
         THEN 'OK' ELSE 'FALLO (' || v_n || ' hilos)' END;

  RAISE EXCEPTION 'RESULTADO:%', r;
END
$test$;
