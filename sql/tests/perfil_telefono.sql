-- Verificación de sql/103: el teléfono propio se guarda normalizado y el
-- formato lo rechaza la base, no el formulario.
-- NO es una migración: corre dentro de una transacción que termina en ROLLBACK.
-- Correr después de aplicar sql/103.

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
  v_tel text;
BEGIN
  SELECT yo, otro INTO v_yo, v_otro FROM sujeto;

  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', v_yo), true);
  PERFORM set_config('role', 'authenticated', true);

  -- 1. Lo tecleado con espacios y guiones queda solo en dígitos.
  BEGIN
    UPDATE usuarios SET telefono = '+54 11 4567-8900' WHERE id = v_yo;
    SELECT telefono INTO v_tel FROM usuarios WHERE id = v_yo;
    INSERT INTO r VALUES ('1 guardo mi telefono normalizado', '541145678900', v_tel,
      v_tel = '541145678900');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('1 guardo mi telefono normalizado', '541145678900',
      SQLSTATE || ' ' || v_err, false);
  END;

  -- 2. Vaciar el campo lo deja en NULL, no en cadena vacía (nullif del trigger).
  BEGIN
    UPDATE usuarios SET telefono = '  ' WHERE id = v_yo;
    SELECT telefono INTO v_tel FROM usuarios WHERE id = v_yo;
    INSERT INTO r VALUES ('2 vaciar deja NULL', 'NULL', coalesce(v_tel, 'NULL'), v_tel IS NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    INSERT INTO r VALUES ('2 vaciar deja NULL', 'NULL', SQLSTATE || ' ' || v_err, false);
  END;

  -- 3. Cuatro dígitos no son un teléfono: lo corta el CHECK (23514), no el form.
  BEGIN
    UPDATE usuarios SET telefono = '1234' WHERE id = v_yo;
    INSERT INTO r VALUES ('3 formato corto rechazado', '23514', 'sin error', false);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO r VALUES ('3 formato corto rechazado', '23514', SQLSTATE, SQLSTATE = '23514');
  END;

  -- 4. El teléfono ajeno sigue fuera de alcance: la policy filtra la fila.
  BEGIN
    UPDATE usuarios SET telefono = '999999999' WHERE id = v_otro;
    SELECT telefono INTO v_tel FROM usuarios WHERE id = v_otro;
    INSERT INTO r VALUES ('4 no toco el telefono de otro', 'distinto de 999999999',
      coalesce(v_tel, 'NULL'), v_tel IS DISTINCT FROM '999999999');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO r VALUES ('4 no toco el telefono de otro', 'distinto de 999999999',
      SQLSTATE, SQLSTATE = '42501');
  END;
END $$;

RESET ROLE;

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
