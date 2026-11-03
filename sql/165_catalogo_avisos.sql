-- Catálogo, tramo 7, 2 de 2: los avisos de la ficha. Nacen en triggers sobre lo que ya se escribe, y se leen con catalogo_avisos.
-- Decisiones: decisiones/catalogo/versiones.md → Los avisos en la base. Esquema: db_schema/catalogo.md y notificaciones.md.
-- Test: sql/tests/catalogo_avisos.sql.
--
-- catalogo_avisos es DEFINER, como duplicados_avisos: quien carga costos no siempre puede leer lo que resuelve su aviso, y al
-- perder un permiso sus avisos dejan de verse. Solo devuelve los avisos propios.

-- ============================================================
-- 1. Las bajas que sacaron algo de la venta
-- ============================================================
-- Lo que un paquete dejó de ofrecer no se puede recalcular después: con el insumo ya de baja, la oferta de antes y la de
-- después son iguales. Se guarda como texto porque los nombres ya quedaron fijos al enviar la versión.
CREATE TABLE IF NOT EXISTS public.catalogo_bajas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  insumo_id   uuid NOT NULL REFERENCES public.catalogo_insumos(id),
  variante_id uuid REFERENCES public.catalogo_variantes(id),
  salen       uuid[] NOT NULL DEFAULT '{}',
  dejan       text[] NOT NULL DEFAULT '{}',
  creado_por  uuid REFERENCES public.usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS catalogo_bajas_insumo ON public.catalogo_bajas (insumo_id);
CREATE INDEX IF NOT EXISTS catalogo_bajas_variante ON public.catalogo_bajas (variante_id);
CREATE INDEX IF NOT EXISTS catalogo_bajas_creado_por ON public.catalogo_bajas (creado_por);

-- Sin policy ni GRANT: se escribe en la cascada y se lee en catalogo_avisos, las dos DEFINER.
ALTER TABLE public.catalogo_bajas ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_bajas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- BEFORE: todavía se ve la oferta de antes, y la de después sale de la misma función que muestra el aviso previo. Un paquete
-- que ya estaba de baja no cambia de causa: la que queda es la que lo sacó de la venta, la última que cayó.
CREATE OR REPLACE FUNCTION public.catalogo_baja_cascada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_insumo uuid;
  v_variante uuid;
  v_salen uuid[];
  v_dejan text[];
  v_baja uuid;
BEGIN
  IF TG_TABLE_NAME = 'catalogo_variantes' THEN
    v_insumo := NEW.insumo_id;
    v_variante := NEW.id;
  ELSE
    v_insumo := NEW.id;
  END IF;

  SELECT coalesce(array_agg(e.paquete_id) FILTER (WHERE e.sale), '{}'),
         coalesce(array_agg(e.nombre || ' (' || array_to_string(e.colores || e.piezas || e.opciones, ', ') || ')'
                            ORDER BY e.nombre) FILTER (WHERE NOT e.sale), '{}')
  INTO v_salen, v_dejan
  FROM public.catalogo_baja_efecto(v_insumo, v_variante) e;

  IF cardinality(v_salen) + cardinality(v_dejan) = 0 THEN
    RETURN NEW;
  END IF;

  UPDATE public.catalogo_paquetes q
  SET activo = false,
      baja_insumo_id = CASE WHEN v_variante IS NULL THEN v_insumo END,
      baja_variante_id = v_variante
  WHERE q.id = ANY (v_salen);

  INSERT INTO public.catalogo_bajas (insumo_id, variante_id, salen, dejan, creado_por)
  VALUES (v_insumo, v_variante, v_salen, v_dejan, auth.uid())
  RETURNING id INTO v_baja;

  PERFORM public.notificar(u.id, 'catalogo_baja', 'catalogo_bajas', v_baja, auth.uid())
  FROM public.usuarios u
  WHERE u.activo AND (
    public.usuario_tiene_permiso(u.id, 'catalogo_aprobar')
    OR (public.usuario_tiene_permiso(u.id, 'catalogo_armar') AND EXISTS (
      SELECT 1 FROM public.catalogo_insumos i WHERE i.id = v_insumo AND i.tipo = 'servicio')));

  RETURN NEW;
END;
$$;

