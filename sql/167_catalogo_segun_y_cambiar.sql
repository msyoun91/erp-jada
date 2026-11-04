-- Catálogo: la variable según un material que se elige, y el vendedor puede cambiar lo que sigue a otro. Van juntas porque se tocan:
-- una variable también puede depender de un material que sigue a otro, y entonces depende de lo que se eligió a mano.
-- Decisiones: decisiones/catalogo/paquete.md. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_segun.sql.
--
-- Las funciones de abajo son las de sql/160, 161 y 162 con estos cambios; el resto de cada una sigue igual.

-- ============================================================
-- 1. Lo secundario también vale en lo que sigue a otro
-- ============================================================
ALTER TABLE public.catalogo_materiales DROP CONSTRAINT IF EXISTS catalogo_materiales_tipo;
ALTER TABLE public.catalogo_materiales ADD CONSTRAINT catalogo_materiales_tipo CHECK (
  (nombre IS NULL) = (tipo = 'unico')
  AND (tipo = 'unico' OR insumo_id IS NULL)
  AND (tipo = 'elige_sistema' OR eleccion IS NULL)
  AND (tipo = 'sigue' OR sigue_material_id IS NULL)
  AND (tipo = 'elige_vendedor' OR NOT sin_eleccion)
  AND (tipo IN ('elige_vendedor', 'sigue') OR NOT secundario));

-- ============================================================
-- 2. La variable según un material
-- ============================================================
ALTER TABLE public.catalogo_variables ADD COLUMN IF NOT EXISTS segun_material_id uuid;

ALTER TABLE public.catalogo_variables DROP CONSTRAINT IF EXISTS catalogo_variables_segun_fk;
ALTER TABLE public.catalogo_variables ADD CONSTRAINT catalogo_variables_segun_fk
  FOREIGN KEY (segun_material_id, version_id) REFERENCES public.catalogo_materiales (id, version_id);

ALTER TABLE public.catalogo_variables DROP CONSTRAINT IF EXISTS catalogo_variables_calculada;
ALTER TABLE public.catalogo_variables ADD CONSTRAINT catalogo_variables_calculada CHECK (ingresa_vendedor OR (
  (formula IS NOT NULL OR segun_material_id IS NOT NULL)
  AND NOT es_lista AND NOT es_cantidad AND minimo IS NULL AND maximo IS NULL AND NOT secundario));

ALTER TABLE public.catalogo_variables DROP CONSTRAINT IF EXISTS catalogo_variables_segun;
ALTER TABLE public.catalogo_variables ADD CONSTRAINT catalogo_variables_segun CHECK (
  segun_material_id IS NULL OR (NOT ingresa_vendedor AND formula IS NULL));

CREATE INDEX IF NOT EXISTS catalogo_variables_segun_material
  ON public.catalogo_variables (segun_material_id);

