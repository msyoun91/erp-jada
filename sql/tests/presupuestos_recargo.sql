-- Verificación de sql/190: el recargo de la comisión del referente. NO es una migración: todo corre dentro de una
-- transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Juan responsable de Belgrano (la tiene a cargo: ve la comisión), Pedro participante que arma (no la ve). Marta y Rosa,
-- referentes. Un renglón a mano de USD 1.000 en una sección al 21 %. Lo creado lleva Zqx190.

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

-- Filas que un UPDATE tocó, como cada uno: RLS no falla, deja 0.
CREATE FUNCTION pg_temp.cambia(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('WITH u AS (%s RETURNING 1) SELECT count(*)::text FROM u', p_sql), p_como);
$f$;


-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','Pedro','Marta','Rosa','VM','VR','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','obras_ver','presupuestos_ver','presupuestos_armar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test190.local', jsonb_build_object('nombre', 'test190 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','presupuestos_ver'), ('Pedro','presupuestos_armar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx190 Torre Belgrano', 'Zqx190 Calle 1', 'referente', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Pedro'), pg_temp.id('Juan'));
INSERT INTO contactos_personas (id, nombre, responsable_id, creado_por)
VALUES (pg_temp.id('Marta'), 'Zqx190 Marta Gómez', pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Rosa'), 'Zqx190 Rosa Paz', pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO contactos_vinculos (id, persona_id, ente, registro_id, roles, creado_por)
VALUES (pg_temp.id('VM'), pg_temp.id('Marta'), 'obra', pg_temp.id('Belgrano'), '{referente}', pg_temp.id('Juan')),
       (pg_temp.id('VR'), pg_temp.id('Rosa'), 'obra', pg_temp.id('Belgrano'), '{referente}', pg_temp.id('Juan'));

INSERT INTO ids VALUES ('P1', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx190 Ventanas', 'USD_OFICIAL', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('V1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1')));
INSERT INTO ids VALUES ('S1', (SELECT id FROM presupuestos_secciones WHERE version_id = pg_temp.id('V1')));
SELECT pg_temp.caso('00 renglón a mano de 1000', 'uuid', CASE WHEN pg_temp.consultar(format(
  $s$INSERT INTO presupuestos_renglones (version_id, seccion_id, tipo, descripcion, precio) VALUES (%L, %L, 'mano', 'Flete cerrado', 1000) RETURNING id::text$s$,
  pg_temp.id('V1'), pg_temp.id('S1')), 'Juan') ~ '^[0-9a-f-]{36}$' THEN 'uuid' END);

CREATE FUNCTION pg_temp.importe(p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT coalesce(sum(importe), 0)::text FROM presupuestos_version_importes(%L)', pg_temp.id('V1')), p_como);
$f$;
CREATE FUNCTION pg_temp.recargo(p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format('SELECT porcentaje::text FROM presupuestos_recargos WHERE version_id = %L', pg_temp.id('V1')), p_como), 'nada');
$f$;
CREATE FUNCTION pg_temp.comision(p_vinculo text, p_pct numeric, p_monto numeric) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT obras_registrar_comision(%L, %s, %s)', pg_temp.id(p_vinculo),
    coalesce(p_pct::text, 'NULL'), coalesce(p_monto::text, 'NULL')), 'Juan');
$f$;

-- 01. Borrador: sigue a lo vigente
SELECT pg_temp.caso('01 sin comisión, el importe es el precio', '1000.00', pg_temp.importe('Juan'));
SELECT pg_temp.caso('01 una comisión en monto no se suma', 'ok/1000.00', pg_temp.comision('VM', NULL, 5000) || '/' || pg_temp.importe('Juan'));
SELECT pg_temp.caso('01 Marta al 5 %: 1000 / 0,95', 'ok/1052.63', pg_temp.comision('VM', 5, NULL) || '/' || pg_temp.importe('Juan'));
SELECT pg_temp.caso('01 Pedro (no la ve) recibe el mismo importe', '1052.63', pg_temp.importe('Pedro'));
SELECT pg_temp.caso('01 Rosa al 3 %: se suman, 1000 / 0,92', 'ok/1086.96', pg_temp.comision('VR', 3, NULL) || '/' || pg_temp.importe('Juan'));
SELECT pg_temp.caso('01 los totales siguen al importe', '1086.96', (
  SELECT pg_temp.consultar(format('SELECT subtotal::text FROM presupuestos_version_totales(%L)', pg_temp.id('V1')), 'Juan')));
SELECT pg_temp.caso('01 un participante sin la obra: nada', '0', pg_temp.importe('Rosa'));
SELECT pg_temp.caso('01 en borrador no hay nada guardado', 'nada', pg_temp.recargo('Juan'));

-- 02. Al salir de borrador queda fijo
UPDATE presupuestos_versiones SET estado = 'en_revision' WHERE id = pg_temp.id('V1');
SELECT pg_temp.caso('02 queda guardado el 8 %', '8.00', pg_temp.recargo('Juan'));
SELECT pg_temp.caso('02 Pedro no lo lee', 'nada', pg_temp.recargo('Pedro'));
SELECT pg_temp.caso('02 Marta pasa al 3 %: la versión no cambia', 'ok/1086.96', pg_temp.comision('VM', 3, NULL) || '/' || pg_temp.importe('Juan'));
SELECT pg_temp.caso('02 ni nadie puede escribirlo', '42501', pg_temp.intentar(format(
  'UPDATE presupuestos_recargos SET porcentaje = 0 WHERE version_id = %L', pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('02 ni calcular el recargo directo', '42501', pg_temp.intentar(format(
  'SELECT presupuestos_recargo_de(%L)', pg_temp.id('V1')), 'Juan'));

-- 03. Vuelve a borrador: sigue a lo vigente (3 + 3)
UPDATE presupuestos_versiones SET estado = 'borrador' WHERE id = pg_temp.id('V1');
SELECT pg_temp.caso('03 de vuelta en borrador, 6 %: 1000 / 0,94', '1063.83', pg_temp.importe('Juan'));
UPDATE presupuestos_versiones SET estado = 'publicado' WHERE id = pg_temp.id('V1');
SELECT pg_temp.caso('03 al salir otra vez se actualiza a 6 %', '6.00', pg_temp.recargo('Juan'));
UPDATE presupuestos_versiones SET estado = 'borrador' WHERE id = pg_temp.id('V1');

-- 04. Comisiones que llegan al 100 %
SELECT pg_temp.caso('04 Marta al 100 % y Rosa al 3 %', 'ok', pg_temp.comision('VM', 100, NULL));
SELECT pg_temp.caso('04 suma de 103 %: PR020', 'PR020', pg_temp.consultar(format(
  'SELECT sum(importe)::text FROM presupuestos_version_importes(%L)', pg_temp.id('V1')), 'Juan'));
CREATE FUNCTION pg_temp.directo(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
BEGIN
  EXECUTE p_sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END;
$f$;
SELECT pg_temp.caso('04 salir de borrador con 103 %: PR020', 'PR020', pg_temp.directo(format(
  $s$UPDATE presupuestos_versiones SET estado = 'en_revision' WHERE id = %L$s$, pg_temp.id('V1'))));

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
