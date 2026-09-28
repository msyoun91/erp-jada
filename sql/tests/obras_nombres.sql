-- Verificación de sql/130: usuarios_con_permiso, obras_nombres y
-- contactos_nombres. NO es una migración: todo corre dentro de una
-- transacción que termina en ROLLBACK. Correr después de aplicar sql/125 a
-- sql/130.
--
-- Mundo: equipo Norte (A vendedor con obras_ver+obras_crear+contactos_ver, B
-- vendedor con obras_ver+contactos_ver) y equipo Sur (C vendedor con
-- obras_ver+obras_crear+contactos_ver, sin relación con Norte). D tiene
-- obras_ver+contactos_ver, sin equipo. SinPermiso no tiene obras_ver.
-- Inactivo tenía obras_ver pero está desactivado. Ob1 es de A (con B
-- participante); Ob2 es de C, sin relación con A. Persona1 es de A; PersonaC
-- es de C, sin vínculos. EmpresaA la carga A (queda del equipo Norte). Todo
-- marcado con Zqx130.

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

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text DEFAULT NULL) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
BEGIN
  IF p_como IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
    PERFORM set_config('role', 'authenticated', true);
  ELSE
    PERFORM set_config('role', 'service_role', true);
  END IF;
  EXECUTE p_sql;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_n int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE format('SELECT count(*) FROM (%s) x', p_sql) INTO v_n;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_n::text;
END;
$f$;

CREATE FUNCTION pg_temp.crear_obra(p_id text, p_nombre text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, %L, 'Calle Zqx130', 'otro', 'casa')$s$,
    pg_temp.id(p_id), p_nombre), p_como);
$f$;

CREATE FUNCTION pg_temp.sumar_participante(p_obra text, p_usuario text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('INSERT INTO obras_participantes (id, obra_id, usuario_id) VALUES (%L, %L, %L)',
    gen_random_uuid(), pg_temp.id(p_obra), pg_temp.id(p_usuario)), p_como);
$f$;

CREATE FUNCTION pg_temp.transferir(p_obra text, p_a text, p_quedarme boolean, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT obras_transferir(%L, %L, %L)',
    pg_temp.id(p_obra), pg_temp.id(p_a), p_quedarme), p_como);
$f$;

