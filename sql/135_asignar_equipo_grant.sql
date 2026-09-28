-- sql/135 — `asignar_equipo` corre como `service_role` e INVOKER: llama directo
-- a `contactos_entregar` (y esta, a `contactos_jefe_de`), y el REVOKE de
-- `sql/133` le dejó 42501 al cambiar de equipo a quien ya tenía uno.
GRANT EXECUTE ON FUNCTION public.contactos_entregar(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.contactos_jefe_de(uuid) TO service_role;
