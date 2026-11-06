-- Presupuestos, tramo 2a: los renglones de Catálogo y a mano, con su precio, el descuento y los totales.
-- Ficha y decisiones: decisiones/presupuestos.md (→ La base). Esquema: db_schema/presupuestos.md.
-- Sigue el 2b: cómo se ve cada opcional, sus montos por ventana, el renglón aparte y los mínimos.
-- Errores, clase PR (siguen a sql/185): PR008 la sección fue sacada · PR009 un renglón a mano no cambia de moneda ·
-- PR010 el paquete no está a la venta · PR011 la sección tiene renglones.

-- ============================================================
-- 1. Catálogo: el precio lo pide quien arma presupuestos
-- ============================================================
-- Una sola regla para el precio, el formulario y los mínimos. Administrar ve y hace todo.
CREATE OR REPLACE FUNCTION public.catalogo_precio_permitido()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.tiene_permiso('presupuestos_armar') OR public.tiene_permiso('presupuestos_administrar');
$$;

REVOKE EXECUTE ON FUNCTION public.catalogo_precio_permitido() FROM PUBLIC, anon, authenticated;

-- Redondear no lee nada: los totales del presupuesto redondean igual que el precio.
GRANT EXECUTE ON FUNCTION public.catalogo_precio_redondear(numeric, public.moneda) TO authenticated;

-- Lo que se vende hoy, ahora con la versión con que se calculó: el renglón la guarda.
CREATE OR REPLACE FUNCTION public.catalogo_precio_venta(p_paquete uuid, p_entrada jsonb, p_opcionales uuid[], p_moneda moneda)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_version uuid;
  v_r jsonb;
  v_o record;
  v_fuera text;
BEGIN
  SELECT v.id INTO v_version
  FROM public.catalogo_versiones v
  JOIN public.catalogo_paquetes q ON q.id = v.paquete_id
  WHERE q.id = p_paquete AND q.activo AND v.estado = 'publicado';

  IF v_version IS NULL THEN
    RETURN jsonb_build_object('precio', NULL::numeric, 'mensaje', 'Este paquete no está a la venta', 'mensajes', '[]'::jsonb);
  END IF;

  v_r := public.catalogo_precio_calcular(v_version, p_entrada, p_opcionales, p_moneda, now())
    || jsonb_build_object('version_id', v_version);
  IF v_r->>'precio' IS NULL THEN
    RETURN v_r;
  END IF;

  SELECT o.armable, o.piezas_fuera, o.opciones_fuera INTO v_o
  FROM public.catalogo_oferta(v_version) o
  WHERE o.color_id IS NOT DISTINCT FROM (v_r->'color'->>'id')::uuid;

  IF NOT FOUND OR NOT v_o.armable THEN
    RETURN v_r || jsonb_build_object('precio', NULL::numeric, 'mensaje', 'Este paquete no se ofrece en este color');
  END IF;

  SELECT string_agg(DISTINCT CASE
           WHEN (f->>'pieza_id')::uuid = ANY (v_o.piezas_fuera) THEN f->>'pieza' ELSE f->>'insumo' END, ', ')
  INTO v_fuera
  FROM jsonb_array_elements(v_r->'filas') f
  WHERE (f->>'pieza_id')::uuid = ANY (v_o.piezas_fuera) OR (f->>'opcion_id')::uuid = ANY (v_o.opciones_fuera);

  IF v_fuera IS NOT NULL THEN
    RETURN v_r || jsonb_build_object('precio', NULL::numeric, 'mensaje', 'Ya no se ofrece: ' || v_fuera);
  END IF;

  RETURN v_r;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_precio(p_paquete uuid, p_entrada jsonb DEFAULT '{}'::jsonb,
                                                  p_opcionales uuid[] DEFAULT '{}'::uuid[], p_moneda moneda DEFAULT NULL::moneda)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_r jsonb;
