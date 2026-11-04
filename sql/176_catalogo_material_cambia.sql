-- Catálogo: cambiar el tipo de un material o a quién sigue saca las opciones que dejan de aplicar (AUDITORIA_CATALOGO.md, hallazgo 9).
-- Decisiones: decisiones/catalogo/versiones.md → Cambiar el tipo de un material o a quién sigue. Esquema: db_schema/catalogo.md.
-- Test: sql/tests/catalogo_segun.sql.

-- Un único no tiene opciones, y una pareja solo vale si su opción es del material que se sigue. Las sueltas no son pareja de nadie:
-- quedan. Sacarlas pasa por catalogo_contenido_baja, que saca también sus parejas, condiciones y valores.
CREATE OR REPLACE FUNCTION public.catalogo_material_cambia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.catalogo_opciones o SET activo = false
  WHERE o.material_id = NEW.id AND o.activo AND (NEW.tipo = 'unico' OR (
    o.sigue_opcion_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.catalogo_opciones s
      WHERE s.id = o.sigue_opcion_id AND s.material_id = NEW.sigue_material_id)));
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER catalogo_material_cambia AFTER UPDATE OF tipo, sigue_material_id ON public.catalogo_materiales
  FOR EACH ROW WHEN (NEW.activo AND (NEW.tipo IS DISTINCT FROM OLD.tipo OR NEW.sigue_material_id IS DISTINCT FROM OLD.sigue_material_id))
  EXECUTE FUNCTION public.catalogo_material_cambia();

REVOKE EXECUTE ON FUNCTION public.catalogo_material_cambia() FROM PUBLIC, anon, authenticated;
