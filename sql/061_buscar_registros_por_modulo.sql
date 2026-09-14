-- ============================================================
-- 061 — "Relacionar" elige el módulo primero
--
-- Pedido del usuario el 2026-09-14 (fase A de PLAN_TAREAS_VINCULOS.md): el
-- buscador de "Relacionar" no busca en todos los módulos a la vez — primero
-- se elige el módulo (toggle) y recién ahí aparecen sus registros.
--
-- `buscar_registros(text)` pasa a `buscar_registros(p_modulo text, p_texto
-- text)`, con la misma salida de sql/059. Cambia el tipo de retorno de un
-- parámetro (agrega uno), así que se dropea antes de recrear.
-- Ver decisiones/tareas/integracion.md → "El buscador de Relacionar elige
-- módulo primero".
-- ============================================================

DROP FUNCTION IF EXISTS buscar_registros(text);

-- "Relacionar": lo que encuentra el buscador del módulo elegido y quien
-- busca puede abrir. Un módulo que registre entes suma su rama, igual que
-- `etiqueta_registro` y `relacionados_de_registro`. La lista de módulos no
-- necesita función propia: sale de `entes` bajo RLS (`getModulosRelacionables`).
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
  END IF;
END;
$$;

-- ============================================================
-- GRANTs — misma firma nueva
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.buscar_registros(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_registros(text, text) TO authenticated;
