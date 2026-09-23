-- Verificación de sql/109: entes, eventos y los dos emisores genéricos.
-- NO es una migración: todo corre dentro de una transacción que termina en
-- ROLLBACK. Correr después de aplicar sql/109.
--
-- sql/109 no registra ningún ente, así que el test arma uno como lo haría un
-- módulo: la tabla `prueba109` (dueño `creado_por`, estado, `lectores` que la
-- ven sin ser dueños), el puente `prueba109_rel` (cada vínculo lo ve solo quien
-- lo creó), su fila en `entes`, sus dos triggers y su rama en
-- `etiqueta_registro` y `puede_ver_relacion`. El DDL también se revierte.
--
-- U1 dueño, U2 lector (tiene la vista, ve la fila, no los vínculos de U1),
-- U3 con la vista pero sin la fila, U4 sin la vista.

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

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text DEFAULT NULL) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
BEGIN
  IF p_como IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
    PERFORM set_config('role', 'authenticated', true);
  END IF;
  EXECUTE p_sql;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE;
END;
$f$;

-- Los eventos de un registro en orden, 'evento:detalle' separados por ' / ';
-- con p_como, los que ese usuario ve; sin él, la tabla cruda.
CREATE FUNCTION pg_temp.eventos(p_registro text, p_como text DEFAULT NULL) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  IF p_como IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
    PERFORM set_config('role', 'authenticated', true);
  END IF;
  SELECT string_agg(evento || CASE WHEN detalle = '{}' THEN '' ELSE ':' || detalle::text END, ' / '
                    ORDER BY created_at)
  INTO v_out FROM eventos WHERE registro_id = pg_temp.id(p_registro);
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN coalesce(v_out, 'nada');
END;
$f$;

CREATE FUNCTION pg_temp.entes_visibles(p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::text INTO v_out FROM entes WHERE codigo = 'prueba109';
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_out;
END;
$f$;

-- ============================================================
-- Montaje: usuarios y vista
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['U1','U2','U3','U4','V','P','Q','R','O']) AS n;

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test109.local', jsonb_build_object('nombre', 'test109 ' || nombre)
FROM ids WHERE nombre IN ('U1','U2','U3','U4');

INSERT INTO submodulos (id, codigo, modulo, tipo, nombre, orden)
VALUES (pg_temp.id('V'), 'prueba109_ver', 'prueba109', 'vista', 'V', 1);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(n), pg_temp.id('V') FROM unnest(ARRAY['U1','U2','U3']) AS n;

-- ============================================================
-- Montaje: el ente, como lo haría un módulo
-- ============================================================
CREATE TYPE estado_prueba109 AS ENUM ('abierta', 'cerrada');

CREATE TABLE prueba109 (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre     text NOT NULL,
  estado     estado_prueba109 NOT NULL DEFAULT 'abierta',
  lectores   uuid[] NOT NULL DEFAULT '{}',
  creado_por uuid NOT NULL DEFAULT auth.uid(),
  activo     boolean NOT NULL DEFAULT true
);
ALTER TABLE prueba109 ENABLE ROW LEVEL SECURITY;
CREATE POLICY s ON prueba109 FOR SELECT TO authenticated
  USING (creado_por = (SELECT auth.uid()) OR (SELECT auth.uid()) = ANY (lectores));
CREATE POLICY i ON prueba109 FOR INSERT TO authenticated WITH CHECK (creado_por = (SELECT auth.uid()));
CREATE POLICY u ON prueba109 FOR UPDATE TO authenticated USING (creado_por = (SELECT auth.uid()));
GRANT SELECT, INSERT, UPDATE ON prueba109 TO authenticated;

CREATE TABLE prueba109_rel (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prueba_id   uuid NOT NULL REFERENCES prueba109(id),
  otro_id     uuid NOT NULL,
  roles       text[] NOT NULL,
  creado_por  uuid NOT NULL DEFAULT auth.uid(),
  activo      boolean NOT NULL DEFAULT true
);
ALTER TABLE prueba109_rel ENABLE ROW LEVEL SECURITY;
CREATE POLICY s ON prueba109_rel FOR SELECT TO authenticated USING (creado_por = (SELECT auth.uid()));
CREATE POLICY i ON prueba109_rel FOR INSERT TO authenticated WITH CHECK (creado_por = (SELECT auth.uid()));
CREATE POLICY u ON prueba109_rel FOR UPDATE TO authenticated USING (creado_por = (SELECT auth.uid()));
GRANT SELECT, INSERT, UPDATE ON prueba109_rel TO authenticated;