CREATE FUNCTION pg_temp.crear_persona(p_id text, p_nombre text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO contactos_personas (id, nombre) VALUES (%L, %L)', pg_temp.id(p_id), p_nombre), p_como);
$f$;

CREATE FUNCTION pg_temp.crear_empresa(p_id text, p_nombre text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO contactos_empresas (id, nombre) VALUES (%L, %L)', pg_temp.id(p_id), p_nombre), p_como);
$f$;

CREATE FUNCTION pg_temp.vincular_persona(p_persona text, p_ente text, p_registro text, p_roles text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO contactos_vinculos (persona_id, ente, registro_id, roles) VALUES (%L, %L, %L, %L::text[])',
    pg_temp.id(p_persona), p_ente, pg_temp.id(p_registro), p_roles), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['A','B','C','D','SinPermiso','Inactivo','Norte','Sur',
                  'Ob1','Ob2','Persona1','PersonaC','EmpresaA']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos WHERE activo AND codigo IN ('contactos_ver','obras_ver','obras_crear');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test130.local', jsonb_build_object('nombre', 'Zqx130 ' || nombre)
FROM ids WHERE nombre IN ('A','B','C','D','SinPermiso','Inactivo');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'Zqx130 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['Norte','Sur']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('Norte','A'),('Norte','B'),('Sur','C')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('A','contactos_ver'), ('A','obras_ver'), ('A','obras_crear'),
  ('B','contactos_ver'), ('B','obras_ver'),
  ('C','contactos_ver'), ('C','obras_ver'), ('C','obras_crear'),
  ('D','contactos_ver'), ('D','obras_ver'),
  ('Inactivo','contactos_ver'), ('Inactivo','obras_ver')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- Tramo 3: lo que cargan quienes pueden aprobar no se congela. Este test
-- prueba reglas de antes, con obras y contactos que se parecen entre sí; el
-- congelado lo prueba `sql/tests/duplicados.sql`.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT DISTINCT us.usuario_id, f.id
FROM usuario_submodulos us
JOIN ids i          ON i.id = us.usuario_id
JOIN submodulos v   ON v.id = us.submodulo_id AND v.codigo IN ('obras_ver', 'contactos_ver')
JOIN submodulos f   ON f.activo AND f.codigo = replace(v.codigo, '_ver', '_aprobar')
WHERE us.activo;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

UPDATE usuarios SET activo = false WHERE id = pg_temp.id('Inactivo');

SELECT pg_temp.caso('00 montaje: A crea Ob1', 'ok', pg_temp.crear_obra('Ob1', 'Zqx130 Ob1', 'A'));
SELECT pg_temp.caso('00 montaje: A suma a B en Ob1', 'ok', pg_temp.sumar_participante('Ob1', 'B', 'A'));
SELECT pg_temp.caso('00 montaje: C crea Ob2', 'ok', pg_temp.crear_obra('Ob2', 'Zqx130 Ob2', 'C'));
SELECT pg_temp.caso('00 montaje: A crea Persona1', 'ok', pg_temp.crear_persona('Persona1', 'Zqx130 Persona1', 'A'));
SELECT pg_temp.caso('00 montaje: C crea PersonaC', 'ok', pg_temp.crear_persona('PersonaC', 'Zqx130 PersonaC', 'C'));
SELECT pg_temp.caso('00 montaje: A crea EmpresaA', 'ok', pg_temp.crear_empresa('EmpresaA', 'Zqx130 EmpresaA', 'A'));

-- ============================================================
-- usuarios_con_permiso
-- ============================================================
SELECT pg_temp.caso('01 SinPermiso (sin obras_ver) -> 0 filas', '0',
  pg_temp.ve($q$SELECT * FROM usuarios_con_permiso('obras_ver')$q$, 'SinPermiso'));

SELECT pg_temp.caso('02 A (con obras_ver) ve a A', '1',
  pg_temp.ve(format($q$SELECT 1 FROM usuarios_con_permiso('obras_ver') WHERE id = %L$q$, pg_temp.id('A')), 'A'));
SELECT pg_temp.caso('02 A ve a B', '1',
  pg_temp.ve(format($q$SELECT 1 FROM usuarios_con_permiso('obras_ver') WHERE id = %L$q$, pg_temp.id('B')), 'A'));
SELECT pg_temp.caso('02 A ve a C', '1',
  pg_temp.ve(format($q$SELECT 1 FROM usuarios_con_permiso('obras_ver') WHERE id = %L$q$, pg_temp.id('C')), 'A'));
SELECT pg_temp.caso('02 A ve a D', '1',
  pg_temp.ve(format($q$SELECT 1 FROM usuarios_con_permiso('obras_ver') WHERE id = %L$q$, pg_temp.id('D')), 'A'));
SELECT pg_temp.caso('02 A no ve a SinPermiso (activo, sin obras_ver)', '0',
  pg_temp.ve(format($q$SELECT 1 FROM usuarios_con_permiso('obras_ver') WHERE id = %L$q$, pg_temp.id('SinPermiso')), 'A'));
SELECT pg_temp.caso('02 A no ve a Inactivo (tenía obras_ver, desactivado)', '0',
  pg_temp.ve(format($q$SELECT 1 FROM usuarios_con_permiso('obras_ver') WHERE id = %L$q$, pg_temp.id('Inactivo')), 'A'));

-- ============================================================
-- obras_nombres
-- ============================================================
SELECT pg_temp.caso('03 obras_nombres para A: exactamente A y B', '2',
  pg_temp.ve('SELECT * FROM obras_nombres()', 'A'));
SELECT pg_temp.caso('03 obras_nombres para A trae a A', '1',
  pg_temp.ve(format('SELECT 1 FROM obras_nombres() WHERE id = %L', pg_temp.id('A')), 'A'));
SELECT pg_temp.caso('03 obras_nombres para A trae a B', '1',
  pg_temp.ve(format('SELECT 1 FROM obras_nombres() WHERE id = %L', pg_temp.id('B')), 'A'));

SELECT pg_temp.caso('04 A no ve Ob2 (de C, sin relación)', '0',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Ob2')), 'A'));
SELECT pg_temp.caso('04 obras_nombres para A no trae a C', '0',
  pg_temp.ve(format('SELECT 1 FROM obras_nombres() WHERE id = %L', pg_temp.id('C')), 'A'));

-- ============================================================
-- contactos_nombres
-- ============================================================
SELECT pg_temp.caso('07 contactos_nombres para A trae a A (dueño de Persona1)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_nombres() WHERE id = %L', pg_temp.id('A')), 'A'));
SELECT pg_temp.caso('07 contactos_nombres para A no trae a C (dueño de PersonaC, sin vínculo)', '0',
  pg_temp.ve(format('SELECT 1 FROM contactos_nombres() WHERE id = %L', pg_temp.id('C')), 'A'));

SELECT pg_temp.caso('08 contactos_nombres para B (Norte) trae al equipo Norte', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_nombres() WHERE id = %L', pg_temp.id('Norte')), 'B'));
SELECT pg_temp.caso('08 contactos_nombres para C (Sur, no ve EmpresaA) no trae a Norte', '0',
  pg_temp.ve(format('SELECT 1 FROM contactos_nombres() WHERE id = %L', pg_temp.id('Norte')), 'C'));

SELECT pg_temp.caso('09 montaje: A vincula a Persona1 con Ob1', 'ok',
  pg_temp.vincular_persona('Persona1', 'obra', 'Ob1', '{referente}', 'A'));
SELECT pg_temp.caso('09 montaje: B (participante de Ob1, la trabaja) edita a Persona1', 'ok',
  pg_temp.intentar(format('UPDATE contactos_personas SET nombre = %L WHERE id = %L',
    'Zqx130 Persona1 editada', pg_temp.id('Persona1')), 'B'));
SELECT pg_temp.caso('09 contactos_nombres para A (dueño de Persona1) trae a B (editó, vía Ob1)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_nombres() WHERE id = %L', pg_temp.id('B')), 'A'));

-- ============================================================
-- obras_nombres: transferencia con quedarme
-- ============================================================
SELECT pg_temp.caso('05 A transfiere Ob1 a D, quedándose', 'ok',
  pg_temp.transferir('Ob1', 'D', true, 'A'));
SELECT pg_temp.caso('05 A sigue viendo Ob1 (quedó participante)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Ob1')), 'A'));
SELECT pg_temp.caso('05 obras_nombres para A trae a A', '1',
  pg_temp.ve(format('SELECT 1 FROM obras_nombres() WHERE id = %L', pg_temp.id('A')), 'A'));
SELECT pg_temp.caso('05 obras_nombres para A trae a D', '1',
  pg_temp.ve(format('SELECT 1 FROM obras_nombres() WHERE id = %L', pg_temp.id('D')), 'A'));

SELECT pg_temp.caso('06 SinPermiso (sin obras_ver) -> 0 filas', '0',
  pg_temp.ve('SELECT * FROM obras_nombres()', 'SinPermiso'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
