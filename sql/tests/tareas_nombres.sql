-- Verificación de sql/120: nombres de quienes aparecen en lo que se ve. NO es
-- una migración: todo corre dentro de una transacción que termina en ROLLBACK.
-- Correr después de aplicar sql/112 a sql/120.
--
-- Mundo: G admin de usuarios (sin tareas_ver); A admin de tareas; equipo T
-- con D delegador y M1; equipo U con E delegador; I1 independiente. H1 de M1
-- con un paso de D y una nota de D; H2 de I1, que después se da de baja. M1
-- tiene una plantilla con un paso asignado al equipo U.
--
-- `ve(X, Y)`: si X recibe el nombre de Y.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated, service_role;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

CREATE FUNCTION pg_temp.como(p_nombre text) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_nombre)), true);
$f$;

CREATE FUNCTION pg_temp.ve(p_como text, p_de text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v boolean;
BEGIN
  PERFORM pg_temp.como(p_como);
  PERFORM set_config('role', 'authenticated', true);
  SELECT EXISTS (SELECT 1 FROM tareas_nombres() n WHERE n.id = pg_temp.id(p_de)) INTO v;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v::text;
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','A','D','M1','E','I1','T','U','H1','H2','P1']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','tareas_ver','tareas_pedir',
                            'tareas_plantillas','tareas_todas','tareas_administrar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test120.local', jsonb_build_object('nombre', 'test120 ' || nombre)
FROM ids WHERE nombre IN ('G','A','D','M1','E','I1');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test120 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['T','U']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('T','D'),('T','M1'),('U','E')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('A','tareas_ver'), ('A','tareas_pedir'), ('A','tareas_todas'), ('A','tareas_administrar'),
  ('D','tareas_ver'), ('M1','tareas_ver'), ('M1','tareas_plantillas'), ('E','tareas_ver'),
  ('I1','tareas_ver')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SET LOCAL role service_role;
SELECT designar_delegador(pg_temp.id('G'), pg_temp.id('D'));
SELECT designar_delegador(pg_temp.id('G'), pg_temp.id('E'));
RESET role;

SELECT pg_temp.como('M1');
INSERT INTO tareas_hilos (id, titulo) VALUES (pg_temp.id('H1'), 'H1');
INSERT INTO tareas (hilo_id, titulo, asignado_id) VALUES (pg_temp.id('H1'), 'paso de D', pg_temp.id('D'));
INSERT INTO tareas_plantillas (id, nombre) VALUES (pg_temp.id('P1'), 'P1');
INSERT INTO tareas_plantillas_pasos (plantilla_id, orden, titulo, asignado_equipo_id)
VALUES (pg_temp.id('P1'), 1, 'al equipo U', pg_temp.id('U'));

SELECT pg_temp.como('D');
INSERT INTO tareas_notas (hilo_id, texto) VALUES (pg_temp.id('H1'), 'nota de D');

SELECT pg_temp.como('I1');
INSERT INTO tareas_hilos (id, titulo) VALUES (pg_temp.id('H2'), 'H2');
INSERT INTO tareas (hilo_id, titulo, asignado_id) VALUES (pg_temp.id('H2'), 'suyo', pg_temp.id('I1'));
SELECT set_config('request.jwt.claims', '', true);

-- ============================================================
-- Casos
-- ============================================================
SELECT pg_temp.caso('01 M1 ve a D, asignado de su hilo', 'true', pg_temp.ve('M1', 'D'));
SELECT pg_temp.caso('02 M1 se ve a sí mismo', 'true', pg_temp.ve('M1', 'M1'));
SELECT pg_temp.caso('03 D ve a M1, responsable del hilo donde participa', 'true', pg_temp.ve('D', 'M1'));
SELECT pg_temp.caso('04 E no ve a M1: no participa', 'false', pg_temp.ve('E', 'M1'));
SELECT pg_temp.caso('05 M1 no ve a I1: no comparten hilo', 'false', pg_temp.ve('M1', 'I1'));
SELECT pg_temp.caso('06 M1 ve al equipo U, de su plantilla', 'true', pg_temp.ve('M1', 'U'));
SELECT pg_temp.caso('07 D no ve al equipo U: la plantilla no es suya', 'false', pg_temp.ve('D', 'U'));
SELECT pg_temp.caso('08 A ve a I1', 'true', pg_temp.ve('A', 'I1'));
SELECT pg_temp.caso('09 G, sin tareas_ver, no ve nada', 'false', pg_temp.ve('G', 'M1'));

UPDATE usuarios SET activo = false WHERE id = pg_temp.id('I1');
SELECT pg_temp.caso('10 A ve a I1 dado de baja, responsable de un huérfano', 'true', pg_temp.ve('A', 'I1'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
