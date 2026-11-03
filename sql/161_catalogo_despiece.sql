-- Catálogo, tramo 4: el cálculo del despiece, con sus alertas y bloqueos, y los casos de prueba.
-- Decisiones: decisiones/catalogo/despiece.md. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_despiece.sql.
--
-- No lee costos: el precio (sql/163) parte de este resultado. Es INVOKER, así que lo abre quien tiene la vista
-- Paquetes, y una función DEFINER del precio lo llama como dueña sin darle a nadie acceso a las tablas.

-- ============================================================
-- 1. Lo que cargaría un vendedor
-- ============================================================
-- {"variables": {"ancho": 1500, "mano": "Izquierda"},
--  "elecciones": {"Hoja": {"Vidrio": "<insumo_id>", "Manija": null}},
--  "piezas": {"Mosquitero": true},
--  "color": "<color_id>"}
-- Piezas, materiales y variables van por nombre, como las fórmulas, porque sus ids cambian de una versión a la
-- siguiente y un caso se copia; insumos y colores, por id, que son los mismos. null en una elección es "sin elección".
CREATE OR REPLACE FUNCTION public.catalogo_entrada_valida(p_entrada jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF jsonb_typeof(p_entrada) IS DISTINCT FROM 'object' THEN
    RETURN false;
  END IF;
  IF coalesce(jsonb_typeof(p_entrada->'variables'), 'object') <> 'object'
     OR coalesce(jsonb_typeof(p_entrada->'elecciones'), 'object') <> 'object'
     OR coalesce(jsonb_typeof(p_entrada->'piezas'), 'object') <> 'object'
     OR coalesce(jsonb_typeof(p_entrada->'color'), 'string') <> 'string' THEN
    RETURN false;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_entrada) k WHERE k <> ALL (ARRAY['variables', 'elecciones', 'piezas', 'color']))
     OR EXISTS (SELECT 1 FROM jsonb_each(p_entrada->'variables') e WHERE jsonb_typeof(e.value) NOT IN ('number', 'string'))
     OR EXISTS (SELECT 1 FROM jsonb_each(p_entrada->'piezas') e WHERE jsonb_typeof(e.value) <> 'boolean')
     OR EXISTS (SELECT 1 FROM jsonb_each(p_entrada->'elecciones') e WHERE jsonb_typeof(e.value) <> 'object') THEN
    RETURN false;
  END IF;
  RETURN NOT EXISTS (
    SELECT 1 FROM jsonb_each(p_entrada->'elecciones') p, jsonb_each(p.value) m
    WHERE jsonb_typeof(m.value) NOT IN ('string', 'null'));
END;
$$;

ALTER TABLE public.catalogo_casos DROP CONSTRAINT IF EXISTS catalogo_casos_entrada_check;
ALTER TABLE public.catalogo_casos DROP CONSTRAINT IF EXISTS catalogo_casos_entrada_forma;
ALTER TABLE public.catalogo_casos ADD CONSTRAINT catalogo_casos_entrada_forma
  CHECK (public.catalogo_entrada_valida(entrada));