BEGIN
  IF NOT public.catalogo_precio_permitido() THEN
    RAISE EXCEPTION 'Pedir el precio requiere armar presupuestos' USING ERRCODE = '42501';
  END IF;
  v_r := public.catalogo_precio_venta(p_paquete, p_entrada, p_opcionales, p_moneda);
  RETURN jsonb_build_object('precio', v_r->'precio', 'mensaje', v_r->'mensaje', 'mensajes', v_r->'mensajes',
                            'version_id', v_r->'version_id');
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_precio_minimos(p_items jsonb, p_moneda moneda DEFAULT NULL::moneda)
RETURNS TABLE(porcentaje_id uuid, nombre text, monto numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_moneda moneda := coalesce(p_moneda, public.monedas_principal_actual());
  v_i record;
  v_m record;
  v_r jsonb;
  v_item integer := 0;
  v_aportes jsonb := '[]';
  v_arrastre jsonb := '{}';
  v_segundos jsonb;
  v_falta numeric;
  v_p2 numeric;
  v_p3 numeric;
BEGIN
  IF NOT public.catalogo_precio_permitido() THEN
    RAISE EXCEPTION 'Pedir el precio requiere armar presupuestos' USING ERRCODE = '42501';
  END IF;

  FOR v_i IN
    SELECT x.paquete_id, x.cantidad, x.entrada, x.opcionales
    FROM jsonb_to_recordset(p_items) AS x (paquete_id uuid, cantidad numeric, entrada jsonb, opcionales uuid[])
  LOOP
    IF v_i.paquete_id IS NULL OR coalesce(v_i.cantidad, 0) <= 0 THEN
      RAISE EXCEPTION 'Los ítems no tienen la forma esperada' USING ERRCODE = 'CA017';
    END IF;

    v_r := public.catalogo_precio_venta(v_i.paquete_id, coalesce(v_i.entrada, '{}'), v_i.opcionales, v_moneda);
    IF v_r->>'precio' IS NOT NULL THEN
      v_item := v_item + 1;
      SELECT v_aportes || coalesce(jsonb_agg(s || jsonb_build_object(
               'item', v_item, 'aporte', (s->>'monto')::numeric * v_i.cantidad)), '[]')
      INTO v_aportes
      FROM jsonb_array_elements(v_r->'servicios') s
      WHERE (s->>'aplica')::boolean;
    END IF;
  END LOOP;

  FOR v_m IN
    SELECT a.porcentaje_id, a.nombre, a.paso, max(a.minimo_convertido) AS minimo, sum(a.aporte) AS suma, array_agg(a.item) AS items
    FROM jsonb_to_recordset(v_aportes) AS a (
      item integer, porcentaje_id uuid, nombre text, paso integer, minimo_por text, minimo_convertido numeric, aporte numeric)
    WHERE a.minimo_por = 'presupuesto'
    GROUP BY a.porcentaje_id, a.nombre, a.paso
    ORDER BY a.paso, a.nombre
  LOOP
    v_falta := v_m.minimo - v_m.suma - coalesce((v_arrastre->>v_m.porcentaje_id::text)::numeric, 0);
    CONTINUE WHEN v_falta <= 0;

    SELECT coalesce(sum(s.porcentaje) FILTER (WHERE s.paso = 2), 0),
           coalesce(sum(s.porcentaje) FILTER (WHERE s.paso = 3), 0),
           coalesce(jsonb_object_agg(s.porcentaje_id, s.porcentaje) FILTER (WHERE s.paso = 2), '{}')
    INTO v_p2, v_p3, v_segundos
    FROM (
      SELECT a.porcentaje_id, a.paso, max(a.porcentaje) AS porcentaje
      FROM jsonb_to_recordset(v_aportes) AS a (item integer, porcentaje_id uuid, paso integer, porcentaje numeric)
      WHERE a.item = ANY (v_m.items) AND a.paso > v_m.paso
      GROUP BY a.porcentaje_id, a.paso
      HAVING count(*) = cardinality(v_m.items)
    ) s;

    SELECT v_arrastre || coalesce(jsonb_object_agg(
             e.key, coalesce((v_arrastre->>e.key)::numeric, 0) + v_falta * e.value::numeric / 100), '{}')
    INTO v_arrastre
    FROM jsonb_each_text(v_segundos) e;

    porcentaje_id := v_m.porcentaje_id;
    nombre := v_m.nombre;
    monto := public.catalogo_precio_redondear(v_falta * (1 + v_p2 / 100) / (1 - v_p3 / 100), v_moneda);
    IF monto > 0 THEN
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

-- ============================================================
-- 2. Catálogo: los paquetes a la venta y el formulario de cada uno
-- ============================================================
-- Un paquete activo con publicada se arma en algún color: la baja en cascada lo saca si deja de armarse.
CREATE OR REPLACE FUNCTION public.catalogo_venta()
RETURNS TABLE(paquete_id uuid, nombre text, categoria_id uuid, categoria text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.catalogo_precio_permitido() THEN
    RAISE EXCEPTION 'Ver los paquetes a la venta requiere armar presupuestos' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT q.id, v.nombre, c.id, c.nombre
    FROM public.catalogo_paquetes q
    JOIN public.catalogo_versiones v ON v.paquete_id = q.id AND v.estado = 'publicado'
    JOIN public.catalogo_categorias c ON c.id = v.categoria_id
    WHERE q.activo
    ORDER BY c.nombre, v.nombre;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.catalogo_venta() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogo_venta() TO authenticated;

-- Qué preguntar, con los predeterminados ya calculados (el despiece sin entrada) y qué se ofrece en cada color.
-- Las claves son las del contenido de la versión, para armar la entrada igual que la calculadora. NULL si no está a la venta.
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
               'id', p.id, 'nombre', p.nombre, 'opcional', true, 'incluida', p.incluida,
               'requiere_pieza_id', p.requiere_pieza_id, 'secundario', p.secundario) ORDER BY p.orden, p.nombre), '[]')
      FROM public.catalogo_piezas p
      WHERE p.version_id = v_version AND p.activo AND p.opcional),
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

