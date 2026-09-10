-- ============================================================
-- 041 — Agenda de Obras: transferir también personas y empresas
--
-- Bajo model A una entidad privada cuyo dueño se va queda huérfana (solo la ve
-- `obras_personas_todas` / `obras_empresas_todas`). Faltaba el camino de
-- reasignarla, que las obras ya tenían.
--
-- FUNCIONES SEPARADAS, UNA POR ENTIDAD — pedido del usuario. No un
-- `obras_transferir` genérico: cada entidad tiene su gate propio (ver-todas =
-- ver + transferir, mismo criterio que `obras_transferir` con las obras).
--
--   obras_transferir(obra, a, contactos_exclusivos[])  gate obras_transferir
--   obras_transferir_persona(persona, a)               gate obras_personas_todas
--   obras_transferir_empresa(empresa, a, personas[])    gate obras_empresas_todas
--
-- CASCADA CON CONFIRMACIÓN
--
-- Al transferir una obra/empresa, lo vinculado que el dueño saliente posee y
-- que está SOLO en esa obra/empresa puede moverse de dueño con ella. Lo demás
-- —vinculado también en otro lado— recibe grant contextual (el contacto se ve
-- solo en esa ficha) y el ownership no se mueve. Lo que al saliente se lo
-- compartió otro no cascadea.
--
-- El cliente pide `obras_contactos_exclusivos_de_*` para armar el checklist; lo
-- tildado viaja en el array y se mueve de dueño, lo no tildado queda como grant
-- contextual.
--
-- `obras_transferencias` gana `tipo` y `persona_id` / `empresa_id` (nullable).
-- `obra_id` pasa a nullable. El trigger de notificación (sql/038) solo dispara
-- para `tipo = 'obra'` — no hay tipo de notificación para persona/empresa y
-- agregarlo toca infra compartida; el receptor las encuentra en su agenda.
-- (ponytail: aviso de transferencia de persona/empresa, si alguien lo pide.)
-- ============================================================

-- ============================================================
-- 1. `obras_transferencias` — log de las tres
-- ============================================================
ALTER TABLE obras_transferencias
  ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'obra',
  ADD COLUMN IF NOT EXISTS persona_id uuid REFERENCES obras_personas(id),
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES obras_empresas(id);

ALTER TABLE obras_transferencias ALTER COLUMN obra_id DROP NOT NULL;

