-- Verificación de sql/142: la comisión del referente. NO es una migración:
-- todo corre dentro de una transacción que revierte. Termina en un DO que
-- lanza "N / M ok" y los casos que fallan.
--
-- Mundo: equipo Norte (JN jefe con obras_equipo; Juan vendedor) y Sur
-- (Pedro). A administra Obras, sin equipo. Juan es responsable de Belgrano,
-- con Pedro de participante; Marta es referente y Rosa arquitecta. El
-- montaje escribe como superusuario; todo lo demás, como cada uno. Nombres
-- con `Zqx142`.

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
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','JN','Pedro','A','Norte','Sur','Belgrano','Marta','Rosa','VM','VR']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','obras_ver','obras_crear','obras_equipo','obras_todas','obras_administrar','usuarios_delegar','usuarios_equipo','tareas_ver','tareas_equipo');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test142.local', jsonb_build_object('nombre', 'test142 ' || nombre)
FROM ids WHERE nombre IN ('Juan','JN','Pedro','A');

INSERT INTO equipos (id, nombre)
SELECT id, 'test142 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n) FROM (VALUES ('Norte','Juan'),('Norte','JN'),('Sur','Pedro')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('JN','contactos_ver'), ('JN','obras_ver'), ('JN','usuarios_equipo'), ('JN','usuarios_delegar'), ('JN','obras_equipo'),
    ('JN','tareas_ver'), ('JN','tareas_equipo'),
  ('A','contactos_ver'), ('A','obras_ver'), ('A','obras_todas'), ('A','obras_administrar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx142 Torre Belgrano', 'Zqx142 Calle 1', 'referente', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Pedro'), pg_temp.id('Juan'));
INSERT INTO contactos_personas (id, nombre, responsable_id, creado_por)
VALUES (pg_temp.id('Marta'), 'Zqx142 Marta Gómez', pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Rosa'), 'Zqx142 Rosa Paz', pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO contactos_vinculos (id, persona_id, ente, registro_id, roles, creado_por)
VALUES (pg_temp.id('VM'), pg_temp.id('Marta'), 'obra', pg_temp.id('Belgrano'), '{referente}', pg_temp.id('Juan')),
       (pg_temp.id('VR'), pg_temp.id('Rosa'), 'obra', pg_temp.id('Belgrano'), '{arquitecto}', pg_temp.id('Juan'));

SELECT pg_temp.caso('00 Pedro participa de Belgrano', 'true',
  (SELECT obras_trabaja_de(pg_temp.id('Belgrano'), pg_temp.id('Pedro'))::text));

-- ============================================================
-- 01. Juan registra la comisión de Marta
-- ============================================================
SELECT pg_temp.caso('01 Juan registra 3 %', 'ok', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, 3, NULL)', pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('01 una activa, de Juan', '1', (
  SELECT count(*)::text FROM obras_comisiones
  WHERE vinculo_id = pg_temp.id('VM') AND activo AND creado_por = pg_temp.id('Juan') AND porcentaje = 3));
