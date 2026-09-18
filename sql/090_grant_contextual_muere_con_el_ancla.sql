-- sql/090 — el grant contextual muere con el ancla
--
-- Auditoría de compartir/transferir (2026-09-18). Cuatro agujeros, una sola
-- causa: el grant contextual se comportaba como una capacidad independiente en
-- vez de "ver esta entidad DENTRO de esta obra/empresa".
--
--   V1 el grant sobrevivía a la revocación de la obra. `obras_revocar_obra`
--      apagaba los contextuales filtrando `otorgada_por = auth.uid()`, y las
--      transferencias reescribían `otorgada_por` de TODOS los grants de la
--      entidad — anclados a cualquier obra, incluidas las que no participaban.
--      Quedaba un grant huérfano: el responsable ya no lo veía en Compartido,
--      el nuevo dueño no podía revocarlo (no es responsable del ancla), y el
--      receptor seguía abriendo la ficha con teléfono y email.
--   V2 el grant de persona anclado en una EMPRESA era irrevocable:
--      `obras_revocar_contextual` solo sabía de anclas obra, y la vista
--      Compartido le pasaba un `empresa_id` como `p_obra_id` → OB026 siempre.
--      Es el estado 2 de sql/087, que es el default.
--   V3 un `p_tipo` desconocido pasaba el gate y no hacía nada: éxito mentiroso.
--   V4 `otorgada_por = auth.uid()` en `obras_transferir` ponía de otorgante al
--      admin que ejecuta, y el `IF p_a_usuario_id <> auth.uid()` (que existía
--      para no violar el CHECK) dejaba sin contactos al admin que se transfiere
--      la obra a sí mismo.
--
-- Las dos reglas que faltaban, escritas una sola vez:
--
--   1. El grant vale mientras quien lo tiene siga viendo el ancla. Antes solo
--      se verificaba que el vínculo entidad↔ancla siguiera vivo.
--   2. `otorgada_por` sigue al dueño del ANCLA, no al de la entidad. Transferir
--      una persona no mueve las obras donde está: esos grants los otorgó —y los
--      revoca— el responsable de cada obra. La reasignación por entidad era un
--      resto del modelo sin ancla anterior a sql/082.
--
-- De yapa, en las tres funciones que se reescriben enteras: el gate OB006
-- ("el destino no tiene acceso a Obras") deja de ser un EXISTS copiado sobre
-- usuario_submodulos y pasa a `usuario_tiene_permiso`, que es la misma regla.
-- `obras_migrar_agenda` conserva la copia — no se toca en esta migración.
--
-- Test: sql/tests/obras_090.sql

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · Vigencia: el grant muere si el ancla deja de verse
-- ─────────────────────────────────────────────────────────────────────────────

-- El ancla de una empresa es siempre una obra. Si el receptor ya no ve esa
-- obra, la empresa deja de abrirse aunque el grant siga activo.
CREATE OR REPLACE FUNCTION obras_empresa_grant_ctx_vigente(p_empresa_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_empresa_grant_contextual g
    WHERE g.empresa_id = p_empresa_id AND g.usuario_id = (select auth.uid()) AND g.activo
      AND obras_puede_ver_obra(g.obra_id)
      AND EXISTS (
        SELECT 1 FROM public.obras_obra_empresa oe
        WHERE oe.obra_id = g.obra_id AND oe.empresa_id = g.empresa_id AND oe.activo
      )
  );
$$;

