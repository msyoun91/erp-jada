-- Nombrar responsable de un hilo se alinea con `tareas_asignar` (sql/014).
--
-- `tareas_hilos_insert` seguía pidiendo `tareas_gestionar_ajenas` para poner a
-- otro como responsable, mientras sql/014 movió esa misma decisión sobre
-- `tareas` a la función `tareas_asignar`. Eran dos ejes para una sola regla:
-- poner a OTRO a cargo de algo exige `tareas_asignar`, y nada la saltea —
-- tampoco `tareas_gestionar_ajenas`, que es autoridad sobre lo ajeno, no
-- permiso para repartir trabajo.
--
-- Faltaba además el lado del UPDATE: el responsable de un hilo podía
-- traspasarlo por API sin tener la función. La UI no lo ofrece (`editarHilo`
-- no manda `responsable_id`), pero la interfaz nunca es la barrera.

-- ============================================================
-- 1. INSERT — mismo criterio que tareas_insert (sql/014)
-- ============================================================
DROP POLICY IF EXISTS tareas_hilos_insert ON tareas_hilos;
CREATE POLICY tareas_hilos_insert ON tareas_hilos FOR INSERT
  WITH CHECK (
    creado_por = auth.uid()
    AND (responsable_id = auth.uid() OR tiene_permiso('tareas_asignar'))
  );

-- ============================================================
-- 2. UPDATE — el WITH CHECK deja de decidir quién queda a cargo
-- ============================================================
-- Sin esto el traspaso es imposible incluso con la función: la fila nueva
-- tiene responsable_id ajeno y el WITH CHECK solo aceptaba
-- `responsable_id = auth.uid()`. En `tareas` el caso no aparece porque ahí el
-- WITH CHECK tiene además la rama del asignado activo (sql/013).
--
-- Quién puede TOCAR el hilo lo sigue decidiendo el USING. Quién puede quedar a
-- cargo pasa a ser del trigger de abajo, que es el único que ve el valor viejo
-- y por lo tanto el único que puede distinguir un traspaso de una edición.
DROP POLICY IF EXISTS tareas_hilos_update ON tareas_hilos;
CREATE POLICY tareas_hilos_update ON tareas_hilos FOR UPDATE
  USING (responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  WITH CHECK (
    responsable_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR tiene_permiso('tareas_asignar')
  );

-- ============================================================
-- 3. Trigger validar_responsable_hilo — traspasar el hilo
-- ============================================================
-- Va en trigger y no en la policy por el mismo motivo que
-- `validar_responsable_tarea` (sql/014): un WITH CHECK solo ve la fila nueva,
-- así que no distingue "cambió el responsable" de "el UPDATE tocó el título".
-- Reusa TA003 — el mensaje ya está en MENSAJES_ERROR y la regla es la misma.
CREATE OR REPLACE FUNCTION validar_responsable_hilo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.responsable_id <> auth.uid() AND NOT tiene_permiso('tareas_asignar') THEN
    RAISE EXCEPTION 'No tenés permiso para poner a otro usuario como responsable'
      USING ERRCODE = 'TA003';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validar_responsable_hilo() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_responsable_hilo ON tareas_hilos;
CREATE TRIGGER trg_validar_responsable_hilo
  BEFORE UPDATE OF responsable_id ON tareas_hilos
  FOR EACH ROW
  WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)
  EXECUTE FUNCTION validar_responsable_hilo();
