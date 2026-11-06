-- Presupuestos, tramo 3b: pedir autorización, autorizar, devolver y retirar, y la lectura de Técnica. Lo que frena publicar se
-- separa de lo que pide autorización: el jefe comercial autoriza la versión (lo mantenido y el descuento sobre el tope) y Técnica
-- cada ventana con una alerta, o mantenida con algo que ya no se ofrece.
-- Ficha y decisiones: decisiones/presupuestos.md (→ Estados y versiones, Quién accede, Precio, La base). Esquema:
-- db_schema/presupuestos.md.
-- Errores, clase PR (siguen a sql/188): PR017 la versión no está en revisión · PR018 el pedido ya no está pendiente ·
-- PR019 devolver pide motivo.

-- ============================================================
-- 1. Catálogo: lo elegido que ya no se ofrece
-- ============================================================
-- Lo que catalogo_precio_venta frenaba adentro, aparte: Presupuestos lo pregunta también de una ventana mantenida, con su
-- versión. NULL si se ofrece; si no, el porqué. `p_r` es lo que devuelve catalogo_precio_calcular. Sin GRANT.
CREATE OR REPLACE FUNCTION public.catalogo_precio_fuera(p_version uuid, p_r jsonb)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_o record;
  v_fuera text;
BEGIN
  SELECT o.armable, o.piezas_fuera, o.opciones_fuera INTO v_o
  FROM public.catalogo_oferta(p_version) o
  WHERE o.color_id IS NOT DISTINCT FROM (p_r->'color'->>'id')::uuid;

  IF NOT FOUND OR NOT v_o.armable THEN
    RETURN 'Este paquete no se ofrece en este color';
  END IF;

  SELECT string_agg(DISTINCT CASE
           WHEN (f->>'pieza_id')::uuid = ANY (v_o.piezas_fuera) THEN f->>'pieza' ELSE f->>'insumo' END, ', ')
  INTO v_fuera
  FROM jsonb_array_elements(p_r->'filas') f
  WHERE (f->>'pieza_id')::uuid = ANY (v_o.piezas_fuera) OR (f->>'opcion_id')::uuid = ANY (v_o.opciones_fuera);

  RETURN 'Ya no se ofrece: ' || v_fuera;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.catalogo_precio_fuera(uuid, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.catalogo_precio_venta(p_paquete uuid, p_entrada jsonb, p_opcionales uuid[], p_moneda moneda)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_version uuid;
  v_r jsonb;
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

  v_fuera := public.catalogo_precio_fuera(v_version, v_r);
  IF v_fuera IS NOT NULL THEN
    RETURN v_r || jsonb_build_object('precio', NULL::numeric, 'mensaje', v_fuera);
  END IF;

  RETURN v_r;
END;
$$;

-- ============================================================
-- 2. presupuestos_autorizaciones — qué se pidió y cómo se resolvió
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.tipo_autorizacion_presupuesto AS ENUM ('comercial', 'tecnica');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.estado_autorizacion_presupuesto AS ENUM ('pendiente', 'autorizada', 'devuelta', 'retirada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Una fila por pedido: del jefe, por versión; de Técnica, por renglón. Pedir de nuevo es otra fila. `activo` false: una
-- autorización del jefe que ya no vale, porque la versión volvió a borrador.
CREATE TABLE IF NOT EXISTS public.presupuestos_autorizaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.presupuestos_versiones(id),
  tipo public.tipo_autorizacion_presupuesto NOT NULL,
  renglon_id uuid REFERENCES public.presupuestos_renglones(id),
  pedido jsonb NOT NULL,
  estado public.estado_autorizacion_presupuesto NOT NULL DEFAULT 'pendiente',
  pedido_por uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  resuelto_por uuid REFERENCES public.usuarios(id),
  resuelto_en timestamptz,
  motivo text CHECK (char_length(btrim(motivo)) BETWEEN 1 AND 500),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT presupuestos_autorizaciones_forma CHECK ((tipo::text = 'tecnica') = (renglon_id IS NOT NULL)),
  CONSTRAINT presupuestos_autorizaciones_resuelta CHECK (
    (estado::text = 'pendiente') = (resuelto_por IS NULL) AND (resuelto_por IS NULL) = (resuelto_en IS NULL)),
  CONSTRAINT presupuestos_autorizaciones_motivo CHECK ((estado::text = 'devuelta') = (motivo IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS presupuestos_autorizaciones_version ON public.presupuestos_autorizaciones (version_id);

ALTER TABLE public.presupuestos_autorizaciones ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_autorizaciones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_autorizaciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Quien ve el presupuesto ve sus pedidos, con los montos. Técnica no: lee por presupuestos_revision_*. Se escribe solo por las
-- funciones del ciclo.
DROP POLICY IF EXISTS presupuestos_autorizaciones_select ON public.presupuestos_autorizaciones;
CREATE POLICY presupuestos_autorizaciones_select ON public.presupuestos_autorizaciones FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.presupuestos_versiones v WHERE v.id = version_id));

GRANT SELECT ON public.presupuestos_autorizaciones TO authenticated;

-- ============================================================
-- 3. Quién autoriza y qué vale
-- ============================================================
-- El jefe comercial, con la obra a cargo; Técnica, cualquier ventana; administrar, todo. Con GRANT: la pantalla muestra el botón.
CREATE OR REPLACE FUNCTION public.presupuestos_puede_autorizar(p_tipo public.tipo_autorizacion_presupuesto, p_obra uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (public.usuario_tiene_permiso(auth.uid(), 'presupuestos_ver')
          AND public.usuario_tiene_permiso(auth.uid(), 'presupuestos_administrar'))
    OR CASE p_tipo
         WHEN 'comercial' THEN public.usuario_tiene_permiso(auth.uid(), 'presupuestos_ver')
           AND public.usuario_tiene_permiso(auth.uid(), 'presupuestos_autorizar')
           AND public.obras_a_cargo_de(p_obra, auth.uid())
         ELSE public.usuario_tiene_permiso(auth.uid(), 'presupuestos_revision')
           AND public.usuario_tiene_permiso(auth.uid(), 'presupuestos_autorizar_tecnica')
       END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_puede_autorizar(public.tipo_autorizacion_presupuesto, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_puede_autorizar(public.tipo_autorizacion_presupuesto, uuid) TO authenticated;

-- Lo que autorizó Técnica vale para una ventana igual: mismo paquete, versión y lo cargado, por los mismos motivos o menos.
CREATE OR REPLACE FUNCTION public.presupuestos_tecnica_cubre(p_autorizado jsonb, p_pedido jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT (p_autorizado->'paquete_id') = (p_pedido->'paquete_id')
     AND (p_autorizado->'catalogo_version_id') = (p_pedido->'catalogo_version_id')
     AND (p_autorizado->'entrada') = (p_pedido->'entrada')
     AND (p_autorizado->'motivos') @> (p_pedido->'motivos');
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_tecnica_cubre(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- Lo que pide autorización en una versión, y en qué está cada cosa: `estado` NULL (falta pedirla), `pendiente` o `autorizada`.
-- {comercial: NULL | {renglones, diferencia, descuento, tope, texto, estado}, tecnica: [{renglon_id, etiqueta, paquete_id,
-- catalogo_version_id, entrada, motivos, texto, estado}]}. Cada renglón mantenido: {renglon_id, etiqueta, moneda, cantidad,
-- precio, hoy, diferencia, condiciones_en}; `hoy` es el precio a hoy (NULL si no tiene) y `diferencia`, lo que se resigna: a hoy
-- menos mantenido, por la cantidad. `diferencia` de la versión: la suma por moneda. `descuento`: solo si pasa el tope.
-- Lo del jefe vale en la vuelta en que se dio (activo); lo de Técnica, en cualquier versión del presupuesto.
CREATE OR REPLACE FUNCTION public.presupuestos_version_pedido(p_version uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_tope numeric;
  v_r record;
  v_hoy numeric;
  v_motivos jsonb;
  v_t jsonb;
  v_renglones jsonb := '[]';
  v_tecnica jsonb := '[]';
  v_descuento numeric;
  v_comercial jsonb;
BEGIN
  SELECT v.* INTO v_v
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE v.id = p_version AND public.presupuestos_arma(p.obra_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  SELECT c.tope_descuento INTO v_tope FROM public.presupuestos_configuracion c WHERE c.activo;
  v_tope := coalesce(v_tope, 0);

  FOR v_r IN
    SELECT r.*, public.presupuestos_renglon_etiqueta(r.designacion, r.ubicacion, r.descripcion) AS etiqueta
    FROM public.presupuestos_renglones r
    WHERE r.version_id = p_version AND r.activo AND r.tipo <> 'mano'
    ORDER BY r.tipo = 'minimo', r.orden, r.created_at
  LOOP
    IF v_r.mantener THEN
      v_hoy := CASE WHEN v_r.tipo = 'catalogo'
        THEN (public.catalogo_precio_en(v_r.paquete_id, NULL, NULL, v_r.entrada, v_r.opcionales, v_r.moneda)->>'precio')::numeric
        ELSE coalesce((SELECT m.monto FROM public.presupuestos_minimos_calcular(p_version, v_r.moneda, '{}') m
                       WHERE m.porcentaje_id = v_r.porcentaje_id), 0) END;
      v_renglones := v_renglones || jsonb_build_object('renglon_id', v_r.id, 'etiqueta', v_r.etiqueta, 'moneda', v_r.moneda,
        'cantidad', v_r.cantidad, 'precio', v_r.precio, 'hoy', v_hoy, 'condiciones_en', v_r.condiciones_en,
        'diferencia', public.catalogo_precio_redondear(v_hoy * v_r.cantidad, v_r.moneda)
                      - public.catalogo_precio_redondear(v_r.precio * v_r.cantidad, v_r.moneda));
    END IF;

    CONTINUE WHEN v_r.tipo <> 'catalogo' OR v_r.precio IS NULL;
    SELECT coalesce(jsonb_agg(m->'mensaje'), '[]') INTO v_motivos
    FROM jsonb_array_elements(v_r.mensajes) m WHERE NOT (m->>'bloquea')::boolean;
    IF v_r.mantener THEN
      v_motivos := v_motivos || coalesce(to_jsonb(public.catalogo_precio_fuera(v_r.catalogo_version_id,
        public.catalogo_precio_calcular(v_r.catalogo_version_id, v_r.entrada, v_r.opcionales, v_r.moneda, v_r.condiciones_en))),
        '[]');
    END IF;
    CONTINUE WHEN v_motivos = '[]';

    v_t := jsonb_build_object('renglon_id', v_r.id, 'etiqueta', v_r.etiqueta, 'paquete_id', v_r.paquete_id,
      'catalogo_version_id', v_r.catalogo_version_id, 'entrada', v_r.entrada, 'motivos', v_motivos,
      'texto', 'autorización de Técnica: ' || v_r.etiqueta || ': '
               || (SELECT string_agg(x, '; ') FROM jsonb_array_elements_text(v_motivos) x));
    v_tecnica := v_tecnica || (v_t || jsonb_build_object('estado', CASE
      WHEN EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones a
                   JOIN public.presupuestos_versiones av ON av.id = a.version_id
                   WHERE av.presupuesto_id = v_v.presupuesto_id AND a.tipo = 'tecnica' AND a.estado = 'autorizada' AND a.activo
                     AND public.presupuestos_tecnica_cubre(a.pedido, v_t)) THEN 'autorizada'
      WHEN EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones a
                   WHERE a.version_id = p_version AND a.renglon_id = v_r.id AND a.estado = 'pendiente') THEN 'pendiente' END));
  END LOOP;

  v_descuento := CASE WHEN v_v.descuento > v_tope THEN v_v.descuento END;
  IF v_renglones <> '[]' OR v_descuento IS NOT NULL THEN
    v_comercial := jsonb_build_object(
      'renglones', v_renglones,
      'diferencia', (SELECT coalesce(jsonb_agg(jsonb_build_object('moneda', d.moneda, 'monto', d.monto) ORDER BY d.moneda), '[]')
                     FROM (SELECT x->>'moneda' AS moneda, sum((x->>'diferencia')::numeric) AS monto
                           FROM jsonb_array_elements(v_renglones) x
                           WHERE x->>'diferencia' IS NOT NULL GROUP BY 1) d),
      'descuento', v_descuento,
      'tope', v_tope,
      'texto', 'autorización del jefe comercial: ' || array_to_string(ARRAY[
        CASE jsonb_array_length(v_renglones) WHEN 0 THEN NULL WHEN 1 THEN '1 renglón mantenido'
          ELSE jsonb_array_length(v_renglones) || ' renglones mantenidos' END,
        CASE WHEN v_descuento IS NOT NULL
          THEN format('descuento de %s %% sobre el tope de %s %%', trim_scale(v_descuento), trim_scale(v_tope)) END], ' · '),
      'estado', CASE
        WHEN EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones a
                     WHERE a.version_id = p_version AND a.tipo = 'comercial' AND a.estado = 'autorizada' AND a.activo
                       AND (v_descuento IS NULL OR jsonb_typeof(a.pedido->'descuento') = 'number')) THEN 'autorizada'
        WHEN EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones a
                     WHERE a.version_id = p_version AND a.tipo = 'comercial' AND a.estado = 'pendiente') THEN 'pendiente' END);
  END IF;

  RETURN jsonb_build_object('comercial', v_comercial, 'tecnica', v_tecnica);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_pedido(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_pedido(uuid) TO authenticated;

-- ============================================================
-- 4. Lo que frena publicar, sin lo que pide autorización
-- ============================================================
-- Lo que frena pedir y publicar, una línea por cosa, para mostrarlo arriba del editor. Lo que pide autorización ya no frena:
-- lo dice presupuestos_version_pedido.
CREATE OR REPLACE FUNCTION public.presupuestos_version_revisar(p_version uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_out text[] := '{}';
  v_r record;
  v_f jsonb;
  v_monto numeric;
BEGIN
  SELECT v.* INTO v_v
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE v.id = p_version AND public.presupuestos_arma(p.obra_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.presupuestos_configuracion WHERE activo) THEN
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

  RETURN v_out;
END;
$$;

-- ============================================================
-- 5. Pedir, resolver, retirar y publicar
-- ============================================================
-- Vuelve a borrador: lo pendiente queda retirado y lo que autorizó el jefe deja de valer. Lo de Técnica sigue. Sin GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_version_a_borrador(p_version uuid)
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
  UPDATE public.presupuestos_autorizaciones SET estado = 'retirada', resuelto_por = auth.uid(), resuelto_en = now()
  WHERE version_id = p_version AND estado = 'pendiente';
  UPDATE public.presupuestos_autorizaciones SET activo = false
  WHERE version_id = p_version AND tipo = 'comercial' AND estado = 'autorizada' AND activo;
  UPDATE public.presupuestos_versiones SET estado = 'borrador' WHERE id = p_version;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_a_borrador(uuid) FROM PUBLIC, anon, authenticated;

-- Publica un borrador, o una versión en revisión, si nada la frena: lo de revisar, lo que pide autorización sin pedir y lo que
-- espera. Guarda el vencimiento con el plazo vigente, la publicada de esa variante pasa a obsoleto y el presupuesto, a
-- publicado. DEFINER: el estado no tiene GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_version_publicar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_p public.presupuestos;
  v_pedido jsonb;
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
  IF NOT v_v.activo OR v_v.estado NOT IN ('borrador', 'en_revision') THEN
    RAISE EXCEPTION 'La versión no está en borrador ni en revisión' USING ERRCODE = 'PR005';
  END IF;

  v_pedido := public.presupuestos_version_pedido(p_version);
  v_frena := public.presupuestos_version_revisar(p_version)
    || ARRAY(SELECT 'Pide ' || (x->>'texto')
             FROM jsonb_array_elements(jsonb_build_array(v_pedido->'comercial') || (v_pedido->'tecnica')) x
             WHERE jsonb_typeof(x) = 'object' AND x->>'estado' IS NULL)
    || ARRAY(SELECT 'Espera la ' || (a.pedido->>'texto')
             FROM public.presupuestos_autorizaciones a
             WHERE a.version_id = p_version AND a.estado = 'pendiente'
             ORDER BY a.tipo, a.created_at);
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

-- Pide lo que falta autorizar y la versión pasa a `en_revision`, sin editarse. Lo que quien pide ya podría autorizar queda
-- autorizado, y se registra así; si no queda nada pendiente, publica en el mismo paso. Devuelve el estado en que quedó.
CREATE OR REPLACE FUNCTION public.presupuestos_version_pedir(p_version uuid)
RETURNS public.estado_version_presupuesto
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_p public.presupuestos;
  v_frena text[];
  v_pedido jsonb;
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

  v_pedido := public.presupuestos_version_pedido(p_version);
  INSERT INTO public.presupuestos_autorizaciones (version_id, tipo, renglon_id, pedido, estado, resuelto_por, resuelto_en)
  SELECT p_version, x.tipo, x.renglon_id, x.pedido,
         CASE WHEN x.puede THEN 'autorizada' ELSE 'pendiente' END::public.estado_autorizacion_presupuesto,
         CASE WHEN x.puede THEN auth.uid() END, CASE WHEN x.puede THEN now() END
  FROM (
    SELECT 'comercial'::public.tipo_autorizacion_presupuesto AS tipo, NULL::uuid AS renglon_id, c - 'estado' AS pedido,
           public.presupuestos_puede_autorizar('comercial', v_p.obra_id) AS puede
    FROM jsonb_array_elements(jsonb_build_array(v_pedido->'comercial')) c
    WHERE jsonb_typeof(c) = 'object' AND c->>'estado' IS NULL
    UNION ALL
    SELECT 'tecnica', (t->>'renglon_id')::uuid, t - 'estado' - 'renglon_id',
           public.presupuestos_puede_autorizar('tecnica', v_p.obra_id)
    FROM jsonb_array_elements(v_pedido->'tecnica') t
    WHERE t->>'estado' IS NULL
  ) x;

  UPDATE public.presupuestos_versiones SET estado = 'en_revision' WHERE id = p_version;
  IF NOT EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones a WHERE a.version_id = p_version AND a.estado = 'pendiente') THEN
    PERFORM public.presupuestos_version_publicar(p_version);
  END IF;
  RETURN (SELECT v.estado FROM public.presupuestos_versiones v WHERE v.id = p_version);
END;
$$;

-- Autoriza o devuelve un pedido pendiente. Devolver pide motivo y la versión vuelve a borrador. Técnica autoriza junto con el
-- pedido los pendientes de las ventanas iguales de la versión: su autorización ya valía para ellas.
CREATE OR REPLACE FUNCTION public.presupuestos_pedido_resolver(p_id uuid, p_autoriza boolean, p_motivo text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_obra uuid;
  v_a public.presupuestos_autorizaciones;
  v_quien text;
  v_cuando text;
BEGIN
  SELECT p.obra_id INTO v_obra
  FROM public.presupuestos_autorizaciones a
  JOIN public.presupuestos_versiones v ON v.id = a.version_id
  JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE a.id = p_id
  FOR UPDATE OF p;
  SELECT * INTO v_a FROM public.presupuestos_autorizaciones WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR NOT public.presupuestos_puede_autorizar(v_a.tipo, v_obra) THEN
    RAISE EXCEPTION 'No se encontró el pedido' USING ERRCODE = '42501';
  END IF;

  IF v_a.estado <> 'pendiente' THEN
    SELECT u.nombre INTO v_quien FROM public.usuarios u WHERE u.id = v_a.resuelto_por;
    v_cuando := to_char(v_a.resuelto_en AT TIME ZONE 'America/Argentina/Buenos_Aires', 'FMDD/FMMM');
    RAISE EXCEPTION '%', CASE
      WHEN v_a.estado = 'autorizada' THEN format('%s ya lo autorizó el %s', v_quien, v_cuando)
      WHEN v_a.estado = 'devuelta' THEN format('%s ya lo devolvió el %s', v_quien, v_cuando)
      WHEN EXISTS (SELECT 1 FROM public.presupuestos_autorizaciones d
                   WHERE d.version_id = v_a.version_id AND d.estado = 'devuelta' AND d.resuelto_en = v_a.resuelto_en)
        THEN format('%s devolvió la versión el %s: volvió a borrador', v_quien, v_cuando)
      ELSE format('%s retiró el pedido el %s: la versión volvió a borrador', v_quien, v_cuando) END
      USING ERRCODE = 'PR018';
  END IF;

  IF p_autoriza THEN
    UPDATE public.presupuestos_autorizaciones a
    SET estado = 'autorizada', resuelto_por = auth.uid(), resuelto_en = now()
    WHERE a.id = p_id
       OR (v_a.tipo = 'tecnica' AND a.tipo = 'tecnica' AND a.version_id = v_a.version_id AND a.estado = 'pendiente'
           AND public.presupuestos_tecnica_cubre(v_a.pedido, a.pedido));
  ELSE
    IF btrim(coalesce(p_motivo, '')) = '' THEN
      RAISE EXCEPTION 'Devolver pide motivo' USING ERRCODE = 'PR019';
    END IF;
    UPDATE public.presupuestos_autorizaciones
    SET estado = 'devuelta', motivo = btrim(p_motivo), resuelto_por = auth.uid(), resuelto_en = now()
    WHERE id = p_id;
    PERFORM public.presupuestos_version_a_borrador(v_a.version_id);
  END IF;
END;
$$;

-- Quien arma retira la versión de la revisión y vuelve a borrador, para editarla. No avisa (decisión del usuario, 2026-11-06).
CREATE OR REPLACE FUNCTION public.presupuestos_version_retirar(p_version uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p public.presupuestos;
BEGIN
  SELECT p.* INTO v_p
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE v.id = p_version
  FOR UPDATE OF p;
  IF NOT FOUND OR NOT public.presupuestos_arma(v_p.obra_id) THEN
    RAISE EXCEPTION 'No se encontró la versión' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM public.presupuestos_versiones WHERE id = p_version AND activo AND estado = 'en_revision' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La versión no está en revisión' USING ERRCODE = 'PR017';
  END IF;
  PERFORM public.presupuestos_version_a_borrador(p_version);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_pedir(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_pedir(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.presupuestos_pedido_resolver(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_pedido_resolver(uuid, boolean, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.presupuestos_version_retirar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_retirar(uuid) TO authenticated;

-- ============================================================
-- 6. Lo que lee Técnica
-- ============================================================
-- Sin precios, montos, totales, obra ni nombre del presupuesto: el número y, por renglón, lo cargado y las alertas. Con la
-- vista Revisión técnica, o administrar.

-- Los pedidos de Técnica pendientes, los más viejos primero.
CREATE OR REPLACE FUNCTION public.presupuestos_revision_pendientes()
RETURNS TABLE (pedido_id uuid, version_id uuid, codigo text, etiqueta text, motivos jsonb, pedido_por uuid, pedido_en timestamptz)
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
    SELECT a.id, a.version_id, p.codigo, a.pedido->>'etiqueta', a.pedido->'motivos', a.pedido_por, a.created_at
    FROM public.presupuestos_autorizaciones a
    JOIN public.presupuestos_versiones v ON v.id = a.version_id
    JOIN public.presupuestos p ON p.id = v.presupuesto_id
    WHERE a.tipo = 'tecnica' AND a.estado = 'pendiente'
    ORDER BY a.created_at, p.numero;
END;
$$;

-- Una versión completa, de un presupuesto con algún pedido de Técnica. Por renglón de Catálogo o a mano, y el último pedido de
-- Técnica de ese renglón en la versión (el pendiente primero).
CREATE OR REPLACE FUNCTION public.presupuestos_revision_version(p_version uuid)
RETURNS TABLE (renglon_id uuid, codigo text, tipo public.tipo_renglon_presupuesto, designacion text, ubicacion text,
               cantidad numeric, paquete_id uuid, paquete text, catalogo_version_id uuid, catalogo_version integer,
               entrada jsonb, mensajes jsonb, descripcion text, pedido_id uuid,
               pedido_estado public.estado_autorizacion_presupuesto, motivos jsonb)
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
    SELECT r.id, p.codigo, r.tipo, r.designacion, r.ubicacion, r.cantidad, r.paquete_id, cv.nombre, r.catalogo_version_id,
           cv.numero, r.entrada, r.mensajes, r.descripcion, a.id, a.estado, a.pedido->'motivos'
    FROM public.presupuestos_renglones r
    JOIN public.presupuestos_versiones v ON v.id = r.version_id
    JOIN public.presupuestos p ON p.id = v.presupuesto_id
    LEFT JOIN public.catalogo_versiones cv ON cv.id = r.catalogo_version_id
    LEFT JOIN LATERAL (
      SELECT x.id, x.estado, x.pedido FROM public.presupuestos_autorizaciones x
      WHERE x.version_id = r.version_id AND x.renglon_id = r.id
      ORDER BY x.estado = 'pendiente' DESC, x.created_at DESC
      LIMIT 1) a ON true
    WHERE r.version_id = p_version AND r.activo AND r.tipo <> 'minimo'
    ORDER BY r.orden, r.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_revision_pendientes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_revision_pendientes() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.presupuestos_revision_version(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_revision_version(uuid) TO authenticated;
