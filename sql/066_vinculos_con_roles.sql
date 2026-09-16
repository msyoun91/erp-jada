-- ============================================================
-- 066 — tareas_vinculos guarda el rol por el que un disparo vinculó
--
-- BACKLOG.md → "Tareas sobre el modelo de entes". La plantilla elige a quién
-- adjuntar por `ente:rol`, pero el vínculo no lo guardaba: el chip decía
-- "Persona Juan Pérez" y no "Arquitecto Juan Pérez".
--
--   1. `tareas_vinculos.roles text[]`: los roles del registro que pidió el
--      paso (`adjuntos`), sin el prefijo del ente, que ya está en la fila.
--      Arreglo y no un solo rol: en Obras una persona tiene varios roles en
--      la misma obra, y el vínculo es uno por (tarea, ente, registro).
--      Vacío = vinculado a mano o el registro que disparó.
--   2. `crear_tarea` copia `roles` de cada elemento de `p_vinculos`.
--   3. `usar_plantilla` agrupa los adjuntos por registro.
--   4. `vinculos_de_tareas` devuelve `roles`.
-- Ver decisiones/tareas/integracion.md → "El vínculo guarda el rol".
-- ============================================================

-- ============================================================
-- 1. La columna
--
-- Solo un disparo pone roles: a mano nadie verifica que la persona tenga
-- ese rol en la obra, y la policy ya exige estar en un trigger para escribir
-- un vínculo con plantilla.
-- ============================================================
ALTER TABLE tareas_vinculos
  ADD COLUMN IF NOT EXISTS roles text[] NOT NULL DEFAULT '{}';

ALTER TABLE tareas_vinculos
  DROP CONSTRAINT IF EXISTS tareas_vinculos_roles_de_disparo,
  ADD CONSTRAINT tareas_vinculos_roles_de_disparo
    CHECK (plantilla_id IS NOT NULL OR cardinality(roles) = 0);

