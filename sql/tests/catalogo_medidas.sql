-- Lo que la unidad del insumo no usa no se guarda (sql/168). Termina en RAISE: revierte todo y devuelve "N / M ok".
DO $$
DECLARE
  v_mm uuid := (SELECT id FROM catalogo_insumos WHERE activo AND unidad = 'mm' LIMIT 1);
  v_m2 uuid := (SELECT id FROM catalogo_insumos WHERE activo AND unidad = 'm2' LIMIT 1);
  v_u uuid := (SELECT id FROM catalogo_insumos WHERE activo AND unidad = 'u' LIMIT 1);
  v_paquete uuid;
  v_version uuid;
  v_pieza uuid;
  v_mat uuid;
  v_mul uuid;
  v_opc uuid;
  v_otra uuid;
  v_mm2 uuid := (SELECT id FROM catalogo_insumos WHERE activo AND unidad = 'mm' AND id <> v_mm LIMIT 1);
  v_error text;
  v_ok int := 0;
  v_total int := 0;
  v_fallos text[] := '{}';
  r record;
BEGIN
  INSERT INTO catalogo_paquetes DEFAULT VALUES RETURNING id INTO v_paquete;
  INSERT INTO catalogo_versiones (paquete_id, nombre, categoria_id)
    VALUES (v_paquete, 'Zqx168', (SELECT id FROM catalogo_categorias WHERE tipo = 'paquete' AND activo LIMIT 1))
    RETURNING id INTO v_version;
  INSERT INTO catalogo_piezas (version_id, nombre) VALUES (v_version, 'Zqx168') RETURNING id INTO v_pieza;

  CREATE TEMP TABLE casos (nombre text, esperado text, real text) ON COMMIT DROP;

  -- Único: vidrio con todo.
  INSERT INTO catalogo_materiales (version_id, pieza_id, tipo, insumo_id, medida, ancho, alto, area)
    VALUES (v_version, v_pieza, 'unico', v_m2, '1', '2', '3', '4') RETURNING id INTO v_mat;
  INSERT INTO casos SELECT '01 m2 borra la medida', '|2|3|4', concat_ws('|', coalesce(medida, ''), ancho, alto, area)
    FROM catalogo_materiales WHERE id = v_mat;

  -- Cambia a perfil: el caso que se reportó.
  UPDATE catalogo_materiales SET insumo_id = v_mm, medida = '5' WHERE id = v_mat;
  INSERT INTO casos SELECT '02 mm borra ancho, alto y área', '5|||', concat_ws('|', medida, coalesce(ancho, ''), coalesce(alto, ''), coalesce(area, ''))
    FROM catalogo_materiales WHERE id = v_mat;
  INSERT INTO casos SELECT '02 y sus árboles', 'true', (ancho_arbol IS NULL AND alto_arbol IS NULL AND area_arbol IS NULL)::text
    FROM catalogo_materiales WHERE id = v_mat;

  -- Una fórmula rota en un campo que no se usa no frena el guardado.
  UPDATE catalogo_materiales SET ancho = 'ancho +' WHERE id = v_mat;
  INSERT INTO casos SELECT '03 fórmula rota sin uso', '', coalesce(ancho, '') FROM catalogo_materiales WHERE id = v_mat;

  -- En u queda la medida de corte.
  UPDATE catalogo_materiales SET insumo_id = v_u, medida = '6', ancho = '7' WHERE id = v_mat;
  INSERT INTO casos SELECT '04 u deja la medida de corte', '6|', concat_ws('|', medida, coalesce(ancho, ''))
    FROM catalogo_materiales WHERE id = v_mat;

  -- Un múltiple no tiene unidad: guarda lo que hereda cada opción.
  INSERT INTO catalogo_materiales (version_id, pieza_id, tipo, nombre, medida, ancho, alto, area)
    VALUES (v_version, v_pieza, 'elige_vendedor', 'Zqx168', '1', '2', '3', '4') RETURNING id INTO v_mul;
  INSERT INTO casos SELECT '05 múltiple sin tocar', '1|2|3|4', concat_ws('|', medida, ancho, alto, area)
    FROM catalogo_materiales WHERE id = v_mul;

  -- Opción: lo mismo que el material.
  INSERT INTO catalogo_opciones (version_id, material_id, insumo_id, medida, ancho, alto, area)
    VALUES (v_version, v_mul, v_m2, '1', '2', '3', '4') RETURNING id INTO v_opc;
  INSERT INTO casos SELECT '06 opción en m2', '|2|3|4', concat_ws('|', coalesce(medida, ''), ancho, alto, area)
    FROM catalogo_opciones WHERE id = v_opc;
  UPDATE catalogo_opciones SET insumo_id = v_mm, medida = '5' WHERE id = v_opc;
  INSERT INTO casos SELECT '07 opción que pasa a mm', '5|||', concat_ws('|', medida, coalesce(ancho, ''), coalesce(alto, ''), coalesce(area, ''))
    FROM catalogo_opciones WHERE id = v_opc;

  -- Misma unidad (sql/169). La opción que queda está en mm.
  BEGIN
    INSERT INTO catalogo_opciones (version_id, material_id, insumo_id) VALUES (v_version, v_mul, v_m2);
    v_error := 'ok';
  EXCEPTION WHEN OTHERS THEN v_error := SQLSTATE;
  END;
  INSERT INTO casos VALUES ('08 otra unidad no entra', 'CA024', v_error);

  INSERT INTO catalogo_opciones (version_id, material_id, insumo_id) VALUES (v_version, v_mul, v_mm2) RETURNING id INTO v_otra;
  INSERT INTO casos VALUES ('09 la misma unidad entra', 'true', (v_otra IS NOT NULL)::text);

  BEGIN
    UPDATE catalogo_opciones SET insumo_id = v_m2 WHERE id = v_otra;
    v_error := 'ok';
  EXCEPTION WHEN OTHERS THEN v_error := SQLSTATE;
  END;
  INSERT INTO casos VALUES ('10 no se cambia a otra unidad', 'CA024', v_error);

  UPDATE catalogo_opciones SET activo = false WHERE id = v_otra;
  UPDATE catalogo_opciones SET insumo_id = v_m2 WHERE id = v_opc;
  INSERT INTO casos SELECT '11 sola, sí se cambia', v_m2::text, insumo_id::text FROM catalogo_opciones WHERE id = v_opc;

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
