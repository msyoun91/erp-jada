-- Portal, tramo 3: los tipos de cambio para las monedas de referencia. Decisiones: decisiones/erp-cliente.md → La base.
-- Test: sql/portal/tests/portal_monedas.sql. Se aplica con el MCP supabase-portal.

-- ============================================================
-- 1. La tabla: una fila por moneda, la vigente del ERP
-- ============================================================
CREATE TABLE public.portal_monedas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moneda text NOT NULL CHECK (moneda ~ '^[A-Z_]{3,20}$'),
  valor numeric(12,2) NOT NULL CHECK (valor > 0),
  fecha timestamptz NOT NULL,
  referencia boolean NOT NULL,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX portal_monedas_moneda ON public.portal_monedas (moneda) WHERE activo;

ALTER TABLE public.portal_monedas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.portal_monedas FROM anon, authenticated;

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.portal_monedas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- 2. El servidor del ERP: reemplazar todas (service_role)
-- ============================================================
-- Recibe [{moneda, valor, fecha, referencia}] con todas las vigentes, ARS incluido (valor 1). Lo que no viene queda inactivo.
CREATE OR REPLACE FUNCTION public.portal_monedas_guardar(p_monedas jsonb)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF jsonb_typeof(p_monedas) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Se esperaba una lista de monedas' USING ERRCODE = '22023';
  END IF;

  UPDATE public.portal_monedas m SET activo = false
  WHERE m.activo AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_monedas) x
    WHERE x->>'moneda' = m.moneda AND (x->>'valor')::numeric = m.valor AND (x->>'fecha')::timestamptz = m.fecha
      AND (x->>'referencia')::boolean = m.referencia);

  INSERT INTO public.portal_monedas (moneda, valor, fecha, referencia)
  SELECT x->>'moneda', (x->>'valor')::numeric, (x->>'fecha')::timestamptz, (x->>'referencia')::boolean
  FROM jsonb_array_elements(p_monedas) x
  WHERE NOT EXISTS (SELECT 1 FROM public.portal_monedas m WHERE m.activo AND m.moneda = x->>'moneda');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.portal_monedas_guardar(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.portal_monedas_guardar(jsonb) TO service_role;

-- ============================================================
-- 3. El servidor del portal: leer (anon)
-- ============================================================
-- Pesos por unidad de cada moneda, y cuáles se muestran como referencia.
CREATE OR REPLACE FUNCTION public.portal_monedas_leer()
RETURNS TABLE(moneda text, valor numeric, fecha timestamptz, referencia boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.moneda, m.valor, m.fecha, m.referencia FROM public.portal_monedas m WHERE m.activo ORDER BY m.moneda;
$$;

REVOKE EXECUTE ON FUNCTION public.portal_monedas_leer() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.portal_monedas_leer() TO anon, service_role;
