-- Catálogo: lo que la unidad del insumo no usa no se guarda. Al cambiar un vidrio por un perfil, su ancho y su alto se borran.
-- Decisiones: decisiones/catalogo/pantallas.md. Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_medidas.sql.

-- Corre antes que las columnas generadas: una fórmula que se borra acá no llega a parsearse.
-- Sin insumo (un múltiple, una opción "ninguna") no hay unidad y no se toca nada.
CREATE OR REPLACE FUNCTION public.catalogo_medidas_limpiar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_unidad unidad_insumo;
BEGIN
  SELECT i.unidad INTO v_unidad FROM public.catalogo_insumos i WHERE i.id = NEW.insumo_id;
  IF v_unidad = 'm2' THEN
    NEW.medida := NULL;
  ELSIF v_unidad IS NOT NULL THEN
    NEW.ancho := NULL;
    NEW.alto := NULL;
    NEW.area := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_medidas_limpiar BEFORE INSERT OR UPDATE ON public.catalogo_materiales
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_medidas_limpiar();
CREATE OR REPLACE TRIGGER catalogo_medidas_limpiar BEFORE INSERT OR UPDATE ON public.catalogo_opciones
  FOR EACH ROW EXECUTE FUNCTION public.catalogo_medidas_limpiar();

REVOKE ALL ON FUNCTION public.catalogo_medidas_limpiar() FROM PUBLIC, anon, authenticated, service_role;
