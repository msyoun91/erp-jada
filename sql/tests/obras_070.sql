-- Verificación de sql/070: en `obras_vinculos_de_obra`, el nombre de la
-- empresa de una persona vinculada (`detalle`) sale solo para quien ve esa
-- empresa, el responsable o `obras_transferir`. `empresa_id` sale siempre.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_052.sql.
--
-- Afirma:
--   A  persona tildada, empresa NO tildada → el receptor ve la persona sin
--      `detalle`; `empresa_id` se conserva (editar el vínculo no lo borra)
--   B  el dueño tilda también la empresa → el receptor ve el nombre
--   C  el responsable ve la empresa privada del receptor en la persona que
--      sumó el receptor (lo de sql/051 sigue)
--   D  el receptor ve la empresa de su propia persona (es suya)
--
-- Último resultado: 4/4.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  v_obra uuid; v_ea uuid; v_pa uuid; v_et uuid; v_pt uuid;
  v_detalle text; v_empresa uuid; v_n int;
  r text := '';
BEGIN
  SET CONSTRAINTS ALL IMMEDIATE;

  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id IN (SELECT id FROM submodulos WHERE modulo = 'obras');
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear','obras_compartido')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_tester, id FROM submodulos WHERE codigo IN
   ('obras_ver','obras_crear','obras_vincular','obras_empresas','obras_empresas_crear',
    'obras_personas','obras_personas_crear')
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- Admin: obra con una empresa y una persona que la representa.
  INSERT INTO obras (nombre, tipo, responsable_id)
  VALUES ('Obra Plokij del test 070', 'edificio', v_admin) RETURNING id INTO v_obra;
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Eadm Empresa 070', v_admin) RETURNING id INTO v_ea;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Padm', 'Mnb', '1140000701', v_admin) RETURNING id INTO v_pa;
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles)
  VALUES (v_obra, v_ea, ARRAY['constructora']::rol_empresa[]);
  INSERT INTO obras_obra_persona (obra_id, persona_id, empresa_id, roles)
  VALUES (v_obra, v_pa, v_ea, ARRAY['compras']::rol_persona[]);

  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[]::uuid[], ARRAY[v_pa]);

  -- A
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT count(*), max(v.detalle), max(v.empresa_id::text)::uuid
    INTO v_n, v_detalle, v_empresa
    FROM obras_vinculos_de_obra(v_obra) v WHERE v.entidad_id = v_pa;
  IF v_n <> 1 THEN RAISE EXCEPTION 'A FALLA: el receptor no ve la persona tildada (%)', v_n; END IF;
  IF v_detalle IS NOT NULL THEN
    RAISE EXCEPTION 'A FALLA: el receptor leyó el nombre de la empresa no compartida (%)', v_detalle;
  END IF;
  IF v_empresa IS DISTINCT FROM v_ea THEN
    RAISE EXCEPTION 'A FALLA: empresa_id no vino (%)', v_empresa;
  END IF;
  r := r || E'\nA OK  empresa no tildada: la persona sale sin detalle, con empresa_id';

  -- B
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  PERFORM obras_compartir_obra(v_obra, v_tester, ARRAY[v_ea], ARRAY[v_pa]);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  SELECT v.detalle, v.empresa_id INTO v_detalle, v_empresa
    FROM obras_vinculos_de_obra(v_obra) v WHERE v.entidad_id = v_pa;
  IF v_detalle IS DISTINCT FROM 'Eadm Empresa 070' OR v_empresa IS DISTINCT FROM v_ea THEN
    RAISE EXCEPTION 'B FALLA: con la empresa tildada no salió (%, %)', v_detalle, v_empresa;
  END IF;
  r := r || E'\nB OK  empresa tildada: el nombre sale';

  -- Receptor: suma su persona con su empresa privada.
  INSERT INTO obras_empresas (razon_social, creado_por)
  VALUES ('Etst Empresa 070', v_tester) RETURNING id INTO v_et;
  INSERT INTO obras_personas (nombre, apellido, telefono, creado_por)
  VALUES ('Ptst', 'Mnb', '1140000702', v_tester) RETURNING id INTO v_pt;
  INSERT INTO obras_obra_persona (obra_id, persona_id, empresa_id, roles)
  VALUES (v_obra, v_pt, v_et, ARRAY['compras']::rol_persona[]);

  -- D
  SELECT v.detalle INTO v_detalle
    FROM obras_vinculos_de_obra(v_obra) v WHERE v.entidad_id = v_pt;
  IF v_detalle IS DISTINCT FROM 'Etst Empresa 070' THEN
    RAISE EXCEPTION 'D FALLA: el receptor no ve la empresa de su persona (%)', v_detalle;
  END IF;
  r := r || E'\nD OK  el receptor ve la empresa de su propia persona';

  -- C
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  SELECT v.detalle, v.empresa_id INTO v_detalle, v_empresa
    FROM obras_vinculos_de_obra(v_obra) v WHERE v.entidad_id = v_pt;
  IF v_detalle IS DISTINCT FROM 'Etst Empresa 070' OR v_empresa IS DISTINCT FROM v_et THEN
    RAISE EXCEPTION 'C FALLA: el responsable no ve la empresa privada del receptor (%, %)', v_detalle, v_empresa;
  END IF;
  r := r || E'\nC OK  el responsable ve la empresa que sumó el receptor';

  RAISE EXCEPTION E'--- obras_070: 4/4 ---%', r;
END;
$test$;
