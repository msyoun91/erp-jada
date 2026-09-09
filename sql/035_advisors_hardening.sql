-- ============================================================
-- 035 — Hardening de advisors (sin cambio de semántica)
--
-- Tres bloques, ninguno toca reglas de negocio:
--   A. auth.uid() envuelto en (select ...) en las 35 policies que lo usan
--   B. superficie RPC: trigger functions y tiene_permiso fuera del API público
--   C. search_path fijo + índices de cobertura para FK
--
-- Corrida vía MCP como migración `advisors_hardening`. Después: rls_obras 29/29,
-- rls_visibilidad_tareas 17/17, perfil_propio + usuarios_activo 6/6.
--
-- A es lo único con impacto medible. Postgres trata auth.uid() como VOLATILE
-- y lo re-evalúa por fila; envuelto en un subselect lo evalúa una vez como
-- InitPlan. Con las tablas chicas de hoy no se nota — a 100k filas sí.
-- ============================================================

-- ============================================================
-- A — RLS: auth.uid() → (select auth.uid())
--
-- ALTER POLICY y no DROP+CREATE: reemplaza la expresión in place, sin
-- ventana donde la tabla quede sin política.
-- ============================================================

ALTER POLICY obras_insert ON public.obras
  WITH CHECK ((tiene_permiso('obras_crear'::text) AND (responsable_id = (select auth.uid()))));

ALTER POLICY obras_select ON public.obras
  USING ((((responsable_id = (select auth.uid())) AND tiene_permiso('obras_ver'::text)) OR tiene_permiso('obras_transferir'::text)));

ALTER POLICY obras_update ON public.obras
  USING (((responsable_id = (select auth.uid())) AND tiene_permiso('obras_editar'::text)))
  WITH CHECK (((responsable_id = (select auth.uid())) AND tiene_permiso('obras_editar'::text)));

ALTER POLICY obras_empresas_insert ON public.obras_empresas
  WITH CHECK ((tiene_permiso('obras_empresas_crear'::text) AND (creado_por = (select auth.uid()))));

ALTER POLICY obras_empresas_select ON public.obras_empresas
  USING (((tiene_permiso('obras_ver'::text) OR tiene_permiso('obras_empresas'::text)) AND ((NOT pendiente) OR (creado_por = (select auth.uid())) OR tiene_permiso('obras_aprobar'::text))));

ALTER POLICY obras_personas_insert ON public.obras_personas
  WITH CHECK ((tiene_permiso('obras_personas_crear'::text) AND (creado_por = (select auth.uid()))));

ALTER POLICY obras_personas_select ON public.obras_personas
  USING (((tiene_permiso('obras_ver'::text) OR tiene_permiso('obras_personas'::text)) AND ((creado_por = (select auth.uid())) OR obras_puede_ver_persona(id))));

ALTER POLICY submodulos_select ON public.submodulos
  USING ((tiene_permiso('usuarios_gestionar'::text) OR (id IN ( SELECT usuario_submodulos.submodulo_id
   FROM usuario_submodulos
  WHERE ((usuario_submodulos.usuario_id = (select auth.uid())) AND usuario_submodulos.activo)))));

ALTER POLICY tareas_insert ON public.tareas
  WITH CHECK (((creado_por = (select auth.uid())) AND ((responsable_id = (select auth.uid())) OR tiene_permiso('tareas_asignar'::text))));

ALTER POLICY tareas_select ON public.tareas
  USING ((tiene_permiso('tareas_gestionar_ajenas'::text) OR (EXISTS ( SELECT 1
   FROM tareas_asignados ta
  WHERE ((ta.tarea_id = tareas.id) AND (ta.usuario_id = (select auth.uid())) AND ta.activo))) OR ((hilo_id IS NOT NULL) AND puede_ver_hilo(hilo_id)) OR ((hilo_id IS NULL) AND (visibilidad = 'publico'::visibilidad) AND ((proyecto_id IS NULL) OR (( SELECT pr.visibilidad
   FROM tareas_proyectos pr
  WHERE (pr.id = tareas.proyecto_id)) = 'publico'::visibilidad) OR es_miembro_proyecto(proyecto_id, (select auth.uid()))))));

