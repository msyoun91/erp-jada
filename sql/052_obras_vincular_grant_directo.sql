-- sql/052 — Tapar el hueco: un contacto compartido VÍA obra/empresa (checklist)
-- no habilita a vincularlo a las obras propias del receptor. Solo el share
-- DIRECTO lo hace, y al revocarlo la cascada arrastra esos vínculos.
--
-- Contexto (decisiones/obras.md → "El grant heredado de obra ve, no reparte"):
--
--   `obras_compartir_obra` / `obras_compartir_empresa` tildando el checklist
--   escriben `obras_persona_compartida` / `obras_empresa_compartida` COMPLETO,
--   solo con `origen_obra_id` seteado. `obras_puede_ver_persona` /
--   `_ver_empresa` no miran `origen_*`, así que ese grant pasaba el WITH CHECK
--   de `obras_obra_persona_insert` / `_empresa_insert` igual que un share
--   directo: el receptor podía sumar el contacto a SU cartera de obras.
--
--   Regla nueva: para colgar un contacto de una obra PROPIA hace falta que el
--   contacto sea del receptor — dueño, `_todas`, o grant DIRECTO
--   (`origen_obra_id IS NULL`). El grant con origen solo abre la ficha dentro
--   de la obra que lo trajo (vía `obras_ficha_persona` con contexto).
--
--   La rama de obra COMPARTIDA no cambia: ahí ya se exigía `creado_por = yo`.
--
-- Además: `obras_revocar_persona` / `_empresa` ganan la cascada que
-- `obras_revocar_obra` ya tenía (sql/051) — al sacar el share directo, los
-- vínculos que el receptor armó con ese contacto en sus obras se desactivan —
-- y un contador para que el panel avise antes.

-- ============================================================
-- 1. Helpers — ¿tengo un grant DIRECTO sobre este contacto?
--
-- DEFINER como `obras_persona_compartida_conmigo` (sql/051): un EXISTS inline
-- en la policy podría recursar contra la policy de `obras_*_compartida`.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_persona_grant_directo(p_persona_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_persona_compartida c
    WHERE c.persona_id = p_persona_id AND c.usuario_id = auth.uid() AND c.activo
      AND c.origen_obra_id IS NULL AND c.origen_empresa_id IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION obras_empresa_grant_directo(p_empresa_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_empresa_compartida c
    WHERE c.empresa_id = p_empresa_id AND c.usuario_id = auth.uid() AND c.activo
      AND c.origen_obra_id IS NULL
  );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_persona_grant_directo(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_empresa_grant_directo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_persona_grant_directo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_empresa_grant_directo(uuid) TO authenticated;

-- ============================================================
-- 2. INSERT de vínculo — la rama "mi obra" exige que el contacto sea mío
-- ============================================================
DROP POLICY IF EXISTS obras_obra_persona_insert ON obras_obra_persona;
CREATE POLICY obras_obra_persona_insert ON obras_obra_persona FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_vincular')
    AND obras_puede_ver_persona(persona_id)
    AND (
      (
        obras_es_mi_obra(obra_id)
        AND (
          EXISTS (
            SELECT 1 FROM obras_personas p
            WHERE p.id = obras_obra_persona.persona_id AND p.creado_por = auth.uid()
          )
          OR obras_persona_grant_directo(persona_id)
          OR tiene_permiso('obras_personas_todas')
        )
      )
      OR (
        obras_obra_compartida_conmigo(obra_id)
        AND EXISTS (
          SELECT 1 FROM obras_personas p
          WHERE p.id = obras_obra_persona.persona_id AND p.creado_por = auth.uid()
        )
      )
    )
  );

DROP POLICY IF EXISTS obras_obra_empresa_insert ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_insert ON obras_obra_empresa FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_vincular')
    AND obras_puede_ver_empresa(empresa_id)
    AND (
      (
        obras_es_mi_obra(obra_id)
        AND (
          EXISTS (
            SELECT 1 FROM obras_empresas e
            WHERE e.id = obras_obra_empresa.empresa_id AND e.creado_por = auth.uid()
          )
          OR obras_empresa_grant_directo(empresa_id)
          OR tiene_permiso('obras_empresas_todas')
        )
      )
      OR (
        obras_obra_compartida_conmigo(obra_id)
        AND EXISTS (
          SELECT 1 FROM obras_empresas e
          WHERE e.id = obras_obra_empresa.empresa_id AND e.creado_por = auth.uid()
        )
      )
    )
  );

