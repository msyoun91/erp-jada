-- Verificación de sql/134: las campanitas directas de obras y contactos
-- (obra_transferida, obra_sumado, obra_quitado, persona_transferida) y su
-- lectura por notificaciones_listar. NO es una migración: todo corre dentro
-- de una transacción que termina en ROLLBACK. Correr después de aplicar
-- sql/125 a sql/134.
--
-- Mundo: V y H, ambos independientes (sin equipo), con obras_ver, obras_crear
-- y contactos_ver. No hace falta jefe ni admin: los avisos de este tramo
-- salen de acciones directas (profundidad 1, `auth.uid()`), no de bajas ni
-- cambios de equipo. Nada depende de los datos reales.
--
-- `intentar`, `avisos` y `bandeja` como en `tareas_avisos.sql`.

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

-- `entidad_id` es directo (obras, contactos_personas) salvo en obras_participantes,
-- donde es la fila de participación: ahí el nombre sale de su obra.
CREATE FUNCTION pg_temp.avisos(p_usuario text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(string_agg(n.tipo || ':' || coalesce(
                               pg_temp.nombre(n.entidad_id),
                               (SELECT pg_temp.nombre(p.obra_id) FROM obras_participantes p WHERE p.id = n.entidad_id),
                               '?'), ' '
                             ORDER BY n.tipo::text, coalesce(
                               pg_temp.nombre(n.entidad_id),
                               (SELECT pg_temp.nombre(p.obra_id) FROM obras_participantes p WHERE p.id = n.entidad_id))), '')
  FROM usuario_notificaciones n
  WHERE n.usuario_id = pg_temp.id(p_usuario) AND n.activo;
$f$;

CREATE FUNCTION pg_temp.limpiar() RETURNS void LANGUAGE sql AS $f$
  UPDATE usuario_notificaciones SET activo = false
  WHERE activo AND usuario_id IN (SELECT id FROM ids);
$f$;

-- La bandeja como la ve X: 'etiqueta|destino|destino_id(nombre)' del aviso de ese tipo.
CREATE FUNCTION pg_temp.bandeja(p_como text, p_tipo text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT string_agg(coalesce(l.etiqueta, '?') || '|' || coalesce(l.destino, '-') || '|'
                     || coalesce(pg_temp.nombre(l.destino_id), coalesce(l.destino_id::text, '-')), ' ')
  INTO v
  FROM notificaciones_listar(100) l WHERE l.tipo::text = p_tipo;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.crear_obra(p_obra text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, %L, 'Calle 1', 'otro', 'casa')$s$,
    pg_temp.id(p_obra), p_obra), p_como);
$f$;

CREATE FUNCTION pg_temp.transferir(p_obra text, p_a text, p_quedarme boolean, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT obras_transferir(%L, %L, %L)',
    pg_temp.id(p_obra), pg_temp.id(p_a), p_quedarme), p_como);
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

