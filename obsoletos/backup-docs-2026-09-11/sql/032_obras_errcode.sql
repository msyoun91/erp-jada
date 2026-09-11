-- ============================================================
-- 032 — Agenda de Obras: los mensajes de negocio llegan a la pantalla
--
-- Las diez `RAISE EXCEPTION` del módulo salían sin `ERRCODE`, así que Postgres
-- las emitía como `P0001` (raise_exception). `mensajeError()` en
-- `lib/utils.ts` resuelve por `error.code` contra un mapa: `P0001` no está, y
-- todas terminaban en "No se pudo completar la operación. Intentá de nuevo."
-- — incluida la que dice en cuántas obras participa la empresa que no se
-- puede desactivar.
--
-- Eso desmentía tres decisiones ya escritas:
--   · `decisiones/obras.md` — "El mensaje viene de la base."
--   · `sql/027` §13 — "El mensaje dice cuántas obras, nunca cuáles."
--   · el ConfirmModal de empresa y de persona, que promete que la base va a
--     explicar por qué no procede.
--
-- POR QUÉ UNA CLASE `OB` Y NO UN MAPA COMO `TA00x`
--
-- `tareas` mapea código → texto en TypeScript porque sus mensajes son fijos.
-- Dos de estos no lo son: llevan el conteo de obras, que es justamente el dato
-- por el que el mensaje existe. Repetir el texto en el mapa perdería el
-- número, y escribirlo en los dos lados sería la duplicación que CLAUDE.md
-- prohíbe.
--
-- Entonces la clase `OB` no es un índice de textos: es la marca de "este
-- mensaje está escrito para que lo lea un usuario". `mensajeError()` deja
-- pasar el texto de la base solo para esos códigos. Un error de Postgres sin
-- marcar sigue cayendo en el genérico — la lista blanca es la barrera, no la
-- confianza en que ningún mensaje interno se escape.
--
-- Regla que queda: un `RAISE EXCEPTION` de este módulo sin `USING ERRCODE` es
-- un mensaje que nadie va a leer.
--
-- Las siete funciones se recrean con `CREATE OR REPLACE` y firma idéntica: los
-- GRANT de `sql/029` y `sql/031` sobreviven, no hay que rehacerlos.
-- ============================================================

-- ============================================================
-- OB001 / OB002 — desactivar una entidad compartida que está en uso
--
-- El conteo va en el mensaje y los nombres nunca: quien desactiva no puede ver
-- esas obras, y el mensaje no puede ser la puerta que la RLS cierra.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_guard_desactivar_empresa()
RETURNS TRIGGER AS $$
DECLARE n int;
BEGIN
  -- Solo obras activas: una obra desactivada no se rompe por esto.
  SELECT count(DISTINCT v.obra_id) INTO n
  FROM (
    SELECT obra_id FROM obras_obra_empresa WHERE empresa_id = OLD.id AND activo
    UNION
    SELECT obra_id FROM obras_obra_persona WHERE empresa_id = OLD.id AND activo
  ) AS v
  JOIN obras o ON o.id = v.obra_id AND o.activo;

  IF n > 0 THEN
    RAISE EXCEPTION 'No se puede desactivar: la empresa participa en % obra(s). Desvinculala primero.', n
      USING ERRCODE = 'OB001';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE OR REPLACE FUNCTION obras_guard_desactivar_persona()
RETURNS TRIGGER AS $$
DECLARE n int;
BEGIN
  SELECT count(DISTINCT v.obra_id) INTO n
  FROM (
    SELECT obra_id FROM obras_obra_persona WHERE persona_id = OLD.id AND activo
    UNION
    SELECT obra_id FROM obras_obra_referente WHERE persona_id = OLD.id AND activo
  ) AS v
  JOIN obras o ON o.id = v.obra_id AND o.activo;

  IF n > 0 THEN
    RAISE EXCEPTION 'No se puede desactivar: la persona participa en % obra(s). Desvinculala primero.', n
      USING ERRCODE = 'OB002';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- ============================================================
