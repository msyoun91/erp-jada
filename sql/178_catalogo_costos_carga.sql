-- Catálogo: la carga de costos con una variante repetida o una moneda sin tipo de cambio (AUDITORIA_CATALOGO.md, hallazgo 11).
-- Decisiones: decisiones/catalogo/precio.md → Moneda. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_registros.sql.

-- El nivel solo avisa: si el anterior no se puede pasar a la moneda nueva, va sin color y no frena la carga.
CREATE OR REPLACE FUNCTION public.catalogo_costos_niveles(p_filas jsonb)
RETURNS TABLE (variante_id uuid, costo numeric, moneda moneda, anterior numeric,
               anterior_moneda moneda, nivel text)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT f.variante_id, f.costo, f.moneda, a.costo, a.moneda,
         public.nivel_cambio(public.catalogo_precio_convertir(a.costo, a.moneda, f.moneda, now()), f.costo)
  FROM jsonb_to_recordset(p_filas) AS f (variante_id uuid, costo numeric, moneda moneda)
  LEFT JOIN public.catalogo_costos_vigentes() a ON a.variante_id = f.variante_id;
$$;

-- Niveles es INVOKER y la llama quien carga costos. Convertir no muestra más que monedas_convertir, que ya tiene EXECUTE.
GRANT EXECUTE ON FUNCTION public.catalogo_precio_convertir(numeric, moneda, moneda, timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.catalogo_costos_cargar(p_filas jsonb, p_confirmar_rojo boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tipos tipo_catalogo[] := public.catalogo_tipos_con_costo();
  v_rojas int;
  v_cargadas int;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_filas) AS f (variante_id uuid)
    LEFT JOIN public.catalogo_variantes va ON va.id = f.variante_id
    LEFT JOIN public.catalogo_insumos i ON i.id = va.insumo_id
    WHERE i.id IS NULL OR NOT i.tipo = ANY (v_tipos)
  ) THEN
    RAISE EXCEPTION 'Cargar este costo requiere catalogo_costos o catalogo_fijos_editar' USING ERRCODE = '42501';
  END IF;

  IF (SELECT count(*) <> count(DISTINCT f.variante_id) FROM jsonb_to_recordset(p_filas) AS f (variante_id uuid)) THEN
    RAISE EXCEPTION 'La misma variante va más de una vez en la carga: dejá una sola fila por variante' USING ERRCODE = 'CA026';
  END IF;

  SELECT count(*) INTO v_rojas FROM public.catalogo_costos_niveles(p_filas) n WHERE n.nivel = 'rojo';
  IF v_rojas > 0 AND NOT coalesce(p_confirmar_rojo, false) THEN
    RAISE EXCEPTION '% 50 %% o más: confirmalo',
      CASE WHEN v_rojas = 1 THEN '1 fila cambia' ELSE v_rojas || ' filas cambian' END
      USING ERRCODE = 'CA003';
  END IF;

  INSERT INTO public.catalogo_costos (variante_id, costo, moneda, creado_por)
  SELECT f.variante_id, f.costo, f.moneda, auth.uid()
  FROM jsonb_to_recordset(p_filas) AS f (variante_id uuid, costo numeric, moneda moneda);
  GET DIAGNOSTICS v_cargadas = ROW_COUNT;
  RETURN v_cargadas;
END;
$$;
