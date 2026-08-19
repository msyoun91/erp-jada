-- Restaura validar_quitar_miembro_proyecto() a la versión de sql/009: solo
-- bloquea con TA001, sin traspasar al dueño las asignaciones sobre tareas
-- cerradas. El traspaso llegó a aplicarse en la base pero su código se
-- descartó, y ningún archivo del repo lo documentaba.

-- El trigger validar_quitar_miembro (sql/009:158) sigue vivo y apunta a este
-- mismo nombre: no hay que recrearlo.
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

REVOKE EXECUTE ON FUNCTION public.validar_quitar_miembro_proyecto() FROM PUBLIC;

-- No se deshace: el backfill ya movió al dueño las asignaciones y los
-- responsable_id que estaban en no-miembros. Con esta versión vuelve a existir
-- el agujero que el traspaso cerraba — quitar un miembro con tareas cerradas
-- deja su asignación activa, y reabrir esa tarea le devuelve trabajo vivo a
-- alguien que ya no es miembro del proyecto.
