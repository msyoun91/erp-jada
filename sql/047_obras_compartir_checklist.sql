-- ============================================================
-- 047 — Agenda de Obras: compartir con checklist + vista Compartido
--
-- Hasta acá "compartir" (obras_compartir_persona / _empresa) daba lectura de
-- UNA ficha suelta. Faltaban tres cosas que pidió el usuario:
--
--   1. Compartir OBRA. La obra solo se transfería (cambia de dueño). Ahora
--      obras_compartir_obra da lectura sin mover el ownership, revocable,
--      igual que persona y empresa. Tabla nueva `obras_obra_compartida`.
--
--   2. CHECKLIST al compartir. Al compartir una obra o una empresa, lo
--      vinculado que es MÍO puede compartirse en el mismo acto. Lo tildado
--      viaja en un array y recibe su propio grant completo, marcado con el
--      origen (`origen_obra_id` / `origen_empresa_id`) para que revocar el
--      padre lo arrastre. Persona no lleva checklist: sus únicas relaciones
--      son empresas (dónde trabaja) y el usuario decidió compartirla sola.
--
--   3. CASCADA de revocación. Revocar una obra/empresa compartida desactiva
--      también los grants que nacieron de ese compartir (los que tienen el
--      `origen_*` correspondiente). Un grant que después se compartió directo
--      pierde el `origen_*` (última escritura gana) y ya no cae con el padre.
--
--   4. VISTA "Compartido" (submódulo `obras_compartido`). Tab nueva que lista
--      todo lo que compartí —obra/empresa/persona— con quién y de qué origen,
--      con revocar. `obras_compartidos_por_mi()`, DEFINER como las de
--      Auditoría: la lista tiene que salir completa aunque un JOIN quede
--      fuera de la RLS del que pregunta.
--
-- REGLA DE ORIGEN — última escritura gana:
--   · compartir por checklist  → setea origen al padre (pisa lo que hubiera)
--   · compartir directo        → limpia origen (queda NULL, no cascadea)
--
-- Errores nuevos: OB026 (solo el responsable comparte/revoca una obra),
-- OB027 (sin acceso a la vista Compartido). Lista blanca `mensajeError`.
--
-- `obras_compartir_empresa` pasa de firma (uuid,uuid) a (uuid,uuid,uuid[]):
-- se dropea la vieja primero (como sql/041 con obras_transferir), sus GRANT
-- se rehacen abajo.
--
-- Sin backfill: 0 filas compartidas al aplicar.
-- ============================================================

-- ============================================================
-- 1. Tabla `obras_obra_compartida`
--
-- UNIQUE entero (no parcial) porque `obras_compartir_obra` hace upsert con
-- ON CONFLICT — revive la fila desactivada en vez de insertar otra. Mismo
-- criterio que las dos tablas `_compartida` de sql/039.
--
-- RLS acotada a las dos puntas (`usuario_id` / `otorgada_por` = auth.uid()),
-- sin EXISTS contra `obras`: la policy de `obras_select` inlinea un EXISTS
-- hacia esta tabla, y dos policies que se miran entre sí dan 42P17 (lección
-- de sql/045). Esta no mira para atrás, así que no recursa.
-- ============================================================
CREATE TABLE IF NOT EXISTS obras_obra_compartida (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id      uuid NOT NULL REFERENCES obras(id),
  usuario_id   uuid NOT NULL REFERENCES usuarios(id),
  otorgada_por uuid NOT NULL REFERENCES usuarios(id),
  activo       boolean DEFAULT true,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now(),
  CONSTRAINT obra_compartida_no_a_si_mismo CHECK (usuario_id <> otorgada_por),
  CONSTRAINT obra_compartida_par_unico UNIQUE (obra_id, usuario_id)
);

