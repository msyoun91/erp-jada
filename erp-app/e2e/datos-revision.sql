-- Datos para `presupuestos.spec.ts` → Revisión técnica. Se corre una vez por MCP (`execute_sql`), después de
-- datos-opcionales.sql (usa su perfil y su categoría); lo que ya está, no lo toca.
-- "Zqx198 Ventana alta": ancho × alto y un Marco del perfil Zqx197; sobre 2000 de alto avisa "Muy alta para una hoja", sin
-- bloquear. Arma Zqx Técnica, aprueba Zqx Gerente. Tester 2 hace de Técnica: Revisión técnica, Autorizar alertas y la vista
-- Paquetes de Catálogo, para el despiece.

DO $$
DECLARE
  v_admin uuid := (SELECT id FROM usuarios WHERE nombre = 'Admin' AND activo);
  v_tester2 uuid := (SELECT id FROM usuarios WHERE nombre = 'Tester 2' AND activo);
  v_tecnica uuid := (SELECT id FROM usuarios WHERE email = 'zqx-tecnica@example.com');
  v_gerente uuid := (SELECT id FROM usuarios WHERE email = 'zqx-gerente@example.com');
  v_perfil uuid := (SELECT id FROM catalogo_insumos WHERE nombre = 'Zqx197 Perfil' AND activo);
  v_ventanas uuid := (SELECT id FROM catalogo_categorias WHERE tipo = 'paquete' AND nombre = 'Zqx197 Ventanas' AND activo);
  v_version uuid;
  v_alto uuid;
  v_marco uuid;
  v_codigo text;
BEGIN
  -- La vista antes que la función (US001).
  FOREACH v_codigo IN ARRAY ARRAY['presupuestos_revision', 'presupuestos_autorizar_tecnica', 'catalogo_paquetes'] LOOP
    IF NOT EXISTS (SELECT 1 FROM usuario_submodulos us JOIN submodulos s ON s.id = us.submodulo_id
                   WHERE us.usuario_id = v_tester2 AND s.codigo = v_codigo AND us.activo) THEN
      INSERT INTO usuario_submodulos (usuario_id, submodulo_id, otorgada_por)
      SELECT v_tester2, s.id, v_admin FROM submodulos s WHERE s.codigo = v_codigo;
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM catalogo_versiones WHERE nombre = 'Zqx198 Ventana alta' AND estado = 'publicado') THEN
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_tecnica), true);
  PERFORM set_config('role', 'authenticated', true);
  v_version := catalogo_paquete_alta('Zqx198 Ventana alta', v_ventanas);
  INSERT INTO catalogo_variables (version_id, nombre, orden, ingresa_vendedor, minimo, maximo, formula)
  VALUES (v_version, 'ancho', 1, true, 100, 5000, '1200');
  INSERT INTO catalogo_variables (version_id, nombre, orden, ingresa_vendedor, minimo, maximo, formula)
  VALUES (v_version, 'alto', 2, true, 100, 5000, '1000') RETURNING id INTO v_alto;
  INSERT INTO catalogo_piezas (version_id, nombre, orden) VALUES (v_version, 'Marco', 1) RETURNING id INTO v_marco;
  INSERT INTO catalogo_materiales (version_id, pieza_id, orden, tipo, insumo_id, medida, cantidad)
  VALUES (v_version, v_marco, 1, 'unico', v_perfil, 'ancho', '2');
  INSERT INTO catalogo_condiciones (version_id, variable_id, condicion, mensaje, bloquea)
  VALUES (v_version, v_alto, 'alto > 2000', 'Muy alta para una hoja', false);
  INSERT INTO catalogo_casos (version_id, nombre, entrada) VALUES (v_version, 'base', '{}');
  PERFORM catalogo_version_enviar(v_version);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_gerente), true);
  PERFORM catalogo_version_aprobar(v_version);
  PERFORM set_config('role', 'postgres', true);
END $$;

SELECT v.nombre, v.estado FROM catalogo_versiones v WHERE v.nombre = 'Zqx198 Ventana alta';
