-- Verificación de sql/133: obras y contactos, bajas y cambios de equipo (el
-- jefe recibe, huérfanas cuando no hay quién reciba, `asignar_equipo` elige la
-- agenda). NO es una migración: todo corre dentro de una transacción que
-- termina en ROLLBACK. Correr después de aplicar sql/125 a sql/134.
--
-- Mundo: G admin de usuarios; A con obras_administrar, obras_todas,
-- contactos_administrar (+ contactos_ver, mecánico: lo pide la vista de
-- contactos_administrar). Equipo Norte: J delegador (usuarios_delegar,
-- obras_equipo, obras_ver, contactos_ver, + usuarios_equipo mecánico), V y H
-- (obras_ver, obras_crear, contactos_ver). Equipo Sur, sin jefe: W (mismos
-- permisos que V). I independiente con obras_ver (+ obras_crear, mecánico,
-- para poder armar su propia obra).
--
-- Para no apagar a J o a H a mitad de la suite (case 8 los necesita activos y
-- al mando), los casos que dan de baja o cambian de equipo a un delegador
-- (6) o le apagan `obras_ver` (7) usan un elenco aparte: V2, V3 (caso 4), I
-- ya cubre el caso 5, W2 (caso 7) y un segundo equipo Centro con J2 delegador
-- y H2 heredero (caso 6). Q es alguien sin nada, para el caso "no recibe
-- nada" del caso 3.
--
-- `intentar` como en `tareas_bajas.sql`.

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
  IF p_como = 'dueño' THEN
    NULL;
  ELSIF p_como IS NOT NULL THEN
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

CREATE FUNCTION pg_temp.crear_obra(p_obra text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, %L, 'Calle 1', 'otro', 'casa')$s$,
    pg_temp.id(p_obra), p_obra), p_como);
$f$;

-- Montaje, como dueño de la sesión (service_role no tiene INSERT ni UPDATE en
-- obras): obras de alguien sin obras_crear (J, J2), y el equipo forzado.
CREATE FUNCTION pg_temp.crear_obra_para(p_obra text, p_responsable text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    $s$INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por) VALUES (%L, %L, 'Calle 1', 'otro', 'casa', %L, %L)$s$,
    pg_temp.id(p_obra), p_obra, pg_temp.id(p_responsable), pg_temp.id(p_responsable)), 'dueño');
$f$;

CREATE FUNCTION pg_temp.editar_obra(p_obra text, p_set text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE obras SET %s WHERE id = %L', p_set, pg_temp.id(p_obra)), p_como);
$f$;

CREATE FUNCTION pg_temp.desactivar_obra(p_obra text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT obras_desactivar(%L)', pg_temp.id(p_obra)), p_como);
$f$;

CREATE FUNCTION pg_temp.transferir(p_obra text, p_a text, p_quedarme boolean, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT obras_transferir(%L, %L, %L)',
    pg_temp.id(p_obra), pg_temp.id(p_a), p_quedarme), p_como);
$f$;

CREATE FUNCTION pg_temp.forzar_equipo(p_obra text, p_equipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE obras SET equipo_id = %L WHERE id = %L', pg_temp.id(p_equipo), pg_temp.id(p_obra)), 'dueño');
$f$;

CREATE FUNCTION pg_temp.sumar_participante(p_obra text, p_usuario text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('INSERT INTO obras_participantes (id, obra_id, usuario_id) VALUES (%L, %L, %L)',
    gen_random_uuid(), pg_temp.id(p_obra), pg_temp.id(p_usuario)), p_como);
$f$;

CREATE FUNCTION pg_temp.quitar_participante(p_obra text, p_usuario text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'UPDATE obras_participantes SET activo = false WHERE obra_id = %L AND usuario_id = %L AND activo',
    pg_temp.id(p_obra), pg_temp.id(p_usuario)), p_como);
$f$;

CREATE FUNCTION pg_temp.crear_persona(p_persona text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO contactos_personas (id, nombre) VALUES (%L, %L)', pg_temp.id(p_persona), p_persona), p_como);
$f$;

CREATE FUNCTION pg_temp.baja(p_usuario text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id(p_usuario)));
$f$;

CREATE FUNCTION pg_temp.perder_permiso(p_usuario text, p_submodulo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'UPDATE usuario_submodulos SET activo = false WHERE usuario_id = %L AND submodulo_id = %L AND activo',
    pg_temp.id(p_usuario), pg_temp.id(p_submodulo)));
