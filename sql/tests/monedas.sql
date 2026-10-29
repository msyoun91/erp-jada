-- Verificación de sql/155–156: Monedas. NO es una migración: todo corre dentro de una transacción
-- que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Ana (Administración) y Carlos (gerente) tienen la vista y las dos funciones; Juan
-- (vendedor) no tiene nada de Monedas. Lo que ya hubiera en las tablas se apaga al empezar. now()
-- es el mismo en toda la transacción: dos valores vigentes de una misma moneda cargados acá
-- empatarían, así que cada moneda prueba un camino (blue: corrección a mano; EUR: rojo de MonedAPI
-- confirmado y después reemplazado; oficial: MonedAPI normal y rojo a mano).

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.consultar(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql INTO v_out;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_out;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT count(*)::text FROM (%s) x', p_sql), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE monedas_tipos_cambio SET activo = false WHERE activo;
UPDATE monedas_principal SET activo = false WHERE activo;
UPDATE monedas_consultas SET created_at = created_at - interval '1 year';

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Ana','Carlos','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('monedas_ver','monedas_corregir','monedas_principal');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test156.local', jsonb_build_object('nombre', 'test156 ' || nombre)
FROM ids WHERE nombre IN ('Ana','Carlos','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Ana','monedas_ver'), ('Ana','monedas_corregir'), ('Ana','monedas_principal'),
  ('Carlos','monedas_ver'), ('Carlos','monedas_corregir'), ('Carlos','monedas_principal')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde) VALUES
  ('USD_OFICIAL', 1450, now() - interval '2 days', 'monedapi', now() - interval '2 days'),
  ('USD_BLUE',    1500, now() - interval '2 days', 'monedapi', now() - interval '2 days'),
  ('EUR',         1780, now() - interval '9 days', 'monedapi', now() - interval '9 days');

-- ============================================================
-- 01. Convertir: lo usa cualquiera, aunque no vea Monedas
-- ============================================================
SELECT pg_temp.caso('01 USD 12 blue → USD oficial, Juan', '12.41', pg_temp.consultar(
  $q$SELECT round(monedas_convertir(12, 'USD_BLUE', 'USD_OFICIAL'), 2)::text$q$, 'Juan'));
SELECT pg_temp.caso('01 EUR 1 → ARS', '1780.00', pg_temp.consultar(
  $q$SELECT round(monedas_convertir(1, 'EUR', 'ARS'), 2)::text$q$, 'Juan'));
SELECT pg_temp.caso('01 ARS → ARS no busca tipo de cambio', '500', pg_temp.consultar(
  $q$SELECT monedas_convertir(500, 'ARS', 'ARS')::text$q$, 'Juan'));
SELECT pg_temp.caso('01 antes del primer tipo de cambio', 'MO001', pg_temp.consultar(
  $q$SELECT monedas_convertir(1, 'EUR', 'ARS', now() - interval '30 days')::text$q$, 'Juan'));

-- ============================================================
-- 02. Quién ve qué
-- ============================================================
SELECT pg_temp.caso('02 Juan no ve el historial', '0',
  pg_temp.ve('SELECT 1 FROM monedas_tipos_cambio', 'Juan'));
SELECT pg_temp.caso('02 Ana ve el historial', '3',
  pg_temp.ve('SELECT 1 FROM monedas_tipos_cambio WHERE activo', 'Ana'));
SELECT pg_temp.caso('02 Juan ve los vigentes', '1500.00', pg_temp.consultar(
  $q$SELECT valor::text FROM monedas_hoy() WHERE moneda = 'USD_BLUE'$q$, 'Juan'));
SELECT pg_temp.caso('02 monedas_hoy: tres, sin ARS', '3',
  pg_temp.ve('SELECT 1 FROM monedas_hoy()', 'Juan'));
SELECT pg_temp.caso('02 Juan no ve el historial por función', '0',
  pg_temp.ve($q$SELECT 1 FROM monedas_historial('USD_BLUE')$q$, 'Juan'));
