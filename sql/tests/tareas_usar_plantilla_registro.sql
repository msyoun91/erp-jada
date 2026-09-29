-- Verificación de sql/150: `usar_plantilla` con registro — marcas válidas al
-- guardar, `{dato}`, `{@registro}`, `{@rol}`, `{si hay}`, pasos
-- condicionados, registro y plantilla en el hilo. NO es una migración: todo
-- corre dentro de una transacción que termina en ROLLBACK.
--
-- Mundo, todos independientes: V y W con Tareas, Obras y Contactos; A
-- administra Tareas, sin Obras. La obra Belgrano es de V: arquitectos Laura
-- (persona de V) y Estudio G (empresa de V); referente Pepe (persona de W,
-- que V ve por el vínculo: quien ve el registro ve sus contactos). Los counts
-- van filtrados por los ids del montaje.

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

-- guardar_plantilla como p_como; `p_plantilla` es el nombre y la clave en ids.
CREATE FUNCTION pg_temp.guardar(p_plantilla text, p_como text, p_pasos jsonb, p_sobre text DEFAULT 'NULL')
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT guardar_plantilla(NULL, %L, NULL, %L, %s)', p_plantilla, p_pasos, p_sobre),
    p_como, p_plantilla);
$f$;

-- usar_plantilla como p_como; el hilo queda en ids como p_hilo_nuevo.
CREATE FUNCTION pg_temp.usar(p_plantilla text, p_como text, p_registro text, p_hilo_nuevo text DEFAULT NULL,
                             p_hilo text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT usar_plantilla(%L, NULL, %L, ''{}'', %L)',
    pg_temp.id(p_plantilla), pg_temp.id(p_hilo), pg_temp.id(p_registro)), p_como, p_hilo_nuevo);
$f$;

-- Los pasos de un hilo: título y el título del previo, por orden de alta.
CREATE FUNCTION pg_temp.pasos(p_hilo text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(t.titulo || '<' || coalesce(p.titulo, '-'), ' | ' ORDER BY t.created_at)
  FROM tareas t LEFT JOIN tareas p ON p.id = t.paso_anterior_id
  WHERE t.hilo_id = pg_temp.id(p_hilo) AND t.activo;
$f$;

CREATE FUNCTION pg_temp.descripcion(p_hilo text, p_titulo text) RETURNS text LANGUAGE sql AS $f$
  SELECT descripcion FROM tareas WHERE hilo_id = pg_temp.id(p_hilo) AND titulo = p_titulo AND activo;
$f$;

CREATE FUNCTION pg_temp.ref(p_ente text, p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('{%s:%s|%s}', p_ente, pg_temp.id(p_nombre), etiqueta_registro(p_ente, pg_temp.id(p_nombre)));
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['V','W','A','Belgrano','ObraW','Laura','EstudioG','Pepe','H0']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('tareas_ver','tareas_plantillas','tareas_todas','tareas_pedir','tareas_administrar',
   'obras_ver','obras_crear','obras_aprobar','contactos_ver','contactos_aprobar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test150.local', jsonb_build_object('nombre', 'test150 ' || nombre)
FROM ids WHERE nombre IN ('V','W','A');

-- Con `_aprobar`, lo que cargan no se congela.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM unnest(ARRAY['V','W']) AS u,
     unnest(ARRAY['tareas_ver','tareas_plantillas','obras_ver','obras_crear','obras_aprobar',
                  'contactos_ver','contactos_aprobar']) AS s
UNION ALL
SELECT pg_temp.id('A'), pg_temp.id(s)
FROM unnest(ARRAY['tareas_ver','tareas_plantillas','tareas_todas','tareas_pedir','tareas_administrar']) AS s;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: Belgrano', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Belgrano', 'Calle {1}', 'otro', 'casa')$s$,
  pg_temp.id('Belgrano')), 'V'));
SELECT pg_temp.caso('00 montaje: ObraW', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO obras (id, nombre, direccion, origen, tipo) VALUES (%L, 'Zqx150 W', 'Calle 2', 'otro', 'casa')$s$,
  pg_temp.id('ObraW')), 'W'));
SELECT pg_temp.caso('00 montaje: Laura', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_personas (id, nombre) VALUES (%L, 'Laura')$s$, pg_temp.id('Laura')), 'V'));
SELECT pg_temp.caso('00 montaje: Estudio G', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_empresas (id, nombre) VALUES (%L, 'Estudio G')$s$, pg_temp.id('EstudioG')), 'V'));
SELECT pg_temp.caso('00 montaje: Pepe, de W', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_personas (id, nombre) VALUES (%L, 'Pepe')$s$, pg_temp.id('Pepe')), 'W'));
SELECT pg_temp.caso('00 montaje: arquitectos', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (persona_id, empresa_id, ente, registro_id, roles)
     VALUES (%1$L, NULL, 'obra', %3$L, '{arquitecto}'), (NULL, %2$L, 'obra', %3$L, '{arquitecto}')$s$,
  pg_temp.id('Laura'), pg_temp.id('EstudioG'), pg_temp.id('Belgrano')), 'V'));