INSERT INTO entes (codigo, modulo, submodulo, estados, datos, ruta, tabla, disparos)
VALUES ('prueba109', 'prueba109', 'prueba109_ver', 'estado_prueba109', '{nombre}', '/prueba109/{id}',
        'prueba109', '{alta,estado}');

CREATE OR REPLACE FUNCTION public.etiqueta_registro(p_ente text, p_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $f$
  SELECT CASE e.modulo
           WHEN 'prueba109' THEN (SELECT p.nombre FROM prueba109 p WHERE p.id = p_id AND p.activo)
         END
  FROM entes e
  WHERE e.codigo = p_ente;
$f$;

CREATE OR REPLACE FUNCTION public.puede_ver_relacion(p_ente text, p_id uuid, p_ente_rel text, p_id_rel uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $f$
  SELECT COALESCE(
    (SELECT CASE e.modulo
              WHEN 'prueba109' THEN EXISTS (
                SELECT 1 FROM prueba109_rel v WHERE v.prueba_id = p_id AND v.otro_id = p_id_rel)
            END
       FROM entes e
      WHERE e.codigo = p_ente),
    false
  );
$f$;

CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado ON prueba109
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('prueba109');

CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, roles ON prueba109_rel
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_relacion('prueba109', 'prueba_id', 'otro', 'otro_id');

-- ============================================================
-- entes
-- ============================================================
SELECT pg_temp.caso('01 con la vista, el ente existe', '1', pg_temp.entes_visibles('U1'));
SELECT pg_temp.caso('01 sin la vista, no', '0', pg_temp.entes_visibles('U4'));
SELECT pg_temp.caso('02 ruta sin {id}', '23514', pg_temp.intentar(
  $s$INSERT INTO entes (codigo, modulo, submodulo, ruta, tabla) VALUES ('x109', 'x', 'x', '/x', 'prueba109')$s$));
SELECT pg_temp.caso('02 el cliente no escribe entes', '42501', pg_temp.intentar(
  $s$INSERT INTO entes (codigo, modulo, submodulo, ruta, tabla) VALUES ('x109', 'x', 'x', '/x/{id}', 'prueba109')$s$, 'U1'));

-- ============================================================
-- Registro: alta, estado, baja, reactivación
-- ============================================================
SELECT pg_temp.caso('03 U1 crea P', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO prueba109 (id, nombre, lectores) VALUES (%L, 'P', %L)$s$,
  pg_temp.id('P'), ARRAY[pg_temp.id('U2')]), 'U1'));
SELECT pg_temp.caso('03 alta y el estado con el que nace', 'alta / estado:{"estado": "abierta", "anterior": null}',
  pg_temp.eventos('P'));
SELECT pg_temp.caso('03 el actor es U1', pg_temp.id('U1')::text,
  (SELECT string_agg(DISTINCT actor_id::text, ',') FROM eventos WHERE registro_id = pg_temp.id('P')));

SELECT pg_temp.caso('04 U1 cierra P', 'ok', pg_temp.intentar(format(
  $s$UPDATE prueba109 SET estado = 'cerrada' WHERE id = %L$s$, pg_temp.id('P')), 'U1'));
SELECT pg_temp.caso('04 un UPDATE sin cambio no emite', 'ok', pg_temp.intentar(format(
  $s$UPDATE prueba109 SET estado = 'cerrada', nombre = 'P' WHERE id = %L$s$, pg_temp.id('P')), 'U1'));
SELECT pg_temp.caso('05 U1 desactiva P', 'ok', pg_temp.intentar(format(
  $s$UPDATE prueba109 SET activo = false WHERE id = %L$s$, pg_temp.id('P')), 'U1'));
SELECT pg_temp.caso('05 U1 la reactiva y la reabre', 'ok', pg_temp.intentar(format(
  $s$UPDATE prueba109 SET activo = true, estado = 'abierta' WHERE id = %L$s$, pg_temp.id('P')), 'U1'));
