-- Presupuestos, tramo 5, 2 de 2: los avisos. Decisiones: decisiones/presupuestos.md → Avisos y La base. Test: sql/tests/presupuestos_avisos.sql.
-- Los tipos salen de sql/192.

-- ============================================================
-- 1. Quién puede autorizar: la regla por usuario, y puede_autorizar la envuelve
-- ============================================================
CREATE OR REPLACE FUNCTION public.presupuestos_puede_autorizar_de(
  p_tipo public.tipo_autorizacion_presupuesto, p_obra uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (public.usuario_tiene_permiso(p_usuario, 'presupuestos_ver')
          AND public.usuario_tiene_permiso(p_usuario, 'presupuestos_administrar'))
    OR CASE p_tipo
         WHEN 'comercial' THEN public.usuario_tiene_permiso(p_usuario, 'presupuestos_ver')
           AND public.usuario_tiene_permiso(p_usuario, 'presupuestos_autorizar')
           AND public.obras_a_cargo_de(p_obra, p_usuario)
         ELSE public.usuario_tiene_permiso(p_usuario, 'presupuestos_revision')
           AND public.usuario_tiene_permiso(p_usuario, 'presupuestos_autorizar_tecnica')
       END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_puede_autorizar_de(public.tipo_autorizacion_presupuesto, uuid, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_puede_autorizar(p_tipo public.tipo_autorizacion_presupuesto, p_obra uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.presupuestos_puede_autorizar_de(p_tipo, p_obra, auth.uid());
$$;

-- ============================================================
-- 2. Los renglones a mano que avisan: nuevos, o distintos del renglón del que se copiaron
-- ============================================================
CREATE OR REPLACE FUNCTION public.presupuestos_mano_nuevos(p_version uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT r.id
  FROM public.presupuestos_renglones r
  LEFT JOIN public.presupuestos_renglones o ON o.id = r.origen_id
  WHERE r.version_id = p_version AND r.activo AND r.tipo = 'mano'
    AND (o.id IS NULL
         OR (r.descripcion, r.precio, r.cantidad, r.moneda) IS DISTINCT FROM (o.descripcion, o.precio, o.cantidad, o.moneda));
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_mano_nuevos(uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 3. Triggers
-- ============================================================
-- Un pedido nuevo: a todos los que pueden autorizar algo de lo pendiente, uno por versión y persona. Pedir de nuevo reemplaza
-- los avisos anteriores de la versión (también el "lista para publicar").
CREATE OR REPLACE FUNCTION public.presupuestos_autorizaciones_avisar_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.usuario_notificaciones n
  SET activo = false
  WHERE n.activo AND n.entidad = 'presupuestos_versiones'
    AND n.tipo IN ('presupuesto_pedido', 'presupuesto_autorizado')
    AND n.entidad_id IN (SELECT a.version_id FROM nuevas a);

  PERFORM public.notificar(u.id, 'presupuesto_pedido', 'presupuestos_versiones', x.version_id, x.pedido_por)
  FROM (SELECT DISTINCT a.version_id, a.pedido_por, p.obra_id
        FROM nuevas a
        JOIN public.presupuestos_versiones v ON v.id = a.version_id
        JOIN public.presupuestos p ON p.id = v.presupuesto_id
        WHERE a.estado = 'pendiente') x
  JOIN public.usuarios u ON u.activo
  WHERE EXISTS (SELECT 1 FROM nuevas a
                WHERE a.version_id = x.version_id AND a.estado = 'pendiente'
                  AND public.presupuestos_puede_autorizar_de(a.tipo, x.obra_id, u.id));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS presupuestos_autorizaciones_avisar_pedido ON public.presupuestos_autorizaciones;
CREATE TRIGGER presupuestos_autorizaciones_avisar_pedido AFTER INSERT ON public.presupuestos_autorizaciones
  REFERENCING NEW TABLE AS nuevas
  FOR EACH STATEMENT EXECUTE FUNCTION public.presupuestos_autorizaciones_avisar_pedido();

-- Resolver: la devolución le llega a quien pidió, con su motivo, una por pedido devuelto. La última pendiente autorizada deja la
-- versión lista para publicar: aviso a quien pidió, uno por versión aunque Técnica autorice varias juntas.
CREATE OR REPLACE FUNCTION public.presupuestos_autorizaciones_avisar_resuelta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.notificar(n.pedido_por, 'presupuesto_devuelto', 'presupuestos_autorizaciones', n.id, n.resuelto_por)
  FROM nuevas n JOIN viejas o ON o.id = n.id
  WHERE o.estado = 'pendiente' AND n.estado = 'devuelta';

  PERFORM public.notificar(x.pedido_por, 'presupuesto_autorizado', 'presupuestos_versiones', x.version_id, x.resuelto_por)
  FROM (SELECT DISTINCT ON (n.version_id) n.version_id, n.pedido_por, n.resuelto_por
        FROM nuevas n JOIN viejas o ON o.id = n.id
        WHERE o.estado = 'pendiente' AND n.estado = 'autorizada'
        ORDER BY n.version_id, n.resuelto_en DESC) x
  WHERE NOT EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones a
                    WHERE a.version_id = x.version_id AND a.estado = 'pendiente')
    AND EXISTS (SELECT 1 FROM public.presupuestos_versiones v
                WHERE v.id = x.version_id AND v.estado = 'en_revision');
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS presupuestos_autorizaciones_avisar_resuelta ON public.presupuestos_autorizaciones;
CREATE TRIGGER presupuestos_autorizaciones_avisar_resuelta AFTER UPDATE ON public.presupuestos_autorizaciones
  REFERENCING OLD TABLE AS viejas NEW TABLE AS nuevas
  FOR EACH STATEMENT EXECUTE FUNCTION public.presupuestos_autorizaciones_avisar_resuelta();

-- Al publicar: si hay renglones a mano nuevos o cambiados, a quienes pueden autorizar lo comercial en la obra, menos quien publica.
CREATE OR REPLACE FUNCTION public.presupuestos_versiones_avisar_mano()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_obra uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.presupuestos_mano_nuevos(NEW.id)) THEN
    RETURN NULL;
  END IF;
  SELECT p.obra_id INTO v_obra FROM public.presupuestos p WHERE p.id = NEW.presupuesto_id;

  PERFORM public.notificar(u.id, 'presupuesto_a_mano', 'presupuestos_versiones', NEW.id, auth.uid())
  FROM public.usuarios u
  WHERE u.activo AND public.presupuestos_puede_autorizar_de('comercial', v_obra, u.id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS presupuestos_versiones_avisar_mano ON public.presupuestos_versiones;
CREATE TRIGGER presupuestos_versiones_avisar_mano AFTER UPDATE OF estado ON public.presupuestos_versiones
  FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado AND NEW.estado = 'publicado')
  EXECUTE FUNCTION public.presupuestos_versiones_avisar_mano();

REVOKE EXECUTE ON FUNCTION
  public.presupuestos_autorizaciones_avisar_pedido(),
  public.presupuestos_autorizaciones_avisar_resuelta(),
  public.presupuestos_versiones_avisar_mano()
FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. Leer los avisos
-- ============================================================
-- DEFINER: Técnica no lee versiones por RLS, y a ella le da solo "P-0142 · v2" y el destino Revisión técnica. Sigue filtrando por
-- auth.uid(): un id ajeno no devuelve nada.
CREATE OR REPLACE FUNCTION public.presupuestos_avisos(p_ids uuid[])
RETURNS TABLE (notificacion_id uuid, etiqueta text, motivo text, destino text, destino_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH n AS (
    SELECT n.id, n.tipo, n.entidad, n.entidad_id
    FROM public.usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo AND n.id = ANY (p_ids)
      AND n.entidad IN ('presupuestos_versiones', 'presupuestos_autorizaciones')
  )
  SELECT n.id,
         p.codigo || ' · v' || v.numero,
         CASE WHEN n.tipo = 'presupuesto_a_mano' THEN m.cuantos || CASE WHEN m.cuantos = 1 THEN ' renglón a mano' ELSE ' renglones a mano' END END,
         CASE WHEN n.tipo = 'presupuesto_pedido' AND NOT public.presupuestos_ve_de(p.obra_id, auth.uid())
              THEN 'presupuestos_revision' ELSE 'presupuesto' END,
         CASE WHEN n.tipo = 'presupuesto_pedido' AND NOT public.presupuestos_ve_de(p.obra_id, auth.uid()) THEN NULL ELSE p.id END
  FROM n
  JOIN public.presupuestos_versiones v ON v.id = n.entidad_id
  JOIN public.presupuestos p ON p.id = v.presupuesto_id
  CROSS JOIN LATERAL (SELECT count(*) AS cuantos FROM public.presupuestos_mano_nuevos(v.id)) m
  WHERE n.entidad = 'presupuestos_versiones'
    AND CASE n.tipo
      WHEN 'presupuesto_pedido' THEN EXISTS (
        SELECT 1 FROM public.presupuestos_autorizaciones a
        WHERE a.version_id = v.id AND a.estado = 'pendiente'
          AND public.presupuestos_puede_autorizar_de(a.tipo, p.obra_id, auth.uid()))
      WHEN 'presupuesto_autorizado' THEN v.estado = 'en_revision' AND public.presupuestos_ve_de(p.obra_id, auth.uid())
      WHEN 'presupuesto_a_mano' THEN m.cuantos > 0 AND public.presupuestos_puede_autorizar_de('comercial', p.obra_id, auth.uid())
    END

  UNION ALL

  SELECT n.id, p.codigo || ' · v' || v.numero, a.motivo, 'presupuesto', p.id
  FROM n
  JOIN public.presupuestos_autorizaciones a ON a.id = n.entidad_id
  JOIN public.presupuestos_versiones v ON v.id = a.version_id
  JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE n.tipo = 'presupuesto_devuelto' AND public.presupuestos_ve_de(p.obra_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_avisos(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_avisos(uuid[]) TO authenticated;

-- ============================================================
-- 5. Notificaciones: entidades y rama en notificaciones_listar
-- ============================================================
ALTER TABLE public.usuario_notificaciones DROP CONSTRAINT usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad = ANY (ARRAY['equipos_miembros', 'usuario_submodulos', 'tareas', 'tareas_hilos',
                              'tareas_plantillas', 'usuarios', 'obras', 'obras_participantes',
                              'contactos_personas', 'contactos_empresas', 'monedas_tipos_cambio',
                              'catalogo_insumos', 'catalogo_categorias', 'catalogo_bajas',
                              'catalogo_porcentajes_valores', 'catalogo_versiones_historia',
                              'presupuestos_versiones', 'presupuestos_autorizaciones']));

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
      OFFSET 0
    ) c
    LEFT JOIN notificaciones_actores() a ON a.id = n.entidad_id
    WHERE n.entidad = 'usuarios' AND c.cuantos > 0

    UNION ALL

    SELECT n.id,
           t.moneda::text,
           concat_ws(' → ', monedas_formato(a.valor), monedas_formato(t.valor)),
           'monedas',
           t.id
    FROM mias n
    JOIN monedas_tipos_cambio t ON t.id = n.entidad_id
    LEFT JOIN LATERAL (
      SELECT p.valor FROM monedas_tipos_cambio p
      WHERE p.moneda = t.moneda AND p.activo AND p.vigente_desde < t.vigente_desde
      ORDER BY p.vigente_desde DESC
      LIMIT 1
    ) a ON true
    WHERE n.entidad = 'monedas_tipos_cambio'

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN catalogo_avisos((SELECT array_agg(m.id) FROM mias m)) x ON x.notificacion_id = n.id

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN presupuestos_avisos((SELECT array_agg(m.id) FROM mias m)) x ON x.notificacion_id = n.id
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;
