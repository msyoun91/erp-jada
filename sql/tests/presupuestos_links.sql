-- Verificación de sql/200: el link de cada presupuesto y el estado de su copia. NO es una migración: todo corre dentro de
-- una transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Laura responsable de Belgrano (ve, no arma), Juan vendedor que participa, Ana vendedora sin la obra, G gerencia.
-- P1 y P2 en Belgrano, cada uno con un renglón a mano de $1.000. Lo creado lleva Zqx200.

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
  RETURN coalesce(nullif(v_out, ''), 'ok');
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

-- Como quien corre el test (el servidor): el SQLSTATE si falla.
CREATE FUNCTION pg_temp.probar(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
BEGIN
  EXECUTE p_sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END;
$f$;

-- Un presupuesto con su v1, una sección y un renglón a mano de 1000.
CREATE FUNCTION pg_temp.alta(p_nombre text, p_obra text, p_como text DEFAULT 'Juan') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_p uuid := pg_temp.consultar(format($s$SELECT presupuestos_alta(%L, %L, 'ARS', 21)::text$s$,
    pg_temp.id(p_obra), 'Zqx200 ' || p_nombre), p_como)::uuid;
  v_v uuid;
BEGIN
  SELECT id INTO v_v FROM presupuestos_versiones WHERE presupuesto_id = v_p;
  INSERT INTO ids VALUES (p_nombre, v_p), (p_nombre || 'v1', v_v);
  PERFORM pg_temp.consultar(format(
    $s$INSERT INTO presupuestos_renglones (version_id, seccion_id, tipo, descripcion, precio)
       SELECT %L, s.id, 'mano', 'Flete', 1000 FROM presupuestos_secciones s WHERE s.version_id = %L RETURNING id::text$s$,
    v_v, v_v), p_como);
END;
$f$;

CREATE FUNCTION pg_temp.copiar(p_nombre text, p_desde text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO ids VALUES (p_nombre, pg_temp.consultar(format('SELECT presupuestos_version_copiar(%L)::text',
    pg_temp.id(p_desde)), 'Juan')::uuid);
$f$;

CREATE FUNCTION pg_temp.publicar(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_version_publicar(%L)::text', pg_temp.id(p_version)), 'Juan');
$f$;

CREATE FUNCTION pg_temp.llamar(p_funcion text, p_p text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT %I(%L)::text', p_funcion, pg_temp.id(p_p)), p_como);
$f$;

CREATE FUNCTION pg_temp.llave(p_p text, p_copiar boolean, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_link_llave(%L, %L)', pg_temp.id(p_p), p_copiar), p_como);
$f$;

CREATE FUNCTION pg_temp.vigente(p_p text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT l.id FROM presupuestos_links l WHERE l.presupuesto_id = pg_temp.id(p_p) AND l.activo;
$f$;

-- El link vigente: revisión/revisión copiada/versiones a la vista. Sin copiar todavía, solo la revisión.
CREATE FUNCTION pg_temp.link(p_p text) RETURNS text LANGUAGE sql AS $f$
  SELECT concat_ws('/', l.revision, l.copia_revision, l.copia_versiones)
  FROM presupuestos_links l WHERE l.id = pg_temp.vigente(p_p);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','Laura','Ana','G','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo = 'presupuestos' OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test200.local', jsonb_build_object('nombre', 'test200 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Laura','Ana','G');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Laura','contactos_ver'), ('Laura','obras_ver'), ('Laura','presupuestos_ver'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por) VALUES
  (pg_temp.id('Belgrano'), 'Zqx200 Torre Belgrano', 'Zqx200 Calle 1', 'llamado', 'edificio_residencial',
   pg_temp.id('Laura'), pg_temp.id('Laura'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Juan'), pg_temp.id('Laura'));

SELECT pg_temp.caso('00 gerencia configura', 'ok', pg_temp.consultar($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, '[]')$s$, 'G'));
SELECT pg_temp.alta('P1', 'Belgrano');
SELECT pg_temp.alta('P2', 'Belgrano');

-- ============================================================
-- 01. En borrador no hay link
-- ============================================================
SELECT pg_temp.caso('01 sin link', '0', (SELECT count(*)::text FROM presupuestos_links WHERE presupuesto_id = pg_temp.id('P1')));
SELECT pg_temp.caso('01 pedir la llave sin link', 'PR029', pg_temp.llave('P1', true, 'Juan'));
SELECT pg_temp.caso('01 anular sin link', 'PR029', pg_temp.llamar('presupuestos_link_anular', 'P1', 'Juan'));
SELECT pg_temp.caso('01 el nombre en borrador no lo crea', 'ok/0', pg_temp.consultar(format(
  $s$UPDATE presupuestos SET nombre = 'Zqx200 Etapa 1' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('P1')), 'Juan')
  || '/' || (SELECT count(*) FROM presupuestos_links WHERE presupuesto_id = pg_temp.id('P1')));

-- ============================================================
-- 02. Publicar la primera versión lo crea
-- ============================================================
SELECT pg_temp.caso('02 publicar', 'ok', pg_temp.publicar('P1v1'));
SELECT pg_temp.caso('02 un link, sin copiar', '1/1', (SELECT count(*) FROM presupuestos_links
  WHERE presupuesto_id = pg_temp.id('P1')) || '/' || pg_temp.link('P1'));
SELECT pg_temp.caso('02 128 bits en hexadecimal, de quien publicó', 'true/Juan', (
  SELECT (l.llave ~ '^[0-9a-f]{32}$')::text || '/' || (SELECT nombre FROM ids WHERE id = l.creado_por)
  FROM presupuestos_links l WHERE l.presupuesto_id = pg_temp.id('P1')));
SELECT pg_temp.caso('02 el otro presupuesto sigue sin link', '0',
  (SELECT count(*)::text FROM presupuestos_links WHERE presupuesto_id = pg_temp.id('P2')));
SELECT pg_temp.caso('02 el estado de la copia lo lee quien ve el presupuesto', '1', pg_temp.consultar(format(
  'SELECT count(revision)::text FROM presupuestos_links WHERE presupuesto_id = %L', pg_temp.id('P1')), 'Laura'));
SELECT pg_temp.caso('02 no lo lee quien no ve la obra', '0', pg_temp.consultar(format(
  'SELECT count(revision)::text FROM presupuestos_links WHERE presupuesto_id = %L', pg_temp.id('P1')), 'Ana'));
SELECT pg_temp.caso('02 la llave no se lee de la tabla: ' || u, '42501', pg_temp.consultar(format(
  'SELECT llave FROM presupuestos_links WHERE presupuesto_id = %L', pg_temp.id('P1')), u))
FROM unnest(ARRAY['Juan', 'Laura', 'G']) AS u;

-- ============================================================
-- 03. La llave: ver como cliente y copiar link
-- ============================================================
SELECT pg_temp.caso('03 quien no trabaja la obra', '42501', pg_temp.llave('P1', false, 'Ana'));
SELECT pg_temp.caso('03 quien ve y no arma', '42501', pg_temp.llave('P1', true, 'Laura'));
SELECT pg_temp.caso('03 ver como cliente da la llave', 'true', (SELECT (pg_temp.llave('P1', false, 'Juan') = l.llave)::text
  FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1')));
SELECT pg_temp.caso('03 y no anota', 'true', (SELECT (l.link_copiado_en IS NULL)::text
  FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1')));
SELECT pg_temp.caso('03 copiar link da la misma', 'true', (SELECT (pg_temp.llave('P1', true, 'Juan') = l.llave)::text
  FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1')));
SELECT pg_temp.caso('03 queda anotado, y no cambia lo que falta copiar', 'true/1', (SELECT (l.link_copiado_en IS NOT NULL)::text
  FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1')) || '/' || pg_temp.link('P1'));
UPDATE presupuestos_links SET link_copiado_en = '2026-01-01' WHERE presupuesto_id = pg_temp.id('P1');
SELECT pg_temp.caso('03 la segunda vez no pisa la primera, tampoco gerencia', 'true/2026-01-01', (
  SELECT (pg_temp.llave('P1', true, 'G') = l.llave)::text FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1'))
  || '/' || (SELECT l.link_copiado_en::date FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1')));

-- ============================================================
-- 04. El portal confirmó
-- ============================================================
SELECT pg_temp.caso('04 no lo llama un usuario: ' || left(f, 40), '42501', pg_temp.consultar(f, 'G'))
FROM unnest(ARRAY[format($s$SELECT presupuestos_portal_copiada(%L, 1, '{1}')::text$s$, pg_temp.vigente('P1')),
                  'SELECT count(*)::text FROM presupuestos_portal_pendientes()']) AS f;
SELECT pg_temp.caso('04 pendiente, con su llave', '1/true', (
  SELECT count(*) || '/' || bool_and(x.llave ~ '^[0-9a-f]{32}$' AND x.activo AND x.revision = 1)::text
  FROM presupuestos_portal_pendientes() x WHERE x.presupuesto_id = pg_temp.id('P1')));
SELECT presupuestos_portal_copiada(pg_temp.vigente('P1'), 1, '{1}');
SELECT pg_temp.caso('04 al día, muestra la v1', '1/1/{1}/0', pg_temp.link('P1') || '/' || (
  SELECT count(*) FROM presupuestos_portal_pendientes() x WHERE x.presupuesto_id = pg_temp.id('P1')));
SELECT presupuestos_portal_copiada(pg_temp.vigente('P1'), 7, '{9}');
SELECT pg_temp.caso('04 una revisión que no existe no anota', '1/1/{1}', pg_temp.link('P1'));

-- ============================================================
-- 05. Lo que cambia lo que muestra el portal
-- ============================================================
SELECT pg_temp.copiar('P1v2', 'P1v1');
SELECT pg_temp.caso('05 un borrador abierto no cambia nada', '1/1/{1}', pg_temp.link('P1'));
SELECT pg_temp.caso('05 publicar la corrección', 'ok', pg_temp.publicar('P1v2'));
SELECT pg_temp.caso('05 la v1 a obsoleta y la v2 publicada: sin actualizar, muestra la v1', '3/1/{1}', pg_temp.link('P1'));
SELECT presupuestos_portal_copiada(pg_temp.vigente('P1'), 2, '{1}');
SELECT pg_temp.caso('05 una revisión intermedia anota, y sigue pendiente', '3/2/{1}/1', pg_temp.link('P1') || '/' || (
  SELECT count(*) FROM presupuestos_portal_pendientes() x WHERE x.presupuesto_id = pg_temp.id('P1')));
SELECT presupuestos_portal_copiada(pg_temp.vigente('P1'), 1, '{9}');
SELECT pg_temp.caso('05 una más vieja que la confirmada no pisa', '3/2/{1}', pg_temp.link('P1'));
SELECT presupuestos_portal_copiada(pg_temp.vigente('P1'), 3, '{2}');
SELECT pg_temp.caso('05 al día, muestra la v2', '3/3/{2}', pg_temp.link('P1'));
SELECT pg_temp.caso('05 cambiar el nombre', 'ok/4/3/{2}', pg_temp.consultar(format(
  $s$UPDATE presupuestos SET nombre = 'Zqx200 Etapa uno' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('P1')), 'Juan')
  || '/' || pg_temp.link('P1'));
SELECT pg_temp.caso('05 escribir el mismo nombre no cuenta', 'ok/4/3/{2}', pg_temp.consultar(format(
  $s$UPDATE presupuestos SET nombre = 'Zqx200 Etapa uno' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('P1')), 'Juan')
  || '/' || pg_temp.link('P1'));
SELECT pg_temp.caso('05 aprobar es una revisión', 'ok/5/3/{2}',
  pg_temp.llamar('presupuestos_aprobar', 'P1v2', 'Juan') || '/' || pg_temp.link('P1'));
SELECT pg_temp.caso('05 sigue habiendo un solo link', '1', (SELECT count(*)::text FROM presupuestos_links
  WHERE presupuesto_id = pg_temp.id('P1')));

-- Una autorización de Técnica puede habilitar una combinación en lo ya publicado; lo del jefe y lo pendiente, no.
SELECT pg_temp.caso('05 se publica el segundo', 'ok/1', pg_temp.publicar('P2v1') || '/' || pg_temp.link('P2'));
INSERT INTO presupuestos_autorizaciones (version_id, tipo, renglon_id, pedido, estado, pedido_por)
SELECT pg_temp.id('P2v1'), 'tecnica', r.id, '{"texto":"Zqx200"}', 'pendiente', pg_temp.id('Juan')
FROM presupuestos_renglones r WHERE r.version_id = pg_temp.id('P2v1');
INSERT INTO presupuestos_autorizaciones (version_id, tipo, pedido, estado, pedido_por, resuelto_por, resuelto_en)
VALUES (pg_temp.id('P2v1'), 'comercial', '{"texto":"Zqx200"}', 'autorizada', pg_temp.id('Juan'), pg_temp.id('G'), now());
SELECT pg_temp.caso('05 Técnica pendiente y el jefe autorizando no cuentan', '1', pg_temp.link('P2'));
UPDATE presupuestos_autorizaciones SET estado = 'autorizada', resuelto_por = pg_temp.id('G'), resuelto_en = now()
WHERE version_id = pg_temp.id('P2v1') AND tipo = 'tecnica';
SELECT pg_temp.caso('05 Técnica autoriza: otra revisión', '2', pg_temp.link('P2'));
SELECT pg_temp.caso('05 y no toca al otro presupuesto', '5/3/{2}', pg_temp.link('P1'));

-- ============================================================
-- 06. Anular
-- ============================================================
INSERT INTO ids VALUES ('viejo', pg_temp.vigente('P1'));
SELECT pg_temp.caso('06 quien no trabaja la obra', '42501', pg_temp.llamar('presupuestos_link_anular', 'P1', 'Ana'));
SELECT pg_temp.caso('06 quien ve y no arma', '42501', pg_temp.llamar('presupuestos_link_anular', 'P1', 'Laura'));
SELECT pg_temp.caso('06 quien arma', 'ok', pg_temp.llamar('presupuestos_link_anular', 'P1', 'Juan'));
SELECT pg_temp.caso('06 el viejo queda cortado y con una revisión sin copiar', 'false/6/3', (
  SELECT concat_ws('/', l.activo::text, l.revision, l.copia_revision) FROM presupuestos_links l WHERE l.id = pg_temp.id('viejo')));
SELECT pg_temp.caso('06 el nuevo: otra llave, sin copiar ni enviar', '1/true/true', pg_temp.link('P1') || '/' || (
  SELECT concat_ws('/', (l.link_copiado_en IS NULL)::text,
                   (l.llave <> (SELECT v.llave FROM presupuestos_links v WHERE v.id = pg_temp.id('viejo')))::text)
  FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1')));
SELECT pg_temp.caso('06 la llave que se da es la nueva', 'true', (SELECT (pg_temp.llave('P1', false, 'Juan') = l.llave)::text
  FROM presupuestos_links l WHERE l.id = pg_temp.vigente('P1')));
SELECT pg_temp.caso('06 pendientes: el corte y el nuevo', 'false,true', (
  SELECT string_agg(x.activo::text, ',' ORDER BY x.activo)
  FROM presupuestos_portal_pendientes() x WHERE x.presupuesto_id = pg_temp.id('P1')));
SELECT presupuestos_portal_copiada(pg_temp.id('viejo'), 6, '{}');
SELECT pg_temp.caso('06 cortado en el portal', '6/6/{}', (
  SELECT concat_ws('/', l.revision, l.copia_revision, l.copia_versiones) FROM presupuestos_links l WHERE l.id = pg_temp.id('viejo')));
SELECT pg_temp.caso('06 lo que pase después no toca al viejo', 'ok/6/2', pg_temp.consultar(format(
  $s$SELECT presupuestos_revertir(%L, 'Zqx200 se arrepintió')::text$s$, pg_temp.id('P1')), 'G')
  || '/' || (SELECT l.revision FROM presupuestos_links l WHERE l.id = pg_temp.id('viejo'))
  || '/' || pg_temp.link('P1'));
SELECT pg_temp.caso('06 un link anulado no vuelve', 'PR002', pg_temp.probar(format(
  'UPDATE presupuestos_links SET activo = true WHERE id = %L', pg_temp.id('viejo'))));
SELECT pg_temp.caso('06 la copia no se adelanta a la revisión', '23514', pg_temp.probar(format(
  'UPDATE presupuestos_links SET copia_revision = revision + 1 WHERE id = %L', pg_temp.id('viejo'))));

-- ============================================================
-- 07. Privilegios
-- ============================================================
SELECT pg_temp.caso('07 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_link_llave(uuid,boolean)', 'presupuestos_link_anular(uuid)', 'presupuestos_portal_pendientes()',
  'presupuestos_portal_copiada(uuid,integer,integer[])', 'presupuestos_links_cambio()']) AS f;
SELECT pg_temp.caso('07 un usuario no llama: ' || f, 'false', has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_portal_pendientes()', 'presupuestos_portal_copiada(uuid,integer,integer[])',
  'presupuestos_links_cambio()']) AS f;
SELECT pg_temp.caso('07 el servidor: ' || f, 'true', has_function_privilege('service_role', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_portal_pendientes()', 'presupuestos_portal_copiada(uuid,integer,integer[])']) AS f;
SELECT pg_temp.caso('07 sin ' || p || ' directo', 'false', has_table_privilege('authenticated', 'public.presupuestos_links', p)::text)
FROM unnest(ARRAY['INSERT', 'UPDATE', 'DELETE']) AS p;
SELECT pg_temp.caso('07 la llave, sin SELECT', 'false',
  has_column_privilege('authenticated', 'public.presupuestos_links', 'llave', 'SELECT')::text);
SELECT pg_temp.caso('07 anon no lee', 'false', has_any_column_privilege('anon', 'public.presupuestos_links', 'SELECT')::text);
SELECT pg_temp.caso('07 RLS activado', 'true', (SELECT relrowsecurity::text FROM pg_class WHERE oid = 'public.presupuestos_links'::regclass));

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
