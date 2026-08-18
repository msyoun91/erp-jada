-- Endurecimiento post-advisors de sql/005_tareas.sql (ya corrido en Supabase
-- vía MCP — este archivo es el registro para el repo).
-- 1) Funciones SECURITY DEFINER de solo-trigger no necesitan ser invocables
--    vía RPC por nadie (PostgREST expone toda función con EXECUTE a PUBLIC
--    por default). puede_ver_hilo sí la necesita `authenticated` porque las
--    policies de RLS la invocan para ese rol.
-- 2) Índices en FKs creado_por/responsable_id sin cobertura (advisor perf).

REVOKE EXECUTE ON FUNCTION public.generar_recurrencia() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.log_evento_tarea() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reabrir_hilo_en_tarea() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validar_cierre_hilo() FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.puede_ver_hilo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.puede_ver_hilo(uuid) TO authenticated;

-- es_creador_proyecto / es_responsable_o_creador_tarea / es_asignado_tarea:
-- agregadas post-005 para romper recursión de RLS (ver DECISIONES.md).
-- Mismo criterio que puede_ver_hilo: las invoca RLS para `authenticated`.
REVOKE EXECUTE ON FUNCTION public.es_creador_proyecto(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.es_creador_proyecto(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.es_responsable_o_creador_tarea(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.es_responsable_o_creador_tarea(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.es_asignado_tarea(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.es_asignado_tarea(uuid) TO authenticated;

CREATE INDEX IF NOT EXISTS idx_tareas_creado_por ON public.tareas (creado_por);
CREATE INDEX IF NOT EXISTS idx_tareas_hilos_creado_por ON public.tareas_hilos (creado_por);
CREATE INDEX IF NOT EXISTS idx_tareas_hilos_responsable_id ON public.tareas_hilos (responsable_id);
CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_creado_por ON public.tareas_plantillas (creado_por);
CREATE INDEX IF NOT EXISTS idx_tareas_proyectos_creado_por ON public.tareas_proyectos (creado_por);
CREATE INDEX IF NOT EXISTS idx_tareas_proyectos_miembros_usuario_id ON public.tareas_proyectos_miembros (usuario_id);
