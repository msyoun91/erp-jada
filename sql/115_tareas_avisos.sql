-- sql/115 — tareas: los avisos.
--
-- Los tipos de la campanita de la ficha (`decisiones/tareas/README.md` →
-- *Eventos que emite*), `transferencia` en `tipo_evento` y los `relacion_*`
-- del asignado. Quedan para cuando existan plantillas y recurrencia: "paso a
-- reasignar" al crear un paso desde un trigger (`BACKLOG.md`).
-- Decisiones: `decisiones/tareas/avisos.md`. Verificado con
-- `sql/tests/tareas_avisos.sql`.
--
-- Los avisos salen de los triggers de tareas con OLD y NEW, no de un
-- consumidor de `eventos`: una sentencia emite varios eventos (relación que se
-- va, relación que llega, estado) y el aviso depende de la combinación.
--
-- La sección 1 va en su propia transacción: un valor de enum recién agregado
-- no se puede usar antes del commit, y el cuerpo SQL de
-- `notificaciones_listar` lo castea al crearse.

-- ============================================================
-- 1. Enums
-- ============================================================
ALTER TYPE tipo_evento ADD VALUE IF NOT EXISTS 'transferencia';

ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'tarea_asignada';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'pedido_recibido';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_editado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'pedido_aceptado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'pedido_rechazado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_reabierto';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'hilo_transferido';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_habilitado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_bloqueado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_reasignado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_quitado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_a_reasignar';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_sumado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_huerfano';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'hilos_huerfanos';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'hilo_dado_de_baja';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_dado_de_baja';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_completado';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'paso_cancelado';

-- ============================================================
-- 2. Eventos: `transferencia` y el asignado
-- ============================================================

-- TG_ARGV = (ente[, columna del dueño]). Con dueño, cambiarlo emite
-- `transferencia` con `{de, a}` (GUIDE_ENTES §2.8).
CREATE OR REPLACE FUNCTION public.emitir_eventos_registro()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ente   text    := TG_ARGV[0];
  v_dueno  text    := TG_ARGV[1];
  v_nueva  jsonb   := to_jsonb(NEW);
  v_vieja  jsonb   := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_activo boolean := (v_nueva->>'activo')::boolean;
  v_estaba boolean := (v_vieja->>'activo')::boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT v_activo THEN
      RETURN NULL;
    END IF;
    PERFORM emitir_evento(v_ente, NEW.id, 'alta');
  ELSIF v_activo AND NOT v_estaba THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'reactivacion');
  END IF;

  IF v_nueva ? 'estado' AND v_nueva->>'estado' IS DISTINCT FROM v_vieja->>'estado' THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'estado',
      jsonb_build_object('estado', v_nueva->>'estado', 'anterior', v_vieja->>'estado'));
  END IF;

  IF TG_OP = 'UPDATE' AND v_dueno IS NOT NULL AND v_nueva->>v_dueno IS DISTINCT FROM v_vieja->>v_dueno THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'transferencia',
      jsonb_build_object('de', v_vieja->>v_dueno, 'a', v_nueva->>v_dueno));
  END IF;

  IF v_estaba AND NOT v_activo THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'baja');
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS emitir_eventos ON public.tareas_hilos;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado, responsable_id ON public.tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('hilo', 'responsable_id');

-- El asignado es columna, no puente: `emitir_eventos_relacion` no sirve. Un
-- evento por asignado que llega o se va. INVOKER, como los otros emisores.
CREATE OR REPLACE FUNCTION public.tareas_emitir_asignado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.asignado_id IS NOT DISTINCT FROM OLD.asignado_id
       AND NEW.asignado_equipo_id IS NOT DISTINCT FROM OLD.asignado_equipo_id THEN
      RETURN NULL;
    END IF;
    PERFORM emitir_evento('tarea', NEW.id, 'relacion_baja', jsonb_build_object(
      'ente', CASE WHEN OLD.asignado_id IS NULL THEN 'equipo' ELSE 'usuario' END,
      'registro_id', coalesce(OLD.asignado_id, OLD.asignado_equipo_id),
      'rol', 'asignado'));
  END IF;

  PERFORM emitir_evento('tarea', NEW.id, 'relacion_alta', jsonb_build_object(
    'ente', CASE WHEN NEW.asignado_id IS NULL THEN 'equipo' ELSE 'usuario' END,
    'registro_id', coalesce(NEW.asignado_id, NEW.asignado_equipo_id),
    'rol', 'asignado'));
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_emitir_asignado() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS emitir_eventos_asignado ON public.tareas;
CREATE TRIGGER emitir_eventos_asignado
  AFTER INSERT OR UPDATE OF asignado_id, asignado_equipo_id ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_emitir_asignado();

