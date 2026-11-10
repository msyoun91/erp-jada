-- Verificación de sql/194: nombre congelado, importe con IVA por renglón y freno de `contratada`. NO es una migración: todo
-- corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Laura responsable de Belgrano y jefa, Juan vendedor que participa. Lo creado lleva Zqx194.

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

-- Un presupuesto con su v1, una sección y un renglón a mano de 1000.
CREATE FUNCTION pg_temp.alta(p_nombre text, p_obra text, p_como text DEFAULT 'Juan') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_p uuid := pg_temp.consultar(format($s$SELECT presupuestos_alta(%L, %L, 'ARS', 21)::text$s$,
    pg_temp.id(p_obra), 'Zqx194 ' || p_nombre), p_como)::uuid;
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

CREATE FUNCTION pg_temp.copiar(p_nombre text, p_desde text, p_variante boolean DEFAULT false) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO ids VALUES (p_nombre, pg_temp.consultar(format('SELECT presupuestos_version_copiar(%L, %L)::text',
    pg_temp.id(p_desde), p_variante), 'Juan')::uuid);
$f$;

CREATE FUNCTION pg_temp.publicar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_version_publicar(%L)::text', pg_temp.id(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.aprobar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_aprobar(%L)::text', pg_temp.id(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.rechazar(p_p text, p_motivo text, p_detalle text DEFAULT NULL, p_como text DEFAULT 'Juan')
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_rechazar(%L, %L, %L)::text', pg_temp.id(p_p), p_motivo, p_detalle), p_como);
$f$;

CREATE FUNCTION pg_temp.revertir(p_p text, p_causa text, p_como text DEFAULT 'Laura') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_revertir(%L, %L)::text', pg_temp.id(p_p), p_causa), p_como);
$f$;

-- estado/motivo/nota de la obra.
CREATE FUNCTION pg_temp.obra(p_obra text) RETURNS text LANGUAGE sql AS $f$
  SELECT concat_ws('/', o.estado, o.motivo_perdida, o.estado_nota) FROM obras o WHERE o.id = pg_temp.id(p_obra);
$f$;

-- estado/motivo/nota del presupuesto y el número de la versión elegida.
CREATE FUNCTION pg_temp.pres(p_p text) RETURNS text LANGUAGE sql AS $f$
  SELECT concat_ws('/', p.estado, p.motivo_rechazo, p.estado_nota,
           (SELECT 'v' || v.numero FROM presupuestos_versiones v WHERE v.id = p.version_aprobada_id))
  FROM presupuestos p WHERE p.id = pg_temp.id(p_p);
$f$;

CREATE FUNCTION pg_temp.mover(p_obra text, p_set text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('UPDATE obras SET %s WHERE id = %L RETURNING ''ok''', p_set, pg_temp.id(p_obra)), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','Laura','G','Belgrano']) AS n;
INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo = 'presupuestos' OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));
INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test194.local', jsonb_build_object('nombre', 'test194 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Laura','G');
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Laura','contactos_ver'), ('Laura','obras_ver'), ('Laura','presupuestos_ver'), ('Laura','presupuestos_armar'),
    ('Laura','presupuestos_autorizar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por) VALUES
  (pg_temp.id('Belgrano'), 'Zqx194 Torre Belgrano', 'Zqx194 Calle 1', 'llamado', 'edificio_residencial',
   pg_temp.id('Laura'), pg_temp.id('Laura'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Juan'), pg_temp.id('Laura'));

SELECT pg_temp.caso('00 gerencia configura', 'ok', pg_temp.consultar($s$SELECT 'ok' FROM presupuestos_configurar(10, 15)$s$, 'G'));
SELECT pg_temp.caso('00 a mano, sin aprobado, no pasa a contratada', 'PR028/idea',
  pg_temp.mover('Belgrano', $s$estado = 'contratada'$s$, 'Laura') || '/' || pg_temp.obra('Belgrano'));
SELECT pg_temp.alta('P1', 'Belgrano');
SELECT pg_temp.alta('P2', 'Belgrano');

CREATE FUNCTION pg_temp.renombrar(p_p text, p_nombre text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($s$UPDATE presupuestos SET nombre = %L WHERE id = %L RETURNING 'ok'$s$, p_nombre, pg_temp.id(p_p)), p_como);
$f$;

-- ============================================================
-- 01. El nombre se edita hasta aprobar o rechazar
-- ============================================================
SELECT pg_temp.caso('01 en borrador', 'ok', pg_temp.renombrar('P1', 'Zqx194 Torre B'));
SELECT pg_temp.caso('01 publicado', 'ok/ok', pg_temp.publicar('P1v1') || '/' || pg_temp.renombrar('P1', 'Zqx194 Torre B2'));
SELECT pg_temp.caso('01 aprobado', 'ok/PR027/contratada', pg_temp.aprobar('P1v1') || '/' || pg_temp.renombrar('P1', 'Zqx194 otro')
  || '/' || pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('01 el mismo nombre no cuenta', 'ok', pg_temp.renombrar('P1', 'Zqx194 Torre B2'));
SELECT pg_temp.caso('01 revertido, se vuelve a poder', 'ok/ok', pg_temp.revertir('P1', 'error') || '/' || pg_temp.renombrar('P1', 'Zqx194 Torre C'));
SELECT pg_temp.caso('01 rechazado', 'ok/PR027', pg_temp.rechazar('P1', 'precio') || '/' || pg_temp.renombrar('P1', 'Zqx194 Torre D'));
SELECT pg_temp.caso('01 el nombre quedó', 'Zqx194 Torre C', (SELECT nombre FROM presupuestos WHERE id = pg_temp.id('P1')));

-- ============================================================
-- 02. Importe con IVA por renglón
-- ============================================================
SELECT pg_temp.caso('02 a 21 %', '1000/1210', pg_temp.consultar(format($s$SELECT trim_scale(importe) || '/' || trim_scale(importe_con_iva) FROM presupuestos_version_importes(%L)$s$, pg_temp.id('P2v1')), 'Juan'));
UPDATE presupuestos_secciones SET alicuota = 10.5 WHERE version_id = pg_temp.id('P2v1');
SELECT pg_temp.caso('02 a 10,5 %', '1000/1105', pg_temp.consultar(format($s$SELECT trim_scale(importe) || '/' || trim_scale(importe_con_iva) FROM presupuestos_version_importes(%L)$s$, pg_temp.id('P2v1')), 'Juan'));

-- ============================================================
-- 03. `contratada` solo con un aprobado
-- ============================================================
SELECT pg_temp.caso('03 aprobar sí la mueve', 'ok/ok/contratada', pg_temp.publicar('P2v1') || '/' || (
  SELECT pg_temp.aprobar('P2v1') || '/' || pg_temp.obra('Belgrano')) );
SELECT pg_temp.caso('03 sin EXECUTE: nombre_congelado', 'false',
  has_function_privilege('authenticated', 'public.presupuestos_nombre_congelado()', 'EXECUTE')::text);
SELECT pg_temp.caso('03 anon: importes', 'false',
  has_function_privilege('anon', 'public.presupuestos_version_importes(uuid)', 'EXECUTE')::text);


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
