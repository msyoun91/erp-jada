-- Verificación de sql/128: `contactos_vinculables`, `contactos_crear_y_vincular`
-- y `obras_alta` (la obra y su "¿Quién?"). NO es una migración: todo corre
-- dentro de una transacción que termina en ROLLBACK. Correr después de
-- aplicar sql/125 a sql/128.
--
-- Mundo: equipo Norte (Juan, con obras_crear) y equipo Sur (Pedro, con
-- obras_crear; Laura jefa delegadora con obras_equipo, sin obras_crear — la
-- usa el caso 10). Marta es persona de Juan, con una empresa propia (Estudio
-- J) abierta. Belgrano es una obra de Juan, con Pedro participante. Los
-- nombres de obra y persona llevan el prefijo `Zqx128` para no cruzarse con
-- datos reales al buscarlos por nombre; todo lo demás va filtrado por los ids
-- del montaje.

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

-- Como `intentar`, pero para funciones que devuelven un uuid: si sale bien,
-- lo guarda en `ids` con el nombre dado (o lo descarta, si es NULL).
CREATE FUNCTION pg_temp.alta(p_nombre_ids text, p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql INTO v_id;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF p_nombre_ids IS NOT NULL THEN
    INSERT INTO ids (nombre, id) VALUES (p_nombre_ids, v_id);
  END IF;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
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

CREATE FUNCTION pg_temp.roles_abiertos(p_persona text, p_ente text, p_registro text) RETURNS text LANGUAGE sql AS $f$
  SELECT array_to_string(roles, ',') FROM contactos_vinculos
  WHERE persona_id = pg_temp.id(p_persona) AND ente = p_ente AND registro_id = pg_temp.id(p_registro)
    AND activo AND hasta IS NULL;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','Pedro','Laura','Norte','Sur',
                  'Marta','PersonaDePedro','EstudioJ','MarmolNorte','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','obras_ver','obras_crear','obras_equipo','usuarios_delegar','usuarios_equipo',
   'tareas_ver','tareas_equipo');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test128.local', jsonb_build_object('nombre', 'test128 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro','Laura');

INSERT INTO equipos (id, nombre)
SELECT id, 'test128 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n) FROM (VALUES ('Norte','Juan'),('Sur','Pedro'),('Sur','Laura')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('Laura','tareas_ver'), ('Laura','tareas_equipo'), ('Laura','usuarios_equipo'), ('Laura','usuarios_delegar'),
  ('Laura','obras_ver'), ('Laura','obras_equipo'), ('Laura','contactos_ver')
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

SELECT pg_temp.caso('00 montaje: Marta, de Juan', 'ok', pg_temp.intentar(format(
  'INSERT INTO contactos_personas (id, nombre) VALUES (%L, %L)', pg_temp.id('Marta'), 'Zqx128 Marta'), 'Juan'));
SELECT pg_temp.caso('00 montaje: Estudio J, de Juan (Norte)', 'ok', pg_temp.intentar(format(
  'INSERT INTO contactos_empresas (id, nombre) VALUES (%L, %L)', pg_temp.id('EstudioJ'), 'Zqx128 Estudio J'), 'Juan'));
SELECT pg_temp.caso('00 montaje: Marta trabaja en Estudio J', 'ok', pg_temp.intentar(format(
  'INSERT INTO contactos_persona_empresa (persona_id, empresa_id, cargo) VALUES (%L, %L, %L)',
  pg_temp.id('Marta'), pg_temp.id('EstudioJ'), 'Arquitecta'), 'Juan'));
SELECT pg_temp.caso('00 montaje: Marmol Norte, de Juan (Norte)', 'ok', pg_temp.intentar(format(
  'INSERT INTO contactos_empresas (id, nombre) VALUES (%L, %L)', pg_temp.id('MarmolNorte'), 'Zqx128 Marmol Norte'), 'Juan'));
SELECT pg_temp.caso('00 montaje: persona de Pedro', 'ok', pg_temp.intentar(format(
  'INSERT INTO contactos_personas (id, nombre) VALUES (%L, %L)', pg_temp.id('PersonaDePedro'), 'Zqx128 Persona de Pedro'), 'Pedro'));
