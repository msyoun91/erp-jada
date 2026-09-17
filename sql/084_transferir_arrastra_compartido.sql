-- ============================================================
-- 084 — Transferir arrastra lo compartido
--
-- RECONSTRUIDO DESDE LA BASE (2026-09-17). Igual que sql/083: ya estaba
-- aplicado y sin archivo. La versión viva de `obras_transferir` cita "sql/071",
-- un archivo que nunca existió en el repo — los números 071 a 075 están libres
-- y quedan libres: renumerar reescribiría historia por nada.
--
-- El orden es el correcto igual: el cuerpo vivo inserta en
-- `obras_persona_grant_contextual` con el índice parcial de sql/082, así que
-- 084 es el lugar donde tiene que ir para reconstruir desde cero.
--
-- Qué agrega sobre sql/041:
--
--   1. Las exclusivas que cambian de dueño se capturan (`RETURNING id`). Antes
--      se movían a ciegas; ahora hay que saber cuáles para tocar sus grants.
--   2. Lo que el receptor ya recibía sobre lo que ahora es suyo se apaga: uno
--      no se comparte consigo mismo, y el CHECK `usuario_id <> otorgada_por` lo
--      rechazaría.
--   3. Lo compartido con terceros sigue vivo pero pasa a colgar del nuevo
--      dueño (`otorgada_por`): quien recibió la obra es quien ahora puede
--      revocar. Si quedara apuntando al saliente, el acceso viviría sin nadie
--      que pueda apagarlo.
--   4. Los contactos del saliente vinculados a la obra y NO tildados como
--      exclusivos entran al receptor como grant contextual anclado a la obra
--      (sql/082): los ve en la ficha, no en su agenda. Empresas sí van a la
--      agenda — una empresa no es un contacto sensible.
--
-- `obras_transferir_persona` no cambió: una persona sola no arrastra nada.
--
-- Ver decisiones/obras/visibilidad.md.
-- ============================================================

-- ============================================================
-- 1. Obra
-- ============================================================
CREATE OR REPLACE FUNCTION obras_transferir(p_obra_id uuid, p_a_usuario_id uuid, p_contactos_exclusivos uuid[] DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
  v_empresas uuid[];
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
  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_contactos_exclusivos)
      AND id IN (SELECT persona_id FROM obras_obra_persona WHERE obra_id = p_obra_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

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
  WITH movidas AS (
    UPDATE obras_empresas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_contactos_exclusivos)
      AND id IN (SELECT empresa_id FROM obras_obra_empresa WHERE obra_id = p_obra_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_empresas FROM movidas;

  -- Lo compartido pasa al nuevo dueño. Lo que el nuevo dueño recibía sobre lo
  -- que ahora es suyo se apaga primero.
  UPDATE obras_obra_compartida SET activo = false
  WHERE obra_id = p_obra_id AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_empresa_compartida SET activo = false
  WHERE empresa_id = ANY(v_empresas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_compartida SET activo = false
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_obra_compartida SET otorgada_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND activo;

  UPDATE obras_empresa_compartida SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (origen_obra_id = p_obra_id OR empresa_id = ANY(v_empresas));

  UPDATE obras_persona_compartida SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (origen_obra_id = p_obra_id OR origen_empresa_id = ANY(v_empresas)
         OR persona_id = ANY(v_personas));

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
-- 2. Empresa
-- ============================================================
-- Acá lo compartido se apaga en vez de pasar de mano: compartir una empresa es
-- una decisión sobre la agenda propia, no sobre la obra. El nuevo dueño decide
-- de cero a quién se la comparte.
CREATE OR REPLACE FUNCTION obras_transferir_empresa(p_empresa_id uuid, p_a_usuario_id uuid, p_personas_exclusivas uuid[] DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
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

  UPDATE obras_persona_compartida SET activo = false, updated_at = now()
    WHERE origen_empresa_id = p_empresa_id AND activo;

  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_personas_exclusivas)
      AND id IN (SELECT persona_id FROM obras_persona_empresa WHERE empresa_id = p_empresa_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  UPDATE obras_persona_compartida SET activo = false, updated_at = now()
    WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_compartida SET otorgada_por = p_a_usuario_id
    WHERE persona_id = ANY(v_personas) AND activo;

  INSERT INTO obras_transferencias (tipo, empresa_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('empresa', p_empresa_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;
