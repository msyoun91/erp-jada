-- Verificación de sql/022: el perfil propio edita `nombre` y nada más.
-- NO es una migración: corre dentro de una transacción que termina en ROLLBACK.
-- Correr después de aplicar sql/022.
--
-- Mismo mecanismo que los otros tests de RLS: rol `authenticated` y
-- `request.jwt.claims` para mover `auth.uid()`. Hacen falta dos usuarios: el
-- segundo es la fila ajena que el primero no debe poder tocar.

BEGIN;

CREATE TEMP TABLE r (
  caso text,
  esperado text,
  obtenido text,
  ok boolean
) ON COMMIT DROP;
GRANT ALL ON r TO authenticated;

CREATE TEMP TABLE sujeto (yo uuid, otro uuid) ON COMMIT DROP;
GRANT ALL ON sujeto TO authenticated;

INSERT INTO sujeto (yo, otro)
SELECT
  (SELECT id FROM usuarios WHERE activo ORDER BY created_at LIMIT 1),
  (SELECT id FROM usuarios WHERE activo ORDER BY created_at DESC LIMIT 1);

DO $$
DECLARE
  v_yo uuid;
  v_otro uuid;
  v_err text;
  v_nombre text;
BEGIN
  SELECT yo, otro INTO v_yo, v_otro FROM sujeto;

  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', v_yo), true);
  PERFORM set_config('role', 'authenticated', true);

  -- 1. Cambiar el nombre propio: pasa.
  BEGIN
    UPDATE usuarios SET nombre = 'Nombre de prueba 022' WHERE id = v_yo;
    SELECT nombre INTO v_nombre FROM usuarios WHERE id = v_yo;
    INSERT INTO r VALUES ('1 cambio mi nombre', 'Nombre de prueba 022', v_nombre,
      v_nombre = 'Nombre de prueba 022');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('1 cambio mi nombre', 'Nombre de prueba 022', SQLSTATE || ' ' || v_err, false);
  END;

  -- 2. Reactivarme solo: el GRANT por columna lo rechaza (42501).
  BEGIN
    UPDATE usuarios SET activo = true WHERE id = v_yo;
    INSERT INTO r VALUES ('2 no puedo tocar activo', '42501', 'sin error', false);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO r VALUES ('2 no puedo tocar activo', '42501', SQLSTATE, SQLSTATE = '42501');
  END;

  -- 3. Renombrar a otro: la policy no le da la fila, así que no actualiza
  --    ninguna (no tira error: RLS filtra, no rechaza).
  BEGIN
    UPDATE usuarios SET nombre = 'Ajeno 022' WHERE id = v_otro;
    SELECT nombre INTO v_nombre FROM usuarios WHERE id = v_otro;
    INSERT INTO r VALUES ('3 no renombro a otro', 'distinto de Ajeno 022', v_nombre,
      v_nombre IS DISTINCT FROM 'Ajeno 022');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO r VALUES ('3 no renombro a otro', 'distinto de Ajeno 022', SQLSTATE, SQLSTATE = '42501');
  END;
END $$;

RESET ROLE;

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