-- Ancla obra XOR empresa. La rama empresa acepta las dos vías de ver la
-- empresa: hoy esos grants son siempre para su dueño (estado 2 de sql/087),
-- pero un receptor con la empresa contextual también tiene que pasar.
CREATE OR REPLACE FUNCTION obras_persona_grant_ctx_vigente(p_persona_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras_persona_grant_contextual g
    WHERE g.persona_id = p_persona_id AND g.usuario_id = auth.uid() AND g.activo
      AND (
        (g.obra_id IS NOT NULL AND obras_puede_ver_obra(g.obra_id) AND EXISTS (
          SELECT 1 FROM public.obras_obra_persona op
          WHERE op.obra_id = g.obra_id AND op.persona_id = g.persona_id AND op.activo
        ))
        OR
        (g.empresa_id IS NOT NULL
         AND (obras_puede_ver_empresa(g.empresa_id)
              OR obras_empresa_grant_ctx_vigente(g.empresa_id))
         AND EXISTS (
          SELECT 1 FROM public.obras_persona_empresa pe
          WHERE pe.empresa_id = g.empresa_id AND pe.persona_id = g.persona_id AND pe.activo
        ))
      )
  );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · Las dos fichas: misma regla en la rama contextual
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_ficha_empresa(p_empresa_id uuid, p_ctx_obra_id uuid DEFAULT NULL)
RETURNS TABLE (
  id uuid, razon_social text, nombre_comercial text, telefono text, email text,
  website text, direccion text, localidad text, provincia provincia,
  observaciones text, creado_por uuid,
  created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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
        AND obras_puede_ver_obra(g.obra_id)
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
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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
          (p_ctx_tipo = 'obra' AND g.obra_id = p_ctx_id
           AND obras_puede_ver_obra(g.obra_id)
           AND EXISTS (
            SELECT 1 FROM obras_obra_persona op
            WHERE op.obra_id = g.obra_id AND op.persona_id = g.persona_id AND op.activo))
          OR
          (p_ctx_tipo = 'empresa' AND g.empresa_id = p_ctx_id
           AND (obras_puede_ver_empresa(g.empresa_id)
                OR obras_empresa_grant_ctx_vigente(g.empresa_id))
           AND EXISTS (
            SELECT 1 FROM obras_persona_empresa pe
            WHERE pe.empresa_id = g.empresa_id AND pe.persona_id = g.persona_id AND pe.activo))
        )
    );
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3 · Revocar la obra apaga TODO lo anclado a ella (V1)
-- ─────────────────────────────────────────────────────────────────────────────

