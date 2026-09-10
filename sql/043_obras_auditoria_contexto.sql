-- ============================================================
-- 043 — Auditoría de accesos: de qué ficha se leyó el contacto
--
-- `sql/039` agregó `obras_accesos_persona.contexto` (`obra:<id>` / `empresa:<id>`
-- cuando el contacto se vio por grant contextual, NULL cuando fue acceso
-- directo a la ficha de la persona). Falta que la vista de Auditoría lo muestre.
--
-- Se resuelve al nombre de la obra/empresa acá y no en la UI: es el único lugar
-- donde `obras_accesos_persona` se convierte en texto, y `obras_auditoria_accesos`
-- ya es DEFINER con guard `obras_auditoria`.
-- ============================================================
-- Cambia la forma de salida (suma `contexto`): DROP primero.
DROP FUNCTION IF EXISTS obras_auditoria_accesos(integer);

CREATE OR REPLACE FUNCTION obras_auditoria_accesos(p_dias integer DEFAULT 30)
RETURNS TABLE (
  acceso_id  uuid,
  created_at timestamptz,
  usuario_id uuid,
  usuario    text,
  persona_id uuid,
  persona    text,
  contexto   text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_auditoria') THEN
    RAISE EXCEPTION 'Sin permiso para ver la auditoría' USING ERRCODE = 'OB010';
  END IF;

  RETURN QUERY
  SELECT a.id, a.created_at, a.usuario_id, u.nombre, a.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         CASE
           WHEN a.contexto LIKE 'obra:%' THEN
             (SELECT o.nombre FROM obras o WHERE o.id = substring(a.contexto from 6)::uuid)
           WHEN a.contexto LIKE 'empresa:%' THEN
             (SELECT e.razon_social FROM obras_empresas e WHERE e.id = substring(a.contexto from 9)::uuid)
         END
  FROM obras_accesos_persona a
  JOIN usuarios u ON u.id = a.usuario_id
  JOIN obras_personas p ON p.id = a.persona_id
  WHERE a.created_at >= now() - make_interval(days => greatest(p_dias, 1))
  ORDER BY a.created_at DESC
  LIMIT 500;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_auditoria_accesos(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_auditoria_accesos(integer) TO authenticated;
