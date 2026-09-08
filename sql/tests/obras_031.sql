-- Verificación de lo que agrega sql/031: las dos funciones de auditoría, el
-- aviso de duplicados que ya no depende de la localidad, la exclusión de la
-- propia fila al editar, y el guardado atómico del referente.
--
-- Mismo andamiaje que rls_obras.sql: DO que termina en RAISE EXCEPTION, así
-- que la transacción entera se revierte y no persiste ni un dato ni un
-- permiso. Los resultados salen en el mensaje del error.
--
-- **Depende de los datos de `sql/seeds/obras_dummy.sql`.** Los ids fijos del
-- seed son lo que hace que los casos 06 a 11 puedan afirmar algo concreto:
-- el par de obras casi duplicadas en localidades escritas distinto, el par de
-- empresas, y el referente que ya existe con 3.50%.
--
-- El setup apaga `obras_auditoria` antes de empezar por la misma razón que
-- rls_obras.sql apaga todo: el caso 01 afirma que sin el submódulo la función
-- corta, y el usuario real lo tiene asignado.
--
-- Último resultado: 12/12.

DO $test$
DECLARE
  v_admin  uuid := '015fa985-fe21-4434-b3c5-7ac78732d765';
  v_tester uuid := '48b90421-a639-4637-b361-501fa7e1a1a0';
  n int; t text; r text := ''; v_id uuid;
BEGIN
  UPDATE usuario_submodulos SET activo = false
  WHERE usuario_id IN (v_admin, v_tester)
    AND submodulo_id = (SELECT id FROM submodulos WHERE codigo = 'obras_auditoria' AND activo);

  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  -- ---------- La auditoría es un permiso, no una pantalla escondida ----------
  BEGIN
    PERFORM * FROM obras_auditoria_accesos(30);
    r := r || E'\n01 auditoria sin permiso: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n01 auditoria sin permiso: cortado (' || SQLERRM || ') OK';
  END;

  PERFORM set_config('role', 'none', true);
  INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
  SELECT v_admin, id FROM submodulos WHERE codigo = 'obras_auditoria' AND activo
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);

  SELECT count(*) INTO n FROM obras_auditoria_accesos(30);
  r := r || E'\n02 accesos ultimos 30 dias: ' || n ||
       CASE WHEN n = 7 THEN ' OK' ELSE ' *** FALLA (el seed siembra 7)' END;

  SELECT count(*) INTO n FROM obras_auditoria_transferencias(90);
  r := r || E'\n03 transferencias ultimos 90 dias: ' || n ||
       CASE WHEN n = 3 THEN ' OK' ELSE ' *** FALLA (el seed siembra 3)' END;

  SELECT persona || ' abierta por ' || usuario INTO t FROM obras_auditoria_accesos(30) LIMIT 1;
  r := r || E'\n04 forma de la fila: ' || t;

  -- La pantalla que vigila el acceso al contacto no puede servir contacto.
  SELECT pg_get_function_result(p.oid) INTO t
  FROM pg_proc p WHERE p.proname = 'obras_auditoria_accesos';
  r := r || E'\n05 la auditoria no devuelve contacto: ' ||
       CASE WHEN t NOT ILIKE '%telefono%' AND t NOT ILIKE '%email%' AND t NOT ILIKE '%whatsapp%'
            THEN 'OK' ELSE '*** FALLA — ' || t END;

  -- ---------- La localidad ya no esconde un duplicado ----------
  -- La obra de Tester está en "Devoto" y la de Admin en "Villa Devoto".
  SELECT count(*) INTO n
  FROM obras_buscar_duplicados_obra('Edificio Nogoya 3400', NULL, 'Devoto')
  WHERE es_mia = false AND obra_id IS NULL AND responsable = 'Tester';
  r := r || E'\n06 aviso ciego con localidad escrita distinta: ' || n ||
       CASE WHEN n = 1 THEN ' OK' ELSE ' *** FALLA — el filtro volvio a esconderla' END;

  -- ---------- Al editar, la fila no se encuentra a si misma ----------
  SELECT count(*) INTO n FROM obras_buscar_duplicados_obra(
    'Edificio Nogoya 3400', NULL, 'Devoto', 'b0000000-0000-4000-a000-000000000001');
  r := r || E'\n07 excluyendo la propia obra: ' || n ||
       CASE WHEN n = 1 THEN ' OK (queda la ajena)' ELSE ' *** FALLA' END;

  SELECT count(*) INTO n FROM obras_buscar_duplicados_empresa(
    'Constructora del Plata S.A.', NULL, 'e0000000-0000-4000-a000-000000000001');
  r := r || E'\n08 excluyendo la propia empresa: ' || n ||
       CASE WHEN n = 1 THEN ' OK (queda la copia)' ELSE ' *** FALLA' END;

  -- ---------- Referente: alta y cambio por el mismo camino ----------
  SELECT obras_guardar_referente(
    'b0000000-0000-4000-a000-000000000003', 'c0000000-0000-4000-a000-000000000006', 2.25, 'alta') INTO v_id;
  r := r || E'\n09 alta de referente: ' || CASE WHEN v_id IS NULL THEN '*** FALLA' ELSE 'OK' END;

  PERFORM obras_guardar_referente(
    'b0000000-0000-4000-a000-000000000001', 'c0000000-0000-4000-a000-000000000001', 4.25, 'renegociado');
  SELECT porcentaje_comision::text || ' / ' || observaciones INTO t
  FROM obras_obra_referente WHERE id = 'a4000000-0000-4000-a000-000000000001';
  r := r || E'\n10 upsert sobre el referente que ya estaba: ' || t ||
       CASE WHEN t = '4.25 / renegociado' THEN ' OK' ELSE ' *** FALLA' END;

  SELECT count(*) INTO n FROM obras_obra_referente
  WHERE obra_id = 'b0000000-0000-4000-a000-000000000001'
    AND persona_id = 'c0000000-0000-4000-a000-000000000001' AND activo;
  r := r || E'\n11 sin fila duplicada: ' || n ||
       CASE WHEN n = 1 THEN ' OK' ELSE ' *** FALLA' END;

  -- La función es SECURITY INVOKER: la autoridad sigue en la policy.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_tester)::text, true);
  BEGIN
    PERFORM obras_guardar_referente(
      'b0000000-0000-4000-a000-000000000001', 'c0000000-0000-4000-a000-000000000001', 99.00, NULL);
    r := r || E'\n12 Tester toca la comision de una obra ajena: PASO *** revisar';
  EXCEPTION WHEN others THEN
    r := r || E'\n12 Tester toca la comision de una obra ajena: cortado (' || SQLERRM || ') OK';
  END;

  RAISE EXCEPTION E'RESULTADO obras_031:%', r;
END;
$test$;
