-- ============================================================
-- 060 — Plantillas: roles de la obra en cada paso
--
-- Pedido del usuario el 2026-09-14: una plantilla disparada por una obra suma
-- a la tarea la empresa o la persona que tiene tal rol en esa obra ("con chips
-- o links para que tengan acceso directo"), y crea un paso solo si la obra
-- tiene a alguien con un rol.
--
--   1. `tareas_plantillas_items`: `adjuntos` (roles cuyos registros se vinculan
--      a la tarea) y `condicion` (el rol que tiene que existir).
--   2. `obras_relacionados_obra` y `relacionados_de_registro`: quién tiene qué
--      rol en un registro, para quien pregunta.
--   3. `guardar_plantilla` los guarda; sin disparador no se aceptan (TA015).
--   4. `usar_plantilla` saltea el paso cuya condición no se cumple y vincula
--      los adjuntos. Si no se crea ningún paso, TA014.
--   5. `disparar_plantillas` toma TA014 como "no corresponde": no avisa.
-- Ver decisiones/tareas/plantillas.md → "Roles de la obra en la plantilla".
-- ============================================================

-- ============================================================
-- 1. Columnas
-- ============================================================
-- Un rol es `ente:rol` (`persona:arquitecto`). Acá se valida la forma; que el
-- rol exista lo cuida el editor: uno que no existe no encuentra a nadie.
ALTER TABLE tareas_plantillas_items
  ADD COLUMN adjuntos  text[] NOT NULL DEFAULT '{}',
  ADD COLUMN condicion text;

ALTER TABLE tareas_plantillas_items
  ADD CONSTRAINT tareas_plantillas_items_adjuntos_formato
    CHECK (array_to_string(adjuntos, ',') ~ '^([a-z_]+:[a-z_]+(,|$))*$'),
  ADD CONSTRAINT tareas_plantillas_items_condicion_formato
    CHECK (condicion IS NULL OR condicion ~ '^[a-z_]+:[a-z_]+$');

-- ============================================================
-- 2. Quién tiene qué rol
-- ============================================================
-- INVOKER: el disparo corre como quien cambió el estado, que es el responsable
-- de la obra y ve todos sus vínculos (sql/051).
CREATE OR REPLACE FUNCTION obras_relacionados_obra(p_obra_id uuid)
RETURNS TABLE (ente text, registro_id uuid, rol text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT 'empresa'::text, v.empresa_id, r::text
    FROM obras_obra_empresa v
    CROSS JOIN LATERAL unnest(v.roles) AS r
   WHERE v.obra_id = p_obra_id AND v.activo
  UNION ALL
  SELECT 'persona'::text, v.persona_id, r::text
    FROM obras_obra_persona v
    CROSS JOIN LATERAL unnest(v.roles) AS r
   WHERE v.obra_id = p_obra_id AND v.activo;
$$;

-- Una rama por ente que tenga relacionados, como `etiqueta_registro` (sql/059).
CREATE OR REPLACE FUNCTION relacionados_de_registro(p_ente text, p_id uuid)
RETURNS TABLE (ente text, registro_id uuid, rol text)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_ente = 'obra' THEN
    RETURN QUERY SELECT * FROM obras_relacionados_obra(p_id);
  END IF;
END;
$$;

-- ============================================================
-- 3. guardar_plantilla (misma firma; resto igual a sql/057)
-- ============================================================
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

  -- Los roles salen del registro que dispara: a mano no hay de dónde.
  IF p_disparo_ente IS NULL AND EXISTS (
       SELECT 1
       FROM (
         SELECT paso FROM jsonb_array_elements(p_pasos) AS pj(paso)
         UNION ALL
         SELECT paso FROM jsonb_array_elements(p_hilos) AS hj(hilo)
         CROSS JOIN LATERAL jsonb_array_elements(hj.hilo->'pasos') AS pj(paso)
       ) s
       WHERE jsonb_array_length(COALESCE(s.paso->'adjuntos', '[]'::jsonb)) > 0
          OR NULLIF(s.paso->>'condicion', '') IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Los roles solo se usan en plantillas que corren solas' USING ERRCODE = 'TA015';
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
    responsable_id, vence_dias, vence_tras_previo, temperatura, adjuntos, condicion
  )
  SELECT
    v_id, s.hilo_id, s.paso->>'titulo', NULLIF(s.paso->>'descripcion', ''), s.pn,
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(s.paso->'asignados', '[]'::jsonb))::uuid),
    COALESCE((s.paso->>'incluir_ejecutor')::boolean, true),
    (s.paso->>'responsable_id')::uuid,
    (s.paso->>'vence_dias')::int,
    COALESCE((s.paso->>'vence_tras_previo')::boolean, false),
    COALESCE((s.paso->>'temperatura')::int, 50),
    ARRAY(SELECT DISTINCT jsonb_array_elements_text(COALESCE(s.paso->'adjuntos', '[]'::jsonb))),
    NULLIF(s.paso->>'condicion', '')
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
-- 4. usar_plantilla (misma firma; resto igual a sql/057)
-- ============================================================
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
    -- Sin nadie con el rol que pide, el paso no se crea y la cadena sigue del
    -- último que sí. Se mira antes de abrir el hilo del paso: en una de
    -- proyecto, un hilo con todos sus pasos salteados no se abre.
    IF v_item.condicion IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM relacionados_de_registro(p_ente, p_registro_id) x
          WHERE x.ente || ':' || x.rol = v_item.condicion
       ) THEN
      CONTINUE;
    END IF;

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

      -- Quien tenga en el registro alguno de los roles adjuntos. DISTINCT: una
      -- persona con dos de esos roles es un solo vínculo.
      INSERT INTO tareas_vinculos (tarea_id, ente, registro_id, plantilla_id)
      SELECT DISTINCT v_id, x.ente, x.registro_id, v_p.id
        FROM relacionados_de_registro(p_ente, p_registro_id) x
       WHERE x.ente || ':' || x.rol = ANY (v_item.adjuntos);
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
    -- Todos los pasos pedían un rol que el registro no tiene: no corresponde,
    -- no es un error de la plantilla. El disparo lo revierte en silencio.
    IF EXISTS (
         SELECT 1 FROM tareas_plantillas_items i
          WHERE i.plantilla_id = v_p.id AND i.activo AND i.condicion IS NOT NULL
       ) THEN
      RAISE EXCEPTION 'Ningún paso corresponde a este registro' USING ERRCODE = 'TA014';
    END IF;
    RAISE EXCEPTION 'La plantilla no tiene pasos' USING ERRCODE = 'TA009';
  END IF;

  RETURN v_derivadas;
