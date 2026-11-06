-- Presupuestos, tramo 2b: cómo se ve cada opcional, lo que suma cada uno en cada ventana, el renglón aparte y los mínimos.
-- Ficha y decisiones: decisiones/presupuestos.md (→ La base). Esquema: db_schema/presupuestos.md.
-- Errores, clase PR (siguen a sql/186): PR012 el mínimo lo pone la base.

-- ============================================================
-- 1. Catálogo: los mínimos de unos ítems, con lo que aporta cada uno
-- ============================================================
-- El mismo cálculo que catalogo_precio_minimos, que ahora lo envuelve. Un ítem trae la versión y la fecha (las de un renglón
-- guardado) o, si no, el paquete, y se calcula a hoy. Sin GRANT: la fecha no la elige quien llama. `aportes` es
-- {clave del ítem: lo que aporta}, para saber de dónde sale cada mínimo.
CREATE OR REPLACE FUNCTION public.catalogo_precio_minimos_items(p_items jsonb, p_moneda moneda)
RETURNS TABLE(porcentaje_id uuid, nombre text, monto numeric, aportes jsonb)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_moneda moneda := coalesce(p_moneda, public.monedas_principal_actual());
  v_i record;
  v_m record;
  v_r jsonb;
  v_aportes jsonb := '[]';
  v_arrastre jsonb := '{}';
  v_segundos jsonb;
  v_falta numeric;
  v_p2 numeric;
  v_p3 numeric;
BEGIN
  FOR v_i IN
    SELECT x.clave, x.paquete_id, x.version_id, x.fecha, x.cantidad, x.entrada, x.opcionales
    FROM jsonb_to_recordset(p_items) AS x (clave text, paquete_id uuid, version_id uuid, fecha timestamptz, cantidad numeric,
                                           entrada jsonb, opcionales uuid[])
  LOOP
    IF (v_i.paquete_id IS NULL AND v_i.version_id IS NULL) OR coalesce(v_i.cantidad, 0) <= 0 THEN
      RAISE EXCEPTION 'Los ítems no tienen la forma esperada' USING ERRCODE = 'CA017';
    END IF;

    IF v_i.version_id IS NULL THEN
      v_r := public.catalogo_precio_venta(v_i.paquete_id, coalesce(v_i.entrada, '{}'), v_i.opcionales, v_moneda);
    ELSE
      v_r := public.catalogo_precio_calcular(v_i.version_id, coalesce(v_i.entrada, '{}'), coalesce(v_i.opcionales, '{}'),
                                             v_moneda, coalesce(v_i.fecha, now()));
    END IF;
    IF v_r->>'precio' IS NOT NULL THEN
      SELECT v_aportes || coalesce(jsonb_agg(s || jsonb_build_object(
               'item', v_i.clave, 'aporte', (s->>'monto')::numeric * v_i.cantidad)), '[]')
      INTO v_aportes
      FROM jsonb_array_elements(v_r->'servicios') s
      WHERE (s->>'aplica')::boolean;
    END IF;
  END LOOP;

  FOR v_m IN
    SELECT a.porcentaje_id, a.nombre, a.paso, max(a.minimo_convertido) AS minimo, sum(a.aporte) AS suma, array_agg(a.item) AS items
    FROM jsonb_to_recordset(v_aportes) AS a (
      item text, porcentaje_id uuid, nombre text, paso integer, minimo_por text, minimo_convertido numeric, aporte numeric)
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
      FROM jsonb_to_recordset(v_aportes) AS a (item text, porcentaje_id uuid, paso integer, porcentaje numeric)
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
    SELECT jsonb_object_agg(a.item, a.aporte) INTO aportes
    FROM jsonb_to_recordset(v_aportes) AS a (item text, porcentaje_id uuid, aporte numeric)
    WHERE a.porcentaje_id = v_m.porcentaje_id;
    IF monto > 0 THEN
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.catalogo_precio_minimos_items(jsonb, moneda) FROM PUBLIC, anon, authenticated;

