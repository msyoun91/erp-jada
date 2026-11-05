-- Catálogo: la campanita resuelve solo los avisos que va a mostrar, no todos los activos (AUDITORIA_CATALOGO.md, hallazgo 17).
-- Decisiones: decisiones/catalogo/versiones.md → Los avisos en la base. Test: sql/tests/catalogo_avisos.sql.

DROP FUNCTION public.catalogo_avisos();

-- Sigue filtrando por auth.uid(): es DEFINER, y un id ajeno no devuelve nada.
CREATE FUNCTION public.catalogo_avisos(p_ids uuid[])
RETURNS TABLE (notificacion_id uuid, etiqueta text, motivo text, destino text, destino_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH n AS (
    SELECT n.id, n.tipo, n.entidad_id
    FROM public.usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo AND n.id = ANY (p_ids)
      AND n.entidad IN ('catalogo_insumos', 'catalogo_categorias', 'catalogo_bajas',
                        'catalogo_porcentajes_valores', 'catalogo_versiones_historia')
  )
  -- Desaparece cuando todas sus variantes tienen costo. El motivo son los colores que faltan.
  SELECT n.id, i.nombre, f.colores, 'catalogo_insumos'::text, i.id
  FROM n
  JOIN public.catalogo_insumos i ON i.id = n.entidad_id AND i.activo
  JOIN LATERAL (
    SELECT string_agg(c.nombre, ', ' ORDER BY c.nombre) AS colores, count(*) AS faltan
    FROM public.catalogo_variantes va
    LEFT JOIN public.catalogo_colores c ON c.id = va.color_id
    WHERE va.insumo_id = i.id AND va.activo
      AND NOT EXISTS (SELECT 1 FROM public.catalogo_costos k WHERE k.variante_id = va.id AND k.activo)
  ) f ON f.faltan > 0
  WHERE n.tipo = 'catalogo_insumo_sin_costo' AND public.tiene_permiso('catalogo_costos')

  UNION ALL

  SELECT n.id, c.nombre, NULL::text, 'catalogo_porcentajes', c.id
  FROM n
  JOIN public.catalogo_categorias c ON c.id = n.entidad_id AND c.activo
  WHERE n.tipo = 'catalogo_categoria_nueva' AND public.tiene_permiso('catalogo_porcentajes_editar')

  UNION ALL

  -- Los paquetes que siguen de baja por esta causa. Reactivar el insumo devuelve lo que se dejó de ofrecer: si no queda nada que
  -- decir, el aviso desaparece.
  SELECT n.id,
         i.nombre || coalesce(' · ' || co.nombre, ''),
         concat_ws(' · ', 'Salieron de la venta: ' || s.nombres, 'Dejaron de ofrecer: ' || d.dejan),
         CASE i.tipo WHEN 'servicio' THEN 'catalogo_fijos' ELSE 'catalogo_insumos' END,
         i.id
  FROM n
  JOIN public.catalogo_bajas b ON b.id = n.entidad_id
  JOIN public.catalogo_insumos i ON i.id = b.insumo_id
  LEFT JOIN public.catalogo_variantes va ON va.id = b.variante_id
  LEFT JOIN public.catalogo_colores co ON co.id = va.color_id
  CROSS JOIN LATERAL (
    SELECT string_agg(v.nombre, ', ' ORDER BY v.nombre) AS nombres
    FROM public.catalogo_paquetes q
    JOIN public.catalogo_versiones v ON v.paquete_id = q.id AND v.estado = 'publicado'
    WHERE q.id = ANY (b.salen) AND NOT q.activo
      AND CASE WHEN b.variante_id IS NULL THEN q.baja_insumo_id = b.insumo_id ELSE q.baja_variante_id = b.variante_id END
  ) s
  CROSS JOIN LATERAL (
    SELECT CASE WHEN NOT i.activo OR NOT coalesce(va.activo, true)
                THEN nullif(array_to_string(b.dejan, ', '), '') END AS dejan
  ) d
  WHERE n.tipo = 'catalogo_baja' AND (s.nombres IS NOT NULL OR d.dejan IS NOT NULL)
    AND (public.tiene_permiso('catalogo_aprobar') OR (i.tipo = 'servicio' AND public.tiene_permiso('catalogo_armar')))

  UNION ALL

  SELECT n.id,
         v.nombre,
         concat_ws(' · ', public.catalogo_porcentaje_cambio(v.id),
                   CASE WHEN v.id <> u.id THEN 'Hubo otro cambio después' END),
         'catalogo_porcentaje',
         v.porcentaje_id
  FROM n
  JOIN public.catalogo_porcentajes_valores v ON v.id = n.entidad_id
  JOIN public.catalogo_porcentajes_vigentes() u ON u.porcentaje_id = v.porcentaje_id
  WHERE (n.tipo = 'catalogo_porcentaje_cambiado' AND public.tiene_permiso('catalogo_aprobar'))
     OR (n.tipo = 'catalogo_porcentaje_revertido' AND public.tiene_permiso('catalogo_porcentajes'))

  UNION ALL

  -- "Espera revisión" solo vale para el último envío y mientras siga en revisión.
  SELECT n.id, v.nombre || ' · v' || v.numero, h.motivo, 'catalogo_version', v.id
  FROM n
  JOIN public.catalogo_versiones_historia h ON h.id = n.entidad_id
  JOIN public.catalogo_versiones v ON v.id = h.version_id
  WHERE (n.tipo = 'catalogo_version_enviada' AND v.estado = 'en_revision' AND public.tiene_permiso('catalogo_aprobar')
         AND NOT EXISTS (
           SELECT 1 FROM public.catalogo_versiones_historia x
           WHERE x.version_id = h.version_id AND x.accion = 'enviada' AND x.created_at > h.created_at))
     OR (n.tipo IN ('catalogo_version_aprobada', 'catalogo_version_devuelta') AND public.tiene_permiso('catalogo_paquetes'));
$$;

REVOKE EXECUTE ON FUNCTION public.catalogo_avisos(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogo_avisos(uuid[]) TO authenticated;

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
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;
