-- sql/143 — obras, tramo 4: los números del widget "Obras".
--
-- - `obras_contar(dias)` → (grupo, clave, cantidad): por estado, la foto de
--   hoy; perdidas por motivo y contratadas por origen y por tipo, las que
--   pasaron a ese estado en los últimos `dias` (evento `estado`) y siguen
--   ahí. Solo números: ni nombres ni ids.
-- - Cuenta lo que quien llama ve y, con `obras_numeros` (función "Ver
--   números", la asigna el admin, no se delega), todas. Sin `obras_ver`,
--   nada. Un alta congelada todavía no cuenta.
--
-- Decisiones: `decisiones/obras.md` → *Los números, en un widget del
-- dashboard* y *El período del widget*. Test: `sql/tests/obras_numeros.sql`.

-- ============================================================
-- 1. Permiso
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT 'obras_numeros', 'obras', 'funcion', 'Ver números', 4, v.id, false
FROM public.submodulos v
WHERE v.codigo = 'obras_ver' AND v.activo
  AND NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = 'obras_numeros' AND s.activo);

-- ============================================================
-- 2. Contar
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_contar(p_dias int)
RETURNS TABLE (grupo text, clave text, cantidad int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH o AS (
    SELECT o.id, o.estado, o.motivo_perdida, o.origen, o.tipo,
           o.estado IN ('perdida', 'contratada') AND EXISTS (
             SELECT 1 FROM public.eventos e
             WHERE e.ente = 'obra' AND e.registro_id = o.id AND e.evento = 'estado'
               AND e.detalle->>'estado' = o.estado::text
               AND e.created_at >= now() - make_interval(days => greatest(p_dias, 0))
           ) AS en_periodo
    FROM public.obras o
    WHERE o.activo
      AND NOT (o.congelada AND o.congelada_antes IS NULL)
      AND public.tiene_permiso('obras_ver')
      AND (public.tiene_permiso('obras_numeros')
           OR public.obras_puede_ver_obra_de(o.id, o.responsable_id, o.equipo_id, o.activo, auth.uid()))
  )
  SELECT 'estado', estado::text, count(*)::int FROM o GROUP BY estado
  UNION ALL
  SELECT 'motivo', motivo_perdida::text, count(*)::int FROM o
  WHERE en_periodo AND estado = 'perdida' GROUP BY motivo_perdida
  UNION ALL
  SELECT 'origen', origen::text, count(*)::int FROM o
  WHERE en_periodo AND estado = 'contratada' GROUP BY origen
  UNION ALL
  SELECT 'tipo', tipo::text, count(*)::int FROM o
  WHERE en_periodo AND estado = 'contratada' GROUP BY tipo;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_contar(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_contar(int) TO authenticated;
