-- Verificación de sql/149: "Sobre", disparo, condición y "se completa
-- cuando" en la plantilla; registro y plantilla en el hilo. NO es una
-- migración: todo corre dentro de una transacción que termina en ROLLBACK.
--
-- Mundo, todos independientes con tareas_ver y tareas_plantillas: V y W ven
-- Obras (y Contactos, que Obras requiere); S no. A administra Tareas, sin Obras. Nada depende de los datos
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

-- Cuántas filas ve `p_como` con esa consulta.
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

-- guardar_plantilla como p_como; `p_plantilla` es el nombre y la clave en ids.
-- `p_sobre` y el disparo van como texto SQL ('NULL' o un literal).
CREATE FUNCTION pg_temp.guardar(p_plantilla text, p_como text, p_pasos jsonb, p_sobre text DEFAULT 'NULL',
                                p_evento text DEFAULT 'NULL', p_estado text DEFAULT 'NULL',
                                p_activo boolean DEFAULT false, p_nuevo boolean DEFAULT true)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT guardar_plantilla(%L, %L, NULL, %L, %s, %s, %s, %L)',
    CASE WHEN NOT p_nuevo THEN pg_temp.id(p_plantilla) END, p_plantilla, p_pasos,
    p_sobre, p_evento, p_estado, p_activo),
    p_como, CASE WHEN p_nuevo THEN p_plantilla END);
$f$;

CREATE FUNCTION pg_temp.plantilla(p_plantilla text) RETURNS text LANGUAGE sql AS $f$
  SELECT concat_ws(':', coalesce(sobre, '-'), coalesce(disparo_evento::text, '-'), coalesce(disparo_estado, '-'),
                   disparo_activo::text)
  FROM tareas_plantillas WHERE id = pg_temp.id(p_plantilla);
$f$;

