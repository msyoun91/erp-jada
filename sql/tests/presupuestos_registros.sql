-- Verificación de sql/185: permisos, configuración, presupuesto, versiones y secciones. NO es una
-- migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok"
-- y los casos que fallan.
--
-- Mundo: equipo Norte (JN jefe, con presupuestos_ver sin armar; Juan vendedor; Vero, que ve obras pero
-- no presupuestos) y Sur (Pedro vendedor; Ana vendedora). Juan es responsable de Belgrano, con Pedro y
-- Vero de participantes. G es gerencia (administra Obras y Presupuestos, configura). T es Técnica: solo
-- Revisión técnica. El montaje escribe como superusuario; todo lo demás, como cada uno. Nombres con `Zqx185`.

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

-- Filas que un UPDATE tocó, como cada uno: RLS no falla, deja 0.
CREATE FUNCTION pg_temp.cambia(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('WITH u AS (%s RETURNING 1) SELECT count(*)::text FROM u', p_sql), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','JN','Vero','Pedro','Ana','G','T','Norte','Sur','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','obras_ver','obras_equipo','obras_todas','obras_administrar','usuarios_delegar','usuarios_equipo',
   'tareas_ver','tareas_equipo','presupuestos_ver','presupuestos_armar','presupuestos_autorizar','presupuestos_administrar',
   'presupuestos_revision','presupuestos_autorizar_tecnica','presupuestos_configuracion');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test185.local', jsonb_build_object('nombre', 'test185 ' || nombre)
FROM ids WHERE nombre IN ('Juan','JN','Vero','Pedro','Ana','G','T');

