-- ============================================================
-- 082 — Compartir una obra/empresa no reparte contactos
--
-- Hasta acá el checklist de `obras_compartir_obra` / `_empresa` daba un grant
-- COMPLETO (`obras_persona_compartida` + `origen_*`): la persona entraba a la
-- agenda del receptor, a su buscador y a su listado. Después hubo que recortar
-- ese grant tres veces —sql/052 (no puede colgarla de sus obras), sql/070 (no
-- ve la razón social de su empresa), sql/049 (estado deseado para poder
-- desarmar la cascada)—. Cada parche lo acercó a algo que ya existía al lado:
-- el grant contextual de `obras_transferir` (sql/041), que ancla en obra XOR
-- empresa, muere con el vínculo y no entra a ninguna agenda.
--
-- Decidido: el checklist escribe `obras_persona_grant_contextual`. Transferir y
-- compartir pasan a tener UNA regla — el contacto ajeno se ve dentro de la
-- ficha que lo trajo, nunca en la agenda. El ancla del grant ES el origen, así
-- que `origen_obra_id` / `origen_empresa_id` de `obras_persona_compartida`
-- sobran y se dropean.
--
-- EMPRESAS NO CAMBIAN. Siguen con grant completo + `origen_obra_id`. Una
-- empresa no tiene dónde esconderse: no hay `obras_ficha_empresa()` DEFINER ni
-- columnas revocadas, así que "contextual" sería solo de UI, y la UI no es
-- barrera. Es además lo que `obras_transferir` ya decidió ("el resto entra a la
-- agenda del receptor (empresa no es sensible)"). El dato sensible de una
-- empresa es su gente, y esa sí pasa a contextual.
--
-- DOS LECTURAS QUE HAY QUE ABRIR, o el receptor deja de ver la fila:
--   · `obras_vinculos_de_obra` mostraba la persona solo con grant COMPLETO
--     (sql/051). Sin esto, compartís la obra y el receptor no ve ninguna.
--   · `obras_persona_empresa_select` (sql/027) es `obras_puede_ver_persona`,
--     que no cuenta contextuales. Sin esto, la ficha de empresa compartida
--     queda sin empleados.
-- `obras_personas_select` (sql/039) ya admite el contextual: el nombre sale por
-- RLS y el contacto sigue saliendo solo por `obras_ficha_persona(..., ctx)`,
-- que registra en `obras_accesos_persona`.
--
-- `obras_revocar_persona` NO cambia: sigue bajando el grant directo Y los
-- contextuales de esa persona para ese usuario. Revocar una persona es el corte
-- total que dice el botón, y es lo que hace funcionar el revocar de la vista
-- Compartido sobre una fila de cascada.
--
-- BUG PREEXISTENTE ARREGLADO ACÁ: `obras_revocar_empresa` perdió la cascada de
-- personas al reescribirse en sql/052 (quedó la de `obras_obra_empresa` y se
-- cayó la de `origen_empresa_id`). Revocar una empresa dejaba vivos los grants
-- de las personas tildadas en su checklist. La versión de abajo la restituye
-- como cascada por ancla.
--
-- Backfill: los grants de persona con origen pasan a contextuales.
-- ============================================================

-- ============================================================
-- 1. Helpers — grant contextual anclado, por ancla
--
-- `obras_persona_grant_ctx_vigente` (sql/039) contesta "hay alguno", que es lo
-- que la policy de `obras_personas` necesita. Acá hace falta "anclado a ESTA
-- obra/empresa": si no, un grant traído por la obra A abriría la fila en la
-- obra B. DEFINER y con parámetro —un EXISTS inline en la policy con la columna
-- sin calificar repite el sombreado de sql/047-048.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_persona_grant_ctx_obra_conmigo(
  p_persona_id uuid, p_obra_id uuid
)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_persona_grant_contextual g
    WHERE g.persona_id = p_persona_id AND g.obra_id = p_obra_id
      AND g.usuario_id = auth.uid() AND g.activo
  );
