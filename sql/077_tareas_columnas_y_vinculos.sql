-- ============================================================
-- 077 — Qué columnas se tocan, quién revive y quién relaciona
--
-- Auditoría 2026-09-17 (`PLAN_AUDITORIA_TAREAS.md`, fase 2). Todo reproducido
-- por la API antes de tocar nada; siempre deja pasar a `tareas_gestionar_ajenas`,
-- la función que administra (decisiones/global/permisos.md).
--
-- 4/5. Los GRANT UPDATE eran de tabla entera. Un asignado falseaba `creado_por`,
--      `created_at` (que ordena los pasos), `origen_*` y `nota_anterior`, y
--      completaba una tarea `hibrido` pasándola a `manual` en la misma
--      sentencia. El autor de una nota la reescribía (el historial "no se
--      pisa"). Ahora cada tabla tiene su lista de columnas, que son las que
--      escriben las actions y las funciones INVOKER. `updated_at` lo pone un
--      trigger y no necesita grant.
-- 6.   Un asignado revivía una tarea archivada (por un manager o por la cascada
--      del proyecto, que "es de ida"). Reactivar una tarea o un hilo queda para
--      el administrador (`TA018`).
-- 7.   `tareas_vinculos`: relacionar y desrelacionar a mano pedía solo ver la
--      tarea. Ahora pide poder gestionarla (`tareas_puede_gestionar_tarea`, la
--      misma regla que `tareas_update`). Reactivar un vínculo por UPDATE deja de
--      existir: volver a relacionar es `vincular_tarea`, que revisa el registro
--      y a los asignados.
-- 8.   El filtro de acceso de sql/063 vivía solo en `crear_tarea` y
--      `sincronizar_asignados`. Un INSERT directo a `tareas_asignados` dejaba
--      asignado a quien no puede abrir lo relacionado. Ahora lo exige la policy
--      (`tareas_asignado_puede_abrir`). Aplica también al administrador, igual
--      que en las funciones: sacarlo o compartirle sigue siendo `tareas_asignar`.
-- ============================================================

-- ─── 4/5: grants por columna ─────────────────────────────────────────────────
REVOKE UPDATE ON tareas FROM authenticated;
GRANT UPDATE (
  titulo, descripcion, hilo_id, proyecto_id, visibilidad, estado, temperatura,
  responsable_id, fecha_vencimiento, vence_dias_tras_previo, posponer_desde, posponer_hasta,
  recurrencia_cantidad, recurrencia_unidad, nota_siguiente, activo
) ON tareas TO authenticated;

REVOKE UPDATE ON tareas_notas FROM authenticated;
GRANT UPDATE (activo) ON tareas_notas TO authenticated;

REVOKE UPDATE ON tareas_hilos_notas FROM authenticated;
GRANT UPDATE (activo) ON tareas_hilos_notas TO authenticated;

REVOKE UPDATE ON tareas_asignados FROM authenticated;
GRANT UPDATE (activo) ON tareas_asignados TO authenticated;

REVOKE UPDATE ON tareas_proyectos_miembros FROM authenticated;
GRANT UPDATE (activo) ON tareas_proyectos_miembros TO authenticated;

REVOKE UPDATE ON tareas_proyectos FROM authenticated;
GRANT UPDATE (nombre, descripcion, visibilidad, activo) ON tareas_proyectos TO authenticated;

REVOKE UPDATE ON tareas_plantillas_hilos FROM authenticated;
GRANT UPDATE (titulo, orden, encadenada, activo) ON tareas_plantillas_hilos TO authenticated;

REVOKE UPDATE ON tareas_plantillas_items FROM authenticated;
GRANT UPDATE (
  titulo, descripcion, orden, asignados, incluir_ejecutor, responsable_id, vence_dias,
  vence_tras_previo, temperatura, adjuntos, condicion, activo
) ON tareas_plantillas_items TO authenticated;

-- ─── 6: reactivar es del administrador ───────────────────────────────────────
CREATE OR REPLACE FUNCTION validar_reactivar_tarea()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT tiene_permiso('tareas_gestionar_ajenas') THEN
    RAISE EXCEPTION 'Solo quien administra tareas puede reactivar lo archivado' USING ERRCODE = 'TA018';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION validar_reactivar_tarea() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_reactivar_tarea ON tareas;
CREATE TRIGGER trg_validar_reactivar_tarea
  BEFORE UPDATE OF activo ON tareas
  FOR EACH ROW WHEN (NOT OLD.activo AND NEW.activo)
  EXECUTE FUNCTION validar_reactivar_tarea();

DROP TRIGGER IF EXISTS trg_validar_reactivar_hilo ON tareas_hilos;
CREATE TRIGGER trg_validar_reactivar_hilo
  BEFORE UPDATE OF activo ON tareas_hilos
  FOR EACH ROW WHEN (NOT OLD.activo AND NEW.activo)
  EXECUTE FUNCTION validar_reactivar_tarea();

-- ─── 7: relacionar pide poder gestionar la tarea ─────────────────────────────
-- Misma regla que el USING de `tareas_update`. DEFINER: la policy de vínculos no
-- puede leer `tareas_asignados` / `tareas_hilos` con la RLS de quien pregunta.
CREATE OR REPLACE FUNCTION tareas_puede_gestionar_tarea(p_tarea_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT tiene_permiso('tareas_gestionar_ajenas')
    OR EXISTS (
      SELECT 1 FROM tareas t
      WHERE t.id = p_tarea_id
        AND (
          t.responsable_id = auth.uid()
          OR EXISTS (SELECT 1 FROM tareas_asignados ta
                      WHERE ta.tarea_id = t.id AND ta.usuario_id = auth.uid() AND ta.activo)
          OR EXISTS (SELECT 1 FROM tareas_hilos h
                      WHERE h.id = t.hilo_id AND h.responsable_id = auth.uid())
        )
    );
$$;

REVOKE EXECUTE ON FUNCTION tareas_puede_gestionar_tarea(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION tareas_puede_gestionar_tarea(uuid) TO authenticated;

DROP POLICY IF EXISTS tareas_vinculos_insert ON tareas_vinculos;
CREATE POLICY tareas_vinculos_insert ON tareas_vinculos
  FOR INSERT
  WITH CHECK (
    CASE
      WHEN plantilla_id IS NOT NULL THEN pg_trigger_depth() > 0
      ELSE (tareas_puede_gestionar_tarea(tarea_id) OR es_siembra_tarea(tarea_id))
           AND etiqueta_registro(ente, registro_id) IS NOT NULL
    END
  );

DROP POLICY IF EXISTS tareas_vinculos_update ON tareas_vinculos;
CREATE POLICY tareas_vinculos_update ON tareas_vinculos
  FOR UPDATE
  USING (plantilla_id IS NULL AND tareas_puede_gestionar_tarea(tarea_id))
  WITH CHECK (plantilla_id IS NULL AND NOT activo);

-- ─── 8: nadie queda asignado sin poder abrir lo relacionado ──────────────────
-- DEFINER: quien siembra asignados todavía no ve la tarea, y leer los vínculos
-- con su RLS los daría por vacíos. `queda_afuera` exime a quien actúa.
CREATE OR REPLACE FUNCTION tareas_asignado_puede_abrir(p_tarea_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM tareas_vinculos v
    WHERE v.tarea_id = p_tarea_id AND v.activo
      AND queda_afuera(p_usuario, v.ente, v.registro_id)
  );
$$;

REVOKE EXECUTE ON FUNCTION tareas_asignado_puede_abrir(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION tareas_asignado_puede_abrir(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS tareas_asignados_insert ON tareas_asignados;
CREATE POLICY tareas_asignados_insert ON tareas_asignados
  FOR INSERT
  WITH CHECK (
    (tiene_permiso('tareas_gestionar_ajenas') OR es_responsable_tarea(tarea_id) OR es_siembra_tarea(tarea_id))
    AND (usuario_id = (SELECT auth.uid()) OR tiene_permiso('tareas_asignar'))
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
    AND (NOT activo OR tareas_asignado_puede_abrir(tarea_id, usuario_id))
  );

DROP POLICY IF EXISTS tareas_asignados_update ON tareas_asignados;
CREATE POLICY tareas_asignados_update ON tareas_asignados
  FOR UPDATE
  USING (
    usuario_id = (SELECT auth.uid()) OR tiene_permiso('tareas_gestionar_ajenas') OR es_responsable_tarea(tarea_id)
  )
  WITH CHECK (
    ((usuario_id = (SELECT auth.uid()) AND NOT activo) OR tiene_permiso('tareas_gestionar_ajenas') OR es_responsable_tarea(tarea_id))
    AND (usuario_id = (SELECT auth.uid()) OR tiene_permiso('tareas_asignar'))
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
    AND (NOT activo OR tareas_asignado_puede_abrir(tarea_id, usuario_id))
  );