SELECT pg_temp.caso('02 Juan no recibe avisos', '0',
  pg_temp.ve('SELECT 1 FROM monedas_avisos()', 'Juan'));
SELECT pg_temp.caso('02 Ana: euro sin actualizar hace 9 días', '1',
  pg_temp.ve($q$SELECT 1 FROM monedas_avisos() WHERE aviso = 'sin_actualizar' AND moneda = 'EUR'$q$, 'Ana'));

-- ============================================================
-- 03. Juan no escribe nada
-- ============================================================
SELECT pg_temp.caso('03 Juan no corrige', '42501', pg_temp.intentar(
  $q$SELECT monedas_corregir('USD_BLUE', 1600)$q$, 'Juan'));
SELECT pg_temp.caso('03 Juan no guarda lo de MonedAPI', '42501', pg_temp.intentar(
  $q$SELECT monedas_guardar_monedapi('USD_BLUE', 1, now())$q$, 'Juan'));
SELECT pg_temp.caso('03 Juan no reserva consultas', '42501', pg_temp.intentar(
  'SELECT monedas_reservar_consulta(true)', 'Juan'));
SELECT pg_temp.caso('03 Juan no elige la principal', '42501', pg_temp.intentar(
  $q$SELECT monedas_elegir_principal('USD_BLUE')$q$, 'Juan'));
SELECT pg_temp.caso('03 Juan no inserta directo', '42501', pg_temp.intentar(
  $q$INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde)
     VALUES ('USD_BLUE', 1, now(), 'manual', now())$q$, 'Juan'));

-- ============================================================
-- 04. Ana corrige el blue a mano: rige y les avisa a los demás que corrigen
-- ============================================================
SELECT pg_temp.caso('04 Ana corrige el blue a 1565', 'ok', pg_temp.intentar(
  $q$SELECT monedas_corregir('USD_BLUE', 1565)$q$, 'Ana'));
SELECT pg_temp.caso('04 rige', '1565.00', (SELECT monedas_tipo_cambio('USD_BLUE')::text));
SELECT pg_temp.caso('04 el anterior sigue para atrás', '1500.00',
  (SELECT monedas_tipo_cambio('USD_BLUE', now() - interval '1 hour')::text));
SELECT pg_temp.caso('04 a Carlos le llega', '1', (
  SELECT count(*)::text FROM usuario_notificaciones
  WHERE usuario_id = pg_temp.id('Carlos') AND tipo = 'tipo_cambio_corregido' AND activo));
SELECT pg_temp.caso('04 a Ana no', '0', (
  SELECT count(*)::text FROM usuario_notificaciones
  WHERE usuario_id = pg_temp.id('Ana') AND entidad = 'monedas_tipos_cambio'));
SELECT pg_temp.caso('04 Carlos lo lee: moneda y antes → después', 'USD_BLUE|$1.500,00 → $1.565,00|monedas',
  pg_temp.consultar($q$SELECT etiqueta || '|' || motivo || '|' || destino FROM notificaciones_listar()
                       WHERE tipo = 'tipo_cambio_corregido'$q$, 'Carlos'));
SELECT pg_temp.caso('04 historial: anterior y nivel', '1500.00|null|test156 Ana', pg_temp.consultar(
  $q$SELECT anterior::text || '|' || coalesce(nivel, 'null') || '|' || cargado_por
     FROM monedas_historial('USD_BLUE') WHERE origen = 'manual'$q$, 'Carlos'));

-- ============================================================
-- 05. MonedAPI trae un euro rojo: espera confirmación; Carlos lo confirma
-- ============================================================
SELECT pg_temp.caso('05 uno más viejo que lo guardado no entra', 'null', (
  SELECT coalesce(monedas_guardar_monedapi('EUR', 1790, now() - interval '10 days')::text, 'null')));
-- La función escribe: va en su propio statement, el que la lee no vería la fila.
INSERT INTO ids SELECT 'EUR rojo', monedas_guardar_monedapi('EUR', 17800, now() - interval '1 hour');
SELECT pg_temp.caso('05 rojo: entra sin regir', '1', (
  SELECT count(*)::text FROM monedas_tipos_cambio WHERE id = pg_temp.id('EUR rojo') AND vigente_desde IS NULL));
