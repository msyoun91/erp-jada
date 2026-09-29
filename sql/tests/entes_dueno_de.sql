-- Verificación de sql/148: `entes.dueno`, la rama `tareas` de
-- `puede_abrir_registro`, `etiqueta_registro_de` y `relacionados_de_registro`
-- con su `_de`. NO es una migración: todo corre dentro de una transacción que
-- termina en ROLLBACK.
--
-- Mundo: Juan (Norte) y Pedro (Sur), vendedores con Obras, Contactos y
-- Tareas. Belgrano es obra de Juan, con Marta (arquitecto, referente) y
-- Estudio G (arquitecto) vinculados, y Pepe con un vínculo cerrado. H es un
-- hilo de Juan. Pedro no ve nada de eso.

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

-- Devuelve el único valor de p_sql como p_como ('ok' si no devuelve nada), o el SQLSTATE.
CREATE FUNCTION pg_temp.como(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  IF p_sql ~* '^\s*select' THEN
    EXECUTE p_sql INTO v_out;
  ELSE
    EXECUTE p_sql;
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN coalesce(v_out, 'ok');
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  RETURN SQLSTATE;
END;
$f$;

-- Las relaciones de una lista, 'ente:nombre:rol' ordenadas; '' si no hay.
CREATE FUNCTION pg_temp.rel(p_sql text) RETURNS text LANGUAGE sql AS $f$
  SELECT 'SELECT coalesce(string_agg(x.ente || '':'' || i.nombre || '':'' || x.rol, '','' ORDER BY i.nombre, x.rol), '''') '
      || 'FROM (' || p_sql || ') x JOIN ids i ON i.id = x.registro_id';
$f$;

CREATE FUNCTION pg_temp.ejecutar(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_out text;
BEGIN
  EXECUTE p_sql INTO v_out;
  RETURN v_out;
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','Pedro','Norte','Sur','Belgrano','Marta','Pepe','EstudioG','H']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','obras_ver','obras_crear','tareas_ver','obras_aprobar','contactos_aprobar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test148.local', jsonb_build_object('nombre', 'test148 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro');

INSERT INTO equipos (id, nombre)
SELECT id, 'test148 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n) FROM (VALUES ('Norte','Juan'),('Sur','Pedro')) AS m (e, n);

-- Con `_aprobar`, lo que cargan no se congela (el congelado es de `duplicados.sql`).
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM unnest(ARRAY['Juan','Pedro']) AS u,
     unnest(ARRAY['contactos_ver','obras_ver','obras_crear','tareas_ver','obras_aprobar','contactos_aprobar']) AS s;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: Belgrano', 'ok', pg_temp.como(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Belgrano', 'Calle 1', 'otro', 'casa')$s$,
  pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('00 montaje: personas', 'ok', pg_temp.como(format(
  $s$INSERT INTO contactos_personas (id, nombre) VALUES (%L, 'Marta'), (%L, 'Pepe')$s$,
  pg_temp.id('Marta'), pg_temp.id('Pepe')), 'Juan'));
SELECT pg_temp.caso('00 montaje: empresa', 'ok', pg_temp.como(format(
  $s$INSERT INTO contactos_empresas (id, nombre) VALUES (%L, 'Estudio G')$s$, pg_temp.id('EstudioG')), 'Juan'));
SELECT pg_temp.caso('00 montaje: vínculos de personas', 'ok', pg_temp.como(format(
  $s$INSERT INTO contactos_vinculos (persona_id, ente, registro_id, roles) VALUES (%1$L, 'obra', %3$L, '{arquitecto,referente}'), (%2$L, 'obra', %3$L, '{referente}')$s$,
  pg_temp.id('Marta'), pg_temp.id('Pepe'), pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('00 montaje: vínculo de la empresa', 'ok', pg_temp.como(format(
  $s$INSERT INTO contactos_vinculos (empresa_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{arquitecto}')$s$,
  pg_temp.id('EstudioG'), pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('00 montaje: se cierra el de Pepe', 'ok', pg_temp.como(format(
  'UPDATE contactos_vinculos SET hasta = current_date WHERE persona_id = %L', pg_temp.id('Pepe')), 'Juan'));
SELECT pg_temp.caso('00 montaje: hilo H', 'ok', pg_temp.como(format(
  $s$INSERT INTO tareas_hilos (id, titulo) VALUES (%L, 'Zqx148 hilo')$s$, pg_temp.id('H')), 'Juan'));

-- ============================================================
-- 01. entes.dueno
-- ============================================================
SELECT pg_temp.caso('01 la columna del dueño de cada ente',
  'empresa:creado_por,hilo:responsable_id,obra:responsable_id,persona:responsable_id,tarea:',
  (SELECT string_agg(codigo || ':' || coalesce(dueno, ''), ',' ORDER BY codigo) FROM entes
   WHERE codigo IN ('hilo','tarea','obra','persona','empresa')));

-- ============================================================
-- 02. etiqueta_registro_de: el nombre si ese usuario lo ve
-- ============================================================
SELECT pg_temp.caso('02 Juan ve Belgrano', 'Belgrano',
  etiqueta_registro_de('obra', pg_temp.id('Belgrano'), pg_temp.id('Juan')));
SELECT pg_temp.caso('02 Pedro no ve Belgrano', NULL,
  etiqueta_registro_de('obra', pg_temp.id('Belgrano'), pg_temp.id('Pedro')));
SELECT pg_temp.caso('02 Juan ve a Marta', 'Marta',
  etiqueta_registro_de('persona', pg_temp.id('Marta'), pg_temp.id('Juan')));
SELECT pg_temp.caso('02 Pedro no ve a Marta', NULL,
  etiqueta_registro_de('persona', pg_temp.id('Marta'), pg_temp.id('Pedro')));
SELECT pg_temp.caso('02 un ente que no existe', NULL,
  etiqueta_registro_de('nada', pg_temp.id('Belgrano'), pg_temp.id('Juan')));

-- ============================================================
-- 03. La rama tareas de puede_abrir_registro
-- ============================================================
SELECT pg_temp.caso('03 Juan ve su hilo', 'Zqx148 hilo',
  etiqueta_registro_de('hilo', pg_temp.id('H'), pg_temp.id('Juan')));
SELECT pg_temp.caso('03 Pedro no ve el hilo de Juan', NULL,
  etiqueta_registro_de('hilo', pg_temp.id('H'), pg_temp.id('Pedro')));
SELECT pg_temp.caso('03 igual que etiqueta_registro como Juan', 'Zqx148 hilo',
  pg_temp.como(format('SELECT etiqueta_registro(''hilo'', %L)', pg_temp.id('H')), 'Juan'));

-- ============================================================
-- 04. relacionados_de_registro_de: vínculos abiertos, persona o empresa
-- ============================================================
SELECT pg_temp.caso('04 Juan: Estudio G y Marta; Pepe cerrado no',
  'empresa:EstudioG:arquitecto,persona:Marta:arquitecto,persona:Marta:referente',
  pg_temp.como(pg_temp.rel(format('SELECT * FROM relacionados_de_registro(''obra'', %L)',
    pg_temp.id('Belgrano'))), 'Juan'));
SELECT pg_temp.caso('04 la _de de Juan dice lo mismo',
  'empresa:EstudioG:arquitecto,persona:Marta:arquitecto,persona:Marta:referente',
  pg_temp.ejecutar(pg_temp.rel(format('SELECT * FROM relacionados_de_registro_de(''obra'', %L, %L)',
    pg_temp.id('Belgrano'), pg_temp.id('Juan')))));
SELECT pg_temp.caso('04 Pedro no ve relaciones de Belgrano', '',
  pg_temp.como(pg_temp.rel(format('SELECT * FROM relacionados_de_registro(''obra'', %L)',
    pg_temp.id('Belgrano'))), 'Pedro'));
SELECT pg_temp.caso('04 ni por la _de', '',
  pg_temp.ejecutar(pg_temp.rel(format('SELECT * FROM relacionados_de_registro_de(''obra'', %L, %L)',
    pg_temp.id('Belgrano'), pg_temp.id('Pedro')))));
SELECT pg_temp.caso('04 un registro sin vínculos', '',
  pg_temp.ejecutar(pg_temp.rel(format('SELECT * FROM relacionados_de_registro_de(''hilo'', %L, %L)',
    pg_temp.id('H'), pg_temp.id('Juan')))));

-- ============================================================
-- 05. Las _de no se llaman desde el cliente
-- ============================================================
SELECT pg_temp.caso('05 etiqueta_registro_de sin EXECUTE', '42501',
  pg_temp.como(format('SELECT etiqueta_registro_de(''obra'', %L, %L)',
    pg_temp.id('Belgrano'), pg_temp.id('Pedro')), 'Pedro'));
SELECT pg_temp.caso('05 relacionados_de_registro_de sin EXECUTE', '42501',
  pg_temp.como(format('SELECT count(*) FROM relacionados_de_registro_de(''obra'', %L, %L)',
    pg_temp.id('Belgrano'), pg_temp.id('Juan')), 'Pedro'));

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
