-- ============================================================
-- 023 — Atomicidad de las escrituras multi-tabla del módulo tareas
--
-- Punto 2 de PLAN_ARQUITECTURA_TAREAS.md. Seis actions escribían dos o más
-- tablas con statements separados: cada uno era su propia transacción, así que
-- un fallo en el segundo dejaba el primero cometido. El caso peor es
-- `crearTarea`: la tarea queda `activo = true` e **invisible para todos** si
-- falla el insert de asignados, porque `tareas_select` no mira `creado_por`
-- (sql/013). Nadie la ve, nadie la puede corregir.
--
-- Cada una pasa a ser una función `SECURITY INVOKER`: el cuerpo corre en una
-- sola transacción y RLS se sigue evaluando con la identidad de quien llama —
-- la autoridad no se mueve de las policies. `actions.ts` queda como glue.
--
-- Los ids se generan en variable en vez de pedir `RETURNING`: la policy de
-- SELECT no ve la fila recién insertada (la tarea todavía no tiene asignados,
-- el proyecto todavía no tiene miembros, `puede_ver_hilo` relee su propia
-- tabla), y `RETURNING` exige pasar por esa policy. Es el mismo motivo por el
-- que el id se generaba en el server; lo único que cambia es dónde.
--
-- TA008 reemplaza al `errorDeUpdate()` de TypeScript: un UPDATE que RLS
-- rechaza afecta 0 filas y no falla, así que acá se convierte en excepción.
-- ============================================================

