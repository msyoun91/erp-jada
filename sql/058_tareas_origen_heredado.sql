-- ============================================================
-- 058 — Lo que nace en un hilo hereda su link de origen
--
-- Pedido del usuario el 2026-09-14: "deep link hereda deep link cuando tarea
-- a hilo". Convertir una tarea en hilo ya la dejaba con su link, pero
-- "Crear siguiente paso", "Agregar tarea" y usar una plantilla en ese hilo
-- creaban tareas sin él.
--
-- El link del hilo no se guarda: es el de su tarea activa más antigua que
-- tenga uno. Una tarea que ya trae el suyo (la de un disparo) no se toca.
-- Ver decisiones/tareas/integracion.md → "El link de origen se hereda dentro del hilo".
-- ============================================================

-- INVOKER: quien crea una tarea en el hilo ya ve sus tareas (`puede_ver_hilo`).
CREATE OR REPLACE FUNCTION heredar_origen_hilo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  SELECT t.origen_app, t.origen_punto
    INTO NEW.origen_app, NEW.origen_punto
    FROM tareas t
   WHERE t.hilo_id = NEW.hilo_id AND t.activo AND t.origen_app IS NOT NULL
   ORDER BY t.created_at
   LIMIT 1;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_heredar_origen_hilo ON tareas;
CREATE TRIGGER trg_heredar_origen_hilo
  BEFORE INSERT ON tareas
  FOR EACH ROW
  WHEN (NEW.hilo_id IS NOT NULL AND NEW.origen_app IS NULL AND NEW.origen_punto IS NULL)
  EXECUTE FUNCTION heredar_origen_hilo();

REVOKE EXECUTE ON FUNCTION public.heredar_origen_hilo() FROM PUBLIC;