CREATE FUNCTION pg_temp.pasos(p_plantilla text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(titulo || ':' || coalesce(condicion, '-') || ':'
                    || coalesce(completa_evento || '=' || completa_valor, '-'), ' ' ORDER BY orden)
  FROM tareas_plantillas_pasos WHERE plantilla_id = pg_temp.id(p_plantilla) AND activo;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['V','W','S','A','Obra','H1']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('tareas_ver','tareas_plantillas','tareas_todas','tareas_pedir','tareas_administrar','obras_ver','contactos_ver');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test149.local', jsonb_build_object('nombre', 'test149 ' || nombre)
FROM ids WHERE nombre IN ('V','W','S','A');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('V','tareas_ver'), ('V','tareas_plantillas'), ('V','obras_ver'), ('V','contactos_ver'),
  ('W','tareas_ver'), ('W','tareas_plantillas'), ('W','obras_ver'), ('W','contactos_ver'),
  ('S','tareas_ver'), ('S','tareas_plantillas'),
  ('A','tareas_ver'), ('A','tareas_todas'), ('A','tareas_pedir'), ('A','tareas_administrar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- ============================================================
-- 01. Guardar con "Sobre", disparo, condición y "se completa cuando"
-- ============================================================
SELECT pg_temp.caso('01 V guarda P1 sobre obra, al entrar en contratada', 'ok',
  pg_temp.guardar('P1', 'V', '[
    {"titulo":"a","condicion":"arquitecto","completa_evento":"relacion_alta","completa_valor":"arquitecto"},
    {"titulo":"b","condicion":"!decisor"},
    {"titulo":"c","completa_evento":"estado","completa_valor":"contratada"}
  ]', '''obra''', '''estado''', '''contratada'''));
SELECT pg_temp.caso('01 la plantilla', 'obra:estado:contratada:false', pg_temp.plantilla('P1'));
SELECT pg_temp.caso('01 los pasos', 'a:arquitecto:relacion_alta=arquitecto b:!decisor:- c:-:estado=contratada',
  pg_temp.pasos('P1'));
SELECT pg_temp.caso('01 disparo al alta', 'ok',
  pg_temp.guardar('P2', 'V', '[{"titulo":"x"}]', '''obra''', '''alta'''));

-- ============================================================
-- 02. Lo que no vale para el ente
-- ============================================================
SELECT pg_temp.caso('02 un rol que la obra no tiene', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","condicion":"capataz"}]', '''obra'''));
SELECT pg_temp.caso('02 un estado que la obra no tiene', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","completa_evento":"estado","completa_valor":"nada"}]', '''obra'''));
SELECT pg_temp.caso('02 condición mal escrita', '23514',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","condicion":"!!arquitecto"}]', '''obra'''));
SELECT pg_temp.caso('02 "se completa" sin evento', '23514',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","completa_valor":"contratada"}]', '''obra'''));
SELECT pg_temp.caso('02 "se completa" sin valor', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","completa_evento":"estado"}]', '''obra'''));
SELECT pg_temp.caso('02 "se completa" con otro evento', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","completa_evento":"baja","completa_valor":"x"}]', '''obra'''));
SELECT pg_temp.caso('02 disparo por estado sin estado', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x"}]', '''obra''', '''estado'''));
SELECT pg_temp.caso('02 al alta no lleva estado', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x"}]', '''obra''', '''alta''', '''idea'''));
SELECT pg_temp.caso('02 estado sin disparo', '23514',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x"}]', '''obra''', 'NULL', '''idea'''));
SELECT pg_temp.caso('02 disparo con un estado que no existe', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x"}]', '''obra''', '''estado''', '''nada'''));
SELECT pg_temp.caso('02 un hilo no dispara', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x"}]', '''hilo''', '''alta'''));
SELECT pg_temp.caso('02 disparo sin "Sobre"', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x"}]', 'NULL', '''alta'''));
SELECT pg_temp.caso('02 activo sin disparo', '23514',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x"}]', '''obra''', 'NULL', 'NULL', true));
SELECT pg_temp.caso('02 condición sin "Sobre"', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","condicion":"arquitecto"}]'));
SELECT pg_temp.caso('02 y por INSERT directo del paso', 'TA024',
  pg_temp.intentar(format($s$INSERT INTO tareas_plantillas_pasos (plantilla_id, orden, titulo, condicion)
    VALUES (%L, 9, 'x', 'capataz')$s$, pg_temp.id('P1')), 'V'));

-- ============================================================
-- 03. Sin el submódulo del ente: ni se arma ni se ve
-- ============================================================
SELECT pg_temp.caso('03 S no arma una plantilla sobre obra', 'TA023',
  pg_temp.guardar('PX', 'S', '[{"titulo":"x"}]', '''obra'''));
SELECT pg_temp.caso('03 S sí sobre hilo', 'ok',
  pg_temp.guardar('PS', 'S', '[{"titulo":"x"}]', '''hilo'''));
SELECT pg_temp.caso('03 V publica P1 y P3 sin "Sobre"', 'ok',
  pg_temp.guardar('P3', 'V', '[{"titulo":"x"}]'));
SELECT pg_temp.caso('03 publicar', 'ok', pg_temp.intentar(format(
  'UPDATE tareas_plantillas SET publicada = true WHERE id IN (%L, %L)', pg_temp.id('P1'), pg_temp.id('P3')), 'V'));
SELECT pg_temp.caso('03 S ve P3 en el Catálogo y P1 no', '1',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas WHERE id IN (%L, %L)', pg_temp.id('P1'), pg_temp.id('P3')), 'S'));
SELECT pg_temp.caso('03 ni sus pasos', '0',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas_pasos WHERE plantilla_id = %L', pg_temp.id('P1')), 'S'));
SELECT pg_temp.caso('03 W ve las dos', '2',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas WHERE id IN (%L, %L)', pg_temp.id('P1'), pg_temp.id('P3')), 'W'));
SELECT pg_temp.caso('03 S no copia P1', 'TA017',
  pg_temp.intentar(format('SELECT copiar_plantilla(%L)', pg_temp.id('P1')), 'S'));

-- ============================================================
-- 04. El admin la ve y la edita, pero no activa el disparo
-- ============================================================
SELECT pg_temp.caso('04 A ve P1', '1',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas WHERE id = %L', pg_temp.id('P1')), 'A'));
SELECT pg_temp.caso('04 A la edita sin cambiar "Sobre"', 'ok',
  pg_temp.guardar('P1', 'A', '[{"titulo":"a","condicion":"arquitecto"}]', '''obra''', '''estado''', '''contratada''',
                  false, false));
SELECT pg_temp.caso('04 A le cambia "Sobre" a hilo, que ve', 'ok',
  pg_temp.guardar('P3', 'A', '[{"titulo":"x"}]', '''hilo''', 'NULL', 'NULL', false, false));
SELECT pg_temp.caso('04 pero no a obra', 'TA023',
  pg_temp.guardar('P3', 'A', '[{"titulo":"x"}]', '''obra''', 'NULL', 'NULL', false, false));
SELECT pg_temp.caso('04 A no activa el disparo de V', 'TA025', pg_temp.intentar(format(
  'UPDATE tareas_plantillas SET disparo_activo = true WHERE id = %L', pg_temp.id('P1')), 'A'));
SELECT pg_temp.caso('04 V sí', 'ok', pg_temp.intentar(format(
  'UPDATE tareas_plantillas SET disparo_activo = true WHERE id = %L', pg_temp.id('P1')), 'V'));
SELECT pg_temp.caso('04 A lo edita con el disparo prendido', 'ok',
  pg_temp.guardar('P1', 'A', '[{"titulo":"a","condicion":"arquitecto"}]', '''obra''', '''estado''', '''contratada''',
                  true, false));
SELECT pg_temp.caso('04 y lo apaga', 'ok', pg_temp.intentar(format(
  'UPDATE tareas_plantillas SET disparo_activo = false WHERE id = %L', pg_temp.id('P1')), 'A'));
SELECT pg_temp.caso('04 V lo vuelve a prender', 'ok', pg_temp.intentar(format(
  'UPDATE tareas_plantillas SET disparo_activo = true WHERE id = %L', pg_temp.id('P1')), 'V'));

-- ============================================================
-- 05. Cambiar "Sobre" con pasos que no le valen
-- ============================================================
SELECT pg_temp.caso('05 UPDATE directo a hilo con condición de obra', 'TA024', pg_temp.intentar(format(
  'UPDATE tareas_plantillas SET sobre = ''hilo'', disparo_evento = NULL, disparo_estado = NULL, disparo_activo = false WHERE id = %L',
  pg_temp.id('P1')), 'V'));
SELECT pg_temp.caso('05 guardar a hilo con pasos nuevos sin marcas', 'ok',
  pg_temp.guardar('P2', 'V', '[{"titulo":"y"}]', '''hilo''', 'NULL', 'NULL', false, false));
SELECT pg_temp.caso('05 P2 quedó sobre hilo', 'hilo:-:-:false', pg_temp.plantilla('P2'));

-- ============================================================
-- 06. La copia del Catálogo trae todo con el disparo apagado
-- ============================================================
SELECT pg_temp.caso('06 W copia P1', 'ok',
  pg_temp.intentar(format('SELECT copiar_plantilla(%L)', pg_temp.id('P1')), 'W', 'C1'));
SELECT pg_temp.caso('06 la copia', 'obra:estado:contratada:false', pg_temp.plantilla('C1'));
SELECT pg_temp.caso('06 sus pasos', 'a:arquitecto:-', pg_temp.pasos('C1'));

-- ============================================================
-- 07. El hilo: registro y plantilla, los tres o ninguno, fuera del GRANT
-- ============================================================
SELECT pg_temp.caso('07 V no escribe el registro del hilo', '42501', pg_temp.intentar(format(
  $s$INSERT INTO tareas_hilos (id, titulo, registro_ente, registro_id, plantilla_id) VALUES (%L, 'x', 'obra', %L, %L)$s$,
  gen_random_uuid(), pg_temp.id('Obra'), pg_temp.id('P1')), 'V'));
SELECT pg_temp.caso('07 V crea H1, recurrente', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO tareas_hilos (id, titulo, recurrencia_cantidad, recurrencia_unidad) VALUES (%L, 'Zqx149 H1', 1, 'dia')$s$,
  pg_temp.id('H1')), 'V'));
SELECT pg_temp.caso('07 solo el ente, no', '23514', pg_temp.intentar(format(
  $s$UPDATE tareas_hilos SET registro_ente = 'obra' WHERE id = %L$s$, pg_temp.id('H1'))));
SELECT pg_temp.caso('07 los tres', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas_hilos SET registro_ente = 'obra', registro_id = %L, plantilla_id = %L WHERE id = %L$s$,
  pg_temp.id('Obra'), pg_temp.id('P1'), pg_temp.id('H1'))));
SELECT pg_temp.caso('07 V cierra H1', 'ok', pg_temp.intentar(format(
  $s$UPDATE tareas_hilos SET estado = 'cerrado' WHERE id = %L$s$, pg_temp.id('H1')), 'V'));
SELECT pg_temp.caso('07 el siguiente ciclo sigue sobre la obra y la plantilla', 'obra:true:true',
  (SELECT registro_ente || ':' || (registro_id = pg_temp.id('Obra')) || ':' || (plantilla_id = pg_temp.id('P1'))
   FROM tareas_hilos WHERE recurrencia_de = pg_temp.id('H1')));

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
