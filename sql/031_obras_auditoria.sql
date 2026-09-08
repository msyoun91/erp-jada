-- ============================================================
-- 031 — Agenda de Obras: los logs se pueden mirar, el aviso de duplicados
-- deja de esconderse detrás de la localidad, y el referente se guarda en una
-- sola transacción.
--
-- Tres cosas que la auditoría del módulo dejó a la vista:
--
-- 1. `obras_accesos_persona` y `obras_transferencias` se escribían y no se
--    leían desde ningún lado. El registro de accesos es lo que justifica que
--    `obras_ficha_persona()` sea el único camino al contacto — sin pantalla,
--    el módulo paga el costo del log y no cobra el beneficio.
--
-- 2. `obras_buscar_duplicados_obra` filtraba la localidad por igualdad
--    exacta del normalizado. "Devoto" y "Villa Devoto" son la misma para
--    cualquiera menos para el `=`, así que el aviso ciego no saltaba justo en
--    el caso para el que existe. Y las tres búsquedas no sabían excluirse a
--    sí mismas, así que solo se podían usar al crear: al editar, la fila se
--    encontraba a sí misma y avisaba de un duplicado que era ella.
--
-- 3. `guardarReferente` hacía SELECT y después UPDATE o INSERT desde
--    TypeScript: dos requests, dos transacciones. El unique parcial evitaba
--    la fila duplicada, así que la carrera terminaba en un 23505 crudo en
--    pantalla en vez de en datos rotos — pero es el patrón que tareas ya bajó
--    a SQL en 023/024.
-- ============================================================

-- ============================================================
-- 1. Submódulo de auditoría
--
-- Vista y no función: es una pantalla propia, y las pantallas del módulo son
-- tabs. `obras_personas_todas` no alcanzaba como puerta — ese permiso es "ver
-- la agenda completa", no "ver quién la estuvo mirando", y son dos cosas
-- distintas que conviene poder dar por separado.
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden) VALUES
  ('obras_auditoria', 'obras', 'vista', 'Auditoría', 4)
ON CONFLICT (codigo) WHERE activo DO NOTHING;

-- ============================================================
-- 2. Accesos a fichas de persona
--
-- SECURITY DEFINER con guard propio, en vez de abrir la policy de la tabla:
-- quien audita necesita ver los accesos de todos, y el nombre de la persona
-- para que la fila signifique algo, pero no tiene por qué tener permiso sobre
-- la agenda. Con un SELECT directo + embed, un auditor sin `obras_personas`
-- recibiría filas con la persona en NULL — el log entero sin poder leerlo.
--
-- Devuelve nombre y apellido. Nunca teléfono, whatsapp ni email: la pantalla
-- que vigila el acceso al contacto no puede ser otra puerta al contacto.
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
    RAISE EXCEPTION 'Sin permiso para ver la auditoría';
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

-- ============================================================
-- 3. Transferencias de obra
--
-- Mismo criterio. Acá sí viaja el nombre de la obra: un log de transferencias
-- que dice "alguien le pasó algo a alguien" no responde la pregunta que
-- justifica el log, que es por qué una obra dejó de estar en una cartera.
-- ============================================================
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
    RAISE EXCEPTION 'Sin permiso para ver la auditoría';
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

-- ============================================================
-- 4. Duplicados de obra — la localidad deja de filtrar
--
-- Pasa de condición a criterio de orden. Escrita distinto no puede esconder
-- una obra que el nombre o la dirección ya marcaron como parecida; escrita
-- igual, la sube al tope de la lista, que es todo lo que aportaba.
--
-- `p_excluir_id` es lo que habilita el chequeo al editar. Sin él, editar una
-- obra la encontraba a sí misma con similitud 1.
--
-- Se dropean antes de recrear porque el parámetro nuevo cambia la firma:
-- CREATE OR REPLACE dejaría las dos versiones y PostgREST no sabría cuál
-- llamar. El DROP se lleva los GRANT, así que se rehacen abajo.
-- ============================================================
DROP FUNCTION IF EXISTS obras_buscar_duplicados_obra(text, text, text);

