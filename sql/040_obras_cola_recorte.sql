-- ============================================================
-- 040 — Agenda de Obras: la cola de aprobación se recorta a las altas
--
-- Bajo model A (sql/039) no se puede vincular lo que no se ve, así que el
-- estado "vínculo a entidad ajena, congelado hasta que un admin lo apruebe"
-- deja de existir: la rama de vínculo-pendiente de sql/033 se va entera.
--
-- Lo que QUEDA de la cola: un alta de obra / empresa / persona que se parece a
-- algo ya cargado entra congelada y la decide `obras_aprobar`. Eso sigue —
-- pedido explícito del usuario: contra el que clickea "crear igual" ignorando
-- el aviso, el trigger es la barrera.
--
-- CAMBIOS
--   - `pendiente` / `motivo_rechazo` se dropean de obras_obra_empresa y
--     obras_obra_persona (+ sus índices parciales).
--   - `obras_marcar_pendiente` pierde las dos ramas de vínculo; sus triggers
--     sobre las tablas de vínculo se dropean.
--   - `obras_guard_congelado` se elimina: su única razón viva —marcar referente
--     exige ver a la persona— pasa al WITH CHECK de obras_obra_referente_insert,
--     que es donde va una regla de este tipo (CLAUDE.md). Los cuatro triggers
--     que la llamaban se dropean.
--   - `obras_pendientes` / `obras_resolver_pendiente` / `obras_solicitante` /
--     `obras_etiqueta` pierden las ramas obra_empresa / obra_persona.
--   - `obras_pendiente_similares` suma cargo y localidad a la fila de persona:
--     para decidir "misma o distinta" sin que la pantalla sea otra puerta al
--     contacto.
--   - `obras_aprobaciones.tipo` CHECK se acota a ('obra','empresa','persona').
--
-- `usuario_notificaciones` no cambia de forma (el enum de tipos nunca tuvo
-- valores de vínculo, el CHECK de `entidad` los sigue permitiendo aunque ya
-- nadie los escriba). Solo `notificaciones_listar` se reescribe: sus ramas
-- obra_empresa/obra_persona leían `motivo_rechazo` de las columnas dropeadas.
-- ============================================================

-- ============================================================
-- 1. Fuera las columnas de vínculo-pendiente
-- ============================================================
DROP TRIGGER IF EXISTS marcar_pendiente  ON obras_obra_empresa;
DROP TRIGGER IF EXISTS marcar_pendiente  ON obras_obra_persona;
DROP TRIGGER IF EXISTS guard_congelado   ON obras_obra_empresa;
DROP TRIGGER IF EXISTS guard_congelado   ON obras_obra_persona;
DROP TRIGGER IF EXISTS guard_congelado   ON obras_persona_empresa;
DROP TRIGGER IF EXISTS guard_congelado   ON obras_obra_referente;

DROP INDEX IF EXISTS idx_obras_obra_empresa_pendiente;
DROP INDEX IF EXISTS idx_obras_obra_persona_pendiente;

ALTER TABLE obras_obra_empresa DROP COLUMN IF EXISTS pendiente;
ALTER TABLE obras_obra_empresa DROP COLUMN IF EXISTS motivo_rechazo;
ALTER TABLE obras_obra_persona DROP COLUMN IF EXISTS pendiente;
ALTER TABLE obras_obra_persona DROP COLUMN IF EXISTS motivo_rechazo;

DROP FUNCTION IF EXISTS obras_guard_congelado();

-- ============================================================
-- 2. Marcar referente exige ver a la persona — ahora en la policy
-- ============================================================
DROP POLICY IF EXISTS obras_obra_referente_insert ON obras_obra_referente;
CREATE POLICY obras_obra_referente_insert ON obras_obra_referente FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_referentes')
    AND obras_es_mi_obra(obra_id)
    AND obras_puede_ver_persona(persona_id)
  );

-- ============================================================
-- 3. `obras_marcar_pendiente` — solo las tres altas
-- ============================================================
CREATE OR REPLACE FUNCTION obras_marcar_pendiente()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  NEW.motivo_rechazo := NULL;

  IF TG_TABLE_NAME = 'obras' THEN
    IF EXISTS (SELECT 1 FROM obras_similares_obra(NEW.nombre, NEW.direccion, NEW.localidad, NEW.id)) THEN
      NEW.pendiente := true;
    END IF;

  ELSIF TG_TABLE_NAME = 'obras_empresas' THEN
    IF EXISTS (SELECT 1 FROM obras_similares_empresa(NEW.razon_social, NEW.nombre_comercial, NEW.id)) THEN
      NEW.pendiente := true;
    END IF;

  ELSIF TG_TABLE_NAME = 'obras_personas' THEN
    IF EXISTS (SELECT 1 FROM obras_similares_persona(NEW.nombre, NEW.apellido, NEW.email, NEW.telefono, NEW.id)) THEN
      NEW.pendiente := true;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 4. `obras_etiqueta` — sin las ramas de vínculo (INVOKER, sql/038 §4.1)
