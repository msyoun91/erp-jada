-- ============================================================
-- 063 — La regla al asignar, relacionar y disparar
--
-- Fase D de PLAN_TAREAS_VINCULOS.md. Fase C (sql/062) dejó la base capaz de
-- contestar "¿el usuario U puede abrir el registro R?"; acá esa pregunta pasa
-- a decidir de verdad quién queda asignado, en los tres caminos: crear/editar
-- una tarea, relacionar un registro con una que ya existe, y el disparo de
-- una plantilla. Suma un ensayo del cambio de estado de una obra (para que la
-- UI pueda preguntar antes de guardar, Fase E) y el aviso de que alguien
-- quedó afuera.
--
-- Regla única (decisiones/tareas/visibilidad.md, decidida con el usuario el
-- 2026-09-14): quien no puede abrir lo relacionado con la tarea no queda
-- asignado; si no queda nadie, la tarea va a quien asigna, con una nota.
-- Quien actúa nunca queda afuera (queda_afuera lo exime, sql/062).
--
--   1. Tipo de notificación (aplicar sola, antes del resto).
--   2. Registro de la transacción: qué pares (usuario, vínculo) quedaron
--      afuera, para que la UI los pueda preguntar (sin_acceso, Fase E) y el
--      ensayo los pueda leer tras el rollback.
--   3. crear_tarea aplica la regla antes de insertar.
--   4. sincronizar_asignados (editar_tarea, reasignar_tarea) también.
--   5. vincular_tarea: relacionar aplica la misma regla.
--   6. usar_plantilla arma los vínculos con plantilla_id y se los pasa a
--      crear_tarea, que ya trae el filtro.
--   7. notificar_disparo distingue "corrió pero alguien quedó afuera".
--   8. disparar_plantillas detecta ese caso mirando el registro.
--   9. notificaciones_listar lleva el aviso nuevo a Tareas.
--  10. obras_ensayar_estado: el cambio de estado de una obra, con rollback,
--      para preguntar antes de guardar de verdad.
-- Ver decisiones/tareas/visibilidad.md → "Quien no puede abrir lo relacionado
-- no queda asignado".
-- ============================================================

-- ============================================================
-- 1. Tipo de notificación (aplicar sola, antes del resto — como sql/056)
-- ============================================================
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_sin_acceso';

-- ============================================================
-- 2. Registro de la transacción
--
-- Nadie más escribe el GUC `tareas.sin_acceso`. Un bloque EXCEPTION que
-- revierte también revierte lo registrado (es local a la transacción, y el
-- ensayo de la sección 10 lee lo que quedó ANTES de forzar su propio
-- rollback). No filtra por queda_afuera de nuevo acá: registra el producto
-- usuarios-excluidos × vínculos-de-la-tarea, y quien lo consuma (sin_acceso)
-- vuelve a aplicar queda_afuera, que es el único predicado de la regla.
-- ============================================================
CREATE OR REPLACE FUNCTION sin_acceso_registrado()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(NULLIF(current_setting('tareas.sin_acceso', true), ''), '[]')::jsonb;
$$;

REVOKE EXECUTE ON FUNCTION public.sin_acceso_registrado() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sin_acceso_registrado() TO authenticated;