CREATE FUNCTION pg_temp.crear_persona(p_id text, p_nombre text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO contactos_personas (id, nombre) VALUES (%L, %L)', pg_temp.id(p_id), p_nombre), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['V','H','Obra1','Obra2','Obra3','Persona1']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos WHERE activo AND codigo IN ('obras_ver','obras_crear','contactos_ver');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test134.local', jsonb_build_object('nombre', 'test134 ' || nombre)
FROM ids WHERE nombre IN ('V','H');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('V','obras_ver'), ('V','obras_crear'), ('V','contactos_ver'),
  ('H','obras_ver'), ('H','contactos_ver')
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

-- ============================================================
-- 01 — Transferir una obra: el nuevo responsable recibe, el actor no
-- ============================================================
SELECT pg_temp.caso('01 V crea Obra1', 'ok', pg_temp.crear_obra('Obra1', 'V'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('01 V transfiere Obra1 a H, sin quedarme', 'ok', pg_temp.transferir('Obra1', 'H', false, 'V'));
SELECT pg_temp.caso('01 H: obra transferida', 'obra_transferida:Obra1', pg_temp.avisos('H'));
SELECT pg_temp.caso('01 la bandeja de H: etiqueta el nombre, destino obra, destino_id la obra',
  'Obra1|obra|Obra1', pg_temp.bandeja('H', 'obra_transferida'));
SELECT pg_temp.caso('01 V, que transfirió, no recibe nada', '', pg_temp.avisos('V'));

-- ============================================================
-- 02 — Sumar y quitar un participante
-- ============================================================
SELECT pg_temp.caso('02 V crea Obra2', 'ok', pg_temp.crear_obra('Obra2', 'V'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('02 V suma a H como participante', 'ok', pg_temp.sumar_participante('Obra2', 'H', 'V'));
SELECT pg_temp.caso('02 H: obra sumado', 'obra_sumado:Obra2', pg_temp.avisos('H'));
SELECT pg_temp.caso('02 la bandeja de H trae destino obra', 'Obra2|obra|Obra2', pg_temp.bandeja('H', 'obra_sumado'));
SELECT pg_temp.caso('02 V, que sumó, no recibe nada', '', pg_temp.avisos('V'));

SELECT pg_temp.limpiar();
SELECT pg_temp.caso('02 V quita a H de Obra2', 'ok', pg_temp.quitar_participante('Obra2', 'H', 'V'));
SELECT pg_temp.caso('02 H: obra quitado', 'obra_quitado:Obra2', pg_temp.avisos('H'));
SELECT pg_temp.caso('02 la bandeja de H: el nombre, sin poder verla ya (destino -, destino_id igual resuelve)',
  'Obra2|-|Obra2', pg_temp.bandeja('H', 'obra_quitado'));
SELECT pg_temp.caso('02 V, que quitó, no recibe nada', '', pg_temp.avisos('V'));

-- ============================================================
-- 03 — Transferir a quien ya participaba: no avisa "quitado"
-- ============================================================
SELECT pg_temp.caso('03 V crea Obra3', 'ok', pg_temp.crear_obra('Obra3', 'V'));
SELECT pg_temp.caso('03 V suma a H como participante de Obra3', 'ok', pg_temp.sumar_participante('Obra3', 'H', 'V'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('03 V transfiere Obra3 a H (que ya participaba)', 'ok', pg_temp.transferir('Obra3', 'H', false, 'V'));
SELECT pg_temp.caso('03 la participación de H (ahora responsable) quedó desactivada', 'false',
  (SELECT activo::text FROM obras_participantes WHERE obra_id = pg_temp.id('Obra3') AND usuario_id = pg_temp.id('H')));
SELECT pg_temp.caso('03 H recibe obra transferida, no obra quitado',
  'obra_transferida:Obra3', pg_temp.avisos('H'));
SELECT pg_temp.caso('03 V, que transfirió sin quedarme, no recibe nada', '', pg_temp.avisos('V'));

-- ============================================================
-- 04 — Transferir una persona
-- ============================================================
SELECT pg_temp.caso('04 V crea a Persona1', 'ok', pg_temp.crear_persona('Persona1', 'Persona1', 'V'));
SELECT pg_temp.limpiar();
SELECT pg_temp.caso('04 V transfiere a Persona1 a H', 'ok',
  pg_temp.intentar(format('SELECT contactos_transferir_persona(%L, %L)', pg_temp.id('Persona1'), pg_temp.id('H')), 'V'));
SELECT pg_temp.caso('04 H: persona transferida', 'persona_transferida:Persona1', pg_temp.avisos('H'));
SELECT pg_temp.caso('04 la bandeja de H: etiqueta el nombre, destino persona, destino_id la persona',
  'Persona1|persona|Persona1', pg_temp.bandeja('H', 'persona_transferida'));
SELECT pg_temp.caso('04 V, que transfirió, no recibe nada', '', pg_temp.avisos('V'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