$f$;

CREATE FUNCTION pg_temp.asignar(p_usuario text, p_equipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, %L)',
    pg_temp.id('G'), pg_temp.id(p_usuario), pg_temp.id(p_equipo)));
$f$;

CREATE FUNCTION pg_temp.asignar_sin_agenda(p_usuario text, p_equipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT asignar_equipo(%L, %L, %L, false)',
    pg_temp.id('G'), pg_temp.id(p_usuario), pg_temp.id(p_equipo)));
$f$;

CREATE FUNCTION pg_temp.quitar_delegador(p_saliente text, p_heredero text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT quitar_delegador(%L, %L, %L)',
    pg_temp.id('G'), pg_temp.id(p_saliente), pg_temp.id(p_heredero)));
$f$;

-- 'V:Norte:true' — responsable, equipo, activo.
CREATE FUNCTION pg_temp.obra_estado(p_obra text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.nombre(o.responsable_id) || ':' || coalesce(pg_temp.nombre(o.equipo_id), '-') || ':' || o.activo::text
  FROM obras o WHERE o.id = pg_temp.id(p_obra);
$f$;

CREATE FUNCTION pg_temp.persona_resp(p_persona text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.nombre(responsable_id) FROM contactos_personas WHERE id = pg_temp.id(p_persona);
$f$;

-- 'true:Norte' — si tiene una fila activa, y su equipo (mismo valor en todas
-- las filas del par, como en `obras_reglas.sql`).
CREATE FUNCTION pg_temp.participante(p_obra text, p_usuario text) RETURNS text LANGUAGE sql AS $f$
  SELECT bool_or(p.activo)::text || ':' || coalesce(pg_temp.nombre((array_agg(p.equipo_id))[1]), '-')
  FROM obras_participantes p
  WHERE p.obra_id = pg_temp.id(p_obra) AND p.usuario_id = pg_temp.id(p_usuario);
$f$;

CREATE FUNCTION pg_temp.evento_transferencia(p_obra text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.nombre((detalle->>'de')::uuid) || '->' || pg_temp.nombre((detalle->>'a')::uuid)
  FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id(p_obra) AND evento = 'transferencia'::tipo_evento
  ORDER BY created_at DESC LIMIT 1;
$f$;

-- Nombres (nuestros, cortos) de quienes tienen un aviso activo de ese tipo.
CREATE FUNCTION pg_temp.avisos_de(p_usuario text, p_tipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(string_agg(pg_temp.nombre(n.entidad_id), ',' ORDER BY pg_temp.nombre(n.entidad_id)), '')
  FROM usuario_notificaciones n
  WHERE n.usuario_id = pg_temp.id(p_usuario) AND n.activo AND n.tipo::text = p_tipo;
$f$;

-- 'motivo|destino' de la fila (tipo, destino_id) de la bandeja de p_como.
CREATE FUNCTION pg_temp.fila(p_como text, p_tipo text, p_quien text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_motivo text;
  v_destino text;
  v_hay boolean;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT true, l.motivo, l.destino INTO v_hay, v_motivo, v_destino
  FROM notificaciones_listar(200) l
  WHERE l.tipo::text = p_tipo AND l.destino_id = pg_temp.id(p_quien);
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF NOT coalesce(v_hay, false) THEN
    RETURN '-';
  END IF;
  RETURN coalesce(v_motivo, '-') || '|' || coalesce(v_destino, '-');
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','A','J','V','H','W','I','V2','V3','W2','Q','J2','H2',
                  'Norte','Sur','Centro',
                  'Ob1V','Ob2V','Ob3V','Ob4V','Ob6V','ObH','ObH2','ObW','ObI','ObV2','ObV3','ObW2','ObJ2',
                  'P1V','P1W','P1V2','P1V3']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('obras_ver','obras_crear','obras_equipo','obras_todas','obras_administrar','obras_aprobar',
                            'contactos_ver','contactos_administrar',
                            'usuarios_ver','usuarios_gestionar','usuarios_delegar','usuarios_equipo','tareas_ver','tareas_equipo');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test133.local', jsonb_build_object('nombre', 'test133 ' || nombre)
FROM ids WHERE nombre IN ('G','A','J','V','H','W','I','V2','V3','W2','Q','J2','H2');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test133 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['Norte','Sur','Centro']) AS e;

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES
  ('Norte','J'),('Norte','V'),('Norte','H'),('Norte','V2'),('Norte','V3'),
  ('Sur','W'),('Sur','W2'),
  ('Centro','J2'),('Centro','H2')
) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('A','contactos_ver'), ('A','contactos_administrar'), ('A','obras_ver'), ('A','obras_administrar'), ('A','obras_todas'),
  ('J','contactos_ver'), ('J','obras_ver'), ('J','obras_equipo'), ('J','usuarios_equipo'), ('J','usuarios_delegar'), ('J','tareas_ver'), ('J','tareas_equipo'),
  ('V','contactos_ver'), ('V','obras_ver'), ('V','obras_crear'),
  ('H','contactos_ver'), ('H','obras_ver'), ('H','obras_crear'),
  ('W','contactos_ver'), ('W','obras_ver'), ('W','obras_crear'),
  ('I','contactos_ver'), ('I','obras_ver'), ('I','obras_crear'),
  ('V2','contactos_ver'), ('V2','obras_ver'), ('V2','obras_crear'),
  ('V3','contactos_ver'), ('V3','obras_ver'), ('V3','obras_crear'),
  ('W2','contactos_ver'), ('W2','obras_ver'), ('W2','obras_crear'),
  ('J2','contactos_ver'), ('J2','obras_ver'), ('J2','obras_equipo'), ('J2','usuarios_equipo'), ('J2','usuarios_delegar'), ('J2','tareas_ver'), ('J2','tareas_equipo'),
  ('H2','contactos_ver'), ('H2','obras_ver'), ('H2','obras_crear')
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

SELECT pg_temp.caso('00 J es delegador de Norte', 'true',
  (SELECT usuario_tiene_permiso(pg_temp.id('J'), 'usuarios_delegar')::text));
SELECT pg_temp.caso('00 J tiene obras_equipo', 'true',
  (SELECT usuario_tiene_permiso(pg_temp.id('J'), 'obras_equipo')::text));
SELECT pg_temp.caso('00 Sur no tiene jefe de obras', NULL, (SELECT obras_jefe_de(pg_temp.id('Sur'))::text));

-- H, para que V, I y (más adelante) J puedan participar de una obra que no es la propia.
SELECT pg_temp.caso('00 H crea ObH', 'ok', pg_temp.crear_obra('ObH', 'H'));
SELECT pg_temp.caso('00 H crea ObH2', 'ok', pg_temp.crear_obra('ObH2', 'H'));

-- ============================================================
-- 01/02/03(V) — Baja de V: obras (todas), participaciones y agenda
-- ============================================================
SELECT pg_temp.caso('01 V crea Ob1V (abierta)', 'ok', pg_temp.crear_obra('Ob1V', 'V'));
SELECT pg_temp.caso('01 V crea Ob2V', 'ok', pg_temp.crear_obra('Ob2V', 'V'));
SELECT pg_temp.caso('01 V la pierde', 'ok', pg_temp.editar_obra('Ob2V', $s$estado = 'perdida', motivo_perdida = 'precio'$s$, 'V'));
SELECT pg_temp.caso('01 V crea Ob3V', 'ok', pg_temp.crear_obra('Ob3V', 'V'));
SELECT pg_temp.caso('01 V la contrata', 'ok', pg_temp.editar_obra('Ob3V', $s$estado = 'contratada'$s$, 'V'));
SELECT pg_temp.caso('01 V crea Ob4V', 'ok', pg_temp.crear_obra('Ob4V', 'V'));
SELECT pg_temp.caso('01 V la desactiva', 'ok', pg_temp.desactivar_obra('Ob4V', 'V'));
SELECT pg_temp.caso('01 V crea Ob6V (para el huérfano de equipo Sur)', 'ok', pg_temp.crear_obra('Ob6V', 'V'));
SELECT pg_temp.caso('01 se le fuerza el equipo Sur', 'ok', pg_temp.forzar_equipo('Ob6V', 'Sur'));
SELECT pg_temp.caso('01 V suma a J como participante de Ob1V', 'ok', pg_temp.sumar_participante('Ob1V', 'J', 'V'));
SELECT pg_temp.caso('01 H suma a V como participante de ObH', 'ok', pg_temp.sumar_participante('ObH', 'V', 'H'));
SELECT pg_temp.caso('02 V crea a P1V', 'ok', pg_temp.crear_persona('P1V', 'V'));

SELECT pg_temp.caso('01 baja de V', 'ok', pg_temp.baja('V'));

SELECT pg_temp.caso('01 Ob1V (abierta) pasa a J, sigue en Norte', 'J:Norte:true', pg_temp.obra_estado('Ob1V'));
SELECT pg_temp.caso('01 Ob2V (perdida) pasa a J', 'J:Norte:true', pg_temp.obra_estado('Ob2V'));
SELECT pg_temp.caso('01 Ob3V (contratada) pasa a J', 'J:Norte:true', pg_temp.obra_estado('Ob3V'));
SELECT pg_temp.caso('01 Ob4V (desactivada) pasa a J igual', 'J:Norte:false', pg_temp.obra_estado('Ob4V'));
SELECT pg_temp.caso('01 J participaba de Ob1V: deja de participar al ser el nuevo responsable', 'false:Norte',
  pg_temp.participante('Ob1V', 'J'));
SELECT pg_temp.caso('01 la participación de V en ObH queda inactiva', 'false:Norte', pg_temp.participante('ObH', 'V'));
SELECT pg_temp.caso('01 J tiene una sola obras_recibidas, de V', 'V', pg_temp.avisos_de('J', 'obras_recibidas'));
SELECT pg_temp.caso('01 J no tiene obra_transferida (la baja corre sin actor)', '', pg_temp.avisos_de('J', 'obra_transferida'));
SELECT pg_temp.caso('01 hay un evento transferencia V->J en Ob1V', 'V->J', pg_temp.evento_transferencia('Ob1V'));

SELECT pg_temp.caso('02 P1V pasa a J', 'J', pg_temp.persona_resp('P1V'));
SELECT pg_temp.caso('02 J tiene una sola agenda_recibida, de V', 'V', pg_temp.avisos_de('J', 'agenda_recibida'));
SELECT pg_temp.caso('02 J no tiene persona_transferida', '', pg_temp.avisos_de('J', 'persona_transferida'));

SELECT pg_temp.caso('03 Ob6V (equipo Sur, sin jefe) queda con V', 'V:Sur:true', pg_temp.obra_estado('Ob6V'));
SELECT pg_temp.caso('03 A recibe obras_huerfanas sobre V', 'V', pg_temp.avisos_de('A', 'obras_huerfanas'));

-- ============================================================
-- 03 — Baja de W (Sur, sin jefe): obras y personas quedan con él
-- ============================================================
SELECT pg_temp.caso('03 W crea ObW', 'ok', pg_temp.crear_obra('ObW', 'W'));
SELECT pg_temp.caso('03 W crea a P1W', 'ok', pg_temp.crear_persona('P1W', 'W'));
SELECT pg_temp.caso('03 baja de W', 'ok', pg_temp.baja('W'));
SELECT pg_temp.caso('03 ObW queda con W (Sur no tiene jefe)', 'W:Sur:true', pg_temp.obra_estado('ObW'));
SELECT pg_temp.caso('03 P1W queda con W', 'W', pg_temp.persona_resp('P1W'));
SELECT pg_temp.caso('03 A recibe obras_huerfanas sobre W', 'V,W', pg_temp.avisos_de('A', 'obras_huerfanas'));
SELECT pg_temp.caso('03 A recibe personas_huerfanas sobre W', 'W', pg_temp.avisos_de('A', 'personas_huerfanas'));

-- ============================================================
-- 03 — Baja de alguien sin obras ni personas: A no recibe nada
-- ============================================================
SELECT pg_temp.caso('03 baja de Q (sin nada)', 'ok', pg_temp.baja('Q'));
SELECT pg_temp.caso('03 A no gana obras_huerfanas por Q', 'V,W', pg_temp.avisos_de('A', 'obras_huerfanas'));
SELECT pg_temp.caso('03 A no gana personas_huerfanas por Q', 'W', pg_temp.avisos_de('A', 'personas_huerfanas'));

-- ============================================================
-- 04 — asignar_equipo: obras siempre al jefe, la agenda según el 4.º argumento
-- ============================================================
SELECT pg_temp.caso('04 V2 crea ObV2', 'ok', pg_temp.crear_obra('ObV2', 'V2'));
SELECT pg_temp.caso('04 V2 crea a P1V2', 'ok', pg_temp.crear_persona('P1V2', 'V2'));
SELECT pg_temp.caso('04 G mueve a V2 a Sur (agenda al jefe, default)', 'ok', pg_temp.asignar('V2', 'Sur'));
SELECT pg_temp.caso('04 ObV2 (era de Norte) pasa a J, sigue en Norte', 'J:Norte:true', pg_temp.obra_estado('ObV2'));
SELECT pg_temp.caso('04 P1V2 pasa a J', 'J', pg_temp.persona_resp('P1V2'));

SELECT pg_temp.caso('04 V3 crea ObV3', 'ok', pg_temp.crear_obra('ObV3', 'V3'));
SELECT pg_temp.caso('04 V3 crea a P1V3', 'ok', pg_temp.crear_persona('P1V3', 'V3'));
SELECT pg_temp.caso('04 G mueve a V3 a Sur, sin pasar la agenda', 'ok', pg_temp.asignar_sin_agenda('V3', 'Sur'));
SELECT pg_temp.caso('04 ObV3 pasa a J igual (el cambio de equipo mueve obras solo)', 'J:Norte:true', pg_temp.obra_estado('ObV3'));
SELECT pg_temp.caso('04 P1V3 se queda con V3', 'V3', pg_temp.persona_resp('P1V3'));

-- ============================================================
-- 05 — Entrar a un equipo desde independiente
-- ============================================================
SELECT pg_temp.caso('05 I crea ObI (independiente, sin equipo)', 'ok', pg_temp.crear_obra('ObI', 'I'));
SELECT pg_temp.caso('05 ObI nace sin equipo', 'I:-:true', pg_temp.obra_estado('ObI'));
SELECT pg_temp.caso('05 H suma a I como participante de ObH (sin equipo)', 'ok', pg_temp.sumar_participante('ObH', 'I', 'H'));
SELECT pg_temp.caso('05 esa participación nace sin equipo', 'true:-', pg_temp.participante('ObH', 'I'));
SELECT pg_temp.caso('05 H suma a I como participante de ObH2', 'ok', pg_temp.sumar_participante('ObH2', 'I', 'H'));
SELECT pg_temp.caso('05 H quita a I de ObH2 antes de que I entre a un equipo', 'ok', pg_temp.quitar_participante('ObH2', 'I', 'H'));

SELECT pg_temp.caso('05 G asigna a I a Norte', 'ok', pg_temp.asignar('I', 'Norte'));
SELECT pg_temp.caso('05 ObI toma Norte', 'I:Norte:true', pg_temp.obra_estado('ObI'));
SELECT pg_temp.caso('05 la participación activa en ObH toma Norte', 'true:Norte', pg_temp.participante('ObH', 'I'));
SELECT pg_temp.caso('05 la participación cerrada de ObH2 queda sin equipo', 'false:-', pg_temp.participante('ObH2', 'I'));

-- ============================================================
-- 06 — quitar_delegador con heredero, y después la baja del saliente
-- ============================================================
SELECT pg_temp.caso('06 ObJ2, de J2 (Centro), alta directa', 'ok', pg_temp.crear_obra_para('ObJ2', 'J2'));
SELECT pg_temp.caso('06 GA quita a J2 como delegador, con H2 de heredero', 'ok', pg_temp.quitar_delegador('J2', 'H2'));
SELECT pg_temp.caso('06 J2 pierde usuarios_delegar', 'false',
  (SELECT usuario_tiene_permiso(pg_temp.id('J2'), 'usuarios_delegar')::text));
SELECT pg_temp.caso('06 H2 hereda obras_equipo', 'true',
  (SELECT usuario_tiene_permiso(pg_temp.id('H2'), 'obras_equipo')::text));
SELECT pg_temp.caso('06 baja de J2', 'ok', pg_temp.baja('J2'));
SELECT pg_temp.caso('06 ObJ2 pasa a H2 (el nuevo jefe de Centro)', 'H2:Centro:true', pg_temp.obra_estado('ObJ2'));

-- ============================================================
-- 07 — Pierde obras_ver sin baja: huérfana igual
-- ============================================================
SELECT pg_temp.caso('07 W2 crea ObW2', 'ok', pg_temp.crear_obra('ObW2', 'W2'));
SELECT pg_temp.caso('07 A no tenía huérfanas de W2 todavía', '-', pg_temp.fila('A', 'obras_huerfanas', 'W2'));
-- obras_crear es función de la vista obras_ver (US001): se apaga primero para
-- poder apagar la vista sin dar de baja a W2.
SELECT pg_temp.caso('07 se le apaga obras_crear a W2 (función de la vista)', 'ok', pg_temp.perder_permiso('W2', 'obras_crear'));
SELECT pg_temp.caso('07 y obras_aprobar (tramo 3, ver el montaje)', 'ok', pg_temp.perder_permiso('W2', 'obras_aprobar'));
SELECT pg_temp.caso('07 se le apaga obras_ver a W2 (sin baja)', 'ok', pg_temp.perder_permiso('W2', 'obras_ver'));
SELECT pg_temp.caso('07 A recibe obras_huerfanas sobre W2', '1 obra|obras_todas', pg_temp.fila('A', 'obras_huerfanas', 'W2'));

-- ============================================================
-- 08 — notificaciones_listar: motivo con el conteo, y J/H siguen operando
-- ============================================================
SELECT pg_temp.caso('08 como J: obras_recibidas de V, destino obras', '3 obras|obras',
  pg_temp.fila('J', 'obras_recibidas', 'V'));
SELECT pg_temp.caso('08 J transfiere Ob1V a H (sin quedarme)', 'ok', pg_temp.transferir('Ob1V', 'H', false, 'J'));
SELECT pg_temp.caso('08 el motivo baja a N-1', '2 obras|obras', pg_temp.fila('J', 'obras_recibidas', 'V'));
SELECT pg_temp.caso('08 J transfiere Ob2V a H', 'ok', pg_temp.transferir('Ob2V', 'H', false, 'J'));
SELECT pg_temp.caso('08 J transfiere Ob3V a H', 'ok', pg_temp.transferir('Ob3V', 'H', false, 'J'));
SELECT pg_temp.caso('08 con 0, la fila desaparece', '-', pg_temp.fila('J', 'obras_recibidas', 'V'));

SELECT pg_temp.caso('08 como A: obras_huerfanas de V, destino obras_todas', '1 obra|obras_todas',
  pg_temp.fila('A', 'obras_huerfanas', 'V'));
SELECT pg_temp.caso('08 como A: personas_huerfanas de W, destino contactos', '1 persona|contactos',
  pg_temp.fila('A', 'personas_huerfanas', 'W'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
