-- `tareas_proyectos_miembros_select` ignoraba si el proyecto sigue activo:
-- desactivar un proyecto le sacaba la fila de la lista, pero sus membresías
-- seguían visibles. `getMiembrosPorProyecto` las traía y armaba entradas del
-- mapa para proyectos que ya no existen para el usuario.
--
-- El EXISTS directo sobre `tareas_proyectos` no recursa: el lado de vuelta
-- (`tareas_proyectos_select`) no mira esta tabla con un EXISTS sino a través de
-- `es_miembro_proyecto`, que es SECURITY DEFINER. El ciclo que documenta
-- db_schema.md ya está roto de ese lado.
DROP POLICY IF EXISTS tareas_proyectos_miembros_select ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_select ON tareas_proyectos_miembros FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM tareas_proyectos p WHERE p.id = proyecto_id AND p.activo)
    AND (
      usuario_id = auth.uid()
      OR tiene_permiso('tareas_gestionar_ajenas')
      OR es_miembro_proyecto(proyecto_id, auth.uid())
    )
  );
