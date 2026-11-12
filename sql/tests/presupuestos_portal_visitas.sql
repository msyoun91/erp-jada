-- Test de sql/203: visitas leídas del portal, el aviso de la primera visita y las monedas que se mandan.
-- Corre en una transacción que termina en RAISE EXCEPTION con "N / M ok": no deja nada.
DO $$
DECLARE
  v_ok int := 0;
  v_total int := 0;
  v_fallas text[] := '{}';
  v_link uuid;
  v_otro uuid;
  v_pres uuid;
  v_resp uuid;
  v_v1 uuid;
  v_v2 uuid;
  v_n int;
  v_j jsonb;
  r record;
BEGIN
  SELECT l.id, l.presupuesto_id, o.responsable_id INTO v_link, v_pres, v_resp
  FROM presupuestos_links l
  JOIN presupuestos p ON p.id = l.presupuesto_id
  JOIN obras o ON o.id = p.obra_id
  WHERE l.activo AND o.responsable_id IS NOT NULL
    AND (SELECT count(*) FROM presupuestos_versiones v WHERE v.presupuesto_id = p.id) >= 2
    AND NOT EXISTS (SELECT 1 FROM presupuestos_links_visitas x WHERE x.link_id = l.id)
  LIMIT 1;
  SELECT id INTO v_v1 FROM presupuestos_versiones WHERE presupuesto_id = v_pres AND numero = 1;
  SELECT id INTO v_v2 FROM presupuestos_versiones WHERE presupuesto_id = v_pres AND numero = 2;

  -- 1. Sin copia confirmada, el link no se lee
  v_total := v_total + 1;
  UPDATE presupuestos_links SET copia_revision = NULL, copia_en = NULL, copia_versiones = NULL WHERE id = v_link;
  IF NOT EXISTS (SELECT 1 FROM presupuestos_portal_links() WHERE link_id = v_link) THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || 'links: sin copia aparece'; END IF;

  -- 2. Con copia, sí, con su llave
  v_total := v_total + 1;
  UPDATE presupuestos_links SET copia_revision = 1, copia_en = now(), copia_versiones = '{1,2}' WHERE id = v_link;
  IF EXISTS (SELECT 1 FROM presupuestos_portal_links() p JOIN presupuestos_links l ON l.id = p.link_id
             WHERE p.link_id = v_link AND p.llave = l.llave) THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || 'links: con copia no aparece'; END IF;

  -- 3. Primera visita de la v1: guarda y avisa al responsable, una vez
  v_total := v_total + 1;
  PERFORM presupuestos_portal_visitas(jsonb_build_array(jsonb_build_object(
    'link', v_link, 'version', 1, 'visitas', 2, 'dispositivos', 1,
    'primera', '2026-11-10T10:00:00Z', 'ultima', '2026-11-10T12:00:00Z')));
  SELECT count(*) INTO v_n FROM usuario_notificaciones
  WHERE tipo = 'presupuesto_visto' AND entidad_id = v_v1 AND usuario_id = v_resp AND activo;
  IF v_n = 1 AND EXISTS (SELECT 1 FROM presupuestos_links_visitas WHERE link_id = v_link AND version_id = v_v1
                         AND visitas = 2 AND dispositivos = 1) THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || ('primera visita: avisos ' || v_n); END IF;

  -- 4. Otra lectura con más visitas: pisa la cuenta, no avisa de nuevo
  v_total := v_total + 1;
  PERFORM presupuestos_portal_visitas(jsonb_build_array(jsonb_build_object(
    'link', v_link, 'version', 1, 'visitas', 5, 'dispositivos', 3,
    'primera', '2026-11-10T10:00:00Z', 'ultima', '2026-11-11T21:40:00Z')));
  SELECT count(*) INTO v_n FROM usuario_notificaciones WHERE tipo = 'presupuesto_visto' AND entidad_id = v_v1;
  IF v_n = 1 AND (SELECT visitas FROM presupuestos_links_visitas WHERE link_id = v_link AND version_id = v_v1 AND activo) = 5
     AND (SELECT count(*) FROM presupuestos_links_visitas WHERE link_id = v_link) = 1 THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || ('relectura: avisos ' || v_n); END IF;

  -- 5. Una versión que no es del presupuesto no entra
  v_total := v_total + 1;
  PERFORM presupuestos_portal_visitas(jsonb_build_array(jsonb_build_object(
    'link', v_link, 'version', 999, 'visitas', 1, 'dispositivos', 1,
    'primera', '2026-11-10T10:00:00Z', 'ultima', '2026-11-10T10:00:00Z')));
  IF (SELECT count(*) FROM presupuestos_links_visitas WHERE link_id = v_link) = 1 THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || 'versión ajena entró'; END IF;

  -- 6. La v1 vista por otro link (el anulado) no avisa de nuevo; la v2, sí
  v_total := v_total + 1;
  INSERT INTO presupuestos_links (presupuesto_id, activo) VALUES (v_pres, false) RETURNING id INTO v_otro;
  PERFORM presupuestos_portal_visitas(jsonb_build_array(
    jsonb_build_object('link', v_otro, 'version', 1, 'visitas', 1, 'dispositivos', 1,
                       'primera', '2026-11-09T10:00:00Z', 'ultima', '2026-11-09T10:00:00Z'),
    jsonb_build_object('link', v_link, 'version', 2, 'visitas', 1, 'dispositivos', 1,
                       'primera', '2026-11-12T10:00:00Z', 'ultima', '2026-11-12T10:00:00Z')));
  IF (SELECT count(*) FROM usuario_notificaciones WHERE tipo = 'presupuesto_visto' AND entidad_id = v_v1) = 1
     AND (SELECT count(*) FROM usuario_notificaciones WHERE tipo = 'presupuesto_visto' AND entidad_id = v_v2) = 1
     AND (SELECT count(*) FROM presupuestos_links_visitas WHERE version_id = v_v1) = 2 THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || 'otro link: avisó de nuevo o no guardó'; END IF;

  -- 7. Lo inválido falla: dispositivos > visitas
  v_total := v_total + 1;
  BEGIN
    PERFORM presupuestos_portal_visitas(jsonb_build_array(jsonb_build_object(
      'link', v_link, 'version', 2, 'visitas', 1, 'dispositivos', 4,
      'primera', '2026-11-12T10:00:00Z', 'ultima', '2026-11-12T10:00:00Z')));
    v_fallas := v_fallas || 'dispositivos > visitas entró';
  EXCEPTION WHEN check_violation THEN v_ok := v_ok + 1;
  END;

  -- 8. El aviso lo lee el responsable: "P-0142 · v1", al presupuesto
  v_total := v_total + 1;
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_resp, 'role', 'authenticated')::text, true);
  SELECT * INTO r FROM presupuestos_avisos(ARRAY(
    SELECT id FROM usuario_notificaciones WHERE tipo = 'presupuesto_visto' AND entidad_id = v_v1));
  IF r.destino = 'presupuesto' AND r.destino_id = v_pres AND r.etiqueta LIKE '% · v1' THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || ('aviso: ' || coalesce(r.etiqueta, 'NULL')); END IF;

  -- 9. Las visitas las lee quien ve el presupuesto
  v_total := v_total + 1;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM presupuestos_links_visitas WHERE link_id = v_link;
  RESET ROLE;
  IF v_n = 2 THEN v_ok := v_ok + 1; ELSE v_fallas := v_fallas || ('RLS: responsable lee ' || v_n); END IF;

  -- 10. Monedas: ARS en 1, cada una una vez, la referencia según la configuración
  v_total := v_total + 1;
  v_j := presupuestos_portal_monedas();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_j) x WHERE x->>'moneda' = 'ARS' AND (x->>'valor')::numeric = 1)
     AND (SELECT count(*) FROM jsonb_array_elements(v_j)) = (SELECT count(DISTINCT x->>'moneda') FROM jsonb_array_elements(v_j) x)
     AND (SELECT coalesce(array_agg((x->>'moneda')::moneda ORDER BY x->>'moneda'), '{}') FROM jsonb_array_elements(v_j) x
          WHERE (x->>'referencia')::boolean)
       = (SELECT coalesce(array_agg(m ORDER BY m::text), '{}') FROM unnest(coalesce(
            (SELECT monedas_referencia FROM presupuestos_configuracion WHERE activo), '{ARS,USD_OFICIAL}')) m
          WHERE m = 'ARS' OR EXISTS (SELECT 1 FROM monedas_hoy() h WHERE h.moneda = m AND h.valor IS NOT NULL))
  THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || ('monedas: ' || v_j::text); END IF;

  -- 11. Nada de esto es de anon ni de authenticated
  v_total := v_total + 1;
  IF NOT has_function_privilege('authenticated', 'presupuestos_portal_visitas(jsonb)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'presupuestos_portal_links()', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'presupuestos_portal_monedas()', 'EXECUTE')
     AND NOT has_function_privilege('anon', 'presupuestos_portal_links()', 'EXECUTE')
     AND NOT has_table_privilege('authenticated', 'presupuestos_links_visitas', 'INSERT')
  THEN v_ok := v_ok + 1;
  ELSE v_fallas := v_fallas || 'grants'; END IF;

  RAISE EXCEPTION '% / % ok%', v_ok, v_total,
    CASE WHEN cardinality(v_fallas) > 0 THEN ' — ' || array_to_string(v_fallas, ' · ') ELSE '' END;
END;
$$;