SELECT pg_temp.caso('01 Rosa no es referente', 'OB036', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, 3, NULL)', pg_temp.id('VR')), 'Juan'));
SELECT pg_temp.caso('01 porcentaje y monto, no', '23514', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, 3, 5000)', pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('01 ni uno ni otro, no', '23514', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, NULL, NULL)', pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('01 moneda con porcentaje, no', '23514', pg_temp.intentar(format(
  $s$SELECT obras_registrar_comision(%L, 3, NULL, 'ARS')$s$, pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('01 el error no tocó la vigente', '1', (
  SELECT count(*)::text FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM') AND activo AND porcentaje = 3));

-- ============================================================
-- 02. Quién la ve
-- ============================================================
SELECT pg_temp.caso('02 Pedro (participante) no la ve', '0', pg_temp.ve(
  'SELECT 1 FROM obras_comisiones', 'Pedro'));
SELECT pg_temp.caso('02 Pedro no la registra', 'OB037', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, 5, NULL)', pg_temp.id('VM')), 'Pedro'));
SELECT pg_temp.caso('02 JN (jefe de Norte) la ve', '1', pg_temp.ve(
  'SELECT 1 FROM obras_comisiones', 'JN'));
SELECT pg_temp.caso('02 A la ve', '1', pg_temp.ve(format(
  'SELECT 1 FROM obras_comisiones WHERE vinculo_id = %L', pg_temp.id('VM')), 'A'));

-- ============================================================
-- 03. Se reemplaza: la vieja queda de historial
-- ============================================================
SELECT pg_temp.caso('03 JN la cambia a 5000', 'ok', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, NULL, 5000)', pg_temp.id('VM')), 'JN'));
SELECT pg_temp.caso('03 USD por defecto', 'USD', (
  SELECT moneda::text FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM') AND activo));
SELECT pg_temp.caso('03 dos filas, una activa', '2/1', (
  SELECT count(*)::text || '/' || (count(*) FILTER (WHERE activo))::text
  FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM')));
SELECT pg_temp.caso('03 Juan ve el historial', '2', pg_temp.ve(format(
  'SELECT 1 FROM obras_comisiones WHERE vinculo_id = %L', pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('03 la vieja no vuelve', 'OB038', pg_temp.intentar(format(
  'UPDATE obras_comisiones SET activo = true WHERE vinculo_id = %L AND NOT activo', pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('03 el monto no se edita', '42501', pg_temp.intentar(format(
  'UPDATE obras_comisiones SET monto = 1 WHERE vinculo_id = %L', pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('03 Juan la pasa a pesos', 'ok', pg_temp.intentar(format(
  $s$SELECT obras_registrar_comision(%L, NULL, 900000, 'ARS')$s$, pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('03 en pesos', 'ARS', (
  SELECT moneda::text FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM') AND activo));

-- ============================================================
-- 04. El participante no toca el referente con comisión
-- ============================================================
SELECT pg_temp.caso('04 Pedro le suma un rol', 'ok', pg_temp.intentar(format(
  $s$UPDATE contactos_vinculos SET roles = '{referente,decisor}' WHERE id = %L$s$, pg_temp.id('VM')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro no le saca referente', 'OB039', pg_temp.intentar(format(
  $s$UPDATE contactos_vinculos SET roles = '{decisor}' WHERE id = %L$s$, pg_temp.id('VM')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro no lo cierra', 'OB039', pg_temp.intentar(format(
  'UPDATE contactos_vinculos SET hasta = current_date WHERE id = %L', pg_temp.id('VM')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro no lo desactiva', 'OB039', pg_temp.intentar(format(
  'SELECT contactos_desactivar_vinculo(%L)', pg_temp.id('VM')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro cambia a Rosa (sin comisión)', 'ok', pg_temp.intentar(format(
  $s$UPDATE contactos_vinculos SET roles = '{arquitecto,decisor}' WHERE id = %L$s$, pg_temp.id('VR')), 'Pedro'));

-- ============================================================
-- 05. Juan le saca referente: la comisión se va con él
-- ============================================================
SELECT pg_temp.caso('05 Juan le saca referente', 'ok', pg_temp.intentar(format(
  $s$UPDATE contactos_vinculos SET roles = '{decisor}' WHERE id = %L$s$, pg_temp.id('VM')), 'Juan'));
SELECT pg_temp.caso('05 ninguna activa', '0', (
  SELECT count(*)::text FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM') AND activo));
SELECT pg_temp.caso('05 sin referente, no se registra', 'OB036', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, 3, NULL)', pg_temp.id('VM')), 'Juan'));

-- ============================================================
-- 06. El admin registra, figura en los nombres y cierra
-- ============================================================
UPDATE contactos_vinculos SET roles = '{decisor,referente}' WHERE id = pg_temp.id('VM');
SELECT pg_temp.caso('06 A registra 2 %', 'ok', pg_temp.intentar(format(
  'SELECT obras_registrar_comision(%L, 2, NULL)', pg_temp.id('VM')), 'A'));
SELECT pg_temp.caso('06 Juan ve el nombre de A', '1', pg_temp.ve(format(
  'SELECT 1 FROM obras_nombres() WHERE id = %L', pg_temp.id('A')), 'Juan'));
SELECT pg_temp.caso('06 Pedro no', '0', pg_temp.ve(format(
  'SELECT 1 FROM obras_nombres() WHERE id = %L', pg_temp.id('A')), 'Pedro'));
SELECT pg_temp.caso('06 A cierra el vínculo', 'ok', pg_temp.intentar(format(
  'UPDATE contactos_vinculos SET hasta = current_date WHERE id = %L', pg_temp.id('VM')), 'A'));
SELECT pg_temp.caso('06 la comisión se cerró con él', '0', (
  SELECT count(*)::text FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM') AND activo));

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
