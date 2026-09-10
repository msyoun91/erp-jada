-- ============================================================
-- 039 — Agenda de Obras: model A, todo privado por dueño
--
-- Cambio de fondo pedido por el usuario: obras, empresas y personas son de
-- carácter propio. No se comparten salvo acto explícito del dueño. Empresas
-- dejan de ser globales — se privatizan por `creado_por`.
--
-- LO QUE ANTES DABA ACCESO Y AHORA NO
--
--   - Vincular una persona a una obra propia. Vincular ya no abre la ficha:
--     para verla hay que ser dueño, tener grant, o `obras_personas_todas`.
--   - Marcar a alguien referente. Misma razón — la rama de `obras_obra_referente`
--     sale de `obras_puede_ver_persona`.
--
--   No se vincula lo que no se ve: el WITH CHECK de los dos INSERT de vínculo
--   ahora exige visibilidad de la entidad vinculada.
--
-- COMPARTIR — dos formas, las dos las inicia `creado_por`
--
--   1. Completa (`obras_persona_compartida` / `obras_empresa_compartida`): la
--      entidad entra a la agenda del receptor. Revocable.
--   2. Contextual (`obras_persona_grant_contextual`): el contacto de la persona
--      se ve SOLO dentro de una ficha de obra o de empresa. No entra a la
--      agenda ni al buscador. Nace de transferir una obra/empresa (sql/041) o
--      del toggle "compartir también los contactos". Muere con el vínculo — se
--      valida en vivo, sin trigger de limpieza.
--
--   Un grant recibido no se re-comparte: las funciones exigen `creado_por`.
--
-- EL CONTACTO DE PERSONA SE PROTEGE A NIVEL COLUMNA
--
-- Hasta acá `GRANT SELECT ON obras_personas` era tabla entera y
-- `obras_ficha_persona()` re-chequeaba el MISMO predicado que la policy: quien
-- veía la fila leía `telefono`/`whatsapp`/`email` con un `select` directo, sin
-- registro. El "único camino" era convención, no barrera. Con grant contextual
-- eso pasa a ser un agujero: la fila tiene que ser visible para mostrar el
-- nombre en la ficha de la obra, y con la columna abierta eso alcanzaría para
-- leer el teléfono.
--
-- Se revoca SELECT de las tres columnas de contacto y sus `_norm`.
-- `obras_ficha_persona()` es DEFINER, saltea el grant de columna, y ahora es de
-- verdad el único camino — y el único que escribe en `obras_accesos_persona`.
-- Toma contexto opcional: con `(obra|empresa, id)` autoriza por grant contextual
-- si el vínculo sigue activo, y lo deja anotado en el log.
--
-- VER NO ES EDITAR
--
-- `obras_personas_update` / `obras_empresas_update` pasan a exigir
-- `creado_por = auth.uid()`. Un grant —completo o contextual— es de lectura.
-- `obras_personas_todas` / `obras_empresas_todas` tampoco editan: para corregir
-- datos de una entidad ajena hay que transferírsela primero. Una puerta, no
-- dos — mismo criterio que `obras_transferir` con las obras.
--
-- CORTE LIMPIO, SIN BACKFILL
--
-- Al correr esto: 0 vínculos persona↔obra cross-owner, 0 pendientes. Nadie
-- pierde acceso a nada real (datos de prueba). Si en el futuro hubiera datos,
-- quien veía por vínculo deja de ver y se re-comparte a mano.
--
-- Las clases OB020–OB023 se suman a la lista blanca de `mensajeError()`
-- (decisiones/obras.md → "Los mensajes de la base los deja pasar una lista
-- blanca de códigos"): son texto escrito para que lo lea un usuario.
-- ============================================================

-- ============================================================
-- 1. Submódulo — "ver todas las empresas", simétrico a obras_personas_todas
-- ============================================================
-- `funcion` exige `vista_id` (CHECK submodulos_vista_id_check). Cuelga de la
-- vista Empresas, igual que obras_personas_todas cuelga de Personas.
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden, vista_id)
SELECT 'obras_empresas_todas', 'obras', 'funcion', 'Ver todas las empresas', 4,
       (SELECT id FROM submodulos WHERE codigo = 'obras_empresas' AND activo)
ON CONFLICT (codigo) WHERE activo DO NOTHING;

