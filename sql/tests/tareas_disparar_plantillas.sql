-- Verificación de sql/152: `disparar_plantillas` y sus dos avisos. NO es una
-- migración: todo corre dentro de una transacción que termina en ROLLBACK.
--
-- Mundo, todos independientes, con Tareas, Plantillas y Obras: V (dueño de
-- las obras) y W (participante de Belgrano, que la mueve). Las plantillas de V
-- sobre obra: PA (alta, con un paso fijo a W, que es pedido), PE (estado
-- `en_cotizacion`, con un paso fijo a W), PApagada y PF (alta; un trigger del
-- test hace fallar su hilo). PW es de W, con el mismo disparo que PE. Los
-- avisos se cuentan por los usuarios del montaje y son acumulados.

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

-- Corre p_sql como p_como (sin p_como, como está); 'ok' o el SQLSTATE. Con
-- p_guardar, el uuid que devuelve queda en ids con ese nombre.
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
  RETURN SQLSTATE;
END;
$f$;

-- El texto que devuelve p_sql, leído como p_como.
CREATE FUNCTION pg_temp.leer(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql INTO v;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  RETURN SQLSTATE;
END;
$f$;

-- guardar_plantilla sobre obra como p_como; `p_plantilla` es la clave en ids.
CREATE FUNCTION pg_temp.guardar(p_plantilla text, p_como text, p_pasos jsonb, p_evento text, p_estado text,
                                p_activo boolean)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT guardar_plantilla(NULL, %L, NULL, %L, ''obra'', %L, %L, %L)',
    'Zqx152 ' || p_plantilla, p_pasos, p_evento, p_estado, p_activo), p_como, p_plantilla);
$f$;

-- Avisos de p_usuario de un tipo: cuántos y de qué actores ('-' sin actor).
CREATE FUNCTION pg_temp.avisos(p_usuario text, p_tipo text) RETURNS text LANGUAGE sql AS $f$
  SELECT count(*) || ':' || coalesce(string_agg(DISTINCT coalesce(i.nombre, '-'), ','), '')
  FROM usuario_notificaciones n LEFT JOIN ids i ON i.id = n.actor_id
  WHERE n.usuario_id = pg_temp.id(p_usuario) AND n.tipo::text = p_tipo AND n.activo;
$f$;

-- Hilos activos de la plantilla sobre la obra.
CREATE FUNCTION pg_temp.hilos(p_plantilla text, p_obra text) RETURNS text LANGUAGE sql AS $f$
  SELECT count(*)::text FROM tareas_hilos
  WHERE plantilla_id = pg_temp.id(p_plantilla) AND registro_id = pg_temp.id(p_obra) AND activo;
$f$;

CREATE FUNCTION pg_temp.hilo(p_plantilla text, p_obra text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM tareas_hilos
  WHERE plantilla_id = pg_temp.id(p_plantilla) AND registro_id = pg_temp.id(p_obra) AND activo
  ORDER BY created_at DESC LIMIT 1;
$f$;

-- El hilo de PF no se inserta: lo inesperado del disparo.
CREATE FUNCTION pg_temp.fallar() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  IF NEW.titulo = 'Zqx152 PF' THEN
    RAISE EXCEPTION 'falla del test';
  END IF;
  RETURN NEW;
END;
$f$;
CREATE TRIGGER zqx152_fallar BEFORE INSERT ON tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar();

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['V','W','Belgrano','Caseros']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('tareas_ver','tareas_plantillas','tareas_pedir','obras_ver','obras_crear','obras_aprobar','contactos_ver');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test152.local', jsonb_build_object('nombre', 'test152 ' || nombre)
FROM ids WHERE nombre IN ('V','W');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM unnest(ARRAY['V','W']) AS u,
     unnest(ARRAY['tareas_ver','tareas_plantillas','obras_ver','obras_crear','obras_aprobar',
                  'contactos_ver']) AS s;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 V guarda PA', 'ok', pg_temp.guardar('PA', 'V',
  jsonb_build_array(jsonb_build_object('titulo', 'Medir {nombre}'),
                    jsonb_build_object('titulo', 'Coordinar', 'asignado_id', pg_temp.id('W'), 'espera_anterior', false)),
  'alta', NULL, true));
SELECT pg_temp.caso('00 V guarda PE', 'ok', pg_temp.guardar('PE', 'V',
  jsonb_build_array(jsonb_build_object('titulo', 'Cotizar'),
                    jsonb_build_object('titulo', 'Revisar', 'asignado_id', pg_temp.id('W'), 'espera_anterior', false)),
  'estado', 'en_cotizacion', true));
