-- ============================================================
-- 064 — Auditoría de tareas y obras: sincronizar por diff, compartir en
--       orden, la pregunta completa
--
-- Bugs confirmados contra la base (decisiones/tareas/visibilidad.md →
-- "Asignados por diferencia, la pregunta completa y compartir en orden";
-- verificación en sql/tests/asignar_con_acceso.sql, casos 13–16). El texto
-- condicional de las plantillas que venía en este archivo quedó en
-- BACKLOG.md, sin construir.
--
--   1. sincronizar_asignados pasa a diff, con el responsable adentro y en el
--      orden que la RLS necesita. Antes desactivaba todo y reinsertaba todo:
--      cada cambio del conjunto re-avisaba «te asignaron» a los que se
--      quedaban, y editar_tarea/reasignar_tarea escribían el responsable
--      ANTES de tocar asignados, así que quien traspasaba la tarea entera
--      (con tareas_asignar, sin gestionar_ajenas) perdía en el primer UPDATE
--      el derecho que el INSERT siguiente exige (42501).
--   2. editar_tarea, reasignar_tarea y vincular_tarea usan la firma nueva.
--   3. sin_acceso_tarea: la pregunta de la UI sale de los vínculos reales de
--      la tarea, no de los que quien edita puede ver.
--   4. obras_compartir_registros procesa obra → empresa → persona: el origen
--      de la cascada dependía del orden del array (y la UI lo mandaba por
--      orden alfabético de etiqueta).
-- ============================================================

-- ============================================================
-- 1. sincronizar_asignados(tarea, asignados, responsable) — diff
--
-- Orden de las escrituras, dictado por las policies de tareas_asignados y
-- tareas (sql/013, sql/014): (a) altas mientras quien actúa todavía es el
-- responsable; (b) bajas ajenas, por lo mismo; (c) el responsable, mientras
-- quien actúa sigue siendo asignado activo (WITH CHECK de tareas_update);
-- (d) la baja propia al final. Un conjunto que no cambia no escribe nada y
-- no avisa a nadie.
-- ============================================================
DROP FUNCTION IF EXISTS public.sincronizar_asignados(uuid, uuid[]);

