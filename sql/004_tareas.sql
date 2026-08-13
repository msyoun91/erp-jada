-- Módulo tareas — tareas propias/asignadas, agrupadas en hilos (con recurrencia opcional).
-- Correr en Supabase SQL Editor. Idempotente donde es posible.

-- ============================================================
-- Enums
-- ============================================================
DO $$
BEGIN
  CREATE TYPE estado_tarea AS ENUM ('pendiente', 'en_progreso', 'completada');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE recurrencia_hilo AS ENUM ('ninguna', 'diaria', 'semanal', 'mensual');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- ============================================================
-- tareas_hilos — agrupador manual; recurrencia = plantilla que
-- genera tareas automáticamente (ver generar_tareas_recurrentes)
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_hilos (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo              text NOT NULL,
  recurrencia         recurrencia_hilo NOT NULL DEFAULT 'ninguna',
  asignado_a_default  uuid REFERENCES usuarios(id),
  ultima_generacion   date,
  creado_por          uuid NOT NULL REFERENCES usuarios(id),
  activo              boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_hilos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_hilos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hilo_id            uuid REFERENCES tareas_hilos(id),
  titulo             text NOT NULL,
  descripcion        text,
  asignado_a         uuid NOT NULL REFERENCES usuarios(id),
  creado_por         uuid NOT NULL REFERENCES usuarios(id),
  estado             estado_tarea NOT NULL DEFAULT 'pendiente',
  fecha_vencimiento  date,
  activo             boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_hilo_id ON tareas (hilo_id);
CREATE INDEX IF NOT EXISTS idx_tareas_asignado_a ON tareas (asignado_a);

DROP TRIGGER IF EXISTS set_updated_at ON tareas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas_notas — historial de notas por tarea (se ve todo junto
-- en el panel de historial del hilo, sin abrir tarea por tarea)
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_notas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tarea_id    uuid NOT NULL REFERENCES tareas(id),
  usuario_id  uuid NOT NULL REFERENCES usuarios(id),
  nota        text NOT NULL,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_notas_tarea_id ON tareas_notas (tarea_id);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_notas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_notas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_notas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- generar_tareas_recurrentes() — crea la tarea del día/semana/mes
-- para cada hilo-plantilla que corresponda. Se llama desde pg_cron.
-- ============================================================
CREATE OR REPLACE FUNCTION generar_tareas_recurrentes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  h RECORD;
BEGIN
  FOR h IN
    SELECT * FROM tareas_hilos
    WHERE activo
      AND recurrencia <> 'ninguna'
      AND asignado_a_default IS NOT NULL
      AND (
        (recurrencia = 'diaria' AND (ultima_generacion IS NULL OR ultima_generacion < current_date))
        OR (recurrencia = 'semanal' AND (ultima_generacion IS NULL OR ultima_generacion <= current_date - 7))
        OR (recurrencia = 'mensual' AND (ultima_generacion IS NULL OR ultima_generacion <= current_date - interval '1 month'))
      )
  LOOP
    INSERT INTO tareas (hilo_id, titulo, asignado_a, creado_por)
    VALUES (h.id, h.titulo, h.asignado_a_default, h.creado_por);

    UPDATE tareas_hilos SET ultima_generacion = current_date WHERE id = h.id;
  END LOOP;
END;
$$;

-- pg_cron: habilitar la extensión desde Supabase Dashboard -> Database ->
-- Extensions (no siempre corre desde SQL Editor por permisos), luego:
-- SELECT cron.schedule('tareas-generar-recurrentes', '0 6 * * *', $$SELECT generar_tareas_recurrentes()$$);

-- ============================================================
-- RLS policies
-- ============================================================
DROP POLICY IF EXISTS tareas_hilos_select ON tareas_hilos;
CREATE POLICY tareas_hilos_select ON tareas_hilos FOR SELECT
  USING (
    tiene_permiso('tareas_todas')
    OR creado_por = auth.uid()
    OR EXISTS (
      SELECT 1 FROM tareas t
      WHERE t.hilo_id = tareas_hilos.id AND t.asignado_a = auth.uid() AND t.activo
    )
  );

DROP POLICY IF EXISTS tareas_hilos_insert ON tareas_hilos;
CREATE POLICY tareas_hilos_insert ON tareas_hilos FOR INSERT
  WITH CHECK (creado_por = auth.uid() AND tiene_permiso('tareas_crear'));

DROP POLICY IF EXISTS tareas_hilos_update ON tareas_hilos;
CREATE POLICY tareas_hilos_update ON tareas_hilos FOR UPDATE
  USING (creado_por = auth.uid() OR tiene_permiso('tareas_todas'))
  WITH CHECK (creado_por = auth.uid() OR tiene_permiso('tareas_todas'));

DROP POLICY IF EXISTS tareas_select ON tareas;
CREATE POLICY tareas_select ON tareas FOR SELECT
  USING (
    tiene_permiso('tareas_todas')
    OR asignado_a = auth.uid()
    OR creado_por = auth.uid()
  );

DROP POLICY IF EXISTS tareas_insert ON tareas;
CREATE POLICY tareas_insert ON tareas FOR INSERT
  WITH CHECK (
    creado_por = auth.uid()
    AND tiene_permiso('tareas_crear')
    AND (asignado_a = auth.uid() OR tiene_permiso('tareas_asignar'))
  );

DROP POLICY IF EXISTS tareas_update ON tareas;
CREATE POLICY tareas_update ON tareas FOR UPDATE
  USING (
    asignado_a = auth.uid() OR creado_por = auth.uid() OR tiene_permiso('tareas_todas')
  )
  WITH CHECK (
    asignado_a = auth.uid() OR tiene_permiso('tareas_asignar') OR tiene_permiso('tareas_todas')
  );

DROP POLICY IF EXISTS tareas_notas_select ON tareas_notas;
CREATE POLICY tareas_notas_select ON tareas_notas FOR SELECT
  USING (
    tiene_permiso('tareas_todas')
    OR EXISTS (
      SELECT 1 FROM tareas t
      WHERE t.id = tareas_notas.tarea_id AND (t.asignado_a = auth.uid() OR t.creado_por = auth.uid())
    )
  );

DROP POLICY IF EXISTS tareas_notas_insert ON tareas_notas;
CREATE POLICY tareas_notas_insert ON tareas_notas FOR INSERT
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM tareas t
      WHERE t.id = tareas_notas.tarea_id
        AND (t.asignado_a = auth.uid() OR t.creado_por = auth.uid() OR tiene_permiso('tareas_todas'))
    )
  );

DROP POLICY IF EXISTS tareas_notas_update ON tareas_notas;
CREATE POLICY tareas_notas_update ON tareas_notas FOR UPDATE
  USING (usuario_id = auth.uid() OR tiene_permiso('tareas_todas'))
  WITH CHECK (usuario_id = auth.uid() OR tiene_permiso('tareas_todas'));

-- RLS no alcanza sin GRANT (ver DECISIONES.md).
GRANT SELECT, INSERT, UPDATE ON public.tareas_hilos TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_notas TO authenticated;

-- ============================================================
-- Seed — submódulos del módulo tareas
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden)
VALUES
  ('tareas_mistareas', 'tareas', 'vista', 'Mis Tareas', 1),
  ('tareas_todas', 'tareas', 'vista', 'Todas las Tareas', 2)
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'tareas_crear', 'tareas', 'funcion', 'Crear tarea', id, 1
FROM submodulos WHERE codigo = 'tareas_mistareas'
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'tareas_asignar', 'tareas', 'funcion', 'Asignar tarea a otro usuario', id, 2
FROM submodulos WHERE codigo = 'tareas_mistareas'
ON CONFLICT DO NOTHING;
