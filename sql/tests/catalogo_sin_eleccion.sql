-- El valor de una variable según un material, para cuando este queda sin elección (sql/170).
-- Termina en RAISE: revierte todo y devuelve "N / M ok".
DO $$
DECLARE
  v_insumo uuid := (SELECT id FROM catalogo_insumos WHERE activo AND unidad = 'u' LIMIT 1);
  v_paquete uuid;
  v_version uuid;
  v_pieza uuid;
  v_opcional uuid;
  v_mat uuid;
  v_mat_op uuid;
  v_opc uuid;
  v_opc_op uuid;
  v_var uuid;
  v_suelta uuid;
  v_ok int := 0;
  v_total int := 0;
  v_fallos text[] := '{}';
  r record;
BEGIN
  INSERT INTO catalogo_paquetes DEFAULT VALUES RETURNING id INTO v_paquete;
  INSERT INTO catalogo_versiones (paquete_id, nombre, categoria_id)
    VALUES (v_paquete, 'Zqx170', (SELECT id FROM catalogo_categorias WHERE tipo = 'paquete' AND activo LIMIT 1))
    RETURNING id INTO v_version;
  INSERT INTO catalogo_piezas (version_id, nombre) VALUES (v_version, 'P') RETURNING id INTO v_pieza;
  INSERT INTO catalogo_piezas (version_id, nombre, opcional) VALUES (v_version, 'Opc', true) RETURNING id INTO v_opcional;
  CREATE TEMP TABLE casos (nombre text, esperado text, real text) ON COMMIT DROP;

  INSERT INTO catalogo_materiales (version_id, pieza_id, tipo, nombre, sin_eleccion)
    VALUES (v_version, v_pieza, 'elige_vendedor', 'Herraje', true) RETURNING id INTO v_mat;
  INSERT INTO catalogo_opciones (version_id, material_id, insumo_id) VALUES (v_version, v_mat, v_insumo) RETURNING id INTO v_opc;
  INSERT INTO catalogo_variables (version_id, nombre, segun_material_id) VALUES (v_version, 'd', v_mat) RETURNING id INTO v_var;
  INSERT INTO catalogo_variables_valores (version_id, variable_id, opcion_id, formula) VALUES (v_version, v_var, v_opc, '20');

  INSERT INTO casos SELECT '01 sin el valor frena', 'd: falta el valor para cuando Herraje queda sin elección', problema
    FROM catalogo_version_referencias(v_version) WHERE nodo = 'v:' || v_var AND problema IS NOT NULL;

  UPDATE catalogo_variables SET formula = '5 + 1' WHERE id = v_var;
  INSERT INTO casos SELECT '02 con el valor no frena', '0', count(*)::text
    FROM catalogo_version_referencias(v_version) WHERE nodo = 'v:' || v_var AND problema IS NOT NULL;

  INSERT INTO casos SELECT '03 sin elegir vale la fórmula', '6', x->>'valor'
    FROM jsonb_array_elements(catalogo_despiece(v_version, '{"elecciones": {"P": {"Herraje": null}}}')->'variables') x
    WHERE x->>'nombre' = 'd';
  INSERT INTO casos SELECT '04 elegida vale la de la opción', '20', x->>'valor'
    FROM jsonb_array_elements(catalogo_despiece(v_version,
      jsonb_build_object('elecciones', jsonb_build_object('P', jsonb_build_object('Herraje', v_insumo))))->'variables') x
    WHERE x->>'nombre' = 'd';

  INSERT INTO catalogo_materiales (version_id, pieza_id, tipo, nombre)
    VALUES (v_version, v_opcional, 'elige_vendedor', 'Tir') RETURNING id INTO v_mat_op;
  INSERT INTO catalogo_opciones (version_id, material_id, insumo_id, predeterminada) VALUES (v_version, v_mat_op, v_insumo, true) RETURNING id INTO v_opc_op;
  INSERT INTO catalogo_variables (version_id, nombre, segun_material_id, formula) VALUES (v_version, 'suelta', v_mat_op, '1') RETURNING id INTO v_suelta;
  INSERT INTO casos SELECT '05 una pieza que puede faltar sigue frenando', 'suelta: depende de Tir, que puede no estar', problema
    FROM catalogo_version_referencias(v_version) WHERE nodo = 'v:' || v_suelta AND problema IS NOT NULL;

  FOR r IN SELECT * FROM casos LOOP
    v_total := v_total + 1;
    IF r.esperado IS NOT DISTINCT FROM r.real THEN
      v_ok := v_ok + 1;
    ELSE
      v_fallos := v_fallos || format('%s: esperaba %s, dio %s', r.nombre, r.esperado, r.real);
    END IF;
  END LOOP;

  RAISE EXCEPTION '% / % ok %', v_ok, v_total, v_fallos;
END $$;