CREATE FUNCTION public.sincronizar_asignados(p_tarea_id uuid, p_asignados uuid[], p_responsable_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_resp_actual uuid;
  v_previos     uuid[];
  v_vinculos    jsonb;
  v_quedan      uuid[];
  v_fuera       uuid[];
  v_vacio       boolean;
  v_resp        uuid;
  v_agregar     uuid[];
  v_quitar      uuid[];
  v_n           int;
BEGIN
  SELECT responsable_id INTO v_resp_actual FROM tareas WHERE id = p_tarea_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La tarea no existe o no tenés permiso para modificarla' USING ERRCODE = 'TA008';
  END IF;

  SELECT coalesce(array_agg(usuario_id), '{}')
    INTO v_previos
    FROM tareas_asignados
   WHERE tarea_id = p_tarea_id AND activo;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('ente', ente, 'registro_id', registro_id)), '[]'::jsonb)
    INTO v_vinculos
    FROM tareas_vinculos
   WHERE tarea_id = p_tarea_id AND activo;

  v_quedan := asignados_con_acceso(p_asignados, v_vinculos);

  SELECT COALESCE(array_agg(u), ARRAY[]::uuid[]) INTO v_fuera
    FROM unnest(p_asignados) AS u
   WHERE NOT u = ANY(v_quedan);

  IF cardinality(v_fuera) > 0 AND NOT tiene_permiso('tareas_asignar') THEN
    RAISE EXCEPTION 'Alguien asignado no puede abrir lo relacionado y no tenés permiso para sacarlo de la tarea'
      USING ERRCODE = 'TA016';
  END IF;

  v_vacio := cardinality(v_quedan) = 0;
  IF v_vacio THEN
    v_quedan := ARRAY[v_uid];
  END IF;

  v_resp := CASE
    WHEN p_responsable_id = ANY(v_quedan) THEN p_responsable_id
    WHEN v_uid = ANY(v_quedan) THEN v_uid
    ELSE v_quedan[1]
  END;

  SELECT COALESCE(array_agg(u), ARRAY[]::uuid[]) INTO v_agregar
    FROM unnest(v_quedan) AS u WHERE NOT u = ANY(v_previos);
  SELECT COALESCE(array_agg(u), ARRAY[]::uuid[]) INTO v_quitar
    FROM unnest(v_previos) AS u WHERE NOT u = ANY(v_quedan);

  IF cardinality(v_agregar) = 0 AND cardinality(v_quitar) = 0 AND v_resp = v_resp_actual THEN
    RETURN;
  END IF;

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT p_tarea_id, u FROM unnest(v_agregar) AS u;

  UPDATE tareas_asignados SET activo = false
   WHERE tarea_id = p_tarea_id AND activo
     AND usuario_id = ANY(v_quitar) AND usuario_id IS DISTINCT FROM v_uid;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> cardinality(array_remove(v_quitar, v_uid)) THEN
    RAISE EXCEPTION 'No se pudo actualizar los asignados' USING ERRCODE = 'TA008';
  END IF;

  IF v_resp IS DISTINCT FROM v_resp_actual THEN
    UPDATE tareas SET responsable_id = v_resp WHERE id = p_tarea_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo actualizar el responsable' USING ERRCODE = 'TA008';
    END IF;
  END IF;

  IF v_uid = ANY(v_quitar) THEN
    UPDATE tareas_asignados SET activo = false
     WHERE tarea_id = p_tarea_id AND activo AND usuario_id = v_uid;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo actualizar los asignados' USING ERRCODE = 'TA008';
    END IF;
  END IF;

  IF cardinality(v_fuera) > 0 THEN
    PERFORM registrar_sin_acceso(p_tarea_id, v_fuera, v_vinculos);
  END IF;

  IF v_vacio THEN
    INSERT INTO tareas_notas (tarea_id, usuario_id, nota)
    VALUES (p_tarea_id, v_uid, format(
      'Quedó asignada a vos: %s no pueden abrir lo relacionado con esta tarea.',
      (SELECT string_agg(nombre, ', ') FROM usuarios WHERE id = ANY(v_fuera))
    ));
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sincronizar_asignados(uuid, uuid[], uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sincronizar_asignados(uuid, uuid[], uuid) TO authenticated;

-- ============================================================
-- 2. editar_tarea, reasignar_tarea y vincular_tarea
-- ============================================================
CREATE OR REPLACE FUNCTION public.editar_tarea(
  p_id uuid, p_titulo text, p_descripcion text, p_proyecto_id uuid, p_visibilidad visibilidad,
  p_responsable_id uuid, p_asignados uuid[], p_fecha_vencimiento date, p_temperatura integer,
  p_recurrencia_cantidad integer, p_recurrencia_unidad recurrencia_unidad, p_vence_dias_tras_previo integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  UPDATE tareas SET
    titulo                 = p_titulo,
    descripcion            = p_descripcion,
    proyecto_id            = p_proyecto_id,
    visibilidad            = p_visibilidad,
    fecha_vencimiento      = CASE WHEN p_vence_dias_tras_previo IS NULL
                                  THEN p_fecha_vencimiento ELSE fecha_vencimiento END,
    temperatura            = p_temperatura,
    recurrencia_cantidad   = p_recurrencia_cantidad,
    recurrencia_unidad     = p_recurrencia_unidad,
    vence_dias_tras_previo = p_vence_dias_tras_previo
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La tarea no existe o no tenés permiso para modificarla' USING ERRCODE = 'TA008';
  END IF;

  PERFORM sincronizar_asignados(p_id, p_asignados, p_responsable_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.reasignar_tarea(p_tarea_id uuid, p_responsable_id uuid, p_asignados uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  PERFORM sincronizar_asignados(p_tarea_id, p_asignados, p_responsable_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.vincular_tarea(p_tarea_id uuid, p_ente text, p_registro_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_activos uuid[];
BEGIN
  INSERT INTO tareas_vinculos (tarea_id, ente, registro_id)
  VALUES (p_tarea_id, p_ente, p_registro_id);

  SELECT COALESCE(array_agg(usuario_id), ARRAY[]::uuid[]) INTO v_activos
    FROM tareas_asignados
   WHERE tarea_id = p_tarea_id AND activo;

  IF cardinality(v_activos) > 0 THEN
    PERFORM sincronizar_asignados(
      p_tarea_id, v_activos, (SELECT responsable_id FROM tareas WHERE id = p_tarea_id)
    );
  END IF;
END;
$$;

-- ============================================================
-- 3. sin_acceso_tarea — la pregunta sobre los vínculos reales de la tarea
--
-- INVOKER: lee tareas_vinculos con la RLS de quien pregunta (ve todos los
-- vínculos de una tarea visible, aunque no pueda abrir el registro), y
-- sin_acceso (DEFINER) apaga la etiqueta de lo que no puede abrir. Antes la
-- UI armaba los pares con `tarea.vinculos`, que vinculos_de_tareas ya había
-- recortado a lo que quien edita ve: un adjunto que no podía abrir no
-- entraba en la pregunta y la base lo aplicaba igual, sin panel.
-- `p_vinculos` suma los que todavía no están (relacionar uno nuevo).
-- ============================================================
CREATE OR REPLACE FUNCTION public.sin_acceso_tarea(p_tarea_id uuid, p_usuarios uuid[], p_vinculos jsonb DEFAULT '[]'::jsonb)
RETURNS TABLE(usuario_id uuid, usuario text, ente text, registro_id uuid, etiqueta text, compartible boolean)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT s.*
  FROM sin_acceso((
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'usuario_id', u.usuario_id, 'ente', v.ente, 'registro_id', v.registro_id
           )), '[]'::jsonb)
    FROM unnest(p_usuarios) AS u(usuario_id)
    CROSS JOIN (
      SELECT tv.ente, tv.registro_id
      FROM tareas_vinculos tv
      WHERE tv.tarea_id = p_tarea_id AND tv.activo
      UNION
      SELECT x->>'ente', (x->>'registro_id')::uuid
      FROM jsonb_array_elements(COALESCE(p_vinculos, '[]'::jsonb)) AS x
    ) AS v
  )) AS s
  ORDER BY s.usuario, s.etiqueta;
$$;

REVOKE EXECUTE ON FUNCTION public.sin_acceso_tarea(uuid, uuid[], jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sin_acceso_tarea(uuid, uuid[], jsonb) TO authenticated;

-- ============================================================
-- 4. obras_compartir_registros — obra → empresa → persona
--
-- El origen de la cascada de una empresa/persona busca una obra (o empresa)
-- «ya compartida con ese usuario en esta llamada o de antes». "En esta
-- llamada" solo se cumplía si la obra venía antes en el array; sin_acceso
-- ordena por etiqueta, así que «Anacleto W.» se procesaba antes que «Obra
-- X» y quedaba como grant directo — el que sql/052 deja re-vincular y el
-- que revocar la obra no arrastra. Solo cambia el ORDER BY del loop.
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_compartir_registros(p_usuario uuid, p_registros jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  x                jsonb;
  v_ente           text;
  v_id             uuid;
  v_origen_obra    uuid;
  v_origen_empresa uuid;
BEGIN
  IF p_usuario = auth.uid() THEN
    RAISE EXCEPTION 'No podés compartirte un registro a vos mismo' USING ERRCODE = 'OB021';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id = p_usuario AND u.activo) THEN
    RAISE EXCEPTION 'El usuario no existe o está inactivo' USING ERRCODE = 'OB023';
  END IF;

  FOR x IN
    SELECT e
    FROM jsonb_array_elements(COALESCE(p_registros, '[]'::jsonb)) AS e
    ORDER BY CASE e->>'ente' WHEN 'obra' THEN 1 WHEN 'empresa' THEN 2 ELSE 3 END
  LOOP
    v_ente := x->>'ente';
    v_id   := (x->>'registro_id')::uuid;

    IF v_ente = 'obra' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras o WHERE o.id = v_id AND o.responsable_id = auth.uid() AND o.activo
      ) THEN
        RAISE EXCEPTION 'Solo el responsable de la obra puede compartirla' USING ERRCODE = 'OB026';
      END IF;

      INSERT INTO obras_obra_compartida (obra_id, usuario_id, otorgada_por, activo)
      VALUES (v_id, p_usuario, auth.uid(), true)
      ON CONFLICT (obra_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now()
        WHERE NOT obras_obra_compartida.activo;

    ELSIF v_ente = 'empresa' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras_empresas e
        WHERE e.id = v_id AND e.creado_por = auth.uid() AND e.activo AND NOT e.pendiente
      ) THEN
        RAISE EXCEPTION 'Solo el dueño de la empresa puede compartirla' USING ERRCODE = 'OB020';
      END IF;

      SELECT oe.obra_id INTO v_origen_obra
      FROM obras_obra_empresa oe
      JOIN obras o ON o.id = oe.obra_id AND o.responsable_id = auth.uid() AND o.activo
      JOIN obras_obra_compartida c ON c.obra_id = oe.obra_id AND c.usuario_id = p_usuario AND c.activo
      WHERE oe.empresa_id = v_id AND oe.activo
      LIMIT 1;

      INSERT INTO obras_empresa_compartida (empresa_id, usuario_id, otorgada_por, activo, origen_obra_id)
      VALUES (v_id, p_usuario, auth.uid(), true, v_origen_obra)
      ON CONFLICT (empresa_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
            origen_obra_id = EXCLUDED.origen_obra_id
        WHERE NOT obras_empresa_compartida.activo;

    ELSIF v_ente = 'persona' THEN
      IF NOT EXISTS (
        SELECT 1 FROM obras_personas p
        WHERE p.id = v_id AND p.creado_por = auth.uid() AND p.activo AND NOT p.pendiente
      ) THEN
        RAISE EXCEPTION 'Solo el dueño de la persona puede compartirla' USING ERRCODE = 'OB020';
      END IF;

      SELECT op.obra_id INTO v_origen_obra
      FROM obras_obra_persona op
      JOIN obras o ON o.id = op.obra_id AND o.responsable_id = auth.uid() AND o.activo
      JOIN obras_obra_compartida c ON c.obra_id = op.obra_id AND c.usuario_id = p_usuario AND c.activo
      WHERE op.persona_id = v_id AND op.activo
      LIMIT 1;

      v_origen_empresa := NULL;
      IF v_origen_obra IS NULL THEN
        SELECT pe.empresa_id INTO v_origen_empresa
        FROM obras_persona_empresa pe
        JOIN obras_empresas e ON e.id = pe.empresa_id AND e.creado_por = auth.uid() AND e.activo
        JOIN obras_empresa_compartida c ON c.empresa_id = pe.empresa_id AND c.usuario_id = p_usuario AND c.activo
        WHERE pe.persona_id = v_id AND pe.activo
        LIMIT 1;
      END IF;

      INSERT INTO obras_persona_compartida
        (persona_id, usuario_id, otorgada_por, activo, origen_obra_id, origen_empresa_id)
      VALUES (v_id, p_usuario, auth.uid(), true, v_origen_obra, v_origen_empresa)
      ON CONFLICT (persona_id, usuario_id) DO UPDATE
        SET activo = true, otorgada_por = auth.uid(), updated_at = now(),
            origen_obra_id = EXCLUDED.origen_obra_id,
            origen_empresa_id = EXCLUDED.origen_empresa_id
        WHERE NOT obras_persona_compartida.activo;
    END IF;
  END LOOP;
END;
$$;

