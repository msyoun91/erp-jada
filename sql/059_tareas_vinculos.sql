-- ============================================================
-- 059 — Tareas relacionadas con obras, empresas y personas
--
-- Pedido del usuario el 2026-09-14: ver las tareas relacionadas en la ficha
-- de una obra, empresa o persona, crear una desde ahí y relacionar una tarea
-- al crearla. Hasta acá `tareas_vinculos` solo lo escribía un disparo.
--
--   1. `entes` suma empresa y persona, sin estado: se vinculan, no disparan.
--   2. `etiqueta_registro`: el nombre de un registro para quien pregunta, NULL
--      si no lo ve. Es también la regla de "lo ve".
--   3. `tareas_vinculos`: plantilla opcional, un vínculo activo por (tarea,
--      registro), y el cliente vincula lo que ve.
--   4. `crear_tarea` recibe los vínculos, en la misma transacción.
--   5. Lecturas para la Lista, las fichas y el buscador de "Relacionar".
-- Ver decisiones/tareas/integracion.md → "Tareas relacionadas con obras, empresas y personas".
-- ============================================================

-- ============================================================
-- 1. Empresa y persona en el catálogo
-- ============================================================
-- Sin estado no hay disparo: `guardar_plantilla` busca el estado en el enum
-- del ente y con NULL no encuentra ninguno (TA012).
ALTER TABLE entes ALTER COLUMN estados DROP NOT NULL;

INSERT INTO entes (codigo, modulo, submodulo, estados, datos, ruta) VALUES
  ('empresa', 'obras', 'obras_empresas', NULL, '{}', '/obras/empresas/{id}'),
  ('persona', 'obras', 'obras_personas', NULL, '{}', '/obras/personas/{id}')
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================
-- 2. El nombre de un registro, si lo ves
-- ============================================================
-- INVOKER: decide la RLS del módulo dueño, sin copiar su regla. `entes` bajo
-- RLS deja afuera los de submódulos que no tenés. Un módulo que registre
-- entes suma su rama.
CREATE OR REPLACE FUNCTION etiqueta_registro(p_ente text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE e.modulo WHEN 'obras' THEN obras_etiqueta(e.codigo, p_id) END
  FROM entes e
  WHERE e.codigo = p_ente;
$$;

-- ============================================================
-- 3. tareas_vinculos también para el cliente
-- ============================================================
ALTER TABLE tareas_vinculos ALTER COLUMN plantilla_id DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tareas_vinculos_activo_unico
  ON tareas_vinculos (tarea_id, ente, registro_id) WHERE activo;

-- Dos altas. La de un disparo lleva plantilla y solo entra adentro de un
-- trigger: una inventada bloquearía el disparo real (sql/055). La del cliente
-- va sin plantilla: una tarea que ve —o que está creando, antes de cargarle
-- asignados (`es_siembra_tarea`, sql/053)— con un registro que ve.
DROP POLICY IF EXISTS tareas_vinculos_insert ON tareas_vinculos;
CREATE POLICY tareas_vinculos_insert ON tareas_vinculos FOR INSERT
  WITH CHECK (
    CASE
      WHEN plantilla_id IS NOT NULL THEN pg_trigger_depth() > 0
      ELSE (EXISTS (SELECT 1 FROM tareas t WHERE t.id = tareas_vinculos.tarea_id)
            OR es_siembra_tarea(tarea_id))
           AND etiqueta_registro(ente, registro_id) IS NOT NULL
    END
  );

-- Desvincular, solo lo vinculado a mano: apagar el vínculo de un disparo lo
-- dejaría volver a disparar.
DROP POLICY IF EXISTS tareas_vinculos_update ON tareas_vinculos;
CREATE POLICY tareas_vinculos_update ON tareas_vinculos FOR UPDATE
  USING (plantilla_id IS NULL AND EXISTS (SELECT 1 FROM tareas t WHERE t.id = tareas_vinculos.tarea_id))
  WITH CHECK (plantilla_id IS NULL);

GRANT UPDATE (activo) ON public.tareas_vinculos TO authenticated;

-- ============================================================
-- 4. crear_tarea recibe los vínculos (resto igual a sql/053)
-- ============================================================
-- Van antes que los asignados: mientras la tarea no tuvo ninguno, quien la
-- crea la puede vincular aunque después no la vaya a ver.
DROP FUNCTION IF EXISTS crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text, int);

