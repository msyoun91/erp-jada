-- `/perfil` — cada usuario edita su propio nombre.
--
-- Hasta acá `usuarios` no tenía policy de UPDATE: toda escritura pasaba por
-- server actions con `service_role` (ver el comentario en `sql/001`). El perfil
-- propio no puede ir por ahí — `service_role` ignora RLS, así que "solo tu
-- fila" quedaría escrito en TypeScript en vez de en la base.
--
-- La policy sola no alcanza: `USING`/`WITH CHECK` no pueden comparar la fila
-- vieja contra la nueva, así que con `id = auth.uid()` un usuario podría
-- ponerse `activo = true` y deshacer su propia desactivación (`sql/020`) desde
-- el perfil. El `GRANT UPDATE (nombre)` es lo que cierra eso: el rol
-- `authenticated` no tiene privilegio sobre ninguna otra columna.
--
-- `email` queda afuera a propósito: es la credencial de login y vive en
-- `auth.users` (`sql/021`). Lo cambia un gestor desde el módulo Usuarios.

DROP POLICY IF EXISTS usuarios_update_propio ON usuarios;
CREATE POLICY usuarios_update_propio ON usuarios FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

GRANT UPDATE (nombre) ON public.usuarios TO authenticated;
