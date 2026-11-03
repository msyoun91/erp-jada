-- Catálogo, tramo 5: el ciclo de una versión (qué frena el envío, enviar, retirar, devolver, aprobar y descartar), lo que se
-- ofrece en cada color, las bajas en cascada, el aviso previo y la reactivación.
-- Decisiones: decisiones/catalogo/versiones.md e insumos.md. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_ciclo.sql.
--
-- Casi todo es DEFINER o se llama desde una DEFINER: Técnica no ve los costos que frenan el envío, y Administración da de
-- baja servicios sin ver los paquetes que usan. Las funciones internas no tienen EXECUTE: solo se llega por las públicas.

-- ============================================================
-- 1. Por qué está de baja y la historia de una versión
-- ============================================================
ALTER TABLE public.catalogo_paquetes
  ADD COLUMN IF NOT EXISTS baja_insumo_id uuid REFERENCES public.catalogo_insumos(id),
  ADD COLUMN IF NOT EXISTS baja_variante_id uuid REFERENCES public.catalogo_variantes(id);

-- Los dos vacíos y de baja: a mano. El insumo y el servicio fijo van en baja_insumo_id.
ALTER TABLE public.catalogo_paquetes DROP CONSTRAINT IF EXISTS catalogo_paquetes_baja;
ALTER TABLE public.catalogo_paquetes ADD CONSTRAINT catalogo_paquetes_baja CHECK (
  num_nonnulls(baja_insumo_id, baja_variante_id) <= CASE WHEN activo THEN 0 ELSE 1 END);

CREATE INDEX IF NOT EXISTS catalogo_paquetes_baja_insumo ON public.catalogo_paquetes (baja_insumo_id);
CREATE INDEX IF NOT EXISTS catalogo_paquetes_baja_variante ON public.catalogo_paquetes (baja_variante_id);

DROP POLICY IF EXISTS catalogo_paquetes_update ON public.catalogo_paquetes;
CREATE POLICY catalogo_paquetes_update ON public.catalogo_paquetes
  FOR UPDATE TO authenticated
  USING ((SELECT public.tiene_permiso('catalogo_armar')))
  WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')));

GRANT UPDATE (activo) ON public.catalogo_paquetes TO authenticated;

DO $$
BEGIN
  CREATE TYPE accion_version_catalogo AS ENUM ('enviada', 'retirada', 'devuelta', 'aprobada', 'obsoleta', 'descartada');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Quién la envió es la última fila 'enviada': no hay otra columna que pueda decir distinto.
