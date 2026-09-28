-- sql/139 — obras y contactos, tramo 3: vínculos guardados, "Por aprobar" y
-- las tres salidas.
--
-- - Congelada no se vincula (CO020) ni suma participantes (OB018). Salvo en el
--   mismo paso en que nace: el vínculo con el que se carga (el "¿Quién?" del
--   alta, o crear y vincular desde el panel) va a `contactos_vinculos_guardados`
--   y se crea cuando sus dos puntas dejan de estar congeladas. "Nace en este
--   paso" es `created_at = now()`: el cliente no escribe `created_at`, y
--   `now()` es el comienzo de la transacción.
-- - El guardado se crea a nombre de quien cargó: `creado_por = cargado_por`, y
--   `contactos_vinculos_validar` / `contactos_persona_empresa_validar` validan
--   contra `NEW.creado_por` (fuera del GRANT: del cliente, siempre es él). Un
--   guardado activo autoriza el vínculo aunque la persona sea de otro ("es la
--   misma"): lo escriben solo funciones. Si quien cargó ya no trabaja el
--   registro, no se crea (`resultado = 'sin_permiso'`) y "alta aprobada" lo
--   cuenta.
-- - Salidas, de `obras_aprobar` / `contactos_aprobar`: aprobar · rechazar con
--   motivo (el alta se desactiva; la edición vuelve a `congelada_antes`) · "es
--   la misma", solo para un alta: se desactiva con `misma_que`; la obra suma a
--   quien la cargó como participante de la existente y le pasa sus guardados;
--   la persona o la empresa se los pasa si el aprobador elige vincular.
-- - Avisos: "alta aprobada / rechazada / es la misma" a quien la cargó (el
--   responsable; de una empresa, quien la cargó) y "Pedro se sumó" al
--   responsable de la existente. Los resuelve `duplicados_avisos` (DEFINER):
--   el aprobador no ve la congelada, y quien la cargó no ve la rechazada.
--
-- Decisiones: `decisiones/obras.md` → *Altas parecidas*, `decisiones/contactos.md`
-- → *Altas parecidas* y *Vincular*. Test: `sql/tests/duplicados.sql`.

-- ============================================================
-- 1. contactos_vinculos_guardados
-- ============================================================
-- Un vínculo con un registro (`ente`, `registro_id`, `roles`) o la empresa
-- de una persona (`a_empresa_id`, `cargo`). Sin policies ni GRANT.
CREATE TABLE IF NOT EXISTS public.contactos_vinculos_guardados (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id   uuid REFERENCES public.contactos_personas(id),
  empresa_id   uuid REFERENCES public.contactos_empresas(id),
  ente         text REFERENCES public.entes(codigo),
  registro_id  uuid,
  roles        text[],
  a_empresa_id uuid REFERENCES public.contactos_empresas(id),
  cargo        text,
  cargado_por  uuid NOT NULL REFERENCES public.usuarios(id),
  resultado    text CHECK (resultado IN ('creado', 'descartado', 'sin_permiso')),
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(persona_id, empresa_id) = 1),
  CHECK (
    (ente IS NOT NULL AND registro_id IS NOT NULL AND roles IS NOT NULL AND a_empresa_id IS NULL AND cargo IS NULL)
    OR (ente IS NULL AND registro_id IS NULL AND roles IS NULL AND a_empresa_id IS NOT NULL AND persona_id IS NOT NULL)
  ),
  CHECK (activo = (resultado IS NULL))
);

ALTER TABLE public.contactos_vinculos_guardados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.contactos_vinculos_guardados FROM anon, authenticated;

DROP TRIGGER IF EXISTS set_updated_at ON public.contactos_vinculos_guardados;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.contactos_vinculos_guardados
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 2. Genéricas: trabajar por usuario y congelado
-- ============================================================
CREATE OR REPLACE FUNCTION public.trabaja_registro_de(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'obras' THEN public.obras_trabaja_de(p_id, p_usuario)
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), false);
$$;

-- 'no' · 'nueva' (alta congelada que nace en esta transacción) · 'si'.
CREATE OR REPLACE FUNCTION public.obras_congelada(p_obra uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN NOT o.congelada THEN 'no' WHEN o.created_at = now() THEN 'nueva' ELSE 'si' END
  FROM public.obras o
  WHERE o.id = p_obra;
$$;

CREATE OR REPLACE FUNCTION public.registro_congelado(p_ente text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'obras' THEN public.obras_congelada(p_id)
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), 'no');
$$;

-- Una sola de las dos.
CREATE OR REPLACE FUNCTION public.contactos_congelado(p_persona uuid, p_empresa uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE WHEN NOT c.congelada THEN 'no' WHEN c.created_at = now() THEN 'nueva' ELSE 'si' END
    FROM (
      SELECT congelada, created_at FROM public.contactos_personas WHERE id = p_persona
      UNION ALL
      SELECT congelada, created_at FROM public.contactos_empresas WHERE id = p_empresa
    ) c
  ), 'no');
