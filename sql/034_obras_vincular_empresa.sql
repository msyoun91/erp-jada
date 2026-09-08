-- ============================================================
-- 034 — Agenda de Obras: la empresa entra a la obra con su gente
--
-- Pedido del usuario: al agregar una empresa a una obra, poder traer de una
-- vez a las personas de esa empresa. Por default vienen todas, y el rol en la
-- obra se elige persona por persona en el momento de agregarlas.
--
-- Dos funciones:
--
--   · `obras_personas_de_empresa` puebla la lista que se tilda. Devuelve
--     identidad mínima — nombre, apellido y cargo, nunca contacto — igual que
--     el buscador de personas: si devolviera solo las personas al alcance de
--     quien pregunta, la lista mostraría dos de las nueve que trabajan en la
--     constructora y el pedido no tendría sentido. Las que no son suyas
--     entran igual, y el trigger de sql/033 las deja pendientes.
--
--   · `obras_vincular_empresa` escribe el vínculo de la empresa y los de las
--     personas en una sola transacción. Es SECURITY INVOKER: la autoridad no
--     se mueve de las policies, que siguen exigiendo `obras_vincular` y que
--     la obra sea propia. Mismo criterio que `obras_guardar_referente`.
-- ============================================================

-- ============================================================
-- 1. La gente de una empresa
--
-- Las personas congeladas no se listan: no se pueden vincular (OB012), así
-- que ofrecerlas sería ofrecer un error.
--
-- `ya_en_obra` es lo que evita el choque con el unique parcial cuando alguien
-- ya estaba vinculado: la UI las muestra destildadas y explicadas.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_personas_de_empresa(
  p_empresa_id uuid,
  p_obra_id    uuid DEFAULT NULL
)
RETURNS TABLE (
  persona_id   uuid,
  nombre       text,
  apellido     text,
  cargo        text,
  es_principal boolean,
  es_mia       boolean,
  ya_en_obra   boolean
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_vincular') THEN
    RAISE EXCEPTION 'Sin permiso para vincular' USING ERRCODE = 'OB018';
  END IF;

  RETURN QUERY
  SELECT p.id, p.nombre, p.apellido, pe.cargo, pe.es_principal,
         p.creado_por = auth.uid(),
         p_obra_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM obras_obra_persona op
           WHERE op.obra_id = p_obra_id AND op.persona_id = p.id AND op.activo
         )
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id AND p.activo AND NOT p.pendiente
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
  ORDER BY pe.es_principal DESC, p.apellido NULLS LAST, p.nombre;
END;
$$;

-- ============================================================
-- 2. Vincular la empresa y su gente en una sola escritura
--
-- `p_personas` es [{"persona_id": uuid, "roles": ["compras", ...]}, ...].
-- Un rol vacío revienta contra el CHECK de cardinalidad, que es lo correcto:
-- la relación con la obra sin rol no significa nada. La UI y el schema Zod
-- lo piden antes de llegar acá.
--
-- ON CONFLICT DO NOTHING contra el unique parcial (obra_id, persona_id)
-- WHERE activo: si la persona ya estaba en la obra, se deja como está y no se
-- pisan sus roles con los que se eligieron para el lote.
--
-- Los contadores vuelven para que el toast pueda decir cuántas quedaron
-- esperando autorización — sin eso, "3 personas vinculadas" mentiría.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_vincular_empresa(
  p_obra_id       uuid,
  p_empresa_id    uuid,
  p_roles         rol_empresa[],
  p_observaciones text  DEFAULT NULL,
  p_personas      jsonb DEFAULT '[]'::jsonb
)
RETURNS TABLE (
  vinculo_id          uuid,
  vinculo_pendiente   boolean,
  personas_agregadas  int,
  personas_pendientes int
)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
DECLARE
  v_id        uuid;
  v_pendiente boolean;
  v_total     int := 0;
  v_esperando int := 0;
BEGIN
  INSERT INTO obras_obra_empresa (obra_id, empresa_id, roles, observaciones)
  VALUES (p_obra_id, p_empresa_id, p_roles, p_observaciones)
  RETURNING id, pendiente INTO v_id, v_pendiente;

  WITH agregadas AS (
    INSERT INTO obras_obra_persona (obra_id, persona_id, empresa_id, roles)
    SELECT p_obra_id,
           (x->>'persona_id')::uuid,
           p_empresa_id,
           ARRAY(SELECT jsonb_array_elements_text(x->'roles'))::rol_persona[]
    FROM jsonb_array_elements(coalesce(p_personas, '[]'::jsonb)) x
    ON CONFLICT (obra_id, persona_id) WHERE activo DO NOTHING
    RETURNING pendiente
  )
  SELECT count(*), count(*) FILTER (WHERE agregadas.pendiente)
  INTO v_total, v_esperando
  FROM agregadas;

  RETURN QUERY SELECT v_id, v_pendiente, v_total, v_esperando;
END;
$$;

-- ============================================================
-- 3. GRANTs — mismo criterio que sql/029
-- ============================================================
REVOKE EXECUTE ON FUNCTION obras_personas_de_empresa(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_vincular_empresa(uuid, uuid, rol_empresa[], text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION obras_personas_de_empresa(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_vincular_empresa(uuid, uuid, rol_empresa[], text, jsonb) TO authenticated;
