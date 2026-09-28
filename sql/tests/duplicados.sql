-- Verificación de sql/137 a sql/139: parecidas, congelado, vínculos guardados,
-- "Por aprobar" y las tres salidas. NO es una migración: todo corre dentro de
-- una transacción que revierte. Termina en un DO que lanza "N / M ok" y los
-- casos que fallan.
--
-- Mundo: equipo Norte (Juan) y Sur (Pedro; Laura, jefa con obras_equipo). Ana
-- aprueba altas de obras y de contactos, y puede crear obras. Juan tiene Torre
-- Belgrano (Av. Libertador 1200), a Marta Gómez (tel 1155550139) y la
-- Constructora Caputo. Pedro tiene Casa Núñez y a Rosa Pérez. El montaje
-- escribe como superusuario (sin actor, no congela); todo lo demás, como cada
-- uno. Todo va en la misma transacción, así que para probar "congelada de
-- antes" se atrasa `created_at` a mano. Nombres con `Zqx139`.

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
FROM unnest(ARRAY['Juan','Pedro','Laura','Ana','Norte','Sur',
                  'Torre','Marta','Caputo','Nunez','Rosa']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','obras_ver','obras_crear','obras_equipo','usuarios_delegar','usuarios_equipo',
   'tareas_ver','tareas_equipo','obras_aprobar','contactos_aprobar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test139.local', jsonb_build_object('nombre', 'test139 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro','Laura','Ana');

INSERT INTO equipos (id, nombre)
SELECT id, 'test139 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n) FROM (VALUES ('Norte','Juan'),('Sur','Pedro'),('Sur','Laura')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('Laura','tareas_ver'), ('Laura','tareas_equipo'), ('Laura','usuarios_equipo'), ('Laura','usuarios_delegar'),
  ('Laura','obras_ver'), ('Laura','obras_equipo'), ('Laura','contactos_ver'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','obras_crear'),
  ('Ana','obras_aprobar'), ('Ana','contactos_aprobar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Torre'), 'Zqx139 Torre Belgrano', 'Av. Libertador 1200', 'otro', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Nunez'), 'Zqx139 Casa Núñez', 'Calle Falsa 4321', 'otro', 'casa',
        pg_temp.id('Pedro'), pg_temp.id('Pedro'));
INSERT INTO contactos_personas (id, nombre, telefono, responsable_id, creado_por)
VALUES (pg_temp.id('Marta'), 'Zqx139 Marta Gómez', '11-5555-0139', pg_temp.id('Juan'), pg_temp.id('Juan')),
       (pg_temp.id('Rosa'), 'Zqx139 Rosa Pérez', NULL, pg_temp.id('Pedro'), pg_temp.id('Pedro'));
INSERT INTO contactos_empresas (id, nombre, creado_por)
VALUES (pg_temp.id('Caputo'), 'Zqx139 Constructora Caputo', pg_temp.id('Juan'));

SELECT pg_temp.caso('00 montaje sin congeladas', '0', (
  SELECT count(*)::text FROM (
    SELECT congelada FROM obras WHERE id IN (pg_temp.id('Torre'), pg_temp.id('Nunez'))
    UNION ALL SELECT congelada FROM contactos_personas WHERE id IN (pg_temp.id('Marta'), pg_temp.id('Rosa'))
    UNION ALL SELECT congelada FROM contactos_empresas WHERE id = pg_temp.id('Caputo')
  ) x WHERE congelada));

-- ============================================================
-- 01. Qué es parecida
-- ============================================================
SELECT pg_temp.caso('01 "Av. del Libertador 1200" se parece a Torre (dirección)', 'direccion', (
  SELECT coincide FROM obras_parecidas_de(NULL, 'Zqx139 Edificio Aurora', 'Av. del Libertador 1200')
  WHERE id = pg_temp.id('Torre')));
SELECT pg_temp.caso('01 "Libertador 1250" no (otro número)', '0', (
  SELECT count(*)::text FROM obras_parecidas_de(NULL, 'Zqx139 Edificio Aurora', 'Libertador 1250')
  WHERE id = pg_temp.id('Torre')));
SELECT pg_temp.caso('01 "Torre Belgrano" sin acento ni mayúsculas se parece (nombre)', 'nombre', (
  SELECT coincide FROM obras_parecidas_de(NULL, 'zqx139 torre belgrano', 'Calle 9')
  WHERE id = pg_temp.id('Torre')));
SELECT pg_temp.caso('01 persona: mismo teléfono con otro formato', '{telefono}', (
  SELECT coincide::text FROM contactos_personas_parecidas_de(NULL, 'Zqx139 Nadie Igual', '(11) 5555 0139', NULL)
  WHERE id = pg_temp.id('Marta')));
SELECT pg_temp.caso('01 persona: "Marta Gomez" sin acento (nombre)', '{nombre}', (
  SELECT coincide::text FROM contactos_personas_parecidas_de(NULL, 'Zqx139 Marta Gomez', NULL, NULL)
  WHERE id = pg_temp.id('Marta')));
SELECT pg_temp.caso('01 empresa: "Constructora Caputo SA"', '1', (
  SELECT count(*)::text FROM contactos_empresas_parecidas_de(NULL, 'Zqx139 Constructora Caputo SA')
  WHERE id = pg_temp.id('Caputo')));

-- ============================================================
-- 02. Aviso a ciegas
-- ============================================================
SELECT pg_temp.caso('02 Pedro: Torre, sin id ni dirección, con su responsable', 'test139 Juan', pg_temp.consultar(
  $s$SELECT responsable FROM obras_parecidas('Zqx139 Torre Belgrano', 'Calle 9')
     WHERE nombre = 'Zqx139 Torre Belgrano' AND id IS NULL AND direccion IS NULL$s$, 'Pedro'));
SELECT pg_temp.caso('02 Juan: su Torre, con id', pg_temp.id('Torre')::text, pg_temp.consultar(
  $s$SELECT id::text FROM obras_parecidas('Zqx139 Torre Belgrano', 'Calle 9') WHERE nombre = 'Zqx139 Torre Belgrano'$s$,
  'Juan'));
SELECT pg_temp.caso('02 Pedro: Marta, de Juan, sin id ni qué coincidió', 'test139 Juan', pg_temp.consultar(
  $s$SELECT dueno FROM contactos_parecidas('persona', 'Zqx139 Marta Gomez')
     WHERE nombre = 'Zqx139 Marta Gómez' AND id IS NULL AND coincide IS NULL$s$, 'Pedro'));
SELECT pg_temp.caso('02 Juan: "Ya la tenés", con id', pg_temp.id('Marta')::text, pg_temp.consultar(
  $s$SELECT id::text FROM contactos_parecidas('persona', 'Zqx139 Marta Gomez') WHERE nombre = 'Zqx139 Marta Gómez'$s$,
  'Juan'));
SELECT pg_temp.caso('02 Pedro: Caputo, con su equipo', '1', pg_temp.ve(format(
  $s$SELECT 1 FROM contactos_parecidas('empresa', 'Zqx139 Constructora Caputo') WHERE id IS NULL AND equipo LIKE %L$s$,
  'test139 Norte%'), 'Pedro'));

-- ============================================================
-- 03. Pedro carga la Belgrano de Juan, con Rosa de referente
-- ============================================================
SELECT pg_temp.caso('03 alta', 'ok', pg_temp.alta('BelgranoPedro', format(
  $s$SELECT obras_alta('Zqx139 Edificio Aurora', 'Av. del Libertador 1200', 'referente', 'edificio_residencial',
     p_quien_persona => %L)$s$, pg_temp.id('Rosa')), 'Pedro'));
SELECT pg_temp.caso('03 entra congelada', 'true',
  (SELECT congelada::text FROM obras WHERE id = pg_temp.id('BelgranoPedro')));
SELECT pg_temp.caso('03 sin vínculo real', '0',
  (SELECT count(*)::text FROM contactos_vinculos WHERE registro_id = pg_temp.id('BelgranoPedro')));
SELECT pg_temp.caso('03 un vínculo guardado: Rosa, referente, cargado por Pedro', '1', (
  SELECT count(*)::text FROM contactos_vinculos_guardados
  WHERE activo AND registro_id = pg_temp.id('BelgranoPedro') AND persona_id = pg_temp.id('Rosa')
    AND roles = '{referente}' AND cargado_por = pg_temp.id('Pedro')));
SELECT pg_temp.caso('03 sin evento alta', '0',
  (SELECT count(*)::text FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id('BelgranoPedro')));
SELECT pg_temp.caso('03 Pedro la ve', '1', pg_temp.ve(format(
  'SELECT 1 FROM obras WHERE id = %L', pg_temp.id('BelgranoPedro')), 'Pedro'));
SELECT pg_temp.caso('03 Laura (jefa de Sur) no la ve', '0', pg_temp.ve(format(
  'SELECT 1 FROM obras WHERE id = %L', pg_temp.id('BelgranoPedro')), 'Laura'));
SELECT pg_temp.caso('03 Ana no la ve por RLS', '0', pg_temp.ve(format(
  'SELECT 1 FROM obras WHERE id = %L', pg_temp.id('BelgranoPedro')), 'Ana'));
SELECT pg_temp.caso('03 Ana: "alta por aprobar" en la campanita, a Por aprobar', 'obras_por_aprobar', pg_temp.consultar(format(
  $s$SELECT destino FROM notificaciones_listar() WHERE tipo = 'alta_por_aprobar' AND destino_id = %L$s$,
  pg_temp.id('BelgranoPedro')), 'Ana'));

-- ============================================================
-- 04. Congelada: se edita, pero no cambia de estado ni suma participantes
-- ============================================================
SELECT pg_temp.caso('04 Pedro edita las notas', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET notas = 'Zqx139 nota' WHERE id = %L$s$, pg_temp.id('BelgranoPedro')), 'Pedro'));
SELECT pg_temp.caso('04 sigue congelada', 'true',
  (SELECT congelada::text FROM obras WHERE id = pg_temp.id('BelgranoPedro')));
