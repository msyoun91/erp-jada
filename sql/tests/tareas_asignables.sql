-- Verificación de sql/116: a quién asignar o pedir. NO es una migración: todo
-- corre dentro de una transacción que termina en ROLLBACK. Correr después de
-- aplicar sql/112 a sql/116.
--
-- Mundo: G admin de usuarios (sin tareas_ver); A admin de tareas (sin
-- equipo); equipo T con D delegador y M1; equipo U con E delegador; equipo V
-- sin delegador; I1 independiente. Nada depende de los datos reales.
--
-- `fila(X, Y)`: la fila de Y como la ve X, 'pedido|puede_recibir'.

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

CREATE FUNCTION pg_temp.fila(p_como text, p_de text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT a.pedido || '|' || a.puede_recibir INTO v
  FROM tareas_asignables() a
  WHERE pg_temp.id(p_de) IN (a.usuario_id, a.equipo_id);
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN coalesce(v, '-');
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','A','D','M1','E','I1','T','U','V']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','tareas_ver','tareas_pedir',
                            'tareas_todas','tareas_administrar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test116.local', jsonb_build_object('nombre', 'test116 ' || nombre)
FROM ids WHERE nombre IN ('G','A','D','M1','E','I1');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test116 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['T','U','V']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('T','D'),('T','M1'),('U','E')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('A','tareas_ver'), ('A','tareas_pedir'), ('A','tareas_todas'), ('A','tareas_administrar'),
  ('D','tareas_ver'), ('M1','tareas_ver'), ('E','tareas_ver'), ('I1','tareas_ver')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SET LOCAL role service_role;
SELECT designar_delegador(pg_temp.id('G'), pg_temp.id('D'));
SELECT designar_delegador(pg_temp.id('G'), pg_temp.id('E'));
RESET role;

-- ============================================================
-- Casos
-- ============================================================
SELECT pg_temp.caso('01 M1 a sí mismo: asigna', 'false|true', pg_temp.fila('M1', 'M1'));
SELECT pg_temp.caso('02 M1 a su delegador: asigna', 'false|true', pg_temp.fila('M1', 'D'));
SELECT pg_temp.caso('03 M1 a su equipo: asigna', 'false|true', pg_temp.fila('M1', 'T'));
SELECT pg_temp.caso('04 M1 a E, otro equipo: pide', 'true|true', pg_temp.fila('M1', 'E'));
SELECT pg_temp.caso('05 M1 al equipo U: pide', 'true|true', pg_temp.fila('M1', 'U'));
SELECT pg_temp.caso('06 M1 al equipo V, sin delegador: no recibe', 'true|false', pg_temp.fila('M1', 'V'));
SELECT pg_temp.caso('07 M1 a G, sin tareas_ver: no recibe', 'true|false', pg_temp.fila('M1', 'G'));
SELECT pg_temp.caso('08 M1 a I1: pide', 'true|true', pg_temp.fila('M1', 'I1'));
SELECT pg_temp.caso('09 I1 a sí mismo: asigna', 'false|true', pg_temp.fila('I1', 'I1'));
SELECT pg_temp.caso('10 I1 a M1: pide', 'true|true', pg_temp.fila('I1', 'M1'));
SELECT pg_temp.caso('11 I1 al equipo T: pide', 'true|true', pg_temp.fila('I1', 'T'));
SELECT pg_temp.caso('12 A a M1: asigna directo', 'false|true', pg_temp.fila('A', 'M1'));
SELECT pg_temp.caso('13 A al equipo U: asigna directo', 'false|true', pg_temp.fila('A', 'U'));
SELECT pg_temp.caso('14 G, sin tareas_ver, no ve nada', '-', pg_temp.fila('G', 'M1'));

UPDATE usuarios SET activo = false WHERE id = pg_temp.id('I1');
SELECT pg_temp.caso('15 I1 inactivo no aparece', '-', pg_temp.fila('M1', 'I1'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
