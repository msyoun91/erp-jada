-- Módulo comercial — Fase 1: red comercial (empresas, personas, obras y sus
-- relaciones) + la lectura comercial de una obra (prospecto).
-- Sin tareas, actividades ni automatizaciones: esta fase captura y relaciona
-- información, no gestiona seguimiento. Ver HANDOFF_COMERCIAL_FASE1.md.
-- Correr en Supabase SQL Editor. Idempotente donde es posible.

-- ============================================================
-- Enums
-- ============================================================
DO $$
BEGIN
  CREATE TYPE tipo_obra AS ENUM (
    'edificio_residencial', 'edificio_comercial', 'vivienda',
    'oficinas', 'local', 'desarrollo_mixto', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE estado_obra AS ENUM (
    'idea', 'proyecto', 'pozo', 'inicio_obra',
    'construccion', 'terminaciones', 'finalizada', 'desconocido'
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE estado_prospecto AS ENUM (
    'nuevo', 'investigando', 'contactado', 'en_seguimiento',
    'interes_confirmado', 'cotizacion_solicitada', 'cotizado',
    'negociacion', 'ganado', 'perdido', 'sin_oportunidad'
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE rol_empresa AS ENUM (
    'desarrolladora', 'constructora', 'inmobiliaria',
    'estudio_arquitectura', 'inversor', 'proveedor', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- 'referente' no está acá a propósito: es la columna obra_persona.es_referente,
-- la que lleva el unique parcial por obra. Tenerlo en los dos lados sería
-- doble fuente de verdad para el mismo hecho.
DO $$
BEGIN
  CREATE TYPE rol_persona AS ENUM (
    'arquitecto', 'desarrollador', 'inversor', 'director', 'compras',
    'oficina_tecnica', 'decisor', 'influenciador', 'contacto_comercial', 'otro'
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE moneda AS ENUM ('ARS', 'USD');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- ============================================================
-- empresas — sin prefijo de módulo: Clientes y Presupuestos las van a usar.
-- El "tipo" de empresa no es un atributo global (una misma empresa es
-- desarrolladora en una obra y constructora en otra) — vive en obra_empresa.
-- ============================================================
CREATE TABLE IF NOT EXISTS empresas (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  razon_social     text NOT NULL,
  nombre_comercial text,
  cuit             text CHECK (cuit IS NULL OR cuit ~ '^[0-9]{11}$'),
  website          text,
  telefono         text,
  email            text,
  direccion        text,
  localidad        text,
  provincia        text,
  observaciones    text,
  creado_por       uuid NOT NULL REFERENCES usuarios(id),
  activo           boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_empresas_cuit_activo
  ON empresas (cuit) WHERE activo AND cuit IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_empresas_creado_por ON empresas (creado_por);

DROP TRIGGER IF EXISTS set_updated_at ON empresas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON empresas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- personas — empresa_principal_id es un dato de ficha, no la autoridad sobre
-- con qué empresa participa en una obra puntual (eso es obra_persona.empresa_id).
-- ============================================================
CREATE TABLE IF NOT EXISTS personas (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre               text NOT NULL,
  apellido             text,
  telefono             text,
  whatsapp             text,
  email                text,
  cargo                text,
  empresa_principal_id uuid REFERENCES empresas(id),
  observaciones        text,
  creado_por           uuid NOT NULL REFERENCES usuarios(id),
  activo               boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_personas_email_activo
  ON personas (lower(email)) WHERE activo AND email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_personas_empresa_principal_id
  ON personas (empresa_principal_id);

CREATE INDEX IF NOT EXISTS idx_personas_creado_por ON personas (creado_por);

DROP TRIGGER IF EXISTS set_updated_at ON personas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON personas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE personas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- obras — la unidad principal del módulo. Una obra existe sin prospecto (RN-01)
-- y sobrevive al prospecto: Presupuestos, Instalación y Postventa van a colgar
-- de acá. fecha_estimada_compra NO vive en obras — es comercial, va al prospecto.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre                text NOT NULL,
  direccion             text,
  localidad             text,
  provincia             text,
  tipo                  tipo_obra NOT NULL DEFAULT 'otro',
  estado_obra           estado_obra NOT NULL DEFAULT 'desconocido',
  cantidad_unidades     int CHECK (cantidad_unidades IS NULL OR cantidad_unidades > 0),
  superficie_estimada   numeric(12,2) CHECK (superficie_estimada IS NULL OR superficie_estimada > 0),
  fecha_estimada_inicio date,
  observaciones         text,
  creado_por            uuid NOT NULL REFERENCES usuarios(id),
  activo                boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_obras_creado_por ON obras (creado_por);

DROP TRIGGER IF EXISTS set_updated_at ON obras;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON obras
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE obras ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- obra_empresa — roles como array de enum: una empresa puede ser
-- desarrolladora y constructora de la misma obra. Tabla hija solo haría falta
-- si un rol necesitara atributos propios; hoy no los tiene.
-- ============================================================
CREATE TABLE IF NOT EXISTS obra_empresa (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id       uuid NOT NULL REFERENCES obras(id),
  empresa_id    uuid NOT NULL REFERENCES empresas(id),
  roles         rol_empresa[] NOT NULL CHECK (array_length(roles, 1) >= 1),
  observaciones text,
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_obra_empresa_activo
  ON obra_empresa (obra_id, empresa_id) WHERE activo;

CREATE INDEX IF NOT EXISTS idx_obra_empresa_empresa_id ON obra_empresa (empresa_id);

DROP TRIGGER IF EXISTS set_updated_at ON obra_empresa;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON obra_empresa
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE obra_empresa ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- obra_persona — misma lógica de roles. es_referente es columna propia (no un
-- valor del enum) porque lleva el unique parcial: una obra tiene un referente.
-- empresa_id es con qué empresa participa en ESTA obra, que puede no ser su
-- empresa principal.
-- ============================================================
CREATE TABLE IF NOT EXISTS obra_persona (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id       uuid NOT NULL REFERENCES obras(id),
  persona_id    uuid NOT NULL REFERENCES personas(id),
  empresa_id    uuid REFERENCES empresas(id),
  roles         rol_persona[] NOT NULL CHECK (array_length(roles, 1) >= 1),
  es_referente  boolean NOT NULL DEFAULT false,
  observaciones text,
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_obra_persona_activo
  ON obra_persona (obra_id, persona_id) WHERE activo;

-- Un referente por obra.
CREATE UNIQUE INDEX IF NOT EXISTS idx_obra_persona_referente_activo
  ON obra_persona (obra_id) WHERE es_referente AND activo;

CREATE INDEX IF NOT EXISTS idx_obra_persona_persona_id ON obra_persona (persona_id);
CREATE INDEX IF NOT EXISTS idx_obra_persona_empresa_id ON obra_persona (empresa_id);

DROP TRIGGER IF EXISTS set_updated_at ON obra_persona;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON obra_persona
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE obra_persona ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- comercial_comisiones — la comisión es una fila, no una columna.
-- Gatear una columna necesitaría vista + GRANT por columna + trigger; gatearla
-- como fila lo resuelve la RLS que ya existe (`comercial_comision`).
-- Hay fila = hay comisión: "sin comisión ⇒ porcentaje null" pasa a ser
-- imposible de violar en vez de una validación que alguien debe recordar.
-- 0.00 sigue siendo "0% configurado", distinto de "sin fila".
-- ============================================================
CREATE TABLE IF NOT EXISTS comercial_comisiones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_persona_id uuid NOT NULL REFERENCES obra_persona(id),
  porcentaje      numeric(5,2) NOT NULL CHECK (porcentaje BETWEEN 0 AND 100),
  activo          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_comercial_comisiones_relacion_activo
  ON comercial_comisiones (obra_persona_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON comercial_comisiones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON comercial_comisiones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE comercial_comisiones ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- comercial_fuentes — única lista que es catálogo y no enum: se pide poder
-- agregar fuentes sin migración.
-- ============================================================
CREATE TABLE IF NOT EXISTS comercial_fuentes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL,
  descripcion text,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_comercial_fuentes_nombre_activo
  ON comercial_fuentes (lower(nombre)) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON comercial_fuentes;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON comercial_fuentes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE comercial_fuentes ENABLE ROW LEVEL SECURITY;

INSERT INTO comercial_fuentes (nombre)
SELECT nombre
FROM (VALUES
  ('Arquitecto'), ('Referido'), ('Avistamiento en calle'),
  ('Avistamiento web'), ('Inmobiliaria'), ('Constructora'),
  ('Desarrolladora'), ('Contacto propio'), ('Otro')
) AS v(nombre)
WHERE NOT EXISTS (
  SELECT 1 FROM comercial_fuentes f WHERE lower(f.nombre) = lower(v.nombre)
);

-- ============================================================
-- comercial_prospectos — la lectura comercial de una obra. 1:1 con obra activa.
-- ============================================================
CREATE TABLE IF NOT EXISTS comercial_prospectos (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id               uuid NOT NULL REFERENCES obras(id),
  estado_prospecto      estado_prospecto NOT NULL DEFAULT 'nuevo',
  fuente_id             uuid REFERENCES comercial_fuentes(id),
  responsable_id        uuid NOT NULL REFERENCES usuarios(id),
  potencial_estimado    numeric(14,2) CHECK (potencial_estimado IS NULL OR potencial_estimado >= 0),
  moneda_potencial      moneda,
  fecha_estimada_compra date,
  observaciones         text,
  creado_por            uuid NOT NULL REFERENCES usuarios(id),
  activo                boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  -- Un monto sin moneda no se puede leer; una moneda sin monto es ruido.
  CONSTRAINT potencial_con_moneda
    CHECK ((potencial_estimado IS NULL) = (moneda_potencial IS NULL))
);

-- Una obra no puede tener dos prospectos vivos.
CREATE UNIQUE INDEX IF NOT EXISTS idx_comercial_prospectos_obra_activo
  ON comercial_prospectos (obra_id) WHERE activo;

CREATE INDEX IF NOT EXISTS idx_comercial_prospectos_responsable_id
  ON comercial_prospectos (responsable_id);
CREATE INDEX IF NOT EXISTS idx_comercial_prospectos_fuente_id
  ON comercial_prospectos (fuente_id);
CREATE INDEX IF NOT EXISTS idx_comercial_prospectos_creado_por
  ON comercial_prospectos (creado_por);

DROP TRIGGER IF EXISTS set_updated_at ON comercial_prospectos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON comercial_prospectos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE comercial_prospectos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- acceso_comercial() — "tiene alguna vista del módulo". Los maestros
-- (empresas, personas, obras y sus relaciones) se leen desde las cuatro
-- vistas; repetir el OR de cuatro términos en diez policies es la duplicación
-- que esta función evita.
-- ============================================================
CREATE OR REPLACE FUNCTION acceso_comercial()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT tiene_permiso('comercial_prospectos')
      OR tiene_permiso('comercial_obras')
      OR tiene_permiso('comercial_empresas')
      OR tiene_permiso('comercial_personas');
$$;

REVOKE EXECUTE ON FUNCTION acceso_comercial() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION acceso_comercial() TO authenticated;

-- ============================================================
-- RLS — maestros: se leen con cualquier vista del módulo, se escriben con la
-- función de gestión de su propia entidad.
-- ============================================================
DROP POLICY IF EXISTS empresas_select ON empresas;
CREATE POLICY empresas_select ON empresas FOR SELECT
  USING (acceso_comercial());

DROP POLICY IF EXISTS empresas_insert ON empresas;
CREATE POLICY empresas_insert ON empresas FOR INSERT
  WITH CHECK (tiene_permiso('comercial_empresas_gestionar') AND creado_por = auth.uid());

DROP POLICY IF EXISTS empresas_update ON empresas;
CREATE POLICY empresas_update ON empresas FOR UPDATE
  USING (tiene_permiso('comercial_empresas_gestionar'))
  WITH CHECK (tiene_permiso('comercial_empresas_gestionar'));

DROP POLICY IF EXISTS personas_select ON personas;
CREATE POLICY personas_select ON personas FOR SELECT
  USING (acceso_comercial());

DROP POLICY IF EXISTS personas_insert ON personas;
CREATE POLICY personas_insert ON personas FOR INSERT
  WITH CHECK (tiene_permiso('comercial_personas_gestionar') AND creado_por = auth.uid());

DROP POLICY IF EXISTS personas_update ON personas;
CREATE POLICY personas_update ON personas FOR UPDATE
  USING (tiene_permiso('comercial_personas_gestionar'))
  WITH CHECK (tiene_permiso('comercial_personas_gestionar'));

DROP POLICY IF EXISTS obras_select ON obras;
CREATE POLICY obras_select ON obras FOR SELECT
  USING (acceso_comercial());

DROP POLICY IF EXISTS obras_insert ON obras;
CREATE POLICY obras_insert ON obras FOR INSERT
  WITH CHECK (tiene_permiso('comercial_obras_gestionar') AND creado_por = auth.uid());

DROP POLICY IF EXISTS obras_update ON obras;
CREATE POLICY obras_update ON obras FOR UPDATE
  USING (tiene_permiso('comercial_obras_gestionar'))
  WITH CHECK (tiene_permiso('comercial_obras_gestionar'));

-- Las relaciones son parte de la ficha de la obra: quien gestiona obras las
-- gestiona. No tienen función propia.
DROP POLICY IF EXISTS obra_empresa_select ON obra_empresa;
CREATE POLICY obra_empresa_select ON obra_empresa FOR SELECT
  USING (acceso_comercial());

DROP POLICY IF EXISTS obra_empresa_insert ON obra_empresa;
CREATE POLICY obra_empresa_insert ON obra_empresa FOR INSERT
  WITH CHECK (tiene_permiso('comercial_obras_gestionar'));

DROP POLICY IF EXISTS obra_empresa_update ON obra_empresa;
CREATE POLICY obra_empresa_update ON obra_empresa FOR UPDATE
  USING (tiene_permiso('comercial_obras_gestionar'))
  WITH CHECK (tiene_permiso('comercial_obras_gestionar'));

DROP POLICY IF EXISTS obra_persona_select ON obra_persona;
CREATE POLICY obra_persona_select ON obra_persona FOR SELECT
  USING (acceso_comercial());

DROP POLICY IF EXISTS obra_persona_insert ON obra_persona;
CREATE POLICY obra_persona_insert ON obra_persona FOR INSERT
  WITH CHECK (tiene_permiso('comercial_obras_gestionar'));

DROP POLICY IF EXISTS obra_persona_update ON obra_persona;
CREATE POLICY obra_persona_update ON obra_persona FOR UPDATE
  USING (tiene_permiso('comercial_obras_gestionar'))
  WITH CHECK (tiene_permiso('comercial_obras_gestionar'));

DROP POLICY IF EXISTS comercial_fuentes_select ON comercial_fuentes;
CREATE POLICY comercial_fuentes_select ON comercial_fuentes FOR SELECT
  USING (acceso_comercial());

DROP POLICY IF EXISTS comercial_fuentes_insert ON comercial_fuentes;
CREATE POLICY comercial_fuentes_insert ON comercial_fuentes FOR INSERT
  WITH CHECK (tiene_permiso('comercial_prospectos_gestionar'));

DROP POLICY IF EXISTS comercial_fuentes_update ON comercial_fuentes;
CREATE POLICY comercial_fuentes_update ON comercial_fuentes FOR UPDATE
  USING (tiene_permiso('comercial_prospectos_gestionar'))
  WITH CHECK (tiene_permiso('comercial_prospectos_gestionar'));

-- ============================================================
-- RLS — comisiones: la fila es el dato sensible. Sin la función no entra en
-- el SELECT, así que quien no la tiene no ve el porcentaje ni sabe que existe.
-- ============================================================
DROP POLICY IF EXISTS comercial_comisiones_select ON comercial_comisiones;
CREATE POLICY comercial_comisiones_select ON comercial_comisiones FOR SELECT
  USING (tiene_permiso('comercial_comision'));

DROP POLICY IF EXISTS comercial_comisiones_insert ON comercial_comisiones;
CREATE POLICY comercial_comisiones_insert ON comercial_comisiones FOR INSERT
  WITH CHECK (tiene_permiso('comercial_comision'));

DROP POLICY IF EXISTS comercial_comisiones_update ON comercial_comisiones;
CREATE POLICY comercial_comisiones_update ON comercial_comisiones FOR UPDATE
  USING (tiene_permiso('comercial_comision'))
  WITH CHECK (tiene_permiso('comercial_comision'));

-- ============================================================
-- RLS — prospectos: se ven los propios. `comercial_gestionar_ajenos` es el
-- único eje admin del módulo — ve, edita y traspasa el responsable.
-- ============================================================
DROP POLICY IF EXISTS comercial_prospectos_select ON comercial_prospectos;
CREATE POLICY comercial_prospectos_select ON comercial_prospectos FOR SELECT
  USING (
    tiene_permiso('comercial_prospectos')
    AND (responsable_id = auth.uid() OR tiene_permiso('comercial_gestionar_ajenos'))
  );

DROP POLICY IF EXISTS comercial_prospectos_insert ON comercial_prospectos;
CREATE POLICY comercial_prospectos_insert ON comercial_prospectos FOR INSERT
  WITH CHECK (
    tiene_permiso('comercial_prospectos_gestionar')
    AND creado_por = auth.uid()
    AND (responsable_id = auth.uid() OR tiene_permiso('comercial_gestionar_ajenos'))
  );

-- UPDATE alineado con SELECT: nadie modifica lo que no ve. El WITH CHECK
-- vuelve a exigir la condición sobre la fila nueva para que traspasar el
-- prospecto a otro necesite la función admin.
DROP POLICY IF EXISTS comercial_prospectos_update ON comercial_prospectos;
CREATE POLICY comercial_prospectos_update ON comercial_prospectos FOR UPDATE
  USING (
    tiene_permiso('comercial_prospectos_gestionar')
    AND (responsable_id = auth.uid() OR tiene_permiso('comercial_gestionar_ajenos'))
  )
  WITH CHECK (
    tiene_permiso('comercial_prospectos_gestionar')
    AND (responsable_id = auth.uid() OR tiene_permiso('comercial_gestionar_ajenos'))
  );

-- ============================================================
-- GRANTs — RLS no alcanza sin esto (ver DECISIONES.md).
-- ============================================================
GRANT SELECT, INSERT, UPDATE ON public.empresas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.personas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obras TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obra_empresa TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.obra_persona TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.comercial_comisiones TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.comercial_fuentes TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.comercial_prospectos TO authenticated;

-- ============================================================
-- Seed — submódulos del módulo comercial
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden)
VALUES
  ('comercial_prospectos', 'comercial', 'vista', 'Prospectos', 1),
  ('comercial_obras', 'comercial', 'vista', 'Obras', 2),
  ('comercial_empresas', 'comercial', 'vista', 'Empresas', 3),
  ('comercial_personas', 'comercial', 'vista', 'Personas', 4)
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'comercial_prospectos_gestionar', 'comercial', 'funcion', 'Gestionar prospectos', id, 1
FROM submodulos WHERE codigo = 'comercial_prospectos'
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'comercial_gestionar_ajenos', 'comercial', 'funcion', 'Ver y gestionar prospectos ajenos', id, 2
FROM submodulos WHERE codigo = 'comercial_prospectos'
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'comercial_comision', 'comercial', 'funcion', 'Ver comisiones', id, 3
FROM submodulos WHERE codigo = 'comercial_prospectos'
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'comercial_obras_gestionar', 'comercial', 'funcion', 'Gestionar obras', id, 1
FROM submodulos WHERE codigo = 'comercial_obras'
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'comercial_empresas_gestionar', 'comercial', 'funcion', 'Gestionar empresas', id, 1
FROM submodulos WHERE codigo = 'comercial_empresas'
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'comercial_personas_gestionar', 'comercial', 'funcion', 'Gestionar personas', id, 1
FROM submodulos WHERE codigo = 'comercial_personas'
ON CONFLICT DO NOTHING;

-- `usuarios_select` ya está extendida para tareas; el picker de responsable de
-- prospecto necesita lo mismo desde comercial.
DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT
  USING (
    id = auth.uid()
    OR tiene_permiso('usuarios_ver')
    OR tiene_permiso('tareas_lista')
    OR tiene_permiso('tareas_proyectos')
    OR tiene_permiso('comercial_prospectos')
  );

-- ============================================================
-- guardar_obra_persona — la relación y su comisión se guardan juntas.
-- SECURITY INVOKER a propósito: quien no tiene `comercial_comision` no ve ni
-- toca la fila de comisión, así que sus UPDATE afectan 0 filas y la comisión
-- que ya existía sobrevive intacta. La regla no vive en actions.ts.
-- ============================================================
CREATE OR REPLACE FUNCTION guardar_obra_persona(
  p_id                  uuid,
  p_obra_id             uuid,
  p_persona_id          uuid,
  p_empresa_id          uuid,
  p_roles               rol_persona[],
  p_es_referente        boolean,
  p_porcentaje_comision numeric,
  p_observaciones       text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_id IS NULL THEN
    INSERT INTO obra_persona (obra_id, persona_id, empresa_id, roles, es_referente, observaciones)
    VALUES (p_obra_id, p_persona_id, p_empresa_id, p_roles, p_es_referente, p_observaciones)
    RETURNING id INTO v_id;
  ELSE
    UPDATE obra_persona
       SET empresa_id    = p_empresa_id,
           roles         = p_roles,
           es_referente  = p_es_referente,
           observaciones = p_observaciones
     WHERE id = p_id AND activo
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'La relación no existe o no se puede editar' USING ERRCODE = 'CM001';
    END IF;
  END IF;

  IF p_porcentaje_comision IS NULL THEN
    UPDATE comercial_comisiones SET activo = false
     WHERE obra_persona_id = v_id AND activo;
  ELSE
    UPDATE comercial_comisiones SET porcentaje = p_porcentaje_comision
     WHERE obra_persona_id = v_id AND activo;

    IF NOT FOUND THEN
      INSERT INTO comercial_comisiones (obra_persona_id, porcentaje)
      VALUES (v_id, p_porcentaje_comision);
    END IF;
  END IF;

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION guardar_obra_persona(uuid, uuid, uuid, uuid, rol_persona[], boolean, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION guardar_obra_persona(uuid, uuid, uuid, uuid, rol_persona[], boolean, numeric, text) TO authenticated;

-- ============================================================
-- Cascadas y bloqueos — invariantes, no validaciones de UI.
-- ============================================================
-- SECURITY DEFINER: la comisión se desactiva con la relación aunque quien
-- desactiva no tenga permiso para verla. Es cascada, no autorización.
CREATE OR REPLACE FUNCTION desactivar_comision_de_relacion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE comercial_comisiones SET activo = false
   WHERE obra_persona_id = NEW.id AND activo;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION desactivar_comision_de_relacion() FROM PUBLIC;

DROP TRIGGER IF EXISTS cascada_comision ON obra_persona;
CREATE TRIGGER cascada_comision
  AFTER UPDATE ON obra_persona
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION desactivar_comision_de_relacion();

-- Desactivar la obra se lleva su prospecto y sus relaciones: la obra es el
-- contenedor, dejarle relaciones vivas deja filas que nadie puede alcanzar.
CREATE OR REPLACE FUNCTION desactivar_obra_en_cascada()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE comercial_prospectos SET activo = false WHERE obra_id = NEW.id AND activo;
  UPDATE obra_empresa SET activo = false WHERE obra_id = NEW.id AND activo;
  UPDATE obra_persona SET activo = false WHERE obra_id = NEW.id AND activo;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION desactivar_obra_en_cascada() FROM PUBLIC;

DROP TRIGGER IF EXISTS cascada_desactivar_obra ON obras;
CREATE TRIGGER cascada_desactivar_obra
  AFTER UPDATE ON obras
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION desactivar_obra_en_cascada();

-- Empresa y persona no cascadean: son maestros reutilizables, y desactivar
-- una empresa no debería vaciar en silencio las obras donde participa. Se
-- bloquea y se pide sacar la relación primero.
CREATE OR REPLACE FUNCTION validar_desactivar_empresa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM obra_empresa WHERE empresa_id = NEW.id AND activo)
     OR EXISTS (SELECT 1 FROM obra_persona WHERE empresa_id = NEW.id AND activo) THEN
    RAISE EXCEPTION 'La empresa participa en obras activas' USING ERRCODE = 'CM002';
  END IF;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION validar_desactivar_empresa() FROM PUBLIC;

DROP TRIGGER IF EXISTS validar_desactivar_empresa ON empresas;
CREATE TRIGGER validar_desactivar_empresa
  BEFORE UPDATE ON empresas
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION validar_desactivar_empresa();

CREATE OR REPLACE FUNCTION validar_desactivar_persona()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM obra_persona WHERE persona_id = NEW.id AND activo) THEN
    RAISE EXCEPTION 'La persona participa en obras activas' USING ERRCODE = 'CM003';
  END IF;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION validar_desactivar_persona() FROM PUBLIC;

DROP TRIGGER IF EXISTS validar_desactivar_persona ON personas;
CREATE TRIGGER validar_desactivar_persona
  BEFORE UPDATE ON personas
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION validar_desactivar_persona();
