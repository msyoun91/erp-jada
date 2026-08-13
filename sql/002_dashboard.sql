-- Dashboard — preferencias de widgets por usuario
-- Correr en Supabase SQL Editor. Idempotente donde es posible.

CREATE TABLE IF NOT EXISTS usuario_widgets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  widget_id   text NOT NULL,
  visible     boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- UNIQUE normal (no parcial): se actualiza con upsert (onConflict usuario_id,widget_id),
-- misma razón que usuario_submodulos.
DO $$
BEGIN
  ALTER TABLE usuario_widgets
    ADD CONSTRAINT usuario_widgets_usuario_widget_key UNIQUE (usuario_id, widget_id);
EXCEPTION WHEN duplicate_table THEN
  NULL;
END $$;

DROP TRIGGER IF EXISTS set_updated_at ON usuario_widgets;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON usuario_widgets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE usuario_widgets ENABLE ROW LEVEL SECURITY;

-- Preferencia propia: sin lógica de autorización compleja (no pasa por
-- tiene_permiso), así que RLS directo alcanza — no requiere service_role
-- en el server action de toggle (a diferencia de usuarios/usuario_submodulos).
DROP POLICY IF EXISTS usuario_widgets_select ON usuario_widgets;
CREATE POLICY usuario_widgets_select ON usuario_widgets FOR SELECT
  USING (usuario_id = auth.uid());

DROP POLICY IF EXISTS usuario_widgets_insert ON usuario_widgets;
CREATE POLICY usuario_widgets_insert ON usuario_widgets FOR INSERT
  WITH CHECK (usuario_id = auth.uid());

DROP POLICY IF EXISTS usuario_widgets_update ON usuario_widgets;
CREATE POLICY usuario_widgets_update ON usuario_widgets FOR UPDATE
  USING (usuario_id = auth.uid())
  WITH CHECK (usuario_id = auth.uid());

-- Escritura directa (sin service_role) requiere GRANT explícito además de RLS.
GRANT SELECT, INSERT, UPDATE ON public.usuario_widgets TO authenticated;
