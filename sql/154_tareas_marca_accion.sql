-- sql/154 — tareas: la marca `{@accion|texto}` en la descripción del paso.
--
-- Vale solo en la descripción de un paso con "se completa cuando": la acción
-- sale de esa condición. La base no la resuelve (`tareas_plantilla_texto` no
-- la toca) y pasa tal cual al paso; la pantalla la vuelve link a la ficha del
-- registro del hilo con `?vincular={rol}` o `?estado={valor}`, según lo que
-- quien lee ve y trabaja. `tareas_plantillas_paso_vale` la suma a lo que
-- validan los dos triggers (TA024).
--
-- Decisión: `decisiones/tareas/catalogo.md` → *El link de acción es una marca
-- de la descripción*.

CREATE OR REPLACE FUNCTION public.tareas_plantillas_paso_vale(p_sobre text, p_condicion text,
                                                             p_completa_evento public.tipo_evento, p_completa_valor text,
                                                             p_titulo text, p_descripcion text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (p_condicion IS NULL OR public.tareas_plantilla_vale(p_sobre, 'relacion_alta', ltrim(p_condicion, '!')))
     AND (p_completa_evento IS NULL OR public.tareas_plantilla_vale(p_sobre, p_completa_evento, p_completa_valor))
     AND public.tareas_plantilla_marcas_valen(p_sobre, p_titulo, p_descripcion)
     AND coalesce(p_titulo, '') !~ '\{@accion\|'
     AND (coalesce(p_descripcion, '') !~ '\{@accion\|'
          OR (p_completa_evento IS NOT NULL
              AND coalesce(p_descripcion, '') !~ '\{@accion\|[^{}]*(\{|$)'
              AND coalesce(p_descripcion, '') !~ '\{@accion\|\}'));
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantillas_paso_vale(text, text, public.tipo_evento, text, text, text) FROM PUBLIC, anon, authenticated;