SELECT pg_temp.caso('04 cambiar el estado', 'OB018', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_busqueda' WHERE id = %L$s$, pg_temp.id('BelgranoPedro')), 'Pedro'));
SELECT pg_temp.caso('04 sumar a Laura', 'OB018', pg_temp.intentar(format(
  'INSERT INTO obras_participantes (obra_id, usuario_id) VALUES (%L, %L)',
  pg_temp.id('BelgranoPedro'), pg_temp.id('Laura')), 'Pedro'));
SELECT pg_temp.caso('04 transferir a Laura', 'OB018', pg_temp.intentar(format(
  'SELECT obras_transferir(%L, %L)', pg_temp.id('BelgranoPedro'), pg_temp.id('Laura')), 'Pedro'));

-- ============================================================
-- 05. Por aprobar
-- ============================================================
SELECT pg_temp.caso('05 Ana la ve con Torre de parecida y Rosa guardada', 'Zqx139 Torre Belgrano|Zqx139 Rosa Pérez',
  pg_temp.consultar(format(
    $s$SELECT (SELECT string_agg(p->>'nombre', ',') FROM jsonb_array_elements(parecidas) p
               WHERE p->>'id' = %L) || '|' || (guardados->0->>'nombre')
       FROM obras_por_aprobar() WHERE id = %L$s$,
    pg_temp.id('Torre'), pg_temp.id('BelgranoPedro')), 'Ana'));
SELECT pg_temp.caso('05 Juan no tiene Por aprobar', '0', pg_temp.ve(
  'SELECT 1 FROM obras_por_aprobar()', 'Juan'));
SELECT pg_temp.caso('05 Juan no resuelve', 'OB019', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'aprobar')$s$, pg_temp.id('BelgranoPedro')), 'Juan'));