SELECT pg_temp.caso('00 montaje: Belgrano, de Juan', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Zqx128 Belgrano', 'Calle 1', 'otro', 'casa')$s$,
  pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('00 montaje: Pedro participa de Belgrano', 'ok', pg_temp.intentar(format(
  'INSERT INTO obras_participantes (obra_id, usuario_id) VALUES (%L, %L)',
  pg_temp.id('Belgrano'), pg_temp.id('Pedro')), 'Juan'));

-- ============================================================
-- 01. obras_alta con "¿Quién?" existente (una persona)
-- ============================================================
SELECT pg_temp.caso('01 Juan da de alta Torre, referida por Marta', 'ok', pg_temp.alta('Torre', format(
  $s$SELECT obras_alta('Zqx128 Torre', 'Calle 1', 'referente', 'edificio_residencial', p_quien_persona => %L)$s$,
  pg_temp.id('Marta')), 'Juan'));
SELECT pg_temp.caso('01 responsable es Juan', pg_temp.id('Juan')::text,
  (SELECT responsable_id::text FROM obras WHERE id = pg_temp.id('Torre')));
SELECT pg_temp.caso('01 vínculo de Marta con Torre', 'referente',
  pg_temp.roles_abiertos('Marta', 'obra', 'Torre'));
SELECT pg_temp.caso('01 evento alta de Torre', '1',
  (SELECT count(*)::text FROM eventos WHERE ente = 'obra' AND registro_id = pg_temp.id('Torre') AND evento = 'alta'));
SELECT pg_temp.caso('01 evento relacion_alta (referente, Marta, actor Juan)', '1', (
  SELECT count(*)::text FROM eventos
  WHERE ente = 'obra' AND registro_id = pg_temp.id('Torre') AND evento = 'relacion_alta'
    AND detalle->>'ente' = 'persona' AND (detalle->>'registro_id')::uuid = pg_temp.id('Marta')
    AND detalle->>'rol' = 'referente' AND actor_id = pg_temp.id('Juan')));

-- ============================================================
-- 02. "¿Quién?" solo vale con origen referente
-- ============================================================
SELECT pg_temp.caso('02 origen cartel con quien', 'OB017', pg_temp.alta(NULL, format(
  $s$SELECT obras_alta('Zqx128 Torre2', 'Calle 1', 'cartel', 'edificio_residencial', p_quien_persona => %L)$s$,
  pg_temp.id('Marta')), 'Juan'));
SELECT pg_temp.caso('02 no quedó ninguna obra', '0',
  (SELECT count(*)::text FROM obras WHERE nombre = 'Zqx128 Torre2'));

-- ============================================================
-- 03. "¿Quién?" es uno solo
-- ============================================================
SELECT pg_temp.caso('03 persona y empresa a la vez', 'OB017', pg_temp.alta(NULL, format(
  $s$SELECT obras_alta('Zqx128 Torre3', 'Calle 1', 'referente', 'edificio_residencial',
     p_quien_persona => %L, p_quien_empresa => %L)$s$,
  pg_temp.id('Marta'), pg_temp.id('EstudioJ')), 'Juan'));
SELECT pg_temp.caso('03 no quedó ninguna obra', '0',
  (SELECT count(*)::text FROM obras WHERE nombre = 'Zqx128 Torre3'));

-- ============================================================
-- 04. "¿Quién?" nuevo: crea la persona y la vincula
-- ============================================================
SELECT pg_temp.caso('04 Juan da de alta con un referente nuevo (Rosa)', 'ok', pg_temp.alta('Torre4', format(
  $s$SELECT obras_alta('Zqx128 Torre4', 'Calle 1', 'referente', 'edificio_residencial',
     p_quien_nuevo_tipo => 'persona', p_quien_nuevo_nombre => 'Zqx128 Rosa', p_quien_nuevo_telefono => '(011) 4444-1234')$s$),
  'Juan'));
SELECT pg_temp.caso('04 Rosa queda de Juan, teléfono normalizado', pg_temp.id('Juan')::text || ':01144441234', (
  SELECT responsable_id::text || ':' || telefono FROM contactos_personas WHERE nombre = 'Zqx128 Rosa'));
SELECT pg_temp.caso('04 Rosa vinculada como referente', 'referente', (
  SELECT array_to_string(v.roles, ',') FROM contactos_vinculos v
  JOIN contactos_personas p ON p.id = v.persona_id
  WHERE p.nombre = 'Zqx128 Rosa' AND v.ente = 'obra' AND v.registro_id = pg_temp.id('Torre4') AND v.activo AND v.hasta IS NULL));

-- ============================================================
-- 05. "¿Quién?" tiene que ser propio; si falla, no queda la obra
-- ============================================================
SELECT pg_temp.caso('05 Juan no es dueño de la persona de Pedro', 'CO016', pg_temp.alta(NULL, format(
  $s$SELECT obras_alta('Zqx128 Torre5', 'Calle 1', 'referente', 'edificio_residencial', p_quien_persona => %L)$s$,
  pg_temp.id('PersonaDePedro')), 'Juan'));
SELECT pg_temp.caso('05 no quedó ninguna obra', '0',
  (SELECT count(*)::text FROM obras WHERE nombre = 'Zqx128 Torre5'));

-- ============================================================
-- 06. contactos_crear_y_vincular: persona nueva con empresa nueva
-- ============================================================
SELECT pg_temp.caso('06 Pedro (participante) crea y vincula a Capataz Uno', 'ok', pg_temp.alta('CapatazUno', format(
  $s$SELECT contactos_crear_y_vincular('obra', %L, '{director_obra}', 'persona', 'Zqx128 Capataz Uno',
     p_empresa_nombre => 'Zqx128 Constructora X', p_cargo => 'Capataz')$s$,
  pg_temp.id('Belgrano')), 'Pedro'));
SELECT pg_temp.caso('06 Capataz Uno es de Pedro', pg_temp.id('Pedro')::text,
  (SELECT responsable_id::text FROM contactos_personas WHERE id = pg_temp.id('CapatazUno')));
SELECT pg_temp.caso('06 Constructora X, equipo Sur, creada por Pedro', pg_temp.id('Sur')::text || ':' || pg_temp.id('Pedro')::text, (
  SELECT e.equipo_id::text || ':' || e.creado_por::text
  FROM contactos_empresas e
  JOIN contactos_persona_empresa pe ON pe.empresa_id = e.id
  WHERE pe.persona_id = pg_temp.id('CapatazUno')));
SELECT pg_temp.caso('06 cargo Capataz', 'Capataz', (
  SELECT cargo FROM contactos_persona_empresa WHERE persona_id = pg_temp.id('CapatazUno')));
SELECT pg_temp.caso('06 vínculo con Belgrano', 'director_obra',
  pg_temp.roles_abiertos('CapatazUno', 'obra', 'Belgrano'));

-- ============================================================
-- 07. Ver un registro no es trabajarlo, tampoco acá
-- ============================================================
SELECT pg_temp.caso('07 Laura (solo ve Belgrano) no crea ni vincula', 'CO015', pg_temp.alta(NULL, format(
  $s$SELECT contactos_crear_y_vincular('obra', %L, '{director_obra}', 'persona', 'Zqx128 Capataz Dos')$s$,
  pg_temp.id('Belgrano')), 'Laura'));
SELECT pg_temp.caso('07 no quedó Capataz Dos', '0',
  (SELECT count(*)::text FROM contactos_personas WHERE nombre = 'Zqx128 Capataz Dos'));

-- ============================================================
-- 08. Combinaciones inválidas de contactos_crear_y_vincular
-- ============================================================
SELECT pg_temp.caso('08 una empresa no lleva cargo', 'CO019', pg_temp.alta(NULL, format(
  $s$SELECT contactos_crear_y_vincular('obra', %L, '{director_obra}', 'empresa', 'Zqx128 Empresa Cargo', p_cargo => 'Algo')$s$,
  pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('08 tipo inexistente', 'CO019', pg_temp.alta(NULL, format(
  $s$SELECT contactos_crear_y_vincular('obra', %L, '{director_obra}', 'otro', 'Zqx128 Nombre')$s$,
  pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('08 empresa elegida y nueva a la vez', 'CO019', pg_temp.alta(NULL, format(
  $s$SELECT contactos_crear_y_vincular('obra', %L, '{director_obra}', 'persona', 'Zqx128 Persona Y',
     p_empresa_id => %L, p_empresa_nombre => 'Zqx128 Otra')$s$,
  pg_temp.id('Belgrano'), pg_temp.id('EstudioJ')), 'Juan'));

-- ============================================================
-- 09. contactos_vinculables: lo propio, y la empresa actual como detalle
-- ============================================================
SELECT pg_temp.caso('09 Juan encuentra a Marta, con Estudio J de detalle', '1', pg_temp.ve(format(
  $s$SELECT 1 FROM contactos_vinculables('ma') v WHERE v.tipo = 'persona' AND v.id = %L AND v.detalle = 'Zqx128 Estudio J'$s$,
  pg_temp.id('Marta')), 'Juan'));
SELECT pg_temp.caso('09 Juan encuentra Marmol Norte (empresa de su equipo)', '1', pg_temp.ve(format(
  $s$SELECT 1 FROM contactos_vinculables('ma') v WHERE v.tipo = 'empresa' AND v.id = %L$s$,
  pg_temp.id('MarmolNorte')), 'Juan'));
SELECT pg_temp.caso('09 Pedro no encuentra a Marta', '0', pg_temp.ve(format(
  $s$SELECT 1 FROM contactos_vinculables('ma') v WHERE v.id = %L$s$,
  pg_temp.id('Marta')), 'Pedro'));

-- ============================================================
-- 10. Sin obras_crear, no hay alta
-- ============================================================
SELECT pg_temp.caso('10 Laura no tiene obras_crear', '42501', pg_temp.alta(NULL,
  $s$SELECT obras_alta('Zqx128 Torre10', 'Calle 1', 'referente', 'edificio_residencial')$s$, 'Laura'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
