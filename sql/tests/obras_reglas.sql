-- Verificación de sql/126: la obra, sus participantes, ver/trabajar/a cargo,
-- estados con motivo de pérdida, transferir, desactivar, el ente `obra` y sus
-- genéricas. NO es una migración: todo corre dentro de una transacción que
-- termina en ROLLBACK. Correr después de aplicar sql/125 a sql/128
-- (`entes.roles` y `contactos_ver` los siembran sql/125 y sql/127; obras_ver
-- requiere contactos_ver desde sql/127).
--
-- Mundo: equipo Norte (JN jefe = delegador con obras_equipo; Juan y Nico
-- vendedores, obras_ver + obras_crear); equipo Sur (Laura jefa = delegador
-- con obras_equipo; Pedro vendedor, obras_ver + obras_crear). A administra
-- Obras (obras_ver, obras_todas, obras_administrar, obras_crear), sin equipo.
-- X solo obras_ver (+ contactos_ver), sin obras_crear, sin equipo. Z no tiene
-- obras_ver. GA administra usuarios (usuarios_gestionar), para
-- `quitar_delegador`. Nada depende de los datos reales.
--
-- `intentar` y `ve` como en `tareas_vinculos.sql`.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.nombre(p_id uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT nombre FROM ids WHERE id = p_id;
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

-- Un valor devuelto por una función, corriendo como alguien.
CREATE FUNCTION pg_temp.leer(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_v text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql INTO v_v;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_v;
END;
$f$;

-- 'idea:Juan:Juan:Norte:-:-:true' — estado, responsable, creado_por, equipo,
-- motivo, nota, activo.
CREATE FUNCTION pg_temp.obra(p_obra text) RETURNS text LANGUAGE sql AS $f$
  SELECT o.estado::text || ':' || pg_temp.nombre(o.responsable_id) || ':' || pg_temp.nombre(o.creado_por)
         || ':' || coalesce(pg_temp.nombre(o.equipo_id), '-') || ':' || coalesce(o.motivo_perdida::text, '-')
         || ':' || coalesce(o.estado_nota, '-') || ':' || o.activo::text
  FROM obras o WHERE o.id = pg_temp.id(p_obra);
$f$;

CREATE FUNCTION pg_temp.campo(p_obra text, p_columna text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v text;
BEGIN
  EXECUTE format('SELECT %I::text FROM obras WHERE id = $1', p_columna) INTO v USING pg_temp.id(p_obra);
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.crear_obra(
  p_obra text, p_direccion text, p_origen text, p_tipo text, p_como text, p_estado text DEFAULT 'idea'
) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO obras (id, nombre, direccion, origen, tipo, estado) VALUES (%L, %L, %L, %L::origen_obra, %L::tipo_obra, %L::estado_obra)',
    pg_temp.id(p_obra), p_obra, p_direccion, p_origen, p_tipo, p_estado
  ), p_como);
$f$;

CREATE FUNCTION pg_temp.editar_obra(p_obra text, p_set text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE obras SET %s WHERE id = %L', p_set, pg_temp.id(p_obra)), p_como);
$f$;

CREATE FUNCTION pg_temp.transferir(p_obra text, p_a text, p_quedarme boolean, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT obras_transferir(%L, %L, %L)',
    pg_temp.id(p_obra), pg_temp.id(p_a), p_quedarme), p_como);
$f$;

CREATE FUNCTION pg_temp.desactivar_obra(p_obra text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT obras_desactivar(%L)', pg_temp.id(p_obra)), p_como);
$f$;

CREATE FUNCTION pg_temp.trabaja(p_obra text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.leer(format('SELECT trabaja_registro(''obra'', %L)', pg_temp.id(p_obra)), p_como);
$f$;

CREATE FUNCTION pg_temp.obras_trabaja_rpc(p_obra text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.leer(format('SELECT obras_trabaja(%L)', pg_temp.id(p_obra)), p_como);
$f$;

CREATE FUNCTION pg_temp.etiqueta(p_obra text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.leer(format('SELECT etiqueta_registro(''obra'', %L)', pg_temp.id(p_obra)), p_como);
$f$;

CREATE FUNCTION pg_temp.sumar_participante(p_obra text, p_usuario text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('INSERT INTO obras_participantes (id, obra_id, usuario_id) VALUES (%L, %L, %L)',
    gen_random_uuid(), pg_temp.id(p_obra), pg_temp.id(p_usuario)), p_como);
$f$;

CREATE FUNCTION pg_temp.set_participante(p_obra text, p_usuario text, p_activo boolean, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE obras_participantes SET activo = %L WHERE obra_id = %L AND usuario_id = %L AND activo = %L',
    p_activo, pg_temp.id(p_obra), pg_temp.id(p_usuario), NOT p_activo), p_como);
$f$;

-- 'true:Sur' — si tiene una fila activa, y su equipo (mismo valor en todas las
-- filas del par: `created_at` es igual en toda la transacción, no sirve para
-- desempatar "la última").
CREATE FUNCTION pg_temp.participante(p_obra text, p_usuario text) RETURNS text LANGUAGE sql AS $f$
  SELECT bool_or(p.activo)::text || ':' || coalesce(pg_temp.nombre((array_agg(p.equipo_id))[1]), '-')
  FROM obras_participantes p
  WHERE p.obra_id = pg_temp.id(p_obra) AND p.usuario_id = pg_temp.id(p_usuario);
$f$;

CREATE FUNCTION pg_temp.evento_campo(p_obra text, p_evento text, p_campo text) RETURNS text LANGUAGE sql AS $f$
  SELECT detalle ->> p_campo
  FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id(p_obra) AND evento = p_evento::tipo_evento
  ORDER BY created_at DESC LIMIT 1;
$f$;

CREATE FUNCTION pg_temp.evento_actor(p_obra text, p_evento text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.nombre(actor_id)
  FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id(p_obra) AND evento = p_evento::tipo_evento
  ORDER BY created_at ASC LIMIT 1;
$f$;

CREATE FUNCTION pg_temp.eventos_de(p_obra text) RETURNS bigint LANGUAGE sql AS $f$
  SELECT count(*) FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id(p_obra);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['A','X','Z','GA','Juan','Nico','JN','Pedro','Laura','Norte','Sur',
                  'Belgrano','Caputo','Palermo','Descarte1','Descarte2','Descarte3']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('contactos_ver','obras_ver','obras_crear','obras_equipo','obras_todas',
                            'obras_administrar','usuarios_ver','usuarios_gestionar','usuarios_delegar',
                            'usuarios_equipo','tareas_ver','tareas_equipo');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test126.local', jsonb_build_object('nombre', 'test126 ' || nombre)
FROM ids WHERE nombre IN ('A','X','Z','GA','Juan','Nico','JN','Pedro','Laura');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test126 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['Norte','Sur']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('Norte','JN'),('Norte','Juan'),('Norte','Nico'),('Sur','Laura'),('Sur','Pedro')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('A','contactos_ver'), ('A','obras_ver'), ('A','obras_crear'), ('A','obras_administrar'), ('A','obras_todas'),
  ('X','contactos_ver'), ('X','obras_ver'),
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Nico','contactos_ver'), ('Nico','obras_ver'), ('Nico','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('JN','contactos_ver'), ('JN','obras_ver'), ('JN','tareas_ver'), ('JN','tareas_equipo'),
    ('JN','usuarios_delegar'), ('JN','usuarios_equipo'), ('JN','obras_equipo'),
  ('Laura','contactos_ver'), ('Laura','obras_ver'), ('Laura','tareas_ver'), ('Laura','tareas_equipo'),
    ('Laura','usuarios_delegar'), ('Laura','usuarios_equipo'), ('Laura','obras_equipo'),
  ('GA','usuarios_ver'), ('GA','usuarios_gestionar')
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

SELECT pg_temp.caso('00 JN es delegador de Norte', 'true',
  (SELECT usuario_tiene_permiso(pg_temp.id('JN'), 'usuarios_delegar')::text));
SELECT pg_temp.caso('00 Laura tiene obras_equipo', 'true',
  (SELECT usuario_tiene_permiso(pg_temp.id('Laura'), 'obras_equipo')::text));

-- ============================================================
-- 01 — Alta de una obra
-- ============================================================
SELECT pg_temp.caso('01 Juan crea Belgrano', 'ok',
  pg_temp.crear_obra('Belgrano', 'Av. Belgrano 123', 'referente', 'casa', 'Juan'));
SELECT pg_temp.caso('01 responsable Juan, creado_por Juan, equipo Norte, idea, sin motivo ni nota',
  'idea:Juan:Juan:Norte:-:-:true', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('01 evento alta, actor Juan', 'Juan', pg_temp.evento_actor('Belgrano', 'alta'));

-- ============================================================
-- 02 — Restricciones del alta
-- ============================================================
SELECT pg_temp.caso('02 nace contratada', 'OB001',
  pg_temp.crear_obra('Descarte1', 'Calle 1', 'referente', 'casa', 'Juan', 'contratada'));
SELECT pg_temp.caso('02 X no tiene obras_crear', '42501',
  pg_temp.crear_obra('Descarte2', 'Calle 2', 'referente', 'casa', 'X'));
SELECT pg_temp.caso('02 Juan no fija responsable_id', '42501', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id) VALUES (%L, 'Descarte3', 'Calle 3', 'referente', 'casa', %L)$s$,
  pg_temp.id('Descarte3'), pg_temp.id('Nico')), 'Juan'));

-- ============================================================
-- 03 — Sumar un participante
-- ============================================================
SELECT pg_temp.caso('03 Juan suma a Pedro', 'ok', pg_temp.sumar_participante('Belgrano', 'Pedro', 'Juan'));
SELECT pg_temp.caso('03 la participación de Pedro es de Sur', 'true:Sur', pg_temp.participante('Belgrano', 'Pedro'));

-- ============================================================
-- 04 — Quién ve Belgrano
-- ============================================================
SELECT pg_temp.caso('04 Juan (responsable)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('04 Pedro (participante)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'Pedro'));
SELECT pg_temp.caso('04 JN (jefe del equipo de la obra)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'JN'));
SELECT pg_temp.caso('04 Laura (jefa del equipo de un participante)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'Laura'));
SELECT pg_temp.caso('04 A (obras_todas)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'A'));
SELECT pg_temp.caso('04 Nico (sin relación)', '0',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'Nico'));
SELECT pg_temp.caso('04 Z (sin obras_ver)', '0',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'Z'));

-- ============================================================
-- 05 — Trabajar
-- ============================================================
SELECT pg_temp.caso('05 Pedro cambia notas', 'ok', pg_temp.editar_obra('Belgrano', $s$notas = 'pedro'$s$, 'Pedro'));
SELECT pg_temp.caso('05 JN cambia notas', 'ok', pg_temp.editar_obra('Belgrano', $s$notas = 'jn'$s$, 'JN'));
SELECT pg_temp.caso('05 Laura no trabaja la obra de otro equipo', 'OB002',
  pg_temp.editar_obra('Belgrano', $s$notas = 'laura'$s$, 'Laura'));
SELECT pg_temp.caso('05 notas siguen en "jn"', 'jn', pg_temp.campo('Belgrano', 'notas'));
SELECT pg_temp.caso('05 Nico, que no la ve, no toca nada', 'ok',
  pg_temp.editar_obra('Belgrano', $s$notas = 'nico'$s$, 'Nico'));
SELECT pg_temp.caso('05 notas sin cambiar', 'jn', pg_temp.campo('Belgrano', 'notas'));
SELECT pg_temp.caso('05 Juan trabaja (responsable)', 'true', pg_temp.trabaja('Belgrano', 'Juan'));
SELECT pg_temp.caso('05 Pedro trabaja (participante)', 'true', pg_temp.trabaja('Belgrano', 'Pedro'));
SELECT pg_temp.caso('05 JN trabaja (jefe del equipo de la obra)', 'true', pg_temp.trabaja('Belgrano', 'JN'));
SELECT pg_temp.caso('05 A trabaja (administrar)', 'true', pg_temp.trabaja('Belgrano', 'A'));
SELECT pg_temp.caso('05 Laura no trabaja (solo la ve)', 'false', pg_temp.trabaja('Belgrano', 'Laura'));
SELECT pg_temp.caso('05 Nico no trabaja', 'false', pg_temp.trabaja('Belgrano', 'Nico'));
SELECT pg_temp.caso('05 obras_trabaja como Laura', 'false', pg_temp.obras_trabaja_rpc('Belgrano', 'Laura'));

-- ============================================================
-- 06 — Participantes: sumar, quitar, no reactivar
-- ============================================================
SELECT pg_temp.caso('06 Pedro (solo participante) no suma', 'OB013',
  pg_temp.sumar_participante('Belgrano', 'Nico', 'Pedro'));
SELECT pg_temp.caso('06 Laura (jefa de otro equipo) no suma', 'OB013',
  pg_temp.sumar_participante('Belgrano', 'Nico', 'Laura'));
SELECT pg_temp.caso('06 JN (jefe del equipo de la obra) suma a Nico', 'ok',
  pg_temp.sumar_participante('Belgrano', 'Nico', 'JN'));
SELECT pg_temp.caso('06 la participación de Nico es de Norte', 'true:Norte', pg_temp.participante('Belgrano', 'Nico'));
SELECT pg_temp.caso('06 sumar a Z, que no ve Obras', 'OB014',
  pg_temp.sumar_participante('Belgrano', 'Z', 'JN'));
SELECT pg_temp.caso('06 Juan desactiva la participación de Pedro', 'ok',
  pg_temp.set_participante('Belgrano', 'Pedro', false, 'Juan'));
SELECT pg_temp.caso('06 reactivarla es una fila nueva, no un UPDATE', 'OB015',
  pg_temp.set_participante('Belgrano', 'Pedro', true, 'Juan'));

-- ============================================================
-- 07 — Estados, con motivo de pérdida y reversión (obra "Caputo")
-- ============================================================
SELECT pg_temp.caso('07 Juan crea Caputo', 'ok',
  pg_temp.crear_obra('Caputo', 'Caputo 456', 'cartel', 'oficinas_comercial', 'Juan'));

SELECT pg_temp.caso('07a idea a en_busqueda', 'ok', pg_temp.editar_obra('Caputo', $s$estado = 'en_busqueda'$s$, 'Juan'));
SELECT pg_temp.caso('07b perdida sin motivo', 'OB011', pg_temp.editar_obra('Caputo', $s$estado = 'perdida'$s$, 'Juan'));
SELECT pg_temp.caso('07c perdida "otro" sin nota', 'OB012',
  pg_temp.editar_obra('Caputo', $s$estado = 'perdida', motivo_perdida = 'otro'$s$, 'Juan'));
SELECT pg_temp.caso('07d perdida "precio" con nota', 'ok', pg_temp.editar_obra('Caputo',
  $s$estado = 'perdida', motivo_perdida = 'precio', estado_nota = '10% más caros'$s$, 'Juan'));
SELECT pg_temp.caso('07d fila: perdida, precio, la nota', 'perdida:Juan:Juan:Norte:precio:10% más caros:true',
  pg_temp.obra('Caputo'));
SELECT pg_temp.caso('07d evento estado', 'perdida', pg_temp.evento_campo('Caputo', 'estado', 'estado'));
SELECT pg_temp.caso('07d evento anterior', 'en_busqueda', pg_temp.evento_campo('Caputo', 'estado', 'anterior'));
SELECT pg_temp.caso('07d evento motivo_perdida', 'precio', pg_temp.evento_campo('Caputo', 'estado', 'motivo_perdida'));
SELECT pg_temp.caso('07d evento estado_nota', '10% más caros', pg_temp.evento_campo('Caputo', 'estado', 'estado_nota'));

SELECT pg_temp.caso('07e perdida a contratada', 'OB010',
  pg_temp.editar_obra('Caputo', $s$estado = 'contratada'$s$, 'Juan'));
SELECT pg_temp.caso('07f perdida a en_busqueda, sin tocar la nota (queda vieja e igual → se limpia)', 'ok',
  pg_temp.editar_obra('Caputo', $s$estado = 'en_busqueda'$s$, 'Juan'));
SELECT pg_temp.caso('07f motivo y nota quedan NULL', 'en_busqueda:Juan:Juan:Norte:-:-:true', pg_temp.obra('Caputo'));
SELECT pg_temp.caso('07f el evento no trae motivo_perdida', NULL, pg_temp.evento_campo('Caputo', 'estado', 'motivo_perdida'));
SELECT pg_temp.caso('07f el evento no trae estado_nota', NULL, pg_temp.evento_campo('Caputo', 'estado', 'estado_nota'));

SELECT pg_temp.caso('07g en_busqueda a contratada', 'ok',
  pg_temp.editar_obra('Caputo', $s$estado = 'contratada'$s$, 'Juan'));
SELECT pg_temp.caso('07h contratada a perdida (con motivo)', 'OB008',
  pg_temp.editar_obra('Caputo', $s$estado = 'perdida', motivo_perdida = 'plazo'$s$, 'Juan'));
SELECT pg_temp.caso('07i contratada a en_cotizacion sin nota', 'OB009',
  pg_temp.editar_obra('Caputo', $s$estado = 'en_cotizacion'$s$, 'Juan'));
SELECT pg_temp.caso('07j contratada a en_cotizacion con nota', 'ok',
  pg_temp.editar_obra('Caputo', $s$estado = 'en_cotizacion', estado_nota = 'clic equivocado'$s$, 'Juan'));
SELECT pg_temp.caso('07j la nota queda en la fila', 'clic equivocado', pg_temp.campo('Caputo', 'estado_nota'));
SELECT pg_temp.caso('07j la nota queda en el evento', 'clic equivocado',
  pg_temp.evento_campo('Caputo', 'estado', 'estado_nota'));

SELECT pg_temp.caso('07k editar notas sin cambiar estado no toca estado_nota', 'ok',
  pg_temp.editar_obra('Caputo', $s$notas = 'seguimiento'$s$, 'Juan'));
SELECT pg_temp.caso('07k estado_nota sigue igual', 'clic equivocado', pg_temp.campo('Caputo', 'estado_nota'));

SELECT pg_temp.caso('07l motivo_perdida solo, sin cambiar estado, no cambia nada', 'ok',
  pg_temp.editar_obra('Caputo', $s$motivo_perdida = 'plazo'$s$, 'Juan'));
SELECT pg_temp.caso('07l motivo_perdida sigue NULL', NULL, pg_temp.campo('Caputo', 'motivo_perdida'));

SELECT pg_temp.caso('07m en_cotizacion a idea', 'ok', pg_temp.editar_obra('Caputo', $s$estado = 'idea'$s$, 'Juan'));
SELECT pg_temp.caso('07m estado_nota queda NULL', NULL, pg_temp.campo('Caputo', 'estado_nota'));

-- ============================================================
-- 08 — Transferir
-- ============================================================
SELECT pg_temp.caso('08 Pedro (ni responsable ni jefe) no transfiere', 'OB003',
  pg_temp.transferir('Belgrano', 'Pedro', false, 'Pedro'));
SELECT pg_temp.caso('08 Juan transfiere a Z, que no ve Obras', 'OB006',
  pg_temp.transferir('Belgrano', 'Z', false, 'Juan'));
SELECT pg_temp.caso('08 Juan transfiere a Pedro, sin quedarme', 'ok',
  pg_temp.transferir('Belgrano', 'Pedro', false, 'Juan'));
SELECT pg_temp.caso('08 responsable Pedro, equipo Sur', 'idea:Pedro:Juan:Sur:-:-:true', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('08 la participación de Pedro (ya la tenía) sigue inactiva', 'false:Sur',
  pg_temp.participante('Belgrano', 'Pedro'));
SELECT pg_temp.caso('08 Juan ya no la ve', '0',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('08 JN la sigue viendo por el participante de Norte (Nico, sumado en 06)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'JN'));
SELECT pg_temp.caso('08 Laura ahora trabaja (su equipo es el de la obra)', 'true', pg_temp.trabaja('Belgrano', 'Laura'));
SELECT pg_temp.caso('08 evento transferencia: de Juan', pg_temp.id('Juan')::text,
  pg_temp.evento_campo('Belgrano', 'transferencia', 'de'));
SELECT pg_temp.caso('08 evento transferencia: a Pedro', pg_temp.id('Pedro')::text,
  pg_temp.evento_campo('Belgrano', 'transferencia', 'a'));

SELECT pg_temp.caso('08 Pedro se la devuelve a Juan, quedándose', 'ok',
  pg_temp.transferir('Belgrano', 'Juan', true, 'Pedro'));
SELECT pg_temp.caso('08 responsable Juan otra vez, equipo Norte', 'idea:Juan:Juan:Norte:-:-:true',
  pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('08 Pedro queda participante activo (fila nueva, de su equipo Sur)', 'true:Sur',
  pg_temp.participante('Belgrano', 'Pedro'));

-- ============================================================
-- 09 — Desactivar
-- ============================================================
SELECT pg_temp.caso('09 Pedro (participante, no a cargo) no desactiva', 'OB004',
  pg_temp.desactivar_obra('Belgrano', 'Pedro'));

SELECT pg_temp.caso('09 Juan crea Palermo', 'ok',
  pg_temp.crear_obra('Palermo', 'Palermo 789', 'web_redes', 'edificio_residencial', 'Juan'));
SELECT pg_temp.caso('09 Palermo a en_busqueda', 'ok', pg_temp.editar_obra('Palermo', $s$estado = 'en_busqueda'$s$, 'Juan'));
SELECT pg_temp.caso('09 Palermo a contratada', 'ok', pg_temp.editar_obra('Palermo', $s$estado = 'contratada'$s$, 'Juan'));
SELECT pg_temp.caso('09 una obra contratada no se desactiva', 'OB007', pg_temp.desactivar_obra('Palermo', 'Juan'));

SELECT pg_temp.caso('09 Juan desactiva Belgrano (idea)', 'ok', pg_temp.desactivar_obra('Belgrano', 'Juan'));
SELECT pg_temp.caso('09 Juan ya no la ve', '0',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('09 A sí (obras_todas)', '1',
  pg_temp.ve(format('SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Belgrano')), 'A'));
SELECT pg_temp.caso('09 A la reactiva', 'ok', pg_temp.editar_obra('Belgrano', 'activo = true', 'A'));
SELECT pg_temp.caso('09 hay un evento baja', 'true',
  (SELECT (count(*) > 0)::text FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id('Belgrano') AND evento = 'baja'));
SELECT pg_temp.caso('09 hay un evento reactivacion', 'true',
  (SELECT (count(*) > 0)::text FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id('Belgrano') AND evento = 'reactivacion'));

-- ============================================================
-- 11 — Genéricas: etiqueta, buscar, puede_abrir_registro, roles del ente
-- ============================================================
SELECT pg_temp.caso('11 etiqueta_registro para Juan (la ve)', 'Belgrano', pg_temp.etiqueta('Belgrano', 'Juan'));
SELECT pg_temp.caso('11 etiqueta_registro para Z (no la ve)', NULL, pg_temp.etiqueta('Belgrano', 'Z'));
SELECT pg_temp.caso('11 buscar_registros trae Belgrano a Juan', '1',
  pg_temp.ve(format('SELECT 1 FROM buscar_registros(''obras'', ''belg'') WHERE registro_id = %L', pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('11 buscar_registros no se lo trae a Z', '0',
  pg_temp.ve(format('SELECT 1 FROM buscar_registros(''obras'', ''belg'') WHERE registro_id = %L', pg_temp.id('Belgrano')), 'Z'));
SELECT pg_temp.caso('11 puede_abrir_registro sin GRANT', '42501', pg_temp.intentar(format(
  'SELECT puede_abrir_registro(''obra'', %L, %L)', pg_temp.id('Belgrano'), pg_temp.id('Juan')), 'Juan'));
SELECT pg_temp.caso('11 el ente obra admite el rol referente', 'true',
  (SELECT ('referente' = ANY (roles))::text FROM entes WHERE codigo = 'obra'));
SELECT pg_temp.caso('11 el ente obra admite el rol director_obra', 'true',
  (SELECT ('director_obra' = ANY (roles))::text FROM entes WHERE codigo = 'obra'));

-- ============================================================
-- 12 — Eventos: lo que no se ve, no pasó
-- ============================================================
SELECT pg_temp.caso('12 Nico no ve eventos de Caputo (no tiene relación)', '0',
  pg_temp.ve(format('SELECT 1 FROM eventos WHERE ente = ''obra'' AND registro_id = %L', pg_temp.id('Caputo')), 'Nico'));
-- alta + 6 estados + el evento estado que el propio INSERT ya emite (OLD es
-- NULL en un insert: 'idea' IS DISTINCT FROM NULL) = 8.
SELECT pg_temp.caso('12 Juan ve los eventos de su Caputo', '8',
  pg_temp.ve(format('SELECT 1 FROM eventos WHERE ente = ''obra'' AND registro_id = %L', pg_temp.id('Caputo')), 'Juan'));

-- ============================================================
-- 10 — quitar_delegador, corrido como service_role
-- ============================================================
-- Sin heredero, la salida del delegador solo vale si no queda nadie más en el
-- equipo (US009): Juan y Nico salen de Norte, JN queda solo. Va al final: desde
-- `sql/133`, salir de Norte entrega las obras de Juan a JN.
SELECT pg_temp.caso('10 Juan sale de Norte', 'ok', pg_temp.intentar(format(
  'UPDATE equipos_miembros SET activo = false WHERE equipo_id = %L AND usuario_id = %L AND activo',
  pg_temp.id('Norte'), pg_temp.id('Juan'))));
SELECT pg_temp.caso('10 Nico sale de Norte', 'ok', pg_temp.intentar(format(
  'UPDATE equipos_miembros SET activo = false WHERE equipo_id = %L AND usuario_id = %L AND activo',
  pg_temp.id('Norte'), pg_temp.id('Nico'))));
SELECT pg_temp.caso('10 GA quita a JN como delegador, sin heredero', 'ok', pg_temp.intentar(format(
  'SELECT quitar_delegador(%L, %L, NULL)', pg_temp.id('GA'), pg_temp.id('JN'))));
SELECT pg_temp.caso('10 JN pierde usuarios_delegar', 'false',
  (SELECT usuario_tiene_permiso(pg_temp.id('JN'), 'usuarios_delegar')::text));
SELECT pg_temp.caso('10 JN pierde obras_equipo', 'false',
  (SELECT usuario_tiene_permiso(pg_temp.id('JN'), 'obras_equipo')::text));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
