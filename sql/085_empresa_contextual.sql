-- ============================================================
-- 085 — La empresa compartida también es contextual
--
-- Pedido del usuario: "es para no ensuciar la agenda y que quede el mismo
-- acercamiento que las personas".
--
-- `sql/082` pasó personas a grant contextual y dejó empresas con grant
-- COMPLETO, con este argumento: "una empresa no tiene dónde esconderse — no hay
-- `obras_ficha_empresa()` DEFINER ni columnas revocadas, así que contextual
-- sería solo de UI, y la UI no es barrera". El argumento era correcto y la
-- respuesta es construir las dos piezas que faltaban, no bajar el estándar.
--
-- Simetría exacta con persona, que son dos capas y no una:
--   · La FILA (razón social) sale por RLS con grant contextual vigente, igual
--     que el nombre de una persona. El listado no la trae porque `getEmpresas`
--     filtra por dueño + share directo — mismo mecanismo que `getPersonas`.
--   · El CONTACTO (`telefono`/`email`/`direccion`/`website`) sale del
--     `GRANT SELECT` de `authenticated` y pasa a salir solo por
--     `obras_ficha_empresa(empresa, ctx_obra)`, DEFINER, que exige el ancla.
--
-- El ancla de una empresa solo puede ser una obra: una empresa no cuelga de
-- otra empresa. Sin XOR, sin índice parcial — UNIQUE entero, que además es lo
-- que `ON CONFLICT` necesita sin cláusula WHERE.
--
-- SIN `obras_accesos_empresa`. `obras_accesos_persona` existe porque el
-- teléfono de una persona es dato personal y hay que poder auditar quién lo
-- miró. El teléfono de una constructora no. Se suma si alguien lo pide.
--
-- `obras_empresa_compartida` queda con un solo significado —acceso completo,
-- acto directo del dueño— y `origen_obra_id` se dropea, igual que `sql/082`
-- hizo con `obras_persona_compartida.origen_*`. El ancla vive en el grant.
--
-- LECTURAS QUE HAY QUE ABRIR, o el receptor deja de ver la fila:
--   · `obras_obra_empresa_select` (policy) exige `obras_empresa_compartida_conmigo`
--   · `obras_vinculos_de_obra`, rama empresa — misma condición
--   · `obras_vinculos_de_obra`, `detalle` de la rama persona (`sql/070`): la
--     razón social de la empresa del vínculo
--
-- LO QUE NO SE TOCA A PROPÓSITO:
--   · `obras_buscar_*` (sql/042) — el contextual no entra al buscador. Es el punto.
--   · `obras_puede_abrir` / `puede_abrir_registro` (sql/062) — el chip abre sin
--     contexto, así que el contextual no cuenta. Misma regla que persona.
--   · Tareas (`obras_compartir_registros`): la empresa que repartía por grant
--     completo deja de repartirse. El usuario decidió romperlo ahora y
--     repararlo después, igual que `sql/082` con la persona anclada en tarea.
--
-- Backfill: los grants de empresa con `origen_obra_id` pasan a contextuales.
-- ============================================================

-- ============================================================
-- 1. Tabla
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_empresa_grant_contextual (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid NOT NULL REFERENCES obras_empresas(id),
  usuario_id    uuid NOT NULL REFERENCES usuarios(id),
  obra_id       uuid NOT NULL REFERENCES obras(id),
  otorgada_por  uuid NOT NULL REFERENCES usuarios(id),
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT empresa_grant_ctx_no_a_si_mismo CHECK (usuario_id <> otorgada_por),
  CONSTRAINT empresa_grant_ctx_ancla_unica UNIQUE (empresa_id, usuario_id, obra_id)
);