-- Sale el filtro `otorgada_por = auth.uid()`: un grant anclado a esta obra solo
-- lo pudo otorgar su responsable, que es quien está llamando. El filtro no
-- protegía nada y era lo que dejaba huérfanos cuando `otorgada_por` se movía.
CREATE OR REPLACE FUNCTION obras_revocar_obra(p_obra_id uuid, p_usuario_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id AND activo;

  UPDATE obras_persona_grant_contextual
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND usuario_id = p_usuario_id AND activo;

  UPDATE obras_obra_empresa
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;

  UPDATE obras_obra_persona
    SET activo = false, updated_at = now()
    WHERE obra_id = p_obra_id AND creado_por = p_usuario_id AND activo;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4 · Revocar contextual: el ancla puede ser obra o empresa (V2, V3)
-- ─────────────────────────────────────────────────────────────────────────────

-- La firma vieja mentía: el cuarto parámetro se llamaba `p_obra_id` y la vista
-- Compartido le pasaba el `origen_id`, que para un grant anclado en empresa es
-- un empresa_id. Renombrar un parámetro pide DROP + CREATE.
DROP FUNCTION IF EXISTS obras_revocar_contextual(text, uuid, uuid, uuid);

CREATE FUNCTION obras_revocar_contextual(
  p_tipo        text,
  p_entidad_id  uuid,
  p_usuario_id  uuid,
  p_ancla_tipo  text,
  p_ancla_id    uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_ancla_mia boolean;
  v_n         int;
BEGIN
  IF p_tipo NOT IN ('empresa', 'persona')
     OR p_ancla_tipo NOT IN ('obra', 'empresa')
     -- Una empresa no cuelga de otra empresa: su ancla es siempre una obra.
     OR (p_tipo = 'empresa' AND p_ancla_tipo = 'empresa') THEN
    RAISE EXCEPTION 'Combinación de tipo y ancla inválida' USING ERRCODE = 'OB031';
  END IF;

  -- Dos autoridades, no una. En el checklist de una obra el otorgante ES el
  -- dueño del ancla, pero el grant recíproco del estado 2 (sql/087) lo otorga
  -- el ENTRANTE sobre un ancla que quedó del saliente: ahí el otorgante ve la
  -- fila en su vista Compartido y no es dueño de nada. Pedir solo lo primero
  -- dejaba esas filas sin forma de revocarse.
  v_ancla_mia := CASE p_ancla_tipo
    WHEN 'obra' THEN EXISTS (
      SELECT 1 FROM obras o WHERE o.id = p_ancla_id AND o.responsable_id = auth.uid())
    ELSE EXISTS (
      SELECT 1 FROM obras_empresas e WHERE e.id = p_ancla_id AND e.creado_por = auth.uid())
  END;

  IF p_tipo = 'empresa' THEN
    UPDATE obras_empresa_grant_contextual
      SET activo = false, updated_at = now()
      WHERE empresa_id = p_entidad_id AND usuario_id = p_usuario_id
        AND obra_id = p_ancla_id AND activo
        AND (v_ancla_mia OR otorgada_por = auth.uid());
  ELSIF p_ancla_tipo = 'obra' THEN
    UPDATE obras_persona_grant_contextual
      SET activo = false, updated_at = now()
      WHERE persona_id = p_entidad_id AND usuario_id = p_usuario_id
        AND obra_id = p_ancla_id AND activo
        AND (v_ancla_mia OR otorgada_por = auth.uid());
  ELSE
    UPDATE obras_persona_grant_contextual
      SET activo = false, updated_at = now()
      WHERE persona_id = p_entidad_id AND usuario_id = p_usuario_id
        AND empresa_id = p_ancla_id AND activo
        AND (v_ancla_mia OR otorgada_por = auth.uid());
  END IF;

  -- Con el ancla propia, cero filas es idempotencia (ya estaba revocado). Sin
  -- el ancla y sin haber tocado nada, no hay autoridad: el éxito silencioso era
  -- justo lo que hacía creer que el botón había funcionado.
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 AND NOT v_ancla_mia THEN
    RAISE EXCEPTION 'Solo el dueño del ancla o quien lo otorgó puede revocar el acceso'
      USING ERRCODE = 'OB026';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_revocar_contextual(text, uuid, uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_revocar_contextual(text, uuid, uuid, text, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5 · Transferir: `otorgada_por` sigue al dueño del ancla (V1, V4)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_transferir(
  p_obra_id      uuid,
  p_a_usuario_id uuid,
  p_migran       uuid[] DEFAULT '{}',
  p_sacar        uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
  v_empresas uuid[];
BEGIN
  IF NOT obras_puede_transferir('obra', p_obra_id) THEN
    RAISE EXCEPTION 'Sin permiso para transferir obras' USING ERRCODE = 'OB003';
  END IF;

  SELECT responsable_id INTO v_actual FROM obras WHERE id = p_obra_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Obra inexistente o desactivada' USING ERRCODE = 'OB004';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La obra ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  -- Sacar algo que no migra no significa nada: sería desvincularlo de lo propio
  -- sin transferirlo, que es otra acción (desvincular, desde la ficha).
  IF EXISTS (SELECT 1 FROM unnest(p_sacar) s WHERE NOT (s = ANY(p_migran))) THEN
    RAISE EXCEPTION 'Solo se puede sacar de tu agenda lo que se transfiere' USING ERRCODE = 'OB032';
  END IF;

  IF NOT usuario_tiene_permiso(p_a_usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras SET responsable_id = p_a_usuario_id WHERE id = p_obra_id;

  INSERT INTO obras_transferencias (tipo, obra_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('obra', p_obra_id, v_actual, p_a_usuario_id, auth.uid());

  -- Personas que se van. El alcance se ensancha respecto de sql/086: además de
  -- las vinculadas a la obra entran las que llegan por una empresa vinculada a
  -- ella — el caso que el checklist viejo no ofrecía.
  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_migran)
      AND (
        id IN (SELECT persona_id FROM obras_obra_persona
               WHERE obra_id = p_obra_id AND activo)
        OR id IN (SELECT pe.persona_id
                  FROM obras_persona_empresa pe
                  JOIN obras_obra_empresa oe ON oe.empresa_id = pe.empresa_id AND oe.activo
                  WHERE oe.obra_id = p_obra_id AND pe.activo)
      )
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  WITH movidas AS (
    UPDATE obras_empresas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_migran)
      AND id IN (SELECT empresa_id FROM obras_obra_empresa
                 WHERE obra_id = p_obra_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_empresas FROM movidas;

  -- Lo que NO migra queda del saliente: grant contextual para el receptor,
  -- anclado a esta obra. El otorgante es el saliente y no `auth.uid()`: quien
  -- cede es quien otorga, el admin que ejecuta no es parte. Eso además vuelve
  -- innecesario el `IF p_a_usuario_id <> auth.uid()` que había acá — estaba
  -- para no violar el CHECK `usuario_id <> otorgada_por`, y dejaba sin
  -- contactos al admin que se transfiere la obra a sí mismo. OB005 ya garantiza
  -- que `v_actual` y el destino son distintos.
  INSERT INTO obras_persona_grant_contextual (persona_id, usuario_id, obra_id, otorgada_por)
  SELECT DISTINCT op.persona_id, p_a_usuario_id, p_obra_id, v_actual
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = v_actual
    AND NOT (op.persona_id = ANY(p_migran))
  ON CONFLICT (persona_id, usuario_id, obra_id) WHERE obra_id IS NOT NULL
  DO UPDATE SET activo = true, otorgada_por = v_actual, updated_at = now();

  INSERT INTO obras_empresa_grant_contextual (empresa_id, usuario_id, obra_id, otorgada_por)
  SELECT DISTINCT oe.empresa_id, p_a_usuario_id, p_obra_id, v_actual
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = v_actual
    AND NOT (oe.empresa_id = ANY(p_migran))
  ON CONFLICT (empresa_id, usuario_id, obra_id)
  DO UPDATE SET activo = true, otorgada_por = v_actual, updated_at = now();

  -- Nadie se comparte consigo mismo: el CHECK usuario_id <> otorgada_por lo
  -- rechazaría.
  UPDATE obras_obra_compartida SET activo = false
  WHERE obra_id = p_obra_id AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
  WHERE empresa_id = ANY(v_empresas) AND usuario_id = p_a_usuario_id AND activo;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  -- Lo compartido con terceros sigue vivo pero cuelga del nuevo dueño: quien
  -- recibe es quien ahora puede revocar. Solo lo anclado a lo que cambió de
  -- mano — la obra, y las empresas que migran, que son ancla de sus personas.
  -- Un grant anclado a OTRA obra del saliente no se toca aunque su entidad se
  -- vaya: esa obra sigue siendo suya, y moverle el otorgante lo dejaba fuera
  -- de su propia vista Compartido con el acceso vivo (V1).
  UPDATE obras_obra_compartida SET otorgada_por = p_a_usuario_id
  WHERE obra_id = p_obra_id AND activo;

  UPDATE obras_empresa_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id AND obra_id = p_obra_id;

  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE activo AND usuario_id <> p_a_usuario_id
    AND (obra_id = p_obra_id OR empresa_id = ANY(v_empresas));

  -- Y los estados 2 y 3 sobre lo que se fue.
  PERFORM obras_transferir_resolver_vinculos(
    v_personas, v_empresas, p_sacar, v_actual, p_a_usuario_id, p_obra_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION obras_transferir_persona(
  p_persona_id   uuid,
  p_a_usuario_id uuid,
  p_sacar        boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual uuid;
BEGIN
  IF NOT obras_puede_transferir('persona', p_persona_id) THEN
    RAISE EXCEPTION 'Sin permiso para transferir personas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_actual FROM obras_personas WHERE id = p_persona_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Persona inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La persona ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF NOT usuario_tiene_permiso(p_a_usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_personas SET creado_por = p_a_usuario_id WHERE id = p_persona_id;

  -- Nadie se comparte consigo mismo.
  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = p_persona_id AND usuario_id = p_a_usuario_id AND activo;

  -- Acá había un `SET otorgada_por = p_a_usuario_id` sobre todos los grants de
  -- la persona. Se va: las anclas (obras y empresas donde está) no cambiaron de
  -- dueño, así que el otorgante sigue siendo el de cada una. Moverlo era lo que
  -- producía el grant huérfano de V1 — irrevocable desde las dos puntas.

  PERFORM obras_transferir_resolver_vinculos(
    ARRAY[p_persona_id], '{}',
    CASE WHEN p_sacar THEN ARRAY[p_persona_id] ELSE '{}'::uuid[] END,
    v_actual, p_a_usuario_id, NULL
  );

  INSERT INTO obras_transferencias (tipo, persona_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('persona', p_persona_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION obras_transferir_empresa(
  p_empresa_id    uuid,
  p_a_usuario_id  uuid,
  p_migran        uuid[] DEFAULT '{}',
  p_sacar         uuid[] DEFAULT '{}',
  p_sacar_empresa boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actual   uuid;
  v_personas uuid[];
  v_sacar    uuid[];
BEGIN
  IF NOT obras_puede_transferir('empresa', p_empresa_id) THEN
    RAISE EXCEPTION 'Sin permiso para transferir empresas' USING ERRCODE = 'OB024';
  END IF;

  SELECT creado_por INTO v_actual FROM obras_empresas WHERE id = p_empresa_id AND activo;
  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'Empresa inexistente o desactivada' USING ERRCODE = 'OB025';
  END IF;

  IF v_actual = p_a_usuario_id THEN
    RAISE EXCEPTION 'La empresa ya es de ese usuario' USING ERRCODE = 'OB005';
  END IF;

  IF EXISTS (SELECT 1 FROM unnest(p_sacar) s WHERE NOT (s = ANY(p_migran))) THEN
    RAISE EXCEPTION 'Solo se puede sacar de tu agenda lo que se transfiere' USING ERRCODE = 'OB032';
  END IF;

  IF NOT usuario_tiene_permiso(p_a_usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'El destino no tiene acceso a Obras' USING ERRCODE = 'OB006';
  END IF;

  UPDATE obras_empresas SET creado_por = p_a_usuario_id WHERE id = p_empresa_id;

  UPDATE obras_empresa_grant_contextual SET activo = false, updated_at = now()
  WHERE empresa_id = p_empresa_id AND usuario_id = p_a_usuario_id AND activo;

  -- La empresa es ancla de las personas que cuelgan de ella: esos grants sí
  -- cambian de otorgante. Los grants DE la empresa, en cambio, están anclados
  -- a obras que no cambiaron de dueño, así que no se tocan.
  UPDATE obras_persona_grant_contextual SET otorgada_por = p_a_usuario_id
  WHERE empresa_id = p_empresa_id AND activo AND usuario_id <> p_a_usuario_id;

  WITH movidas AS (
    UPDATE obras_personas SET creado_por = p_a_usuario_id
    WHERE creado_por = v_actual AND id = ANY(p_migran)
      AND id IN (SELECT persona_id FROM obras_persona_empresa
                 WHERE empresa_id = p_empresa_id AND activo)
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}') INTO v_personas FROM movidas;

  UPDATE obras_persona_grant_contextual SET activo = false, updated_at = now()
  WHERE persona_id = ANY(v_personas) AND usuario_id = p_a_usuario_id AND activo;

  -- La empresa entra a `p_sacar` del resolver si el panel eligió el estado 3
  -- para ella misma: ahí se va de las obras del saliente y suelta a sus
  -- personas que siguen siendo de él.
  v_sacar := p_sacar;
  IF p_sacar_empresa THEN
    v_sacar := v_sacar || p_empresa_id;
  END IF;

  PERFORM obras_transferir_resolver_vinculos(
    v_personas, ARRAY[p_empresa_id], v_sacar, v_actual, p_a_usuario_id, NULL
  );

  INSERT INTO obras_transferencias (tipo, empresa_id, de_usuario_id, a_usuario_id, ejecutada_por)
  VALUES ('empresa', p_empresa_id, v_actual, p_a_usuario_id, auth.uid());
END;
$$;

COMMIT;
