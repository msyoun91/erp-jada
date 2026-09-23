-- sql/111 — el admin no podía escribir nada de equipos ni permisos desde la app.
--
-- Las funciones de admin de `sql/105`/`sql/106` son INVOKER y la app las llama
-- con `service_role`, pero `usuario_tiene_permiso` y `equipo_de` quedaron con
-- `REVOKE ... FROM PUBLIC` y sin GRANT a `service_role`; y `equipos`,
-- `equipos_miembros` y `submodulos.delegable` no tenían grant de escritura para
-- ese rol. Todo daba 42501. `sql/tests/usuarios_equipos.sql` no lo vio porque
-- corría la parte del admin como `postgres`.

GRANT EXECUTE ON FUNCTION public.usuario_tiene_permiso(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.equipo_de(uuid) TO service_role;

GRANT SELECT, INSERT, UPDATE ON public.equipos TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.equipos_miembros TO service_role;
GRANT UPDATE (delegable) ON public.submodulos TO service_role;
