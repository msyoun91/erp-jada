-- Verificación de sql/143: los números del widget "Obras". NO es una
-- migración: todo corre dentro de una transacción que revierte. Termina en un
-- DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Juan (Norte) y Pedro (Sur), vendedores. Dueño tiene obras_ver y
-- obras_numeros, sin obras propias. X no ve Obras. De Juan: J1 en idea; J2
-- perdida por precio hoy; J3 perdida por plazo hace 100 días; J4 contratada
-- hoy (referente, casa); J5 contratada y revertida; J6 alta congelada. De
-- Pedro: P1 contratada hoy (cartel, casa). El montaje escribe como
-- superusuario; las consultas, como cada uno. Nombres con `Zqx143`.

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
  RETURN v_out;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

-- La cantidad de un grupo y clave para quien llama; 0 si no hay fila.
CREATE FUNCTION pg_temp.n(p_grupo text, p_clave text, p_dias int, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format(
    'SELECT coalesce(sum(cantidad), 0)::text FROM obras_contar(%s) WHERE grupo = %L AND (%L IS NULL OR clave = %L)',
    p_dias, p_grupo, p_clave, p_clave), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','Pedro','Dueno','X','Norte','Sur','J1','J2','J3','J4','J5','J6','P1']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','obras_ver','obras_crear','obras_numeros');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test143.local', jsonb_build_object('nombre', 'test143 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro','Dueno','X');

INSERT INTO equipos (id, nombre)
SELECT id, 'test143 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');
INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n) FROM (VALUES ('Norte','Juan'),('Sur','Pedro')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','obras_crear'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','obras_crear'),
  ('Dueno','contactos_ver'), ('Dueno','obras_ver'), ('Dueno','obras_numeros')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
SELECT pg_temp.id(o), 'Zqx143 obra ' || o, 'Zqx143 calle ' || o, origen::origen_obra, 'casa', pg_temp.id(r), pg_temp.id(r)
FROM (VALUES ('J1','Juan','otro'), ('J2','Juan','otro'), ('J3','Juan','otro'), ('J4','Juan','referente'),
             ('J5','Juan','otro'), ('J6','Juan','otro'), ('P1','Pedro','cartel')) AS x (o, r, origen);

UPDATE obras SET estado = 'perdida', motivo_perdida = 'precio' WHERE id = pg_temp.id('J2');
UPDATE obras SET estado = 'perdida', motivo_perdida = 'plazo' WHERE id = pg_temp.id('J3');
UPDATE eventos SET created_at = now() - interval '100 days'
WHERE ente = 'obra' AND registro_id = pg_temp.id('J3') AND evento = 'estado' AND detalle->>'estado' = 'perdida';
UPDATE obras SET estado = 'contratada' WHERE id IN (pg_temp.id('J4'), pg_temp.id('J5'), pg_temp.id('P1'));
UPDATE obras SET estado = 'en_cotizacion', estado_nota = 'Zqx143 se cayó' WHERE id = pg_temp.id('J5');
UPDATE obras SET congelada = true WHERE id = pg_temp.id('J6');

SELECT pg_temp.caso('00 J6 quedó congelada', 'true', (SELECT congelada::text FROM obras WHERE id = pg_temp.id('J6')));
SELECT pg_temp.caso('00 J5 volvió a cotización', 'en_cotizacion', (SELECT estado::text FROM obras WHERE id = pg_temp.id('J5')));

-- ============================================================
-- 01. Juan cuenta las suyas
-- ============================================================
SELECT pg_temp.caso('01 por estado: 5 (la congelada no)', '5', pg_temp.n('estado', NULL, 30, 'Juan'));
SELECT pg_temp.caso('01 dos perdidas hoy', '2', pg_temp.n('estado', 'perdida', 30, 'Juan'));
SELECT pg_temp.caso('01 una contratada', '1', pg_temp.n('estado', 'contratada', 30, 'Juan'));
SELECT pg_temp.caso('01 en el período, perdida por precio', '1', pg_temp.n('motivo', 'precio', 30, 'Juan'));
SELECT pg_temp.caso('01 la de hace 100 días, no', '0', pg_temp.n('motivo', 'plazo', 30, 'Juan'));
SELECT pg_temp.caso('01 con 365 días, sí', '1', pg_temp.n('motivo', 'plazo', 365, 'Juan'));
SELECT pg_temp.caso('01 contratada por referente', '1', pg_temp.n('origen', 'referente', 30, 'Juan'));
SELECT pg_temp.caso('01 la revertida no cuenta', '1', pg_temp.n('tipo', 'casa', 30, 'Juan'));
SELECT pg_temp.caso('01 no ve la de Pedro', '0', pg_temp.n('origen', 'cartel', 30, 'Juan'));

-- ============================================================
-- 02. Pedro, las suyas
-- ============================================================
SELECT pg_temp.caso('02 Pedro: una', '1', pg_temp.n('estado', NULL, 30, 'Pedro'));
SELECT pg_temp.caso('02 Pedro: por cartel', '1', pg_temp.n('origen', 'cartel', 30, 'Pedro'));

-- ============================================================
-- 03. Con obras_numeros, todas; sin obras_ver, nada
-- ============================================================
SELECT pg_temp.caso('03 Dueño cuenta todas', (
  SELECT count(*)::text FROM obras WHERE activo AND NOT (congelada AND congelada_antes IS NULL)),
  pg_temp.n('estado', NULL, 30, 'Dueno'));
SELECT pg_temp.caso('03 Dueño ve la de Juan y la de Pedro', 'true', (
  pg_temp.n('origen', 'cartel', 30, 'Dueno')::int >= 1 AND pg_temp.n('origen', 'referente', 30, 'Dueno')::int >= 1)::text);
SELECT pg_temp.caso('03 X: nada', '0', pg_temp.consultar('SELECT count(*)::text FROM obras_contar(30)', 'X'));
SELECT pg_temp.caso('03 obras_numeros no se delega', 'false', (
  SELECT delegable::text FROM submodulos WHERE codigo = 'obras_numeros' AND activo));

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
