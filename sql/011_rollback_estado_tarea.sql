-- Rollback de la regla "solo el responsable o un asignado cambia el estado".
-- El trigger llegó a aplicarse en la base pero su código (gate en TareaRow,
-- mensaje TA003 en MENSAJES_ERROR) se descartó: dejarlo vivo hace que el
-- usuario reciba un error crudo de Postgres al mover un estado.

DROP TRIGGER IF EXISTS validar_estado_tarea ON tareas;

-- La función queda sin ningún trigger que la use.
DROP FUNCTION IF EXISTS validar_quien_cambia_estado();

-- Fuera de alcance: validar_quitar_miembro_proyecto() sigue en la versión que
-- traspasa al dueño las asignaciones sobre tareas cerradas, no en la de
-- sql/009. Restaurarla es una decisión aparte — y el backfill que ya movió
-- asignaciones y responsable_id no se deshace desde acá.