-- ============================================================
-- 06. "Es la misma": Pedro participa de Torre y Rosa queda de referente
-- ============================================================
SELECT pg_temp.caso('06 existente inválida (la misma congelada)', 'OB023', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'es_la_misma', p_existente => %L)$s$,
  pg_temp.id('BelgranoPedro'), pg_temp.id('BelgranoPedro')), 'Ana'));
SELECT pg_temp.caso('06 Ana: es la misma que Torre', 'ok', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'es_la_misma', p_existente => %L)$s$,
  pg_temp.id('BelgranoPedro'), pg_temp.id('Torre')), 'Ana'));
SELECT pg_temp.caso('06 la de Pedro, desactivada y apuntando a Torre', 'false|false|' || pg_temp.id('Torre'), (
  SELECT activo || '|' || congelada || '|' || misma_que FROM obras WHERE id = pg_temp.id('BelgranoPedro')));
SELECT pg_temp.caso('06 Pedro participa de Torre', '1', (
  SELECT count(*)::text FROM obras_participantes
  WHERE obra_id = pg_temp.id('Torre') AND usuario_id = pg_temp.id('Pedro') AND activo));
SELECT pg_temp.caso('06 Rosa, referente de Torre, a nombre de Pedro', 'referente', (
  SELECT array_to_string(roles, ',') FROM contactos_vinculos
  WHERE persona_id = pg_temp.id('Rosa') AND registro_id = pg_temp.id('Torre') AND activo
    AND creado_por = pg_temp.id('Pedro')));
