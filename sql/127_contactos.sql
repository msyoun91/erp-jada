-- sql/127 — contactos, tramo 1: personas, empresas y sus vínculos.
--
-- Persona, empresa, persona ↔ empresa, vínculos con cualquier registro
-- (`contactos_vinculos`), historial de ediciones, "Ver contacto" que registra,
-- transferir y desactivar, permisos, y los entes `persona` y `empresa` con sus
-- ramas en las genéricas. Quedan para los tramos siguientes: bajas y
-- huérfanas, congelado y "Por aprobar", compartir empresa, razones sociales,
-- fusionar, Auditoría y campanitas. Ficha y decisiones:
-- `decisiones/contactos.md`. Verificado con `sql/tests/contactos_reglas.sql`.
--
-- Directo o sistema, como Obras (`sql/126`). Mensajes con clase `CO`.

-- ============================================================
-- 1. contactos_personas — ente `persona`
-- ============================================================
-- Teléfono y email son contacto: fuera del GRANT SELECT, se leen solo con
-- "Ver contacto" (sección 9). El teléfono se guarda solo con dígitos, como
-- `usuarios.telefono` (`sql/103`).
CREATE TABLE IF NOT EXISTS public.contactos_personas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre         text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 200),
  telefono       text CHECK (telefono ~ '^[0-9]{8,15}$'),
  email          text CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' AND length(email) <= 254),
  notas          text CHECK (length(notas) <= 5000),
  responsable_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  creado_por     uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contactos_personas_responsable
  ON public.contactos_personas (responsable_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.contactos_personas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.contactos_personas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2. contactos_empresas — ente `empresa`, del equipo de quien la carga
-- ============================================================
-- `equipo_id`: el de quien la carga, guardado. Sin equipo, es de quien la
-- cargó. El teléfono de una empresa no es sensible.
CREATE TABLE IF NOT EXISTS public.contactos_empresas (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre     text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 200),
  telefono   text CHECK (telefono ~ '^[0-9]{8,15}$'),
  email      text CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' AND length(email) <= 254),
  web        text CHECK (length(web) <= 300),
  notas      text CHECK (length(notas) <= 5000),
  creado_por uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  equipo_id  uuid REFERENCES public.equipos(id),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contactos_empresas_equipo ON public.contactos_empresas (equipo_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_contactos_empresas_creado_por ON public.contactos_empresas (creado_por) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.contactos_empresas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.contactos_empresas ENABLE ROW LEVEL SECURITY;

-- Teléfono solo con dígitos, email en minúsculas; vacío es NULL.
CREATE OR REPLACE FUNCTION public.contactos_normalizar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.nombre := btrim(NEW.nombre);
  NEW.telefono := public.normalizar_telefono(NEW.telefono);
  NEW.email := nullif(lower(btrim(NEW.email)), '');
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_normalizar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS contactos_normalizar ON public.contactos_personas;
CREATE TRIGGER contactos_normalizar
  BEFORE INSERT OR UPDATE OF nombre, telefono, email ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_normalizar();

DROP TRIGGER IF EXISTS contactos_normalizar ON public.contactos_empresas;
CREATE TRIGGER contactos_normalizar
  BEFORE INSERT OR UPDATE OF nombre, telefono, email ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_normalizar();

-- ============================================================
-- 3. contactos_persona_empresa y contactos_vinculos
-- ============================================================
-- Uno abierto por par (GUIDE_ENTES §2.6): los cerrados son historia y volver
-- es una fila nueva. `activo = false` es "cargado por error".
CREATE TABLE IF NOT EXISTS public.contactos_persona_empresa (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id uuid NOT NULL REFERENCES public.contactos_personas(id),
  empresa_id uuid NOT NULL REFERENCES public.contactos_empresas(id),
  cargo      text CHECK (length(btrim(cargo)) BETWEEN 1 AND 200),
  desde      date NOT NULL DEFAULT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,
  hasta      date,
  creado_por uuid DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contactos_persona_empresa_periodo CHECK (hasta IS NULL OR hasta >= desde)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_contactos_persona_empresa_abierta
  ON public.contactos_persona_empresa (persona_id, empresa_id) WHERE activo AND hasta IS NULL;
CREATE INDEX IF NOT EXISTS idx_contactos_persona_empresa_empresa
  ON public.contactos_persona_empresa (empresa_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.contactos_persona_empresa;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.contactos_persona_empresa
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.contactos_persona_empresa ENABLE ROW LEVEL SECURITY;

-- El contacto, en dos columnas con FK; el registro, `(ente, registro_id)`.
-- Los roles válidos los declara el ente (`entes.roles`).
CREATE TABLE IF NOT EXISTS public.contactos_vinculos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id  uuid REFERENCES public.contactos_personas(id),
  empresa_id  uuid REFERENCES public.contactos_empresas(id),
  ente        text NOT NULL REFERENCES public.entes(codigo),
  registro_id uuid NOT NULL,
  roles       text[] NOT NULL CHECK (cardinality(roles) > 0),
  desde       date NOT NULL DEFAULT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,
  hasta       date,
  creado_por  uuid DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contactos_vinculos_un_contacto CHECK (num_nonnulls(persona_id, empresa_id) = 1),
  CONSTRAINT contactos_vinculos_periodo CHECK (hasta IS NULL OR hasta >= desde)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_contactos_vinculos_persona_abierto
  ON public.contactos_vinculos (persona_id, ente, registro_id) WHERE activo AND hasta IS NULL AND persona_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_contactos_vinculos_empresa_abierto
  ON public.contactos_vinculos (empresa_id, ente, registro_id) WHERE activo AND hasta IS NULL AND empresa_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contactos_vinculos_registro
  ON public.contactos_vinculos (ente, registro_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.contactos_vinculos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.contactos_vinculos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.contactos_vinculos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. contactos_ediciones y contactos_accesos — logs
-- ============================================================
-- Sin `activo` ni `updated_at`, como `eventos`: nadie oculta ni reescribe.
-- Las ediciones las escribe un trigger (sección 8); los accesos, "Ver
-- contacto" (sección 9). Los accesos los lee solo Auditoría (tramo 4).
CREATE TABLE IF NOT EXISTS public.contactos_ediciones (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id uuid REFERENCES public.contactos_personas(id),
  empresa_id uuid REFERENCES public.contactos_empresas(id),
  campo      text NOT NULL,
  anterior   text,
  nuevo      text,
  actor_id   uuid REFERENCES public.usuarios(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT contactos_ediciones_un_contacto CHECK (num_nonnulls(persona_id, empresa_id) = 1)
);

CREATE INDEX IF NOT EXISTS idx_contactos_ediciones_persona
  ON public.contactos_ediciones (persona_id, created_at) WHERE persona_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contactos_ediciones_empresa
  ON public.contactos_ediciones (empresa_id, created_at) WHERE empresa_id IS NOT NULL;

ALTER TABLE public.contactos_ediciones ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.contactos_accesos (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id uuid NOT NULL REFERENCES public.contactos_personas(id),
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_contactos_accesos_persona ON public.contactos_accesos (persona_id, created_at);
CREATE INDEX IF NOT EXISTS idx_contactos_accesos_usuario ON public.contactos_accesos (usuario_id, created_at);

ALTER TABLE public.contactos_accesos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. Catálogo de permisos
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, delegable)
SELECT 'contactos_ver', 'contactos', 'vista', 'Ver', 1, true
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = 'contactos_ver' AND s.activo);

INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT 'contactos_administrar', 'contactos', 'funcion', 'Administrar', 1, v.id, false
FROM public.submodulos v
WHERE v.codigo = 'contactos_ver' AND v.activo
  AND NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = 'contactos_administrar' AND s.activo);

-- La declara Obras (`decisiones/obras.md`); va acá porque `contactos_ver`
-- nace en esta migración.
INSERT INTO public.submodulo_reglas (submodulo_id, otro_id, tipo)
SELECT a.id, b.id, 'requiere'
FROM public.submodulos a, public.submodulos b
WHERE a.codigo = 'obras_ver' AND a.activo
  AND b.codigo = 'contactos_ver' AND b.activo
  AND NOT EXISTS (
    SELECT 1 FROM public.submodulo_reglas x
    WHERE x.activo AND x.submodulo_id = a.id AND x.otro_id = b.id
  );

-- ============================================================
-- 6. Ver
-- ============================================================
-- Una persona la ven su dueño (activa), quien ve un registro al que está
-- vinculada (el vínculo activo; cerrado también, es historia) y
-- `contactos_administrar`. Una empresa, su equipo (o quien la cargó, si no
-- tiene), quien ve un registro vinculado y el admin. "Ve el registro" es
-- `puede_abrir_registro`: DEFINER, porque "Ver contacto" pregunta por
-- `auth.uid()` desde una función DEFINER. Reciben las columnas de la fila,
-- no el id (GUIDE_ENTES §2.3).
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
      )
    );
$$;

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
        (p_activo AND (p_equipo = public.equipo_de(p_usuario) OR (p_equipo IS NULL AND p_creado_por = p_usuario)))
        OR EXISTS (
          SELECT 1 FROM public.contactos_vinculos v
          WHERE v.empresa_id = p_empresa AND v.activo
            AND public.puede_abrir_registro(v.ente, v.registro_id, p_usuario)
        )
      )
    );
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_puede_ver_persona_de(uuid, uuid, boolean, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_puede_ver_empresa_de(uuid, uuid, uuid, boolean, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.contactos_puede_ver_persona(p_persona uuid, p_responsable uuid, p_activo boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.contactos_puede_ver_persona_de(p_persona, p_responsable, p_activo, auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.contactos_puede_ver_empresa(p_empresa uuid, p_equipo uuid, p_creado_por uuid, p_activo boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.contactos_puede_ver_empresa_de(p_empresa, p_equipo, p_creado_por, p_activo, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_puede_ver_persona(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_puede_ver_persona(uuid, uuid, boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_puede_ver_empresa(uuid, uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_puede_ver_empresa(uuid, uuid, uuid, boolean) TO authenticated;

-- ============================================================
-- 7. Escribir — quién, en triggers
-- ============================================================
-- Corrige una persona su dueño, el admin o quien trabaja un registro al que
-- está vinculada; una desactivada, solo el admin. Una empresa, su equipo (o
-- quien la cargó), el admin o quien trabaja un registro vinculado.
-- `trabaja_registro` responde por `auth.uid()` también desde un trigger
-- DEFINER.
CREATE OR REPLACE FUNCTION public.contactos_personas_al_crear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.activo := true;
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
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL THEN
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
  END IF;

  IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id
     AND NOT public.usuario_tiene_permiso(NEW.responsable_id, 'contactos_ver') THEN
    RAISE EXCEPTION 'Una persona se transfiere a alguien activo que ve Contactos' USING ERRCODE = 'CO005';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_empresas_al_crear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.activo := true;
  NEW.equipo_id := public.equipo_de(NEW.creado_por);
  RETURN NEW;
END;
$$;

-- Desactiva el jefe del equipo (su delegador) o, sin equipo, quien la cargó;
-- el equipo lo cambia solo el admin.
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
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL THEN
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
      CASE WHEN OLD.equipo_id IS NULL THEN OLD.creado_por = v_uid
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

-- Suma la empresa de una persona su dueño (o el admin), con una empresa que
-- ve. Un período cerrado no se reabre ni se cambia.
CREATE OR REPLACE FUNCTION public.contactos_persona_empresa_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
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
     AND NOT public.usuario_tiene_permiso(v_uid, 'contactos_administrar') THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND responsable_id = v_uid
    ) THEN
      RAISE EXCEPTION 'La empresa de una persona la maneja su dueño' USING ERRCODE = 'CO012';
    END IF;
    IF TG_OP = 'INSERT' AND NOT EXISTS (
      SELECT 1 FROM public.contactos_empresas e
      WHERE e.id = NEW.empresa_id
        AND public.contactos_puede_ver_empresa_de(e.id, e.equipo_id, e.creado_por, e.activo, v_uid)
    ) THEN
      RAISE EXCEPTION 'Esa empresa no existe o no la ves' USING ERRCODE = 'CO013';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Vincula, sobre un registro que trabaja, el dueño de la persona o el equipo
-- de la empresa (y el admin de Contactos); cierra, cambia el rol o desactiva
-- quien trabaja el registro. Los roles, sin repetir y del ente.
CREATE OR REPLACE FUNCTION public.contactos_vinculos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
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
    IF NOT public.trabaja_registro(NEW.ente, NEW.registro_id) THEN
      RAISE EXCEPTION 'Vinculan y cambian contactos quienes trabajan el registro' USING ERRCODE = 'CO015';
    END IF;

    IF TG_OP = 'INSERT' AND NOT public.usuario_tiene_permiso(v_uid, 'contactos_administrar') AND NOT (
      EXISTS (SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND responsable_id = v_uid)
      OR EXISTS (
        SELECT 1 FROM public.contactos_empresas
        WHERE id = NEW.empresa_id
          AND (equipo_id = public.equipo_de(v_uid) OR (equipo_id IS NULL AND creado_por = v_uid))
      )
    ) THEN
      RAISE EXCEPTION 'Vincula una persona su dueño, y una empresa su equipo' USING ERRCODE = 'CO016';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_personas_al_crear() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_personas_al_editar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_empresas_al_crear() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_empresas_al_editar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_persona_empresa_validar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_vinculos_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS contactos_personas_al_crear ON public.contactos_personas;
CREATE TRIGGER contactos_personas_al_crear
  BEFORE INSERT ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_personas_al_crear();

DROP TRIGGER IF EXISTS contactos_personas_al_editar ON public.contactos_personas;
CREATE TRIGGER contactos_personas_al_editar
  BEFORE UPDATE ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_personas_al_editar();

DROP TRIGGER IF EXISTS contactos_empresas_al_crear ON public.contactos_empresas;
CREATE TRIGGER contactos_empresas_al_crear
  BEFORE INSERT ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_empresas_al_crear();

DROP TRIGGER IF EXISTS contactos_empresas_al_editar ON public.contactos_empresas;
CREATE TRIGGER contactos_empresas_al_editar
  BEFORE UPDATE ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_empresas_al_editar();

DROP TRIGGER IF EXISTS contactos_persona_empresa_validar ON public.contactos_persona_empresa;
CREATE TRIGGER contactos_persona_empresa_validar
  BEFORE INSERT OR UPDATE ON public.contactos_persona_empresa
  FOR EACH ROW EXECUTE FUNCTION public.contactos_persona_empresa_validar();

DROP TRIGGER IF EXISTS contactos_vinculos_validar ON public.contactos_vinculos;
CREATE TRIGGER contactos_vinculos_validar
  BEFORE INSERT OR UPDATE ON public.contactos_vinculos
  FOR EACH ROW EXECUTE FUNCTION public.contactos_vinculos_validar();

-- ============================================================
-- 8. contactos_ediciones — el valor anterior de lo que edita una persona
-- ============================================================
-- TG_ARGV = las columnas de contenido. Lo que corre en cascada no es una
-- edición.
CREATE OR REPLACE FUNCTION public.contactos_registrar_ediciones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viejo jsonb := to_jsonb(OLD);
  v_nuevo jsonb := to_jsonb(NEW);
  v_campo text;
BEGIN
  IF pg_trigger_depth() > 1 OR auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  FOREACH v_campo IN ARRAY TG_ARGV LOOP
    IF v_viejo -> v_campo IS DISTINCT FROM v_nuevo -> v_campo THEN
      INSERT INTO public.contactos_ediciones (persona_id, empresa_id, campo, anterior, nuevo, actor_id)
      VALUES (
        CASE WHEN TG_TABLE_NAME = 'contactos_personas' THEN NEW.id END,
        CASE WHEN TG_TABLE_NAME = 'contactos_empresas' THEN NEW.id END,
        v_campo, v_viejo ->> v_campo, v_nuevo ->> v_campo, auth.uid()
      );
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_registrar_ediciones() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS contactos_registrar_ediciones ON public.contactos_personas;
CREATE TRIGGER contactos_registrar_ediciones
  AFTER UPDATE OF nombre, telefono, email, notas ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_registrar_ediciones('nombre', 'telefono', 'email', 'notas');

DROP TRIGGER IF EXISTS contactos_registrar_ediciones ON public.contactos_empresas;
CREATE TRIGGER contactos_registrar_ediciones
  AFTER UPDATE OF nombre, telefono, email, web, notas ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_registrar_ediciones('nombre', 'telefono', 'email', 'web', 'notas');

-- ============================================================
-- 9. "Ver contacto" — teléfono y email de una persona, registrado
-- ============================================================
-- Quien ve la persona, y cada vez queda en `contactos_accesos`. El historial
-- de esos dos campos pasa por el mismo camino.
CREATE OR REPLACE FUNCTION public.contactos_registrar_acceso(p_persona uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.contactos_personas p
    WHERE p.id = p_persona
      AND public.contactos_puede_ver_persona_de(p.id, p.responsable_id, p.activo, auth.uid())
  ) THEN
    RAISE EXCEPTION 'Esa persona no existe o no la ves' USING ERRCODE = 'CO017';
  END IF;

  INSERT INTO public.contactos_accesos (persona_id, usuario_id) VALUES (p_persona, auth.uid());
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_registrar_acceso(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.contactos_ver_contacto(p_persona uuid)
RETURNS TABLE (telefono text, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.contactos_registrar_acceso(p_persona);
  RETURN QUERY SELECT p.telefono, p.email FROM public.contactos_personas p WHERE p.id = p_persona;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_historial_contacto(p_persona uuid)
RETURNS TABLE (campo text, anterior text, nuevo text, actor_id uuid, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.contactos_registrar_acceso(p_persona);
  RETURN QUERY
    SELECT e.campo, e.anterior, e.nuevo, e.actor_id, e.created_at
    FROM public.contactos_ediciones e
    WHERE e.persona_id = p_persona AND e.campo IN ('telefono', 'email')
    ORDER BY e.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_ver_contacto(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_ver_contacto(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_historial_contacto(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_historial_contacto(uuid) TO authenticated;

-- ============================================================
-- 10. Policies y GRANT
-- ============================================================
DROP POLICY IF EXISTS contactos_personas_select ON public.contactos_personas;
CREATE POLICY contactos_personas_select ON public.contactos_personas FOR SELECT TO authenticated
  USING (contactos_puede_ver_persona(id, responsable_id, activo));

DROP POLICY IF EXISTS contactos_personas_insert ON public.contactos_personas;
CREATE POLICY contactos_personas_insert ON public.contactos_personas FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('contactos_ver'));

DROP POLICY IF EXISTS contactos_personas_update ON public.contactos_personas;
CREATE POLICY contactos_personas_update ON public.contactos_personas FOR UPDATE TO authenticated
  USING (contactos_puede_ver_persona(id, responsable_id, activo))
  WITH CHECK (true);

DROP POLICY IF EXISTS contactos_empresas_select ON public.contactos_empresas;
CREATE POLICY contactos_empresas_select ON public.contactos_empresas FOR SELECT TO authenticated
  USING (contactos_puede_ver_empresa(id, equipo_id, creado_por, activo));

DROP POLICY IF EXISTS contactos_empresas_insert ON public.contactos_empresas;
CREATE POLICY contactos_empresas_insert ON public.contactos_empresas FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('contactos_ver'));

DROP POLICY IF EXISTS contactos_empresas_update ON public.contactos_empresas;
CREATE POLICY contactos_empresas_update ON public.contactos_empresas FOR UPDATE TO authenticated
  USING (contactos_puede_ver_empresa(id, equipo_id, creado_por, activo))
  WITH CHECK (true);

-- Se ve con la persona; la empresa aparece solo si se la ve (su propia RLS).
DROP POLICY IF EXISTS contactos_persona_empresa_select ON public.contactos_persona_empresa;
CREATE POLICY contactos_persona_empresa_select ON public.contactos_persona_empresa FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.contactos_personas p WHERE p.id = persona_id)
    AND (activo OR tiene_permiso('contactos_administrar'))
  );

DROP POLICY IF EXISTS contactos_persona_empresa_insert ON public.contactos_persona_empresa;
CREATE POLICY contactos_persona_empresa_insert ON public.contactos_persona_empresa FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.contactos_personas p WHERE p.id = persona_id));

DROP POLICY IF EXISTS contactos_persona_empresa_update ON public.contactos_persona_empresa;
CREATE POLICY contactos_persona_empresa_update ON public.contactos_persona_empresa FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.contactos_personas p WHERE p.id = persona_id))
  WITH CHECK (true);

-- Se ve si se ve el registro; el cargado por error, solo el admin.
DROP POLICY IF EXISTS contactos_vinculos_select ON public.contactos_vinculos;
CREATE POLICY contactos_vinculos_select ON public.contactos_vinculos FOR SELECT TO authenticated
  USING (
    etiqueta_registro(ente, registro_id) IS NOT NULL
    AND (activo OR tiene_permiso('contactos_administrar'))
  );

DROP POLICY IF EXISTS contactos_vinculos_insert ON public.contactos_vinculos;
CREATE POLICY contactos_vinculos_insert ON public.contactos_vinculos FOR INSERT TO authenticated
  WITH CHECK (etiqueta_registro(ente, registro_id) IS NOT NULL);

DROP POLICY IF EXISTS contactos_vinculos_update ON public.contactos_vinculos;
CREATE POLICY contactos_vinculos_update ON public.contactos_vinculos FOR UPDATE TO authenticated
  USING (etiqueta_registro(ente, registro_id) IS NOT NULL AND activo)
  WITH CHECK (true);

-- Con el registro que se ve; teléfono y email, solo por "Ver contacto".
DROP POLICY IF EXISTS contactos_ediciones_select ON public.contactos_ediciones;
CREATE POLICY contactos_ediciones_select ON public.contactos_ediciones FOR SELECT TO authenticated
  USING (
    CASE
      WHEN persona_id IS NOT NULL THEN
        campo NOT IN ('telefono', 'email')
        AND EXISTS (SELECT 1 FROM public.contactos_personas p WHERE p.id = persona_id)
      ELSE EXISTS (SELECT 1 FROM public.contactos_empresas e WHERE e.id = empresa_id)
    END
  );

GRANT SELECT (id, nombre, notas, responsable_id, creado_por, activo, created_at, updated_at)
  ON public.contactos_personas TO authenticated;
GRANT INSERT (id, nombre, telefono, email, notas) ON public.contactos_personas TO authenticated;
GRANT UPDATE (nombre, telefono, email, notas, activo) ON public.contactos_personas TO authenticated;

GRANT SELECT ON public.contactos_empresas TO authenticated;
GRANT INSERT (id, nombre, telefono, email, web, notas) ON public.contactos_empresas TO authenticated;
GRANT UPDATE (nombre, telefono, email, web, notas, activo, equipo_id) ON public.contactos_empresas TO authenticated;

GRANT SELECT ON public.contactos_persona_empresa TO authenticated;
GRANT INSERT (id, persona_id, empresa_id, cargo, desde) ON public.contactos_persona_empresa TO authenticated;
GRANT UPDATE (cargo, hasta, activo) ON public.contactos_persona_empresa TO authenticated;

GRANT SELECT ON public.contactos_vinculos TO authenticated;
GRANT INSERT (id, persona_id, empresa_id, ente, registro_id, roles, desde) ON public.contactos_vinculos TO authenticated;
GRANT UPDATE (roles, hasta, activo) ON public.contactos_vinculos TO authenticated;

GRANT SELECT ON public.contactos_ediciones TO authenticated;

-- ============================================================
-- 11. Transferir y desactivar — DEFINER, las reglas son los triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_transferir_persona(p_persona uuid, p_responsable uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.contactos_personas SET responsable_id = p_responsable WHERE id = p_persona AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa persona no existe o está desactivada' USING ERRCODE = 'CO018';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_desactivar_persona(p_persona uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.contactos_personas SET activo = false WHERE id = p_persona AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa persona no existe o está desactivada' USING ERRCODE = 'CO018';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_desactivar_empresa(p_empresa uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.contactos_empresas SET activo = false WHERE id = p_empresa AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa empresa no existe o está desactivada' USING ERRCODE = 'CO018';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_transferir_persona(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_transferir_persona(uuid, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_desactivar_persona(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_desactivar_persona(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_desactivar_empresa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_desactivar_empresa(uuid) TO authenticated;

-- ============================================================
-- 12. Entes `persona` y `empresa`, eventos y ramas
-- ============================================================
-- Emiten alta, baja, reactivación y (la persona) transferencia; no disparan.
INSERT INTO public.entes (codigo, modulo, submodulo, estados, datos, roles, ruta, tabla, disparos)
VALUES
  ('persona', 'contactos', 'contactos_ver', NULL, '{nombre}', '{}', '/contactos/personas/{id}',
   'public.contactos_personas', '{}'),
  ('empresa', 'contactos', 'contactos_ver', NULL, '{nombre}', '{}', '/contactos/empresas/{id}',
   'public.contactos_empresas', '{}')
ON CONFLICT (codigo) DO NOTHING;

DROP TRIGGER IF EXISTS emitir_eventos ON public.contactos_personas;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, responsable_id ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('persona', 'responsable_id');

DROP TRIGGER IF EXISTS emitir_eventos ON public.contactos_empresas;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('empresa');

-- Del lado del registro: "la obra suma una arquitecta". Uno por columna del
-- contacto, así el ente relacionado es fijo; el del registro sale de `ente`.
DROP TRIGGER IF EXISTS emitir_eventos_persona ON public.contactos_vinculos;
CREATE TRIGGER emitir_eventos_persona
  AFTER INSERT OR UPDATE OF activo, roles, hasta ON public.contactos_vinculos
  FOR EACH ROW WHEN (NEW.persona_id IS NOT NULL)
  EXECUTE FUNCTION emitir_eventos_relacion('ente', 'registro_id', 'persona', 'persona_id');

DROP TRIGGER IF EXISTS emitir_eventos_empresa ON public.contactos_vinculos;
CREATE TRIGGER emitir_eventos_empresa
  AFTER INSERT OR UPDATE OF activo, roles, hasta ON public.contactos_vinculos
  FOR EACH ROW WHEN (NEW.empresa_id IS NOT NULL)
  EXECUTE FUNCTION emitir_eventos_relacion('ente', 'registro_id', 'empresa', 'empresa_id');

CREATE OR REPLACE FUNCTION public.contactos_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'persona' THEN (SELECT nombre FROM public.contactos_personas WHERE id = p_id)
    WHEN 'empresa' THEN (SELECT nombre FROM public.contactos_empresas WHERE id = p_id)
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_etiqueta(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_etiqueta(text, uuid) TO authenticated;

-- Lo que se ve, activo, cuyo nombre contiene el texto.
CREATE OR REPLACE FUNCTION public.contactos_buscar(p_texto text)
RETURNS TABLE (tipo text, id uuid, titulo text, subtitulo text)
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
    SELECT 'persona'::text AS tipo, p.id, p.nombre, strpos(lower(p.nombre), q.t) AS pos
    FROM q JOIN public.contactos_personas p ON p.activo AND strpos(lower(p.nombre), q.t) > 0
    UNION ALL
    SELECT 'empresa', e.id, e.nombre, strpos(lower(e.nombre), q.t)
    FROM q JOIN public.contactos_empresas e ON e.activo AND strpos(lower(e.nombre), q.t) > 0
  )
  SELECT tipo, id, nombre, NULL::text
  FROM encontrados
  ORDER BY pos <> 1, nombre
  LIMIT 15;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_buscar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_buscar(text) TO authenticated;

-- Un evento de relación con un contacto lo ve quien ve algún vínculo del par
-- (la RLS de `contactos_vinculos` decide).
CREATE OR REPLACE FUNCTION public.contactos_puede_ver_relacion(p_ente text, p_id uuid, p_contacto uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.contactos_vinculos v
    WHERE v.ente = p_ente AND v.registro_id = p_id AND p_contacto IN (v.persona_id, v.empresa_id)
  );
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_puede_ver_relacion(text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_puede_ver_relacion(text, uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.etiqueta_registro(p_ente text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE e.modulo
    WHEN 'tareas'    THEN public.tareas_etiqueta(p_ente, p_id)
    WHEN 'obras'     THEN public.obras_etiqueta(p_ente, p_id)
    WHEN 'contactos' THEN public.contactos_etiqueta(p_ente, p_id)
  END
  FROM public.entes e
  WHERE e.codigo = p_ente;
$$;

-- "Lo ve", por usuario explícito. Sin GRANT: la llaman funciones DEFINER.
CREATE OR REPLACE FUNCTION public.contactos_puede_abrir(p_tipo text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'persona' THEN (
      SELECT public.contactos_puede_ver_persona_de(p.id, p.responsable_id, p.activo, p_usuario)
      FROM public.contactos_personas p WHERE p.id = p_id
    )
    WHEN 'empresa' THEN (
      SELECT public.contactos_puede_ver_empresa_de(x.id, x.equipo_id, x.creado_por, x.activo, p_usuario)
      FROM public.contactos_empresas x WHERE x.id = p_id
    )
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_puede_abrir(text, uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'obras'     THEN public.obras_puede_abrir(p_ente, p_id, p_usuario)
      WHEN 'contactos' THEN public.contactos_puede_abrir(p_ente, p_id, p_usuario)
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), false);
$$;

-- La relación con un contacto la contesta Contactos, que es dueño de la
-- puente, sea cual sea el módulo del registro.
CREATE OR REPLACE FUNCTION public.puede_ver_relacion(p_ente text, p_id uuid, p_ente_rel text, p_id_rel uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE
      WHEN r.modulo = 'contactos' THEN public.contactos_puede_ver_relacion(p_ente, p_id, p_id_rel)
      WHEN e.modulo = 'tareas'    THEN public.tareas_etiqueta(p_ente, p_id) IS NOT NULL
    END
    FROM public.entes e
    LEFT JOIN public.entes r ON r.codigo = p_ente_rel
    WHERE e.codigo = p_ente
  ), false);
$$;

CREATE OR REPLACE FUNCTION public.buscar_registros(p_modulo text, p_texto text)
RETURNS TABLE (ente text, registro_id uuid, etiqueta text, detalle text, href text)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_modulo = 'tareas' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.tareas_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  ELSIF p_modulo = 'obras' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.obras_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  ELSIF p_modulo = 'contactos' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.contactos_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  END IF;
END;
$$;