-- Desde afuera, sin versión ni fecha: a hoy.
CREATE OR REPLACE FUNCTION public.catalogo_precio_minimos(p_items jsonb, p_moneda moneda DEFAULT NULL::moneda)
RETURNS TABLE(porcentaje_id uuid, nombre text, monto numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.catalogo_precio_permitido() THEN
    RAISE EXCEPTION 'Pedir el precio requiere armar presupuestos' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT m.porcentaje_id, m.nombre, m.monto
    FROM public.catalogo_precio_minimos_items((
      SELECT coalesce(jsonb_agg(jsonb_build_object('clave', t.i, 'paquete_id', t.x->'paquete_id', 'cantidad', t.x->'cantidad',
               'entrada', t.x->'entrada', 'opcionales', t.x->'opcionales') ORDER BY t.i), '[]')
      FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(x, i)), p_moneda) m;
END;
$$;

-- ============================================================
-- 2. Catálogo: el precio con lo que suma cada opcional
-- ============================================================
-- Cada línea es lo que sube el precio al agregar ese opcional, en el orden del cálculo: piezas (la requerida antes de la que la
-- requiere), después servicios por paso y nombre. Así lo que se cruza (un recargo sobre el mosquitero) queda en la línea que va
-- después, y las líneas más el precio sin opcionales dan el precio exacto. Una tanda por moneda; la primera es la del precio.
-- Si un paso no da número, no hay precio: no debería pasar, porque cada paso tiene menos que el precio entero.
CREATE OR REPLACE FUNCTION public.catalogo_precio_lineas(p_paquete uuid, p_entrada jsonb, p_opcionales uuid[], p_monedas moneda[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_r jsonb;
  v_adentro uuid[];
  v_pasos jsonb;
  v_lineas jsonb := '[]';
  v_moneda moneda;
  v_entrada jsonb;
  v_opc uuid[];
  v_antes jsonb;
  v_x jsonb;
  v_paso record;
BEGIN
  IF NOT public.catalogo_precio_permitido() THEN
    RAISE EXCEPTION 'Pedir el precio requiere armar presupuestos' USING ERRCODE = '42501';
  END IF;

  v_r := public.catalogo_precio_venta(p_paquete, p_entrada, p_opcionales, p_monedas[1]);
  IF v_r->>'precio' IS NULL THEN
    RETURN jsonb_build_object('precio', NULL::numeric, 'mensaje', v_r->'mensaje', 'mensajes', v_r->'mensajes',
                              'version_id', v_r->'version_id', 'lineas', '[]'::jsonb);
  END IF;

  SELECT e.adentro INTO v_adentro FROM public.catalogo_despiece_entrada((v_r->>'version_id')::uuid, p_entrada) e;

  WITH RECURSIVE d AS (
    SELECT p.id, p.nombre, p.orden, p.requiere_pieza_id, 0 AS nivel
    FROM public.catalogo_piezas p
    WHERE p.id = ANY (v_adentro) AND p.opcional
    UNION ALL
    SELECT d.id, d.nombre, d.orden, r.requiere_pieza_id, d.nivel + 1
    FROM d JOIN public.catalogo_piezas r ON r.id = d.requiere_pieza_id
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('pieza', x.nombre, 'nombre', x.nombre) ORDER BY x.nivel, x.orden, x.nombre), '[]')
  INTO v_pasos
  FROM (SELECT d.nombre, d.orden, max(d.nivel) AS nivel FROM d GROUP BY d.id, d.nombre, d.orden) x;

  SELECT v_pasos || coalesce(jsonb_agg(jsonb_build_object('porcentaje_id', t.s->'porcentaje_id', 'nombre', t.s->'nombre')
                                       ORDER BY t.o), '[]')
  INTO v_pasos
  FROM jsonb_array_elements(v_r->'servicios') WITH ORDINALITY AS t(s, o)
  WHERE (t.s->>'opcional')::boolean AND (t.s->>'aplica')::boolean;

  IF v_pasos = '[]' THEN
    RETURN jsonb_build_object('precio', v_r->'precio', 'mensaje', v_r->'mensaje', 'mensajes', v_r->'mensajes',
                              'version_id', v_r->'version_id', 'lineas', '[]'::jsonb);
  END IF;

  FOR v_moneda IN SELECT u.m FROM unnest(p_monedas) WITH ORDINALITY AS u(m, i) GROUP BY u.m ORDER BY min(u.i) LOOP
    -- Sin ningún opcional, y se suman de a uno; el último paso es el precio entero en esa moneda.
    v_entrada := p_entrada || jsonb_build_object('piezas', coalesce(p_entrada->'piezas', '{}') || coalesce((
      SELECT jsonb_object_agg(x->>'pieza', false) FROM jsonb_array_elements(v_pasos) x WHERE x ? 'pieza'), '{}'));
    v_opc := '{}';
    v_antes := public.catalogo_precio_venta(p_paquete, v_entrada, v_opc, v_moneda);
    FOR v_paso IN
      SELECT t.x, t.i, count(*) OVER () AS n FROM jsonb_array_elements(v_pasos) WITH ORDINALITY AS t(x, i) ORDER BY t.i
    LOOP
      IF v_paso.x ? 'pieza' THEN
        v_entrada := jsonb_set(v_entrada, ARRAY['piezas', v_paso.x->>'pieza'], 'true');
      ELSE
        v_opc := v_opc || (v_paso.x->>'porcentaje_id')::uuid;
      END IF;
      IF v_paso.i < v_paso.n THEN
        v_x := public.catalogo_precio_venta(p_paquete, v_entrada, v_opc, v_moneda);
      ELSIF v_moneda = p_monedas[1] THEN
        v_x := v_r;
      ELSE
        v_x := public.catalogo_precio_venta(p_paquete, p_entrada, p_opcionales, v_moneda);
      END IF;
      IF v_antes->>'precio' IS NULL OR v_x->>'precio' IS NULL THEN
        RETURN jsonb_build_object('precio', NULL::numeric,
          'mensaje', coalesce(v_x->>'mensaje', v_antes->>'mensaje', 'No se puede separar ' || (v_paso.x->>'nombre')),
          'mensajes', v_r->'mensajes', 'version_id', v_r->'version_id', 'lineas', '[]'::jsonb);
      END IF;
      v_lineas := v_lineas || (v_paso.x || jsonb_build_object(
        'moneda', v_moneda, 'monto', (v_x->>'precio')::numeric - (v_antes->>'precio')::numeric));
      v_antes := v_x;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('precio', v_r->'precio', 'mensaje', v_r->'mensaje', 'mensajes', v_r->'mensajes',
                            'version_id', v_r->'version_id', 'lineas', v_lineas);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.catalogo_precio_lineas(uuid, jsonb, uuid[], moneda[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogo_precio_lineas(uuid, jsonb, uuid[], moneda[]) TO authenticated;

-- ============================================================
-- 3. presupuestos_opcionales: cómo se ve cada opcional
-- ============================================================
-- Un opcional en toda la versión: la pieza por nombre (cada paquete tiene la suya), el servicio por id.
CREATE OR REPLACE FUNCTION public.presupuestos_clave(p_pieza text, p_porcentaje uuid)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT coalesce('pieza:' || lower(btrim(p_pieza)), 'servicio:' || p_porcentaje::text);
$$;

DO $$ BEGIN
  CREATE TYPE public.forma_opcional_presupuesto AS ENUM ('debajo', 'aparte');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Sin fila, el opcional va en el precio. Volver al precio es desactivar la fila.
CREATE TABLE IF NOT EXISTS public.presupuestos_opcionales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.presupuestos_versiones(id),
  pieza text CHECK (char_length(btrim(pieza)) BETWEEN 1 AND 100),
  porcentaje_id uuid REFERENCES public.catalogo_porcentajes(id),
  clave text GENERATED ALWAYS AS (public.presupuestos_clave(pieza, porcentaje_id)) STORED,
  forma public.forma_opcional_presupuesto NOT NULL,
  seccion_id uuid,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (seccion_id, version_id) REFERENCES public.presupuestos_secciones (id, version_id),
  CONSTRAINT presupuestos_opcionales_cual CHECK (num_nonnulls(pieza, porcentaje_id) = 1),
  CONSTRAINT presupuestos_opcionales_seccion CHECK ((forma = 'aparte') = (seccion_id IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_opcionales_clave ON public.presupuestos_opcionales (version_id, clave) WHERE activo;
CREATE INDEX IF NOT EXISTS presupuestos_opcionales_seccion ON public.presupuestos_opcionales (seccion_id);

ALTER TABLE public.presupuestos_opcionales ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_opcionales;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_opcionales
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP POLICY IF EXISTS presupuestos_opcionales_select ON public.presupuestos_opcionales;
CREATE POLICY presupuestos_opcionales_select ON public.presupuestos_opcionales FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.presupuestos_versiones v WHERE v.id = version_id));
DROP POLICY IF EXISTS presupuestos_opcionales_insert ON public.presupuestos_opcionales;
CREATE POLICY presupuestos_opcionales_insert ON public.presupuestos_opcionales FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = version_id AND p.activo AND public.presupuestos_arma(p.obra_id)));
DROP POLICY IF EXISTS presupuestos_opcionales_update ON public.presupuestos_opcionales;
CREATE POLICY presupuestos_opcionales_update ON public.presupuestos_opcionales FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = version_id AND p.activo AND public.presupuestos_arma(p.obra_id)));