-- OB003 a OB006 — transferir
-- ============================================================
CREATE OR REPLACE FUNCTION obras_transferir(p_obra_id uuid, p_a_usuario_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  INSERT INTO obras_transferencias (obra_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES (p_obra_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

-- ============================================================
-- OB007 / OB008 — desactivar y reactivar obra
-- ============================================================
CREATE OR REPLACE FUNCTION obras_set_activo(p_obra_id uuid, p_activo boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_desactivar') THEN
    RAISE EXCEPTION 'Sin permiso para desactivar obras' USING ERRCODE = 'OB007';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM obras WHERE id = p_obra_id AND responsable_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'La obra no existe o no sos su responsable' USING ERRCODE = 'OB008';
  END IF;

  UPDATE obras SET activo = p_activo WHERE id = p_obra_id;
END;
$$;

-- ============================================================
-- OB009 — ficha de persona fuera de alcance
--
-- El texto no distingue "no existe" de "no la podés ver", y no debe: decir
-- cuál de las dos es ya es contar que esa persona está en la agenda.
--
-- El log se movió DESPUÉS de confirmar que la fila existe y está activa. Lo
-- cazó `sql/tests/obras_032.sql`: quien tiene `obras_personas_todas` pasa el
-- guard con cualquier uuid, porque `obras_puede_ver_persona` no mira si la
-- persona existe. Con un id inventado el INSERT moría contra la FK (23503,
-- "El registro relacionado no existe"), y con una persona real pero inactiva
-- no moría — registraba un acceso fantasma y devolvía cero filas.
--
-- Un log de accesos que anota aperturas que no ocurrieron deja de servir para
-- lo único que justifica su costo, que es contar cuántas fichas abrió alguien.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_ficha_persona(p_persona_id uuid)
RETURNS TABLE (
  id             uuid,
  nombre         text,
  apellido       text,
  telefono       text,
  whatsapp       text,
  email          text,
  observaciones  text,
  creado_por     uuid,
  created_at     timestamptz,
  updated_at     timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT obras_puede_ver_persona(p_persona_id)
     OR NOT EXISTS (SELECT 1 FROM obras_personas p WHERE p.id = p_persona_id AND p.activo)
  THEN
    RAISE EXCEPTION 'Sin acceso a esta persona' USING ERRCODE = 'OB009';
  END IF;

  INSERT INTO obras_accesos_persona (usuario_id, persona_id)
  VALUES (auth.uid(), p_persona_id);

  RETURN QUERY
  SELECT p.id, p.nombre, p.apellido, p.telefono, p.whatsapp, p.email,
         p.observaciones, p.creado_por, p.created_at, p.updated_at
  FROM obras_personas p
  WHERE p.id = p_persona_id AND p.activo;
END;
$$;

-- ============================================================
-- OB010 — auditoría sin permiso
-- ============================================================
CREATE OR REPLACE FUNCTION obras_auditoria_accesos(p_dias int DEFAULT 30)
RETURNS TABLE (
  acceso_id   uuid,
  created_at  timestamptz,
  usuario_id  uuid,
  usuario     text,
  persona_id  uuid,
  persona     text
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_auditoria') THEN
    RAISE EXCEPTION 'Sin permiso para ver la auditoría' USING ERRCODE = 'OB010';
  END IF;

  RETURN QUERY
  SELECT a.id, a.created_at, a.usuario_id, u.nombre, a.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, ''))
  FROM obras_accesos_persona a
  JOIN usuarios u ON u.id = a.usuario_id
  JOIN obras_personas p ON p.id = a.persona_id
  WHERE a.created_at >= now() - make_interval(days => greatest(p_dias, 1))
  ORDER BY a.created_at DESC
  LIMIT 500;
END;
$$;

CREATE OR REPLACE FUNCTION obras_auditoria_transferencias(p_dias int DEFAULT 90)
RETURNS TABLE (
  transferencia_id  uuid,
  created_at        timestamptz,
  obra_id           uuid,
  obra              text,
  de_usuario        text,
  a_usuario         text,
  ejecutada_por     text
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_auditoria') THEN
    RAISE EXCEPTION 'Sin permiso para ver la auditoría' USING ERRCODE = 'OB010';
  END IF;

  RETURN QUERY
  SELECT t.id, t.created_at, t.obra_id, o.nombre, ud.nombre, ua.nombre, ue.nombre
  FROM obras_transferencias t
  JOIN obras o    ON o.id = t.obra_id
  JOIN usuarios ud ON ud.id = t.de_usuario_id
  JOIN usuarios ua ON ua.id = t.a_usuario_id
  JOIN usuarios ue ON ue.id = t.ejecutada_por
  WHERE t.created_at >= now() - make_interval(days => greatest(p_dias, 1))
  ORDER BY t.created_at DESC
  LIMIT 500;
END;
$$;
