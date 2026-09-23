-- sql/106 — la pestaña Equipos: vista, lectura y las escrituras del admin.
--
-- La vista `usuarios_equipos` solo decide quién ve la pestaña y qué puede leer.
-- Escribir sigue siendo de `usuarios_gestionar`: la autoridad de admin es una
-- sola, y las reglas de `sql/105` ya la usan para definir quién es admin.
-- Decisión: `decisiones/usuarios.md` → *La pestaña Equipos*. Verificado con
-- `sql/tests/usuarios_equipos.sql`.

-- ============================================================
-- Catálogo
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden)
SELECT 'usuarios_equipos', 'usuarios', 'vista', 'Equipos', 2
WHERE NOT EXISTS (
  SELECT 1 FROM public.submodulos WHERE codigo = 'usuarios_equipos' AND activo
);

UPDATE public.submodulos SET orden = 3 WHERE codigo = 'usuarios_equipo' AND activo;

-- Quien hoy administra usuarios es quien arma los equipos.
INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, activo)
SELECT us.usuario_id, v.id, true
FROM public.usuario_submodulos us
JOIN public.submodulos g ON g.id = us.submodulo_id AND g.codigo = 'usuarios_gestionar'
CROSS JOIN public.submodulos v
WHERE us.activo AND v.codigo = 'usuarios_equipos' AND v.activo
ON CONFLICT (usuario_id, submodulo_id) DO UPDATE SET activo = true;

-- ============================================================
-- Lectura: la pestaña ve todos los equipos, sus miembros y los permisos de
-- los miembros (para marcar al delegador). No ve permisos de independientes.
-- ============================================================
DROP POLICY IF EXISTS equipos_select ON public.equipos;
CREATE POLICY equipos_select ON public.equipos FOR SELECT
  USING (
    tiene_permiso('usuarios_ver')
    OR tiene_permiso('usuarios_equipos')
    OR (tiene_permiso('usuarios_equipo') AND id = mi_equipo())
  );

DROP POLICY IF EXISTS equipos_miembros_select ON public.equipos_miembros;
CREATE POLICY equipos_miembros_select ON public.equipos_miembros FOR SELECT
  USING (
    tiene_permiso('usuarios_ver')
    OR tiene_permiso('usuarios_equipos')
    OR (tiene_permiso('usuarios_equipo') AND activo AND equipo_id = mi_equipo())
  );

DROP POLICY IF EXISTS usuarios_select ON public.usuarios;
CREATE POLICY usuarios_select ON public.usuarios FOR SELECT
  USING (
    id = (select auth.uid())
    OR tiene_permiso('usuarios_ver')
    OR tiene_permiso('usuarios_equipos')
    OR (
      tiene_permiso('usuarios_equipo')
      AND id IN (
        SELECT usuario_id FROM public.equipos_miembros
        WHERE activo AND equipo_id = mi_equipo()
      )
    )
  );

DROP POLICY IF EXISTS usuario_submodulos_select ON public.usuario_submodulos;
CREATE POLICY usuario_submodulos_select ON public.usuario_submodulos FOR SELECT
  USING (
    usuario_id = (select auth.uid())
    OR tiene_permiso('usuarios_gestionar')
    OR (
      tiene_permiso('usuarios_equipos')
      AND usuario_id IN (SELECT usuario_id FROM public.equipos_miembros WHERE activo)
    )
    OR (
      tiene_permiso('usuarios_equipo')
      AND usuario_id IN (
        SELECT usuario_id FROM public.equipos_miembros
        WHERE activo AND equipo_id = mi_equipo()
      )
    )
  );

DROP POLICY IF EXISTS submodulos_select ON public.submodulos;
CREATE POLICY submodulos_select ON public.submodulos FOR SELECT
  USING (
    tiene_permiso('usuarios_gestionar')
    OR tiene_permiso('usuarios_equipos')
    OR tiene_permiso('usuarios_equipo')
    OR id IN (
      SELECT submodulo_id FROM public.usuario_submodulos
      WHERE usuario_id = (select auth.uid()) AND activo
    )
  );

-- ============================================================
-- asignar_equipo — mover a un usuario de equipo, o dejarlo independiente
-- ============================================================
-- Cambiar de equipo son dos escrituras (apagar la membresía, crear otra): van
-- juntas o ninguna. Las reglas (admin fuera, delegador no sale, equipo activo,
-- lo delegado no viaja) las pone `equipos_miembros_validar`.
CREATE OR REPLACE FUNCTION public.asignar_equipo(p_admin uuid, p_usuario uuid, p_equipo uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  IF public.equipo_de(p_usuario) IS NOT DISTINCT FROM p_equipo THEN
    RETURN;
  END IF;

  UPDATE public.equipos_miembros SET activo = false
  WHERE usuario_id = p_usuario AND activo;

  IF p_equipo IS NOT NULL THEN
    INSERT INTO public.equipos_miembros (equipo_id, usuario_id) VALUES (p_equipo, p_usuario);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.asignar_equipo(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.asignar_equipo(uuid, uuid, uuid) TO service_role;

-- ============================================================
-- designar_delegador — le da la función y su vista
-- ============================================================
-- Que sea miembro y que el equipo no tenga otro lo valida el trigger diferido.
CREATE OR REPLACE FUNCTION public.designar_delegador(p_admin uuid, p_usuario uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, otorgada_por, activo)
  SELECT p_usuario, s.id, p_admin, true
  FROM public.submodulos s
  WHERE s.codigo IN ('usuarios_equipo', 'usuarios_delegar') AND s.activo
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE
    SET activo = true, otorgada_por = EXCLUDED.otorgada_por
    WHERE NOT public.usuario_submodulos.activo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.designar_delegador(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.designar_delegador(uuid, uuid) TO service_role;

-- ============================================================
-- fijar_delegables — el conjunto de submódulos que se pueden delegar
-- ============================================================
-- Apagar primero dispara `submodulos_deja_de_ser_delegable`, que revoca lo
-- delegado; el CHECK rechaza cualquier submódulo de usuarios.
CREATE OR REPLACE FUNCTION public.fijar_delegables(p_admin uuid, p_submodulos uuid[])
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  UPDATE public.submodulos SET delegable = false
  WHERE delegable AND id <> ALL (p_submodulos);

  UPDATE public.submodulos SET delegable = true
  WHERE NOT delegable AND id = ANY (p_submodulos);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fijar_delegables(uuid, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fijar_delegables(uuid, uuid[]) TO service_role;