SELECT pg_temp.caso('00 montaje: referente de W', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO contactos_vinculos (persona_id, ente, registro_id, roles) VALUES (%L, 'obra', %L, '{referente}')$s$,
  pg_temp.id('Pepe'), pg_temp.id('Belgrano'))));
SELECT pg_temp.caso('00 montaje: H0, hilo suelto de V', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO tareas_hilos (id, titulo) VALUES (%L, 'Zqx150 H0')$s$, pg_temp.id('H0')), 'V'));
SELECT pg_temp.caso('00 V ve a Pepe por la obra', 'Pepe', etiqueta_registro_de('persona', pg_temp.id('Pepe'), pg_temp.id('V')));

-- ============================================================
-- 01. Marcas al guardar
-- ============================================================
SELECT pg_temp.caso('01 V guarda PO sobre obra, con todas las marcas', 'ok',
  pg_temp.guardar('PO', 'V', $j$[
    {"titulo":"Medir {nombre}",
     "descripcion":"En {direccion}{localidad}. Obra {@registro}. Arq: {@arquitecto}.{si hay decisor} Decide {@decisor}.{fin}{si no hay decisor} Sin decisor.{fin}{si hay referente} Ref: {@referente}.{fin}"},
    {"titulo":"Llamar al decisor","condicion":"decisor"},
    {"titulo":"Presupuestar","condicion":"!decisor"},
    {"titulo":"Paralelo","espera_anterior":false,"condicion":"decisor"},
    {"titulo":"Tras paralelo"}
  ]$j$, '''obra'''));