SELECT pg_temp.caso('06 el guardado quedó creado', 'creado', (
  SELECT resultado FROM contactos_vinculos_guardados WHERE persona_id = pg_temp.id('Rosa')));
SELECT pg_temp.caso('06 la de Pedro no emitió alta ni baja', '0',
  (SELECT count(*)::text FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id('BelgranoPedro')));
SELECT pg_temp.caso('06 Ana: el aviso por aprobar se fue', '0', pg_temp.ve(format(
  $s$SELECT 1 FROM notificaciones_listar() WHERE tipo = 'alta_por_aprobar' AND destino_id = %L$s$,
  pg_temp.id('BelgranoPedro')), 'Ana'));
SELECT pg_temp.caso('06 Pedro: es la misma que Torre, con link', 'Zqx139 Torre Belgrano|obra', pg_temp.consultar(
  $s$SELECT motivo || '|' || destino FROM notificaciones_listar() WHERE tipo = 'alta_es_la_misma'$s$, 'Pedro'));
SELECT pg_temp.caso('06 Juan: Pedro se sumó a Torre', 'Zqx139 Torre Belgrano|test139 Pedro', pg_temp.consultar(
  $s$SELECT etiqueta || '|' || motivo FROM notificaciones_listar() WHERE tipo = 'obra_misma_sumado'$s$, 'Juan'));
SELECT pg_temp.caso('06 ya resuelta', 'OB020', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'aprobar')$s$, pg_temp.id('BelgranoPedro')), 'Ana'));

-- ============================================================
-- 07. Aprobar una homónima: nace entonces
-- ============================================================
SELECT pg_temp.caso('07 alta de Pedro parecida por nombre', 'ok', pg_temp.alta('Homonima',
  $s$SELECT obras_alta('Zqx139 Torre Belgranos', 'Calle Otra 77', 'otro', 'casa')$s$, 'Pedro'));
