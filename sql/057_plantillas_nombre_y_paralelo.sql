-- ============================================================
-- 057 — Plantillas: el nombre de lo que crean, y hilos en paralelo
--
-- Pedidos del usuario el 2026-09-14:
--   1. `tareas_plantillas.titulo_creado`: el hilo o proyecto que crea una
--      plantilla ya no tiene por qué llamarse como ella. NULL = su nombre.
--   2. `encadenada` en la plantilla de tipo hilo y en cada hilo de una de
--      proyecto: false = sus pasos no se esperan entre sí. Es el caso real que
--      esperaba "plantilla-checklist" (BACKLOG.md).
--   3. `guardar_plantilla` los recibe y `usar_plantilla` los aplica.
-- Ver decisiones/tareas/plantillas.md → "Nombre de lo que crea e hilos en paralelo".
-- ============================================================

-- ============================================================
-- 1. Columnas
-- ============================================================
ALTER TABLE tareas_plantillas
  ADD COLUMN titulo_creado text,
  ADD COLUMN encadenada boolean NOT NULL DEFAULT true;

ALTER TABLE tareas_plantillas_hilos
  ADD COLUMN encadenada boolean NOT NULL DEFAULT true;

GRANT UPDATE (titulo_creado, encadenada) ON public.tareas_plantillas TO authenticated;

-- ============================================================
-- 2. guardar_plantilla (resto igual a sql/055)
-- ============================================================
-- Fuera de su tipo, los dos valores no significan nada y se guardan neutros:
-- una de tarea no crea nada que nombrar, y solo la de hilo tiene una cadena
-- propia (la de proyecto la decide cada hilo).
DROP FUNCTION IF EXISTS guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text);

