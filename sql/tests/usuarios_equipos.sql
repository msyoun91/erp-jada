-- Verificación de sql/105 y sql/106: techo, un delegador por equipo, cascadas,
-- heredero y las escrituras de la pestaña Equipos; desde sql/112, la
-- delegación lleva `tareas_equipo` y requiere `tareas_ver`. NO es una
-- migración: todo corre dentro de una transacción que termina en ROLLBACK.
-- Correr después de aplicar sql/112.
--
-- Arma su propio mundo: cinco usuarios (A admin, D delegador, M1 y M2
-- miembros, I independiente), el equipo T y un módulo `prueba105` con V (vista
-- delegable), F (función de V, delegable), W (vista no delegable) y X (vista
-- delegable que D no tiene al principio). Nada depende de los datos reales.
--
-- `intentar` corre un statement, fuerza los chequeos diferidos con
-- `SET CONSTRAINTS ALL IMMEDIATE` (con ROLLBACK nunca llegaría el commit que los
-- dispara) y devuelve 'ok' o el SQLSTATE. Con `p_como`, corre con la sesión de
-- ese usuario (rol `authenticated`); sin él, como el admin con `service_role`.
-- `fila` resume una asignación como 'on:D' (activa, la otorgó D), 'off:A',
-- 'on:null' o 'none'.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.ids(VARIADIC p_nombres text[]) RETURNS uuid[] LANGUAGE sql AS $f$
  SELECT coalesce(array_agg(pg_temp.id(n)), '{}') FROM unnest(p_nombres) AS n;
$f$;

CREATE FUNCTION pg_temp.fila(p_usuario text, p_sub text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce((
    SELECT CASE WHEN us.activo THEN 'on' ELSE 'off' END || ':' || coalesce(o.nombre, 'null')
    FROM usuario_submodulos us
    LEFT JOIN ids o ON o.id = us.otorgada_por
    WHERE us.usuario_id = pg_temp.id(p_usuario) AND us.submodulo_id = pg_temp.id(p_sub)
  ), 'none');
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
  RETURN SQLSTATE;
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['A','D','M1','M2','I','T','V','F','W','X']) AS n;

INSERT INTO ids (nombre, id)
SELECT replace(codigo, 'usuarios_', ''), id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','usuarios_equipo','usuarios_delegar');

-- Desde sql/112 la delegación requiere `tareas_ver` y `tareas_equipo`.
INSERT INTO ids (nombre, id)
SELECT CASE codigo WHEN 'tareas_ver' THEN 'tver' ELSE 'teq' END, id FROM submodulos
WHERE activo AND codigo IN ('tareas_ver','tareas_equipo');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test105.local', jsonb_build_object('nombre', 'test105 ' || nombre)
FROM ids WHERE nombre IN ('A','D','M1','M2','I');

INSERT INTO submodulos (id, codigo, modulo, tipo, nombre, orden, delegable, vista_id) VALUES
  (pg_temp.id('V'), 'prueba105_v', 'prueba105', 'vista',   'V', 1, true,  NULL),
  (pg_temp.id('F'), 'prueba105_f', 'prueba105', 'funcion', 'F', 1, true,  pg_temp.id('V')),
  (pg_temp.id('W'), 'prueba105_w', 'prueba105', 'vista',   'W', 2, false, NULL),
  (pg_temp.id('X'), 'prueba105_x', 'prueba105', 'vista',   'X', 3, true,  NULL);

-- El admin, como los de antes de sql/104: otorgada_por NULL.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
VALUES (pg_temp.id('A'), pg_temp.id('ver')), (pg_temp.id('A'), pg_temp.id('gestionar'));

INSERT INTO equipos (id, nombre) VALUES (pg_temp.id('T'), 'test105 ' || pg_temp.id('T'));
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id('T'), pg_temp.id(n) FROM unnest(ARRAY['D','M1','M2']) AS n;

-- Quien pueda llegar a delegador tiene `tareas_ver` del admin.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(n), pg_temp.id('tver') FROM unnest(ARRAY['M2','I']) AS n;

