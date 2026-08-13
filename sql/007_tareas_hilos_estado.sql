-- Elimina recurrencia de hilos (a pedido, ya no se usa) y agrega estado
-- abierto/cerrado con cierre/apertura automática según las tareas del hilo.
-- Correr en Supabase SQL Editor.

-- ============================================================
-- Eliminar recurrencia
-- ============================================================
DROP FUNCTION IF EXISTS generar_tareas_recurrentes();

ALTER TABLE tareas_hilos DROP COLUMN IF EXISTS recurrencia;
ALTER TABLE tareas_hilos DROP COLUMN IF EXISTS asignado_a_default;
ALTER TABLE tareas_hilos DROP COLUMN IF EXISTS ultima_generacion;

DROP TYPE IF EXISTS recurrencia_hilo;

-- ============================================================
-- estado del hilo
-- ============================================================
DO $$
BEGIN
  CREATE TYPE estado_hilo AS ENUM ('abierto', 'cerrado');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

ALTER TABLE tareas_hilos ADD COLUMN IF NOT EXISTS estado estado_hilo NOT NULL DEFAULT 'abierto';

-- ============================================================
-- Cierre/apertura automática: un hilo se cierra cuando TODAS sus
-- tareas activas están completadas, y se reabre si deja de cumplirse
-- (nueva tarea, reasignación de hilo, o estado revertido).
-- SECURITY DEFINER porque el usuario que completa la tarea puede no
-- tener permiso de UPDATE sobre ese hilo puntual (RLS de tareas_hilos
-- exige ser el creador o tener tareas_todas).
-- ============================================================
CREATE OR REPLACE FUNCTION sync_estado_hilo(p_hilo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pendientes int;
  v_total int;
BEGIN
  IF p_hilo_id IS NULL THEN RETURN; END IF;

  SELECT count(*) FILTER (WHERE estado <> 'completada'), count(*)
    INTO v_pendientes, v_total
  FROM tareas WHERE hilo_id = p_hilo_id AND activo;

  IF v_total > 0 AND v_pendientes = 0 THEN
    UPDATE tareas_hilos SET estado = 'cerrado' WHERE id = p_hilo_id AND estado <> 'cerrado';
  ELSE
    UPDATE tareas_hilos SET estado = 'abierto' WHERE id = p_hilo_id AND estado <> 'abierto';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION trg_sync_estado_hilo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM sync_estado_hilo(OLD.hilo_id);
    RETURN OLD;
  END IF;

  PERFORM sync_estado_hilo(NEW.hilo_id);
  IF TG_OP = 'UPDATE' AND OLD.hilo_id IS DISTINCT FROM NEW.hilo_id THEN
    PERFORM sync_estado_hilo(OLD.hilo_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_estado_hilo ON tareas;
CREATE TRIGGER sync_estado_hilo
  AFTER INSERT OR DELETE OR UPDATE OF estado, hilo_id, activo ON tareas
  FOR EACH ROW EXECUTE FUNCTION trg_sync_estado_hilo();
