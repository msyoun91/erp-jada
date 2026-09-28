-- sql/130 — obras y contactos: nombres de quienes aparecen en lo que se ve, y a quién se transfiere.
--
-- `usuarios_select` no deja ver otros equipos (`sql/104`): la ficha de una obra
-- quedaba sin el nombre del responsable ni de los participantes, y transferir
-- sin a quién ofrecer. Mismo patrón que `tareas_nombres()` y
-- `tareas_asignables()` (`sql/116`, `sql/120`): solo id y nombre, con las
-- reglas de las policies; no autoriza nada. Decisión: `decisiones/obras.md` →
-- *Los nombres de lo que se ve*. Verificado con `sql/tests/obras_nombres.sql`.

-- Los activos con el permiso, para quien también lo tiene: a quién se
-- transfiere una obra (`obras_ver`) o una persona (`contactos_ver`), y a quién
-- se suma de participante. Los triggers vuelven a exigirlo (OB006, OB014, CO005).
CREATE OR REPLACE FUNCTION public.usuarios_con_permiso(p_codigo text)
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id, u.nombre
  FROM usuarios u
  WHERE u.activo
    AND public.tiene_permiso(p_codigo)
    AND public.usuario_tiene_permiso(u.id, p_codigo)
  ORDER BY u.nombre;
$$;

REVOKE EXECUTE ON FUNCTION public.usuarios_con_permiso(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.usuarios_con_permiso(text) TO authenticated;

-- Responsable, quien la cargó, participantes (y quién los sumó) y los actores
-- y transferencias del historial de las obras que quien llama ve.
CREATE OR REPLACE FUNCTION public.obras_nombres()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH o AS (
    SELECT o.id, o.responsable_id, o.creado_por
    FROM obras o
    WHERE public.obras_puede_ver_obra_de(o.id, o.responsable_id, o.equipo_id, o.activo, auth.uid())
  ),
  ev AS (
    SELECT e.actor_id, e.evento, e.detalle
    FROM eventos e JOIN o ON o.id = e.registro_id
    WHERE e.ente = 'obra'
  ),
  refs AS (
    SELECT responsable_id AS id FROM o
    UNION SELECT creado_por FROM o
    UNION SELECT p.usuario_id FROM obras_participantes p JOIN o ON o.id = p.obra_id
    UNION SELECT p.agregado_por FROM obras_participantes p JOIN o ON o.id = p.obra_id
    UNION SELECT actor_id FROM ev
    UNION SELECT (detalle->>'de')::uuid FROM ev WHERE evento = 'transferencia'
    UNION SELECT (detalle->>'a')::uuid FROM ev WHERE evento = 'transferencia'
  )
  SELECT u.id, u.nombre FROM usuarios u JOIN refs r ON r.id = u.id;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_nombres() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_nombres() TO authenticated;

-- Dueño y quien cargó cada persona y empresa que quien llama ve, el equipo de
-- la empresa y los autores de sus ediciones (también las de teléfono y email:
-- el nombre de quien editó no es el dato).
CREATE OR REPLACE FUNCTION public.contactos_nombres()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH p AS (
    SELECT p.id, p.responsable_id, p.creado_por
    FROM contactos_personas p
    WHERE public.contactos_puede_ver_persona_de(p.id, p.responsable_id, p.activo, auth.uid())
  ),
  e AS (
    SELECT e.id, e.creado_por, e.equipo_id
    FROM contactos_empresas e
    WHERE public.contactos_puede_ver_empresa_de(e.id, e.equipo_id, e.creado_por, e.activo, auth.uid())
  ),
  refs AS (
    SELECT responsable_id AS id FROM p
    UNION SELECT creado_por FROM p
    UNION SELECT creado_por FROM e
    UNION SELECT d.actor_id FROM contactos_ediciones d JOIN p ON p.id = d.persona_id
    UNION SELECT d.actor_id FROM contactos_ediciones d JOIN e ON e.id = d.empresa_id
  )
  SELECT u.id, u.nombre FROM usuarios u JOIN refs r ON r.id = u.id
  UNION ALL
  SELECT q.id, q.nombre FROM equipos q WHERE q.id IN (SELECT equipo_id FROM e);
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_nombres() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_nombres() TO authenticated;