CREATE OR REPLACE FUNCTION guardar_plantilla(
  p_id             uuid,
  p_nombre         text,
  p_descripcion    text,
  p_alcance        alcance_plantilla,
  p_tipo           tipo_plantilla,
  p_visibilidad    visibilidad,
  p_miembros       uuid[],
  p_hilos          jsonb,
  p_pasos          jsonb,
  p_disparo_ente   text    DEFAULT NULL,
  p_disparo_estado text    DEFAULT NULL,
  p_titulo_creado  text    DEFAULT NULL,
  p_encadenada     boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id            uuid := COALESCE(p_id, gen_random_uuid());
  v_hilo_ids      uuid[];
  v_titulo_creado text := CASE WHEN p_tipo <> 'tarea' THEN NULLIF(trim(p_titulo_creado), '') END;
  v_encadenada    boolean := p_tipo <> 'hilo' OR COALESCE(p_encadenada, true);
BEGIN
  IF (p_tipo = 'tarea' AND (jsonb_array_length(p_hilos) > 0 OR jsonb_array_length(p_pasos) <> 1))
     OR (p_tipo = 'hilo' AND jsonb_array_length(p_hilos) > 0) THEN
    RAISE EXCEPTION 'La plantilla no corresponde a su tipo' USING ERRCODE = 'TA010';
  END IF;

  IF jsonb_array_length(p_pasos) = 0 AND jsonb_array_length(p_hilos) = 0
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_hilos) h
       WHERE jsonb_array_length(COALESCE(h->'pasos', '[]'::jsonb)) = 0
     ) THEN
    RAISE EXCEPTION 'La plantilla no tiene pasos' USING ERRCODE = 'TA009';
  END IF;

  -- `entes` bajo RLS: un ente cuyo submódulo no tenés tampoco pasa.
  IF p_disparo_ente IS NOT NULL AND NOT EXISTS (
       SELECT 1
       FROM entes e
       JOIN pg_enum en ON en.enumtypid = e.estados
       WHERE e.codigo = p_disparo_ente AND en.enumlabel = p_disparo_estado
     ) THEN
    RAISE EXCEPTION 'El disparador no es válido' USING ERRCODE = 'TA012';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO tareas_plantillas (
      id, nombre, descripcion, alcance, tipo, visibilidad, miembros,
      disparo_ente, disparo_estado, titulo_creado, encadenada, creado_por
    )
    VALUES (
      v_id, p_nombre, p_descripcion, p_alcance, p_tipo, p_visibilidad, p_miembros,
      p_disparo_ente, p_disparo_estado, v_titulo_creado, v_encadenada, auth.uid()
    );
  ELSE
    UPDATE tareas_plantillas SET
      nombre         = p_nombre,
      descripcion    = p_descripcion,
      tipo           = p_tipo,
      visibilidad    = p_visibilidad,
      miembros       = p_miembros,
      disparo_ente   = p_disparo_ente,
      disparo_estado = p_disparo_estado,
      titulo_creado  = v_titulo_creado,
      encadenada     = v_encadenada
    WHERE id = p_id AND activo;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La plantilla no existe o no tenés permiso para modificarla' USING ERRCODE = 'TA008';
    END IF;

    UPDATE tareas_plantillas_items SET activo = false WHERE plantilla_id = v_id AND activo;
    UPDATE tareas_plantillas_hilos SET activo = false WHERE plantilla_id = v_id AND activo;
  END IF;

  -- La privada arranca prendida para su dueño; ON CONFLICT respeta que la haya
  -- apagado antes. La de sistema no: cada uno la activa para sí.
  IF p_disparo_ente IS NOT NULL
     AND (SELECT alcance FROM tareas_plantillas WHERE id = v_id) = 'privada' THEN
    INSERT INTO tareas_plantillas_activaciones (plantilla_id, usuario_id)
    VALUES (v_id, auth.uid())
    ON CONFLICT (plantilla_id, usuario_id) DO NOTHING;
  END IF;

  v_hilo_ids := ARRAY(SELECT gen_random_uuid() FROM jsonb_array_elements(p_hilos));

  INSERT INTO tareas_plantillas_hilos (id, plantilla_id, titulo, orden, encadenada)
  SELECT v_hilo_ids[hn], v_id, hilo->>'titulo', hn, COALESCE((hilo->>'encadenada')::boolean, true)
  FROM jsonb_array_elements(p_hilos) WITH ORDINALITY AS hj(hilo, hn);

  INSERT INTO tareas_plantillas_items (
    plantilla_id, hilo_id, titulo, descripcion, orden, asignados, incluir_ejecutor,
    responsable_id, vence_dias, vence_tras_previo, temperatura
  )
  SELECT
    v_id, s.hilo_id, s.paso->>'titulo', NULLIF(s.paso->>'descripcion', ''), s.pn,
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(s.paso->'asignados', '[]'::jsonb))::uuid),
    COALESCE((s.paso->>'incluir_ejecutor')::boolean, true),
    (s.paso->>'responsable_id')::uuid,
    (s.paso->>'vence_dias')::int,
    COALESCE((s.paso->>'vence_tras_previo')::boolean, false),
    COALESCE((s.paso->>'temperatura')::int, 50)
  FROM (
    SELECT NULL::uuid AS hilo_id, paso, pn
    FROM jsonb_array_elements(p_pasos) WITH ORDINALITY AS pj(paso, pn)
    UNION ALL
    SELECT v_hilo_ids[hj.hn], pj.paso, pj.pn
    FROM jsonb_array_elements(p_hilos) WITH ORDINALITY AS hj(hilo, hn)
    CROSS JOIN LATERAL jsonb_array_elements(hj.hilo->'pasos') WITH ORDINALITY AS pj(paso, pn)
  ) s;

  RETURN v_id;
END;
$$;

