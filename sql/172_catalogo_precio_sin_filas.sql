-- Catálogo: si con esas medidas y elecciones no queda ninguna fila, no hay precio (AUDITORIA_CATALOGO.md, hallazgo 3).
-- Decisiones: decisiones/catalogo/precio.md → Sin filas, no hay precio. Esquema: db_schema/catalogo.md.
-- Test: sql/tests/catalogo_precio.sql. La función es la de sql/163 con este cambio; el resto sigue igual.

-- El despiece con el costo de cada fila y los servicios en %, paso por paso. La versión y la fecha las decide quien la llama:
-- no tiene EXECUTE. sin_precio es la única razón para no dar número: precio es NULL si y solo si trae algo.
CREATE OR REPLACE FUNCTION public.catalogo_precio_calcular(
  p_version uuid, p_entrada jsonb, p_opcionales uuid[], p_moneda moneda, p_en timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_moneda moneda := coalesce(p_moneda, public.monedas_principal_actual());
  v_opcionales uuid[] := coalesce(p_opcionales, '{}');
  v_d jsonb := public.catalogo_despiece(p_version, p_entrada);
  v_vigentes public.catalogo_porcentajes_valores[];
  v_s public.catalogo_porcentajes_valores;
  v_filas jsonb;
  v_piezas jsonb;
  v_servicios jsonb := '[]';
  v_sin_costo text[];
  v_sin_opcional boolean;
  v_sin_filas boolean;
  v_sin text[];
  v_costo numeric;
  v_paso1 numeric := 0;
  v_paso2 numeric := 0;
  v_paso3 numeric;
  v_base numeric;
  v_monto numeric;
  v_minimo numeric;
  v_precio numeric;
BEGIN
  v_vigentes := ARRAY(
    SELECT x FROM public.catalogo_porcentajes_vigentes(p_en) x WHERE NOT x.de_baja ORDER BY x.paso, x.nombre);

  v_sin_opcional := EXISTS (
    SELECT 1 FROM unnest(v_opcionales) AS e (id)
    WHERE NOT EXISTS (SELECT 1 FROM unnest(v_vigentes) x WHERE x.porcentaje_id = e.id AND x.opcional));

  -- El costo de lo que va por mm se carga por metro.
  WITH f AS (
    SELECT x.fila, x.i, c.costo, c.moneda, c.created_at,
           x.fila->>'insumo' || coalesce(' · ' || (x.fila->>'color'), '') AS quien,
           public.catalogo_precio_convertir(
             c.costo * (x.fila->>'total')::numeric / CASE WHEN x.fila->>'unidad' = 'mm' THEN 1000 ELSE 1 END,
             c.moneda, v_moneda, p_en) AS importe
    FROM jsonb_array_elements(v_d->'filas') WITH ORDINALITY x(fila, i)
    LEFT JOIN public.catalogo_variantes va
      ON va.insumo_id = (x.fila->>'insumo_id')::uuid
     AND va.color_id IS NOT DISTINCT FROM (x.fila->>'color_id')::uuid
    LEFT JOIN public.catalogo_costos_vigentes(p_en) c ON c.variante_id = va.id
  )
  SELECT coalesce(jsonb_agg(f.fila || jsonb_strip_nulls(jsonb_build_object(
           'costo', f.costo, 'costo_moneda', f.moneda, 'costo_desde', f.created_at, 'importe', f.importe)) ORDER BY f.i), '[]'),
         coalesce(sum(f.importe), 0),
         coalesce(array_agg(DISTINCT CASE
           WHEN f.costo IS NULL THEN f.quien || ': sin costo a esa fecha'
           ELSE format('%s: sin tipo de cambio de %s a %s a esa fecha', f.quien, f.moneda, v_moneda)
         END) FILTER (WHERE f.importe IS NULL), '{}')
  INTO v_filas, v_costo, v_sin_costo
  FROM f;

  -- Con un bloqueo, el porqué ya está en sin_precio y en mensajes.
  v_sin_filas := (v_d->>'calculable')::boolean AND NOT (v_d->>'bloqueado')::boolean AND jsonb_array_length(v_filas) = 0;

  SELECT coalesce(jsonb_agg(p.x || jsonb_build_object('subtotal', (
           SELECT coalesce(sum((f->>'importe')::numeric), 0) FROM jsonb_array_elements(v_filas) f
           WHERE f->>'pieza_id' = p.x->>'id')) ORDER BY p.i), '[]')
  INTO v_piezas
  FROM jsonb_array_elements(v_d->'piezas') WITH ORDINALITY p(x, i);

  IF (v_d->>'calculable')::boolean AND cardinality(v_sin_costo) = 0 THEN
    SELECT coalesce(sum(x.porcentaje), 0) INTO v_paso3
    FROM unnest(v_vigentes) x
    WHERE x.paso = 3 AND (NOT x.opcional OR x.porcentaje_id = ANY (v_opcionales));

    -- Vienen por paso, y dentro de un paso ninguno se calcula sobre otro. Los del 3 se despejan juntos.
    FOREACH v_s IN ARRAY v_vigentes LOOP
      v_base := CASE
        WHEN v_s.opcional AND NOT v_s.porcentaje_id = ANY (v_opcionales) THEN 0
        WHEN v_s.paso = 3 THEN (v_costo + v_paso1 + v_paso2) / (1 - v_paso3 / 100)
        WHEN v_s.paso = 2 THEN v_costo + v_paso1
        WHEN cardinality(v_s.categorias) = 0 THEN v_costo
        ELSE (SELECT coalesce(sum((f->>'importe')::numeric), 0) FROM jsonb_array_elements(v_filas) f
              WHERE (f->>'categoria_id')::uuid = ANY (v_s.categorias))
      END;
      v_monto := v_base * v_s.porcentaje / 100;
      v_minimo := NULL;

      -- Sin base no aplica, y sin aplicar no hay mínimo. El de presupuesto se compara en catalogo_precio_minimos.
      IF v_base > 0 AND v_s.minimo IS NOT NULL THEN
        v_minimo := public.catalogo_precio_convertir(v_s.minimo, v_s.minimo_moneda, v_moneda, p_en);
        IF v_minimo IS NULL THEN
          v_sin_costo := v_sin_costo
            || format('%s: sin tipo de cambio de %s a %s a esa fecha', v_s.nombre, v_s.minimo_moneda, v_moneda);
        ELSIF v_s.minimo_por = 'paquete' THEN
          v_monto := greatest(v_monto, v_minimo);
        END IF;
      END IF;

      IF v_s.paso = 1 THEN
        v_paso1 := v_paso1 + v_monto;
      ELSIF v_s.paso = 2 THEN
        v_paso2 := v_paso2 + v_monto;
      END IF;

      v_servicios := v_servicios || jsonb_strip_nulls(jsonb_build_object(
        'porcentaje_id', v_s.porcentaje_id, 'nombre', v_s.nombre, 'porcentaje', v_s.porcentaje, 'paso', v_s.paso,
        'opcional', v_s.opcional, 'aplica', v_base > 0, 'desde', v_s.created_at,
        'categorias', to_jsonb(ARRAY(
          SELECT c.nombre FROM public.catalogo_categorias c WHERE c.id = ANY (v_s.categorias) ORDER BY c.nombre)),
        'base', v_base, 'monto', v_monto,
        'minimo', v_s.minimo, 'minimo_moneda', v_s.minimo_moneda, 'minimo_por', v_s.minimo_por,
        'minimo_convertido', v_minimo));
    END LOOP;

    v_precio := (v_costo + v_paso1 + v_paso2) / (1 - v_paso3 / 100);
  END IF;

  v_sin := ARRAY(SELECT jsonb_array_elements_text(v_d->'errores'))
    || ARRAY(SELECT m->>'mensaje' FROM jsonb_array_elements(v_d->'mensajes') m WHERE (m->>'bloquea')::boolean)
    || v_sin_costo
    || CASE WHEN v_sin_opcional THEN ARRAY['Un servicio opcional elegido no está a esa fecha'] ELSE '{}'::text[] END
    || CASE WHEN v_sin_filas THEN ARRAY['Con estas medidas y elecciones el paquete no lleva nada'] ELSE '{}'::text[] END;

  RETURN v_d || jsonb_build_object(
    'mensaje', coalesce(v_d->>'mensaje', CASE
      WHEN v_sin_opcional THEN 'Un servicio opcional elegido ya no está'
      WHEN cardinality(v_sin_costo) > 0 THEN 'Este paquete no tiene precio a la fecha del presupuesto'
      WHEN v_sin_filas THEN 'Con estas medidas y elecciones el paquete no lleva nada'
    END),
    'moneda', v_moneda,
    'fecha', p_en,
    'filas', v_filas,
    'piezas', v_piezas,
    'costo_despiece', CASE WHEN v_precio IS NOT NULL THEN v_costo END,
    'servicios', v_servicios,
    'subtotal', CASE WHEN v_precio IS NOT NULL THEN v_costo + v_paso1 END,
    'sin_precio', to_jsonb(v_sin),
    'precio_exacto', CASE WHEN cardinality(v_sin) = 0 THEN v_precio END,
    'precio', CASE WHEN cardinality(v_sin) = 0 THEN public.catalogo_precio_redondear(v_precio, v_moneda) END
  );
END;
$$;
