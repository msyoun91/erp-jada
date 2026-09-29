-- Verificación de sql/146–147: fusionar personas y empresas, y que la fusionada no se reactive. NO es una migración:
-- todo corre dentro de una transacción que revierte. Termina en un DO que
-- lanza "N / M ok" y los casos que fallan.
--
-- Mundo: equipo Norte (Juan) y Sur (Pedro). Ana administra Contactos y no ve
-- Obras. Juan es responsable de Belgrano, con Pedro de participante; Pedro,
-- de Olivos. Marta está dos veces: Marta Uno (de Juan), referente de Belgrano
-- con 3 %, en Caputo; Marta Dos (de Pedro), referente y decisora de Belgrano
-- con USD 5000, arquitecta de Olivos (y antes cliente, cerrado), en Caputo y
-- en Caputo Dos, con un guardado. Rosa Uno es decisora de Belgrano y Rosa Dos
-- referente con 2 %. Caputo es de Norte y constructora de Belgrano; Caputo
-- Dos, de Sur y desarrolladora de Belgrano. Zeta está congelada. El montaje
-- escribe como superusuario; lo demás, como cada uno. Nombres con `Zqx146`.

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
FROM unnest(ARRAY['Juan','Pedro','Ana','Norte','Sur','Belgrano','Olivos',
                  'Marta1','Marta2','Rosa1','Rosa2','Zeta','Caputo','Caputo2',
                  'VM1','VM2','VO2','VC2','VR1','VR2','VE1','VE2']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','contactos_administrar','obras_ver','obras_crear');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test146.local', jsonb_build_object('nombre', 'test146 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro','Ana');

INSERT INTO equipos (id, nombre)
SELECT id, 'test146 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n) FROM (VALUES ('Norte','Juan'),('Sur','Pedro')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('Ana','contactos_ver'), ('Ana','contactos_administrar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx146 Torre Belgrano', 'Zqx146 Calle 1', 'referente', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Olivos'), 'Zqx146 Casa Olivos', 'Zqx146 Calle 2', 'otro', 'casa',
        pg_temp.id('Pedro'), pg_temp.id('Pedro'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Pedro'), pg_temp.id('Juan'));

INSERT INTO contactos_personas (id, nombre, telefono, email, responsable_id, creado_por)
VALUES (pg_temp.id('Marta1'), 'Zqx146 Marta Uno', '1146000001', 'uno@zqx146.test', pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Marta2'), 'Zqx146 Marta Dos', '1146000002', NULL, pg_temp.id('Pedro'), pg_temp.id('Pedro')),
       (pg_temp.id('Rosa1'),  'Zqx146 Rosa Uno', NULL, NULL, pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Rosa2'),  'Zqx146 Rosa Dos', NULL, NULL, pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Zeta'),   'Zqx146 Zeta', NULL, NULL, pg_temp.id('Juan'), pg_temp.id('Juan'));
UPDATE contactos_personas SET congelada = true WHERE id = pg_temp.id('Zeta');

INSERT INTO contactos_empresas (id, nombre, creado_por)
VALUES (pg_temp.id('Caputo'), 'Zqx146 Caputo', pg_temp.id('Juan')),
       (pg_temp.id('Caputo2'), 'Zqx146 Caputo Dos', pg_temp.id('Pedro'));

INSERT INTO contactos_vinculos (id, persona_id, empresa_id, ente, registro_id, roles, creado_por)
VALUES (pg_temp.id('VM1'), pg_temp.id('Marta1'), NULL, 'obra', pg_temp.id('Belgrano'), '{referente}', pg_temp.id('Juan')),
       (pg_temp.id('VM2'), pg_temp.id('Marta2'), NULL, 'obra', pg_temp.id('Belgrano'), '{referente,decisor}', pg_temp.id('Pedro')),
       (pg_temp.id('VC2'), pg_temp.id('Marta2'), NULL, 'obra', pg_temp.id('Olivos'), '{cliente}', pg_temp.id('Pedro')),
       (pg_temp.id('VR1'), pg_temp.id('Rosa1'), NULL, 'obra', pg_temp.id('Belgrano'), '{decisor}', pg_temp.id('Juan')),
       (pg_temp.id('VR2'), pg_temp.id('Rosa2'), NULL, 'obra', pg_temp.id('Belgrano'), '{referente}', pg_temp.id('Juan')),
       (pg_temp.id('VE1'), NULL, pg_temp.id('Caputo'), 'obra', pg_temp.id('Belgrano'), '{constructora}', pg_temp.id('Juan')),
       (pg_temp.id('VE2'), NULL, pg_temp.id('Caputo2'), 'obra', pg_temp.id('Belgrano'), '{desarrolladora}', pg_temp.id('Pedro'));
UPDATE contactos_vinculos SET desde = current_date - 30, hasta = current_date - 1 WHERE id = pg_temp.id('VC2');
INSERT INTO contactos_vinculos (id, persona_id, ente, registro_id, roles, creado_por)
VALUES (pg_temp.id('VO2'), pg_temp.id('Marta2'), 'obra', pg_temp.id('Olivos'), '{arquitecto}', pg_temp.id('Pedro'));

INSERT INTO obras_comisiones (vinculo_id, porcentaje, monto, moneda, creado_por)
VALUES (pg_temp.id('VM1'), 3, NULL, NULL, pg_temp.id('Juan')),
       (pg_temp.id('VM2'), NULL, 5000, 'USD', pg_temp.id('Juan')),
       (pg_temp.id('VR2'), 2, NULL, NULL, pg_temp.id('Juan'));

INSERT INTO contactos_persona_empresa (persona_id, empresa_id, creado_por)
VALUES (pg_temp.id('Marta1'), pg_temp.id('Caputo'), pg_temp.id('Juan')),
       (pg_temp.id('Marta2'), pg_temp.id('Caputo'), pg_temp.id('Pedro')),
       (pg_temp.id('Marta2'), pg_temp.id('Caputo2'), pg_temp.id('Pedro'));

INSERT INTO contactos_vinculos_guardados (persona_id, ente, registro_id, roles, cargado_por)
VALUES (pg_temp.id('Marta2'), 'obra', pg_temp.id('Olivos'), '{decisor}', pg_temp.id('Pedro'));

SELECT pg_temp.caso('00 Caputo es de Norte y Caputo Dos de Sur', 'true', (
  (SELECT equipo_id FROM contactos_empresas WHERE id = pg_temp.id('Caputo')) = pg_temp.id('Norte')
  AND (SELECT equipo_id FROM contactos_empresas WHERE id = pg_temp.id('Caputo2')) = pg_temp.id('Sur'))::text);

-- ============================================================
-- 01. Quién y qué se fusiona
-- ============================================================
SELECT pg_temp.caso('01 Juan no fusiona', 'CO029', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('persona', %L, %L)$s$, pg_temp.id('Marta1'), pg_temp.id('Marta2')), 'Juan'));
SELECT pg_temp.caso('01 una congelada no se fusiona', 'CO030', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('persona', %L, %L)$s$, pg_temp.id('Marta1'), pg_temp.id('Zeta')), 'Ana'));
SELECT pg_temp.caso('01 consigo misma, no', 'CO030', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('persona', %L, %L)$s$, pg_temp.id('Marta1'), pg_temp.id('Marta1')), 'Ana'));
SELECT pg_temp.caso('01 una persona con una empresa, no', 'CO030', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('persona', %L, %L)$s$, pg_temp.id('Marta1'), pg_temp.id('Caputo')), 'Ana'));