GRANT SELECT ON public.presupuestos_opcionales TO authenticated;
GRANT INSERT (id, version_id, pieza, porcentaje_id, forma, seccion_id) ON public.presupuestos_opcionales TO authenticated;
GRANT UPDATE (forma, seccion_id, activo) ON public.presupuestos_opcionales TO authenticated;

-- Solo en un borrador activo; aparte, en una sección activa.
CREATE OR REPLACE FUNCTION public.presupuestos_opcionales_validar()
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
  IF NEW.activo AND NEW.seccion_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.presupuestos_secciones s WHERE s.id = NEW.seccion_id AND s.activo) THEN
    RAISE EXCEPTION 'La sección fue sacada' USING ERRCODE = 'PR008';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_opcionales_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_opcionales_validar ON public.presupuestos_opcionales;
CREATE TRIGGER presupuestos_opcionales_validar
  BEFORE INSERT OR UPDATE ON public.presupuestos_opcionales
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_opcionales_validar();

DROP TRIGGER IF EXISTS presupuestos_opcionales_no_reactivar ON public.presupuestos_opcionales;
CREATE TRIGGER presupuestos_opcionales_no_reactivar
  BEFORE UPDATE OF activo ON public.presupuestos_opcionales
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_no_reactivar();

-- ============================================================
-- 4. Renglones: sus líneas, y el renglón del mínimo
-- ============================================================
ALTER TYPE public.tipo_renglon_presupuesto ADD VALUE IF NOT EXISTS 'minimo';

