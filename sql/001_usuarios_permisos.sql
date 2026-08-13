-- Módulo usuarios + sistema de permisos (submódulos)
-- Correr en Supabase SQL Editor. Idempotente donde es posible.

-- ============================================================
-- Trigger genérico updated_at (reusar en toda tabla nueva)
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- usuarios — perfil 1:1 con auth.users
-- ============================================================
CREATE TABLE IF NOT EXISTS usuarios (
  id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      text NOT NULL,
  email       text NOT NULL,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_email_activo
  ON usuarios (email) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON usuarios;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON usuarios
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Auto-crear fila usuarios al crear un auth.users (signup o admin.createUser)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.usuarios (id, nombre, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'nombre', NEW.email), NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- submodulos — catálogo (única unidad de autorización, sin roles)
-- ============================================================
DO $$
BEGIN
  CREATE TYPE tipo_submodulo AS ENUM ('seccion', 'funcion');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

CREATE TABLE IF NOT EXISTS submodulos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      text NOT NULL,
  modulo      text NOT NULL,
  tipo        tipo_submodulo NOT NULL,
  nombre      text NOT NULL,
  orden       int NOT NULL DEFAULT 0,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_submodulos_codigo_activo
  ON submodulos (codigo) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON submodulos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON submodulos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE submodulos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- usuario_submodulos — asignación usuario ↔ submódulo
-- ============================================================
CREATE TABLE IF NOT EXISTS usuario_submodulos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  submodulo_id  uuid NOT NULL REFERENCES submodulos(id) ON DELETE CASCADE,
  activo        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- UNIQUE constraint normal (no parcial): esta tabla se actualiza con upsert
-- (onConflict usuario_id,submodulo_id) — los índices parciales no sirven para eso.
DO $$
BEGIN
  ALTER TABLE usuario_submodulos
    ADD CONSTRAINT usuario_submodulos_usuario_submodulo_key UNIQUE (usuario_id, submodulo_id);
EXCEPTION WHEN duplicate_table THEN
  NULL;
END $$;

DROP TRIGGER IF EXISTS set_updated_at ON usuario_submodulos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON usuario_submodulos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE usuario_submodulos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tiene_permiso(codigo) — usada en RLS y disponible para queries
-- ============================================================
CREATE OR REPLACE FUNCTION tiene_permiso(p_codigo text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.usuario_submodulos us
    JOIN public.submodulos s ON s.id = us.submodulo_id
    WHERE us.usuario_id = auth.uid()
      AND us.activo
      AND s.activo
      AND s.codigo = p_codigo
  );
$$;

-- ============================================================
-- RLS policies
-- ============================================================
DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT
  USING (id = auth.uid() OR tiene_permiso('usuarios_ver'));

DROP POLICY IF EXISTS submodulos_select ON submodulos;
CREATE POLICY submodulos_select ON submodulos FOR SELECT
  USING (
    tiene_permiso('usuarios_gestionar')
    OR id IN (
      SELECT submodulo_id FROM usuario_submodulos
      WHERE usuario_id = auth.uid() AND activo
    )
  );

DROP POLICY IF EXISTS usuario_submodulos_select ON usuario_submodulos;
CREATE POLICY usuario_submodulos_select ON usuario_submodulos FOR SELECT
  USING (usuario_id = auth.uid() OR tiene_permiso('usuarios_gestionar'));

-- Sin policies de INSERT/UPDATE/DELETE: esas operaciones pasan siempre
-- por server actions con service_role (ver modules/usuarios/actions.ts).

-- RLS no alcanza sin GRANT: sin esto, SELECT falla con
-- "permission denied for table" (42501) aunque la policy sea correcta.
GRANT SELECT ON public.usuarios TO authenticated;
GRANT SELECT ON public.submodulos TO authenticated;
GRANT SELECT ON public.usuario_submodulos TO authenticated;

-- ============================================================
-- Seed — submódulos del propio módulo usuarios
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden)
VALUES
  ('usuarios_ver', 'usuarios', 'seccion', 'Usuarios', 1),
  ('usuarios_gestionar', 'usuarios', 'funcion', 'Gestionar usuarios y permisos', 1)
ON CONFLICT DO NOTHING;

-- ============================================================
-- BOOTSTRAP — primer usuario admin (correr manualmente una vez)
-- ============================================================
-- 1. Crear el primer usuario desde Supabase Dashboard → Authentication → Add user
--    (o con signup normal desde /login una vez exista la página).
-- 2. Correr esto reemplazando el email:
--
-- INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
-- SELECT u.id, s.id
-- FROM usuarios u, submodulos s
-- WHERE u.email = 'admin@ejemplo.com'
--   AND s.codigo IN ('usuarios_ver', 'usuarios_gestionar');