CREATE INDEX IF NOT EXISTS idx_empresa_grant_ctx_usuario
  ON obras_empresa_grant_contextual (usuario_id, empresa_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON obras_empresa_grant_contextual;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON obras_empresa_grant_contextual
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Solo lectura desde el cliente (dueño o receptor). La escritura pasa por las
-- DEFINER de abajo, igual que `obras_persona_grant_contextual`.
ALTER TABLE obras_empresa_grant_contextual ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS empresa_grant_ctx_select ON obras_empresa_grant_contextual;
CREATE POLICY empresa_grant_ctx_select ON obras_empresa_grant_contextual FOR SELECT
  USING (
    usuario_id = (select auth.uid())
    OR EXISTS (
      SELECT 1 FROM obras_empresas e
      WHERE e.id = empresa_id AND e.creado_por = (select auth.uid())
    )
  );

GRANT SELECT ON public.obras_empresa_grant_contextual TO authenticated;

-- ============================================================
-- 2. Helpers
--
-- `_vigente` contesta "hay alguno" y sirve a la policy de `obras_empresas`.
-- `_obra_conmigo` corta por padre, para que un grant traído por la obra A no
-- abra la fila en la obra B. Los dos validan el vínculo en vivo: el grant muere
-- con él, sin trigger de limpieza (misma decisión que `sql/039`).
-- ============================================================
CREATE OR REPLACE FUNCTION obras_empresa_grant_ctx_vigente(p_empresa_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_empresa_grant_contextual g
    WHERE g.empresa_id = p_empresa_id AND g.usuario_id = (select auth.uid()) AND g.activo
      AND EXISTS (
        SELECT 1 FROM public.obras_obra_empresa oe
        WHERE oe.obra_id = g.obra_id AND oe.empresa_id = g.empresa_id AND oe.activo
      )
  );
$$;

CREATE OR REPLACE FUNCTION obras_empresa_grant_ctx_obra_conmigo(
  p_empresa_id uuid, p_obra_id uuid
)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_empresa_grant_contextual g
    WHERE g.empresa_id = p_empresa_id AND g.obra_id = p_obra_id
      AND g.usuario_id = (select auth.uid()) AND g.activo
  );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_empresa_grant_ctx_vigente(uuid)             FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_empresa_grant_ctx_obra_conmigo(uuid, uuid)  FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.obras_empresa_grant_ctx_vigente(uuid)             TO authenticated;
GRANT  EXECUTE ON FUNCTION public.obras_empresa_grant_ctx_obra_conmigo(uuid, uuid)  TO authenticated;

-- ============================================================
-- 3. Backfill — la cascada de empresa pasa a contextual
--
-- Antes de tocar las funciones. Un grant directo (origen NULL) no se toca.
-- ============================================================
INSERT INTO obras_empresa_grant_contextual
  (empresa_id, usuario_id, obra_id, otorgada_por, activo)
SELECT c.empresa_id, c.usuario_id, c.origen_obra_id, c.otorgada_por, true
FROM obras_empresa_compartida c
WHERE c.activo AND c.origen_obra_id IS NOT NULL
ON CONFLICT (empresa_id, usuario_id, obra_id)
DO UPDATE SET activo = true, updated_at = now();

UPDATE obras_empresa_compartida
  SET activo = false, updated_at = now()
  WHERE activo AND origen_obra_id IS NOT NULL;

-- ============================================================
-- 4. El contacto de la empresa se protege a nivel columna
--
-- Simétrico a `sql/039` sobre `obras_personas`. La fila tiene que ser visible
-- para mostrar la razón social dentro de la ficha de la obra; con las columnas
-- abiertas eso alcanzaría para leer el teléfono con un `select` directo.
--
-- `localidad` y `provincia` SE QUEDAN: no son contacto, y el detector de
-- duplicados y `obras_buscar_empresas` las devuelven (enmascaradas cuando
-- corresponde). Las `_norm` también, igual que `nombre_norm` en persona.
--
-- **Se revoca el SELECT de tabla y se otorga la lista de columnas**, no un
-- `REVOKE SELECT (col)`: en Postgres el revoke por columna NO recorta un grant
-- de tabla entera —queda sin efecto y `information_schema.column_privileges`
-- sigue mostrando las cuatro—. Mismo patrón exacto que `sql/039` §4.
-- ============================================================
REVOKE SELECT ON public.obras_empresas FROM authenticated;
GRANT SELECT (
  id, razon_social, nombre_comercial, localidad, provincia, observaciones,
  creado_por, activo, pendiente, motivo_rechazo, created_at, updated_at,
  razon_social_norm, nombre_comercial_norm
) ON public.obras_empresas TO authenticated;

