-- Verificación de sql/100: transferir bloquea la fila que va a cambiar de dueño.
--
-- NO es migración: corre dentro de un DO que termina en RAISE EXCEPTION, así
-- que la transacción se revierte. Mismo andamiaje que obras_096.sql.
--
-- Es un test de fuente, no de comportamiento: la carrera necesita dos sesiones
-- simultáneas y el arnés del repo corre en una sola. Lo que sí atrapa —y es el
-- riesgo real, porque cada migración reescribe la función entera con CREATE OR
-- REPLACE— es que una próxima copie el cuerpo sin el candado.
--
-- El comportamiento de las tres funciones lo siguen cubriendo obras_087,
-- obras_089, obras_090 y obras_096; correrlos después de sql/100.
--
-- Afirma:
--   A las tres funciones de transferencia leen al saliente con FOR UPDATE
--
-- Último resultado: sin correr todavía (sql/100 pendiente de aplicar).

DO $test$
DECLARE
  v_con int; v_total int; r text := '';
BEGIN
  -- `[^\n]*` y no `.*`: en Postgres el punto matchea el salto de línea, así que
  -- `.*` daría por bueno un FOR UPDATE de cualquier otro statement del cuerpo.
  SELECT count(*),
         count(*) FILTER (WHERE pg_get_functiondef(p.oid) ~* 'INTO v_actual[^\n]*FOR UPDATE')
  INTO v_total, v_con
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('obras_transferir', 'obras_transferir_persona', 'obras_transferir_empresa');

  IF v_con = 3 AND v_total = 3 THEN
    r := r || 'A OK — las tres bloquean la fila del saliente';
  ELSE
    r := r || format('A FALLA — %s funciones, %s con FOR UPDATE (esperado 3 y 3)', v_total, v_con);
  END IF;

  RAISE EXCEPTION E'\n%\n', r;
END;
$test$;
