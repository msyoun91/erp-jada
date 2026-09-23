-- Verificación de sql/108: los eventos de usuarios que llegan a la campanita.
-- NO es una migración: todo corre dentro de una transacción que termina en
-- ROLLBACK. Correr después de aplicar sql/108.
--
-- Arma su propio mundo: A admin, D delegador, M1 miembro, N el que llega, el
-- equipo T y un módulo `prueba108` con V (vista delegable) y F (función de V,
-- delegable). Mismos helpers que `usuarios_equipos.sql`; `bandeja` lee
-- `notificaciones_listar` con la sesión del usuario y `cuenta` mira la tabla
-- cruda, filtrada por el montaje.

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

CREATE FUNCTION pg_temp.cuenta(p_usuario text, p_tipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT count(*)::text FROM usuario_notificaciones
  WHERE usuario_id = pg_temp.id(p_usuario) AND tipo::text = p_tipo;
$f$;

-- 'tipo|etiqueta|destino|actor' por fila, ordenadas; 'vacía' si no hay nada.
CREATE FUNCTION pg_temp.bandeja(p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT string_agg(concat_ws('|', tipo, etiqueta, destino, coalesce(actor, 'null')), ' / '
                    ORDER BY tipo::text, etiqueta)
  INTO v_out FROM notificaciones_listar(30);
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN coalesce(v_out, 'vacía');
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['A','D','M1','N','T','V','F']) AS n;

INSERT INTO ids (nombre, id)
SELECT replace(codigo, 'usuarios_', ''), id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','usuarios_equipo','usuarios_delegar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test108.local', jsonb_build_object('nombre', 'test108 ' || nombre)
FROM ids WHERE nombre IN ('A','D','M1','N');

INSERT INTO submodulos (id, codigo, modulo, tipo, nombre, orden, delegable, vista_id) VALUES
  (pg_temp.id('V'), 'prueba108_v', 'prueba108', 'vista',   'V', 1, true, NULL),
  (pg_temp.id('F'), 'prueba108_f', 'prueba108', 'funcion', 'F', 1, true, pg_temp.id('V'));

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
VALUES (pg_temp.id('A'), pg_temp.id('ver')), (pg_temp.id('A'), pg_temp.id('gestionar'));

INSERT INTO equipos (id, nombre) VALUES (pg_temp.id('T'), 'test108 T');
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id('T'), pg_temp.id(n) FROM unnest(ARRAY['D','M1']) AS n;

-- ============================================================
-- permiso_otorgado / delegador_designado
-- ============================================================
SELECT pg_temp.caso('00 admin se da V a sí mismo',
  'ok', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('A'), pg_temp.ids('ver','gestionar','V'))));
-- El `ver` del montaje sí avisa: entró con otorgada_por NULL, es del sistema.
SELECT pg_temp.caso('00 no se notifica a sí mismo', '0',
  (SELECT count(*)::text FROM usuario_notificaciones n
   JOIN usuario_submodulos us ON us.id = n.entidad_id
   WHERE us.usuario_id = pg_temp.id('A') AND us.submodulo_id = pg_temp.id('V')));

SELECT pg_temp.caso('01 A designa a D y le da V y F',
  'ok', pg_temp.intentar(format('SELECT asignar_submodulos(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.ids('equipo','delegar','V','F'))));
SELECT pg_temp.caso('01 una sola designación', '1', pg_temp.cuenta('D', 'delegador_designado'));
SELECT pg_temp.caso('01 Mi equipo no avisa aparte; F no avisa', '1', pg_temp.cuenta('D', 'permiso_otorgado'));
SELECT pg_temp.caso('01 bandeja de D',
  'delegador_designado|test108 T|mi_equipo|test108 A / permiso_otorgado|V|prueba108|test108 A',
  pg_temp.bandeja('D'));

SELECT pg_temp.caso('02 D delega V y F a M1',
  'ok', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M1'), pg_temp.ids('V','F')), 'D'));
SELECT pg_temp.caso('02 bandeja de M1', 'permiso_otorgado|V|prueba108|test108 D', pg_temp.bandeja('M1'));

SELECT pg_temp.caso('03 D le saca V y F a M1',
  'ok', pg_temp.intentar(format('SELECT delegar_submodulos(%L, %L)',
    pg_temp.id('M1'), '{}'::uuid[]), 'D'));
SELECT pg_temp.caso('03 el permiso revocado sale de la bandeja', 'vacía', pg_temp.bandeja('M1'));
SELECT pg_temp.caso('03 la fila sigue en la tabla', '1', pg_temp.cuenta('M1', 'permiso_otorgado'));

-- ============================================================
-- miembro_nuevo
-- ============================================================
SELECT pg_temp.caso('04 A suma a N al equipo',
  'ok', pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('N'), pg_temp.id('T'))));
SELECT pg_temp.caso('04 le llega al delegador', '1', pg_temp.cuenta('D', 'miembro_nuevo'));
SELECT pg_temp.caso('04 no al resto del equipo', '0', pg_temp.cuenta('M1', 'miembro_nuevo'));
SELECT pg_temp.caso('04 bandeja de D, sin actor (service_role)',
  'delegador_designado|test108 T|mi_equipo|test108 A / miembro_nuevo|test108 N|mi_equipo|null / permiso_otorgado|V|prueba108|test108 A',
  pg_temp.bandeja('D'));

SELECT pg_temp.caso('05 A deja a N independiente',
  'ok', pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, NULL)',
    pg_temp.id('A'), pg_temp.id('N'))));
SELECT pg_temp.caso('05 el miembro que se fue sale de la bandeja',
  'delegador_designado|test108 T|mi_equipo|test108 A / permiso_otorgado|V|prueba108|test108 A',
  pg_temp.bandeja('D'));

-- ============================================================
-- Herencia
-- ============================================================
SELECT pg_temp.caso('06 D sale con M1 de heredero',
  'ok', pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, %L)',
    pg_temp.id('A'), pg_temp.id('D'), pg_temp.id('M1'))));
SELECT pg_temp.caso('06 bandeja de M1: designado, Mi equipo no avisa aparte',
  'delegador_designado|test108 T|mi_equipo|test108 A / permiso_otorgado|V|prueba108|test108 A',
  pg_temp.bandeja('M1'));
SELECT pg_temp.caso('06 D ya no ve su designación',
  'permiso_otorgado|V|prueba108|test108 A', pg_temp.bandeja('D'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
