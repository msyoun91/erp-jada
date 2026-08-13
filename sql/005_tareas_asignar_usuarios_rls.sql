-- tareas_asignar necesita listar usuarios activos para elegir a quién asignar.
-- La policy usuarios_select (sql/001) solo dejaba ver la fila propia o con
-- usuarios_ver — sin esto, el select de getUsuariosParaAsignar() devuelve
-- solo el propio usuario para cualquiera sin usuarios_ver.
-- Correr en Supabase SQL Editor.

DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT
  USING (
    id = auth.uid()
    OR tiene_permiso('usuarios_ver')
    OR tiene_permiso('tareas_asignar')
  );