$$;

CREATE OR REPLACE FUNCTION obras_persona_grant_ctx_empresa_conmigo(
  p_persona_id uuid, p_empresa_id uuid
)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_persona_grant_contextual g
    WHERE g.persona_id = p_persona_id AND g.empresa_id = p_empresa_id
      AND g.usuario_id = auth.uid() AND g.activo
  );
$$;

-- ============================================================
-- 2. Backfill — la cascada de persona pasa a contextual
--
-- Antes de tocar las funciones: lo que hoy está compartido por checklist se
-- reescribe como grant contextual con el mismo ancla, y el grant completo se
-- baja. Un grant directo (origen NULL) no se toca.
-- ============================================================
INSERT INTO obras_persona_grant_contextual
  (persona_id, usuario_id, obra_id, otorgada_por, activo)
SELECT c.persona_id, c.usuario_id, c.origen_obra_id, c.otorgada_por, true
FROM obras_persona_compartida c
WHERE c.activo AND c.origen_obra_id IS NOT NULL
ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
DO UPDATE SET activo = true, updated_at = now();

INSERT INTO obras_persona_grant_contextual
  (persona_id, usuario_id, empresa_id, otorgada_por, activo)
SELECT c.persona_id, c.usuario_id, c.origen_empresa_id, c.otorgada_por, true
FROM obras_persona_compartida c
WHERE c.activo AND c.origen_empresa_id IS NOT NULL
ON CONFLICT (persona_id, usuario_id, empresa_id) WHERE empresa_id IS NOT NULL
DO UPDATE SET activo = true, updated_at = now();

UPDATE obras_persona_compartida
  SET activo = false, updated_at = now()
  WHERE activo AND (origen_obra_id IS NOT NULL OR origen_empresa_id IS NOT NULL);

-- ============================================================
-- 3. obras_compartir_obra — personas tildadas → grant contextual
--
-- Empresas: sin cambios (grant completo + origen, estado deseado de sql/049).
-- Personas: el ancla es la obra. Destildar apaga el grant de ESTA obra; uno
-- anclado a otra obra, o un share directo, no se toca.
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

  -- Personas tildadas: vinculadas a esta obra y mías (no congeladas). El
  -- contacto se abre dentro de esta obra, no entra a la agenda del receptor.
  INSERT INTO obras_persona_grant_contextual
    (persona_id, usuario_id, obra_id, otorgada_por, activo)
  SELECT DISTINCT op.persona_id, p_usuario_id, p_obra_id, auth.uid(), true
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    AND op.persona_id = ANY(p_personas)
  ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  UPDATE obras_empresa_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (empresa_id = ANY(p_empresas));

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (persona_id = ANY(p_personas));
END;
$$;

