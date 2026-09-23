-- Verificación de sql/110: reglas `requiere` y `excluye` entre permisos. NO es
-- una migración: corre dentro de una transacción que termina en ROLLBACK.
--
-- Arma su propio mundo: A admin, P independiente, y un módulo `prueba110` con
-- cuatro vistas: R1 requiere R2, E1 excluye E2. Además prueba la regla real de
-- `sql/110`: Equipos excluye Mi equipo.
--
-- `intentar` es el de `usuarios_equipos.sql`: fuerza los chequeos diferidos y
-- devuelve 'ok' o el SQLSTATE.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.ids(VARIADIC p_nombres text[]) RETURNS uuid[] LANGUAGE sql AS $f$
  SELECT coalesce(array_agg(pg_temp.id(n)), '{}') FROM unnest(p_nombres) AS n;
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

CREATE FUNCTION pg_temp.intentar(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
BEGIN
  EXECUTE p_sql;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.asignar(p_usuario text, VARIADIC p_subs text[]) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id(p_usuario), pg_temp.ids(VARIADIC p_subs)));
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['A','P','R1','R2','E1','E2']) AS n;

INSERT INTO ids (nombre, id)
SELECT replace(codigo, 'usuarios_', ''), id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','usuarios_equipos','usuarios_equipo');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test110.local', jsonb_build_object('nombre', 'test110 ' || nombre)
FROM ids WHERE nombre IN ('A','P');

INSERT INTO submodulos (id, codigo, modulo, tipo, nombre, orden, vista_id) VALUES
  (pg_temp.id('R1'), 'prueba110_r1', 'prueba110', 'vista', 'R1', 1, NULL),
  (pg_temp.id('R2'), 'prueba110_r2', 'prueba110', 'vista', 'R2', 2, NULL),
  (pg_temp.id('E1'), 'prueba110_e1', 'prueba110', 'vista', 'E1', 3, NULL),
  (pg_temp.id('E2'), 'prueba110_e2', 'prueba110', 'vista', 'E2', 4, NULL);

INSERT INTO submodulo_reglas (submodulo_id, otro_id, tipo) VALUES
  (pg_temp.id('R1'), pg_temp.id('R2'), 'requiere'),
  (pg_temp.id('E1'), pg_temp.id('E2'), 'excluye');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
VALUES (pg_temp.id('A'), pg_temp.id('ver')), (pg_temp.id('A'), pg_temp.id('gestionar'));

-- ============================================================
-- requiere
-- ============================================================
SELECT pg_temp.caso('01 R1 sin R2', 'US016', pg_temp.asignar('P', 'R1'));
SELECT pg_temp.caso('02 R1 con R2', 'ok', pg_temp.asignar('P', 'R1', 'R2'));
SELECT pg_temp.caso('03 sacar R2 dejando R1', 'US016', pg_temp.asignar('P', 'R1'));
SELECT pg_temp.caso('04 R2 sin R1: la regla va en un sentido', 'ok', pg_temp.asignar('P', 'R2'));

-- ============================================================
-- excluye
-- ============================================================
SELECT pg_temp.caso('05 E1 y E2 juntos', 'US017', pg_temp.asignar('P', 'E1', 'E2'));
SELECT pg_temp.caso('06 E2 solo', 'ok', pg_temp.asignar('P', 'E2'));
SELECT pg_temp.caso('07 E1 sobre E2 existente, por insert directo',
  'US017', pg_temp.intentar(format('INSERT INTO usuario_submodulos (usuario_id, submodulo_id) VALUES (%L, %L)',
    pg_temp.id('P'), pg_temp.id('E1'))));
SELECT pg_temp.caso('08 real: Equipos y Mi equipo', 'US017', pg_temp.asignar('P', 'equipos', 'equipo'));
SELECT pg_temp.caso('09 real: Equipos solo', 'ok', pg_temp.asignar('P', 'equipos'));

-- ============================================================
-- Lo inactivo no pesa
-- ============================================================
UPDATE submodulo_reglas SET activo = false WHERE submodulo_id = pg_temp.id('R1');
SELECT pg_temp.caso('10 regla desactivada', 'ok', pg_temp.asignar('P', 'R1'));

SELECT pg_temp.caso('11 montaje: P con E2', 'ok', pg_temp.asignar('P', 'E2'));
UPDATE submodulos SET activo = false WHERE id = pg_temp.id('E2');
SELECT pg_temp.caso('11 E1 con E2 retirado del catálogo',
  'ok', pg_temp.intentar(format('INSERT INTO usuario_submodulos (usuario_id, submodulo_id) VALUES (%L, %L)',
    pg_temp.id('P'), pg_temp.id('E1'))));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