-- ============================================================
-- 3. Revocar el share directo arrastra los vínculos del receptor
--
-- Misma regla que `obras_revocar_obra` (sql/051): vincular no es compartir. El
-- trigger `cascada_desactivar` (sql/036) baja los referentes de las personas.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_revocar_persona(p_persona_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras_personas p WHERE p.id = p_persona_id AND p.creado_por = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la persona puede revocar el acceso' USING ERRCODE = 'OB020';
  END IF;

  UPDATE obras_persona_compartida
    SET activo = false, updated_at = now()
    WHERE persona_id = p_persona_id AND usuario_id = p_usuario_id AND activo;

  -- El grant contextual también cae: si le sacan la ficha, no hay contexto que
  -- la sostenga.
  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE persona_id = p_persona_id AND usuario_id = p_usuario_id AND activo;

  -- Los vínculos que el receptor armó con esta persona en SUS obras se caen
  -- con el acceso.
  UPDATE obras_obra_persona
    SET activo = false, updated_at = now()
    WHERE persona_id = p_persona_id AND creado_por = p_usuario_id AND activo;
END;
$$;

CREATE OR REPLACE FUNCTION obras_revocar_empresa(p_empresa_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras_empresas e WHERE e.id = p_empresa_id AND e.creado_por = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la empresa puede revocar el acceso' USING ERRCODE = 'OB020';
  END IF;

  UPDATE obras_empresa_compartida
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND usuario_id = p_usuario_id AND activo;

  UPDATE obras_obra_empresa
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND creado_por = p_usuario_id AND activo;
END;
$$;

-- ============================================================
-- 4. Contadores para el aviso previo — gate: dueño del contacto
-- ============================================================
CREATE OR REPLACE FUNCTION obras_contar_vinculos_persona_receptor(p_persona_id uuid, p_usuario_id uuid)
RETURNS integer LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT (
    SELECT count(*) FROM public.obras_obra_persona
    WHERE persona_id = p_persona_id AND creado_por = p_usuario_id AND activo
  )::integer
  WHERE EXISTS (
    SELECT 1 FROM public.obras_personas p
    WHERE p.id = p_persona_id AND p.creado_por = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION obras_contar_vinculos_empresa_receptor(p_empresa_id uuid, p_usuario_id uuid)
RETURNS integer LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT (
    SELECT count(*) FROM public.obras_obra_empresa
    WHERE empresa_id = p_empresa_id AND creado_por = p_usuario_id AND activo
  )::integer
  WHERE EXISTS (
    SELECT 1 FROM public.obras_empresas e
    WHERE e.id = p_empresa_id AND e.creado_por = auth.uid()
  );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_contar_vinculos_persona_receptor(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_contar_vinculos_empresa_receptor(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_contar_vinculos_persona_receptor(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_contar_vinculos_empresa_receptor(uuid, uuid) TO authenticated;

-- ============================================================
-- 5. obras_vincular_empresa — el filtro de personas del lote sigue a la RLS
--
-- sql/044 filtraba las personas del lote por `obras_puede_ver_persona`. Ahora
-- colgar un contacto de una obra pide que sea mío (regla de arriba), que es más
-- estricto que verlo: una persona compartida pasaba el filtro y después
-- reventaba el WITH CHECK, abortando el INSERT...SELECT entero. El filtro pasa
-- a `creado_por = auth.uid()` — la intersección de lo que aceptan las dos ramas
-- del insert. Las demás se saltean en silencio, igual que antes (la ficha de la
-- empresa las muestra en identidad mínima; para colgarlas hay que pedir acceso).
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
    WHERE EXISTS (
      SELECT 1 FROM obras_personas p
      WHERE p.id = (x->>'persona_id')::uuid AND p.creado_por = auth.uid()
    )
    ON CONFLICT (obra_id, persona_id) WHERE activo DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_total FROM agregadas;

  RETURN QUERY SELECT v_id, false, v_total, 0;
END;
$$;