-- ============================================================
-- 02. Ana fusiona a Marta: queda la de Juan, con el teléfono y el
--     vínculo en Belgrano (y su comisión) de la de Pedro
-- ============================================================
SELECT pg_temp.caso('02 Ana fusiona', 'ok', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('persona', %L, %L, true, false, ARRAY[%L]::uuid[])$s$,
  pg_temp.id('Marta1'), pg_temp.id('Marta2'), pg_temp.id('VM2')), 'Ana'));
SELECT pg_temp.caso('02 Marta Dos: inactiva, fusionada en Marta Uno', 'false/true', (
  SELECT activo::text || '/' || (fusionada_en = pg_temp.id('Marta1'))::text
  FROM contactos_personas WHERE id = pg_temp.id('Marta2')));
SELECT pg_temp.caso('02 Marta Uno: dueño Juan, teléfono de la otra, su email', 'true', (
  SELECT (responsable_id = pg_temp.id('Juan') AND telefono = '1146000002' AND email = 'uno@zqx146.test')::text
  FROM contactos_personas WHERE id = pg_temp.id('Marta1')));
SELECT pg_temp.caso('02 en Belgrano queda el vínculo elegido, de Marta Uno', pg_temp.id('VM2')::text, (
  SELECT string_agg(id::text, ',') FROM contactos_vinculos
  WHERE persona_id = pg_temp.id('Marta1') AND registro_id = pg_temp.id('Belgrano') AND activo AND hasta IS NULL));
