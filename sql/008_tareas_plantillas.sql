-- Plantillas de tareas: lista con nombre + ítems, reutilizable al agregar
-- tareas a un hilo. Correr en Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS tareas_plantillas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL,
  creado_por  uuid NOT NULL REFERENCES usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_plantillas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_plantillas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_plantillas ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS tareas_plantillas_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_id  uuid NOT NULL REFERENCES tareas_plantillas(id),
  titulo        text NOT NULL,
  descripcion   text,
  orden         int NOT NULL DEFAULT 0,
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_items_plantilla_id ON tareas_plantillas_items (plantilla_id);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_plantillas_items;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_plantillas_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_plantillas_items ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- RLS — tareas_plantillas es recurso compartido del equipo, no por
-- creador: cualquiera con tareas_plantillas puede editar/desactivar
-- cualquier plantilla. Lectura además abierta a tareas_crear (para
-- poder usarlas al agregar tareas a un hilo sin gestionar el catálogo).
-- ============================================================
DROP POLICY IF EXISTS tareas_plantillas_select ON tareas_plantillas;
CREATE POLICY tareas_plantillas_select ON tareas_plantillas FOR SELECT
  USING (tiene_permiso('tareas_plantillas') OR tiene_permiso('tareas_crear'));

DROP POLICY IF EXISTS tareas_plantillas_insert ON tareas_plantillas;
CREATE POLICY tareas_plantillas_insert ON tareas_plantillas FOR INSERT
  WITH CHECK (creado_por = auth.uid() AND tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_update ON tareas_plantillas;
CREATE POLICY tareas_plantillas_update ON tareas_plantillas FOR UPDATE
  USING (tiene_permiso('tareas_plantillas'))
  WITH CHECK (tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_items_select ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_select ON tareas_plantillas_items FOR SELECT
  USING (tiene_permiso('tareas_plantillas') OR tiene_permiso('tareas_crear'));

DROP POLICY IF EXISTS tareas_plantillas_items_insert ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_insert ON tareas_plantillas_items FOR INSERT
  WITH CHECK (tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_items_update ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_update ON tareas_plantillas_items FOR UPDATE
  USING (tiene_permiso('tareas_plantillas'))
  WITH CHECK (tiene_permiso('tareas_plantillas'));

GRANT SELECT, INSERT, UPDATE ON public.tareas_plantillas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_plantillas_items TO authenticated;

-- ============================================================
-- Seed — nueva vista del módulo tareas
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden)
VALUES ('tareas_plantillas', 'tareas', 'vista', 'Plantillas', 3)
ON CONFLICT DO NOTHING;
