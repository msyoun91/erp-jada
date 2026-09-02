-- ============================================================
-- 024 — Atomicidad de las ediciones multi-tabla del módulo tareas
--
-- Cola de sql/023. Ahí entraron las seis escrituras cuyo modo de falla era
-- dejar una fila **invisible** (la tarea sin asignados que `tareas_select` no
-- muestra). Las tres de acá fallan distinto: dejan una fila **visible pero
-- inconsistente** — `editarTarea` cambiaba el título y después sincronizaba
-- asignados; si lo segundo fallaba, el título ya estaba cometido. Se ve y se
-- puede corregir a mano, y por eso no entraron en la misma tanda; el arreglo
-- es el mismo.
--
-- Mismo criterio que 023: `SECURITY INVOKER` — el cuerpo corre en una sola
-- transacción y RLS se sigue evaluando con la identidad de quien llama.
--
-- `sincronizar_asignados` baja entera desde `actions.ts` y queda como el único
-- escritor de `tareas_asignados` sobre una tarea que ya existe, igual que era
-- en TypeScript: sus dos callers (`editar_tarea`, `reasignar_tarea`) la
-- comparten en vez de repetir el desactivar-y-reinsertar. Va con GRANT a
-- `authenticated` porque una función `SECURITY INVOKER` llamada desde otra
-- exige EXECUTE al rol que invoca — no es una función privada. Que además
-- quede expuesta por PostgREST no abre nada nuevo: `tareas_asignados` ya
-- acepta INSERT/UPDATE directo del cliente, con las mismas policies.
-- ============================================================

