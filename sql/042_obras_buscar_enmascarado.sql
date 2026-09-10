-- ============================================================
-- 042 — Agenda de Obras: el buscador enmascara, no esconde
--
-- Con las tres entidades privadas por dueño, un `SELECT` bajo RLS solo
-- encuentra lo propio. El usuario pidió que el buscador (global y el aviso de
-- duplicados del alta) muestre lo ajeno **enmascarado**: identidad mínima + el
-- nombre del dueño, sin link, sin ficha. Alcanza para no cargarlo dos veces y
-- para ir a preguntar; no para leer la agenda del otro.
--
-- CAMBIOS
--   - `obras_buscar_duplicados_obra`: la obra ajena ahora devuelve `nombre`
--     (antes NULL). Dirección y localidad siguen NULL; `obra_id` también, para
--     que la UI no la enlace.
--   - `obras_buscar_duplicados_empresa`: pasa a DEFINER y enmascara — la empresa
--     ajena devuelve `razon_social` y el nombre de quien la cargó, nada más.
--     Antes era INVOKER (con empresas globales alcanzaba); ahora sin esto el
--     alta que el trigger congela no tendría aviso en el formulario.
--   - `obras_buscar` (global): las tres ramas pasan por funciones DEFINER que
--     devuelven la misma forma —`es_ajeno` + `duenio`—. La obra/empresa ajena
--     ya no desaparece: aparece enmascarada. `visible`/`cargada_por` se
--     reemplazan por `es_ajeno`/`duenio` en las tres.
-- ============================================================

