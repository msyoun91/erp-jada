-- sql/141 — obras y contactos, tramo 3: el aviso a ciegas ordena por parecido.
--
-- - Corta en 10, y ordenado por nombre la más parecida podía quedar afuera:
--   con once "Torre Belgrano Zqx…" de corridas anteriores, "Zqx139 Torre
--   Belgrano" no salía en su propio aviso. Ahora, lo que ve primero (como
--   antes), después mismo teléfono o email, después el nombre más parecido.
-- - Solo cambia el ORDER BY; el resto, igual que sql/138 (obras) y sql/140
--   (contactos).
--
-- Decisión: `decisiones/obras.md` → *Altas parecidas*. Test: `sql/tests/duplicados.sql`.

CREATE OR REPLACE FUNCTION public.obras_parecidas(p_nombre text, p_direccion text, p_obra uuid DEFAULT NULL)
RETURNS TABLE (id uuid, nombre text, direccion text, responsable text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN x.ve THEN o.id END, o.nombre, CASE WHEN x.ve THEN o.direccion END, u.nombre
  FROM public.obras_parecidas_de(p_obra, p_nombre, p_direccion) p
  JOIN public.obras o    ON o.id = p.id
  JOIN public.usuarios u ON u.id = o.responsable_id
  CROSS JOIN LATERAL (
    SELECT public.obras_puede_ver_obra_de(o.id, o.responsable_id, o.equipo_id, o.activo, auth.uid()) AS ve
  ) x
  WHERE public.tiene_permiso('obras_ver')
  ORDER BY x.ve DESC,
           extensions.similarity(public.normalizar_texto(o.nombre), public.normalizar_texto(p_nombre)) DESC,
           o.nombre
  LIMIT 10;
$$;

CREATE OR REPLACE FUNCTION public.contactos_parecidas(
  p_tipo text, p_nombre text, p_telefono text DEFAULT NULL, p_email text DEFAULT NULL, p_id uuid DEFAULT NULL
)
RETURNS TABLE (id uuid, nombre text, dueno text, equipo text, coincide text[])
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN c.tuya AND NOT c.congelada THEN c.id END, c.nombre, u.nombre, c.equipo,
         CASE WHEN c.tuya THEN c.coincide END
  FROM (
    SELECT p.id, p.nombre, p.responsable_id AS dueno_id, NULL::text AS equipo, x.coincide, p.congelada,
           p.responsable_id = auth.uid() AS tuya
    FROM public.contactos_personas_parecidas_de(p_id, p_nombre, p_telefono, p_email) x
    JOIN public.contactos_personas p ON p.id = x.id
    WHERE p_tipo = 'persona'
    UNION ALL
    SELECT e.id, e.nombre, e.creado_por, q.nombre, '{nombre}'::text[], e.congelada,
           public.contactos_empresa_del_equipo_de(e.id, e.equipo_id, e.creado_por, auth.uid())
    FROM public.contactos_empresas_parecidas_de(p_id, p_nombre) x
    JOIN public.contactos_empresas e ON e.id = x.id
    LEFT JOIN public.equipos q       ON q.id = e.equipo_id
    WHERE p_tipo = 'empresa'
  ) c
  JOIN public.usuarios u ON u.id = c.dueno_id
  WHERE public.tiene_permiso('contactos_ver')
  ORDER BY c.tuya DESC,
           c.coincide && '{telefono,email}' DESC,
           extensions.similarity(public.normalizar_texto(c.nombre), public.normalizar_texto(p_nombre)) DESC,
           c.nombre
  LIMIT 10;
$$;
