-- ============================================================
-- 054 — `obras_buscar_duplicados_empresa` vuelve a ser solo de authenticated
--
-- `sql/042` la dropeó y la recreó como DEFINER (cambiaba el tipo de retorno)
-- sin repetir el REVOKE/GRANT que le había puesto `sql/031`. Una función
-- recreada nace con EXECUTE para PUBLIC, así que quedó llamable sin sesión
-- por `/rest/v1/rpc/`. No filtraba datos —sin `auth.uid()` el WHERE
-- `tiene_permiso(...)` da false— pero era la única DEFINER abierta a anon y
-- la barrera era ese WHERE. Lo marcó `get_advisors('security')`, lint 0028.
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.obras_buscar_duplicados_empresa(text, text, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.obras_buscar_duplicados_empresa(text, text, uuid) TO authenticated;