-- `lineas`: lo que suma cada opcional elegido, [{clave, nombre, moneda, monto}], en la moneda del renglón y, si va aparte en
-- otra moneda, también en esa. `porcentaje_id`: el servicio del mínimo.
ALTER TABLE public.presupuestos_renglones
  ADD COLUMN IF NOT EXISTS lineas jsonb,
  ADD COLUMN IF NOT EXISTS porcentaje_id uuid REFERENCES public.catalogo_porcentajes(id);

-- tipo::text: el valor nuevo del enum no se usa en la misma transacción que lo crea.
ALTER TABLE public.presupuestos_renglones DROP CONSTRAINT IF EXISTS presupuestos_renglones_forma;
ALTER TABLE public.presupuestos_renglones ADD CONSTRAINT presupuestos_renglones_forma CHECK (CASE tipo::text
  WHEN 'catalogo' THEN paquete_id IS NOT NULL AND catalogo_version_id IS NOT NULL AND condiciones_en IS NOT NULL
                       AND entrada IS NOT NULL AND opcionales IS NOT NULL AND mensajes IS NOT NULL AND lineas IS NOT NULL
                       AND descripcion IS NULL AND porcentaje_id IS NULL
  WHEN 'mano' THEN descripcion IS NOT NULL AND precio IS NOT NULL AND paquete_id IS NULL AND catalogo_version_id IS NULL
                   AND condiciones_en IS NULL AND entrada IS NULL AND opcionales IS NULL AND mensajes IS NULL
                   AND mensaje IS NULL AND lineas IS NULL AND porcentaje_id IS NULL
  WHEN 'minimo' THEN porcentaje_id IS NOT NULL AND descripcion IS NOT NULL AND precio IS NOT NULL AND condiciones_en IS NOT NULL
                     AND paquete_id IS NULL AND catalogo_version_id IS NULL AND entrada IS NULL AND opcionales IS NULL
                     AND mensajes IS NULL AND mensaje IS NULL AND lineas IS NULL
  ELSE false
END);

