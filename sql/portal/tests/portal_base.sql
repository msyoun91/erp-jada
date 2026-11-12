-- Verificación de sql/portal/001: links, copias y visitas en la base del portal. NO es una migración: todo corre dentro de una
-- transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan. Se corre con el MCP supabase-portal.
--
-- Mundo: H1 y H2, dos huellas. El ERP copia como service_role; el servidor del portal lee y anota como anon.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
GRANT ALL ON r TO anon, service_role;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

-- Corre `p_sql` con el rol `p_rol`: lo que devuelve, 'ok' si nada, o el SQLSTATE si falla.
CREATE FUNCTION pg_temp.como(p_rol text, p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('role', p_rol, true);
  EXECUTE p_sql INTO v_out;
  PERFORM set_config('role', v_rol, true);
  RETURN coalesce(nullif(v_out, ''), 'ok');
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.h(p text) RETURNS text LANGUAGE sql AS $f$ SELECT repeat(p, 64); $f$;

CREATE FUNCTION pg_temp.copiar(p_h text, p_rev int, p_copia text, p_versiones text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.como('service_role', format('SELECT public.portal_copiar(%L, %s, %L, %L::int[])::text',
                                             pg_temp.h(p_h), p_rev, p_copia, p_versiones));
$f$;

CREATE FUNCTION pg_temp.leer(p_h text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.como('anon', format('SELECT coalesce(public.portal_leer(%L), %L)', pg_temp.h(p_h), 'NULL'));
$f$;

CREATE FUNCTION pg_temp.visitar(p_h text, p_version int, p_dispositivo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.como('anon', format('SELECT public.portal_visitar(%L, %s, %L::uuid)::text', pg_temp.h(p_h), p_version, p_dispositivo));
$f$;

CREATE FUNCTION pg_temp.visitas(p_h text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.como('service_role', format(
    $q$SELECT coalesce(string_agg(format('v%%s: %%s/%%s', version, visitas, dispositivos), ' ' ORDER BY version), '-')
       FROM public.portal_visitas_de(ARRAY[%L])$q$, pg_temp.h(p_h)));
$f$;

-- ============================================================
-- 01 Copiar
-- ============================================================
SELECT pg_temp.caso('01 copia nueva', 'ok', pg_temp.copiar('a', 3, 'QUFB', '{1,2}'));
SELECT pg_temp.caso('01 anon la lee', 'QUFB', pg_temp.leer('a'));
SELECT pg_temp.caso('01 reintento de la misma revisión no pisa', 'ok', pg_temp.copiar('a', 3, 'QkJC', '{1,2}'));
SELECT pg_temp.caso('01 sigue la primera', 'QUFB', pg_temp.leer('a'));
SELECT pg_temp.caso('01 una revisión vieja que llega tarde', 'ok', pg_temp.copiar('a', 2, 'Q0ND', '{1}'));
SELECT pg_temp.caso('01 sigue la primera, otra vez', 'QUFB', pg_temp.leer('a'));
SELECT pg_temp.caso('01 una revisión nueva', 'ok', pg_temp.copiar('a', 4, 'RERE', '{1,3}'));
SELECT pg_temp.caso('01 la nueva', 'RERE', pg_temp.leer('a'));
SELECT pg_temp.caso('01 sus versiones', '{1,3}', (SELECT versiones::text FROM public.portal_links WHERE huella = pg_temp.h('a')));
SELECT pg_temp.caso('01 huella que no está', 'NULL', pg_temp.leer('f'));

-- ============================================================
-- 02 Lo inválido falla
-- ============================================================
SELECT pg_temp.caso('02 huella corta', '23514', pg_temp.como('service_role',
  'SELECT public.portal_copiar(''abc'', 1, ''QUFB'', ''{1}'')::text'));
SELECT pg_temp.caso('02 huella en mayúsculas', '23514', pg_temp.copiar('A', 1, 'QUFB', '{1}'));
SELECT pg_temp.caso('02 copia que no es base64', '23514', pg_temp.copiar('b', 1, 'no es base64!', '{1}'));
SELECT pg_temp.caso('02 versión NULL', '23514', pg_temp.copiar('b', 1, 'QUFB', '{1,NULL}'));
SELECT pg_temp.caso('02 revisión 0', '23514', pg_temp.copiar('b', 0, 'QUFB', '{1}'));
SELECT pg_temp.caso('02 cortar con versiones', '22023', pg_temp.copiar('b', 1, NULL, '{1}'));
SELECT pg_temp.caso('02 nada quedó', '0', (SELECT count(*)::text FROM public.portal_links WHERE huella = pg_temp.h('b')));

-- ============================================================
-- 03 Visitas
-- ============================================================
SELECT pg_temp.caso('03 primera apertura', 'ok', pg_temp.visitar('a', 1, '00000000-0000-0000-0000-00000000000d'));
SELECT pg_temp.caso('03 una visita', 'v1: 1/1', pg_temp.visitas('a'));
SELECT pg_temp.caso('03 abre de nuevo enseguida', 'ok', pg_temp.visitar('a', 1, '00000000-0000-0000-0000-00000000000d'));
SELECT pg_temp.caso('03 sigue una', 'v1: 1/1', pg_temp.visitas('a'));
UPDATE public.portal_visitas SET ultima = now() - interval '29 minutes';
SELECT pg_temp.visitar('a', 1, '00000000-0000-0000-0000-00000000000d');
SELECT pg_temp.caso('03 a los 29 min sigue una', 'v1: 1/1', pg_temp.visitas('a'));
SELECT pg_temp.caso('03 y la estiró', '1', (SELECT count(*)::text FROM public.portal_visitas WHERE ultima = now()));
UPDATE public.portal_visitas SET ultima = now() - interval '31 minutes';
SELECT pg_temp.visitar('a', 1, '00000000-0000-0000-0000-00000000000d');
SELECT pg_temp.caso('03 a los 31 min es otra', 'v1: 2/1', pg_temp.visitas('a'));
SELECT pg_temp.visitar('a', 1, '00000000-0000-0000-0000-00000000000e');
SELECT pg_temp.caso('03 otro dispositivo', 'v1: 3/2', pg_temp.visitas('a'));
SELECT pg_temp.visitar('a', 3, '00000000-0000-0000-0000-00000000000d');
SELECT pg_temp.caso('03 otra versión, aparte', 'v1: 3/2 v3: 1/1', pg_temp.visitas('a'));
SELECT pg_temp.caso('03 versión que no muestra: no anota ni avisa', 'ok',
  pg_temp.visitar('a', 2, '00000000-0000-0000-0000-00000000000d'));
SELECT pg_temp.visitar('a', 1, NULL);
SELECT pg_temp.visitar('f', 1, '00000000-0000-0000-0000-00000000000d');
SELECT pg_temp.caso('03 sin la v2, sin dispositivo, sin huella', 'v1: 3/2 v3: 1/1', pg_temp.visitas('a'));
SELECT pg_temp.caso('03 huella sin visitas', '-', pg_temp.visitas('f'));

-- ============================================================
-- 04 Cortar
-- ============================================================
SELECT pg_temp.caso('04 cortar', 'ok', pg_temp.copiar('a', 5, NULL, '{}'));
SELECT pg_temp.caso('04 no se lee', 'NULL', pg_temp.leer('a'));
SELECT pg_temp.caso('04 sin copia', 'false|true', (SELECT activo::text || '|' || (copia IS NULL)::text
                                                   FROM public.portal_links WHERE huella = pg_temp.h('a')));
SELECT pg_temp.visitar('a', 1, '00000000-0000-0000-0000-00000000000f');
SELECT pg_temp.caso('04 no anota visitas, y las viejas siguen', 'v1: 3/2 v3: 1/1', pg_temp.visitas('a'));
SELECT pg_temp.caso('04 una copia más nueva no lo revive', 'ok', pg_temp.copiar('a', 9, 'RkZG', '{1}'));
SELECT pg_temp.caso('04 sigue cortado', 'NULL', pg_temp.leer('a'));
SELECT pg_temp.caso('04 cortar uno que nunca se copió', 'ok', pg_temp.copiar('c', 1, NULL, NULL));
SELECT pg_temp.caso('04 y una copia vieja que llega después', 'ok', pg_temp.copiar('c', 1, 'RkZG', '{1}'));
SELECT pg_temp.caso('04 no lo abre', 'NULL', pg_temp.leer('c'));

-- ============================================================
-- 05 Quién puede qué
-- ============================================================
SELECT pg_temp.caso('05 anon no copia', '42501', pg_temp.como('anon', format(
  'SELECT public.portal_copiar(%L, 1, ''QUFB'', ''{1}'')::text', pg_temp.h('d'))));
SELECT pg_temp.caso('05 anon no lee visitas', '42501', pg_temp.como('anon', 'SELECT count(*)::text FROM public.portal_visitas_de(''{}'')'));
SELECT pg_temp.caso('05 anon no lee la tabla de links', '42501', pg_temp.como('anon', 'SELECT count(*)::text FROM public.portal_links'));
SELECT pg_temp.caso('05 anon no lee la tabla de visitas', '42501', pg_temp.como('anon', 'SELECT count(*)::text FROM public.portal_visitas'));
SELECT pg_temp.caso('05 authenticated no ejecuta ninguna', 'false', (
  SELECT bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE'))::text
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace));
SELECT pg_temp.caso('05 PUBLIC no ejecuta ninguna', 'false', (
  SELECT bool_or(acl.grantee = 0)::text
  FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
  WHERE p.pronamespace = 'public'::regnamespace AND acl.privilege_type = 'EXECUTE'));
SELECT pg_temp.caso('05 anon ejecuta solo leer y visitar', 'portal_leer,portal_visitar', (
  SELECT string_agg(p.proname, ',' ORDER BY p.proname)
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE')));
SELECT pg_temp.caso('05 RLS en las dos', 'true', (
  SELECT bool_and(relrowsecurity)::text FROM pg_class WHERE oid IN ('public.portal_links'::regclass, 'public.portal_visitas'::regclass)));

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
