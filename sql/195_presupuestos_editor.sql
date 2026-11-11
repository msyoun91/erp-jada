-- Lo que pidió el editor de Presupuestos (decisiones/presupuestos.md → Pantallas):
-- `presupuestos_version_importes` da también lo que lee el cliente en cada renglón, porque quien arma no lee Catálogo:
-- 1. `nombre` en los renglones: el de la versión del paquete con que se calculó, o la descripción (a mano y mínimo),
-- 2. `debajo`: las líneas de los opcionales que van debajo de la ventana, con el recargo, la cantidad y el IVA, redondeadas
--    como el importe. No suman: ya están en el importe de la ventana, así que `totales` no cambia.
-- Test: sql/tests/presupuestos_opcionales.sql (02).

DROP FUNCTION IF EXISTS public.presupuestos_version_importes(uuid);
CREATE FUNCTION public.presupuestos_version_importes(p_version uuid)
RETURNS TABLE(renglon_id uuid, seccion_id uuid, moneda public.moneda, alicuota numeric, clave text, nombre text, importe numeric,
              importe_con_iva numeric, debajo jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH r AS (
    SELECT r.id, r.seccion_id, r.moneda, r.cantidad, r.precio, r.lineas, s.alicuota,
           coalesce((SELECT cv.nombre FROM public.catalogo_versiones cv WHERE cv.id = r.catalogo_version_id), r.descripcion) AS nombre
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
  de AS (
    SELECT d.id, jsonb_agg(jsonb_build_object('clave', d.clave, 'nombre', d.nombre, 'importe', d.importe,
             'importe_con_iva', public.catalogo_precio_redondear(d.importe * (1 + d.alicuota / 100), d.moneda)) ORDER BY d.n) AS lineas
    FROM (
      SELECT r.id, r.moneda, r.alicuota, x.n, o.clave, x.l->>'nombre' AS nombre,
             public.catalogo_precio_redondear((x.l->>'monto')::numeric * r.cantidad / f.factor, r.moneda) AS importe
      FROM r CROSS JOIN f
      CROSS JOIN LATERAL jsonb_array_elements(r.lineas) WITH ORDINALITY AS x (l, n)
      JOIN public.presupuestos_opcionales o
        ON o.version_id = p_version AND o.activo AND o.forma = 'debajo' AND o.clave = x.l->>'clave'
      WHERE r.precio IS NOT NULL AND x.l->>'moneda' = r.moneda::text
    ) d
    GROUP BY d.id
  ),
  i AS (
    SELECT r.id AS renglon_id, r.seccion_id, r.moneda, r.alicuota, NULL::text AS clave, r.nombre,
           public.catalogo_precio_redondear(
             (r.precio - coalesce((SELECT sum(ap.propio) FROM ap WHERE ap.id = r.id), 0)) * r.cantidad / f.factor, r.moneda) AS importe,
           coalesce((SELECT de.lineas FROM de WHERE de.id = r.id), '[]'::jsonb) AS debajo
    FROM r, f
    UNION ALL
    SELECT ap.id, ap.seccion_id, ap.moneda, ap.alicuota, ap.clave, ap.linea->>'nombre',
           public.catalogo_precio_redondear((ap.linea->>'monto')::numeric * ap.cantidad / f.factor, ap.moneda),
           NULL::jsonb
    FROM ap, f
  )
  SELECT i.renglon_id, i.seccion_id, i.moneda, i.alicuota, i.clave, i.nombre, i.importe,
         public.catalogo_precio_redondear(i.importe * (1 + i.alicuota / 100), i.moneda), i.debajo
  FROM i;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) TO authenticated;
