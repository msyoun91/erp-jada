-- sql/138 — obras y contactos, tramo 3: lo parecido se congela.
--
-- Una obra, persona o empresa que se parece a otra activa entra congelada, y
-- editar un dato comparado que pasa a parecerse también congela. Lo resuelve
-- quien tiene `obras_aprobar` / `contactos_aprobar` (`sql/139`); lo que carga
-- quien tiene la función no se congela.
--
-- - Parecida: trigramas sobre el texto normalizado. Obra: nombre ≥ 0,45, o
--   dirección ≥ 0,45 con los mismos números. Persona: mismo teléfono, mismo
--   email o nombre ≥ 0,55. Empresa: nombre ≥ 0,45. Contra todo lo activo,
--   congeladas incluidas.
-- - En la fila: `congelada`, `congelada_antes` (los datos comparados como
--   estaban aprobados; NULL si es un alta), `rechazo_motivo` y `misma_que`
--   (la existente, si se resolvió "es la misma"). Fuera de los GRANT de
--   escritura: los escriben este trigger y las funciones de `sql/139`. Por eso
--   un UPDATE que cambia `congelada` es del sistema, y las reglas de actor no
--   lo miran.
-- - Un alta congelada la ven su responsable (quien la cargó: no se transfiere)
--   y "ver todo"; una edición congelada, los que ya la veían. Congelada, la
--   obra no cambia de estado ni se transfiere, y la persona no se transfiere
--   (OB018, CO020). No vincularla es de `sql/139`.
-- - El alta se emite al aprobarse; rechazada o "es la misma", no existió.
-- - Aviso a ciegas antes de guardar: `obras_parecidas`, `contactos_parecidas`.
--
-- Decisiones: `decisiones/obras.md` → *Altas parecidas*, `decisiones/contactos.md`
-- → *Altas parecidas*. Test: `sql/tests/duplicados.sql`.

-- ============================================================
-- 1. Columnas
-- ============================================================
ALTER TABLE public.obras
  ADD COLUMN IF NOT EXISTS congelada boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS congelada_antes jsonb,
  ADD COLUMN IF NOT EXISTS rechazo_motivo text CHECK (length(rechazo_motivo) BETWEEN 1 AND 1000),
  ADD COLUMN IF NOT EXISTS misma_que uuid REFERENCES public.obras(id);

ALTER TABLE public.contactos_personas
  ADD COLUMN IF NOT EXISTS congelada boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS congelada_antes jsonb,
  ADD COLUMN IF NOT EXISTS rechazo_motivo text CHECK (length(rechazo_motivo) BETWEEN 1 AND 1000),
  ADD COLUMN IF NOT EXISTS misma_que uuid REFERENCES public.contactos_personas(id);

ALTER TABLE public.contactos_empresas
  ADD COLUMN IF NOT EXISTS congelada boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS congelada_antes jsonb,
  ADD COLUMN IF NOT EXISTS rechazo_motivo text CHECK (length(rechazo_motivo) BETWEEN 1 AND 1000),
  ADD COLUMN IF NOT EXISTS misma_que uuid REFERENCES public.contactos_empresas(id);

-- La persona tiene GRANT SELECT por columna; `congelada_antes` guarda el
-- teléfono y el email anteriores, así que queda afuera.
GRANT SELECT (congelada, rechazo_motivo, misma_que) ON public.contactos_personas TO authenticated;

-- ============================================================
-- 2. Permisos
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT f.codigo, f.modulo, 'funcion', 'Aprobar altas', f.orden, v.id, false
FROM (VALUES
  ('obras_aprobar',     'obras',     3, 'obras_ver'),
  ('contactos_aprobar', 'contactos', 2, 'contactos_ver')
) AS f (codigo, modulo, orden, vista)
JOIN public.submodulos v ON v.codigo = f.vista AND v.activo
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = f.codigo AND s.activo);

-- ============================================================
-- 3. Parecida
-- ============================================================
CREATE OR REPLACE FUNCTION public.normalizar_texto(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT nullif(btrim(regexp_replace(
    lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p, ''))),
    '\s+', ' ', 'g')), '');
$$;

