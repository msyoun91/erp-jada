-- ============================================================
-- 050 — obras_compartidos_por_mi(): el origen como (tipo, id, nombre)
--
-- La vista Compartido devolvía `origen` como texto ya formateado
-- ('directo' / 'obra: <nombre>' / 'empresa: <nombre>'). Para poder AGRUPAR en
-- la UI lo compartido en cascada bajo su obra/empresa padre hace falta el id
-- del padre, no una etiqueta. Se parte en tres columnas:
--
--   origen_tipo   text  -- NULL (directo) | 'obra' | 'empresa'
--   origen_id     uuid  -- id del padre, NULL si directo
--   origen_nombre text  -- nombre del padre, NULL si directo
--
-- El padre siempre está en el mismo resultado: obras_compartir_obra /
-- _empresa insertan el grant del padre para ese usuario antes de la cascada.
--
-- Solo cambia la firma de retorno de una función; el gate y el resto igual.
-- `ORDER BY` pasa a la posición 9 (compartida_el).
-- ============================================================

DROP FUNCTION IF EXISTS obras_compartidos_por_mi();

CREATE OR REPLACE FUNCTION obras_compartidos_por_mi()
RETURNS TABLE (
  tipo           text,
  entidad_id     uuid,
  entidad_nombre text,
  usuario_id     uuid,
  usuario_nombre text,
  origen_tipo    text,
  origen_id      uuid,
  origen_nombre  text,
  compartida_el  timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_compartido') THEN
    RAISE EXCEPTION 'Sin acceso a la vista Compartido' USING ERRCODE = 'OB027';
  END IF;

  RETURN QUERY
  SELECT 'obra'::text, c.obra_id, o.nombre, c.usuario_id, u.nombre,
         NULL::text, NULL::uuid, NULL::text, c.created_at
  FROM obras_obra_compartida c
  JOIN obras o     ON o.id = c.obra_id
  JOIN usuarios u  ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'empresa'::text, c.empresa_id, e.razon_social, c.usuario_id, u.nombre,
         CASE WHEN c.origen_obra_id IS NOT NULL THEN 'obra' END,
         c.origen_obra_id,
         CASE WHEN c.origen_obra_id IS NOT NULL
              THEN (SELECT nombre FROM obras WHERE id = c.origen_obra_id) END,
         c.created_at
  FROM obras_empresa_compartida c
  JOIN obras_empresas e ON e.id = c.empresa_id
  JOIN usuarios u       ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'persona'::text, c.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         c.usuario_id, u.nombre,
         CASE
           WHEN c.origen_obra_id    IS NOT NULL THEN 'obra'
           WHEN c.origen_empresa_id IS NOT NULL THEN 'empresa'
         END,
         coalesce(c.origen_obra_id, c.origen_empresa_id),
         CASE
           WHEN c.origen_obra_id IS NOT NULL
             THEN (SELECT nombre FROM obras WHERE id = c.origen_obra_id)
           WHEN c.origen_empresa_id IS NOT NULL
             THEN (SELECT razon_social FROM obras_empresas WHERE id = c.origen_empresa_id)
         END,
         c.created_at
  FROM obras_persona_compartida c
  JOIN obras_personas p ON p.id = c.persona_id
  JOIN usuarios u       ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  ORDER BY 9 DESC
  LIMIT 500;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_compartidos_por_mi() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_compartidos_por_mi() TO authenticated;
