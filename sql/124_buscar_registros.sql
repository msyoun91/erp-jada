-- sql/124 — "Relacionar": `buscar_registros` y la rama de tareas.
--
-- El botón "Relacionar" de la descripción del paso elige primero el módulo y
-- después busca en `buscar_registros(p_modulo, p_texto)`: lo que quien escribe
-- ve (INVOKER, la RLS recorta), para insertar `{ente:uuid|nombre}`. Un módulo
-- con entes suma su rama, igual que en `etiqueta_registro`. La lista de
-- módulos no necesita función: sale de `entes` bajo RLS.
-- Decisión: `decisiones/tareas/registro.md` → *"Relacionar": primero el
-- módulo*. Verificado con `sql/tests/tareas_buscar.sql`.

-- ============================================================
-- 1. La rama de tareas: hilos y pasos activos cuyo título contiene el texto
-- ============================================================
-- `strpos` y no LIKE: el texto no se escapa. Lo abierto primero, después lo
-- que empieza con el texto, después lo reciente.
CREATE OR REPLACE FUNCTION public.tareas_buscar(p_texto text)
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
    SELECT 'hilo'::text AS tipo, h.id, h.titulo, NULL::text AS subtitulo,
           h.estado = 'cerrado' AS cerrado, strpos(lower(h.titulo), q.t) AS pos, h.created_at
    FROM q JOIN public.tareas_hilos h ON h.activo AND strpos(lower(h.titulo), q.t) > 0
    UNION ALL
    SELECT 'tarea', t.id, t.titulo, h.titulo,
           t.estado IN ('completada', 'cancelada'), strpos(lower(t.titulo), q.t), t.created_at
    FROM q
    JOIN public.tareas t ON t.activo AND strpos(lower(t.titulo), q.t) > 0
    JOIN public.tareas_hilos h ON h.id = t.hilo_id
  )
  SELECT tipo, id, titulo, subtitulo
  FROM encontrados
  ORDER BY cerrado, pos <> 1, created_at DESC
  LIMIT 15;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_buscar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_buscar(text) TO authenticated;

-- ============================================================
-- 2. La genérica
-- ============================================================
-- El JOIN con `entes` (RLS: activo y con el submódulo de la ficha) deja
-- afuera lo que quien busca no podría abrir.
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
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.buscar_registros(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buscar_registros(text, text) TO authenticated;
