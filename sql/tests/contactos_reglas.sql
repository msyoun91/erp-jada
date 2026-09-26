-- Verificación de sql/127: personas, empresas, sus vínculos con cualquier
-- registro, "Ver contacto", ediciones, transferir y desactivar. NO es una
-- migración: todo corre dentro de una transacción que termina en ROLLBACK.
-- Correr después de aplicar sql/125 a sql/128.
--
-- Mundo: equipo Norte (Juan vendedor, JN jefe delegador con obras_equipo, Nico
-- vendedor) y equipo Sur (Pedro vendedor, Laura jefa delegadora con
-- obras_equipo). A administra Contactos y Obras, sin equipo. Z no ve
-- Contactos. Obras directas (INSERT como su responsable): Belgrano de Juan
-- (con Pedro participante), Núñez de Pedro, Obra Nico de Nico, ObraJuan2 de
-- Juan (una segunda, para el caso de CO009). Nada depende de los datos
-- reales: los counts van filtrados por los ids del montaje.

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

-- Como `intentar`, pero para funciones que devuelven un único valor (lo
-- necesita, por ejemplo, "Ver contacto").
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

-- Cuántos eventos relacion_* (de Belgrano) hay, sin RLS: para verificar los
-- datos, no la visibilidad (que se prueba aparte con `ve`).
CREATE FUNCTION pg_temp.eventos(p_ente text, p_registro text, p_tipo text, p_contacto text DEFAULT NULL, p_rol text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $f$
  SELECT count(*)::text FROM eventos e
  WHERE e.ente = p_ente AND e.registro_id = pg_temp.id(p_registro) AND e.evento::text = p_tipo
    AND (p_contacto IS NULL OR (e.detalle->>'registro_id')::uuid = pg_temp.id(p_contacto))
    AND (p_rol IS NULL OR e.detalle->>'rol' = p_rol);
$f$;

-- Los roles del vínculo abierto (activo, sin `hasta`) de una persona con un registro.
CREATE FUNCTION pg_temp.roles_abiertos(p_persona text, p_ente text, p_registro text) RETURNS text LANGUAGE sql AS $f$
  SELECT array_to_string(roles, ',') FROM contactos_vinculos
  WHERE persona_id = pg_temp.id(p_persona) AND ente = p_ente AND registro_id = pg_temp.id(p_registro)
    AND activo AND hasta IS NULL;
$f$;

-- El id del vínculo abierto (activo, sin `hasta`) de una persona con un registro.
CREATE FUNCTION pg_temp.vinculo_abierto(p_persona text, p_ente text, p_registro text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM contactos_vinculos
  WHERE persona_id = pg_temp.id(p_persona) AND ente = p_ente AND registro_id = pg_temp.id(p_registro)
    AND activo AND hasta IS NULL;
$f$;

-- El id del único vínculo (cualquier estado) de una persona con un registro.
CREATE FUNCTION pg_temp.vinculo_de(p_persona text, p_ente text, p_registro text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM contactos_vinculos
  WHERE persona_id = pg_temp.id(p_persona) AND ente = p_ente AND registro_id = pg_temp.id(p_registro);
$f$;

CREATE FUNCTION pg_temp.crear_persona(p_id text, p_nombre text, p_telefono text, p_email text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO contactos_personas (id, nombre, telefono, email) VALUES (%L, %L, %L, %L)',
    pg_temp.id(p_id), p_nombre, p_telefono, p_email), p_como);
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

CREATE FUNCTION pg_temp.vincular_empresa(p_empresa text, p_ente text, p_registro text, p_roles text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    'INSERT INTO contactos_vinculos (empresa_id, ente, registro_id, roles) VALUES (%L, %L, %L, %L::text[])',
    pg_temp.id(p_empresa), p_ente, pg_temp.id(p_registro), p_roles), p_como);
$f$;

CREATE FUNCTION pg_temp.crear_obra(p_id text, p_nombre text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, %L, 'Calle 1', 'otro', 'casa')$s$,
    pg_temp.id(p_id), p_nombre), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['A','Z','Juan','Nico','Pedro','JN','Laura','Norte','Sur',
                  'Belgrano','Nunez','ObraNico','ObraJuan2',
                  'Marta','Pepe','Caputo','EstudioG','EmpresaSur','AdminCo','LauraPersona']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','contactos_administrar','obras_ver','obras_crear','obras_equipo','obras_todas',
   'obras_administrar','usuarios_delegar','usuarios_equipo','tareas_ver','tareas_equipo');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test127.local', jsonb_build_object('nombre', 'test127 ' || nombre)