-- ============================================================
-- 4. obras_compartir_empresa — personas tildadas → grant contextual
-- ============================================================
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

  INSERT INTO obras_empresa_compartida (empresa_id, usuario_id, otorgada_por, activo)
  VALUES (p_empresa_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (empresa_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = NULL;

  INSERT INTO obras_persona_grant_contextual
    (persona_id, usuario_id, empresa_id, otorgada_por, activo)
  SELECT DISTINCT pe.persona_id, p_usuario_id, p_empresa_id, auth.uid(), true
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    AND pe.persona_id = ANY(p_personas)
  ON CONFLICT (persona_id, usuario_id, empresa_id) WHERE empresa_id IS NOT NULL
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo
      AND NOT (persona_id = ANY(p_personas));
END;
$$;

-- ============================================================
-- 5. obras_compartir_persona — sin origen que limpiar
--
-- `obras_persona_compartida` pasa a tener un solo significado: acceso completo,
-- acto directo del dueño sobre esa persona. El contextual vive en su tabla.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_compartir_persona(p_persona_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte una persona a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM obras_personas p
    WHERE p.id = p_persona_id AND p.creado_por = auth.uid()
      AND p.activo AND NOT p.pendiente
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la persona puede compartirla' USING ERRCODE = 'OB020';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario_id AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  INSERT INTO obras_persona_compartida (persona_id, usuario_id, otorgada_por, activo)
  VALUES (p_persona_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (persona_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();
END;
$$;

-- ============================================================
-- 6. Revocar — la cascada de persona cae por ancla
-- ============================================================
CREATE OR REPLACE FUNCTION obras_revocar_obra(p_obra_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras o WHERE o.id = p_obra_id AND o.responsable_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede revocar el acceso' USING ERRCODE = 'OB026';
  END IF;

  UPDATE obras_obra_compartida
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id AND activo;

  UPDATE obras_empresa_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  -- Vincular no es compartir: los vínculos que el receptor agregó a esta obra
  -- se caen cuando pierde el acceso (sql/051).
  UPDATE obras_obra_empresa
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;

  UPDATE obras_obra_persona
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;
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

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  -- Los vínculos que el receptor armó con esta empresa en SUS obras (sql/052).
  UPDATE obras_obra_empresa
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND creado_por = p_usuario_id AND activo;
END;
$$;

-- ============================================================
-- 7. obras_persona_grant_directo — sin origen, todo share de persona es directo
-- ============================================================
CREATE OR REPLACE FUNCTION obras_persona_grant_directo(p_persona_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_persona_compartida c
    WHERE c.persona_id = p_persona_id AND c.usuario_id = auth.uid() AND c.activo
  );
$$;

-- ============================================================
-- 8. obras_vinculos_de_obra — el receptor ve la fila con grant contextual
--
-- Sin esto el cambio rompe la función entera: la rama de persona exigía grant
-- COMPLETO (sql/051) y ahora el checklist no otorga ninguno.
-- `detalle` (la razón social de la empresa del vínculo) no cambia: sigue
-- gateado por `obras_puede_ver_empresa` (sql/070).
-- ============================================================
CREATE OR REPLACE FUNCTION obras_vinculos_de_obra(p_obra_id uuid)
RETURNS TABLE (
  tipo              text,
  vinculo_id        uuid,
  entidad_id        uuid,
  nombre            text,
  detalle           text,
  roles             text[],
  observaciones     text,
  empresa_id        uuid,
  creado_por        uuid,
  creado_por_nombre text,
  es_de_receptor    boolean
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT obras_puede_ver_obra(p_obra_id) THEN
    RAISE EXCEPTION 'Sin acceso a esta obra' USING ERRCODE = 'OB022';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, oe.id, e.id, e.razon_social, NULL::text,
         oe.roles::text[], oe.observaciones, NULL::uuid,
         oe.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, oe.creado_por)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  JOIN usuarios u       ON u.id = oe.creado_por
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND (
      oe.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_empresa_compartida_conmigo(oe.empresa_id))
    )

  UNION ALL
  SELECT 'persona'::text, op.id, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         CASE WHEN vis.empresa_visible THEN e2.razon_social END,
         op.roles::text[], op.observaciones, op.empresa_id,
         op.creado_por, u.nombre,
         obras_obra_compartida_con(p_obra_id, op.creado_por)
  FROM obras_obra_persona op
  JOIN obras_personas p       ON p.id = op.persona_id
  JOIN usuarios u             ON u.id = op.creado_por
  LEFT JOIN obras_empresas e2 ON e2.id = op.empresa_id
  CROSS JOIN LATERAL (
    SELECT op.empresa_id IS NOT NULL
       AND (obras_es_mi_obra(p_obra_id)
            OR tiene_permiso('obras_transferir')
            OR obras_puede_ver_empresa(op.empresa_id)) AS empresa_visible
  ) vis
  WHERE op.obra_id = p_obra_id AND op.activo
    AND (
      op.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND (obras_persona_compartida_conmigo(op.persona_id)
               OR obras_persona_grant_ctx_obra_conmigo(op.persona_id, p_obra_id)))
    );
END;
$$;

-- ============================================================
-- 9. obras_persona_empresa_select — el empleado sale con grant contextual
--
-- Acotado al ancla: la fila se ve dentro de la empresa que la otorgó, no en
-- cualquier empresa donde esa persona figure.
-- ============================================================
DROP POLICY IF EXISTS obras_persona_empresa_select ON obras_persona_empresa;
CREATE POLICY obras_persona_empresa_select ON obras_persona_empresa FOR SELECT
  USING (
    obras_puede_ver_persona(persona_id)
    OR obras_persona_grant_ctx_empresa_conmigo(persona_id, empresa_id)
  );

-- ============================================================
-- 10. Checklist — `ya_compartida` mira el grant contextual de ESTE padre
--
-- Un share directo también cuenta: la persona ya tiene acceso completo, tildarla
-- no agrega nada. Destildarla solo apaga el contextual, no toca el directo.
-- (Referencias calificadas por alias: `id` es el OUT param — lección sql/048.)
-- ============================================================
CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_obra(
  p_obra_id uuid, p_usuario_id uuid
)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text, ya_compartida boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id AND o.responsable_id = auth.uid() AND o.activo
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, e.id, e.razon_social,
         nullif(array_to_string(oe.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_empresa_compartida c
                 WHERE c.empresa_id = e.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo
  UNION ALL
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         nullif(array_to_string(op.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_persona_grant_contextual g
                 WHERE g.persona_id = p.id AND g.usuario_id = p_usuario_id
                   AND g.obra_id = p_obra_id AND g.activo)
         OR EXISTS (SELECT 1 FROM obras_persona_compartida c
                 WHERE c.persona_id = p.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente;
END;
$$;

CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_empresa(
  p_empresa_id uuid, p_usuario_id uuid
)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text, ya_compartida boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras_empresas e
    WHERE e.id = p_empresa_id AND e.creado_por = auth.uid() AND e.activo
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
  END IF;

  RETURN QUERY
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         nullif(pe.cargo, ''),
         EXISTS (SELECT 1 FROM obras_persona_grant_contextual g
                 WHERE g.persona_id = p.id AND g.usuario_id = p_usuario_id
                   AND g.empresa_id = p_empresa_id AND g.activo)
         OR EXISTS (SELECT 1 FROM obras_persona_compartida c
                 WHERE c.persona_id = p.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente;
END;
$$;

-- ============================================================
-- 11. Vista Compartido — la persona de cascada sale de la tabla contextual
--
-- El origen ya no es una columna aparte: es el ancla del grant. La rama de
-- persona se parte en dos — directo (`obras_persona_compartida`, sin origen) y
-- contextual (anclado, se anida bajo su padre en `CompartidoView`).
-- ============================================================
CREATE OR REPLACE FUNCTION obras_compartidos_por_mi()
RETURNS TABLE (
  tipo           text,
  entidad_id     uuid,
  entidad_nombre text,
  usuario_id     uuid,
  usuario_nombre text,
  origen_tipo    text,
  origen_id      uuid,
  origen_nombre  text,
  compartida_el  timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_compartido') THEN
    RAISE EXCEPTION 'Sin acceso a la vista Compartido' USING ERRCODE = 'OB027';
  END IF;

  RETURN QUERY
  SELECT 'obra'::text, c.obra_id, o.nombre, c.usuario_id, u.nombre,
         NULL::text, NULL::uuid, NULL::text, c.created_at
  FROM obras_obra_compartida c
  JOIN obras o     ON o.id = c.obra_id
  JOIN usuarios u  ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'empresa'::text, c.empresa_id, e.razon_social, c.usuario_id, u.nombre,
         CASE WHEN c.origen_obra_id IS NOT NULL THEN 'obra' END,
         c.origen_obra_id,
         CASE WHEN c.origen_obra_id IS NOT NULL
              THEN (SELECT nombre FROM obras WHERE id = c.origen_obra_id) END,
         c.created_at
  FROM obras_empresa_compartida c
  JOIN obras_empresas e ON e.id = c.empresa_id
  JOIN usuarios u       ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'persona'::text, c.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         c.usuario_id, u.nombre,
         NULL::text, NULL::uuid, NULL::text, c.created_at
  FROM obras_persona_compartida c
  JOIN obras_personas p ON p.id = c.persona_id
  JOIN usuarios u       ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'persona'::text, g.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         g.usuario_id, u.nombre,
         CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
         coalesce(g.obra_id, g.empresa_id),
         CASE WHEN g.obra_id IS NOT NULL
              THEN (SELECT nombre FROM obras WHERE id = g.obra_id)
              ELSE (SELECT razon_social FROM obras_empresas WHERE id = g.empresa_id) END,
         g.created_at
  FROM obras_persona_grant_contextual g
  JOIN obras_personas p ON p.id = g.persona_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.otorgada_por = auth.uid() AND g.activo

  ORDER BY 9 DESC
  LIMIT 500;
END;
$$;

-- ============================================================
-- 12. obras_compartir_registros (Tareas) — la persona también va contextual
--
-- Decisión del usuario: nada de compartir reparte contactos, tampoco al asignar
-- una tarea. El ancla es la misma que sql/062 ya buscaba para el origen —una
-- obra (o empresa) mía, activa, vinculada a esa persona y ya compartida con ese
-- usuario en esta llamada o de antes—, así que el vínculo que el grant
-- contextual valida en vivo existe por construcción. Sin ancla no hay grant
-- posible: corta con OB029 en vez de otorgar algo que no abre nada.
--
-- OJO — ESTO DEJA EL FLUJO DE TAREAS A MEDIO CAMINO, A PROPÓSITO. Ni con ancla
-- el receptor puede abrir la ficha desde la tarea: `obras_puede_ver_persona_de`
-- (y por lo tanto `puede_abrir_registro`) no cuenta contextuales, y el chip sale
-- de `entes.ruta` sin `?ctx=`. O sea que "compartir al asignar" va a seguir
-- ofreciéndose para esa persona. La reparación —ancla `tarea_id` en
-- `obras_persona_grant_contextual`, su rama en `obras_ficha_persona`, el chip
-- con ctx y `obras_puede_abrir` aprendiéndola— queda anotada en BACKLOG.md.
--
-- La rama de empresa no cambia. Firma y GRANTs intactos.
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_compartir_registros(p_usuario uuid, p_registros jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  x                jsonb;
  v_ente           text;
  v_id             uuid;
  v_origen_obra    uuid;
  v_origen_empresa uuid;
BEGIN
  IF p_usuario = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte un registro a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  FOR x IN
    SELECT e
    FROM jsonb_array_elements(COALESCE(p_registros, '[]'::jsonb)) AS e
    ORDER BY CASE e->>'ente' WHEN 'obra' THEN 1 WHEN 'empresa' THEN 2 ELSE 3 END
  LOOP
    v_ente := x->>'ente';
    v_id   := (x->>'registro_id')::uuid;

    IF v_ente = 'obra' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras o WHERE o.id = v_id AND o.responsable_id = auth.uid() AND o.activo
      ) THEN
        RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
      END IF;

      INSERT INTO obras_obra_compartida (obra_id, usuario_id, otorgada_por, activo)
      VALUES (v_id, p_usuario, auth.uid(), true)
      ON CONFLICT (obra_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now()
        WHERE NOT obras_obra_compartida.activo;

    ELSIF v_ente = 'empresa' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras_empresas e
        WHERE e.id = v_id AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
      ) THEN
        RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
      END IF;

      SELECT oe.obra_id INTO v_origen_obra
      FROM obras_obra_empresa oe
      JOIN obras o ON o.id = oe.obra_id AND o.responsable_id = auth.uid() AND o.activo
      JOIN obras_obra_compartida c ON c.obra_id = oe.obra_id AND c.usuario_id = p_usuario AND c.activo
      WHERE oe.empresa_id = v_id AND oe.activo
      LIMIT 1;

      INSERT INTO obras_empresa_compartida (empresa_id, usuario_id, otorgada_por, activo, origen_obra_id)
      VALUES (v_id, p_usuario, auth.uid(), true, v_origen_obra)
      ON CONFLICT (empresa_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
            origen_obra_id = EXCLUDED.origen_obra_id
        WHERE NOT obras_empresa_compartida.activo;

    ELSIF v_ente = 'persona' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras_personas p
        WHERE p.id = v_id AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
      ) THEN
        RAISE EXCEPTION 'Solo el dueño de la persona puede compartirla' USING ERRCODE = 'OB020';
      END IF;

      SELECT op.obra_id INTO v_origen_obra
      FROM obras_obra_persona op
      JOIN obras o ON o.id = op.obra_id AND o.responsable_id = auth.uid() AND o.activo
      JOIN obras_obra_compartida c ON c.obra_id = op.obra_id AND c.usuario_id = p_usuario AND c.activo
      WHERE op.persona_id = v_id AND op.activo
      LIMIT 1;

      v_origen_empresa := NULL;
      IF v_origen_obra IS NULL THEN
        SELECT pe.empresa_id INTO v_origen_empresa
        FROM obras_persona_empresa pe
        JOIN obras_empresas e ON e.id = pe.empresa_id AND e.creado_por = auth.uid() AND e.activo
        JOIN obras_empresa_compartida c ON c.empresa_id = pe.empresa_id AND c.usuario_id = p_usuario AND c.activo
        WHERE pe.persona_id = v_id AND pe.activo
        LIMIT 1;
      END IF;

      IF v_origen_obra IS NULL AND v_origen_empresa IS NULL THEN
        RAISE EXCEPTION 'Esa persona no cuelga de ninguna obra o empresa compartida con ese usuario: compartila desde su ficha'
          USING ERRCODE = 'OB029';
      END IF;

      -- Un INSERT por ancla: el ON CONFLICT infiere UN índice parcial, y los de
      -- obra y empresa son dos distintos (`uq_grant_ctx_obra` / `_empresa`).
      IF v_origen_obra IS NOT NULL THEN
        INSERT INTO obras_persona_grant_contextual
          (persona_id, usuario_id, obra_id, otorgada_por, activo)
        VALUES (v_id, p_usuario, v_origen_obra, auth.uid(), true)
        ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
        DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now()
          WHERE NOT obras_persona_grant_contextual.activo;
      ELSE
        INSERT INTO obras_persona_grant_contextual
          (persona_id, usuario_id, empresa_id, otorgada_por, activo)
        VALUES (v_id, p_usuario, v_origen_empresa, auth.uid(), true)
        ON CONFLICT (persona_id, usuario_id, empresa_id) WHERE empresa_id IS NOT NULL
        DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now()
          WHERE NOT obras_persona_grant_contextual.activo;
      END IF;
    END IF;
  END LOOP;
END;
$$;

-- ============================================================
-- 13. Las columnas de origen de persona sobran — el ancla las reemplaza
-- ============================================================
ALTER TABLE obras_persona_compartida DROP COLUMN IF EXISTS origen_obra_id;
ALTER TABLE obras_persona_compartida DROP COLUMN IF EXISTS origen_empresa_id;

-- ============================================================
-- 14. GRANTs
--
-- Los dos helpers nuevos: `_empresa_conmigo` lo necesita `authenticated` porque
-- corre dentro de una policy; `_obra_conmigo` solo lo llama una DEFINER, pero
-- va igual por simetría.
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.obras_persona_grant_ctx_obra_conmigo(uuid, uuid)    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_persona_grant_ctx_empresa_conmigo(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_persona_grant_ctx_obra_conmigo(uuid, uuid)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_persona_grant_ctx_empresa_conmigo(uuid, uuid)  TO authenticated;
