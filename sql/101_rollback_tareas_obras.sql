-- sql/101 — rollback de tareas, obras y la infra cross-módulo que trajeron
--
-- Deja la base en el esquema de `sql/001`–`sql/003` más las mejoras de usuarios
-- y dashboard posteriores (`sql/020`, `021`, `022`, `035`), que NO se revierten:
-- son de módulos que siguen en pie.
--
-- UN SOLO ARCHIVO, y no uno por módulo, a propósito. Tareas y obras están
-- entrelazadas en las dos direcciones: `tareas_vinculos` referencia `entes`,
-- que registra filas de obras; las funciones de obras llaman a
-- `registrar_sin_acceso`, que es infra de tareas; `disparar_plantillas` lee la
-- tabla del ente por `entes.tabla`. Dos archivos habría que correrlos igual en
-- una transacción y en un orden fijo — el corte no compra nada y suma una
-- forma de equivocarse.
--
-- CORRE COMO UNA SOLA TRANSACCIÓN. Si algo falla, no queda esquema a medio
-- desarmar (misma razón por la que `sql/003` se pudo reintentar entero).
--
-- ────────────────────────────────────────────────────────────────────────────
-- QUÉ SOBREVIVE
--
--   tablas     usuarios · submodulos · usuario_submodulos · usuario_widgets
--              usuario_tutorial (genérica: usuario_id + paso text, sin nada
--              de tareas en el esquema; se queda vacía)
--   funciones  tiene_permiso · validar_vista_id · update_updated_at
--              handle_new_user · handle_user_email_updated
--   enums      tipo_submodulo
--
-- QUÉ NO HACE ESTE ARCHIVO
--
--   No toca git. El código de tareas y obras sale del repo por la rama, no
--   por acá.
--   No borra usuarios ni sus permisos de `usuarios`/`dashboard`. Sí borra los
--   submódulos de tareas y obras, que dejan de existir.
--
-- DATOS QUE SE PIERDEN (contados antes de escribir esto)
--
--   14 obras · 16 personas · 10 empresas · 46 tareas · 7 proyectos
--   27 eventos · 4 entes
--
--   No hay backup automático. Si algo de eso hace falta después, se exporta
--   ANTES de correr este archivo.
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1 · tiene_permiso vuelve a su cuerpo de sql/001 ──────────────────────────
--
-- Hoy delega en `usuario_tiene_permiso(auth.uid(), codigo)` (`sql/062`), que se
-- va en la sección 3. Va PRIMERO: las policies de `submodulos` y
-- `usuario_submodulos` la usan y tienen que seguir en pie todo el archivo.
--
-- ⚠ ESTA SECCIÓN ESTUVO MAL Y LA REPARA `sql/102`. Volver a `sql/001` perdió
-- el `JOIN usuarios u ... AND u.activo` que había agregado `sql/020`: un
-- usuario desactivado conservaba todos sus permisos de RLS. El cuerpo bueno es
-- el de `sql/102`; el de abajo queda como registro de lo que corrió.

CREATE OR REPLACE FUNCTION tiene_permiso(p_codigo text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.usuario_submodulos us
    JOIN public.submodulos s ON s.id = us.submodulo_id
    WHERE us.usuario_id = auth.uid()
      AND us.activo
      AND s.activo
      AND s.codigo = p_codigo
  );
$$;


-- ── 2 · Las tablas ───────────────────────────────────────────────────────────
--
-- CASCADE se lleva sus policies, triggers, índices, constraints y las vistas
-- que dependan. Ninguna tabla que sobrevive tiene trigger de tareas u obras
-- colgando (verificado contra pg_trigger).

DROP TABLE IF EXISTS
  -- tareas
  tareas_vinculos,
  tareas_plantillas_activaciones,
  tareas_plantillas_items,
  tareas_plantillas_hilos,
  tareas_plantillas,
  tareas_hilos_notas,
  tareas_notas,
  tareas_asignados,
  tareas,
  tareas_hilos,
  tareas_proyectos_miembros,
  tareas_proyectos,
  -- obras
  obras_empresa_grant_contextual,
  obras_persona_grant_contextual,
  obras_obra_compartida,
  obras_aprobaciones,
  obras_accesos_persona,
  obras_transferencias,
  obras_obra_referente,
  obras_obra_persona,
  obras_obra_empresa,
  obras_persona_empresa,
  obras_personas,
  obras_empresas,
  obras,
  -- infra cross-módulo que existía solo para estos dos
  eventos,
  entes,
  usuario_notificaciones
CASCADE;


-- ── 3 · Las funciones ────────────────────────────────────────────────────────
--
-- Por nombre y no por firma: varias tienen sobrecargas (`obras_ctx_vigente` con
-- 2 y con 4 argumentos, `tiene_permiso`/`usuario_tiene_permiso`). El bloque
-- borra todas las sobrecargas de cada nombre.
--
-- La lista va explícita y no por patrón para que se pueda auditar: un
-- `LIKE 'notificar%'` se llevaría lo que alguien agregue mañana sin que nadie
-- lo relea. Los dos prefijos sí van por patrón — ahí el namespace es el módulo.

