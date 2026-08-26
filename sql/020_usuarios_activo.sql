-- Un usuario desactivado deja de tener permisos.
--
-- `desactivarUsuario` solo ponía `usuarios.activo = false` y nadie lo leía:
-- `tiene_permiso()` miraba `usuario_submodulos.activo` y `submodulos.activo`,
-- nunca al usuario. El desactivado conservaba la sesión y todos sus permisos,
-- mientras el modal de confirmación prometía que "perderá el acceso".
--
-- La barrera queda en tres capas y esta es la de la base: cubre toda policy que
-- pase por `tiene_permiso`, incluso cuando el request no pasa por Next
-- (PostgREST directo con un access token todavía sin expirar).

CREATE OR REPLACE FUNCTION tiene_permiso(p_codigo text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.usuario_submodulos us
    JOIN public.submodulos s ON s.id = us.submodulo_id
    JOIN public.usuarios u ON u.id = us.usuario_id
    WHERE us.usuario_id = auth.uid()
      AND u.activo
      AND us.activo
      AND s.activo
      AND s.codigo = p_codigo
  );
$$;

-- `usuarios_select` no cambia: la rama `id = auth.uid()` tiene que seguir
-- devolviendo la fila propia al desactivado — es lo que el proxy consulta para
-- echarlo. Y el módulo Usuarios necesita listar inactivos para reactivarlos.
