-- Verificación de sql/153: pasos que se completan solos. NO es una migración:
-- todo corre dentro de una transacción que termina en ROLLBACK.
--
-- Mundo, los dos independientes, con Tareas, Plantillas, Obras y Contactos:
-- V (dueño de las obras, con tareas_pedir) y W. Plantillas de V sobre obra,
-- sin disparo: P (1 "vincular arquitecto" → 2 "pasar a en_cotizacion", en
-- cadena; 3 "vincular decisor", pedido a W; 4 sin condición), PB (A manual →
-- B "vincular arquitecto") y PR (un paso "vincular arquitecto").

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

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text DEFAULT NULL, p_guardar text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_id uuid;
BEGIN
  IF p_como IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
    PERFORM set_config('role', 'authenticated', true);
  END IF;
  IF p_guardar IS NULL THEN
    EXECUTE p_sql;
  ELSE
    EXECUTE p_sql INTO v_id;
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF p_guardar IS NOT NULL THEN
    INSERT INTO ids VALUES (p_guardar, v_id) ON CONFLICT (nombre) DO UPDATE SET id = EXCLUDED.id;
  END IF;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  RETURN SQLSTATE || ' ' || SQLERRM;
END;
$f$;

CREATE FUNCTION pg_temp.guardar(p_plantilla text, p_pasos jsonb) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT guardar_plantilla(NULL, %L, NULL, %L, ''obra'', NULL, NULL, false)',
    'Zqx153 ' || p_plantilla, p_pasos), 'V', p_plantilla);
$f$;

CREATE FUNCTION pg_temp.usar(p_plantilla text, p_obra text, p_hilo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT usar_plantilla(%L, NULL, NULL, ''{}'', %L)',
    pg_temp.id(p_plantilla), pg_temp.id(p_obra)), 'V', p_hilo);
$f$;

-- Estado de los pasos del hilo, en orden: "título:estado".
CREATE FUNCTION pg_temp.pasos(p_hilo text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(titulo || ':' || estado, ' ' ORDER BY created_at)
  FROM tareas WHERE hilo_id = pg_temp.id(p_hilo) AND activo;
$f$;

CREATE FUNCTION pg_temp.paso(p_hilo text, p_titulo text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM tareas WHERE hilo_id = pg_temp.id(p_hilo) AND titulo = p_titulo AND activo;
$f$;

CREATE FUNCTION pg_temp.vincular(p_persona text, p_obra text, p_rol text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    $s$INSERT INTO contactos_vinculos (persona_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, %L)$s$,
    pg_temp.id(p_persona), pg_temp.id(p_obra), ARRAY[p_rol]), 'V');
$f$;

CREATE FUNCTION pg_temp.avisos(p_usuario text, p_tipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT count(*) || ':' || coalesce(string_agg(DISTINCT coalesce(i.nombre, '-'), ','), '')
  FROM usuario_notificaciones n LEFT JOIN ids i ON i.id = n.actor_id
  WHERE n.usuario_id = pg_temp.id(p_usuario) AND n.tipo::text = p_tipo AND n.activo;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['V','W','Belgrano','Caseros','Laura','Marta','Hugo']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('tareas_ver','tareas_plantillas','tareas_pedir','obras_ver','obras_crear','obras_aprobar','contactos_ver',
   'contactos_crear');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test153.local', jsonb_build_object('nombre', 'test153 ' || nombre)
FROM ids WHERE nombre IN ('V','W');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM unnest(ARRAY['V','W']) AS u,
     unnest(ARRAY['tareas_ver','tareas_plantillas','obras_ver','obras_crear','obras_aprobar',
                  'contactos_ver','contactos_crear']) AS s
WHERE pg_temp.id(s) IS NOT NULL;
INSERT INTO usuario_submodulos (usuario_id, submodulo_id) VALUES (pg_temp.id('V'), pg_temp.id('tareas_pedir'));
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO contactos_personas (id, nombre, responsable_id, creado_por)
SELECT pg_temp.id(n), 'Zqx153 ' || n || ' ' || left(pg_temp.id(n)::text, 8), pg_temp.id('V'), pg_temp.id('V')
FROM unnest(ARRAY['Laura','Marta','Hugo']) AS n;

SELECT pg_temp.caso('00 V crea Belgrano', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Zqx153 Belgrano', 'Calle 1', 'otro', 'casa')$s$,
  pg_temp.id('Belgrano')), 'V'));
SELECT pg_temp.caso('00 V crea Caseros', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Zqx153 Caseros', 'Calle 2', 'otro', 'casa')$s$,
  pg_temp.id('Caseros')), 'V'));