-- ============================================================
-- 2. Tablas de grant
--
-- Las dos "compartida" llevan UNIQUE entero (persona_id, usuario_id) a
-- propósito, no parcial WHERE activo: re-compartir el mismo par no inserta una
-- fila nueva, revive la que hay (`activo = true`). Volver a compartir a alguien
-- es el mismo permiso, no uno nuevo — el índice parcial es para reutilizar un
-- código único tras desactivar, que no es este caso.
--
-- `obras_persona_grant_contextual` ancla en obra XOR empresa. El parcial va por
-- ancla porque el mismo par (persona, usuario) puede tener grant en dos obras
-- distintas.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_persona_compartida (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id    uuid NOT NULL REFERENCES obras_personas(id),
  usuario_id    uuid NOT NULL REFERENCES usuarios(id),
  otorgada_por  uuid NOT NULL REFERENCES usuarios(id),
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT persona_compartida_no_a_si_mismo CHECK (usuario_id <> otorgada_por),
  CONSTRAINT persona_compartida_par_unico UNIQUE (persona_id, usuario_id)
);

CREATE TABLE IF NOT EXISTS obras_empresa_compartida (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid NOT NULL REFERENCES obras_empresas(id),
  usuario_id    uuid NOT NULL REFERENCES usuarios(id),
  otorgada_por  uuid NOT NULL REFERENCES usuarios(id),
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT empresa_compartida_no_a_si_mismo CHECK (usuario_id <> otorgada_por),
  CONSTRAINT empresa_compartida_par_unico UNIQUE (empresa_id, usuario_id)
);

