-- Catálogo: el nombre de un color que ofrece una versión enviada y el de una categoría que un servicio en % usó quedan fijos (AUDITORIA_CATALOGO.md, hallazgo 13).
-- Decisiones: decisiones/catalogo/insumos.md → Las categorías siguen la misma regla; paquete.md → Los colores son una lista común. Test: sql/tests/catalogo_paquetes.sql y catalogo_registros.sql.

-- Toda la historia, no solo el valor vigente: revertir o reactivar devuelve las categorías de un valor anterior, ya con el nombre nuevo.
CREATE OR REPLACE FUNCTION public.catalogo_categorias_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.nombre <> OLD.nombre AND (
    EXISTS (SELECT 1 FROM public.catalogo_insumos i WHERE i.categoria_id = NEW.id)
    OR EXISTS (SELECT 1 FROM public.catalogo_versiones v WHERE v.categoria_id = NEW.id AND v.enviada)
    OR EXISTS (SELECT 1 FROM public.catalogo_porcentajes_valores pv WHERE NEW.id = ANY (pv.categorias))
  ) THEN
    RAISE EXCEPTION 'La categoría % ya se usa: su nombre queda fijo', OLD.nombre
      USING ERRCODE = 'CA006';
  END IF;
  IF OLD.activo AND NOT NEW.activo AND (
    EXISTS (SELECT 1 FROM public.catalogo_insumos i WHERE i.categoria_id = NEW.id AND i.activo)
    OR EXISTS (
      SELECT 1 FROM public.catalogo_versiones v
      JOIN public.catalogo_paquetes p ON p.id = v.paquete_id
      WHERE v.categoria_id = NEW.id AND v.estado = 'publicado' AND p.activo)
  ) THEN
    RAISE EXCEPTION 'La categoría % tiene registros activos adentro: no se puede dar de baja', OLD.nombre
      USING ERRCODE = 'CA007';
  END IF;
  RETURN NEW;
END;
$$;

-- SECURITY DEFINER, como el de categorías: quien tiene `catalogo_cargar` puede no tener la vista Paquetes, y con RLS no vería la versión.
CREATE OR REPLACE FUNCTION public.catalogo_colores_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.nombre <> OLD.nombre AND (
    EXISTS (SELECT 1 FROM public.catalogo_variantes v WHERE v.color_id = NEW.id)
    OR EXISTS (
      SELECT 1 FROM public.catalogo_versiones_colores vc
      JOIN public.catalogo_versiones v ON v.id = vc.version_id
      WHERE vc.color_id = NEW.id AND vc.activo AND v.enviada)
  ) THEN
    RAISE EXCEPTION 'El color % ya se usa: su nombre queda fijo', OLD.nombre USING ERRCODE = 'CA006';
  END IF;
  IF OLD.activo AND NOT NEW.activo AND EXISTS (
    SELECT 1 FROM public.catalogo_variantes v WHERE v.color_id = NEW.id AND v.activo
  ) THEN
    RAISE EXCEPTION 'El color % tiene variantes activas: no se puede dar de baja', OLD.nombre
      USING ERRCODE = 'CA007';
  END IF;
  RETURN NEW;
END;
$$;