CREATE FUNCTION obras_buscar_duplicados_obra(
  p_nombre     text,
  p_direccion  text DEFAULT NULL,
  p_localidad  text DEFAULT NULL,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  es_mia       boolean,
  obra_id      uuid,
  nombre       text,
  direccion    text,
  localidad    text,
  responsable  text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH candidatas AS (
    SELECT o.id, o.nombre, o.direccion, o.localidad, o.localidad_norm, o.responsable_id,
           o.responsable_id = auth.uid() AS mia,
           greatest(
             extensions.similarity(o.nombre_norm, obras_normalizar(p_nombre)),
             CASE
               WHEN p_direccion IS NULL OR o.direccion_norm IS NULL THEN 0
               ELSE extensions.similarity(o.direccion_norm, obras_normalizar(p_direccion))
             END
           ) AS score
    FROM obras o
    WHERE o.activo
      AND o.id IS DISTINCT FROM p_excluir_id
  )
  SELECT c.mia,
         CASE WHEN c.mia THEN c.id END,
         CASE WHEN c.mia THEN c.nombre END,
         CASE WHEN c.mia THEN c.direccion END,
         CASE WHEN c.mia THEN c.localidad END,
         u.nombre
  FROM candidatas c
  JOIN usuarios u ON u.id = c.responsable_id
  WHERE c.score >= 0.45 AND tiene_permiso('obras_ver')
  ORDER BY
    (p_localidad IS NOT NULL
      AND c.localidad_norm IS NOT NULL
      AND c.localidad_norm = obras_normalizar(p_localidad)) DESC,
    c.score DESC
  LIMIT 5;
$$;

-- ============================================================
-- 5. Duplicados de empresa y de persona — solo `p_excluir_id`
-- ============================================================
DROP FUNCTION IF EXISTS obras_buscar_duplicados_empresa(text, text);

CREATE FUNCTION obras_buscar_duplicados_empresa(
  p_razon_social      text,
  p_nombre_comercial  text DEFAULT NULL,
  p_excluir_id        uuid DEFAULT NULL
)
RETURNS TABLE (
  empresa_id        uuid,
  razon_social      text,
  nombre_comercial  text,
  localidad         text
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = public
AS $$
  SELECT e.id, e.razon_social, e.nombre_comercial, e.localidad
  FROM obras_empresas e
  WHERE e.activo
    AND e.id IS DISTINCT FROM p_excluir_id
    AND greatest(
      extensions.similarity(e.razon_social_norm, obras_normalizar(p_razon_social)),
      CASE
        WHEN p_nombre_comercial IS NULL OR e.nombre_comercial_norm IS NULL THEN 0
        ELSE extensions.similarity(e.nombre_comercial_norm, obras_normalizar(p_nombre_comercial))
      END
    ) >= 0.45
  ORDER BY extensions.similarity(e.razon_social_norm, obras_normalizar(p_razon_social)) DESC
  LIMIT 5;
$$;

DROP FUNCTION IF EXISTS obras_buscar_duplicados_persona(text, text, text, text);

CREATE FUNCTION obras_buscar_duplicados_persona(
  p_nombre     text,
  p_apellido   text DEFAULT NULL,
  p_email      text DEFAULT NULL,
  p_telefono   text DEFAULT NULL,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  persona_id  uuid,
  nombre      text,
  apellido    text,
  empresa     text,
  coincide    text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT p.id, p.nombre, p.apellido,
         (
           SELECT e.razon_social
           FROM obras_persona_empresa pe
           JOIN obras_empresas e ON e.id = pe.empresa_id AND e.activo
           WHERE pe.persona_id = p.id AND pe.activo
           ORDER BY pe.es_principal DESC
           LIMIT 1
         ),
         CASE
           WHEN p.email_norm IS NOT NULL
            AND p.email_norm = nullif(lower(btrim(coalesce(p_email, ''))), '') THEN 'email'
           WHEN p.telefono_norm IS NOT NULL
            AND p.telefono_norm = obras_normalizar_telefono(p_telefono) THEN 'telefono'
           ELSE 'nombre'
         END
  FROM obras_personas p
  WHERE p.activo
    AND p.id IS DISTINCT FROM p_excluir_id
    AND (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
    AND (
      (p.email_norm IS NOT NULL
        AND p.email_norm = nullif(lower(btrim(coalesce(p_email, ''))), ''))
      OR (p.telefono_norm IS NOT NULL
        AND p.telefono_norm = obras_normalizar_telefono(p_telefono))
      OR extensions.similarity(
           p.nombre_norm,
           obras_normalizar(p_nombre || ' ' || coalesce(p_apellido, ''))
         ) >= 0.55
    )
  LIMIT 5;
$$;

-- ============================================================
-- 6. Guardar referente en una sola transacción
--
-- SECURITY INVOKER: la autoridad sigue en las policies de
-- `obras_obra_referente`, que exigen `obras_referentes` y que la obra sea
-- propia. El ON CONFLICT apunta al unique parcial (obra_id, persona_id)
-- WHERE activo, así que reasignar la comisión de un referente que ya está es
-- un UPDATE y no un INSERT que choca.
--
-- Un referente dado de baja no revive por acá: su fila tiene activo = false y
-- el índice parcial no la ve, así que se inserta una nueva. Es lo correcto —
-- volver a poner un referente es un acto nuevo, no deshacer el anterior.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_guardar_referente(
  p_obra_id             uuid,
  p_persona_id          uuid,
  p_porcentaje_comision numeric,
  p_observaciones       text DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $$
  INSERT INTO obras_obra_referente (obra_id, persona_id, porcentaje_comision, observaciones)
  VALUES (p_obra_id, p_persona_id, p_porcentaje_comision, p_observaciones)
  ON CONFLICT (obra_id, persona_id) WHERE activo
  DO UPDATE SET porcentaje_comision = excluded.porcentaje_comision,
                observaciones       = excluded.observaciones
  RETURNING id;
$$;

-- ============================================================
-- 7. GRANTs — mismo criterio que sql/029: nada para PUBLIC
-- ============================================================
REVOKE EXECUTE ON FUNCTION obras_auditoria_accesos(int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_auditoria_transferencias(int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_buscar_duplicados_obra(text, text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_buscar_duplicados_empresa(text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_buscar_duplicados_persona(text, text, text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_guardar_referente(uuid, uuid, numeric, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION obras_auditoria_accesos(int) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_auditoria_transferencias(int) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_buscar_duplicados_obra(text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_buscar_duplicados_empresa(text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_buscar_duplicados_persona(text, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION obras_guardar_referente(uuid, uuid, numeric, text) TO authenticated;
