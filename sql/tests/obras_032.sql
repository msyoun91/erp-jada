-- Verificación de lo que agrega sql/032: cada RAISE EXCEPTION del módulo sale
-- con su código `OB0xx` y no como `P0001`.
--
-- Lo que se prueba acá no es que las funciones corten — eso ya lo cubren
-- rls_obras.sql y obras_031.sql — sino que el corte llegue **identificado**.
-- Sin `ERRCODE`, `mensajeError()` en `lib/utils.ts` no puede distinguir un
-- mensaje escrito para el usuario de un error interno de Postgres, y los diez
-- terminaban en el genérico "No se pudo completar la operación".
--
-- El caso 01 es el que justifica la clase entera: afirma que el conteo de
-- obras viaja dentro del mensaje. Un mapa código → texto en TypeScript, como
-- el de `tareas`, habría perdido ese número — que es el único dato que ese
-- mensaje tiene para dar.
--
-- Mismo andamiaje que los otros dos: DO que termina en RAISE EXCEPTION, así
-- que la transacción entera se revierte y no persiste ni un dato ni un
-- permiso. Los resultados salen en el mensaje del error.
--
-- **Depende de los datos de `sql/seeds/obras_dummy.sql`** para los casos 01 y
-- 02: sin una empresa y una persona participando en obras activas, los dos
-- guards no tienen de qué quejarse.
--
-- El setup apaga `obras_transferir`, `obras_desactivar` y `obras_auditoria` de
-- Admin: los casos 03, 07 y 12 afirman que sin el submódulo la función corta,
-- y el usuario real los tiene asignados.
--
-- Los casos 09 a 11 cazaron un bug que no era de códigos: `obras_ficha_persona`
-- escribía el log antes de confirmar que la persona existiera. Ver `sql/032`.
--
-- Último resultado: 12/12.

