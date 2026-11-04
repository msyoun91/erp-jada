-- Catálogo: las escrituras de dos pasos del editor pasan a la base (AUDITORIA_CATALOGO.md, hallazgo 4).
-- Decisiones: decisiones/catalogo/pantallas.md → Editor del borrador. Esquema: db_schema/catalogo.md.
-- Test: sql/tests/catalogo_paquetes.sql.

-- Corre dentro del mismo statement que marca la nueva: si esa fila no se puede guardar, la anterior sigue marcada.
-- Dos marcas a la vez las sigue frenando el índice único.
CREATE OR REPLACE FUNCTION public.catalogo_predeterminada_apagar()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  UPDATE public.catalogo_opciones
  SET predeterminada = false
  WHERE material_id = NEW.material_id AND predeterminada AND activo AND id <> NEW.id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_predeterminada_apagar BEFORE INSERT OR UPDATE OF predeterminada ON public.catalogo_opciones
  FOR EACH ROW WHEN (NEW.predeterminada AND NEW.activo) EXECUTE FUNCTION public.catalogo_predeterminada_apagar();

CREATE OR REPLACE FUNCTION public.catalogo_color_base_apagar()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  UPDATE public.catalogo_versiones_colores
  SET base = false
  WHERE version_id = NEW.version_id AND base AND activo AND id <> NEW.id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_color_base_apagar BEFORE INSERT OR UPDATE OF base ON public.catalogo_versiones_colores
  FOR EACH ROW WHEN (NEW.base AND NEW.activo) EXECUTE FUNCTION public.catalogo_color_base_apagar();

REVOKE ALL ON FUNCTION public.catalogo_predeterminada_apagar(), public.catalogo_color_base_apagar()
  FROM PUBLIC, anon, authenticated, service_role;

-- FOR UPDATE: dos altas a la vez se turnan, y la segunda ve la base de la primera. Quien no tiene catalogo_armar no llega a
-- tomarla: sigue de largo y lo frena RLS, con su 42501.
CREATE OR REPLACE FUNCTION public.catalogo_version_color_sumar(p_version uuid, p_color uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  PERFORM 1 FROM public.catalogo_versiones WHERE id = p_version FOR UPDATE;

  INSERT INTO public.catalogo_versiones_colores (version_id, color_id, base)
  VALUES (p_version, p_color, NOT EXISTS (
    SELECT 1 FROM public.catalogo_versiones_colores c WHERE c.version_id = p_version AND c.base AND c.activo));
END;
$$;

-- Con RLS, un UPDATE sin permiso no da error: no encuentra filas. Por eso se cuentan, y si falta alguna no queda nada.
CREATE OR REPLACE FUNCTION public.catalogo_contenido_ordenar(p_tabla text, p_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  v_filas int;
BEGIN
  IF p_tabla NOT IN ('catalogo_piezas', 'catalogo_variables', 'catalogo_materiales', 'catalogo_opciones') THEN
    RAISE EXCEPTION 'Esa tabla no se ordena' USING ERRCODE = '22023';
  END IF;

  EXECUTE format(
    'UPDATE public.%I t SET orden = x.pos - 1 FROM unnest($1) WITH ORDINALITY AS x (id, pos) WHERE t.id = x.id', p_tabla)
    USING p_ids;

  GET DIAGNOSTICS v_filas = ROW_COUNT;
  IF v_filas <> cardinality(p_ids) THEN
    RAISE EXCEPTION 'No se pudieron ordenar todas las filas' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.catalogo_version_color_sumar(uuid, uuid), public.catalogo_contenido_ordenar(text, uuid[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogo_version_color_sumar(uuid, uuid), public.catalogo_contenido_ordenar(text, uuid[])
  TO authenticated;
