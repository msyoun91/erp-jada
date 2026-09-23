-- sql/108 — notificaciones: los primeros eventos, de usuarios.
--
-- Decisión: `decisiones/usuarios.md` → *Notificaciones*. Tres tipos que salen
-- de dos escrituras que ya ocurren:
--   miembro_nuevo        — al delegador, cuando el admin le suma alguien al equipo
--   permiso_otorgado     — al usuario, cuando recibe una vista
--   delegador_designado  — la variante del anterior cuando lo que recibe es
--                          `usuarios_delegar` (designación o herencia)
--
-- La sección 1 va en su propia transacción: un valor de enum recién agregado
-- no se puede usar antes del commit, y el cuerpo SQL de
-- `notificaciones_listar` lo castea al crearse.

-- ============================================================
-- 1. Enum
-- ============================================================
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'miembro_nuevo';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'permiso_otorgado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'delegador_designado';

-- ============================================================
-- 2. CHECK de `entidad`
-- ============================================================
ALTER TABLE public.usuario_notificaciones
  DROP CONSTRAINT IF EXISTS usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones
  ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad IN ('equipos_miembros', 'usuario_submodulos'));

-- ============================================================
-- 3a. miembro_nuevo — al delegador del equipo
--
-- Cambiar de equipo siempre inserta una membresía nueva (`asignar_equipo`), así
-- que alcanza con el INSERT. El actor queda NULL: el admin escribe con
-- `service_role` y la membresía no guarda quién la creó.
-- ============================================================
CREATE OR REPLACE FUNCTION public.equipos_miembros_notificar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.notificar(us.usuario_id, 'miembro_nuevo', 'equipos_miembros', NEW.id, (select auth.uid()))
  FROM public.usuario_submodulos us
  JOIN public.submodulos s ON s.id = us.submodulo_id AND s.codigo = 'usuarios_delegar' AND s.activo
  JOIN public.equipos_miembros m ON m.usuario_id = us.usuario_id AND m.activo
  WHERE us.activo AND m.equipo_id = NEW.equipo_id;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.equipos_miembros_notificar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS equipos_miembros_notificar ON public.equipos_miembros;
CREATE TRIGGER equipos_miembros_notificar
  AFTER INSERT ON public.equipos_miembros
  FOR EACH ROW
  WHEN (NEW.activo)
  EXECUTE FUNCTION public.equipos_miembros_notificar();

-- ============================================================
-- 3b. permiso_otorgado / delegador_designado — al que recibe
--
-- Solo vistas: una función nunca llega sola (necesita su vista), y avisar
-- cada checkbox del panel sería una ráfaga. La excepción es `usuarios_delegar`,
-- que es la variante. `usuarios_equipo` no avisa si llega con la delegación:
-- los AFTER ROW corren al final de la sentencia, así que cuando la vista se
-- evalúa la función ya está escrita (`designar_delegador` y la copia de
-- `quitar_delegador` insertan las dos juntas). Un permiso que vuelve deja un
-- solo aviso vivo: el nuevo.
-- ============================================================
CREATE OR REPLACE FUNCTION public.usuario_submodulos_notificar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_codigo text;
  v_tipo   tipo_submodulo;
BEGIN
  SELECT codigo, tipo INTO v_codigo, v_tipo FROM public.submodulos WHERE id = NEW.submodulo_id;

  -- Reactivar reusa la fila: sin esto, el aviso de la vez anterior volvería a
  -- resolverse al lado del nuevo, con el actor de entonces.
  UPDATE public.usuario_notificaciones SET activo = false
  WHERE entidad = 'usuario_submodulos' AND entidad_id = NEW.id AND activo;

  IF v_codigo = 'usuarios_delegar' THEN
    PERFORM public.notificar(NEW.usuario_id, 'delegador_designado', 'usuario_submodulos', NEW.id, NEW.otorgada_por);
  ELSIF v_tipo = 'vista' AND NOT (
    v_codigo = 'usuarios_equipo' AND public.usuario_tiene_permiso(NEW.usuario_id, 'usuarios_delegar')
  ) THEN
    PERFORM public.notificar(NEW.usuario_id, 'permiso_otorgado', 'usuario_submodulos', NEW.id, NEW.otorgada_por);
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.usuario_submodulos_notificar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS usuario_submodulos_notificar_alta ON public.usuario_submodulos;
CREATE TRIGGER usuario_submodulos_notificar_alta
  AFTER INSERT ON public.usuario_submodulos
  FOR EACH ROW
  WHEN (NEW.activo)
  EXECUTE FUNCTION public.usuario_submodulos_notificar();