SELECT pg_temp.caso('07 congelada', 'true', (SELECT congelada::text FROM obras WHERE id = pg_temp.id('Homonima')));
SELECT pg_temp.caso('07 rechazar sin motivo', 'OB021', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'rechazar', '  ')$s$, pg_temp.id('Homonima')), 'Ana'));
SELECT pg_temp.caso('07 Ana aprueba', 'ok', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'aprobar')$s$, pg_temp.id('Homonima')), 'Ana'));
SELECT pg_temp.caso('07 evento alta, uno', '1', (
  SELECT count(*)::text FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id('Homonima') AND evento = 'alta'));
SELECT pg_temp.caso('07 Laura ya la ve', '1', pg_temp.ve(format(
  'SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Homonima')), 'Laura'));
SELECT pg_temp.caso('07 Pedro: alta aprobada', '1', pg_temp.ve(format(
  $s$SELECT 1 FROM notificaciones_listar() WHERE tipo = 'alta_aprobada' AND destino_id = %L$s$,
  pg_temp.id('Homonima')), 'Pedro'));

-- ============================================================
-- 08. Lo que carga quien aprueba no se congela
-- ============================================================
SELECT pg_temp.caso('08 Ana carga una igual a Torre', 'ok', pg_temp.alta('DeAna',
  $s$SELECT obras_alta('Zqx139 Torre Belgrano', 'Av. Libertador 1200', 'otro', 'casa')$s$, 'Ana'));
SELECT pg_temp.caso('08 no congelada', 'false', (SELECT congelada::text FROM obras WHERE id = pg_temp.id('DeAna')));

-- ============================================================
-- 09. Editar también congela; rechazar vuelve al dato anterior
-- ============================================================
SELECT pg_temp.caso('09 Pedro renombra Casa Núñez como Torre Belgrano', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET nombre = 'Zqx139 Torre Belgrano' WHERE id = %L$s$, pg_temp.id('Nunez')), 'Pedro'));
SELECT pg_temp.caso('09 congelada, con el nombre anterior guardado', 'true|Zqx139 Casa Núñez', (
  SELECT congelada || '|' || (congelada_antes->>'nombre') FROM obras WHERE id = pg_temp.id('Nunez')));
SELECT pg_temp.caso('09 Laura la sigue viendo (edición)', '1', pg_temp.ve(format(
  'SELECT 1 FROM obras WHERE id = %L', pg_temp.id('Nunez')), 'Laura'));
SELECT pg_temp.caso('09 "es la misma" no va con una edición', 'OB022', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'es_la_misma', p_existente => %L)$s$, pg_temp.id('Nunez'), pg_temp.id('Torre')), 'Ana'));
SELECT pg_temp.caso('09 Ana rechaza', 'ok', pg_temp.intentar(format(
  $s$SELECT obras_resolver(%L, 'rechazar', 'Es otra obra, no la renombres')$s$, pg_temp.id('Nunez')), 'Ana'));
SELECT pg_temp.caso('09 vuelve el nombre, activa y descongelada', 'Zqx139 Casa Núñez|true|false', (
  SELECT nombre || '|' || activo || '|' || congelada FROM obras WHERE id = pg_temp.id('Nunez')));
SELECT pg_temp.caso('09 Pedro: rechazada, con el motivo', 'Es otra obra, no la renombres', pg_temp.consultar(
  $s$SELECT motivo FROM notificaciones_listar() WHERE tipo = 'alta_rechazada'$s$, 'Pedro'));
SELECT pg_temp.caso('09 renombrar y volver: se descongela sola', 'okokfalse', (
  SELECT pg_temp.intentar(format($s$UPDATE obras SET nombre = 'Zqx139 Torre Belgrano' WHERE id = %L$s$,
                                 pg_temp.id('Nunez')), 'Pedro')
      || pg_temp.intentar(format($s$UPDATE obras SET nombre = 'Zqx139 Casa Núñez' WHERE id = %L$s$,
                                 pg_temp.id('Nunez')), 'Pedro')
      || (SELECT congelada::text FROM obras WHERE id = pg_temp.id('Nunez'))) );