REVOKE EXECUTE ON FUNCTION public.catalogo_venta_formulario(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogo_venta_formulario(uuid) TO authenticated;

-- ============================================================
-- 3. El descuento de la versión
-- ============================================================
ALTER TABLE public.presupuestos_versiones
  ADD COLUMN IF NOT EXISTS descuento numeric(5,2) NOT NULL DEFAULT 0 CHECK (descuento >= 0 AND descuento <= 100);

GRANT INSERT (descuento) ON public.presupuestos_versiones TO authenticated;
GRANT UPDATE (descuento) ON public.presupuestos_versiones TO authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_versiones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_presupuesto public.presupuestos;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO v_presupuesto FROM public.presupuestos WHERE id = NEW.presupuesto_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se encontró el presupuesto' USING ERRCODE = '42501';
    END IF;
    IF NOT v_presupuesto.activo OR v_presupuesto.estado NOT IN ('borrador', 'publicado') THEN
      RAISE EXCEPTION 'El presupuesto % no admite versiones: está %', v_presupuesto.codigo,
        CASE WHEN NOT v_presupuesto.activo THEN 'desactivado' ELSE v_presupuesto.estado::text END
        USING ERRCODE = 'PR003';
    END IF;
    SELECT coalesce(max(v.numero), 0) + 1 INTO NEW.numero
    FROM public.presupuestos_versiones v WHERE v.presupuesto_id = NEW.presupuesto_id;
    IF NEW.variante > (SELECT coalesce(max(v.variante), 0) + 1
                       FROM public.presupuestos_versiones v WHERE v.presupuesto_id = NEW.presupuesto_id) THEN
      RAISE EXCEPTION 'La variante % no sigue a las que tiene el presupuesto', NEW.variante USING ERRCODE = 'PR004';
    END IF;
    RETURN NEW;
  END IF;

  IF (NEW.variante_nombre, NEW.iva_discriminado, NEW.descuento)
       IS DISTINCT FROM (OLD.variante_nombre, OLD.iva_discriminado, OLD.descuento)
     AND OLD.estado <> 'borrador' THEN
    RAISE EXCEPTION 'La versión no está en borrador' USING ERRCODE = 'PR005';
  END IF;

  IF OLD.activo AND NOT NEW.activo THEN
    IF OLD.estado <> 'borrador' THEN
      RAISE EXCEPTION 'Solo se descarta un borrador' USING ERRCODE = 'PR005';
    END IF;
    PERFORM 1 FROM public.presupuestos WHERE id = OLD.presupuesto_id FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM public.presupuestos_versiones v
                   WHERE v.presupuesto_id = OLD.presupuesto_id AND v.activo AND v.id <> OLD.id) THEN
      RAISE EXCEPTION 'Es la única versión del presupuesto: se desactiva el presupuesto' USING ERRCODE = 'PR006';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 4. presupuestos_renglones
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.tipo_renglon_presupuesto AS ENUM ('catalogo', 'mano');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- El renglón apunta a una sección de su misma versión.
CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_secciones_id_version ON public.presupuestos_secciones (id, version_id);