SELECT pg_temp.caso('00 V guarda PApagada', 'ok',
  pg_temp.guardar('PApagada', 'V', '[{"titulo":"x"}]', 'alta', NULL, false));
SELECT pg_temp.caso('00 V guarda PF', 'ok', pg_temp.guardar('PF', 'V', '[{"titulo":"x"}]', 'alta', NULL, true));
SELECT pg_temp.caso('00 W guarda PW', 'ok',
  pg_temp.guardar('PW', 'W', '[{"titulo":"w"}]', 'estado', 'en_cotizacion', true));

-- ============================================================
-- 01. Alta: V crea Belgrano
-- ============================================================
SELECT pg_temp.caso('01 la obra se crea aunque PF falle', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Zqx152 Belgrano', 'Calle 1', 'otro', 'casa')$s$,
  pg_temp.id('Belgrano')), 'V'));
SELECT pg_temp.caso('01 PA corrió una vez', '1', pg_temp.hilos('PA', 'Belgrano'));
SELECT pg_temp.caso('01 el hilo es de V', 'true',
  (SELECT (responsable_id = pg_temp.id('V'))::text FROM tareas_hilos WHERE id = pg_temp.hilo('PA', 'Belgrano')));
SELECT pg_temp.caso('01 {nombre} resuelto', 'Medir Zqx152 Belgrano',
  (SELECT titulo FROM tareas WHERE hilo_id = pg_temp.hilo('PA', 'Belgrano') AND titulo LIKE 'Medir%'));
SELECT pg_temp.caso('01 el pedido sin tareas_pedir queda en V', 'true',
  (SELECT (asignado_id = pg_temp.id('V'))::text FROM tareas
   WHERE hilo_id = pg_temp.hilo('PA', 'Belgrano') AND titulo = 'Coordinar'));
SELECT pg_temp.caso('01 PApagada no corrió', '0', pg_temp.hilos('PApagada', 'Belgrano'));
SELECT pg_temp.caso('01 PE no corrió: nace en idea', '0', pg_temp.hilos('PE', 'Belgrano'));
SELECT pg_temp.caso('01 PF no dejó hilo', '0', pg_temp.hilos('PF', 'Belgrano'));
SELECT pg_temp.caso('01 actuó V: sin "plantilla disparada"', '0:', pg_temp.avisos('V', 'plantilla_disparada'));
SELECT pg_temp.caso('01 sus pasos no le avisan', '0:', pg_temp.avisos('V', 'tarea_asignada'));
SELECT pg_temp.caso('01 ni "paso sumado"', '0:', pg_temp.avisos('V', 'paso_sumado'));
SELECT pg_temp.caso('01 "paso a reasignar" por Coordinar', '1:-', pg_temp.avisos('V', 'paso_a_reasignar'));
SELECT pg_temp.caso('01 "plantilla fallida", sin actor', '1:-', pg_temp.avisos('V', 'plantilla_fallida'));
SELECT pg_temp.caso('01 la campanita de V: la fallida → PF', 'Zqx152 PF:plantillas:true', pg_temp.leer(format(
  $s$SELECT etiqueta || ':' || destino || ':' || (destino_id = %L) FROM notificaciones_listar()
     WHERE tipo = 'plantilla_fallida'$s$, pg_temp.id('PF')), 'V'));

-- ============================================================
-- 02. Estado: W, participante, la pasa a en_cotizacion
-- ============================================================
SELECT pg_temp.caso('02 V suma a W', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras_participantes (obra_id, usuario_id) VALUES (%L, %L)$s$,
  pg_temp.id('Belgrano'), pg_temp.id('W')), 'V'));
