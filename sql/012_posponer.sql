-- Posponer (snooze) hilos y tareas — sin cron: el filtro de las queries
-- (posponer_hasta IS NULL OR posponer_hasta <= hoy) hace que reaparezca
-- solo al llegar la fecha.
-- Correr en Supabase SQL Editor.

ALTER TABLE tareas_hilos ADD COLUMN IF NOT EXISTS posponer_hasta date;
ALTER TABLE tareas ADD COLUMN IF NOT EXISTS posponer_hasta date;
