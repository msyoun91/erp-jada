-- Descripción opcional del hilo. Nullable: los hilos existentes y los creados
-- desde otros caminos (plantillas, etc.) no la tienen.
alter table tareas_hilos add column if not exists descripcion text;
