-- sql/140 — contactos, tramo 3: una empresa se comparte con otro equipo.
--
-- - `contactos_empresa_equipos`: el equipo con el que se compartió la ve, la
--   vincula y la corrige como propia. Sigue siendo del equipo dueño: la
--   desactiva su jefe y la reactiva el admin.
-- - "Es de mi equipo" (el suyo, sin equipo quien la cargó, o compartida con
--   el mío) lo contesta una sola función, `contactos_empresa_del_equipo_de`,
--   que usan ver, corregir, vincular, el buscador y el aviso a ciegas.
-- - Comparten y dejan de compartir el equipo dueño (sin equipo, quien la
--   cargó) o el admin, con `contactos_compartir_empresa`. Congelada no se
--   comparte (CO020). Dejar de compartir no toca los vínculos que el otro
--   equipo ya creó: solo deja de poder vincularla de nuevo.
-- - Sin campanita ni evento: la respuesta al pedido de Tareas ya avisa.
--
-- Decisión: `decisiones/contactos.md` → *Una empresa se comparte con otro
-- equipo*. Test: `sql/tests/contactos_compartir.sql`.

-- ============================================================
-- 1. contactos_empresa_equipos
-- ============================================================
-- Volver a compartir es una fila nueva, como los vínculos.
CREATE TABLE IF NOT EXISTS public.contactos_empresa_equipos (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     uuid NOT NULL REFERENCES public.contactos_empresas(id),
  equipo_id      uuid NOT NULL REFERENCES public.equipos(id),
  compartida_por uuid NOT NULL REFERENCES public.usuarios(id),
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS contactos_empresa_equipos_unica
  ON public.contactos_empresa_equipos (empresa_id, equipo_id) WHERE activo;
CREATE INDEX IF NOT EXISTS contactos_empresa_equipos_equipo
  ON public.contactos_empresa_equipos (equipo_id) WHERE activo;

ALTER TABLE public.contactos_empresa_equipos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.contactos_empresa_equipos FROM anon, authenticated;
GRANT SELECT ON public.contactos_empresa_equipos TO authenticated;

-- Se ve con la empresa. La escribe solo `contactos_compartir_empresa`.
DROP POLICY IF EXISTS contactos_empresa_equipos_select ON public.contactos_empresa_equipos;
CREATE POLICY contactos_empresa_equipos_select ON public.contactos_empresa_equipos
  FOR SELECT TO authenticated
  USING (activo AND EXISTS (SELECT 1 FROM public.contactos_empresas e WHERE e.id = empresa_id));

DROP TRIGGER IF EXISTS set_updated_at ON public.contactos_empresa_equipos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.contactos_empresa_equipos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 2. "Es de mi equipo"
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_empresa_del_equipo_de(
  p_empresa uuid, p_equipo uuid, p_creado_por uuid, p_usuario uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_equipo = public.equipo_de(p_usuario)
    OR (p_equipo IS NULL AND p_creado_por = p_usuario)
    OR EXISTS (
      SELECT 1 FROM public.contactos_empresa_equipos c
      WHERE c.empresa_id = p_empresa AND c.activo AND c.equipo_id = public.equipo_de(p_usuario)
    );
$$;

CREATE OR REPLACE FUNCTION public.contactos_empresa_de_mi_equipo(p_empresa uuid, p_equipo uuid, p_creado_por uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.contactos_empresa_del_equipo_de(p_empresa, p_equipo, p_creado_por, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_empresa_del_equipo_de(uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_empresa_de_mi_equipo(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_empresa_de_mi_equipo(uuid, uuid, uuid) TO authenticated;

-- ============================================================
-- 3. Ver
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_puede_ver_empresa_de(
  p_empresa uuid, p_equipo uuid, p_creado_por uuid, p_activo boolean, p_usuario uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'contactos_administrar')
    OR (
      public.usuario_tiene_permiso(p_usuario, 'contactos_ver')
      AND (
        (p_activo AND CASE
          WHEN EXISTS (
            SELECT 1 FROM public.contactos_empresas c
            WHERE c.id = p_empresa AND c.congelada AND c.congelada_antes IS NULL
          ) THEN p_creado_por = p_usuario
          ELSE public.contactos_empresa_del_equipo_de(p_empresa, p_equipo, p_creado_por, p_usuario)
        END)
        OR EXISTS (
          SELECT 1 FROM public.contactos_vinculos v
          WHERE v.empresa_id = p_empresa AND v.activo
            AND public.puede_abrir_registro(v.ente, v.registro_id, p_usuario)
        )
      )
    );
$$;

-- ============================================================
-- 4. Corregir: también el equipo con el que se compartió
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_empresas_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adm boolean;
BEGIN
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL AND NEW.congelada IS NOT DISTINCT FROM OLD.congelada THEN
    v_adm := public.usuario_tiene_permiso(v_uid, 'contactos_administrar');

    IF (NEW.nombre, NEW.telefono, NEW.email, NEW.web, NEW.notas)
       IS DISTINCT FROM (OLD.nombre, OLD.telefono, OLD.email, OLD.web, OLD.notas)
       AND NOT v_adm
       AND NOT (
         OLD.activo AND (
           public.contactos_empresa_del_equipo_de(OLD.id, OLD.equipo_id, OLD.creado_por, v_uid)
           OR EXISTS (
             SELECT 1 FROM public.contactos_vinculos v
             WHERE v.empresa_id = OLD.id AND v.activo AND public.trabaja_registro(v.ente, v.registro_id)
           )
         )
       ) THEN
      RAISE EXCEPTION 'Corrigen una empresa su equipo, el admin o quien trabaja una obra donde está' USING ERRCODE = 'CO006';
    END IF;

    IF OLD.activo AND NOT NEW.activo AND NOT v_adm AND NOT (
      CASE WHEN OLD.equipo_id IS NULL OR (OLD.congelada AND OLD.congelada_antes IS NULL) THEN OLD.creado_por = v_uid
           ELSE OLD.equipo_id = public.equipo_de(v_uid) AND public.usuario_tiene_permiso(v_uid, 'usuarios_delegar')
      END
    ) THEN
      RAISE EXCEPTION 'Desactivan una empresa el jefe de su equipo o el admin' USING ERRCODE = 'CO007';
    END IF;

    IF NOT OLD.activo AND NEW.activo AND NOT v_adm THEN
      RAISE EXCEPTION 'Solo el admin reactiva un contacto' USING ERRCODE = 'CO004';
    END IF;

    IF NEW.equipo_id IS DISTINCT FROM OLD.equipo_id AND NOT v_adm THEN
      RAISE EXCEPTION 'Solo el admin cambia el equipo de una empresa' USING ERRCODE = 'CO008';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 5. Vincular: también el equipo con el que se compartió
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_vinculos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_actor uuid := NEW.creado_por;
  v_contacto text;
  v_registro text;
BEGIN
  IF TG_OP = 'INSERT' OR NEW.roles IS DISTINCT FROM OLD.roles THEN
    NEW.roles := ARRAY(SELECT DISTINCT r FROM unnest(NEW.roles) r ORDER BY r);
    IF NOT NEW.roles <@ (SELECT e.roles FROM public.entes e WHERE e.codigo = NEW.ente) THEN
      RAISE EXCEPTION 'Ese rol no existe para ese registro' USING ERRCODE = 'CO014';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.activo := true;
    IF NOT EXISTS (SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND activo)
       AND NOT EXISTS (SELECT 1 FROM public.contactos_empresas WHERE id = NEW.empresa_id AND activo) THEN
      RAISE EXCEPTION 'Una persona o una empresa desactivada no se vincula' USING ERRCODE = 'CO009';
    END IF;
  ELSIF OLD.hasta IS NOT NULL AND (NEW.hasta, NEW.roles) IS DISTINCT FROM (OLD.hasta, OLD.roles) THEN
    RAISE EXCEPTION 'Un vínculo cerrado no se cambia: volver es un vínculo nuevo' USING ERRCODE = 'CO010';
  ELSIF NOT OLD.activo AND NEW.activo THEN
    RAISE EXCEPTION 'Un vínculo desactivado no vuelve: se vincula de nuevo' USING ERRCODE = 'CO011';
  END IF;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL THEN
    IF TG_OP = 'INSERT' THEN
      IF NOT public.trabaja_registro_de(NEW.ente, NEW.registro_id, v_actor) THEN
        RAISE EXCEPTION 'Vinculan y cambian contactos quienes trabajan el registro' USING ERRCODE = 'CO015';
      END IF;

      IF NOT public.usuario_tiene_permiso(v_actor, 'contactos_administrar') AND NOT (
        EXISTS (SELECT 1 FROM public.contactos_personas WHERE id = NEW.persona_id AND responsable_id = v_actor)
        OR EXISTS (
          SELECT 1 FROM public.contactos_empresas e
          WHERE e.id = NEW.empresa_id
            AND public.contactos_empresa_del_equipo_de(e.id, e.equipo_id, e.creado_por, v_actor)
        )
        OR EXISTS (
          SELECT 1 FROM public.contactos_vinculos_guardados g
          WHERE g.activo AND g.cargado_por = v_actor AND g.ente = NEW.ente AND g.registro_id = NEW.registro_id
            AND (g.persona_id = NEW.persona_id OR g.empresa_id = NEW.empresa_id)
        )
      ) THEN
        RAISE EXCEPTION 'Vincula una persona su dueño, y una empresa su equipo' USING ERRCODE = 'CO016';
      END IF;
    ELSIF NOT public.trabaja_registro(NEW.ente, NEW.registro_id) AND NOT EXISTS (
      SELECT 1 FROM public.contactos_vinculos_guardados g
      WHERE g.activo AND g.ente = NEW.ente AND g.registro_id = NEW.registro_id
        AND (g.persona_id = NEW.persona_id OR g.empresa_id = NEW.empresa_id)
        AND public.trabaja_registro_de(g.ente, g.registro_id, g.cargado_por)
    ) THEN
      RAISE EXCEPTION 'Vinculan y cambian contactos quienes trabajan el registro' USING ERRCODE = 'CO015';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_contacto := public.contactos_congelado(NEW.persona_id, NEW.empresa_id);
    v_registro := public.registro_congelado(NEW.ente, NEW.registro_id);
    IF 'si' IN (v_contacto, v_registro) THEN
      RAISE EXCEPTION 'Espera aprobación: no se vincula hasta que la aprueben' USING ERRCODE = 'CO020';
    END IF;
    IF 'nueva' IN (v_contacto, v_registro) THEN
      INSERT INTO public.contactos_vinculos_guardados (persona_id, empresa_id, ente, registro_id, roles, cargado_por)
      VALUES (NEW.persona_id, NEW.empresa_id, NEW.ente, NEW.registro_id, NEW.roles, v_actor);
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 6. Buscar para vincular y aviso a ciegas: la compartida es tuya
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_vinculables(p_texto text)
RETURNS TABLE (tipo text, id uuid, nombre text, detalle text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(btrim(p_texto)) AS t
    WHERE length(btrim(p_texto)) >= 2
  ),
  encontrados AS (
    SELECT 'persona'::text AS tipo, p.id, p.nombre,
           (SELECT e.nombre
            FROM public.contactos_persona_empresa pe
            JOIN public.contactos_empresas e ON e.id = pe.empresa_id
            WHERE pe.persona_id = p.id AND pe.activo AND pe.hasta IS NULL
            ORDER BY pe.desde DESC
            LIMIT 1) AS detalle,
           strpos(lower(p.nombre), q.t) AS pos
    FROM q
    JOIN public.contactos_personas p
      ON p.activo AND NOT p.congelada AND p.responsable_id = (select auth.uid()) AND strpos(lower(p.nombre), q.t) > 0
    UNION ALL
    SELECT 'empresa', e.id, e.nombre, NULL, strpos(lower(e.nombre), q.t)
    FROM q
    JOIN public.contactos_empresas e
      ON e.activo AND NOT e.congelada
     AND public.contactos_empresa_de_mi_equipo(e.id, e.equipo_id, e.creado_por)
     AND strpos(lower(e.nombre), q.t) > 0
  )
  SELECT tipo, id, nombre, detalle
  FROM encontrados
  ORDER BY pos <> 1, nombre
  LIMIT 15;
$$;

-- Si es tuya (la persona, de tu agenda; la empresa, de tu equipo o compartida
-- con él), entera: id para "Vincular esa" y qué coincidió. De otro, nombre,
-- dueño y, de una empresa, su equipo, así se la pide a ese equipo.
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
  ORDER BY c.tuya DESC, c.nombre
  LIMIT 10;
$$;

-- ============================================================
-- 7. Compartir y dejar de compartir
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_compartir_empresa(p_empresa uuid, p_equipo uuid, p_compartir boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_empresa public.contactos_empresas%ROWTYPE;
BEGIN
  SELECT * INTO v_empresa FROM public.contactos_empresas WHERE id = p_empresa AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa empresa no existe o está desactivada' USING ERRCODE = 'CO018';
  END IF;

  IF NOT public.usuario_tiene_permiso(v_uid, 'contactos_administrar') AND NOT (
    public.usuario_tiene_permiso(v_uid, 'contactos_ver')
    AND (v_empresa.equipo_id = public.equipo_de(v_uid)
         OR (v_empresa.equipo_id IS NULL AND v_empresa.creado_por = v_uid))
  ) THEN
    RAISE EXCEPTION 'Comparten una empresa su equipo o el admin' USING ERRCODE = 'CO027';
  END IF;

  IF p_compartir THEN
    IF v_empresa.congelada THEN
      RAISE EXCEPTION 'Espera aprobación: no se comparte hasta que la aprueben' USING ERRCODE = 'CO020';
    END IF;
    IF p_equipo IS NOT DISTINCT FROM v_empresa.equipo_id
       OR NOT EXISTS (SELECT 1 FROM public.equipos WHERE id = p_equipo AND activo) THEN
      RAISE EXCEPTION 'Ese equipo no existe o ya es el de la empresa' USING ERRCODE = 'CO028';
    END IF;
    INSERT INTO public.contactos_empresa_equipos (empresa_id, equipo_id, compartida_por)
    VALUES (p_empresa, p_equipo, v_uid)
    ON CONFLICT (empresa_id, equipo_id) WHERE activo DO NOTHING;
  ELSE
    UPDATE public.contactos_empresa_equipos
    SET activo = false
    WHERE empresa_id = p_empresa AND equipo_id = p_equipo AND activo;
  END IF;
END;
$$;

-- Con quién compartir: los equipos activos (el vendedor no lee `equipos`).
CREATE OR REPLACE FUNCTION public.contactos_equipos()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT q.id, q.nombre
  FROM public.equipos q
  WHERE q.activo AND public.tiene_permiso('contactos_ver')
  ORDER BY q.nombre;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_compartir_empresa(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_compartir_empresa(uuid, uuid, boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_equipos() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_equipos() TO authenticated;