SELECT pg_temp.caso('00 montaje: D delegador con V, F, W',
  'ok', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.ids('tver','teq','equipo','delegar','V','F','W'))));

SELECT pg_temp.caso('00 montaje: M1 recibe W del admin',
  'ok', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('M1'), pg_temp.ids('W'))));

-- ============================================================
-- Techo
-- ============================================================
SELECT pg_temp.caso('01 D delega V y F a M1',
  'ok', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M1'), pg_temp.ids('V','F')), 'D'));
SELECT pg_temp.caso('01 M1.F la otorgó D', 'on:D', pg_temp.fila('M1','F'));

SELECT pg_temp.caso('02 función sin su vista',
  'US001', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M2'), pg_temp.ids('F')), 'D'));

SELECT pg_temp.caso('03 W no es delegable',
  'US007', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M2'), pg_temp.ids('W')), 'D'));

SELECT pg_temp.caso('04 X no la tiene D',
  'US008', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M2'), pg_temp.ids('X')), 'D'));

SELECT pg_temp.caso('05 I no es de su equipo',
  '42501', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('I'), pg_temp.ids('V')), 'D'));

SELECT pg_temp.caso('06 M1 no es delegador',
  '42501', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M2'), pg_temp.ids('V')), 'M1'));

SELECT pg_temp.caso('07 D saca todo lo suyo a M1',
  'ok', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M1'), '{}'::uuid[]), 'D'));
SELECT pg_temp.caso('07 M1.V apagada', 'off:D', pg_temp.fila('M1','V'));
SELECT pg_temp.caso('07 M1.W del admin sigue', 'on:A', pg_temp.fila('M1','W'));

SELECT pg_temp.caso('08 D apaga W del admin por PostgREST directo',
  'ok', pg_temp.intentar(format('UPDATE usuario_submodulos SET activo = false WHERE usuario_id = %L AND submodulo_id = %L',
    pg_temp.id('M1'), pg_temp.id('W')), 'D'));
SELECT pg_temp.caso('08 M1.W no se tocó', 'on:A', pg_temp.fila('M1','W'));

SELECT pg_temp.caso('09 D se hace pasar por el admin',
  '42501', pg_temp.intentar(format('INSERT INTO usuario_submodulos (usuario_id, submodulo_id, otorgada_por) VALUES (%L, %L, %L)',
    pg_temp.id('M2'), pg_temp.id('V'), pg_temp.id('A')), 'D'));

-- ============================================================
-- Un delegador por equipo, admin fuera de los equipos
-- ============================================================
SELECT pg_temp.caso('10 segundo delegador en T',
  'US004', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('M2'), pg_temp.ids('tver','teq','equipo','delegar'))));

SELECT pg_temp.caso('11 independiente delegador',
  'US003', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('I'), pg_temp.ids('tver','teq','equipo','delegar'))));

SELECT pg_temp.caso('12 miembro con usuarios_gestionar',
  'US002', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('M1'), pg_temp.ids('W','ver','gestionar'))));

SELECT pg_temp.caso('13 admin entra a un equipo',
  'US002', pg_temp.intentar(format('INSERT INTO equipos_miembros (equipo_id, usuario_id) VALUES (%L, %L)',
    pg_temp.id('T'), pg_temp.id('A'))));

SELECT pg_temp.caso('14 usuarios_ver no se marca delegable',
  '23514', pg_temp.intentar(format('UPDATE submodulos SET delegable = true WHERE id = %L', pg_temp.id('ver'))));

SELECT pg_temp.caso('15 equipo con miembros no se desactiva',
  'US010', pg_temp.intentar(format('UPDATE equipos SET activo = false WHERE id = %L', pg_temp.id('T'))));

SELECT pg_temp.caso('16 cambiar de equipo editando la fila',
  'US015', pg_temp.intentar(format('UPDATE equipos_miembros SET equipo_id = gen_random_uuid() WHERE usuario_id = %L AND activo',
    pg_temp.id('M1'))));