-- ============================================================
-- 3. usar_plantilla (misma firma; resto igual a sql/055)
-- ============================================================
-- El nombre sale de "Usar" si lo escribieron, si no de `titulo_creado`, si no
-- de la plantilla. La cadena, de la plantilla de hilo o de cada hilo de la de
-- proyecto. Sin cadena, "vence tras el anterior" corre desde la creación, como
-- ya pasaba con el primer paso.
CREATE OR REPLACE FUNCTION usar_plantilla(
  p_plantilla_id uuid,
  p_titulo       text,
  p_proyecto_id  uuid,
  p_hilo_id      uuid,
  p_ente         text  DEFAULT NULL,
  p_registro_id  uuid  DEFAULT NULL,
  p_datos        jsonb DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_uid           uuid := auth.uid();
  v_puede_asignar boolean := tiene_permiso('tareas_asignar');
  v_p             tareas_plantillas%ROWTYPE;
  v_titulo        text;
  v_proyecto      uuid := p_proyecto_id;
  v_hilo          uuid := p_hilo_id;
  v_hilo_pl       uuid;
  v_primero       boolean := true;
  v_encadena      boolean;
  v_item          record;
  v_anterior      uuid;
  v_asignados     uuid[];
  v_responsable   uuid;
  v_vacio         boolean;
  v_id            uuid;
  v_creadas       int := 0;
  v_derivadas     int := 0;
  v_origen_app    text;
  v_origen_punto  text;
BEGIN
  SELECT * INTO v_p FROM tareas_plantillas WHERE id = p_plantilla_id AND activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La plantilla no existe o no es visible' USING ERRCODE = 'TA008';
  END IF;

  IF v_p.disparo_ente IS DISTINCT FROM p_ente THEN
    RAISE EXCEPTION 'Una plantilla con disparador se crea sola: no se usa a mano' USING ERRCODE = 'TA013';
  END IF;

  IF p_ente IS NOT NULL THEN
    SELECT e.modulo, replace(e.ruta, '{id}', p_registro_id::text)
      INTO v_origen_app, v_origen_punto
      FROM entes e
     WHERE e.codigo = p_ente;
  END IF;

  v_titulo := rellenar_datos(COALESCE(NULLIF(trim(p_titulo), ''), v_p.titulo_creado, v_p.nombre), p_datos);

  IF v_p.tipo = 'proyecto' AND (p_proyecto_id IS NOT NULL OR p_hilo_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Una plantilla de proyecto crea su propio proyecto' USING ERRCODE = 'TA011';
  END IF;

  IF p_hilo_id IS NOT NULL THEN
    SELECT proyecto_id INTO v_proyecto FROM tareas_hilos WHERE id = p_hilo_id AND activo;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'El hilo no existe o no es visible' USING ERRCODE = 'TA008';
    END IF;
  END IF;

  IF v_p.tipo = 'proyecto' THEN
    v_proyecto := crear_proyecto(
      v_titulo, NULL, v_p.visibilidad,
      ARRAY(
        SELECT DISTINCT m FROM unnest(v_p.miembros || v_uid) AS m
        JOIN usuarios u ON u.id = m AND u.activo
      )
    );
  ELSIF v_p.tipo = 'hilo' AND p_hilo_id IS NULL THEN
    v_hilo := gen_random_uuid();
    INSERT INTO tareas_hilos (id, titulo, proyecto_id, visibilidad, responsable_id, creado_por)
    VALUES (v_hilo, v_titulo, v_proyecto,
            CASE WHEN v_proyecto IS NULL THEN 'privado' ELSE 'publico' END::visibilidad,
            v_uid, v_uid);
  END IF;

  FOR v_item IN
    SELECT i.*, h.titulo AS hilo_titulo, h.encadenada AS hilo_encadenada
      FROM tareas_plantillas_items i
      LEFT JOIN tareas_plantillas_hilos h ON h.id = i.hilo_id
     WHERE i.plantilla_id = v_p.id AND i.activo
     ORDER BY h.orden NULLS LAST, i.orden
  LOOP
    IF v_p.tipo = 'proyecto' AND (v_primero OR v_item.hilo_id IS DISTINCT FROM v_hilo_pl) THEN
      v_hilo_pl := v_item.hilo_id;
      v_anterior := NULL;
      v_hilo := NULL;

      IF v_item.hilo_id IS NOT NULL THEN
        v_hilo := gen_random_uuid();
        INSERT INTO tareas_hilos (id, titulo, proyecto_id, visibilidad, responsable_id, creado_por)
        VALUES (v_hilo, rellenar_datos(v_item.hilo_titulo, p_datos), v_proyecto, 'publico', v_uid, v_uid);
      END IF;
    END IF;
    v_primero := false;

    v_encadena := v_hilo IS NOT NULL AND CASE v_p.tipo
      WHEN 'hilo'     THEN v_p.encadenada
      WHEN 'proyecto' THEN v_item.hilo_encadenada
      ELSE false
    END;

    v_asignados := ARRAY(
      SELECT DISTINCT a
        FROM unnest(v_item.asignados || CASE WHEN v_item.incluir_ejecutor THEN ARRAY[v_uid] ELSE '{}'::uuid[] END) AS a
        JOIN usuarios u ON u.id = a AND u.activo
       WHERE (a = v_uid OR v_puede_asignar)
         AND (v_proyecto IS NULL OR es_miembro_proyecto(v_proyecto, a))
    );

    v_vacio := cardinality(v_asignados) = 0;
    IF v_vacio THEN
      v_asignados := ARRAY[v_uid];
    END IF;

    v_responsable := CASE
      WHEN v_item.responsable_id = ANY(v_asignados) THEN v_item.responsable_id
      WHEN v_uid = ANY(v_asignados) THEN v_uid
      ELSE v_asignados[1]
    END;

    v_id := crear_tarea(
      rellenar_datos(v_item.titulo, p_datos),
      rellenar_datos(v_item.descripcion, p_datos),
      v_hilo,
      CASE WHEN v_hilo IS NULL THEN v_proyecto END,
      CASE WHEN v_encadena THEN v_anterior END,
      CASE WHEN v_proyecto IS NULL THEN 'privado' ELSE 'publico' END::visibilidad,
      v_responsable,
      v_asignados,
      CASE
        WHEN v_item.vence_dias IS NOT NULL
         AND NOT (v_item.vence_tras_previo AND v_encadena AND v_anterior IS NOT NULL)
        THEN current_date + v_item.vence_dias
      END,
      v_item.temperatura,
      NULL, NULL, 'manual', v_origen_app, v_origen_punto,
      CASE
        WHEN v_item.vence_tras_previo AND v_encadena AND v_anterior IS NOT NULL
        THEN v_item.vence_dias
      END
    );

    IF p_ente IS NOT NULL THEN
      INSERT INTO tareas_vinculos (tarea_id, ente, registro_id, plantilla_id)
      VALUES (v_id, p_ente, p_registro_id, v_p.id);
    END IF;

    IF v_vacio THEN
      INSERT INTO tareas_notas (tarea_id, usuario_id, nota)
      VALUES (v_id, v_uid, format(
        'Quedó asignada a vos: %s, de la plantilla «%s», no pueden recibirla (inactivos, fuera del proyecto o sin permiso para asignarles).',
        COALESCE((SELECT string_agg(nombre, ', ') FROM usuarios WHERE id = ANY(v_item.asignados)), 'los asignados'),
        v_p.nombre
      ));
      v_derivadas := v_derivadas + 1;
    END IF;

    v_anterior := v_id;
    v_creadas := v_creadas + 1;
  END LOOP;

  IF v_creadas = 0 THEN
    RAISE EXCEPTION 'La plantilla no tiene pasos' USING ERRCODE = 'TA009';
  END IF;

  RETURN v_derivadas;
END;
$$;

-- ============================================================
-- 4. GRANTs — mismo criterio que sql/006 / sql/055
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text, text, boolean) TO authenticated;
