-- sql/133 — obras y contactos: bajas y cambios de equipo (tramo 2).
--
-- La baja de un vendedor y su salida de un equipo pasan sus obras (todas:
-- abiertas, perdidas, contratadas, desactivadas) al jefe del `equipo_id`
-- guardado en cada obra, y cierran sus participaciones. Sin jefe que pueda
-- recibir, la obra queda con él: huérfana. Entrar a un equipo desde
-- independiente le pone ese equipo a sus obras y participaciones sin equipo.
--
-- La agenda (personas) pasa al jefe del equipo actual: en la baja, siempre; en
-- el cambio de equipo, si el admin lo elige (`asignar_equipo`, por defecto sí).
-- Las empresas no se mueven: son del equipo.
--
-- Jefe: en Obras, el miembro con `obras_equipo` (uno por equipo, requiere
-- `usuarios_delegar`); en Contactos, el delegador del equipo, con
-- `contactos_ver`. El delegador no sale ni se da de baja sin heredero
-- (`sql/105`), y el heredero recibe la copia de sus permisos antes: en el
-- momento de la entrega, el jefe es otro.
--
-- Huérfana: la obra o la persona cuyo dueño ya no ve el módulo (inactivo o sin
-- la vista), como en Tareas. Campanitas, una por hecho y sobre quien se fue:
-- "obras recibidas" y "agenda recibida" al jefe; "obras huérfanas" y
-- "personas huérfanas" a quienes administran el módulo, en la baja y cuando
-- el dueño pierde la vista. El número se cuenta al leer (`sql/134`).
--
-- Las escrituras corren a profundidad 2 o desde `service_role`: las reglas de
-- actor no aplican; OB006 y CO005 (el destino ve el módulo) sí. Nunca falla.
-- Decisiones: `decisiones/obras.md` → *Bajas y cambios de equipo*,
-- `decisiones/contactos.md` → *La persona se transfiere*. Test:
-- `sql/tests/obras_contactos_bajas.sql`.