CREATE OR REPLACE FUNCTION public.numeros_de(p text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT ARRAY(SELECT DISTINCT m[1] FROM regexp_matches(coalesce(p, ''), '(\d+)', 'g') m ORDER BY 1);
$$;

-- Sin los números, cualquier obra sobre la misma avenida se parecía.
CREATE OR REPLACE FUNCTION public.obras_parecidas_de(p_obra uuid, p_nombre text, p_direccion text)
RETURNS TABLE (id uuid, coincide text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH q AS (
    SELECT public.normalizar_texto(p_nombre) AS n,
           public.normalizar_texto(p_direccion) AS d,
           public.numeros_de(p_direccion) AS num
  ),
  c AS (
    SELECT o.id,
           extensions.similarity(public.normalizar_texto(o.nombre), q.n) >= 0.45 AS por_nombre,
           cardinality(q.num) > 0
             AND public.numeros_de(o.direccion) = q.num
             AND extensions.similarity(public.normalizar_texto(o.direccion), q.d) >= 0.45 AS por_direccion
    FROM public.obras o, q
    WHERE o.activo AND o.id IS DISTINCT FROM p_obra
  )
  SELECT id, CASE WHEN por_nombre THEN 'nombre' ELSE 'direccion' END
  FROM c
  WHERE por_nombre OR por_direccion;
$$;

CREATE OR REPLACE FUNCTION public.contactos_personas_parecidas_de(
  p_persona uuid, p_nombre text, p_telefono text, p_email text
)
RETURNS TABLE (id uuid, coincide text[])
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH q AS (
    SELECT public.normalizar_texto(p_nombre) AS n,
           public.normalizar_telefono(p_telefono) AS tel,
           nullif(lower(btrim(p_email)), '') AS mail
  ),
  c AS (
    SELECT p.id, array_remove(ARRAY[
             CASE WHEN p.telefono = q.tel THEN 'telefono' END,
             CASE WHEN p.email = q.mail THEN 'email' END,
             CASE WHEN extensions.similarity(public.normalizar_texto(p.nombre), q.n) >= 0.55 THEN 'nombre' END
           ], NULL) AS coincide
    FROM public.contactos_personas p, q
    WHERE p.activo AND p.id IS DISTINCT FROM p_persona
  )
  SELECT id, coincide FROM c WHERE cardinality(coincide) > 0;
$$;

CREATE OR REPLACE FUNCTION public.contactos_empresas_parecidas_de(p_empresa uuid, p_nombre text)
RETURNS TABLE (id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT e.id
  FROM public.contactos_empresas e
  WHERE e.activo AND e.id IS DISTINCT FROM p_empresa
    AND extensions.similarity(public.normalizar_texto(e.nombre), public.normalizar_texto(p_nombre)) >= 0.45;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_parecidas_de(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_personas_parecidas_de(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_empresas_parecidas_de(uuid, text) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. Ver: un alta congelada, solo quien la cargó
-- ============================================================
-- Obra: su responsable (quien la cargó: congelada no se transfiere) y "ver
-- todo". Participantes no tiene; el jefe del equipo, hasta que se apruebe, no.
-- Una edición congelada la siguen viendo y trabajando los mismos.
CREATE OR REPLACE FUNCTION public.obras_puede_ver_obra_de(
  p_obra uuid, p_responsable uuid, p_equipo uuid, p_activo boolean, p_usuario uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'obras_todas')
    OR (
      p_activo
      AND public.usuario_tiene_permiso(p_usuario, 'obras_ver')
      AND (
        p_responsable = p_usuario
        OR (
          NOT EXISTS (
            SELECT 1 FROM public.obras c
            WHERE c.id = p_obra AND c.congelada AND c.congelada_antes IS NULL
          )
          AND (
            EXISTS (
              SELECT 1 FROM public.obras_participantes p
              WHERE p.obra_id = p_obra AND p.activo AND p.usuario_id = p_usuario
            )
            OR (
              public.usuario_tiene_permiso(p_usuario, 'obras_equipo')
              AND (
                p_equipo = public.equipo_de(p_usuario)
                OR EXISTS (
                  SELECT 1 FROM public.obras_participantes p
                  WHERE p.obra_id = p_obra AND p.activo AND p.equipo_id = public.equipo_de(p_usuario)
                )
              )
            )
          )
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.obras_trabaja_de(p_obra uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras o
    WHERE o.id = p_obra
      AND o.activo
      AND public.usuario_tiene_permiso(p_usuario, 'obras_ver')
      AND (
        o.responsable_id = p_usuario
        OR public.usuario_tiene_permiso(p_usuario, 'obras_administrar')
        OR (
          NOT (o.congelada AND o.congelada_antes IS NULL)
          AND (
            EXISTS (
              SELECT 1 FROM public.obras_participantes p
              WHERE p.obra_id = o.id AND p.activo AND p.usuario_id = p_usuario
            )
            OR (public.usuario_tiene_permiso(p_usuario, 'obras_equipo') AND o.equipo_id = public.equipo_de(p_usuario))
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.obras_a_cargo_de(p_obra uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras o
    WHERE o.id = p_obra
      AND o.activo
      AND public.usuario_tiene_permiso(p_usuario, 'obras_ver')
      AND (
        o.responsable_id = p_usuario
        OR public.usuario_tiene_permiso(p_usuario, 'obras_administrar')
        OR (
          NOT (o.congelada AND o.congelada_antes IS NULL)
          AND public.usuario_tiene_permiso(p_usuario, 'obras_equipo')
          AND o.equipo_id = public.equipo_de(p_usuario)
        )
      )
  );
$$;

-- Persona: el alta ya la ve solo su dueño (congelada no se vincula). Suma el
-- aprobador, para "Ver contacto" sobre la congelada (queda registrado).
CREATE OR REPLACE FUNCTION public.contactos_puede_ver_persona_de(
  p_persona uuid, p_responsable uuid, p_activo boolean, p_usuario uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'contactos_administrar')
    OR (
      public.usuario_tiene_permiso(p_usuario, 'contactos_ver')
      AND (
        (p_activo AND p_responsable = p_usuario)
        OR EXISTS (
          SELECT 1 FROM public.contactos_vinculos v
          WHERE v.persona_id = p_persona AND v.activo
            AND public.puede_abrir_registro(v.ente, v.registro_id, p_usuario)
        )
        OR (
          public.usuario_tiene_permiso(p_usuario, 'contactos_aprobar')
          AND EXISTS (SELECT 1 FROM public.contactos_personas c WHERE c.id = p_persona AND c.congelada AND c.activo)
        )
      )
    );
$$;

-- Empresa: el alta congelada, quien la cargó, no su equipo.
CREATE OR REPLACE FUNCTION public.contactos_puede_ver_empresa_de(
  p_empresa uuid, p_equipo uuid, p_creado_por uuid, p_activo boolean, p_usuario uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'contactos_administrar')
    OR (
      public.usuario_tiene_permiso(p_usuario, 'contactos_ver')
      AND (
        (p_activo AND CASE
          WHEN EXISTS (
            SELECT 1 FROM public.contactos_empresas c
            WHERE c.id = p_empresa AND c.congelada AND c.congelada_antes IS NULL
          ) THEN p_creado_por = p_usuario
          ELSE p_equipo = public.equipo_de(p_usuario) OR (p_equipo IS NULL AND p_creado_por = p_usuario)
        END)
        OR EXISTS (
          SELECT 1 FROM public.contactos_vinculos v
          WHERE v.empresa_id = p_empresa AND v.activo
            AND public.puede_abrir_registro(v.ente, v.registro_id, p_usuario)
        )
      )
    );
$$;

-- ============================================================
-- 5. Reglas de actor: el sistema no pasa por ellas; congelada, se frena
-- ============================================================
-- Igual que `sql/126` y `sql/127`, más: un UPDATE que cambia `congelada` es
-- de una función de `sql/139` (el cliente no la escribe) y no mira al actor;
-- congelada, la obra no cambia de estado ni se transfiere (OB018) y la persona
-- no se transfiere (CO020).
CREATE OR REPLACE FUNCTION public.obras_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_abiertos estado_obra[] := '{idea,en_busqueda,en_cotizacion}';
BEGIN
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL AND NEW.congelada IS NOT DISTINCT FROM OLD.congelada THEN
    IF (NEW.nombre, NEW.direccion, NEW.localidad, NEW.notas, NEW.origen, NEW.tipo, NEW.compra_estimada,
        NEW.estado, NEW.motivo_perdida, NEW.estado_nota)
       IS DISTINCT FROM
       (OLD.nombre, OLD.direccion, OLD.localidad, OLD.notas, OLD.origen, OLD.tipo, OLD.compra_estimada,
        OLD.estado, OLD.motivo_perdida, OLD.estado_nota)
       AND NOT public.obras_trabaja_de(OLD.id, v_uid) THEN
      RAISE EXCEPTION 'Solo quien trabaja la obra la edita' USING ERRCODE = 'OB002';
    END IF;

    IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id
       AND NOT public.obras_a_cargo_de(OLD.id, v_uid) THEN
      RAISE EXCEPTION 'Transfieren la obra su responsable, su jefe o el admin' USING ERRCODE = 'OB003';
    END IF;

    IF OLD.activo AND NOT NEW.activo AND NOT public.obras_a_cargo_de(OLD.id, v_uid) THEN
      RAISE EXCEPTION 'Desactivan la obra su responsable, su jefe o el admin' USING ERRCODE = 'OB004';
    END IF;

    IF NOT OLD.activo AND NEW.activo AND NOT public.usuario_tiene_permiso(v_uid, 'obras_administrar') THEN
      RAISE EXCEPTION 'Solo el admin reactiva una obra' USING ERRCODE = 'OB005';
    END IF;

    IF OLD.congelada AND (NEW.estado, NEW.responsable_id) IS DISTINCT FROM (OLD.estado, OLD.responsable_id) THEN
      RAISE EXCEPTION 'La obra espera aprobación: no cambia de estado ni se transfiere' USING ERRCODE = 'OB018';
    END IF;
  END IF;

  IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id THEN
    IF NOT public.usuario_tiene_permiso(NEW.responsable_id, 'obras_ver') THEN
      RAISE EXCEPTION 'La obra se transfiere a alguien activo que ve Obras' USING ERRCODE = 'OB006';
    END IF;
    NEW.equipo_id := public.equipo_de(NEW.responsable_id);
  END IF;

  IF OLD.activo AND NOT NEW.activo AND NEW.estado = 'contratada' THEN
    RAISE EXCEPTION 'Una obra contratada no se desactiva' USING ERRCODE = 'OB007';
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    IF NEW.estado_nota IS NOT DISTINCT FROM OLD.estado_nota THEN
      NEW.estado_nota := NULL;
    END IF;

    IF OLD.estado = 'contratada' THEN
      IF NEW.estado <> ALL (v_abiertos) THEN
        RAISE EXCEPTION 'Una obra contratada vuelve a idea, búsqueda o cotización, no a perdida' USING ERRCODE = 'OB008';
      END IF;
      IF NEW.estado_nota IS NULL THEN
        RAISE EXCEPTION 'Revertir una obra contratada pide la causa' USING ERRCODE = 'OB009';
      END IF;
    ELSIF OLD.estado = 'perdida' AND NEW.estado = 'contratada' THEN
      RAISE EXCEPTION 'Una obra perdida se reabre a idea, búsqueda o cotización' USING ERRCODE = 'OB010';
    END IF;

    IF NEW.estado = 'perdida' THEN
      IF NEW.motivo_perdida IS NULL THEN
        RAISE EXCEPTION 'Perder una obra pide el motivo' USING ERRCODE = 'OB011';
      END IF;
      IF NEW.motivo_perdida = 'otro' AND NEW.estado_nota IS NULL THEN
        RAISE EXCEPTION 'Con motivo "otro", contá qué pasó' USING ERRCODE = 'OB012';
      END IF;
    ELSE
      NEW.motivo_perdida := NULL;
      IF OLD.estado <> 'contratada' THEN
        NEW.estado_nota := NULL;
      END IF;
    END IF;
  ELSE
    NEW.motivo_perdida := OLD.motivo_perdida;
    NEW.estado_nota := OLD.estado_nota;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_personas_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adm boolean;
BEGIN
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL AND NEW.congelada IS NOT DISTINCT FROM OLD.congelada THEN
    v_adm := public.usuario_tiene_permiso(v_uid, 'contactos_administrar');

    IF (NEW.nombre, NEW.telefono, NEW.email, NEW.notas) IS DISTINCT FROM (OLD.nombre, OLD.telefono, OLD.email, OLD.notas)
       AND NOT v_adm
       AND NOT (
         OLD.activo AND (
           OLD.responsable_id = v_uid
           OR EXISTS (
             SELECT 1 FROM public.contactos_vinculos v
             WHERE v.persona_id = OLD.id AND v.activo AND public.trabaja_registro(v.ente, v.registro_id)
           )
         )
       ) THEN
      RAISE EXCEPTION 'Corrigen a una persona su dueño, el admin o quien trabaja una obra donde está' USING ERRCODE = 'CO001';
    END IF;

    IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id AND OLD.responsable_id <> v_uid AND NOT v_adm THEN
      RAISE EXCEPTION 'Transfieren una persona su dueño o el admin' USING ERRCODE = 'CO002';
    END IF;

    IF OLD.activo AND NOT NEW.activo AND OLD.responsable_id <> v_uid AND NOT v_adm THEN
      RAISE EXCEPTION 'Desactivan una persona su dueño o el admin' USING ERRCODE = 'CO003';
    END IF;

    IF NOT OLD.activo AND NEW.activo AND NOT v_adm THEN
      RAISE EXCEPTION 'Solo el admin reactiva un contacto' USING ERRCODE = 'CO004';
    END IF;

    IF OLD.congelada AND NEW.responsable_id IS DISTINCT FROM OLD.responsable_id THEN
      RAISE EXCEPTION 'El contacto espera aprobación: no se transfiere ni se vincula' USING ERRCODE = 'CO020';
    END IF;
  END IF;

  IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id
     AND NOT public.usuario_tiene_permiso(NEW.responsable_id, 'contactos_ver') THEN
    RAISE EXCEPTION 'Una persona se transfiere a alguien activo que ve Contactos' USING ERRCODE = 'CO005';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_empresas_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adm boolean;
BEGIN
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL AND NEW.congelada IS NOT DISTINCT FROM OLD.congelada THEN
    v_adm := public.usuario_tiene_permiso(v_uid, 'contactos_administrar');

    IF (NEW.nombre, NEW.telefono, NEW.email, NEW.web, NEW.notas)
       IS DISTINCT FROM (OLD.nombre, OLD.telefono, OLD.email, OLD.web, OLD.notas)
       AND NOT v_adm
       AND NOT (
         OLD.activo AND (
           OLD.equipo_id = public.equipo_de(v_uid)
           OR (OLD.equipo_id IS NULL AND OLD.creado_por = v_uid)
           OR EXISTS (
             SELECT 1 FROM public.contactos_vinculos v
             WHERE v.empresa_id = OLD.id AND v.activo AND public.trabaja_registro(v.ente, v.registro_id)
           )
         )
       ) THEN
      RAISE EXCEPTION 'Corrigen una empresa su equipo, el admin o quien trabaja una obra donde está' USING ERRCODE = 'CO006';
    END IF;

    IF OLD.activo AND NOT NEW.activo AND NOT v_adm AND NOT (
      CASE WHEN OLD.equipo_id IS NULL OR (OLD.congelada AND OLD.congelada_antes IS NULL) THEN OLD.creado_por = v_uid
           ELSE OLD.equipo_id = public.equipo_de(v_uid) AND public.usuario_tiene_permiso(v_uid, 'usuarios_delegar')
      END
    ) THEN
      RAISE EXCEPTION 'Desactivan una empresa el jefe de su equipo o el admin' USING ERRCODE = 'CO007';
    END IF;

    IF NOT OLD.activo AND NEW.activo AND NOT v_adm THEN
      RAISE EXCEPTION 'Solo el admin reactiva un contacto' USING ERRCODE = 'CO004';
    END IF;

    IF NEW.equipo_id IS DISTINCT FROM OLD.equipo_id AND NOT v_adm THEN
      RAISE EXCEPTION 'Solo el admin cambia el equipo de una empresa' USING ERRCODE = 'CO008';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 6. Congelar — después de las reglas y de normalizar
-- ============================================================
-- Los triggers corren por nombre: `*_congelar` va después de `*_al_editar`,
-- que así ve `congelada` como la mandó el UPDATE. Congela lo que carga o edita
-- alguien sin la función de aprobar; descongela, si deja de parecerse,
-- cualquiera. Editar de nuevo mientras espera no pisa `congelada_antes`.
CREATE OR REPLACE FUNCTION public.obras_congelar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_congela boolean := pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL
                       AND NOT public.usuario_tiene_permiso(auth.uid(), 'obras_aprobar');
  v_parecida boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.congelada := v_congela AND EXISTS (SELECT 1 FROM public.obras_parecidas_de(NEW.id, NEW.nombre, NEW.direccion));
    NEW.congelada_antes := NULL;
    NEW.rechazo_motivo := NULL;
    NEW.misma_que := NULL;
    RETURN NEW;
  END IF;

  IF NEW.congelada IS DISTINCT FROM OLD.congelada
     OR (NEW.nombre, NEW.direccion) IS NOT DISTINCT FROM (OLD.nombre, OLD.direccion) THEN
    RETURN NEW;
  END IF;

  v_parecida := EXISTS (SELECT 1 FROM public.obras_parecidas_de(NEW.id, NEW.nombre, NEW.direccion));
  IF OLD.congelada AND NOT v_parecida THEN
    NEW.congelada := false;
    NEW.congelada_antes := NULL;
  ELSIF NOT OLD.congelada AND v_parecida AND v_congela THEN
    NEW.congelada := true;
    NEW.congelada_antes := jsonb_build_object('nombre', OLD.nombre, 'direccion', OLD.direccion);
    NEW.rechazo_motivo := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_personas_congelar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_congela boolean := pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL
                       AND NOT public.usuario_tiene_permiso(auth.uid(), 'contactos_aprobar');
  v_parecida boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.congelada := v_congela AND EXISTS (
      SELECT 1 FROM public.contactos_personas_parecidas_de(NEW.id, NEW.nombre, NEW.telefono, NEW.email));
    NEW.congelada_antes := NULL;
    NEW.rechazo_motivo := NULL;
    NEW.misma_que := NULL;
    RETURN NEW;
  END IF;

  IF NEW.congelada IS DISTINCT FROM OLD.congelada
     OR (NEW.nombre, NEW.telefono, NEW.email) IS NOT DISTINCT FROM (OLD.nombre, OLD.telefono, OLD.email) THEN
    RETURN NEW;
  END IF;

  v_parecida := EXISTS (
    SELECT 1 FROM public.contactos_personas_parecidas_de(NEW.id, NEW.nombre, NEW.telefono, NEW.email));
  IF OLD.congelada AND NOT v_parecida THEN
    NEW.congelada := false;
    NEW.congelada_antes := NULL;
  ELSIF NOT OLD.congelada AND v_parecida AND v_congela THEN
    NEW.congelada := true;
    NEW.congelada_antes := jsonb_build_object('nombre', OLD.nombre, 'telefono', OLD.telefono, 'email', OLD.email);
    NEW.rechazo_motivo := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_empresas_congelar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_congela boolean := pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL
                       AND NOT public.usuario_tiene_permiso(auth.uid(), 'contactos_aprobar');
  v_parecida boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.congelada := v_congela AND EXISTS (SELECT 1 FROM public.contactos_empresas_parecidas_de(NEW.id, NEW.nombre));
    NEW.congelada_antes := NULL;
    NEW.rechazo_motivo := NULL;
    NEW.misma_que := NULL;
    RETURN NEW;
  END IF;

  IF NEW.congelada IS DISTINCT FROM OLD.congelada OR NEW.nombre IS NOT DISTINCT FROM OLD.nombre THEN
    RETURN NEW;
  END IF;

  v_parecida := EXISTS (SELECT 1 FROM public.contactos_empresas_parecidas_de(NEW.id, NEW.nombre));
  IF OLD.congelada AND NOT v_parecida THEN
    NEW.congelada := false;
    NEW.congelada_antes := NULL;
  ELSIF NOT OLD.congelada AND v_parecida AND v_congela THEN
    NEW.congelada := true;
    NEW.congelada_antes := jsonb_build_object('nombre', OLD.nombre);
    NEW.rechazo_motivo := NULL;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_congelar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_personas_congelar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_empresas_congelar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS obras_congelar ON public.obras;
CREATE TRIGGER obras_congelar
  BEFORE INSERT OR UPDATE ON public.obras
  FOR EACH ROW EXECUTE FUNCTION public.obras_congelar();

DROP TRIGGER IF EXISTS contactos_personas_congelar ON public.contactos_personas;
CREATE TRIGGER contactos_personas_congelar
  BEFORE INSERT OR UPDATE ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_personas_congelar();

DROP TRIGGER IF EXISTS contactos_empresas_congelar ON public.contactos_empresas;
CREATE TRIGGER contactos_empresas_congelar
  BEFORE INSERT OR UPDATE ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_empresas_congelar();

-- ============================================================
-- 7. Eventos: el alta congelada nace al aprobarse
-- ============================================================
-- Como `sql/125`, más: un alta que entra congelada no emite; al aprobarse
-- emite como si naciera (alta y su estado). Rechazada, "es la misma" o
-- retirada por quien la cargó, no existió: no emite baja.
CREATE OR REPLACE FUNCTION public.emitir_eventos_registro()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ente     text    := TG_ARGV[0];
  v_dueno    text    := nullif(TG_ARGV[1], '');
  v_extras   text[]  := string_to_array(nullif(TG_ARGV[2], ''), ',');
  v_nueva    jsonb   := to_jsonb(NEW);
  v_vieja    jsonb   := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_activo   boolean := (v_nueva->>'activo')::boolean;
  v_estaba   boolean := (v_vieja->>'activo')::boolean;
  v_esperaba boolean := coalesce((v_vieja->>'congelada')::boolean, false) AND v_vieja->>'congelada_antes' IS NULL;
  v_detalle  jsonb;
  v_col      text;
BEGIN
  IF coalesce((v_nueva->>'congelada')::boolean, false) AND (TG_OP = 'INSERT' OR v_esperaba) THEN
    RETURN NULL;
  END IF;
  IF v_esperaba THEN
    IF NOT v_activo THEN
      RETURN NULL;
    END IF;
    v_vieja := NULL;
    v_estaba := NULL;
  END IF;

  IF v_vieja IS NULL THEN
    IF NOT v_activo THEN
      RETURN NULL;
    END IF;
    PERFORM emitir_evento(v_ente, NEW.id, 'alta');
  ELSIF v_activo AND NOT v_estaba THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'reactivacion');
  END IF;

  IF v_nueva ? 'estado' AND v_nueva->>'estado' IS DISTINCT FROM v_vieja->>'estado' THEN
    v_detalle := jsonb_build_object('estado', v_nueva->>'estado', 'anterior', v_vieja->>'estado');
    FOREACH v_col IN ARRAY coalesce(v_extras, '{}') LOOP
      IF v_nueva->>v_col IS NOT NULL THEN
        v_detalle := v_detalle || jsonb_build_object(v_col, v_nueva->v_col);
      END IF;
    END LOOP;
    PERFORM emitir_evento(v_ente, NEW.id, 'estado', v_detalle);
  END IF;

  IF v_vieja IS NOT NULL AND v_dueno IS NOT NULL AND v_nueva->>v_dueno IS DISTINCT FROM v_vieja->>v_dueno THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'transferencia',
      jsonb_build_object('de', v_vieja->>v_dueno, 'a', v_nueva->>v_dueno));
  END IF;

  IF v_estaba AND NOT v_activo THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'baja');
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS emitir_eventos ON public.obras;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado, responsable_id, congelada ON public.obras
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('obra', 'responsable_id', 'motivo_perdida,estado_nota');

DROP TRIGGER IF EXISTS emitir_eventos ON public.contactos_personas;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, responsable_id, congelada ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('persona', 'responsable_id');

DROP TRIGGER IF EXISTS emitir_eventos ON public.contactos_empresas;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, congelada ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('empresa');

-- ============================================================
-- 8. "Alta por aprobar" — a quienes tienen la función
-- ============================================================
-- TG_ARGV = (función que aprueba, entidad del aviso). Al congelarse, no en
-- cada edición mientras espera.
ALTER TABLE public.usuario_notificaciones
  DROP CONSTRAINT IF EXISTS usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones
  ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad IN ('equipos_miembros', 'usuario_submodulos', 'tareas', 'tareas_hilos', 'usuarios',
                     'obras', 'obras_participantes', 'contactos_personas', 'contactos_empresas'));

CREATE OR REPLACE FUNCTION public.avisar_por_aprobar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.congelada THEN
    RETURN NULL;
  END IF;
  PERFORM public.notificar(u.id, 'alta_por_aprobar', TG_ARGV[1], NEW.id, auth.uid())
  FROM public.usuarios u
  WHERE u.activo AND public.usuario_tiene_permiso(u.id, TG_ARGV[0]);
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.avisar_por_aprobar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS avisar_por_aprobar ON public.obras;
CREATE TRIGGER avisar_por_aprobar
  AFTER INSERT OR UPDATE OF congelada ON public.obras
  FOR EACH ROW WHEN (NEW.congelada)
  EXECUTE FUNCTION public.avisar_por_aprobar('obras_aprobar', 'obras');

DROP TRIGGER IF EXISTS avisar_por_aprobar ON public.contactos_personas;
CREATE TRIGGER avisar_por_aprobar
  AFTER INSERT OR UPDATE OF congelada ON public.contactos_personas
  FOR EACH ROW WHEN (NEW.congelada)
  EXECUTE FUNCTION public.avisar_por_aprobar('contactos_aprobar', 'contactos_personas');

DROP TRIGGER IF EXISTS avisar_por_aprobar ON public.contactos_empresas;
CREATE TRIGGER avisar_por_aprobar
  AFTER INSERT OR UPDATE OF congelada ON public.contactos_empresas
  FOR EACH ROW WHEN (NEW.congelada)
  EXECUTE FUNCTION public.avisar_por_aprobar('contactos_aprobar', 'contactos_empresas');

-- ============================================================
-- 9. Aviso a ciegas, antes de guardar
-- ============================================================
-- De lo que no ve, solo el nombre y el responsable. Lo que ve trae el id y la
-- dirección, para abrirla. `p_obra` excluye la propia al editar.
CREATE OR REPLACE FUNCTION public.obras_parecidas(p_nombre text, p_direccion text, p_obra uuid DEFAULT NULL)
RETURNS TABLE (id uuid, nombre text, direccion text, responsable text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN x.ve THEN o.id END, o.nombre, CASE WHEN x.ve THEN o.direccion END, u.nombre
  FROM public.obras_parecidas_de(p_obra, p_nombre, p_direccion) p
  JOIN public.obras o    ON o.id = p.id
  JOIN public.usuarios u ON u.id = o.responsable_id
  CROSS JOIN LATERAL (
    SELECT public.obras_puede_ver_obra_de(o.id, o.responsable_id, o.equipo_id, o.activo, auth.uid()) AS ve
  ) x
  WHERE public.tiene_permiso('obras_ver')
  ORDER BY x.ve DESC, o.nombre
  LIMIT 10;
$$;

-- Si es tuya (la persona, de tu agenda; la empresa, de tu equipo), entera: id
-- para "Vincular esa" y qué coincidió. De otro, nombre, dueño y, de una
-- empresa, su equipo, así se la pide a ese equipo.
CREATE OR REPLACE FUNCTION public.contactos_parecidas(
  p_tipo text, p_nombre text, p_telefono text DEFAULT NULL, p_email text DEFAULT NULL, p_id uuid DEFAULT NULL
)
RETURNS TABLE (id uuid, nombre text, dueno text, equipo text, coincide text[])
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN c.tuya AND NOT c.congelada THEN c.id END, c.nombre, u.nombre, c.equipo,
         CASE WHEN c.tuya THEN c.coincide END
  FROM (
    SELECT p.id, p.nombre, p.responsable_id AS dueno_id, NULL::text AS equipo, x.coincide, p.congelada,
           p.responsable_id = auth.uid() AS tuya
    FROM public.contactos_personas_parecidas_de(p_id, p_nombre, p_telefono, p_email) x
    JOIN public.contactos_personas p ON p.id = x.id
    WHERE p_tipo = 'persona'
    UNION ALL
    SELECT e.id, e.nombre, e.creado_por, q.nombre, '{nombre}'::text[], e.congelada,
           e.equipo_id = public.equipo_de(auth.uid()) OR (e.equipo_id IS NULL AND e.creado_por = auth.uid())
    FROM public.contactos_empresas_parecidas_de(p_id, p_nombre) x
    JOIN public.contactos_empresas e ON e.id = x.id
    LEFT JOIN public.equipos q       ON q.id = e.equipo_id
    WHERE p_tipo = 'empresa'
  ) c
  JOIN public.usuarios u ON u.id = c.dueno_id
  WHERE public.tiene_permiso('contactos_ver')
  ORDER BY c.tuya DESC, c.nombre
  LIMIT 10;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_parecidas(text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_parecidas(text, text, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_parecidas(text, text, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_parecidas(text, text, text, text, uuid) TO authenticated;

-- ============================================================
-- 10. contactos_vinculables — sin las congeladas
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_vinculables(p_texto text)
RETURNS TABLE (tipo text, id uuid, nombre text, detalle text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(btrim(p_texto)) AS t
    WHERE length(btrim(p_texto)) >= 2
  ),
  encontrados AS (
    SELECT 'persona'::text AS tipo, p.id, p.nombre,
           (SELECT e.nombre
            FROM public.contactos_persona_empresa pe
            JOIN public.contactos_empresas e ON e.id = pe.empresa_id
            WHERE pe.persona_id = p.id AND pe.activo AND pe.hasta IS NULL
            ORDER BY pe.desde DESC
            LIMIT 1) AS detalle,
           strpos(lower(p.nombre), q.t) AS pos
    FROM q
    JOIN public.contactos_personas p
      ON p.activo AND NOT p.congelada AND p.responsable_id = (select auth.uid()) AND strpos(lower(p.nombre), q.t) > 0
    UNION ALL
    SELECT 'empresa', e.id, e.nombre, NULL, strpos(lower(e.nombre), q.t)
    FROM q
    JOIN public.contactos_empresas e
      ON e.activo AND NOT e.congelada
     AND (e.equipo_id = public.mi_equipo() OR (e.equipo_id IS NULL AND e.creado_por = (select auth.uid())))
     AND strpos(lower(e.nombre), q.t) > 0
  )
  SELECT tipo, id, nombre, detalle
  FROM encontrados
  ORDER BY pos <> 1, nombre
  LIMIT 15;
$$;