-- Un valor por opción: número o fórmula. Se apunta a la fila de la opción, como una condición. Lo que quede de otro material,
-- después de cambiar segun_material_id, no se mira: el cálculo y el envío solo leen las opciones del material actual.
CREATE TABLE IF NOT EXISTS public.catalogo_variables_valores (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id   uuid NOT NULL REFERENCES public.catalogo_versiones(id),
  variable_id  uuid NOT NULL,
  opcion_id    uuid NOT NULL,
  formula      text NOT NULL,
  formula_arbol jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(formula)) STORED,
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (variable_id, version_id) REFERENCES public.catalogo_variables (id, version_id),
  FOREIGN KEY (opcion_id, version_id) REFERENCES public.catalogo_opciones (id, version_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS catalogo_variables_valores_unico
  ON public.catalogo_variables_valores (variable_id, opcion_id) WHERE activo;
CREATE INDEX IF NOT EXISTS catalogo_variables_valores_version
  ON public.catalogo_variables_valores (version_id);
CREATE INDEX IF NOT EXISTS catalogo_variables_valores_opcion
  ON public.catalogo_variables_valores (opcion_id);

ALTER TABLE public.catalogo_variables_valores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalogo_variables_valores_select ON public.catalogo_variables_valores;
CREATE POLICY catalogo_variables_valores_select ON public.catalogo_variables_valores
  FOR SELECT TO authenticated USING ((SELECT public.tiene_permiso('catalogo_paquetes')));
DROP POLICY IF EXISTS catalogo_variables_valores_insert ON public.catalogo_variables_valores;
CREATE POLICY catalogo_variables_valores_insert ON public.catalogo_variables_valores
  FOR INSERT TO authenticated WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')));
DROP POLICY IF EXISTS catalogo_variables_valores_update ON public.catalogo_variables_valores;
CREATE POLICY catalogo_variables_valores_update ON public.catalogo_variables_valores
  FOR UPDATE TO authenticated
  USING ((SELECT public.tiene_permiso('catalogo_armar')))
  WITH CHECK ((SELECT public.tiene_permiso('catalogo_armar')));

CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON public.catalogo_variables_valores
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE OR REPLACE TRIGGER catalogo_contenido_validar BEFORE INSERT OR UPDATE ON public.catalogo_variables_valores
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_contenido_validar();

GRANT SELECT, INSERT ON public.catalogo_variables_valores TO authenticated;
GRANT UPDATE (formula, activo) ON public.catalogo_variables_valores TO authenticated;
GRANT UPDATE (segun_material_id) ON public.catalogo_variables TO authenticated;

-- ============================================================
-- 3. Sacar y copiar
-- ============================================================
-- Sacar un material saca las variables según él: sin él no tienen de dónde sacar un valor.
CREATE OR REPLACE FUNCTION public.catalogo_contenido_baja()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  CASE TG_TABLE_NAME
    WHEN 'catalogo_piezas' THEN
      UPDATE public.catalogo_variables SET activo = false WHERE pieza_id = NEW.id AND activo;
      UPDATE public.catalogo_materiales SET activo = false WHERE pieza_id = NEW.id AND activo;
      UPDATE public.catalogo_piezas SET requiere_pieza_id = NULL WHERE requiere_pieza_id = NEW.id;
    WHEN 'catalogo_variables' THEN
      UPDATE public.catalogo_condiciones SET activo = false WHERE variable_id = NEW.id AND activo;
      UPDATE public.catalogo_variables_valores SET activo = false WHERE variable_id = NEW.id AND activo;
    WHEN 'catalogo_materiales' THEN
      UPDATE public.catalogo_opciones SET activo = false WHERE material_id = NEW.id AND activo;
      UPDATE public.catalogo_condiciones SET activo = false WHERE material_id = NEW.id AND activo;
      UPDATE public.catalogo_materiales SET sigue_material_id = NULL WHERE sigue_material_id = NEW.id;
      UPDATE public.catalogo_variables SET activo = false WHERE segun_material_id = NEW.id AND activo;
    WHEN 'catalogo_opciones' THEN
      UPDATE public.catalogo_opciones SET activo = false WHERE sigue_opcion_id = NEW.id AND activo;
      UPDATE public.catalogo_condiciones SET activo = false WHERE opcion_id = NEW.id AND activo;
      UPDATE public.catalogo_variables_valores SET activo = false WHERE opcion_id = NEW.id AND activo;
  END CASE;
  RETURN NULL;
END;
$$;

-- Las variables van después de los materiales, porque ahora apuntan a uno.
CREATE OR REPLACE FUNCTION public.catalogo_version_copiar(p_origen uuid, p_paquete uuid, p_nombre text)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_destino uuid;
  v_piezas jsonb;
  v_variables jsonb;
  v_materiales jsonb;
  v_opciones jsonb;
BEGIN
  INSERT INTO public.catalogo_versiones (paquete_id, nombre, categoria_id)
  SELECT p_paquete, p_nombre, o.categoria_id FROM public.catalogo_versiones o WHERE o.id = p_origen
  RETURNING id INTO v_destino;
  IF v_destino IS NULL THEN
    RAISE EXCEPTION 'No se encontró la versión de la que se copia' USING ERRCODE = 'CA014';
  END IF;

  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_piezas
  FROM public.catalogo_piezas x WHERE x.version_id = p_origen AND x.activo;
  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_variables
  FROM public.catalogo_variables x WHERE x.version_id = p_origen AND x.activo;
  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_materiales
  FROM public.catalogo_materiales x WHERE x.version_id = p_origen AND x.activo;
  SELECT coalesce(jsonb_object_agg(x.id, gen_random_uuid()), '{}') INTO v_opciones
  FROM public.catalogo_opciones x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_versiones_colores (version_id, color_id, base)
  SELECT v_destino, x.color_id, x.base
  FROM public.catalogo_versiones_colores x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_piezas (id, version_id, nombre, orden, cantidad, opcional, incluida,
    requiere_pieza_id, secundario, calcula_espesor, peso_a_produccion, espesor_a_produccion)
  SELECT (v_piezas ->> x.id::text)::uuid, v_destino, x.nombre, x.orden, x.cantidad, x.opcional, x.incluida,
    (v_piezas ->> x.requiere_pieza_id::text)::uuid, x.secundario, x.calcula_espesor, x.peso_a_produccion,
    x.espesor_a_produccion
  FROM public.catalogo_piezas x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_materiales (id, version_id, pieza_id, orden, tipo, nombre, insumo_id, medida, ancho,
    alto, area, cantidad, eleccion, sin_eleccion, sigue_material_id, secundario, cuenta_peso, cuenta_espesor)
  SELECT (v_materiales ->> x.id::text)::uuid, v_destino, (v_piezas ->> x.pieza_id::text)::uuid, x.orden, x.tipo,
    x.nombre, x.insumo_id, x.medida, x.ancho, x.alto, x.area, x.cantidad, x.eleccion, x.sin_eleccion,
    (v_materiales ->> x.sigue_material_id::text)::uuid, x.secundario, x.cuenta_peso, x.cuenta_espesor
  FROM public.catalogo_materiales x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_variables (id, version_id, pieza_id, nombre, orden, ingresa_vendedor, es_lista,
    formula, valores, valor_predeterminado, es_cantidad, minimo, maximo, secundario, a_produccion, segun_material_id)
  SELECT (v_variables ->> x.id::text)::uuid, v_destino, (v_piezas ->> x.pieza_id::text)::uuid, x.nombre, x.orden,
    x.ingresa_vendedor, x.es_lista, x.formula, x.valores, x.valor_predeterminado, x.es_cantidad, x.minimo,
    x.maximo, x.secundario, x.a_produccion, (v_materiales ->> x.segun_material_id::text)::uuid
  FROM public.catalogo_variables x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_opciones (id, version_id, material_id, orden, insumo_id, sigue_opcion_id,
    predeterminada, medida, ancho, alto, area, cantidad)
  SELECT (v_opciones ->> x.id::text)::uuid, v_destino, (v_materiales ->> x.material_id::text)::uuid, x.orden,
    x.insumo_id, (v_opciones ->> x.sigue_opcion_id::text)::uuid, x.predeterminada, x.medida, x.ancho, x.alto,
    x.area, x.cantidad
  FROM public.catalogo_opciones x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_variables_valores (version_id, variable_id, opcion_id, formula)
  SELECT v_destino, (v_variables ->> x.variable_id::text)::uuid, (v_opciones ->> x.opcion_id::text)::uuid, x.formula
  FROM public.catalogo_variables_valores x
  JOIN public.catalogo_variables va ON va.id = x.variable_id
  JOIN public.catalogo_opciones o ON o.id = x.opcion_id AND o.material_id = va.segun_material_id
  WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_condiciones (version_id, variable_id, material_id, opcion_id, condicion, mensaje, bloquea)
  SELECT v_destino, (v_variables ->> x.variable_id::text)::uuid, (v_materiales ->> x.material_id::text)::uuid,
    (v_opciones ->> x.opcion_id::text)::uuid, x.condicion, x.mensaje, x.bloquea
  FROM public.catalogo_condiciones x WHERE x.version_id = p_origen AND x.activo;

  INSERT INTO public.catalogo_casos (version_id, nombre, entrada)
  SELECT v_destino, x.nombre, x.entrada
  FROM public.catalogo_casos x WHERE x.version_id = p_origen AND x.activo;

  RETURN v_destino;
END;
$$;

-- ============================================================
-- 4. El cálculo
-- ============================================================
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
      WHERE x.version_id = p_version AND x.activo AND x.tipo IN ('elige_vendedor', 'sigue')
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
    WHERE x.version_id = p_version AND x.activo AND x.tipo IN ('elige_vendedor', 'elige_sistema', 'sigue')
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

    -- Lo que sigue a otro solo entra acá si se eligió a mano: sin clave, vuelve a la pareja. null es "ninguna".
    IF v_m.tipo = 'sigue' THEN
      IF v_valor IS NOT NULL THEN
        SELECT o.id INTO v_opcion FROM public.catalogo_opciones o
        WHERE o.material_id = v_m.id AND o.activo AND o.insumo_id::text IS NOT DISTINCT FROM v_valor #>> '{}'
        ORDER BY o.orden, o.created_at, o.id
        LIMIT 1;
        IF v_opcion IS NULL THEN
          errores := errores || format('%s: esa opción ya no existe', v_m.nombre);
        ELSE
          elegidas := elegidas || jsonb_build_object(v_m.id, v_opcion);
        END IF;
      END IF;
      CONTINUE;
    END IF;

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

CREATE OR REPLACE FUNCTION public.catalogo_despiece_elegir(p_m jsonb, p_elegidas jsonb, p_faltan text[], p_v jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_elegida text;
  v_o jsonb;
  v_mano jsonb;
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
      -- A mano: si es el mismo insumo que la pareja de lo elegido, vale esa fila, con sus fórmulas. Da lo mismo que no tocarlo.
      IF p_elegidas ? (p_m->>'id') THEN
        SELECT o INTO v_mano FROM jsonb_array_elements(p_m->'opciones') o WHERE o->>'id' = p_elegidas->>(p_m->>'id');
        SELECT o INTO v_o FROM jsonb_array_elements(p_m->'opciones') o
        WHERE o->>'sigue_opcion' = v_elegida AND o->'insumo'->>'id' IS NOT DISTINCT FROM v_mano->'insumo'->>'id';
        v_o := coalesce(v_o, v_mano);
        RETURN CASE WHEN v_o ? 'insumo' THEN v_o END;
      END IF;
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

-- Qué fórmula le toca a una variable según un material: la de la opción elegida. Esperar la elección es esperar un valor, y
-- un material que no está o que falta elegir ya da su propio error: por eso CA002.
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
    RAISE EXCEPTION '% no tiene una opción elegida', v_nombre USING ERRCODE = 'CA018';
  END IF;
  IF NOT coalesce(p_x->'segun_valores', '{}') ? v_opcion THEN
    RAISE EXCEPTION 'falta el valor de la opción elegida en %', v_nombre USING ERRCODE = 'CA018';
  END IF;
  RETURN p_x->'segun_valores'->v_opcion;
END;
$$;

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
    'a_produccion', x.a_produccion, 'segun_material_id', x.segun_material_id,
    'segun_nombre', coalesce(sm.nombre, si.nombre),
    'segun_valores', (
      SELECT jsonb_object_agg(vv.opcion_id, vv.formula_arbol)
      FROM public.catalogo_variables_valores vv
      WHERE vv.variable_id = x.id AND vv.activo)
  )) ORDER BY x.pieza_id IS NOT NULL, p.orden, p.nombre, x.orden, x.created_at, x.id), '[]') INTO v_variables
  FROM public.catalogo_variables x
  LEFT JOIN public.catalogo_piezas p ON p.id = x.pieza_id
  LEFT JOIN public.catalogo_materiales sm ON sm.id = x.segun_material_id
  LEFT JOIN public.catalogo_insumos si ON si.id = sm.insumo_id
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
            ELSIF v_x ? 'segun_material_id' THEN
              v_num := public.catalogo_formula_evaluar(
                public.catalogo_despiece_segun(v_x, v_materiales, v_elegidas, v_e.faltan, v_ambito), v_ambito);
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
-- 5. La oferta y lo que frena el envío
-- ============================================================
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

    -- Una opción sale si no está su insumo o la pareja de alguno de los que la siguen. "ninguna" siempre está. En lo que sigue
    -- a otro también sale la fila sin su insumo: el vendedor la puede elegir a mano.
    SELECT coalesce(array_agg(o.id), '{}') INTO v_opciones
    FROM public.catalogo_opciones o
    JOIN public.catalogo_materiales m ON m.id = o.material_id
    WHERE o.version_id = p_version AND o.activo AND o.insumo_id IS NOT NULL
      AND m.activo
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
  SELECT 'v:' || x.id, x.nombre, x.pieza_id, vv.formula_arbol
  FROM public.catalogo_variables x
  JOIN public.catalogo_opciones o ON o.material_id = x.segun_material_id AND o.activo
  JOIN public.catalogo_variables_valores vv ON vv.variable_id = x.id AND vv.opcion_id = o.id AND vv.activo
  WHERE x.version_id = p_version AND x.activo
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

