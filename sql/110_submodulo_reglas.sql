-- sql/110 — reglas entre permisos: uno requiere a otro, o no se pueden tener juntos.
--
-- La regla vive en una tabla y no en el cuerpo del trigger: el panel de
-- permisos la lee de ahí para avisar antes de guardar, y el trigger la hace
-- valer. Decisión: `decisiones/global/permisos.md` → *Reglas entre permisos*.
-- Verificado con `sql/tests/submodulo_reglas.sql`.
--
-- Vista → función no se carga acá: ya la da `submodulos.vista_id` (US001).
-- Las dos reglas de tareas (`tareas_equipo` requiere `usuarios_delegar`,
-- `usuarios_delegar` requiere `tareas_ver`) entran con la migración de tareas:
-- esos submódulos todavía no existen.

DO $$ BEGIN
  CREATE TYPE tipo_regla_submodulo AS ENUM ('requiere', 'excluye');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- `excluye` se carga una sola vez por par y vale en los dos sentidos.
CREATE TABLE IF NOT EXISTS public.submodulo_reglas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submodulo_id uuid NOT NULL REFERENCES public.submodulos (id),
  otro_id uuid NOT NULL REFERENCES public.submodulos (id),
  tipo tipo_regla_submodulo NOT NULL,
  activo boolean NOT NULL DEFAULT true,
  CONSTRAINT submodulo_reglas_distintos CHECK (submodulo_id <> otro_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS submodulo_reglas_par
  ON public.submodulo_reglas (submodulo_id, otro_id) WHERE activo;

ALTER TABLE public.submodulo_reglas ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.submodulo_reglas TO authenticated;

-- Solo lectura: las reglas se cargan por migración, como el catálogo.
DROP POLICY IF EXISTS submodulo_reglas_select ON public.submodulo_reglas;
CREATE POLICY submodulo_reglas_select ON public.submodulo_reglas FOR SELECT
  USING (tiene_permiso('usuarios_ver'));

-- La pestaña Equipos es del admin y Mi equipo del delegador: nadie es las dos cosas.
INSERT INTO public.submodulo_reglas (submodulo_id, otro_id, tipo)
SELECT a.id, b.id, 'excluye'
FROM public.submodulos a, public.submodulos b
WHERE a.codigo = 'usuarios_equipos' AND a.activo
  AND b.codigo = 'usuarios_equipo' AND b.activo
  AND NOT EXISTS (
    SELECT 1 FROM public.submodulo_reglas r
    WHERE r.activo AND r.submodulo_id = a.id AND r.otro_id = b.id
  );

-- ============================================================
-- usuario_submodulos_validar — mismo cuerpo que `sql/105` más las reglas
-- ============================================================
CREATE OR REPLACE FUNCTION public.usuario_submodulos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  f public.usuario_submodulos;
  s public.submodulos;
  o public.submodulos;
  v_equipo uuid;
BEGIN
  SELECT * INTO f FROM public.usuario_submodulos WHERE id = NEW.id;
  SELECT * INTO s FROM public.submodulos WHERE id = f.submodulo_id;

  IF NOT f.activo THEN
    IF s.tipo = 'vista' AND EXISTS (
      SELECT 1
      FROM public.usuario_submodulos us
      JOIN public.submodulos fn ON fn.id = us.submodulo_id
      WHERE us.usuario_id = f.usuario_id AND us.activo AND fn.vista_id = s.id
    ) THEN
      RAISE EXCEPTION 'Cada función requiere que su vista esté autorizada' USING ERRCODE = 'US001';
    END IF;

    SELECT x.* INTO o
    FROM public.submodulo_reglas r
    JOIN public.submodulos x ON x.id = r.submodulo_id AND x.activo
    JOIN public.usuario_submodulos us ON us.submodulo_id = x.id AND us.usuario_id = f.usuario_id AND us.activo
    WHERE r.activo AND r.tipo = 'requiere' AND r.otro_id = s.id
    LIMIT 1;
    IF FOUND AND s.activo THEN
      RAISE EXCEPTION '«%» de % requiere «%» de %', o.nombre, o.modulo, s.nombre, s.modulo USING ERRCODE = 'US016';
    END IF;
    RETURN NULL;
  END IF;

  IF s.tipo = 'funcion' AND NOT EXISTS (
    SELECT 1 FROM public.usuario_submodulos
    WHERE usuario_id = f.usuario_id AND submodulo_id = s.vista_id AND activo
  ) THEN
    RAISE EXCEPTION 'Cada función requiere que su vista esté autorizada' USING ERRCODE = 'US001';
  END IF;

  IF s.activo THEN
    SELECT x.* INTO o
    FROM public.submodulo_reglas r
    JOIN public.submodulos x ON x.id = r.otro_id AND x.activo
    WHERE r.activo AND r.tipo = 'requiere' AND r.submodulo_id = s.id
      AND NOT EXISTS (
        SELECT 1 FROM public.usuario_submodulos
        WHERE usuario_id = f.usuario_id AND submodulo_id = x.id AND activo
      )
    LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION '«%» de % requiere «%» de %', s.nombre, s.modulo, o.nombre, o.modulo USING ERRCODE = 'US016';
    END IF;

    SELECT x.* INTO o
    FROM public.submodulo_reglas r
    JOIN public.submodulos x
      ON x.id = CASE WHEN r.submodulo_id = s.id THEN r.otro_id ELSE r.submodulo_id END AND x.activo
    JOIN public.usuario_submodulos us ON us.submodulo_id = x.id AND us.usuario_id = f.usuario_id AND us.activo
    WHERE r.activo AND r.tipo = 'excluye' AND s.id IN (r.submodulo_id, r.otro_id)
    LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION '«%» de % no se puede tener junto con «%» de %', s.nombre, s.modulo, o.nombre, o.modulo USING ERRCODE = 'US017';
    END IF;
  END IF;

  v_equipo := public.equipo_de(f.usuario_id);

  IF s.codigo = 'usuarios_gestionar' AND v_equipo IS NOT NULL THEN
    RAISE EXCEPTION 'Quien administra usuarios no puede ser miembro de un equipo' USING ERRCODE = 'US002';
  END IF;

  IF s.codigo = 'usuarios_delegar' THEN
    IF v_equipo IS NULL THEN
      RAISE EXCEPTION 'El delegador tiene que ser miembro de un equipo' USING ERRCODE = 'US003';
    END IF;

    -- Serializa dos designaciones concurrentes en el mismo equipo.
    PERFORM 1 FROM public.equipos WHERE id = v_equipo FOR UPDATE;

    IF EXISTS (
      SELECT 1
      FROM public.usuario_submodulos us
      JOIN public.equipos_miembros m ON m.usuario_id = us.usuario_id AND m.activo
      WHERE m.equipo_id = v_equipo
        AND us.submodulo_id = s.id
        AND us.activo
        AND us.usuario_id <> f.usuario_id
    ) THEN
      RAISE EXCEPTION 'El equipo ya tiene un delegador' USING ERRCODE = 'US004';
    END IF;
  END IF;

  -- El techo, para las filas delegadas.
  IF f.otorgada_por IS NOT NULL AND public.equipo_de(f.otorgada_por) IS NOT NULL THEN
    IF f.otorgada_por = f.usuario_id OR v_equipo IS DISTINCT FROM public.equipo_de(f.otorgada_por) THEN
      RAISE EXCEPTION 'Solo se delega a otro miembro del mismo equipo' USING ERRCODE = 'US005';
    END IF;
    IF NOT public.usuario_tiene_permiso(f.otorgada_por, 'usuarios_delegar') THEN
      RAISE EXCEPTION 'Solo el delegador del equipo puede delegar permisos' USING ERRCODE = 'US006';
    END IF;
    IF NOT s.delegable THEN
      RAISE EXCEPTION 'Ese permiso no es delegable' USING ERRCODE = 'US007';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.usuario_submodulos
      WHERE usuario_id = f.otorgada_por AND submodulo_id = s.id AND activo
    ) THEN
      RAISE EXCEPTION 'El delegador no puede dar un permiso que no tiene' USING ERRCODE = 'US008';
    END IF;
  END IF;

  RETURN NULL;
END;
$$;
