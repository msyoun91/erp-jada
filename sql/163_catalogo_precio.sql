-- Catálogo, tramo 6: el precio de un paquete, el detalle del gerente, los mínimos por presupuesto y los precios de referencia.
-- Decisiones: decisiones/catalogo/precio.md. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_precio.sql.
--
-- Todo parte de catalogo_despiece: no hay otro cálculo, y nada se guarda. Las públicas son DEFINER porque leen lo que quien
-- llama no puede abrir. catalogo_precio y catalogo_precio_minimos piden catalogo_aprobar hasta que la ficha de Presupuestos
-- nombre su permiso (decisiones/catalogo/permisos.md). Las internas no tienen EXECUTE.

-- ============================================================
-- 1. Un precio
-- ============================================================
CREATE OR REPLACE FUNCTION public.catalogo_precio_redondear(p_monto numeric, p_moneda moneda)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT round(p_monto, CASE WHEN p_moneda = 'ARS' THEN 0 ELSE 2 END);
$$;

-- NULL sin tipo de cambio: quien llama dice qué monto no se pudo pasar.
CREATE OR REPLACE FUNCTION public.catalogo_precio_convertir(p_monto numeric, p_de moneda, p_a moneda, p_en timestamptz)
RETURNS numeric
LANGUAGE plpgsql
STABLE
STRICT
SET search_path = public
AS $$
BEGIN
  RETURN public.monedas_convertir(p_monto, p_de, p_a, p_en);
EXCEPTION WHEN SQLSTATE 'MO001' THEN
  RETURN NULL;
