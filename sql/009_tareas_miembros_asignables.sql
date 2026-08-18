-- Miembros de proyecto = quién puede recibir tareas (ver DECISIONES.md).
-- Ejes ortogonales: `visibilidad` decide quién VE un proyecto, la membresía
-- decide quién TRABAJA en él. Aplica a proyectos públicos y privados por igual.

-- ============================================================
-- Helpers
-- ============================================================

-- SECURITY DEFINER por el mismo motivo que es_creador_proyecto: la policy de
-- tareas_proyectos_miembros no puede consultar su propia tabla sin disparar
-- 42P17 infinite recursion.
CREATE OR REPLACE FUNCTION es_miembro_proyecto(p_proyecto_id uuid, p_usuario_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tareas_proyectos_miembros m
    WHERE m.proyecto_id = p_proyecto_id AND m.usuario_id = p_usuario_id AND m.activo
  );
$$;

-- Proyecto efectivo de una tarea: el propio si está suelta, el del hilo si
-- tiene hilo (el CHECK de `tareas` garantiza que nunca hay los dos). Sin
-- proyecto no hay restricción: cualquier usuario puede recibir la tarea.
CREATE OR REPLACE FUNCTION es_miembro_proyecto_de_tarea(p_tarea_id uuid, p_usuario_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.proyecto_id IS NULL OR es_miembro_proyecto(s.proyecto_id, p_usuario_id)
  FROM (
    SELECT COALESCE(t.proyecto_id, h.proyecto_id) AS proyecto_id
    FROM tareas t
    LEFT JOIN tareas_hilos h ON h.id = t.hilo_id
    WHERE t.id = p_tarea_id
  ) s;
$$;

-- ============================================================
-- Policies
-- ============================================================

-- Un miembro necesita ver a los demás miembros del proyecto: sin esto el
-- picker de asignados le queda vacío a todo el que no sea creador del
-- proyecto ni tenga tareas_gestionar_ajenas.
DROP POLICY IF EXISTS tareas_proyectos_miembros_select ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_select ON tareas_proyectos_miembros FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_creador_proyecto(proyecto_id)
    OR es_miembro_proyecto(proyecto_id, auth.uid())
  );

-- La membresía se exige solo sobre filas activas: desactivar una asignación
-- (reasignar) tiene que seguir siendo posible aunque el usuario ya no sea
-- miembro. La regla no la saltea ni tareas_gestionar_ajenas — es una regla de
-- negocio ("quién trabaja"), no un nivel de permiso.
DROP POLICY IF EXISTS tareas_asignados_insert ON tareas_asignados;
CREATE POLICY tareas_asignados_insert ON tareas_asignados FOR INSERT
  WITH CHECK (
    (tiene_permiso('tareas_gestionar_ajenas') OR es_responsable_o_creador_tarea(tarea_id))
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
  );

DROP POLICY IF EXISTS tareas_asignados_update ON tareas_asignados;
CREATE POLICY tareas_asignados_update ON tareas_asignados FOR UPDATE
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_o_creador_tarea(tarea_id)
  )
  WITH CHECK (
    (
      usuario_id = auth.uid()
      OR tiene_permiso('tareas_gestionar_ajenas')
      OR es_responsable_o_creador_tarea(tarea_id)
    )
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
  );

-- ============================================================
-- Triggers — la regla tiene dos caras y las policies solo cubren una
-- ============================================================

-- Cara 2: mover una tarea a otro proyecto (editar proyecto_id, asociarla a un
-- hilo de otro proyecto) dejaría asignados que no son miembros. Se valida acá
-- y no en la policy de `tareas` porque el dato que cambia vive en otra tabla.
CREATE OR REPLACE FUNCTION validar_proyecto_tarea_miembros()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proyecto_id uuid;
BEGIN
  v_proyecto_id := COALESCE(
    NEW.proyecto_id,
    (SELECT h.proyecto_id FROM tareas_hilos h WHERE h.id = NEW.hilo_id)
  );

  IF v_proyecto_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM tareas_asignados ta
    WHERE ta.tarea_id = NEW.id AND ta.activo
      AND NOT es_miembro_proyecto(v_proyecto_id, ta.usuario_id)
  ) THEN
    RAISE EXCEPTION 'Hay asignados que no son miembros del proyecto destino'
      USING ERRCODE = 'TA002';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validar_proyecto_tarea ON tareas;
CREATE TRIGGER validar_proyecto_tarea
  BEFORE UPDATE OF proyecto_id, hilo_id ON tareas
  FOR EACH ROW
  WHEN (
    NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id
    OR NEW.hilo_id IS DISTINCT FROM OLD.hilo_id
  )
  EXECUTE FUNCTION validar_proyecto_tarea_miembros();

-- Quitar un miembro con tareas activas se bloquea con error explícito, en vez
-- de desactivar sus asignaciones por detrás.
CREATE OR REPLACE FUNCTION validar_quitar_miembro_proyecto()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM tareas t
    LEFT JOIN tareas_hilos h ON h.id = t.hilo_id
    JOIN tareas_asignados ta ON ta.tarea_id = t.id AND ta.activo AND ta.usuario_id = OLD.usuario_id
    WHERE t.activo
      AND t.estado IN ('pendiente', 'en_progreso')
      AND COALESCE(t.proyecto_id, h.proyecto_id) = OLD.proyecto_id
  ) THEN
    RAISE EXCEPTION 'El miembro tiene tareas activas en el proyecto'
      USING ERRCODE = 'TA001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validar_quitar_miembro ON tareas_proyectos_miembros;
CREATE TRIGGER validar_quitar_miembro
  BEFORE UPDATE ON tareas_proyectos_miembros
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION validar_quitar_miembro_proyecto();

-- ============================================================
-- GRANTs — mismo criterio que sql/006
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.es_miembro_proyecto(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.es_miembro_proyecto(uuid, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.es_miembro_proyecto_de_tarea(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.es_miembro_proyecto_de_tarea(uuid, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.validar_proyecto_tarea_miembros() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validar_quitar_miembro_proyecto() FROM PUBLIC;

-- ============================================================
-- Backfill — proyectos sin miembros activos (todos los públicos creados
-- antes de esta regla). Miembro = creador + responsables de sus hilos + todo
-- usuario con asignación activa en alguna de sus tareas, para que ninguna
-- reasignación existente quede bloqueada.
-- ============================================================
INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
SELECT DISTINCT p.id, u.usuario_id
FROM tareas_proyectos p
CROSS JOIN LATERAL (
  SELECT p.creado_por AS usuario_id
  UNION
  SELECT h.responsable_id
  FROM tareas_hilos h
  WHERE h.activo AND h.proyecto_id = p.id
  UNION
  SELECT ta.usuario_id
  FROM tareas t
  LEFT JOIN tareas_hilos h2 ON h2.id = t.hilo_id
  JOIN tareas_asignados ta ON ta.tarea_id = t.id AND ta.activo
  WHERE t.activo AND COALESCE(t.proyecto_id, h2.proyecto_id) = p.id
) u
WHERE p.activo
  AND NOT EXISTS (
    SELECT 1 FROM tareas_proyectos_miembros m
    WHERE m.proyecto_id = p.id AND m.activo
  );