-- ============================================================
-- 10. Una congelada de antes no se vincula
-- ============================================================
SELECT pg_temp.caso('10 alta congelada', 'ok', pg_temp.alta('Vieja',
  $s$SELECT obras_alta('Zqx139 Torre Belgrano Norte', 'Calle 3', 'otro', 'casa')$s$, 'Pedro'));
UPDATE obras SET created_at = created_at - interval '1 hour' WHERE id = pg_temp.id('Vieja');
SELECT pg_temp.caso('10 vincular a Rosa después', 'CO020', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (persona_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{cliente}')$s$,
  pg_temp.id('Rosa'), pg_temp.id('Vieja')), 'Pedro'));

-- ============================================================
-- 11. Persona desde el panel: "es la misma" le deja a Pedro la Marta de Juan
-- ============================================================
SELECT pg_temp.caso('11 Pedro crea "Marta Gomez" para Casa Núñez', 'ok', pg_temp.alta('Marta2', format(
  $s$SELECT contactos_crear_y_vincular('obra', %L, '{arquitecto}', 'persona', 'Zqx139 Marta Gomez')$s$,
  pg_temp.id('Nunez')), 'Pedro'));
SELECT pg_temp.caso('11 congelada y guardada', 'true|1', (
  SELECT (SELECT congelada::text FROM contactos_personas WHERE id = pg_temp.id('Marta2')) || '|' ||
         (SELECT count(*) FROM contactos_vinculos_guardados WHERE activo AND persona_id = pg_temp.id('Marta2'))));
SELECT pg_temp.caso('11 Ana la ve en Por aprobar, parecida a Marta por nombre', '["nombre"]', pg_temp.consultar(format(
  $s$SELECT (SELECT (p->'coincide')::text FROM jsonb_array_elements(parecidas) p WHERE p->>'id' = %L)
     FROM contactos_por_aprobar() WHERE id = %L$s$, pg_temp.id('Marta'), pg_temp.id('Marta2')), 'Ana'));
SELECT pg_temp.caso('11 Ana ve su contacto (Ver contacto)', 'ok', pg_temp.intentar(format(
  'SELECT contactos_ver_contacto(%L)', pg_temp.id('Marta2')), 'Ana'));
SELECT pg_temp.caso('11 Ana: es la misma que Marta, vinculando', 'ok', pg_temp.intentar(format(
  $s$SELECT contactos_resolver('persona', %L, 'es_la_misma', p_existente => %L)$s$,
  pg_temp.id('Marta2'), pg_temp.id('Marta')), 'Ana'));
SELECT pg_temp.caso('11 Marta, arquitecta de Casa Núñez, a nombre de Pedro', 'arquitecto', (
  SELECT array_to_string(roles, ',') FROM contactos_vinculos
  WHERE persona_id = pg_temp.id('Marta') AND registro_id = pg_temp.id('Nunez') AND activo
    AND creado_por = pg_temp.id('Pedro')));
SELECT pg_temp.caso('11 Marta sigue siendo de Juan', pg_temp.id('Juan')::text, (
  SELECT responsable_id::text FROM contactos_personas WHERE id = pg_temp.id('Marta')));
SELECT pg_temp.caso('11 Pedro ve a Marta en contexto', '1', pg_temp.ve(format(
  'SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('11 Pedro vincula él solo a Marta en otra obra', 'CO016', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (persona_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{cliente}')$s$,
  pg_temp.id('Marta'), pg_temp.id('Homonima')), 'Pedro'));

-- ============================================================
-- 12. Mismo teléfono: no se aprueba, se rechaza
-- ============================================================
SELECT pg_temp.caso('12 Pedro crea otra con el teléfono de Marta', 'ok', pg_temp.intentar(
  $s$INSERT INTO contactos_personas (nombre, telefono) VALUES ('Zqx139 Alguien Distinto', '1155550139')$s$, 'Pedro'));
