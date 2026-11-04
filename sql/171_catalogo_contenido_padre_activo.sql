-- Catálogo: nada entra ni se apunta a lo que ya se sacó del borrador (AUDITORIA_CATALOGO.md, hallazgo 2).
-- Decisiones: decisiones/catalogo/versiones.md → Lo que nunca tiene sentido se frena al guardar. Esquema: db_schema/catalogo.md.
-- Test: sql/tests/catalogo_paquetes.sql. La función es la de sql/160 con este cambio; el resto sigue igual.

-- FOR SHARE sobre la versión: enviar la versión (sql/162) la toma FOR UPDATE, así no entra una edición en medio. Quien no
-- tiene catalogo_armar no llega a verla: sigue de largo y lo frena RLS, con su 42501.
-- FOR SHARE sobre el padre: si se está sacando, espera y ve cómo quedó; si entra primero, la cascada de la baja ya lo ve. Solo
-- al cambiar a quién apunta: una edición común no lo toma, porque cruzada con la cascada daría un deadlock.
CREATE OR REPLACE FUNCTION public.catalogo_contenido_validar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_estado estado_version_catalogo;
  v_nuevo jsonb := to_jsonb(NEW);
  v_viejo jsonb := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE '{}'::jsonb END;
  v_activo boolean;
  r record;
BEGIN
  SELECT v.estado INTO v_estado FROM public.catalogo_versiones v WHERE v.id = NEW.version_id FOR SHARE;
  IF v_estado <> 'borrador' THEN
    RAISE EXCEPTION 'Esta versión ya no está en borrador: no se edita' USING ERRCODE = 'CA012';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.activo AND NOT OLD.activo THEN
    RAISE EXCEPTION 'Lo que se sacó de un borrador no vuelve: cargalo de nuevo' USING ERRCODE = 'CA015';
  END IF;
  IF NEW.activo THEN
    FOR r IN
      SELECT p.columna, p.tabla
      FROM (VALUES ('pieza_id', 'catalogo_piezas'), ('requiere_pieza_id', 'catalogo_piezas'),
                   ('material_id', 'catalogo_materiales'), ('sigue_material_id', 'catalogo_materiales'),
                   ('segun_material_id', 'catalogo_materiales'), ('opcion_id', 'catalogo_opciones'),
                   ('sigue_opcion_id', 'catalogo_opciones'), ('variable_id', 'catalogo_variables')) AS p(columna, tabla)
      WHERE v_nuevo->>p.columna IS NOT NULL AND v_nuevo->>p.columna IS DISTINCT FROM v_viejo->>p.columna
    LOOP
      EXECUTE format('SELECT x.activo FROM public.%I x WHERE x.id = $1 FOR SHARE', r.tabla)
        INTO v_activo USING (v_nuevo->>r.columna)::uuid;
      IF v_activo IS FALSE THEN
        RAISE EXCEPTION 'Eso ya se sacó de este borrador: recargá la página para ver cómo quedó' USING ERRCODE = 'CA025';
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
