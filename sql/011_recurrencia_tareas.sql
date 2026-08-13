-- Recurrencia también para tareas sueltas (sin hilo) — sql/010 solo la dejó
-- en tareas_hilos. Mismas columnas/semántica, dueño distinto: si la tarea
-- tiene hilo_id, la recurrencia la maneja el hilo (ver asociarTareaHilo).
-- Correr en Supabase SQL Editor, después de sql/010.

ALTER TABLE tareas ADD COLUMN IF NOT EXISTS recurrencia_activa boolean NOT NULL DEFAULT false;
ALTER TABLE tareas ADD COLUMN IF NOT EXISTS recurrencia_intervalo recurrencia_intervalo;
ALTER TABLE tareas ADD COLUMN IF NOT EXISTS recurrencia_cada int NOT NULL DEFAULT 1;
ALTER TABLE tareas ADD COLUMN IF NOT EXISTS recurrencia_proxima date;

ALTER TABLE tareas DROP CONSTRAINT IF EXISTS recurrencia_completa;
ALTER TABLE tareas ADD CONSTRAINT recurrencia_completa CHECK (
  NOT recurrencia_activa
  OR (recurrencia_intervalo IS NOT NULL AND recurrencia_proxima IS NOT NULL AND recurrencia_cada > 0)
);

-- ============================================================
-- avanzar_recurrencia() — próxima fecha >= hoy, con catch-up si el
-- cron estuvo caído varios períodos. Compartida entre hilos y tareas
-- sueltas para no duplicar el cálculo en dos funciones.
-- ============================================================
CREATE OR REPLACE FUNCTION avanzar_recurrencia(p_fecha date, p_intervalo recurrencia_intervalo, p_cada int)
RETURNS date
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_paso interval := (p_cada || ' ' ||
    CASE p_intervalo WHEN 'dia' THEN 'day' WHEN 'mes' THEN 'month' ELSE 'year' END
  )::interval;
  v_resultado date := p_fecha;
BEGIN
  WHILE v_resultado <= current_date LOOP
    v_resultado := v_resultado + v_paso;
  END LOOP;
  RETURN v_resultado;
END;
$$;

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
    UPDATE tareas_hilos
      SET recurrencia_proxima = avanzar_recurrencia(h.recurrencia_proxima, h.recurrencia_intervalo, h.recurrencia_cada)
      WHERE id = h.id;
  END LOOP;

  FOR t IN
    SELECT * FROM tareas
    WHERE activo AND hilo_id IS NULL AND recurrencia_activa AND recurrencia_proxima <= current_date
  LOOP
    UPDATE tareas
      SET estado = 'pendiente',
          recurrencia_proxima = avanzar_recurrencia(t.recurrencia_proxima, t.recurrencia_intervalo, t.recurrencia_cada)
      WHERE id = t.id;
  END LOOP;
END;
$$;

-- pg_cron ya agendado en sql/010 corre esta misma función — no hace falta
-- un segundo schedule.
