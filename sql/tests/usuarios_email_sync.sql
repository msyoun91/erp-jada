-- Verificación de sql/021: cambiar el email en `auth.users` lo baja a
-- `usuarios`. NO es una migración: corre dentro de una transacción que termina
-- en ROLLBACK. Correr después de aplicar sql/021.
--
-- Escribe `auth.users` directo, sin pasar por GoTrue: lo que se prueba es el
-- trigger, y la action llega al mismo UPDATE por la API de admin.

BEGIN;

CREATE TEMP TABLE r (
  caso text,
  esperado text,
  obtenido text,
  ok boolean
) ON COMMIT DROP;

CREATE TEMP TABLE sujeto (usuario_id uuid, email_previo text) ON COMMIT DROP;

INSERT INTO sujeto (usuario_id, email_previo)
SELECT id, email FROM usuarios WHERE activo ORDER BY created_at LIMIT 1;

UPDATE auth.users
SET email = 'test-sync-021@example.invalid'
WHERE id = (SELECT usuario_id FROM sujeto);

INSERT INTO r
SELECT
  '1 el email nuevo baja a usuarios',
  'test-sync-021@example.invalid',
  u.email,
  u.email = 'test-sync-021@example.invalid'
FROM usuarios u
WHERE u.id = (SELECT usuario_id FROM sujeto);

-- El trigger tiene `WHEN (NEW.email IS DISTINCT FROM OLD.email)`: un UPDATE
-- que no toca el email no debe reescribir la fila de `usuarios`. Se planta un
-- centinela en `usuarios` que solo sobrevive si el trigger NO corrió —
-- comparar contra el mismo valor de antes no probaría nada.
UPDATE usuarios SET email = 'centinela-021@example.invalid'
WHERE id = (SELECT usuario_id FROM sujeto);

UPDATE auth.users
SET updated_at = now()
WHERE id = (SELECT usuario_id FROM sujeto);

INSERT INTO r
SELECT
  '2 update sin cambio de email no dispara el trigger',
  'centinela-021@example.invalid',
  u.email,
  u.email = 'centinela-021@example.invalid'
FROM usuarios u
WHERE u.id = (SELECT usuario_id FROM sujeto);

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