-- `moneda` es la del precio escrito: la pone el trigger con la de la sección, y si la sección cambia, el de Catálogo se
-- recalcula y el a mano no se deja.
CREATE TABLE IF NOT EXISTS public.presupuestos_renglones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.presupuestos_versiones(id),
  seccion_id uuid NOT NULL,
  tipo public.tipo_renglon_presupuesto NOT NULL,
  designacion text CHECK (char_length(btrim(designacion)) BETWEEN 1 AND 30),
  ubicacion text CHECK (char_length(btrim(ubicacion)) BETWEEN 1 AND 100),
  cantidad numeric NOT NULL DEFAULT 1 CHECK (cantidad > 0),
  orden integer NOT NULL DEFAULT 0,
  paquete_id uuid REFERENCES public.catalogo_paquetes(id),
  catalogo_version_id uuid REFERENCES public.catalogo_versiones(id),
  condiciones_en timestamptz,
  entrada jsonb,
  opcionales uuid[],
  mensajes jsonb,
  descripcion text CHECK (char_length(btrim(descripcion)) BETWEEN 1 AND 500),
  moneda public.moneda NOT NULL,
  precio numeric CHECK (precio >= 0),
  mensaje text,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (seccion_id, version_id) REFERENCES public.presupuestos_secciones (id, version_id),
  CONSTRAINT presupuestos_renglones_forma CHECK (CASE tipo
    WHEN 'catalogo' THEN paquete_id IS NOT NULL AND catalogo_version_id IS NOT NULL AND condiciones_en IS NOT NULL
                         AND entrada IS NOT NULL AND opcionales IS NOT NULL AND mensajes IS NOT NULL AND descripcion IS NULL
    WHEN 'mano' THEN descripcion IS NOT NULL AND precio IS NOT NULL AND paquete_id IS NULL AND catalogo_version_id IS NULL
                     AND condiciones_en IS NULL AND entrada IS NULL AND opcionales IS NULL AND mensajes IS NULL
                     AND mensaje IS NULL
  END)
);

CREATE INDEX IF NOT EXISTS presupuestos_renglones_version ON public.presupuestos_renglones (version_id);
CREATE INDEX IF NOT EXISTS presupuestos_renglones_seccion ON public.presupuestos_renglones (seccion_id);

ALTER TABLE public.presupuestos_renglones ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_renglones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_renglones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP POLICY IF EXISTS presupuestos_renglones_select ON public.presupuestos_renglones;
CREATE POLICY presupuestos_renglones_select ON public.presupuestos_renglones FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.presupuestos_versiones v WHERE v.id = version_id));
DROP POLICY IF EXISTS presupuestos_renglones_insert ON public.presupuestos_renglones;
CREATE POLICY presupuestos_renglones_insert ON public.presupuestos_renglones FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = version_id AND p.activo AND public.presupuestos_arma(p.obra_id)));
DROP POLICY IF EXISTS presupuestos_renglones_update ON public.presupuestos_renglones;
CREATE POLICY presupuestos_renglones_update ON public.presupuestos_renglones FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = version_id AND p.activo AND public.presupuestos_arma(p.obra_id)));