SELECT pg_temp.caso('02 con los roles sumados', '{decisor,referente}', (
  SELECT roles::text FROM contactos_vinculos WHERE id = pg_temp.id('VM2')));
SELECT pg_temp.caso('02 el otro, desactivado y apuntando al que queda', 'false/true', (
  SELECT activo::text || '/' || (fusionado_en = pg_temp.id('VM2'))::text
  FROM contactos_vinculos WHERE id = pg_temp.id('VM1')));
SELECT pg_temp.caso('02 comisión vigente: USD 5000', '5000.00 USD', (
  SELECT monto::text || ' ' || moneda FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM2') AND activo));
SELECT pg_temp.caso('02 el 3 % pasó como historial', '2/1', (
  SELECT count(*)::text || '/' || (count(*) FILTER (WHERE activo))::text
  FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VM2')));
SELECT pg_temp.caso('02 Olivos, abierto y cerrado, pasan a Marta Uno', '2', (
  SELECT count(*)::text FROM contactos_vinculos
  WHERE persona_id = pg_temp.id('Marta1') AND registro_id = pg_temp.id('Olivos')
    AND id IN (pg_temp.id('VO2'), pg_temp.id('VC2'))));
SELECT pg_temp.caso('02 en Caputo, una sola relación abierta', '1', (
  SELECT count(*)::text FROM contactos_persona_empresa
  WHERE persona_id = pg_temp.id('Marta1') AND empresa_id = pg_temp.id('Caputo') AND activo AND hasta IS NULL));
SELECT pg_temp.caso('02 Caputo Dos pasa a Marta Uno', '1', (
  SELECT count(*)::text FROM contactos_persona_empresa
  WHERE persona_id = pg_temp.id('Marta1') AND empresa_id = pg_temp.id('Caputo2') AND activo));
SELECT pg_temp.caso('02 el guardado pasa a Marta Uno', '1', (
  SELECT count(*)::text FROM contactos_vinculos_guardados
  WHERE persona_id = pg_temp.id('Marta1') AND activo AND registro_id = pg_temp.id('Olivos')));
SELECT pg_temp.caso('02 Pedro recibe el aviso: Marta Dos, con la de Juan', 'Zqx146 Marta Dos/test146 Juan/persona', pg_temp.consultar(
  $s$SELECT etiqueta || '/' || motivo || '/' || destino FROM notificaciones_listar() WHERE tipo = 'persona_fusionada'$s$, 'Pedro'));
SELECT pg_temp.caso('02 Ana, no', '0', pg_temp.ve(
  $s$SELECT 1 FROM notificaciones_listar() WHERE tipo = 'persona_fusionada'$s$, 'Ana'));
SELECT pg_temp.caso('02 la ficha vieja lleva a Marta Uno', pg_temp.id('Marta1')::text || '/test146 Juan', pg_temp.consultar(format(
  $s$SELECT id || '/' || dueno FROM contactos_fusionada('persona', %L)$s$, pg_temp.id('Marta2')), 'Pedro'));
SELECT pg_temp.caso('02 dos veces, no', 'CO030', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('persona', %L, %L)$s$, pg_temp.id('Marta1'), pg_temp.id('Marta2')), 'Ana'));

-- ============================================================
-- 03. Rosa: por defecto queda el vínculo de la que queda, y la única
--     comisión pasa sin preguntar
-- ============================================================
SELECT pg_temp.caso('03 Ana fusiona a Rosa', 'ok', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('persona', %L, %L)$s$, pg_temp.id('Rosa1'), pg_temp.id('Rosa2')), 'Ana'));
SELECT pg_temp.caso('03 queda el de Rosa Uno, decisora y referente', '{decisor,referente}', (
  SELECT roles::text FROM contactos_vinculos WHERE id = pg_temp.id('VR1') AND activo));
