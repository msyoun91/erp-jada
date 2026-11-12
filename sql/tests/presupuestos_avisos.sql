-- Verificación de sql/192 y sql/193: los avisos de Presupuestos. NO es una migración: todo corre dentro de una transacción que
-- revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Laura responsable de Belgrano y jefa (autoriza), Juan vendedor que participa, Marta jefa sin la obra, Ana vendedora sin
-- la obra, Sofia de Técnica (autoriza alertas), Rita de Técnica que solo mira, G gerencia. Los pedidos se arman a mano en
-- `presupuestos_autorizaciones` (lo que pide el jefe o Técnica se prueba en presupuestos_autorizaciones.sql); acá se prueba a quién
-- le llega y cuándo desaparece. Lo creado lleva Zqx193.

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

CREATE FUNCTION pg_temp.alta(p_nombre text, p_obra text, p_como text DEFAULT 'Juan') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_p uuid := pg_temp.consultar(format($s$SELECT presupuestos_alta(%L, %L, 'ARS', 21)::text$s$,
    pg_temp.id(p_obra), 'Zqx193 ' || p_nombre), p_como)::uuid;
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

CREATE FUNCTION pg_temp.copiar(p_nombre text, p_desde text, p_como text DEFAULT 'Juan') RETURNS void LANGUAGE sql AS $f$
  INSERT INTO ids VALUES (p_nombre, pg_temp.consultar(format('SELECT presupuestos_version_copiar(%L)::text',
    pg_temp.id(p_desde)), p_como)::uuid);
$f$;

CREATE FUNCTION pg_temp.publicar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_version_publicar(%L)::text', pg_temp.id(p_version)), p_como);
$f$;

-- "P-0142 · v2": lo que muestra la campanita.
CREATE FUNCTION pg_temp.et(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT p.codigo || ' · v' || v.numero
  FROM presupuestos_versiones v JOIN presupuestos p ON p.id = v.presupuesto_id WHERE v.id = pg_temp.id(p_version);
$f$;

-- Un pedido armado a mano: una fila por tipo, y la versión en revisión. Técnica apunta al primer renglón.
CREATE FUNCTION pg_temp.pedir(p_version text, p_tipos text[], p_como text DEFAULT 'Juan') RETURNS void LANGUAGE sql AS $f$
  INSERT INTO presupuestos_autorizaciones (version_id, tipo, renglon_id, pedido, pedido_por)
  SELECT pg_temp.id(p_version), t::tipo_autorizacion_presupuesto,
         CASE WHEN t = 'tecnica' THEN (SELECT x.id FROM presupuestos_renglones x
                                       WHERE x.version_id = pg_temp.id(p_version) AND x.activo ORDER BY x.created_at LIMIT 1) END,
         jsonb_build_object('texto', 'Zqx193'), pg_temp.id(p_como)
  FROM unnest(p_tipos) t;
  UPDATE presupuestos_versiones SET estado = 'en_revision' WHERE id = pg_temp.id(p_version);
$f$;

CREATE FUNCTION pg_temp.resolver(p_version text, p_tipo text, p_autoriza boolean, p_como text, p_motivo text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_pedido_resolver(%L, %L, %L)::text',
    (SELECT a.id FROM presupuestos_autorizaciones a
     WHERE a.version_id = pg_temp.id(p_version) AND a.tipo::text = p_tipo AND a.estado = 'pendiente'),
    p_autoriza, p_motivo), p_como);
$f$;

-- Lo que ve en la campanita: "etiqueta | motivo | destino | actor", o '-'.
CREATE FUNCTION pg_temp.campanita(p_como text, p_tipo text, p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$
    SELECT coalesce(string_agg(x.etiqueta || ' | ' || coalesce(x.motivo, '') || ' | ' || coalesce(x.destino, '') || ' | '
                               || coalesce(x.actor, ''), ' ; '), '-')
    FROM notificaciones_listar(100) x WHERE x.tipo = %L AND x.etiqueta = %L$q$, p_tipo, pg_temp.et(p_version)), p_como);
$f$;