-- ============================================================
-- 5. obras_ficha_empresa — el único camino al contacto
--
-- Un parámetro menos que `obras_ficha_persona`: el ancla solo puede ser obra.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_ficha_empresa(
  p_empresa_id uuid,
  p_ctx_obra_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id                uuid,
  razon_social      text,
  nombre_comercial  text,
  telefono          text,
  email             text,
  website           text,
  direccion         text,
  localidad         text,
  provincia         provincia,
  observaciones     text,
  creado_por        uuid,
  created_at        timestamptz,
  updated_at        timestamptz
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
    v_ok := EXISTS (
      SELECT 1 FROM obras_empresa_grant_contextual g
      WHERE g.empresa_id = p_empresa_id AND g.usuario_id = auth.uid() AND g.activo
        AND g.obra_id = p_ctx_obra_id
        AND EXISTS (
          SELECT 1 FROM obras_obra_empresa oe
          WHERE oe.obra_id = g.obra_id AND oe.empresa_id = g.empresa_id AND oe.activo
        )
    );
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

REVOKE EXECUTE ON FUNCTION public.obras_ficha_empresa(uuid, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.obras_ficha_empresa(uuid, uuid) TO authenticated;

-- ============================================================
-- 6. obras_empresas_select — la fila sale con grant contextual
--
-- Como `obras_personas_select` desde `sql/039`: la razón social sale por RLS,
-- el contacto sigue saliendo solo por la DEFINER.
-- ============================================================
DROP POLICY IF EXISTS obras_empresas_select ON obras_empresas;
CREATE POLICY obras_empresas_select ON obras_empresas FOR SELECT
  USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
    AND (
      creado_por = (select auth.uid())
      OR (pendiente AND tiene_permiso('obras_aprobar'))
      OR (
        NOT pendiente
        AND (
          tiene_permiso('obras_empresas_todas')
          OR EXISTS (
            SELECT 1 FROM obras_empresa_compartida c
            WHERE c.empresa_id = obras_empresas.id
              AND c.usuario_id = (select auth.uid()) AND c.activo
          )
          OR obras_empresa_grant_ctx_vigente(obras_empresas.id)
        )
      )
    )
  );

-- ============================================================
-- 7. obras_obra_empresa_select — el receptor ve el vínculo con contextual
--
-- Sin esto compartís la obra y el receptor no ve ninguna empresa.
-- Anclado: el grant traído por la obra A no abre el vínculo de la obra B.
-- ============================================================
DROP POLICY IF EXISTS obras_obra_empresa_select ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_select ON obras_obra_empresa FOR SELECT
  USING (
    creado_por = (select auth.uid())
    OR obras_es_mi_obra(obra_id)
    OR tiene_permiso('obras_transferir')
    OR (
      obras_obra_compartida_conmigo(obra_id)
      AND (
        obras_empresa_compartida_conmigo(empresa_id)
        OR obras_empresa_grant_ctx_obra_conmigo(empresa_id, obra_id)
      )
    )
  );

-- ============================================================
-- 8. obras_empresa_grant_directo — colapsa a "¿hay grant activo?"
--
-- `origen_obra_id` deja de existir; `obras_empresa_compartida` pasa a ser solo
-- directo. Mismo colapso que `obras_persona_grant_directo` en `sql/082`.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_empresa_grant_directo(p_empresa_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_empresa_compartida c
    WHERE c.empresa_id = p_empresa_id AND c.usuario_id = (select auth.uid()) AND c.activo
  );
$$;

-- ============================================================
-- 9. obras_compartir_obra — empresas tildadas → grant contextual
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

  -- Empresas tildadas: vinculadas a esta obra y mías. Se abren dentro de esta
  -- obra, no entran a la agenda del receptor.
  INSERT INTO obras_empresa_grant_contextual
    (empresa_id, usuario_id, obra_id, otorgada_por, activo)
  SELECT DISTINCT oe.empresa_id, p_usuario_id, p_obra_id, auth.uid(), true
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
    AND oe.empresa_id = ANY(p_empresas)
  ON CONFLICT (empresa_id, usuario_id, obra_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  -- Personas tildadas: igual, ancladas a esta obra (sql/082).
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

  -- Estado deseado (sql/049): lo destildado se apaga, por ancla.
  UPDATE obras_empresa_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id
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
-- 10. obras_revocar_obra — la cascada de empresa va por ancla
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

  UPDATE obras_empresa_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  UPDATE obras_obra_empresa
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;

  UPDATE obras_obra_persona
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;
END;
$$;

-- ============================================================
-- 11. obras_revocar_empresa — corte total, contextuales incluidos
--
-- Igual que `obras_revocar_persona`: el botón dice "revocar la empresa", así
-- que baja el grant directo Y los contextuales de esa empresa para ese usuario,
-- vengan de la obra que vengan.
-- ============================================================
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

  UPDATE obras_empresa_grant_contextual
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND usuario_id = p_usuario_id AND activo;

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  UPDATE obras_obra_empresa
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND creado_por = p_usuario_id AND activo;
END;
$$;

-- ============================================================
-- 12. obras_transferir — la rama de empresas deja de ir a la agenda
--
-- Lo demás no cambia respecto de `sql/084`. Las empresas tildadas siguen
-- cambiando de dueño; las destildadas pasan de `obras_empresa_compartida` a
-- grant contextual anclado a la obra — que es lo que el usuario esperaba al
-- destildarlas y no pasaba.
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
  --  - el resto → grant contextual anclado a la obra
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
  -- dueño; el resto entra como grant contextual anclado a la obra (sql/085).
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

  UPDATE obras_empresa_grant_contextual SET activo = false
  WHERE empresa_id = ANY(v_empresas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_compartida SET activo = false
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_obra_compartida SET otorgada_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND activo;

  UPDATE obras_empresa_compartida SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND empresa_id = ANY(v_empresas);

  UPDATE obras_empresa_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas));

  UPDATE obras_persona_compartida SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND persona_id = ANY(v_personas);

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas)
         OR persona_id = ANY(v_personas));

  IF p_a_usuario_id <> auth.uid() THEN
    INSERT INTO obras_empresa_grant_contextual (empresa_id, usuario_id, obra_id, otorgada_por)
    SELECT DISTINCT oe.empresa_id, p_a_usuario_id, p_obra_id, auth.uid()
    FROM obras_obra_empresa oe
    JOIN obras_empresas e ON e.id = oe.empresa_id
    WHERE oe.obra_id = p_obra_id AND oe.activo
      AND e.creado_por = v_actual
      AND NOT (oe.empresa_id = ANY(p_contactos_exclusivos))
    ON CONFLICT (empresa_id, usuario_id, obra_id)
    DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();
  END IF;
