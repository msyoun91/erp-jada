-- sql/102 — reparar `tiene_permiso`: `sql/101` le sacó el chequeo de `usuarios.activo`
--
-- `sql/101` tenía que devolver `tiene_permiso` a un cuerpo propio, porque el que
-- estaba delegaba en `usuario_tiene_permiso` (`sql/062`) y esa función se iba con
-- la infra cross-módulo. Restauró el cuerpo de `sql/001` — que es anterior a
-- `sql/020`, donde se había agregado el `JOIN usuarios u ... AND u.activo`.
--
-- Efecto mientras estuvo mal: **un usuario desactivado conservaba todos sus
-- permisos en RLS.** La barrera del proxy seguía en pie (`usuarios_select` le
-- devuelve su propia fila al desactivado, que es lo que lo echa del sistema),
-- así que no había sesión desde la que explotara — pero la autorización en base
-- sí estaba abierta, que es exactamente lo que `sql/020` vino a cerrar.
--
-- La lección, para el sistema de permisos nuevo: **un rollback que "vuelve" una
-- función a una versión anterior tiene que volver a la última buena, no a la
-- primera.** Entre `sql/001` y hoy, `tiene_permiso` se tocó una vez más de lo
-- que el rollback miró. Verificable con `sql/tests/usuarios_activo.sql`.

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

-- Verificación:
--   SELECT pg_get_functiondef(oid) LIKE '%u.activo%'
--     FROM pg_proc WHERE proname = 'tiene_permiso';   -- true
