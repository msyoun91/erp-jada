-- Tramo 3c: el recargo de la comisión del referente (decisiones/presupuestos.md, BACKLOG → Comisiones).
-- El % sale de obras_comisiones (vigentes, de los referentes de la obra, en %), se suman y se despejan una vez: precio / (1 - %).
-- En borrador la versión sigue a lo vigente; al salir de borrador queda guardado (presupuestos_recargos). Lo lee solo quien
-- ve la comisión; el resto recibe los importes ya con el recargo.

CREATE TABLE IF NOT EXISTS public.presupuestos_recargos (
  version_id uuid PRIMARY KEY REFERENCES public.presupuestos_versiones(id),
  porcentaje numeric(5,2) NOT NULL CHECK (porcentaje >= 0 AND porcentaje < 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.presupuestos_recargos ENABLE ROW LEVEL SECURITY;
DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_recargos;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.presupuestos_recargos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP POLICY IF EXISTS presupuestos_recargos_select ON public.presupuestos_recargos;
CREATE POLICY presupuestos_recargos_select ON public.presupuestos_recargos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
                 WHERE v.id = version_id AND public.obras_a_cargo(p.obra_id)));
REVOKE ALL ON public.presupuestos_recargos FROM PUBLIC, anon;
GRANT SELECT ON public.presupuestos_recargos TO authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_recargo_vigente(p_obra uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(sum(c.porcentaje), 0)
  FROM public.obras_comisiones c
  JOIN public.contactos_vinculos v ON v.id = c.vinculo_id
  WHERE c.activo AND c.porcentaje IS NOT NULL
    AND v.ente = 'obra' AND v.registro_id = p_obra AND v.activo AND v.hasta IS NULL AND 'referente' = ANY (v.roles);
$$;
REVOKE EXECUTE ON FUNCTION public.presupuestos_recargo_vigente(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_recargo_de(p_version uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado public.estado_version_presupuesto;
  v_obra uuid;
  v_r numeric;
BEGIN
  SELECT v.estado, p.obra_id INTO v_estado, v_obra
  FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id WHERE v.id = p_version;
  IF v_estado = 'borrador' THEN
    v_r := public.presupuestos_recargo_vigente(v_obra);
  ELSE
    SELECT r.porcentaje INTO v_r FROM public.presupuestos_recargos r WHERE r.version_id = p_version;
  END IF;
  v_r := coalesce(v_r, 0);
  IF v_r >= 100 THEN
    RAISE EXCEPTION 'Las comisiones de los referentes suman % %%: no pueden llegar al 100 %%', trim_scale(v_r) USING ERRCODE = 'PR020';
  END IF;
  RETURN v_r;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.presupuestos_recargo_de(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_recargar(p_version uuid, p_monto numeric, p_moneda public.moneda)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.catalogo_precio_redondear(p_monto / (1 - public.presupuestos_recargo_de(p_version) / 100), p_moneda);
$$;
REVOKE EXECUTE ON FUNCTION public.presupuestos_recargar(uuid, numeric, public.moneda) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_versiones_fijar_recargo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_r numeric;
BEGIN
  SELECT public.presupuestos_recargo_vigente(p.obra_id) INTO v_r FROM public.presupuestos p WHERE p.id = NEW.presupuesto_id;
  IF v_r >= 100 THEN
    RAISE EXCEPTION 'Las comisiones de los referentes suman % %%: no pueden llegar al 100 %%', trim_scale(v_r) USING ERRCODE = 'PR020';
  END IF;
  INSERT INTO public.presupuestos_recargos (version_id, porcentaje) VALUES (NEW.id, v_r)
  ON CONFLICT (version_id) DO UPDATE SET porcentaje = EXCLUDED.porcentaje;
  RETURN NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.presupuestos_versiones_fijar_recargo() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_versiones_fijar_recargo ON public.presupuestos_versiones;
CREATE TRIGGER presupuestos_versiones_fijar_recargo
  AFTER UPDATE OF estado ON public.presupuestos_versiones
  FOR EACH ROW WHEN (OLD.estado = 'borrador' AND NEW.estado <> 'borrador')
  EXECUTE FUNCTION public.presupuestos_versiones_fijar_recargo();

-- Lo que se cobra en cada sección, con el recargo. DEFINER porque lee el recargo: la visibilidad la decide acá.
CREATE OR REPLACE FUNCTION public.presupuestos_version_importes(p_version uuid)
RETURNS TABLE(renglon_id uuid, seccion_id uuid, moneda public.moneda, alicuota numeric, clave text, nombre text, importe numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH r AS (
    SELECT r.id, r.seccion_id, r.moneda, r.cantidad, r.precio, r.lineas, s.alicuota
    FROM public.presupuestos_renglones r
    JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
    WHERE r.version_id = p_version AND r.activo
      AND EXISTS (SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
                  WHERE v.id = p_version AND public.presupuestos_ve(p.obra_id))
  ),
  f AS (SELECT 1 - public.presupuestos_recargo_de(p_version) / 100 AS factor),
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
           (r.precio - coalesce((SELECT sum(ap.propio) FROM ap WHERE ap.id = r.id), 0)) * r.cantidad / f.factor, r.moneda)
  FROM r, f
  UNION ALL
  SELECT ap.id, ap.seccion_id, ap.moneda, ap.alicuota, ap.clave, ap.linea->>'nombre',
         public.catalogo_precio_redondear((ap.linea->>'monto')::numeric * ap.cantidad / f.factor, ap.moneda)
  FROM ap, f;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) TO authenticated;

-- El pedido del jefe muestra los precios con el recargo, como el resto (lo que compara publicar sigue sin él).
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
        'cantidad', v_r.cantidad, 'precio', public.presupuestos_recargar(p_version, v_r.precio, v_r.moneda),
        'hoy', public.presupuestos_recargar(p_version, v_hoy, v_r.moneda), 'condiciones_en', v_r.condiciones_en,
        'diferencia', public.presupuestos_recargar(p_version, v_hoy * v_r.cantidad, v_r.moneda)
                      - public.presupuestos_recargar(p_version, v_r.precio * v_r.cantidad, v_r.moneda));
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
