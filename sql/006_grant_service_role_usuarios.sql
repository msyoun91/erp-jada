-- Bug pre-existente encontrado al probar el módulo tareas: el rol service_role
-- nunca tuvo GRANT en usuarios/usuario_submodulos (sql/001 solo otorgó a
-- authenticated). Los server actions con cliente admin (modules/usuarios/actions.ts)
-- fallan con "permission denied for table" (42501) al hacer UPDATE/INSERT.
-- Confirmado pegándole directo a PostgREST con la service_role key:
-- {"code":"42501","hint":"Grant the required privileges to the current role
--  with: GRANT SELECT ON public.usuario_submodulos TO service_role."}
-- Correr en Supabase SQL Editor.

GRANT SELECT, UPDATE ON public.usuarios TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.usuario_submodulos TO service_role;
GRANT SELECT ON public.submodulos TO service_role;