-- Qué piezas están, qué eligió el vendedor y en qué color, sin calcular nada. Lo que la entrada elige y la versión
-- ya no tiene es un error: un caso copiado no puede seguir de largo sin esa elección.
CREATE OR REPLACE FUNCTION public.catalogo_despiece_entrada(
  p_version uuid,
  p_entrada jsonb,
  OUT adentro uuid[],
  OUT elegidas jsonb,
  OUT faltan text[],
  OUT errores text[],
  OUT color jsonb
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_m record;
  v_valor jsonb;
  v_opcion uuid;
BEGIN
  elegidas := '{}';
  faltan := '{}';

  errores := ARRAY(
    SELECT format('%s: esa pieza ya no se puede elegir', k)
    FROM jsonb_object_keys(coalesce(p_entrada->'piezas', '{}')) k
    WHERE NOT EXISTS (
      SELECT 1 FROM public.catalogo_piezas p
      WHERE p.version_id = p_version AND p.activo AND p.opcional AND p.nombre = k)
    ORDER BY 1);

  errores := errores || ARRAY(
    SELECT format('%s: esa elección ya no existe', m.key)
    FROM jsonb_each(coalesce(p_entrada->'elecciones', '{}')) p, jsonb_each(p.value) m
    WHERE NOT EXISTS (
      SELECT 1 FROM public.catalogo_materiales x
      JOIN public.catalogo_piezas y ON y.id = x.pieza_id
      WHERE x.version_id = p_version AND x.activo AND x.tipo = 'elige_vendedor'
        AND y.nombre = p.key AND x.nombre = m.key)
    ORDER BY 1);

  -- Destildar el Cajón destilda la Cortina que lo requiere, y una Cortina incluida trae su Cajón.
  WITH RECURSIVE marcadas AS (
    SELECT p.id, p.opcional, p.incluida, p.requiere_pieza_id,
           (p_entrada->'piezas'->>p.nombre)::boolean AS marcada
    FROM public.catalogo_piezas p
    WHERE p.version_id = p_version AND p.activo
  ),
  fuera AS (
    SELECT m.id FROM marcadas m WHERE m.opcional AND m.marcada = false
    UNION
    SELECT m.id FROM marcadas m JOIN fuera f ON m.requiere_pieza_id = f.id
  ),
  dentro AS (
    SELECT m.id, m.requiere_pieza_id FROM marcadas m
    WHERE (NOT m.opcional OR coalesce(m.marcada, m.incluida))
      AND m.id NOT IN (SELECT f.id FROM fuera f)
    UNION
    SELECT r.id, r.requiere_pieza_id FROM marcadas r JOIN dentro d ON r.id = d.requiere_pieza_id
  )
  SELECT coalesce(array_agg(d.id), '{}') INTO adentro FROM dentro d;

  FOR v_m IN
    SELECT x.id, x.nombre, x.tipo, x.sin_eleccion, y.nombre AS pieza, x.pieza_id = ANY (adentro) AS esta
    FROM public.catalogo_materiales x
    JOIN public.catalogo_piezas y ON y.id = x.pieza_id
    WHERE x.version_id = p_version AND x.activo AND x.tipo IN ('elige_vendedor', 'elige_sistema')
  LOOP
    IF v_m.tipo = 'elige_sistema' THEN
      -- Lo define su regla al calcular. En una pieza que no está no corre, y quien lo sigue no puede esperarla.
      IF NOT v_m.esta THEN
        elegidas := elegidas || jsonb_build_object(v_m.id, NULL::uuid);
      END IF;
      CONTINUE;
    END IF;

    v_valor := p_entrada->'elecciones'->v_m.pieza->v_m.nombre;
    v_opcion := NULL;
    IF v_valor IS NULL THEN
      SELECT o.id INTO v_opcion FROM public.catalogo_opciones o
      WHERE o.material_id = v_m.id AND o.activo AND o.predeterminada;
      IF v_opcion IS NULL AND NOT v_m.sin_eleccion THEN
        faltan := faltan || v_m.id::text;
      END IF;
    ELSIF jsonb_typeof(v_valor) = 'null' THEN
      IF NOT v_m.sin_eleccion THEN
        faltan := faltan || v_m.id::text;
      END IF;
    ELSE
      SELECT o.id INTO v_opcion FROM public.catalogo_opciones o
      WHERE o.material_id = v_m.id AND o.activo AND o.insumo_id::text = v_valor #>> '{}';
      IF v_opcion IS NULL THEN
        errores := errores || format('%s: esa opción ya no existe', v_m.nombre);
      END IF;
    END IF;
    elegidas := elegidas || jsonb_build_object(v_m.id, v_opcion);
  END LOOP;

  IF p_entrada ? 'color' THEN
    SELECT jsonb_build_object('id', c.id, 'nombre', c.nombre) INTO color
    FROM public.catalogo_versiones_colores vc
    JOIN public.catalogo_colores c ON c.id = vc.color_id
    WHERE vc.version_id = p_version AND vc.activo AND c.id::text = p_entrada->>'color';
    IF color IS NULL THEN
      errores := errores || 'El color elegido no está en esta versión'::text;
    END IF;
  ELSE
    SELECT jsonb_build_object('id', c.id, 'nombre', c.nombre) INTO color
    FROM public.catalogo_versiones_colores vc
    JOIN public.catalogo_colores c ON c.id = vc.color_id
    WHERE vc.version_id = p_version AND vc.activo AND vc.base;
  END IF;
END;
$$;

-- ============================================================
-- 2. Una fila
-- ============================================================
-- 1500 → 1.500, -18 → −18, 666,666 → 666,67: se lee como en el resto del sistema.
CREATE OR REPLACE FUNCTION public.catalogo_numero_texto(p_n numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE WHEN round(p_n, 2) < 0 THEN '−' ELSE '' END
    || translate(rtrim(to_char(abs(round(p_n, 2)), 'FM999,999,999,999,990.99'), '.'), ',.', '.,');
$$;

CREATE OR REPLACE FUNCTION public.catalogo_despiece_medida(p_arbol jsonb, p_v jsonb, p_que text, p_unidad text DEFAULT 'mm')
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_n numeric;
BEGIN
  IF p_arbol IS NULL THEN
    RETURN NULL;
  END IF;
  v_n := public.catalogo_formula_evaluar(p_arbol, p_v);
  IF v_n <= 0 THEN
    RAISE EXCEPTION '% dio % %', p_que, public.catalogo_numero_texto(v_n), p_unidad USING ERRCODE = 'CA018';
  END IF;
  RETURN v_n;
END;
$$;

-- Qué opción ocupa el lugar de un material. '{}' es el único, que no tiene opciones; NULL es que no lleva.
-- Esperar a lo que elige otro material es lo mismo que esperar un valor: por eso CA002.
CREATE OR REPLACE FUNCTION public.catalogo_despiece_elegir(p_m jsonb, p_elegidas jsonb, p_faltan text[], p_v jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_elegida text;
  v_o jsonb;
BEGIN
  CASE p_m->>'tipo'
    WHEN 'unico' THEN
      IF NOT p_m ? 'insumo' THEN
        RAISE EXCEPTION 'falta el insumo' USING ERRCODE = 'CA018';
      END IF;
      RETURN '{}';
    WHEN 'elige_vendedor' THEN
      IF (p_m->>'id') = ANY (p_faltan) THEN
        RAISE EXCEPTION 'falta elegir una opción' USING ERRCODE = 'CA018';
      END IF;
      v_elegida := p_elegidas->>(p_m->>'id');
      RETURN (SELECT o FROM jsonb_array_elements(p_m->'opciones') o WHERE o->>'id' = v_elegida);
    WHEN 'elige_sistema' THEN
      IF NOT p_m ? 'eleccion' THEN
        RAISE EXCEPTION 'falta la regla que elige' USING ERRCODE = 'CA018';
      END IF;
      v_elegida := public.catalogo_eleccion_evaluar(p_m->'eleccion', p_v);
      IF v_elegida IS NULL THEN
        RETURN NULL;
      END IF;
      SELECT o INTO v_o FROM jsonb_array_elements(p_m->'opciones') o WHERE o->'insumo'->>'nombre' = v_elegida;
      IF v_o IS NULL THEN
        RAISE EXCEPTION 'la regla eligió %, que no es una de sus opciones', v_elegida USING ERRCODE = 'CA018';
      END IF;
      RETURN v_o;
    ELSE
      IF NOT p_m ? 'sigue' THEN
        RAISE EXCEPTION 'no tiene a quién seguir' USING ERRCODE = 'CA018';
      END IF;
      IF p_m->>'sigue_tipo' NOT IN ('elige_vendedor', 'elige_sistema') THEN
        RAISE EXCEPTION 'sigue a un material que no elige' USING ERRCODE = 'CA018';
      END IF;
      IF NOT p_elegidas ? (p_m->>'sigue') THEN
        RAISE EXCEPTION 'Falta el valor de %', p_m->>'sigue_nombre' USING ERRCODE = 'CA002';
      END IF;
      v_elegida := p_elegidas->>(p_m->>'sigue');
      IF v_elegida IS NULL THEN
        RETURN NULL;
      END IF;
      SELECT o INTO v_o FROM jsonb_array_elements(p_m->'opciones') o WHERE o->>'sigue_opcion' = v_elegida;
      IF v_o IS NULL THEN
        RAISE EXCEPTION 'falta la pareja de la opción elegida' USING ERRCODE = 'CA018';
      END IF;
      RETURN CASE WHEN v_o ? 'insumo' THEN v_o END;
  END CASE;
END;
$$;

-- p_m || p_o: lo que la opción no trae lo hereda del material, cada fórmula por separado. Cada unidad lee solo sus
-- fórmulas: el Enrollable (u) no toma el ancho y el alto de la Tela (m2).
-- valor: lo que vale en otra fórmula, lo de una pieza. La medida de un insumo en u no se cobra ni vale: es para cortar.
CREATE OR REPLACE FUNCTION public.catalogo_despiece_fila(p_m jsonb, p_o jsonb, p_cant_pieza numeric, p_color jsonb, p_v jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_f jsonb := p_m || p_o;
  v_i jsonb := v_f->'insumo';
  v_unidad text := v_i->>'unidad';
  v_cuenta boolean := v_i->>'tipo' = 'insumo';
  v_cant numeric;
  v_medida numeric;
  v_ancho numeric;
  v_alto numeric;
  v_area numeric;
  v_valor numeric;
  v_en_unidad numeric;
BEGIN
  v_cant := public.catalogo_formula_evaluar(v_f->'cantidad', p_v);
  IF v_cant < 0 THEN
    RAISE EXCEPTION 'la cantidad dio %', public.catalogo_numero_texto(v_cant) USING ERRCODE = 'CA018';
  END IF;
  IF v_cant = 0 THEN
    RETURN NULL;
  END IF;

  IF v_unidad = 'm2' THEN
    v_ancho := public.catalogo_despiece_medida(v_f->'ancho', p_v, 'el ancho');
    v_alto := public.catalogo_despiece_medida(v_f->'alto', p_v, 'el alto');
    v_area := coalesce(public.catalogo_despiece_medida(v_f->'area', p_v, 'el área', 'mm²'), v_ancho * v_alto);
    IF v_area IS NULL THEN
      RAISE EXCEPTION 'falta el ancho o el alto' USING ERRCODE = 'CA018';
    END IF;
    v_valor := v_area * v_cant;
    v_en_unidad := v_valor / 1000000;
  ELSE
    v_medida := public.catalogo_despiece_medida(v_f->'medida', p_v, 'la medida');
    IF v_unidad = 'u' THEN
      v_valor := v_cant;
      v_en_unidad := v_cant;
    ELSIF v_medida IS NULL THEN
      RAISE EXCEPTION 'falta la medida' USING ERRCODE = 'CA018';
    ELSE
      v_valor := v_medida * v_cant;
      v_en_unidad := v_valor / 1000;
    END IF;
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'valor', v_valor,
    'peso', CASE WHEN v_cuenta AND (p_m->>'cuenta_peso')::boolean THEN v_en_unidad * (v_i->>'peso')::numeric END,
    'sin_peso', CASE WHEN v_cuenta AND (p_m->>'cuenta_peso')::boolean AND NOT v_i ? 'peso' THEN true END,
    'espesor', CASE WHEN v_cuenta AND (p_m->>'cuenta_espesor')::boolean THEN v_cant * (v_i->>'espesor')::numeric END,
    'sin_espesor', CASE WHEN v_cuenta AND (p_m->>'cuenta_espesor')::boolean AND NOT v_i ? 'espesor' THEN true END,
    'fila', jsonb_build_object(
      'pieza_id', p_m->>'pieza_id',
      'pieza', p_m->>'pieza',
      'material_id', p_m->>'id',
      'opcion_id', p_o->>'id',
      'material', p_m->>'nombre',
      'insumo_id', v_i->>'id',
      'insumo', v_i->>'nombre',
      'tipo', v_i->>'tipo',
      'categoria_id', v_i->>'categoria_id',
      'unidad', v_unidad,
      'color_id', CASE WHEN (v_i->>'con_color')::boolean THEN p_color->>'id' END,
      'color', CASE WHEN (v_i->>'con_color')::boolean THEN p_color->>'nombre' END,
      'medida', v_medida,
      'ancho', v_ancho,
      'alto', v_alto,
      'area', v_area / 1000000,
      'cantidad', v_cant * p_cant_pieza,
      'total', CASE WHEN v_unidad = 'mm' THEN v_valor ELSE v_en_unidad END * p_cant_pieza
    )
  ));
END;
$$;

-- ============================================================
-- 3. Lo que ya se puede usar en otra fórmula
-- ============================================================
-- Un nombre vale recién cuando están todos sus materiales. local: lo de una pieza, para adentro de esa pieza.
-- global: lo de todo el paquete, para las demás. datos: peso y espesor de una pieza. esperan: a qué espera cada dato.
CREATE OR REPLACE FUNCTION public.catalogo_despiece_sumas(p_piezas jsonb, p_materiales jsonb, p_cant jsonb, p_hechos jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  WITH m AS (
    SELECT x->>'pieza_id' AS pieza_id, x->>'nombre' AS nombre, p_hechos->(x->>'id') AS h,
           (x->>'cuenta_peso')::boolean AS cuenta_peso, (x->>'cuenta_espesor')::boolean AS cuenta_espesor
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

-- ============================================================
-- 4. El cálculo
-- ============================================================
-- Las fórmulas se escriben en cualquier orden y una puede usar lo que otra todavía no calculó: se vuelve a pasar
-- hasta que una vuelta no resuelve nada, y lo que queda esperando es lo circular o lo que no existe. Por eso un
-- borrador a medias da "no se puede calcular" y no un error de la base.
CREATE OR REPLACE FUNCTION public.catalogo_despiece(p_version uuid, p_entrada jsonb DEFAULT '{}')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_e record;
  v_c record;
  v_piezas jsonb;
  v_variables jsonb;
  v_materiales jsonb;
  v_x jsonb;
  v_o jsonb;
  v_fila jsonb;
  v_valor jsonb;
  v_cant jsonb := '{}';
  v_valores jsonb := '{}';
  v_listas jsonb := '{}';
  v_elegidas jsonb;
  v_hechos jsonb := '{}';
  v_listos jsonb := '{}';
  v_fallos jsonb := '{}';
  v_espera jsonb;
  v_sumas jsonb;
  v_global jsonb;
  v_ambito jsonb;
  v_salen jsonb := '{}';
  v_salida_variables jsonb := '[]';
  v_salida_piezas jsonb := '[]';
  v_salida_filas jsonb := '[]';
  v_mensajes jsonb := '[]';
  v_errores text[];
  v_raices text[];
  v_progreso boolean;
  v_id text;
  v_quien text;
  v_pieza text;
  v_txt text;
  v_num numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.catalogo_versiones v WHERE v.id = p_version) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = 'CA016';
  END IF;
  IF NOT public.catalogo_entrada_valida(p_entrada) THEN
    RAISE EXCEPTION 'La entrada no tiene la forma esperada' USING ERRCODE = 'CA017';
  END IF;

  SELECT * INTO v_e FROM public.catalogo_despiece_entrada(p_version, p_entrada);
  v_elegidas := v_e.elegidas;

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'clase', 'pieza', 'id', p.id, 'nombre', p.nombre, 'cantidad', p.cantidad_arbol,
    'calcula_espesor', p.calcula_espesor, 'peso_a_produccion', p.peso_a_produccion,
    'espesor_a_produccion', p.espesor_a_produccion
  )) ORDER BY p.orden, p.nombre), '[]') INTO v_piezas
  FROM public.catalogo_piezas p
  WHERE p.id = ANY (v_e.adentro);

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'clase', 'variable', 'id', x.id, 'nombre', x.nombre, 'pieza_id', x.pieza_id, 'ingresa', x.ingresa_vendedor,
    'es_lista', x.es_lista, 'formula', x.formula_arbol, 'valores', to_jsonb(x.valores),
    'predeterminado', x.valor_predeterminado, 'es_cantidad', x.es_cantidad, 'minimo', x.minimo, 'maximo', x.maximo,
    'a_produccion', x.a_produccion
  )) ORDER BY x.pieza_id IS NOT NULL, p.orden, p.nombre, x.orden, x.created_at, x.id), '[]') INTO v_variables
  FROM public.catalogo_variables x
  LEFT JOIN public.catalogo_piezas p ON p.id = x.pieza_id
  WHERE x.version_id = p_version AND x.activo AND (x.pieza_id IS NULL OR x.pieza_id = ANY (v_e.adentro));

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'clase', 'material', 'id', m.id, 'pieza_id', m.pieza_id, 'pieza', p.nombre, 'tipo', m.tipo,
    'nombre', coalesce(m.nombre, i.nombre), 'insumo', to_jsonb(i),
    'medida', m.medida_arbol, 'ancho', m.ancho_arbol, 'alto', m.alto_arbol, 'area', m.area_arbol,
    'cantidad', m.cantidad_arbol, 'eleccion', m.eleccion_arbol,
    'sigue', m.sigue_material_id, 'sigue_tipo', s.tipo, 'sigue_nombre', s.nombre,
    'cuenta_peso', m.cuenta_peso, 'cuenta_espesor', m.cuenta_espesor,
    'opciones', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'sigue_opcion', o.sigue_opcion_id, 'insumo', to_jsonb(oi),
        'medida', o.medida_arbol, 'ancho', o.ancho_arbol, 'alto', o.alto_arbol, 'area', o.area_arbol,
        'cantidad', o.cantidad_arbol
      ) ORDER BY o.orden, o.created_at, o.id), '[]')
      FROM public.catalogo_opciones o
      LEFT JOIN public.catalogo_insumos oi ON oi.id = o.insumo_id
      WHERE o.material_id = m.id AND o.activo)
  )) ORDER BY p.orden, p.nombre, m.orden, m.created_at, m.id), '[]') INTO v_materiales
  FROM public.catalogo_materiales m
  JOIN public.catalogo_piezas p ON p.id = m.pieza_id
  LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
  LEFT JOIN public.catalogo_materiales s ON s.id = m.sigue_material_id
  WHERE m.version_id = p_version AND m.activo AND m.pieza_id = ANY (v_e.adentro);

  LOOP
    v_sumas := public.catalogo_despiece_sumas(v_piezas, v_materiales, v_cant, v_hechos);
    v_global := (v_sumas->'global') || (v_sumas->'datos') || v_valores;
    v_espera := '{}';
    v_progreso := false;

    FOR v_x IN SELECT x FROM jsonb_array_elements(v_variables || v_piezas || v_materiales) x LOOP
      v_id := v_x->>'id';
      CONTINUE WHEN v_listos ? v_id OR v_fallos ? v_id;

      v_quien := CASE v_x->>'clase'
        WHEN 'pieza' THEN 'cantidad de ' || (v_x->>'nombre')
        ELSE coalesce(v_x->>'nombre', 'Un material de ' || (v_x->>'pieza'))
      END;
      v_pieza := coalesce(v_x->>'pieza_id', v_id);
      v_ambito := v_global || coalesce(v_sumas->'local'->v_pieza, '{}');

      BEGIN
        IF v_x->>'clase' = 'variable' THEN
          v_valor := CASE WHEN (v_x->>'ingresa')::boolean THEN p_entrada->'variables'->v_quien END;
          IF (v_x->>'es_lista')::boolean THEN
            IF v_valor IS NOT NULL AND (jsonb_typeof(v_valor) <> 'string' OR NOT (v_x->'valores') ? (v_valor #>> '{}')) THEN
              RAISE EXCEPTION 'el valor % no está en la lista', v_valor #>> '{}' USING ERRCODE = 'CA018';
            END IF;
            v_txt := coalesce(v_valor #>> '{}', v_x->>'predeterminado');
            IF v_txt IS NULL THEN
              RAISE EXCEPTION 'falta elegir un valor' USING ERRCODE = 'CA018';
            END IF;
            v_listas := v_listas || jsonb_build_object(v_quien, v_txt);
          ELSE
            IF v_valor IS NOT NULL THEN
              IF jsonb_typeof(v_valor) <> 'number' THEN
                RAISE EXCEPTION 'no es un número' USING ERRCODE = 'CA018';
              END IF;
              v_num := (v_valor #>> '{}')::numeric;
            ELSIF v_x ? 'formula' THEN
              v_num := public.catalogo_formula_evaluar(v_x->'formula', v_ambito);
            ELSE
              RAISE EXCEPTION 'falta el valor' USING ERRCODE = 'CA018';
            END IF;
            v_valores := v_valores || jsonb_build_object(v_quien, v_num);
            v_global := v_global || jsonb_build_object(v_quien, v_num);
          END IF;

        ELSIF v_x->>'clase' = 'pieza' THEN
          v_num := public.catalogo_formula_evaluar(v_x->'cantidad', v_ambito);
          IF v_num < 0 THEN
            RAISE EXCEPTION 'dio %', public.catalogo_numero_texto(v_num) USING ERRCODE = 'CA018';
          END IF;
          v_cant := v_cant || jsonb_build_object(v_id, v_num);

        ELSE
          IF NOT v_cant ? v_pieza THEN
            v_espera := v_espera || jsonb_build_object(v_quien, 'cantidad de ' || (v_x->>'pieza'));
            CONTINUE;
          END IF;

          IF (v_cant->>v_pieza)::numeric = 0 THEN
            v_fila := NULL;
            IF v_x->>'tipo' = 'elige_sistema' THEN
              v_elegidas := v_elegidas || jsonb_build_object(v_id, NULL::uuid);
            END IF;
          ELSE
            v_o := public.catalogo_despiece_elegir(v_x, v_elegidas, v_e.faltan, v_ambito);
            IF v_x->>'tipo' = 'elige_sistema' THEN
              v_elegidas := v_elegidas || jsonb_build_object(v_id, v_o->'id');
            END IF;
            v_fila := CASE WHEN v_o IS NOT NULL THEN
              public.catalogo_despiece_fila(v_x, v_o, (v_cant->>v_pieza)::numeric, v_e.color, v_ambito) END;
          END IF;
          v_hechos := v_hechos || jsonb_build_object(v_id, coalesce(v_fila, '{"valor": 0}'));
        END IF;

        v_listos := v_listos || jsonb_build_object(v_id, true);
        v_progreso := true;
      EXCEPTION
        WHEN SQLSTATE 'CA002' THEN
          v_espera := v_espera || jsonb_build_object(v_quien, replace(SQLERRM, 'Falta el valor de ', ''));
        WHEN division_by_zero OR numeric_value_out_of_range OR SQLSTATE 'CA018' THEN
          v_fallos := v_fallos || jsonb_build_object(v_id, jsonb_build_object('quien', v_quien, 'motivo',
            CASE SQLSTATE
              WHEN '22012' THEN 'una cuenta divide por cero'
              WHEN '22003' THEN 'una cuenta da fuera de rango'
              ELSE SQLERRM
            END));
      END;
    END LOOP;

    EXIT WHEN NOT v_progreso;
  END LOOP;

  FOR v_x IN SELECT x FROM jsonb_array_elements(v_variables) x LOOP
    v_id := v_x->>'id';
    v_quien := v_x->>'nombre';

    -- Adentro de una pieza con cantidad 0 no se evalúa nada: la cuenta de la variable solo sirve a quien la use,
    -- que puede ser esa misma cantidad, y si falla frena a ese y no a esta.
    IF (v_cant->>(v_x->>'pieza_id'))::numeric = 0 THEN
      v_fallos := v_fallos - v_id;
      v_espera := v_espera - v_quien;
      CONTINUE;
    END IF;
    CONTINUE WHEN NOT (v_valores ? v_quien OR v_listas ? v_quien);

    v_salen := v_salen || jsonb_build_object(v_id, true);
    v_salida_variables := v_salida_variables || jsonb_strip_nulls(jsonb_build_object(
      'id', v_id, 'nombre', v_quien, 'pieza_id', v_x->>'pieza_id',
      'valor', coalesce(v_valores->v_quien, v_listas->v_quien),
      'a_produccion', (v_x->>'a_produccion')::boolean));

    v_num := (v_valores->>v_quien)::numeric;
    IF v_num < (v_x->>'minimo')::numeric OR v_num > (v_x->>'maximo')::numeric THEN
      v_txt := CASE
        WHEN v_x ? 'minimo' AND v_x ? 'maximo' THEN format('va de %s a %s',
          public.catalogo_numero_texto((v_x->>'minimo')::numeric), public.catalogo_numero_texto((v_x->>'maximo')::numeric))
        WHEN v_x ? 'minimo' THEN format('va desde %s', public.catalogo_numero_texto((v_x->>'minimo')::numeric))
        ELSE format('va hasta %s', public.catalogo_numero_texto((v_x->>'maximo')::numeric))
      END;
      v_mensajes := v_mensajes || jsonb_build_object(
        'mensaje', upper(left(v_quien, 1)) || substr(v_quien, 2) || ' ' || v_txt
          || CASE WHEN (v_x->>'es_cantidad')::boolean THEN '' ELSE ' mm' END,
        'bloquea', true,
        'variable_id', v_id);
    END IF;
  END LOOP;

  v_errores := v_e.errores || ARRAY(
    SELECT (f.value->>'quien') || ': ' || (f.value->>'motivo')
    FROM jsonb_each(v_fallos) f
    ORDER BY 1);

  FOR v_c IN
    SELECT c.variable_id, c.material_id, c.opcion_id, c.condicion_arbol, c.mensaje, c.bloquea,
           coalesce(x.pieza_id, m.pieza_id)::text AS pieza_id,
           coalesce(x.nombre, m.nombre, i.nombre) AS quien,
           coalesce(c.material_id, o.material_id)::text AS de_material
    FROM public.catalogo_condiciones c
    LEFT JOIN public.catalogo_variables x ON x.id = c.variable_id
    LEFT JOIN public.catalogo_opciones o ON o.id = c.opcion_id
    LEFT JOIN public.catalogo_materiales m ON m.id = coalesce(c.material_id, o.material_id)
    LEFT JOIN public.catalogo_insumos i ON i.id = m.insumo_id
    LEFT JOIN public.catalogo_piezas p ON p.id = coalesce(x.pieza_id, m.pieza_id)
    WHERE c.version_id = p_version AND c.activo
    ORDER BY c.variable_id IS NULL, p.orden, p.nombre, coalesce(x.orden, m.orden), c.created_at, c.id
  LOOP
    v_fila := v_hechos->v_c.de_material->'fila';
    CONTINUE WHEN CASE
      WHEN v_c.variable_id IS NOT NULL THEN NOT v_salen ? v_c.variable_id::text
      WHEN v_c.material_id IS NOT NULL THEN v_fila IS NULL
      ELSE (v_fila->>'opcion_id') IS DISTINCT FROM v_c.opcion_id::text
    END;

    v_ambito := v_global || coalesce(v_sumas->'local'->v_c.pieza_id, '{}');
    BEGIN
      IF public.catalogo_condicion_evaluar(v_c.condicion_arbol, v_ambito) THEN
        v_mensajes := v_mensajes || jsonb_strip_nulls(jsonb_build_object(
          'mensaje', v_c.mensaje, 'bloquea', v_c.bloquea, 'variable_id', v_c.variable_id,
          'material_id', v_c.material_id, 'opcion_id', v_c.opcion_id));
      END IF;
    EXCEPTION
      WHEN SQLSTATE 'CA002' THEN
        v_espera := v_espera || jsonb_build_object(v_c.quien, replace(SQLERRM, 'Falta el valor de ', ''));
      WHEN division_by_zero OR numeric_value_out_of_range THEN
        v_errores := v_errores || format('%s: una condición no se puede hacer', v_c.quien);
    END;
  END LOOP;

  -- El peso que alguien usa y espera a un material es un eslabón más; el que nadie usa no se nombra.
  SELECT v_espera || coalesce(jsonb_object_agg(d.key, d.value), '{}') INTO v_espera
  FROM jsonb_each(v_sumas->'esperan') d
  WHERE EXISTS (SELECT 1 FROM jsonb_each_text(v_espera) e WHERE e.value = d.key);

  -- Quien espera a algo que espera o que falló no agrega nada: se dice de quién viene. Si todos esperan a otro y nada
  -- falló, es un círculo.
  SELECT array_agg(format('%s: usa %s, que no existe o no se pudo calcular', e.key, e.value) ORDER BY e.key) INTO v_raices
  FROM jsonb_each_text(v_espera) e
  WHERE NOT v_espera ? e.value
    AND NOT EXISTS (SELECT 1 FROM jsonb_each(v_fallos) f WHERE f.value->>'quien' = e.value);
  v_errores := v_errores || coalesce(v_raices, '{}');

  IF cardinality(v_errores) = 0 AND v_espera <> '{}' THEN
    SELECT 'Referencia circular entre ' || string_agg(e.key, ', ' ORDER BY e.key) INTO v_txt
    FROM jsonb_each_text(v_espera) e;
    v_errores := ARRAY[v_txt];
  END IF;

  IF cardinality(v_errores) = 0 THEN
    SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', p.x->>'id', 'nombre', p.x->>'nombre', 'cantidad', v_cant->(p.x->>'id'),
      'peso', v_sumas->'datos'->('peso ' || (p.x->>'nombre')),
      'espesor', v_sumas->'datos'->('espesor ' || (p.x->>'nombre')),
      'peso_a_produccion', p.x->'peso_a_produccion', 'espesor_a_produccion', p.x->'espesor_a_produccion'
    )) ORDER BY p.i), '[]') INTO v_salida_piezas
    FROM jsonb_array_elements(v_piezas) WITH ORDINALITY p(x, i)
    WHERE (v_cant->>(p.x->>'id'))::numeric > 0;

    SELECT coalesce(jsonb_agg(v_hechos->(m.x->>'id')->'fila' ORDER BY m.i), '[]') INTO v_salida_filas
    FROM jsonb_array_elements(v_materiales) WITH ORDINALITY m(x, i)
    WHERE v_hechos->(m.x->>'id') ? 'fila';
  END IF;

  RETURN jsonb_build_object(
    'calculable', cardinality(v_errores) = 0,
    'bloqueado', jsonb_path_exists(v_mensajes, '$[*] ? (@.bloquea == true)'),
    'mensaje', CASE WHEN cardinality(v_errores) > 0 THEN 'No se puede calcular con estas medidas' END,
    'errores', to_jsonb(v_errores),
    'mensajes', v_mensajes,
    'color', v_e.color,
    'variables', v_salida_variables,
    'piezas', v_salida_piezas,
    'filas', v_salida_filas
  );
