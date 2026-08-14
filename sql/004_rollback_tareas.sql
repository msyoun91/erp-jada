-- Revierte todo lo que dejó el módulo tareas en la base (sql/004-015 de la
-- rama tareas-v1) — el código volvió al commit previo (1693fd7) pero la DB
-- de Supabase no se revierte sola. Idempotente: todo con IF EXISTS.
-- Correr en Supabase SQL Editor.

-- ============================================================
-- Cron job de recurrencia (si se llegó a agendar desde el Dashboard)
-- ============================================================
DO $$
BEGIN
  PERFORM cron.unschedule('tareas-generar-recurrentes');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- ============================================================
-- Tablas (CASCADE se lleva triggers, policies, índices y FKs propias)
-- ============================================================
DROP TABLE IF EXISTS tareas_eventos CASCADE;
DROP TABLE IF EXISTS tareas_notas CASCADE;
DROP TABLE IF EXISTS tareas_plantillas_items CASCADE;
DROP TABLE IF EXISTS tareas_plantillas CASCADE;
DROP TABLE IF EXISTS tareas CASCADE;
DROP TABLE IF EXISTS tareas_hilos CASCADE;

-- ============================================================
-- Funciones (no se van solas con las tablas — no son propiedad de ninguna)
-- ============================================================
DROP FUNCTION IF EXISTS generar_tareas_recurrentes() CASCADE;
DROP FUNCTION IF EXISTS sync_estado_hilo(uuid) CASCADE;
DROP FUNCTION IF EXISTS trg_sync_estado_hilo() CASCADE;
DROP FUNCTION IF EXISTS log_evento_tarea() CASCADE;
DROP FUNCTION IF EXISTS avanzar_recurrencia(date, recurrencia_intervalo, integer) CASCADE;

-- ============================================================
-- Enums
-- ============================================================
DROP TYPE IF EXISTS recurrencia_intervalo CASCADE;
DROP TYPE IF EXISTS estado_hilo CASCADE;
DROP TYPE IF EXISTS estado_tarea CASCADE;
DROP TYPE IF EXISTS recurrencia_hilo CASCADE; -- ya eliminado por sql/007 en su momento, no-op

-- ============================================================
-- usuarios_select — revertir el OR agregado por sql/005 (tareas_asignar
-- ya no existe como submódulo)
-- ============================================================
DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT
  USING (id = auth.uid() OR tiene_permiso('usuarios_ver'));

-- ============================================================
-- Submódulos del módulo tareas (cascada automática sobre
-- usuario_submodulos por el ON DELETE CASCADE de sql/001)
-- ============================================================
DELETE FROM submodulos WHERE modulo = 'tareas';

-- No se toca sql/006 (GRANT a service_role sobre usuarios/usuario_submodulos):
-- es un fix del módulo usuarios, no un rastro de tareas.