-- ============================================================
-- La salida del delegador pide heredero
-- ============================================================
SELECT pg_temp.caso('17 desactivar a D',
  'US009', pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id('D'))));

SELECT pg_temp.caso('18 sacar a D del equipo',
  'US009', pg_temp.intentar(format('UPDATE equipos_miembros SET activo = false WHERE usuario_id = %L AND activo', pg_temp.id('D'))));

SELECT pg_temp.caso('19 sacarle usuarios_delegar sin heredero',
  'US009', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.ids('tver','teq','equipo','V','F','W'))));

-- ============================================================
-- Cascadas
-- ============================================================
SELECT pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
  pg_temp.id('M1'), pg_temp.ids('V','F')), 'D');

SELECT pg_temp.caso('20 el admin le saca F a D',
  'ok', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.ids('tver','teq','equipo','delegar','V','W'))));
SELECT pg_temp.caso('20 M1.F se fue con él', 'off:D', pg_temp.fila('M1','F'));
SELECT pg_temp.caso('20 M1.V se queda', 'on:D', pg_temp.fila('M1','V'));

SELECT pg_temp.caso('21 M1 sale del equipo',
  'ok', pg_temp.intentar(format('UPDATE equipos_miembros SET activo = false WHERE usuario_id = %L AND activo', pg_temp.id('M1'))));
SELECT pg_temp.caso('21 M1.V delegada se va', 'off:D', pg_temp.fila('M1','V'));
SELECT pg_temp.caso('21 M1.W del admin se queda', 'on:A', pg_temp.fila('M1','W'));

-- ============================================================
-- Heredero
-- ============================================================
-- M1 vuelve a T. D suma X y reparte: V y X a M1, V a M2.
INSERT INTO equipos_miembros (equipo_id, usuario_id) VALUES (pg_temp.id('T'), pg_temp.id('M1'));
SELECT pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
  pg_temp.id('A'), pg_temp.id('D'), pg_temp.ids('tver','teq','equipo','delegar','V','F','W','X')));
SELECT pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
  pg_temp.id('M1'), pg_temp.ids('V','X')), 'D');
SELECT pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
  pg_temp.id('M2'), pg_temp.ids('V')), 'D');

SELECT pg_temp.caso('22 heredero fuera del equipo',
  'US012', pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.id('I'))));

SELECT pg_temp.caso('23 heredero sin la delegación',
  'US013', pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.id('M2'), pg_temp.ids('delegar'))));
SELECT pg_temp.caso('23b heredero sin tareas_equipo',
  'US013', pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.id('M2'), pg_temp.ids('teq'))));

SELECT pg_temp.caso('24 M2 hereda, sin X',
  'ok', pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.id('M2'), pg_temp.ids('X'))));
SELECT pg_temp.caso('24 M2 es el delegador', 'on:A', pg_temp.fila('M2','delegar'));
SELECT pg_temp.caso('24 M2 tiene tareas_equipo', 'on:A', pg_temp.fila('M2','teq'));
SELECT pg_temp.caso('24 M2.V que le dio D pasa al admin', 'on:A', pg_temp.fila('M2','V'));
SELECT pg_temp.caso('24 M2 recibe copia de W', 'on:A', pg_temp.fila('M2','W'));
SELECT pg_temp.caso('24 M2 no recibe X', 'none', pg_temp.fila('M2','X'));
SELECT pg_temp.caso('24 M1.V ahora es de M2', 'on:M2', pg_temp.fila('M1','V'));
SELECT pg_temp.caso('24 M1.X se revoca', 'off:M2', pg_temp.fila('M1','X'));
SELECT pg_temp.caso('24 D pierde usuarios_delegar', 'off:A', pg_temp.fila('D','delegar'));
SELECT pg_temp.caso('24 D pierde la vista Mi equipo', 'off:A', pg_temp.fila('D','equipo'));
SELECT pg_temp.caso('24 D pierde tareas_equipo', 'off:A', pg_temp.fila('D','teq'));
SELECT pg_temp.caso('24 D conserva V', 'on:A', pg_temp.fila('D','V'));