END;
$$;

-- ============================================================
-- 13. obras_transferir_empresa — apaga también los contextuales
--
-- La decisión de `sql/084` no cambia: acá lo compartido SE APAGA en vez de
-- pasar de mano, porque compartir una empresa es una decisión sobre la agenda
-- propia. Solo se suma la tabla nueva al apagado.
-- ============================================================
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

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND activo;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND activo;

  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_personas_exclusivas)
      AND id IN (SELECT persona_id FROM obras_persona_empresa WHERE empresa_id = p_empresa_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  UPDATE obras_persona_compartida SET activo = false, updated_at = now()
    WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  INSERT INTO obras_transferencias (tipo, empresa_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('empresa', p_empresa_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

-- ============================================================
-- 14. obras_vinculos_de_obra — la rama empresa y el `detalle` de persona
--
-- Dos aperturas, las dos ancladas:
--   · rama empresa: sin esto el receptor no ve ninguna empresa de la obra
--   · `detalle` de la rama persona (`sql/070`): la razón social de la empresa
--     del vínculo. Si el receptor recibió esa empresa por esta obra, la ve.
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
          AND (obras_empresa_compartida_conmigo(oe.empresa_id)
               OR obras_empresa_grant_ctx_obra_conmigo(oe.empresa_id, p_obra_id)))
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
            OR obras_empresa_grant_ctx_obra_conmigo(op.empresa_id, p_obra_id)) AS empresa_visible
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
-- 15. Checklist — `ya_compartida` mira el grant contextual de ESTA obra
--
-- Un share directo también cuenta: la empresa ya tiene acceso completo,
-- tildarla no agrega nada. Destildarla solo apaga el contextual.
-- (Referencias calificadas por alias: `id` es el OUT param — lección sql/048.)
-- ============================================================
CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_obra(
  p_obra_id uuid, p_usuario_id uuid
)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text, ya_compartida boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
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
         EXISTS (SELECT 1 FROM obras_empresa_grant_contextual g
                 WHERE g.empresa_id = e.id AND g.usuario_id = p_usuario_id
                   AND g.obra_id = p_obra_id AND g.activo)
         OR EXISTS (SELECT 1 FROM obras_empresa_compartida c
                 WHERE c.empresa_id = e.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
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

-- ============================================================
-- 16. Vista Compartido — la empresa se parte en directo y contextual
--
-- Simétrico a lo que `sql/082` hizo con la rama de persona.
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
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
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
         NULL::text, NULL::uuid, NULL::text, c.created_at
  FROM obras_empresa_compartida c
  JOIN obras_empresas e ON e.id = c.empresa_id
  JOIN usuarios u       ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'empresa'::text, g.empresa_id, e.razon_social, g.usuario_id, u.nombre,
         'obra'::text, g.obra_id,
         (SELECT nombre FROM obras WHERE id = g.obra_id),
         g.created_at
  FROM obras_empresa_grant_contextual g
  JOIN obras_empresas e ON e.id = g.empresa_id
  JOIN usuarios u       ON u.id = g.usuario_id
  WHERE g.otorgada_por = auth.uid() AND g.activo

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
-- 17. obras_compartir_empresa — solo suelta el `origen_obra_id = NULL`
--
-- Compartir una empresa desde su ficha sigue siendo grant COMPLETO: es acto
-- directo del dueño sobre su agenda, no cascada de una obra. Lo único que
-- cambia es que ya no hay origen que limpiar. Sus personas tildadas siguen
-- yendo a contextual anclado en la empresa (`sql/082`).
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
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

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
-- 18. obras_compartir_registros (Tareas) — la empresa también ancla
--
-- Dejarla escribiendo `origen_obra_id` no la degradaba: la hacía CRASHEAR al
-- dropear la columna, y con ella asignar cualquier tarea que arrastre una
-- empresa. La rama de empresa pasa a ser la misma que `sql/082` le dio a la de
-- persona: ancla en la obra que ya buscaba como origen —mía, activa, vinculada
-- a esa empresa y ya compartida con ese usuario— y corta con `OB029` si no hay
-- ninguna. El vínculo que el grant valida en vivo existe por construcción.
--
-- Queda a medio camino igual que la persona, y por el mismo motivo: el receptor
-- todavía no abre la ficha desde la tarea (`obras_puede_abrir` no cuenta
-- contextuales, el chip sale sin `?ctx=`). La reparación conjunta está en
-- `BACKLOG.md`.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_compartir_registros(p_usuario uuid, p_registros jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

      IF v_origen_obra IS NULL THEN
        RAISE EXCEPTION 'Esa empresa no cuelga de ninguna obra compartida con ese usuario: compartila desde su ficha'
          USING ERRCODE = 'OB029';
      END IF;

      INSERT INTO obras_empresa_grant_contextual
        (empresa_id, usuario_id, obra_id, otorgada_por, activo)
      VALUES (v_id, p_usuario, v_origen_obra, auth.uid(), true)
      ON CONFLICT (empresa_id, usuario_id, obra_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now()
        WHERE NOT obras_empresa_grant_contextual.activo;

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
-- 19. `origen_obra_id` se dropea
--
-- Va último: todo lo de arriba ya dejó de leerlo o escribirlo.
--
-- `obras_emitir_eventos_grant` no se toca: lee `v_nueva->'origen_obra_id'`
-- sobre el `to_jsonb(NEW)`, así que la clave ausente sale NULL y
-- `jsonb_strip_nulls` la borra. Tampoco se le cuelga el trigger a
-- `obras_empresa_grant_contextual`: `obras_persona_grant_contextual` no lo
-- tiene desde `sql/083`, y la simetría manda. Consecuencia asumida —
-- el checklist de una obra deja de emitir `compartido`/`revocado` para
-- empresas, igual que ya dejó de emitirlos para personas en `sql/082`.
-- ============================================================
ALTER TABLE obras_empresa_compartida DROP COLUMN IF EXISTS origen_obra_id;
