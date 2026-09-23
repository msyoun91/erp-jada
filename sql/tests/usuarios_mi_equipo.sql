-- Lecturas de la vista "Mi equipo" con la sesión del delegador: lo que
-- `getMiEquipo()` pide a PostgREST, recortado por la RLS de sql/104–106.
-- NO es una migración: todo termina en ROLLBACK.
--
-- Mundo propio: D delegador y M1 miembro de T, M2 miembro de otro equipo U,
-- I independiente, A admin.

BEGIN;

CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON ids TO authenticated;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['A','D','M1','M2','I','T','U']) AS n;
INSERT INTO ids (nombre, id)
SELECT replace(codigo, 'usuarios_', ''), id FROM submodulos
WHERE activo AND codigo IN ('usuarios_ver','usuarios_gestionar','usuarios_equipo','usuarios_delegar');

CREATE FUNCTION pg_temp.id(p text) RETURNS uuid LANGUAGE sql AS $f$ SELECT id FROM ids WHERE nombre = p $f$;

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@testmieq.local', jsonb_build_object('nombre', 'testmieq ' || nombre)
FROM ids WHERE nombre IN ('A','D','M1','M2','I');
UPDATE usuarios SET telefono = '1122334455' WHERE id = pg_temp.id('M1');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
VALUES (pg_temp.id('A'), pg_temp.id('ver')), (pg_temp.id('A'), pg_temp.id('gestionar'));
INSERT INTO equipos (id, nombre) VALUES
  (pg_temp.id('T'), 'testmieq T ' || pg_temp.id('T')),
  (pg_temp.id('U'), 'testmieq U ' || pg_temp.id('U'));
INSERT INTO equipos_miembros (equipo_id, usuario_id) VALUES
  (pg_temp.id('T'), pg_temp.id('D')), (pg_temp.id('T'), pg_temp.id('M1')),
  (pg_temp.id('U'), pg_temp.id('M2'));
SELECT asignar_submodulos(pg_temp.id('A'), pg_temp.id('D'), ARRAY[pg_temp.id('equipo'), pg_temp.id('delegar')]);

SELECT set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', pg_temp.id('D')), true);
SET LOCAL ROLE authenticated;

SELECT caso, esperado, obtenido, esperado = obtenido AS ok FROM (VALUES
  ('01 su membresía trae el equipo', 'T',
   (SELECT i.nombre FROM equipos_miembros m JOIN equipos e ON e.id = m.equipo_id JOIN ids i ON i.id = e.id
    WHERE m.usuario_id = pg_temp.id('D') AND m.activo)),
  ('02 ve solo su equipo', 'T',
   (SELECT string_agg(i.nombre, ',' ORDER BY i.nombre) FROM equipos e JOIN ids i ON i.id = e.id)),
  ('03 miembros de T', 'D,M1',
   (SELECT string_agg(i.nombre, ',' ORDER BY i.nombre) FROM equipos_miembros m JOIN ids i ON i.id = m.usuario_id
    WHERE m.equipo_id = pg_temp.id('T') AND m.activo)),
  ('04 no ve a M2, I ni A', '0',
   (SELECT count(*)::text FROM usuarios WHERE id IN (pg_temp.id('M2'), pg_temp.id('I'), pg_temp.id('A')))),
  ('05 lee el teléfono de M1', '1122334455',
   (SELECT telefono FROM usuarios WHERE id = pg_temp.id('M1'))),
  ('06 lee sus permisos con otorgada_por', '2',
   (SELECT count(*)::text FROM usuario_submodulos WHERE usuario_id = pg_temp.id('D') AND activo AND otorgada_por = pg_temp.id('A'))),
  ('07 no lee permisos fuera de T', '0',
   (SELECT count(*)::text FROM usuario_submodulos WHERE usuario_id IN (pg_temp.id('A'), pg_temp.id('M2')))),
  ('08 lee el catálogo de submódulos', 'true',
   (SELECT (count(*) > 0)::text FROM submodulos WHERE codigo = 'usuarios_delegar'))
) AS t(caso, esperado, obtenido);

ROLLBACK;
