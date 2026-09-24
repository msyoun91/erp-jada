-- sql/120 — tareas: nombres de quienes aparecen en lo que se ve.
--
-- `usuarios_select` y `equipos_select` no dejan ver otros equipos (`sql/104`)
-- y `tareas_asignables()` trae solo los activos: un hilo con responsable dado
-- de baja, o una nota de alguien que ya se fue, quedaba sin nombre. Esto
-- devuelve solo id y nombre de los usuarios y equipos que figuran en hilos,
-- pasos, notas, historial y plantillas que quien llama ve, con las mismas
-- reglas que sus policies. Mismo patrón que `notificaciones_actores()`.
-- Decisión: `decisiones/tareas/participacion.md` → *Los nombres de lo que se
-- ve*. Verificado con `sql/tests/tareas_nombres.sql`.

CREATE OR REPLACE FUNCTION public.tareas_nombres()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH yo AS (
    SELECT auth.uid() AS id, public.tiene_permiso('tareas_administrar') AS adm
  ),
  h AS (
    SELECT h.id, h.responsable_id
    FROM tareas_hilos h, yo
    WHERE public.tareas_puede_ver_hilo_de(h.id, h.responsable_id, h.equipo_id, h.activo, yo.id)
  ),
  t AS (
    SELECT t.asignado_id, t.asignado_equipo_id
    FROM tareas t JOIN h ON h.id = t.hilo_id, yo
    WHERE t.activo OR yo.adm
  ),
  n AS (
    SELECT n.autor_id, n.ocultada_por
    FROM tareas_notas n JOIN h ON h.id = n.hilo_id, yo
    WHERE n.activo OR yo.adm
  ),
  e AS (
    SELECT e.actor_id, e.ocultada_por
    FROM tareas_ediciones e JOIN h ON h.id = e.hilo_id, yo
    WHERE e.activo OR yo.adm
  ),
  p AS (
    SELECT p.id, p.dueno_id
    FROM tareas_plantillas p, yo
    WHERE yo.adm
       OR (public.tiene_permiso('tareas_plantillas') AND (p.dueno_id = yo.id OR (p.publicada AND p.activo)))
  ),
  refs AS (
    SELECT responsable_id AS id FROM h
    UNION SELECT asignado_id FROM t
    UNION SELECT asignado_equipo_id FROM t
    UNION SELECT autor_id FROM n
    UNION SELECT ocultada_por FROM n
    UNION SELECT actor_id FROM e
    UNION SELECT ocultada_por FROM e
    UNION SELECT dueno_id FROM p
    UNION SELECT pp.asignado_id FROM tareas_plantillas_pasos pp JOIN p ON p.id = pp.plantilla_id WHERE pp.activo
    UNION SELECT pp.asignado_equipo_id FROM tareas_plantillas_pasos pp JOIN p ON p.id = pp.plantilla_id WHERE pp.activo
  )
  SELECT u.id, u.nombre FROM usuarios u JOIN refs r ON r.id = u.id
  WHERE public.tiene_permiso('tareas_ver')
  UNION ALL
  SELECT q.id, q.nombre FROM equipos q JOIN refs r ON r.id = q.id
  WHERE public.tiene_permiso('tareas_ver');
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_nombres() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_nombres() TO authenticated;