-- Un mínimo por servicio y versión. Solo el mínimo tiene porcentaje_id.
CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_renglones_minimo ON public.presupuestos_renglones (version_id, porcentaje_id)
  WHERE activo AND porcentaje_id IS NOT NULL;

-- El mínimo lo crea el trigger de la base como quien arma: porcentaje_id se inserta, y presupuestos_renglones_validar frena al
-- que lo intenta directo.
GRANT INSERT (porcentaje_id) ON public.presupuestos_renglones TO authenticated;

-- Los mínimos de una versión desde sus renglones de Catálogo con precio, con la versión y la fecha con que se calcularon.
-- `seccion_id` es dónde arranca uno nuevo: la sección que más aporta (decisión del usuario, 2026-11-06). Quien llama elige la
-- versión y la moneda, no la fecha, y no ve lo que aporta cada ventana.
CREATE OR REPLACE FUNCTION public.presupuestos_minimos_calcular(p_version uuid, p_moneda moneda)
RETURNS TABLE(porcentaje_id uuid, nombre text, monto numeric, seccion_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = p_version AND public.presupuestos_arma(p.obra_id)) THEN
    RAISE EXCEPTION 'Calcular los mínimos requiere armar el presupuesto' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT m.porcentaje_id, m.nombre, m.monto, (
      SELECT r.seccion_id
      FROM jsonb_each_text(m.aportes) a
      JOIN public.presupuestos_renglones r ON r.id = a.key::uuid
      JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
      GROUP BY r.seccion_id, s.orden, s.nombre
      ORDER BY sum(a.value::numeric) DESC, s.orden, s.nombre
      LIMIT 1)
    FROM public.catalogo_precio_minimos_items((
      SELECT coalesce(jsonb_agg(jsonb_build_object('clave', r.id, 'version_id', r.catalogo_version_id,
               'fecha', r.condiciones_en, 'cantidad', r.cantidad, 'entrada', r.entrada, 'opcionales', r.opcionales)), '[]')
      FROM public.presupuestos_renglones r
      WHERE r.version_id = p_version AND r.activo AND r.lineas IS NOT NULL AND r.precio IS NOT NULL), p_moneda) m;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_minimos_calcular(uuid, moneda) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_minimos_calcular(uuid, moneda) TO authenticated;

-- Solo en un borrador activo, en una sección activa de la misma versión. FOR SHARE: no entra una edición mientras la versión
-- se envía.
-- De Catálogo: se calcula a hoy, con sus líneas, al crearlo, al cambiar lo cargado, cuando su sección cambia de moneda y cuando
-- a un opcional aparte le falta la línea en la moneda de su renglón aparte; lo demás no lo toca.
-- Mínimo: lo pone y lo saca la base (presupuestos_renglones_minimos); quien arma lo mueve, y uno de un opcional aparte vuelve
-- a la sección de ese renglón. Se recalcula cada vez que se toca.
CREATE OR REPLACE FUNCTION public.presupuestos_renglones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_version public.presupuestos_versiones;
  v_seccion public.presupuestos_secciones;
  v_monedas public.moneda[];
  v_p jsonb;
  v_m record;