SELECT pg_temp.caso('25 ahora D se puede desactivar',
  'ok', pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id('D'))));

SELECT pg_temp.caso('26 sin heredero quedando miembros',
  'US009', pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, NULL)',
    pg_temp.id('A'), pg_temp.id('M2'))));

SELECT pg_temp.caso('27 V deja de ser delegable',
  'ok', pg_temp.intentar(format('UPDATE submodulos SET delegable = false WHERE id = %L', pg_temp.id('V'))));
SELECT pg_temp.caso('27 M1.V delegada se revoca', 'off:M2', pg_temp.fila('M1','V'));
SELECT pg_temp.caso('27 M2.V del admin se queda', 'on:A', pg_temp.fila('M2','V'));

-- M1 sale: M2 queda solo y puede irse sin heredero.
SELECT pg_temp.intentar(format('UPDATE equipos_miembros SET activo = false WHERE usuario_id = %L AND activo', pg_temp.id('M1')));
SELECT pg_temp.caso('28 sin heredero, solo en el equipo',
  'ok', pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, NULL)',
    pg_temp.id('A'), pg_temp.id('M2'))));
SELECT pg_temp.caso('28 M2 pierde tareas_equipo', 'off:A', pg_temp.fila('M2','teq'));

-- ============================================================
-- sql/106 — las escrituras de la pestaña Equipos
-- ============================================================
SELECT pg_temp.caso('29 I entra a T',
  'ok', pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('I'), pg_temp.id('T'))));
SELECT pg_temp.caso('29 I es de T', pg_temp.id('T')::text, equipo_de(pg_temp.id('I'))::text);

SELECT pg_temp.caso('30 el admin no entra a un equipo',
  'US002', pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('A'), pg_temp.id('T'))));

SELECT pg_temp.caso('31 sin usuarios_gestionar no se asigna equipo',
  '42501', pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, NULL)',
    pg_temp.id('I'), pg_temp.id('I'))));

SELECT pg_temp.caso('32 M2 vuelve a ser delegador',
  'ok', pg_temp.intentar(format('SELECT designar_delegador(%L, %L)',
    pg_temp.id('A'), pg_temp.id('M2'))));
SELECT pg_temp.caso('32 M2.delegar la otorgó A', 'on:A', pg_temp.fila('M2','delegar'));
SELECT pg_temp.caso('32 M2 tiene Mi equipo', 'on:A', pg_temp.fila('M2','equipo'));
SELECT pg_temp.caso('32 M2 tiene tareas_equipo', 'on:A', pg_temp.fila('M2','teq'));

SELECT pg_temp.caso('33 un segundo delegador en T',
  'US004', pg_temp.intentar(format('SELECT designar_delegador(%L, %L)',
    pg_temp.id('A'), pg_temp.id('I'))));

SELECT pg_temp.caso('34 el delegador no sale del equipo',
  'US009', pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, NULL)',
    pg_temp.id('A'), pg_temp.id('M2'))));

SELECT pg_temp.caso('35 I queda independiente',
  'ok', pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, NULL)',
    pg_temp.id('A'), pg_temp.id('I'))));
SELECT pg_temp.caso('35 I no tiene equipo', NULL, equipo_de(pg_temp.id('I'))::text);

SELECT pg_temp.caso('36 delegables: solo V',
  'ok', pg_temp.intentar(format('SELECT fijar_delegables(%L, %L)',
    pg_temp.id('A'), pg_temp.ids('V'))));
SELECT pg_temp.caso('36 X deja de ser delegable', 'false',
  (SELECT delegable::text FROM submodulos WHERE id = pg_temp.id('X')));
SELECT pg_temp.caso('36 V vuelve a ser delegable', 'true',
  (SELECT delegable::text FROM submodulos WHERE id = pg_temp.id('V')));

SELECT pg_temp.caso('37 usuarios nunca es delegable',
  '23514', pg_temp.intentar(format('SELECT fijar_delegables(%L, %L)',
    pg_temp.id('A'), pg_temp.ids('V','ver'))));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