CREATE TABLE IF NOT EXISTS obras_persona_grant_contextual (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id    uuid NOT NULL REFERENCES obras_personas(id),
  usuario_id    uuid NOT NULL REFERENCES usuarios(id),
  obra_id       uuid REFERENCES obras(id),
  empresa_id    uuid REFERENCES obras_empresas(id),
  otorgada_por  uuid NOT NULL REFERENCES usuarios(id),
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT grant_ctx_una_ancla CHECK ((obra_id IS NOT NULL) <> (empresa_id IS NOT NULL)),
  CONSTRAINT grant_ctx_no_a_si_mismo CHECK (usuario_id <> otorgada_por)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_grant_ctx_obra
  ON obras_persona_grant_contextual (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_grant_ctx_empresa
  ON obras_persona_grant_contextual (persona_id, usuario_id, empresa_id) WHERE empresa_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_persona_compartida_usuario
  ON obras_persona_compartida (usuario_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_empresa_compartida_usuario
  ON obras_empresa_compartida (usuario_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_grant_ctx_usuario
  ON obras_persona_grant_contextual (usuario_id, persona_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON obras_persona_compartida;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON obras_persona_compartida
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON obras_empresa_compartida;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON obras_empresa_compartida
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON obras_persona_grant_contextual;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON obras_persona_grant_contextual
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS: solo lectura desde el cliente. La escritura pasa por funciones DEFINER
-- que verifican `creado_por` (más abajo y en sql/041). Sin GRANT de INSERT/
-- UPDATE, igual que obras_aprobaciones y usuario_notificaciones.
ALTER TABLE obras_persona_compartida        ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_empresa_compartida        ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_persona_grant_contextual  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS persona_compartida_select ON obras_persona_compartida;
CREATE POLICY persona_compartida_select ON obras_persona_compartida FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR EXISTS (SELECT 1 FROM obras_personas p WHERE p.id = persona_id AND p.creado_por = auth.uid())
  );

DROP POLICY IF EXISTS empresa_compartida_select ON obras_empresa_compartida;
CREATE POLICY empresa_compartida_select ON obras_empresa_compartida FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR EXISTS (SELECT 1 FROM obras_empresas e WHERE e.id = empresa_id AND e.creado_por = auth.uid())
  );

DROP POLICY IF EXISTS grant_ctx_select ON obras_persona_grant_contextual;
CREATE POLICY grant_ctx_select ON obras_persona_grant_contextual FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR EXISTS (SELECT 1 FROM obras_personas p WHERE p.id = persona_id AND p.creado_por = auth.uid())
  );

GRANT SELECT ON public.obras_persona_compartida       TO authenticated;
GRANT SELECT ON public.obras_empresa_compartida       TO authenticated;
GRANT SELECT ON public.obras_persona_grant_contextual TO authenticated;

-- ============================================================
-- 3. `obras_accesos_persona` — de qué ficha se leyó el contacto
-- ============================================================
ALTER TABLE obras_accesos_persona ADD COLUMN IF NOT EXISTS contexto text;

-- ============================================================
-- 4. Contacto de persona: SELECT por columna
--
-- Sin `telefono`, `whatsapp`, `email` ni sus `_norm`. Lo que quedaba abierto
-- por `GRANT SELECT ON public.obras_personas` (sql/027 §16).
-- ============================================================
REVOKE SELECT ON public.obras_personas FROM authenticated;
GRANT SELECT (
  id, nombre, apellido, observaciones, creado_por, activo, pendiente,
  motivo_rechazo, created_at, updated_at, nombre_norm
) ON public.obras_personas TO authenticated;

-- ============================================================
-- 5. Visibilidad de persona — sin la rama de vínculo ni la de referente
--
-- `creado_por = auth.uid()` sigue adentro, pero la policy lo prueba además como
-- columna directa (más abajo): en un INSERT ... RETURNING la fila nueva no está
-- en el snapshot de una función STABLE (bug de sql/027 §"RLS + INSERT
-- RETURNING"). Acá dentro sirve para el resto de los llamadores.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_ver_persona(p_persona_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT (public.tiene_permiso('obras_ver') OR public.tiene_permiso('obras_personas'))
    AND EXISTS (
      SELECT 1 FROM public.obras_personas p
      WHERE p.id = p_persona_id
        AND (
          p.creado_por = auth.uid()
          OR (
            NOT p.pendiente
            AND (
              public.tiene_permiso('obras_personas_todas')
              OR EXISTS (
                SELECT 1 FROM public.obras_persona_compartida c
                WHERE c.persona_id = p_persona_id AND c.usuario_id = auth.uid() AND c.activo
              )
            )
          )
        )
    );
$$;

-- Grant contextual activo con el vínculo que lo ancla todavía vivo. Sin
-- argumento de contexto: la policy de SELECT solo necesita "hay alguno", el
-- match del contexto puntual lo hace `obras_ficha_persona`.
CREATE OR REPLACE FUNCTION obras_persona_grant_ctx_vigente(p_persona_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_persona_grant_contextual g
    WHERE g.persona_id = p_persona_id AND g.usuario_id = auth.uid() AND g.activo
      AND (
        (g.obra_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.obras_obra_persona op
          WHERE op.obra_id = g.obra_id AND op.persona_id = g.persona_id AND op.activo
        ))
        OR
        (g.empresa_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.obras_persona_empresa pe
          WHERE pe.empresa_id = g.empresa_id AND pe.persona_id = g.persona_id AND pe.activo
        ))
      )
  );
$$;

-- Visibilidad de empresa — antes global, ahora por dueño + grant + _todas.
-- Función aparte para el WITH CHECK del vínculo; la policy de SELECT inlinea la
-- misma condición para no releer la fila recién insertada.
CREATE OR REPLACE FUNCTION obras_puede_ver_empresa(p_empresa_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT (public.tiene_permiso('obras_ver') OR public.tiene_permiso('obras_empresas'))
    AND EXISTS (
      SELECT 1 FROM public.obras_empresas e
      WHERE e.id = p_empresa_id AND e.activo
        AND (
          e.creado_por = auth.uid()
          OR (
            NOT e.pendiente
            AND (
              public.tiene_permiso('obras_empresas_todas')
              OR EXISTS (
                SELECT 1 FROM public.obras_empresa_compartida c
                WHERE c.empresa_id = p_empresa_id AND c.usuario_id = auth.uid() AND c.activo
              )
            )
          )
        )
    );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_persona_grant_ctx_vigente(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_puede_ver_empresa(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_persona_grant_ctx_vigente(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_puede_ver_empresa(uuid) TO authenticated;

-- ============================================================
-- 6. Policies
-- ============================================================

-- --- obras_personas ---
DROP POLICY IF EXISTS obras_personas_select ON obras_personas;
CREATE POLICY obras_personas_select ON obras_personas FOR SELECT
  USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
    AND (
      creado_por = auth.uid()
      OR obras_puede_ver_persona(id)
      OR obras_persona_grant_ctx_vigente(id)
    )
  );

-- Editar exige ser dueño. Un grant es de lectura; `obras_personas_todas` mira
-- y transfiere, no corrige.
DROP POLICY IF EXISTS obras_personas_update ON obras_personas;
CREATE POLICY obras_personas_update ON obras_personas FOR UPDATE
  USING (tiene_permiso('obras_personas_editar') AND creado_por = auth.uid())
  WITH CHECK (tiene_permiso('obras_personas_editar') AND creado_por = auth.uid());

-- --- obras_empresas ---
-- `obras_aprobar` ve la congelada para poder decidirla (igual que en sql/033).
-- El resto solo ve las no-congeladas: dueño, `obras_empresas_todas`, o grant.
DROP POLICY IF EXISTS obras_empresas_select ON obras_empresas;
CREATE POLICY obras_empresas_select ON obras_empresas FOR SELECT
  USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
    AND (
      creado_por = auth.uid()
      OR (pendiente AND tiene_permiso('obras_aprobar'))
      OR (
        NOT pendiente
        AND (
          tiene_permiso('obras_empresas_todas')
          OR EXISTS (
            SELECT 1 FROM obras_empresa_compartida c
            WHERE c.empresa_id = id AND c.usuario_id = auth.uid() AND c.activo
          )
        )
      )
    )
  );

DROP POLICY IF EXISTS obras_empresas_update ON obras_empresas;
CREATE POLICY obras_empresas_update ON obras_empresas FOR UPDATE
  USING (tiene_permiso('obras_empresas_editar') AND creado_por = auth.uid())
  WITH CHECK (tiene_permiso('obras_empresas_editar') AND creado_por = auth.uid());

-- --- vínculos: no se vincula lo que no se ve ---
DROP POLICY IF EXISTS obras_obra_persona_insert ON obras_obra_persona;
CREATE POLICY obras_obra_persona_insert ON obras_obra_persona FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_vincular')
    AND obras_es_mi_obra(obra_id)
    AND obras_puede_ver_persona(persona_id)
  );

DROP POLICY IF EXISTS obras_obra_empresa_insert ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_insert ON obras_obra_empresa FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_vincular')
    AND obras_es_mi_obra(obra_id)
    AND obras_puede_ver_empresa(empresa_id)
  );

-- persona↔empresa: vincular un empleo exige ver a la persona (ser dueño o
-- grant completo — un grant contextual no alcanza para editarle la ficha).
DROP POLICY IF EXISTS obras_persona_empresa_insert ON obras_persona_empresa;
CREATE POLICY obras_persona_empresa_insert ON obras_persona_empresa FOR INSERT
  WITH CHECK (
    tiene_permiso('obras_personas_empresas')
    AND obras_puede_ver_persona(persona_id)
    AND obras_puede_ver_empresa(empresa_id)
  );

-- ============================================================
-- 7. obras_ficha_persona — 3 args, contexto opcional
--
-- Se dropea la de 1 arg: agregar parámetros crea una función nueva, no
-- reemplaza, y el GRANT de sql/029 apunta a la firma vieja.
-- ============================================================
DROP FUNCTION IF EXISTS public.obras_ficha_persona(uuid);

CREATE OR REPLACE FUNCTION obras_ficha_persona(
  p_persona_id uuid,
  p_ctx_tipo   text DEFAULT NULL,
  p_ctx_id     uuid DEFAULT NULL
)
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
DECLARE
  v_ok boolean;
BEGIN
  v_ok := obras_puede_ver_persona(p_persona_id);

  IF NOT v_ok AND p_ctx_tipo IS NOT NULL AND p_ctx_id IS NOT NULL THEN
    v_ok := EXISTS (
      SELECT 1 FROM obras_persona_grant_contextual g
      WHERE g.persona_id = p_persona_id AND g.usuario_id = auth.uid() AND g.activo
        AND (
          (p_ctx_tipo = 'obra' AND g.obra_id = p_ctx_id AND EXISTS (
            SELECT 1 FROM obras_obra_persona op
            WHERE op.obra_id = g.obra_id AND op.persona_id = g.persona_id AND op.activo))
          OR
          (p_ctx_tipo = 'empresa' AND g.empresa_id = p_ctx_id AND EXISTS (
            SELECT 1 FROM obras_persona_empresa pe
            WHERE pe.empresa_id = g.empresa_id AND pe.persona_id = g.persona_id AND pe.activo))
        )
    );
  END IF;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'Sin acceso a esta persona' USING ERRCODE = 'OB022';
  END IF;

  INSERT INTO obras_accesos_persona (usuario_id, persona_id, contexto)
  VALUES (auth.uid(), p_persona_id,
          nullif(concat_ws(':', p_ctx_tipo, p_ctx_id::text), ''));

  RETURN QUERY
  SELECT p.id, p.nombre, p.apellido, p.telefono, p.whatsapp, p.email,
         p.observaciones, p.creado_por, p.created_at, p.updated_at
  FROM obras_personas p
  WHERE p.id = p_persona_id AND p.activo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_ficha_persona(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_ficha_persona(uuid, text, uuid) TO authenticated;

-- ============================================================
-- 8. Compartir / revocar — DEFINER, exigen `creado_por`
--
-- En Postgres y no en actions.ts: "solo el dueño comparte" es la regla, y vive
-- donde no la puede saltear otro camino. El ON CONFLICT revive la fila
-- desactivada en vez de insertar otra (UNIQUE entero, ver §2).
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
END;
$$;

CREATE OR REPLACE FUNCTION obras_compartir_empresa(p_empresa_id uuid, p_usuario_id uuid)
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
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_compartir_persona(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_revocar_persona(uuid, uuid)   FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_compartir_empresa(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_revocar_empresa(uuid, uuid)   FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_compartir_persona(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_revocar_persona(uuid, uuid)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_compartir_empresa(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_revocar_empresa(uuid, uuid)   TO authenticated;