-- ============================================================
-- 2. crear_tarea — igual que sql/063 salvo `roles`
-- ============================================================
CREATE OR REPLACE FUNCTION crear_tarea(
  p_titulo                 text,
  p_descripcion            text,
  p_hilo_id                uuid,
  p_proyecto_id            uuid,
  p_paso_anterior_id       uuid,
  p_visibilidad            visibilidad,
  p_responsable_id         uuid,
  p_asignados              uuid[],
  p_fecha_vencimiento      date,
  p_temperatura            int,
  p_recurrencia_cantidad   int,
  p_recurrencia_unidad     recurrencia_unidad,
  p_modo_completado        modo_completado,
  p_origen_app             text,
  p_origen_punto           text,
  p_vence_dias_tras_previo int,
  p_vinculos               jsonb DEFAULT '[]'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id          uuid := gen_random_uuid();
  v_asignados   uuid[] := asignados_con_acceso(p_asignados, p_vinculos);
  v_fuera       uuid[];
  v_vacio       boolean := cardinality(v_asignados) = 0;
BEGIN
  SELECT COALESCE(array_agg(u), ARRAY[]::uuid[]) INTO v_fuera
    FROM unnest(p_asignados) AS u
   WHERE NOT u = ANY(v_asignados);

  -- Si no queda nadie, la tarea es de quien la crea, con nota (más abajo):
  -- quien actúa nunca queda afuera (queda_afuera lo exime), así que esto
  -- siempre resuelve.
  IF v_vacio THEN
    v_asignados := ARRAY[auth.uid()];
  END IF;

  INSERT INTO tareas (
    id, titulo, descripcion, hilo_id, proyecto_id, paso_anterior_id,
    visibilidad, responsable_id, fecha_vencimiento, temperatura,
    recurrencia_cantidad, recurrencia_unidad, modo_completado,
    origen_app, origen_punto, vence_dias_tras_previo, creado_por
  ) VALUES (
    v_id, p_titulo, p_descripcion, p_hilo_id, p_proyecto_id, p_paso_anterior_id,
    p_visibilidad,
    CASE
      WHEN p_responsable_id = ANY(v_asignados) THEN p_responsable_id
      WHEN auth.uid() = ANY(v_asignados) THEN auth.uid()
      ELSE v_asignados[1]
    END,
    p_fecha_vencimiento, p_temperatura,
    p_recurrencia_cantidad, p_recurrencia_unidad, p_modo_completado,
    p_origen_app, p_origen_punto, p_vence_dias_tras_previo, auth.uid()
  );

  -- El plantilla_id y los roles de cada elemento los copia un disparo
  -- (usar_plantilla); la policy de tareas_vinculos sigue exigiendo
  -- pg_trigger_depth() > 0 para esos, y el CHECK de roles pide plantilla, así
  -- que uno inventado por el cliente sigue sin poder colarse acá.
  INSERT INTO tareas_vinculos (tarea_id, ente, registro_id, plantilla_id, roles)
  SELECT v_id, x->>'ente', (x->>'registro_id')::uuid, (x->>'plantilla_id')::uuid,
         ARRAY(SELECT jsonb_array_elements_text(x->'roles'))
  FROM jsonb_array_elements(COALESCE(p_vinculos, '[]'::jsonb)) AS x;

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT v_id, u FROM unnest(v_asignados) AS u;

  IF cardinality(v_fuera) > 0 THEN
    PERFORM registrar_sin_acceso(v_id, v_fuera, p_vinculos);
  END IF;

  IF v_vacio THEN
    INSERT INTO tareas_notas (tarea_id, usuario_id, nota)
    VALUES (v_id, auth.uid(), format(
      'Quedó asignada a vos: %s no pueden abrir lo relacionado con esta tarea.',
      (SELECT string_agg(nombre, ', ') FROM usuarios WHERE id = ANY(v_fuera))
    ));
  END IF;

  RETURN v_id;
END;
$$;

-- ============================================================
-- 3. usar_plantilla — igual que sql/065 salvo los vínculos
--
-- `relacionados_de_registro` devuelve una fila por rol: antes el DISTINCT
-- dejaba un vínculo por registro; ahora lo hace el GROUP BY.
-- ============================================================
CREATE OR REPLACE FUNCTION public.usar_plantilla(
  p_plantilla_id uuid,
  p_titulo       text,
  p_proyecto_id  uuid,
  p_hilo_id      uuid,
  p_ente         text  DEFAULT NULL,
  p_registro_id  uuid  DEFAULT NULL,
  p_datos        jsonb DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
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
  v_vinculos      jsonb;
  v_id            uuid;
  v_creadas       int := 0;
  v_derivadas     int := 0;
  v_origen_app    text;
  v_origen_punto  text;
  v_roles         text[];
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

  -- Sin registro, `relacionados_de_registro` no devuelve nada: ningún rol.
  v_roles := ARRAY(SELECT DISTINCT x.ente || ':' || x.rol FROM relacionados_de_registro(p_ente, p_registro_id) x);

  v_titulo := rellenar_datos(COALESCE(NULLIF(trim(p_titulo), ''), v_p.titulo_creado, v_p.nombre), p_datos, v_roles);

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
    -- `ente:rol` se saltea si nadie lo tiene; `!ente:rol`, si alguien lo tiene.
    IF v_item.condicion IS NOT NULL
       AND (ltrim(v_item.condicion, '!') = ANY (v_roles)) = starts_with(v_item.condicion, '!') THEN
      CONTINUE;
    END IF;

    IF v_p.tipo = 'proyecto' AND (v_primero OR v_item.hilo_id IS DISTINCT FROM v_hilo_pl) THEN
      v_hilo_pl := v_item.hilo_id;
      v_anterior := NULL;
      v_hilo := NULL;

      IF v_item.hilo_id IS NOT NULL THEN
        v_hilo := gen_random_uuid();
        INSERT INTO tareas_hilos (id, titulo, proyecto_id, visibilidad, responsable_id, creado_por)
        VALUES (v_hilo, rellenar_datos(v_item.hilo_titulo, p_datos, v_roles), v_proyecto, 'publico', v_uid, v_uid);
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

    v_vinculos := CASE WHEN p_ente IS NOT NULL THEN
      jsonb_build_array(jsonb_build_object('ente', p_ente, 'registro_id', p_registro_id, 'plantilla_id', v_p.id))
      || (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                 'ente', a.ente, 'registro_id', a.registro_id, 'plantilla_id', v_p.id, 'roles', a.roles
               )), '[]'::jsonb)
        FROM (
          -- Un vínculo por registro. Roles por código: `adjuntos` no guarda
          -- el orden en que se eligieron (guardar_plantilla hace DISTINCT).
          SELECT x.ente, x.registro_id, array_agg(x.rol ORDER BY x.rol) AS roles
          FROM relacionados_de_registro(p_ente, p_registro_id) x
          WHERE x.ente || ':' || x.rol = ANY (v_item.adjuntos)
          GROUP BY x.ente, x.registro_id
        ) a
      )
    ELSE '[]'::jsonb END;

    v_id := crear_tarea(
      rellenar_datos(v_item.titulo, p_datos, v_roles),
      rellenar_datos(v_item.descripcion, p_datos, v_roles),
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
      END,
      v_vinculos
    );

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
-- 4. vinculos_de_tareas — suma `roles`
--
-- Cambia el tipo de retorno: DROP + CREATE, y el GRANT se repite.
-- ============================================================
DROP FUNCTION IF EXISTS public.vinculos_de_tareas();

CREATE FUNCTION public.vinculos_de_tareas()
RETURNS TABLE (
  id           uuid,
  tarea_id     uuid,
  ente         text,
  registro_id  uuid,
  etiqueta     text,
  href         text,
  de_plantilla boolean,
  roles        text[]
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT v.id, v.tarea_id, v.ente, v.registro_id, x.etiqueta,
         replace(e.ruta, '{id}', v.registro_id::text), v.plantilla_id IS NOT NULL, v.roles
  FROM tareas_vinculos v
  JOIN tareas t ON t.id = v.tarea_id AND t.activo
  JOIN entes e ON e.codigo = v.ente
  CROSS JOIN LATERAL (SELECT etiqueta_registro(v.ente, v.registro_id) AS etiqueta) x
  WHERE v.activo AND x.etiqueta IS NOT NULL
  ORDER BY v.created_at;
$$;

REVOKE EXECUTE ON FUNCTION public.vinculos_de_tareas() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.vinculos_de_tareas() TO authenticated;
