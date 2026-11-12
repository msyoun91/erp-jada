-- Verificación de sql/191: aprobar, rechazar y revertir, y la obra que sigue a sus presupuestos. NO es una migración: todo
-- corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Laura responsable de Belgrano y jefa (autoriza), Juan vendedor que participa, Ana vendedora sin la obra, G gerencia.
-- Belgrano arranca en `idea` con P1 (Etapa 1) y P2 (Etapa 2); Palermo, de Juan, para la obra congelada y la contratada a mano.
-- Cada presupuesto lleva un renglón a mano de $1.000. Lo creado lleva Zqx191.

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
    pg_temp.id(p_obra), 'Zqx191 ' || p_nombre), p_como)::uuid;
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

-- El último evento `estado` del registro: a qué estado, con qué actor.
CREATE FUNCTION pg_temp.evento(p_ente text, p_registro text) RETURNS text LANGUAGE sql AS $f$
  SELECT concat_ws('/', e.detalle->>'estado', e.detalle->>'motivo_rechazo', e.detalle->>'estado_nota',
           (SELECT nombre FROM ids WHERE id = e.actor_id))
  FROM eventos e WHERE e.ente = p_ente AND e.registro_id = pg_temp.id(p_registro) AND e.evento = 'estado'
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','Laura','Ana','G','Belgrano','Palermo']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo = 'presupuestos' OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test191.local', jsonb_build_object('nombre', 'test191 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Laura','Ana','G');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Laura','contactos_ver'), ('Laura','obras_ver'), ('Laura','presupuestos_ver'), ('Laura','presupuestos_armar'),
    ('Laura','presupuestos_autorizar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por) VALUES
  (pg_temp.id('Belgrano'), 'Zqx191 Torre Belgrano', 'Zqx191 Calle 1', 'llamado', 'edificio_residencial',
   pg_temp.id('Laura'), pg_temp.id('Laura')),
  (pg_temp.id('Palermo'), 'Zqx191 Casa Palermo', 'Zqx191 Calle 2', 'llamado', 'edificio_residencial',
   pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Juan'), pg_temp.id('Laura'));

SELECT pg_temp.caso('00 gerencia configura', 'ok', pg_temp.consultar($s$SELECT 'ok' FROM presupuestos_configurar(10, 15, '[]')$s$, 'G'));
SELECT pg_temp.alta('P1', 'Belgrano');
SELECT pg_temp.alta('P2', 'Belgrano');
SELECT pg_temp.alta('P4', 'Palermo');
SELECT pg_temp.caso('00 la variante 1 es Aluminio', 'ok', pg_temp.consultar(format(
  $s$UPDATE presupuestos_versiones SET variante_nombre = 'Aluminio' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('P1v1')), 'Juan'));
SELECT pg_temp.caso('00 la obra arranca en idea', 'idea', pg_temp.obra('Belgrano'));

-- ============================================================
-- 01. Publicar mueve la obra
-- ============================================================
SELECT pg_temp.caso('01 aprobar un borrador', 'PR003', pg_temp.aprobar('P1v1'));
SELECT pg_temp.caso('01 rechazar un borrador', 'PR003', pg_temp.rechazar('P1', 'precio'));
SELECT pg_temp.caso('01 se publica el primero', 'ok/en_cotizacion', pg_temp.publicar('P1v1') || '/' || pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('01 el evento de la obra, con quien actuó', 'en_cotizacion/Juan', pg_temp.evento('obra', 'Belgrano'));
SELECT pg_temp.caso('01 se publica el segundo: no la mueve', 'ok/en_cotizacion', pg_temp.publicar('P2v1') || '/' || pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('01 a mano no pasa a perdida con publicados', 'PR026',
  pg_temp.mover('Belgrano', $s$estado = 'perdida', motivo_perdida = 'precio'$s$));
SELECT pg_temp.caso('01 a mano vuelve a idea', 'ok/idea', pg_temp.mover('Belgrano', $s$estado = 'idea'$s$) || '/' || pg_temp.obra('Belgrano'));

-- ============================================================
-- 02. Rechazar
-- ============================================================
SELECT pg_temp.caso('02 quien no trabaja la obra', '42501', pg_temp.rechazar('P2', 'precio', NULL, 'Ana'));
SELECT pg_temp.caso('02 sin motivo', 'PR022', pg_temp.consultar(format(
  'SELECT presupuestos_rechazar(%L, NULL)::text', pg_temp.id('P2')), 'Juan'));
SELECT pg_temp.caso('02 "otro" sin detalle', 'PR022', pg_temp.rechazar('P2', 'otro', '  '));
SELECT pg_temp.caso('02 Juan rechaza la Etapa 2', 'ok/rechazado/precio', pg_temp.rechazar('P2', 'precio') || '/' || pg_temp.pres('P2'));
SELECT pg_temp.caso('02 queda uno publicado: la obra va a cotización', 'en_cotizacion', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('02 el evento lleva el motivo', 'rechazado/precio/Juan', pg_temp.evento('presupuesto', 'P2'));
SELECT pg_temp.caso('02 rechazado no admite versiones', 'PR003', pg_temp.consultar(format(
  'SELECT presupuestos_version_copiar(%L)::text', pg_temp.id('P2v1')), 'Juan'));
SELECT pg_temp.caso('02 ni rechazarlo de nuevo', 'PR003', pg_temp.rechazar('P2', 'plazo'));
SELECT pg_temp.caso('02 ni aprobarlo', 'PR003', pg_temp.aprobar('P2v1'));

-- ============================================================
-- 03. Aprobar: una variante, y lo abierto se descarta
-- ============================================================
-- P1: v1 Aluminio publicada; v2 PVC publicada; v3 corrección de PVC publicada (v2 obsoleta); v4 corrección de Aluminio con
-- descuento sobre el tope, en revisión.
SELECT pg_temp.copiar('P1v2', 'P1v1', true);
SELECT pg_temp.caso('03 montaje: PVC', 'ok/ok', pg_temp.consultar(format(
  $s$UPDATE presupuestos_versiones SET variante_nombre = 'PVC' WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('P1v2')), 'Juan')
  || '/' || pg_temp.publicar('P1v2'));
SELECT pg_temp.copiar('P1v3', 'P1v2');
SELECT pg_temp.caso('03 montaje: PVC corregida', 'ok', pg_temp.publicar('P1v3'));
SELECT pg_temp.copiar('P1v4', 'P1v1');
SELECT pg_temp.caso('03 montaje: una en revisión', 'ok/en_revision', pg_temp.consultar(format(
  $s$UPDATE presupuestos_versiones SET descuento = 20 WHERE id = %L RETURNING 'ok'$s$, pg_temp.id('P1v4')), 'Juan')
  || '/' || pg_temp.consultar(format('SELECT presupuestos_version_pedir(%L)::text', pg_temp.id('P1v4')), 'Juan'));

SELECT pg_temp.caso('03 quien no trabaja la obra', '42501', pg_temp.aprobar('P1v3', 'Ana'));
SELECT pg_temp.caso('03 una versión reemplazada', 'PR021', pg_temp.aprobar('P1v2'));
SELECT pg_temp.caso('03 una en revisión', 'PR021', pg_temp.aprobar('P1v4'));
SELECT pg_temp.caso('03 Juan aprueba PVC', 'ok/aprobado/v3', pg_temp.aprobar('P1v3') || '/' || pg_temp.pres('P1'));
SELECT pg_temp.caso('03 la obra queda contratada', 'contratada', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('03 el evento de la obra', 'contratada/Juan', pg_temp.evento('obra', 'Belgrano'));
SELECT pg_temp.caso('03 la que estaba en revisión se descartó', 'borrador/false', (
  SELECT v.estado || '/' || v.activo FROM presupuestos_versiones v WHERE v.id = pg_temp.id('P1v4')));
SELECT pg_temp.caso('03 y su pedido quedó retirado', 'retirada', (
  SELECT string_agg(a.estado::text, ',') FROM presupuestos_autorizaciones a WHERE a.version_id = pg_temp.id('P1v4')));
SELECT pg_temp.caso('03 las publicadas siguen publicadas', 'v1 publicado,v3 publicado', (
  SELECT string_agg('v' || v.numero || ' ' || v.estado, ',' ORDER BY v.numero) FROM presupuestos_versiones v
  WHERE v.presupuesto_id = pg_temp.id('P1') AND v.activo AND v.estado = 'publicado'));
SELECT pg_temp.caso('03 aprobado no admite versiones', 'PR003', pg_temp.consultar(format(
  'SELECT presupuestos_version_copiar(%L)::text', pg_temp.id('P1v3')), 'Juan'));
SELECT pg_temp.caso('03 ni quitar una variante', 'PR003', pg_temp.consultar(format(
  'SELECT presupuestos_variante_quitar(%L)::text', pg_temp.id('P1v1')), 'Juan'));
SELECT pg_temp.caso('03 ni aprobar otra variante', 'PR003', pg_temp.aprobar('P1v1'));
SELECT pg_temp.caso('03 a mano la obra no sale de contratada', 'PR025',
  pg_temp.mover('Belgrano', $s$estado = 'en_cotizacion', estado_nota = 'me equivoqué'$s$, 'Laura'));

-- ============================================================
-- 04. Revertir
-- ============================================================
SELECT pg_temp.caso('04 el vendedor no revierte', '42501', pg_temp.revertir('P1', 'error', 'Juan'));
SELECT pg_temp.caso('04 quien no ve la obra', '42501', pg_temp.revertir('P1', 'error', 'Ana'));
SELECT pg_temp.caso('04 sin causa', 'PR024', pg_temp.revertir('P1', '  '));
SELECT pg_temp.caso('04 Laura revierte la aprobación', 'ok/publicado/variante equivocada',
  pg_temp.revertir('P1', ' variante equivocada ') || '/' || pg_temp.pres('P1'));
SELECT pg_temp.caso('04 la obra vuelve a cotización, con la causa', 'en_cotizacion/variante equivocada', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('04 el evento lleva la causa', 'publicado/variante equivocada/Laura', pg_temp.evento('presupuesto', 'P1'));
SELECT pg_temp.caso('04 uno publicado no se revierte', 'PR023', pg_temp.revertir('P1', 'otra vez'));
SELECT pg_temp.caso('04 vuelve a admitir versiones', 'uuid', CASE WHEN pg_temp.consultar(format(
  'SELECT presupuestos_version_copiar(%L)::text', pg_temp.id('P1v1')), 'Juan') ~ '^[0-9a-f-]{36}$' THEN 'uuid' END);

-- ============================================================
-- 05. El rechazo que deja la obra perdida, y su reversión
-- ============================================================
SELECT pg_temp.caso('05 Juan rechaza la Etapa 1, con un borrador abierto', 'ok/rechazado/otro/se fue con otro',
  pg_temp.rechazar('P1', 'otro', 'se fue con otro') || '/' || pg_temp.pres('P1'));
SELECT pg_temp.caso('05 sin publicados ni aprobados: perdida, con el motivo', 'perdida/otro/se fue con otro', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('05 el borrador se descartó', '0', (
  SELECT count(*)::text FROM presupuestos_versiones v
  WHERE v.presupuesto_id = pg_temp.id('P1') AND v.activo AND v.estado IN ('borrador', 'en_revision')));
SELECT pg_temp.caso('05 gerencia revierte el rechazo', 'ok/publicado/se arrepintió', pg_temp.revertir('P1', 'se arrepintió', 'G')
  || '/' || pg_temp.pres('P1'));
SELECT pg_temp.caso('05 la obra se reabre', 'en_cotizacion', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('05 se aprueba de nuevo: la nota se limpia', 'ok/aprobado/v1/contratada',
  pg_temp.aprobar('P1v1', 'Laura') || '/' || pg_temp.pres('P1') || '/' || pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('05 revertir el rechazo de la Etapa 2 no la saca de contratada', 'ok/publicado/era otro/contratada',
  pg_temp.revertir('P2', 'era otro') || '/' || pg_temp.pres('P2') || '/' || pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('05 rechazar la Etapa 2 tampoco', 'ok/contratada', pg_temp.rechazar('P2', 'plazo') || '/' || pg_temp.obra('Belgrano'));

-- ============================================================
-- 06. Publicar en una obra perdida la reabre
-- ============================================================
SELECT pg_temp.caso('06 montaje: perdida', 'ok/ok/perdida/plazo', pg_temp.revertir('P1', 'error') || '/' || pg_temp.rechazar('P1', 'plazo')
  || '/' || pg_temp.obra('Belgrano'));
SELECT pg_temp.alta('P3', 'Belgrano');
SELECT pg_temp.caso('06 un borrador no la mueve', 'perdida/plazo', pg_temp.obra('Belgrano'));
SELECT pg_temp.caso('06 publicado, se reabre', 'ok/en_cotizacion', pg_temp.publicar('P3v1') || '/' || pg_temp.obra('Belgrano'));

-- ============================================================
-- 07. La obra congelada y la contratada a mano
-- ============================================================
UPDATE obras SET congelada = true, congelada_antes = '{}' WHERE id = pg_temp.id('Palermo');
SELECT pg_temp.caso('07 congelada: publicar espera', 'OB018', pg_temp.publicar('P4v1'));
SELECT pg_temp.caso('07 y el presupuesto sigue en borrador', 'borrador', pg_temp.pres('P4'));
UPDATE obras SET congelada = false, congelada_antes = NULL WHERE id = pg_temp.id('Palermo');
SELECT pg_temp.caso('07 contratada a mano, sin aprobado, no se puede', 'PR028/idea',
  pg_temp.mover('Palermo', $s$estado = 'contratada'$s$) || '/' || pg_temp.obra('Palermo'));
ALTER TABLE obras DISABLE TRIGGER presupuestos_obra_estado;
UPDATE obras SET estado = 'contratada' WHERE id = pg_temp.id('Palermo');
ALTER TABLE obras ENABLE TRIGGER presupuestos_obra_estado;
SELECT pg_temp.caso('07 montaje: una contratada de antes, sin presupuesto', 'contratada', pg_temp.obra('Palermo'));
SELECT pg_temp.caso('07 publicar no la saca de contratada', 'ok/contratada', pg_temp.publicar('P4v1') || '/' || pg_temp.obra('Palermo'));
SELECT pg_temp.caso('07 rechazar tampoco', 'ok/contratada', pg_temp.rechazar('P4', 'precio') || '/' || pg_temp.obra('Palermo'));
SELECT pg_temp.caso('07 sin aprobados, a mano sale con su causa', 'ok/idea/no era',
  pg_temp.mover('Palermo', $s$estado = 'idea', estado_nota = 'no era'$s$) || '/' || pg_temp.obra('Palermo'));

-- ============================================================
-- 08. Lo que no se llama ni se escribe desde afuera
-- ============================================================
SELECT pg_temp.caso('08 sin EXECUTE: ' || f, 'false', has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_mover_obra()', 'presupuestos_obra_estado()', 'presupuestos_cerrar_abiertas(uuid)']) AS f;
SELECT pg_temp.caso('08 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_aprobar(uuid)', 'presupuestos_rechazar(uuid,motivo_perdida,text)',
  'presupuestos_revertir(uuid,text)']) AS f;
SELECT pg_temp.caso('08 sin UPDATE de ' || c, 'false', has_column_privilege('authenticated', 'public.presupuestos', c, 'UPDATE')::text)
FROM unnest(ARRAY['estado', 'version_aprobada_id', 'motivo_rechazo', 'estado_nota']) AS c;

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