CREATE INDEX IF NOT EXISTS idx_obra_compartida_usuario
  ON obras_obra_compartida (usuario_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON obras_obra_compartida;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON obras_obra_compartida
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE obras_obra_compartida ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS obra_compartida_select ON obras_obra_compartida;
CREATE POLICY obra_compartida_select ON obras_obra_compartida FOR SELECT
  USING (usuario_id = auth.uid() OR otorgada_por = auth.uid());

-- Toda escritura pasa por función SECURITY DEFINER: alcanza con SELECT.
GRANT SELECT ON public.obras_obra_compartida TO authenticated;

-- ============================================================
-- 2. Marca de origen en las dos tablas `_compartida` existentes
--
-- Un grant nacido de tildar la relación en el checklist de un padre lleva el
-- id del padre acá. Directo → NULL. La cascada de revocación filtra por esto.
-- ============================================================
ALTER TABLE obras_empresa_compartida
  ADD COLUMN IF NOT EXISTS origen_obra_id uuid REFERENCES obras(id);

ALTER TABLE obras_persona_compartida
  ADD COLUMN IF NOT EXISTS origen_obra_id uuid REFERENCES obras(id);

ALTER TABLE obras_persona_compartida
  ADD COLUMN IF NOT EXISTS origen_empresa_id uuid REFERENCES obras_empresas(id);

-- ============================================================
-- 3. Visibilidad de obra — suma la rama "compartida conmigo"
--
-- `obras_puede_ver_obra` gatea el SELECT de los vínculos (obra↔empresa,
-- obra↔persona, referente). El receptor de una obra compartida ve esos
-- vínculos; el contacto de las personas sigue saliendo solo por
-- `obras_ficha_persona()`, y solo abre la ficha completa de las que además
-- recibieron su propio grant (las tildadas en el checklist).
-- ============================================================
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
        OR (
          public.tiene_permiso('obras_ver')
          AND EXISTS (
            SELECT 1 FROM public.obras_obra_compartida c
            WHERE c.obra_id = o.id AND c.usuario_id = auth.uid() AND c.activo
          )
        )
      )
  );
$$;

DROP POLICY IF EXISTS obras_select ON obras;
CREATE POLICY obras_select ON obras FOR SELECT
  USING (
    (responsable_id = auth.uid() AND tiene_permiso('obras_ver'))
    OR tiene_permiso('obras_transferir')
    OR (
      tiene_permiso('obras_ver')
      AND EXISTS (
        -- `obras.id` calificado: `obras_obra_compartida` también tiene `id` y
        -- lo sombrea, dejando `c.obra_id = c.id` (siempre falso).
        SELECT 1 FROM obras_obra_compartida c
        WHERE c.obra_id = obras.id AND c.usuario_id = auth.uid() AND c.activo
      )
    )
  );

