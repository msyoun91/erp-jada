-- Log append-only de cambios de estado de tareas — base de la vista Auditoría.
-- El dato no era derivable de `tareas`: `estado` es el valor actual y
-- generar_tareas_recurrentes() lo pisa a 'pendiente' cada ciclo, así que las
-- veces que una tarea recurrente se completó no dejaban rastro. `updated_at`
-- tampoco sirve: lo mueve cualquier update (posponer, asociar hilo, editar).
-- Correr en Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS tareas_eventos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tarea_id uuid NOT NULL REFERENCES tareas(id),
  usuario_id uuid REFERENCES usuarios(id),
  estado_anterior estado_tarea,
  estado_nuevo estado_tarea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Sin columna `activo`: excepción explícita a la regla "nunca DELETE, siempre
-- activo" (ver DECISIONES.md). Un flag para ocultar filas es justo lo que un
-- log de auditoría no debe tener.

CREATE INDEX IF NOT EXISTS tareas_eventos_created_at_idx ON tareas_eventos (created_at DESC);
CREATE INDEX IF NOT EXISTS tareas_eventos_usuario_idx ON tareas_eventos (usuario_id, created_at DESC);
CREATE INDEX IF NOT EXISTS tareas_eventos_tarea_idx ON tareas_eventos (tarea_id);

-- ============================================================
-- Trigger: registra todo cambio de estado. usuario_id NULL = sistema, que es
-- el caso del cron de recurrencia (SECURITY DEFINER, sin auth.uid()).
-- ============================================================
CREATE OR REPLACE FUNCTION log_evento_tarea()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO tareas_eventos (tarea_id, usuario_id, estado_anterior, estado_nuevo)
  VALUES (NEW.id, auth.uid(), OLD.estado, NEW.estado);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS log_evento_tarea_trigger ON tareas;
CREATE TRIGGER log_evento_tarea_trigger
  AFTER UPDATE OF estado ON tareas
  FOR EACH ROW
  WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
  EXECUTE FUNCTION log_evento_tarea();

-- ============================================================
-- RLS — solo lectura, y solo con el permiso de la vista. Nadie escribe a mano:
-- el INSERT lo hace el trigger (SECURITY DEFINER) y no hay GRANT de
-- INSERT/UPDATE/DELETE, así que la tabla es append-only por permisos, no por
-- convención.
-- ============================================================
ALTER TABLE tareas_eventos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tareas_eventos_select ON tareas_eventos;
CREATE POLICY tareas_eventos_select ON tareas_eventos FOR SELECT
  USING (tiene_permiso('tareas_auditoria'));

GRANT SELECT ON public.tareas_eventos TO authenticated;

-- ============================================================
-- Seed — nueva vista del módulo tareas
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden)
VALUES ('tareas_auditoria', 'tareas', 'vista', 'Auditoría', 4)
ON CONFLICT DO NOTHING;
