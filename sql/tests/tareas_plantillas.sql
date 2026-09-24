-- Verificación de sql/118: plantillas personales y Catálogo. NO es una
-- migración: todo corre dentro de una transacción que termina en ROLLBACK.
-- Correr después de aplicar sql/112 a sql/118.
--
-- Mundo: G admin de usuarios; A admin de tareas (sin equipo); equipo T con D
-- delegador, M1 (con tareas_pedir), M2 y M3; equipo U con E delegador y N1.
-- Todos con tareas_plantillas salvo E. Nada depende de los datos reales.
--
-- `pasos(H)`: los pasos del hilo H en orden de creación,
-- 'título:estado:asignado:vence:vence_dias:título del previo'.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.nombre(p_id uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT nombre FROM ids WHERE id = p_id;
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

-- Con `p_guardar`, lo que devuelve la sentencia queda en `ids` con ese nombre.
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
  ELSE
    PERFORM set_config('role', 'service_role', true);
  END IF;
  IF p_guardar IS NOT NULL THEN
    EXECUTE p_sql INTO v_id;
  ELSE
    EXECUTE p_sql;
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF p_guardar IS NOT NULL THEN
    INSERT INTO ids VALUES (p_guardar, v_id);
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

CREATE FUNCTION pg_temp.guardar(p_plantilla text, p_como text, p_pasos jsonb, p_nuevo boolean DEFAULT true)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT guardar_plantilla(%L, %L, NULL, %L)',
    CASE WHEN NOT p_nuevo THEN pg_temp.id(p_plantilla) END, p_plantilla, p_pasos),
    p_como, CASE WHEN p_nuevo THEN p_plantilla END);
$f$;

CREATE FUNCTION pg_temp.usar(p_plantilla text, p_como text, p_hilo text,
                             p_asignados jsonb DEFAULT '{}', p_en text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT usar_plantilla(%L, %L, %L, %L)',
    pg_temp.id(p_plantilla), p_hilo, pg_temp.id(p_en), p_asignados),
    p_como, CASE WHEN p_en IS NULL THEN p_hilo END);
$f$;

CREATE FUNCTION pg_temp.pasos(p_hilo text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(t.titulo || ':' || t.estado || ':'
                    || coalesce(pg_temp.nombre(coalesce(t.asignado_id, t.asignado_equipo_id)), '?') || ':'
                    || coalesce((t.vence - tareas_hoy())::text, '') || ':'
                    || coalesce(t.vence_dias::text, '') || ':' || coalesce(p.titulo, ''), ' '
                    ORDER BY t.created_at)
  FROM tareas t
  LEFT JOIN tareas p ON p.id = t.paso_anterior_id
  WHERE t.hilo_id = pg_temp.id(p_hilo) AND t.activo;
$f$;

CREATE FUNCTION pg_temp.paso_id(p_plantilla text, p_orden int) RETURNS text LANGUAGE sql AS $f$
  SELECT id::text FROM tareas_plantillas_pasos
  WHERE plantilla_id = pg_temp.id(p_plantilla) AND orden = p_orden AND activo;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['G','A','D','M1','M2','M3','E','N1','T','U']) AS n;

INSERT INTO ids (nombre, id)
SELECT codigo, id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','tareas_ver','tareas_pedir',
                            'tareas_plantillas','tareas_todas','tareas_administrar');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test118.local', jsonb_build_object('nombre', 'test118 ' || nombre)
FROM ids WHERE nombre IN ('G','A','D','M1','M2','M3','E','N1');