-- ============================================================
CREATE OR REPLACE FUNCTION obras_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql STABLE SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra' THEN (SELECT o.nombre FROM obras o WHERE o.id = p_id)
    WHEN 'empresa' THEN (SELECT e.razon_social FROM obras_empresas e WHERE e.id = p_id)
    WHEN 'persona' THEN (
      SELECT btrim(p.nombre || ' ' || coalesce(p.apellido, ''))
      FROM obras_personas p WHERE p.id = p_id
    )
  END;
$$;

-- ============================================================
-- 5. `obras_solicitante` — sin las ramas de vínculo (sql/038 §4)
-- ============================================================
CREATE OR REPLACE FUNCTION obras_solicitante(p_tipo text, p_id uuid)
RETURNS uuid
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra'    THEN (SELECT o.responsable_id FROM obras o WHERE o.id = p_id)
    WHEN 'empresa' THEN (SELECT e.creado_por FROM obras_empresas e WHERE e.id = p_id)
    WHEN 'persona' THEN (SELECT p.creado_por FROM obras_personas p WHERE p.id = p_id)
  END;
$$;

-- ============================================================
-- 6. `obras_pendientes` — tres altas, sin vínculos
-- ============================================================
CREATE OR REPLACE FUNCTION obras_pendientes()
RETURNS TABLE (
  tipo        text,
  registro_id uuid,
  etiqueta    text,
  motivo      text,
  solicitante text,
  created_at  timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_pendientes') THEN
    RAISE EXCEPTION 'Sin permiso para ver las autorizaciones pendientes' USING ERRCODE = 'OB013';
  END IF;

  RETURN QUERY
  WITH filas AS (
    SELECT 'obra'::text AS tipo, o.id, o.created_at,
           'Posible duplicado de una obra que ya existe'::text AS motivo
    FROM obras o WHERE o.pendiente AND o.activo
    UNION ALL
    SELECT 'empresa', e.id, e.created_at,
           'Posible duplicado de una empresa que ya existe'
    FROM obras_empresas e WHERE e.pendiente AND e.activo
    UNION ALL
    SELECT 'persona', p.id, p.created_at,
           'Posible duplicado de una persona que ya existe'
    FROM obras_personas p WHERE p.pendiente AND p.activo
  )
  SELECT f.tipo, f.id, obras_etiqueta(f.tipo, f.id), f.motivo, u.nombre, f.created_at
  FROM filas f
  JOIN usuarios u ON u.id = obras_solicitante(f.tipo, f.id)
  ORDER BY f.created_at
  LIMIT 500;
END;
$$;

-- ============================================================
-- 7. `obras_pendiente_similares` — la persona con cargo y localidad
--
-- Excepción consciente al aviso ciego (ya venía así para obras): el que aprueba
-- ve el nombre de la entidad ajena contra la que se parece. Nunca contacto. La
-- persona suma empresa+cargo y las localidades de sus obras: es lo que decide
-- "misma persona o dos que se llaman igual".
-- ============================================================
CREATE OR REPLACE FUNCTION obras_pendiente_similares(p_tipo text, p_id uuid)
RETURNS TABLE (etiqueta text, detalle text)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_aprobar') THEN
    RAISE EXCEPTION 'Sin permiso para resolver autorizaciones' USING ERRCODE = 'OB014';
  END IF;

  IF p_tipo = 'obra' THEN
    RETURN QUERY
    SELECT o2.nombre,
           concat_ws(' · ', u.nombre, o2.localidad, o2.direccion)
    FROM obras o
    CROSS JOIN LATERAL obras_similares_obra(o.nombre, o.direccion, o.localidad, o.id) s
    JOIN obras o2   ON o2.id = s.obra_id
    JOIN usuarios u ON u.id = o2.responsable_id
    WHERE o.id = p_id;

  ELSIF p_tipo = 'empresa' THEN
    RETURN QUERY
    SELECT e2.razon_social,
           concat_ws(' · ', e2.nombre_comercial, e2.localidad)
    FROM obras_empresas e
    CROSS JOIN LATERAL obras_similares_empresa(e.razon_social, e.nombre_comercial, e.id) s
    JOIN obras_empresas e2 ON e2.id = s.empresa_id
    WHERE e.id = p_id;

  ELSIF p_tipo = 'persona' THEN
    RETURN QUERY
    SELECT btrim(p2.nombre || ' ' || coalesce(p2.apellido, '')),
           concat_ws(' · ',
             s.coincide,
             (SELECT e.razon_social || coalesce(' (' || pe.cargo || ')', '')
              FROM obras_persona_empresa pe
              JOIN obras_empresas e ON e.id = pe.empresa_id AND e.activo
              WHERE pe.persona_id = p2.id AND pe.activo
              ORDER BY pe.es_principal DESC
              LIMIT 1),
             (SELECT string_agg(DISTINCT o.localidad, ', ')
              FROM obras_obra_persona op
              JOIN obras o ON o.id = op.obra_id AND o.activo
              WHERE op.persona_id = p2.id AND op.activo AND o.localidad IS NOT NULL),
             u.nombre)
    FROM obras_personas p
    CROSS JOIN LATERAL obras_similares_persona(p.nombre, p.apellido, p.email, p.telefono, p.id) s
    JOIN obras_personas p2 ON p2.id = s.persona_id
    JOIN usuarios u        ON u.id = p2.creado_por
    WHERE p.id = p_id;
  END IF;
END;
$$;

-- ============================================================
-- 8. `obras_resolver_pendiente` — sin las ramas de vínculo
-- ============================================================
CREATE OR REPLACE FUNCTION obras_resolver_pendiente(
  p_tipo    text,
  p_id      uuid,
  p_aprobar boolean,
  p_motivo  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tabla    text;
  v_etiqueta text;
  v_filas    int;
BEGIN
  IF NOT tiene_permiso('obras_aprobar') THEN
    RAISE EXCEPTION 'Sin permiso para resolver autorizaciones' USING ERRCODE = 'OB014';
  END IF;

  v_tabla := CASE p_tipo
    WHEN 'obra'    THEN 'obras'
    WHEN 'empresa' THEN 'obras_empresas'
    WHEN 'persona' THEN 'obras_personas'
  END;

  IF v_tabla IS NULL THEN
    RAISE EXCEPTION 'Tipo de solicitud desconocido' USING ERRCODE = 'OB015';
  END IF;

  IF NOT p_aprobar AND btrim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'Un rechazo necesita un motivo: es lo único que va a leer quien la cargó.'
      USING ERRCODE = 'OB016';
  END IF;

  v_etiqueta := obras_etiqueta(p_tipo, p_id);

  EXECUTE format(
    'UPDATE %I
        SET pendiente      = false,
            activo         = CASE WHEN $1 THEN activo ELSE false END,
            motivo_rechazo = CASE WHEN $1 THEN NULL ELSE $2 END
      WHERE id = $3 AND pendiente', v_tabla)
  USING p_aprobar, btrim(p_motivo), p_id;

  GET DIAGNOSTICS v_filas = ROW_COUNT;
  IF v_filas = 0 THEN
    RAISE EXCEPTION 'Esa solicitud ya fue resuelta o no existe' USING ERRCODE = 'OB017';
  END IF;

  INSERT INTO obras_aprobaciones (tipo, registro_id, etiqueta, aprobada, motivo, decidido_por)
  VALUES (p_tipo, p_id, coalesce(v_etiqueta, '(sin nombre)'), p_aprobar, btrim(p_motivo), auth.uid());
END;
$$;

-- ============================================================
-- 9. `obras_aprobaciones.tipo` — sin los valores de vínculo
--
-- 0 filas con esos tipos al correr esto, así que el CHECK nuevo no rechaza nada.
-- ============================================================
ALTER TABLE obras_aprobaciones DROP CONSTRAINT IF EXISTS obras_aprobaciones_tipo_check;
ALTER TABLE obras_aprobaciones ADD CONSTRAINT obras_aprobaciones_tipo_check
  CHECK (tipo IN ('obra', 'empresa', 'persona'));

-- ============================================================
-- 10. `notificaciones_listar` (sql/038) — sin las ramas de vínculo
--
-- Referenciaban `oe.motivo_rechazo` / `op.motivo_rechazo`, columnas que se
-- dropean en §1. El resto de la función queda igual: INVOKER, INNER JOIN por
-- rama, el texto de `obras_etiqueta`.
-- ============================================================
CREATE OR REPLACE FUNCTION notificaciones_listar(p_limite int DEFAULT 30)
RETURNS TABLE (
  id         uuid,
  tipo       tipo_notificacion,
  etiqueta   text,
  motivo     text,
  actor      text,
  destino    text,
  destino_id uuid,
  leida      boolean,
  created_at timestamptz
)
LANGUAGE sql STABLE SET search_path = public
AS $$
  WITH mias AS (
    SELECT n.*
    FROM usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo
    ORDER BY n.created_at DESC
    LIMIT greatest(coalesce(p_limite, 30), 1)
  ),
  resuelta AS (
    SELECT n.id AS notificacion_id,
           obras_etiqueta('obra', o.id) AS etiqueta,
           o.motivo_rechazo             AS motivo,
           'obra'::text                 AS destino,
           o.id                         AS destino_id
    FROM mias n JOIN obras o ON o.id = n.entidad_id
    WHERE n.entidad = 'obra'
    UNION ALL
    SELECT n.id, obras_etiqueta('empresa', e.id), e.motivo_rechazo, 'empresa', e.id
    FROM mias n JOIN obras_empresas e ON e.id = n.entidad_id
    WHERE n.entidad = 'empresa'
    UNION ALL
    SELECT n.id, obras_etiqueta('persona', p.id), p.motivo_rechazo, 'persona', p.id
    FROM mias n JOIN obras_personas p ON p.id = n.entidad_id
    WHERE n.entidad = 'persona'
    UNION ALL
    SELECT n.id, t.titulo, NULL::text, 'tarea', t.id
    FROM mias n JOIN tareas t ON t.id = n.entidad_id
    WHERE n.entidad = 'tarea'
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, u.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r      ON r.notificacion_id = n.id
  LEFT JOIN usuarios u ON u.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;