SELECT pg_temp.caso('00 V guarda P', 'ok', pg_temp.guardar('P', jsonb_build_array(
  jsonb_build_object('titulo', 'Arq', 'completa_evento', 'relacion_alta', 'completa_valor', 'arquitecto',
                     'espera_anterior', false),
  jsonb_build_object('titulo', 'Cot', 'completa_evento', 'estado', 'completa_valor', 'en_cotizacion'),
  jsonb_build_object('titulo', 'Dec', 'completa_evento', 'relacion_alta', 'completa_valor', 'decisor',
                     'asignado_id', pg_temp.id('W'), 'espera_anterior', false),
  jsonb_build_object('titulo', 'Suelto', 'espera_anterior', false))));
SELECT pg_temp.caso('00 V guarda PB', 'ok', pg_temp.guardar('PB', jsonb_build_array(
  jsonb_build_object('titulo', 'A', 'espera_anterior', false),
  jsonb_build_object('titulo', 'B', 'completa_evento', 'relacion_alta', 'completa_valor', 'arquitecto'))));
SELECT pg_temp.caso('00 V guarda PR', 'ok', pg_temp.guardar('PR', jsonb_build_array(
  jsonb_build_object('titulo', 'R', 'completa_evento', 'relacion_alta', 'completa_valor', 'arquitecto',
                     'espera_anterior', false))));

-- ============================================================
-- 01. Usarla copia la condición al paso
-- ============================================================
SELECT pg_temp.caso('01 V usa P sobre Belgrano', 'ok', pg_temp.usar('P', 'Belgrano', 'H1'));
SELECT pg_temp.caso('01 nada se completa: la obra no cumple', 'Arq:pendiente Cot:pendiente Dec:solicitada Suelto:pendiente',
  pg_temp.pasos('H1'));
SELECT pg_temp.caso('01 la condición, copiada', 'relacion_alta:arquitecto estado:en_cotizacion relacion_alta:decisor -',
  (SELECT string_agg(coalesce(completa_evento || ':' || completa_valor, '-'), ' ' ORDER BY created_at)
   FROM tareas WHERE hilo_id = pg_temp.id('H1')));
SELECT pg_temp.caso('01 authenticated no la escribe', '42501', left(pg_temp.intentar(format(
  $s$UPDATE tareas SET completa_valor = 'cliente' WHERE id = %L$s$, pg_temp.paso('H1', 'Arq')), 'V'), 5));

-- ============================================================
-- 02. El evento: vincular un arquitecto
-- ============================================================
SELECT pg_temp.caso('02 V vincula a Laura de arquitecta', 'ok', pg_temp.vincular('Laura', 'Belgrano', 'arquitecto'));
SELECT pg_temp.caso('02 Arq se completa; Cot se habilita pero la obra sigue en idea',
  'Arq:completada Cot:pendiente Dec:solicitada Suelto:pendiente', pg_temp.pasos('H1'));
SELECT pg_temp.caso('02 sin resultado: la pantalla muestra la condición', NULL,
  (SELECT resultado FROM tareas WHERE id = pg_temp.paso('H1', 'Arq')));
SELECT pg_temp.caso('02 actuó V, el responsable: sin "paso completado"', '0:', pg_temp.avisos('V', 'paso_completado'));

-- ============================================================
-- 03. El evento: pasar de estado
-- ============================================================
SELECT pg_temp.caso('03 V la pasa a en_busqueda', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_busqueda' WHERE id = %L$s$, pg_temp.id('Belgrano')), 'V'));
SELECT pg_temp.caso('03 otro estado no la completa', 'pendiente',
  (SELECT estado::text FROM tareas WHERE id = pg_temp.paso('H1', 'Cot')));
SELECT pg_temp.caso('03 V la pasa a en_cotizacion', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_cotizacion' WHERE id = %L$s$, pg_temp.id('Belgrano')), 'V'));
SELECT pg_temp.caso('03 Cot se completa', 'completada',
  (SELECT estado::text FROM tareas WHERE id = pg_temp.paso('H1', 'Cot')));

-- ============================================================
-- 04. Un pedido sin aceptar no se completa; al aceptarlo, sí
-- ============================================================
SELECT pg_temp.caso('04 V vincula a Marta de decisora', 'ok', pg_temp.vincular('Marta', 'Belgrano', 'decisor'));
SELECT pg_temp.caso('04 Dec sigue solicitada', 'solicitada',
  (SELECT estado::text FROM tareas WHERE id = pg_temp.paso('H1', 'Dec')));
SELECT pg_temp.caso('04 W acepta', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas SET estado = 'pendiente' WHERE id = %L$s$, pg_temp.paso('H1', 'Dec')), 'W'));
SELECT pg_temp.caso('04 al aceptarlo, se completa', 'completada',
  (SELECT estado::text FROM tareas WHERE id = pg_temp.paso('H1', 'Dec')));
