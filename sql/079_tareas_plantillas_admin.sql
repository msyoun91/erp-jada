-- ============================================================
-- 079 — El administrador ve las plantillas privadas; los items respetan asignar
--
-- Auditoría 2026-09-17 (`PLAN_AUDITORIA_TAREAS.md`, fase 4).
--
-- C.  Siempre hay una función que administra (decisiones/global/permisos.md).
--     `tareas_gestionar_ajenas` ahora ve las plantillas privadas ajenas: las lee
--     y las puede usar, pero no editarlas (`puede_gestionar_plantilla` sigue
--     igual). Los hilos y pasos de la plantilla la acompañan solos: su SELECT es
--     un EXISTS sobre `tareas_plantillas`.
--     Lo que no la acompaña es la activación. Prender el disparador de una
--     privada ajena la haría correr con los cambios del administrador, así que
--     activar sigue pidiendo que la plantilla sea de sistema o propia.
-- 18. `tareas_plantillas_items_update` no tenía la regla de `sql/014` que sí
--     tiene el INSERT: sin `tareas_asignar`, un PATCH directo ponía a otro en un
--     paso. `usar_plantilla` lo filtraba al usar, pero la plantilla quedaba
--     guardada con un asignado que su dueño no podía elegir. Apagar un paso
--     queda libre: `guardar_plantilla` desactiva los pasos viejos antes de
--     insertar los nuevos, y esos pueden tener asignados que puso otro.
-- ============================================================

DROP POLICY IF EXISTS tareas_plantillas_select ON tareas_plantillas;
CREATE POLICY tareas_plantillas_select ON tareas_plantillas
  FOR SELECT
  USING (
    tiene_permiso('tareas_plantillas')
    AND (alcance = 'sistema' OR creado_por = (SELECT auth.uid()) OR tiene_permiso('tareas_gestionar_ajenas'))
    AND (disparo_ente IS NULL OR EXISTS (SELECT 1 FROM entes e WHERE e.codigo = tareas_plantillas.disparo_ente))
  );

DROP POLICY IF EXISTS tareas_plantillas_activaciones_insert ON tareas_plantillas_activaciones;
CREATE POLICY tareas_plantillas_activaciones_insert ON tareas_plantillas_activaciones
  FOR INSERT
  WITH CHECK (
    usuario_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM tareas_plantillas p
      WHERE p.id = tareas_plantillas_activaciones.plantilla_id
        AND p.disparo_ente IS NOT NULL
        AND (p.alcance = 'sistema' OR p.creado_por = (SELECT auth.uid()))
    )
  );

DROP POLICY IF EXISTS tareas_plantillas_activaciones_update ON tareas_plantillas_activaciones;
CREATE POLICY tareas_plantillas_activaciones_update ON tareas_plantillas_activaciones
  FOR UPDATE
  USING (usuario_id = (SELECT auth.uid()))
  WITH CHECK (
    usuario_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM tareas_plantillas p
      WHERE p.id = tareas_plantillas_activaciones.plantilla_id
        AND p.disparo_ente IS NOT NULL
        AND (p.alcance = 'sistema' OR p.creado_por = (SELECT auth.uid()))
    )
  );

DROP POLICY IF EXISTS tareas_plantillas_items_update ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_update ON tareas_plantillas_items
  FOR UPDATE
  USING (puede_gestionar_plantilla(plantilla_id))
  WITH CHECK (
    puede_gestionar_plantilla(plantilla_id)
    AND (
      NOT activo
      OR tiene_permiso('tareas_asignar')
      OR (asignados <@ ARRAY[(SELECT auth.uid())] AND (responsable_id IS NULL OR responsable_id = (SELECT auth.uid())))
    )
  );