$$;

REVOKE EXECUTE ON FUNCTION public.trabaja_registro_de(text, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_congelada(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.registro_congelado(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_congelado(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 3. Vincular: a nombre de `creado_por`, y lo congelado se guarda
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_vinculos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_actor uuid := NEW.creado_por;
  v_contacto text;
  v_registro text;
BEGIN
  IF TG_OP = 'INSERT' OR NEW.roles IS DISTINCT FROM OLD.roles THEN
    NEW.roles := ARRAY(SELECT DISTINCT r FROM unnest(NEW.roles) r ORDER BY r);
    IF NOT NEW.roles <@ (SELECT e.roles FROM public.entes e WHERE e.codigo = NEW.ente) THEN
      RAISE EXCEPTION 'Ese rol no existe para ese registro' USING ERRCODE = 'CO014';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.activo := true;
    IF NOT EXISTS (SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND activo)
       AND NOT EXISTS (SELECT 1 FROM public.contactos_empresas WHERE id = NEW.empresa_id AND activo) THEN
      RAISE EXCEPTION 'Una persona o una empresa desactivada no se vincula' USING ERRCODE = 'CO009';
    END IF;
  ELSIF OLD.hasta IS NOT NULL AND (NEW.hasta, NEW.roles) IS DISTINCT FROM (OLD.hasta, OLD.roles) THEN
    RAISE EXCEPTION 'Un vínculo cerrado no se cambia: volver es un vínculo nuevo' USING ERRCODE = 'CO010';
  ELSIF NOT OLD.activo AND NEW.activo THEN
    RAISE EXCEPTION 'Un vínculo desactivado no vuelve: se vincula de nuevo' USING ERRCODE = 'CO011';
  END IF;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL THEN
    IF TG_OP = 'INSERT' THEN
      IF NOT public.trabaja_registro_de(NEW.ente, NEW.registro_id, v_actor) THEN
        RAISE EXCEPTION 'Vinculan y cambian contactos quienes trabajan el registro' USING ERRCODE = 'CO015';
      END IF;

      IF NOT public.usuario_tiene_permiso(v_actor, 'contactos_administrar') AND NOT (
        EXISTS (SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND responsable_id = v_actor)
        OR EXISTS (
          SELECT 1 FROM public.contactos_empresas
          WHERE id = NEW.empresa_id
            AND (equipo_id = public.equipo_de(v_actor) OR (equipo_id IS NULL AND creado_por = v_actor))
        )
        OR EXISTS (
          SELECT 1 FROM public.contactos_vinculos_guardados g
          WHERE g.activo AND g.cargado_por = v_actor AND g.ente = NEW.ente AND g.registro_id = NEW.registro_id
            AND (g.persona_id = NEW.persona_id OR g.empresa_id = NEW.empresa_id)
        )
      ) THEN
        RAISE EXCEPTION 'Vincula una persona su dueño, y una empresa su equipo' USING ERRCODE = 'CO016';
      END IF;
    ELSIF NOT public.trabaja_registro(NEW.ente, NEW.registro_id) AND NOT EXISTS (
      SELECT 1 FROM public.contactos_vinculos_guardados g
      WHERE g.activo AND g.ente = NEW.ente AND g.registro_id = NEW.registro_id
        AND (g.persona_id = NEW.persona_id OR g.empresa_id = NEW.empresa_id)
        AND public.trabaja_registro_de(g.ente, g.registro_id, g.cargado_por)
    ) THEN
      RAISE EXCEPTION 'Vinculan y cambian contactos quienes trabajan el registro' USING ERRCODE = 'CO015';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_contacto := public.contactos_congelado(NEW.persona_id, NEW.empresa_id);
    v_registro := public.registro_congelado(NEW.ente, NEW.registro_id);
    IF 'si' IN (v_contacto, v_registro) THEN
      RAISE EXCEPTION 'Espera aprobación: no se vincula hasta que la aprueben' USING ERRCODE = 'CO020';
    END IF;
    IF 'nueva' IN (v_contacto, v_registro) THEN
      INSERT INTO public.contactos_vinculos_guardados (persona_id, empresa_id, ente, registro_id, roles, cargado_por)
      VALUES (NEW.persona_id, NEW.empresa_id, NEW.ente, NEW.registro_id, NEW.roles, v_actor);
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_persona_empresa_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_actor uuid := CASE WHEN TG_OP = 'INSERT' THEN NEW.creado_por ELSE auth.uid() END;
  v_persona text;
  v_empresa text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.activo := true;
    IF NOT EXISTS (SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND activo)
       OR NOT EXISTS (SELECT 1 FROM public.contactos_empresas WHERE id = NEW.empresa_id AND activo) THEN
      RAISE EXCEPTION 'Una persona o una empresa desactivada no se vincula' USING ERRCODE = 'CO009';
    END IF;
  ELSIF OLD.hasta IS NOT NULL AND (NEW.hasta, NEW.cargo) IS DISTINCT FROM (OLD.hasta, OLD.cargo) THEN
    RAISE EXCEPTION 'Un vínculo cerrado no se cambia: volver es un vínculo nuevo' USING ERRCODE = 'CO010';
  ELSIF NOT OLD.activo AND NEW.activo THEN
    RAISE EXCEPTION 'Un vínculo desactivado no vuelve: se vincula de nuevo' USING ERRCODE = 'CO011';
  END IF;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL
     AND NOT public.usuario_tiene_permiso(v_actor, 'contactos_administrar') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND responsable_id = v_actor
    ) THEN
      RAISE EXCEPTION 'La empresa de una persona la maneja su dueño' USING ERRCODE = 'CO012';
    END IF;
    IF TG_OP = 'INSERT' AND NOT EXISTS (
      SELECT 1 FROM public.contactos_empresas e
      WHERE e.id = NEW.empresa_id
        AND public.contactos_puede_ver_empresa_de(e.id, e.equipo_id, e.creado_por, e.activo, v_actor)
    ) THEN
      RAISE EXCEPTION 'Esa empresa no existe o no la ves' USING ERRCODE = 'CO013';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_persona := public.contactos_congelado(NEW.persona_id, NULL);
    v_empresa := public.contactos_congelado(NULL, NEW.empresa_id);
    IF 'si' IN (v_persona, v_empresa) THEN
      RAISE EXCEPTION 'Espera aprobación: no se vincula hasta que la aprueben' USING ERRCODE = 'CO020';
    END IF;
    IF 'nueva' IN (v_persona, v_empresa) THEN
      INSERT INTO public.contactos_vinculos_guardados (persona_id, a_empresa_id, cargo, cargado_por)
      VALUES (NEW.persona_id, NEW.empresa_id, NEW.cargo, v_actor);
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 4. Participantes: congelada no suma; "es la misma" sí
-- ============================================================
-- La excepción a OB013: quien cargó la obra que el aprobador acaba de
-- resolver como "es la misma" (esa fila, en esta transacción).
CREATE OR REPLACE FUNCTION public.obras_participantes_al_crear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  NEW.activo := true;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.obras WHERE id = NEW.obra_id AND congelada) THEN
      RAISE EXCEPTION 'La obra espera aprobación: no suma participantes' USING ERRCODE = 'OB018';
    END IF;

    IF NOT public.obras_a_cargo_de(NEW.obra_id, v_uid) AND NOT EXISTS (
      SELECT 1 FROM public.obras c
      WHERE c.misma_que = NEW.obra_id AND c.responsable_id = NEW.usuario_id AND c.updated_at = now()
    ) THEN
      RAISE EXCEPTION 'Suman y quitan participantes el responsable, su jefe o el admin' USING ERRCODE = 'OB013';
    END IF;
  END IF;

  IF NOT public.usuario_tiene_permiso(NEW.usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'Participa de una obra alguien activo que ve Obras' USING ERRCODE = 'OB014';
  END IF;

  NEW.equipo_id := public.equipo_de(NEW.usuario_id);
  RETURN NEW;
END;
$$;

-- ============================================================
-- 5. Crear y descartar los guardados
-- ============================================================
-- Los de `p_id` (cualquiera de sus puntas) cuyas puntas ya no están
-- congeladas. Si el vínculo abierto ya existe, se suman los roles. Lo que
-- las reglas rechazan queda como `sin_permiso`.
CREATE OR REPLACE FUNCTION public.contactos_crear_guardados(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g public.contactos_vinculos_guardados;
  v_abierto uuid;
  v_resultado text;
BEGIN
  FOR g IN
    SELECT * FROM public.contactos_vinculos_guardados x
    WHERE x.activo AND p_id IN (x.persona_id, x.empresa_id, x.registro_id, x.a_empresa_id)
      AND public.contactos_congelado(x.persona_id, x.empresa_id) = 'no'
      AND (x.ente IS NULL OR public.registro_congelado(x.ente, x.registro_id) = 'no')
      AND (x.a_empresa_id IS NULL OR public.contactos_congelado(NULL, x.a_empresa_id) = 'no')
    FOR UPDATE
  LOOP
    BEGIN
      IF g.ente IS NOT NULL THEN
        SELECT v.id INTO v_abierto
        FROM public.contactos_vinculos v
        WHERE v.activo AND v.hasta IS NULL AND v.ente = g.ente AND v.registro_id = g.registro_id
          AND (v.persona_id = g.persona_id OR v.empresa_id = g.empresa_id);
        IF v_abierto IS NULL THEN
          INSERT INTO public.contactos_vinculos (persona_id, empresa_id, ente, registro_id, roles, creado_por)
          VALUES (g.persona_id, g.empresa_id, g.ente, g.registro_id, g.roles, g.cargado_por);
        ELSE
          UPDATE public.contactos_vinculos SET roles = roles || g.roles WHERE id = v_abierto;
        END IF;
      ELSIF NOT EXISTS (
        SELECT 1 FROM public.contactos_persona_empresa pe
        WHERE pe.activo AND pe.hasta IS NULL AND pe.persona_id = g.persona_id AND pe.empresa_id = g.a_empresa_id
      ) THEN
        INSERT INTO public.contactos_persona_empresa (persona_id, empresa_id, cargo, creado_por)
        VALUES (g.persona_id, g.a_empresa_id, g.cargo, g.cargado_por);
      END IF;
      v_resultado := 'creado';
    EXCEPTION WHEN OTHERS THEN
      v_resultado := 'sin_permiso';
    END;

    UPDATE public.contactos_vinculos_guardados SET activo = false, resultado = v_resultado WHERE id = g.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_descartar_guardados(p_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.contactos_vinculos_guardados SET activo = false, resultado = 'descartado'
  WHERE activo AND p_id IN (persona_id, empresa_id, registro_id, a_empresa_id);
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_crear_guardados(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_descartar_guardados(uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 6. Resolver
-- ============================================================
-- Cada UPDATE cambia `congelada`: así las reglas de actor no lo miran y el
-- congelar no vuelve a evaluar (`sql/138`). "Es la misma" es solo para un
-- alta: una edición que se parece se aprueba o se rechaza; unir dos obras que
-- ya existían es fusionar.
CREATE OR REPLACE FUNCTION public.obras_resolver(
  p_obra uuid, p_decision text, p_motivo text DEFAULT NULL, p_existente uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v public.obras;
  v_existente public.obras;
  v_participacion uuid;
BEGIN
  IF NOT public.usuario_tiene_permiso(v_uid, 'obras_aprobar') THEN
    RAISE EXCEPTION 'Resuelve las obras parecidas quien tiene "Aprobar altas"' USING ERRCODE = 'OB019';
  END IF;

  SELECT * INTO v FROM public.obras WHERE id = p_obra AND activo AND congelada FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa obra no espera aprobación' USING ERRCODE = 'OB020';
  END IF;

  IF p_decision = 'aprobar' THEN
    UPDATE public.obras SET congelada = false, congelada_antes = NULL WHERE id = p_obra;
    PERFORM public.contactos_crear_guardados(p_obra);
    PERFORM public.notificar(v.responsable_id, 'alta_aprobada', 'obras', p_obra, v_uid);

  ELSIF p_decision = 'rechazar' THEN
    IF nullif(btrim(p_motivo), '') IS NULL THEN
      RAISE EXCEPTION 'Rechazar pide el motivo' USING ERRCODE = 'OB021';
    END IF;
    IF v.congelada_antes IS NULL THEN
      UPDATE public.obras SET congelada = false, activo = false, rechazo_motivo = btrim(p_motivo) WHERE id = p_obra;
      PERFORM public.contactos_descartar_guardados(p_obra);
    ELSE
      UPDATE public.obras
      SET congelada = false, congelada_antes = NULL, rechazo_motivo = btrim(p_motivo),
          nombre = v.congelada_antes->>'nombre', direccion = v.congelada_antes->>'direccion'
      WHERE id = p_obra;
    END IF;
    PERFORM public.notificar(v.responsable_id, 'alta_rechazada', 'obras', p_obra, v_uid);

  ELSIF p_decision = 'es_la_misma' THEN
    IF v.congelada_antes IS NOT NULL THEN
      RAISE EXCEPTION 'Una edición parecida se aprueba o se rechaza' USING ERRCODE = 'OB022';
    END IF;
    SELECT * INTO v_existente FROM public.obras WHERE id = p_existente AND id <> p_obra AND activo AND NOT congelada;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La existente tiene que ser otra obra, activa y aprobada' USING ERRCODE = 'OB023';
    END IF;

    UPDATE public.obras SET congelada = false, activo = false, misma_que = p_existente WHERE id = p_obra;

    IF v_existente.responsable_id <> v.responsable_id AND NOT EXISTS (
      SELECT 1 FROM public.obras_participantes
      WHERE obra_id = p_existente AND usuario_id = v.responsable_id AND activo
    ) THEN
      v_participacion := gen_random_uuid();
      INSERT INTO public.obras_participantes (id, obra_id, usuario_id)
      VALUES (v_participacion, p_existente, v.responsable_id);
      PERFORM public.notificar(v_existente.responsable_id, 'obra_misma_sumado', 'obras_participantes',
                               v_participacion, v_uid);
    END IF;

    UPDATE public.contactos_vinculos_guardados SET registro_id = p_existente
    WHERE activo AND ente = 'obra' AND registro_id = p_obra;
    PERFORM public.contactos_crear_guardados(p_existente);
    PERFORM public.notificar(v.responsable_id, 'alta_es_la_misma', 'obras', p_obra, v_uid);

  ELSE
    RAISE EXCEPTION 'Se aprueba, se rechaza o es la misma' USING ERRCODE = 'OB024';
  END IF;
END;
$$;

-- Una persona se aprueba solo si es homónima: con el mismo teléfono o email
-- es la misma. "Es la misma" pasa a la existente los vínculos con registros
-- si `p_vincular`; la empresa de la persona, no (la existente tiene dueño).
CREATE OR REPLACE FUNCTION public.contactos_resolver(
  p_tipo text, p_id uuid, p_decision text, p_motivo text DEFAULT NULL,
  p_existente uuid DEFAULT NULL, p_vincular boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_antes jsonb;
  v_dueno uuid;
  v_entidad text := CASE p_tipo WHEN 'persona' THEN 'contactos_personas' WHEN 'empresa' THEN 'contactos_empresas' END;
BEGIN
  IF NOT public.usuario_tiene_permiso(v_uid, 'contactos_aprobar') THEN
    RAISE EXCEPTION 'Resuelve los contactos parecidos quien tiene "Aprobar altas"' USING ERRCODE = 'CO021';
  END IF;
  IF v_entidad IS NULL OR p_decision NOT IN ('aprobar', 'rechazar', 'es_la_misma') THEN
    RAISE EXCEPTION 'Una persona o una empresa, y se aprueba, se rechaza o es la misma' USING ERRCODE = 'CO019';
  END IF;

  IF p_tipo = 'persona' THEN
    SELECT congelada_antes, responsable_id INTO v_antes, v_dueno
    FROM public.contactos_personas WHERE id = p_id AND activo AND congelada FOR UPDATE;
  ELSE
    SELECT congelada_antes, creado_por INTO v_antes, v_dueno
    FROM public.contactos_empresas WHERE id = p_id AND activo AND congelada FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese contacto no espera aprobación' USING ERRCODE = 'CO022';
  END IF;

  IF p_decision = 'aprobar' THEN
    IF p_tipo = 'persona' THEN
      IF EXISTS (
        SELECT 1
        FROM public.contactos_personas p,
             public.contactos_personas_parecidas_de(p.id, p.nombre, p.telefono, p.email) x
        WHERE p.id = p_id AND x.coincide && '{telefono,email}'
      ) THEN
        RAISE EXCEPTION 'Con el mismo teléfono o email es la misma persona: no se aprueba' USING ERRCODE = 'CO023';
      END IF;
      UPDATE public.contactos_personas SET congelada = false, congelada_antes = NULL WHERE id = p_id;
    ELSE
      UPDATE public.contactos_empresas SET congelada = false, congelada_antes = NULL WHERE id = p_id;
    END IF;
    PERFORM public.contactos_crear_guardados(p_id);
    PERFORM public.notificar(v_dueno, 'alta_aprobada', v_entidad, p_id, v_uid);

  ELSIF p_decision = 'rechazar' THEN
    IF nullif(btrim(p_motivo), '') IS NULL THEN
      RAISE EXCEPTION 'Rechazar pide el motivo' USING ERRCODE = 'CO024';
    END IF;
    IF v_antes IS NULL THEN
      IF p_tipo = 'persona' THEN
        UPDATE public.contactos_personas SET congelada = false, activo = false, rechazo_motivo = btrim(p_motivo)
        WHERE id = p_id;
      ELSE
        UPDATE public.contactos_empresas SET congelada = false, activo = false, rechazo_motivo = btrim(p_motivo)
        WHERE id = p_id;
      END IF;
      PERFORM public.contactos_descartar_guardados(p_id);
    ELSIF p_tipo = 'persona' THEN
      UPDATE public.contactos_personas
      SET congelada = false, congelada_antes = NULL, rechazo_motivo = btrim(p_motivo),
          nombre = v_antes->>'nombre', telefono = v_antes->>'telefono', email = v_antes->>'email'
      WHERE id = p_id;
    ELSE
      UPDATE public.contactos_empresas
      SET congelada = false, congelada_antes = NULL, rechazo_motivo = btrim(p_motivo), nombre = v_antes->>'nombre'
      WHERE id = p_id;
    END IF;
    PERFORM public.notificar(v_dueno, 'alta_rechazada', v_entidad, p_id, v_uid);

  ELSE
    IF v_antes IS NOT NULL THEN
      RAISE EXCEPTION 'Una edición parecida se aprueba o se rechaza' USING ERRCODE = 'CO025';
    END IF;

    IF p_tipo = 'persona' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.contactos_personas WHERE id = p_existente AND id <> p_id AND activo AND NOT congelada
      ) THEN
        RAISE EXCEPTION 'La existente tiene que ser otra persona, activa y aprobada' USING ERRCODE = 'CO026';
      END IF;
      UPDATE public.contactos_personas SET congelada = false, activo = false, misma_que = p_existente WHERE id = p_id;
      IF p_vincular THEN
        UPDATE public.contactos_vinculos_guardados SET persona_id = p_existente
        WHERE activo AND persona_id = p_id AND ente IS NOT NULL;
      END IF;
    ELSE
      IF NOT EXISTS (
        SELECT 1 FROM public.contactos_empresas WHERE id = p_existente AND id <> p_id AND activo AND NOT congelada
      ) THEN
        RAISE EXCEPTION 'La existente tiene que ser otra empresa, activa y aprobada' USING ERRCODE = 'CO026';
      END IF;
      UPDATE public.contactos_empresas SET congelada = false, activo = false, misma_que = p_existente WHERE id = p_id;
      IF p_vincular THEN
        UPDATE public.contactos_vinculos_guardados SET empresa_id = p_existente WHERE activo AND empresa_id = p_id;
        UPDATE public.contactos_vinculos_guardados SET a_empresa_id = p_existente WHERE activo AND a_empresa_id = p_id;
      END IF;
    END IF;

    IF p_vincular THEN
      PERFORM public.contactos_crear_guardados(p_existente);
    END IF;
    PERFORM public.contactos_descartar_guardados(p_id);
    PERFORM public.notificar(v_dueno, 'alta_es_la_misma', v_entidad, p_id, v_uid);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_resolver(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_resolver(uuid, text, text, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_resolver(text, uuid, text, text, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_resolver(text, uuid, text, text, uuid, boolean) TO authenticated;

-- ============================================================
-- 7. "Por aprobar"
-- ============================================================
-- La congelada completa, con sus vínculos guardados; de cada parecida, lo
-- que la identifica y su id (para "es la misma"), sin contactos.
CREATE OR REPLACE FUNCTION public.obras_por_aprobar()
RETURNS TABLE (
  id uuid, nombre text, direccion text, localidad text, notas text, origen origen_obra, tipo tipo_obra,
  estado estado_obra, responsable text, created_at timestamptz, antes jsonb, parecidas jsonb, guardados jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT o.id, o.nombre, o.direccion, o.localidad, o.notas, o.origen, o.tipo, o.estado, u.nombre, o.created_at,
         o.congelada_antes,
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
                   'id', p.id, 'nombre', p.nombre, 'direccion', p.direccion, 'responsable', pu.nombre,
                   'coincide', x.coincide) ORDER BY p.nombre), '[]')
          FROM public.obras_parecidas_de(o.id, o.nombre, o.direccion) x
          JOIN public.obras p     ON p.id = x.id
          JOIN public.usuarios pu ON pu.id = p.responsable_id),
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
                   'tipo', CASE WHEN g.persona_id IS NOT NULL THEN 'persona' ELSE 'empresa' END,
                   'nombre', coalesce(cp.nombre, ce.nombre), 'roles', g.roles)), '[]')
          FROM public.contactos_vinculos_guardados g
          LEFT JOIN public.contactos_personas cp ON cp.id = g.persona_id
          LEFT JOIN public.contactos_empresas ce ON ce.id = g.empresa_id
          WHERE g.activo AND g.ente = 'obra' AND g.registro_id = o.id)
  FROM public.obras o
  JOIN public.usuarios u ON u.id = o.responsable_id
  WHERE o.activo AND o.congelada AND public.tiene_permiso('obras_aprobar')
  ORDER BY o.created_at;
$$;

-- De la persona, teléfono y email no: se piden con "Ver contacto", que
-- registra. De cada parecida, qué dato coincidió, sin mostrarlo.
CREATE OR REPLACE FUNCTION public.contactos_por_aprobar()
RETURNS TABLE (
  tipo text, id uuid, nombre text, notas text, dueno text, equipo text, created_at timestamptz,
  antes jsonb, parecidas jsonb, guardados jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH c AS (
    SELECT 'persona'::text AS tipo, p.id, p.nombre, p.notas, p.responsable_id AS dueno_id, NULL::uuid AS equipo_id,
           p.created_at,
           CASE WHEN p.congelada_antes IS NOT NULL THEN jsonb_build_object('nombre', p.congelada_antes->'nombre') END AS antes,
           (SELECT jsonb_agg(jsonb_build_object(
                     'id', q.id, 'nombre', q.nombre, 'dueno', qu.nombre, 'equipo', NULL, 'coincide', x.coincide)
                     ORDER BY q.nombre)
            FROM public.contactos_personas_parecidas_de(p.id, p.nombre, p.telefono, p.email) x
            JOIN public.contactos_personas q ON q.id = x.id
            JOIN public.usuarios qu          ON qu.id = q.responsable_id) AS parecidas
    FROM public.contactos_personas p
    WHERE p.activo AND p.congelada
    UNION ALL
    SELECT 'empresa', e.id, e.nombre, e.notas, e.creado_por, e.equipo_id, e.created_at, e.congelada_antes,
           (SELECT jsonb_agg(jsonb_build_object(
                     'id', q.id, 'nombre', q.nombre, 'dueno', qu.nombre, 'equipo', qe.nombre, 'coincide', '{nombre}'::text[])
                     ORDER BY q.nombre)
            FROM public.contactos_empresas_parecidas_de(e.id, e.nombre) x
            JOIN public.contactos_empresas q ON q.id = x.id
            JOIN public.usuarios qu          ON qu.id = q.creado_por
            LEFT JOIN public.equipos qe      ON qe.id = q.equipo_id)
    FROM public.contactos_empresas e
    WHERE e.activo AND e.congelada
  )
  SELECT c.tipo, c.id, c.nombre, c.notas, u.nombre, q.nombre, c.created_at, c.antes,
         coalesce(c.parecidas, '[]'),
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
                   'ente', g.ente, 'registro', public.etiqueta_registro(g.ente, g.registro_id), 'roles', g.roles,
                   'empresa', ae.nombre, 'cargo', g.cargo)), '[]')
          FROM public.contactos_vinculos_guardados g
          LEFT JOIN public.contactos_empresas ae ON ae.id = g.a_empresa_id
          WHERE g.activo AND c.id IN (g.persona_id, g.empresa_id))
  FROM c
  JOIN public.usuarios u     ON u.id = c.dueno_id
  LEFT JOIN public.equipos q ON q.id = c.equipo_id
  WHERE public.tiene_permiso('contactos_aprobar')
  ORDER BY c.created_at;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_por_aprobar() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_por_aprobar() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_por_aprobar() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_por_aprobar() TO authenticated;

-- ============================================================
-- 8. Avisos
-- ============================================================
-- Solo de los propios. "Por aprobar" desaparece al resolverse. El link, solo
-- si el lector ve el registro; de "es la misma", a la existente.
CREATE OR REPLACE FUNCTION public.duplicados_avisos()
RETURNS TABLE (notificacion_id uuid, etiqueta text, motivo text, destino text, destino_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH n AS (
    SELECT n.id, n.tipo, n.entidad, n.entidad_id, n.usuario_id,
           CASE n.entidad WHEN 'obras' THEN 'obra' WHEN 'contactos_personas' THEN 'persona'
                          WHEN 'contactos_empresas' THEN 'empresa' END AS ente
    FROM public.usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo
      AND n.tipo IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma')
  ),
  f AS (
    SELECT n.*, r.nombre, r.activo, r.congelada, r.antes, r.rechazo, r.misma
    FROM n
    JOIN LATERAL (
      SELECT o.nombre, o.activo, o.congelada, o.congelada_antes AS antes, o.rechazo_motivo AS rechazo, o.misma_que AS misma
      FROM public.obras o WHERE n.entidad = 'obras' AND o.id = n.entidad_id
      UNION ALL
      SELECT p.nombre, p.activo, p.congelada, p.congelada_antes, p.rechazo_motivo, p.misma_que
      FROM public.contactos_personas p WHERE n.entidad = 'contactos_personas' AND p.id = n.entidad_id
      UNION ALL
      SELECT e.nombre, e.activo, e.congelada, e.congelada_antes, e.rechazo_motivo, e.misma_que
      FROM public.contactos_empresas e WHERE n.entidad = 'contactos_empresas' AND e.id = n.entidad_id
    ) r ON true
  )
  SELECT f.id, f.nombre,
         CASE WHEN f.antes IS NOT NULL THEN 'edición' END,
         CASE f.ente WHEN 'obra' THEN 'obras_por_aprobar' ELSE 'contactos_por_aprobar' END,
         f.entidad_id
  FROM f
  WHERE f.tipo = 'alta_por_aprobar' AND f.activo AND f.congelada

  UNION ALL

  SELECT f.id, f.nombre,
         CASE f.tipo
           WHEN 'alta_rechazada' THEN f.rechazo
           WHEN 'alta_aprobada' THEN (
             SELECT CASE WHEN count(*) = 1 THEN '1 vínculo no se creó'
                         WHEN count(*) > 1 THEN count(*) || ' vínculos no se crearon' END
             FROM public.contactos_vinculos_guardados g
             WHERE g.resultado = 'sin_permiso' AND g.cargado_por = f.usuario_id
               AND f.entidad_id IN (g.persona_id, g.empresa_id, g.registro_id, g.a_empresa_id))
           ELSE CASE WHEN x.ve THEN public.etiqueta_registro(f.ente, f.misma) END
         END,
         CASE WHEN x.ve THEN f.ente END,
         CASE WHEN x.ve THEN coalesce(f.misma, f.entidad_id) END
  FROM f
  CROSS JOIN LATERAL (
    SELECT public.puede_abrir_registro(f.ente, coalesce(f.misma, f.entidad_id), auth.uid()) AS ve
  ) x
  WHERE f.tipo <> 'alta_por_aprobar'

  UNION ALL

  SELECT n.id, o.nombre, u.nombre,
         CASE WHEN public.puede_abrir_registro('obra', o.id, auth.uid()) THEN 'obra' END,
         o.id
  FROM public.usuario_notificaciones n
  JOIN public.obras_participantes p ON p.id = n.entidad_id
  JOIN public.obras o               ON o.id = p.obra_id
  JOIN public.usuarios u            ON u.id = p.usuario_id
  WHERE n.usuario_id = auth.uid() AND n.activo AND n.tipo = 'obra_misma_sumado';
$$;

REVOKE EXECUTE ON FUNCTION public.duplicados_avisos() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duplicados_avisos() TO authenticated;

-- Como `sql/134`, más la rama de las altas parecidas. Las ramas de `obras`,
-- `obras_participantes` y `contactos_personas` dejan afuera esos tipos, que
-- apuntan a las mismas tablas.
CREATE OR REPLACE FUNCTION public.notificaciones_listar(p_limite int DEFAULT 30)
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
           u.nombre AS etiqueta,
           NULL::text AS motivo,
           'mi_equipo'::text AS destino,
           m.usuario_id AS destino_id
    FROM mias n
    JOIN equipos_miembros m ON m.id = n.entidad_id AND m.activo
    JOIN usuarios u         ON u.id = m.usuario_id
    WHERE n.entidad = 'equipos_miembros'

    UNION ALL

    SELECT n.id,
           CASE WHEN n.tipo = 'delegador_designado' THEN e.nombre ELSE s.nombre END,
           NULL::text,
           CASE WHEN n.tipo = 'delegador_designado' THEN 'mi_equipo' ELSE s.modulo END,
           us.id
    FROM mias n
    JOIN usuario_submodulos us ON us.id = n.entidad_id AND us.activo
    JOIN submodulos s          ON s.id = us.submodulo_id
    LEFT JOIN equipos e        ON e.id = mi_equipo()
    WHERE n.entidad = 'usuario_submodulos'

    UNION ALL

    SELECT n.id,
           coalesce(t.titulo, x.titulo),
           CASE WHEN n.tipo = 'pedido_rechazado' THEN t.motivo_rechazo END,
           CASE WHEN t.id IS NOT NULL THEN 'tarea' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas t                 ON t.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas' AND (t.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id,
           coalesce(h.titulo, x.titulo),
           NULL::text,
           CASE WHEN h.id IS NOT NULL THEN 'hilo' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas_hilos h           ON h.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas_hilos' AND (h.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, o.nombre, NULL::text, 'obra', o.id
    FROM mias n
    JOIN obras o ON o.id = n.entidad_id
    WHERE n.entidad = 'obras'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma')

    UNION ALL

    SELECT n.id,
           coalesce(o.nombre, x.nombre),
           NULL::text,
           CASE WHEN o.id IS NOT NULL THEN 'obra' END,
           coalesce(o.id, x.obra_id)
    FROM mias n
    LEFT JOIN obras_avisos_salida() x ON x.notificacion_id = n.id
    LEFT JOIN obras_participantes p   ON p.id = n.entidad_id
    LEFT JOIN obras o                 ON o.id = coalesce(p.obra_id, x.obra_id)
    WHERE n.entidad = 'obras_participantes' AND n.tipo <> 'obra_misma_sumado'
      AND (o.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, c.nombre, NULL::text, 'persona', c.id
    FROM mias n
    JOIN contactos_personas c ON c.id = n.entidad_id
    WHERE n.entidad = 'contactos_personas'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma')

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN duplicados_avisos() x ON x.notificacion_id = n.id

    UNION ALL

    SELECT n.id,
           a.nombre,
           c.cuantos || ' ' || CASE
             WHEN n.tipo = 'hilos_huerfanos' THEN
               CASE WHEN c.cuantos = 1 THEN 'hilo abierto' ELSE 'hilos abiertos' END
             WHEN n.tipo IN ('obras_huerfanas', 'obras_recibidas') THEN
               CASE WHEN c.cuantos = 1 THEN 'obra' ELSE 'obras' END
             ELSE
               CASE WHEN c.cuantos = 1 THEN 'persona' ELSE 'personas' END
           END,
           CASE n.tipo
             WHEN 'hilos_huerfanos' THEN 'tareas_todas'
             WHEN 'obras_huerfanas' THEN 'obras_todas'
             WHEN 'obras_recibidas' THEN 'obras'
             ELSE 'contactos'
           END,
           n.entidad_id
    FROM mias n
    CROSS JOIN LATERAL (
      SELECT CASE n.tipo
        WHEN 'hilos_huerfanos' THEN (
          SELECT count(*) FROM tareas_hilos h
          WHERE h.responsable_id = n.entidad_id AND h.activo AND h.estado = 'abierto')
        WHEN 'obras_huerfanas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.entidad_id AND o.activo)
        WHEN 'personas_huerfanas' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.entidad_id AND p.activo)
        WHEN 'obras_recibidas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.usuario_id AND o.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'obra' AND e.registro_id = o.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
        WHEN 'agenda_recibida' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.usuario_id AND p.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'persona' AND e.registro_id = p.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
      END AS cuantos
    ) c
    LEFT JOIN notificaciones_actores() a ON a.id = n.entidad_id
    WHERE n.entidad = 'usuarios' AND c.cuantos > 0
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.notificaciones_listar(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notificaciones_listar(int) TO authenticated;
