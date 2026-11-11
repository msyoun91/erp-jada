-- Datos para `presupuestos.spec.ts` → mantener: el presupuesto "Mantener Zqx198", con la variante 1 y su copia, la variante 2,
-- en borrador, con dos ventanas del paquete de e2e/datos-opcionales.sql (que se corre antes). Copiar no tiene pantalla todavía
-- (las acciones de la ficha). Se corre una vez por MCP (`execute_sql`); si ya existe, no hace nada.

DO $$
DECLARE
  v_admin uuid := (SELECT id FROM usuarios WHERE nombre = 'Admin' AND activo);
  v_obra uuid := (SELECT id FROM obras WHERE nombre = 'Edificio Norte Zqx20218 A' AND activo);
  v_paquete uuid := (SELECT paquete_id FROM catalogo_versiones WHERE nombre = 'Zqx197 Ventana opcionales' AND estado = 'publicado');
  v_presupuesto uuid;
  v_version uuid;
  v_seccion uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM presupuestos WHERE nombre = 'Mantener Zqx198' AND activo) THEN
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  v_presupuesto := presupuestos_alta(v_obra, 'Mantener Zqx198', 'ARS', 21);
  SELECT id INTO v_version FROM presupuestos_versiones WHERE presupuesto_id = v_presupuesto;
  SELECT id INTO v_seccion FROM presupuestos_secciones WHERE version_id = v_version;
  INSERT INTO presupuestos_renglones (version_id, seccion_id, tipo, designacion, orden, paquete_id, entrada, opcionales)
  SELECT v_version, v_seccion, 'catalogo', d.designacion, d.orden, v_paquete,
         jsonb_build_object('variables', jsonb_build_object('ancho', d.ancho, 'alto', 1000),
                            'piezas', '{"Mosquitero": false, "Cajón": false, "Cortina": false}'::jsonb),
         '{}'
  FROM (VALUES ('V1', 1, 1200), ('V2', 2, 1500)) d(designacion, orden, ancho);
  PERFORM presupuestos_version_copiar(v_version, true);
  PERFORM set_config('role', 'postgres', true);
END $$;

SELECT v.numero, v.variante, v.estado, count(r.*) FILTER (WHERE r.origen_id IS NOT NULL) AS copiados
FROM presupuestos p
JOIN presupuestos_versiones v ON v.presupuesto_id = p.id
LEFT JOIN presupuestos_renglones r ON r.version_id = v.id AND r.activo
WHERE p.nombre = 'Mantener Zqx198' AND p.activo
GROUP BY v.numero, v.variante, v.estado ORDER BY v.numero;