-- El precio se escribe solo en uno a mano: en uno de Catálogo lo pone el trigger.
GRANT SELECT ON public.presupuestos_renglones TO authenticated;
GRANT INSERT (id, version_id, seccion_id, tipo, designacion, ubicacion, cantidad, orden, paquete_id, entrada, opcionales,
              descripcion, precio) ON public.presupuestos_renglones TO authenticated;
GRANT UPDATE (seccion_id, designacion, ubicacion, cantidad, orden, paquete_id, entrada, opcionales, descripcion, precio,
              activo) ON public.presupuestos_renglones TO authenticated;

-- Solo en un borrador activo, en una sección activa de la misma versión. El de Catálogo se calcula a hoy al crearlo, al
-- cambiar lo cargado y al cambiar la moneda de su sección; lo demás no lo toca. FOR SHARE: no entra una edición mientras
-- la versión se envía.
CREATE OR REPLACE FUNCTION public.presupuestos_renglones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_version public.presupuestos_versiones;
  v_seccion public.presupuestos_secciones;
  v_p jsonb;
BEGIN
  SELECT * INTO v_version FROM public.presupuestos_versiones WHERE id = NEW.version_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  IF NOT v_version.activo OR v_version.estado <> 'borrador' THEN
    RAISE EXCEPTION 'La versión no está en borrador' USING ERRCODE = 'PR005';
  END IF;

  SELECT * INTO v_seccion FROM public.presupuestos_secciones WHERE id = NEW.seccion_id AND version_id = NEW.version_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sección no es de esta versión' USING ERRCODE = '23503';
  END IF;
  IF NOT v_seccion.activo AND NEW.activo THEN
    RAISE EXCEPTION 'La sección "%" fue sacada', v_seccion.nombre USING ERRCODE = 'PR008';
  END IF;

  IF NEW.tipo = 'mano' THEN
    IF TG_OP = 'INSERT' THEN
      NEW.moneda := v_seccion.moneda;
    ELSIF NEW.activo AND v_seccion.moneda <> OLD.moneda THEN
      RAISE EXCEPTION 'Un renglón a mano no cambia de moneda: "%" está en %', OLD.descripcion, OLD.moneda
        USING ERRCODE = 'PR009';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NOT (NEW.activo AND (
         (NEW.paquete_id, NEW.entrada, NEW.opcionales) IS DISTINCT FROM (OLD.paquete_id, OLD.entrada, OLD.opcionales)
         OR v_seccion.moneda <> OLD.moneda)) THEN
      NEW.precio := OLD.precio;
      RETURN NEW;
    END IF;
  END IF;

  NEW.entrada := coalesce(NEW.entrada, '{}');
  NEW.opcionales := coalesce(NEW.opcionales, '{}');
  v_p := public.catalogo_precio(NEW.paquete_id, NEW.entrada, NEW.opcionales, v_seccion.moneda);
  -- Uno que ya estaba sigue con su versión y queda sin precio, con el porqué.
  IF v_p->>'version_id' IS NULL THEN
    IF TG_OP = 'INSERT' THEN
      RAISE EXCEPTION 'El paquete no está a la venta' USING ERRCODE = 'PR010';
    ELSIF NEW.paquete_id <> OLD.paquete_id THEN
      RAISE EXCEPTION 'El paquete no está a la venta' USING ERRCODE = 'PR010';
    END IF;
  ELSE
    NEW.catalogo_version_id := (v_p->>'version_id')::uuid;
  END IF;
  NEW.condiciones_en := now();
  NEW.moneda := v_seccion.moneda;
  NEW.precio := (v_p->>'precio')::numeric;
  NEW.mensaje := v_p->>'mensaje';
  NEW.mensajes := coalesce(v_p->'mensajes', '[]');
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_renglones_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_renglones_validar ON public.presupuestos_renglones;
CREATE TRIGGER presupuestos_renglones_validar
  BEFORE INSERT OR UPDATE ON public.presupuestos_renglones
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_renglones_validar();

