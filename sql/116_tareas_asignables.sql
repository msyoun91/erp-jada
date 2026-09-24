-- sql/116 — tareas: a quién asignar o pedir.
--
-- `usuarios_select` no deja ver otros equipos (`sql/104`). Esto devuelve solo
-- el nombre de usuarios y equipos activos, y por fila lo que la UI necesita
-- para decidir sin otra consulta: si sería un pedido para quien llama y si
-- puede recibirlo. Las reglas siguen en los triggers de `sql/113`; esto no
-- autoriza nada. Decisión: `decisiones/tareas/participacion.md` → *A quién
-- se asigna o se pide*. Verificado con `sql/tests/tareas_asignables.sql`.

CREATE OR REPLACE FUNCTION public.tareas_asignables()
RETURNS TABLE (
  usuario_id    uuid,
  equipo_id     uuid,
  nombre        text,
  pedido        boolean,
  puede_recibir boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH d AS (
    SELECT u.id AS usuario_id, NULL::uuid AS equipo_id, u.nombre
    FROM usuarios u
    WHERE u.activo
    UNION ALL
    SELECT NULL, e.id, e.nombre
    FROM equipos e
    WHERE e.activo
  )
  SELECT d.usuario_id, d.equipo_id, d.nombre,
         NOT public.tiene_permiso('tareas_administrar')
           AND public.tareas_es_pedido(auth.uid(), d.usuario_id, d.equipo_id),
         public.tareas_puede_recibir(d.usuario_id, d.equipo_id)
  FROM d
  WHERE public.tiene_permiso('tareas_ver')
  ORDER BY d.nombre;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_asignables() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_asignables() TO authenticated;