SELECT pg_temp.caso('05 se sigue usando el vigente', '1780.00', (SELECT monedas_tipo_cambio('EUR')::text));
SELECT pg_temp.caso('05 Ana ve el rojo por confirmar', '17800.00', pg_temp.consultar(
  $q$SELECT valor::text FROM monedas_avisos() WHERE aviso = 'por_confirmar'$q$, 'Ana'));
SELECT pg_temp.caso('05 la barra sigue mostrando el vigente', '1780.00', pg_temp.consultar(
  $q$SELECT valor::text FROM monedas_hoy() WHERE moneda = 'EUR'$q$, 'Juan'));
SELECT pg_temp.caso('05 Juan no confirma', '42501', pg_temp.intentar(
  format('SELECT monedas_confirmar(%L)', pg_temp.id('EUR rojo')), 'Juan'));
SELECT pg_temp.caso('05 Carlos confirma', 'ok', pg_temp.intentar(
  format('SELECT monedas_confirmar(%L)', pg_temp.id('EUR rojo')), 'Carlos'));
SELECT pg_temp.caso('05 rige desde la confirmación', '17800.00', (SELECT monedas_tipo_cambio('EUR')::text));
SELECT pg_temp.caso('05 no se confirma dos veces', 'MO003', pg_temp.intentar(
  format('SELECT monedas_confirmar(%L)', pg_temp.id('EUR rojo')), 'Carlos'));
SELECT pg_temp.caso('05 a Ana le llega la confirmación', '1', (
  SELECT count(*)::text FROM usuario_notificaciones
  WHERE usuario_id = pg_temp.id('Ana') AND tipo = 'tipo_cambio_confirmado' AND activo));
SELECT pg_temp.caso('05 el euro ya no está sin actualizar', '0',
  pg_temp.ve($q$SELECT 1 FROM monedas_avisos() WHERE aviso = 'sin_actualizar'$q$, 'Ana'));

-- Otro rojo, y Ana lo corrige en vez de confirmarlo: el pendiente se apaga.
SELECT monedas_guardar_monedapi('EUR', 1790, now() - interval '30 minutes');
SELECT pg_temp.caso('05 otro rojo espera', '1', (
  SELECT count(*)::text FROM monedas_tipos_cambio WHERE moneda = 'EUR' AND activo AND vigente_desde IS NULL));
SELECT pg_temp.caso('05 Ana corrige (rojo contra 17800, confirmado)', 'ok', pg_temp.intentar(
  $q$SELECT monedas_corregir('EUR', 1795, true)$q$, 'Ana'));
SELECT pg_temp.caso('05 ya no hay pendiente', '0', (
  SELECT count(*)::text FROM monedas_tipos_cambio WHERE moneda = 'EUR' AND activo AND vigente_desde IS NULL));

-- ============================================================
-- 06. Oficial: MonedAPI normal entra solo; un rojo a mano pide confirmación
-- ============================================================
INSERT INTO ids SELECT 'Oficial 1460', monedas_guardar_monedapi('USD_OFICIAL', 1460, now() - interval '1 hour');
SELECT pg_temp.caso('06 MonedAPI normal rige al guardarse', '1', (
  SELECT count(*)::text FROM monedas_tipos_cambio
  WHERE id = pg_temp.id('Oficial 1460') AND vigente_desde = now() AND creado_por IS NULL));
SELECT pg_temp.caso('06 MonedAPI no avisa a nadie', '0', (
  SELECT count(*)::text FROM usuario_notificaciones n JOIN monedas_tipos_cambio t ON t.id = n.entidad_id
  WHERE t.origen = 'monedapi' AND n.tipo = 'tipo_cambio_corregido'));
SELECT pg_temp.caso('06 Ana: 15000 sin confirmar', 'MO002', pg_temp.intentar(
  $q$SELECT monedas_corregir('USD_OFICIAL', 15000)$q$, 'Ana'));