-- ============================================================
-- 3b. Bug preexistente: `obras_empresas_select` (sql/039) nunca dejó ver una
--     empresa por grant directo
--
-- El EXISTS inline salió como `WHERE c.empresa_id = c.id` — `obras_empresas.id`
-- lo sombrea la columna `id` de `obras_empresa_compartida`, así que comparaba
-- la fila del grant contra sí misma (siempre falso). `obras_compartir_empresa`
-- escribía la fila y el receptor seguía sin ver nada; lo tapaba que ningún
-- test ejercía ese camino (model_a solo probó compartir PERSONA). El checklist
-- de sql/047 lo necesita funcionando.
-- ============================================================
DROP POLICY IF EXISTS obras_empresas_select ON obras_empresas;
CREATE POLICY obras_empresas_select ON obras_empresas FOR SELECT
  USING (
    (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
    AND (
      creado_por = auth.uid()
      OR (pendiente AND tiene_permiso('obras_aprobar'))
      OR (
        NOT pendiente
        AND (
          tiene_permiso('obras_empresas_todas')
          OR EXISTS (
            SELECT 1 FROM obras_empresa_compartida c
            WHERE c.empresa_id = obras_empresas.id AND c.usuario_id = auth.uid() AND c.activo
          )
        )
      )
    )
  );

-- ============================================================
-- 4. Buscador global — la obra compartida sale sin enmascarar
-- ============================================================
CREATE OR REPLACE FUNCTION obras_buscar_obras(p_texto text)
RETURNS TABLE (tipo text, id uuid, titulo text, subtitulo text, es_ajeno boolean, duenio text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  WITH patron AS (
    SELECT '%' || obras_normalizar(p_texto) || '%' AS contiene,
           obras_normalizar(p_texto) || '%'        AS empieza
    WHERE length(obras_normalizar(p_texto)) >= 2
  ),
  vis AS (
    SELECT o.id, o.nombre, o.nombre_norm, o.direccion, o.localidad,
           (
             o.responsable_id = auth.uid()
             OR tiene_permiso('obras_transferir')
             OR EXISTS (
               SELECT 1 FROM obras_obra_compartida c
               WHERE c.obra_id = o.id AND c.usuario_id = auth.uid() AND c.activo
             )
           ) AS puede,
           u.nombre AS resp
    FROM patron x
    JOIN obras o ON o.activo
      AND (o.nombre_norm LIKE x.contiene OR o.direccion_norm LIKE x.contiene OR o.localidad_norm LIKE x.contiene)
    JOIN usuarios u ON u.id = o.responsable_id
    WHERE tiene_permiso('obras_ver')
  )
  SELECT 'obra'::text,
         CASE WHEN v.puede THEN v.id END,
         v.nombre,
         CASE WHEN v.puede THEN nullif(concat_ws(' · ', v.direccion, v.localidad), '') END,
         NOT v.puede,
         CASE WHEN NOT v.puede THEN v.resp END
  FROM vis v, patron x
  ORDER BY NOT v.puede, (v.nombre_norm NOT LIKE x.empieza), v.nombre
  LIMIT 5;
$$;

-- ============================================================
-- 5. obras_compartir_obra — nueva, con checklist
-- ============================================================
CREATE OR REPLACE FUNCTION obras_compartir_obra(
  p_obra_id    uuid,
  p_usuario_id uuid,
  p_empresas   uuid[] DEFAULT '{}',
  p_personas   uuid[] DEFAULT '{}'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte una obra a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id AND o.responsable_id = auth.uid() AND o.activo
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario_id AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  INSERT INTO obras_obra_compartida (obra_id, usuario_id, otorgada_por, activo)
  VALUES (p_obra_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (obra_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now();

  -- Empresas tildadas: vinculadas a esta obra y mías. Grant completo con
  -- origen = esta obra (última escritura gana: si ya estaba compartida por
  -- otra vía, ahora cuelga de acá).
  INSERT INTO obras_empresa_compartida
    (empresa_id, usuario_id, otorgada_por, activo, origen_obra_id)
  SELECT DISTINCT oe.empresa_id, p_usuario_id, auth.uid(), true, p_obra_id
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo
    AND oe.empresa_id = ANY(p_empresas)
  ON CONFLICT (empresa_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = p_obra_id;

  -- Personas tildadas: vinculadas a esta obra y mías (no congeladas).
  INSERT INTO obras_persona_compartida
    (persona_id, usuario_id, otorgada_por, activo, origen_obra_id)
  SELECT DISTINCT op.persona_id, p_usuario_id, auth.uid(), true, p_obra_id
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    AND op.persona_id = ANY(p_personas)
  ON CONFLICT (persona_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = p_obra_id, origen_empresa_id = NULL;
END;
$$;

-- ============================================================
-- 6. obras_compartir_empresa — +checklist de personas (firma nueva)
-- ============================================================
DROP FUNCTION IF EXISTS obras_compartir_empresa(uuid, uuid);

CREATE OR REPLACE FUNCTION obras_compartir_empresa(
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_personas   uuid[] DEFAULT '{}'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte una empresa a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM obras_empresas e
    WHERE e.id = p_empresa_id AND e.creado_por = auth.uid()
      AND e.activo AND NOT e.pendiente
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario_id AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  -- Compartir directo la empresa: limpia el origen (deja de colgar de una obra).
  INSERT INTO obras_empresa_compartida (empresa_id, usuario_id, otorgada_por, activo)
  VALUES (p_empresa_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (empresa_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = NULL;

  -- Personas tildadas: empleadas en esta empresa y mías. Grant completo con
  -- origen = esta empresa.
  INSERT INTO obras_persona_compartida
    (persona_id, usuario_id, otorgada_por, activo, origen_empresa_id)
  SELECT DISTINCT pe.persona_id, p_usuario_id, auth.uid(), true, p_empresa_id
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
    AND pe.persona_id = ANY(p_personas)
  ON CONFLICT (persona_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_empresa_id = p_empresa_id, origen_obra_id = NULL;
END;
$$;

-- ============================================================
-- 7. obras_compartir_persona — sin checklist, pero limpia el origen
--
-- Compartir una persona directo la vuelve independiente: si venía colgada de
-- una obra/empresa por checklist, deja de caerse con ese padre.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_compartir_persona(p_persona_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte una persona a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM obras_personas p
    WHERE p.id = p_persona_id AND p.creado_por = auth.uid()
      AND p.activo AND NOT p.pendiente
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la persona puede compartirla' USING ERRCODE = 'OB020';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario_id AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  INSERT INTO obras_persona_compartida (persona_id, usuario_id, otorgada_por, activo)
  VALUES (p_persona_id, p_usuario_id, auth.uid(), true)
  ON CONFLICT (persona_id, usuario_id)
  DO UPDATE SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
                origen_obra_id = NULL, origen_empresa_id = NULL;
END;
$$;

-- ============================================================
-- 8. Revocar — cascada por origen
-- ============================================================
CREATE OR REPLACE FUNCTION obras_revocar_obra(p_obra_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

  -- Lo que se compartió tildándolo en el checklist de esta obra cae con ella.
  -- Un grant directo (origen NULL) o colgado de otro padre no se toca.
  UPDATE obras_empresa_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;

  UPDATE obras_persona_compartida
    SET activo = false, updated_at = now()
    WHERE origen_obra_id = p_obra_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;
END;
$$;

CREATE OR REPLACE FUNCTION obras_revocar_empresa(p_empresa_id uuid, p_usuario_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras_empresas e WHERE e.id = p_empresa_id AND e.creado_por = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la empresa puede revocar el acceso' USING ERRCODE = 'OB020';
  END IF;

  UPDATE obras_empresa_compartida
    SET activo = false, updated_at = now()
    WHERE empresa_id = p_empresa_id AND usuario_id = p_usuario_id AND activo;

  -- Personas que se compartieron tildándolas en el checklist de esta empresa.
  UPDATE obras_persona_compartida
    SET activo = false, updated_at = now()
    WHERE origen_empresa_id = p_empresa_id AND usuario_id = p_usuario_id
      AND otorgada_por = auth.uid() AND activo;
END;
$$;

-- ============================================================
-- 9. Checklist — qué relaciones mías puedo compartir con este usuario
--
-- DEFINER STABLE como `obras_contactos_exclusivos_de_*`: identidad mínima,
-- nunca contacto. `ya_compartida` marca las que ese usuario ya tiene (para
-- venir tildadas y no re-otorgar).
-- ============================================================
CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_obra(
  p_obra_id uuid, p_usuario_id uuid
)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text, ya_compartida boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras WHERE id = p_obra_id AND responsable_id = auth.uid() AND activo
  ) THEN
    RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
  END IF;

  RETURN QUERY
  SELECT 'empresa'::text, e.id, e.razon_social,
         nullif(array_to_string(oe.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_empresa_compartida c
                 WHERE c.empresa_id = e.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_obra_empresa oe
  JOIN obras_empresas e ON e.id = oe.empresa_id
  WHERE oe.obra_id = p_obra_id AND oe.activo
    AND e.creado_por = auth.uid() AND e.activo
  UNION ALL
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         nullif(array_to_string(op.roles::text[], ', '), ''),
         EXISTS (SELECT 1 FROM obras_persona_compartida c
                 WHERE c.persona_id = p.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_obra_persona op
  JOIN obras_personas p ON p.id = op.persona_id
  WHERE op.obra_id = p_obra_id AND op.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente;
END;
$$;

CREATE OR REPLACE FUNCTION obras_relaciones_compartibles_empresa(
  p_empresa_id uuid, p_usuario_id uuid
)
RETURNS TABLE (tipo text, id uuid, etiqueta text, detalle text, ya_compartida boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM obras_empresas WHERE id = p_empresa_id AND creado_por = auth.uid() AND activo
  ) THEN
    RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
  END IF;

  RETURN QUERY
  SELECT 'persona'::text, p.id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         nullif(pe.cargo, ''),
         EXISTS (SELECT 1 FROM obras_persona_compartida c
                 WHERE c.persona_id = p.id AND c.usuario_id = p_usuario_id AND c.activo)
  FROM obras_persona_empresa pe
  JOIN obras_personas p ON p.id = pe.persona_id
  WHERE pe.empresa_id = p_empresa_id AND pe.activo
    AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente;
END;
$$;

-- ============================================================
-- 10. Vista Compartido — todo lo que compartí, en un lugar
--
-- DEFINER como las de Auditoría: los JOIN a obras/empresas/personas/usuarios
-- tienen que resolver aunque el que pregunta no vea alguna fila por RLS —con
-- INNER JOIN, una fila fuera de alcance haría desaparecer la línea entera.
-- Solo devuelve lo propio (`otorgada_por = auth.uid()`).
-- ============================================================
CREATE OR REPLACE FUNCTION obras_compartidos_por_mi()
RETURNS TABLE (
  tipo           text,
  entidad_id     uuid,
  entidad_nombre text,
  usuario_id     uuid,
  usuario_nombre text,
  origen         text,
  compartida_el  timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_compartido') THEN
    RAISE EXCEPTION 'Sin acceso a la vista Compartido' USING ERRCODE = 'OB027';
  END IF;

  RETURN QUERY
  SELECT 'obra'::text, c.obra_id, o.nombre, c.usuario_id, u.nombre,
         'directo'::text, c.created_at
  FROM obras_obra_compartida c
  JOIN obras o     ON o.id = c.obra_id
  JOIN usuarios u  ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'empresa'::text, c.empresa_id, e.razon_social, c.usuario_id, u.nombre,
         CASE WHEN c.origen_obra_id IS NOT NULL
              THEN 'obra: ' || coalesce((SELECT nombre FROM obras WHERE id = c.origen_obra_id), '—')
              ELSE 'directo' END,
         c.created_at
  FROM obras_empresa_compartida c
  JOIN obras_empresas e ON e.id = c.empresa_id
  JOIN usuarios u       ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  UNION ALL
  SELECT 'persona'::text, c.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         c.usuario_id, u.nombre,
         CASE
           WHEN c.origen_obra_id IS NOT NULL
             THEN 'obra: ' || coalesce((SELECT nombre FROM obras WHERE id = c.origen_obra_id), '—')
           WHEN c.origen_empresa_id IS NOT NULL
             THEN 'empresa: ' || coalesce((SELECT razon_social FROM obras_empresas WHERE id = c.origen_empresa_id), '—')
           ELSE 'directo'
         END,
         c.created_at
  FROM obras_persona_compartida c
  JOIN obras_personas p ON p.id = c.persona_id
  JOIN usuarios u       ON u.id = c.usuario_id
  WHERE c.otorgada_por = auth.uid() AND c.activo

  ORDER BY 7 DESC
  LIMIT 500;
END;
$$;

-- ============================================================
-- 11. GRANTs
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.obras_compartir_obra(uuid, uuid, uuid[], uuid[])       FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_compartir_empresa(uuid, uuid, uuid[])            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_compartir_persona(uuid, uuid)                    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_revocar_obra(uuid, uuid)                         FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_revocar_empresa(uuid, uuid)                      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_relaciones_compartibles_obra(uuid, uuid)         FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_relaciones_compartibles_empresa(uuid, uuid)      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_compartidos_por_mi()                             FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.obras_compartir_obra(uuid, uuid, uuid[], uuid[])        TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_compartir_empresa(uuid, uuid, uuid[])             TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_compartir_persona(uuid, uuid)                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_revocar_obra(uuid, uuid)                          TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_revocar_empresa(uuid, uuid)                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_relaciones_compartibles_obra(uuid, uuid)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_relaciones_compartibles_empresa(uuid, uuid)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_compartidos_por_mi()                              TO authenticated;

-- ============================================================
-- 12. Submódulo de la vista nueva
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden) VALUES
  ('obras_compartido', 'obras', 'vista', 'Compartido', 6)
ON CONFLICT (codigo) WHERE activo DO NOTHING;
