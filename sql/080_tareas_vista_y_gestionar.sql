-- ============================================================
-- 080 — Escribir pide una vista de tareas; posponer, archivar y mover de hilo
--       quedan para quien gestiona la tarea
--
-- Auditoría 2026-09-17 (`PLAN_AUDITORIA_TAREAS.md`, fase 6). Siempre deja pasar
-- a `tareas_gestionar_ajenas` (decisiones/global/permisos.md).
--
-- 10. Crear tareas, hilos y notas no pedía ningún permiso del módulo: alguien
--     con solo `obras_ver` insertaba por la API. No alcanza con `tareas_lista`:
--     Misión crea el siguiente paso, Proyectos crea hilos y tareas, Plantillas
--     las usa y un disparo crea con la identidad de quien actuó (que ya
--     necesita `tareas_plantillas` para ver la plantilla). La regla es tener
--     alguna vista de tareas que crea — todas menos Auditoría, que es lectura.
-- 17. La UI limita posponer, archivar, convertir en hilo y mover o quitar de
--     hilo al responsable; `tareas_update` se lo dejaba a cualquier asignado.
--     Ahora lo exige un trigger: responsable de la tarea, responsable del hilo
--     donde está (`desactivar_hilo` y `deshacer_conversion_hilo` lo necesitan)
--     o el administrador. Solo corre con `current_user = 'authenticated'`: la
--     cascada del proyecto y `reactivar_posponer_vencidos` son DEFINER y tocan
--     lo mismo por todos. `proyecto_id` no entra: "Modificar tarea" lo edita y
--     eso sigue siendo del asignado.
-- ============================================================

-- ─── 10: escribir pide una vista de tareas ───────────────────────────────────
CREATE OR REPLACE FUNCTION tareas_puede_escribir()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT tiene_permiso('tareas_lista') OR tiene_permiso('tareas_mision')
      OR tiene_permiso('tareas_proyectos') OR tiene_permiso('tareas_plantillas');
$$;

REVOKE EXECUTE ON FUNCTION tareas_puede_escribir() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION tareas_puede_escribir() TO authenticated;

DROP POLICY IF EXISTS tareas_insert ON tareas;
CREATE POLICY tareas_insert ON tareas
  FOR INSERT
  WITH CHECK (
    creado_por = (SELECT auth.uid())
    AND (responsable_id = (SELECT auth.uid()) OR tiene_permiso('tareas_asignar'))
    AND tareas_puede_escribir()
  );

DROP POLICY IF EXISTS tareas_hilos_insert ON tareas_hilos;
CREATE POLICY tareas_hilos_insert ON tareas_hilos
  FOR INSERT
  WITH CHECK (
    creado_por = (SELECT auth.uid())
    AND (responsable_id = (SELECT auth.uid()) OR tiene_permiso('tareas_asignar'))
    AND (proyecto_id IS NULL OR tareas_proyecto_destino_valido(proyecto_id, (SELECT auth.uid())))
    AND tareas_puede_escribir()
  );

DROP POLICY IF EXISTS tareas_notas_insert ON tareas_notas;
CREATE POLICY tareas_notas_insert ON tareas_notas
  FOR INSERT
  WITH CHECK (
    usuario_id = (SELECT auth.uid())
    AND (tiene_permiso('tareas_gestionar_ajenas') OR es_responsable_tarea(tarea_id) OR es_asignado_tarea(tarea_id))
    AND tareas_puede_escribir()
  );

DROP POLICY IF EXISTS tareas_hilos_notas_insert ON tareas_hilos_notas;
CREATE POLICY tareas_hilos_notas_insert ON tareas_hilos_notas
  FOR INSERT
  WITH CHECK (
    usuario_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM tareas_hilos h
      WHERE h.id = tareas_hilos_notas.hilo_id
        AND (h.responsable_id = (SELECT auth.uid()) OR tiene_permiso('tareas_gestionar_ajenas'))
    )
    AND tareas_puede_escribir()
  );

-- ─── 17: posponer, archivar y mover de hilo ──────────────────────────────────
-- INVOKER a propósito: bajo una DEFINER `current_user` es el dueño y la regla
-- no aplica. El hilo se lee con la RLS de quien actúa; su responsable lo ve.
CREATE OR REPLACE FUNCTION validar_gestionar_tarea()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user = 'authenticated'
     AND OLD.responsable_id IS DISTINCT FROM auth.uid()
     AND NOT tiene_permiso('tareas_gestionar_ajenas')
     AND NOT EXISTS (SELECT 1 FROM tareas_hilos h
                      WHERE h.id = OLD.hilo_id AND h.responsable_id = auth.uid()) THEN
    RAISE EXCEPTION 'Solo el responsable puede posponer, archivar o mover de hilo esta tarea' USING ERRCODE = 'TA019';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION validar_gestionar_tarea() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_gestionar_tarea ON tareas;
CREATE TRIGGER trg_validar_gestionar_tarea
  BEFORE UPDATE OF hilo_id, posponer_desde, posponer_hasta, activo ON tareas
  FOR EACH ROW WHEN (
    OLD.hilo_id IS DISTINCT FROM NEW.hilo_id
    OR OLD.posponer_desde IS DISTINCT FROM NEW.posponer_desde
    OR OLD.posponer_hasta IS DISTINCT FROM NEW.posponer_hasta
    OR (OLD.activo AND NOT NEW.activo)
  )
  EXECUTE FUNCTION validar_gestionar_tarea();