SELECT pg_temp.caso('06 Ana: 15000 confirmado', 'ok', pg_temp.intentar(
  $q$SELECT monedas_corregir('USD_OFICIAL', 15000, true)$q$, 'Ana'));
SELECT pg_temp.caso('06 nivel_cambio: 1250 → 1520 amarillo', 'amarillo', nivel_cambio(1250, 1520));
SELECT pg_temp.caso('06 nivel_cambio: 1450 → 1,45 rojo', 'rojo', nivel_cambio(1450, 1.45));
SELECT pg_temp.caso('06 nivel_cambio: 1450 → 1460 nada', 'null', coalesce(nivel_cambio(1450, 1460), 'null'));

-- ============================================================
-- 07. Consultas a MonedAPI: una por hora, o por minuto con el botón
-- ============================================================
SELECT pg_temp.caso('07 la primera reserva', 'si', (
  SELECT CASE WHEN monedas_reservar_consulta(false) IS NULL THEN 'no' ELSE 'si' END));
SELECT pg_temp.caso('07 el botón dentro del minuto no', 'no', (
  SELECT CASE WHEN monedas_reservar_consulta(true) IS NULL THEN 'no' ELSE 'si' END));
UPDATE monedas_consultas SET created_at = now() - interval '2 minutes' WHERE created_at = now();
SELECT pg_temp.caso('07 pasado el minuto, el botón sí', 'si', (
  SELECT CASE WHEN monedas_reservar_consulta(true) IS NULL THEN 'no' ELSE 'si' END));
SELECT pg_temp.caso('07 la de cada hora no', 'no', (
  SELECT CASE WHEN monedas_reservar_consulta(false) IS NULL THEN 'no' ELSE 'si' END));
SELECT monedas_cerrar_consulta(c.id, 'timeout') FROM monedas_consultas c WHERE c.ok IS NULL;
SELECT pg_temp.caso('07 Ana ve que MonedAPI falla', '1',
  pg_temp.ve($q$SELECT 1 FROM monedas_avisos() WHERE aviso = 'monedapi_falla'$q$, 'Ana'));
INSERT INTO monedas_consultas (forzada, ok) VALUES (true, true);
SELECT pg_temp.caso('07 una que anda lo apaga', '0',
  pg_temp.ve($q$SELECT 1 FROM monedas_avisos() WHERE aviso = 'monedapi_falla'$q$, 'Ana'));

-- ============================================================
-- 08. Moneda principal
-- ============================================================
SELECT pg_temp.caso('08 sin elegir, ARS', 'ARS', pg_temp.consultar('SELECT monedas_principal_actual()::text', 'Juan'));
SELECT pg_temp.caso('08 Ana elige USD blue', 'ok', pg_temp.intentar(
  $q$SELECT monedas_elegir_principal('USD_BLUE')$q$, 'Ana'));
SELECT pg_temp.caso('08 Juan la ve', 'USD_BLUE', pg_temp.consultar('SELECT monedas_principal_actual()::text', 'Juan'));
SELECT pg_temp.caso('08 elegir la misma no suma fila', 'ok1', (
  SELECT pg_temp.intentar($q$SELECT monedas_elegir_principal('USD_BLUE')$q$, 'Carlos')
    || (SELECT count(*) FROM monedas_principal WHERE activo)::text) );

-- ============================================================
-- Resultado
-- ============================================================
DO $$
DECLARE
  v_ok int;
  v_total int;
  v_fallan text;
BEGIN
  SELECT count(*) FILTER (WHERE ok), count(*),
         string_agg(caso || ' → esperado ' || coalesce(esperado, 'NULL') || ', obtenido ' || coalesce(obtenido, 'NULL'),
                    E'\n' ORDER BY caso) FILTER (WHERE NOT ok)
  INTO v_ok, v_total, v_fallan
  FROM r;
  RAISE EXCEPTION '% / % ok%', v_ok, v_total, coalesce(E'\n' || v_fallan, '');
END;
$$;

ROLLBACK;