ALTER TABLE obras_transferencias DROP CONSTRAINT IF EXISTS transferencia_tipo_ancla;
ALTER TABLE obras_transferencias ADD CONSTRAINT transferencia_tipo_ancla CHECK (
  (tipo = 'obra'    AND obra_id    IS NOT NULL AND persona_id IS NULL AND empresa_id IS NULL) OR
  (tipo = 'persona' AND persona_id IS NOT NULL AND obra_id    IS NULL AND empresa_id IS NULL) OR
  (tipo = 'empresa' AND empresa_id IS NOT NULL AND obra_id    IS NULL AND persona_id IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_obras_transferencias_persona ON obras_transferencias (persona_id);
CREATE INDEX IF NOT EXISTS idx_obras_transferencias_empresa ON obras_transferencias (empresa_id);

-- El que dio y el que recibió pueden ver su propia fila aunque ya no vean la
-- entidad; para obras sigue mandando `obras_puede_ver_obra`.
DROP POLICY IF EXISTS obras_transferencias_select ON obras_transferencias;
CREATE POLICY obras_transferencias_select ON obras_transferencias FOR SELECT
  USING (
    de_usuario_id = auth.uid()
    OR a_usuario_id = auth.uid()
    OR (obra_id IS NOT NULL AND obras_puede_ver_obra(obra_id))
  );

-- El trigger de aviso (sql/038) solo tiene sentido para obra.
DROP TRIGGER IF EXISTS trg_notificar_transferencia_obra ON obras_transferencias;
CREATE TRIGGER trg_notificar_transferencia_obra
  AFTER INSERT ON obras_transferencias
  FOR EACH ROW WHEN (NEW.tipo = 'obra')
  EXECUTE FUNCTION notificar_transferencia_obra();

-- ============================================================
-- 2. Contactos exclusivos — para el checklist de confirmación
--
-- "Exclusivo a esta obra" = vinculado a ella y a ninguna otra obra. La
-- pertenencia a una empresa (`obras_persona_empresa`) no cuenta como otra obra.
-- Se filtra por el dueño ACTUAL de la entidad, no por `auth.uid()`: así el
-- admin que transfiere una obra ajena ve la misma lista que vería su
-- responsable.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_contactos_exclusivos_de_obra(p_obra_id uuid)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
DECLARE
  v_duenio uuid;
BEGIN
  IF NOT tiene_permiso('obras_transferir') THEN
    RAISE EXCEPTION 'Sin permiso para transferir obras' USING ERRCODE = 'OB003';
  END IF;

  SELECT responsable_id INTO v_duenio FROM obras WHERE id = p_obra_id AND activo;
  IF v_duenio IS NULL THEN
    RAISE EXCEPTION 'Obra inexistente o desactivada' USING ERRCODE = 'OB004';
  END IF;

  RETURN QUERY
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         array_to_string(op.roles::text[], ', ')
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = v_duenio AND p.activo
    AND NOT EXISTS (
      SELECT 1 FROM obras_obra_persona op2
      WHERE op2.persona_id = op.persona_id AND op2.activo AND op2.obra_id <> p_obra_id
    )
  UNION ALL
  SELECT 'empresa'::text, e.id, e.razon_social,
         array_to_string(oe.roles::text[], ', ')
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = v_duenio AND e.activo
    AND NOT EXISTS (
      SELECT 1 FROM obras_obra_empresa oe2
      WHERE oe2.empresa_id = oe.empresa_id AND oe2.activo AND oe2.obra_id <> p_obra_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION obras_contactos_exclusivos_de_empresa(p_empresa_id uuid)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
DECLARE
  v_duenio uuid;
BEGIN
  IF NOT tiene_permiso('obras_empresas_todas') THEN
    RAISE EXCEPTION 'Sin permiso para transferir empresas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_duenio FROM obras_empresas WHERE id = p_empresa_id AND activo;
  IF v_duenio IS NULL THEN
    RAISE EXCEPTION 'Empresa inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  RETURN QUERY
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         pe.cargo
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
    AND p.creado_por = v_duenio AND p.activo
    AND NOT EXISTS (
      SELECT 1 FROM obras_persona_empresa pe2
      WHERE pe2.persona_id = pe.persona_id AND pe2.activo AND pe2.empresa_id <> p_empresa_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM obras_obra_persona op
      WHERE op.persona_id = pe.persona_id AND op.activo
    );
END;
$$;

-- ============================================================
-- 3. `obras_transferir` — suma la cascada
-- ============================================================
DROP FUNCTION IF EXISTS obras_transferir(uuid, uuid);

CREATE OR REPLACE FUNCTION obras_transferir(
  p_obra_id             uuid,
  p_a_usuario_id        uuid,
  p_contactos_exclusivos uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual uuid;
BEGIN
  IF NOT tiene_permiso('obras_transferir') THEN
    RAISE EXCEPTION 'Sin permiso para transferir obras' USING ERRCODE = 'OB003';
  END IF;

  SELECT responsable_id INTO v_actual FROM obras WHERE id = p_obra_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Obra inexistente o desactivada' USING ERRCODE = 'OB004';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La obra ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario_id AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras SET responsable_id = p_a_usuario_id WHERE id = p_obra_id;

  INSERT INTO obras_transferencias (tipo, obra_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('obra', p_obra_id, v_actual, p_a_usuario_id, auth.uid());

  -- Personas del dueño saliente vinculadas a esta obra:
  --  - tildadas como exclusivas → cambian de dueño con la obra
  --  - el resto → grant contextual anclado a la obra (contacto solo en su ficha)
  UPDATE obras_personas SET creado_por = p_a_usuario_id
  WHERE creado_por = v_actual AND id = ANY(p_contactos_exclusivos)
    AND id IN (SELECT persona_id FROM obras_obra_persona WHERE obra_id = p_obra_id AND activo);

  -- El grant es para el receptor; si transfiere a sí mismo (admin) no hace
  -- falta y además chocaría con el CHECK usuario_id <> otorgada_por.
  IF p_a_usuario_id <> auth.uid() THEN
    INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, obra_id, otorgada_por)
    SELECT DISTINCT op.persona_id, p_a_usuario_id, p_obra_id, auth.uid()
    FROM obras_obra_persona op
    JOIN obras_personas p ON p.id = op.persona_id
    WHERE op.obra_id = p_obra_id AND op.activo
      AND p.creado_por = v_actual
      AND NOT (op.persona_id = ANY(p_contactos_exclusivos))
    ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
    DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();
  END IF;

  -- Empresas del dueño saliente vinculadas a esta obra: exclusivas cambian de
  -- dueño; el resto entra a la agenda del receptor (empresa no es sensible).
  UPDATE obras_empresas SET creado_por = p_a_usuario_id
  WHERE creado_por = v_actual AND id = ANY(p_contactos_exclusivos)
    AND id IN (SELECT empresa_id FROM obras_obra_empresa WHERE obra_id = p_obra_id AND activo);

  IF p_a_usuario_id <> auth.uid() THEN
    INSERT INTO obras_empresa_compartida (empresa_id, usuario_id, otorgada_por)
    SELECT DISTINCT oe.empresa_id, p_a_usuario_id, auth.uid()
    FROM obras_obra_empresa oe
    JOIN obras_empresas e ON e.id = oe.empresa_id
    WHERE oe.obra_id = p_obra_id AND oe.activo
      AND e.creado_por = v_actual
      AND NOT (oe.empresa_id = ANY(p_contactos_exclusivos))
    ON CONFLICT (empresa_id, usuario_id)
    DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();
  END IF;
END;
$$;

-- ============================================================
-- 4. `obras_transferir_persona`
-- ============================================================
CREATE OR REPLACE FUNCTION obras_transferir_persona(p_persona_id uuid, p_a_usuario_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual uuid;
BEGIN
  IF NOT tiene_permiso('obras_personas_todas') THEN
    RAISE EXCEPTION 'Sin permiso para transferir personas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_actual FROM obras_personas WHERE id = p_persona_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Persona inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La persona ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario_id AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_personas SET creado_por = p_a_usuario_id WHERE id = p_persona_id;

  -- Los grants que el dueño viejo había otorgado se revocan; el nuevo re-comparte.
  UPDATE obras_persona_compartida SET activo = false, updated_at = now()
    WHERE persona_id = p_persona_id AND activo;
  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
    WHERE persona_id = p_persona_id AND activo;

  INSERT INTO obras_transferencias (tipo, persona_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('persona', p_persona_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

-- ============================================================
-- 5. `obras_transferir_empresa`
-- ============================================================
CREATE OR REPLACE FUNCTION obras_transferir_empresa(
  p_empresa_id         uuid,
  p_a_usuario_id       uuid,
  p_personas_exclusivas uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual uuid;
BEGIN
  IF NOT tiene_permiso('obras_empresas_todas') THEN
    RAISE EXCEPTION 'Sin permiso para transferir empresas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_actual FROM obras_empresas WHERE id = p_empresa_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Empresa inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La empresa ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN usuario_submodulos us ON us.usuario_id = u.id AND us.activo
    JOIN submodulos s ON s.id = us.submodulo_id AND s.activo
    WHERE u.id = p_a_usuario_id AND u.activo AND s.codigo = 'obras_ver'
  ) THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_empresas SET creado_por = p_a_usuario_id WHERE id = p_empresa_id;

  UPDATE obras_empresa_compartida SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND activo;

  -- Personas del dueño saliente empleadas en esta empresa y tildadas como
  -- exclusivas → cambian de dueño con ella. El resto no se toca: si están en
  -- una obra, esa obra decide su alcance.
  UPDATE obras_personas SET creado_por = p_a_usuario_id
  WHERE creado_por = v_actual AND id = ANY(p_personas_exclusivas)
    AND id IN (SELECT persona_id FROM obras_persona_empresa WHERE empresa_id = p_empresa_id AND activo);

  INSERT INTO obras_transferencias (tipo, empresa_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('empresa', p_empresa_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

-- ============================================================
-- 6. GRANTs
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid, uuid[])                  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_transferir_persona(uuid, uuid)                  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_transferir_empresa(uuid, uuid, uuid[])          FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_contactos_exclusivos_de_obra(uuid)              FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_contactos_exclusivos_de_empresa(uuid)           FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid, uuid[])                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_transferir_persona(uuid, uuid)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_transferir_empresa(uuid, uuid, uuid[])           TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_contactos_exclusivos_de_obra(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_contactos_exclusivos_de_empresa(uuid)            TO authenticated;
