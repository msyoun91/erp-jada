-- Datos para `presupuestos.spec.ts` → la calculadora de venta: un paquete a la venta con un servicio que tiene mínimo.
-- Se corre una vez por MCP (`execute_sql`); si ya existe, no hace nada. Arma Zqx Técnica, aprueba Zqx Gerente.
-- "Zqx199 Ventana con mínimo": ancho × alto y un Marco de perfil. "Zqx199 Colocación": 10 % de los perfiles, paso 1, con
-- mínimo de $ 50.000 por presupuesto: una ventana sola no lo alcanza.

DO $$
DECLARE
  v_tecnica uuid := (SELECT id FROM usuarios WHERE email = 'zqx-tecnica@example.com');
  v_gerente uuid := (SELECT id FROM usuarios WHERE email = 'zqx-gerente@example.com');
  v_perfiles uuid;
  v_ventanas uuid;
  v_perfil uuid;
  v_version uuid;
  v_marco uuid;
  v_servicio uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM catalogo_versiones WHERE nombre = 'Zqx199 Ventana con mínimo' AND estado = 'publicado') THEN
    RETURN;
  END IF;

  INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx199 Perfiles') RETURNING id INTO v_perfiles;
  INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx199 Ventanas') RETURNING id INTO v_ventanas;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_tecnica), true);
  PERFORM set_config('role', 'authenticated', true);
  v_perfil := catalogo_insumo_alta('Zqx199 Perfil', v_perfiles, 'mm', 1, NULL);
  v_version := catalogo_paquete_alta('Zqx199 Ventana con mínimo', v_ventanas);

  INSERT INTO catalogo_variables (version_id, nombre, orden, ingresa_vendedor, minimo, maximo, formula)
  VALUES (v_version, 'ancho', 1, true, 100, 5000, '1200');
  INSERT INTO catalogo_variables (version_id, nombre, orden, ingresa_vendedor, minimo, maximo, formula)
  VALUES (v_version, 'alto', 2, true, 100, 5000, '1000');
  INSERT INTO catalogo_piezas (version_id, nombre, orden) VALUES (v_version, 'Marco', 1) RETURNING id INTO v_marco;
  INSERT INTO catalogo_materiales (version_id, pieza_id, orden, tipo, insumo_id, medida, cantidad)
  VALUES (v_version, v_marco, 1, 'unico', v_perfil, 'ancho', '2');
  INSERT INTO catalogo_casos (version_id, nombre, entrada) VALUES (v_version, 'base', '{}');
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, 50, 'ARS', v_gerente, now() - interval '1 day'
  FROM catalogo_variantes va WHERE va.insumo_id = v_perfil AND va.color_id IS NULL;

  INSERT INTO catalogo_porcentajes DEFAULT VALUES RETURNING id INTO v_servicio;
  INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda,
    minimo_por, opcional, de_baja, creado_por, created_at)
  VALUES (v_servicio, 'Zqx199 Colocación', 10, 1, ARRAY[v_perfiles], 50000, 'ARS', 'presupuesto', false, false, v_gerente,
    now() - interval '1 day');

  PERFORM set_config('role', 'authenticated', true);
  PERFORM catalogo_version_enviar(v_version);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_gerente), true);
  PERFORM catalogo_version_aprobar(v_version);
  PERFORM set_config('role', 'postgres', true);
END $$;

SELECT v.nombre, v.estado FROM catalogo_versiones v WHERE v.nombre = 'Zqx199 Ventana con mínimo';