END;
$$;

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
    || CASE WHEN v_sin_opcional THEN ARRAY['Un servicio opcional elegido no está a esa fecha'] ELSE '{}'::text[] END;

  RETURN v_d || jsonb_build_object(
    'mensaje', coalesce(v_d->>'mensaje', CASE
      WHEN v_sin_opcional THEN 'Un servicio opcional elegido ya no está'
      WHEN cardinality(v_sin_costo) > 0 THEN 'Este paquete no tiene precio a la fecha del presupuesto'
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

-- Lo que se vende hoy: la versión publicada de un paquete activo, a la fecha de hoy, y solo lo que se ofrece. Lo elegido que ya
-- no se ofrece no da número ni se saca solo: el precio cambiaría sin que nadie lo note.
CREATE OR REPLACE FUNCTION public.catalogo_precio_venta(p_paquete uuid, p_entrada jsonb, p_opcionales uuid[], p_moneda moneda)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_version uuid;
  v_r jsonb;
  v_o record;
  v_fuera text;
BEGIN
  SELECT v.id INTO v_version
  FROM public.catalogo_versiones v
  JOIN public.catalogo_paquetes q ON q.id = v.paquete_id
  WHERE q.id = p_paquete AND q.activo AND v.estado = 'publicado';

  IF v_version IS NULL THEN
    RETURN jsonb_build_object('precio', NULL::numeric, 'mensaje', 'Este paquete no está a la venta', 'mensajes', '[]'::jsonb);
  END IF;

  v_r := public.catalogo_precio_calcular(v_version, p_entrada, p_opcionales, p_moneda, now());
  IF v_r->>'precio' IS NULL THEN
    RETURN v_r;
  END IF;

  SELECT o.armable, o.piezas_fuera, o.opciones_fuera INTO v_o
  FROM public.catalogo_oferta(v_version) o
  WHERE o.color_id IS NOT DISTINCT FROM (v_r->'color'->>'id')::uuid;

  IF NOT FOUND OR NOT v_o.armable THEN
    RETURN v_r || jsonb_build_object('precio', NULL::numeric, 'mensaje', 'Este paquete no se ofrece en este color');
  END IF;

  SELECT string_agg(DISTINCT CASE
           WHEN (f->>'pieza_id')::uuid = ANY (v_o.piezas_fuera) THEN f->>'pieza' ELSE f->>'insumo' END, ', ')
  INTO v_fuera
  FROM jsonb_array_elements(v_r->'filas') f
  WHERE (f->>'pieza_id')::uuid = ANY (v_o.piezas_fuera) OR (f->>'opcion_id')::uuid = ANY (v_o.opciones_fuera);

  IF v_fuera IS NOT NULL THEN
    RETURN v_r || jsonb_build_object('precio', NULL::numeric, 'mensaje', 'Ya no se ofrece: ' || v_fuera);
  END IF;

  RETURN v_r;
END;
$$;

-- ============================================================
-- 2. Lo que recibe cada uno
-- ============================================================
-- Sin moneda, la principal. Solo el número y los mensajes: ni despiece, ni costos, ni los errores del cálculo.
CREATE OR REPLACE FUNCTION public.catalogo_precio(
  p_paquete uuid, p_entrada jsonb DEFAULT '{}', p_opcionales uuid[] DEFAULT '{}', p_moneda moneda DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_r jsonb;
BEGIN
  IF NOT public.tiene_permiso('catalogo_aprobar') THEN
    RAISE EXCEPTION 'Pedir el precio requiere catalogo_aprobar' USING ERRCODE = '42501';
  END IF;
  v_r := public.catalogo_precio_venta(p_paquete, p_entrada, p_opcionales, p_moneda);
  RETURN jsonb_build_object('precio', v_r->'precio', 'mensaje', v_r->'mensaje', 'mensajes', v_r->'mensajes');
END;
$$;

-- Cualquier versión a cualquier fecha, sin mirar la oferta: la baja del DVH no borra lo que costaba en marzo.
CREATE OR REPLACE FUNCTION public.catalogo_precio_detalle(
  p_version uuid, p_entrada jsonb DEFAULT '{}', p_opcionales uuid[] DEFAULT '{}', p_moneda moneda DEFAULT NULL,
  p_en timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tiene_permiso('catalogo_aprobar') THEN
    RAISE EXCEPTION 'El detalle del precio requiere catalogo_aprobar' USING ERRCODE = '42501';
  END IF;
  RETURN public.catalogo_precio_calcular(p_version, p_entrada, p_opcionales, p_moneda, p_en);
END;
$$;

-- ============================================================
-- 3. Los mínimos por presupuesto
-- ============================================================
-- Ítems: [{paquete_id, cantidad, entrada, opcionales}]. Un renglón por mínimo que no se alcanzó, con la diferencia ya pasada
-- por los pasos siguientes. Un ítem sin precio no cuenta. De los opcionales, a un renglón le toca lo que eligieron todos los
-- ítems que cuentan para ese mínimo: a nadie se le cobra lo que no eligió. Lo que el renglón de un paso 1 paga de un servicio
-- del paso 2 suma para el mínimo de ese servicio.
CREATE OR REPLACE FUNCTION public.catalogo_precio_minimos(p_items jsonb, p_moneda moneda DEFAULT NULL)
RETURNS TABLE (porcentaje_id uuid, nombre text, monto numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_moneda moneda := coalesce(p_moneda, public.monedas_principal_actual());
  v_i record;
  v_m record;
  v_r jsonb;
  v_item integer := 0;
  v_aportes jsonb := '[]';
  v_arrastre jsonb := '{}';
  v_segundos jsonb;
  v_falta numeric;
  v_p2 numeric;
  v_p3 numeric;
BEGIN
  IF NOT public.tiene_permiso('catalogo_aprobar') THEN
    RAISE EXCEPTION 'Pedir el precio requiere catalogo_aprobar' USING ERRCODE = '42501';
  END IF;

  FOR v_i IN
    SELECT x.paquete_id, x.cantidad, x.entrada, x.opcionales
    FROM jsonb_to_recordset(p_items) AS x (paquete_id uuid, cantidad numeric, entrada jsonb, opcionales uuid[])
  LOOP
    IF v_i.paquete_id IS NULL OR coalesce(v_i.cantidad, 0) <= 0 THEN
      RAISE EXCEPTION 'Los ítems no tienen la forma esperada' USING ERRCODE = 'CA017';
    END IF;

    v_r := public.catalogo_precio_venta(v_i.paquete_id, coalesce(v_i.entrada, '{}'), v_i.opcionales, v_moneda);
    IF v_r->>'precio' IS NOT NULL THEN
      v_item := v_item + 1;
      SELECT v_aportes || coalesce(jsonb_agg(s || jsonb_build_object(
               'item', v_item, 'aporte', (s->>'monto')::numeric * v_i.cantidad)), '[]')
      INTO v_aportes
      FROM jsonb_array_elements(v_r->'servicios') s
      WHERE (s->>'aplica')::boolean;
    END IF;
  END LOOP;

  FOR v_m IN
    SELECT a.porcentaje_id, a.nombre, a.paso, max(a.minimo_convertido) AS minimo, sum(a.aporte) AS suma, array_agg(a.item) AS items
    FROM jsonb_to_recordset(v_aportes) AS a (
      item integer, porcentaje_id uuid, nombre text, paso integer, minimo_por text, minimo_convertido numeric, aporte numeric)
    WHERE a.minimo_por = 'presupuesto'
    GROUP BY a.porcentaje_id, a.nombre, a.paso
    ORDER BY a.paso, a.nombre
  LOOP
    v_falta := v_m.minimo - v_m.suma - coalesce((v_arrastre->>v_m.porcentaje_id::text)::numeric, 0);
    CONTINUE WHEN v_falta <= 0;

    SELECT coalesce(sum(s.porcentaje) FILTER (WHERE s.paso = 2), 0),
           coalesce(sum(s.porcentaje) FILTER (WHERE s.paso = 3), 0),
           coalesce(jsonb_object_agg(s.porcentaje_id, s.porcentaje) FILTER (WHERE s.paso = 2), '{}')
    INTO v_p2, v_p3, v_segundos
    FROM (
      SELECT a.porcentaje_id, a.paso, max(a.porcentaje) AS porcentaje
      FROM jsonb_to_recordset(v_aportes) AS a (item integer, porcentaje_id uuid, paso integer, porcentaje numeric)
      WHERE a.item = ANY (v_m.items) AND a.paso > v_m.paso
      GROUP BY a.porcentaje_id, a.paso
      HAVING count(*) = cardinality(v_m.items)
    ) s;

    SELECT v_arrastre || coalesce(jsonb_object_agg(
             e.key, coalesce((v_arrastre->>e.key)::numeric, 0) + v_falta * e.value::numeric / 100), '{}')
    INTO v_arrastre
    FROM jsonb_each_text(v_segundos) e;

    porcentaje_id := v_m.porcentaje_id;
    nombre := v_m.nombre;
    monto := public.catalogo_precio_redondear(v_falta * (1 + v_p2 / 100) / (1 - v_p3 / 100), v_moneda);
    IF monto > 0 THEN
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

-- ============================================================
-- 4. Precios de referencia
-- ============================================================
-- Cada caso de cada versión publicada de un paquete activo, a dos fechas. Un caso no elige servicios opcionales, así que van
-- sin ellos. Lo que no se puede comparar va al final, con el porqué.
CREATE OR REPLACE FUNCTION public.catalogo_precios_referencia(
  p_moneda moneda DEFAULT NULL,
  p_desde timestamptz DEFAULT now() - interval '30 days',
  p_hasta timestamptz DEFAULT now()
)
RETURNS TABLE (
  paquete_id uuid, version_id uuid, numero integer, nombre text, caso_id uuid, caso text,
  precio_desde numeric, precio_hasta numeric, cambio numeric, sin_precio_desde text[], sin_precio_hasta text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_moneda moneda := coalesce(p_moneda, public.monedas_principal_actual());
BEGIN
  IF NOT public.tiene_permiso('catalogo_aprobar') THEN
    RAISE EXCEPTION 'Los precios de referencia requieren catalogo_aprobar' USING ERRCODE = '42501';
  END IF;

  -- OFFSET 0: sin él, Postgres repite el cálculo entero en cada columna que lo lee.
  RETURN QUERY
    SELECT v.paquete_id, v.id, v.numero, v.nombre, c.id, c.nombre, p.desde, p.hasta,
           (p.hasta - p.desde) / NULLIF(p.desde, 0) * 100,
           ARRAY(SELECT jsonb_array_elements_text(r.d->'sin_precio')),
           ARRAY(SELECT jsonb_array_elements_text(r.h->'sin_precio'))
    FROM public.catalogo_versiones v
    JOIN public.catalogo_paquetes q ON q.id = v.paquete_id AND q.activo
    JOIN public.catalogo_casos c ON c.version_id = v.id AND c.activo
    CROSS JOIN LATERAL (
      SELECT public.catalogo_precio_calcular(v.id, c.entrada, '{}', v_moneda, p_desde) AS d,
             public.catalogo_precio_calcular(v.id, c.entrada, '{}', v_moneda, p_hasta) AS h
      OFFSET 0
    ) r
    CROSS JOIN LATERAL (SELECT (r.d->>'precio')::numeric AS desde, (r.h->>'precio')::numeric AS hasta) p
    WHERE v.estado = 'publicado'
    ORDER BY abs(p.hasta - p.desde) / NULLIF(p.desde, 0) DESC NULLS LAST, v.nombre, c.nombre;
END;
$$;

-- ============================================================
-- 5. Privilegios de las funciones
-- ============================================================
REVOKE EXECUTE ON FUNCTION
  public.catalogo_precio_redondear(numeric, moneda),
  public.catalogo_precio_convertir(numeric, moneda, moneda, timestamptz),
  public.catalogo_precio_calcular(uuid, jsonb, uuid[], moneda, timestamptz),
  public.catalogo_precio_venta(uuid, jsonb, uuid[], moneda)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.catalogo_precio(uuid, jsonb, uuid[], moneda),
  public.catalogo_precio_detalle(uuid, jsonb, uuid[], moneda, timestamptz),
  public.catalogo_precio_minimos(jsonb, moneda),
  public.catalogo_precios_referencia(moneda, timestamptz, timestamptz)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.catalogo_precio(uuid, jsonb, uuid[], moneda),
  public.catalogo_precio_detalle(uuid, jsonb, uuid[], moneda, timestamptz),
  public.catalogo_precio_minimos(jsonb, moneda),
  public.catalogo_precios_referencia(moneda, timestamptz, timestamptz)
TO authenticated;