SELECT pg_temp.caso('04 V: "paso completado", de W', '1:W', pg_temp.avisos('V', 'paso_completado'));
SELECT pg_temp.caso('04 Suelto no se toca', 'pendiente',
  (SELECT estado::text FROM tareas WHERE id = pg_temp.paso('H1', 'Suelto')));

-- ============================================================
-- 05. Reabrir no vuelve a completarlo
-- ============================================================
SELECT pg_temp.caso('05 W reabre Dec', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas SET estado = 'pendiente' WHERE id = %L$s$, pg_temp.paso('H1', 'Dec')), 'W'));
SELECT pg_temp.caso('05 queda abierto aunque la obra tenga decisor', 'pendiente',
  (SELECT estado::text FROM tareas WHERE id = pg_temp.paso('H1', 'Dec')));
SELECT pg_temp.caso('05 W lo completa a mano igual', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas SET estado = 'completada' WHERE id = %L$s$, pg_temp.paso('H1', 'Dec')), 'W'));

-- ============================================================
-- 06. Bloqueado al llegar el evento: se evalúa al habilitarse
-- ============================================================
SELECT pg_temp.caso('06 V usa PB sobre Caseros', 'ok', pg_temp.usar('PB', 'Caseros', 'H2'));
SELECT pg_temp.caso('06 V vincula a Hugo de arquitecto en Caseros', 'ok', pg_temp.vincular('Hugo', 'Caseros', 'arquitecto'));
SELECT pg_temp.caso('06 B, bloqueado, no se completa', 'A:pendiente B:pendiente', pg_temp.pasos('H2'));
SELECT pg_temp.caso('06 V completa A', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas SET estado = 'completada' WHERE id = %L$s$, pg_temp.paso('H2', 'A')), 'V'));
SELECT pg_temp.caso('06 al habilitarse, B se completa', 'A:completada B:completada', pg_temp.pasos('H2'));

-- ============================================================
-- 07. Al nacer: la obra ya cumple
-- ============================================================
SELECT pg_temp.caso('07 V usa P otra vez sobre Belgrano', 'ok', pg_temp.usar('P', 'Belgrano', 'H3'));
SELECT pg_temp.caso('07 Arq y Cot nacen completados; el pedido espera',
  'Arq:completada Cot:completada Dec:solicitada Suelto:pendiente', pg_temp.pasos('H3'));

-- ============================================================
-- 08. Sumada a un hilo sin registro, sin condición
-- ============================================================
INSERT INTO ids VALUES ('H4', gen_random_uuid());
SELECT pg_temp.caso('08 V crea un hilo suelto', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO tareas_hilos (id, titulo, responsable_id) VALUES (%L, 'Zqx153 suelto', %L)$s$,
  pg_temp.id('H4'), pg_temp.id('V')), 'V'));
SELECT pg_temp.caso('08 V le suma PR con Belgrano', 'ok', pg_temp.intentar(format(
  'SELECT usar_plantilla(%L, NULL, %L, ''{}'', %L)', pg_temp.id('PR'), pg_temp.id('H4'), pg_temp.id('Belgrano')), 'V'));
SELECT pg_temp.caso('08 R sin condición y abierto', 'R:pendiente:-',
  (SELECT titulo || ':' || estado || ':' || coalesce(completa_evento::text, '-') FROM tareas WHERE hilo_id = pg_temp.id('H4')));

-- ============================================================
-- 09. La recurrencia copia la condición
-- ============================================================
SELECT pg_temp.caso('09 V usa PR sobre Belgrano: nace completado', 'ok', pg_temp.usar('PR', 'Belgrano', 'H5'));
SELECT pg_temp.caso('09 R completado', 'R:completada', pg_temp.pasos('H5'));
SELECT pg_temp.caso('09 V lo hace mensual', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas_hilos SET recurrencia_cantidad = 1, recurrencia_unidad = 'mes' WHERE id = %L$s$,
  pg_temp.id('H5')), 'V'));
SELECT pg_temp.caso('09 V lo cierra', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas_hilos SET estado = 'cerrado' WHERE id = %L$s$, pg_temp.id('H5')), 'V'));
SELECT pg_temp.caso('09 el siguiente, sobre Belgrano, con la condición y ya completado',
  'relacion_alta:arquitecto:completada:true',
  (SELECT t.completa_evento || ':' || t.completa_valor || ':' || t.estado || ':' || (h.registro_id = pg_temp.id('Belgrano'))
   FROM tareas_hilos h JOIN tareas t ON t.hilo_id = h.id WHERE h.recurrencia_de = pg_temp.id('H5')));

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
