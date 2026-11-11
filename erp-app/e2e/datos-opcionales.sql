-- Datos para `presupuestos.spec.ts` → opcionales: un paquete a la venta con piezas opcionales y un servicio en % opcional.
-- Se corre una vez por MCP (`execute_sql`); si ya existe, no hace nada. Arma Zqx Técnica, aprueba Zqx Gerente.
-- "Zqx197 Ventana opcionales": ancho × alto, Marco de perfil, y opcionales Mosquitero (tela), Cajón y Cortina, que requiere
-- el Cajón. "Zqx197 Colocación": 10 % de los perfiles, paso 1, opcional. Como todo servicio opcional, se ofrece en toda
-- ventana (`catalogo_venta_formulario`), y suma solo donde hay perfiles Zqx197.

DO $$
DECLARE
  v_tecnica uuid := (SELECT id FROM usuarios WHERE email = 'zqx-tecnica@example.com');
  v_gerente uuid := (SELECT id FROM usuarios WHERE email = 'zqx-gerente@example.com');
  v_perfiles uuid;
  v_ventanas uuid;
  v_perfil uuid;
  v_tela uuid;
  v_manija uuid;
  v_version uuid;
  v_ancho uuid;
  v_marco uuid;
  v_mosquitero uuid;
  v_cajon uuid;
  v_cortina uuid;
  v_servicio uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM catalogo_versiones WHERE nombre = 'Zqx197 Ventana opcionales' AND estado = 'publicado') THEN
    RETURN;
  END IF;

  INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx197 Perfiles') RETURNING id INTO v_perfiles;
  INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx197 Ventanas') RETURNING id INTO v_ventanas;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_tecnica), true);
  PERFORM set_config('role', 'authenticated', true);
  v_perfil := catalogo_insumo_alta('Zqx197 Perfil', v_perfiles, 'mm', 1, NULL);
  v_tela := catalogo_insumo_alta('Zqx197 Tela', v_perfiles, 'm2', 1, NULL);
  v_manija := catalogo_insumo_alta('Zqx197 Manija', v_perfiles, 'u', 1, NULL);
  v_version := catalogo_paquete_alta('Zqx197 Ventana opcionales', v_ventanas);

  INSERT INTO catalogo_variables (version_id, nombre, orden, ingresa_vendedor, minimo, maximo, formula)
  VALUES (v_version, 'ancho', 1, true, 100, 5000, '1200') RETURNING id INTO v_ancho;
  INSERT INTO catalogo_variables (version_id, nombre, orden, ingresa_vendedor, minimo, maximo, formula)
  VALUES (v_version, 'alto', 2, true, 100, 5000, '1000');
  INSERT INTO catalogo_piezas (version_id, nombre, orden) VALUES (v_version, 'Marco', 1) RETURNING id INTO v_marco;
  INSERT INTO catalogo_piezas (version_id, nombre, orden, opcional) VALUES (v_version, 'Mosquitero', 2, true)
    RETURNING id INTO v_mosquitero;
  INSERT INTO catalogo_piezas (version_id, nombre, orden, opcional) VALUES (v_version, 'Cajón', 4, true)
    RETURNING id INTO v_cajon;
  INSERT INTO catalogo_piezas (version_id, nombre, orden, opcional, requiere_pieza_id)
  VALUES (v_version, 'Cortina', 3, true, v_cajon) RETURNING id INTO v_cortina;
  INSERT INTO catalogo_materiales (version_id, pieza_id, orden, tipo, insumo_id, medida, cantidad)
  VALUES (v_version, v_marco, 1, 'unico', v_perfil, 'ancho', '2');
  INSERT INTO catalogo_materiales (version_id, pieza_id, orden, tipo, insumo_id, ancho, alto)
  VALUES (v_version, v_mosquitero, 1, 'unico', v_tela, 'ancho', 'alto');
  INSERT INTO catalogo_materiales (version_id, pieza_id, orden, tipo, insumo_id, cantidad)
  VALUES (v_version, v_cajon, 1, 'unico', v_manija, '1');
  INSERT INTO catalogo_materiales (version_id, pieza_id, orden, tipo, insumo_id, cantidad)
  VALUES (v_version, v_cortina, 1, 'unico', v_manija, '2');
  INSERT INTO catalogo_casos (version_id, nombre, entrada) VALUES (v_version, 'base', '{}');
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, c.costo, 'ARS', v_gerente, now() - interval '1 day'
  FROM (VALUES (v_perfil, 50), (v_tela, 8000), (v_manija, 15000)) c(insumo, costo)
  JOIN catalogo_variantes va ON va.insumo_id = c.insumo AND va.color_id IS NULL;

  INSERT INTO catalogo_porcentajes DEFAULT VALUES RETURNING id INTO v_servicio;
  INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, opcional, de_baja, creado_por,
    created_at)
  VALUES (v_servicio, 'Zqx197 Colocación', 10, 1, ARRAY[v_perfiles], true, false, v_gerente, now() - interval '1 day');

  PERFORM set_config('role', 'authenticated', true);
  PERFORM catalogo_version_enviar(v_version);
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_gerente), true);
  PERFORM catalogo_version_aprobar(v_version);
  PERFORM set_config('role', 'postgres', true);
END $$;

SELECT v.nombre, v.estado FROM catalogo_versiones v WHERE v.nombre = 'Zqx197 Ventana opcionales';
