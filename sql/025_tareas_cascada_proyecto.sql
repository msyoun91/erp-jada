-- ============================================================
-- 025 — Archivar un proyecto se lleva lo que hay adentro
--
-- `desactivarProyecto` desactivaba solo la fila del proyecto. Sus hilos y sus
-- tareas sueltas quedaban activos: el trabajo no desaparecía de la Lista (el
-- hilo sigue siendo hilo, la tarea suelta sigue suelta), pero perdía la
-- agrupación y quedaba apuntando a un proyecto archivado — que además no se
-- lista, así que el select de "proyecto" en el form de la tarea aparecía vacío
-- sobre un valor todavía seteado. Archivar es "se va todo junto", no "se
-- sueltan las partes"; simétrico con `desactivar_hilo`, que ya se lleva sus
-- tareas desde sql/023.
--
-- **Trigger y no función `.rpc()`.** La cascada no es un acto aparte del
-- usuario: es la consecuencia de archivar. Como trigger, la regla vale para
-- cualquier escritor de `activo = false` sobre `tareas_proyectos` y
-- `desactivarProyecto` sigue siendo el mismo UPDATE de una tabla que era.
--
-- **`SECURITY DEFINER`, y la autorización no se mueve.** Quien archiva un
-- proyecto es su creador-miembro o un manager (`tareas_proyectos_update`); eso
-- no le da UPDATE sobre los hilos de adentro, que exigen ser responsable del
-- hilo o `tareas_gestionar_ajenas`. Con `SECURITY INVOKER` la cascada se
-- frenaría en seco contra RLS y en silencio —0 filas no es error— dejando el
-- proyecto archivado y la mitad de adentro viva, que es peor que no cascadear.
-- El permiso para el acto sigue viviendo en la policy del UPDATE que dispara
-- este trigger: si esa no pasa, el trigger no llega a correr.
--
-- Los miembros del proyecto no se tocan: no son trabajo, y su SELECT ya exige
-- que el proyecto esté activo (`sql/016`).
-- ============================================================

CREATE OR REPLACE FUNCTION cascada_desactivar_proyecto()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Las tareas primero, en una sola sentencia: las de los hilos del proyecto y
  -- las sueltas que cuelgan de él (`proyecto_id` solo se usa sin `hilo_id`).
  -- Una cadena de pasos vive entera dentro de un hilo, así que cae completa y
  -- `trg_validar_desactivar_paso` —diferido al COMMIT— no encuentra siguientes
  -- activos que reclamar.
  UPDATE public.tareas SET activo = false
   WHERE activo
     AND (proyecto_id = NEW.id
          OR hilo_id IN (SELECT id FROM public.tareas_hilos WHERE proyecto_id = NEW.id));

  UPDATE public.tareas_hilos SET activo = false
   WHERE proyecto_id = NEW.id AND activo;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cascada_desactivar_proyecto() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_cascada_desactivar_proyecto ON tareas_proyectos;
CREATE TRIGGER trg_cascada_desactivar_proyecto
  AFTER UPDATE ON tareas_proyectos
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION cascada_desactivar_proyecto();
