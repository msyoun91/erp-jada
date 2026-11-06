-- Presupuestos, tramo 3a: la versión nueva (corregir, actualizar o sumar variante) copia la anterior, cada ventana y cada mínimo
-- se mantienen o se actualizan, y publicar, con lo que lo frena, el vencimiento y la anterior a obsoleto; quitar una variante.
-- Sigue el 3b: pedir, autorizar, devolver y retirar, y la lectura de Técnica. Hasta entonces, lo que pide autorización frena.
-- Ficha y decisiones: decisiones/presupuestos.md (→ Precio, La base). Esquema: db_schema/presupuestos.md.
-- Errores, clase PR (siguen a sql/187): PR013 solo se mantiene lo copiado, con su paquete · PR014 algo frena publicar ·
-- PR015 solo se quita una variante publicada · PR016 la última variante no se quita.

-- ============================================================
-- 1. Catálogo: el precio a una versión y una fecha
-- ============================================================
-- Sin versión, lo que se vende hoy; con versión, como era a esa fecha (mantener). Sin GRANT: la fecha no la elige quien llama.
CREATE OR REPLACE FUNCTION public.catalogo_precio_en(p_paquete uuid, p_version uuid, p_fecha timestamptz, p_entrada jsonb,
                                                     p_opcionales uuid[], p_moneda moneda)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE WHEN p_version IS NULL THEN public.catalogo_precio_venta(p_paquete, p_entrada, p_opcionales, p_moneda)
    ELSE public.catalogo_precio_calcular(p_version, p_entrada, p_opcionales, p_moneda, p_fecha)
         || jsonb_build_object('version_id', p_version) END;
$$;

REVOKE EXECUTE ON FUNCTION public.catalogo_precio_en(uuid, uuid, timestamptz, jsonb, uuid[], moneda) FROM PUBLIC, anon, authenticated;

