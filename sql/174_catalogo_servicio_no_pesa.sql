-- Catálogo: el servicio fijo no cuenta para el peso ni el espesor, tenga la marca que tenga (AUDITORIA_CATALOGO.md, hallazgo 7).
-- Decisiones: decisiones/catalogo/paquete.md → El servicio fijo nunca cuenta. Esquema: db_schema/catalogo.md.
-- Tests: sql/tests/catalogo_despiece.sql y catalogo_ciclo.sql. Las funciones son las de sql/161 y sql/167 con este cambio.

-- Se resuelve al leer y no apagando la marca al guardar: el editor no la muestra en un servicio, y un material que pasa de servicio a
-- insumo tiene que volver a contar.
CREATE OR REPLACE FUNCTION public.catalogo_despiece_sumas(p_piezas jsonb, p_materiales jsonb, p_cant jsonb, p_hechos jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  WITH m AS (
    SELECT x->>'pieza_id' AS pieza_id, x->>'nombre' AS nombre, p_hechos->(x->>'id') AS h,
           (x->>'cuenta_peso')::boolean AND x#>>'{insumo,tipo}' IS DISTINCT FROM 'servicio' AS cuenta_peso,
           (x->>'cuenta_espesor')::boolean AND x#>>'{insumo,tipo}' IS DISTINCT FROM 'servicio' AS cuenta_espesor
    FROM jsonb_array_elements(p_materiales) x
  ),
  por_pieza AS (
    SELECT pieza_id, nombre, sum((h->>'valor')::numeric) AS valor, bool_and(h IS NOT NULL) AS listo
    FROM m WHERE nombre IS NOT NULL
    GROUP BY pieza_id, nombre
  ),
  en_total AS (
    SELECT nombre, sum(valor * (p_cant->>pieza_id)::numeric) AS valor, bool_and(listo) AS listo
    FROM por_pieza
    GROUP BY nombre
  ),
  datos AS (
    SELECT 'peso ' || (p.x->>'nombre') AS nombre, sum((m.h->>'peso')::numeric) AS valor,
           bool_and(m.pieza_id IS NULL OR (m.h IS NOT NULL AND NOT m.h ? 'sin_peso')) AS listo,
           min(m.nombre) FILTER (WHERE m.pieza_id IS NOT NULL AND m.h IS NULL) AS espera
    FROM jsonb_array_elements(p_piezas) p(x)
    LEFT JOIN m ON m.pieza_id = p.x->>'id' AND m.cuenta_peso
    GROUP BY p.x->>'nombre'
    UNION ALL
    SELECT 'espesor ' || (p.x->>'nombre'), sum((m.h->>'espesor')::numeric),
           bool_and(m.pieza_id IS NULL OR (m.h IS NOT NULL AND NOT m.h ? 'sin_espesor')),
           min(m.nombre) FILTER (WHERE m.pieza_id IS NOT NULL AND m.h IS NULL)
    FROM jsonb_array_elements(p_piezas) p(x)
    LEFT JOIN m ON m.pieza_id = p.x->>'id' AND m.cuenta_espesor
    WHERE (p.x->>'calcula_espesor')::boolean
    GROUP BY p.x->>'nombre'
  )
  SELECT jsonb_build_object(
    'local', (SELECT coalesce(jsonb_object_agg(t.pieza_id, t.valores), '{}') FROM (
                SELECT pieza_id, jsonb_object_agg(nombre, valor) AS valores
                FROM por_pieza WHERE listo GROUP BY pieza_id) t),
    'global', (SELECT coalesce(jsonb_object_agg(nombre, valor), '{}') FROM en_total WHERE listo),
    'datos', (SELECT coalesce(jsonb_object_agg(nombre, coalesce(valor, 0)), '{}') FROM datos WHERE listo),
    'esperan', (SELECT coalesce(jsonb_object_agg(nombre, espera), '{}') FROM datos WHERE espera IS NOT NULL)
  );
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_circular(p_version uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH RECURSIVE materiales AS (
    SELECT m.id, m.pieza_id, m.eleccion_arbol, m.sigue_material_id, p.nombre AS pieza,
           m.cuenta_peso AND i.tipo IS DISTINCT FROM 'servicio' AS cuenta_peso,
           m.cuenta_espesor AND i.tipo IS DISTINCT FROM 'servicio' AS cuenta_espesor,
           coalesce(m.nombre, i.nombre, 'Un material de ' || p.nombre) AS quien
    FROM public.catalogo_materiales m
    JOIN public.catalogo_piezas p ON p.id = m.pieza_id
    LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
    WHERE m.version_id = p_version AND m.activo
  ),
  aristas AS (
    SELECT r.nodo AS desde, r.quien, h.hasta
    FROM public.catalogo_version_referencias(p_version) r, unnest(r.hacia) AS h (hasta)
    WHERE r.nodo IS NOT NULL
    UNION ALL
    SELECT 'm:' || m.id, m.quien, 'p:' || m.pieza_id FROM materiales m
    UNION ALL
    SELECT 'm:' || m.id, m.quien, 'c:' || m.id FROM materiales m WHERE m.eleccion_arbol IS NOT NULL
    UNION ALL
    SELECT 'c:' || m.id, m.quien, 'p:' || m.pieza_id FROM materiales m WHERE m.eleccion_arbol IS NOT NULL
    UNION ALL
    SELECT 'm:' || m.id, m.quien, 'c:' || m.sigue_material_id FROM materiales m WHERE m.sigue_material_id IS NOT NULL
    UNION ALL
    SELECT 'c:' || m.id, m.quien, 'c:' || m.sigue_material_id FROM materiales m WHERE m.sigue_material_id IS NOT NULL
    UNION ALL
    SELECT 'peso:' || m.pieza_id, 'peso ' || m.pieza, 'm:' || m.id FROM materiales m WHERE m.cuenta_peso
    UNION ALL
    SELECT 'espesor:' || m.pieza_id, 'espesor ' || m.pieza, 'm:' || m.id FROM materiales m WHERE m.cuenta_espesor
  ),
  llega AS (
    SELECT a.desde, a.hasta FROM aristas a
    UNION
    SELECT l.desde, a.hasta FROM llega l JOIN aristas a ON a.desde = l.hasta
  )
  SELECT string_agg(DISTINCT a.quien, ', ' ORDER BY a.quien)
  FROM aristas a
  WHERE EXISTS (SELECT 1 FROM llega l WHERE l.desde = a.desde AND l.hasta = a.desde);
$$;