-- ============================================================
-- 1. Obras
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_jefe_de(p_equipo uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT m.usuario_id
  FROM public.equipos_miembros m
  JOIN public.equipos e ON e.id = m.equipo_id AND e.activo
  WHERE m.equipo_id = p_equipo
    AND m.activo
    AND public.usuario_tiene_permiso(m.usuario_id, 'obras_equipo')
    AND public.usuario_tiene_permiso(m.usuario_id, 'obras_ver')
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.obras_entregar(p_usuario uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_jefes uuid[];
  v_jefe uuid;
BEGIN
  WITH movidas AS (
    UPDATE public.obras o
    SET responsable_id = d.destino
    FROM (SELECT id, public.obras_jefe_de(id) AS destino FROM public.equipos) d
    WHERE o.responsable_id = p_usuario
      AND d.id = o.equipo_id
      AND d.destino IS NOT NULL
      AND d.destino <> p_usuario
    RETURNING o.responsable_id
  )
  SELECT array_agg(DISTINCT responsable_id) INTO v_jefes FROM movidas;

  FOREACH v_jefe IN ARRAY coalesce(v_jefes, '{}')
  LOOP
    UPDATE public.usuario_notificaciones SET activo = false
    WHERE usuario_id = v_jefe AND tipo = 'obras_recibidas' AND entidad_id = p_usuario AND activo;

    PERFORM public.notificar(v_jefe, 'obras_recibidas', 'usuarios', p_usuario, auth.uid());
  END LOOP;

  UPDATE public.obras_participantes SET activo = false
  WHERE usuario_id = p_usuario AND activo;
END;
$$;

CREATE OR REPLACE FUNCTION public.obras_avisar_huerfanas(p_usuario uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public.usuario_tiene_permiso(p_usuario, 'obras_ver')
     OR NOT EXISTS (SELECT 1 FROM public.obras WHERE responsable_id = p_usuario AND activo) THEN
    RETURN;
  END IF;

  UPDATE public.usuario_notificaciones SET activo = false
  WHERE tipo = 'obras_huerfanas' AND entidad_id = p_usuario AND activo;

  PERFORM public.notificar(u.id, 'obras_huerfanas', 'usuarios', p_usuario, auth.uid())
  FROM public.usuarios u
  WHERE public.usuario_tiene_permiso(u.id, 'obras_administrar');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_jefe_de(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_entregar(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_avisar_huerfanas(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.obras_usuario_baja()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.obras_entregar(NEW.id);
  PERFORM public.obras_avisar_huerfanas(NEW.id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.obras_cambio_de_equipo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.activo AND NOT NEW.activo THEN
    PERFORM public.obras_entregar(NEW.usuario_id);

  ELSIF NEW.activo AND (TG_OP = 'INSERT' OR NOT OLD.activo) THEN
    UPDATE public.obras SET equipo_id = NEW.equipo_id
    WHERE responsable_id = NEW.usuario_id AND equipo_id IS NULL;

    UPDATE public.obras_participantes SET equipo_id = NEW.equipo_id
    WHERE usuario_id = NEW.usuario_id AND equipo_id IS NULL AND activo;
  END IF;
  RETURN NULL;
END;
$$;

-- Diferido, como `tareas_perdida_de_ver`: salir de un equipo le apaga lo
-- delegado antes de que `obras_cambio_de_equipo` entregue.
CREATE OR REPLACE FUNCTION public.obras_perdida_de_ver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.submodulos WHERE id = NEW.submodulo_id AND codigo = 'obras_ver') THEN
    PERFORM public.obras_avisar_huerfanas(NEW.usuario_id);
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_usuario_baja() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_cambio_de_equipo() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_perdida_de_ver() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS obras_usuario_baja ON public.usuarios;
CREATE TRIGGER obras_usuario_baja
  AFTER UPDATE OF activo ON public.usuarios
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.obras_usuario_baja();

DROP TRIGGER IF EXISTS obras_cambio_de_equipo ON public.equipos_miembros;
CREATE TRIGGER obras_cambio_de_equipo
  AFTER INSERT OR UPDATE OF activo ON public.equipos_miembros
  FOR EACH ROW EXECUTE FUNCTION public.obras_cambio_de_equipo();

DROP TRIGGER IF EXISTS obras_perdida_de_ver ON public.usuario_submodulos;
CREATE CONSTRAINT TRIGGER obras_perdida_de_ver
  AFTER UPDATE OF activo ON public.usuario_submodulos
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.obras_perdida_de_ver();

-- ============================================================
-- 2. Contactos — la agenda
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_jefe_de(p_equipo uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT m.usuario_id
  FROM public.equipos_miembros m
  JOIN public.equipos e ON e.id = m.equipo_id AND e.activo
  WHERE m.equipo_id = p_equipo
    AND m.activo
    AND public.usuario_tiene_permiso(m.usuario_id, 'usuarios_delegar')
    AND public.usuario_tiene_permiso(m.usuario_id, 'contactos_ver')
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.contactos_entregar(p_usuario uuid, p_equipo uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_jefe uuid := public.contactos_jefe_de(p_equipo);
BEGIN
  IF v_jefe IS NULL OR v_jefe = p_usuario THEN
    RETURN;
  END IF;

  UPDATE public.contactos_personas SET responsable_id = v_jefe
  WHERE responsable_id = p_usuario;

  IF FOUND THEN
    UPDATE public.usuario_notificaciones SET activo = false
    WHERE usuario_id = v_jefe AND tipo = 'agenda_recibida' AND entidad_id = p_usuario AND activo;

    PERFORM public.notificar(v_jefe, 'agenda_recibida', 'usuarios', p_usuario, auth.uid());
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_avisar_huerfanas(p_usuario uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public.usuario_tiene_permiso(p_usuario, 'contactos_ver')
     OR NOT EXISTS (SELECT 1 FROM public.contactos_personas WHERE responsable_id = p_usuario AND activo) THEN
    RETURN;
  END IF;

  UPDATE public.usuario_notificaciones SET activo = false
  WHERE tipo = 'personas_huerfanas' AND entidad_id = p_usuario AND activo;

  PERFORM public.notificar(u.id, 'personas_huerfanas', 'usuarios', p_usuario, auth.uid())
  FROM public.usuarios u
  WHERE public.usuario_tiene_permiso(u.id, 'contactos_administrar');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_jefe_de(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_entregar(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_avisar_huerfanas(uuid) FROM PUBLIC, anon, authenticated;

-- La baja no apaga la membresía: el equipo actual sigue siendo el suyo.
CREATE OR REPLACE FUNCTION public.contactos_usuario_baja()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.contactos_entregar(NEW.id, public.equipo_de(NEW.id));
  PERFORM public.contactos_avisar_huerfanas(NEW.id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_perdida_de_ver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.submodulos WHERE id = NEW.submodulo_id AND codigo = 'contactos_ver') THEN
    PERFORM public.contactos_avisar_huerfanas(NEW.usuario_id);
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_usuario_baja() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_perdida_de_ver() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS contactos_usuario_baja ON public.usuarios;
CREATE TRIGGER contactos_usuario_baja
  AFTER UPDATE OF activo ON public.usuarios
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.contactos_usuario_baja();

DROP TRIGGER IF EXISTS contactos_perdida_de_ver ON public.usuario_submodulos;
CREATE CONSTRAINT TRIGGER contactos_perdida_de_ver
  AFTER UPDATE OF activo ON public.usuario_submodulos
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.contactos_perdida_de_ver();

-- ============================================================
-- 3. asignar_equipo — el admin elige si la agenda pasa al jefe
-- ============================================================
-- La elección es del momento, no de una regla: por eso la agenda se entrega
-- acá y no desde un trigger de `equipos_miembros`, antes de apagar la
-- membresía (después, `equipo_de` ya no da el anterior).
DROP FUNCTION IF EXISTS public.asignar_equipo(uuid, uuid, uuid);

CREATE OR REPLACE FUNCTION public.asignar_equipo(
  p_admin uuid,
  p_usuario uuid,
  p_equipo uuid,
  p_agenda_al_jefe boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_anterior uuid := public.equipo_de(p_usuario);
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  IF v_anterior IS NOT DISTINCT FROM p_equipo THEN
    RETURN;
  END IF;

  IF p_agenda_al_jefe AND v_anterior IS NOT NULL THEN
    PERFORM public.contactos_entregar(p_usuario, v_anterior);
  END IF;

  UPDATE public.equipos_miembros SET activo = false
  WHERE usuario_id = p_usuario AND activo;

  IF p_equipo IS NOT NULL THEN
    INSERT INTO public.equipos_miembros (equipo_id, usuario_id) VALUES (p_equipo, p_usuario);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.asignar_equipo(uuid, uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.asignar_equipo(uuid, uuid, uuid, boolean) TO service_role;