CREATE OR REPLACE FUNCTION registrar_sin_acceso(p_tarea_id uuid, p_usuarios uuid[], p_vinculos jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_nuevos jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'tarea_id', p_tarea_id, 'usuario_id', u.usuario_id,
           'ente', v->>'ente', 'registro_id', v->>'registro_id'
         )), '[]'::jsonb)
    INTO v_nuevos
    FROM unnest(p_usuarios) AS u(usuario_id)
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p_vinculos, '[]'::jsonb)) AS v;

  PERFORM set_config('tareas.sin_acceso', (sin_acceso_registrado() || v_nuevos)::text, true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.registrar_sin_acceso(uuid, uuid[], jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_sin_acceso(uuid, uuid[], jsonb) TO authenticated;

-- ============================================================
-- 3. crear_tarea aplica la regla antes de insertar (misma firma que sql/059)
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

  -- El plantilla_id de cada elemento lo copia un disparo (usar_plantilla,
  -- sección 6); la policy de tareas_vinculos sigue exigiendo
  -- pg_trigger_depth() > 0 para esos, así que uno inventado por el cliente
  -- sigue sin poder colarse acá.
  INSERT INTO tareas_vinculos (tarea_id, ente, registro_id, plantilla_id)
  SELECT v_id, x->>'ente', (x->>'registro_id')::uuid, (x->>'plantilla_id')::uuid
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
-- 4. sincronizar_asignados aplica la misma regla (editar_tarea, reasignar_tarea)
--
-- El early return compara contra el conjunto YA filtrado (v_quedan), no
-- contra p_asignados: si lo que en verdad va a quedar asignado no cambió,
-- no hay nada que tocar, aunque el cliente haya pedido de más. Por eso
-- "editar el título sin tocar asignados" no reescribe nada incluso si uno de
-- los ya asignados perdió el acceso mientras tanto — el editor sin
-- `tareas_asignar` ni se entera: TA016 corta ANTES de esa comparación, así
-- que la edición entera se revierte y no toca nada, en vez de sacar a
-- alguien por izquierda.
-- ============================================================
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
  v_previos  uuid[];
  v_vinculos jsonb;
  v_quedan   uuid[];
  v_fuera    uuid[];
  v_vacio    boolean;
BEGIN
  SELECT coalesce(array_agg(usuario_id ORDER BY usuario_id), '{}')
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

  -- Sacar a otro de una tarea es asignar (sql/014): sin la función, la
  -- edición entera se revierte en vez de sacarlo en silencio.
  IF cardinality(v_fuera) > 0 AND NOT tiene_permiso('tareas_asignar') THEN
    RAISE EXCEPTION 'Alguien asignado no puede abrir lo relacionado y no tenés permiso para sacarlo de la tarea'
      USING ERRCODE = 'TA016';
  END IF;

  v_vacio := cardinality(v_quedan) = 0;
  IF v_vacio THEN
    v_quedan := ARRAY[auth.uid()];
  END IF;

  IF v_previos = (SELECT coalesce(array_agg(u ORDER BY u), '{}') FROM unnest(v_quedan) AS u) THEN
    RETURN;
  END IF;

  -- Guardado por el conteo: la tarea sin asignados activos (recién creada por
  -- otra vía, o ya vaciada) afecta 0 filas legítimamente.
  IF array_length(v_previos, 1) > 0 THEN
    UPDATE tareas_asignados SET activo = false
     WHERE tarea_id = p_tarea_id AND activo;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo actualizar los asignados' USING ERRCODE = 'TA008';
    END IF;
  END IF;

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT p_tarea_id, u FROM unnest(v_quedan) AS u;

  UPDATE tareas
     SET responsable_id = CASE WHEN auth.uid() = ANY(v_quedan) THEN auth.uid() ELSE v_quedan[1] END
   WHERE id = p_tarea_id AND NOT (responsable_id = ANY(v_quedan));

  IF cardinality(v_fuera) > 0 THEN
    PERFORM registrar_sin_acceso(p_tarea_id, v_fuera, v_vinculos);
  END IF;

  IF v_vacio THEN
    INSERT INTO tareas_notas (tarea_id, usuario_id, nota)
    VALUES (p_tarea_id, auth.uid(), format(
      'Quedó asignada a vos: %s no pueden abrir lo relacionado con esta tarea.',
      (SELECT string_agg(nombre, ', ') FROM usuarios WHERE id = ANY(v_fuera))
    ));
  END IF;
END;
$$;

-- ============================================================
-- 5. vincular_tarea — relacionar aplica la misma regla
--
-- Reemplaza el INSERT directo de la action `vincularTarea`. Sin asignados
-- activos no se llama a sincronizar_asignados: si no, relacionar asignaría a
-- quien relaciona (que siempre está exento de queda_afuera).
-- ============================================================
CREATE OR REPLACE FUNCTION vincular_tarea(p_tarea_id uuid, p_ente text, p_registro_id uuid)
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
    PERFORM sincronizar_asignados(p_tarea_id, v_activos);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.vincular_tarea(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.vincular_tarea(uuid, text, uuid) TO authenticated;

-- ============================================================
-- 6. usar_plantilla arma los vínculos con plantilla_id (misma firma que sql/060)
--
-- El registro y sus adjuntos pasan por p_vinculos a crear_tarea, que ya trae
-- el filtro de acceso. Reemplaza los dos INSERT directos a tareas_vinculos
-- que iban después de crear_tarea. El v_vacio propio de la plantilla no
-- cambia: ese caso ya asigna a v_uid, que está exento de queda_afuera, así
-- que crear_tarea nunca lo vuelve a vaciar y no hay nota doble.
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
  v_vinculos      jsonb;
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

    -- El registro que dispara, más los adjuntos del paso, cada uno con
    -- plantilla_id: crear_tarea los inserta y les aplica el filtro de acceso.
    v_vinculos := CASE WHEN p_ente IS NOT NULL THEN
      jsonb_build_array(jsonb_build_object('ente', p_ente, 'registro_id', p_registro_id, 'plantilla_id', v_p.id))
      || (
        SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
                 'ente', x.ente, 'registro_id', x.registro_id, 'plantilla_id', v_p.id
               )), '[]'::jsonb)
        FROM relacionados_de_registro(p_ente, p_registro_id) x
        WHERE x.ente || ':' || x.rol = ANY (v_item.adjuntos)
      )
    ELSE '[]'::jsonb END;

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
-- 7. notificar_disparo distingue "corrió, pero alguien quedó afuera"
--
-- Cambia la firma: se borra la de dos argumentos para no dejar una
-- sobrecarga. `p_sin_acceso` con DEFAULT false: las llamadas de dos
-- argumentos que ya existían (plantillas_disparo.sql) siguen andando.
-- ============================================================
DROP FUNCTION IF EXISTS notificar_disparo(uuid, boolean);