BEGIN
  SELECT * INTO v_version FROM public.presupuestos_versiones WHERE id = NEW.version_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  IF NOT v_version.activo OR v_version.estado <> 'borrador' THEN
    RAISE EXCEPTION 'La versión no está en borrador' USING ERRCODE = 'PR005';
  END IF;

  IF NEW.tipo = 'minimo' THEN
    IF pg_trigger_depth() = 1 THEN
      IF TG_OP = 'INSERT' THEN
        RAISE EXCEPTION 'El mínimo lo pone la base' USING ERRCODE = 'PR012';
      ELSIF OLD.activo AND NOT NEW.activo THEN
        RAISE EXCEPTION 'El mínimo lo saca la base, cuando las ventanas lo superan' USING ERRCODE = 'PR012';
      END IF;
    END IF;
    NEW.seccion_id := coalesce((
      SELECT o.seccion_id FROM public.presupuestos_opcionales o
      WHERE o.version_id = NEW.version_id AND o.activo AND o.forma = 'aparte'
        AND o.clave = public.presupuestos_clave(NULL, NEW.porcentaje_id)), NEW.seccion_id);
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

  IF NEW.tipo = 'minimo' THEN
    NEW.cantidad := 1;
    IF NOT NEW.activo THEN
      NEW.precio := OLD.precio;
      RETURN NEW;
    END IF;
    -- shortcut: una vuelta por los renglones de la versión por cada mínimo; si pesa en versiones grandes, una por moneda.
    SELECT * INTO v_m FROM public.presupuestos_minimos_calcular(NEW.version_id, v_seccion.moneda) m
    WHERE m.porcentaje_id = NEW.porcentaje_id;
    NEW.moneda := v_seccion.moneda;
    NEW.precio := coalesce(v_m.monto, 0);
    NEW.condiciones_en := now();
    IF v_m.nombre IS NOT NULL THEN
      NEW.descripcion := v_m.nombre;
    ELSIF TG_OP = 'UPDATE' THEN
      NEW.descripcion := OLD.descripcion;
    END IF;
    RETURN NEW;
  END IF;

  -- De Catálogo. Las monedas de los renglones aparte que no son la de su sección: cada opcional se calcula también en esas.
  v_monedas := ARRAY[v_seccion.moneda] || ARRAY(
    SELECT DISTINCT s.moneda
    FROM public.presupuestos_opcionales o
    JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
    WHERE o.version_id = NEW.version_id AND o.activo AND o.forma = 'aparte' AND s.moneda <> v_seccion.moneda);

  IF TG_OP = 'UPDATE' THEN
    IF NOT (NEW.activo AND (
         (NEW.paquete_id, NEW.entrada, NEW.opcionales) IS DISTINCT FROM (OLD.paquete_id, OLD.entrada, OLD.opcionales)
         OR v_seccion.moneda <> OLD.moneda
         OR EXISTS (
           SELECT 1
           FROM public.presupuestos_opcionales o
           JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
           WHERE o.version_id = NEW.version_id AND o.activo AND o.forma = 'aparte'
             AND OLD.lineas @> jsonb_build_array(jsonb_build_object('clave', o.clave))
             AND NOT OLD.lineas @> jsonb_build_array(jsonb_build_object('clave', o.clave, 'moneda', s.moneda))))) THEN
      NEW.precio := OLD.precio;
      RETURN NEW;
    END IF;
  END IF;

  NEW.entrada := coalesce(NEW.entrada, '{}');
  NEW.opcionales := coalesce(NEW.opcionales, '{}');
  v_p := public.catalogo_precio_lineas(NEW.paquete_id, NEW.entrada, NEW.opcionales, v_monedas);
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
  NEW.lineas := (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'clave', public.presupuestos_clave(t.l->>'pieza', (t.l->>'porcentaje_id')::uuid),
             'nombre', t.l->'nombre', 'moneda', t.l->'moneda', 'monto', t.l->'monto') ORDER BY t.i), '[]')
    FROM jsonb_array_elements(v_p->'lineas') WITH ORDINALITY AS t(l, i));
  RETURN NEW;
