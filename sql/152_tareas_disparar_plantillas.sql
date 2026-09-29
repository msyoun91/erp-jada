-- sql/152 — tareas, tramo 5, paso 4: `disparar_plantillas` y sus dos avisos.
--
--   1. `tareas_disparar_plantillas` (AFTER INSERT ON eventos; DEFINER): con
--      `alta` o `estado` de un ente que los tiene en `entes.disparos`, corren
--      las plantillas del dueño del registro (`entes.dueno`) con ese disparo
--      prendido, sobre la interna `tareas_usar_plantilla_de(..., dueño)`. Se
--      saltea el dueño que no puede recibir y la plantilla que no ve (perdió
--      `tareas_plantillas` o el submódulo del ente). No se repite: un hilo
--      activo de la plantilla sobre el registro, cerrado incluido, la frena.
--      Cada plantilla corre en su propio bloque: lo inesperado se registra
--      (WARNING) y avisa "plantilla fallida", y la acción del emisor sigue.
--   2. Avisos. Al dueño, "plantilla disparada" → el hilo, con quien actuó de
--      actor (si actuó él, nada). Los pasos avisan sin actor —también a quien
--      disparó— y los del dueño no avisan aparte, ni "paso sumado": lo marca
--      `tareas.disparo` mientras corre la interna. "Paso a reasignar" sigue
--      saliendo de `tareas_al_crear`. "Plantilla fallida" → la plantilla, al
--      dueño siempre (sin actor si actuó él).
--   3. La baja apaga los disparos de quien se va.
--   4. `notificaciones_listar`: "disparada" lleva el registro en `motivo`;
--      "fallida" resuelve la plantilla con la RLS del lector.
--   5. `tareas_estado_al_abrir`: en un disparo, sin actor. Si no, el pedido a
--      quien movió el registro nacía aceptado.
--
-- Decisiones: `decisiones/tareas/catalogo.md` → *El disparo sigue al
-- registro*, *Una plantilla nunca falla*, *Un disparo no se repite*;
-- `decisiones/tareas/avisos.md` → *Un disparo avisa una vez al dueño*.

-- ============================================================
-- 1. El disparo
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_disparar_plantillas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ente public.entes;
  v_dueno uuid;
  v_actor uuid := auth.uid();
  v_pl public.tareas_plantillas;
  v_hilo uuid;
BEGIN
  IF NEW.evento NOT IN ('alta', 'estado') THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_ente FROM public.entes e
  WHERE e.codigo = NEW.ente AND e.activo AND NEW.evento = ANY (e.disparos) AND e.dueno IS NOT NULL;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  EXECUTE format('SELECT %I FROM public.%I WHERE id = $1', v_ente.dueno, v_ente.tabla)
    INTO v_dueno USING NEW.registro_id;
  IF v_dueno IS NULL OR NOT public.tareas_puede_recibir(v_dueno, NULL) THEN
    RETURN NULL;
  END IF;

  FOR v_pl IN
    SELECT * FROM public.tareas_plantillas p
    WHERE p.dueno_id = v_dueno AND p.activo AND p.disparo_activo
      AND p.sobre = NEW.ente AND p.disparo_evento = NEW.evento
      AND (NEW.evento = 'alta' OR p.disparo_estado = NEW.detalle ->> 'estado')
      AND public.tareas_puede_ver_plantilla_de(p.dueno_id, p.publicada, p.activo, p.sobre, v_dueno)
      AND NOT EXISTS (
        SELECT 1 FROM public.tareas_hilos h
        WHERE h.plantilla_id = p.id AND h.registro_ente = NEW.ente AND h.registro_id = NEW.registro_id
          AND h.activo)
    ORDER BY p.created_at, p.id
  LOOP
    BEGIN
      PERFORM set_config('tareas.disparo', 'on', true);
      v_hilo := public.tareas_usar_plantilla_de(v_pl.id, NULL, NULL, '{}', NEW.registro_id, v_dueno);
      PERFORM set_config('tareas.disparo', '', true);
      PERFORM public.notificar(v_dueno, 'plantilla_disparada', 'tareas_hilos', v_hilo, v_actor);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'disparar_plantillas: plantilla % sobre % %: % (%)',
        v_pl.id, NEW.ente, NEW.registro_id, SQLERRM, SQLSTATE;
      PERFORM public.notificar(v_dueno, 'plantilla_fallida', 'tareas_plantillas', v_pl.id,
                               NULLIF(v_actor, v_dueno));
    END;
  END LOOP;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_disparar_plantillas() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS disparar_plantillas ON public.eventos;