-- ============================================================
-- 2. Insumo sin costo y categoría de insumo nueva
-- ============================================================
-- Un aviso por insumo, aunque tenga varios colores: una variante nueva reemplaza el anterior, para que vuelva a estar sin leer.
-- El servicio fijo nace con su costo. Volver a sumar un color con costo no avisa.
CREATE OR REPLACE FUNCTION public.catalogo_variantes_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.catalogo_costos k WHERE k.variante_id = NEW.id AND k.activo)
     OR NOT EXISTS (SELECT 1 FROM public.catalogo_insumos i WHERE i.id = NEW.insumo_id AND i.tipo = 'insumo') THEN
    RETURN NULL;
  END IF;

  UPDATE public.usuario_notificaciones SET activo = false
  WHERE tipo = 'catalogo_insumo_sin_costo' AND entidad_id = NEW.insumo_id AND activo;

  PERFORM public.notificar(u.id, 'catalogo_insumo_sin_costo', 'catalogo_insumos', NEW.insumo_id, auth.uid())
  FROM public.usuarios u
  WHERE u.activo AND public.usuario_tiene_permiso(u.id, 'catalogo_costos');
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_variantes_avisar_alta AFTER INSERT ON public.catalogo_variantes
  FOR EACH ROW WHEN (NEW.activo) EXECUTE FUNCTION public.catalogo_variantes_avisar();
CREATE OR REPLACE TRIGGER catalogo_variantes_avisar_vuelve AFTER UPDATE OF activo ON public.catalogo_variantes
  FOR EACH ROW WHEN (NOT OLD.activo AND NEW.activo) EXECUTE FUNCTION public.catalogo_variantes_avisar();

CREATE OR REPLACE FUNCTION public.catalogo_categorias_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.notificar(u.id, 'catalogo_categoria_nueva', 'catalogo_categorias', NEW.id, auth.uid())
  FROM public.usuarios u
  WHERE u.activo AND public.usuario_tiene_permiso(u.id, 'catalogo_porcentajes_editar');
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_categorias_avisar AFTER INSERT ON public.catalogo_categorias
  FOR EACH ROW WHEN (NEW.tipo = 'insumo') EXECUTE FUNCTION public.catalogo_categorias_avisar();

-- ============================================================
-- 3. Cambios en un servicio en %
-- ============================================================
-- Una reversión es un cambio más, para los demás gerentes. A quien hizo el cambio le llega un solo aviso, el de la reversión.
CREATE OR REPLACE FUNCTION public.catalogo_porcentajes_valores_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_autor uuid;
BEGIN
  SELECT r.creado_por INTO v_autor
  FROM public.catalogo_porcentajes_valores r
  JOIN public.usuarios u ON u.id = r.creado_por AND u.activo
  WHERE r.id = NEW.revierte_id;

  PERFORM public.notificar(u.id, 'catalogo_porcentaje_cambiado', 'catalogo_porcentajes_valores', NEW.id, NEW.creado_por)
  FROM public.usuarios u
  WHERE u.activo AND public.usuario_tiene_permiso(u.id, 'catalogo_aprobar') AND u.id IS DISTINCT FROM v_autor;

  PERFORM public.notificar(v_autor, 'catalogo_porcentaje_revertido', 'catalogo_porcentajes_valores', NEW.id, NEW.creado_por);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_porcentajes_valores_avisar AFTER INSERT ON public.catalogo_porcentajes_valores
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_porcentajes_valores_avisar();

-- ============================================================
-- 4. El ciclo de una versión
-- ============================================================
-- Apuntan a la fila de la historia, no a la versión: una versión retirada y reenviada no revive el aviso anterior.
CREATE OR REPLACE FUNCTION public.catalogo_versiones_historia_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_envio uuid;
BEGIN
  IF NEW.accion = 'enviada' THEN
    PERFORM public.notificar(u.id, 'catalogo_version_enviada', 'catalogo_versiones_historia', NEW.id, NEW.creado_por)
    FROM public.usuarios u
    WHERE u.activo AND public.usuario_tiene_permiso(u.id, 'catalogo_aprobar');
    RETURN NULL;
  END IF;

  SELECT h.creado_por INTO v_envio
  FROM public.catalogo_versiones_historia h
  WHERE h.version_id = NEW.version_id AND h.accion = 'enviada'
  ORDER BY h.created_at DESC
  LIMIT 1;

  PERFORM public.notificar(
    v_envio,
    CASE NEW.accion WHEN 'aprobada' THEN 'catalogo_version_aprobada' ELSE 'catalogo_version_devuelta' END::tipo_notificacion,
    'catalogo_versiones_historia', NEW.id, NEW.creado_por);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_versiones_historia_avisar AFTER INSERT ON public.catalogo_versiones_historia
  FOR EACH ROW WHEN (NEW.accion IN ('enviada', 'aprobada', 'devuelta'))
  EXECUTE FUNCTION public.catalogo_versiones_historia_avisar();

