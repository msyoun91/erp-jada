-- Verificación de sql/140: una empresa se comparte con otro equipo. NO es una
-- migración: todo corre dentro de una transacción que revierte. Termina en un
-- DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: equipo Norte (Juan) y Sur (Pedro; Laura). Ana administra contactos.
-- Norte tiene la Constructora Caputo y Hormigones Mayo (congelada). Pedro
-- tiene Casa Núñez y Casa Olivos, y a Rosa Pérez. El montaje escribe como
-- superusuario; todo lo demás, como cada uno. Nombres con `Zqx140`.

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

CREATE FUNCTION pg_temp.alta(p_nombre_ids text, p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql INTO v_id;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  INSERT INTO ids (nombre, id) VALUES (p_nombre_ids, v_id);
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
FROM unnest(ARRAY['Juan','Pedro','Laura','Ana','Norte','Sur','Nada',
                  'Caputo','Mayo','Nunez','Olivos','Rosa']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','contactos_administrar','obras_ver','obras_crear');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test140.local', jsonb_build_object('nombre', 'test140 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro','Laura','Ana');

INSERT INTO equipos (id, nombre)
SELECT id, 'test140 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n) FROM (VALUES ('Norte','Juan'),('Sur','Pedro'),('Sur','Laura')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('Laura','contactos_ver'),
  ('Ana','contactos_ver'), ('Ana','contactos_administrar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Nunez'), 'Zqx140 Casa Núñez', 'Calle Falsa 4321', 'otro', 'casa',
        pg_temp.id('Pedro'), pg_temp.id('Pedro')),
       (pg_temp.id('Olivos'), 'Zqx140 Casa Olivos', 'Calle Verdadera 99', 'otro', 'casa',
        pg_temp.id('Pedro'), pg_temp.id('Pedro'));
INSERT INTO contactos_personas (id, nombre, responsable_id, creado_por)
VALUES (pg_temp.id('Rosa'), 'Zqx140 Rosa Pérez', pg_temp.id('Pedro'), pg_temp.id('Pedro'));
INSERT INTO contactos_empresas (id, nombre, creado_por)
VALUES (pg_temp.id('Caputo'), 'Zqx140 Constructora Caputo', pg_temp.id('Juan')),
       (pg_temp.id('Mayo'), 'Zqx140 Hormigones Mayo', pg_temp.id('Juan'));
UPDATE contactos_empresas SET congelada = true WHERE id = pg_temp.id('Mayo');

SELECT pg_temp.caso('00 Caputo es de Norte', pg_temp.id('Norte')::text,
  (SELECT equipo_id::text FROM contactos_empresas WHERE id = pg_temp.id('Caputo')));

-- ============================================================
-- 01. Sin compartir, Pedro no la tiene
-- ============================================================
SELECT pg_temp.caso('01 Pedro no ve Caputo', '0', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('01 el buscador de Pedro no la trae', '0', pg_temp.ve(
  $s$SELECT 1 FROM contactos_vinculables('Zqx140 Constructora')$s$, 'Pedro'));
SELECT pg_temp.caso('01 aviso a ciegas: sin id', '1', pg_temp.ve(
  $s$SELECT 1 FROM contactos_parecidas('empresa', 'Zqx140 Constructora Caputo')
     WHERE nombre = 'Zqx140 Constructora Caputo' AND id IS NULL$s$, 'Pedro'));
SELECT pg_temp.caso('01 Pedro no la vincula a Núñez', 'CO016', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (empresa_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{constructora}')$s$,
  pg_temp.id('Caputo'), pg_temp.id('Nunez')), 'Pedro'));

-- ============================================================
-- 02. Quién comparte y con quién
-- ============================================================
SELECT pg_temp.caso('02 Pedro no comparte una empresa de Norte', 'CO027', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, true)', pg_temp.id('Caputo'), pg_temp.id('Sur')), 'Pedro'));
SELECT pg_temp.caso('02 no con su propio equipo', 'CO028', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, true)', pg_temp.id('Caputo'), pg_temp.id('Norte')), 'Juan'));
SELECT pg_temp.caso('02 no con un equipo que no existe', 'CO028', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, true)', pg_temp.id('Caputo'), pg_temp.id('Nada')), 'Juan'));
SELECT pg_temp.caso('02 congelada no se comparte', 'CO020', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, true)', pg_temp.id('Mayo'), pg_temp.id('Sur')), 'Juan'));
SELECT pg_temp.caso('02 Pedro ve los equipos para elegir', '2', pg_temp.ve(
  $s$SELECT 1 FROM contactos_equipos() WHERE nombre LIKE 'test140 %'$s$, 'Pedro'));
SELECT pg_temp.caso('02 no se escribe directo', '42501', pg_temp.intentar(format(
  'INSERT INTO contactos_empresa_equipos (empresa_id, equipo_id, compartida_por) VALUES (%L, %L, %L)',
  pg_temp.id('Caputo'), pg_temp.id('Sur'), pg_temp.id('Pedro')), 'Pedro'));

-- ============================================================
-- 03. Juan la comparte con Sur
-- ============================================================
SELECT pg_temp.caso('03 Juan comparte', 'ok', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, true)', pg_temp.id('Caputo'), pg_temp.id('Sur')), 'Juan'));
SELECT pg_temp.caso('03 dos veces no duplica', 'ok', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, true)', pg_temp.id('Caputo'), pg_temp.id('Sur')), 'Juan'));
SELECT pg_temp.caso('03 una fila activa, a nombre de Juan', '1', (
  SELECT count(*)::text FROM contactos_empresa_equipos
  WHERE empresa_id = pg_temp.id('Caputo') AND activo AND compartida_por = pg_temp.id('Juan')));
SELECT pg_temp.caso('03 Pedro la ve', '1', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('03 Laura la ve', '1', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo')), 'Laura'));
SELECT pg_temp.caso('03 Pedro ve con quién está compartida', '1', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresa_equipos WHERE empresa_id = %L', pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('03 el buscador de Pedro la trae', '1', pg_temp.ve(
  $s$SELECT 1 FROM contactos_vinculables('Zqx140 Constructora')$s$, 'Pedro'));
SELECT pg_temp.caso('03 aviso a ciegas: con id', pg_temp.id('Caputo')::text, pg_temp.consultar(
  $s$SELECT id::text FROM contactos_parecidas('empresa', 'Zqx140 Constructora Caputo')
     WHERE nombre = 'Zqx140 Constructora Caputo'$s$, 'Pedro'));

-- ============================================================
-- 04. Sur la vincula y la corrige como propia; sigue siendo de Norte
-- ============================================================
SELECT pg_temp.caso('04 Pedro la vincula a Núñez', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (empresa_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{constructora}')$s$,
  pg_temp.id('Caputo'), pg_temp.id('Nunez')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro suma a Rosa en Caputo', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_persona_empresa (persona_id, empresa_id, cargo) VALUES (%L, %L, 'Compras')$s$,
  pg_temp.id('Rosa'), pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro la corrige', '1', pg_temp.consultar(format(
  $s$WITH u AS (UPDATE contactos_empresas SET notas = 'Zqx140 nota de Sur' WHERE id = %L RETURNING 1)
     SELECT count(*)::text FROM u$s$, pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro no la desactiva', 'CO007', pg_temp.intentar(format(
  'SELECT contactos_desactivar_empresa(%L)', pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro no deja de compartirla', 'CO027', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, false)', pg_temp.id('Caputo'), pg_temp.id('Sur')), 'Pedro'));
SELECT pg_temp.caso('04 Pedro no le cambia el equipo', 'CO008', pg_temp.intentar(format(
  'UPDATE contactos_empresas SET equipo_id = %L WHERE id = %L', pg_temp.id('Sur'), pg_temp.id('Caputo')), 'Pedro'));

-- ============================================================
-- 05. Juan deja de compartir: los vínculos quedan
-- ============================================================
SELECT pg_temp.caso('05 Juan deja de compartir', 'ok', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, false)', pg_temp.id('Caputo'), pg_temp.id('Sur')), 'Juan'));
SELECT pg_temp.caso('05 el vínculo en Núñez sigue', '1', (
  SELECT count(*)::text FROM contactos_vinculos
  WHERE empresa_id = pg_temp.id('Caputo') AND registro_id = pg_temp.id('Nunez') AND activo AND hasta IS NULL));
SELECT pg_temp.caso('05 Pedro la sigue viendo por Núñez', '1', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo')), 'Pedro'));
SELECT pg_temp.caso('05 el buscador de Pedro ya no la trae', '0', pg_temp.ve(
  $s$SELECT 1 FROM contactos_vinculables('Zqx140 Constructora')$s$, 'Pedro'));
SELECT pg_temp.caso('05 Pedro no la vincula a Olivos', 'CO016', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (empresa_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{constructora}')$s$,
  pg_temp.id('Caputo'), pg_temp.id('Olivos')), 'Pedro'));
SELECT pg_temp.caso('05 Laura (no ve Núñez) ya no la ve', '0', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo')), 'Laura'));

-- ============================================================
-- 06. El admin vuelve a compartirla: fila nueva
-- ============================================================
SELECT pg_temp.caso('06 Ana comparte', 'ok', pg_temp.intentar(format(
  'SELECT contactos_compartir_empresa(%L, %L, true)', pg_temp.id('Caputo'), pg_temp.id('Sur')), 'Ana'));
SELECT pg_temp.caso('06 dos filas, una activa', '2/1', (
  SELECT count(*)::text || '/' || (count(*) FILTER (WHERE activo))::text FROM contactos_empresa_equipos
  WHERE empresa_id = pg_temp.id('Caputo')));
SELECT pg_temp.caso('06 Pedro ya la vincula a Olivos', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (empresa_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{constructora}')$s$,
  pg_temp.id('Caputo'), pg_temp.id('Olivos')), 'Pedro'));

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
