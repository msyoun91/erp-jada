-- Verificación de sql/089: transferir lo propio sin ver lo ajeno.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_087.sql.
--
-- El tester queda con los TRES permisos personales y NINGUNO de los globales:
-- es exactamente el usuario que sql/089 inventa.
--
-- Afirma:
--   A obra propia + obras_transferir_propias → transfiere
--   B obra ajena con el mismo permiso → OB003
--   C el checklist (`candidatos`) acompaña: abre la propia, rechaza la ajena
--   D persona propia migra; persona ajena → OB024
--   E empresa propia migra; empresa ajena → OB024
--   F el permiso personal NO ensancha la vista: la obra ajena sigue invisible
--   G sin ninguno de los seis permisos, lo propio tampoco se transfiere → OB003
--
-- Último resultado: 7/7 (2026-09-17).
--
-- Las verificaciones de dueño se leen desde la sesión del ENTRANTE: apenas la
-- transferencia se ejecuta, el saliente deja de ver la fila y el SELECT le
-- devolvería NULL — el caso pasaría o fallaría por la razón equivocada.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_ajena uuid;
  v_persona uuid; v_persona_ajena uuid;
  v_emp uuid; v_emp_ajena uuid;
  v_n int; v_duenio uuid; r text := '';
  v_rol text := current_setting('role', true);
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');

  -- El destino solo necesita `obras_ver` (OB006); acá además crea lo ajeno.
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear',
    'obras_transferir_propias','obras_personas_transferir_propias',
    'obras_empresas_transferir_propias')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);

  -- Lo ajeno, creado por el admin.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Kzrb Mwqt 089', 'casa', v_admin) RETURNING id INTO v_ajena;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Xdpl', 'Vnrgq', v_admin) RETURNING id INTO v_persona_ajena;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Jhtv Bzql SA', v_admin) RETURNING id INTO v_emp_ajena;

  -- Lo propio, creado por el tester.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Fqsn Dwxh 089', 'edificio', v_tester) RETURNING id INTO v_obra;
  INSERT INTO obras_personas (nombre, apellido, creado_por)
  VALUES ('Rmcz', 'Tgkwb', v_tester) RETURNING id INTO v_persona;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Pwld Cxvn SA', v_tester) RETURNING id INTO v_emp;

  -- F — antes de transferir nada: el permiso personal no muestra lo ajeno
  SELECT count(*) INTO v_n FROM obras WHERE id = v_ajena;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'F FALLA: el permiso personal dejó ver la obra ajena (%)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM obras_personas WHERE id = v_persona_ajena;
  IF v_n <> 0 THEN RAISE EXCEPTION 'F FALLA: se ve la persona ajena (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM obras_empresas WHERE id = v_emp_ajena;
  IF v_n <> 0 THEN RAISE EXCEPTION 'F FALLA: se ve la empresa ajena (%)', v_n; END IF;
  r := r || E'\nF OK  transferir lo propio no ensancha la vista';

  -- C — el checklist abre lo propio y rechaza lo ajeno. Sobre la propia lo que
  -- se afirma es que NO levanta: la obra recién creada no tiene contactos, así
  -- que la lista vacía es el resultado correcto.
  PERFORM obras_transferir_candidatos('obra', v_obra);
  BEGIN
    PERFORM obras_transferir_candidatos('obra', v_ajena);
    RAISE EXCEPTION 'C FALLA: el checklist abrió una obra ajena';
  EXCEPTION WHEN SQLSTATE 'OB003' THEN NULL;
  END;
  r := r || E'\nC OK  candidatos: abre la propia, rechaza la ajena';

  -- B — la obra ajena no se transfiere (y va antes de A: después de A el
  -- tester pierde la propia y el caso dejaría de ser comparable)
  BEGIN
    PERFORM obras_transferir(v_ajena, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[]);
    RAISE EXCEPTION 'B FALLA: transfirió una obra ajena';
  EXCEPTION WHEN SQLSTATE 'OB003' THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT responsable_id INTO v_duenio FROM obras WHERE id = v_ajena;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  IF v_duenio IS DISTINCT FROM v_admin THEN
    RAISE EXCEPTION 'B FALLA: la obra ajena cambió de dueño';
  END IF;
  r := r || E'\nB OK  obra ajena → OB003';

  -- D — persona: la propia migra, la ajena no
  BEGIN
    PERFORM obras_transferir_persona(v_persona_ajena, v_tester, false);
    RAISE EXCEPTION 'D FALLA: transfirió una persona ajena';
  EXCEPTION WHEN SQLSTATE 'OB024' THEN NULL;
  END;
  PERFORM obras_transferir_persona(v_persona, v_admin, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT creado_por INTO v_duenio FROM obras_personas WHERE id = v_persona;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  IF v_duenio IS DISTINCT FROM v_admin THEN
    RAISE EXCEPTION 'D FALLA: la persona propia no migró';
  END IF;
  r := r || E'\nD OK  persona: la propia migra, la ajena → OB024';

  -- E — empresa: ídem
  BEGIN
    PERFORM obras_transferir_empresa(v_emp_ajena, v_tester, ARRAY[]::uuid[], ARRAY[]::uuid[], false);
    RAISE EXCEPTION 'E FALLA: transfirió una empresa ajena';
  EXCEPTION WHEN SQLSTATE 'OB024' THEN NULL;
  END;
  PERFORM obras_transferir_empresa(v_emp, v_admin, ARRAY[]::uuid[], ARRAY[]::uuid[], false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT creado_por INTO v_duenio FROM obras_empresas WHERE id = v_emp;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  IF v_duenio IS DISTINCT FROM v_admin THEN
    RAISE EXCEPTION 'E FALLA: la empresa propia no migró';
  END IF;
  r := r || E'\nE OK  empresa: la propia migra, la ajena → OB024';

  -- A — la obra propia sí
  PERFORM obras_transferir(v_obra, v_admin, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT responsable_id INTO v_duenio FROM obras WHERE id = v_obra;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  IF v_duenio IS DISTINCT FROM v_admin THEN
    RAISE EXCEPTION 'A FALLA: la obra propia no se transfirió';
  END IF;
  r := r || E'\nA OK  obra propia + permiso personal → transfiere';

  -- G — sin ninguno de los seis permisos, ni lo propio. Sacar el permiso pide
  -- volver al rol de la sesión: `usuario_submodulos` no se escribe como
  -- `authenticated` y el UPDATE se perdería sin ruido, que haría pasar el caso
  -- por la razón equivocada.
  PERFORM set_config('role', COALESCE(v_rol, 'none'), true);
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id = v_tester
    AND submodulo_id IN (SELECT id FROM submodulos
                          WHERE codigo = 'obras_transferir_propias');
  PERFORM set_config('role', 'authenticated', true);

  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Lqvb Nzdt 089', 'casa', v_tester) RETURNING id INTO v_obra;
  BEGIN
    PERFORM obras_transferir(v_obra, v_admin, ARRAY[]::uuid[], ARRAY[]::uuid[]);
    RAISE EXCEPTION 'G FALLA: transfirió sin permiso';
  EXCEPTION WHEN SQLSTATE 'OB003' THEN NULL;
  END;
  r := r || E'\nG OK  sin permiso, lo propio tampoco → OB003';

  RAISE EXCEPTION E'obras_089 — 7/7\n%', r;
END;
$test$;
