-- sql/151 — tareas, tramo 5, paso 4a: los tipos de aviso del disparo.
--
-- En su propia transacción: `notificaciones_listar` (sql/152) los castea al
-- crearse, y un valor de enum no se usa antes del commit.
--
-- Decisión: `decisiones/tareas/avisos.md` → *Un disparo avisa una vez al dueño*.

ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_disparada';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_fallida';

ALTER TABLE public.usuario_notificaciones DROP CONSTRAINT usuario_notificaciones_entidad_check;
ALTER TABLE public.usuario_notificaciones ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad = ANY (ARRAY['equipos_miembros', 'usuario_submodulos', 'tareas', 'tareas_hilos',
                              'tareas_plantillas', 'usuarios', 'obras', 'obras_participantes',
                              'contactos_personas', 'contactos_empresas']));