FROM ids WHERE nombre IN ('A','Z','Juan','Nico','Pedro','JN','Laura');

INSERT INTO equipos (id, nombre)
SELECT id, 'test127 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('Norte','Juan'),('Norte','JN'),('Norte','Nico'),('Sur','Pedro'),('Sur','Laura')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('A','contactos_ver'), ('A','contactos_administrar'), ('A','obras_ver'), ('A','obras_todas'), ('A','obras_administrar'),
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Nico','contactos_ver'), ('Nico','obras_ver'), ('Nico','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('JN','tareas_ver'), ('JN','tareas_equipo'), ('JN','usuarios_equipo'), ('JN','usuarios_delegar'), ('JN','obras_ver'), ('JN','obras_equipo'), ('JN','contactos_ver'),
  ('Laura','tareas_ver'), ('Laura','tareas_equipo'), ('Laura','usuarios_equipo'), ('Laura','usuarios_delegar'), ('Laura','obras_ver'), ('Laura','obras_equipo'), ('Laura','contactos_ver')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: Belgrano de Juan', 'ok', pg_temp.crear_obra('Belgrano', 'Belgrano', 'Juan'));
SELECT pg_temp.caso('00 montaje: Núñez de Pedro', 'ok', pg_temp.crear_obra('Nunez', 'Núñez', 'Pedro'));
SELECT pg_temp.caso('00 montaje: Obra Nico de Nico', 'ok', pg_temp.crear_obra('ObraNico', 'Obra Nico', 'Nico'));
SELECT pg_temp.caso('00 montaje: ObraJuan2 de Juan', 'ok', pg_temp.crear_obra('ObraJuan2', 'ObraJuan2', 'Juan'));
SELECT pg_temp.caso('00 montaje: Juan suma a Pedro a Belgrano', 'ok', pg_temp.intentar(format(
  'INSERT INTO obras_participantes (obra_id, usuario_id) VALUES (%L, %L)',
  pg_temp.id('Belgrano'), pg_temp.id('Pedro')), 'Juan'));

-- ============================================================
-- 01. Alta de una persona; teléfono y email normalizados
-- ============================================================
SELECT pg_temp.caso('01 Juan crea a Marta', 'ok',
  pg_temp.crear_persona('Marta', 'Marta', '11 5555-0000', ' Marta@X.com ', 'Juan'));
SELECT pg_temp.caso('01 teléfono normalizado', '1155550000',
  (SELECT telefono FROM contactos_personas WHERE id = pg_temp.id('Marta')));
SELECT pg_temp.caso('01 email normalizado', 'marta@x.com',
  (SELECT email FROM contactos_personas WHERE id = pg_temp.id('Marta')));
SELECT pg_temp.caso('01 responsable Juan', pg_temp.id('Juan')::text,
  (SELECT responsable_id::text FROM contactos_personas WHERE id = pg_temp.id('Marta')));

