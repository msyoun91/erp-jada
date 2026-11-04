-- Catálogo: una variable según un material lleva, en `formula`, su valor para cuando ese material queda sin elección.
-- Si el material puede quedar vacío es obligatoria para enviar. Una pieza que puede faltar sigue frenando: es otro caso.
-- Decisiones: decisiones/catalogo/paquete.md. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_sin_eleccion.sql.
-- Las dos funciones son las de sql/167 con estos cambios; el resto sigue igual.

ALTER TABLE public.catalogo_variables DROP CONSTRAINT IF EXISTS catalogo_variables_segun;
ALTER TABLE public.catalogo_variables ADD CONSTRAINT catalogo_variables_segun CHECK (
  segun_material_id IS NULL OR NOT ingresa_vendedor);

CREATE OR REPLACE FUNCTION public.catalogo_despiece_segun(p_x jsonb, p_materiales jsonb, p_elegidas jsonb, p_faltan text[], p_v jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_nombre text := p_x->>'segun_nombre';
  v_m jsonb;
  v_id text := p_x->>'segun_material_id';
  v_opcion text;
BEGIN
  SELECT m INTO v_m FROM jsonb_array_elements(p_materiales) m WHERE m->>'id' = v_id;
  IF v_m IS NULL OR v_id = ANY (p_faltan) THEN
    RAISE EXCEPTION 'Falta el valor de %', v_nombre USING ERRCODE = 'CA002';
  END IF;

  CASE v_m->>'tipo'
    WHEN 'unico' THEN
      RAISE EXCEPTION '% no se elige', v_nombre USING ERRCODE = 'CA018';
    WHEN 'elige_sistema' THEN
      IF NOT p_elegidas ? v_id THEN
        RAISE EXCEPTION 'Falta el valor de %', v_nombre USING ERRCODE = 'CA002';
      END IF;
      v_opcion := p_elegidas->>v_id;
    ELSE
      v_opcion := public.catalogo_despiece_elegir(v_m, p_elegidas, p_faltan, p_v)->>'id';
  END CASE;

  IF v_opcion IS NULL THEN
    IF p_x ? 'formula' THEN
      RETURN p_x->'formula';
    END IF;
    RAISE EXCEPTION '% no tiene una opción elegida', v_nombre USING ERRCODE = 'CA018';
  END IF;
  IF NOT coalesce(p_x->'segun_valores', '{}') ? v_opcion THEN
    RAISE EXCEPTION 'falta el valor de la opción elegida en %', v_nombre USING ERRCODE = 'CA018';
  END IF;
  RETURN p_x->'segun_valores'->v_opcion;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_referencias(p_version uuid)
RETURNS TABLE (nodo text, quien text, problema text, hacia text[])
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH alcance AS (
    SELECT a.desde, a.llega FROM public.catalogo_version_alcance(p_version) a
  ),
  piezas AS (
    SELECT p.id, p.nombre, p.calcula_espesor
    FROM public.catalogo_piezas p
    WHERE p.version_id = p_version AND p.activo
  ),
  materiales AS (
    SELECT m.id, m.pieza_id, m.tipo, coalesce(m.nombre, i.nombre) AS nombre,
           CASE m.tipo
             WHEN 'elige_vendedor' THEN m.sin_eleccion
             WHEN 'elige_sistema' THEN coalesce(jsonb_path_exists(m.eleccion_arbol, '$.** ? (@.op == "ninguno")'), false)
             WHEN 'sigue' THEN coalesce(s.sin_eleccion, false)
               OR coalesce(jsonb_path_exists(s.eleccion_arbol, '$.** ? (@.op == "ninguno")'), false)
               OR EXISTS (
                 SELECT 1 FROM public.catalogo_opciones o
                 WHERE o.material_id = m.id AND o.activo AND o.insumo_id IS NULL)
             ELSE false
           END AS puede_faltar
    FROM public.catalogo_materiales m
    LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
    LEFT JOIN public.catalogo_materiales s ON s.id = m.sigue_material_id
    WHERE m.version_id = p_version AND m.activo
  ),
  usos AS (
    SELECT f.nodo, f.quien, f.pieza_id, u.nombre
    FROM public.catalogo_version_formulas(p_version) f,
         unnest(public.catalogo_formula_usa(f.arbol)) AS u (nombre)
  )
  SELECT u.nodo, u.quien,
    CASE
      WHEN d.hacia IS NULL THEN format('%s: usa %s, que no existe', u.quien, u.nombre)
      WHEN d.lista THEN format('%s: usa %s, que es una lista de valores', u.quien, u.nombre)
      WHEN NOT d.seguro THEN format('%s: usa %s, que puede no estar', u.quien, u.nombre)
    END,
    d.hacia
  FROM usos u
  CROSS JOIN LATERAL (
    SELECT array_agg(t.hacia) AS hacia, bool_or(t.lista) AS lista,
           bool_or(NOT t.puede_faltar AND (t.pieza IS NULL OR EXISTS (
             SELECT 1 FROM alcance a WHERE a.desde IS NOT DISTINCT FROM u.pieza_id AND a.llega = t.pieza))) AS seguro
    FROM (
      SELECT 'v:' || x.id AS hacia, x.es_lista AS lista, x.pieza_id AS pieza, false AS puede_faltar
      FROM public.catalogo_variables x
      WHERE x.version_id = p_version AND x.activo AND x.nombre = u.nombre
      UNION ALL
      SELECT 'peso:' || p.id, false, p.id, false FROM piezas p WHERE u.nombre = 'peso ' || p.nombre
      UNION ALL
      SELECT 'espesor:' || p.id, false, p.id, false
      FROM piezas p WHERE p.calcula_espesor AND u.nombre = 'espesor ' || p.nombre
      UNION ALL
      SELECT 'm:' || m.id, false, m.pieza_id, m.puede_faltar
      FROM materiales m
      WHERE m.nombre = u.nombre AND (m.pieza_id = u.pieza_id OR NOT EXISTS (
        SELECT 1 FROM materiales l WHERE l.nombre = u.nombre AND l.pieza_id = u.pieza_id))
    ) t
  ) d
  UNION ALL
  SELECT 'v:' || x.id, x.nombre,
    CASE
      WHEN m.tipo = 'unico' THEN format('%s: depende de %s, que no se elige', x.nombre, m.nombre)
      WHEN NOT EXISTS (
        SELECT 1 FROM alcance a WHERE a.desde IS NOT DISTINCT FROM x.pieza_id AND a.llega = m.pieza_id)
        THEN format('%s: depende de %s, que puede no estar', x.nombre, m.nombre)
      WHEN m.puede_faltar AND x.formula IS NULL
        THEN format('%s: falta el valor para cuando %s queda sin elección', x.nombre, m.nombre)
    END,
    ARRAY['c:' || m.id]
  FROM public.catalogo_variables x
  JOIN materiales m ON m.id = x.segun_material_id
  WHERE x.version_id = p_version AND x.activo;
$$;
