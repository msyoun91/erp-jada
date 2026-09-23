-- sql/107 — notificaciones: la infra, sin ningún evento.
--
-- Vuelve lo de `sql/038` que no era de tareas ni de obras; `sql/101` lo había
-- borrado junto con ellas porque su vocabulario era enteramente de esos dos
-- módulos. Queda el mecanismo y nada que lo dispare: el enum sin valores, la
-- tabla sin CHECK de `entidad` y `notificaciones_listar` sin ramas. El primer
-- evento suma las tres cosas en su propia migración.
--
-- Las reglas son las de siempre (`decisiones/global/infra.md` → *Notificaciones*):
-- infra sin submódulo, RLS por `auth.uid()`, nadie inserta salvo `notificar()`,
-- y la notificación apunta, no copia.

-- ============================================================
-- 1. Enum — vacío hasta el primer evento (`ALTER TYPE ... ADD VALUE`)
-- ============================================================
DO $$ BEGIN
  CREATE TYPE tipo_notificacion AS ENUM ();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 2. La tabla
--
-- `entidad` es el discriminador de a qué tabla apunta `entidad_id`. Sin CHECK
-- por ahora: un `IN ()` vacío no es SQL válido, y con el enum vacío nada puede
-- insertarse igual. El primer evento suma el CHECK con su vocabulario.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.usuario_notificaciones (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES public.usuarios(id),
  tipo        tipo_notificacion NOT NULL,
  entidad     text NOT NULL,
  entidad_id  uuid NOT NULL,
  actor_id    uuid REFERENCES public.usuarios(id),
  leida_at    timestamptz,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_usuario_notificaciones_bandeja
  ON public.usuario_notificaciones (usuario_id, created_at DESC) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_usuario_notificaciones_actor
  ON public.usuario_notificaciones (actor_id);

DROP TRIGGER IF EXISTS set_updated_at ON public.usuario_notificaciones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.usuario_notificaciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.usuario_notificaciones ENABLE ROW LEVEL SECURITY;

-- Sin policy ni GRANT de INSERT: una notificación que el cliente pudiera
-- insertar sería un canal para escribirle a otro usuario.
DROP POLICY IF EXISTS usuario_notificaciones_select ON public.usuario_notificaciones;
CREATE POLICY usuario_notificaciones_select ON public.usuario_notificaciones FOR SELECT
  USING (usuario_id = (select auth.uid()));

DROP POLICY IF EXISTS usuario_notificaciones_update ON public.usuario_notificaciones;
CREATE POLICY usuario_notificaciones_update ON public.usuario_notificaciones FOR UPDATE
  USING (usuario_id = (select auth.uid()))
  WITH CHECK (usuario_id = (select auth.uid()));

-- GRANT por columna: RLS no acota columnas, el GRANT sí.
GRANT SELECT ON public.usuario_notificaciones TO authenticated;
GRANT UPDATE (leida_at, activo) ON public.usuario_notificaciones TO authenticated;

-- ============================================================
-- 3. Un solo lugar donde nace una notificación
--
-- `IS DISTINCT FROM` y no `<>`: con `auth.uid()` NULL (service_role, SQL
-- editor) la comparación daría NULL y el aviso se perdería en silencio.
-- ============================================================
CREATE OR REPLACE FUNCTION public.notificar(
  p_usuario_id uuid,
  p_tipo       tipo_notificacion,
  p_entidad    text,
  p_entidad_id uuid,
  p_actor_id   uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id IS NULL OR p_entidad_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT (p_usuario_id IS DISTINCT FROM p_actor_id) THEN
    RETURN;
  END IF;

  INSERT INTO usuario_notificaciones (usuario_id, tipo, entidad, entidad_id, actor_id)
  VALUES (p_usuario_id, p_tipo, p_entidad, p_entidad_id, p_actor_id);
END;
$$;

-- ============================================================
-- 4. La bandeja
--
-- INVOKER: cada evento suma a `resuelta` una rama con INNER JOIN contra su
-- tabla, y la RLS del que lee decide qué sobrevive. Sin ramas, `resuelta` es
-- una fila imposible que solo fija las columnas, y la bandeja sale vacía.
-- ============================================================
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
    SELECT NULL::uuid AS notificacion_id,
           NULL::text AS etiqueta,
           NULL::text AS motivo,
           NULL::text AS destino,
           NULL::uuid AS destino_id
    WHERE false
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, u.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r      ON r.notificacion_id = n.id
  LEFT JOIN usuarios u ON u.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;

-- ============================================================
-- 5. GRANTs de ejecución — `notificar` solo desde triggers, nunca por RPC
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.notificar(uuid, tipo_notificacion, text, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notificaciones_listar(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notificaciones_listar(int) TO authenticated;