-- ============================================================
-- 02. El teléfono no se lee por SELECT directo, el nombre sí
-- ============================================================
SELECT pg_temp.caso('02 Juan no lee el teléfono por SELECT', '42501',
  pg_temp.intentar(format('SELECT telefono FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Juan'));
SELECT pg_temp.caso('02 Juan sí lee el nombre', 'ok',
  pg_temp.intentar(format('SELECT nombre FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Juan'));

-- ============================================================
-- 03. Vincular con roles repetidos: se guardan sin repetir
-- ============================================================
SELECT pg_temp.caso('03 Juan vincula a Marta con Belgrano', 'ok',
  pg_temp.vincular_persona('Marta', 'obra', 'Belgrano', '{arquitecto,referente,arquitecto}', 'Juan'));
SELECT pg_temp.caso('03 roles guardados sin repetir', 'arquitecto,referente',
  pg_temp.roles_abiertos('Marta', 'obra', 'Belgrano'));
SELECT pg_temp.caso('03 evento relacion_alta arquitecto', '1',
  pg_temp.eventos('obra', 'Belgrano', 'relacion_alta', 'Marta', 'arquitecto'));
SELECT pg_temp.caso('03 evento relacion_alta referente', '1',
  pg_temp.eventos('obra', 'Belgrano', 'relacion_alta', 'Marta', 'referente'));

-- ============================================================
-- 04. Un rol que el ente no declara
-- ============================================================
SELECT pg_temp.caso('04 rol inexistente para obra', 'CO014',
  pg_temp.vincular_persona('Marta', 'obra', 'ObraJuan2', '{capataz}', 'Juan'));

-- ============================================================
-- 05. Vincula quien es dueño de la persona; participar es trabajar
-- ============================================================
SELECT pg_temp.caso('05 Pedro no es dueño de Marta', 'CO016',
  pg_temp.vincular_persona('Marta', 'obra', 'Nunez', '{referente}', 'Pedro'));
SELECT pg_temp.caso('05 Pedro crea a Pepe', 'ok',
  pg_temp.crear_persona('Pepe', 'Pepe', NULL, NULL, 'Pedro'));
SELECT pg_temp.caso('05 Pedro (participante) vincula a Pepe con Belgrano', 'ok',
  pg_temp.vincular_persona('Pepe', 'obra', 'Belgrano', '{decisor}', 'Pedro'));

-- ============================================================
-- 06. Ver un registro no es trabajarlo
-- ============================================================
SELECT pg_temp.caso('06 Laura crea una persona suya', 'ok',
  pg_temp.crear_persona('LauraPersona', 'Persona de Laura', NULL, NULL, 'Laura'));
SELECT pg_temp.caso('06 Laura no trabaja Belgrano (solo la ve)', 'CO015',
  pg_temp.vincular_persona('LauraPersona', 'obra', 'Belgrano', '{referente}', 'Laura'));

-- ============================================================
-- 07. Quién ve a Marta
-- ============================================================
SELECT pg_temp.caso('07 Juan ve a Marta (dueño)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Juan'));
SELECT pg_temp.caso('07 Pedro ve a Marta (vía Belgrano, participante)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('07 Laura ve a Marta (jefa de Sur, Pedro participa)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Laura'));
SELECT pg_temp.caso('07 JN ve a Marta (jefe de Norte, equipo de Belgrano)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'JN'));
SELECT pg_temp.caso('07 A ve a Marta (admin)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'A'));
SELECT pg_temp.caso('07 Nico no ve a Marta', '0',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Nico'));
SELECT pg_temp.caso('07 Z no ve a Marta', '0',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Z'));

-- ============================================================
-- 08. "Ver contacto": teléfono y registro del acceso
-- ============================================================
SELECT pg_temp.caso('08 Pedro ve el contacto de Marta', '1155550000',
  pg_temp.consultar(format('SELECT telefono FROM contactos_ver_contacto(%L)', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('08 queda 1 acceso de Pedro a Marta', '1',
  (SELECT count(*)::text FROM contactos_accesos WHERE persona_id = pg_temp.id('Marta') AND usuario_id = pg_temp.id('Pedro')));
SELECT pg_temp.caso('08 Nico no puede ver el contacto', 'CO017',
  pg_temp.consultar(format('SELECT telefono FROM contactos_ver_contacto(%L)', pg_temp.id('Marta')), 'Nico'));
SELECT pg_temp.caso('08 Nico no deja acceso', '0',
  (SELECT count(*)::text FROM contactos_accesos WHERE persona_id = pg_temp.id('Marta') AND usuario_id = pg_temp.id('Nico')));

-- ============================================================
-- 09. Corrige el teléfono quien trabaja el registro donde está
-- ============================================================
SELECT pg_temp.caso('09 Pedro cambia el teléfono de Marta', 'ok',
  pg_temp.intentar(format('UPDATE contactos_personas SET telefono = %L WHERE id = %L', '11 6666-0000', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('09 queda la edición de teléfono', '1',
  (SELECT count(*)::text FROM contactos_ediciones
   WHERE persona_id = pg_temp.id('Marta') AND campo = 'telefono' AND anterior = '1155550000' AND nuevo = '1166660000'
     AND actor_id = pg_temp.id('Pedro')));
SELECT pg_temp.caso('09 Laura no trabaja Belgrano, no corrige a Marta', 'CO001',
  pg_temp.intentar(format('UPDATE contactos_personas SET nombre = %L WHERE id = %L', 'Otra', pg_temp.id('Marta')), 'Laura'));
SELECT pg_temp.caso('09 Nico no ve a Marta, su UPDATE no toca nada', 'ok',
  pg_temp.intentar(format('UPDATE contactos_personas SET notas = %L WHERE id = %L', 'x', pg_temp.id('Marta')), 'Nico'));
SELECT pg_temp.caso('09 las notas de Marta siguen NULL', NULL,
  (SELECT notas FROM contactos_personas WHERE id = pg_temp.id('Marta')));

-- ============================================================
-- 10. Historial: teléfono y email solo por "Ver contacto"
-- ============================================================
SELECT pg_temp.caso('10 Juan renombra a Marta', 'ok',
  pg_temp.intentar(format('UPDATE contactos_personas SET nombre = %L WHERE id = %L', 'Marta Gómez', pg_temp.id('Marta')), 'Juan'));
SELECT pg_temp.caso('10 Pedro ve la edición de nombre', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_ediciones WHERE persona_id = %L AND campo = ''nombre''', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('10 Pedro no ve la edición de teléfono por SELECT directo', '0',
  pg_temp.ve(format('SELECT 1 FROM contactos_ediciones WHERE persona_id = %L AND campo = ''telefono''', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('10 el historial sí trae el teléfono', '1',
  pg_temp.consultar(format(
    'SELECT count(*)::text FROM contactos_historial_contacto(%L) WHERE campo = ''telefono''', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('10 el historial suma un acceso más', '2',
  (SELECT count(*)::text FROM contactos_accesos WHERE persona_id = pg_temp.id('Marta') AND usuario_id = pg_temp.id('Pedro')));

-- ============================================================
-- 11. Cerrar un vínculo es la baja de todos sus roles; uno cerrado no se toca
-- ============================================================
SELECT pg_temp.caso('11 Laura no trabaja Belgrano, no cierra el vínculo', 'CO015',
  pg_temp.intentar(format(
    'UPDATE contactos_vinculos SET hasta = current_date WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L',
    pg_temp.id('Marta'), pg_temp.id('Belgrano')), 'Laura'));
SELECT pg_temp.caso('11 Pedro cierra el vínculo de Marta', 'ok',
  pg_temp.intentar(format(
    'UPDATE contactos_vinculos SET hasta = current_date WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L AND hasta IS NULL',
    pg_temp.id('Marta'), pg_temp.id('Belgrano')), 'Pedro'));
SELECT pg_temp.caso('11 2 eventos relacion_baja (arquitecto y referente)', '2',
  pg_temp.eventos('obra', 'Belgrano', 'relacion_baja', 'Marta'));
SELECT pg_temp.caso('11 un vínculo cerrado no se reabre', 'CO010',
  pg_temp.intentar(format(
    'UPDATE contactos_vinculos SET hasta = NULL WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L',
    pg_temp.id('Marta'), pg_temp.id('Belgrano')), 'Pedro'));
SELECT pg_temp.caso('11 ni se le cambian los roles', 'CO010',
  pg_temp.intentar(format(
    'UPDATE contactos_vinculos SET roles = ''{cliente}'' WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L',
    pg_temp.id('Marta'), pg_temp.id('Belgrano')), 'Pedro'));

-- ============================================================
-- 12. Volver a vincular es una fila nueva; dos abiertas no
-- ============================================================
SELECT pg_temp.caso('12 Juan vuelve a vincular a Marta con Belgrano', 'ok',
  pg_temp.vincular_persona('Marta', 'obra', 'Belgrano', '{arquitecto}', 'Juan'));
SELECT pg_temp.caso('12 roles de la fila nueva', 'arquitecto',
  pg_temp.roles_abiertos('Marta', 'obra', 'Belgrano'));
SELECT pg_temp.caso('12 dos vínculos abiertos para el mismo par, no', '23505',
  pg_temp.vincular_persona('Marta', 'obra', 'Belgrano', '{referente}', 'Juan'));

-- ============================================================
-- 13. Cambiar roles del vínculo abierto: solo altas y bajas de la diferencia
-- ============================================================
SELECT pg_temp.caso('13 Pedro suma decisor al vínculo abierto', 'ok',
  pg_temp.intentar(format(
    'UPDATE contactos_vinculos SET roles = ''{arquitecto,decisor}'' WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L AND hasta IS NULL',
    pg_temp.id('Marta'), pg_temp.id('Belgrano')), 'Pedro'));
SELECT pg_temp.caso('13 1 evento relacion_alta (decisor)', '1',
  pg_temp.eventos('obra', 'Belgrano', 'relacion_alta', 'Marta', 'decisor'));
SELECT pg_temp.caso('13 sin bajas nuevas (siguen las 2 de antes)', '2',
  pg_temp.eventos('obra', 'Belgrano', 'relacion_baja', 'Marta'));

-- ============================================================
-- 14. Desactivar un vínculo va por función (sql/129); solo la ve quien administra
-- ============================================================
-- Postgres exige, para un UPDATE sin RETURNING, que la fila resultante siga
-- pasando la policy SELECT de la tabla; desactivar por UPDATE directo saca al
-- que lo hace de su propia visibilidad y Postgres lo rechaza con 42501 antes
-- de tocar nada. `contactos_desactivar_vinculo` (sql/129) resuelve esto yendo
-- por una función DEFINER; las reglas siguen siendo las del trigger.
SELECT pg_temp.caso('14 Pedro desactiva el vínculo de Pepe', 'ok',
  pg_temp.intentar(format('SELECT contactos_desactivar_vinculo(%L)',
    pg_temp.vinculo_de('Pepe', 'obra', 'Belgrano')), 'Pedro'));
SELECT pg_temp.caso('14 evento relacion_baja de Pepe', '1',
  pg_temp.eventos('obra', 'Belgrano', 'relacion_baja', 'Pepe', 'decisor'));
SELECT pg_temp.caso('14 reactivarlo con UPDATE no toca filas', 'ok',
  pg_temp.intentar(format(
    'UPDATE contactos_vinculos SET activo = true WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L',
    pg_temp.id('Pepe'), pg_temp.id('Belgrano')), 'Pedro'));
SELECT pg_temp.caso('14 sigue desactivado', 'false',
  (SELECT activo::text FROM contactos_vinculos WHERE persona_id = pg_temp.id('Pepe') AND ente = 'obra' AND registro_id = pg_temp.id('Belgrano')));
SELECT pg_temp.caso('14 Pedro ya no ve ese vínculo', '0',
  pg_temp.ve(format('SELECT 1 FROM contactos_vinculos WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L',
    pg_temp.id('Pepe'), pg_temp.id('Belgrano')), 'Pedro'));
SELECT pg_temp.caso('14 A sí lo ve', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_vinculos WHERE persona_id = %L AND ente = ''obra'' AND registro_id = %L',
    pg_temp.id('Pepe'), pg_temp.id('Belgrano')), 'A'));
SELECT pg_temp.caso('14 Laura (solo ve Belgrano) no desactiva el vínculo de Marta', 'CO015',
  pg_temp.intentar(format('SELECT contactos_desactivar_vinculo(%L)',
    pg_temp.vinculo_abierto('Marta', 'obra', 'Belgrano')), 'Laura'));
SELECT pg_temp.caso('14 desactivar uno ya desactivado', 'CO018',
  pg_temp.intentar(format('SELECT contactos_desactivar_vinculo(%L)',
    pg_temp.vinculo_de('Pepe', 'obra', 'Belgrano')), 'Pedro'));

-- ============================================================
-- 15. Empresas: del equipo de quien la carga
-- ============================================================
SELECT pg_temp.caso('15 Juan crea la empresa Caputo', 'ok', pg_temp.crear_empresa('Caputo', 'Caputo', 'Juan'));
SELECT pg_temp.caso('15 Caputo queda en Norte', pg_temp.id('Norte')::text,
  (SELECT equipo_id::text FROM contactos_empresas WHERE id = pg_temp.id('Caputo')));
SELECT pg_temp.caso('15 Nico (Norte) vincula Caputo con Obra Nico', 'ok',
  pg_temp.vincular_empresa('Caputo', 'obra', 'ObraNico', '{constructora}', 'Nico'));
SELECT pg_temp.caso('15 Pedro (Sur) no vincula Caputo con Núñez', 'CO016',
  pg_temp.vincular_empresa('Caputo', 'obra', 'Nunez', '{constructora}', 'Pedro'));

-- ============================================================
-- 16. Desactivar una empresa: el jefe de su equipo, o el admin
-- ============================================================
SELECT pg_temp.caso('16 Juan (no es el jefe) no desactiva Caputo', 'CO007',
  pg_temp.intentar(format('SELECT contactos_desactivar_empresa(%L)', pg_temp.id('Caputo')), 'Juan'));
SELECT pg_temp.caso('16 JN (jefe de Norte) sí la desactiva', 'ok',
  pg_temp.intentar(format('SELECT contactos_desactivar_empresa(%L)', pg_temp.id('Caputo')), 'JN'));
SELECT pg_temp.caso('16 A crea una empresa sin equipo', 'ok', pg_temp.crear_empresa('AdminCo', 'AdminCo', 'A'));
SELECT pg_temp.caso('16 A la desactiva', 'ok',
  pg_temp.intentar(format('SELECT contactos_desactivar_empresa(%L)', pg_temp.id('AdminCo')), 'A'));

-- ============================================================
-- 17. Persona ↔ empresa: la maneja el dueño de la persona, con una empresa que ve
-- ============================================================
SELECT pg_temp.caso('17 Juan crea la empresa Estudio G', 'ok', pg_temp.crear_empresa('EstudioG', 'Estudio G', 'Juan'));
SELECT pg_temp.caso('17 Juan suma Estudio G a Marta', 'ok',
  pg_temp.intentar(format(
    'INSERT INTO contactos_persona_empresa (persona_id, empresa_id, cargo) VALUES (%L, %L, ''Arquitecta'')',
    pg_temp.id('Marta'), pg_temp.id('EstudioG')), 'Juan'));
SELECT pg_temp.caso('17 Pedro no es dueño de Marta', 'CO012',
  pg_temp.intentar(format(
    'INSERT INTO contactos_persona_empresa (persona_id, empresa_id) VALUES (%L, %L)',
    pg_temp.id('Marta'), pg_temp.id('EstudioG')), 'Pedro'));
SELECT pg_temp.caso('17 Pedro crea la empresa de Sur', 'ok', pg_temp.crear_empresa('EmpresaSur', 'Empresa de Sur', 'Pedro'));
SELECT pg_temp.caso('17 Juan no ve la empresa de Sur', 'CO013',
  pg_temp.intentar(format(
    'INSERT INTO contactos_persona_empresa (persona_id, empresa_id) VALUES (%L, %L)',
    pg_temp.id('Marta'), pg_temp.id('EmpresaSur')), 'Juan'));
SELECT pg_temp.caso('17 Pedro no maneja la empresa de Marta (no es su dueño)', 'CO012',
  pg_temp.intentar(format('SELECT contactos_desactivar_persona_empresa(%L)', (
    SELECT id FROM contactos_persona_empresa WHERE persona_id = pg_temp.id('Marta') AND empresa_id = pg_temp.id('EstudioG')
  )), 'Pedro'));
SELECT pg_temp.caso('17 Juan (dueño de Marta) desactiva la relación', 'ok',
  pg_temp.intentar(format('SELECT contactos_desactivar_persona_empresa(%L)', (
    SELECT id FROM contactos_persona_empresa WHERE persona_id = pg_temp.id('Marta') AND empresa_id = pg_temp.id('EstudioG')
  )), 'Juan'));
SELECT pg_temp.caso('17 desactivar de nuevo', 'CO018',
  pg_temp.intentar(format('SELECT contactos_desactivar_persona_empresa(%L)', (
    SELECT id FROM contactos_persona_empresa WHERE persona_id = pg_temp.id('Marta') AND empresa_id = pg_temp.id('EstudioG')
  )), 'Juan'));

-- ============================================================
-- 18. Transferir una persona: su dueño o el admin, a alguien que ve Contactos
-- ============================================================
SELECT pg_temp.caso('18 Pedro no es dueño de Marta', 'CO002',
  pg_temp.intentar(format('SELECT contactos_transferir_persona(%L, %L)', pg_temp.id('Marta'), pg_temp.id('Pedro')), 'Pedro'));
SELECT pg_temp.caso('18 Z no ve Contactos', 'CO005',
  pg_temp.intentar(format('SELECT contactos_transferir_persona(%L, %L)', pg_temp.id('Marta'), pg_temp.id('Z')), 'Juan'));
SELECT pg_temp.caso('18 Juan transfiere a Marta a Nico', 'ok',
  pg_temp.intentar(format('SELECT contactos_transferir_persona(%L, %L)', pg_temp.id('Marta'), pg_temp.id('Nico')), 'Juan'));
SELECT pg_temp.caso('18 evento de transferencia', 'ok', (
  SELECT CASE WHEN detalle->>'de' = pg_temp.id('Juan')::text AND detalle->>'a' = pg_temp.id('Nico')::text
    THEN 'ok' ELSE detalle::text END
  FROM eventos WHERE ente = 'persona' AND registro_id = pg_temp.id('Marta') AND evento = 'transferencia'));
SELECT pg_temp.caso('18 Juan sigue viendo a Marta (vía Belgrano)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Juan'));

-- ============================================================
-- 19. Desactivar una persona no cierra sus vínculos
-- ============================================================
SELECT pg_temp.caso('19 Nico (nuevo dueño) desactiva a Marta', 'ok',
  pg_temp.intentar(format('SELECT contactos_desactivar_persona(%L)', pg_temp.id('Marta')), 'Nico'));
SELECT pg_temp.caso('19 el vínculo con Belgrano sigue activo', 'true',
  (SELECT activo::text FROM contactos_vinculos WHERE persona_id = pg_temp.id('Marta') AND ente = 'obra'
     AND registro_id = pg_temp.id('Belgrano') AND hasta IS NULL));
SELECT pg_temp.caso('19 Pedro sigue viendo a Marta (aunque desactivada)', '1',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('19 una persona desactivada no se vincula', 'CO009',
  pg_temp.vincular_persona('Marta', 'obra', 'ObraJuan2', '{referente}', 'Juan'));
SELECT pg_temp.caso('19 A reactiva a Marta', 'ok',
  pg_temp.intentar(format('UPDATE contactos_personas SET activo = true WHERE id = %L', pg_temp.id('Marta')), 'A'));

-- ============================================================
-- 20. Un evento de relación lo ve quien ve algún vínculo del par
-- ============================================================
SELECT pg_temp.caso('20 Nico no ve Belgrano, 0 eventos de relación', '0',
  pg_temp.ve(format(
    $q$SELECT 1 FROM eventos WHERE ente = 'obra' AND registro_id = %L AND evento IN ('relacion_alta','relacion_baja')$q$,
    pg_temp.id('Belgrano')), 'Nico'));
SELECT pg_temp.caso('20 Laura ve los de Marta, no los de Pepe (su vínculo está inactivo)', '6',
  pg_temp.ve(format(
    $q$SELECT 1 FROM eventos WHERE ente = 'obra' AND registro_id = %L AND evento IN ('relacion_alta','relacion_baja')$q$,
    pg_temp.id('Belgrano')), 'Laura'));

-- ============================================================
-- 21. Genéricas: buscar y etiquetar respetan lo que cada quien ve
-- ============================================================
SELECT pg_temp.caso('21 Pedro encuentra a Marta buscando "mar"', '1',
  pg_temp.ve(format($q$SELECT 1 FROM buscar_registros('contactos', 'mar') b WHERE b.registro_id = %L$q$,
    pg_temp.id('Marta')), 'Pedro'));
SELECT pg_temp.caso('21 Z no encuentra nada de Contactos', '0',
  pg_temp.ve($q$SELECT 1 FROM buscar_registros('contactos', 'mar')$q$, 'Z'));
SELECT pg_temp.caso('21 etiqueta_registro de Marta es NULL para Z', NULL,
  pg_temp.consultar(format('SELECT etiqueta_registro(''persona'', %L)', pg_temp.id('Marta')), 'Z'));

-- ============================================================
-- 22. Desactivar la obra saca de la vista lo que solo llegaba por ella
-- ============================================================
SELECT pg_temp.caso('22 Juan desactiva Belgrano', 'ok',
  pg_temp.intentar(format('SELECT obras_desactivar(%L)', pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('22 Laura deja de ver a Marta', '0',
  pg_temp.ve(format('SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Laura'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
