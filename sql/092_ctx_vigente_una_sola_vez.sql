-- sql/092 — la vigencia del grant contextual se escribe una sola vez
--
-- Cambio estructural que sql/090 dejó a mitad, de la misma auditoría de
-- compartir/transferir. No es un refactor cosmético: al unificar apareció un
-- séptimo lugar donde la regla estaba escrita mal.
--
-- LA REGLA. Un grant contextual vale mientras se cumplan tres cosas a la vez:
--
--   1. la fila de grant está activa,
--   2. el vínculo entidad↔ancla sigue vivo,
--   3. quien lo recibió sigue viendo el ancla.
--
-- (3) la agregó sql/090, y la agregó en cuatro lugares: los dos
-- `obras_*_grant_ctx_vigente` y la rama contextual de las dos `obras_ficha_*`.
-- El `BACKLOG.md` decía "seis" y decía que en los seis quedaba correcta. Eran
-- siete y quedaban cuatro: los tres `obras_*_grant_ctx_*_conmigo` no se
-- tocaron y siguen chequeando solo (1).
--
-- EL AGUJERO. Dos de esos tres se salvan por el llamador:
-- `obras_obra_persona_select` y `obras_obra_empresa_select` los usan detrás de
-- `obras_obra_compartida_conmigo(obra_id)`, que es (3), y la fila que filtran
-- es el vínculo mismo, que es (2). El tercero no tiene quien lo cubra:
--
--   obras_persona_empresa_select
--     = obras_puede_ver_persona(persona_id)
--       OR obras_persona_grant_ctx_empresa_conmigo(persona_id, empresa_id)
--
-- La segunda rama no verifica el ancla en ningún lado. Un grant de persona
-- anclado en una empresa que el receptor ya no ve —la empresa se transfirió,
-- su propio grant contextual murió, el vínculo obra↔empresa se apagó— sigue
-- dejando leer la fila persona↔empresa por PostgREST directo: `cargo`,
-- `es_principal`, `observaciones`. Es identidad, no contacto (el contacto está
-- revocado a nivel columna desde sql/039 y sql/085), y es exactamente la clase
-- que sql/090 cerró. Sobrevivió porque la regla estaba escrita siete veces.
--
-- LA FORMA DE QUE NO VUELVA. Una sola
-- `obras_ctx_vigente(tipo, entidad, ancla_tipo, ancla_id)`; el ancla en NULL
-- pregunta "¿hay alguno vigente?" y el ancla dada pregunta "¿este?". Las cinco
-- funciones viejas se dropean en vez de quedar como envoltorios: sus nombres
-- son parte de por qué el agujero pasó desapercibido —`_grant_ctx_empresa_
-- conmigo` promete "hay un grant mío anclado ahí", que es (1) y nada más—, y un
-- nombre que dice menos que la regla es el próximo bug.
--
-- RECURSIÓN. La rama persona-anclada-en-empresa pregunta si se ve la empresa
-- ancla, y una de las respuestas es que la empresa esté vigente por su propio
-- grant: `obras_ctx_vigente` se llama a sí misma con tipo `empresa`. La cadena
-- termina — la rama empresa nunca vuelve a persona — y Postgres acepta la
-- autorreferencia en una función `LANGUAGE sql`. Verificado antes de escribirla.
--
-- QUÉ SE ENDURECE. Los tres `_conmigo` ganan (2) y (3), así que tres lecturas
-- se cierran donde antes pasaban:
--   · la fila persona↔empresa del agujero de arriba;
--   · un vínculo obra↔persona / obra↔empresa desactivado deja de leerse por
--     grant contextual (los callers ya filtran `activo`, así que no cambia
--     ninguna pantalla);
--   · en `obras_vinculos_de_obra`, el `detalle` de una persona —la razón social
--     de la empresa que representa en esa obra— deja de salir cuando el grant
--     de esa empresa quedó huérfano. Coherente: ese mismo grant ya no abre la
--     ficha de la empresa desde sql/090.
--
-- De paso, `auth.uid()` suelto pasa a `(select auth.uid())` en las dos policies
-- que lo tenían así (GUIDE_DB: suelto es VOLATILE y se re-evalúa por fila).
--
-- Test: sql/tests/obras_092.sql

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · La regla, una sola vez
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_ctx_vigente(
  p_tipo       text,
  p_entidad_id uuid,
  p_ancla_tipo text DEFAULT NULL,
  p_ancla_id   uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE p_tipo

    -- El ancla de una empresa solo puede ser una obra: una empresa no cuelga de
    -- otra empresa. Un `p_ancla_tipo` distinto de 'obra' no matchea y da false,
    -- que es el mismo corte que OB031 hace explícito en obras_revocar_contextual.
    WHEN 'empresa' THEN EXISTS (
      SELECT 1 FROM public.obras_empresa_grant_contextual g
      WHERE g.empresa_id = p_entidad_id
        AND g.usuario_id = (select auth.uid())
        AND g.activo
        AND (p_ancla_tipo IS NULL OR (p_ancla_tipo = 'obra' AND g.obra_id = p_ancla_id))
        AND obras_puede_ver_obra(g.obra_id)
        AND EXISTS (
          SELECT 1 FROM public.obras_obra_empresa oe
          WHERE oe.obra_id = g.obra_id AND oe.empresa_id = g.empresa_id AND oe.activo
        )
    )

    WHEN 'persona' THEN EXISTS (
      SELECT 1 FROM public.obras_persona_grant_contextual g
      WHERE g.persona_id = p_entidad_id
        AND g.usuario_id = (select auth.uid())
        AND g.activo
        AND (
          (g.obra_id IS NOT NULL
           AND (p_ancla_tipo IS NULL OR (p_ancla_tipo = 'obra' AND g.obra_id = p_ancla_id))
           AND obras_puede_ver_obra(g.obra_id)
           AND EXISTS (
             SELECT 1 FROM public.obras_obra_persona op
             WHERE op.obra_id = g.obra_id AND op.persona_id = g.persona_id AND op.activo
           ))
          OR
          (g.empresa_id IS NOT NULL
           AND (p_ancla_tipo IS NULL OR (p_ancla_tipo = 'empresa' AND g.empresa_id = p_ancla_id))
           AND (obras_puede_ver_empresa(g.empresa_id)
                OR obras_ctx_vigente('empresa', g.empresa_id))
           AND EXISTS (
             SELECT 1 FROM public.obras_persona_empresa pe
             WHERE pe.empresa_id = g.empresa_id AND pe.persona_id = g.persona_id AND pe.activo
           ))
        )
    )

    ELSE false
  END;
$$;

REVOKE EXECUTE ON FUNCTION obras_ctx_vigente(text, uuid, text, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION obras_ctx_vigente(text, uuid, text, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · Las cinco policies que la usaban
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS obras_personas_select ON obras_personas;
CREATE POLICY obras_personas_select ON obras_personas
  FOR SELECT USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
    AND (
      creado_por = (select auth.uid())
      OR obras_puede_ver_persona(id)
      OR obras_ctx_vigente('persona', id)
    )
  );

DROP POLICY IF EXISTS obras_empresas_select ON obras_empresas;
CREATE POLICY obras_empresas_select ON obras_empresas
  FOR SELECT USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
    AND (
      creado_por = (select auth.uid())
      OR (pendiente AND tiene_permiso('obras_aprobar'))
      OR ((NOT pendiente) AND (
            tiene_permiso('obras_empresas_todas')
            OR obras_ctx_vigente('empresa', id)
          ))
    )
  );

DROP POLICY IF EXISTS obras_obra_persona_select ON obras_obra_persona;
CREATE POLICY obras_obra_persona_select ON obras_obra_persona
  FOR SELECT USING (
    creado_por = (select auth.uid())
    OR obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (obras_obra_compartida_conmigo(obra_id)
        AND obras_ctx_vigente('persona', persona_id, 'obra', obra_id))
  );

DROP POLICY IF EXISTS obras_obra_empresa_select ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_select ON obras_obra_empresa
  FOR SELECT USING (
    creado_por = (select auth.uid())
    OR obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (obras_obra_compartida_conmigo(obra_id)
        AND obras_ctx_vigente('empresa', empresa_id, 'obra', obra_id))
  );

-- La del agujero. La rama contextual pasa de "hay un grant" a la regla entera.
DROP POLICY IF EXISTS obras_persona_empresa_select ON obras_persona_empresa;
CREATE POLICY obras_persona_empresa_select ON obras_persona_empresa
  FOR SELECT USING (
    obras_puede_ver_persona(persona_id)
    OR obras_ctx_vigente('persona', persona_id, 'empresa', empresa_id)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 3 · Las dos fichas: la rama contextual colapsa a una línea
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_ficha_persona(
  p_persona_id uuid,
  p_ctx_tipo   text DEFAULT NULL,
  p_ctx_id     uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid, nombre text, apellido text, telefono text, whatsapp text, email text,
  observaciones text, creado_por uuid,
  created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ok boolean;
BEGIN
  v_ok := obras_puede_ver_persona(p_persona_id);

  IF NOT v_ok AND p_ctx_tipo IS NOT NULL AND p_ctx_id IS NOT NULL THEN
    v_ok := obras_ctx_vigente('persona', p_persona_id, p_ctx_tipo, p_ctx_id);
  END IF;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'Sin acceso a esta persona' USING ERRCODE = 'OB022';
  END IF;

  INSERT INTO obras_accesos_persona (usuario_id, persona_id, contexto)
  VALUES (auth.uid(), p_persona_id, nullif(concat_ws(':', p_ctx_tipo, p_ctx_id::text), ''));

  RETURN QUERY
  SELECT p.id, p.nombre, p.apellido, p.telefono, p.whatsapp, p.email,
         p.observaciones, p.creado_por, p.created_at, p.updated_at
  FROM obras_personas p
  WHERE p.id = p_persona_id AND p.activo;
END;
$$;

CREATE OR REPLACE FUNCTION obras_ficha_empresa(
  p_empresa_id  uuid,
  p_ctx_obra_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid, razon_social text, nombre_comercial text, telefono text, email text,
  website text, direccion text, localidad text, provincia provincia,
  observaciones text, creado_por uuid,
  created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ok boolean;
BEGIN
  v_ok := obras_puede_ver_empresa(p_empresa_id);

  IF NOT v_ok AND p_ctx_obra_id IS NOT NULL THEN
    v_ok := obras_ctx_vigente('empresa', p_empresa_id, 'obra', p_ctx_obra_id);
  END IF;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'Sin acceso a esta empresa' USING ERRCODE = 'OB030';
  END IF;

  RETURN QUERY
  SELECT e.id, e.razon_social, e.nombre_comercial, e.telefono, e.email,
         e.website, e.direccion, e.localidad, e.provincia, e.observaciones,
         e.creado_por, e.created_at, e.updated_at
  FROM obras_empresas e
  WHERE e.id = p_empresa_id AND e.activo;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4 · obras_vinculos_de_obra — tres llamadas, misma regla
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_vinculos_de_obra(p_obra_id uuid)
RETURNS TABLE (
  tipo text, vinculo_id uuid, entidad_id uuid, nombre text, detalle text,
  roles text[], observaciones text, empresa_id uuid,
  creado_por uuid, creado_por_nombre text, es_de_receptor boolean
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
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
          AND obras_ctx_vigente('empresa', oe.empresa_id, 'obra', p_obra_id))
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
            OR obras_puede_ver_empresa(op.empresa_id)
            OR obras_ctx_vigente('empresa', op.empresa_id, 'obra', p_obra_id)) AS empresa_visible
  ) vis
  WHERE op.obra_id = p_obra_id AND op.activo
    AND (
      op.creado_por = auth.uid()
      OR obras_es_mi_obra(p_obra_id)
      OR tiene_permiso('obras_transferir')
      OR (obras_obra_compartida_conmigo(p_obra_id)
          AND obras_ctx_vigente('persona', op.persona_id, 'obra', p_obra_id))
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5 · Las cinco que sobran
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS obras_persona_grant_ctx_vigente(uuid);
DROP FUNCTION IF EXISTS obras_empresa_grant_ctx_vigente(uuid);
DROP FUNCTION IF EXISTS obras_persona_grant_ctx_obra_conmigo(uuid, uuid);
DROP FUNCTION IF EXISTS obras_persona_grant_ctx_empresa_conmigo(uuid, uuid);
DROP FUNCTION IF EXISTS obras_empresa_grant_ctx_obra_conmigo(uuid, uuid);

COMMIT;