INSERT INTO ids SELECT 'Tel', id FROM contactos_personas WHERE nombre = 'Zqx139 Alguien Distinto';
SELECT pg_temp.caso('12 congelada', 'true', (SELECT congelada::text FROM contactos_personas WHERE id = pg_temp.id('Tel')));
SELECT pg_temp.caso('12 aprobar', 'CO023', pg_temp.intentar(format(
  $s$SELECT contactos_resolver('persona', %L, 'aprobar')$s$, pg_temp.id('Tel')), 'Ana'));
SELECT pg_temp.caso('12 transferirla', 'CO020', pg_temp.intentar(format(
  'SELECT contactos_transferir_persona(%L, %L)', pg_temp.id('Tel'), pg_temp.id('Laura')), 'Pedro'));
SELECT pg_temp.caso('12 rechazar', 'ok', pg_temp.intentar(format(
  $s$SELECT contactos_resolver('persona', %L, 'rechazar', 'Es Marta Gómez')$s$, pg_temp.id('Tel')), 'Ana'));
SELECT pg_temp.caso('12 desactivada con el motivo, sin baja', 'false|Es Marta Gómez|0', (
  SELECT activo || '|' || rechazo_motivo || '|' ||
         (SELECT count(*) FROM eventos WHERE ente = 'persona' AND registro_id = p.id)
  FROM contactos_personas p WHERE id = pg_temp.id('Tel')));
SELECT pg_temp.caso('12 Pedro: rechazada, sin link', 'Es Marta Gómez|', pg_temp.consultar(format(
  $s$SELECT motivo || '|' || coalesce(destino, '') FROM notificaciones_listar() n
     WHERE tipo = 'alta_rechazada' AND etiqueta = 'Zqx139 Alguien Distinto'$s$), 'Pedro'));

-- ============================================================
-- 13. Empresa: el alta congelada no la ve su equipo hasta aprobarse
-- ============================================================
SELECT pg_temp.caso('13 Pedro crea "Constructora Caputo"', 'ok', pg_temp.intentar(
  $s$INSERT INTO contactos_empresas (nombre) VALUES ('Zqx139 Constructora Caputo')$s$, 'Pedro'));
INSERT INTO ids SELECT 'Caputo2', id FROM contactos_empresas WHERE nombre = 'Zqx139 Constructora Caputo' AND creado_por = pg_temp.id('Pedro');
SELECT pg_temp.caso('13 congelada', 'true', (SELECT congelada::text FROM contactos_empresas WHERE id = pg_temp.id('Caputo2')));
SELECT pg_temp.caso('13 Laura (su equipo) no la ve', '0', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo2')), 'Laura'));
SELECT pg_temp.caso('13 Ana: Caputo de Norte en las parecidas', '1', pg_temp.consultar(format(
  $s$SELECT (SELECT count(*) FROM jsonb_array_elements(parecidas) p WHERE p->>'id' = %L)::text
     FROM contactos_por_aprobar() WHERE id = %L$s$,
  pg_temp.id('Caputo'), pg_temp.id('Caputo2')), 'Ana'));
SELECT pg_temp.caso('13 Ana aprueba', 'ok', pg_temp.intentar(format(
  $s$SELECT contactos_resolver('empresa', %L, 'aprobar')$s$, pg_temp.id('Caputo2')), 'Ana'));
SELECT pg_temp.caso('13 Laura ya la ve', '1', pg_temp.ve(format(
  'SELECT 1 FROM contactos_empresas WHERE id = %L', pg_temp.id('Caputo2')), 'Laura'));
SELECT pg_temp.caso('13 evento alta al aprobarse', '1', (
  SELECT count(*)::text FROM eventos WHERE ente = 'empresa' AND registro_id = pg_temp.id('Caputo2') AND evento = 'alta'));

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