END;
$$;

-- Después de cada cambio en renglones de Catálogo, los mínimos de su versión: el que hace falta se toca (y el trigger de arriba
-- lo recalcula) o se crea en la sección que más aporta; el que ya no, se saca. Así la próxima vez vuelve a arrancar por la regla.
CREATE OR REPLACE FUNCTION public.presupuestos_renglones_minimos()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_version uuid;
  v_m record;
  v_hacen_falta uuid[];
BEGIN
  FOR v_version IN SELECT DISTINCT n.version_id FROM nuevos n WHERE n.lineas IS NOT NULL LOOP
    v_hacen_falta := '{}';
    FOR v_m IN SELECT * FROM public.presupuestos_minimos_calcular(v_version, public.monedas_principal_actual()) LOOP
      v_hacen_falta := v_hacen_falta || v_m.porcentaje_id;
      UPDATE public.presupuestos_renglones r SET seccion_id = r.seccion_id
      WHERE r.version_id = v_version AND r.activo AND r.porcentaje_id = v_m.porcentaje_id;
      IF NOT FOUND THEN
        INSERT INTO public.presupuestos_renglones (version_id, seccion_id, tipo, porcentaje_id, descripcion)
        VALUES (v_version, v_m.seccion_id, 'minimo', v_m.porcentaje_id, v_m.nombre);
      END IF;
    END LOOP;
    UPDATE public.presupuestos_renglones r SET activo = false
    WHERE r.version_id = v_version AND r.activo AND r.porcentaje_id IS NOT NULL AND NOT r.porcentaje_id = ANY (v_hacen_falta);
  END LOOP;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_renglones_minimos() FROM PUBLIC, anon, authenticated;

-- Una tabla de transición pide un trigger por evento.
DROP TRIGGER IF EXISTS presupuestos_renglones_minimos_alta ON public.presupuestos_renglones;
CREATE TRIGGER presupuestos_renglones_minimos_alta
  AFTER INSERT ON public.presupuestos_renglones
  REFERENCING NEW TABLE AS nuevos
  FOR EACH STATEMENT EXECUTE FUNCTION public.presupuestos_renglones_minimos();
DROP TRIGGER IF EXISTS presupuestos_renglones_minimos_cambio ON public.presupuestos_renglones;
CREATE TRIGGER presupuestos_renglones_minimos_cambio
  AFTER UPDATE ON public.presupuestos_renglones
  REFERENCING NEW TABLE AS nuevos
  FOR EACH STATEMENT EXECUTE FUNCTION public.presupuestos_renglones_minimos();

-- Cambiar cómo se ve un opcional toca las ventanas que lo tienen (el trigger de renglones decide si les falta una moneda) y su
-- mínimo (que sigue al renglón aparte).
CREATE OR REPLACE FUNCTION public.presupuestos_opcionales_renglones()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.presupuestos_renglones r SET seccion_id = r.seccion_id
  WHERE r.version_id = NEW.version_id AND r.activo
    AND (r.lineas @> jsonb_build_array(jsonb_build_object('clave', NEW.clave)) OR r.porcentaje_id = NEW.porcentaje_id);
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_opcionales_renglones() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_opcionales_renglones ON public.presupuestos_opcionales;
CREATE TRIGGER presupuestos_opcionales_renglones
  AFTER INSERT OR UPDATE ON public.presupuestos_opcionales
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_opcionales_renglones();