SELECT pg_temp.caso('03 el 2 % sigue vigente, en el que queda', '2.00', (
  SELECT porcentaje::text FROM obras_comisiones WHERE vinculo_id = pg_temp.id('VR1') AND activo));
SELECT pg_temp.caso('03 Juan (dueño de Rosa Dos) recibe el aviso', '1', pg_temp.ve(
  $s$SELECT 1 FROM notificaciones_listar() WHERE tipo = 'persona_fusionada'$s$, 'Juan'));

-- ============================================================
-- 04. Empresas de equipos distintos
-- ============================================================
SELECT pg_temp.caso('04 Ana fusiona Caputo Dos en Caputo', 'ok', pg_temp.intentar(format(
  $s$SELECT contactos_fusionar('empresa', %L, %L)$s$, pg_temp.id('Caputo'), pg_temp.id('Caputo2')), 'Ana'));
SELECT pg_temp.caso('04 Caputo en Belgrano: constructora y desarrolladora', '{constructora,desarrolladora}', (
  SELECT roles::text FROM contactos_vinculos WHERE id = pg_temp.id('VE1') AND activo));
SELECT pg_temp.caso('04 Caputo queda compartida con Sur', '1', (
  SELECT count(*)::text FROM contactos_empresa_equipos
  WHERE empresa_id = pg_temp.id('Caputo') AND equipo_id = pg_temp.id('Sur') AND activo));
SELECT pg_temp.caso('04 Marta Uno: una sola relación abierta con Caputo', '1', (
  SELECT count(*)::text FROM contactos_persona_empresa
  WHERE persona_id = pg_temp.id('Marta1') AND empresa_id = pg_temp.id('Caputo') AND activo AND hasta IS NULL));
SELECT pg_temp.caso('04 Pedro ve Caputo', '1', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('04 la ficha de Caputo Dos lleva a Caputo, de Norte', 'test146 Norte', pg_temp.consultar(format(
  $s$SELECT split_part(dueno, ' ', 1) || ' ' || split_part(dueno, ' ', 2) FROM contactos_fusionada('empresa', %L)$s$,
  pg_temp.id('Caputo2')), 'Pedro'));

-- ============================================================
-- 05. Fuera de la fusión, las reglas siguen
-- ============================================================
SELECT pg_temp.caso('05 Juan no mueve un vínculo a otra persona', '42501', pg_temp.intentar(format(
  'UPDATE contactos_vinculos SET persona_id = %L WHERE id = %L', pg_temp.id('Rosa1'), pg_temp.id('VO2')), 'Juan'));
SELECT pg_temp.caso('05 Pedro (participante) no le saca referente a Marta', 'OB039', pg_temp.intentar(format(
  $s$UPDATE contactos_vinculos SET roles = '{decisor}' WHERE id = %L$s$, pg_temp.id('VM2')), 'Pedro'));

-- ============================================================
-- 06. Una fusionada no se reactiva (sql/147), ni el admin ni el SQL directo
-- ============================================================
SELECT pg_temp.caso('06 Ana no reactiva a Marta Dos', 'CO031', pg_temp.intentar(format(
  'UPDATE contactos_personas SET activo = true WHERE id = %L', pg_temp.id('Marta2')), 'Ana'));
SELECT pg_temp.caso('06 Ana no reactiva Caputo Dos', 'CO031', pg_temp.intentar(format(
  'UPDATE contactos_empresas SET activo = true WHERE id = %L', pg_temp.id('Caputo2')), 'Ana'));
DO $$
BEGIN
  UPDATE contactos_personas SET activo = true, fusionada_en = NULL WHERE id = pg_temp.id('Rosa2');
  PERFORM pg_temp.caso('06 como superusuario, tampoco', 'CO031', 'ok');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.caso('06 como superusuario, tampoco', 'CO031', SQLSTATE);
END $$;

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
