-- Presupuestos, pantallas: Revisión técnica (decisiones/presupuestos.md → Pantallas).
-- Las dos funciones de Técnica devuelven también el número de la versión: con dos variantes del 142 en revisión, la lista
-- mostraba dos "P-0142". La cola, además, el nombre de quien pidió: Técnica no lee `usuarios` de otros ni ve la obra, y
-- su aviso ya lo dice. La versión, si una autorización de Técnica del presupuesto cubre cada ventana (`cubierta`): la V2
-- autorizada en la v1 no tiene pedido en la v2, y se veía con su alerta sin estar resuelta. Lo demás, como en sql/189. Cambia
-- lo que devuelven, así que se borran y se crean de nuevo.
-- Test: sql/tests/presupuestos_autorizaciones.sql (01).

DROP FUNCTION IF EXISTS public.presupuestos_revision_pendientes();
DROP FUNCTION IF EXISTS public.presupuestos_revision_version(uuid);

-- Los pedidos de Técnica pendientes, los más viejos primero.
CREATE FUNCTION public.presupuestos_revision_pendientes()
RETURNS TABLE (pedido_id uuid, version_id uuid, codigo text, version integer, etiqueta text, motivos jsonb, pedido_por uuid,
               pedido_por_nombre text, pedido_en timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (public.usuario_tiene_permiso(auth.uid(), 'presupuestos_revision')
          OR (public.usuario_tiene_permiso(auth.uid(), 'presupuestos_ver')
              AND public.usuario_tiene_permiso(auth.uid(), 'presupuestos_administrar'))) THEN
    RAISE EXCEPTION 'Revisión técnica requiere la vista' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT a.id, a.version_id, p.codigo, v.numero, a.pedido->>'etiqueta', a.pedido->'motivos', a.pedido_por, u.nombre,
           a.created_at
    FROM public.presupuestos_autorizaciones a
    JOIN public.presupuestos_versiones v ON v.id = a.version_id
    JOIN public.presupuestos p ON p.id = v.presupuesto_id
    LEFT JOIN public.usuarios u ON u.id = a.pedido_por
    WHERE a.tipo = 'tecnica' AND a.estado = 'pendiente'
    ORDER BY a.created_at, p.numero;
END;
$$;

-- Una versión completa, de un presupuesto con algún pedido de Técnica. Por renglón de Catálogo o a mano, el último pedido de
-- Técnica de ese renglón en la versión (el pendiente primero) y si lo cubre una autorización de Técnica del presupuesto, como
-- en `presupuestos_version_pedido` pero con las alertas guardadas: sin lo dado de baja de una mantenida, que pide recalcularla.
-- En revisión no cambia nada: lo que eso no cubre ya tiene su pedido pendiente.
CREATE FUNCTION public.presupuestos_revision_version(p_version uuid)
RETURNS TABLE (renglon_id uuid, codigo text, version integer, tipo public.tipo_renglon_presupuesto, designacion text,
               ubicacion text, cantidad numeric, paquete_id uuid, paquete text, catalogo_version_id uuid,
               catalogo_version integer, entrada jsonb, mensajes jsonb, descripcion text, pedido_id uuid,
               pedido_estado public.estado_autorizacion_presupuesto, motivos jsonb, cubierta boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v
    WHERE v.id = p_version
      AND ((public.usuario_tiene_permiso(auth.uid(), 'presupuestos_ver')
            AND public.usuario_tiene_permiso(auth.uid(), 'presupuestos_administrar'))
        OR (public.usuario_tiene_permiso(auth.uid(), 'presupuestos_revision')
            AND EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones a
                        JOIN public.presupuestos_versiones av ON av.id = a.version_id
                        WHERE av.presupuesto_id = v.presupuesto_id AND a.tipo = 'tecnica')))) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT r.id, p.codigo, v.numero, r.tipo, r.designacion, r.ubicacion, r.cantidad, r.paquete_id, cv.nombre,
           r.catalogo_version_id, cv.numero, r.entrada, r.mensajes, r.descripcion, a.id, a.estado, a.pedido->'motivos',
           al.alertas <> '[]' AND EXISTS (
             SELECT 1 FROM public.presupuestos_autorizaciones x
             JOIN public.presupuestos_versiones xv ON xv.id = x.version_id
             WHERE xv.presupuesto_id = v.presupuesto_id AND x.tipo = 'tecnica' AND x.estado = 'autorizada' AND x.activo
               AND public.presupuestos_tecnica_cubre(x.pedido, jsonb_build_object('paquete_id', r.paquete_id,
                     'catalogo_version_id', r.catalogo_version_id, 'entrada', r.entrada, 'motivos', al.alertas)))
    FROM public.presupuestos_renglones r
    JOIN public.presupuestos_versiones v ON v.id = r.version_id
    JOIN public.presupuestos p ON p.id = v.presupuesto_id
    LEFT JOIN public.catalogo_versiones cv ON cv.id = r.catalogo_version_id
    LEFT JOIN LATERAL (
      SELECT x.id, x.estado, x.pedido FROM public.presupuestos_autorizaciones x
      WHERE x.version_id = r.version_id AND x.renglon_id = r.id
      ORDER BY x.estado = 'pendiente' DESC, x.created_at DESC
      LIMIT 1) a ON true
    CROSS JOIN LATERAL (
      SELECT coalesce(jsonb_agg(m->'mensaje'), '[]') AS alertas
      FROM jsonb_array_elements(coalesce(r.mensajes, '[]')) m WHERE NOT (m->>'bloquea')::boolean) al
    WHERE r.version_id = p_version AND r.activo AND r.tipo <> 'minimo'
    ORDER BY r.orden, r.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_revision_pendientes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_revision_pendientes() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.presupuestos_revision_version(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_revision_version(uuid) TO authenticated;