-- Quien ve el paso ve quién lo tuvo: el asignado es una columna del paso.
CREATE OR REPLACE FUNCTION public.puede_ver_relacion(p_ente text, p_id uuid, p_ente_rel text, p_id_rel uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'tareas' THEN public.tareas_etiqueta(p_ente, p_id) IS NOT NULL
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), false);
$$;

-- ============================================================
-- 3. CHECK de `entidad`
-- ============================================================
ALTER TABLE public.usuario_notificaciones
  DROP CONSTRAINT IF EXISTS usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones
  ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad IN ('equipos_miembros', 'usuario_submodulos', 'tareas', 'tareas_hilos', 'usuarios'));

-- ============================================================
-- 4. Helpers — sin GRANT
-- ============================================================

-- Asignado = equipo → el aviso le llega a su delegador.
CREATE OR REPLACE FUNCTION public.tareas_destinatario(p_usuario uuid, p_equipo uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT coalesce(p_usuario, public.tareas_delegador_de(p_equipo));
$$;

-- Al asignado de un paso que le llega: "pedido recibido" si hay que decidirlo
-- —también al delegador de la persona—, "tarea asignada" si no.
CREATE OR REPLACE FUNCTION public.tareas_avisar_asignado(p public.tareas)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  PERFORM public.notificar(d.usuario,
    CASE WHEN p.estado = 'solicitada' THEN 'pedido_recibido' ELSE 'tarea_asignada' END::tipo_notificacion,
    'tareas', p.id, auth.uid())
  FROM (
    SELECT public.tareas_destinatario(p.asignado_id, p.asignado_equipo_id)
    UNION
    SELECT public.tareas_delegador_de(p.equipo_id) WHERE p.estado = 'solicitada'
  ) AS d (usuario);
END;
$$;

-- *Sin destino, queda huérfano*: al responsable de cada paso abierto que le
-- quedó, y a quienes tienen `tareas_administrar` si le quedaron hilos abiertos
-- — uno por hecho, que reemplaza al anterior sobre la misma persona.
CREATE OR REPLACE FUNCTION public.tareas_avisar_huerfanos(p_usuario uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public.tareas_puede_recibir(p_usuario, NULL) THEN
    RETURN;
  END IF;

  PERFORM public.notificar(h.responsable_id, 'paso_huerfano', 'tareas', t.id, auth.uid())
  FROM public.tareas t
  JOIN public.tareas_hilos h ON h.id = t.hilo_id AND h.activo
  WHERE t.asignado_id = p_usuario
    AND t.activo
    AND t.estado IN ('solicitada', 'pendiente', 'rechazada')
    AND h.responsable_id <> p_usuario;

  IF EXISTS (
    SELECT 1 FROM public.tareas_hilos
    WHERE responsable_id = p_usuario AND activo AND estado = 'abierto'
  ) THEN
    UPDATE public.usuario_notificaciones SET activo = false
    WHERE tipo = 'hilos_huerfanos' AND entidad_id = p_usuario AND activo;

    PERFORM public.notificar(u.id, 'hilos_huerfanos', 'usuarios', p_usuario, auth.uid())
    FROM public.usuarios u
    WHERE public.usuario_tiene_permiso(u.id, 'tareas_administrar');
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_destinatario(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_avisar_asignado(public.tareas) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_avisar_huerfanos(uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 5. Avisos del paso
--
-- Nunca al que hizo la acción (`notificar`), y una sola vez por persona y
-- cambio: quien recibe el paso no recibe además "paso reasignado".
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_resp uuid;
  v_nuevo uuid := public.tareas_destinatario(NEW.asignado_id, NEW.asignado_equipo_id);
  v_viejo uuid;
  v_reasigna boolean;
BEGIN
  SELECT responsable_id INTO v_resp FROM public.tareas_hilos WHERE id = NEW.hilo_id;

  IF TG_OP = 'INSERT' THEN
    PERFORM public.tareas_avisar_asignado(NEW);
    IF v_uid IS DISTINCT FROM v_resp THEN
      PERFORM public.notificar(v_resp, 'paso_sumado', 'tareas', NEW.id, v_uid);
    END IF;
    RETURN NULL;
  END IF;

  v_viejo := public.tareas_destinatario(OLD.asignado_id, OLD.asignado_equipo_id);
  v_reasigna := NEW.asignado_id IS DISTINCT FROM OLD.asignado_id
                OR NEW.asignado_equipo_id IS DISTINCT FROM OLD.asignado_equipo_id;

  IF NOT NEW.activo THEN
    IF OLD.activo THEN
      PERFORM public.notificar(v_viejo, 'paso_dado_de_baja', 'tareas', NEW.id, v_uid);
    END IF;
    RETURN NULL;
  END IF;

  -- Reabrir o reactivar con un asignado que ya no puede recibir lo dejó en el
  -- responsable (`tareas_al_editar`).
  IF v_reasigna AND (NOT OLD.activo OR OLD.estado IN ('completada', 'cancelada')) THEN
    PERFORM public.notificar(v_resp, 'paso_a_reasignar', 'tareas', NEW.id, v_uid);
    RETURN NULL;
  END IF;

  IF NOT OLD.activo THEN
    RETURN NULL;
  END IF;

  IF v_reasigna THEN
    PERFORM public.tareas_avisar_asignado(NEW);

    -- Al que lo pierde, si sigue: la baja, el cambio de equipo y la pérdida
    -- de `tareas_ver` no le avisan.
    IF v_viejo IS DISTINCT FROM v_nuevo AND (
         OLD.asignado_id IS NULL
         OR (public.tareas_puede_recibir(OLD.asignado_id, NULL)
             AND public.equipo_de(OLD.asignado_id) IS NOT DISTINCT FROM OLD.equipo_id)
       ) THEN
      PERFORM public.notificar(v_viejo, 'paso_quitado', 'tareas', NEW.id, v_uid);
    END IF;

    IF v_resp IS DISTINCT FROM v_nuevo AND v_resp IS DISTINCT FROM v_viejo THEN
      PERFORM public.notificar(v_resp, 'paso_reasignado', 'tareas', NEW.id, v_uid);
    END IF;
    RETURN NULL;
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    IF NEW.estado = 'solicitada' OR (OLD.estado = 'rechazada' AND NEW.estado = 'pendiente') THEN
      PERFORM public.tareas_avisar_asignado(NEW);
    ELSIF OLD.estado = 'solicitada' AND NEW.estado = 'pendiente' THEN
      PERFORM public.notificar(v_resp, 'pedido_aceptado', 'tareas', NEW.id, v_uid);
    ELSIF NEW.estado = 'rechazada' THEN
      PERFORM public.notificar(v_resp, 'pedido_rechazado', 'tareas', NEW.id, v_uid);
    ELSIF NEW.estado = 'completada' THEN
      PERFORM public.notificar(v_resp, 'paso_completado', 'tareas', NEW.id, v_uid);
    ELSIF NEW.estado = 'cancelada' THEN
      PERFORM public.notificar(v_nuevo, 'paso_cancelado', 'tareas', NEW.id, v_uid);
    ELSE
      PERFORM public.notificar(v_nuevo, 'paso_reabierto', 'tareas', NEW.id, v_uid);
    END IF;

  -- Lo que edita una persona, como `tareas_registrar_ediciones`; el
  -- vencimiento que deriva la base no es una edición.
  ELSIF pg_trigger_depth() = 1 AND v_uid IS NOT NULL AND (
    NEW.titulo IS DISTINCT FROM OLD.titulo
    OR NEW.descripcion IS DISTINCT FROM OLD.descripcion
    OR NEW.vence IS DISTINCT FROM OLD.vence
    OR NEW.vence_dias IS DISTINCT FROM OLD.vence_dias
  ) THEN
    PERFORM public.notificar(v_nuevo, 'paso_editado', 'tareas', NEW.id, v_uid);
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_avisar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_avisar ON public.tareas;
CREATE TRIGGER tareas_avisar
  AFTER INSERT OR UPDATE OF asignado_id, asignado_equipo_id, estado, activo, titulo, descripcion, vence, vence_dias
  ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_avisar();

-- `sql/113` + los avisos de la cadena: habilitarse avisa siempre; bloquearse,
-- solo al insertar antes (reabrir el previo avisa "paso reabierto").
CREATE OR REPLACE FUNCTION public.tareas_propagar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sig uuid;
  v_trababa boolean;
  v_traba boolean;
BEGIN
  IF NEW.activo AND NEW.estado IN ('solicitada', 'pendiente', 'rechazada') THEN
    UPDATE public.tareas_hilos SET estado = 'abierto' WHERE id = NEW.hilo_id AND estado = 'cerrado';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
    RETURN NULL;
  END IF;

  v_sig := public.tareas_siguiente_efectivo(NEW.id);
  IF v_sig IS NULL THEN
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.estado IN ('completada', 'cancelada')
     AND NEW.estado IN ('solicitada', 'pendiente', 'rechazada') THEN
    UPDATE public.tareas SET estado = 'pendiente' WHERE id = v_sig AND estado = 'completada';
  END IF;

  -- En un INSERT solo hay siguiente si es *Insertar antes de*: antes lo
  -- trababa el previo del paso nuevo.
  v_trababa := CASE
    WHEN TG_OP = 'INSERT' OR OLD.estado = 'cancelada' THEN public.tareas_bloquea(NEW.paso_anterior_id)
    ELSE OLD.estado <> 'completada'
  END;
  v_traba := public.tareas_bloquea(NEW.id);

  IF v_trababa IS DISTINCT FROM v_traba THEN
    UPDATE public.tareas
    SET vence = CASE WHEN v_traba THEN NULL ELSE public.tareas_hoy() + vence_dias END
    WHERE id = v_sig AND vence_dias IS NOT NULL AND estado IN ('solicitada', 'pendiente', 'rechazada');

    IF NOT v_traba OR TG_OP = 'INSERT' THEN
      PERFORM public.notificar(public.tareas_destinatario(t.asignado_id, t.asignado_equipo_id),
        CASE WHEN v_traba THEN 'paso_bloqueado' ELSE 'paso_habilitado' END::tipo_notificacion,
        'tareas', t.id, auth.uid())
      FROM public.tareas t
      WHERE t.id = v_sig AND t.estado IN ('solicitada', 'pendiente');
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- ============================================================
-- 6. Avisos del hilo
-- ============================================================
-- Transferido: solo si está abierto (la baja mueve también los cerrados, y
-- esos no avisan). Dado de baja: a los asignados de sus pasos abiertos.
CREATE OR REPLACE FUNCTION public.tareas_hilos_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id AND NEW.activo AND NEW.estado = 'abierto' THEN
    PERFORM public.notificar(NEW.responsable_id, 'hilo_transferido', 'tareas_hilos', NEW.id, auth.uid());
  END IF;

  IF OLD.activo AND NOT NEW.activo THEN
    PERFORM public.notificar(d.usuario, 'hilo_dado_de_baja', 'tareas_hilos', NEW.id, auth.uid())
    FROM (
      SELECT DISTINCT public.tareas_destinatario(t.asignado_id, t.asignado_equipo_id)
      FROM public.tareas t
      WHERE t.hilo_id = NEW.id AND t.activo AND t.estado IN ('solicitada', 'pendiente', 'rechazada')
    ) AS d (usuario);
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_hilos_avisar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_hilos_avisar ON public.tareas_hilos;
CREATE TRIGGER tareas_hilos_avisar
  AFTER UPDATE OF responsable_id, activo ON public.tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION public.tareas_hilos_avisar();

-- ============================================================
-- 7. Huérfanos: la baja y la pérdida de `tareas_ver`
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_usuario_baja()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.tareas_entregar(NEW.id);
  PERFORM public.tareas_avisar_huerfanos(NEW.id);
  RETURN NULL;
END;
$$;

-- Diferido: salir de un equipo le apaga lo delegado (`tareas_ver` incluido)
-- antes de que `tareas_cambio_de_equipo` entregue; al cierre, ya se entregó.
CREATE OR REPLACE FUNCTION public.tareas_perdida_de_ver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.submodulos WHERE id = NEW.submodulo_id AND codigo = 'tareas_ver') THEN
    PERFORM public.tareas_avisar_huerfanos(NEW.usuario_id);
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_perdida_de_ver() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_perdida_de_ver ON public.usuario_submodulos;
CREATE CONSTRAINT TRIGGER tareas_perdida_de_ver
  AFTER UPDATE OF activo ON public.usuario_submodulos
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION public.tareas_perdida_de_ver();

-- ============================================================
-- 8. La bandeja
-- ============================================================

-- Lo que el destinatario perdió (paso quitado, paso o hilo dados de baja) ya
-- no pasa su RLS: el título sale de acá, solo para esos tipos y solo de los
-- avisos propios, como el nombre en `notificaciones_actores`.
CREATE OR REPLACE FUNCTION public.tareas_avisos_salida()
RETURNS TABLE (notificacion_id uuid, titulo text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT n.id, coalesce(t.titulo, h.titulo)
  FROM usuario_notificaciones n
  LEFT JOIN tareas t       ON n.entidad = 'tareas' AND t.id = n.entidad_id
  LEFT JOIN tareas_hilos h ON n.entidad = 'tareas_hilos' AND h.id = n.entidad_id
  WHERE n.usuario_id = auth.uid()
    AND n.activo
    AND n.tipo IN ('paso_quitado', 'paso_dado_de_baja', 'hilo_dado_de_baja');
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_avisos_salida() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_avisos_salida() TO authenticated;

-- También el nombre de quien dejó hilos huérfanos (`entidad = 'usuarios'`).
CREATE OR REPLACE FUNCTION public.notificaciones_actores()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT u.id, u.nombre
  FROM usuario_notificaciones n
  JOIN usuarios u ON u.id = n.actor_id OR (n.entidad = 'usuarios' AND u.id = n.entidad_id)
  WHERE n.usuario_id = auth.uid() AND n.activo;
$$;

-- Paso e hilo, con la RLS del que lee; las salidas, con título y link solo si
-- todavía lo ve. Hilos huérfanos: mientras le queden abiertos que el lector ve.
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

    UNION ALL

    SELECT n.id,
           coalesce(t.titulo, x.titulo),
           CASE WHEN n.tipo = 'pedido_rechazado' THEN t.motivo_rechazo END,
           CASE WHEN t.id IS NOT NULL THEN 'tarea' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas t                 ON t.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas' AND (t.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id,
           coalesce(h.titulo, x.titulo),
           NULL::text,
           CASE WHEN h.id IS NOT NULL THEN 'hilo' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas_hilos h           ON h.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas_hilos' AND (h.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id,
           a.nombre,
           c.abiertos || CASE WHEN c.abiertos = 1 THEN ' hilo abierto' ELSE ' hilos abiertos' END,
           'tareas_todas',
           n.entidad_id
    FROM mias n
    CROSS JOIN LATERAL (
      SELECT count(*) AS abiertos
      FROM tareas_hilos h
      WHERE h.responsable_id = n.entidad_id AND h.activo AND h.estado = 'abierto'
    ) c
    LEFT JOIN notificaciones_actores() a ON a.id = n.entidad_id
    WHERE n.entidad = 'usuarios' AND c.abiertos > 0
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
