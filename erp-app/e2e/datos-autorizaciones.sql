-- Datos para `presupuestos.spec.ts` → antes de publicar. Se corre una vez por MCP (`execute_sql`); lo que ya está, no lo toca.
-- Configuración de prueba, tope 10 % y plazo 15 días (decisión del usuario, 2026-11-11), hasta que gerencia cargue la suya
-- en Configuración: sin ella, `presupuestos_version_revisar` frena todo. Tester hace de vendedor, con `presupuestos_ver` y
-- `presupuestos_armar`: arma en las obras que trabaja y no autoriza. Autoriza Admin, con `presupuestos_administrar`.

DO $$
DECLARE
  v_admin uuid := (SELECT id FROM usuarios WHERE nombre = 'Admin' AND activo);
  v_tester uuid := (SELECT id FROM usuarios WHERE nombre = 'Tester' AND activo);
  v_codigo text;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  IF NOT EXISTS (SELECT 1 FROM presupuestos_configuracion WHERE activo) THEN
    INSERT INTO presupuestos_configuracion (tope_descuento, plazo_dias) VALUES (10, 15);
  END IF;

  -- La vista antes que la función (US001).
  FOREACH v_codigo IN ARRAY ARRAY['presupuestos_ver', 'presupuestos_armar'] LOOP
    IF NOT EXISTS (SELECT 1 FROM usuario_submodulos us JOIN submodulos s ON s.id = us.submodulo_id
                   WHERE us.usuario_id = v_tester AND s.codigo = v_codigo AND us.activo) THEN
      INSERT INTO usuario_submodulos (usuario_id, submodulo_id, otorgada_por)
      SELECT v_tester, s.id, v_admin FROM submodulos s WHERE s.codigo = v_codigo;
    END IF;
  END LOOP;
END $$;
