-- ============================================================
-- 121 — "gana el admin" como gesto explícito
-- ============================================================
-- `asignar_submodulos` no le cambia el dueño a una fila activa: guardar el
-- panel no se apropia de lo delegado. `p_tomar` es el gesto: esas filas, si
-- siguen asignadas, pasan a `otorgada_por = admin`; el delegador ya no las
-- revoca y no caen en su cascada.

DROP FUNCTION IF EXISTS public.asignar_submodulos(uuid, uuid, uuid[]);

CREATE OR REPLACE FUNCTION public.asignar_submodulos(
  p_admin uuid,
  p_usuario uuid,
  p_submodulos uuid[],
  p_tomar uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  UPDATE public.usuario_submodulos SET activo = false
  WHERE usuario_id = p_usuario AND activo AND submodulo_id <> ALL (p_submodulos);

  INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, otorgada_por, activo)
  SELECT DISTINCT p_usuario, x, p_admin, true FROM unnest(p_submodulos) AS x
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE
    SET activo = true, otorgada_por = EXCLUDED.otorgada_por
    WHERE NOT public.usuario_submodulos.activo;

  UPDATE public.usuario_submodulos SET otorgada_por = p_admin
  WHERE usuario_id = p_usuario AND activo
    AND submodulo_id = ANY (p_tomar) AND submodulo_id = ANY (p_submodulos)
    AND otorgada_por IS DISTINCT FROM p_admin;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.asignar_submodulos(uuid, uuid, uuid[], uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.asignar_submodulos(uuid, uuid, uuid[], uuid[]) TO service_role;
