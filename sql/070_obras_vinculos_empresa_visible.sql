-- ============================================================
-- 070 — La empresa de una persona en la obra la ve quien ve la empresa
--
-- `obras_vinculos_de_obra` (sql/051) es DEFINER para que el responsable lea el
-- nombre de lo que sumó un receptor. La rama de persona resolvía `detalle`
-- (la razón social de `obras_obra_persona.empresa_id`) con un subselect sin
-- filtro: el receptor al que le tildaron la persona pero no su empresa leía
-- igual el nombre de la empresa. La ficha de la persona ya la ocultaba (el
-- embed pasa por la RLS de `obras_empresas`), así que el mismo dato salía en
-- una ficha y no en la otra.
--
-- Ahora `detalle` sale solo si quien pregunta es el responsable, tiene
-- `obras_transferir` (los dos ya ven todos los vínculos) o ve la empresa
-- (`obras_puede_ver_empresa`: dueño, grant completo o `obras_empresas_todas`).
-- La fila de la persona no cambia.
--
-- `empresa_id` sigue saliendo. El receptor que vinculó su persona con una
-- empresa tildada puede editar ese vínculo después de que el dueño la
-- destilde: con el id en NULL el panel mandaría NULL y borraría la empresa
-- guardada. Un uuid suelto no vale nada (exposición ya aceptada en sql/062).
--
-- Sin rama de `creado_por`: ese mismo receptor deja de ver el nombre, igual
-- que en la sección Empresas.
--
-- Firma y GRANT iguales (CREATE OR REPLACE los conserva).
--
-- Ver decisiones/obras/visibilidad.md → "La empresa de una persona en la obra
-- la ve quien ve la empresa".
-- ============================================================
CREATE OR REPLACE FUNCTION obras_vinculos_de_obra(p_obra_id uuid)
RETURNS TABLE (
  tipo              text,
  vinculo_id        uuid,
  entidad_id        uuid,
  nombre            text,
  detalle           text,
  roles             text[],
  observaciones     text,
  empresa_id        uuid,
  creado_por        uuid,
  creado_por_nombre text,
  es_de_receptor    boolean
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT obras_puede_ver_obra(p_obra_id) THEN
    RAISE EXCEPTION 'Sin acceso a esta obra' USING ERRCODE = 'OB022';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, oe.id, e.id, e.razon_social, NULL::text,
         oe.roles::text[], oe.observaciones, NULL::uuid,
         oe.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, oe.creado_por)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  JOIN usuarios u       ON u.id = oe.creado_por
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND (
      oe.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_empresa_compartida_conmigo(oe.empresa_id))
    )

  UNION ALL
  SELECT 'persona'::text, op.id, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         CASE WHEN vis.empresa_visible THEN e2.razon_social END,
         op.roles::text[], op.observaciones, op.empresa_id,
         op.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, op.creado_por)
  FROM obras_obra_persona op
  JOIN obras_personas p       ON p.id = op.persona_id
  JOIN usuarios u             ON u.id = op.creado_por
  LEFT JOIN obras_empresas e2 ON e2.id = op.empresa_id
  CROSS JOIN LATERAL (
    SELECT op.empresa_id IS NOT NULL
       AND (obras_es_mi_obra(p_obra_id)
            OR tiene_permiso('obras_transferir')
            OR obras_puede_ver_empresa(op.empresa_id)) AS empresa_visible
  ) vis
  WHERE op.obra_id = p_obra_id AND op.activo
    AND (
      op.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_persona_compartida_conmigo(op.persona_id))
    );
END;
$$;