INSERT INTO usuario_submodulos (usuario_id, submodulo_id) VALUES (pg_temp.id('V'), pg_temp.id('tareas_pedir'));
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('02 W la pasa a en_cotizacion', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_cotizacion' WHERE id = %L$s$, pg_temp.id('Belgrano')), 'W'));
SELECT pg_temp.caso('02 PE corrió', '1', pg_temp.hilos('PE', 'Belgrano'));
SELECT pg_temp.caso('02 el hilo es de V, no de quien actuó', 'true',
  (SELECT (responsable_id = pg_temp.id('V'))::text FROM tareas_hilos WHERE id = pg_temp.hilo('PE', 'Belgrano')));
SELECT pg_temp.caso('02 PW no: la obra no es de W', '0', pg_temp.hilos('PW', 'Belgrano'));
SELECT pg_temp.caso('02 V recibe "plantilla disparada" de W', '1:W', pg_temp.avisos('V', 'plantilla_disparada'));
SELECT pg_temp.caso('02 Revisar es un pedido a W, aunque lo movió W', 'solicitada:true',
  (SELECT estado || ':' || (asignado_id = pg_temp.id('W')) FROM tareas
   WHERE hilo_id = pg_temp.hilo('PE', 'Belgrano') AND titulo = 'Revisar'));
SELECT pg_temp.caso('02 W recibe el pedido, sin actor', '1:-', pg_temp.avisos('W', 'pedido_recibido'));
SELECT pg_temp.caso('02 V no recibe "paso sumado"', '0:', pg_temp.avisos('V', 'paso_sumado'));
SELECT pg_temp.caso('02 la campanita de V: el hilo, la obra y W', 'Zqx152 PE:Zqx152 Belgrano:hilo:test152 W',
  pg_temp.leer($s$SELECT etiqueta || ':' || motivo || ':' || destino || ':' || actor FROM notificaciones_listar()
                  WHERE tipo = 'plantilla_disparada'$s$, 'V'));

-- ============================================================
-- 03. No se repite
-- ============================================================
SELECT pg_temp.caso('03 W la vuelve a en_busqueda', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_busqueda' WHERE id = %L$s$, pg_temp.id('Belgrano')), 'W'));
SELECT pg_temp.caso('03 V cierra el hilo de PE', 'ok', pg_temp.intentar(format(
  $s$SELECT tareas_cancelar_y_cerrar(%L, 'hecho')$s$, pg_temp.hilo('PE', 'Belgrano')), 'V'));
SELECT pg_temp.caso('03 y W la pasa a en_cotizacion otra vez', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_cotizacion' WHERE id = %L$s$, pg_temp.id('Belgrano')), 'W'));
SELECT pg_temp.caso('03 cerrado cuenta: no corre', '1', pg_temp.hilos('PE', 'Belgrano'));
SELECT pg_temp.caso('03 desactivado no cuenta', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas_hilos SET activo = false WHERE id = %L$s$, pg_temp.hilo('PE', 'Belgrano'))));
SELECT pg_temp.caso('03 W la vuelve a en_busqueda', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_busqueda' WHERE id = %L$s$, pg_temp.id('Belgrano')), 'W'));
SELECT pg_temp.caso('03 W la pasa a en_cotizacion: corre de nuevo', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_cotizacion' WHERE id = %L$s$, pg_temp.id('Belgrano')), 'W'));
SELECT pg_temp.caso('03 un hilo nuevo', '1', pg_temp.hilos('PE', 'Belgrano'));
SELECT pg_temp.caso('03 PA no corre por un cambio de estado', '1', pg_temp.hilos('PA', 'Belgrano'));

-- ============================================================
-- 04. El dueño que no puede recibir, y la baja
-- ============================================================
SELECT pg_temp.caso('04 W crea Caseros', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Zqx152 Caseros', 'Calle 2', 'otro', 'casa')$s$,
  pg_temp.id('Caseros')), 'W'));
SELECT pg_temp.caso('04 W suma a V', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras_participantes (obra_id, usuario_id) VALUES (%L, %L)$s$,
  pg_temp.id('Caseros'), pg_temp.id('V')), 'W'));
UPDATE usuario_submodulos SET activo = false
WHERE usuario_id = pg_temp.id('W') AND submodulo_id IN (pg_temp.id('tareas_ver'), pg_temp.id('tareas_plantillas'));
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.caso('04 V la pasa a en_cotizacion', 'ok', pg_temp.intentar(format(
  $s$UPDATE obras SET estado = 'en_cotizacion' WHERE id = %L$s$, pg_temp.id('Caseros')), 'V'));
SELECT pg_temp.caso('04 W sin tareas_ver: PW no corre', '0', pg_temp.hilos('PW', 'Caseros'));
UPDATE usuarios SET activo = false WHERE id = pg_temp.id('V');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.caso('04 la baja de V apaga sus disparos', 'PA:false,PApagada:false,PE:false,PF:false',
  (SELECT string_agg(i.nombre || ':' || p.disparo_activo, ',' ORDER BY i.nombre)
   FROM tareas_plantillas p JOIN ids i ON i.id = p.id WHERE p.dueno_id = pg_temp.id('V')));

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