END;
$$;

-- ============================================================
-- 5. Los casos de prueba
-- ============================================================
-- Un caso no es un motor aparte: corre el mismo cálculo. Lo muestra el editor y lo lee el envío (sql/162).
CREATE OR REPLACE FUNCTION public.catalogo_casos_calcular(p_version uuid)
RETURNS TABLE (caso_id uuid, nombre text, resultado jsonb)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT c.id, c.nombre, public.catalogo_despiece(c.version_id, c.entrada)
  FROM public.catalogo_casos c
  WHERE c.version_id = p_version AND c.activo
  ORDER BY c.nombre;
$$;

-- ============================================================
-- 6. Privilegios
-- ============================================================
-- Los pasos tienen EXECUTE porque catalogo_despiece es INVOKER. Ninguno lee costos.
REVOKE EXECUTE ON FUNCTION
  public.catalogo_entrada_valida(jsonb),
  public.catalogo_despiece_entrada(uuid, jsonb),
  public.catalogo_numero_texto(numeric),
  public.catalogo_despiece_medida(jsonb, jsonb, text, text),
  public.catalogo_despiece_elegir(jsonb, jsonb, text[], jsonb),
  public.catalogo_despiece_fila(jsonb, jsonb, numeric, jsonb, jsonb),
  public.catalogo_despiece_sumas(jsonb, jsonb, jsonb, jsonb),
  public.catalogo_despiece(uuid, jsonb),
  public.catalogo_casos_calcular(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.catalogo_entrada_valida(jsonb),
  public.catalogo_despiece_entrada(uuid, jsonb),
  public.catalogo_numero_texto(numeric),
  public.catalogo_despiece_medida(jsonb, jsonb, text, text),
  public.catalogo_despiece_elegir(jsonb, jsonb, text[], jsonb),
  public.catalogo_despiece_fila(jsonb, jsonb, numeric, jsonb, jsonb),
  public.catalogo_despiece_sumas(jsonb, jsonb, jsonb, jsonb),
  public.catalogo_despiece(uuid, jsonb),
  public.catalogo_casos_calcular(uuid)
TO authenticated;