CREATE OR REPLACE FUNCTION notificar_disparo(
  p_plantilla_id uuid,
  p_corrio       boolean,
  p_sin_acceso   boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() = 0 THEN
    RETURN;
  END IF;

  PERFORM public.notificar(
    auth.uid(),
    CASE
      WHEN NOT p_corrio  THEN 'plantilla_fallida'
      WHEN p_sin_acceso  THEN 'plantilla_sin_acceso'
      ELSE 'plantilla_disparada'
    END::tipo_notificacion,
    'plantilla',
    p_plantilla_id,
    NULL
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notificar_disparo(uuid, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notificar_disparo(uuid, boolean, boolean) TO authenticated;

-- ============================================================
-- 8. disparar_plantillas detecta el caso mirando el registro de la transacción
--
-- No resetea `tareas.sin_acceso`: el ensayo (sección 10) necesita lo de todas
-- las plantillas que corrieron.
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
  v_antes   int;
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
        v_antes := jsonb_array_length(sin_acceso_registrado());
        PERFORM usar_plantilla(v_pl, NULL, NULL, NULL, v_ente, NEW.id, v_datos);
        PERFORM notificar_disparo(v_pl, true, jsonb_array_length(sin_acceso_registrado()) > v_antes);
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
-- 9. notificaciones_listar lleva el aviso nuevo a Tareas (resto igual a sql/056)
-- ============================================================
CREATE OR REPLACE FUNCTION notificaciones_listar(p_limite int DEFAULT 30)
RETURNS TABLE (
  id         uuid,
  tipo       tipo_notificacion,
  etiqueta   text,
  motivo     text,
  actor      text,
  destino    text,
  destino_id uuid,
  leida      boolean,
  created_at timestamptz
)
LANGUAGE sql STABLE SET search_path = public
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
           obras_etiqueta('obra', o.id) AS etiqueta,
           o.motivo_rechazo             AS motivo,
           'obra'::text                 AS destino,
           o.id                         AS destino_id
    FROM mias n JOIN obras o ON o.id = n.entidad_id
    WHERE n.entidad = 'obra'
    UNION ALL
    SELECT n.id, obras_etiqueta('empresa', e.id), e.motivo_rechazo, 'empresa', e.id
    FROM mias n JOIN obras_empresas e ON e.id = n.entidad_id
    WHERE n.entidad = 'empresa'
    UNION ALL
    SELECT n.id, obras_etiqueta('persona', p.id), p.motivo_rechazo, 'persona', p.id
    FROM mias n JOIN obras_personas p ON p.id = n.entidad_id
    WHERE n.entidad = 'persona'
    UNION ALL
    SELECT n.id, t.titulo, NULL::text, 'tarea', t.id
    FROM mias n JOIN tareas t ON t.id = n.entidad_id
    WHERE n.entidad = 'tarea'
    UNION ALL
    SELECT n.id, pl.nombre, NULL::text,
           CASE WHEN n.tipo IN ('plantilla_disparada', 'plantilla_sin_acceso') THEN 'tareas'
                WHEN pl.activo THEN 'plantilla' END,
           pl.id
    FROM mias n JOIN tareas_plantillas pl ON pl.id = n.entidad_id
    WHERE n.entidad = 'plantilla'
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, u.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r      ON r.notificacion_id = n.id
  LEFT JOIN usuarios u ON u.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;

-- ============================================================
-- 10. obras_ensayar_estado — el cambio de estado, con rollback
--
-- Adentro de un bloque que termina en RAISE con un SQLSTATE propio (TA017),
-- que ese mismo bloque atrapa: el cambio se hace de verdad (así el trigger de
-- Obras dispara sus plantillas de verdad) y se revierte entero al final —
-- tareas, vínculos, avisos, auditoría. `TA017` nunca sale de la función, así
-- que no necesita entrar a MENSAJES_ERROR. Cualquier otro error (RLS, el
-- CHECK de pérdida) sube tal cual: no lo atrapa este bloque.
--
-- INVOKER a propósito: el disparo exige `current_user = 'authenticated'`
-- (ver disparar_plantillas) — con DEFINER el UPDATE correría como el dueño
-- de la función y no dispararía nada.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_ensayar_estado(
  p_obra_id         uuid,
  p_estado          estado_obra,
  p_motivo_perdida  motivo_perdida,
  p_detalle_perdida text
)
RETURNS TABLE (
  usuario_id  uuid,
  usuario     text,
  ente        text,
  registro_id uuid,
  etiqueta    text,
  compartible boolean
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_pares jsonb := '[]'::jsonb;
BEGIN
  BEGIN
    UPDATE obras
       SET estado = p_estado, motivo_perdida = p_motivo_perdida, detalle_perdida = p_detalle_perdida
     WHERE id = p_obra_id AND estado IS DISTINCT FROM p_estado;

    IF FOUND THEN
      v_pares := sin_acceso_registrado();
    END IF;

    RAISE EXCEPTION 'ensayo' USING ERRCODE = 'TA017';
  EXCEPTION
    WHEN SQLSTATE 'TA017' THEN
      NULL;
  END;

  RETURN QUERY SELECT * FROM sin_acceso(v_pares);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_ensayar_estado(uuid, estado_obra, motivo_perdida, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_ensayar_estado(uuid, estado_obra, motivo_perdida, text) TO authenticated;