INSERT INTO equipos (id, nombre)
SELECT pg_temp.id(e), 'test118 ' || e || ' ' || pg_temp.id(e) FROM unnest(ARRAY['T','U']) AS e;
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('T','D'),('T','M1'),('T','M2'),('T','M3'),('U','E'),('U','N1')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s)
FROM (VALUES
  ('G','usuarios_ver'), ('G','usuarios_gestionar'),
  ('A','tareas_ver'), ('A','tareas_pedir'), ('A','tareas_todas'), ('A','tareas_administrar'),
  ('D','tareas_ver'), ('D','tareas_plantillas'),
  ('M1','tareas_ver'), ('M1','tareas_pedir'), ('M1','tareas_plantillas'),
  ('M2','tareas_ver'), ('M2','tareas_plantillas'), ('M3','tareas_ver'), ('M3','tareas_plantillas'),
  ('E','tareas_ver'), ('N1','tareas_ver'), ('N1','tareas_plantillas')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.caso('00 montaje: D delegador de T', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('D'))));
SELECT pg_temp.caso('00 montaje: E delegador de U', 'ok',
  pg_temp.intentar(format('SELECT designar_delegador(%L, %L)', pg_temp.id('G'), pg_temp.id('E'))));

-- ============================================================
-- Guardar y usar
-- ============================================================
SELECT pg_temp.caso('01 M1 guarda P1: vacío, M2 en cadena a 3 días, pedido a N1 en paralelo a 5', 'ok',
  pg_temp.guardar('P1', 'M1', format('[
    {"titulo":"a"},
    {"titulo":"b","asignado_id":"%s","vence_dias":3},
    {"titulo":"c","asignado_id":"%s","vence_dias":5,"espera_anterior":false,"prioridad":"alta"}
  ]', pg_temp.id('M2'), pg_temp.id('N1'))::jsonb));
SELECT pg_temp.caso('01 sin pasos no se guarda', 'TA020', pg_temp.guardar('PX', 'M1', '[]'));
SELECT pg_temp.caso('01 E sin tareas_plantillas no guarda', '42501',
  pg_temp.guardar('PE', 'E', '[{"titulo":"x"}]'));

SELECT pg_temp.caso('02 M1 usa P1', 'ok', pg_temp.usar('P1', 'M1', 'H1'));
SELECT pg_temp.caso('02 H1: título, responsable M1', 'H1:M1',
  (SELECT titulo || ':' || pg_temp.nombre(responsable_id) FROM tareas_hilos WHERE id = pg_temp.id('H1')));
SELECT pg_temp.caso('02 pasos: vacío en M1, cadena relativa, pedido con fecha',
  'a:pendiente:M1::: b:pendiente:M2::3:a c:solicitada:N1:5::', pg_temp.pasos('H1'));
SELECT pg_temp.caso('02 c conserva la prioridad', 'alta',
  (SELECT prioridad::text FROM tareas WHERE hilo_id = pg_temp.id('H1') AND titulo = 'c'));

SELECT pg_temp.caso('03 sin título usa el nombre', 'ok',
  pg_temp.intentar(format('SELECT usar_plantilla(%L)', pg_temp.id('P1')), 'M1', 'H2'));
SELECT pg_temp.caso('03 H2 se llama P1', 'P1',
  (SELECT titulo FROM tareas_hilos WHERE id = pg_temp.id('H2')));

SELECT pg_temp.caso('04 el elegido gana sobre el fijo y el vacío', 'ok',
  pg_temp.usar('P1', 'M1', 'H3', jsonb_build_object(
    pg_temp.paso_id('P1', 1), jsonb_build_object('asignado_equipo_id', pg_temp.id('T')),
    pg_temp.paso_id('P1', 2), jsonb_build_object('asignado_id', pg_temp.id('M3')))));
SELECT pg_temp.caso('04 a al equipo, b a M3',
  'a:pendiente:T::: b:pendiente:M3::3:a c:solicitada:N1:5::', pg_temp.pasos('H3'));

-- ============================================================
-- Personal: nadie más la ve, la edita ni la usa
-- ============================================================
SELECT pg_temp.caso('05 M2 no ve P1 sin publicar', '0',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas WHERE id = %L', pg_temp.id('P1')), 'M2'));
SELECT pg_temp.caso('05 ni sus pasos', '0',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas_pasos WHERE plantilla_id = %L', pg_temp.id('P1')), 'M2'));
SELECT pg_temp.caso('05 A la ve', '1',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas WHERE id = %L', pg_temp.id('P1')), 'A'));
SELECT pg_temp.caso('05 M2 no la usa', 'TA017', pg_temp.usar('P1', 'M2', 'HX'));
SELECT pg_temp.caso('05 M2 no la edita', 'TA017',
  pg_temp.guardar('P1', 'M2', '[{"titulo":"x"}]', false));

-- ============================================================
-- Catálogo
-- ============================================================
SELECT pg_temp.caso('06 M2 no publica P1', 'ok',
  pg_temp.intentar(format('UPDATE tareas_plantillas SET publicada = true WHERE id = %L', pg_temp.id('P1')), 'M2'));
SELECT pg_temp.caso('06 sigue sin publicar', 'false',
  (SELECT publicada::text FROM tareas_plantillas WHERE id = pg_temp.id('P1')));
SELECT pg_temp.caso('06 A no publica lo ajeno', 'TA018',
  pg_temp.intentar(format('UPDATE tareas_plantillas SET publicada = true WHERE id = %L', pg_temp.id('P1')), 'A'));
SELECT pg_temp.caso('06 M1 publica P1', 'ok',
  pg_temp.intentar(format('UPDATE tareas_plantillas SET publicada = true WHERE id = %L', pg_temp.id('P1')), 'M1'));
SELECT pg_temp.caso('06 N1, de otro equipo, la ve con sus pasos', '3',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas_pasos WHERE plantilla_id = %L', pg_temp.id('P1')), 'N1'));
SELECT pg_temp.caso('06 E sin tareas_plantillas no la ve', '0',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas WHERE id = %L', pg_temp.id('P1')), 'E'));
SELECT pg_temp.caso('06 publicada, M2 sigue sin usarla', 'TA017', pg_temp.usar('P1', 'M2', 'HX'));

SELECT pg_temp.caso('07 M2 la copia', 'ok',
  pg_temp.intentar(format('SELECT copiar_plantilla(%L)', pg_temp.id('P1')), 'M2', 'C1'));
SELECT pg_temp.caso('07 la copia: de M2, sin publicar, con origen', 'P1:M2:false:true',
  (SELECT nombre || ':' || pg_temp.nombre(dueno_id) || ':' || publicada || ':'
          || (copiada_de = pg_temp.id('P1'))
   FROM tareas_plantillas WHERE id = pg_temp.id('C1')));
SELECT pg_temp.caso('07 pasos sin asignados, con forma y plazos', 'a:t: b:t:3 c:f:5',
  (SELECT string_agg(titulo || ':' || left(espera_anterior::text, 1) || ':' || coalesce(vence_dias::text, ''), ' '
                     ORDER BY orden)
   FROM tareas_plantillas_pasos
   WHERE plantilla_id = pg_temp.id('C1') AND activo AND asignado_id IS NULL AND asignado_equipo_id IS NULL));
SELECT pg_temp.caso('07 M2 usa la copia: sin fijos, todo en M2', 'ok',
  pg_temp.usar('C1', 'M2', 'H4'));
SELECT pg_temp.caso('07 H4', 'a:pendiente:M2::: b:pendiente:M2::3:a c:pendiente:M2:5::', pg_temp.pasos('H4'));
SELECT pg_temp.caso('07 una sin publicar no se copia', 'TA017',
  pg_temp.intentar(format('SELECT copiar_plantilla(%L)', pg_temp.id('C1')), 'M1'));

SELECT pg_temp.caso('08 A despublica P1', 'ok',
  pg_temp.intentar(format('UPDATE tareas_plantillas SET publicada = false WHERE id = %L', pg_temp.id('P1')), 'A'));
SELECT pg_temp.caso('08 M2 ya no la ve; la copia sigue', '0:3',
  pg_temp.ve(format('SELECT 1 FROM tareas_plantillas WHERE id = %L', pg_temp.id('P1')), 'M2') || ':'
  || pg_temp.ve(format('SELECT 1 FROM tareas_plantillas_pasos WHERE plantilla_id = %L AND activo', pg_temp.id('C1')), 'M2'));

-- ============================================================
-- Asignados que ya no valen
-- ============================================================
SELECT pg_temp.caso('09 M2 guarda P2 con un pedido fijo a N1', 'ok',
  pg_temp.guardar('P2', 'M2', format('[{"titulo":"x","asignado_id":"%s"}]', pg_temp.id('N1'))::jsonb));
SELECT pg_temp.caso('09 sin tareas_pedir no la usa', 'TA010', pg_temp.usar('P2', 'M2', 'HX'));
SELECT pg_temp.caso('09 y no deja el hilo a medias', '0',
  (SELECT count(*)::text FROM tareas_hilos WHERE titulo = 'HX'));

SELECT pg_temp.caso('10 M1 guarda P3 con fijo M3', 'ok',
  pg_temp.guardar('P3', 'M1', format('[{"titulo":"y","asignado_id":"%s"}]', pg_temp.id('M3'))::jsonb));
SELECT pg_temp.caso('10 baja de M3', 'ok',
  pg_temp.intentar(format('UPDATE usuarios SET activo = false WHERE id = %L', pg_temp.id('M3'))));
SELECT pg_temp.caso('10 M1 la usa: el fijo que no puede recibir queda en M1', 'ok', pg_temp.usar('P3', 'M1', 'H5'));
SELECT pg_temp.caso('10 H5', 'y:pendiente:M1:::', pg_temp.pasos('H5'));

-- ============================================================
-- Sumar a un hilo existente
-- ============================================================
SELECT pg_temp.caso('11 M1 suma P3 a H1, en paralelo', 'ok', pg_temp.usar('P3', 'M1', NULL, '{}', 'H1'));
SELECT pg_temp.caso('11 H1 con y al final, sin previo',
  'a:pendiente:M1::: b:pendiente:M2::3:a c:solicitada:N1:5:: y:pendiente:M1:::', pg_temp.pasos('H1'));
SELECT pg_temp.caso('11 M2, asignado en H1, no suma una cadena: solo pasos suyos en paralelo', 'TA001',
  pg_temp.usar('C1', 'M2', NULL, '{}', 'H1'));

-- ============================================================
-- Editar reemplaza; desactivar y reactivar
-- ============================================================
SELECT pg_temp.caso('12 M1 edita P1 a un paso', 'ok',
  pg_temp.guardar('P1', 'M1', '[{"titulo":"solo"}]', false));
SELECT pg_temp.caso('12 un paso activo', 'solo',
  (SELECT string_agg(titulo, ' ') FROM tareas_plantillas_pasos WHERE plantilla_id = pg_temp.id('P1') AND activo));
SELECT pg_temp.caso('12 la copia no cambia', '3',
  (SELECT count(*)::text FROM tareas_plantillas_pasos WHERE plantilla_id = pg_temp.id('C1') AND activo));

SELECT pg_temp.caso('13 M1 desactiva P1', 'ok',
  pg_temp.intentar(format('UPDATE tareas_plantillas SET activo = false WHERE id = %L', pg_temp.id('P1')), 'M1'));
SELECT pg_temp.caso('13 desactivada no se usa', 'TA017', pg_temp.usar('P1', 'M1', 'HX'));
SELECT pg_temp.caso('13 M1 no la reactiva', 'TA019',
  pg_temp.intentar(format('UPDATE tareas_plantillas SET activo = true WHERE id = %L', pg_temp.id('P1')), 'M1'));
SELECT pg_temp.caso('13 A la reactiva', 'ok',
  pg_temp.intentar(format('UPDATE tareas_plantillas SET activo = true WHERE id = %L', pg_temp.id('P1')), 'A'));

SELECT caso, esperado, obtenido, ok FROM r ORDER BY ok, caso;

ROLLBACK;
