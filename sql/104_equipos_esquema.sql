-- sql/104 — equipos y delegación: el esquema.
--
-- Solo tablas, columnas, seed y visibilidad. Las reglas (un delegador por
-- equipo, techo, cascadas, heredero) son `sql/105`: hasta que corra, nadie
-- escribe en estas tablas salvo el admin con `service_role`, y el delegador no
-- tiene por dónde otorgar nada. Decisión: `decisiones/usuarios.md` → *Equipos y
-- delegación de permisos*.

-- ============================================================
-- equipos
-- ============================================================
CREATE TABLE IF NOT EXISTS public.equipos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL CHECK (length(btrim(nombre)) > 0),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_equipos_nombre_activo
  ON public.equipos (nombre) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.equipos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.equipos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.equipos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- equipos_miembros
-- ============================================================
-- Cambiar de equipo es desactivar la fila vieja e insertar otra: la fila
-- inactiva queda como historia y el unique parcial deja una sola vigente.
CREATE TABLE IF NOT EXISTS public.equipos_miembros (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipo_id   uuid NOT NULL REFERENCES public.equipos(id),
  usuario_id  uuid NOT NULL REFERENCES public.usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_equipos_miembros_usuario_activo
  ON public.equipos_miembros (usuario_id) WHERE activo;

CREATE INDEX IF NOT EXISTS idx_equipos_miembros_equipo
  ON public.equipos_miembros (equipo_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.equipos_miembros;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.equipos_miembros
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.equipos_miembros ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- usuario_submodulos.otorgada_por · submodulos.delegable
-- ============================================================
-- NULL = lo otorgó el admin antes de que existiera la columna. Las filas
-- nuevas guardan quién: la action de admin lo pasa explícito (con
-- `service_role`, `auth.uid()` es NULL), el flujo del delegador lo toma de su
-- sesión. `updated_at` ya estaba desde `sql/001`.
ALTER TABLE public.usuario_submodulos
  ADD COLUMN IF NOT EXISTS otorgada_por uuid REFERENCES public.usuarios(id);

CREATE INDEX IF NOT EXISTS idx_usuario_submodulos_otorgada_por
  ON public.usuario_submodulos (otorgada_por) WHERE activo AND otorgada_por IS NOT NULL;

-- `false` por defecto: una función nueva nace sin poder delegarse.
ALTER TABLE public.submodulos
  ADD COLUMN IF NOT EXISTS delegable boolean NOT NULL DEFAULT false;

-- ============================================================
-- Seed — vista "Mi equipo" y su función
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden)
SELECT 'usuarios_equipo', 'usuarios', 'vista', 'Mi equipo', 2
WHERE NOT EXISTS (
  SELECT 1 FROM public.submodulos WHERE codigo = 'usuarios_equipo' AND activo
);

INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id)
SELECT 'usuarios_delegar', 'usuarios', 'funcion', 'Delegar permisos a su equipo', 1, v.id
FROM public.submodulos v
WHERE v.codigo = 'usuarios_equipo' AND v.activo
  AND NOT EXISTS (
    SELECT 1 FROM public.submodulos WHERE codigo = 'usuarios_delegar' AND activo
  );

-- ============================================================
-- mi_equipo() — el equipo vigente de quien llama
-- ============================================================
-- DEFINER para que las policies de `equipos_miembros` puedan preguntarlo sin
-- consultarse a sí mismas (42P17). Sin argumento a propósito: con un
-- `p_usuario`, cualquier sesión podría averiguar el equipo de cualquiera.
CREATE OR REPLACE FUNCTION public.mi_equipo()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT m.equipo_id
  FROM public.equipos_miembros m
  JOIN public.equipos e ON e.id = m.equipo_id
  WHERE m.usuario_id = auth.uid()
    AND m.activo
    AND e.activo;
$$;

REVOKE EXECUTE ON FUNCTION public.mi_equipo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mi_equipo() TO authenticated;

-- ============================================================
-- RLS — el admin ve todo; el delegador, su equipo
-- ============================================================
-- La rama del delegador pide la vista `usuarios_equipo`, igual que la del admin
-- pide `usuarios_ver`: ver es de la vista, otorgar es de la función.
DROP POLICY IF EXISTS equipos_select ON public.equipos;
CREATE POLICY equipos_select ON public.equipos FOR SELECT
  USING (
    tiene_permiso('usuarios_ver')
    OR (tiene_permiso('usuarios_equipo') AND id = mi_equipo())
  );

DROP POLICY IF EXISTS equipos_miembros_select ON public.equipos_miembros;
CREATE POLICY equipos_miembros_select ON public.equipos_miembros FOR SELECT
  USING (
    tiene_permiso('usuarios_ver')
    OR (tiene_permiso('usuarios_equipo') AND activo AND equipo_id = mi_equipo())
  );

-- Se reescribe entera: las ramas de `tareas_*` y `obras_*` apuntaban a
-- submódulos que `sql/101` retiró y ya no conceden nada.
DROP POLICY IF EXISTS usuarios_select ON public.usuarios;
CREATE POLICY usuarios_select ON public.usuarios FOR SELECT
  USING (
    id = (select auth.uid())
    OR tiene_permiso('usuarios_ver')
    OR (
      tiene_permiso('usuarios_equipo')
      AND id IN (
        SELECT usuario_id FROM public.equipos_miembros
        WHERE activo AND equipo_id = mi_equipo()
      )
    )
  );

DROP POLICY IF EXISTS usuario_submodulos_select ON public.usuario_submodulos;
CREATE POLICY usuario_submodulos_select ON public.usuario_submodulos FOR SELECT
  USING (
    usuario_id = (select auth.uid())
    OR tiene_permiso('usuarios_gestionar')
    OR (
      tiene_permiso('usuarios_equipo')
      AND usuario_id IN (
        SELECT usuario_id FROM public.equipos_miembros
        WHERE activo AND equipo_id = mi_equipo()
      )
    )
  );

-- El delegador tiene que poder nombrar los permisos de su equipo, incluidos los
-- que le dio el admin a un miembro y él no tiene. El catálogo no es secreto.
DROP POLICY IF EXISTS submodulos_select ON public.submodulos;
CREATE POLICY submodulos_select ON public.submodulos FOR SELECT
  USING (
    tiene_permiso('usuarios_gestionar')
    OR tiene_permiso('usuarios_equipo')
    OR id IN (
      SELECT submodulo_id FROM public.usuario_submodulos
      WHERE usuario_id = (select auth.uid()) AND activo
    )
  );

-- Toda escritura del admin pasa por `service_role`; la del delegador, por las
-- funciones de `sql/105`. Por eso alcanza con SELECT.
GRANT SELECT ON public.equipos TO authenticated;
GRANT SELECT ON public.equipos_miembros TO authenticated;