-- ============================================================
-- 5. Leer los avisos
-- ============================================================
-- Qué cambió contra el valor anterior. Del mínimo no da números: la moneda sale como un código, y el detalle está en la historia.
CREATE OR REPLACE FUNCTION public.catalogo_porcentaje_cambio(p_valor uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v public.catalogo_porcentajes_valores;
  a public.catalogo_porcentajes_valores;
  v_cambios text[] := '{}';
  v_suma text;
  v_saca text;
BEGIN
  SELECT * INTO v FROM public.catalogo_porcentajes_valores x WHERE x.id = p_valor;
  SELECT * INTO a FROM public.catalogo_porcentajes_valores x
  WHERE x.porcentaje_id = v.porcentaje_id AND x.activo AND x.created_at < v.created_at
  ORDER BY x.created_at DESC
  LIMIT 1;
  IF a.id IS NULL THEN
    RETURN 'Alta: ' || public.catalogo_numero_texto(v.porcentaje) || ' %';
  END IF;

  IF v.de_baja <> a.de_baja THEN
    v_cambios := v_cambios || CASE WHEN v.de_baja THEN 'De baja' ELSE 'Reactivado' END;
  END IF;
  IF v.nombre <> a.nombre THEN
    v_cambios := v_cambios || ('Se llamaba ' || a.nombre);
  END IF;
  IF v.porcentaje <> a.porcentaje THEN
    v_cambios := v_cambios || (public.catalogo_numero_texto(a.porcentaje) || ' % → '
                               || public.catalogo_numero_texto(v.porcentaje) || ' %');
  END IF;
  IF v.paso <> a.paso THEN
    v_cambios := v_cambios || ('Paso ' || a.paso || ' → ' || v.paso);
  END IF;

  SELECT string_agg(c.nombre, ', ' ORDER BY c.nombre) FILTER (WHERE c.id = ANY (v.categorias) AND NOT c.id = ANY (a.categorias)),
         string_agg(c.nombre, ', ' ORDER BY c.nombre) FILTER (WHERE c.id = ANY (a.categorias) AND NOT c.id = ANY (v.categorias))
  INTO v_suma, v_saca
  FROM public.catalogo_categorias c
  WHERE c.id = ANY (v.categorias || a.categorias);
  IF cardinality(v.categorias) = 0 AND cardinality(a.categorias) > 0 THEN
    v_cambios := v_cambios || 'Ahora sobre todo el despiece'::text;
  ELSIF cardinality(a.categorias) = 0 AND cardinality(v.categorias) > 0 THEN
    v_cambios := v_cambios || ('Ahora solo sobre ' || v_suma);
  ELSE
    IF v_suma IS NOT NULL THEN
      v_cambios := v_cambios || ('Suma ' || v_suma);
    END IF;
    IF v_saca IS NOT NULL THEN
      v_cambios := v_cambios || ('Saca ' || v_saca);
    END IF;
  END IF;

  IF (v.minimo, v.minimo_moneda, v.minimo_por) IS DISTINCT FROM (a.minimo, a.minimo_moneda, a.minimo_por) THEN
    v_cambios := v_cambios || 'Cambió el mínimo'::text;
  END IF;
  IF v.opcional <> a.opcional THEN
    v_cambios := v_cambios || CASE WHEN v.opcional THEN 'Ahora es opcional' ELSE 'Ya no es opcional' END;
  END IF;

  RETURN array_to_string(v_cambios, ' · ');
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_avisos()
RETURNS TABLE (notificacion_id uuid, etiqueta text, motivo text, destino text, destino_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH n AS (
    SELECT n.id, n.tipo, n.entidad_id
    FROM public.usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo
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

-- ============================================================
-- 6. Privilegios de las funciones
-- ============================================================
REVOKE EXECUTE ON FUNCTION
  public.catalogo_variantes_avisar(),
  public.catalogo_categorias_avisar(),
  public.catalogo_porcentajes_valores_avisar(),
  public.catalogo_versiones_historia_avisar(),
  public.catalogo_porcentaje_cambio(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.catalogo_avisos() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogo_avisos() TO authenticated;

-- ============================================================
-- 7. Notificaciones: entidades y rama en notificaciones_listar
-- ============================================================
ALTER TABLE public.usuario_notificaciones DROP CONSTRAINT usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad = ANY (ARRAY['equipos_miembros', 'usuario_submodulos', 'tareas', 'tareas_hilos',
                              'tareas_plantillas', 'usuarios', 'obras', 'obras_participantes',
                              'contactos_personas', 'contactos_empresas', 'monedas_tipos_cambio',
                              'catalogo_insumos', 'catalogo_categorias', 'catalogo_bajas',
                              'catalogo_porcentajes_valores', 'catalogo_versiones_historia']));

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
    JOIN catalogo_avisos() x ON x.notificacion_id = n.id
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;
