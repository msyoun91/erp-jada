-- ============================================================
-- 049 — Compartir editable: el checklist es "estado deseado"
--
-- Hasta acá `obras_compartir_obra` / `_empresa` solo agregaban: lo tildado
-- recibía grant, lo destildado quedaba como estuviera. Para poder AJUSTAR lo
-- ya compartido con un usuario (sacar una empresa del reparto, agregar una
-- persona) sin revocar la obra/empresa entera, ahora la llamada expresa el
-- estado completo del reparto:
--
--   · tildado    → grant completo, origen = este padre (igual que antes)
--   · destildado → si colgaba de ESTE padre (cascada), se desactiva
--
-- Un grant directo (origen NULL) o colgado de otro padre no se toca — mismo
-- criterio que la cascada de `obras_revocar_obra` / `obras_revocar_empresa`.
-- Un array vacío desactiva toda la cascada de ese padre para ese usuario.
--
-- El alta inicial no cambia: no hay grants de origen que desactivar.
-- Solo se reemplaza el cuerpo de dos funciones; firmas y GRANTs intactos.
-- ============================================================

CREATE OR REPLACE FUNCTION obras_compartir_obra(
  p_obra_id    uuid,
  p_usuario_id uuid,
  p_empresas   uuid[] DEFAULT '{}',
  p_personas   uuid[] DEFAULT '{}'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte una obra a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id AND o.responsable_id = auth.uid() AND o.activo
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario_id AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  INSERT INTO obras_obra_compartida (obra_id, usuario_id, otorgada_por, activo)
  VALUES (p_obra_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (obra_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  -- Empresas tildadas: vinculadas a esta obra y mías. Grant completo con
  -- origen = esta obra (última escritura gana).
  INSERT INTO obras_empresa_compartida
    (empresa_id, usuario_id, otorgada_por, activo, origen_obra_id)
  SELECT DISTINCT oe.empresa_id, p_usuario_id, auth.uid(), true, p_obra_id
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo
    AND oe.empresa_id = ANY(p_empresas)
  ON CONFLICT (empresa_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = p_obra_id;

  -- Personas tildadas: vinculadas a esta obra y mías (no congeladas).
  INSERT INTO obras_persona_compartida
    (persona_id, usuario_id, otorgada_por, activo, origen_obra_id)
  SELECT DISTINCT op.persona_id, p_usuario_id, auth.uid(), true, p_obra_id
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    AND op.persona_id = ANY(p_personas)
  ON CONFLICT (persona_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = p_obra_id, origen_empresa_id = NULL;

  -- Destildado: la cascada de ESTA obra que quedó fuera del checklist se apaga.
  UPDATE obras_empresa_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (empresa_id = ANY(p_empresas));

  UPDATE obras_persona_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (persona_id = ANY(p_personas));
END;
$$;

CREATE OR REPLACE FUNCTION obras_compartir_empresa(
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_personas   uuid[] DEFAULT '{}'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte una empresa a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM obras_empresas e
    WHERE e.id = p_empresa_id AND e.creado_por = auth.uid()
      AND e.activo AND NOT e.pendiente
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario_id AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  -- Compartir directo la empresa: limpia el origen (deja de colgar de una obra).
  INSERT INTO obras_empresa_compartida (empresa_id, usuario_id, otorgada_por, activo)
  VALUES (p_empresa_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (empresa_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = NULL;

  -- Personas tildadas: empleadas en esta empresa y mías. Grant completo con
  -- origen = esta empresa.
  INSERT INTO obras_persona_compartida
    (persona_id, usuario_id, otorgada_por, activo, origen_empresa_id)
  SELECT DISTINCT pe.persona_id, p_usuario_id, auth.uid(), true, p_empresa_id
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    AND pe.persona_id = ANY(p_personas)
  ON CONFLICT (persona_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_empresa_id = p_empresa_id, origen_obra_id = NULL;

  -- Destildado: la cascada de ESTA empresa que quedó fuera del checklist se apaga.
  UPDATE obras_persona_compartida
    SET activo = false, updated_at = now()
    WHERE origen_empresa_id = p_empresa_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (persona_id = ANY(p_personas));
END;
$$;
