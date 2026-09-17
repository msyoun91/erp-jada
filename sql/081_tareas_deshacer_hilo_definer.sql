-- ============================================================
-- 081 — `deshacer_conversion_hilo` pasa a DEFINER
--
-- Auditoría 2026-09-17 (`PLAN_AUDITORIA_TAREAS.md`, ítem 24). El responsable
-- del hilo que no es responsable ni asignado de la tarea más antigua no podía
-- deshacer: el WITH CHECK de `tareas_update` mira el hilo de la fila nueva, y
-- deshacer lo deja en NULL (`42501`). Una policy no ve OLD, así que no hay
-- arreglo INVOKER sin abrir el WITH CHECK a cualquier tarea suelta.
--
-- La autorización es la que ya decidía el último paso: el UPDATE de
-- `tareas_hilos` (USING: responsable del hilo o `tareas_gestionar_ajenas`).
-- Como DEFINER, `validar_gestionar_tarea` (sql/080) no corre; esta guarda
-- cubre lo mismo, porque el responsable del hilo ya entraba ahí.
-- ============================================================

CREATE OR REPLACE FUNCTION deshacer_conversion_hilo(p_hilo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proyecto_id uuid;
  v_ids         uuid[];
BEGIN
  SELECT proyecto_id INTO v_proyecto_id FROM tareas_hilos
   WHERE id = p_hilo_id
     AND (responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'));

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El hilo no existe o no es visible' USING ERRCODE = 'TA008';
  END IF;

  SELECT array_agg(id ORDER BY created_at) INTO v_ids
    FROM tareas WHERE hilo_id = p_hilo_id AND activo;

  IF v_ids IS NOT NULL THEN
    IF array_length(v_ids, 1) > 1 THEN
      UPDATE tareas SET activo = false WHERE id = ANY(v_ids[2:]);
    END IF;

    UPDATE tareas SET hilo_id = NULL, proyecto_id = v_proyecto_id WHERE id = v_ids[1];
  END IF;

  UPDATE tareas_hilos SET activo = false WHERE id = p_hilo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION deshacer_conversion_hilo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION deshacer_conversion_hilo(uuid) TO authenticated;