-- ============================================================
-- 5. Secciones: la de un renglón aparte tampoco se saca, y cambiar la moneda alcanza a las ventanas con opcionales ahí
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
     AND (EXISTS (SELECT 1 FROM public.presupuestos_renglones r WHERE r.seccion_id = OLD.id AND r.activo)
          OR EXISTS (SELECT 1 FROM public.presupuestos_opcionales o WHERE o.seccion_id = OLD.id AND o.activo)) THEN
    RAISE EXCEPTION 'La sección "%" tiene renglones: se mueven o se sacan antes', OLD.nombre USING ERRCODE = 'PR011';
  END IF;
  RETURN NEW;
END;
$$;

-- Los de la sección, y los de Catálogo de la versión por si tienen un opcional aparte acá: el trigger de renglones recalcula
-- los que lo necesitan. Uno a mano en la sección frena el cambio.
CREATE OR REPLACE FUNCTION public.presupuestos_secciones_moneda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.presupuestos_renglones SET seccion_id = seccion_id
  WHERE version_id = NEW.version_id AND activo AND (seccion_id = NEW.id OR lineas IS NOT NULL);
  RETURN NULL;
END;
$$;

-- ============================================================
-- 6. Lo que se cobra en cada sección, y los totales
-- ============================================================
-- Una fila por importe que ve el cliente: cada renglón (clave NULL) sin sus opcionales aparte, y cada opcional aparte de cada
-- ventana en la sección y la moneda de su renglón aparte. El renglón aparte es la suma de estas por clave. NULL: sin precio.
-- Cada producto se redondea por renglón, como el precio.
CREATE OR REPLACE FUNCTION public.presupuestos_version_importes(p_version uuid)
RETURNS TABLE(renglon_id uuid, seccion_id uuid, moneda public.moneda, alicuota numeric, clave text, nombre text, importe numeric)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH r AS (
    SELECT r.id, r.seccion_id, r.moneda, r.cantidad, r.precio, r.lineas, s.alicuota
    FROM public.presupuestos_renglones r
    JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
    WHERE r.version_id = p_version AND r.activo
  ),
  ap AS (
    SELECT r.id, r.cantidad, o.clave, s.id AS seccion_id, s.moneda, s.alicuota,
           (SELECT (l->>'monto')::numeric FROM jsonb_array_elements(r.lineas) l
            WHERE l->>'clave' = o.clave AND l->>'moneda' = r.moneda::text) AS propio,
           (SELECT l FROM jsonb_array_elements(r.lineas) l
            WHERE l->>'clave' = o.clave AND l->>'moneda' = s.moneda::text) AS linea
    FROM r
    JOIN public.presupuestos_opcionales o ON o.version_id = p_version AND o.activo AND o.forma = 'aparte'
    JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
    WHERE r.precio IS NOT NULL AND r.lineas @> jsonb_build_array(jsonb_build_object('clave', o.clave))
  )
  SELECT r.id, r.seccion_id, r.moneda, r.alicuota, NULL::text, NULL::text,
         public.catalogo_precio_redondear(
           (r.precio - coalesce((SELECT sum(ap.propio) FROM ap WHERE ap.id = r.id), 0)) * r.cantidad, r.moneda)
  FROM r
  UNION ALL
  SELECT ap.id, ap.seccion_id, ap.moneda, ap.alicuota, ap.clave, ap.linea->>'nombre',
         public.catalogo_precio_redondear((ap.linea->>'monto')::numeric * ap.cantidad, ap.moneda)
  FROM ap;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) TO authenticated;

-- El descuento se aplica a cada alícuota, y el IVA va después. Lo sin precio no suma: se cuenta aparte.
CREATE OR REPLACE FUNCTION public.presupuestos_version_totales(p_version uuid)
RETURNS TABLE(moneda public.moneda, subtotal numeric, descuento numeric, iva jsonb, total numeric, sin_precio integer)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH a AS (
    SELECT i.moneda, i.alicuota, coalesce(sum(i.importe), 0) AS base, count(*) FILTER (WHERE i.importe IS NULL) AS sin_precio
    FROM public.presupuestos_version_importes(p_version) i
    GROUP BY i.moneda, i.alicuota
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