SELECT pg_temp.caso('05 la secuencia, reactivación antes que estado',
  'alta / estado:{"estado": "abierta", "anterior": null} / estado:{"estado": "cerrada", "anterior": "abierta"} / baja / reactivacion / estado:{"estado": "abierta", "anterior": "cerrada"}',
  pg_temp.eventos('P'));

SELECT pg_temp.caso('06 nacer inactivo no emite', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO prueba109 (id, nombre, activo) VALUES (%L, 'Q', false)$s$, pg_temp.id('Q')), 'U1'));
SELECT pg_temp.caso('06 Q sin eventos', 'nada', pg_temp.eventos('Q'));

-- ============================================================
-- Relación: un evento por rol
-- ============================================================
SELECT pg_temp.caso('07 U1 vincula O a P con dos roles', 'ok', pg_temp.intentar(format(
  $s$INSERT INTO prueba109_rel (id, prueba_id, otro_id, roles) VALUES (%L, %L, %L, '{x,y}')$s$,
  pg_temp.id('R'), pg_temp.id('P'), pg_temp.id('O')), 'U1'));
SELECT pg_temp.caso('08 U1 le saca x', 'ok', pg_temp.intentar(format(
  $s$UPDATE prueba109_rel SET roles = '{y}' WHERE id = %L$s$, pg_temp.id('R')), 'U1'));
SELECT pg_temp.caso('09 U1 lo desvincula', 'ok', pg_temp.intentar(format(
  $s$UPDATE prueba109_rel SET activo = false WHERE id = %L$s$, pg_temp.id('R')), 'U1'));
SELECT pg_temp.caso('09 los eventos de relación, del lado de P',
  'relacion_alta:x / relacion_alta:y / relacion_baja:x / relacion_baja:y',
  (SELECT string_agg(evento || ':' || (detalle->>'rol'), ' / ' ORDER BY evento, detalle->>'rol')
   FROM eventos WHERE registro_id = pg_temp.id('P') AND evento IN ('relacion_alta', 'relacion_baja')
     AND detalle->>'ente' = 'otro' AND detalle->>'registro_id' = pg_temp.id('O')::text));

-- ============================================================
-- Quién ve
-- ============================================================
SELECT pg_temp.caso('10 el dueño ve los diez', '10',
  (SELECT count(*)::text FROM regexp_split_to_table(pg_temp.eventos('P', 'U1'), ' / ')));
SELECT pg_temp.caso('11 el lector ve P pero no el vínculo de U1',
  'alta / estado:{"estado": "abierta", "anterior": null} / estado:{"estado": "cerrada", "anterior": "abierta"} / baja / reactivacion / estado:{"estado": "abierta", "anterior": "cerrada"}',
  pg_temp.eventos('P', 'U2'));
SELECT pg_temp.caso('12 con la vista y sin la fila, nada', 'nada', pg_temp.eventos('P', 'U3'));
SELECT pg_temp.caso('12 sin la vista, nada', 'nada', pg_temp.eventos('P', 'U4'));
SELECT pg_temp.caso('13 P archivada: ni el dueño ve sus eventos', 'oknada', (
  SELECT pg_temp.intentar(format($s$UPDATE prueba109 SET activo = false WHERE id = %L$s$, pg_temp.id('P')), 'U1')
         || pg_temp.eventos('P', 'U1')) );

-- ============================================================
-- Nadie inventa un evento
-- ============================================================
SELECT pg_temp.caso('14 INSERT directo', '42501', pg_temp.intentar(format(
  $s$INSERT INTO eventos (ente, registro_id, evento) VALUES ('prueba109', %L, 'alta')$s$, pg_temp.id('P')), 'U1'));
SELECT pg_temp.caso('14 emitir_evento por RPC', '42501', pg_temp.intentar(format(
  $s$SELECT emitir_evento('prueba109', %L, 'alta')$s$, pg_temp.id('P')), 'U1'));
SELECT pg_temp.caso('14 el cliente no edita eventos', '42501', pg_temp.intentar(
  $s$UPDATE eventos SET evento = 'baja' WHERE ente = 'prueba109'$s$, 'U1'));
SELECT pg_temp.caso('14 anon no llama emitir_evento', 'false',
  has_function_privilege('anon', 'public.emitir_evento(text, uuid, tipo_evento, jsonb)', 'EXECUTE')::text);

SELECT caso, esperado, obtenido, ok FROM r ORDER BY caso;

ROLLBACK;