DO $$
DECLARE
  r record;
  nombres text[] := ARRAY[
    -- escrituras y lectura de tareas
    'crear_tarea', 'editar_tarea', 'crear_proyecto', 'editar_proyecto',
    'sincronizar_asignados', 'reasignar_tarea', 'vincular_tarea',
    'vinculos_de_tareas', 'convertir_tarea_en_hilo', 'deshacer_conversion_hilo',
    'reabrir_hilo_en_tarea', 'desactivar_hilo', 'cascada_desactivar_proyecto',
    'generar_recurrencia', 'reactivar_posponer_vencidos',
    'arrancar_vencimiento_siguiente', 'fijar_vencimiento_tras_previo',
    'heredar_origen_hilo', 'es_siembra_tarea',
    -- predicados de tareas
    'es_asignado_tarea', 'es_responsable_tarea', 'es_creador_proyecto',
    'es_miembro_proyecto', 'es_miembro_proyecto_de_tarea',
    'proyecto_tiene_miembros', 'puede_ver_hilo', 'puede_ver_hilo_de',
    -- triggers de validación de tareas
    'validar_cierre_hilo', 'validar_desactivar_paso', 'validar_destino_tarea',
    'validar_gestionar_tarea', 'validar_paso_previo', 'validar_paso_tarea',
    'validar_proyecto_tarea_miembros', 'validar_quitar_miembro_proyecto',
    'validar_reactivar_tarea', 'validar_responsable_hilo',
    'validar_responsable_tarea',
    -- plantillas
    'guardar_plantilla', 'usar_plantilla', 'disparar_plantillas',
    'plantilla_disparada', 'puede_gestionar_plantilla', 'rellenar_datos',
    -- eventos
    'emitir_evento', 'emitir_eventos_registro', 'emitir_eventos_relacion',
    'puede_ver_relacion',
    -- entes y acceso cross-módulo (sql/059, 061, 062, 063)
    'etiqueta_registro', 'relacionados_de_registro', 'buscar_registros',
    'puede_abrir_registro', 'puede_compartir_registro', 'compartir_registros',
    'queda_afuera', 'asignados_con_acceso', 'sin_acceso', 'sin_acceso_tarea',
    'sin_acceso_registrado', 'registrar_sin_acceso', 'puede_ver_compartido',
    'usuario_tiene_permiso',
    -- notificaciones (sql/038 y las que sumaron los módulos)
    'notificar', 'notificaciones_listar', 'notificaciones_avisos',
    'notificar_tarea_asignada', 'notificar_transferencia_obra',
    'notificar_decision_obra', 'notificar_disparo',
    'notificar_cambio_plantilla', 'notificar_obra_desactivada'
  ];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS firma
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND (
        p.proname = ANY(nombres)
        OR p.proname LIKE 'obras\_%'
        OR p.proname LIKE 'tareas\_%'
      )
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.firma);
  END LOOP;
END;
$$;


-- ── 4 · Los enums ────────────────────────────────────────────────────────────
--
-- Después de las funciones: `entes.estados` guarda un `regtype` y varias
-- funciones los reciben como parámetro. Sobrevive `tipo_submodulo` (sql/001).

DROP TYPE IF EXISTS
  estado_tarea, estado_hilo, visibilidad, modo_completado, recurrencia_unidad,
  tipo_plantilla, alcance_plantilla,
  estado_obra, tipo_obra, origen_obra, motivo_perdida, provincia,
  rol_empresa, rol_persona,
  tipo_evento, tipo_notificacion
CASCADE;


-- ── 5 · Los submódulos de tareas y obras ─────────────────────────────────────
--
-- `usuario_submodulos` primero, por la FK. Se borran de verdad y no con
-- `activo = false`: la regla de no-DELETE protege datos de negocio, y un
-- permiso a un módulo que ya no existe no es un dato, es basura que el modal
-- de permisos tendría que aprender a esconder.

DELETE FROM usuario_submodulos
WHERE submodulo_id IN (SELECT id FROM submodulos WHERE modulo IN ('tareas', 'obras'));

DELETE FROM submodulos WHERE modulo IN ('tareas', 'obras');


-- ── 6 · Verificación ─────────────────────────────────────────────────────────
--
-- Corre después, en una consulta aparte. Las tres tienen que dar 0.
--
--   SELECT count(*) FROM pg_tables
--    WHERE schemaname = 'public'
--      AND (tablename LIKE 'tareas%' OR tablename LIKE 'obras%'
--           OR tablename IN ('entes', 'eventos', 'usuario_notificaciones'));
--
--   SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public'
--      AND (p.proname LIKE 'obras\_%' OR p.proname LIKE 'tareas\_%');
--
--   SELECT count(*) FROM submodulos WHERE modulo IN ('tareas', 'obras');
--
-- Y esta tiene que seguir dando true para un usuario con permiso:
--
--   SELECT tiene_permiso('usuarios_ver');