-- Cuántas filas activas tiene en la tabla (sin la RLS): una por versión y persona.
CREATE FUNCTION pg_temp.filas(p_como text, p_tipo text, p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT count(*)::text FROM usuario_notificaciones n
  WHERE n.usuario_id = pg_temp.id(p_como) AND n.tipo::text = p_tipo AND n.activo
    AND coalesce((SELECT a.version_id FROM presupuestos_autorizaciones a WHERE a.id = n.entidad_id), n.entidad_id)
        = pg_temp.id(p_version);
$f$;

CREATE FUNCTION pg_temp.todas(p_tipo text, p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT count(*)::text FROM usuario_notificaciones n
  WHERE n.tipo::text = p_tipo AND n.activo
    AND coalesce((SELECT a.version_id FROM presupuestos_autorizaciones a WHERE a.id = n.entidad_id), n.entidad_id)
        = pg_temp.id(p_version);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','Laura','Marta','Ana','Sofia','Rita','G','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo = 'presupuestos' OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test193.local', jsonb_build_object('nombre', 'test193 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Laura','Marta','Ana','Sofia','Rita','G');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Laura','contactos_ver'), ('Laura','obras_ver'), ('Laura','presupuestos_ver'), ('Laura','presupuestos_armar'),
    ('Laura','presupuestos_autorizar'),
  ('Marta','contactos_ver'), ('Marta','obras_ver'), ('Marta','presupuestos_ver'), ('Marta','presupuestos_armar'),
    ('Marta','presupuestos_autorizar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('Sofia','presupuestos_revision'), ('Sofia','presupuestos_autorizar_tecnica'),
  ('Rita','presupuestos_revision'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx193 Torre Belgrano', 'Zqx193 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Laura'), pg_temp.id('Laura'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Juan'), pg_temp.id('Laura'));

SELECT pg_temp.caso('00 gerencia configura', 'ok', pg_temp.consultar($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, '[]')$s$, 'G'));
SELECT pg_temp.alta('P1', 'Belgrano');
SELECT pg_temp.alta('P2', 'Belgrano');
SELECT pg_temp.alta('P3', 'Belgrano');

-- ============================================================
-- 01. Un pedido llega a todos los que pueden autorizar algo de lo pendiente
-- ============================================================
SELECT pg_temp.pedir('P1v1', ARRAY['comercial', 'tecnica']);

