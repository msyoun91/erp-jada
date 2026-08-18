-- Módulo tareas — notas (historial, no campo único) en tareas/hilos, y
-- default de visibilidad publico -> privado (tareas, tareas_hilos,
-- tareas_proyectos). Pedido explícito del usuario, no cambia el enum
-- ni el resto del modelo de visibilidad en cascada.
-- Correr en Supabase SQL Editor. Idempotente donde es posible.

-- ============================================================
-- Default de visibilidad: privado (antes publico). Filas existentes
-- no se tocan — solo aplica a inserts nuevos sin valor explícito.
-- ============================================================
ALTER TABLE tareas_proyectos ALTER COLUMN visibilidad SET DEFAULT 'privado';
ALTER TABLE tareas_hilos ALTER COLUMN visibilidad SET DEFAULT 'privado';
ALTER TABLE tareas ALTER COLUMN visibilidad SET DEFAULT 'privado';

-- ============================================================
-- tareas_notas — historial de notas de una tarea. Append-only en la
-- práctica (sin UPDATE de texto): "agregar nota", no "editar nota".
-- activo boolean por "Reglas Siempre Activas" (nunca DELETE) — permite
-- que el autor oculte una nota propia sin perder el registro.
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_notas (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tarea_id   uuid NOT NULL REFERENCES tareas(id),
  usuario_id uuid NOT NULL REFERENCES usuarios(id),
  nota       text NOT NULL,
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_notas_tarea_id ON tareas_notas (tarea_id);

ALTER TABLE tareas_notas ENABLE ROW LEVEL SECURITY;

-- SELECT vía EXISTS sobre `tareas`: la RLS de `tareas` ya resuelve
-- visibilidad en cascada para el rol que consulta — no hace falta
-- repetirla acá. Sin riesgo de recursión: la policy de `tareas` no
-- mira hacia `tareas_notas` (mismo criterio que puede_ver_hilo, pero
-- acá alcanza con EXISTS directo porque la referencia es de ida sola).
DROP POLICY IF EXISTS tareas_notas_select ON tareas_notas;
CREATE POLICY tareas_notas_select ON tareas_notas FOR SELECT
  USING (EXISTS (SELECT 1 FROM tareas t WHERE t.id = tareas_notas.tarea_id));

-- INSERT: mismo actor que puede gestionar la tarea (creador/responsable/
-- asignado activo/tareas_gestionar_ajenas) — reusa las funciones
-- SECURITY DEFINER ya creadas en sql/005 para evitar el mismo problema
-- de recursión que tareas_asignados.
DROP POLICY IF EXISTS tareas_notas_insert ON tareas_notas;
CREATE POLICY tareas_notas_insert ON tareas_notas FOR INSERT
  WITH CHECK (
    usuario_id = auth.uid()
    AND (
      tiene_permiso('tareas_gestionar_ajenas')
      OR es_responsable_o_creador_tarea(tarea_id)
      OR es_asignado_tarea(tarea_id)
    )
  );

-- UPDATE: solo para activo=false (ocultar nota propia) — el autor o ajenas.
DROP POLICY IF EXISTS tareas_notas_update ON tareas_notas;
CREATE POLICY tareas_notas_update ON tareas_notas FOR UPDATE
  USING (usuario_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  WITH CHECK (usuario_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'));

-- ============================================================
-- tareas_hilos_notas — mismo patrón, para hilos. Actor de INSERT es el
-- mismo set que ya gatea las acciones de gestión del hilo en la UI
-- (creador/responsable/tareas_gestionar_ajenas) — no cualquier asignado
-- a una tarea del hilo, para no abrir un tercer actor sin pedido explícito.
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_hilos_notas (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hilo_id    uuid NOT NULL REFERENCES tareas_hilos(id),
  usuario_id uuid NOT NULL REFERENCES usuarios(id),
  nota       text NOT NULL,
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_hilos_notas_hilo_id ON tareas_hilos_notas (hilo_id);

ALTER TABLE tareas_hilos_notas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tareas_hilos_notas_select ON tareas_hilos_notas;
CREATE POLICY tareas_hilos_notas_select ON tareas_hilos_notas FOR SELECT
  USING (EXISTS (SELECT 1 FROM tareas_hilos h WHERE h.id = tareas_hilos_notas.hilo_id));

DROP POLICY IF EXISTS tareas_hilos_notas_insert ON tareas_hilos_notas;
CREATE POLICY tareas_hilos_notas_insert ON tareas_hilos_notas FOR INSERT
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM tareas_hilos h
      WHERE h.id = tareas_hilos_notas.hilo_id
        AND (h.creado_por = auth.uid() OR h.responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
    )
  );

DROP POLICY IF EXISTS tareas_hilos_notas_update ON tareas_hilos_notas;
CREATE POLICY tareas_hilos_notas_update ON tareas_hilos_notas FOR UPDATE
  USING (usuario_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  WITH CHECK (usuario_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'));

-- ============================================================
-- GRANTs — RLS no alcanza sin esto (ver DECISIONES.md).
-- ============================================================
GRANT SELECT, INSERT, UPDATE ON public.tareas_notas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_hilos_notas TO authenticated;