-- ============================================================
-- 1. Aviso ciego de obra — ahora con el nombre
-- ============================================================
CREATE OR REPLACE FUNCTION obras_buscar_duplicados_obra(
  p_nombre     text,
  p_direccion  text DEFAULT NULL,
  p_localidad  text DEFAULT NULL,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  es_mia       boolean,
  obra_id      uuid,
  nombre       text,
  direccion    text,
  localidad    text,
  responsable  text
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT o.responsable_id = auth.uid(),
         CASE WHEN o.responsable_id = auth.uid() THEN o.id END,
         o.nombre,
         CASE WHEN o.responsable_id = auth.uid() THEN o.direccion END,
         CASE WHEN o.responsable_id = auth.uid() THEN o.localidad END,
         u.nombre
  FROM obras_similares_obra(p_nombre, p_direccion, p_localidad, p_excluir_id) s
  JOIN obras o    ON o.id = s.obra_id
  JOIN usuarios u ON u.id = o.responsable_id
  WHERE tiene_permiso('obras_ver')
  ORDER BY s.misma_localidad DESC, s.score DESC;
$$;

-- ============================================================
-- 2. Aviso de empresa — DEFINER y enmascarado
--
-- Cambia la forma de salida (suma `es_mia` y `cargada_por`), así que se dropea
-- primero — `CREATE OR REPLACE` no cambia el tipo de retorno.
-- ============================================================
DROP FUNCTION IF EXISTS obras_buscar_duplicados_empresa(text, text, uuid);

CREATE OR REPLACE FUNCTION obras_buscar_duplicados_empresa(
  p_razon_social      text,
  p_nombre_comercial  text DEFAULT NULL,
  p_excluir_id        uuid DEFAULT NULL
)
RETURNS TABLE (
  es_mia            boolean,
  empresa_id        uuid,
  razon_social      text,
  nombre_comercial  text,
  localidad         text,
  cargada_por       text
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT obras_puede_ver_empresa(e.id),
         CASE WHEN obras_puede_ver_empresa(e.id) THEN e.id END,
         e.razon_social,
         CASE WHEN obras_puede_ver_empresa(e.id) THEN e.nombre_comercial END,
         CASE WHEN obras_puede_ver_empresa(e.id) THEN e.localidad END,
         u.nombre
  FROM obras_similares_empresa(p_razon_social, p_nombre_comercial, p_excluir_id) s
  JOIN obras_empresas e ON e.id = s.empresa_id
  LEFT JOIN usuarios u  ON u.id = e.creado_por
  WHERE (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
  ORDER BY s.score DESC;
$$;

-- ============================================================
-- 3. Buscador global — tres ramas, misma forma, enmascarado
--
-- `obras_buscar` y `obras_buscar_personas` cambian de columnas de salida
-- (`visible`/`cargada_por` → `es_ajeno`/`duenio`), así que se dropean primero.
-- `obras_buscar` cuelga de `obras_buscar_personas`: ese orden.
-- ============================================================
DROP FUNCTION IF EXISTS obras_buscar(text);
DROP FUNCTION IF EXISTS obras_buscar_personas(text);

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
           (o.responsable_id = auth.uid() OR tiene_permiso('obras_transferir')) AS puede,
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

CREATE OR REPLACE FUNCTION obras_buscar_empresas(p_texto text)
RETURNS TABLE (tipo text, id uuid, titulo text, subtitulo text, es_ajeno boolean, duenio text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  WITH patron AS (
    SELECT '%' || obras_normalizar(p_texto) || '%' AS contiene,
           obras_normalizar(p_texto) || '%'        AS empieza
    WHERE length(obras_normalizar(p_texto)) >= 2
  ),
  vis AS (
    SELECT e.id, e.razon_social, e.razon_social_norm, e.nombre_comercial, e.localidad,
           obras_puede_ver_empresa(e.id) AS puede,
           u.nombre AS creador
    FROM patron x
    JOIN obras_empresas e ON e.activo
      AND (e.razon_social_norm LIKE x.contiene OR e.nombre_comercial_norm LIKE x.contiene)
    LEFT JOIN usuarios u ON u.id = e.creado_por
    WHERE (tiene_permiso('obras_ver') OR tiene_permiso('obras_empresas'))
      AND (NOT e.pendiente OR e.creado_por = auth.uid())
  )
  SELECT 'empresa'::text,
         CASE WHEN v.puede THEN v.id END,
         v.razon_social,
         CASE WHEN v.puede THEN nullif(concat_ws(' · ', v.nombre_comercial, v.localidad), '') END,
         NOT v.puede,
         CASE WHEN NOT v.puede THEN v.creador END
  FROM vis v, patron x
  ORDER BY NOT v.puede, (v.razon_social_norm NOT LIKE x.empieza), v.razon_social
  LIMIT 5;
$$;

CREATE OR REPLACE FUNCTION obras_buscar_personas(p_texto text)
RETURNS TABLE (tipo text, id uuid, titulo text, subtitulo text, es_ajeno boolean, duenio text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  WITH patron AS (
    SELECT '%' || obras_normalizar(p_texto) || '%' AS contiene,
           obras_normalizar(p_texto) || '%'        AS empieza
    WHERE length(obras_normalizar(p_texto)) >= 2
  ),
  vis AS (
    SELECT p.id, p.nombre, p.apellido, p.nombre_norm,
           obras_puede_ver_persona(p.id) AS puede,
           u.nombre AS creador
    FROM patron x
    JOIN obras_personas p ON p.activo AND p.nombre_norm LIKE x.contiene
    LEFT JOIN usuarios u ON u.id = p.creado_por
    WHERE (tiene_permiso('obras_ver') OR tiene_permiso('obras_personas'))
      AND (NOT p.pendiente OR p.creado_por = auth.uid())
  )
  SELECT 'persona'::text,
         CASE WHEN v.puede THEN v.id END,
         btrim(v.nombre || ' ' || coalesce(v.apellido, '')),
         (
           SELECT e.razon_social
           FROM obras_persona_empresa pe
           JOIN obras_empresas e ON e.id = pe.empresa_id AND e.activo
           WHERE pe.persona_id = v.id AND pe.activo
           ORDER BY pe.es_principal DESC
           LIMIT 1
         ),
         NOT v.puede,
         CASE WHEN NOT v.puede THEN v.creador END
  FROM vis v, patron x
  ORDER BY NOT v.puede, (v.nombre_norm NOT LIKE x.empieza), v.nombre_norm
  LIMIT 5;
$$;

CREATE OR REPLACE FUNCTION obras_buscar(p_texto text)
RETURNS TABLE (
  tipo      text,
  id        uuid,
  titulo    text,
  subtitulo text,
  es_ajeno  boolean,
  duenio    text
)
LANGUAGE sql STABLE SET search_path = public
AS $$
  WITH r AS (
    SELECT * FROM obras_buscar_obras(p_texto)
    UNION ALL
    SELECT * FROM obras_buscar_empresas(p_texto)
    UNION ALL
    SELECT * FROM obras_buscar_personas(p_texto)
  )
  SELECT r.tipo, r.id, r.titulo, r.subtitulo, r.es_ajeno, r.duenio
  FROM r
  ORDER BY CASE r.tipo WHEN 'obra' THEN 1 WHEN 'empresa' THEN 2 ELSE 3 END,
           r.es_ajeno, r.titulo;
$$;

-- ============================================================
-- 4. Superficie RPC
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.obras_buscar(text)          FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_buscar_obras(text)    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_buscar_empresas(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_buscar_personas(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_buscar(text)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_buscar_obras(text)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_buscar_empresas(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_buscar_personas(text) TO authenticated;
