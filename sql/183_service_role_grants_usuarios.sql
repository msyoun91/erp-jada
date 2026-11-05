-- sql/183 — los permisos de `service_role` que la base real tiene y `sql/` no.
--
-- `sql/004` los atribuye a `sql/006`, que no los tiene. Una base armada solo desde
-- `sql/` daba 42501 en `designar_delegador` y las bajas de usuarios. En la base real
-- no cambia nada.

GRANT SELECT, INSERT, UPDATE ON public.usuario_submodulos TO service_role;
GRANT SELECT, UPDATE ON public.usuarios TO service_role;
GRANT SELECT ON public.submodulos TO service_role;