CREATE TRIGGER disparar_plantillas
  AFTER INSERT ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.tareas_disparar_plantillas();

-- ============================================================
-- 2. Los pasos de un disparo avisan sin actor, y no al dueño
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_avisar_asignado(p public.tareas)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_disparo boolean := current_setting('tareas.disparo', true) IS NOT DISTINCT FROM 'on';
BEGIN
  PERFORM public.notificar(d.usuario,
    CASE WHEN p.estado = 'solicitada' THEN 'pedido_recibido' ELSE 'tarea_asignada' END::tipo_notificacion,
    'tareas', p.id, CASE WHEN NOT v_disparo THEN auth.uid() END)
  FROM (
    SELECT public.tareas_destinatario(p.asignado_id, p.asignado_equipo_id)
    UNION
    SELECT public.tareas_delegador_de(p.equipo_id) WHERE p.estado = 'solicitada'
  ) AS d (usuario)
  WHERE NOT (v_disparo AND d.usuario IN (SELECT h.responsable_id FROM public.tareas_hilos h WHERE h.id = p.hilo_id));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_avisar_asignado(public.tareas) FROM PUBLIC, anon, authenticated;
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
    IF v_uid IS DISTINCT FROM v_resp AND current_setting('tareas.disparo', true) IS DISTINCT FROM 'on' THEN
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

  IF v_reasigna AND (NOT OLD.activo OR OLD.estado IN ('completada', 'cancelada')) THEN
    PERFORM public.notificar(v_resp, 'paso_a_reasignar', 'tareas', NEW.id, v_uid);
    RETURN NULL;
  END IF;

  IF NOT OLD.activo THEN
    RETURN NULL;
  END IF;

  IF v_reasigna THEN
    PERFORM public.tareas_avisar_asignado(NEW);

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

-- ============================================================
-- 3. La baja apaga sus disparos
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
  UPDATE public.tareas_plantillas SET disparo_activo = false
  WHERE dueno_id = NEW.id AND disparo_activo;
  RETURN NULL;
END;
$$;

-- ============================================================
-- 4. notificaciones_listar
-- ============================================================
CREATE OR REPLACE FUNCTION public.notificaciones_listar(p_limite int DEFAULT 30)
RETURNS TABLE (id uuid, tipo tipo_notificacion, etiqueta text, motivo text, actor text, destino text,
               destino_id uuid, leida boolean, created_at timestamptz)