DROP TRIGGER IF EXISTS usuario_submodulos_notificar_reactiva ON public.usuario_submodulos;
CREATE TRIGGER usuario_submodulos_notificar_reactiva
  AFTER UPDATE OF activo ON public.usuario_submodulos
  FOR EACH ROW
  WHEN (NEW.activo AND NOT OLD.activo)
  EXECUTE FUNCTION public.usuario_submodulos_notificar();

-- ============================================================
-- 4. El nombre de quien lo provocó
--
-- `usuarios_select` no deja que un miembro vea al delegador ni al admin (en
-- `master` lo abrían las ramas de tareas). Abrir la tabla expondría email y
-- teléfono; esto devuelve solo el nombre, y solo de los actores de las
-- notificaciones propias.
-- ============================================================
CREATE OR REPLACE FUNCTION public.notificaciones_actores()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT u.id, u.nombre
  FROM usuario_notificaciones n
  JOIN usuarios u ON u.id = n.actor_id
  WHERE n.usuario_id = auth.uid() AND n.activo;
$$;

REVOKE EXECUTE ON FUNCTION public.notificaciones_actores() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notificaciones_actores() TO authenticated;

-- ============================================================
-- 5. La bandeja — una rama por entidad
--
-- Las dos piden la fila activa: un miembro que se fue o un permiso revocado
-- dejan de ser verdad y el aviso desaparece. `permiso_otorgado` devuelve el
-- módulo en `destino` y el nombre de la vista en `etiqueta`; la UI compone la
-- etiqueta con el label del módulo (`LABEL_MAP`), que no vive en la base.
-- ============================================================
CREATE OR REPLACE FUNCTION public.notificaciones_listar(p_limite int DEFAULT 30)
RETURNS TABLE (
  id         uuid,
  tipo       tipo_notificacion,
  etiqueta   text,
  motivo     text,
  actor      text,
  destino    text,
  destino_id uuid,
  leida      boolean,
  created_at timestamptz
)
LANGUAGE sql STABLE SET search_path = public
AS $$
  WITH mias AS (
    SELECT n.*
    FROM usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo
    ORDER BY n.created_at DESC
    LIMIT greatest(coalesce(p_limite, 30), 1)
  ),
  resuelta AS (
    SELECT n.id AS notificacion_id,
           u.nombre AS etiqueta,
           NULL::text AS motivo,
           'mi_equipo'::text AS destino,
           m.usuario_id AS destino_id
    FROM mias n
    JOIN equipos_miembros m ON m.id = n.entidad_id AND m.activo
    JOIN usuarios u         ON u.id = m.usuario_id
    WHERE n.entidad = 'equipos_miembros'

    UNION ALL

    SELECT n.id,
           CASE WHEN n.tipo = 'delegador_designado' THEN e.nombre ELSE s.nombre END,
           NULL::text,
           CASE WHEN n.tipo = 'delegador_designado' THEN 'mi_equipo' ELSE s.modulo END,
           us.id
    FROM mias n
    JOIN usuario_submodulos us ON us.id = n.entidad_id AND us.activo
    JOIN submodulos s          ON s.id = us.submodulo_id
    LEFT JOIN equipos e        ON e.id = mi_equipo()
    WHERE n.entidad = 'usuario_submodulos'
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.notificaciones_listar(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notificaciones_listar(int) TO authenticated;
