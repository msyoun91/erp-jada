-- Verificación de sql/144: Auditoría. NO es una migración: todo corre dentro
-- de una transacción que revierte. Termina en un DO que lanza "N / M ok" y los
-- casos que fallan.
--
-- Mundo: Juan es dueño de Marta, Rosa y Sin (sin accesos). Pedro miró a Marta
-- dos veces hoy y a Rosa hace 100 días; X miró a Rosa 600 veces. Juan mira a
-- Marta con "Ver contacto". Aud solo tiene la vista Auditoría. El montaje
-- escribe como superusuario; lo demás, como cada uno. Nombres con `Zqx144`.

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

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT count(*)::text FROM (%s) x', p_sql), p_como);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','Pedro','X','Aud','Marta','Rosa','Sin']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND codigo IN
  ('contactos_ver','contactos_auditoria');

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test144.local', jsonb_build_object('nombre', 'test144 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Pedro','X','Aud');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Pedro','contactos_ver'), ('X','contactos_ver'), ('Aud','contactos_auditoria')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO contactos_personas (id, nombre, telefono, responsable_id, creado_por)
SELECT pg_temp.id(n), 'Zqx144 ' || n, '1144' || (1000 + i)::text || '000', pg_temp.id('Juan'), pg_temp.id('Juan')
FROM (VALUES ('Marta', 1), ('Rosa', 2), ('Sin', 3)) AS x (n, i);

INSERT INTO contactos_accesos (persona_id, usuario_id, created_at)
VALUES (pg_temp.id('Marta'), pg_temp.id('Pedro'), now() - interval '1 hour'),
       (pg_temp.id('Marta'), pg_temp.id('Pedro'), now() - interval '2 hours'),
       (pg_temp.id('Rosa'),  pg_temp.id('Pedro'), now() - interval '100 days');
INSERT INTO contactos_accesos (persona_id, usuario_id, created_at)
SELECT pg_temp.id('Rosa'), pg_temp.id('X'), now() - make_interval(mins => g)
FROM generate_series(1, 600) g;

SELECT pg_temp.caso('00 Juan mira a Marta', '1', pg_temp.ve(format(
  'SELECT * FROM contactos_ver_contacto(%L)', pg_temp.id('Marta')), 'Juan'));

-- ============================================================
-- 01. Resumen por usuario
-- ============================================================
SELECT pg_temp.caso('01 Pedro, 30 días: 2 accesos, 1 persona', '2/1', pg_temp.consultar(format(
  $s$SELECT accesos || '/' || personas FROM contactos_auditoria_resumen(30) WHERE usuario_id = %L$s$,
  pg_temp.id('Pedro')), 'Aud'));
SELECT pg_temp.caso('01 Pedro, 365 días: 3 accesos, 2 personas', '3/2', pg_temp.consultar(format(
  $s$SELECT accesos || '/' || personas FROM contactos_auditoria_resumen(365) WHERE usuario_id = %L$s$,
  pg_temp.id('Pedro')), 'Aud'));
SELECT pg_temp.caso('01 el "Ver contacto" de Juan cuenta', '1', pg_temp.consultar(format(
  $s$SELECT accesos::text FROM contactos_auditoria_resumen(30) WHERE usuario_id = %L$s$,
  pg_temp.id('Juan')), 'Aud'));
SELECT pg_temp.caso('01 de más a menos: X, Pedro, Juan', 'X,Pedro,Juan', pg_temp.consultar(format(
  $s$SELECT string_agg(i.nombre, ',' ORDER BY x.o)
     FROM contactos_auditoria_resumen(30) WITH ORDINALITY AS x (usuario_id, usuario, accesos, personas, o)
     JOIN ids i ON i.id = x.usuario_id
     WHERE x.usuario_id IN (%L, %L, %L)$s$,
  pg_temp.id('X'), pg_temp.id('Pedro'), pg_temp.id('Juan')), 'Aud'));

-- ============================================================
-- 02. Detalle y filtro por persona
-- ============================================================
SELECT pg_temp.caso('02 detalle de Pedro: 2, con el dueño', '2', pg_temp.ve(format(
  $s$SELECT 1 FROM contactos_auditoria_detalle(30, %L) WHERE dueno_id = %L AND dueno = 'test144 Juan'$s$,
  pg_temp.id('Pedro'), pg_temp.id('Juan')), 'Aud'));
SELECT pg_temp.caso('02 ¿quién miró a Marta? 3', '3', pg_temp.ve(format(
  'SELECT 1 FROM contactos_auditoria_detalle(30, NULL, %L)', pg_temp.id('Marta')), 'Aud'));
SELECT pg_temp.caso('02 tope: 501 filas', '501', pg_temp.ve(format(
  'SELECT 1 FROM contactos_auditoria_detalle(30, %L)', pg_temp.id('X')), 'Aud'));
SELECT pg_temp.caso('02 el buscador trae a Marta', '1', pg_temp.ve(
  $s$SELECT 1 FROM contactos_auditoria_personas('zqx144 mar')$s$, 'Aud'));
SELECT pg_temp.caso('02 no trae a quien nadie miró', '0', pg_temp.ve(
  $s$SELECT 1 FROM contactos_auditoria_personas('Zqx144 Sin')$s$, 'Aud'));

-- ============================================================
-- 03. Sin la vista, nada; con la vista, no abre la agenda
-- ============================================================
SELECT pg_temp.caso('03 X (contactos_ver) no ve el resumen', '0', pg_temp.ve(
  'SELECT 1 FROM contactos_auditoria_resumen(365)', 'X'));
SELECT pg_temp.caso('03 X no ve el detalle', '0', pg_temp.ve(format(
  'SELECT 1 FROM contactos_auditoria_detalle(365, %L)', pg_temp.id('Pedro')), 'X'));
SELECT pg_temp.caso('03 X no usa el buscador', '0', pg_temp.ve(
  $s$SELECT 1 FROM contactos_auditoria_personas('Zqx144')$s$, 'X'));
SELECT pg_temp.caso('03 Aud no ve a Marta', '0', pg_temp.ve(format(
  'SELECT 1 FROM contactos_personas WHERE id = %L', pg_temp.id('Marta')), 'Aud'));
SELECT pg_temp.caso('03 Aud no ve su teléfono', 'CO017', pg_temp.consultar(format(
  'SELECT telefono FROM contactos_ver_contacto(%L)', pg_temp.id('Marta')), 'Aud'));
SELECT pg_temp.caso('03 auditoría no se delega', 'false', (
  SELECT delegable::text FROM submodulos WHERE codigo = 'contactos_auditoria' AND activo));

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
