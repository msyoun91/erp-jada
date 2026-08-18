-- Reactivación de posponer, sin cron: se llama al leer la lista (queries.ts),
-- no por job. SECURITY DEFINER porque quien mira una tarea/hilo visible por
-- cascada puede no tener UPDATE propio sobre esa fila — es mecánica de
-- sistema (recalcular una fecha ya vencida), no una edición de negocio,
-- mismo criterio que reabrir_hilo_en_tarea/generar_recurrencia.
CREATE OR REPLACE FUNCTION reactivar_posponer_vencidos()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE tareas
  SET fecha_vencimiento = CASE
        WHEN fecha_vencimiento IS NOT NULL THEN fecha_vencimiento + (posponer_hasta - posponer_desde)
        ELSE fecha_vencimiento
      END,
      posponer_desde = NULL,
      posponer_hasta = NULL
  WHERE posponer_hasta IS NOT NULL AND posponer_hasta <= current_date;

  UPDATE tareas_hilos
  SET posponer_desde = NULL,
      posponer_hasta = NULL
  WHERE posponer_hasta IS NOT NULL AND posponer_hasta <= current_date;
END;
$$;

REVOKE EXECUTE ON FUNCTION reactivar_posponer_vencidos() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION reactivar_posponer_vencidos() TO authenticated;
