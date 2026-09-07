-- ============================================================
-- 029 — Agenda de Obras: hardening posterior al advisor de Supabase
--
-- Dos cosas que 027/028 dejaron abiertas:
--
-- 1. `GRANT EXECUTE ... TO authenticated` no quita nada: Postgres otorga
--    EXECUTE a PUBLIC por defecto en toda función nueva, así que las
--    SECURITY DEFINER del módulo quedaban invocables por `anon` — sin login —
--    vía /rest/v1/rpc/<nombre>. No era explotable (todas cortan con
--    `tiene_permiso`, falso sin sesión), pero la defensa no puede depender de
--    que nadie toque el guard después. Se revoca de PUBLIC y se otorga
--    explícitamente solo a `authenticated`.
--
-- 2. Los tres helpers inmutables no fijaban `search_path`. No son SECURITY
--    DEFINER, pero `obras_array_sin_duplicados` se evalúa dentro de un CHECK
--    y `obras_normalizar` dentro de triggers: mejor que no dependan del
--    search_path de quien escribe.
--
-- Las funciones de trigger se revocan de PUBLIC sin otorgarse a nadie: el
-- disparo del trigger no verifica EXECUTE del usuario, se resolvió al crearlo.
-- ============================================================

-- ============================================================
-- 1. search_path fijo en los helpers
-- ============================================================
ALTER FUNCTION public.obras_normalizar(text)           SET search_path = public, extensions;
ALTER FUNCTION public.obras_normalizar_telefono(text)  SET search_path = public, extensions;
ALTER FUNCTION public.obras_array_sin_duplicados(anyarray) SET search_path = public;

-- ============================================================
-- 2. Fuera de PUBLIC
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_set_activo(uuid, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_buscar_duplicados_obra(text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_buscar_duplicados_empresa(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_buscar_duplicados_persona(text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_ficha_persona(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_puede_ver_obra(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_puede_ver_persona(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_es_mi_obra(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_normalizar(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_normalizar_telefono(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_array_sin_duplicados(anyarray) FROM PUBLIC;

-- Solo de trigger: nadie las llama por RPC.
REVOKE EXECUTE ON FUNCTION public.obras_normalizar_obra() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_normalizar_empresa() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_normalizar_persona() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_guard_desactivar_empresa() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_guard_desactivar_persona() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.obras_cascada_desactivar() FROM PUBLIC;

-- ============================================================
-- 3. Solo `authenticated`
--
-- Las tres de visibilidad las necesita el rol para que las policies puedan
-- evaluarlas; las de normalización, para los CHECK y los triggers.
-- ============================================================
GRANT EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_set_activo(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_buscar_duplicados_obra(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_buscar_duplicados_empresa(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_buscar_duplicados_persona(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_ficha_persona(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_puede_ver_obra(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_puede_ver_persona(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_es_mi_obra(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_normalizar(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_normalizar_telefono(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obras_array_sin_duplicados(anyarray) TO authenticated;