DROP TRIGGER IF EXISTS presupuestos_renglones_no_reactivar ON public.presupuestos_renglones;
CREATE TRIGGER presupuestos_renglones_no_reactivar
  BEFORE UPDATE OF activo ON public.presupuestos_renglones
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_no_reactivar();

-- ============================================================
-- 5. Secciones: no se sacan con renglones, y cambiar la moneda recalcula
-- ============================================================
CREATE OR REPLACE FUNCTION public.presupuestos_secciones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_version public.presupuestos_versiones;
BEGIN
  SELECT * INTO v_version FROM public.presupuestos_versiones WHERE id = NEW.version_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  IF NOT v_version.activo OR v_version.estado <> 'borrador' THEN
    RAISE EXCEPTION 'La versión no está en borrador' USING ERRCODE = 'PR005';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.activo AND NOT NEW.activo
     AND EXISTS (SELECT 1 FROM public.presupuestos_renglones r WHERE r.seccion_id = OLD.id AND r.activo) THEN
    RAISE EXCEPTION 'La sección "%" tiene renglones: se mueven o se sacan antes', OLD.nombre USING ERRCODE = 'PR011';
  END IF;
  RETURN NEW;
END;
$$;

-- Tocar los renglones los recalcula en la moneda nueva (presupuestos_renglones_validar); uno a mano frena el cambio.
CREATE OR REPLACE FUNCTION public.presupuestos_secciones_moneda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.presupuestos_renglones SET seccion_id = seccion_id WHERE seccion_id = NEW.id AND activo;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_secciones_moneda() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_secciones_moneda ON public.presupuestos_secciones;
CREATE TRIGGER presupuestos_secciones_moneda
  AFTER UPDATE OF moneda ON public.presupuestos_secciones
  FOR EACH ROW WHEN (NEW.moneda IS DISTINCT FROM OLD.moneda)
  EXECUTE FUNCTION public.presupuestos_secciones_moneda();

-- ============================================================
-- 6. Totales por moneda: subtotal, descuento, IVA por alícuota y total
-- ============================================================
-- El descuento se aplica a cada alícuota, y el IVA va después. Lo sin precio no suma: se cuenta aparte.
CREATE OR REPLACE FUNCTION public.presupuestos_version_totales(p_version uuid)
RETURNS TABLE(moneda public.moneda, subtotal numeric, descuento numeric, iva jsonb, total numeric, sin_precio integer)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH a AS (
    SELECT r.moneda, s.alicuota,
           coalesce(sum(public.catalogo_precio_redondear(r.precio * r.cantidad, r.moneda)), 0) AS base,
           count(*) FILTER (WHERE r.precio IS NULL) AS sin_precio
    FROM public.presupuestos_renglones r
    JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
    WHERE r.version_id = p_version AND r.activo
    GROUP BY r.moneda, s.alicuota
  ),
  b AS (
    SELECT a.*, public.catalogo_precio_redondear(a.base * v.descuento / 100, a.moneda) AS rebaja
    FROM a JOIN public.presupuestos_versiones v ON v.id = p_version
  ),
  c AS (
    SELECT b.*, public.catalogo_precio_redondear((b.base - b.rebaja) * b.alicuota / 100, b.moneda) AS impuesto FROM b
  )
  SELECT c.moneda, sum(c.base), sum(c.rebaja),
         jsonb_agg(jsonb_build_object('alicuota', c.alicuota, 'monto', c.impuesto) ORDER BY c.alicuota DESC),
         sum(c.base - c.rebaja + c.impuesto), sum(c.sin_precio)::integer
  FROM c
  GROUP BY c.moneda
  ORDER BY c.moneda;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_totales(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_totales(uuid) TO authenticated;
