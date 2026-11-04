-- Catálogo: un material múltiple con cantidad 0 no exige elegir, si ninguna opción trae cantidad propia (AUDITORIA_CATALOGO.md, hallazgo 8).
-- Decisiones: decisiones/catalogo/despiece.md → Primero se calcula la cantidad. Esquema: db_schema/catalogo.md.
-- Test: sql/tests/catalogo_despiece.sql. La función es la de sql/167 con este cambio.

CREATE OR REPLACE FUNCTION public.catalogo_despiece(p_version uuid, p_entrada jsonb DEFAULT '{}')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_e record;
  v_c record;
  v_piezas jsonb;
  v_variables jsonb;
  v_materiales jsonb;
  v_x jsonb;
  v_o jsonb;
  v_fila jsonb;
  v_valor jsonb;
  v_cant jsonb := '{}';
  v_valores jsonb := '{}';
  v_listas jsonb := '{}';
  v_elegidas jsonb;
  v_hechos jsonb := '{}';
  v_listos jsonb := '{}';
  v_fallos jsonb := '{}';
  v_espera jsonb;
  v_sumas jsonb;
  v_global jsonb;
  v_ambito jsonb;
  v_salen jsonb := '{}';
  v_salida_variables jsonb := '[]';
  v_salida_piezas jsonb := '[]';
  v_salida_filas jsonb := '[]';
  v_mensajes jsonb := '[]';
  v_errores text[];
  v_raices text[];
  v_progreso boolean;
  v_id text;
  v_quien text;
  v_pieza text;
  v_txt text;
  v_num numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.catalogo_versiones v WHERE v.id = p_version) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = 'CA016';
  END IF;
  IF NOT public.catalogo_entrada_valida(p_entrada) THEN
    RAISE EXCEPTION 'La entrada no tiene la forma esperada' USING ERRCODE = 'CA017';
  END IF;

  SELECT * INTO v_e FROM public.catalogo_despiece_entrada(p_version, p_entrada);
  v_elegidas := v_e.elegidas;

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'clase', 'pieza', 'id', p.id, 'nombre', p.nombre, 'cantidad', p.cantidad_arbol,
    'calcula_espesor', p.calcula_espesor, 'peso_a_produccion', p.peso_a_produccion,
    'espesor_a_produccion', p.espesor_a_produccion
  )) ORDER BY p.orden, p.nombre), '[]') INTO v_piezas
  FROM public.catalogo_piezas p
  WHERE p.id = ANY (v_e.adentro);

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'clase', 'variable', 'id', x.id, 'nombre', x.nombre, 'pieza_id', x.pieza_id, 'ingresa', x.ingresa_vendedor,
    'es_lista', x.es_lista, 'formula', x.formula_arbol, 'valores', to_jsonb(x.valores),
    'predeterminado', x.valor_predeterminado, 'es_cantidad', x.es_cantidad, 'minimo', x.minimo, 'maximo', x.maximo,
    'a_produccion', x.a_produccion, 'segun_material_id', x.segun_material_id,
    'segun_nombre', coalesce(sm.nombre, si.nombre),
    'segun_valores', (
      SELECT jsonb_object_agg(vv.opcion_id, vv.formula_arbol)
      FROM public.catalogo_variables_valores vv
      WHERE vv.variable_id = x.id AND vv.activo)
  )) ORDER BY x.pieza_id IS NOT NULL, p.orden, p.nombre, x.orden, x.created_at, x.id), '[]') INTO v_variables
  FROM public.catalogo_variables x
  LEFT JOIN public.catalogo_piezas p ON p.id = x.pieza_id
  LEFT JOIN public.catalogo_materiales sm ON sm.id = x.segun_material_id
  LEFT JOIN public.catalogo_insumos si ON si.id = sm.insumo_id
  WHERE x.version_id = p_version AND x.activo AND (x.pieza_id IS NULL OR x.pieza_id = ANY (v_e.adentro));

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'clase', 'material', 'id', m.id, 'pieza_id', m.pieza_id, 'pieza', p.nombre, 'tipo', m.tipo,
    'nombre', coalesce(m.nombre, i.nombre), 'insumo', to_jsonb(i),
    'medida', m.medida_arbol, 'ancho', m.ancho_arbol, 'alto', m.alto_arbol, 'area', m.area_arbol,
    'cantidad', m.cantidad_arbol, 'eleccion', m.eleccion_arbol,
    'sigue', m.sigue_material_id, 'sigue_tipo', s.tipo, 'sigue_nombre', s.nombre,
    'cuenta_peso', m.cuenta_peso, 'cuenta_espesor', m.cuenta_espesor,
    'opciones', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'sigue_opcion', o.sigue_opcion_id, 'insumo', to_jsonb(oi),
        'medida', o.medida_arbol, 'ancho', o.ancho_arbol, 'alto', o.alto_arbol, 'area', o.area_arbol,
        'cantidad', o.cantidad_arbol
      ) ORDER BY o.orden, o.created_at, o.id), '[]')
      FROM public.catalogo_opciones o
      LEFT JOIN public.catalogo_insumos oi ON oi.id = o.insumo_id
      WHERE o.material_id = m.id AND o.activo)
  )) ORDER BY p.orden, p.nombre, m.orden, m.created_at, m.id), '[]') INTO v_materiales
  FROM public.catalogo_materiales m
  JOIN public.catalogo_piezas p ON p.id = m.pieza_id
  LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
  LEFT JOIN public.catalogo_materiales s ON s.id = m.sigue_material_id
  WHERE m.version_id = p_version AND m.activo AND m.pieza_id = ANY (v_e.adentro);

  LOOP
    v_sumas := public.catalogo_despiece_sumas(v_piezas, v_materiales, v_cant, v_hechos);
    v_global := (v_sumas->'global') || (v_sumas->'datos') || v_valores;
    v_espera := '{}';
    v_progreso := false;

    FOR v_x IN SELECT x FROM jsonb_array_elements(v_variables || v_piezas || v_materiales) x LOOP
      v_id := v_x->>'id';
      CONTINUE WHEN v_listos ? v_id OR v_fallos ? v_id;

      v_quien := CASE v_x->>'clase'
        WHEN 'pieza' THEN 'cantidad de ' || (v_x->>'nombre')
        ELSE coalesce(v_x->>'nombre', 'Un material de ' || (v_x->>'pieza'))
      END;
      v_pieza := coalesce(v_x->>'pieza_id', v_id);
      v_ambito := v_global || coalesce(v_sumas->'local'->v_pieza, '{}');

      BEGIN
        IF v_x->>'clase' = 'variable' THEN
          v_valor := CASE WHEN (v_x->>'ingresa')::boolean THEN p_entrada->'variables'->v_quien END;
          IF (v_x->>'es_lista')::boolean THEN
            IF v_valor IS NOT NULL AND (jsonb_typeof(v_valor) <> 'string' OR NOT (v_x->'valores') ? (v_valor #>> '{}')) THEN
              RAISE EXCEPTION 'el valor % no está en la lista', v_valor #>> '{}' USING ERRCODE = 'CA018';
            END IF;
            v_txt := coalesce(v_valor #>> '{}', v_x->>'predeterminado');
            IF v_txt IS NULL THEN
              RAISE EXCEPTION 'falta elegir un valor' USING ERRCODE = 'CA018';
            END IF;
            v_listas := v_listas || jsonb_build_object(v_quien, v_txt);
          ELSE
            IF v_valor IS NOT NULL THEN
              IF jsonb_typeof(v_valor) <> 'number' THEN
                RAISE EXCEPTION 'no es un número' USING ERRCODE = 'CA018';
              END IF;
              v_num := (v_valor #>> '{}')::numeric;
            ELSIF v_x ? 'segun_material_id' THEN
              v_num := public.catalogo_formula_evaluar(
                public.catalogo_despiece_segun(v_x, v_materiales, v_elegidas, v_e.faltan, v_ambito), v_ambito);
            ELSIF v_x ? 'formula' THEN
              v_num := public.catalogo_formula_evaluar(v_x->'formula', v_ambito);
            ELSE
              RAISE EXCEPTION 'falta el valor' USING ERRCODE = 'CA018';
            END IF;
            v_valores := v_valores || jsonb_build_object(v_quien, v_num);
            v_global := v_global || jsonb_build_object(v_quien, v_num);
          END IF;

        ELSIF v_x->>'clase' = 'pieza' THEN
          v_num := public.catalogo_formula_evaluar(v_x->'cantidad', v_ambito);
          IF v_num < 0 THEN
            RAISE EXCEPTION 'dio %', public.catalogo_numero_texto(v_num) USING ERRCODE = 'CA018';
          END IF;
          v_cant := v_cant || jsonb_build_object(v_id, v_num);

        ELSE
          IF NOT v_cant ? v_pieza THEN
            v_espera := v_espera || jsonb_build_object(v_quien, 'cantidad de ' || (v_x->>'pieza'));
            CONTINUE;
          END IF;

          IF (v_cant->>v_pieza)::numeric = 0 THEN
            v_fila := NULL;
            IF v_x->>'tipo' = 'elige_sistema' THEN
              v_elegidas := v_elegidas || jsonb_build_object(v_id, NULL::uuid);
            END IF;
          ELSE
            -- Si la cantidad no depende de la opción, ya se sabe si hace falta elegir. Queda sin elección, y quien la use, también.
            IF v_id = ANY (v_e.faltan) AND NOT jsonb_path_exists(v_x, '$.opciones[*].cantidad')
              AND public.catalogo_formula_evaluar(v_x->'cantidad', v_ambito) = 0 THEN
              v_e.faltan := array_remove(v_e.faltan, v_id);
            END IF;
            v_o := public.catalogo_despiece_elegir(v_x, v_elegidas, v_e.faltan, v_ambito);
            IF v_x->>'tipo' = 'elige_sistema' THEN
              v_elegidas := v_elegidas || jsonb_build_object(v_id, v_o->'id');
            END IF;
            v_fila := CASE WHEN v_o IS NOT NULL THEN
              public.catalogo_despiece_fila(v_x, v_o, (v_cant->>v_pieza)::numeric, v_e.color, v_ambito) END;
          END IF;
          v_hechos := v_hechos || jsonb_build_object(v_id, coalesce(v_fila, '{"valor": 0}'));
        END IF;

        v_listos := v_listos || jsonb_build_object(v_id, true);
        v_progreso := true;
      EXCEPTION
        WHEN SQLSTATE 'CA002' THEN
          v_espera := v_espera || jsonb_build_object(v_quien, replace(SQLERRM, 'Falta el valor de ', ''));
        WHEN division_by_zero OR numeric_value_out_of_range OR SQLSTATE 'CA018' THEN
          v_fallos := v_fallos || jsonb_build_object(v_id, jsonb_build_object('quien', v_quien, 'motivo',
            CASE SQLSTATE
              WHEN '22012' THEN 'una cuenta divide por cero'
              WHEN '22003' THEN 'una cuenta da fuera de rango'
              ELSE SQLERRM
            END));
      END;
    END LOOP;

    EXIT WHEN NOT v_progreso;
  END LOOP;

  -- Lo que no llegó a saber su cantidad, y por eso sigue esperando, dice lo que falta: elegir.
  SELECT v_fallos || coalesce(jsonb_object_agg(m.x->>'id',
    jsonb_build_object('quien', m.x->>'nombre', 'motivo', 'falta elegir una opción')), '{}') INTO v_fallos
  FROM jsonb_array_elements(v_materiales) m(x)
  WHERE (m.x->>'id') = ANY (v_e.faltan) AND v_cant ? (m.x->>'pieza_id')
    AND NOT v_listos ? (m.x->>'id') AND NOT v_fallos ? (m.x->>'id');

  FOR v_x IN SELECT x FROM jsonb_array_elements(v_variables) x LOOP
    v_id := v_x->>'id';
    v_quien := v_x->>'nombre';

    -- Adentro de una pieza con cantidad 0 no se evalúa nada: la cuenta de la variable solo sirve a quien la use,
    -- que puede ser esa misma cantidad, y si falla frena a ese y no a esta.
    IF (v_cant->>(v_x->>'pieza_id'))::numeric = 0 THEN
      v_fallos := v_fallos - v_id;
      v_espera := v_espera - v_quien;
      CONTINUE;
    END IF;
    CONTINUE WHEN NOT (v_valores ? v_quien OR v_listas ? v_quien);

    v_salen := v_salen || jsonb_build_object(v_id, true);
    v_salida_variables := v_salida_variables || jsonb_strip_nulls(jsonb_build_object(
      'id', v_id, 'nombre', v_quien, 'pieza_id', v_x->>'pieza_id',
      'valor', coalesce(v_valores->v_quien, v_listas->v_quien),
      'a_produccion', (v_x->>'a_produccion')::boolean));

    v_num := (v_valores->>v_quien)::numeric;
    IF v_num < (v_x->>'minimo')::numeric OR v_num > (v_x->>'maximo')::numeric THEN
      v_txt := CASE
        WHEN v_x ? 'minimo' AND v_x ? 'maximo' THEN format('va de %s a %s',
          public.catalogo_numero_texto((v_x->>'minimo')::numeric), public.catalogo_numero_texto((v_x->>'maximo')::numeric))
        WHEN v_x ? 'minimo' THEN format('va desde %s', public.catalogo_numero_texto((v_x->>'minimo')::numeric))
        ELSE format('va hasta %s', public.catalogo_numero_texto((v_x->>'maximo')::numeric))
      END;
      v_mensajes := v_mensajes || jsonb_build_object(
        'mensaje', upper(left(v_quien, 1)) || substr(v_quien, 2) || ' ' || v_txt
          || CASE WHEN (v_x->>'es_cantidad')::boolean THEN '' ELSE ' mm' END,
        'bloquea', true,
        'variable_id', v_id);
    END IF;
  END LOOP;

  v_errores := v_e.errores || ARRAY(
    SELECT (f.value->>'quien') || ': ' || (f.value->>'motivo')
    FROM jsonb_each(v_fallos) f
    ORDER BY 1);

  FOR v_c IN
    SELECT c.variable_id, c.material_id, c.opcion_id, c.condicion_arbol, c.mensaje, c.bloquea,
           coalesce(x.pieza_id, m.pieza_id)::text AS pieza_id,
           coalesce(x.nombre, m.nombre, i.nombre) AS quien,
           coalesce(c.material_id, o.material_id)::text AS de_material
    FROM public.catalogo_condiciones c
    LEFT JOIN public.catalogo_variables x ON x.id = c.variable_id
    LEFT JOIN public.catalogo_opciones o ON o.id = c.opcion_id
    LEFT JOIN public.catalogo_materiales m ON m.id = coalesce(c.material_id, o.material_id)
    LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
    LEFT JOIN public.catalogo_piezas p ON p.id = coalesce(x.pieza_id, m.pieza_id)
    WHERE c.version_id = p_version AND c.activo
    ORDER BY c.variable_id IS NULL, p.orden, p.nombre, coalesce(x.orden, m.orden), c.created_at, c.id
  LOOP
    v_fila := v_hechos->v_c.de_material->'fila';
    CONTINUE WHEN CASE
      WHEN v_c.variable_id IS NOT NULL THEN NOT v_salen ? v_c.variable_id::text
      WHEN v_c.material_id IS NOT NULL THEN v_fila IS NULL
      ELSE (v_fila->>'opcion_id') IS DISTINCT FROM v_c.opcion_id::text
    END;

    v_ambito := v_global || coalesce(v_sumas->'local'->v_c.pieza_id, '{}');
    BEGIN
      IF public.catalogo_condicion_evaluar(v_c.condicion_arbol, v_ambito) THEN
        v_mensajes := v_mensajes || jsonb_strip_nulls(jsonb_build_object(
          'mensaje', v_c.mensaje, 'bloquea', v_c.bloquea, 'variable_id', v_c.variable_id,
          'material_id', v_c.material_id, 'opcion_id', v_c.opcion_id));
      END IF;
    EXCEPTION
      WHEN SQLSTATE 'CA002' THEN
        v_espera := v_espera || jsonb_build_object(v_c.quien, replace(SQLERRM, 'Falta el valor de ', ''));
      WHEN division_by_zero OR numeric_value_out_of_range THEN
        v_errores := v_errores || format('%s: una condición no se puede hacer', v_c.quien);
    END;
  END LOOP;

  -- El peso que alguien usa y espera a un material es un eslabón más; el que nadie usa no se nombra.
  SELECT v_espera || coalesce(jsonb_object_agg(d.key, d.value), '{}') INTO v_espera
  FROM jsonb_each(v_sumas->'esperan') d
  WHERE EXISTS (SELECT 1 FROM jsonb_each_text(v_espera) e WHERE e.value = d.key);

  -- Quien espera a algo que espera o que falló no agrega nada: se dice de quién viene. Si todos esperan a otro y nada
  -- falló, es un círculo.
  SELECT array_agg(format('%s: usa %s, que no existe o no se pudo calcular', e.key, e.value) ORDER BY e.key) INTO v_raices
  FROM jsonb_each_text(v_espera) e
  WHERE NOT v_espera ? e.value
    AND NOT EXISTS (SELECT 1 FROM jsonb_each(v_fallos) f WHERE f.value->>'quien' = e.value);
  v_errores := v_errores || coalesce(v_raices, '{}');

  IF cardinality(v_errores) = 0 AND v_espera <> '{}' THEN
    SELECT 'Referencia circular entre ' || string_agg(e.key, ', ' ORDER BY e.key) INTO v_txt
    FROM jsonb_each_text(v_espera) e;
    v_errores := ARRAY[v_txt];
  END IF;

  IF cardinality(v_errores) = 0 THEN
    SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', p.x->>'id', 'nombre', p.x->>'nombre', 'cantidad', v_cant->(p.x->>'id'),
      'peso', v_sumas->'datos'->('peso ' || (p.x->>'nombre')),
      'espesor', v_sumas->'datos'->('espesor ' || (p.x->>'nombre')),
      'peso_a_produccion', p.x->'peso_a_produccion', 'espesor_a_produccion', p.x->'espesor_a_produccion'
    )) ORDER BY p.i), '[]') INTO v_salida_piezas
    FROM jsonb_array_elements(v_piezas) WITH ORDINALITY p(x, i)
    WHERE (v_cant->>(p.x->>'id'))::numeric > 0;

    SELECT coalesce(jsonb_agg(v_hechos->(m.x->>'id')->'fila' ORDER BY m.i), '[]') INTO v_salida_filas
    FROM jsonb_array_elements(v_materiales) WITH ORDINALITY m(x, i)
    WHERE v_hechos->(m.x->>'id') ? 'fila';
  END IF;

  RETURN jsonb_build_object(
    'calculable', cardinality(v_errores) = 0,
    'bloqueado', jsonb_path_exists(v_mensajes, '$[*] ? (@.bloquea == true)'),
    'mensaje', CASE WHEN cardinality(v_errores) > 0 THEN 'No se puede calcular con estas medidas' END,
    'errores', to_jsonb(v_errores),
    'mensajes', v_mensajes,
    'color', v_e.color,
    'variables', v_salida_variables,
    'piezas', v_salida_piezas,
    'filas', v_salida_filas
  );
END;
$$;
