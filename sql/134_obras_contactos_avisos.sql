-- sql/134 — obras y contactos: campanitas (tramo 2).
--
-- Directas, solo cuando actúa alguien (profundidad 1 y `auth.uid()`): lo que
-- mueven la baja y el cambio de equipo avisa una vez por hecho (`sql/133`).
--   obra_transferida    → el nuevo responsable
--   obra_sumado         → el participante
--   obra_quitado        → el ex participante (salida: el nombre, aunque ya no la vea)
--   persona_transferida → el nuevo dueño
-- `notificaciones_listar` suma sus ramas; las de `usuarios` cuentan al leer y
-- desaparecen en 0. Congelado y "alta resuelta" entran con el tramo 3.
-- Decisiones: `decisiones/obras.md` y `decisiones/contactos.md` → *Eventos
-- que emite*. Test: `sql/tests/obras_contactos_avisos.sql`.

-- ============================================================
-- 1. Vocabulario de `entidad`
-- ============================================================
ALTER TABLE public.usuario_notificaciones
  DROP CONSTRAINT IF EXISTS usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones
  ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad IN ('equipos_miembros', 'usuario_submodulos', 'tareas', 'tareas_hilos', 'usuarios',
                     'obras', 'obras_participantes', 'contactos_personas'));

-- ============================================================
-- 2. Triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL THEN
    PERFORM public.notificar(NEW.responsable_id, 'obra_transferida', 'obras', NEW.id, auth.uid());
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.obras_participantes_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() > 1 OR auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  IF TG_OP = 'INSERT' AND NEW.activo THEN
    PERFORM public.notificar(NEW.usuario_id, 'obra_sumado', 'obras_participantes', NEW.id, auth.uid());
  ELSIF TG_OP = 'UPDATE' AND OLD.activo AND NOT NEW.activo THEN
    PERFORM public.notificar(NEW.usuario_id, 'obra_quitado', 'obras_participantes', NEW.id, auth.uid());
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_personas_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL THEN
    PERFORM public.notificar(NEW.responsable_id, 'persona_transferida', 'contactos_personas', NEW.id, auth.uid());
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_avisar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_participantes_avisar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_personas_avisar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS obras_avisar ON public.obras;
CREATE TRIGGER obras_avisar
  AFTER UPDATE OF responsable_id ON public.obras
  FOR EACH ROW WHEN (OLD.responsable_id IS DISTINCT FROM NEW.responsable_id)
  EXECUTE FUNCTION public.obras_avisar();

DROP TRIGGER IF EXISTS obras_participantes_avisar ON public.obras_participantes;
CREATE TRIGGER obras_participantes_avisar
  AFTER INSERT OR UPDATE OF activo ON public.obras_participantes
  FOR EACH ROW EXECUTE FUNCTION public.obras_participantes_avisar();

DROP TRIGGER IF EXISTS contactos_personas_avisar ON public.contactos_personas;
CREATE TRIGGER contactos_personas_avisar
  AFTER UPDATE OF responsable_id ON public.contactos_personas
  FOR EACH ROW WHEN (OLD.responsable_id IS DISTINCT FROM NEW.responsable_id)
  EXECUTE FUNCTION public.contactos_personas_avisar();

-- ============================================================
-- 3. Lectura
-- ============================================================
-- "Te quitaron de una obra" avisa de algo que el lector ya no ve: el nombre
-- sale de acá, solo de sus propios avisos, como `tareas_avisos_salida`.
CREATE OR REPLACE FUNCTION public.obras_avisos_salida()
RETURNS TABLE (notificacion_id uuid, nombre text, obra_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT n.id, o.nombre, o.id
  FROM usuario_notificaciones n
  JOIN obras_participantes p ON p.id = n.entidad_id
  JOIN obras o               ON o.id = p.obra_id
  WHERE n.usuario_id = auth.uid()
    AND n.activo
    AND n.tipo = 'obra_quitado';
$$;

REVOKE EXECUTE ON FUNCTION public.obras_avisos_salida() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_avisos_salida() TO authenticated;

-- Obra y persona, con la RLS del que lee; la salida, con link solo si todavía
-- la ve. Las de `usuarios` (huérfanos y recibidas) cuentan lo que el lector ve
-- hoy: huérfanas, las que le quedan a quien se fue; recibidas, las que llegaron
-- de él al lector (evento `transferencia` `{de, a}`) y siguen a su nombre.
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

    SELECT n.id, o.nombre, NULL::text, 'obra', o.id
    FROM mias n
    JOIN obras o ON o.id = n.entidad_id
    WHERE n.entidad = 'obras'

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
    WHERE n.entidad = 'obras_participantes' AND (o.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, c.nombre, NULL::text, 'persona', c.id
    FROM mias n
    JOIN contactos_personas c ON c.id = n.entidad_id
    WHERE n.entidad = 'contactos_personas'

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

REVOKE EXECUTE ON FUNCTION public.notificaciones_listar(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notificaciones_listar(int) TO authenticated;
