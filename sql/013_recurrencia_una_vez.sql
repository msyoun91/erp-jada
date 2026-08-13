-- "Repetir una sola vez" — dispara un ciclo y se apaga sola, en vez de
-- seguir avanzando recurrencia_proxima indefinidamente.
-- Correr en Supabase SQL Editor, después de sql/011.

ALTER TABLE tareas_hilos ADD COLUMN IF NOT EXISTS recurrencia_una_vez boolean NOT NULL DEFAULT false;
ALTER TABLE tareas ADD COLUMN IF NOT EXISTS recurrencia_una_vez boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION generar_tareas_recurrentes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  h RECORD;
  t RECORD;
BEGIN
  FOR h IN
    SELECT * FROM tareas_hilos
    WHERE activo AND recurrencia_activa AND recurrencia_proxima <= current_date
  LOOP
    UPDATE tareas SET estado = 'pendiente' WHERE hilo_id = h.id AND activo AND estado <> 'pendiente';

    IF h.recurrencia_una_vez THEN
      UPDATE tareas_hilos SET recurrencia_activa = false WHERE id = h.id;
    ELSE
      UPDATE tareas_hilos
        SET recurrencia_proxima = avanzar_recurrencia(h.recurrencia_proxima, h.recurrencia_intervalo, h.recurrencia_cada)
        WHERE id = h.id;
    END IF;
  END LOOP;

  FOR t IN
    SELECT * FROM tareas
    WHERE activo AND hilo_id IS NULL AND recurrencia_activa AND recurrencia_proxima <= current_date
  LOOP
    IF t.recurrencia_una_vez THEN
      UPDATE tareas SET estado = 'pendiente', recurrencia_activa = false WHERE id = t.id;
    ELSE
      UPDATE tareas
        SET estado = 'pendiente',
            recurrencia_proxima = avanzar_recurrencia(t.recurrencia_proxima, t.recurrencia_intervalo, t.recurrencia_cada)
        WHERE id = t.id;
    END IF;
  END LOOP;
END;
$$;