CREATE TABLE IF NOT EXISTS public.catalogo_versiones_historia (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  accion     accion_version_catalogo NOT NULL,
  motivo     text CHECK (motivo <> '' AND motivo = btrim(motivo)),
  creado_por uuid NOT NULL REFERENCES public.usuarios(id),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT catalogo_versiones_historia_motivo CHECK ((accion = 'devuelta') = (motivo IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS catalogo_versiones_historia_version ON public.catalogo_versiones_historia (version_id);

ALTER TABLE public.catalogo_versiones_historia ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalogo_versiones_historia_select ON public.catalogo_versiones_historia;
CREATE POLICY catalogo_versiones_historia_select ON public.catalogo_versiones_historia
  FOR SELECT TO authenticated USING ((SELECT public.tiene_permiso('catalogo_paquetes')));

GRANT SELECT ON public.catalogo_versiones_historia TO authenticated;

CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_versiones_historia
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- 2. Lo que se ofrece en cada color
-- ============================================================
-- Se calcula sin guardar nada: reactivar el DVH lo devuelve sin versión nueva. p_sin_insumo y p_sin_variante responden "¿y
-- si esto se diera de baja?", para que el aviso previo y la baja usen las mismas reglas. Una versión sin colores da una
-- fila con color NULL. Lo que no tiene costo cuenta como que no está. Un color de baja no se mira: ya no tiene variantes.
CREATE OR REPLACE FUNCTION public.catalogo_oferta(p_version uuid, p_sin_insumo uuid DEFAULT NULL, p_sin_variante uuid DEFAULT NULL)
RETURNS TABLE (color_id uuid, color text, armable boolean, piezas_fuera uuid[], opciones_fuera uuid[], faltan text[])
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_color record;
  v_hay uuid[];
  v_opciones uuid[];
  v_materiales uuid[];
BEGIN
  FOR v_color IN
    SELECT c.id, c.nombre
    FROM public.catalogo_versiones_colores vc
    JOIN public.catalogo_colores c ON c.id = vc.color_id
    WHERE vc.version_id = p_version AND vc.activo
    UNION ALL
    SELECT NULL, NULL
    WHERE NOT EXISTS (
      SELECT 1 FROM public.catalogo_versiones_colores vc WHERE vc.version_id = p_version AND vc.activo)
    ORDER BY 2
  LOOP
    SELECT coalesce(array_agg(i.id), '{}') INTO v_hay
    FROM public.catalogo_insumos i
    WHERE i.activo AND i.id IS DISTINCT FROM p_sin_insumo
      AND i.id IN (
        SELECT m.insumo_id FROM public.catalogo_materiales m WHERE m.version_id = p_version AND m.activo
        UNION
        SELECT o.insumo_id FROM public.catalogo_opciones o WHERE o.version_id = p_version AND o.activo)
      AND EXISTS (
        SELECT 1 FROM public.catalogo_variantes va
        WHERE va.insumo_id = i.id AND va.activo AND va.id IS DISTINCT FROM p_sin_variante
          AND CASE WHEN i.con_color THEN va.color_id = v_color.id ELSE va.color_id IS NULL END
          AND EXISTS (SELECT 1 FROM public.catalogo_costos k WHERE k.variante_id = va.id AND k.activo));

    -- Una opción sale si no está su insumo o la pareja de alguno de los que la siguen. "ninguna" siempre está.
    SELECT coalesce(array_agg(o.id), '{}') INTO v_opciones
    FROM public.catalogo_opciones o
    JOIN public.catalogo_materiales m ON m.id = o.material_id
    WHERE o.version_id = p_version AND o.activo AND o.insumo_id IS NOT NULL
      AND m.activo AND m.tipo IN ('elige_vendedor', 'elige_sistema')
      AND (NOT o.insumo_id = ANY (v_hay) OR EXISTS (
        SELECT 1 FROM public.catalogo_materiales s
        WHERE s.sigue_material_id = m.id AND s.activo AND NOT EXISTS (
          SELECT 1 FROM public.catalogo_opciones r
          WHERE r.material_id = s.id AND r.activo AND r.sigue_opcion_id = o.id
            AND (r.insumo_id IS NULL OR r.insumo_id = ANY (v_hay)))));

    -- Un material sin el que su pieza no se arma. Lo que sigue a otro no se mira: si le falta la pareja, sale la opción
    -- de aquel. El sistema no puede elegir otra, así que necesita todas las suyas.
    SELECT coalesce(array_agg(m.id), '{}') INTO v_materiales
    FROM public.catalogo_materiales m
    WHERE m.version_id = p_version AND m.activo AND CASE m.tipo
      WHEN 'unico' THEN m.insumo_id IS NULL OR NOT m.insumo_id = ANY (v_hay)
      WHEN 'elige_vendedor' THEN NOT m.sin_eleccion AND NOT EXISTS (
        SELECT 1 FROM public.catalogo_opciones o
        WHERE o.material_id = m.id AND o.activo AND o.insumo_id IS NOT NULL AND NOT o.id = ANY (v_opciones))
      WHEN 'elige_sistema' THEN NOT EXISTS (
          SELECT 1 FROM public.catalogo_opciones o
          WHERE o.material_id = m.id AND o.activo AND o.insumo_id IS NOT NULL)
        OR EXISTS (
          SELECT 1 FROM public.catalogo_opciones o WHERE o.material_id = m.id AND o.id = ANY (v_opciones))
      ELSE false
    END;

    -- Si el Cajón no se ofrece, tampoco la Cortina que lo requiere.
    WITH RECURSIVE fuera AS (
      SELECT m.pieza_id AS id FROM public.catalogo_materiales m WHERE m.id = ANY (v_materiales)
      UNION
      SELECT p.id FROM public.catalogo_piezas p JOIN fuera f ON p.requiere_pieza_id = f.id WHERE p.activo
    )
    SELECT coalesce(array_agg(f.id), '{}') INTO piezas_fuera FROM fuera f;

    color_id := v_color.id;
    color := v_color.nombre;
    armable := NOT EXISTS (SELECT 1 FROM public.catalogo_piezas p WHERE p.id = ANY (piezas_fuera) AND NOT p.opcional);
    opciones_fuera := ARRAY(
      SELECT o.id FROM public.catalogo_opciones o
      JOIN public.catalogo_materiales m ON m.id = o.material_id
      WHERE o.id = ANY (v_opciones) AND NOT m.pieza_id = ANY (piezas_fuera));
    faltan := ARRAY(
      SELECT DISTINCT i.nombre || CASE WHEN i.con_color AND v_color.nombre IS NOT NULL THEN ' · ' || v_color.nombre ELSE '' END
      FROM public.catalogo_materiales m
      JOIN public.catalogo_piezas p ON p.id = m.pieza_id AND NOT p.opcional
      LEFT JOIN public.catalogo_opciones o ON o.material_id = m.id AND o.activo
      LEFT JOIN public.catalogo_materiales s ON s.sigue_material_id = m.id AND s.activo
      LEFT JOIN public.catalogo_opciones r ON r.material_id = s.id AND r.activo AND r.sigue_opcion_id = o.id
      JOIN public.catalogo_insumos i ON i.id IN (m.insumo_id, o.insumo_id, r.insumo_id)
      WHERE m.id = ANY (v_materiales) AND NOT i.id = ANY (v_hay)
      ORDER BY 1);
    RETURN NEXT;
  END LOOP;
END;
$$;

-- ============================================================
-- 3. Qué frena el envío
-- ============================================================
-- Cada fórmula de la versión mirada entera: el cálculo solo ve la rama que toma. nodo es de qué paso del cálculo es: v:
-- variable, p: cantidad de una pieza, m: un material, c: lo que elige la regla de un material. Una condición no tiene nodo:
-- corre al final y nadie espera su resultado.
CREATE OR REPLACE FUNCTION public.catalogo_version_formulas(p_version uuid)
RETURNS TABLE (nodo text, quien text, pieza_id uuid, arbol jsonb)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH materiales AS (
    SELECT m.id, m.pieza_id, m.medida_arbol, m.ancho_arbol, m.alto_arbol, m.area_arbol, m.cantidad_arbol, m.eleccion_arbol,
           coalesce(m.nombre, i.nombre, 'Un material de ' || p.nombre) AS quien
    FROM public.catalogo_materiales m
    JOIN public.catalogo_piezas p ON p.id = m.pieza_id
    LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
    WHERE m.version_id = p_version AND m.activo
  )
  SELECT 'v:' || x.id, x.nombre, x.pieza_id, x.formula_arbol
  FROM public.catalogo_variables x
  WHERE x.version_id = p_version AND x.activo AND x.formula_arbol IS NOT NULL
  UNION ALL
  SELECT 'p:' || p.id, 'cantidad de ' || p.nombre, p.id, p.cantidad_arbol
  FROM public.catalogo_piezas p
  WHERE p.version_id = p_version AND p.activo
  UNION ALL
  SELECT 'm:' || m.id, m.quien, m.pieza_id, f.arbol
  FROM materiales m,
       LATERAL (VALUES (m.medida_arbol), (m.ancho_arbol), (m.alto_arbol), (m.area_arbol), (m.cantidad_arbol)) AS f (arbol)
  WHERE f.arbol IS NOT NULL
  UNION ALL
  SELECT 'c:' || m.id, m.quien, m.pieza_id, m.eleccion_arbol
  FROM materiales m
  WHERE m.eleccion_arbol IS NOT NULL
  UNION ALL
  SELECT 'm:' || m.id, m.quien, m.pieza_id, f.arbol
  FROM materiales m
  JOIN public.catalogo_opciones o ON o.material_id = m.id AND o.activo,
       LATERAL (VALUES (o.medida_arbol), (o.ancho_arbol), (o.alto_arbol), (o.area_arbol), (o.cantidad_arbol)) AS f (arbol)
  WHERE f.arbol IS NOT NULL
  UNION ALL
  SELECT NULL, coalesce(x.nombre, m.quien), coalesce(x.pieza_id, m.pieza_id), c.condicion_arbol
  FROM public.catalogo_condiciones c
  LEFT JOIN public.catalogo_variables x ON x.id = c.variable_id
  LEFT JOIN public.catalogo_opciones o ON o.id = c.opcion_id
  LEFT JOIN materiales m ON m.id = coalesce(c.material_id, o.material_id)
  WHERE c.version_id = p_version AND c.activo;
$$;

-- Qué seguro está cuando se calcula lo de cada pieza: lo fijo, lo suyo y la cadena de lo que requiere. desde NULL es una
-- variable suelta.
CREATE OR REPLACE FUNCTION public.catalogo_version_alcance(p_version uuid)
RETURNS TABLE (desde uuid, llega uuid)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH RECURSIVE piezas AS (
    SELECT p.id, p.opcional, p.requiere_pieza_id
    FROM public.catalogo_piezas p
    WHERE p.version_id = p_version AND p.activo
  ),
  cadena AS (
    SELECT p.id AS desde, p.id AS llega FROM piezas p
    UNION
    SELECT c.desde, p.requiere_pieza_id
    FROM cadena c JOIN piezas p ON p.id = c.llega
    WHERE p.requiere_pieza_id IS NOT NULL
  )
  SELECT c.desde, c.llega FROM cadena c
  UNION
  SELECT d.id, f.id
  FROM (SELECT p.id FROM piezas p UNION ALL SELECT NULL) d
  CROSS JOIN piezas f
  WHERE NOT f.opcional;
$$;

-- Cada nombre que usa cada fórmula: a qué apunta y qué tiene de malo. Un nombre con alguna aparición segura vale: el Tornillo
-- de Marco y de un Mosquitero opcional tiene total siempre, y como se llama como su insumo no se le podría cambiar el nombre.
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
    SELECT m.id, m.pieza_id, coalesce(m.nombre, i.nombre) AS nombre,
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
  ) d;
$$;

-- Quiénes están en un círculo. Un material espera la cantidad de su pieza y lo que elige su regla; quien lo sigue, solo lo
-- que elige aquel; el peso de una pieza, cada material que cuenta.
CREATE OR REPLACE FUNCTION public.catalogo_version_circular(p_version uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH RECURSIVE materiales AS (
    SELECT m.id, m.pieza_id, m.eleccion_arbol, m.sigue_material_id, m.cuenta_peso, m.cuenta_espesor, p.nombre AS pieza,
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

-- Cada insumo que usa la versión, con las fórmulas que le tocan: lo que la opción no trae, lo hereda del material.
CREATE OR REPLACE FUNCTION public.catalogo_version_insumos(p_version uuid)
RETURNS TABLE (
  material text, pieza text, insumo_id uuid, insumo text, tipo tipo_catalogo, unidad unidad_insumo, con_color boolean,
  activo boolean, peso numeric, espesor numeric, con_medida boolean, con_ancho boolean, con_alto boolean, con_area boolean,
  cuenta_peso boolean, cuenta_espesor boolean
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT coalesce(m.nombre, i.nombre), p.nombre, i.id, i.nombre, i.tipo, i.unidad, i.con_color, i.activo, i.peso, i.espesor,
         coalesce(o.medida, m.medida) IS NOT NULL, coalesce(o.ancho, m.ancho) IS NOT NULL,
         coalesce(o.alto, m.alto) IS NOT NULL, coalesce(o.area, m.area) IS NOT NULL,
         m.cuenta_peso, m.cuenta_espesor AND p.calcula_espesor
  FROM public.catalogo_materiales m
  JOIN public.catalogo_piezas p ON p.id = m.pieza_id
  LEFT JOIN public.catalogo_opciones o ON o.material_id = m.id AND o.activo AND m.tipo <> 'unico'
  JOIN public.catalogo_insumos i ON i.id = coalesce(o.insumo_id, m.insumo_id)
  WHERE m.version_id = p_version AND m.activo;
$$;

-- La única lista de lo que frena (decisiones/catalogo/versiones.md → Qué frena el envío), en ese orden. El "si" sin "si no"
-- no está: el parser no lo guarda. Devuelve todo lo que encuentra, para que Lucía lo corrija de una vez.
CREATE OR REPLACE FUNCTION public.catalogo_version_frena(p_version uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_v public.catalogo_versiones;
  v_out text[] := '{}';
  v_txt text;
BEGIN
  SELECT v.* INTO v_v FROM public.catalogo_versiones v WHERE v.id = p_version;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = 'CA016';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.catalogo_piezas p WHERE p.version_id = p_version AND p.activo) THEN
    v_out := v_out || 'El paquete está vacío'::text;
  END IF;
  v_out := v_out || ARRAY(
    SELECT format('%s: la pieza no tiene materiales', p.nombre)
    FROM public.catalogo_piezas p
    WHERE p.version_id = p_version AND p.activo
      AND NOT EXISTS (SELECT 1 FROM public.catalogo_materiales m WHERE m.pieza_id = p.id AND m.activo)
    ORDER BY p.orden, p.nombre);

  v_out := v_out || ARRAY(
    SELECT DISTINCT format('%s está de baja', u.insumo)
    FROM public.catalogo_version_insumos(p_version) u
    WHERE NOT u.activo
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT DISTINCT format('%s no tiene costo', u.insumo || coalesce(' · ' || c.nombre, ''))
    FROM public.catalogo_version_insumos(p_version) u
    JOIN public.catalogo_variantes va ON va.insumo_id = u.insumo_id AND va.activo
    LEFT JOIN public.catalogo_colores c ON c.id = va.color_id
    WHERE (va.color_id IS NULL OR va.color_id IN (
        SELECT vc.color_id FROM public.catalogo_versiones_colores vc WHERE vc.version_id = p_version AND vc.activo))
      AND NOT EXISTS (SELECT 1 FROM public.catalogo_costos k WHERE k.variante_id = va.id AND k.activo)
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT DISTINCT format('%s: falta %s',
      CASE WHEN u.material = u.insumo THEN u.material ELSE format('%s (%s)', u.material, u.insumo) END,
      CASE
        WHEN u.unidad = 'mm' THEN 'la medida'
        WHEN u.tipo = 'servicio' THEN 'el área'
        ELSE 'el ancho o el alto'
      END)
    FROM public.catalogo_version_insumos(p_version) u
    WHERE CASE
      WHEN u.unidad = 'mm' THEN NOT u.con_medida
      WHEN u.unidad = 'm2' AND u.tipo = 'servicio' THEN NOT (u.con_area OR (u.con_ancho AND u.con_alto))
      WHEN u.unidad = 'm2' THEN NOT (u.con_ancho AND u.con_alto)
      ELSE false
    END
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT format('%s: falta la pareja de %s', s.nombre, i.nombre)
    FROM public.catalogo_materiales s
    JOIN public.catalogo_opciones o ON o.material_id = s.sigue_material_id AND o.activo
    JOIN public.catalogo_insumos i ON i.id = o.insumo_id
    WHERE s.version_id = p_version AND s.activo
      AND NOT EXISTS (
        SELECT 1 FROM public.catalogo_opciones r
        WHERE r.material_id = s.id AND r.activo AND r.sigue_opcion_id = o.id)
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT DISTINCT r.problema
    FROM public.catalogo_version_referencias(p_version) r
    WHERE r.problema IS NOT NULL
    ORDER BY 1);

  -- Seguir a otro también es usarlo: si su pieza no está, el que sigue no sabe qué eligió.
  v_out := v_out || ARRAY(
    SELECT format('%s: sigue a %s, que puede no estar', s.nombre, l.nombre)
    FROM public.catalogo_materiales s
    JOIN public.catalogo_materiales l ON l.id = s.sigue_material_id
    WHERE s.version_id = p_version AND s.activo AND NOT EXISTS (
      SELECT 1 FROM public.catalogo_version_alcance(p_version) a WHERE a.desde = s.pieza_id AND a.llega = l.pieza_id)
    ORDER BY 1);

  v_txt := public.catalogo_version_circular(p_version);
  IF v_txt IS NOT NULL THEN
    v_out := v_out || format('Referencia circular entre %s', v_txt);
  END IF;

  SELECT string_agg(DISTINCT p.nombre, ', ' ORDER BY p.nombre) INTO v_txt
  FROM public.catalogo_piezas p
  WHERE p.version_id = p_version AND p.activo AND p.id IN (
    WITH RECURSIVE cadena AS (
      SELECT q.id AS desde, q.requiere_pieza_id AS hasta
      FROM public.catalogo_piezas q
      WHERE q.version_id = p_version AND q.activo AND q.requiere_pieza_id IS NOT NULL
      UNION
      SELECT c.desde, q.requiere_pieza_id
      FROM cadena c JOIN public.catalogo_piezas q ON q.id = c.hasta
      WHERE q.activo AND q.requiere_pieza_id IS NOT NULL
    )
    SELECT c.desde FROM cadena c WHERE c.desde = c.hasta);
  IF v_txt IS NOT NULL THEN
    v_out := v_out || format('Requisito circular entre %s', v_txt);
  END IF;

  v_out := v_out || ARRAY(
    SELECT DISTINCT format('%s: falta el %s, y la pieza %s lo cuenta', u.insumo, d.dato, u.pieza)
    FROM public.catalogo_version_insumos(p_version) u,
         LATERAL (VALUES ('peso', u.cuenta_peso AND u.peso IS NULL), ('espesor', u.cuenta_espesor AND u.espesor IS NULL)) AS d (dato, falta)
    WHERE u.tipo = 'insumo' AND d.falta
    ORDER BY 1);

  -- Sin predeterminado no se puede plegar lo que hay que cargar. Un material con "sin elección" se resuelve sin pedir nada.
  v_out := v_out || ARRAY(
    SELECT format('%s: es secundaria y no tiene predeterminado', x.nombre)
    FROM public.catalogo_variables x
    WHERE x.version_id = p_version AND x.activo AND x.secundario
      AND CASE WHEN x.es_lista THEN x.valor_predeterminado IS NULL ELSE x.formula IS NULL END
    ORDER BY 1);
  v_out := v_out || ARRAY(
    SELECT format('%s: es secundario y no tiene predeterminado', m.nombre)
    FROM public.catalogo_materiales m
    WHERE m.version_id = p_version AND m.activo AND m.secundario AND NOT m.sin_eleccion
      AND NOT EXISTS (
        SELECT 1 FROM public.catalogo_opciones o WHERE o.material_id = m.id AND o.activo AND o.predeterminada)
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT format('%s: %s', x.nombre,
      CASE WHEN x.minimo > x.maximo THEN 'el mínimo es mayor que el máximo' ELSE 'falta el mínimo o el máximo' END)
    FROM public.catalogo_variables x
    WHERE x.version_id = p_version AND x.activo AND x.ingresa_vendedor AND NOT x.es_lista
      AND (x.minimo IS NULL OR x.maximo IS NULL OR x.minimo > x.maximo)
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT format('%s: una variable no se llama como un material', x.nombre)
    FROM public.catalogo_variables x
    WHERE x.version_id = p_version AND x.activo AND EXISTS (
      SELECT 1 FROM public.catalogo_materiales m
      LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
      WHERE m.version_id = p_version AND m.activo AND lower(coalesce(m.nombre, i.nombre)) = lower(x.nombre))
    ORDER BY 1);
  v_out := v_out || ARRAY(
    SELECT format('%s: una variable no se llama como el peso o el espesor de una pieza', x.nombre)
    FROM public.catalogo_variables x
    WHERE x.version_id = p_version AND x.activo AND EXISTS (
      SELECT 1 FROM public.catalogo_piezas p
      WHERE p.version_id = p_version AND p.activo
        AND lower(x.nombre) IN (lower('peso ' || p.nombre), lower('espesor ' || p.nombre)))
    ORDER BY 1);
  IF EXISTS (
    SELECT 1 FROM public.catalogo_versiones o
    WHERE o.paquete_id <> v_v.paquete_id AND o.estado IN ('publicado', 'en_revision')
      AND lower(o.nombre) = lower(v_v.nombre)
  ) THEN
    v_out := v_out || format('El nombre %s ya lo tiene otro paquete', v_v.nombre);
  END IF;

  v_out := v_out || ARRAY(
    SELECT format('Un material de %s no tiene insumo', p.nombre)
    FROM public.catalogo_materiales m
    JOIN public.catalogo_piezas p ON p.id = m.pieza_id
    WHERE m.version_id = p_version AND m.activo AND m.tipo = 'unico' AND m.insumo_id IS NULL
    ORDER BY 1);
  v_out := v_out || ARRAY(
    SELECT format('%s: no tiene opciones', m.nombre)
    FROM public.catalogo_materiales m
    WHERE m.version_id = p_version AND m.activo AND m.tipo IN ('elige_vendedor', 'elige_sistema')
      AND NOT EXISTS (
        SELECT 1 FROM public.catalogo_opciones o
        WHERE o.material_id = m.id AND o.activo AND o.insumo_id IS NOT NULL)
    ORDER BY 1);
  v_out := v_out || ARRAY(
    SELECT format('%s: %s', m.nombre, CASE
      WHEN m.sigue_material_id IS NULL THEN 'no tiene a quién seguir'
      ELSE format('sigue a %s, que no elige', coalesce(l.nombre, i.nombre))
    END)
    FROM public.catalogo_materiales m
    LEFT JOIN public.catalogo_materiales l ON l.id = m.sigue_material_id
    LEFT JOIN public.catalogo_insumos i ON i.id = l.insumo_id
    WHERE m.version_id = p_version AND m.activo AND m.tipo = 'sigue'
      AND (l.id IS NULL OR l.tipo NOT IN ('elige_vendedor', 'elige_sistema'))
    ORDER BY 1);
  v_out := v_out || ARRAY(
    SELECT format('%s: la lista no tiene valores', x.nombre)
    FROM public.catalogo_variables x
    WHERE x.version_id = p_version AND x.activo AND x.es_lista AND cardinality(x.valores) = 0
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT format('%s: lo define el sistema y no tiene regla', m.nombre)
    FROM public.catalogo_materiales m
    WHERE m.version_id = p_version AND m.activo AND m.tipo = 'elige_sistema' AND m.eleccion_arbol IS NULL
    ORDER BY 1);
  v_out := v_out || ARRAY(
    SELECT DISTINCT format('%s: la regla elige %s, que no es una de sus opciones', m.nombre, e #>> '{}')
    FROM public.catalogo_materiales m,
         jsonb_path_query(m.eleccion_arbol, '$.** ? (@.op == "opcion").v') AS e
    WHERE m.version_id = p_version AND m.activo AND NOT EXISTS (
      SELECT 1 FROM public.catalogo_opciones o
      JOIN public.catalogo_insumos i ON i.id = o.insumo_id
      WHERE o.material_id = m.id AND o.activo AND i.nombre = e #>> '{}')
    ORDER BY 1);

  IF EXISTS (SELECT 1 FROM public.catalogo_versiones_colores vc WHERE vc.version_id = p_version AND vc.activo) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.catalogo_versiones_colores vc WHERE vc.version_id = p_version AND vc.activo AND vc.base
    ) THEN
      v_out := v_out || 'Falta elegir el color base'::text;
    END IF;
  ELSE
    v_out := v_out || ARRAY(
      SELECT DISTINCT format('%s tiene colores y la versión no ofrece ninguno', u.insumo)
      FROM public.catalogo_version_insumos(p_version) u
      WHERE u.con_color
      ORDER BY 1);
  END IF;

  v_out := v_out || ARRAY(
    SELECT format('En %s no se puede armar: falta %s', o.color, array_to_string(o.faltan, ', '))
    FROM public.catalogo_oferta(p_version) o
    WHERE o.color_id IS NOT NULL AND NOT o.armable
    ORDER BY 1);

  SELECT c.nombre INTO v_txt FROM public.catalogo_categorias c WHERE c.id = v_v.categoria_id AND NOT c.activo;
  IF FOUND THEN
    v_out := v_out || format('La categoría %s está de baja', v_txt);
  END IF;
  v_out := v_out || ARRAY(
    SELECT format('El color %s está de baja', c.nombre)
    FROM public.catalogo_versiones_colores vc
    JOIN public.catalogo_colores c ON c.id = vc.color_id
    WHERE vc.version_id = p_version AND vc.activo AND NOT c.activo
    ORDER BY 1);

  IF NOT EXISTS (SELECT 1 FROM public.catalogo_casos c WHERE c.version_id = p_version AND c.activo) THEN
    v_out := v_out || 'La versión no tiene casos de prueba'::text;
  END IF;
  -- Solo los errores: un bloqueo o un valor fuera de rango puede ser justo lo que se quiere probar.
  v_out := v_out || ARRAY(
    SELECT format('Caso %s: %s', c.nombre, e)
    FROM public.catalogo_casos_calcular(p_version) c,
         jsonb_array_elements_text(c.resultado->'errores') AS e
    ORDER BY c.nombre, e);

  RETURN v_out;
END;
$$;

-- ============================================================
-- 4. El ciclo
-- ============================================================
CREATE OR REPLACE FUNCTION public.catalogo_version_tomar(p_version uuid, p_permiso text, p_estado estado_version_catalogo)
RETURNS public.catalogo_versiones
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_v public.catalogo_versiones;
BEGIN
  IF NOT public.tiene_permiso(p_permiso) THEN
    RAISE EXCEPTION 'Esto requiere %', p_permiso USING ERRCODE = '42501';
  END IF;
  SELECT v.* INTO v_v FROM public.catalogo_versiones v WHERE v.id = p_version FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = 'CA016';
  END IF;
  IF v_v.estado <> p_estado THEN
    IF p_estado = 'borrador' THEN
      RAISE EXCEPTION 'Esta versión ya no está en borrador' USING ERRCODE = 'CA012';
    END IF;
    RAISE EXCEPTION 'Esta versión no está en revisión' USING ERRCODE = 'CA022';
  END IF;
  RETURN v_v;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_registrar(
  p_version uuid, p_estado estado_version_catalogo, p_accion accion_version_catalogo, p_motivo text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.catalogo_versiones SET estado = p_estado WHERE id = p_version;
  INSERT INTO public.catalogo_versiones_historia (version_id, accion, motivo, creado_por)
  VALUES (p_version, p_accion, p_motivo, auth.uid());
END;
$$;

-- Lo que el control de sql/160 no ve mientras la versión no se confirme: quien edita un insumo espera acá, y después ya la ve
-- enviada. Y al revés: quien da de baja un insumo espera, y su cascada ya encuentra la versión publicada.
CREATE OR REPLACE FUNCTION public.catalogo_version_bloquear(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  PERFORM 1 FROM public.catalogo_insumos i
  WHERE i.id IN (SELECT u.insumo_id FROM public.catalogo_version_insumos(p_version) u)
  ORDER BY i.id FOR SHARE;
  PERFORM 1 FROM public.catalogo_variantes va
  WHERE va.insumo_id IN (SELECT u.insumo_id FROM public.catalogo_version_insumos(p_version) u)
  ORDER BY va.id FOR SHARE;
  PERFORM 1 FROM public.catalogo_categorias c
  WHERE c.id = (SELECT v.categoria_id FROM public.catalogo_versiones v WHERE v.id = p_version)
  FOR SHARE;
  PERFORM 1 FROM public.catalogo_colores c
  WHERE c.id IN (
    SELECT vc.color_id FROM public.catalogo_versiones_colores vc WHERE vc.version_id = p_version AND vc.activo)
  ORDER BY c.id FOR SHARE;
END;
$$;

-- Después de bloquear: frena corre con una foto nueva, que ya ve lo que confirmó quien estaba adelante.
CREATE OR REPLACE FUNCTION public.catalogo_version_exigir(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_frena text[];
BEGIN
  PERFORM public.catalogo_version_bloquear(p_version);
  v_frena := public.catalogo_version_frena(p_version);
  IF cardinality(v_frena) > 0 THEN
    RAISE EXCEPTION '%', array_to_string(v_frena, E'\n') USING ERRCODE = 'CA019';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_revisar(p_version uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tiene_permiso('catalogo_paquetes') THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = 'CA016';
  END IF;
  RETURN public.catalogo_version_frena(p_version);
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_oferta(p_version uuid)
RETURNS TABLE (color_id uuid, color text, armable boolean, piezas_fuera uuid[], opciones_fuera uuid[], faltan text[])
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tiene_permiso('catalogo_paquetes')
     OR NOT EXISTS (SELECT 1 FROM public.catalogo_versiones v WHERE v.id = p_version) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = 'CA016';
  END IF;
  RETURN QUERY SELECT o.color_id, o.color, o.armable, o.piezas_fuera, o.opciones_fuera, o.faltan
    FROM public.catalogo_oferta(p_version) o;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_enviar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.catalogo_version_tomar(p_version, 'catalogo_armar', 'borrador');
  PERFORM public.catalogo_version_exigir(p_version);
  PERFORM public.catalogo_version_registrar(p_version, 'en_revision', 'enviada');
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_retirar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.catalogo_version_tomar(p_version, 'catalogo_armar', 'en_revision');
  PERFORM public.catalogo_version_registrar(p_version, 'borrador', 'retirada');
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_devolver(p_version uuid, p_motivo text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_motivo text := nullif(btrim(p_motivo), '');
BEGIN
  PERFORM public.catalogo_version_tomar(p_version, 'catalogo_aprobar', 'en_revision');
  IF v_motivo IS NULL THEN
    RAISE EXCEPTION 'Para devolverla hay que decir por qué' USING ERRCODE = 'CA021';
  END IF;
  PERFORM public.catalogo_version_registrar(p_version, 'borrador', 'devuelta', v_motivo);
END;
$$;

-- Primero la anterior: el índice deja una sola publicada por paquete. No toca si el paquete está activo: aprobar una versión
-- de un paquete de baja no lo pone a la venta.
CREATE OR REPLACE FUNCTION public.catalogo_version_aprobar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.catalogo_versiones;
  v_anterior uuid;
BEGIN
  v_v := public.catalogo_version_tomar(p_version, 'catalogo_aprobar', 'en_revision');
  PERFORM public.catalogo_version_exigir(p_version);

  SELECT a.id INTO v_anterior FROM public.catalogo_versiones a
  WHERE a.paquete_id = v_v.paquete_id AND a.estado = 'publicado';
  IF FOUND THEN
    PERFORM public.catalogo_version_registrar(v_anterior, 'obsoleto', 'obsoleta');
  END IF;
  PERFORM public.catalogo_version_registrar(p_version, 'publicado', 'aprobada');
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_version_descartar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.catalogo_versiones;
BEGIN
  v_v := public.catalogo_version_tomar(p_version, 'catalogo_armar', 'borrador');
  IF NOT EXISTS (
    SELECT 1 FROM public.catalogo_versiones p WHERE p.paquete_id = v_v.paquete_id AND p.estado = 'publicado'
  ) THEN
    RAISE EXCEPTION 'Este paquete no tiene una versión publicada: en vez de descartarla, dalo de baja'
      USING ERRCODE = 'CA023';
  END IF;
  PERFORM public.catalogo_version_registrar(p_version, 'descartado', 'descartada');
END;
$$;

-- ============================================================
-- 5. Bajas en cascada, aviso previo y reactivación
-- ============================================================
-- Qué pasaría con cada paquete activo si se da de baja este insumo o, con p_variante, solo esa variante. Compara la oferta
-- de hoy con la de después: lo que ya estaba afuera no es de esta baja. sale: no se arma en ningún color.
CREATE OR REPLACE FUNCTION public.catalogo_baja_efecto(p_insumo uuid, p_variante uuid DEFAULT NULL)
RETURNS TABLE (paquete_id uuid, nombre text, sale boolean, colores text[], piezas text[], opciones text[])
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_q record;
  v_o record;
  v_piezas uuid[];
  v_opciones uuid[];
BEGIN
  FOR v_q IN
    SELECT v.id, v.paquete_id, v.nombre
    FROM public.catalogo_versiones v
    JOIN public.catalogo_paquetes q ON q.id = v.paquete_id
    WHERE q.activo AND v.estado = 'publicado' AND (
      EXISTS (SELECT 1 FROM public.catalogo_materiales m WHERE m.version_id = v.id AND m.activo AND m.insumo_id = p_insumo)
      OR EXISTS (SELECT 1 FROM public.catalogo_opciones o WHERE o.version_id = v.id AND o.activo AND o.insumo_id = p_insumo))
    ORDER BY v.nombre
  LOOP
    paquete_id := v_q.paquete_id;
    nombre := v_q.nombre;
    sale := true;
    colores := '{}';
    v_piezas := '{}';
    v_opciones := '{}';

    FOR v_o IN
      SELECT d.color AS color_nombre, d.armable AS despues, a.armable AS antes,
             ARRAY(SELECT unnest(d.piezas_fuera) EXCEPT SELECT unnest(a.piezas_fuera)) AS piezas_nuevas,
             ARRAY(SELECT unnest(d.opciones_fuera) EXCEPT SELECT unnest(a.opciones_fuera)) AS opciones_nuevas
      FROM public.catalogo_oferta(v_q.id) a
      JOIN public.catalogo_oferta(v_q.id, CASE WHEN p_variante IS NULL THEN p_insumo END, p_variante) d
        ON d.color_id IS NOT DISTINCT FROM a.color_id
    LOOP
      IF v_o.despues THEN
        sale := false;
        v_piezas := v_piezas || v_o.piezas_nuevas;
        v_opciones := v_opciones || v_o.opciones_nuevas;
      ELSIF v_o.antes AND v_o.color_nombre IS NOT NULL THEN
        colores := colores || v_o.color_nombre;
      END IF;
    END LOOP;

    piezas := ARRAY(SELECT DISTINCT p.nombre FROM public.catalogo_piezas p WHERE p.id = ANY (v_piezas) ORDER BY 1);
    opciones := ARRAY(
      SELECT DISTINCT i.nombre
      FROM public.catalogo_opciones o
      JOIN public.catalogo_insumos i ON i.id = o.insumo_id
      WHERE o.id = ANY (v_opciones)
      ORDER BY 1);

    IF sale OR cardinality(colores) + cardinality(piezas) + cardinality(opciones) > 0 THEN
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

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
BEGIN
  IF TG_TABLE_NAME = 'catalogo_variantes' THEN
    v_insumo := NEW.insumo_id;
    v_variante := NEW.id;
  ELSE
    v_insumo := NEW.id;
  END IF;

  UPDATE public.catalogo_paquetes q
  SET activo = false,
      baja_insumo_id = CASE WHEN v_variante IS NULL THEN v_insumo END,
      baja_variante_id = v_variante
  FROM public.catalogo_baja_efecto(v_insumo, v_variante) e
  WHERE e.paquete_id = q.id AND e.sale;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_insumos_baja BEFORE UPDATE OF activo ON public.catalogo_insumos
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo) EXECUTE FUNCTION public.catalogo_baja_cascada();
CREATE OR REPLACE TRIGGER catalogo_variantes_baja BEFORE UPDATE OF activo ON public.catalogo_variantes
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo) EXECUTE FUNCTION public.catalogo_baja_cascada();

-- Vuelve a vender la publicada sin pasar por el gerente, que ya la aprobó. Sin publicada no hay nada que revisar.
CREATE OR REPLACE FUNCTION public.catalogo_paquete_reactivar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_version uuid;
  v_txt text;
BEGIN
  SELECT v.id INTO v_version FROM public.catalogo_versiones v WHERE v.paquete_id = NEW.id AND v.estado = 'publicado';
  IF FOUND THEN
    PERFORM public.catalogo_version_bloquear(v_version);

    SELECT c.nombre INTO v_txt
    FROM public.catalogo_versiones v
    JOIN public.catalogo_categorias c ON c.id = v.categoria_id AND NOT c.activo
    WHERE v.id = v_version;
    IF FOUND THEN
      RAISE EXCEPTION 'La categoría % está de baja: reactivala primero', v_txt USING ERRCODE = 'CA008';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.catalogo_oferta(v_version) o WHERE o.armable) THEN
      SELECT string_agg(DISTINCT f, ', ' ORDER BY f) INTO v_txt
      FROM public.catalogo_oferta(v_version) o, unnest(o.faltan) AS f;
      RAISE EXCEPTION 'No se puede reactivar: falta %', v_txt USING ERRCODE = 'CA020';
    END IF;
  END IF;

  NEW.baja_insumo_id := NULL;
  NEW.baja_variante_id := NULL;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_paquetes_reactivar BEFORE UPDATE OF activo ON public.catalogo_paquetes
  FOR EACH ROW WHEN (NOT OLD.activo AND NEW.activo) EXECUTE FUNCTION public.catalogo_paquete_reactivar();

-- Quien no tiene la vista Paquetes ve solo los números.
CREATE OR REPLACE FUNCTION public.catalogo_baja_aviso(p_insumo uuid, p_variante uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_puede boolean;
  v_out jsonb;
BEGIN
  SELECT public.catalogo_puede_editar(i.tipo) INTO v_puede
  FROM public.catalogo_insumos i
  WHERE i.id = p_insumo AND (p_variante IS NULL OR EXISTS (
    SELECT 1 FROM public.catalogo_variantes va WHERE va.id = p_variante AND va.insumo_id = i.id));
  IF NOT coalesce(v_puede, false) THEN
    RAISE EXCEPTION 'Dar esto de baja requiere catalogo_cargar o catalogo_fijos_editar' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object('salen', count(*) FILTER (WHERE e.sale), 'dejan', count(*) FILTER (WHERE NOT e.sale))
    || CASE WHEN public.tiene_permiso('catalogo_paquetes') THEN jsonb_build_object(
         'salen_nombres', coalesce(jsonb_agg(e.nombre ORDER BY e.nombre) FILTER (WHERE e.sale), '[]'),
         'dejan_detalle', coalesce(jsonb_agg(jsonb_build_object(
           'nombre', e.nombre, 'colores', e.colores, 'piezas', e.piezas, 'opciones', e.opciones
         ) ORDER BY e.nombre) FILTER (WHERE NOT e.sale), '[]'))
       ELSE '{}'::jsonb END
  INTO v_out
  FROM public.catalogo_baja_efecto(p_insumo, p_variante) e;
  RETURN v_out;
END;
$$;

-- ============================================================
-- 6. Privilegios de las funciones
-- ============================================================
REVOKE EXECUTE ON FUNCTION
  public.catalogo_oferta(uuid, uuid, uuid),
  public.catalogo_version_formulas(uuid),
  public.catalogo_version_alcance(uuid),
  public.catalogo_version_referencias(uuid),
  public.catalogo_version_circular(uuid),
  public.catalogo_version_insumos(uuid),
  public.catalogo_version_frena(uuid),
  public.catalogo_version_tomar(uuid, text, estado_version_catalogo),
  public.catalogo_version_registrar(uuid, estado_version_catalogo, accion_version_catalogo, text),
  public.catalogo_version_bloquear(uuid),
  public.catalogo_version_exigir(uuid),
  public.catalogo_baja_efecto(uuid, uuid),
  public.catalogo_baja_cascada(),
  public.catalogo_paquete_reactivar()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.catalogo_version_revisar(uuid),
  public.catalogo_version_oferta(uuid),
  public.catalogo_version_enviar(uuid),
  public.catalogo_version_retirar(uuid),
  public.catalogo_version_devolver(uuid, text),
  public.catalogo_version_aprobar(uuid),
  public.catalogo_version_descartar(uuid),
  public.catalogo_baja_aviso(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.catalogo_version_revisar(uuid),
  public.catalogo_version_oferta(uuid),
  public.catalogo_version_enviar(uuid),
  public.catalogo_version_retirar(uuid),
  public.catalogo_version_devolver(uuid, text),
  public.catalogo_version_aprobar(uuid),
  public.catalogo_version_descartar(uuid),
  public.catalogo_baja_aviso(uuid, uuid)
TO authenticated;
