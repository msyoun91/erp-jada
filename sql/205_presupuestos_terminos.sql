-- Términos y condiciones del presupuesto. Los generales, en la configuración (cambian poco, con historial); los particulares,
-- en la versión. Al publicar, la versión guarda qué configuración regía: lo publicado no cambia si gerencia edita los generales.
-- Decisión: decisiones/presupuestos.md → *Términos y condiciones*. Esquema: db_schema/presupuestos.md.
-- Test: sql/tests/presupuestos_terminos.sql.

-- ============================================================
-- 1. Columnas
-- ============================================================
ALTER TABLE public.presupuestos_configuracion
  ADD COLUMN IF NOT EXISTS terminos text
  CHECK (length(terminos) BETWEEN 1 AND 5000 AND btrim(terminos) = terminos);

ALTER TABLE public.presupuestos_versiones
  ADD COLUMN IF NOT EXISTS condiciones text
  CHECK (length(condiciones) BETWEEN 1 AND 3000 AND btrim(condiciones) = condiciones),
  ADD COLUMN IF NOT EXISTS configuracion_id uuid REFERENCES public.presupuestos_configuracion(id);

GRANT INSERT (terminos) ON public.presupuestos_configuracion TO authenticated;
GRANT INSERT (condiciones), UPDATE (condiciones) ON public.presupuestos_versiones TO authenticated;

-- ============================================================
-- 2. Configurar: los términos van siempre, NULL = sin términos
-- ============================================================
DROP FUNCTION IF EXISTS public.presupuestos_configurar(numeric, integer, public.moneda[]);
CREATE OR REPLACE FUNCTION public.presupuestos_configurar(p_tope numeric, p_plazo integer, p_terminos text,
                                                          p_monedas public.moneda[] DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_monedas public.moneda[];
BEGIN
  IF NOT public.tiene_permiso('presupuestos_configuracion') THEN
    RAISE EXCEPTION 'Sin permiso para configurar Presupuestos' USING ERRCODE = '42501';
  END IF;
  SELECT c.monedas_referencia INTO v_monedas FROM public.presupuestos_configuracion c WHERE c.activo;
  UPDATE public.presupuestos_configuracion SET activo = false WHERE activo;
  INSERT INTO public.presupuestos_configuracion (id, tope_descuento, plazo_dias, monedas_referencia, terminos)
  VALUES (v_id, p_tope, p_plazo, coalesce(p_monedas, v_monedas, '{ARS,USD_OFICIAL}'), nullif(btrim(p_terminos), ''));
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer, text, public.moneda[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer, text, public.moneda[]) TO authenticated;

-- ============================================================
-- 3. Las condiciones particulares solo se editan en borrador
-- ============================================================
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

  IF (NEW.variante_nombre, NEW.iva_discriminado, NEW.descuento, NEW.condiciones)
       IS DISTINCT FROM (OLD.variante_nombre, OLD.iva_discriminado, OLD.descuento, OLD.condiciones)
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
-- 4. Copiar lleva las condiciones particulares
-- ============================================================
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

  INSERT INTO public.presupuestos_versiones (id, presupuesto_id, variante, variante_nombre, iva_discriminado, descuento, origen_id,
                                             condiciones)
  VALUES (v_id, v_d.presupuesto_id,
          CASE WHEN p_variante_nueva THEN (SELECT max(v.variante) + 1 FROM public.presupuestos_versiones v
                                           WHERE v.presupuesto_id = v_d.presupuesto_id)
               ELSE v_d.variante END,
          CASE WHEN p_variante_nueva THEN NULL ELSE v_d.variante_nombre END,
          v_d.iva_discriminado, v_d.descuento, p_desde, v_d.condiciones);

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

-- ============================================================
-- 5. Publicar congela qué configuración regía
-- ============================================================
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
      vence = (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date + c.plazo_dias,
      configuracion_id = c.id
  FROM public.presupuestos_configuracion c
  WHERE presupuestos_versiones.id = p_version AND c.activo;
  UPDATE public.presupuestos SET estado = 'publicado' WHERE id = v_p.id AND estado = 'borrador';
END;
$$;

-- ============================================================
-- 6. La copia del portal lleva las condiciones de cada versión
-- ============================================================
CREATE OR REPLACE FUNCTION public.presupuestos_portal_copia(p_link uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_l public.presupuestos_links;
  v_p public.presupuestos;
BEGIN
  SELECT * INTO v_l FROM public.presupuestos_links WHERE id = p_link;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_p FROM public.presupuestos WHERE id = v_l.presupuesto_id;
  IF NOT v_l.activo THEN
    RETURN jsonb_build_object('revision', v_l.revision, 'estado', 'cortado');
  ELSIF NOT v_p.activo OR v_p.estado NOT IN ('publicado', 'aprobado') THEN
    RETURN jsonb_build_object('revision', v_l.revision, 'estado', 'no_disponible');
  END IF;

  RETURN jsonb_build_object(
    'revision', v_l.revision, 'estado', v_p.estado, 'codigo', v_p.codigo, 'nombre', v_p.nombre,
    'aprobado_en', CASE WHEN v_p.estado = 'aprobado' THEN (
      SELECT max(e.created_at) FROM public.eventos e
      WHERE e.ente = 'presupuesto' AND e.registro_id = v_p.id AND e.evento = 'estado' AND e.detalle->>'estado' = 'aprobado') END,
    'whatsapp', (SELECT u.telefono FROM public.obras o JOIN public.usuarios u ON u.id = o.responsable_id WHERE o.id = v_p.obra_id),
    'versiones', (
      SELECT coalesce(jsonb_agg(public.presupuestos_portal_version(v.id, v_p.estado = 'publicado')
                                || jsonb_build_object('condiciones', v.condiciones, 'terminos', c.terminos) ORDER BY v.variante), '[]')
      FROM public.presupuestos_versiones v
      LEFT JOIN public.presupuestos_configuracion c ON c.id = v.configuracion_id
      WHERE v.presupuesto_id = v_p.id AND v.activo
        AND CASE WHEN v_p.estado = 'aprobado' THEN v.id = v_p.version_aprobada_id ELSE v.estado = 'publicado' END));
END;
$$;
