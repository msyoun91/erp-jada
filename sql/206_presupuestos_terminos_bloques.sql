-- Términos generales en bloques ("1. Colocación", "2. Forma de pago"): cada versión elige cuáles van, todos por defecto.
-- Sigue a sql/205. Decisión: decisiones/presupuestos.md → *Términos y condiciones*. Esquema: db_schema/presupuestos.md.
-- Test: sql/tests/presupuestos_terminos.sql.

-- ============================================================
-- 1. Los bloques: [{id, titulo, texto}], en orden
-- ============================================================
-- Hasta 30, cada uno con id, título (1–100) y texto (1–3000) sin espacios a los lados; ni id ni título repetidos. El CHECK la
-- corre con los permisos de quien escribe: `authenticated` necesita EXECUTE.
CREATE OR REPLACE FUNCTION public.presupuestos_terminos_validos(p jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT jsonb_typeof(p) = 'array' AND jsonb_array_length(p) <= 30
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p) b
      WHERE jsonb_typeof(b) <> 'object'
         OR coalesce(b->>'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         OR coalesce(length(b->>'titulo'), 0) NOT BETWEEN 1 AND 100 OR btrim(b->>'titulo') <> b->>'titulo'
         OR coalesce(length(b->>'texto'), 0) NOT BETWEEN 1 AND 3000 OR btrim(b->>'texto') <> b->>'texto')
    AND (SELECT count(DISTINCT b->>'id') = count(*) AND count(DISTINCT lower(b->>'titulo')) = count(*)
         FROM jsonb_array_elements(p) b);
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_terminos_validos(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_terminos_validos(jsonb) TO authenticated;

ALTER TABLE public.presupuestos_configuracion DROP CONSTRAINT IF EXISTS presupuestos_configuracion_terminos_check;
ALTER TABLE public.presupuestos_configuracion
  ALTER COLUMN terminos TYPE jsonb USING CASE WHEN terminos IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(jsonb_build_object(
    'id', gen_random_uuid(), 'titulo', 'Términos y condiciones', 'texto', terminos)) END,
  ALTER COLUMN terminos SET DEFAULT '[]',
  ALTER COLUMN terminos SET NOT NULL,
  ADD CONSTRAINT presupuestos_configuracion_terminos_check CHECK (public.presupuestos_terminos_validos(terminos));

-- Los que el vendedor sacó de esta versión. Un id que ya no está en la configuración no hace nada.
ALTER TABLE public.presupuestos_versiones
  ADD COLUMN IF NOT EXISTS terminos_fuera uuid[] NOT NULL DEFAULT '{}'
  CHECK (array_position(terminos_fuera, NULL) IS NULL);

GRANT INSERT (terminos_fuera), UPDATE (terminos_fuera) ON public.presupuestos_versiones TO authenticated;

-- ============================================================
-- 2. Configurar: el bloque nuevo recibe su id acá
-- ============================================================
DROP FUNCTION IF EXISTS public.presupuestos_configurar(numeric, integer, text, public.moneda[]);
CREATE OR REPLACE FUNCTION public.presupuestos_configurar(p_tope numeric, p_plazo integer, p_terminos jsonb,
                                                          p_monedas public.moneda[] DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_monedas public.moneda[];
  v_terminos jsonb;
BEGIN
  IF NOT public.tiene_permiso('presupuestos_configuracion') THEN
    RAISE EXCEPTION 'Sin permiso para configurar Presupuestos' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_terminos) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Los términos van en una lista de bloques' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', coalesce(nullif(b->>'id', ''), gen_random_uuid()::text),
           'titulo', btrim(b->>'titulo'), 'texto', btrim(b->>'texto')) ORDER BY n), '[]')
  INTO v_terminos
  FROM jsonb_array_elements(p_terminos) WITH ORDINALITY t(b, n);

  SELECT c.monedas_referencia INTO v_monedas FROM public.presupuestos_configuracion c WHERE c.activo;
  UPDATE public.presupuestos_configuracion SET activo = false WHERE activo;
  INSERT INTO public.presupuestos_configuracion (id, tope_descuento, plazo_dias, monedas_referencia, terminos)
  VALUES (v_id, p_tope, p_plazo, coalesce(p_monedas, v_monedas, '{ARS,USD_OFICIAL}'), v_terminos);
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer, jsonb, public.moneda[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer, jsonb, public.moneda[]) TO authenticated;

-- ============================================================
-- 3. Los bloques de una versión: los que regían al publicar; abierta, los vigentes
-- ============================================================
-- Todos, en orden, con `incluido`. La regla de cuáles ve el cliente vive acá: el editor, el impreso y la copia la leen.
CREATE OR REPLACE FUNCTION public.presupuestos_version_terminos(p_version uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(b || jsonb_build_object('incluido', NOT ((b->>'id')::uuid = ANY (v.terminos_fuera))) ORDER BY n), '[]')
  FROM public.presupuestos_versiones v
  JOIN public.presupuestos_configuracion c
    ON c.id = v.configuracion_id OR (v.configuracion_id IS NULL AND v.estado IN ('borrador', 'en_revision') AND c.activo)
  CROSS JOIN LATERAL jsonb_array_elements(c.terminos) WITH ORDINALITY t(b, n)
  WHERE v.id = p_version;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_terminos(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_terminos(uuid) TO authenticated;

-- ============================================================
-- 4. Los bloques que se sacan, solo en borrador; copiar los lleva
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

  IF (NEW.variante_nombre, NEW.iva_discriminado, NEW.descuento, NEW.condiciones, NEW.terminos_fuera)
       IS DISTINCT FROM (OLD.variante_nombre, OLD.iva_discriminado, OLD.descuento, OLD.condiciones, OLD.terminos_fuera)
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
                                             condiciones, terminos_fuera)
  VALUES (v_id, v_d.presupuesto_id,
          CASE WHEN p_variante_nueva THEN (SELECT max(v.variante) + 1 FROM public.presupuestos_versiones v
                                           WHERE v.presupuesto_id = v_d.presupuesto_id)
               ELSE v_d.variante END,
          CASE WHEN p_variante_nueva THEN NULL ELSE v_d.variante_nombre END,
          v_d.iva_discriminado, v_d.descuento, p_desde, v_d.condiciones, v_d.terminos_fuera);

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
-- 5. La copia del portal lleva solo los bloques incluidos
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
                                || jsonb_build_object('condiciones', v.condiciones, 'terminos', (
                                     SELECT coalesce(jsonb_agg(b - 'incluido' ORDER BY n), '[]')
                                     FROM jsonb_array_elements(public.presupuestos_version_terminos(v.id)) WITH ORDINALITY t(b, n)
                                     WHERE (b->>'incluido')::boolean))
                                ORDER BY v.variante), '[]')
      FROM public.presupuestos_versiones v
      WHERE v.presupuesto_id = v_p.id AND v.activo
        AND CASE WHEN v_p.estado = 'aprobado' THEN v.id = v_p.version_aprobada_id ELSE v.estado = 'publicado' END));
END;
$$;
