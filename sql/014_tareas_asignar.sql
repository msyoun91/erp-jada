-- Asignar usuarios a una tarea pasa a ser una función del módulo.
--
-- Antes no existía la función: `tareas_asignados_insert` solo pedía ser
-- responsable de la tarea, y como quien la crea queda responsable, cualquiera
-- podía poner a otro a trabajar. La UI mostraba el picker sin mirar permisos
-- porque no había permiso que mirar.
--
-- Regla nueva, una sola: poner a OTRO usuario en una tarea — como asignado o
-- como responsable — exige `tareas_asignar`. Asignarse uno mismo, no.
-- Es un eje aparte de `tareas_gestionar_ajenas` (autoridad sobre tareas que no
-- son propias) y de la membresía del proyecto (quién puede trabajar): las tres
-- condiciones se exigen juntas, ninguna saltea a la otra.

-- ============================================================
-- 1. Submódulo-función
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'tareas_asignar', 'tareas', 'funcion', 'Asignar usuarios', id, 2
FROM submodulos WHERE codigo = 'tareas_lista'
ON CONFLICT DO NOTHING;

-- Quien ya tenía `tareas_gestionar_ajenas` venía asignando a otros: se le
-- conserva la capacidad para no romper equipos en curso (mismo criterio que el
-- backfill de `tareas_proyectos_miembros` en sql/013). Alta manual desde
-- Usuarios para el resto.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT us.usuario_id, nueva.id
FROM usuario_submodulos us
JOIN submodulos g ON g.id = us.submodulo_id AND g.codigo = 'tareas_gestionar_ajenas'
CROSS JOIN submodulos nueva
WHERE us.activo AND nueva.codigo = 'tareas_asignar'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 2. tareas — el responsable al crear
-- ============================================================
-- Reemplaza la rama `tiene_permiso('tareas_gestionar_ajenas')`: nombrar
-- responsable a otro es asignar, no es gestionar lo ajeno.
DROP POLICY IF EXISTS tareas_insert ON tareas;
CREATE POLICY tareas_insert ON tareas FOR INSERT
  WITH CHECK (
    creado_por = auth.uid()
    AND (responsable_id = auth.uid() OR tiene_permiso('tareas_asignar'))
  );

-- ============================================================
-- 3. tareas_asignados — a quién se pone en la tarea
-- ============================================================
-- El conjunto nuevo (`usuario_id = auth.uid() OR tiene_permiso(...)`) se suma
-- a las condiciones que ya había, no las reemplaza.
DROP POLICY IF EXISTS tareas_asignados_insert ON tareas_asignados;
CREATE POLICY tareas_asignados_insert ON tareas_asignados FOR INSERT
  WITH CHECK (
    (tiene_permiso('tareas_gestionar_ajenas') OR es_responsable_tarea(tarea_id))
    AND (usuario_id = auth.uid() OR tiene_permiso('tareas_asignar'))
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
  );

-- Sacar a otro de una tarea también es asignar (reasignar = desactivar + volver
-- a insertar). Sacarse uno mismo sigue sin pedir permiso — ya estaba acotado a
-- `NOT activo` en sql/013 para que nadie se re-agregue por API.
DROP POLICY IF EXISTS tareas_asignados_update ON tareas_asignados;
CREATE POLICY tareas_asignados_update ON tareas_asignados FOR UPDATE
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_tarea(tarea_id)
  )
  WITH CHECK (
    (
      (usuario_id = auth.uid() AND NOT activo)
      OR tiene_permiso('tareas_gestionar_ajenas')
      OR es_responsable_tarea(tarea_id)
    )
    AND (usuario_id = auth.uid() OR tiene_permiso('tareas_asignar'))
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
  );

-- ============================================================
-- 4. Trigger validar_responsable_tarea — traspasar el responsable
-- ============================================================
-- Va en trigger y no en la policy porque la condición necesita el valor viejo:
-- un WITH CHECK solo ve la fila nueva, así que no puede distinguir "cambió el
-- responsable" de "el UPDATE tocó otra columna". Mismo criterio que
-- validar_proyecto_tarea (sql/009).
CREATE OR REPLACE FUNCTION validar_responsable_tarea()
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

REVOKE EXECUTE ON FUNCTION public.validar_responsable_tarea() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_responsable_tarea ON tareas;
CREATE TRIGGER trg_validar_responsable_tarea
  BEFORE UPDATE OF responsable_id ON tareas
  FOR EACH ROW
  WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)
  EXECUTE FUNCTION validar_responsable_tarea();
