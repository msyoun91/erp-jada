-- ============================================================
-- 027 — Agenda de Obras (Fase 1) — schema, RLS y permisos
--
-- Módulo `obras`. Nombre visible: "Agenda de Obras".
-- Entidad central: obra. Empresas y personas son entidades propias,
-- relacionadas con la obra por tablas puente con roles múltiples.
--
-- Las funciones de negocio (transferir, desactivar, detección difusa de
-- duplicados, ficha de persona con registro de acceso) van en `sql/028`.
--
-- DECISIONES QUE ESTE ARCHIVO IMPLEMENTA (ver decisiones/obras.md):
--
-- 1. Ser referente NO es un rol de `rol_persona`: es la existencia de una fila
--    en `obras_obra_referente`. Una sola fuente de verdad.
-- 2. La obra es privada de su responsable. La ve él y quien tenga
--    `obras_transferir` (que necesita verlas todas para poder reasignarlas).
-- 3. Las personas son el activo sensible del módulo (celular directo del que
--    decide la compra). No son globales: cada uno ve las de sus obras, las que
--    cargó, y nada más. `obras_personas_todas` levanta ese límite.
-- 4. Las empresas SÍ son globales: razón social y web son datos casi públicos,
--    y compartirlas es lo que evita que cada vendedor cargue su propia copia de
--    la misma constructora.
-- 5. Sin campo `cuit`.
-- ============================================================

-- ============================================================
-- 0. Extensiones — búsqueda difusa de duplicados
-- ============================================================
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

-- Normaliza para comparar: sin acentos, minúsculas, sin espacios de más.
-- "XYZ S.A." y "xyz sa" tienen que colisionar en la detección de duplicados.
CREATE OR REPLACE FUNCTION public.obras_normalizar(t text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT nullif(
    btrim(regexp_replace(
      lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(t, ''))),
      '[^a-z0-9]+', ' ', 'g'
    )),
    ''
  );
$$;