LANGUAGE sql
STABLE
SET search_path = public
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
           CASE WHEN n.tipo = 'plantilla_disparada' THEN etiqueta_registro(h.registro_ente, h.registro_id) END,
           CASE WHEN h.id IS NOT NULL THEN 'hilo' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas_hilos h           ON h.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas_hilos' AND (h.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, p.nombre, NULL::text, 'plantillas', p.id
    FROM mias n
    JOIN tareas_plantillas p ON p.id = n.entidad_id
    WHERE n.entidad = 'tareas_plantillas'

    UNION ALL

    SELECT n.id, o.nombre, NULL::text, 'obra', o.id
    FROM mias n
    JOIN obras o ON o.id = n.entidad_id
    WHERE n.entidad = 'obras'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma')

    UNION ALL

    SELECT n.id,
           coalesce(o.nombre, x.nombre),
           NULL::text,
           CASE WHEN o.id IS NOT NULL THEN 'obra' END,
           coalesce(o.id, x.obra_id)
    FROM mias n
    LEFT JOIN obras_avisos_salida() x ON x.notificacion_id = n.id
    LEFT JOIN obras_participantes p   ON p.id = n.entidad_id
    LEFT JOIN obras o                 ON o.id = coalesce(p.obra_id, x.obra_id)
    WHERE n.entidad = 'obras_participantes' AND n.tipo <> 'obra_misma_sumado'
      AND (o.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, c.nombre, NULL::text, 'persona', c.id
    FROM mias n
    JOIN contactos_personas c ON c.id = n.entidad_id
    WHERE n.entidad = 'contactos_personas'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma',
                         'persona_fusionada')

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN duplicados_avisos() x ON x.notificacion_id = n.id

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN contactos_fusion_avisos() x ON x.notificacion_id = n.id

    UNION ALL

    SELECT n.id,
           a.nombre,
           c.cuantos || ' ' || CASE
             WHEN n.tipo = 'hilos_huerfanos' THEN
               CASE WHEN c.cuantos = 1 THEN 'hilo abierto' ELSE 'hilos abiertos' END
             WHEN n.tipo IN ('obras_huerfanas', 'obras_recibidas') THEN
               CASE WHEN c.cuantos = 1 THEN 'obra' ELSE 'obras' END
             ELSE
               CASE WHEN c.cuantos = 1 THEN 'persona' ELSE 'personas' END
           END,
           CASE n.tipo
             WHEN 'hilos_huerfanos' THEN 'tareas_todas'
             WHEN 'obras_huerfanas' THEN 'obras_todas'
             WHEN 'obras_recibidas' THEN 'obras'
             ELSE 'contactos'
           END,
           n.entidad_id
    FROM mias n
    CROSS JOIN LATERAL (
      SELECT CASE n.tipo
        WHEN 'hilos_huerfanos' THEN (
          SELECT count(*) FROM tareas_hilos h
          WHERE h.responsable_id = n.entidad_id AND h.activo AND h.estado = 'abierto')
        WHEN 'obras_huerfanas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.entidad_id AND o.activo)
        WHEN 'personas_huerfanas' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.entidad_id AND p.activo)
        WHEN 'obras_recibidas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.usuario_id AND o.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'obra' AND e.registro_id = o.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
        WHEN 'agenda_recibida' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.usuario_id AND p.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'persona' AND e.registro_id = p.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
      END AS cuantos
    ) c
    LEFT JOIN notificaciones_actores() a ON a.id = n.entidad_id
    WHERE n.entidad = 'usuarios' AND c.cuantos > 0
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;

-- ============================================================
-- 5. En un disparo no actúa nadie
--
-- Quien movió el registro no abre los pasos: si es el asignado, el pedido del
-- dueño nacía aceptado, y si es admin, nunca pedido.
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_estado_al_abrir(
  p_responsable uuid, p_usuario uuid, p_equipo uuid, p_directo boolean
)
RETURNS estado_tarea
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_actor uuid := CASE WHEN current_setting('tareas.disparo', true) IS DISTINCT FROM 'on' THEN auth.uid() END;
BEGIN
  IF NOT public.tareas_es_pedido(p_responsable, p_usuario, p_equipo)
     OR public.tareas_actua_como_asignado(v_actor, p_usuario, p_equipo)
     OR public.usuario_tiene_permiso(v_actor, 'tareas_administrar') THEN
    RETURN 'pendiente';
  END IF;

  IF p_directo AND NOT public.usuario_tiene_permiso(v_actor, 'tareas_pedir') THEN
    RAISE EXCEPTION 'Pedir a otro equipo requiere el permiso Pedir a otros equipos' USING ERRCODE = 'TA010';
  END IF;

  RETURN 'solicitada';
END;
$$;
