-- ============================================================
-- 048 — Fix: `obras_relaciones_compartibles_obra` / `_empresa` (sql/047)
--        tiraban 42702 "column reference \"id\" is ambiguous"
--
-- Las dos declaran `RETURNS TABLE (..., id uuid, ...)`, así que `id` es una
-- variable plpgsql. El guard hacía `SELECT 1 FROM obras WHERE id = p_obra_id`
-- (idem `obras_empresas`): Postgres no sabe si `id` es la columna o el OUT
-- param y aborta la función entera al planear. El checklist "Compartir
-- también" del panel nunca se poblaba porque la RPC fallaba siempre.
--
-- Fix mínimo: calificar la columna en el guard. El resto ya venía aliaseado.
-- ============================================================

CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_obra(
  p_obra_id uuid, p_usuario_id uuid
)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text, ya_compartida boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id AND o.responsable_id = auth.uid() AND o.activo
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, e.id, e.razon_social,
         nullif(array_to_string(oe.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_empresa_compartida c
                 WHERE c.empresa_id = e.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo
  UNION ALL
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         nullif(array_to_string(op.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_persona_compartida c
                 WHERE c.persona_id = p.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente;
END;
$$;

CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_empresa(
  p_empresa_id uuid, p_usuario_id uuid
)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text, ya_compartida boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras_empresas e
    WHERE e.id = p_empresa_id AND e.creado_por = auth.uid() AND e.activo
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
  END IF;

  RETURN QUERY
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         nullif(pe.cargo, ''),
         EXISTS (SELECT 1 FROM obras_persona_compartida c
                 WHERE c.persona_id = p.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente;
END;
$$;