INSERT INTO equipos (id, nombre)
SELECT id, 'test185 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('Norte','Juan'),('Norte','JN'),('Norte','Vero'),('Sur','Pedro'),('Sur','Ana')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','presupuestos_ver'), ('Pedro','presupuestos_armar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('Vero','contactos_ver'), ('Vero','obras_ver'),
  ('JN','contactos_ver'), ('JN','obras_ver'), ('JN','usuarios_equipo'), ('JN','usuarios_delegar'), ('JN','obras_equipo'),
    ('JN','tareas_ver'), ('JN','tareas_equipo'), ('JN','presupuestos_ver'), ('JN','presupuestos_autorizar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion'),
  ('T','presupuestos_revision'), ('T','presupuestos_autorizar_tecnica')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx185 Torre Belgrano', 'Zqx185 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Pedro'), pg_temp.id('Juan')),
       (pg_temp.id('Belgrano'), pg_temp.id('Vero'), pg_temp.id('Juan'));

-- ============================================================
-- 00. Permisos sembrados
-- ============================================================
SELECT pg_temp.caso('00 delegables: ver, armar, revisión', 'presupuestos_armar,presupuestos_revision,presupuestos_ver', (
  SELECT string_agg(codigo, ',' ORDER BY codigo) FROM submodulos
  WHERE activo AND modulo = 'presupuestos' AND delegable));
SELECT pg_temp.caso('00 siete permisos', '7', (
  SELECT count(*)::text FROM submodulos WHERE activo AND modulo = 'presupuestos'));
SELECT pg_temp.caso('00 ver requiere obras_ver; administrar, obras_administrar',
  'presupuestos_administrar>obras_administrar,presupuestos_ver>obras_ver', (
  SELECT string_agg(a.codigo || '>' || b.codigo, ',' ORDER BY a.codigo) FROM submodulo_reglas x
  JOIN submodulos a ON a.id = x.submodulo_id JOIN submodulos b ON b.id = x.otro_id
  WHERE x.activo AND x.tipo = 'requiere' AND a.modulo = 'presupuestos'));

-- ============================================================
-- 01. Alta: quien trabaja la obra y arma
-- ============================================================
INSERT INTO ids VALUES ('P1', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx185 Ventanas', 'USD_OFICIAL', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('V1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1')));

SELECT pg_temp.caso('01 código P- y borrador', 'true/borrador', (
  SELECT (codigo = 'P-' || lpad(numero::text, greatest(4, length(numero::text)), '0'))::text || '/' || estado
  FROM presupuestos WHERE id = pg_temp.id('P1')));
SELECT pg_temp.caso('01 creado por Juan', 'true', (
  SELECT (creado_por = pg_temp.id('Juan'))::text FROM presupuestos WHERE id = pg_temp.id('P1')));
SELECT pg_temp.caso('01 v1, variante 1, borrador', '1/1/borrador', (
  SELECT numero || '/' || variante || '/' || estado FROM presupuestos_versiones WHERE id = pg_temp.id('V1')));
SELECT pg_temp.caso('01 una sección General en USD oficial al 21', 'General/USD_OFICIAL/21.0', (
  SELECT string_agg(nombre || '/' || moneda || '/' || alicuota, ',') FROM presupuestos_secciones
  WHERE version_id = pg_temp.id('V1')));
INSERT INTO ids VALUES ('P2', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx185 Puertas', 'ARS', 10.5, 'Planta baja')::text$s$, pg_temp.id('Belgrano')), 'Pedro')::uuid);
SELECT pg_temp.caso('01 Pedro (participante) arma', 'true', (SELECT (pg_temp.id('P2') IS NOT NULL)::text));
SELECT pg_temp.caso('01 el número sigue', 'true', (
  SELECT (b.numero > a.numero)::text FROM presupuestos a, presupuestos b
  WHERE a.id = pg_temp.id('P1') AND b.id = pg_temp.id('P2')));
SELECT pg_temp.caso('01 Ana (no trabaja la obra) no', '42501', pg_temp.intentar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx185 X', 'ARS', 21)$s$, pg_temp.id('Belgrano')), 'Ana'));
SELECT pg_temp.caso('01 JN (jefe, sin armar) no', '42501', pg_temp.intentar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx185 X', 'ARS', 21)$s$, pg_temp.id('Belgrano')), 'JN'));
SELECT pg_temp.caso('01 Vero (sin presupuestos_ver) no', '42501', pg_temp.intentar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx185 X', 'ARS', 21)$s$, pg_temp.id('Belgrano')), 'Vero'));
SELECT pg_temp.caso('01 T no', '42501', pg_temp.intentar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx185 X', 'ARS', 21)$s$, pg_temp.id('Belgrano')), 'T'));
SELECT pg_temp.caso('01 alícuota 15 no', '23514', pg_temp.intentar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx185 X', 'ARS', 15)$s$, pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('01 sin nombre no', '23514', pg_temp.intentar(format(
  $s$SELECT presupuestos_alta(%L, '  ', 'ARS', 21)$s$, pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('01 el número no se escribe', '42501', pg_temp.intentar(format(
  $s$INSERT INTO presupuestos (nombre, obra_id, numero) VALUES ('Zqx185 X', %L, 1)$s$, pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('01 eventos alta y estado', 'alta,estado', (
  SELECT string_agg(evento::text, ',' ORDER BY created_at) FROM eventos
  WHERE ente = 'presupuesto' AND registro_id = pg_temp.id('P1')));

-- ============================================================
-- 02. Quién ve
-- ============================================================
SELECT pg_temp.caso('02 Juan ve los dos', '2', pg_temp.ve(format(
  'SELECT 1 FROM presupuestos WHERE obra_id = %L', pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('02 JN (jefe del equipo de la obra) ve', '2', pg_temp.ve(format(
  'SELECT 1 FROM presupuestos WHERE obra_id = %L', pg_temp.id('Belgrano')), 'JN'));
SELECT pg_temp.caso('02 G ve', '2', pg_temp.ve(format(
  'SELECT 1 FROM presupuestos WHERE obra_id = %L', pg_temp.id('Belgrano')), 'G'));
SELECT pg_temp.caso('02 Ana no ve', '0', pg_temp.ve(format(
  'SELECT 1 FROM presupuestos WHERE obra_id = %L', pg_temp.id('Belgrano')), 'Ana'));
SELECT pg_temp.caso('02 Vero (ve la obra, sin presupuestos_ver) no ve', '0', pg_temp.ve(format(
  'SELECT 1 FROM presupuestos WHERE obra_id = %L', pg_temp.id('Belgrano')), 'Vero'));
SELECT pg_temp.caso('02 T no ve', '0', pg_temp.ve(format(
  'SELECT 1 FROM presupuestos WHERE obra_id = %L', pg_temp.id('Belgrano')), 'T'));
SELECT pg_temp.caso('02 Ana no ve versiones ni secciones', '0/0',
  pg_temp.ve(format('SELECT 1 FROM presupuestos_versiones WHERE presupuesto_id = %L', pg_temp.id('P1')), 'Ana') || '/' ||
  pg_temp.ve(format('SELECT 1 FROM presupuestos_secciones WHERE version_id = %L', pg_temp.id('V1')), 'Ana'));
SELECT pg_temp.caso('02 Pedro ve versión y sección', '1/1',
  pg_temp.ve(format('SELECT 1 FROM presupuestos_versiones WHERE presupuesto_id = %L', pg_temp.id('P1')), 'Pedro') || '/' ||
  pg_temp.ve(format('SELECT 1 FROM presupuestos_secciones WHERE version_id = %L', pg_temp.id('V1')), 'Pedro'));
SELECT pg_temp.caso('02 etiqueta para Juan', 'true', pg_temp.consultar(format(
  $s$SELECT (etiqueta_registro('presupuesto', %L) LIKE 'P-%% · Zqx185 Ventanas')::text$s$, pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('02 sin etiqueta para Ana', NULL, pg_temp.consultar(format(
  $s$SELECT etiqueta_registro('presupuesto', %L)$s$, pg_temp.id('P1')), 'Ana'));
SELECT pg_temp.caso('02 Ana no ve sus eventos', '0', pg_temp.ve(format(
  $s$SELECT 1 FROM eventos WHERE ente = 'presupuesto' AND registro_id = %L$s$, pg_temp.id('P1')), 'Ana'));
SELECT pg_temp.caso('02 buscar: Juan 2, Ana 0', '2/0',
  pg_temp.ve($s$SELECT 1 FROM buscar_registros('presupuestos', 'zqx185')$s$, 'Juan') || '/' ||
  pg_temp.ve($s$SELECT 1 FROM buscar_registros('presupuestos', 'zqx185')$s$, 'Ana'));
SELECT pg_temp.caso('02 buscar por código', '1', pg_temp.ve(format(
  $s$SELECT 1 FROM buscar_registros('presupuestos', %L) WHERE registro_id = %L$s$,
  (SELECT codigo FROM presupuestos WHERE id = pg_temp.id('P1')), pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('02 puede abrir: JN sí, Ana no', 'true/false',
  puede_abrir_registro('presupuesto', pg_temp.id('P1'), pg_temp.id('JN'))::text || '/' ||
  puede_abrir_registro('presupuesto', pg_temp.id('P1'), pg_temp.id('Ana'))::text);

-- ============================================================
-- 03. El borrador se edita
-- ============================================================
SELECT pg_temp.caso('03 Juan renombra', '1', pg_temp.cambia(format(
  $s$UPDATE presupuestos SET nombre = 'Zqx185 Ventanas torre' WHERE id = %L$s$, pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('03 JN no', '0', pg_temp.cambia(format(
  $s$UPDATE presupuestos SET nombre = 'Zqx185 JN' WHERE id = %L$s$, pg_temp.id('P1')), 'JN'));
SELECT pg_temp.caso('03 la obra no cambia', '42501', pg_temp.intentar(format(
  'UPDATE presupuestos SET obra_id = obra_id WHERE id = %L', pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('03 el estado no se escribe', '42501', pg_temp.intentar(format(
  $s$UPDATE presupuestos SET estado = 'aprobado' WHERE id = %L$s$, pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('03 Juan suma Colocación en pesos al 10,5', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO presupuestos_secciones (version_id, nombre, moneda, alicuota, orden) VALUES (%L, 'Colocación', 'ARS', 10.5, 1)$s$,
  pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('03 nombre repetido no', '23505', pg_temp.intentar(format(
  $s$INSERT INTO presupuestos_secciones (version_id, nombre, moneda, alicuota) VALUES (%L, ' colocación ', 'ARS', 21)$s$,
  pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('03 Ana no suma', '42501', pg_temp.intentar(format(
  $s$INSERT INTO presupuestos_secciones (version_id, nombre, moneda, alicuota) VALUES (%L, 'Ana', 'ARS', 21)$s$,
  pg_temp.id('V1')), 'Ana'));
SELECT pg_temp.caso('03 todas al 10,5 de una vez', '2', pg_temp.cambia(format(
  'UPDATE presupuestos_secciones SET alicuota = 10.5 WHERE version_id = %L', pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('03 nombre de variante e IVA incluido', '1', pg_temp.cambia(format(
  $s$UPDATE presupuestos_versiones SET variante_nombre = 'Aluminio', iva_discriminado = false WHERE id = %L$s$,
  pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('03 el estado de la versión no se escribe', '42501', pg_temp.intentar(format(
  $s$UPDATE presupuestos_versiones SET estado = 'publicado' WHERE id = %L$s$, pg_temp.id('V1')), 'Juan'));

-- ============================================================
-- 04. Versiones: variantes, descartar
-- ============================================================
SELECT pg_temp.caso('04 Juan suma la variante 2', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO presupuestos_versiones (presupuesto_id, variante, variante_nombre) VALUES (%L, 2, 'PVC')$s$,
  pg_temp.id('P1')), 'Juan'));
INSERT INTO ids VALUES ('V2', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1') AND variante = 2));
SELECT pg_temp.caso('04 es la v2', '2', (SELECT numero::text FROM presupuestos_versiones WHERE id = pg_temp.id('V2')));
SELECT pg_temp.caso('04 la variante 4 no sigue', 'PR004', pg_temp.intentar(format(
  'INSERT INTO presupuestos_versiones (presupuesto_id, variante) VALUES (%L, 4)', pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('04 otra abierta de la variante 1, no', '23505', pg_temp.intentar(format(
  'INSERT INTO presupuestos_versiones (presupuesto_id, variante) VALUES (%L, 1)', pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('04 Ana no suma versiones', '42501', pg_temp.intentar(format(
  'INSERT INTO presupuestos_versiones (presupuesto_id, variante) VALUES (%L, 3)', pg_temp.id('P1')), 'Ana'));
SELECT pg_temp.caso('04 Juan descarta la v2', '1', pg_temp.cambia(format(
  'UPDATE presupuestos_versiones SET activo = false WHERE id = %L', pg_temp.id('V2')), 'Juan'));
SELECT pg_temp.caso('04 la descartada no vuelve', 'PR002', pg_temp.intentar(format(
  'UPDATE presupuestos_versiones SET activo = true WHERE id = %L', pg_temp.id('V2')), 'Juan'));
SELECT pg_temp.caso('04 en la descartada no se suman secciones', 'PR005', pg_temp.intentar(format(
  $s$INSERT INTO presupuestos_secciones (version_id, nombre, moneda, alicuota) VALUES (%L, 'X', 'ARS', 21)$s$,
  pg_temp.id('V2')), 'Juan'));
SELECT pg_temp.caso('04 la única versión no se descarta', 'PR006', pg_temp.intentar(format(
  'UPDATE presupuestos_versiones SET activo = false WHERE id = %L', pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('04 otra de la variante 2', 'ok', pg_temp.intentar(format(
  'INSERT INTO presupuestos_versiones (presupuesto_id, variante) VALUES (%L, 2)', pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('04 cuenta la descartada: es la v3', '3', (
  SELECT max(numero)::text FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1')));

-- Lo que el ciclo hará en el tramo 3: acá, a mano.
UPDATE presupuestos_versiones SET estado = 'publicado' WHERE id = pg_temp.id('V1');
UPDATE presupuestos SET estado = 'publicado' WHERE id = pg_temp.id('P1');

SELECT pg_temp.caso('04 publicada: el nombre no cambia', 'PR005', pg_temp.intentar(format(
  $s$UPDATE presupuestos_versiones SET variante_nombre = 'Otro' WHERE id = %L$s$, pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('04 publicada: sus secciones tampoco', 'PR005', pg_temp.intentar(format(
  'UPDATE presupuestos_secciones SET alicuota = 21 WHERE version_id = %L', pg_temp.id('V1')), 'Juan'));
SELECT pg_temp.caso('04 publicada: no se descarta', 'PR005', pg_temp.intentar(format(
  'UPDATE presupuestos_versiones SET activo = false WHERE id = %L', pg_temp.id('V1')), 'Juan'));

-- ============================================================
-- 05. Desactivar el presupuesto y la obra
-- ============================================================
SELECT pg_temp.caso('05 publicado no se desactiva', 'PR001', pg_temp.intentar(format(
  'UPDATE presupuestos SET activo = false WHERE id = %L', pg_temp.id('P1')), 'Juan'));
SELECT pg_temp.caso('05 la obra con presupuestos no se desactiva', 'PR007', pg_temp.intentar(format(
  'SELECT obras_desactivar(%L)', pg_temp.id('Belgrano')), 'Juan'));
SELECT pg_temp.caso('05 Pedro desactiva su borrador', '1', pg_temp.cambia(format(
  'UPDATE presupuestos SET activo = false WHERE id = %L', pg_temp.id('P2')), 'Pedro'));
SELECT pg_temp.caso('05 evento baja', '1', (
  SELECT count(*)::text FROM eventos WHERE ente = 'presupuesto' AND registro_id = pg_temp.id('P2') AND evento = 'baja'));
SELECT pg_temp.caso('05 desactivado no se renombra', '0', pg_temp.cambia(format(
  $s$UPDATE presupuestos SET nombre = 'Zqx185 Y' WHERE id = %L$s$, pg_temp.id('P2')), 'G'));
-- 42501 y no PR003: el FOR UPDATE del trigger ya no lo encuentra (la policy de UPDATE pide activo).
SELECT pg_temp.caso('05 desactivado no admite versiones', '42501', pg_temp.intentar(format(
  'INSERT INTO presupuestos_versiones (presupuesto_id, variante) VALUES (%L, 2)', pg_temp.id('P2')), 'G'));
SELECT pg_temp.caso('05 Pedro sigue viéndolo', '1', pg_temp.ve(format(
  'SELECT 1 FROM presupuestos WHERE id = %L', pg_temp.id('P2')), 'Pedro'));
SELECT pg_temp.caso('05 su número sigue tomado', '1', (
  SELECT count(*)::text FROM presupuestos a, presupuestos b
  WHERE a.id = pg_temp.id('P2') AND b.id = pg_temp.id('P1') AND a.numero <> b.numero AND a.codigo <> b.codigo));

UPDATE presupuestos SET estado = 'aprobado' WHERE id = pg_temp.id('P1');
SELECT pg_temp.caso('05 aprobado no admite versiones', 'PR003', pg_temp.intentar(format(
  'INSERT INTO presupuestos_versiones (presupuesto_id, variante) VALUES (%L, 3)', pg_temp.id('P1')), 'Juan'));

-- ============================================================
-- 06. Configuración
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;
SELECT pg_temp.caso('06 G configura 5 % y 15 días', 'ok', pg_temp.intentar(
  'SELECT presupuestos_configurar(5, 15)', 'G'));
SELECT pg_temp.caso('06 Juan no', '42501', pg_temp.intentar('SELECT presupuestos_configurar(50, 90)', 'Juan'));
SELECT pg_temp.caso('06 Juan no inserta directo', '42501', pg_temp.intentar(
  'INSERT INTO presupuestos_configuracion (tope_descuento, plazo_dias) VALUES (50, 90)', 'Juan'));
SELECT pg_temp.caso('06 tope 150 no', '23514', pg_temp.intentar('SELECT presupuestos_configurar(150, 15)', 'G'));
SELECT pg_temp.caso('06 G la cambia a 7 % y 20 días', 'ok', pg_temp.intentar(
  'SELECT presupuestos_configurar(7, 20)', 'G'));
SELECT pg_temp.caso('06 una vigente, la nueva', '7.00/20', (
  SELECT string_agg(tope_descuento || '/' || plazo_dias, ',') FROM presupuestos_configuracion WHERE activo));
SELECT pg_temp.caso('06 la anterior queda de historial', 'true', (
  SELECT (count(*) >= 2)::text FROM presupuestos_configuracion WHERE creado_por = pg_temp.id('G')));
SELECT pg_temp.caso('06 Juan lee la vigente; T no', '1/0',
  pg_temp.ve('SELECT 1 FROM presupuestos_configuracion WHERE activo', 'Juan') || '/' ||
  pg_temp.ve('SELECT 1 FROM presupuestos_configuracion WHERE activo', 'T'));
SELECT pg_temp.caso('06 la anterior no vuelve', 'PR002', pg_temp.intentar(format(
  'UPDATE presupuestos_configuracion SET activo = true WHERE NOT activo AND creado_por = %L', pg_temp.id('G')), 'G'));

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
