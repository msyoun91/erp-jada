-- Lo que pidieron las pantallas de Presupuestos (decisiones/presupuestos.md → Pantallas, 2026-11-10):
-- 1. el nombre no cambia después de aprobar o rechazar,
-- 2. el importe con IVA de cada renglón lo da la base,
-- 3. la obra pasa a `contratada` solo cuando hay un presupuesto aprobado.

-- ============================================================
-- 1. Nombre congelado
-- ============================================================
-- Lo ve el cliente: aprobado o rechazado ya no cambia. Revertir lo devuelve a `publicado`, y ahí se vuelve a poder.
CREATE OR REPLACE FUNCTION public.presupuestos_nombre_congelado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.estado IN ('aprobado', 'rechazado') THEN
    RAISE EXCEPTION 'El nombre de un presupuesto aprobado o rechazado no cambia' USING ERRCODE = 'PR027';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_nombre_congelado() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_nombre_congelado ON public.presupuestos;
CREATE TRIGGER presupuestos_nombre_congelado
  BEFORE UPDATE OF nombre ON public.presupuestos
  FOR EACH ROW WHEN (OLD.nombre IS DISTINCT FROM NEW.nombre)
  EXECUTE FUNCTION public.presupuestos_nombre_congelado();

-- ============================================================
-- 2. Importe con IVA por renglón
-- ============================================================
-- Con IVA incluido, editor, impreso y portal muestran lo mismo: el importe con IVA sale redondeado de acá. DROP porque cambia el
-- retorno: se repiten los privilegios (`totales` no depende de la firma, lee las columnas por nombre).
DROP FUNCTION IF EXISTS public.presupuestos_version_importes(uuid);
CREATE FUNCTION public.presupuestos_version_importes(p_version uuid)
RETURNS TABLE(renglon_id uuid, seccion_id uuid, moneda public.moneda, alicuota numeric, clave text, nombre text, importe numeric,
              importe_con_iva numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH r AS (
    SELECT r.id, r.seccion_id, r.moneda, r.cantidad, r.precio, r.lineas, s.alicuota
    FROM public.presupuestos_renglones r
    JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
    WHERE r.version_id = p_version AND r.activo
      AND EXISTS (SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
                  WHERE v.id = p_version AND public.presupuestos_ve(p.obra_id))
  ),
  f AS (SELECT 1 - public.presupuestos_recargo_de(p_version) / 100 AS factor),
  ap AS (
    SELECT r.id, r.cantidad, o.clave, s.id AS seccion_id, s.moneda, s.alicuota,
           (SELECT (l->>'monto')::numeric FROM jsonb_array_elements(r.lineas) l
            WHERE l->>'clave' = o.clave AND l->>'moneda' = r.moneda::text) AS propio,
           (SELECT l FROM jsonb_array_elements(r.lineas) l
            WHERE l->>'clave' = o.clave AND l->>'moneda' = s.moneda::text) AS linea
    FROM r
    JOIN public.presupuestos_opcionales o ON o.version_id = p_version AND o.activo AND o.forma = 'aparte'
    JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
    WHERE r.precio IS NOT NULL AND r.lineas @> jsonb_build_array(jsonb_build_object('clave', o.clave))
  ),
  i AS (
    SELECT r.id AS renglon_id, r.seccion_id, r.moneda, r.alicuota, NULL::text AS clave, NULL::text AS nombre,
           public.catalogo_precio_redondear(
             (r.precio - coalesce((SELECT sum(ap.propio) FROM ap WHERE ap.id = r.id), 0)) * r.cantidad / f.factor, r.moneda) AS importe
    FROM r, f
    UNION ALL
    SELECT ap.id, ap.seccion_id, ap.moneda, ap.alicuota, ap.clave, ap.linea->>'nombre',
           public.catalogo_precio_redondear((ap.linea->>'monto')::numeric * ap.cantidad / f.factor, ap.moneda)
    FROM ap, f
  )
  SELECT i.renglon_id, i.seccion_id, i.moneda, i.alicuota, i.clave, i.nombre, i.importe,
         public.catalogo_precio_redondear(i.importe * (1 + i.alicuota / 100), i.moneda)
  FROM i;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) TO authenticated;

-- ============================================================
-- 3. `contratada` solo con un aprobado
-- ============================================================
-- Al aprobar, el presupuesto ya está `aprobado` cuando `presupuestos_mover_obra` mueve la obra: pasa. A mano no. Las obras que ya
-- están `contratada` sin presupuesto quedan como están: el freno corre al entrar al estado, no sobre lo que ya está.
CREATE OR REPLACE FUNCTION public.presupuestos_obra_estado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.estado = 'contratada' AND NEW.estado <> 'contratada'
     AND EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = NEW.id AND p.activo AND p.estado = 'aprobado') THEN
    RAISE EXCEPTION 'La obra tiene un presupuesto aprobado: se revierte la aprobación' USING ERRCODE = 'PR025';
  END IF;
  IF NEW.estado = 'perdida' AND OLD.estado <> 'perdida'
     AND EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = NEW.id AND p.activo AND p.estado = 'publicado') THEN
    RAISE EXCEPTION 'La obra tiene presupuestos publicados: primero se aprueban o se rechazan' USING ERRCODE = 'PR026';
  END IF;
  IF NEW.estado = 'contratada' AND OLD.estado <> 'contratada'
     AND NOT EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.obra_id = NEW.id AND p.activo AND p.estado = 'aprobado') THEN
    RAISE EXCEPTION 'La obra pasa a contratada al aprobar un presupuesto' USING ERRCODE = 'PR028';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_obra_estado() FROM PUBLIC, anon, authenticated;
