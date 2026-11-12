-- Test de sql/portal/002: los tipos de cambio en el portal. Termina en RAISE EXCEPTION con "N / M ok": no deja nada.
DO $$
DECLARE
  v_ok int := 0;
  v_total int := 0;
  v_fallas text[] := '{}';
  v_n int;
BEGIN
  UPDATE portal_monedas SET activo = false WHERE activo;

  -- 1. Alta: lo que llega queda vigente
  v_total := v_total + 1;
  PERFORM portal_monedas_guardar('[{"moneda":"ARS","valor":1,"fecha":"2000-01-01T00:00:00Z","referencia":true},
    {"moneda":"USD_OFICIAL","valor":1450,"fecha":"2026-11-12T10:00:00Z","referencia":true},
    {"moneda":"EUR","valor":1600,"fecha":"2026-11-12T10:00:00Z","referencia":false}]');
  IF (SELECT count(*) FROM portal_monedas_leer()) = 3 THEN v_ok := v_ok + 1; ELSE v_fallas := v_fallas || 'alta'; END IF;

  -- 2. Lo mismo otra vez no crea filas
  v_total := v_total + 1;
  SELECT count(*) INTO v_n FROM portal_monedas;
  PERFORM portal_monedas_guardar('[{"moneda":"ARS","valor":1,"fecha":"2000-01-01T00:00:00Z","referencia":true},
    {"moneda":"USD_OFICIAL","valor":1450,"fecha":"2026-11-12T10:00:00Z","referencia":true},
    {"moneda":"EUR","valor":1600,"fecha":"2026-11-12T10:00:00Z","referencia":false}]');
  IF (SELECT count(*) FROM portal_monedas) = v_n THEN v_ok := v_ok + 1; ELSE v_fallas := v_fallas || 'repetir crea filas'; END IF;

  -- 3. Un valor nuevo reemplaza; lo que no viene se apaga; un cambio de referencia también reemplaza
  v_total := v_total + 1;
  PERFORM portal_monedas_guardar('[{"moneda":"ARS","valor":1,"fecha":"2000-01-01T00:00:00Z","referencia":false},
    {"moneda":"USD_OFICIAL","valor":1460,"fecha":"2026-11-12T11:00:00Z","referencia":true}]');
  IF (SELECT valor FROM portal_monedas_leer() WHERE moneda = 'USD_OFICIAL') = 1460
     AND NOT (SELECT referencia FROM portal_monedas_leer() WHERE moneda = 'ARS')
     AND NOT EXISTS (SELECT 1 FROM portal_monedas_leer() WHERE moneda = 'EUR') THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || 'reemplazo'; END IF;

  -- 4. Lo inválido falla: no es lista, valor 0, moneda rara
  v_total := v_total + 1;
  v_n := 0;
  BEGIN PERFORM portal_monedas_guardar('{}'); EXCEPTION WHEN invalid_parameter_value THEN v_n := v_n + 1; END;
  BEGIN PERFORM portal_monedas_guardar('[{"moneda":"EUR","valor":0,"fecha":"2026-11-12T10:00:00Z","referencia":true}]');
  EXCEPTION WHEN check_violation THEN v_n := v_n + 1; END;
  BEGIN PERFORM portal_monedas_guardar('[{"moneda":"<b>","valor":1,"fecha":"2026-11-12T10:00:00Z","referencia":true}]');
  EXCEPTION WHEN check_violation THEN v_n := v_n + 1; END;
  IF v_n = 3 THEN v_ok := v_ok + 1; ELSE v_fallas := v_fallas || ('inválidos: ' || v_n || ' / 3'); END IF;

  -- 5. anon lee y no escribe; nadie toca la tabla directo
  v_total := v_total + 1;
  IF has_function_privilege('anon', 'portal_monedas_leer()', 'EXECUTE')
     AND NOT has_function_privilege('anon', 'portal_monedas_guardar(jsonb)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'portal_monedas_guardar(jsonb)', 'EXECUTE')
     AND NOT has_table_privilege('anon', 'portal_monedas', 'SELECT')
     AND has_function_privilege('service_role', 'portal_monedas_guardar(jsonb)', 'EXECUTE')
  THEN v_ok := v_ok + 1; ELSE v_fallas := v_fallas || 'grants'; END IF;

  RAISE EXCEPTION '% / % ok%', v_ok, v_total,
    CASE WHEN cardinality(v_fallas) > 0 THEN ' — ' || array_to_string(v_fallas, ' · ') ELSE '' END;
END;
$$;
