-- Catálogo: las opciones de un material van todas en la misma unidad. La primera la fija; se puede cambiar cuando queda sola.
-- Decisiones: decisiones/catalogo/paquete.md. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_medidas.sql.

-- El bloqueo evita que dos opciones de distinta unidad entren a la vez sin verse.
CREATE OR REPLACE FUNCTION public.catalogo_opciones_misma_unidad()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_unidad unidad_insumo;
BEGIN
  IF NOT NEW.activo OR NEW.insumo_id IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM 1 FROM public.catalogo_materiales m WHERE m.id = NEW.material_id FOR UPDATE;

  SELECT i.unidad INTO v_unidad
  FROM public.catalogo_opciones o
  JOIN public.catalogo_insumos i ON i.id = o.insumo_id
  WHERE o.material_id = NEW.material_id AND o.activo AND o.id <> NEW.id
    AND i.unidad <> (SELECT n.unidad FROM public.catalogo_insumos n WHERE n.id = NEW.insumo_id)
  LIMIT 1;

  IF v_unidad IS NOT NULL THEN
    RAISE EXCEPTION 'Las opciones de un material van en la misma unidad: este va en %', v_unidad USING ERRCODE = 'CA024';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_opciones_misma_unidad BEFORE INSERT OR UPDATE OF insumo_id ON public.catalogo_opciones
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_opciones_misma_unidad();

REVOKE ALL ON FUNCTION public.catalogo_opciones_misma_unidad() FROM PUBLIC, anon, authenticated, service_role;
