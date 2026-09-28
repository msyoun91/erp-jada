-- sql/146 — contactos, tramo 4: fusionar dos personas o dos empresas.
--
-- - `contactos_fusionar(tipo, queda, se_va, telefono_de_la_otra,
--   email_de_la_otra, conservar[])` — `contactos_administrar` (CO029). Las dos
--   activas y aprobadas (CO030): la congelada se resuelve con "es la misma".
--   La que queda conserva dueño y nombre; teléfono y email, los elige el
--   admin campo por campo. La que se va se desactiva con `fusionada_en`; sus
--   ediciones y accesos quedan donde estaban.
-- - Vínculos: los de la que se va pasan a la que queda. Si las dos tenían uno
--   abierto en el mismo registro (un choque), queda uno con los roles
--   sumados: el de la que queda, salvo que el admin lo ponga en `conservar`
--   (el de la que se va). El otro se desactiva con `fusionado_en`, y
--   `contactos_vinculos_fusionar` suma sus roles al que queda. Persona ↔
--   empresa, igual: un choque deja una sola relación abierta.
-- - La comisión es de Obras: su trigger sobre el puente la pasa al vínculo
--   que queda; si ese ya tenía una activa, la otra pasa desactivada, como
--   historial. Así el admin elige la comisión eligiendo el vínculo.
-- - Los guardados que apuntan a la que se va (una persona aprobada vinculada
--   a una obra congelada) pasan a la que queda.
-- - Dos empresas de equipos distintos: la que queda se comparte con el
--   equipo de la otra y con los que la otra estaba compartida.
-- - Campanita `persona_fusionada` al dueño de la que se va.
-- - Lo que apunta a la que se va (tareas, eventos, links) no se toca:
--   `contactos_fusionada(tipo, id)` da a la ficha el "Se fusionó con …".
--
-- Las reglas de actor de `contactos_vinculos_validar` no miran un UPDATE que
-- cambia el contacto o `fusionado_en`: esas columnas no tienen GRANT, las
-- escribe solo esta función.
--
-- Decisiones: `decisiones/contactos.md` → *Fusionar*, *Fusionar dos vínculos
-- con comisión* y *Una congelada no se fusiona*. Test:
-- `sql/tests/contactos_fusionar.sql`.

-- ============================================================
-- 1. Columnas
-- ============================================================
ALTER TABLE public.contactos_personas
  ADD COLUMN IF NOT EXISTS fusionada_en uuid REFERENCES public.contactos_personas(id);
ALTER TABLE public.contactos_empresas
  ADD COLUMN IF NOT EXISTS fusionada_en uuid REFERENCES public.contactos_empresas(id);
ALTER TABLE public.contactos_vinculos
  ADD COLUMN IF NOT EXISTS fusionado_en uuid REFERENCES public.contactos_vinculos(id);

GRANT SELECT (fusionada_en) ON public.contactos_personas TO authenticated;

-- ============================================================
-- 2. Vincular: la fusión no pasa por las reglas de actor
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
    NEW.fusionado_en := NULL;
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
    ELSIF (NEW.persona_id, NEW.empresa_id, NEW.fusionado_en) IS NOT DISTINCT FROM (OLD.persona_id, OLD.empresa_id, OLD.fusionado_en)
      AND NOT public.trabaja_registro(NEW.ente, NEW.registro_id) AND NOT EXISTS (
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

-- El vínculo que se va suma sus roles al que queda.
CREATE OR REPLACE FUNCTION public.contactos_vinculos_fusionar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.contactos_vinculos SET roles = roles || NEW.roles WHERE id = NEW.fusionado_en;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_vinculos_fusionar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS contactos_vinculos_fusionar ON public.contactos_vinculos;
CREATE TRIGGER contactos_vinculos_fusionar
  AFTER UPDATE OF fusionado_en ON public.contactos_vinculos
  FOR EACH ROW WHEN (OLD.fusionado_en IS NULL AND NEW.fusionado_en IS NOT NULL)
  EXECUTE FUNCTION public.contactos_vinculos_fusionar();

-- ============================================================
-- 3. Obras: la comisión sigue al vínculo que queda
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_vinculo_con_comision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.fusionado_en IS NULL AND NEW.fusionado_en IS NOT NULL THEN
    UPDATE public.obras_comisiones c
    SET vinculo_id = NEW.fusionado_en,
        activo = c.activo AND NOT EXISTS (
          SELECT 1 FROM public.obras_comisiones q WHERE q.vinculo_id = NEW.fusionado_en AND q.activo
        )
    WHERE c.vinculo_id = NEW.id;
    RETURN NULL;
  END IF;

  IF NEW.activo AND NEW.hasta IS NULL AND 'referente' = ANY (NEW.roles) THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.obras_comisiones c WHERE c.vinculo_id = NEW.id AND c.activo) THEN
    RETURN NULL;
  END IF;

  IF pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL
     AND NOT public.obras_a_cargo_de(NEW.registro_id, auth.uid()) THEN
    RAISE EXCEPTION 'Este referente lo maneja el responsable de la obra' USING ERRCODE = 'OB039';
  END IF;

  UPDATE public.obras_comisiones SET activo = false WHERE vinculo_id = NEW.id AND activo;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS obras_vinculo_con_comision ON public.contactos_vinculos;