-- El cálculo de catalogo_precio_lineas (sql/187), a una versión y una fecha. Sin GRANT.
CREATE OR REPLACE FUNCTION public.catalogo_precio_lineas_en(p_paquete uuid, p_version uuid, p_fecha timestamptz, p_entrada jsonb,
                                                            p_opcionales uuid[], p_monedas moneda[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
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
  v_r := public.catalogo_precio_en(p_paquete, p_version, p_fecha, p_entrada, p_opcionales, p_monedas[1]);
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
    v_antes := public.catalogo_precio_en(p_paquete, p_version, p_fecha, v_entrada, v_opc, v_moneda);
    FOR v_paso IN
      SELECT t.x, t.i, count(*) OVER () AS n FROM jsonb_array_elements(v_pasos) WITH ORDINALITY AS t(x, i) ORDER BY t.i
    LOOP
      IF v_paso.x ? 'pieza' THEN
        v_entrada := jsonb_set(v_entrada, ARRAY['piezas', v_paso.x->>'pieza'], 'true');
      ELSE
        v_opc := v_opc || (v_paso.x->>'porcentaje_id')::uuid;
      END IF;
      IF v_paso.i < v_paso.n THEN
        v_x := public.catalogo_precio_en(p_paquete, p_version, p_fecha, v_entrada, v_opc, v_moneda);
      ELSIF v_moneda = p_monedas[1] THEN
        v_x := v_r;
      ELSE
        v_x := public.catalogo_precio_en(p_paquete, p_version, p_fecha, p_entrada, p_opcionales, v_moneda);
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

REVOKE EXECUTE ON FUNCTION public.catalogo_precio_lineas_en(uuid, uuid, timestamptz, jsonb, uuid[], moneda[])
  FROM PUBLIC, anon, authenticated;

-- Desde afuera, a hoy.
CREATE OR REPLACE FUNCTION public.catalogo_precio_lineas(p_paquete uuid, p_entrada jsonb, p_opcionales uuid[], p_monedas moneda[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.catalogo_precio_permitido() THEN
    RAISE EXCEPTION 'Pedir el precio requiere armar presupuestos' USING ERRCODE = '42501';
  END IF;
  RETURN public.catalogo_precio_lineas_en(p_paquete, NULL, NULL, p_entrada, p_opcionales, p_monedas);
END;
$$;

-- ============================================================
-- 2. Catálogo: el mínimo a su fecha
-- ============================================================
-- El umbral de cada mínimo es el valor del servicio a una fecha: la de `p_fechas` ({porcentaje_id: fecha}, la de un mínimo
-- mantenido) o hoy. Lo que aporta cada ítem sigue a la versión y la fecha del ítem. Antes era el mayor de los umbrales de los
-- ítems, cada uno a su fecha: con ventanas mantenidas y a hoy mezcladas, el mínimo no era ni el de antes ni el de hoy.
DROP FUNCTION IF EXISTS public.catalogo_precio_minimos_items(jsonb, moneda);
CREATE FUNCTION public.catalogo_precio_minimos_items(p_items jsonb, p_moneda moneda, p_fechas jsonb DEFAULT '{}')
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
  v_en timestamptz;
  v_minimo numeric;
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
    SELECT a.porcentaje_id, a.nombre, a.paso, sum(a.aporte) AS suma, array_agg(a.item) AS items
    FROM jsonb_to_recordset(v_aportes) AS a (
      item text, porcentaje_id uuid, nombre text, paso integer, minimo_por text, aporte numeric)
    WHERE a.minimo_por = 'presupuesto'
    GROUP BY a.porcentaje_id, a.nombre, a.paso
    ORDER BY a.paso, a.nombre
  LOOP
    v_en := coalesce((p_fechas->>v_m.porcentaje_id::text)::timestamptz, now());
    v_minimo := NULL;
    SELECT public.catalogo_precio_convertir(x.minimo, x.minimo_moneda, v_moneda, v_en) INTO v_minimo
    FROM public.catalogo_porcentajes_vigentes(v_en) x
    WHERE x.porcentaje_id = v_m.porcentaje_id AND NOT x.de_baja AND x.minimo_por = 'presupuesto';
    v_falta := v_minimo - v_m.suma - coalesce((v_arrastre->>v_m.porcentaje_id::text)::numeric, 0);
    CONTINUE WHEN v_falta IS NULL OR v_falta <= 0;

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

REVOKE EXECUTE ON FUNCTION public.catalogo_precio_minimos_items(jsonb, moneda, jsonb) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 3. De dónde se copió, mantener y el vencimiento
-- ============================================================
-- `origen_id`: la versión, o el renglón, del que se copió. Mantener es recalcular con la versión de Catálogo y la fecha del
-- renglón de origen: solo hay dos valores, hoy o los de la versión anterior. `vence` lo pone publicar.
ALTER TABLE public.presupuestos_versiones
  ADD COLUMN IF NOT EXISTS origen_id uuid REFERENCES public.presupuestos_versiones(id),
  ADD COLUMN IF NOT EXISTS vence date;

ALTER TABLE public.presupuestos_renglones
  ADD COLUMN IF NOT EXISTS origen_id uuid REFERENCES public.presupuestos_renglones(id),
  ADD COLUMN IF NOT EXISTS mantener boolean NOT NULL DEFAULT false;

ALTER TABLE public.presupuestos_renglones DROP CONSTRAINT IF EXISTS presupuestos_renglones_mantener;
ALTER TABLE public.presupuestos_renglones ADD CONSTRAINT presupuestos_renglones_mantener
  CHECK (NOT mantener OR (origen_id IS NOT NULL AND tipo::text <> 'mano'));

GRANT INSERT (origen_id) ON public.presupuestos_versiones TO authenticated;
GRANT INSERT (origen_id, mantener) ON public.presupuestos_renglones TO authenticated;
GRANT UPDATE (mantener) ON public.presupuestos_renglones TO authenticated;

-- Al crear, el origen es otra versión activa del mismo presupuesto.
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
    IF NEW.origen_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM public.presupuestos_versiones o
         WHERE o.id = NEW.origen_id AND o.presupuesto_id = NEW.presupuesto_id AND o.activo) THEN
      RAISE EXCEPTION 'La versión de origen no es de este presupuesto' USING ERRCODE = '23503';
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
-- 4. El precio de un renglón: a hoy o mantenido
-- ============================================================
-- Las monedas en que se calcula un renglón de Catálogo: la de su sección, y las de los renglones aparte en otra moneda.
CREATE OR REPLACE FUNCTION public.presupuestos_renglon_monedas(p_version uuid, p_moneda moneda)
RETURNS moneda[]
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT ARRAY[p_moneda] || ARRAY(
    SELECT DISTINCT s.moneda
    FROM public.presupuestos_opcionales o
    JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
    WHERE o.version_id = p_version AND o.activo AND o.forma = 'aparte' AND s.moneda <> p_moneda
    ORDER BY s.moneda);
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_renglon_monedas(uuid, moneda) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_renglon_monedas(uuid, moneda) TO authenticated;

-- Cómo se nombra un renglón en lo que frena publicar: "V4 · Lavadero".
CREATE OR REPLACE FUNCTION public.presupuestos_renglon_etiqueta(p_designacion text, p_ubicacion text, p_descripcion text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT coalesce(p_designacion, p_descripcion, 'Sin designación') || coalesce(' · ' || p_ubicacion, '');
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_renglon_etiqueta(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_renglon_etiqueta(text, text, text) TO authenticated;

-- El precio y las líneas de una ventana, listos para guardar: a hoy, o con la versión y la fecha de `p_origen` (mantener).
-- La fecha la pone el renglón de origen, de la versión de la que se copió esta y con el mismo paquete: quien llama no la elige.
CREATE OR REPLACE FUNCTION public.presupuestos_precio_lineas(p_version uuid, p_origen uuid, p_paquete uuid, p_entrada jsonb,
                                                             p_opcionales uuid[], p_monedas moneda[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_o public.presupuestos_renglones;
  v_p jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = p_version AND public.presupuestos_arma(p.obra_id)) THEN
    RAISE EXCEPTION 'Calcular el precio requiere armar el presupuesto' USING ERRCODE = '42501';
  END IF;
  IF p_origen IS NOT NULL THEN
    SELECT o.* INTO v_o
    FROM public.presupuestos_renglones o
    JOIN public.presupuestos_versiones v ON v.origen_id = o.version_id
    WHERE o.id = p_origen AND v.id = p_version AND o.tipo = 'catalogo' AND o.paquete_id = p_paquete;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Solo se mantiene una ventana copiada de la versión anterior, con su mismo paquete' USING ERRCODE = 'PR013';
    END IF;
  END IF;

  v_p := public.catalogo_precio_lineas_en(p_paquete, v_o.catalogo_version_id, v_o.condiciones_en,
                                          coalesce(p_entrada, '{}'), coalesce(p_opcionales, '{}'), p_monedas);
  RETURN v_p || jsonb_build_object('condiciones_en', coalesce(v_o.condiciones_en, now()), 'lineas', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'clave', public.presupuestos_clave(t.l->>'pieza', (t.l->>'porcentaje_id')::uuid),
             'nombre', t.l->'nombre', 'moneda', t.l->'moneda', 'monto', t.l->'monto') ORDER BY t.i), '[]')
    FROM jsonb_array_elements(v_p->'lineas') WITH ORDINALITY AS t(l, i)));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_precio_lineas(uuid, uuid, uuid, jsonb, uuid[], moneda[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_precio_lineas(uuid, uuid, uuid, jsonb, uuid[], moneda[]) TO authenticated;

-- Los mínimos de la versión. Uno mantenido toma el umbral a la fecha del mínimo de origen (el de la versión de la que se
-- copió, con el mismo servicio). `p_mantener`: los servicios mantenidos; NULL, los guardados. Quien llama elige cuáles se
-- mantienen, no la fecha.
DROP FUNCTION IF EXISTS public.presupuestos_minimos_calcular(uuid, moneda);
CREATE FUNCTION public.presupuestos_minimos_calcular(p_version uuid, p_moneda moneda, p_mantener uuid[] DEFAULT NULL)
RETURNS TABLE(porcentaje_id uuid, nombre text, monto numeric, seccion_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fechas jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE v.id = p_version AND public.presupuestos_arma(p.obra_id)) THEN
    RAISE EXCEPTION 'Calcular los mínimos requiere armar el presupuesto' USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(jsonb_object_agg(o.porcentaje_id, o.condiciones_en), '{}') INTO v_fechas
  FROM public.presupuestos_versiones v
  JOIN public.presupuestos_renglones o ON o.version_id = v.origen_id AND o.activo AND o.porcentaje_id IS NOT NULL
  WHERE v.id = p_version AND o.porcentaje_id = ANY (coalesce(p_mantener, ARRAY(
    SELECT r.porcentaje_id FROM public.presupuestos_renglones r
    WHERE r.version_id = p_version AND r.activo AND r.mantener AND r.porcentaje_id IS NOT NULL)));

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
      WHERE r.version_id = p_version AND r.activo AND r.lineas IS NOT NULL AND r.precio IS NOT NULL), p_moneda, v_fechas) m;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_minimos_calcular(uuid, moneda, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_minimos_calcular(uuid, moneda, uuid[]) TO authenticated;

-- Como en sql/187, más: un renglón copiado tiene su origen en la versión de la que se copió esta; mantener recalcula con la
-- versión y la fecha del origen, y se recalcula también al escribir `mantener` (presupuestos_renglones_a_hoy). Uno copiado
-- cuyo paquete ya no está a la venta entra sin precio, con la versión de su origen. Un mínimo nuevo toma su origen por
-- servicio y arranca en la sección de igual nombre que la de su origen: quien lo había movido no lo pierde al corregir.
CREATE OR REPLACE FUNCTION public.presupuestos_renglones_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_version public.presupuestos_versiones;
  v_seccion public.presupuestos_secciones;
  v_origen public.presupuestos_renglones;
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

  IF NEW.mantener AND (NEW.origen_id IS NULL OR NEW.tipo = 'mano') THEN
    RAISE EXCEPTION 'Solo se mantiene una ventana o un mínimo copiados de la versión anterior' USING ERRCODE = 'PR013';
  END IF;

  IF NEW.tipo = 'minimo' THEN
    IF pg_trigger_depth() = 1 THEN
      IF TG_OP = 'INSERT' THEN
        RAISE EXCEPTION 'El mínimo lo pone la base' USING ERRCODE = 'PR012';
      ELSIF OLD.activo AND NOT NEW.activo THEN
        RAISE EXCEPTION 'El mínimo lo saca la base, cuando las ventanas lo superan' USING ERRCODE = 'PR012';
      END IF;
    END IF;
    IF TG_OP = 'INSERT' THEN
      SELECT o.* INTO v_origen FROM public.presupuestos_renglones o
      WHERE o.version_id = v_version.origen_id AND o.activo AND o.porcentaje_id = NEW.porcentaje_id;
      NEW.origen_id := v_origen.id;
      NEW.seccion_id := coalesce((
        SELECT s.id
        FROM public.presupuestos_secciones so
        JOIN public.presupuestos_secciones s ON lower(btrim(s.nombre)) = lower(btrim(so.nombre))
        WHERE so.id = v_origen.seccion_id AND s.version_id = NEW.version_id AND s.activo), NEW.seccion_id);
    ELSIF NEW.mantener THEN
      SELECT * INTO v_origen FROM public.presupuestos_renglones WHERE id = NEW.origen_id;
    END IF;
    NEW.seccion_id := coalesce((
      SELECT o.seccion_id FROM public.presupuestos_opcionales o
      WHERE o.version_id = NEW.version_id AND o.activo AND o.forma = 'aparte'
        AND o.clave = public.presupuestos_clave(NULL, NEW.porcentaje_id)), NEW.seccion_id);
  ELSIF NEW.origen_id IS NOT NULL THEN
    SELECT * INTO v_origen FROM public.presupuestos_renglones WHERE id = NEW.origen_id;
    IF TG_OP = 'INSERT' AND (NOT FOUND OR v_origen.version_id IS DISTINCT FROM v_version.origen_id
                             OR v_origen.tipo <> NEW.tipo) THEN
      RAISE EXCEPTION 'El renglón de origen no es de la versión copiada' USING ERRCODE = '23503';
    END IF;
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
      NEW.condiciones_en := OLD.condiciones_en;
      RETURN NEW;
    END IF;
    -- shortcut: una vuelta por los renglones de la versión por cada mínimo; si pesa en versiones grandes, una por moneda.
    SELECT * INTO v_m
    FROM public.presupuestos_minimos_calcular(NEW.version_id, v_seccion.moneda, ARRAY(
           SELECT r.porcentaje_id FROM public.presupuestos_renglones r
           WHERE r.version_id = NEW.version_id AND r.activo AND r.mantener AND r.porcentaje_id <> NEW.porcentaje_id)
         || CASE WHEN NEW.mantener THEN ARRAY[NEW.porcentaje_id] ELSE '{}'::uuid[] END) m
    WHERE m.porcentaje_id = NEW.porcentaje_id;
    NEW.moneda := v_seccion.moneda;
    NEW.precio := coalesce(v_m.monto, 0);
    NEW.condiciones_en := CASE WHEN NEW.mantener THEN v_origen.condiciones_en ELSE now() END;
    IF v_m.nombre IS NOT NULL THEN
      NEW.descripcion := v_m.nombre;
    ELSIF TG_OP = 'UPDATE' THEN
      NEW.descripcion := OLD.descripcion;
    END IF;
    RETURN NEW;
  END IF;

  -- De Catálogo. `condiciones_en` NULL: se escribió `mantener` (presupuestos_renglones_a_hoy).
  IF TG_OP = 'UPDATE' THEN
    IF NOT (NEW.activo AND (
         NEW.condiciones_en IS NULL
         OR NEW.mantener <> OLD.mantener
         OR (NEW.paquete_id, NEW.entrada, NEW.opcionales) IS DISTINCT FROM (OLD.paquete_id, OLD.entrada, OLD.opcionales)
         OR v_seccion.moneda <> OLD.moneda
         OR EXISTS (
           SELECT 1
           FROM public.presupuestos_opcionales o
           JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
           WHERE o.version_id = NEW.version_id AND o.activo AND o.forma = 'aparte'
             AND OLD.lineas @> jsonb_build_array(jsonb_build_object('clave', o.clave))
             AND NOT OLD.lineas @> jsonb_build_array(jsonb_build_object('clave', o.clave, 'moneda', s.moneda))))) THEN
      NEW.precio := OLD.precio;
      NEW.condiciones_en := OLD.condiciones_en;
      RETURN NEW;
    END IF;
  END IF;

  NEW.entrada := coalesce(NEW.entrada, '{}');
  NEW.opcionales := coalesce(NEW.opcionales, '{}');
  v_p := public.presupuestos_precio_lineas(NEW.version_id, CASE WHEN NEW.mantener THEN NEW.origen_id END, NEW.paquete_id,
                                           NEW.entrada, NEW.opcionales,
                                           public.presupuestos_renglon_monedas(NEW.version_id, v_seccion.moneda));
  -- Uno que ya estaba, o copiado con su paquete, sigue con su versión y queda sin precio, con el porqué.
  IF v_p->>'version_id' IS NULL THEN
    IF (TG_OP = 'INSERT' AND v_origen.paquete_id IS DISTINCT FROM NEW.paquete_id)
       OR (TG_OP = 'UPDATE' AND NEW.paquete_id <> OLD.paquete_id) THEN
      RAISE EXCEPTION 'El paquete no está a la venta' USING ERRCODE = 'PR010';
    END IF;
    IF TG_OP = 'INSERT' THEN
      NEW.catalogo_version_id := v_origen.catalogo_version_id;
    END IF;
  ELSE
    NEW.catalogo_version_id := (v_p->>'version_id')::uuid;
  END IF;
  NEW.condiciones_en := (v_p->>'condiciones_en')::timestamptz;
  NEW.moneda := v_seccion.moneda;
  NEW.precio := (v_p->>'precio')::numeric;
  NEW.mensaje := v_p->>'mensaje';
  NEW.mensajes := coalesce(v_p->'mensajes', '[]');
  NEW.lineas := v_p->'lineas';
  RETURN NEW;
END;
$$;

-- Escribir `mantener`, aunque no cambie, recalcula: así se actualiza a hoy una ventana que ya estaba a hoy y cambió de precio.
-- La marca es `condiciones_en` NULL, que nadie escribe; presupuestos_renglones_validar corre después (orden alfabético).
CREATE OR REPLACE FUNCTION public.presupuestos_renglones_a_hoy()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.tipo = 'catalogo' THEN
    NEW.condiciones_en := NULL;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_renglones_a_hoy() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_renglones_a_hoy ON public.presupuestos_renglones;
CREATE TRIGGER presupuestos_renglones_a_hoy
  BEFORE UPDATE OF mantener ON public.presupuestos_renglones
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_renglones_a_hoy();

-- ============================================================
-- 5. Corregir, actualizar o sumar variante: copiar una versión
-- ============================================================
-- La versión nueva es de la misma variante (corrección o actualización) o de la siguiente, y arranca con las secciones, cómo se
-- ve cada opcional, las ventanas y los renglones a mano de la de origen. Las ventanas arrancan a hoy; los mínimos los pone la
-- base. Como quien arma: la RLS y los triggers deciden.
CREATE OR REPLACE FUNCTION public.presupuestos_version_copiar(p_desde uuid, p_variante_nueva boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_d public.presupuestos_versiones;
  v_id uuid := gen_random_uuid();
  v_secciones jsonb;
BEGIN
  SELECT * INTO v_d FROM public.presupuestos_versiones WHERE id = p_desde AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.presupuestos_versiones (id, presupuesto_id, variante, variante_nombre, iva_discriminado, descuento, origen_id)
  VALUES (v_id, v_d.presupuesto_id,
          CASE WHEN p_variante_nueva THEN (SELECT max(v.variante) + 1 FROM public.presupuestos_versiones v
                                           WHERE v.presupuesto_id = v_d.presupuesto_id)
               ELSE v_d.variante END,
          CASE WHEN p_variante_nueva THEN NULL ELSE v_d.variante_nombre END,
          v_d.iva_discriminado, v_d.descuento, p_desde);

  SELECT coalesce(jsonb_object_agg(s.id, gen_random_uuid()), '{}') INTO v_secciones
  FROM public.presupuestos_secciones s WHERE s.version_id = p_desde AND s.activo;

  INSERT INTO public.presupuestos_secciones (id, version_id, nombre, moneda, alicuota, orden)
  SELECT (v_secciones->>s.id::text)::uuid, v_id, s.nombre, s.moneda, s.alicuota, s.orden
  FROM public.presupuestos_secciones s WHERE s.version_id = p_desde AND s.activo;

  INSERT INTO public.presupuestos_opcionales (version_id, pieza, porcentaje_id, forma, seccion_id)
  SELECT v_id, o.pieza, o.porcentaje_id, o.forma, (v_secciones->>o.seccion_id::text)::uuid
  FROM public.presupuestos_opcionales o WHERE o.version_id = p_desde AND o.activo;

  INSERT INTO public.presupuestos_renglones (version_id, seccion_id, tipo, designacion, ubicacion, cantidad, orden, paquete_id,
                                             entrada, opcionales, descripcion, precio, origen_id)
  SELECT v_id, (v_secciones->>r.seccion_id::text)::uuid, r.tipo, r.designacion, r.ubicacion, r.cantidad, r.orden, r.paquete_id,
         r.entrada, r.opcionales, r.descripcion, CASE WHEN r.tipo = 'mano' THEN r.precio END, r.id
  FROM public.presupuestos_renglones r
  WHERE r.version_id = p_desde AND r.activo AND r.tipo <> 'minimo'
  ORDER BY r.orden, r.created_at;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_copiar(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_copiar(uuid, boolean) TO authenticated;

-- ============================================================
-- 6. Publicar y quitar una variante
-- ============================================================
-- Lo que frena publicar, una línea por cosa, para mostrarlo arriba del editor. Lo que pide autorización frena hasta el 3b.
CREATE OR REPLACE FUNCTION public.presupuestos_version_revisar(p_version uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_c public.presupuestos_configuracion;
  v_out text[] := '{}';
  v_r record;
  v_f jsonb;
  v_monto numeric;
  v_n integer;
BEGIN
  SELECT v.* INTO v_v
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE v.id = p_version AND public.presupuestos_arma(p.obra_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_c FROM public.presupuestos_configuracion WHERE activo;
  IF NOT FOUND THEN
    v_out := v_out || 'Falta configurar el plazo de vencimiento, en Presupuestos → Configuración'::text;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.presupuestos_renglones r WHERE r.version_id = p_version AND r.activo) THEN
    v_out := v_out || 'La versión no tiene renglones'::text;
  END IF;

  IF v_v.variante_nombre IS NULL AND EXISTS (
       SELECT 1 FROM public.presupuestos_versiones o
       WHERE o.presupuesto_id = v_v.presupuesto_id AND o.activo AND o.estado = 'publicado' AND o.variante <> v_v.variante) THEN
    v_out := v_out || 'La variante necesita nombre: el presupuesto tiene más de una'::text;
  END IF;

  v_out := v_out || ARRAY(
    SELECT public.presupuestos_renglon_etiqueta(r.designacion, r.ubicacion, r.descripcion) || ': '
           || coalesce(r.mensaje, (SELECT string_agg(m->>'mensaje', '; ') FROM jsonb_array_elements(r.mensajes) m
                                   WHERE (m->>'bloquea')::boolean), 'sin precio')
    FROM public.presupuestos_renglones r
    WHERE r.version_id = p_version AND r.activo AND r.tipo = 'catalogo' AND r.precio IS NULL
    ORDER BY r.orden, r.created_at);

  -- Lo que está a hoy y cambió desde que se calculó (decisión del usuario, 2026-11-06).
  FOR v_r IN
    SELECT r.*, s.moneda AS seccion_moneda
    FROM public.presupuestos_renglones r JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
    WHERE r.version_id = p_version AND r.activo AND r.tipo = 'catalogo' AND NOT r.mantener AND r.precio IS NOT NULL
    ORDER BY r.orden, r.created_at
  LOOP
    v_f := public.presupuestos_precio_lineas(p_version, NULL, v_r.paquete_id, v_r.entrada, v_r.opcionales,
                                             public.presupuestos_renglon_monedas(p_version, v_r.seccion_moneda));
    IF ((v_f->>'precio')::numeric, (v_f->>'version_id')::uuid, v_f->'lineas')
       IS DISTINCT FROM (v_r.precio, v_r.catalogo_version_id, v_r.lineas) THEN
      v_out := v_out || format('%s: cambió desde que se calculó (%s → %s %s): %s',
        public.presupuestos_renglon_etiqueta(v_r.designacion, v_r.ubicacion, v_r.descripcion),
        trim_scale(v_r.precio), coalesce(trim_scale((v_f->>'precio')::numeric)::text, 'sin precio'), v_r.moneda,
        CASE WHEN v_r.origen_id IS NULL THEN 'actualizala' ELSE 'actualizala o mantenela' END);
    END IF;
  END LOOP;

  FOR v_r IN
    SELECT r.*, s.moneda AS seccion_moneda
    FROM public.presupuestos_renglones r JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
    WHERE r.version_id = p_version AND r.activo AND r.tipo = 'minimo' AND NOT r.mantener
    ORDER BY r.descripcion
  LOOP
    v_monto := NULL;
    SELECT m.monto INTO v_monto FROM public.presupuestos_minimos_calcular(p_version, v_r.seccion_moneda) m
    WHERE m.porcentaje_id = v_r.porcentaje_id;
    IF coalesce(v_monto, 0) <> v_r.precio THEN
      v_out := v_out || format('Mínimo de %s: cambió desde que se calculó (%s → %s %s): actualizalo', v_r.descripcion,
        trim_scale(v_r.precio), trim_scale(coalesce(v_monto, 0)), v_r.moneda);
    END IF;
  END LOOP;

  v_out := v_out || ARRAY(
    SELECT format('Falta el mínimo de %s: actualizá las ventanas', m.nombre)
    FROM public.presupuestos_minimos_calcular(p_version, public.monedas_principal_actual()) m
    WHERE NOT EXISTS (SELECT 1 FROM public.presupuestos_renglones r
                      WHERE r.version_id = p_version AND r.activo AND r.porcentaje_id = m.porcentaje_id)
    ORDER BY m.nombre);

  SELECT count(*) INTO v_n FROM public.presupuestos_renglones r WHERE r.version_id = p_version AND r.activo AND r.mantener;
  IF v_n > 0 THEN
    v_out := v_out || format('Pide autorización del jefe comercial: %s',
      CASE v_n WHEN 1 THEN '1 renglón mantenido' ELSE v_n || ' renglones mantenidos' END);
  END IF;

  IF v_v.descuento > coalesce(v_c.tope_descuento, 0) THEN
    v_out := v_out || format('Pide autorización del jefe comercial: descuento de %s %% sobre el tope de %s %%',
      trim_scale(v_v.descuento), trim_scale(coalesce(v_c.tope_descuento, 0)));
  END IF;

  v_out := v_out || ARRAY(
    SELECT 'Pide autorización de Técnica: ' || public.presupuestos_renglon_etiqueta(r.designacion, r.ubicacion, r.descripcion)
           || ': ' || string_agg(m->>'mensaje', '; ')
    FROM public.presupuestos_renglones r, jsonb_array_elements(r.mensajes) m
    WHERE r.version_id = p_version AND r.activo AND r.tipo = 'catalogo' AND r.precio IS NOT NULL
      AND NOT (m->>'bloquea')::boolean
    GROUP BY r.id, r.designacion, r.ubicacion, r.descripcion, r.orden, r.created_at
    ORDER BY r.orden, r.created_at);

  RETURN v_out;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_revisar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_revisar(uuid) TO authenticated;

-- Publica un borrador sin nada que lo frene: guarda el vencimiento con el plazo vigente, la publicada de esa variante pasa a
-- obsoleto y el presupuesto, a publicado. DEFINER: el estado no tiene GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_version_publicar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_p public.presupuestos;
  v_frena text[];
BEGIN
  SELECT p.* INTO v_p
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE v.id = p_version
  FOR UPDATE OF p;
  IF NOT FOUND OR NOT public.presupuestos_arma(v_p.obra_id) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_v FROM public.presupuestos_versiones WHERE id = p_version FOR UPDATE;

  IF NOT v_p.activo OR v_p.estado NOT IN ('borrador', 'publicado') THEN
    RAISE EXCEPTION 'El presupuesto % no admite publicar: está %', v_p.codigo,
      CASE WHEN NOT v_p.activo THEN 'desactivado' ELSE v_p.estado::text END USING ERRCODE = 'PR003';
  END IF;
  IF NOT v_v.activo OR v_v.estado <> 'borrador' THEN
    RAISE EXCEPTION 'La versión no está en borrador' USING ERRCODE = 'PR005';
  END IF;

  v_frena := public.presupuestos_version_revisar(p_version);
  IF cardinality(v_frena) > 0 THEN
    RAISE EXCEPTION '%', array_to_string(v_frena, E'\n') USING ERRCODE = 'PR014';
  END IF;

  UPDATE public.presupuestos_versiones SET estado = 'obsoleto'
  WHERE presupuesto_id = v_v.presupuesto_id AND variante = v_v.variante AND activo AND estado = 'publicado';
  UPDATE public.presupuestos_versiones
  SET estado = 'publicado',
      vence = (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date
              + (SELECT c.plazo_dias FROM public.presupuestos_configuracion c WHERE c.activo)
  WHERE id = p_version;
  UPDATE public.presupuestos SET estado = 'publicado' WHERE id = v_p.id AND estado = 'borrador';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_publicar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_publicar(uuid) TO authenticated;

-- El cliente ya no la elige: la publicada pasa a obsoleto y el presupuesto sigue con las demás. La última no se quita.
CREATE OR REPLACE FUNCTION public.presupuestos_variante_quitar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_p public.presupuestos;
BEGIN
  SELECT p.* INTO v_p
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE v.id = p_version
  FOR UPDATE OF p;
  IF NOT FOUND OR NOT public.presupuestos_arma(v_p.obra_id) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_v FROM public.presupuestos_versiones WHERE id = p_version FOR UPDATE;

  IF NOT v_p.activo OR v_p.estado <> 'publicado' THEN
    RAISE EXCEPTION 'El presupuesto % no admite quitar variantes: está %', v_p.codigo,
      CASE WHEN NOT v_p.activo THEN 'desactivado' ELSE v_p.estado::text END USING ERRCODE = 'PR003';
  END IF;
  IF NOT v_v.activo OR v_v.estado <> 'publicado' THEN
    RAISE EXCEPTION 'Solo se quita una variante publicada' USING ERRCODE = 'PR015';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.presupuestos_versiones o
                 WHERE o.presupuesto_id = v_v.presupuesto_id AND o.activo AND o.estado = 'publicado' AND o.id <> p_version) THEN
    RAISE EXCEPTION 'Es la única variante publicada: para eso está rechazar' USING ERRCODE = 'PR016';
  END IF;

  UPDATE public.presupuestos_versiones SET estado = 'obsoleto' WHERE id = p_version;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_variante_quitar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_variante_quitar(uuid) TO authenticated;