ALTER POLICY tareas_update ON public.tareas
  USING ((tiene_permiso('tareas_gestionar_ajenas'::text) OR (responsable_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM tareas_asignados ta
  WHERE ((ta.tarea_id = tareas.id) AND (ta.usuario_id = (select auth.uid())) AND ta.activo))) OR (EXISTS ( SELECT 1
   FROM tareas_hilos h
  WHERE ((h.id = tareas.hilo_id) AND (h.responsable_id = (select auth.uid())))))))
  WITH CHECK (((tiene_permiso('tareas_gestionar_ajenas'::text) OR (responsable_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM tareas_asignados ta
  WHERE ((ta.tarea_id = tareas.id) AND (ta.usuario_id = (select auth.uid())) AND ta.activo))) OR (EXISTS ( SELECT 1
   FROM tareas_hilos h
  WHERE ((h.id = tareas.hilo_id) AND (h.responsable_id = (select auth.uid())))))) AND ((estado <> 'completada'::estado_tarea) OR (modo_completado = 'manual'::modo_completado) OR (responsable_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text))));

ALTER POLICY tareas_asignados_insert ON public.tareas_asignados
  WITH CHECK (((tiene_permiso('tareas_gestionar_ajenas'::text) OR es_responsable_tarea(tarea_id)) AND ((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_asignar'::text)) AND ((NOT activo) OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))));

ALTER POLICY tareas_asignados_select ON public.tareas_asignados
  USING (((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text) OR es_responsable_tarea(tarea_id) OR es_asignado_tarea(tarea_id)));

ALTER POLICY tareas_asignados_update ON public.tareas_asignados
  USING (((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text) OR es_responsable_tarea(tarea_id)))
  WITH CHECK (((((usuario_id = (select auth.uid())) AND (NOT activo)) OR tiene_permiso('tareas_gestionar_ajenas'::text) OR es_responsable_tarea(tarea_id)) AND ((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_asignar'::text)) AND ((NOT activo) OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))));

ALTER POLICY tareas_eventos_select ON public.tareas_eventos
  USING (((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_auditoria'::text)));

ALTER POLICY tareas_hilos_insert ON public.tareas_hilos
  WITH CHECK (((creado_por = (select auth.uid())) AND ((responsable_id = (select auth.uid())) OR tiene_permiso('tareas_asignar'::text))));

ALTER POLICY tareas_hilos_update ON public.tareas_hilos
  USING (((responsable_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text)))
  WITH CHECK (((responsable_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text) OR tiene_permiso('tareas_asignar'::text)));

ALTER POLICY tareas_hilos_notas_insert ON public.tareas_hilos_notas
  WITH CHECK (((usuario_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM tareas_hilos h
  WHERE ((h.id = tareas_hilos_notas.hilo_id) AND ((h.responsable_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text)))))));

ALTER POLICY tareas_hilos_notas_update ON public.tareas_hilos_notas
  USING (((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text)))
  WITH CHECK (((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text)));

ALTER POLICY tareas_notas_insert ON public.tareas_notas
  WITH CHECK (((usuario_id = (select auth.uid())) AND (tiene_permiso('tareas_gestionar_ajenas'::text) OR es_responsable_tarea(tarea_id) OR es_asignado_tarea(tarea_id))));

ALTER POLICY tareas_notas_update ON public.tareas_notas
  USING (((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text)))
  WITH CHECK (((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text)));

ALTER POLICY tareas_plantillas_insert ON public.tareas_plantillas
  WITH CHECK (((creado_por = (select auth.uid())) AND tiene_permiso('tareas_plantillas'::text)));

ALTER POLICY tareas_proyectos_insert ON public.tareas_proyectos
  WITH CHECK (((creado_por = (select auth.uid())) AND tiene_permiso('tareas_proyectos_crear'::text)));

ALTER POLICY tareas_proyectos_select ON public.tareas_proyectos
  USING (((visibilidad = 'publico'::visibilidad) OR tiene_permiso('tareas_gestionar_ajenas'::text) OR es_miembro_proyecto(id, (select auth.uid()))));

ALTER POLICY tareas_proyectos_update ON public.tareas_proyectos
  USING ((((creado_por = (select auth.uid())) AND es_miembro_proyecto(id, (select auth.uid()))) OR tiene_permiso('tareas_gestionar_ajenas'::text)))
  WITH CHECK ((((creado_por = (select auth.uid())) AND es_miembro_proyecto(id, (select auth.uid()))) OR tiene_permiso('tareas_gestionar_ajenas'::text)));

ALTER POLICY tareas_proyectos_miembros_select ON public.tareas_proyectos_miembros
  USING (((EXISTS ( SELECT 1
   FROM tareas_proyectos p
  WHERE ((p.id = tareas_proyectos_miembros.proyecto_id) AND p.activo))) AND ((usuario_id = (select auth.uid())) OR tiene_permiso('tareas_gestionar_ajenas'::text) OR es_miembro_proyecto(proyecto_id, (select auth.uid())))));

ALTER POLICY usuario_submodulos_select ON public.usuario_submodulos
  USING (((usuario_id = (select auth.uid())) OR tiene_permiso('usuarios_gestionar'::text)));

ALTER POLICY usuario_tutorial_insert ON public.usuario_tutorial
  WITH CHECK ((usuario_id = (select auth.uid())));

ALTER POLICY usuario_tutorial_select ON public.usuario_tutorial
  USING ((usuario_id = (select auth.uid())));

ALTER POLICY usuario_tutorial_update ON public.usuario_tutorial
  USING ((usuario_id = (select auth.uid())))
  WITH CHECK ((usuario_id = (select auth.uid())));

ALTER POLICY usuario_widgets_insert ON public.usuario_widgets
  WITH CHECK ((usuario_id = (select auth.uid())));

ALTER POLICY usuario_widgets_select ON public.usuario_widgets
  USING ((usuario_id = (select auth.uid())));

ALTER POLICY usuario_widgets_update ON public.usuario_widgets
  USING ((usuario_id = (select auth.uid())))
  WITH CHECK ((usuario_id = (select auth.uid())));

ALTER POLICY usuarios_select ON public.usuarios
  USING (((id = (select auth.uid())) OR tiene_permiso('usuarios_ver'::text) OR tiene_permiso('tareas_lista'::text) OR tiene_permiso('tareas_proyectos'::text) OR tiene_permiso('obras_transferir'::text)));

ALTER POLICY usuarios_update_propio ON public.usuarios
  USING ((id = (select auth.uid())))
  WITH CHECK ((id = (select auth.uid())));

-- ============================================================
-- B — superficie RPC
--
-- Toda función del schema public nace con EXECUTE a PUBLIC, y PostgREST
-- publica un endpoint /rest/v1/rpc/<fn> por cada una. Las cuatro de abajo
-- son trigger functions: nadie las llama a mano y devolver `trigger` hace
-- que PostgREST rechace la llamada igual. El endpoint no debería existir.
--
-- Revocar no rompe los triggers: Postgres chequea EXECUTE al crear el
-- trigger, no al dispararlo.
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.handle_new_user()            FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_user_email_updated()  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_guard_congelado()      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_marcar_pendiente()     FROM PUBLIC, anon, authenticated;

-- tiene_permiso sí se llama, pero solo con sesión: las policies la invocan
-- como `authenticated`. Sin sesión devuelve false, así que exponerla a anon
-- no filtra nada — pero tampoco sirve para nada.
--
-- OJO: si algún día una policy tiene que evaluarse como `anon`, esto la
-- rompe con 42501 "permission denied for function tiene_permiso" — un error
-- que no menciona la policy. Hoy no hay lectura anónima: el middleware
-- manda a /login antes de tocar la base.
REVOKE EXECUTE ON FUNCTION public.tiene_permiso(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.tiene_permiso(text) TO authenticated;

-- ============================================================
-- C — search_path e índices de cobertura
-- ============================================================

-- SECURITY INVOKER, así que no hay escalada posible — pero un search_path
-- fijo es gratis y saca el warning.
ALTER FUNCTION public.update_updated_at() SET search_path = public;

-- FK sin índice: cada UPDATE/DELETE en la tabla referenciada escanea entera
-- la que referencia para validar la constraint.
CREATE INDEX IF NOT EXISTS idx_obras_accesos_persona_persona_id  ON public.obras_accesos_persona (persona_id);
CREATE INDEX IF NOT EXISTS idx_obras_aprobaciones_decidido_por   ON public.obras_aprobaciones (decidido_por);
CREATE INDEX IF NOT EXISTS idx_obras_empresas_creado_por         ON public.obras_empresas (creado_por);
CREATE INDEX IF NOT EXISTS idx_obras_obra_persona_empresa_id     ON public.obras_obra_persona (empresa_id);
CREATE INDEX IF NOT EXISTS idx_obras_persona_empresa_empresa_id  ON public.obras_persona_empresa (empresa_id);
CREATE INDEX IF NOT EXISTS idx_obras_transferencias_a_usuario    ON public.obras_transferencias (a_usuario_id);
CREATE INDEX IF NOT EXISTS idx_obras_transferencias_de_usuario   ON public.obras_transferencias (de_usuario_id);
CREATE INDEX IF NOT EXISTS idx_obras_transferencias_ejecutada    ON public.obras_transferencias (ejecutada_por);
CREATE INDEX IF NOT EXISTS idx_submodulos_vista_id               ON public.submodulos (vista_id);
CREATE INDEX IF NOT EXISTS idx_tareas_hilos_notas_usuario_id     ON public.tareas_hilos_notas (usuario_id);
CREATE INDEX IF NOT EXISTS idx_tareas_notas_usuario_id           ON public.tareas_notas (usuario_id);
CREATE INDEX IF NOT EXISTS idx_usuario_submodulos_submodulo_id   ON public.usuario_submodulos (submodulo_id);
