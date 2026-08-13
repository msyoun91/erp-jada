-- Reintroduce recurrencia en tareas_hilos (revierte sql/007 — ver DECISIONES.md).
-- Configurable por día/mes/año en vez de diaria/semanal/mensual fijo.
-- Correr en Supabase SQL Editor.

DO $$
BEGIN
  CREATE TYPE recurrencia_intervalo AS ENUM ('dia', 'mes', 'anio');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

ALTER TABLE tareas_hilos ADD COLUMN IF NOT EXISTS recurrencia_activa boolean NOT NULL DEFAULT false;
ALTER TABLE tareas_hilos ADD COLUMN IF NOT EXISTS recurrencia_intervalo recurrencia_intervalo;
ALTER TABLE tareas_hilos ADD COLUMN IF NOT EXISTS recurrencia_cada int NOT NULL DEFAULT 1;
ALTER TABLE tareas_hilos ADD COLUMN IF NOT EXISTS recurrencia_proxima date;

ALTER TABLE tareas_hilos DROP CONSTRAINT IF EXISTS recurrencia_completa;
ALTER TABLE tareas_hilos ADD CONSTRAINT recurrencia_completa CHECK (
  NOT recurrencia_activa
  OR (recurrencia_intervalo IS NOT NULL AND recurrencia_proxima IS NOT NULL AND recurrencia_cada > 0)
);

-- ============================================================
-- generar_tareas_recurrentes() — al llegar recurrencia_proxima,
-- resetea las tareas activas del hilo a 'pendiente' (el trigger
-- sync_estado_hilo ya existente reabre el hilo solo) y agenda la
-- próxima fecha. Catch-up si el cron estuvo caído varios períodos.
-- ============================================================
CREATE OR REPLACE FUNCTION generar_tareas_recurrentes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  h RECORD;
  v_paso interval;
  v_proxima date;
BEGIN
  FOR h IN
    SELECT * FROM tareas_hilos
    WHERE activo AND recurrencia_activa AND recurrencia_proxima <= current_date
  LOOP
    v_paso := (h.recurrencia_cada || ' ' ||
      CASE h.recurrencia_intervalo WHEN 'dia' THEN 'day' WHEN 'mes' THEN 'month' ELSE 'year' END
    )::interval;

    v_proxima := h.recurrencia_proxima;
    WHILE v_proxima <= current_date LOOP
      v_proxima := v_proxima + v_paso;
    END LOOP;

    UPDATE tareas SET estado = 'pendiente' WHERE hilo_id = h.id AND activo AND estado <> 'pendiente';
    UPDATE tareas_hilos SET recurrencia_proxima = v_proxima WHERE id = h.id;
  END LOOP;
END;
$$;

-- pg_cron: habilitar la extensión desde Supabase Dashboard -> Database ->
-- Extensions, luego:
-- SELECT cron.schedule('tareas-generar-recurrentes', '0 6 * * *', $$SELECT generar_tareas_recurrentes()$$);