END;
$$;

-- ============================================================
-- 5. disparar_plantillas: TA014 no avisa (resto igual a sql/056)
-- ============================================================
CREATE OR REPLACE FUNCTION disparar_plantillas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid  := auth.uid();
  v_ente    text  := TG_ARGV[0];
  v_columna text  := TG_ARGV[1];
  v_fila    jsonb := to_jsonb(NEW);
  v_estado  text  := v_fila->>v_columna;
  v_datos   jsonb;
  v_pl      uuid;
BEGIN
  IF current_user <> 'authenticated' OR NOT (v_fila->>'activo')::boolean THEN
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE' AND v_estado IS NOT DISTINCT FROM to_jsonb(OLD)->>v_columna THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_object_agg(d.dato, v_fila->>d.dato)
    INTO v_datos
    FROM entes e
    CROSS JOIN LATERAL unnest(e.datos) AS d(dato)
   WHERE e.codigo = v_ente;

  PERFORM set_config('tareas.disparo', 'on', true);

  FOR v_pl IN
    SELECT p.id
      FROM tareas_plantillas p
      JOIN tareas_plantillas_activaciones a
        ON a.plantilla_id = p.id AND a.usuario_id = v_uid AND a.activo
     WHERE p.activo AND p.disparo_ente = v_ente AND p.disparo_estado = v_estado
     ORDER BY p.created_at
  LOOP
    BEGIN
      IF NOT plantilla_disparada(v_pl, v_ente, NEW.id) THEN
        PERFORM usar_plantilla(v_pl, NULL, NULL, NULL, v_ente, NEW.id, v_datos);
        PERFORM notificar_disparo(v_pl, true);
      END IF;
    EXCEPTION
      WHEN SQLSTATE 'TA014' THEN
        NULL;
      WHEN OTHERS THEN
        PERFORM notificar_disparo(v_pl, false);
    END;
  END LOOP;

  PERFORM set_config('tareas.disparo', '', true);
  RETURN NULL;
END;
$$;

-- ============================================================
-- 6. GRANTs — mismo criterio que sql/006 / sql/059
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.obras_relacionados_obra(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_relacionados_obra(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.relacionados_de_registro(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.relacionados_de_registro(text, uuid) TO authenticated;