SELECT pg_temp.caso('01 {@rol} en el título', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"Con {@arquitecto}"}]', '''obra'''));
SELECT pg_temp.caso('01 {si} en el título', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"{si hay arquitecto}a{fin}"}]', '''obra'''));
SELECT pg_temp.caso('01 dato que la obra no tiene', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","descripcion":"{telefono}"}]', '''obra'''));
SELECT pg_temp.caso('01 rol que la obra no tiene', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","descripcion":"{@capataz}"}]', '''obra'''));
SELECT pg_temp.caso('01 {si} sin {fin}', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","descripcion":"{si hay arquitecto}a"}]', '''obra'''));
SELECT pg_temp.caso('01 {fin} suelto', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","descripcion":"a{fin}"}]', '''obra'''));
SELECT pg_temp.caso('01 {si} anidado', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","descripcion":"{si hay arquitecto}{si hay decisor}a{fin}{fin}"}]', '''obra'''));
SELECT pg_temp.caso('01 sin "Sobre", ninguna marca', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","descripcion":"{nombre}"}]'));
SELECT pg_temp.caso('01 sin "Sobre", {@registro} tampoco', 'TA024',
  pg_temp.guardar('PX', 'V', '[{"titulo":"x","descripcion":"{@registro}"}]'));
SELECT pg_temp.caso('01 llaves que no son marca, sí', 'ok',
  pg_temp.guardar('PN', 'V', '[{"titulo":"Suelta {X}","descripcion":"a {Hola mundo} b"}]'));
SELECT pg_temp.caso('01 cambiar "Sobre" a hilo con {direccion}', 'TA024', pg_temp.intentar(format(
  $s$UPDATE tareas_plantillas SET sobre = 'hilo' WHERE id = %L$s$, pg_temp.id('PO')), 'V'));

-- ============================================================
-- 02. El registro
-- ============================================================
SELECT pg_temp.caso('02 con "Sobre", sin registro', 'TA026', pg_temp.usar('PO', 'V', NULL));
SELECT pg_temp.caso('02 sin "Sobre", con registro', 'TA026', pg_temp.usar('PN', 'V', 'Belgrano'));
SELECT pg_temp.caso('02 una obra que V no ve', 'TA026', pg_temp.usar('PO', 'V', 'ObraW'));
SELECT pg_temp.caso('02 W no usa la de V', 'TA017', pg_temp.usar('PO', 'W', 'Belgrano'));
SELECT pg_temp.caso('02 A la ve pero no ve la obra', 'TA026', pg_temp.usar('PO', 'A', 'Belgrano'));

-- ============================================================
-- 03. Sin decisor
-- ============================================================
SELECT pg_temp.caso('03 V usa PO sobre Belgrano', 'ok', pg_temp.usar('PO', 'V', 'Belgrano', 'H1'));
SELECT pg_temp.caso('03 el hilo guarda registro y plantilla', 'obra:true:true',
  (SELECT registro_ente || ':' || (registro_id = pg_temp.id('Belgrano')) || ':' || (plantilla_id = pg_temp.id('PO'))
   FROM tareas_hilos WHERE id = pg_temp.id('H1')));
SELECT pg_temp.caso('03 pasos: los condicionados no cortan la cadena',
  'Medir Belgrano<- | Presupuestar<Medir Belgrano | Tras paralelo<-', pg_temp.pasos('H1'));
SELECT pg_temp.caso('03 la descripción',
  format('En Calle (1). Obra %s. Arq: %s, %s. Sin decisor. Ref: %s.',
         pg_temp.ref('obra', 'Belgrano'), pg_temp.ref('empresa', 'EstudioG'), pg_temp.ref('persona', 'Laura'),
         pg_temp.ref('persona', 'Pepe')),
  pg_temp.descripcion('H1', 'Medir Belgrano'));
SELECT pg_temp.caso('03 vínculos: la obra, los dos arquitectos y el referente', 'empresa,obra,persona,persona',
  (SELECT string_agg(v.ente, ',' ORDER BY v.ente) FROM tareas_vinculos v JOIN tareas t ON t.id = v.tarea_id
   WHERE t.hilo_id = pg_temp.id('H1') AND v.activo));

-- ============================================================
-- 04. Con decisor
-- ============================================================
SELECT pg_temp.caso('04 Estudio G pasa a ser también decisor', 'ok', pg_temp.intentar(format(
  $s$UPDATE contactos_vinculos SET roles = '{arquitecto,decisor}' WHERE empresa_id = %L$s$, pg_temp.id('EstudioG')), 'V'));
SELECT pg_temp.caso('04 V usa PO otra vez', 'ok', pg_temp.usar('PO', 'V', 'Belgrano', 'H2'));
SELECT pg_temp.caso('04 pasos',
  'Medir Belgrano<- | Llamar al decisor<Medir Belgrano | Paralelo<- | Tras paralelo<Paralelo', pg_temp.pasos('H2'));
SELECT pg_temp.caso('04 la descripción',
  format('En Calle (1). Obra %1$s. Arq: %2$s, %3$s. Decide %2$s. Ref: %4$s.',
         pg_temp.ref('obra', 'Belgrano'), pg_temp.ref('empresa', 'EstudioG'), pg_temp.ref('persona', 'Laura'),
         pg_temp.ref('persona', 'Pepe')),
  pg_temp.descripcion('H2', 'Medir Belgrano'));

-- ============================================================
-- 05. Sumar a un hilo existente
-- ============================================================
SELECT pg_temp.caso('05 V suma PO a H0', 'ok', pg_temp.usar('PO', 'V', 'Belgrano', NULL, 'H0'));
SELECT pg_temp.caso('05 H0 no cambia su registro', 'true',
  (SELECT (registro_ente IS NULL AND plantilla_id IS NULL)::text FROM tareas_hilos WHERE id = pg_temp.id('H0')));
SELECT pg_temp.caso('05 y tiene los pasos', '4',
  (SELECT count(*)::text FROM tareas WHERE hilo_id = pg_temp.id('H0') AND activo));
SELECT pg_temp.caso('05 W guarda una sin "Sobre"', 'ok', pg_temp.guardar('PW', 'W', '[{"titulo":"w"}]'));
SELECT pg_temp.caso('05 W no suma a H0, que no ve', '42501', pg_temp.usar('PW', 'W', NULL, NULL, 'H0'));

-- ============================================================
-- 06. Sin "Sobre", como antes
-- ============================================================
SELECT pg_temp.caso('06 V usa PN', 'ok', pg_temp.usar('PN', 'V', NULL, 'H3'));
SELECT pg_temp.caso('06 el texto queda tal cual', 'Suelta {X}:a {Hola mundo} b',
  (SELECT titulo || ':' || descripcion FROM tareas WHERE hilo_id = pg_temp.id('H3')));
SELECT pg_temp.caso('06 el hilo, sin registro', 'true',
  (SELECT (registro_ente IS NULL AND plantilla_id IS NULL)::text FROM tareas_hilos WHERE id = pg_temp.id('H3')));
SELECT pg_temp.caso('06 el hilo es de V', 'true',
  (SELECT (responsable_id = pg_temp.id('V'))::text FROM tareas_hilos WHERE id = pg_temp.id('H3')));

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
