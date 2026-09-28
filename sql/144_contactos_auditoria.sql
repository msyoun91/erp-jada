-- sql/144 — contactos, tramo 4: Auditoría, quién miró teléfono o email.
--
-- - Vista `contactos_auditoria` ("Auditoría", no delegable). No pide
--   `contactos_ver`: el auditor no necesita ver la agenda de nadie.
-- - Tres funciones DEFINER sobre `contactos_accesos`, vacías sin la vista.
--   Devuelven nombres y fechas, nunca el dato: la pantalla que vigila el
--   acceso no es otra puerta al contacto.
--   · `contactos_auditoria_resumen(dias)`: por usuario, accesos y personas
--     distintas, de más a menos.
--   · `contactos_auditoria_detalle(dias, usuario?, persona?)`: cada acceso,
--     con el dueño actual de la persona. Hasta 501 filas: la pantalla muestra
--     500 y, si llegó la 501, avisa que hay más.
--   · `contactos_auditoria_personas(texto)`: el buscador del filtro "¿quién
--     miró a Marta?"; solo personas con algún acceso.
--
-- Decisiones: `decisiones/contactos.md` → *El registro lo mira una vista
-- propia* y *Auditoría: resumen por usuario*. Test:
-- `sql/tests/contactos_auditoria.sql`.

-- ============================================================
-- 1. Permiso
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, delegable)
SELECT 'contactos_auditoria', 'contactos', 'vista', 'Auditoría', 2, false
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = 'contactos_auditoria' AND s.activo);

-- ============================================================
-- 2. Resumen, detalle y buscador
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_auditoria_resumen(p_dias int)
RETURNS TABLE (usuario_id uuid, usuario text, accesos int, personas int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.usuario_id, u.nombre, count(*)::int, count(DISTINCT a.persona_id)::int
  FROM public.contactos_accesos a
  JOIN public.usuarios u ON u.id = a.usuario_id
  WHERE public.tiene_permiso('contactos_auditoria')
    AND a.created_at >= now() - make_interval(days => greatest(p_dias, 0))
  GROUP BY a.usuario_id, u.nombre
  ORDER BY count(*) DESC, u.nombre;
$$;

CREATE OR REPLACE FUNCTION public.contactos_auditoria_detalle(
  p_dias int, p_usuario uuid DEFAULT NULL, p_persona uuid DEFAULT NULL
)
RETURNS TABLE (
  usuario_id uuid, usuario text, persona_id uuid, persona text, dueno_id uuid, dueno text, created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.usuario_id, u.nombre, a.persona_id, p.nombre, p.responsable_id, d.nombre, a.created_at
  FROM public.contactos_accesos a
  JOIN public.usuarios u            ON u.id = a.usuario_id
  JOIN public.contactos_personas p  ON p.id = a.persona_id
  JOIN public.usuarios d            ON d.id = p.responsable_id
  WHERE public.tiene_permiso('contactos_auditoria')
    AND a.created_at >= now() - make_interval(days => greatest(p_dias, 0))
    AND (p_usuario IS NULL OR a.usuario_id = p_usuario)
    AND (p_persona IS NULL OR a.persona_id = p_persona)
  ORDER BY a.created_at DESC
  LIMIT 501;
$$;

CREATE OR REPLACE FUNCTION public.contactos_auditoria_personas(p_texto text)
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.nombre
  FROM public.contactos_personas p
  WHERE public.tiene_permiso('contactos_auditoria')
    AND length(btrim(p_texto)) >= 2
    AND strpos(lower(p.nombre), lower(btrim(p_texto))) > 0
    AND EXISTS (SELECT 1 FROM public.contactos_accesos a WHERE a.persona_id = p.id)
  ORDER BY strpos(lower(p.nombre), lower(btrim(p_texto))) <> 1, p.nombre
  LIMIT 15;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_auditoria_resumen(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_auditoria_resumen(int) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_auditoria_detalle(int, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_auditoria_detalle(int, uuid, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_auditoria_personas(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_auditoria_personas(text) TO authenticated;