CREATE OR REPLACE FUNCTION crear_tarea(
  p_titulo                 text,
  p_descripcion            text,
  p_hilo_id                uuid,
  p_proyecto_id            uuid,
  p_paso_anterior_id       uuid,
  p_visibilidad            visibilidad,
  p_responsable_id         uuid,
  p_asignados              uuid[],
  p_fecha_vencimiento      date,
  p_temperatura            int,
  p_recurrencia_cantidad   int,
  p_recurrencia_unidad     recurrencia_unidad,
  p_modo_completado        modo_completado,
  p_origen_app             text,
  p_origen_punto           text,
  p_vence_dias_tras_previo int,
  p_vinculos               jsonb DEFAULT '[]'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO tareas (
    id, titulo, descripcion, hilo_id, proyecto_id, paso_anterior_id,
    visibilidad, responsable_id, fecha_vencimiento, temperatura,
    recurrencia_cantidad, recurrencia_unidad, modo_completado,
    origen_app, origen_punto, vence_dias_tras_previo, creado_por
  ) VALUES (
    v_id, p_titulo, p_descripcion, p_hilo_id, p_proyecto_id, p_paso_anterior_id,
    p_visibilidad, p_responsable_id, p_fecha_vencimiento, p_temperatura,
    p_recurrencia_cantidad, p_recurrencia_unidad, p_modo_completado,
    p_origen_app, p_origen_punto, p_vence_dias_tras_previo, auth.uid()
  );

  INSERT INTO tareas_vinculos (tarea_id, ente, registro_id)
  SELECT v_id, x->>'ente', (x->>'registro_id')::uuid
  FROM jsonb_array_elements(COALESCE(p_vinculos, '[]'::jsonb)) AS x;

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT v_id, u FROM unnest(p_asignados) AS u;

  RETURN v_id;
END;
$$;

-- ============================================================
-- 5. Lecturas
-- ============================================================
-- Los vínculos activos de las tareas activas que ves, con nombre y ruta. Lo
-- que no ves no sale: ni la tarea (RLS) ni el registro (etiqueta NULL).
CREATE OR REPLACE FUNCTION vinculos_de_tareas()
RETURNS TABLE (
  id           uuid,
  tarea_id     uuid,
  ente         text,
  registro_id  uuid,
  etiqueta     text,
  href         text,
  de_plantilla boolean
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT v.id, v.tarea_id, v.ente, v.registro_id, x.etiqueta,
         replace(e.ruta, '{id}', v.registro_id::text), v.plantilla_id IS NOT NULL
  FROM tareas_vinculos v
  JOIN tareas t ON t.id = v.tarea_id AND t.activo
  JOIN entes e ON e.codigo = v.ente
  CROSS JOIN LATERAL (SELECT etiqueta_registro(v.ente, v.registro_id) AS etiqueta) x
  WHERE v.activo AND x.etiqueta IS NOT NULL
  ORDER BY v.created_at;
$$;

-- La sección Tareas de una ficha: las tareas activas que ves, vinculadas a un
-- registro que ves. Lo terminado va al final.
CREATE OR REPLACE FUNCTION tareas_de_registro(p_ente text, p_registro_id uuid)
RETURNS TABLE (
  id                uuid,
  titulo            text,
  estado            estado_tarea,
  fecha_vencimiento date,
  responsable       text,
  hilo              text,
  proyecto          text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT t.id, t.titulo, t.estado, t.fecha_vencimiento, u.nombre, h.titulo, p.nombre
  FROM tareas_vinculos v
  JOIN tareas t ON t.id = v.tarea_id AND t.activo
  LEFT JOIN tareas_hilos h ON h.id = t.hilo_id
  LEFT JOIN tareas_proyectos p ON p.id = COALESCE(t.proyecto_id, h.proyecto_id)
  LEFT JOIN usuarios u ON u.id = t.responsable_id
  WHERE v.ente = p_ente AND v.registro_id = p_registro_id AND v.activo
    AND etiqueta_registro(p_ente, p_registro_id) IS NOT NULL
  ORDER BY t.estado IN ('completada', 'cancelada'), t.fecha_vencimiento NULLS LAST, t.created_at DESC;
$$;

-- "Relacionar": lo que encuentra el buscador del módulo y quien busca puede
-- abrir. Lo ajeno enmascarado (id NULL) queda afuera, y `entes` (RLS) deja
-- solo los de submódulos que tenés.
CREATE OR REPLACE FUNCTION buscar_registros(p_texto text)
RETURNS TABLE (
  ente        text,
  registro_id uuid,
  etiqueta    text,
  detalle     text,
  href        text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
  FROM obras_buscar(p_texto) b
  JOIN entes e ON e.codigo = b.tipo
  WHERE b.id IS NOT NULL AND NOT b.es_ajeno;
$$;

-- ============================================================
-- 6. GRANTs — mismo criterio que sql/006 / sql/053
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.etiqueta_registro(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.etiqueta_registro(text, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text, int, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text, int, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.vinculos_de_tareas() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.vinculos_de_tareas() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.tareas_de_registro(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tareas_de_registro(text, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.buscar_registros(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_registros(text) TO authenticated;
