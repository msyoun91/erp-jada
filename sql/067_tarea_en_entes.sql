-- ============================================================
-- 067 — `tarea` entra a `entes`
--
-- BACKLOG.md → "Tareas sobre el modelo de entes". Hasta acá una tarea podía
-- apuntar a una obra, pero nada podía apuntar a una tarea: no tenía etiqueta,
-- ni "quién la puede abrir", ni buscador.
--
--   1. La visibilidad de una tarea y de un hilo, por usuario explícito. La
--      policy `tareas_select` pasa a llamarla: la regla se escribe una vez.
--   2. Las ramas del módulo: `tareas_etiqueta`, `tareas_puede_abrir`,
--      `tareas_buscar`.
--   3. La fila en `entes` y la rama en las tres genéricas.
--   4. Una tarea no se relaciona consigo misma.
--
-- Una tarea no se comparte (decidido el 2026-09-16): sin rama en
-- `puede_compartir_registro` ni en `compartir_registros`, que ya devuelven
-- false y no hacen nada para un módulo que no está en su CASE.
-- Ver decisiones/tareas/integracion.md → "Tarea en entes".
-- ============================================================

-- ============================================================
-- 1. Visibilidad por usuario explícito
--
-- Los cuerpos vigentes de `puede_ver_hilo` (sql/013) y de la policy
-- `tareas_select` (sql/035), con auth.uid() -> p_usuario y
-- tiene_permiso(x) -> usuario_tiene_permiso(p_usuario, x).
-- ============================================================
CREATE OR REPLACE FUNCTION puede_ver_hilo_de(p_hilo_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    usuario_tiene_permiso(p_usuario, 'tareas_gestionar_ajenas')
    OR h.responsable_id = p_usuario
    OR EXISTS (
      SELECT 1 FROM tareas t
      JOIN tareas_asignados ta ON ta.tarea_id = t.id AND ta.activo
      WHERE t.hilo_id = h.id AND ta.usuario_id = p_usuario
    )
    OR (
      h.proyecto_id IS NOT NULL AND h.visibilidad = 'publico'
      AND (
        (SELECT pr.visibilidad FROM tareas_proyectos pr WHERE pr.id = h.proyecto_id) = 'publico'
        OR es_miembro_proyecto(h.proyecto_id, p_usuario)
      )
    )
  FROM tareas_hilos h
  WHERE h.id = p_hilo_id;
$$;

CREATE OR REPLACE FUNCTION puede_ver_hilo(p_hilo_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT puede_ver_hilo_de(p_hilo_id, auth.uid()); $$;

-- Recibe las columnas y no solo el id: en un UPDATE la policy de SELECT se
-- evalúa también sobre la fila nueva, y releer `tareas` por id devolvería la
-- vieja. Así la policy sigue decidiendo sobre lo que queda escrito.
CREATE OR REPLACE FUNCTION tareas_puede_ver_tarea_de(
  p_id          uuid,
  p_hilo_id     uuid,
  p_visibilidad visibilidad,
  p_proyecto_id uuid,
  p_usuario     uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    usuario_tiene_permiso(p_usuario, 'tareas_gestionar_ajenas')
    OR EXISTS (
      SELECT 1 FROM tareas_asignados ta
      WHERE ta.tarea_id = p_id AND ta.usuario_id = p_usuario AND ta.activo
    )
    OR (p_hilo_id IS NOT NULL AND puede_ver_hilo_de(p_hilo_id, p_usuario))
    OR (
      p_hilo_id IS NULL AND p_visibilidad = 'publico'
      AND (
        p_proyecto_id IS NULL
        OR (SELECT pr.visibilidad FROM tareas_proyectos pr WHERE pr.id = p_proyecto_id) = 'publico'
        OR es_miembro_proyecto(p_proyecto_id, p_usuario)
      )
    );
$$;

CREATE OR REPLACE FUNCTION tareas_puede_ver_tarea(
  p_id          uuid,
  p_hilo_id     uuid,
  p_visibilidad visibilidad,
  p_proyecto_id uuid
)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT tareas_puede_ver_tarea_de(p_id, p_hilo_id, p_visibilidad, p_proyecto_id, auth.uid()); $$;

ALTER POLICY tareas_select ON public.tareas
  USING (tareas_puede_ver_tarea(id, hilo_id, visibilidad, proyecto_id));

-- ============================================================
-- 2. Las ramas del módulo
-- ============================================================
-- INVOKER: decide `tareas_select`. Una tarea desactivada no existe.
CREATE OR REPLACE FUNCTION tareas_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'tarea' THEN (SELECT t.titulo FROM tareas t WHERE t.id = p_id AND t.activo)
  END;
$$;

CREATE OR REPLACE FUNCTION tareas_puede_abrir(p_tipo text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'tarea' THEN (
      SELECT tareas_puede_ver_tarea_de(t.id, t.hilo_id, t.visibilidad, t.proyecto_id, p_usuario)
      FROM tareas t
      WHERE t.id = p_id AND t.activo
    )
  END;
$$;

-- INVOKER: solo lo que quien busca ve. Normaliza igual que el buscador de
-- Obras, para que "Relacionar" encuentre con el mismo criterio en los dos
-- módulos. Lo pendiente primero, después lo que empieza con el texto.
CREATE OR REPLACE FUNCTION tareas_buscar(p_texto text)
RETURNS TABLE (tipo text, id uuid, titulo text, subtitulo text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH patron AS (
    SELECT '%' || obras_normalizar(p_texto) || '%' AS contiene,
           obras_normalizar(p_texto) || '%'        AS empieza
    WHERE length(obras_normalizar(p_texto)) >= 2
  )
  SELECT 'tarea'::text, t.id, t.titulo, COALESCE(h.titulo, p.nombre)
  FROM patron x
  JOIN tareas t ON t.activo AND obras_normalizar(t.titulo) LIKE x.contiene
  LEFT JOIN tareas_hilos h ON h.id = t.hilo_id
  LEFT JOIN tareas_proyectos p ON p.id = COALESCE(t.proyecto_id, h.proyecto_id)
  ORDER BY t.estado IN ('completada', 'cancelada'),
           obras_normalizar(t.titulo) NOT LIKE x.empieza,
           t.created_at DESC
  LIMIT 10;
$$;

-- ============================================================
-- 3. El catálogo y las genéricas
-- ============================================================
-- Sin `estados`: no hay trigger sobre `tareas.estado`, y con el enum
-- `guardar_plantilla` aceptaría un disparo que nunca corre.
INSERT INTO entes (codigo, modulo, submodulo, estados, datos, ruta)
VALUES ('tarea', 'tareas', 'tareas_lista', NULL, '{}', '/tareas?tarea={id}')
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION etiqueta_registro(p_ente text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE e.modulo
           WHEN 'obras'  THEN obras_etiqueta(e.codigo, p_id)
           WHEN 'tareas' THEN tareas_etiqueta(e.codigo, p_id)
         END
  FROM entes e
  WHERE e.codigo = p_ente;
$$;

CREATE OR REPLACE FUNCTION puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT e.activo
       AND usuario_tiene_permiso(p_usuario, e.submodulo)
       AND CASE e.modulo
             WHEN 'obras'  THEN obras_puede_abrir(e.codigo, p_id, p_usuario)
             WHEN 'tareas' THEN tareas_puede_abrir(e.codigo, p_id, p_usuario)
           END
     FROM entes e
     WHERE e.codigo = p_ente),
    false
  );
$$;

CREATE OR REPLACE FUNCTION buscar_registros(p_modulo text, p_texto text)
RETURNS TABLE (
  ente        text,
  registro_id uuid,
  etiqueta    text,
  detalle     text,
  href        text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_modulo = 'obras' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM obras_buscar(p_texto) b
      JOIN entes e ON e.codigo = b.tipo
      WHERE b.id IS NOT NULL AND NOT b.es_ajeno;
  ELSIF p_modulo = 'tareas' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM tareas_buscar(p_texto) b
      JOIN entes e ON e.codigo = b.tipo;
  END IF;
END;
$$;

-- ============================================================
-- 4. Una tarea no se relaciona consigo misma
-- ============================================================
ALTER TABLE tareas_vinculos
  DROP CONSTRAINT IF EXISTS tareas_vinculos_no_a_si_misma,
  ADD CONSTRAINT tareas_vinculos_no_a_si_misma
    CHECK (ente <> 'tarea' OR registro_id <> tarea_id);

-- ============================================================
-- 5. GRANTs — las `_de` solo las llaman otras DEFINER; el envoltorio lo llama
-- la policy, y etiqueta y buscar, las genéricas INVOKER.
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.puede_ver_hilo_de(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_tarea_de(uuid, uuid, visibilidad, uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tareas_puede_abrir(text, uuid, uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_tarea(uuid, uuid, visibilidad, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tareas_etiqueta(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tareas_buscar(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tareas_puede_ver_tarea(uuid, uuid, visibilidad, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tareas_etiqueta(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tareas_buscar(text) TO authenticated;
