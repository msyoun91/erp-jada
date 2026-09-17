-- ============================================================
-- 078 — Deshacer una conversión con pasos, la fecha de Argentina y los largos
--
-- Auditoría 2026-09-17 (`PLAN_AUDITORIA_TAREAS.md`, fase 3).
--
-- 13. `deshacer_conversion_hilo` fallaba siempre con TA006 si el hilo tenía
--     pasos encadenados: sacaba del hilo a la tarea más antigua mientras su
--     paso siguiente seguía activo. Ahora desactiva primero el resto y después
--     mueve la primera. `trg_validar_desactivar_paso` es diferido y ve la
--     cadena ya caída entera.
-- 14. La base corre en UTC. `current_date` adelantaba un día entre las 21 y las
--     24 de Argentina: un pospuesto volvía antes y un plazo "tras el anterior"
--     sumaba un día de más. La zona se fija en cada función que calcula fechas
--     de tareas, no en la base entera: las demás funciones y el formato de los
--     timestamptz que ve la app no cambian. `SET` en la función vale también
--     para los triggers que dispara adentro.
-- 20. Índice parcial para `reactivar_posponer_vencidos`, que corre en cada
--     carga de la Lista y de una ficha con tareas.
-- 11. Los largos solo estaban en Zod: por la API entraban textos de megas. Los
--     CHECK son más holgados que Zod en títulos y textos porque
--     `rellenar_datos` expande `{dato}` después de validar el formulario.
-- ============================================================

-- ─── 13 ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION deshacer_conversion_hilo(p_hilo_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_proyecto_id uuid;
  v_ids         uuid[];
BEGIN
  SELECT proyecto_id INTO v_proyecto_id FROM tareas_hilos WHERE id = p_hilo_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El hilo no existe o no es visible' USING ERRCODE = 'TA008';
  END IF;

  SELECT array_agg(id ORDER BY created_at) INTO v_ids
    FROM tareas WHERE hilo_id = p_hilo_id AND activo;

  IF v_ids IS NOT NULL THEN
    IF array_length(v_ids, 1) > 1 THEN
      UPDATE tareas SET activo = false WHERE id = ANY(v_ids[2:]);

      IF NOT FOUND THEN
        RAISE EXCEPTION 'No se pudieron desactivar las tareas del hilo' USING ERRCODE = 'TA008';
      END IF;
    END IF;

    UPDATE tareas SET hilo_id = NULL, proyecto_id = v_proyecto_id WHERE id = v_ids[1];

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo restaurar la tarea' USING ERRCODE = 'TA008';
    END IF;
  END IF;

  UPDATE tareas_hilos SET activo = false WHERE id = p_hilo_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se pudo desactivar el hilo' USING ERRCODE = 'TA008';
  END IF;
END;
$$;

-- ─── 14 ──────────────────────────────────────────────────────────────────────
ALTER FUNCTION reactivar_posponer_vencidos() SET timezone = 'America/Argentina/Buenos_Aires';
ALTER FUNCTION fijar_vencimiento_tras_previo() SET timezone = 'America/Argentina/Buenos_Aires';
ALTER FUNCTION arrancar_vencimiento_siguiente() SET timezone = 'America/Argentina/Buenos_Aires';
ALTER FUNCTION generar_recurrencia() SET timezone = 'America/Argentina/Buenos_Aires';
ALTER FUNCTION usar_plantilla(uuid, text, uuid, uuid, text, uuid, jsonb) SET timezone = 'America/Argentina/Buenos_Aires';
ALTER FUNCTION notificaciones_avisos() SET timezone = 'America/Argentina/Buenos_Aires';

-- ─── 20 ──────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tareas_posponer_hasta ON tareas (posponer_hasta) WHERE posponer_hasta IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tareas_hilos_posponer_hasta ON tareas_hilos (posponer_hasta) WHERE posponer_hasta IS NOT NULL;

-- ─── 11 ──────────────────────────────────────────────────────────────────────
ALTER TABLE tareas
  ADD CONSTRAINT tareas_largos CHECK (
    char_length(titulo) <= 500
    AND char_length(descripcion) <= 5000
    AND char_length(nota_siguiente) <= 5000
    AND char_length(nota_anterior) <= 5000
    AND char_length(origen_app) <= 100
    AND char_length(origen_punto) <= 500
  ),
  ADD CONSTRAINT tareas_origen_punto_interno CHECK (origen_punto ~ '^/(?!/)');

ALTER TABLE tareas_hilos
  ADD CONSTRAINT tareas_hilos_largos CHECK (char_length(titulo) <= 500 AND char_length(descripcion) <= 5000);

ALTER TABLE tareas_proyectos
  ADD CONSTRAINT tareas_proyectos_largos CHECK (char_length(nombre) <= 500 AND char_length(descripcion) <= 5000);

ALTER TABLE tareas_notas
  ADD CONSTRAINT tareas_notas_largo CHECK (char_length(nota) <= 5000);

ALTER TABLE tareas_hilos_notas
  ADD CONSTRAINT tareas_hilos_notas_largo CHECK (char_length(nota) <= 5000);

ALTER TABLE tareas_plantillas
  ADD CONSTRAINT tareas_plantillas_largos CHECK (
    char_length(nombre) <= 500 AND char_length(descripcion) <= 5000 AND char_length(titulo_creado) <= 500
  );

ALTER TABLE tareas_plantillas_hilos
  ADD CONSTRAINT tareas_plantillas_hilos_largo CHECK (char_length(titulo) <= 500);

ALTER TABLE tareas_plantillas_items
  ADD CONSTRAINT tareas_plantillas_items_largos CHECK (char_length(titulo) <= 500 AND char_length(descripcion) <= 5000);