-- ============================================================
-- 1. sincronizar_asignados — el conjunto de asignados de una tarea existente
-- ============================================================
-- Si el conjunto no cambió no toca nada: editar el título de una tarea no debe
-- reescribir sus asignaciones, y sin ese corte quien no tiene `tareas_asignar`
-- no podría guardar ningún cambio en una tarea compartida (los asignados
-- viajan igual como defaults ocultos del form, y reinsertarlos choca contra la
-- policy).
--
-- Desactiva y reinserta en vez de UPSERT: el índice único de tareas_asignados
-- es parcial (WHERE activo) y ON CONFLICT necesita el predicado; una fila
-- vieja inactiva y una nueva activa para el mismo par no chocan.
CREATE OR REPLACE FUNCTION sincronizar_asignados(
  p_tarea_id  uuid,
  p_asignados uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_previos uuid[];
BEGIN
  SELECT coalesce(array_agg(usuario_id ORDER BY usuario_id), '{}')
    INTO v_previos
    FROM tareas_asignados
   WHERE tarea_id = p_tarea_id AND activo;

  IF v_previos = (SELECT coalesce(array_agg(u ORDER BY u), '{}') FROM unnest(p_asignados) AS u) THEN
    RETURN;
  END IF;

  -- Guardado por el conteo: la tarea sin asignados activos (recién creada por
  -- otra vía, o ya vaciada) afecta 0 filas legítimamente, y sin la guarda ese
  -- 0 sería indistinguible de un UPDATE que RLS rechazó.
  IF array_length(v_previos, 1) > 0 THEN
    UPDATE tareas_asignados SET activo = false
     WHERE tarea_id = p_tarea_id AND activo;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo actualizar los asignados' USING ERRCODE = 'TA008';
    END IF;
  END IF;

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT p_tarea_id, u FROM unnest(p_asignados) AS u;
END;
$$;

-- ============================================================
-- 2. editar_tarea — los campos y los asignados en una sola transacción
-- ============================================================
-- Orden conservado del TypeScript: primero la fila, después los asignados.
-- `validar_proyecto_tarea` se dispara en el UPDATE de `proyecto_id` y valida
-- contra los asignados **de ese momento** — invertir el orden cambiaría contra
-- qué conjunto se valida, que es un cambio de comportamiento, no de forma.
CREATE OR REPLACE FUNCTION editar_tarea(
  p_id                   uuid,
  p_titulo               text,
  p_descripcion          text,
  p_proyecto_id          uuid,
  p_visibilidad          visibilidad,
  p_responsable_id       uuid,
  p_asignados            uuid[],
  p_fecha_vencimiento    date,
  p_temperatura          int,
  p_recurrencia_cantidad int,
  p_recurrencia_unidad   recurrencia_unidad
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  UPDATE tareas SET
    titulo               = p_titulo,
    descripcion          = p_descripcion,
    proyecto_id          = p_proyecto_id,
    visibilidad          = p_visibilidad,
    responsable_id       = p_responsable_id,
    fecha_vencimiento    = p_fecha_vencimiento,
    temperatura          = p_temperatura,
    recurrencia_cantidad = p_recurrencia_cantidad,
    recurrencia_unidad   = p_recurrencia_unidad
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La tarea no existe o no tenés permiso para modificarla' USING ERRCODE = 'TA008';
  END IF;

  PERFORM sincronizar_asignados(p_id, p_asignados);
END;
$$;

-- ============================================================
-- 3. reasignar_tarea — el responsable y los asignados no se separan
-- ============================================================
CREATE OR REPLACE FUNCTION reasignar_tarea(
  p_tarea_id       uuid,
  p_responsable_id uuid,
  p_asignados      uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  UPDATE tareas SET responsable_id = p_responsable_id WHERE id = p_tarea_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La tarea no existe o no tenés permiso para modificarla' USING ERRCODE = 'TA008';
  END IF;

  PERFORM sincronizar_asignados(p_tarea_id, p_asignados);
END;
$$;

-- ============================================================
-- 4. editar_proyecto — el proyecto y el diff de miembros
-- ============================================================
-- Diff en vez de desactivar-todo-y-reinsertar: `validar_quitar_miembro` (TA001)
-- se dispara por fila que pasa a inactiva, así que barrer la membresía entera
-- haría fallar el guardado por miembros que se quedan.
CREATE OR REPLACE FUNCTION editar_proyecto(
  p_id          uuid,
  p_nombre      text,
  p_descripcion text,
  p_visibilidad visibilidad,
  p_miembros    uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_quitados uuid[];
BEGIN
  UPDATE tareas_proyectos SET
    nombre      = p_nombre,
    descripcion = p_descripcion,
    visibilidad = p_visibilidad
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El proyecto no existe o no tenés permiso para modificarlo' USING ERRCODE = 'TA008';
  END IF;

  SELECT coalesce(array_agg(usuario_id), '{}')
    INTO v_quitados
    FROM tareas_proyectos_miembros
   WHERE proyecto_id = p_id AND activo AND NOT (usuario_id = ANY(p_miembros));

  IF array_length(v_quitados, 1) > 0 THEN
    UPDATE tareas_proyectos_miembros SET activo = false
     WHERE proyecto_id = p_id AND activo AND usuario_id = ANY(v_quitados);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo quitar a los miembros' USING ERRCODE = 'TA008';
    END IF;
  END IF;

  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
  SELECT p_id, u
    FROM unnest(p_miembros) AS u
   WHERE NOT EXISTS (
     SELECT 1 FROM tareas_proyectos_miembros m
      WHERE m.proyecto_id = p_id AND m.usuario_id = u AND m.activo
   );
END;
$$;

-- ============================================================
-- 5. GRANTs — mismo criterio que sql/006 y sql/023: PostgREST expone toda
-- función a PUBLIC por default.
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.sincronizar_asignados(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sincronizar_asignados(uuid, uuid[]) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.editar_tarea(uuid, text, text, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.editar_tarea(uuid, text, text, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.reasignar_tarea(uuid, uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reasignar_tarea(uuid, uuid, uuid[]) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.editar_proyecto(uuid, text, text, visibilidad, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.editar_proyecto(uuid, text, text, visibilidad, uuid[]) TO authenticated;