SELECT pg_temp.caso('01 Laura, jefa de la obra', pg_temp.et('P1v1') || ' |  | presupuesto | test193 Juan',
  pg_temp.campanita('Laura', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 gerencia, que administra', pg_temp.et('P1v1') || ' |  | presupuesto | test193 Juan',
  pg_temp.campanita('G', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 Técnica, a Revisión técnica y sin más que el número', pg_temp.et('P1v1') || ' |  | presupuestos_revision | test193 Juan',
  pg_temp.campanita('Sofia', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 Técnica que solo mira no recibe', '-', pg_temp.campanita('Rita', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 una jefa sin la obra no recibe', '-', pg_temp.campanita('Marta', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 quien arma sin autorizar no recibe', '-', pg_temp.campanita('Ana', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 quien pidió no recibe el suyo', '-', pg_temp.campanita('Juan', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 gerencia, uno por versión aunque pida de los dos tipos', '1', pg_temp.filas('G', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('01 Laura, uno', '1', pg_temp.filas('Laura', 'presupuesto_pedido', 'P1v1'));

-- ============================================================
-- 02. Desaparece cuando no le queda nada pendiente que pueda autorizar
-- ============================================================
SELECT pg_temp.caso('02 Laura autoriza lo comercial', 'ok', pg_temp.resolver('P1v1', 'comercial', true, 'Laura'));
SELECT pg_temp.caso('02 a Laura ya no le queda nada', '-', pg_temp.campanita('Laura', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('02 gerencia sigue: falta Técnica', pg_temp.et('P1v1') || ' |  | presupuesto | test193 Juan',
  pg_temp.campanita('G', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('02 Técnica sigue', pg_temp.et('P1v1') || ' |  | presupuestos_revision | test193 Juan',
  pg_temp.campanita('Sofia', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('02 aún no está lista para publicar', '-', pg_temp.campanita('Juan', 'presupuesto_autorizado', 'P1v1'));

-- ============================================================
-- 03. Lista para publicar: a quien pidió, cuando se autoriza la última
-- ============================================================
SELECT pg_temp.caso('03 Sofia autoriza la última', 'ok', pg_temp.resolver('P1v1', 'tecnica', true, 'Sofia'));
SELECT pg_temp.caso('03 le llega a Juan, que pidió', pg_temp.et('P1v1') || ' |  | presupuesto | test193 Sofia',
  pg_temp.campanita('Juan', 'presupuesto_autorizado', 'P1v1'));
SELECT pg_temp.caso('03 a nadie más', '0/0/0', pg_temp.filas('Laura', 'presupuesto_autorizado', 'P1v1') || '/'
  || pg_temp.filas('G', 'presupuesto_autorizado', 'P1v1') || '/' || pg_temp.filas('Sofia', 'presupuesto_autorizado', 'P1v1'));
SELECT pg_temp.caso('03 el pedido de gerencia desapareció', '-', pg_temp.campanita('G', 'presupuesto_pedido', 'P1v1'));
SELECT pg_temp.caso('03 y el de Técnica', '-', pg_temp.campanita('Sofia', 'presupuesto_pedido', 'P1v1'));

-- ============================================================
-- 04. Publicar: el renglón a mano nuevo avisa a quienes autorizan lo comercial, menos a quien publica
-- ============================================================
SELECT pg_temp.caso('04 Juan publica la v1', 'ok', pg_temp.publicar('P1v1'));
SELECT pg_temp.caso('04 la versión salió de revisión: ya no está lista para publicar', '-',
  pg_temp.campanita('Juan', 'presupuesto_autorizado', 'P1v1'));
SELECT pg_temp.caso('04 Laura: un renglón a mano', pg_temp.et('P1v1') || ' | 1 renglón a mano | presupuesto | test193 Juan',
  pg_temp.campanita('Laura', 'presupuesto_a_mano', 'P1v1'));
SELECT pg_temp.caso('04 gerencia también', pg_temp.et('P1v1') || ' | 1 renglón a mano | presupuesto | test193 Juan',
  pg_temp.campanita('G', 'presupuesto_a_mano', 'P1v1'));
SELECT pg_temp.caso('04 quien publica no', '-', pg_temp.campanita('Juan', 'presupuesto_a_mano', 'P1v1'));
SELECT pg_temp.caso('04 Técnica no autoriza lo comercial', '-', pg_temp.campanita('Sofia', 'presupuesto_a_mano', 'P1v1'));
SELECT pg_temp.caso('04 la jefa sin la obra no', '-', pg_temp.campanita('Marta', 'presupuesto_a_mano', 'P1v1'));

-- La v2 corrige sin tocar el flete: no avisa. La v3 lo sube: avisa y cuenta uno. La v4 lo sube otra vez y suma un andamio: dos.
SELECT pg_temp.copiar('P1v2', 'P1v1');
SELECT pg_temp.caso('04 publicar la corrección igual', 'ok', pg_temp.publicar('P1v2'));
SELECT pg_temp.caso('04 el mismo flete no avisa', '-', pg_temp.campanita('Laura', 'presupuesto_a_mano', 'P1v2'));
SELECT pg_temp.copiar('P1v3', 'P1v2');
SELECT pg_temp.caso('04 el flete a $1.500', 'ok', pg_temp.consultar(format(
  $s$UPDATE presupuestos_renglones SET precio = 1500 WHERE version_id = %L AND descripcion = 'Flete' RETURNING 'ok'$s$,
  pg_temp.id('P1v3')), 'Juan'));
SELECT pg_temp.caso('04 publicar la v3', 'ok', pg_temp.publicar('P1v3'));
SELECT pg_temp.caso('04 el flete cambió: uno', pg_temp.et('P1v3') || ' | 1 renglón a mano | presupuesto | test193 Juan',
  pg_temp.campanita('Laura', 'presupuesto_a_mano', 'P1v3'));
SELECT pg_temp.copiar('P1v4', 'P1v3');
SELECT pg_temp.caso('04 el flete otra vez y un andamio', 'ok/ok', pg_temp.consultar(format(
  $s$UPDATE presupuestos_renglones SET precio = 1800 WHERE version_id = %L AND descripcion = 'Flete' RETURNING 'ok'$s$,
  pg_temp.id('P1v4')), 'Juan') || '/' || pg_temp.consultar(format(
  $s$INSERT INTO presupuestos_renglones (version_id, seccion_id, tipo, descripcion, precio)
     SELECT %L, s.id, 'mano', 'Andamio', 500 FROM presupuestos_secciones s WHERE s.version_id = %L AND s.activo RETURNING 'ok'$s$,
  pg_temp.id('P1v4'), pg_temp.id('P1v4')), 'Juan'));
SELECT pg_temp.caso('04 publicar la v4', 'ok', pg_temp.publicar('P1v4'));
SELECT pg_temp.caso('04 los dos cambiados: dos', pg_temp.et('P1v4') || ' | 2 renglones a mano | presupuesto | test193 Juan',
  pg_temp.campanita('Laura', 'presupuesto_a_mano', 'P1v4'));

-- ============================================================
-- 05. Devolver: a quien pidió, con el motivo, y queda como noticia
-- ============================================================
SELECT pg_temp.pedir('P2v1', ARRAY['comercial']);
SELECT pg_temp.caso('05 Laura recibe el pedido', pg_temp.et('P2v1') || ' |  | presupuesto | test193 Juan',
  pg_temp.campanita('Laura', 'presupuesto_pedido', 'P2v1'));
SELECT pg_temp.caso('05 Laura devuelve', 'ok', pg_temp.resolver('P2v1', 'comercial', false, 'Laura', 'Bajá el descuento al 10 %'));
SELECT pg_temp.caso('05 Juan recibe la devolución con el motivo',
  pg_temp.et('P2v1') || ' | Bajá el descuento al 10 % | presupuesto | test193 Laura',
  pg_temp.campanita('Juan', 'presupuesto_devuelto', 'P2v1'));
SELECT pg_temp.caso('05 el pedido de Laura desapareció', '-', pg_temp.campanita('Laura', 'presupuesto_pedido', 'P2v1'));
SELECT pg_temp.caso('05 devolver no es "lista para publicar"', '-', pg_temp.campanita('Juan', 'presupuesto_autorizado', 'P2v1'));
SELECT pg_temp.caso('05 la devolución es solo de Juan', '0/0', pg_temp.filas('G', 'presupuesto_devuelto', 'P2v1') || '/'
  || pg_temp.filas('Laura', 'presupuesto_devuelto', 'P2v1'));

-- Juan corrige y vuelve a pedir: la devolución sigue, y el pedido nuevo reemplaza al anterior.
SELECT pg_temp.pedir('P2v1', ARRAY['comercial']);
SELECT pg_temp.caso('05 la devolución sigue aunque pida de nuevo',
  pg_temp.et('P2v1') || ' | Bajá el descuento al 10 % | presupuesto | test193 Laura',
  pg_temp.campanita('Juan', 'presupuesto_devuelto', 'P2v1'));
SELECT pg_temp.caso('05 el pedido nuevo le llega a Laura', pg_temp.et('P2v1') || ' |  | presupuesto | test193 Juan',
  pg_temp.campanita('Laura', 'presupuesto_pedido', 'P2v1'));
SELECT pg_temp.caso('05 uno activo por persona: el anterior se desactivó', '1/1',
  pg_temp.filas('Laura', 'presupuesto_pedido', 'P2v1') || '/' || pg_temp.filas('G', 'presupuesto_pedido', 'P2v1'));

-- ============================================================
-- 06. Retirar no avisa
-- ============================================================
SELECT pg_temp.pedir('P3v1', ARRAY['comercial']);
SELECT pg_temp.caso('06 Laura recibe el pedido', pg_temp.et('P3v1') || ' |  | presupuesto | test193 Juan',
  pg_temp.campanita('Laura', 'presupuesto_pedido', 'P3v1'));
SELECT pg_temp.caso('06 Juan retira', 'ok', pg_temp.consultar(format('SELECT presupuestos_version_retirar(%L)::text',
  pg_temp.id('P3v1')), 'Juan'));
SELECT pg_temp.caso('06 el pedido desaparece', '-', pg_temp.campanita('Laura', 'presupuesto_pedido', 'P3v1'));
SELECT pg_temp.caso('06 y nadie recibe nada nuevo', '0/0', pg_temp.todas('presupuesto_devuelto', 'P3v1') || '/'
  || pg_temp.todas('presupuesto_autorizado', 'P3v1'));

-- ============================================================
-- 07. Si al pedir ya queda todo autorizado, se publica en el mismo paso y no hay aviso de pedido
-- ============================================================
SELECT pg_temp.caso('07 descuento sobre el tope', 'ok', pg_temp.consultar(format(
  $s$UPDATE presupuestos_versiones SET descuento = 20 WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('P3v1')), 'Juan'));
SELECT pg_temp.caso('07 gerencia pide: se publica', 'publicado', pg_temp.consultar(format(
  'SELECT presupuestos_version_pedir(%L)::text', pg_temp.id('P3v1')), 'G'));
SELECT pg_temp.caso('07 ni pedido ni lista para publicar', '0/0', pg_temp.todas('presupuesto_pedido', 'P3v1') || '/'
  || pg_temp.todas('presupuesto_autorizado', 'P3v1'));
SELECT pg_temp.caso('07 sí el renglón a mano nuevo, a Laura', pg_temp.et('P3v1') || ' | 1 renglón a mano | presupuesto | test193 G',
  pg_temp.campanita('Laura', 'presupuesto_a_mano', 'P3v1'));

-- ============================================================
-- 08. Quién autoriza sigue igual, y lo ajeno no se lee
-- ============================================================
SELECT pg_temp.caso('08 Laura autoriza lo comercial en Belgrano', 'true', pg_temp.consultar(format(
  $s$SELECT presupuestos_puede_autorizar('comercial', %L)::text$s$, pg_temp.id('Belgrano')), 'Laura'));
SELECT pg_temp.caso('08 Marta no', 'false', pg_temp.consultar(format(
  $s$SELECT presupuestos_puede_autorizar('comercial', %L)::text$s$, pg_temp.id('Belgrano')), 'Marta'));
SELECT pg_temp.caso('08 Sofia autoriza lo de Técnica', 'true', pg_temp.consultar(format(
  $s$SELECT presupuestos_puede_autorizar('tecnica', %L)::text$s$, pg_temp.id('Belgrano')), 'Sofia'));
SELECT pg_temp.caso('08 gerencia, las dos', 'true/true', pg_temp.consultar(format(
  $s$SELECT presupuestos_puede_autorizar('comercial', %1$L)::text$s$, pg_temp.id('Belgrano')), 'G') || '/' || pg_temp.consultar(format(
  $s$SELECT presupuestos_puede_autorizar('tecnica', %1$L)::text$s$, pg_temp.id('Belgrano')), 'G'));
SELECT pg_temp.caso('08 los avisos de Laura, leídos por Juan: nada', '0', pg_temp.consultar(format(
  $s$SELECT count(*)::text FROM presupuestos_avisos(%L::uuid[])$s$,
  (SELECT array_agg(n.id) FROM usuario_notificaciones n WHERE n.usuario_id = pg_temp.id('Laura'))::text), 'Juan'));
SELECT pg_temp.caso('08 y los de ella, leídos por ella', 'true', pg_temp.consultar(format(
  $s$SELECT (count(*) > 0)::text FROM presupuestos_avisos(%L::uuid[])$s$,
  (SELECT array_agg(n.id) FROM usuario_notificaciones n WHERE n.usuario_id = pg_temp.id('Laura'))::text), 'Laura'));
SELECT pg_temp.caso('08 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_avisos(uuid[])', 'presupuestos_puede_autorizar_de(tipo_autorizacion_presupuesto,uuid,uuid)',
  'presupuestos_mano_nuevos(uuid)', 'presupuestos_autorizaciones_avisar_pedido()',
  'presupuestos_autorizaciones_avisar_resuelta()', 'presupuestos_versiones_avisar_mano()']) AS f;
SELECT pg_temp.caso('08 authenticated: ' || f, 'false', has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_puede_autorizar_de(tipo_autorizacion_presupuesto,uuid,uuid)',
  'presupuestos_mano_nuevos(uuid)', 'presupuestos_autorizaciones_avisar_pedido()',
  'presupuestos_autorizaciones_avisar_resuelta()', 'presupuestos_versiones_avisar_mano()']) AS f;
SELECT pg_temp.caso('08 authenticated lee sus avisos', 'true',
  has_function_privilege('authenticated', 'public.presupuestos_avisos(uuid[])', 'EXECUTE')::text);

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
