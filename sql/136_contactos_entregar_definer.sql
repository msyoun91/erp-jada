-- sql/136 — `contactos_entregar` corre como su dueño.
--
-- `asignar_equipo` es INVOKER y la llama `service_role`, que no tiene UPDATE
-- sobre `contactos_personas`: el cambio de equipo con agenda al jefe fallaba
-- con 42501. Las entregas de Obras no lo sufren porque las llaman triggers
-- DEFINER. Sin GRANT a `authenticated` (`sql/133`); EXECUTE para
-- `service_role` desde `sql/135`.
ALTER FUNCTION public.contactos_entregar(uuid, uuid) SECURITY DEFINER;
