-- Presupuestos, pantallas: el formulario de venta trae todas las piezas, no solo las opcionales.
--
-- La entrada nombra la pieza de cada elección (`{"Hoja": {"Vidrio": …}}`) y los materiales que elige el vendedor apuntan a su
-- pieza por id: sin las fijas, el Vidrio de la Hoja no se podía cargar ni leer. Cada pieza trae su `opcional` real; el
-- formulario pregunta solo por las opcionales. Lo demás, como en sql/186.

CREATE OR REPLACE FUNCTION public.catalogo_venta_formulario(p_paquete uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_version uuid;
  v_d jsonb;
BEGIN
  IF NOT public.catalogo_precio_permitido() THEN
    RAISE EXCEPTION 'Ver los paquetes a la venta requiere armar presupuestos' USING ERRCODE = '42501';
  END IF;

  SELECT v.id INTO v_version
  FROM public.catalogo_versiones v
  JOIN public.catalogo_paquetes q ON q.id = v.paquete_id
  WHERE q.id = p_paquete AND q.activo AND v.estado = 'publicado';
  IF v_version IS NULL THEN
    RETURN NULL;
  END IF;

  v_d := public.catalogo_despiece(v_version, '{}');

  RETURN jsonb_build_object(
    'version_id', v_version,
    'piezas', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'nombre', p.nombre, 'opcional', p.opcional, 'incluida', p.incluida,
               'requiere_pieza_id', p.requiere_pieza_id, 'secundario', p.secundario) ORDER BY p.orden, p.nombre), '[]')
      FROM public.catalogo_piezas p
      WHERE p.version_id = v_version AND p.activo),
    'variables', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', x.id, 'nombre', x.nombre, 'pieza_id', x.pieza_id, 'ingresa_vendedor', true, 'es_lista', x.es_lista,
               'valores', x.valores, 'es_cantidad', x.es_cantidad, 'minimo', x.minimo, 'maximo', x.maximo,
               'secundario', x.secundario,
               'predeterminado', (SELECT d->'valor' FROM jsonb_array_elements(v_d->'variables') d WHERE d->>'id' = x.id::text))
             ORDER BY x.orden, x.nombre), '[]')
      FROM public.catalogo_variables x
      WHERE x.version_id = v_version AND x.activo AND x.ingresa_vendedor),
    'materiales', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', m.id, 'pieza_id', m.pieza_id, 'nombre', m.nombre, 'tipo', m.tipo, 'sin_eleccion', m.sin_eleccion,
               'sigue_material_id', m.sigue_material_id, 'secundario', m.secundario) ORDER BY m.orden, m.nombre), '[]')
      FROM public.catalogo_materiales m
      WHERE m.version_id = v_version AND m.activo AND m.tipo IN ('elige_vendedor', 'sigue')),
    'opciones', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', o.id, 'material_id', o.material_id, 'insumo_id', o.insumo_id, 'nombre', i.nombre,
               'predeterminada', o.predeterminada, 'sigue_opcion_id', o.sigue_opcion_id) ORDER BY o.orden), '[]')
      FROM public.catalogo_opciones o
      JOIN public.catalogo_materiales m ON m.id = o.material_id AND m.activo AND m.tipo IN ('elige_vendedor', 'sigue')
      LEFT JOIN public.catalogo_insumos i ON i.id = o.insumo_id
      WHERE o.version_id = v_version AND o.activo),
    'colores', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', o.color_id, 'nombre', o.color, 'base', coalesce(c.base, false),
               'piezas_fuera', to_jsonb(o.piezas_fuera), 'opciones_fuera', to_jsonb(o.opciones_fuera)) ORDER BY o.color), '[]')
      FROM public.catalogo_oferta(v_version, NULL, NULL) o
      LEFT JOIN public.catalogo_versiones_colores c ON c.version_id = v_version AND c.color_id = o.color_id AND c.activo
      WHERE o.armable),
    'servicios', (
      SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.porcentaje_id, 'nombre', s.nombre) ORDER BY s.paso, s.nombre), '[]')
      FROM public.catalogo_porcentajes_vigentes(now()) s
      WHERE s.opcional AND NOT s.de_baja)
  );
END;
$$;