-- Teléfonos: solo dígitos. "11 4567-8900" y "+54 11 4567 8900" no son el mismo
-- string pero sí el mismo teléfono, y comparar por string no sirve.
CREATE OR REPLACE FUNCTION public.obras_normalizar_telefono(t text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT nullif(regexp_replace(coalesce(t, ''), '[^0-9]', '', 'g'), '');
$$;

-- Usada por los CHECK de los arrays de roles.
CREATE OR REPLACE FUNCTION public.obras_array_sin_duplicados(a anyarray)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $$
  SELECT cardinality(a) = (SELECT count(DISTINCT x) FROM unnest(a) AS x);
$$;

-- ============================================================
-- 1. Enums
-- ============================================================
DO $$ BEGIN
  CREATE TYPE estado_obra AS ENUM ('idea', 'en_construccion', 'perdida', 'terminada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE tipo_obra AS ENUM (
    'edificio', 'casa', 'refaccion', 'complejo_viviendas',
    'local', 'oficina', 'hotel', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE origen_obra AS ENUM (
    'arquitecto', 'inmobiliaria', 'constructora', 'desarrolladora',
    'referido', 'deteccion_propia', 'internet', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE motivo_perdida AS ENUM (
    'perdimos_licitacion', 'eligieron_otro_proveedor', 'precio',
    'especificacion_fuera_de_provision', 'obra_cancelada', 'sin_interes', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE rol_empresa AS ENUM (
    'constructora', 'desarrolladora', 'inmobiliaria',
    'estudio_arquitectura', 'direccion_obra', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Sin 'referente': eso vive en obras_obra_referente (decisión 1).
DO $$ BEGIN
  CREATE TYPE rol_persona AS ENUM (
    'arquitecto', 'desarrollador', 'inversor', 'director_obra', 'compras',
    'oficina_tecnica', 'decisor', 'influenciador', 'contacto_comercial', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Enum y no texto libre: el filtro por ubicación muere el primer día si
-- conviven "CABA", "Capital" y "C.A.B.A." como tres provincias distintas.
DO $$ BEGIN
  CREATE TYPE provincia AS ENUM (
    'caba', 'buenos_aires', 'catamarca', 'chaco', 'chubut', 'cordoba',
    'corrientes', 'entre_rios', 'formosa', 'jujuy', 'la_pampa', 'la_rioja',
    'mendoza', 'misiones', 'neuquen', 'rio_negro', 'salta', 'san_juan',
    'san_luis', 'santa_cruz', 'santa_fe', 'santiago_del_estero',
    'tierra_del_fuego', 'tucuman'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 2. obras — entidad central
--
-- `responsable_id` no es dato decorativo: define quién ve la obra (RLS más
-- abajo). Arranca en el creador y solo se mueve con `obras_transferir`.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre                 text NOT NULL CHECK (btrim(nombre) <> ''),
  tipo                   tipo_obra NOT NULL,
  estado                 estado_obra NOT NULL DEFAULT 'idea',
  direccion              text,
  localidad              text,
  provincia              provincia,
  cantidad_unidades      int CHECK (cantidad_unidades > 0),
  superficie_estimada    numeric(10,2) CHECK (superficie_estimada > 0),
  fecha_estimada_inicio  date,
  fecha_estimada_compra  date,
  origen                 origen_obra,
  observaciones          text,
  motivo_perdida         motivo_perdida,
  detalle_perdida        text,
  responsable_id         uuid NOT NULL REFERENCES usuarios(id),
  nombre_norm            text,
  direccion_norm         text,
  localidad_norm         text,
  activo                 boolean NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),

  -- Pasar a perdida exige motivo. Salir de perdida NO lo borra: el motivo es
  -- información histórica, por eso el CHECK va en una sola dirección.
  CONSTRAINT obras_perdida_con_motivo
    CHECK (estado <> 'perdida' OR motivo_perdida IS NOT NULL),

  -- 'otro' sin explicación no dice nada; los demás motivos se explican solos.
  CONSTRAINT obras_motivo_otro_con_detalle
    CHECK (
      motivo_perdida IS DISTINCT FROM 'otro'
      OR btrim(coalesce(detalle_perdida, '')) <> ''
    )
);

CREATE INDEX IF NOT EXISTS idx_obras_responsable ON obras (responsable_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_estado ON obras (estado) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_localidad_norm ON obras (localidad_norm) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_nombre_trgm
  ON obras USING gin (nombre_norm extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_obras_direccion_trgm
  ON obras USING gin (direccion_norm extensions.gin_trgm_ops);

-- ============================================================
-- 3. obras_empresas — entidad Empresa
--
-- Una empresa no tiene rol global: el rol vive en su relación con cada obra.
-- La misma constructora puede ser desarrolladora en la obra de al lado.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_empresas (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  razon_social           text NOT NULL CHECK (btrim(razon_social) <> ''),
  nombre_comercial       text,
  website                text,
  telefono               text,
  email                  text,
  direccion              text,
  localidad              text,
  provincia              provincia,
  observaciones          text,
  creado_por             uuid NOT NULL REFERENCES usuarios(id),
  razon_social_norm      text,
  nombre_comercial_norm  text,
  activo                 boolean NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_obras_empresas_razon_trgm
  ON obras_empresas USING gin (razon_social_norm extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_obras_empresas_comercial_trgm
  ON obras_empresas USING gin (nombre_comercial_norm extensions.gin_trgm_ops);

-- ============================================================
-- 4. obras_personas — entidad Persona
--
-- Sin `empresa_id`: una persona puede trabajar en varias empresas y eso vive
-- en obras_persona_empresa. Sin columna de rol: el rol es por obra.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_personas (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          text NOT NULL CHECK (btrim(nombre) <> ''),
  apellido        text,
  telefono        text,
  whatsapp        text,
  email           text,
  observaciones   text,
  creado_por      uuid NOT NULL REFERENCES usuarios(id),
  nombre_norm     text,
  email_norm      text,
  telefono_norm   text,
  whatsapp_norm   text,
  activo          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_obras_personas_creado_por
  ON obras_personas (creado_por) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_personas_email
  ON obras_personas (email_norm) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_personas_telefono
  ON obras_personas (telefono_norm) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_personas_nombre_trgm
  ON obras_personas USING gin (nombre_norm extensions.gin_trgm_ops);

-- ============================================================
-- 5. obras_persona_empresa — persona ↔ empresa (cargo)
--
-- `cargo` es texto libre a propósito: "Jefe de compras zona sur" no entra en
-- ningún enum, y no se usa para filtrar ni para derivar roles de obra.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_persona_empresa (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id     uuid NOT NULL REFERENCES obras_personas(id),
  empresa_id     uuid NOT NULL REFERENCES obras_empresas(id),
  cargo          text,
  es_principal   boolean NOT NULL DEFAULT false,
  observaciones  text,
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_persona_empresa_unica
  ON obras_persona_empresa (persona_id, empresa_id) WHERE activo;

-- Como máximo una empresa principal por persona.
CREATE UNIQUE INDEX IF NOT EXISTS idx_persona_empresa_principal_unica
  ON obras_persona_empresa (persona_id) WHERE activo AND es_principal;

-- ============================================================
-- 6. obras_obra_empresa — obra ↔ empresa (roles múltiples)
--
-- Una sola fila por par, con array de roles. Dos filas para representar
-- "constructora + desarrolladora" sería duplicar la relación.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_obra_empresa (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id        uuid NOT NULL REFERENCES obras(id),
  empresa_id     uuid NOT NULL REFERENCES obras_empresas(id),
  roles          rol_empresa[] NOT NULL,
  observaciones  text,
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT obra_empresa_roles_no_vacio CHECK (cardinality(roles) > 0),
  CONSTRAINT obra_empresa_roles_sin_repetir CHECK (obras_array_sin_duplicados(roles))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_obra_empresa_unica
  ON obras_obra_empresa (obra_id, empresa_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obra_empresa_empresa
  ON obras_obra_empresa (empresa_id) WHERE activo;

-- ============================================================
-- 7. obras_obra_persona — obra ↔ persona (roles múltiples)
--
-- `empresa_id` es contexto: a quién representa esa persona en esta obra.
-- No se valida contra obras_persona_empresa ni contra obras_obra_empresa —
-- es informativo, no una invariante.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_obra_persona (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id        uuid NOT NULL REFERENCES obras(id),
  persona_id     uuid NOT NULL REFERENCES obras_personas(id),
  empresa_id     uuid REFERENCES obras_empresas(id),
  roles          rol_persona[] NOT NULL,
  observaciones  text,
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT obra_persona_roles_no_vacio CHECK (cardinality(roles) > 0),
  CONSTRAINT obra_persona_roles_sin_repetir CHECK (obras_array_sin_duplicados(roles))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_obra_persona_unica
  ON obras_obra_persona (obra_id, persona_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obra_persona_persona
  ON obras_obra_persona (persona_id) WHERE activo;

-- ============================================================
-- 8. obras_obra_referente — obra ↔ referente (comisión)
--
-- La comisión es de la relación, no de la persona: el mismo referente puede
-- tener 3.50% en una obra y 2.00% en otra.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_obra_referente (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id              uuid NOT NULL REFERENCES obras(id),
  persona_id           uuid NOT NULL REFERENCES obras_personas(id),
  porcentaje_comision  numeric(5,2) NOT NULL
    CHECK (porcentaje_comision >= 0 AND porcentaje_comision <= 100),
  observaciones        text,
  activo               boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_obra_referente_unica
  ON obras_obra_referente (obra_id, persona_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obra_referente_persona
  ON obras_obra_referente (persona_id) WHERE activo;

-- ============================================================
-- 9. obras_transferencias — log de cambios de responsable
--
-- Sin `activo`: es un log. La fila significa "esto pasó" y no tiene otro
-- estado que existir (mismo criterio que usuario_tutorial).
-- Ahora que el responsable decide quién ve la obra, "¿por qué no la veo más?"
-- necesita respuesta.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_transferencias (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id        uuid NOT NULL REFERENCES obras(id),
  de_usuario_id  uuid NOT NULL REFERENCES usuarios(id),
  a_usuario_id   uuid NOT NULL REFERENCES usuarios(id),
  ejecutada_por  uuid NOT NULL REFERENCES usuarios(id),
  created_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT transferencia_cambia_responsable CHECK (de_usuario_id <> a_usuario_id)
);

CREATE INDEX IF NOT EXISTS idx_obras_transferencias_obra
  ON obras_transferencias (obra_id);

-- ============================================================
-- 10. obras_accesos_persona — log de acceso a datos de contacto
--
-- Contra un insider autorizado no hay prevención: quien ve un teléfono en
-- pantalla lo puede fotografiar. Lo que sí se puede es dejar rastro. Esta
-- tabla convierte "se llevó la agenda" en una consulta que muestra 340 fichas
-- abiertas en dos días.
-- Sin `activo`: log, igual que obras_transferencias.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_accesos_persona (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES usuarios(id),
  persona_id  uuid NOT NULL REFERENCES obras_personas(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_obras_accesos_usuario_fecha
  ON obras_accesos_persona (usuario_id, created_at DESC);

-- ============================================================
-- 11. Triggers de normalización
--
-- Las columnas `_norm` no las escribe nadie desde la app: se derivan acá.
-- Columnas GENERATED no sirven porque unaccent() no es IMMUTABLE.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_normalizar_obra()
RETURNS TRIGGER AS $$
BEGIN
  NEW.nombre_norm    = obras_normalizar(NEW.nombre);
  NEW.direccion_norm = obras_normalizar(NEW.direccion);
  NEW.localidad_norm = obras_normalizar(NEW.localidad);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS normalizar ON obras;
CREATE TRIGGER normalizar
  BEFORE INSERT OR UPDATE ON obras
  FOR EACH ROW EXECUTE FUNCTION obras_normalizar_obra();

CREATE OR REPLACE FUNCTION obras_normalizar_empresa()
RETURNS TRIGGER AS $$
BEGIN
  NEW.razon_social_norm     = obras_normalizar(NEW.razon_social);
  NEW.nombre_comercial_norm = obras_normalizar(NEW.nombre_comercial);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS normalizar ON obras_empresas;
CREATE TRIGGER normalizar
  BEFORE INSERT OR UPDATE ON obras_empresas
  FOR EACH ROW EXECUTE FUNCTION obras_normalizar_empresa();

CREATE OR REPLACE FUNCTION obras_normalizar_persona()
RETURNS TRIGGER AS $$
BEGIN
  NEW.nombre_norm    = obras_normalizar(NEW.nombre || ' ' || coalesce(NEW.apellido, ''));
  NEW.email_norm     = nullif(lower(btrim(coalesce(NEW.email, ''))), '');
  NEW.telefono_norm  = obras_normalizar_telefono(NEW.telefono);
  NEW.whatsapp_norm  = obras_normalizar_telefono(NEW.whatsapp);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS normalizar ON obras_personas;
CREATE TRIGGER normalizar
  BEFORE INSERT OR UPDATE ON obras_personas
  FOR EACH ROW EXECUTE FUNCTION obras_normalizar_persona();

-- ============================================================
-- 12. Triggers updated_at
-- ============================================================
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'obras', 'obras_empresas', 'obras_personas', 'obras_persona_empresa',
    'obras_obra_empresa', 'obras_obra_persona', 'obras_obra_referente'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS set_updated_at ON %I', t);
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON %I
         FOR EACH ROW EXECUTE FUNCTION update_updated_at()', t
    );
  END LOOP;
END $$;

-- ============================================================
-- 13. Desactivar una entidad compartida no puede romper obras ajenas
--
-- Empresas y personas las ve más de un vendedor. Si A desactiva "ABC SA",
-- las obras de B se quedan sin constructora — y A ni siquiera puede ver el
-- daño, porque esas obras le son invisibles. El trigger corta eso.
-- El mensaje dice cuántas obras, nunca cuáles: mismo criterio que el aviso
-- ciego de duplicados.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_guard_desactivar_empresa()
RETURNS TRIGGER AS $$
DECLARE n int;
BEGIN
  -- Solo obras activas: una obra desactivada no se rompe por esto.
  SELECT count(DISTINCT v.obra_id) INTO n
  FROM (
    SELECT obra_id FROM obras_obra_empresa WHERE empresa_id = OLD.id AND activo
    UNION
    SELECT obra_id FROM obras_obra_persona WHERE empresa_id = OLD.id AND activo
  ) AS v
  JOIN obras o ON o.id = v.obra_id AND o.activo;

  IF n > 0 THEN
    RAISE EXCEPTION 'No se puede desactivar: la empresa participa en % obra(s). Desvinculala primero.', n;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS guard_desactivar ON obras_empresas;
CREATE TRIGGER guard_desactivar
  BEFORE UPDATE ON obras_empresas
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION obras_guard_desactivar_empresa();

CREATE OR REPLACE FUNCTION obras_guard_desactivar_persona()
RETURNS TRIGGER AS $$
DECLARE n int;
BEGIN
  SELECT count(DISTINCT v.obra_id) INTO n
  FROM (
    SELECT obra_id FROM obras_obra_persona WHERE persona_id = OLD.id AND activo
    UNION
    SELECT obra_id FROM obras_obra_referente WHERE persona_id = OLD.id AND activo
  ) AS v
  JOIN obras o ON o.id = v.obra_id AND o.activo;

  IF n > 0 THEN
    RAISE EXCEPTION 'No se puede desactivar: la persona participa en % obra(s). Desvinculala primero.', n;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS guard_desactivar ON obras_personas;
CREATE TRIGGER guard_desactivar
  BEFORE UPDATE ON obras_personas
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION obras_guard_desactivar_persona();

-- Sin obras de por medio, desactivar sí procede — y la relación persona↔empresa
-- se va con la entidad, para no dejar un cargo colgado de una empresa inactiva.
CREATE OR REPLACE FUNCTION obras_cascada_desactivar()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_TABLE_NAME = 'obras_empresas' THEN
    UPDATE obras_persona_empresa SET activo = false
    WHERE empresa_id = OLD.id AND activo;
  ELSE
    UPDATE obras_persona_empresa SET activo = false
    WHERE persona_id = OLD.id AND activo;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS cascada_desactivar ON obras_empresas;
CREATE TRIGGER cascada_desactivar
  AFTER UPDATE ON obras_empresas
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION obras_cascada_desactivar();

DROP TRIGGER IF EXISTS cascada_desactivar ON obras_personas;
CREATE TRIGGER cascada_desactivar
  AFTER UPDATE ON obras_personas
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION obras_cascada_desactivar();

-- ============================================================
-- 14. Helpers de visibilidad
--
-- SECURITY DEFINER STABLE, no EXISTS directo en la policy: dos policies que se
-- miran entre sí dan 42P17 infinite recursion.
-- ============================================================

-- La obra es privada de su responsable. Quien transfiere las ve todas porque
-- no puede reasignar lo que no ve.
CREATE OR REPLACE FUNCTION obras_puede_ver_obra(p_obra_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras o
    WHERE o.id = p_obra_id
      AND (
        (o.responsable_id = auth.uid() AND public.tiene_permiso('obras_ver'))
        OR public.tiene_permiso('obras_transferir')
      )
  );
$$;

-- Ver ≠ editar: el que transfiere mira y reasigna, no toca los datos.
CREATE OR REPLACE FUNCTION obras_es_mi_obra(p_obra_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras o
    WHERE o.id = p_obra_id AND o.activo AND o.responsable_id = auth.uid()
  );
$$;

-- Las personas son el activo sensible del módulo: cada uno ve las de sus obras
-- y las que cargó. La agenda completa la ve solo `obras_personas_todas`.
CREATE OR REPLACE FUNCTION obras_puede_ver_persona(p_persona_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT (public.tiene_permiso('obras_ver') OR public.tiene_permiso('obras_personas'))
    AND (
      public.tiene_permiso('obras_personas_todas')
      OR EXISTS (
        SELECT 1 FROM public.obras_personas p
        WHERE p.id = p_persona_id AND p.creado_por = auth.uid()
      )
      OR EXISTS (
        SELECT 1 FROM public.obras_obra_persona op
        JOIN public.obras o ON o.id = op.obra_id
        WHERE op.persona_id = p_persona_id AND op.activo
          AND o.responsable_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1 FROM public.obras_obra_referente r
        JOIN public.obras o ON o.id = r.obra_id
        WHERE r.persona_id = p_persona_id AND r.activo
          AND o.responsable_id = auth.uid()
      )
    );
$$;

-- ============================================================
-- 15. RLS
-- ============================================================
ALTER TABLE obras                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_empresas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_personas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_persona_empresa  ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_obra_empresa     ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_obra_persona     ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_obra_referente   ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_transferencias   ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras_accesos_persona  ENABLE ROW LEVEL SECURITY;

-- --- obras ---------------------------------------------------
DROP POLICY IF EXISTS obras_select ON obras;
CREATE POLICY obras_select ON obras FOR SELECT
  USING (
    (responsable_id = auth.uid() AND tiene_permiso('obras_ver'))
    OR tiene_permiso('obras_transferir')
  );

DROP POLICY IF EXISTS obras_insert ON obras;
CREATE POLICY obras_insert ON obras FOR INSERT
  WITH CHECK (tiene_permiso('obras_crear') AND responsable_id = auth.uid());

-- Solo el responsable edita. El que transfiere ve todo y no toca nada: si hay
-- que corregir una obra ajena, se la transfiere primero. Una puerta, no dos.
DROP POLICY IF EXISTS obras_update ON obras;
CREATE POLICY obras_update ON obras FOR UPDATE
  USING (responsable_id = auth.uid() AND tiene_permiso('obras_editar'))
  WITH CHECK (responsable_id = auth.uid() AND tiene_permiso('obras_editar'));

-- --- obras_empresas ------------------------------------------
-- Compartidas: razón social y web son datos casi públicos, y compartirlas es
-- lo que evita que cada vendedor cargue su propia copia de la misma empresa.
DROP POLICY IF EXISTS obras_empresas_select ON obras_empresas;
CREATE POLICY obras_empresas_select ON obras_empresas FOR SELECT
  USING (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'));

DROP POLICY IF EXISTS obras_empresas_insert ON obras_empresas;
CREATE POLICY obras_empresas_insert ON obras_empresas FOR INSERT
  WITH CHECK (tiene_permiso('obras_empresas_crear') AND creado_por = auth.uid());

DROP POLICY IF EXISTS obras_empresas_update ON obras_empresas;
CREATE POLICY obras_empresas_update ON obras_empresas FOR UPDATE
  USING (tiene_permiso('obras_empresas_editar'))
  WITH CHECK (tiene_permiso('obras_empresas_editar'));

-- --- obras_personas ------------------------------------------
-- `creado_por` se prueba como columna y no vía obras_puede_ver_persona: esa
-- función relee la fila, y en un INSERT ... RETURNING (lo que hace
-- .insert().select() de Supabase) la fila nueva todavía no está en el snapshot
-- de una función STABLE — el creador no podía leer lo que acababa de escribir.
DROP POLICY IF EXISTS obras_personas_select ON obras_personas;
CREATE POLICY obras_personas_select ON obras_personas FOR SELECT
  USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
    AND (creado_por = auth.uid() OR obras_puede_ver_persona(id))
  );

DROP POLICY IF EXISTS obras_personas_insert ON obras_personas;
CREATE POLICY obras_personas_insert ON obras_personas FOR INSERT
  WITH CHECK (tiene_permiso('obras_personas_crear') AND creado_por = auth.uid());

DROP POLICY IF EXISTS obras_personas_update ON obras_personas;
CREATE POLICY obras_personas_update ON obras_personas FOR UPDATE
  USING (tiene_permiso('obras_personas_editar') AND obras_puede_ver_persona(id))
  WITH CHECK (tiene_permiso('obras_personas_editar') AND obras_puede_ver_persona(id));

-- --- obras_persona_empresa -----------------------------------
DROP POLICY IF EXISTS obras_persona_empresa_select ON obras_persona_empresa;
CREATE POLICY obras_persona_empresa_select ON obras_persona_empresa FOR SELECT
  USING (obras_puede_ver_persona(persona_id));

DROP POLICY IF EXISTS obras_persona_empresa_insert ON obras_persona_empresa;
CREATE POLICY obras_persona_empresa_insert ON obras_persona_empresa FOR INSERT
  WITH CHECK (tiene_permiso('obras_personas_empresas') AND obras_puede_ver_persona(persona_id));

DROP POLICY IF EXISTS obras_persona_empresa_update ON obras_persona_empresa;
CREATE POLICY obras_persona_empresa_update ON obras_persona_empresa FOR UPDATE
  USING (tiene_permiso('obras_personas_empresas') AND obras_puede_ver_persona(persona_id))
  WITH CHECK (tiene_permiso('obras_personas_empresas') AND obras_puede_ver_persona(persona_id));

-- --- obras_obra_empresa --------------------------------------
DROP POLICY IF EXISTS obras_obra_empresa_select ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_select ON obras_obra_empresa FOR SELECT
  USING (obras_puede_ver_obra(obra_id));

DROP POLICY IF EXISTS obras_obra_empresa_insert ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_insert ON obras_obra_empresa FOR INSERT
  WITH CHECK (tiene_permiso('obras_vincular') AND obras_es_mi_obra(obra_id));

DROP POLICY IF EXISTS obras_obra_empresa_update ON obras_obra_empresa;
CREATE POLICY obras_obra_empresa_update ON obras_obra_empresa FOR UPDATE
  USING (tiene_permiso('obras_vincular') AND obras_es_mi_obra(obra_id))
  WITH CHECK (tiene_permiso('obras_vincular') AND obras_es_mi_obra(obra_id));

-- --- obras_obra_persona --------------------------------------
DROP POLICY IF EXISTS obras_obra_persona_select ON obras_obra_persona;
CREATE POLICY obras_obra_persona_select ON obras_obra_persona FOR SELECT
  USING (obras_puede_ver_obra(obra_id));

DROP POLICY IF EXISTS obras_obra_persona_insert ON obras_obra_persona;
CREATE POLICY obras_obra_persona_insert ON obras_obra_persona FOR INSERT
  WITH CHECK (tiene_permiso('obras_vincular') AND obras_es_mi_obra(obra_id));

DROP POLICY IF EXISTS obras_obra_persona_update ON obras_obra_persona;
CREATE POLICY obras_obra_persona_update ON obras_obra_persona FOR UPDATE
  USING (tiene_permiso('obras_vincular') AND obras_es_mi_obra(obra_id))
  WITH CHECK (tiene_permiso('obras_vincular') AND obras_es_mi_obra(obra_id));

-- --- obras_obra_referente ------------------------------------
-- La fila contiene la comisión, así que verla ES ver la comisión: no hace
-- falta (ni se permite) un permiso por campo.
DROP POLICY IF EXISTS obras_obra_referente_select ON obras_obra_referente;
CREATE POLICY obras_obra_referente_select ON obras_obra_referente FOR SELECT
  USING (obras_puede_ver_obra(obra_id) AND tiene_permiso('obras_referentes'));

DROP POLICY IF EXISTS obras_obra_referente_insert ON obras_obra_referente;
CREATE POLICY obras_obra_referente_insert ON obras_obra_referente FOR INSERT
  WITH CHECK (tiene_permiso('obras_referentes') AND obras_es_mi_obra(obra_id));

DROP POLICY IF EXISTS obras_obra_referente_update ON obras_obra_referente;
CREATE POLICY obras_obra_referente_update ON obras_obra_referente FOR UPDATE
  USING (tiene_permiso('obras_referentes') AND obras_es_mi_obra(obra_id))
  WITH CHECK (tiene_permiso('obras_referentes') AND obras_es_mi_obra(obra_id));

-- --- logs ----------------------------------------------------
-- Solo lectura desde la app; los escribe la función que ejecuta la acción.
DROP POLICY IF EXISTS obras_transferencias_select ON obras_transferencias;
CREATE POLICY obras_transferencias_select ON obras_transferencias FOR SELECT
  USING (obras_puede_ver_obra(obra_id));

DROP POLICY IF EXISTS obras_accesos_persona_select ON obras_accesos_persona;
CREATE POLICY obras_accesos_persona_select ON obras_accesos_persona FOR SELECT
  USING (tiene_permiso('obras_personas_todas'));

-- ============================================================
-- 16. GRANTs
--
-- RLS no alcanza: sin GRANT la query falla con 42501 y el error no menciona
-- políticas. Las columnas que no se otorgan son las que solo puede mover una
-- función que verifica su propio permiso.
-- ============================================================
GRANT SELECT, INSERT ON public.obras TO authenticated;

-- Ni `activo` ni `responsable_id`: desactivar y transferir son permisos
-- distintos de editar, y van por función (sql/028).
GRANT UPDATE (
  nombre, tipo, estado, direccion, localidad, provincia, cantidad_unidades,
  superficie_estimada, fecha_estimada_inicio, fecha_estimada_compra, origen,
  observaciones, motivo_perdida, detalle_perdida
) ON public.obras TO authenticated;

GRANT SELECT, INSERT, UPDATE ON public.obras_empresas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obras_personas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obras_persona_empresa TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obras_obra_empresa TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obras_obra_persona TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obras_obra_referente TO authenticated;

-- Logs: se leen, no se escriben desde el cliente.
GRANT SELECT ON public.obras_transferencias TO authenticated;
GRANT SELECT ON public.obras_accesos_persona TO authenticated;

-- ============================================================
-- 17. usuarios_select — el que transfiere necesita el picker de destino
--
-- Se reescribe la policy entera: las cláusulas de perfil propio, usuarios_ver
-- y tareas son de otras migraciones y siguen vigentes.
-- ============================================================
DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT
  USING (
    id = auth.uid()
    OR tiene_permiso('usuarios_ver')
    OR tiene_permiso('tareas_lista')
    OR tiene_permiso('tareas_proyectos')
    OR tiene_permiso('obras_transferir')
  );

-- ============================================================
-- 18. Submódulos — 3 vistas, 12 funciones
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden) VALUES
  ('obras_ver',      'obras', 'vista', 'Obras',    1),
  ('obras_empresas', 'obras', 'vista', 'Empresas', 2),
  ('obras_personas', 'obras', 'vista', 'Personas', 3)
ON CONFLICT (codigo) WHERE activo DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden, vista_id)
SELECT f.codigo, 'obras', 'funcion', f.nombre, f.orden,
       (SELECT id FROM submodulos WHERE codigo = f.vista AND activo)
FROM (VALUES
  ('obras_crear',             'Crear obra',                  1, 'obras_ver'),
  ('obras_editar',            'Editar obra',                 2, 'obras_ver'),
  ('obras_vincular',          'Vincular empresas y personas',3, 'obras_ver'),
  ('obras_referentes',        'Referentes y comisión',       4, 'obras_ver'),
  ('obras_transferir',        'Transferir obra',             5, 'obras_ver'),
  ('obras_desactivar',        'Desactivar obra',             6, 'obras_ver'),
  ('obras_empresas_crear',    'Crear empresa',               1, 'obras_empresas'),
  ('obras_empresas_editar',   'Editar empresa',              2, 'obras_empresas'),
  ('obras_personas_crear',    'Crear persona',               1, 'obras_personas'),
  ('obras_personas_editar',   'Editar persona',              2, 'obras_personas'),
  ('obras_personas_empresas', 'Vincular persona a empresa',  3, 'obras_personas'),
  ('obras_personas_todas',    'Ver todas las personas',      4, 'obras_personas')
) AS f(codigo, nombre, orden, vista)
ON CONFLICT (codigo) WHERE activo DO NOTHING;