CREATE TRIGGER obras_vinculo_con_comision
  AFTER UPDATE OF roles, hasta, activo, fusionado_en ON public.contactos_vinculos
  FOR EACH ROW WHEN (NEW.ente = 'obra')
  EXECUTE FUNCTION public.obras_vinculo_con_comision();

-- ============================================================
-- 4. Fusionar
-- ============================================================
CREATE OR REPLACE FUNCTION public.contactos_fusionar(
  p_tipo text, p_queda uuid, p_se_va uuid,
  p_telefono_de_la_otra boolean DEFAULT false, p_email_de_la_otra boolean DEFAULT false,
  p_conservar uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_col text := CASE p_tipo WHEN 'persona' THEN 'persona_id' WHEN 'empresa' THEN 'empresa_id' END;
  v_telefono text;
  v_email text;
  v_dueno uuid;
  v public.contactos_vinculos;
  v_choque uuid;
  pe public.contactos_persona_empresa;
BEGIN
  IF NOT public.usuario_tiene_permiso(v_uid, 'contactos_administrar') THEN
    RAISE EXCEPTION 'Fusiona contactos el admin' USING ERRCODE = 'CO029';
  END IF;

  IF p_tipo = 'persona' THEN
    PERFORM 1 FROM public.contactos_personas
    WHERE id IN (p_queda, p_se_va) AND activo AND NOT congelada FOR UPDATE;
    SELECT telefono, email, responsable_id INTO v_telefono, v_email, v_dueno
    FROM public.contactos_personas WHERE id = p_se_va;
  ELSIF p_tipo = 'empresa' THEN
    PERFORM 1 FROM public.contactos_empresas
    WHERE id IN (p_queda, p_se_va) AND activo AND NOT congelada FOR UPDATE;
    SELECT telefono, email INTO v_telefono, v_email FROM public.contactos_empresas WHERE id = p_se_va;
  END IF;
  IF v_col IS NULL OR p_queda IS NOT DISTINCT FROM p_se_va OR (
    SELECT count(*) FROM (
      SELECT id FROM public.contactos_personas WHERE p_tipo = 'persona' AND id IN (p_queda, p_se_va) AND activo AND NOT congelada
      UNION ALL
      SELECT id FROM public.contactos_empresas WHERE p_tipo = 'empresa' AND id IN (p_queda, p_se_va) AND activo AND NOT congelada
    ) x
  ) <> 2 THEN
    RAISE EXCEPTION 'Se fusionan dos personas o dos empresas distintas, activas y aprobadas' USING ERRCODE = 'CO030';
  END IF;

  -- Primero se va: así el dato que se copia no la encuentra parecida.
  IF p_tipo = 'persona' THEN
    UPDATE public.contactos_personas SET activo = false, fusionada_en = p_queda WHERE id = p_se_va;
    IF p_telefono_de_la_otra OR p_email_de_la_otra THEN
      UPDATE public.contactos_personas
      SET telefono = CASE WHEN p_telefono_de_la_otra THEN v_telefono ELSE telefono END,
          email    = CASE WHEN p_email_de_la_otra THEN v_email ELSE email END
      WHERE id = p_queda;
    END IF;
  ELSE
    UPDATE public.contactos_empresas SET activo = false, fusionada_en = p_queda WHERE id = p_se_va;
    IF p_telefono_de_la_otra OR p_email_de_la_otra THEN
      UPDATE public.contactos_empresas
      SET telefono = CASE WHEN p_telefono_de_la_otra THEN v_telefono ELSE telefono END,
          email    = CASE WHEN p_email_de_la_otra THEN v_email ELSE email END
      WHERE id = p_queda;
    END IF;
  END IF;

  -- Vínculos con registros
  FOR v IN
    EXECUTE format('SELECT * FROM public.contactos_vinculos WHERE %I = $1 ORDER BY created_at FOR UPDATE', v_col)
    USING p_se_va
  LOOP
    v_choque := NULL;
    IF v.activo AND v.hasta IS NULL THEN
      EXECUTE format(
        'SELECT id FROM public.contactos_vinculos
         WHERE %I = $1 AND ente = $2 AND registro_id = $3 AND activo AND hasta IS NULL', v_col)
      INTO v_choque USING p_queda, v.ente, v.registro_id;
    END IF;

    IF v_choque IS NULL THEN
      EXECUTE format('UPDATE public.contactos_vinculos SET %I = $1 WHERE id = $2', v_col) USING p_queda, v.id;
    ELSIF v.id = ANY (p_conservar) THEN
      UPDATE public.contactos_vinculos SET activo = false, fusionado_en = v.id WHERE id = v_choque;
      EXECUTE format('UPDATE public.contactos_vinculos SET %I = $1 WHERE id = $2', v_col) USING p_queda, v.id;
    ELSE
      UPDATE public.contactos_vinculos SET activo = false, fusionado_en = v_choque WHERE id = v.id;
    END IF;
  END LOOP;

  -- Persona ↔ empresa
  FOR pe IN
    EXECUTE format('SELECT * FROM public.contactos_persona_empresa WHERE %I = $1 FOR UPDATE', v_col)
    USING p_se_va
  LOOP
    IF pe.activo AND pe.hasta IS NULL AND EXISTS (
      SELECT 1 FROM public.contactos_persona_empresa x
      WHERE x.activo AND x.hasta IS NULL
        AND x.persona_id = CASE WHEN p_tipo = 'persona' THEN p_queda ELSE pe.persona_id END
        AND x.empresa_id = CASE WHEN p_tipo = 'empresa' THEN p_queda ELSE pe.empresa_id END
    ) THEN
      UPDATE public.contactos_persona_empresa SET activo = false WHERE id = pe.id;
    ELSE
      EXECUTE format('UPDATE public.contactos_persona_empresa SET %I = $1 WHERE id = $2', v_col) USING p_queda, pe.id;
    END IF;
  END LOOP;

  -- Guardados
  EXECUTE format('UPDATE public.contactos_vinculos_guardados SET %I = $1 WHERE activo AND %I = $2', v_col, v_col)
  USING p_queda, p_se_va;
  IF p_tipo = 'empresa' THEN
    UPDATE public.contactos_vinculos_guardados SET a_empresa_id = p_queda WHERE activo AND a_empresa_id = p_se_va;

    INSERT INTO public.contactos_empresa_equipos (empresa_id, equipo_id, compartida_por)
    SELECT p_queda, x.equipo_id, v_uid
    FROM (
      SELECT equipo_id FROM public.contactos_empresas WHERE id = p_se_va
      UNION
      SELECT equipo_id FROM public.contactos_empresa_equipos WHERE empresa_id = p_se_va AND activo
    ) x
    WHERE x.equipo_id IS NOT NULL
      AND x.equipo_id IS DISTINCT FROM (SELECT equipo_id FROM public.contactos_empresas WHERE id = p_queda)
    ON CONFLICT (empresa_id, equipo_id) WHERE activo DO NOTHING;
  ELSE
    PERFORM public.notificar(v_dueno, 'persona_fusionada', 'contactos_personas', p_se_va, v_uid);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_fusionar(text, uuid, uuid, boolean, boolean, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_fusionar(text, uuid, uuid, boolean, boolean, uuid[]) TO authenticated;

-- ============================================================
-- 5. "Se fusionó con …"
-- ============================================================
-- Para quien ve la que se va o la que queda. El id, solo si ve la que queda:
-- el link no lleva a algo que no existe para él.
CREATE OR REPLACE FUNCTION public.contactos_fusionada(p_tipo text, p_id uuid)
RETURNS TABLE (id uuid, nombre text, dueno text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN x.ve_queda THEN x.id END, x.nombre, x.dueno
  FROM (
    SELECT q.id, q.nombre, u.nombre AS dueno,
           public.contactos_puede_ver_persona_de(q.id, q.responsable_id, q.activo, auth.uid()) AS ve_queda,
           public.contactos_puede_ver_persona_de(s.id, s.responsable_id, s.activo, auth.uid()) AS ve_se_va
    FROM public.contactos_personas s
    JOIN public.contactos_personas q ON q.id = s.fusionada_en
    JOIN public.usuarios u           ON u.id = q.responsable_id
    WHERE p_tipo = 'persona' AND s.id = p_id
    UNION ALL
    SELECT q.id, q.nombre, coalesce(eq.nombre, u.nombre),
           public.contactos_puede_ver_empresa_de(q.id, q.equipo_id, q.creado_por, q.activo, auth.uid()),
           public.contactos_puede_ver_empresa_de(s.id, s.equipo_id, s.creado_por, s.activo, auth.uid())
    FROM public.contactos_empresas s
    JOIN public.contactos_empresas q ON q.id = s.fusionada_en
    JOIN public.usuarios u           ON u.id = q.creado_por
    LEFT JOIN public.equipos eq      ON eq.id = q.equipo_id
    WHERE p_tipo = 'empresa' AND s.id = p_id
  ) x
  WHERE x.ve_queda OR x.ve_se_va;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_fusionada(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_fusionada(text, uuid) TO authenticated;

-- ============================================================
-- 6. Aviso
-- ============================================================
-- El dueño de la que se va quizás ya no la ve ni ve la que queda: el texto
-- sale de acá, solo de sus propios avisos, como `duplicados_avisos`.
CREATE OR REPLACE FUNCTION public.contactos_fusion_avisos()
RETURNS TABLE (notificacion_id uuid, etiqueta text, motivo text, destino text, destino_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT n.id, s.nombre, u.nombre,
         CASE WHEN x.ve THEN 'persona' END,
         CASE WHEN x.ve THEN q.id END
  FROM public.usuario_notificaciones n
  JOIN public.contactos_personas s ON s.id = n.entidad_id
  JOIN public.contactos_personas q ON q.id = s.fusionada_en
  JOIN public.usuarios u           ON u.id = q.responsable_id
  CROSS JOIN LATERAL (
    SELECT public.contactos_puede_ver_persona_de(q.id, q.responsable_id, q.activo, auth.uid()) AS ve
  ) x
  WHERE n.usuario_id = auth.uid() AND n.activo AND n.tipo = 'persona_fusionada';
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_fusion_avisos() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_fusion_avisos() TO authenticated;

CREATE OR REPLACE FUNCTION public.notificaciones_listar(p_limite int DEFAULT 30)
RETURNS TABLE (id uuid, tipo tipo_notificacion, etiqueta text, motivo text, actor text, destino text,
               destino_id uuid, leida boolean, created_at timestamptz)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH mias AS (
    SELECT n.*
    FROM usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo
    ORDER BY n.created_at DESC
    LIMIT greatest(coalesce(p_limite, 30), 1)
  ),
  resuelta AS (
    SELECT n.id AS notificacion_id,
           u.nombre AS etiqueta,
           NULL::text AS motivo,
           'mi_equipo'::text AS destino,
           m.usuario_id AS destino_id
    FROM mias n
    JOIN equipos_miembros m ON m.id = n.entidad_id AND m.activo
    JOIN usuarios u         ON u.id = m.usuario_id
    WHERE n.entidad = 'equipos_miembros'

    UNION ALL

    SELECT n.id,
           CASE WHEN n.tipo = 'delegador_designado' THEN e.nombre ELSE s.nombre END,
           NULL::text,
           CASE WHEN n.tipo = 'delegador_designado' THEN 'mi_equipo' ELSE s.modulo END,
           us.id
    FROM mias n
    JOIN usuario_submodulos us ON us.id = n.entidad_id AND us.activo
    JOIN submodulos s          ON s.id = us.submodulo_id
    LEFT JOIN equipos e        ON e.id = mi_equipo()
    WHERE n.entidad = 'usuario_submodulos'

    UNION ALL

    SELECT n.id,
           coalesce(t.titulo, x.titulo),
           CASE WHEN n.tipo = 'pedido_rechazado' THEN t.motivo_rechazo END,
           CASE WHEN t.id IS NOT NULL THEN 'tarea' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas t                 ON t.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas' AND (t.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id,
           coalesce(h.titulo, x.titulo),
           NULL::text,
           CASE WHEN h.id IS NOT NULL THEN 'hilo' END,
           n.entidad_id
    FROM mias n
    LEFT JOIN tareas_hilos h           ON h.id = n.entidad_id
    LEFT JOIN tareas_avisos_salida() x ON x.notificacion_id = n.id
    WHERE n.entidad = 'tareas_hilos' AND (h.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, o.nombre, NULL::text, 'obra', o.id
    FROM mias n
    JOIN obras o ON o.id = n.entidad_id
    WHERE n.entidad = 'obras'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma')

    UNION ALL

    SELECT n.id,
           coalesce(o.nombre, x.nombre),
           NULL::text,
           CASE WHEN o.id IS NOT NULL THEN 'obra' END,
           coalesce(o.id, x.obra_id)
    FROM mias n
    LEFT JOIN obras_avisos_salida() x ON x.notificacion_id = n.id
    LEFT JOIN obras_participantes p   ON p.id = n.entidad_id
    LEFT JOIN obras o                 ON o.id = coalesce(p.obra_id, x.obra_id)
    WHERE n.entidad = 'obras_participantes' AND n.tipo <> 'obra_misma_sumado'
      AND (o.id IS NOT NULL OR x.notificacion_id IS NOT NULL)

    UNION ALL

    SELECT n.id, c.nombre, NULL::text, 'persona', c.id
    FROM mias n
    JOIN contactos_personas c ON c.id = n.entidad_id
    WHERE n.entidad = 'contactos_personas'
      AND n.tipo NOT IN ('alta_por_aprobar', 'alta_aprobada', 'alta_rechazada', 'alta_es_la_misma',
                         'persona_fusionada')

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN duplicados_avisos() x ON x.notificacion_id = n.id

    UNION ALL

    SELECT x.notificacion_id, x.etiqueta, x.motivo, x.destino, x.destino_id
    FROM mias n
    JOIN contactos_fusion_avisos() x ON x.notificacion_id = n.id

    UNION ALL

    SELECT n.id,
           a.nombre,
           c.cuantos || ' ' || CASE
             WHEN n.tipo = 'hilos_huerfanos' THEN
               CASE WHEN c.cuantos = 1 THEN 'hilo abierto' ELSE 'hilos abiertos' END
             WHEN n.tipo IN ('obras_huerfanas', 'obras_recibidas') THEN
               CASE WHEN c.cuantos = 1 THEN 'obra' ELSE 'obras' END
             ELSE
               CASE WHEN c.cuantos = 1 THEN 'persona' ELSE 'personas' END
           END,
           CASE n.tipo
             WHEN 'hilos_huerfanos' THEN 'tareas_todas'
             WHEN 'obras_huerfanas' THEN 'obras_todas'
             WHEN 'obras_recibidas' THEN 'obras'
             ELSE 'contactos'
           END,
           n.entidad_id
    FROM mias n
    CROSS JOIN LATERAL (
      SELECT CASE n.tipo
        WHEN 'hilos_huerfanos' THEN (
          SELECT count(*) FROM tareas_hilos h
          WHERE h.responsable_id = n.entidad_id AND h.activo AND h.estado = 'abierto')
        WHEN 'obras_huerfanas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.entidad_id AND o.activo)
        WHEN 'personas_huerfanas' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.entidad_id AND p.activo)
        WHEN 'obras_recibidas' THEN (
          SELECT count(*) FROM obras o
          WHERE o.responsable_id = n.usuario_id AND o.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'obra' AND e.registro_id = o.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
        WHEN 'agenda_recibida' THEN (
          SELECT count(*) FROM contactos_personas p
          WHERE p.responsable_id = n.usuario_id AND p.activo
            AND EXISTS (
              SELECT 1 FROM eventos e
              WHERE e.ente = 'persona' AND e.registro_id = p.id AND e.evento = 'transferencia'
                AND e.detalle @> jsonb_build_object('de', n.entidad_id, 'a', n.usuario_id)))
      END AS cuantos
    ) c
    LEFT JOIN notificaciones_actores() a ON a.id = n.entidad_id
    WHERE n.entidad = 'usuarios' AND c.cuantos > 0
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, a.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r                      ON r.notificacion_id = n.id
  LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;
