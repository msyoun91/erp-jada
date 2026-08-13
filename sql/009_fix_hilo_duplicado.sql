-- Limpieza puntual (no migración de esquema): el hilo "Mantenimiento depósito"
-- quedó duplicado por un bug de UI ya corregido (CrearTareaPanel creaba un hilo
-- nuevo en cada reintento de submit si el paso siguiente fallaba). Este es el
-- duplicado huérfano, sin tareas.
-- Correr en Supabase SQL Editor.

UPDATE tareas_hilos SET activo = false
WHERE id = 'a074dc70-1229-475a-a062-3718c6fc41ad'
RETURNING id, titulo, activo;