-- ============================================================
-- 1. crear_tarea — la tarea y sus asignados nacen juntos
-- ============================================================
CREATE OR REPLACE FUNCTION crear_tarea(
  p_titulo               text,
  p_descripcion          text,
  p_hilo_id              uuid,
  p_proyecto_id          uuid,
  p_paso_anterior_id     uuid,
  p_visibilidad          visibilidad,
  p_responsable_id       uuid,
  p_asignados            uuid[],
  p_fecha_vencimiento    date,
  p_temperatura          int,
  p_recurrencia_cantidad int,
  p_recurrencia_unidad   recurrencia_unidad,
  p_modo_completado      modo_completado,
  p_origen_app           text,
  p_origen_punto         text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO tareas (
    id, titulo, descripcion, hilo_id, proyecto_id, paso_anterior_id,
    visibilidad, responsable_id, fecha_vencimiento, temperatura,
    recurrencia_cantidad, recurrencia_unidad, modo_completado,
    origen_app, origen_punto, creado_por
  ) VALUES (
    v_id, p_titulo, p_descripcion, p_hilo_id, p_proyecto_id, p_paso_anterior_id,
    p_visibilidad, p_responsable_id, p_fecha_vencimiento, p_temperatura,
    p_recurrencia_cantidad, p_recurrencia_unidad, p_modo_completado,
    p_origen_app, p_origen_punto, auth.uid()
  );

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT v_id, u FROM unnest(p_asignados) AS u;

  RETURN v_id;
END;
$$;

-- ============================================================
-- 2. crear_proyecto — el proyecto y su primera membresía nacen juntos
-- ============================================================
-- La rama de siembra de `tareas_proyectos_miembros_insert`
-- (`es_creador_proyecto AND NOT proyecto_tiene_miembros`) sigue siendo la que
-- autoriza este segundo INSERT: dentro de la transacción el proyecto ya existe
-- y todavía no tiene miembros, exactamente el estado que esa rama contempla.
CREATE OR REPLACE FUNCTION crear_proyecto(
  p_nombre      text,
  p_descripcion text,
  p_visibilidad visibilidad,
  p_miembros    uuid[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO tareas_proyectos (id, nombre, descripcion, visibilidad, creado_por)
  VALUES (v_id, p_nombre, p_descripcion, p_visibilidad, auth.uid());

  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
  SELECT v_id, u FROM unnest(p_miembros) AS u;

  RETURN v_id;
END;
$$;

-- ============================================================
-- 3. convertir_tarea_en_hilo — el hilo nuevo y la mudanza de la tarea
-- ============================================================
-- `creado_por` del hilo es siempre quien ejecuta (no el creador original):
-- `tareas_hilos_insert` exige `creado_por = auth.uid()` en su WITH CHECK.
CREATE OR REPLACE FUNCTION convertir_tarea_en_hilo(p_tarea_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_hilo_id uuid := gen_random_uuid();
  v_tarea   tareas%ROWTYPE;
BEGIN
  SELECT * INTO v_tarea FROM tareas WHERE id = p_tarea_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La tarea no existe o no es visible' USING ERRCODE = 'TA008';
  END IF;

  INSERT INTO tareas_hilos (id, titulo, descripcion, visibilidad, proyecto_id, responsable_id, creado_por)
  VALUES (v_hilo_id, v_tarea.titulo, v_tarea.descripcion, v_tarea.visibilidad,
          v_tarea.proyecto_id, v_tarea.responsable_id, auth.uid());

  UPDATE tareas SET hilo_id = v_hilo_id, proyecto_id = NULL WHERE id = p_tarea_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se pudo mover la tarea al hilo' USING ERRCODE = 'TA008';
  END IF;

  RETURN v_hilo_id;
END;
$$;

-- ============================================================
-- 4. deshacer_conversion_hilo — colapso del hilo en su tarea más antigua
-- ============================================================
-- Orden conservado del TypeScript: primero se restaura la más antigua, después
-- se desactiva el resto. Si algo activo la tiene como paso previo,
-- `validar_paso_tarea` corta con TA006 antes de tocar nada — ese rechazo es el
-- comportamiento que ya existía y no se cambia acá.
CREATE OR REPLACE FUNCTION deshacer_conversion_hilo(p_hilo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_proyecto_id uuid;
  v_ids         uuid[];
BEGIN
  SELECT proyecto_id INTO v_proyecto_id FROM tareas_hilos WHERE id = p_hilo_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El hilo no existe o no es visible' USING ERRCODE = 'TA008';
  END IF;

  SELECT array_agg(id ORDER BY created_at) INTO v_ids
    FROM tareas WHERE hilo_id = p_hilo_id AND activo;

  IF v_ids IS NOT NULL THEN
    UPDATE tareas SET hilo_id = NULL, proyecto_id = v_proyecto_id WHERE id = v_ids[1];

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo restaurar la tarea' USING ERRCODE = 'TA008';
    END IF;

    IF array_length(v_ids, 1) > 1 THEN
      UPDATE tareas SET activo = false WHERE id = ANY(v_ids[2:]);

      IF NOT FOUND THEN
        RAISE EXCEPTION 'No se pudieron desactivar las tareas del hilo' USING ERRCODE = 'TA008';
      END IF;
    END IF;
  END IF;

  UPDATE tareas_hilos SET activo = false WHERE id = p_hilo_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se pudo desactivar el hilo' USING ERRCODE = 'TA008';
  END IF;
END;
$$;

-- ============================================================
-- 5. desactivar_hilo — las tareas caen con el hilo
-- ============================================================
-- Sin conteo sobre las tareas: un hilo sin tareas afecta 0 filas y es correcto.
CREATE OR REPLACE FUNCTION desactivar_hilo(p_hilo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  UPDATE tareas SET activo = false WHERE hilo_id = p_hilo_id;

  UPDATE tareas_hilos SET activo = false WHERE id = p_hilo_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El hilo no existe o no tenés permiso para desactivarlo' USING ERRCODE = 'TA008';
  END IF;
END;
$$;

-- ============================================================
-- 6. agregar_tareas_desde_plantilla — la cadena entera o nada
-- ============================================================
-- Los items ya vienen ordenados por `orden`, y ese orden siempre significó
-- "primero esto, después aquello": cada paso espera al anterior. El loop
-- reemplaza al INSERT multi-fila del TypeScript — ahí el motivo de agrupar era
-- ahorrar round-trips desde el server, que dentro de la función ya no existe.
CREATE OR REPLACE FUNCTION agregar_tareas_desde_plantilla(
  p_plantilla_id   uuid,
  p_hilo_id        uuid,
  p_responsable_id uuid,
  p_asignados      uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_item     record;
  v_id       uuid;
  v_anterior uuid := NULL;
BEGIN
  FOR v_item IN
    SELECT titulo FROM tareas_plantillas_items
     WHERE plantilla_id = p_plantilla_id AND activo
     ORDER BY orden
  LOOP
    v_id := gen_random_uuid();

    INSERT INTO tareas (id, titulo, hilo_id, responsable_id, creado_por, paso_anterior_id)
    VALUES (v_id, v_item.titulo, p_hilo_id, p_responsable_id, auth.uid(), v_anterior);

    INSERT INTO tareas_asignados (tarea_id, usuario_id)
    SELECT v_id, u FROM unnest(p_asignados) AS u;

    v_anterior := v_id;
  END LOOP;

  IF v_anterior IS NULL THEN
    RAISE EXCEPTION 'La plantilla no tiene pasos' USING ERRCODE = 'TA009';
  END IF;
END;
$$;

-- ============================================================
-- 7. GRANTs — mismo criterio que sql/006: PostgREST expone toda función a
-- PUBLIC por default.
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.crear_proyecto(text, text, visibilidad, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crear_proyecto(text, text, visibilidad, uuid[]) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.convertir_tarea_en_hilo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.convertir_tarea_en_hilo(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.deshacer_conversion_hilo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deshacer_conversion_hilo(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.desactivar_hilo(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.desactivar_hilo(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.agregar_tareas_desde_plantilla(uuid, uuid, uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.agregar_tareas_desde_plantilla(uuid, uuid, uuid, uuid[]) TO authenticated;
