-- El impreso de Presupuestos (decisiones/presupuestos.md → Pantallas, El impreso): lo cargado en cada ventana, con los nombres
-- del color y de lo elegido y el orden de las medidas. Quien ve el presupuesto no lee Catálogo (la RLS pide una de sus
-- vistas): la base le da los nombres, y el texto lo arma la pantalla con `textoCargado`, como Revisión técnica. Solo lo que
-- guardan las ventanas de la versión; lo dado de baja sigue con su nombre, porque la versión no cambia.
-- Test: sql/tests/presupuestos_autorizaciones.sql (06).

CREATE FUNCTION public.presupuestos_version_nombres(p_version uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH r AS (
    SELECT r.catalogo_version_id, r.entrada
    FROM public.presupuestos_renglones r
    WHERE r.version_id = p_version AND r.activo AND r.tipo = 'catalogo'
      AND EXISTS (SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
                  WHERE v.id = p_version AND public.presupuestos_ve(p.obra_id))
  ),
  ids AS (
    SELECT r.entrada->>'color' AS id FROM r
    UNION
    SELECT m.value FROM r, jsonb_each(coalesce(r.entrada->'elecciones', '{}')) e, jsonb_each_text(e.value) m
  )
  SELECT jsonb_build_object(
    'nombres', coalesce((
      SELECT jsonb_object_agg(x.id, x.nombre) FROM (
        SELECT c.id, c.nombre FROM public.catalogo_colores c WHERE c.id::text IN (SELECT ids.id FROM ids)
        UNION ALL
        SELECT i.id, i.nombre FROM public.catalogo_insumos i WHERE i.id::text IN (SELECT ids.id FROM ids)) x), '{}'),
    'orden', coalesce((
      SELECT jsonb_object_agg(cv.version_id || ':' || cv.nombre, cv.orden)
      FROM public.catalogo_variables cv
      WHERE cv.activo AND cv.ingresa_vendedor AND cv.version_id IN (SELECT r.catalogo_version_id FROM r)), '{}'));
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_nombres(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_nombres(uuid) TO authenticated;