-- Una variable según un material también lo usa: lo revisa como a un nombre, y para lo circular espera lo que elige.
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
      WHEN m.puede_faltar OR NOT EXISTS (
        SELECT 1 FROM alcance a WHERE a.desde IS NOT DISTINCT FROM x.pieza_id AND a.llega = m.pieza_id)
        THEN format('%s: depende de %s, que puede no estar', x.nombre, m.nombre)
    END,
    ARRAY['c:' || m.id]
  FROM public.catalogo_variables x
  JOIN materiales m ON m.id = x.segun_material_id
  WHERE x.version_id = p_version AND x.activo;
$$;

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

  -- Una suelta igual a una pareja saldría dos veces en la lista, con fórmulas que pueden ser distintas.
  v_out := v_out || ARRAY(
    SELECT DISTINCT format('%s: %s ya es la pareja de otra opción', m.nombre, i.nombre)
    FROM public.catalogo_opciones o
    JOIN public.catalogo_materiales m ON m.id = o.material_id
    JOIN public.catalogo_insumos i ON i.id = o.insumo_id
    WHERE o.version_id = p_version AND o.activo AND o.sigue_opcion_id IS NULL AND m.activo AND m.tipo = 'sigue'
      AND EXISTS (
        SELECT 1 FROM public.catalogo_opciones r
        WHERE r.material_id = m.id AND r.activo AND r.sigue_opcion_id IS NOT NULL AND r.insumo_id = o.insumo_id)
    ORDER BY 1);

  v_out := v_out || ARRAY(
    SELECT format('%s: falta el valor de %s', x.nombre, i.nombre)
    FROM public.catalogo_variables x
    JOIN public.catalogo_opciones o ON o.material_id = x.segun_material_id AND o.activo
    JOIN public.catalogo_insumos i ON i.id = o.insumo_id
    WHERE x.version_id = p_version AND x.activo
      AND NOT EXISTS (
        SELECT 1 FROM public.catalogo_variables_valores vv
        WHERE vv.variable_id = x.id AND vv.opcion_id = o.id AND vv.activo)
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
    WHERE m.version_id = p_version AND m.activo AND m.tipo = 'elige_vendedor' AND m.secundario AND NOT m.sin_eleccion
      AND NOT EXISTS (
        SELECT 1 FROM public.catalogo_opciones o WHERE o.material_id = m.id AND o.activo AND o.predeterminada)
    ORDER BY 1);
  -- Lo que sigue a otro se pliega si hay algo propuesto: una predeterminada en el que elige, o la regla del sistema.
  v_out := v_out || ARRAY(
    SELECT format('%s: es secundario y %s no tiene predeterminada', m.nombre, l.nombre)
    FROM public.catalogo_materiales m
    JOIN public.catalogo_materiales l ON l.id = m.sigue_material_id
    WHERE m.version_id = p_version AND m.activo AND m.tipo = 'sigue' AND m.secundario AND l.tipo = 'elige_vendedor'
      AND NOT EXISTS (
        SELECT 1 FROM public.catalogo_opciones o WHERE o.material_id = l.id AND o.activo AND o.predeterminada)
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
-- 6. Privilegios
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.catalogo_despiece_segun(jsonb, jsonb, jsonb, text[], jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogo_despiece_segun(jsonb, jsonb, jsonb, text[], jsonb) TO authenticated;
