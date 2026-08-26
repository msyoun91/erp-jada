-- Tutorial guiado — qué pasos ya vio cada usuario.
--
-- Tabla de infraestructura cross-módulo (sin prefijo, como `usuario_widgets`):
-- el namespace vive en el código del paso (`tareas_lista_isla`), no en el
-- nombre de la tabla. Un segundo módulo con tutorial no necesita tabla nueva.
--
-- Sin columna `activo`: una fila significa "visto" y nunca se borra ni se
-- desactiva. Volver a ver el tutorial es el botón de la vista, no un reset de
-- datos — la fila no tiene otro estado que existir.

CREATE TABLE IF NOT EXISTS usuario_tutorial (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  paso        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- UNIQUE constraint y no índice único parcial: el upsert de Supabase
-- (`onConflict`) no funciona con índices parciales.
DO $$ BEGIN
  ALTER TABLE usuario_tutorial
    ADD CONSTRAINT usuario_tutorial_usuario_paso_key UNIQUE (usuario_id, paso);
EXCEPTION WHEN duplicate_table THEN
  NULL;
END $$;

DROP TRIGGER IF EXISTS set_updated_at ON usuario_tutorial;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON usuario_tutorial
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE usuario_tutorial ENABLE ROW LEVEL SECURITY;

-- Preferencia estrictamente propia: no pasa por `tiene_permiso`, así que RLS
-- directo alcanza y el server action usa el cliente normal (mismo criterio que
-- `usuario_widgets`, no el de `usuarios`/`usuario_submodulos`).
DROP POLICY IF EXISTS usuario_tutorial_select ON usuario_tutorial;
CREATE POLICY usuario_tutorial_select ON usuario_tutorial FOR SELECT
  USING (usuario_id = auth.uid());

DROP POLICY IF EXISTS usuario_tutorial_insert ON usuario_tutorial;
CREATE POLICY usuario_tutorial_insert ON usuario_tutorial FOR INSERT
  WITH CHECK (usuario_id = auth.uid());

DROP POLICY IF EXISTS usuario_tutorial_update ON usuario_tutorial;
CREATE POLICY usuario_tutorial_update ON usuario_tutorial FOR UPDATE
  USING (usuario_id = auth.uid())
  WITH CHECK (usuario_id = auth.uid());

-- Escritura directa (sin service_role) requiere GRANT además de RLS.
GRANT SELECT, INSERT, UPDATE ON public.usuario_tutorial TO authenticated;
