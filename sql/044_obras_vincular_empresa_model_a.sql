-- ============================================================
-- 044 — `obras_vincular_empresa` bajo model A
--
-- `sql/040` dropeó `pendiente` de `obras_obra_empresa` y `obras_obra_persona`,
-- y `obras_vincular_empresa` (sql/034) leía esa columna con `RETURNING ...
-- pendiente`. Además, bajo model A no se puede vincular una persona que no se
-- ve: el WITH CHECK nuevo de `obras_obra_persona_insert` lo rechaza con error
-- duro, no con conflicto.
--
-- CAMBIOS
--   - Sin `RETURNING pendiente`. La firma de salida se mantiene
--     (`vinculo_pendiente` / `personas_pendientes`) para no tocar `actions.ts`,
--     pero siempre valen false / 0: no hay estado pendiente de vínculo.
--   - Las personas del lote se filtran a las que el que vincula puede ver.
--     Las demás se saltean en silencio — la ficha de la empresa las muestra en
--     identidad mínima, pero para colgarlas de una obra hay que pedir acceso
--     primero.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_vincular_empresa(
  p_obra_id       uuid,
  p_empresa_id    uuid,
  p_roles         rol_empresa[],
  p_observaciones text DEFAULT NULL,
  p_personas      jsonb DEFAULT '[]'::jsonb
)
RETURNS TABLE (
  vinculo_id          uuid,
  vinculo_pendiente   boolean,
  personas_agregadas  integer,
  personas_pendientes integer
)
LANGUAGE plpgsql SET search_path = public
AS $$
DECLARE
  v_id    uuid;
  v_total int := 0;
BEGIN
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles, observaciones)
  VALUES (p_obra_id, p_empresa_id, p_roles, p_observaciones)
  RETURNING id INTO v_id;

  WITH agregadas AS (
    INSERT INTO obras_obra_persona (obra_id, persona_id, empresa_id, roles)
    SELECT p_obra_id,
           (x->>'persona_id')::uuid,
           p_empresa_id,
           ARRAY(SELECT jsonb_array_elements_text(x->'roles'))::rol_persona[]
    FROM jsonb_array_elements(coalesce(p_personas, '[]'::jsonb)) x
    WHERE obras_puede_ver_persona((x->>'persona_id')::uuid)
    ON CONFLICT (obra_id, persona_id) WHERE activo DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_total FROM agregadas;

  RETURN QUERY SELECT v_id, false, v_total, 0;
END;
$$;