DO $test$
DECLARE
  v_admin   uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester  uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_nada    uuid := '00000000-0000-4000-a000-0000000000ff';
  v_empresa uuid;
  v_persona uuid;
  v_obra    uuid;
  v_persona_ok uuid;
  v_accesos int;
  n         int;
  r         text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  -- ---------- OB001 / OB002: el conteo tiene que sobrevivir ----------
  -- Corren como dueño de la sesión: los guards son triggers, no dependen de
  -- permisos, y lo que se mide es el código y el texto.
  SELECT oe.empresa_id INTO v_empresa
  FROM obras_obra_empresa oe JOIN obras o ON o.id = oe.obra_id AND o.activo
  WHERE oe.activo LIMIT 1;

  SELECT op.persona_id INTO v_persona
  FROM obras_obra_persona op JOIN obras o ON o.id = op.obra_id AND o.activo
  WHERE op.activo LIMIT 1;

  IF v_empresa IS NULL OR v_persona IS NULL THEN
    RAISE EXCEPTION 'Falta el seed: correr sql/seeds/obras_dummy.sql antes de este test';
  END IF;

  BEGIN
    UPDATE obras_empresas SET activo = false WHERE id = v_empresa;
    r := r || E'\n01 OB001 empresa en uso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n01 OB001 empresa en uso: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB001' AND SQLERRM ~ 'participa en [0-9]+ obra'
              THEN ' con el conteo OK'
              ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  BEGIN
    UPDATE obras_personas SET activo = false WHERE id = v_persona;
    r := r || E'\n02 OB002 persona en uso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n02 OB002 persona en uso: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB002' AND SQLERRM ~ 'participa en [0-9]+ obra'
              THEN ' con el conteo OK'
              ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  -- ---------- Setup de permisos ----------
  -- Admin queda como vendedor sin transferir, sin desactivar y sin auditoría.
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id = v_admin
    AND submodulo_id IN (SELECT id FROM submodulos
                         WHERE codigo IN ('obras_transferir', 'obras_desactivar',
                                          'obras_auditoria'));

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos
  WHERE codigo IN ('obras_ver', 'obras_crear', 'obras_personas')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  SELECT id INTO v_obra FROM obras WHERE responsable_id = v_admin AND activo LIMIT 1;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- ---------- OB003 a OB006: transferir ----------
  BEGIN
    PERFORM obras_transferir(coalesce(v_obra, v_nada), v_tester);
    r := r || E'\n03 OB003 sin permiso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n03 OB003 sin permiso: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB003' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  PERFORM set_config('role', 'none', true);
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo = 'obras_transferir' AND activo
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM obras_transferir(v_nada, v_tester);
    r := r || E'\n04 OB004 obra inexistente: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n04 OB004 obra inexistente: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB004' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  BEGIN
    PERFORM obras_transferir(v_obra, v_admin);
    r := r || E'\n05 OB005 ya es de ese usuario: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n05 OB005 ya es de ese usuario: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB005' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  -- Tester sin `obras_ver`: transferirle la obra la haría desaparecer.
  PERFORM set_config('role', 'none', true);
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id = v_tester
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM obras_transferir(v_obra, v_tester);
    r := r || E'\n06 OB006 destino sin acceso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n06 OB006 destino sin acceso: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB006' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  -- ---------- OB007 / OB008: desactivar ----------
  BEGIN
    PERFORM obras_set_activo(v_obra, false);
    r := r || E'\n07 OB007 sin permiso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n07 OB007 sin permiso: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB007' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  PERFORM set_config('role', 'none', true);
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo = 'obras_desactivar' AND activo
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM obras_set_activo(v_nada, false);
    r := r || E'\n08 OB008 obra ajena o inexistente: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n08 OB008 obra ajena o inexistente: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB008' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  -- ---------- OB009: ficha fuera de alcance ----------
  -- Los casos 09 a 11 son los que cazaron el orden invertido: el log se
  -- escribía antes de confirmar que la fila existiera. Con
  -- `obras_personas_todas` el guard pasa con cualquier uuid, así que el INSERT
  -- moría contra la FK (23503) en vez de cortar con OB009 — y con una persona
  -- real pero inactiva no moría: anotaba un acceso que nunca ocurrió.
  PERFORM set_config('role', 'none', true);
  SELECT count(*) INTO v_accesos FROM obras_accesos_persona;
  PERFORM set_config('role', 'authenticated', true);

  BEGIN
    PERFORM * FROM obras_ficha_persona(v_nada);
    r := r || E'\n09 OB009 ficha sin acceso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n09 OB009 ficha sin acceso: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB009' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  PERFORM set_config('role', 'none', true);
  SELECT count(*) - v_accesos INTO n FROM obras_accesos_persona;
  r := r || E'\n10 sin acceso fantasma: ' || n ||
       CASE WHEN n = 0 THEN ' OK' ELSE ' *** FALLA — el log anota lo que no paso' END;

  -- Y la ficha que sí procede sigue dejando rastro: el arreglo no puede
  -- apagar el registro que justifica que esta función sea el único camino.
  SELECT id INTO v_persona_ok FROM obras_personas WHERE activo LIMIT 1;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM * FROM obras_ficha_persona(v_persona_ok);

  PERFORM set_config('role', 'none', true);
  SELECT count(*) - v_accesos INTO n FROM obras_accesos_persona;
  r := r || E'\n11 ficha valida sigue registrando: ' || n ||
       CASE WHEN n = 1 THEN ' OK' ELSE ' *** FALLA' END;
  PERFORM set_config('role', 'authenticated', true);

  -- ---------- OB010: auditoría ----------
  BEGIN
    PERFORM * FROM obras_auditoria_accesos(30);
    r := r || E'\n12 OB010 auditoria sin permiso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n12 OB010 auditoria sin permiso: ' || SQLSTATE ||
         CASE WHEN SQLSTATE = 'OB010' THEN ' OK' ELSE ' *** FALLA — ' || SQLERRM END;
  END;

  RAISE EXCEPTION E'RESULTADO obras_032:%', r;
END;
$test$;
