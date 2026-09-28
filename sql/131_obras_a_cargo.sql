-- sql/131 — obras: la ficha pregunta si quien la abre la tiene a cargo.
--
-- Transferir, desactivar y sumar o quitar participantes piden tenerla a cargo
-- (OB003, OB004, OB013). La UI muestra esos botones con la misma regla, sin
-- copiarla: envoltorio con `auth.uid()`, como `obras_trabaja`. No autoriza
-- nada; los triggers siguen siendo la barrera.

CREATE OR REPLACE FUNCTION public.obras_a_cargo(p_obra uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.obras_a_cargo_de(p_obra, auth.uid());
$$;
REVOKE EXECUTE ON FUNCTION public.obras_a_cargo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_a_cargo(uuid) TO authenticated;
