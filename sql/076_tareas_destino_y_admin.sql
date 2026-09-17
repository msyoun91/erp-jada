-- ============================================================
-- 076 — Dónde se puede escribir una tarea, un hilo o un miembro
--
-- Auditoría 2026-09-17 (`PLAN_AUDITORIA_TAREAS.md`, fase 1). Tres huecos por
-- la API, más la regla de que siempre hay una función que administra
-- (`tareas_gestionar_ajenas`, ver decisiones/global/permisos.md):
--
-- 1. `tareas_insert` no miraba `hilo_id`: con el id de un hilo ajeno, cualquiera
--    creaba una tarea adentro, se la asignaba (siembra) y `puede_ver_hilo` le
--    abría el hilo entero. Lo mismo moviendo una tarea propia
--    (`asociarTareaHilo`). Ahora el hilo destino tiene que estar activo y ser
--    visible para quien escribe — o ser un hilo suyo todavía vacío:
--    `convertir_tarea_en_hilo` crea el hilo con el responsable de la tarea, que
--    puede no ser quien convierte, y mueve la tarea después.
-- 2. `tareas_insert` y `tareas_hilos_insert` no miraban `proyecto_id`: se metía
--    trabajo en proyectos privados ajenos, y el responsable de un hilo lo movía
--    de proyecto por UPDATE directo (la regla vivía solo en Zod). Ahora el
--    proyecto destino tiene que estar activo y ser visible
--    (`tareas_proyecto_destino_valido`, fuente única), y `tareas_hilos` pierde
--    UPDATE de `proyecto_id`, `creado_por`, `id` y `created_at`.
-- 3. Con `tareas_proyectos_miembros`, sumar o sacar miembros valía en cualquier
--    proyecto, aunque no lo viera: uno se sumaba a un privado ajeno. Ahora solo
--    en proyectos donde es miembro; `tareas_gestionar_ajenas`, en cualquiera.
--    `editar_proyecto` inserta antes de quitar, para que quien se saca a sí
--    mismo en el mismo guardado todavía pueda sumar a los otros.
-- A. El administrador (`tareas_gestionar_ajenas`) asigna a alguien que no es
--    miembro del proyecto: en vez de rechazar, lo suma al proyecto
--    (`tareas_sumar_miembros_admin`, llamada antes de insertar asignados, y
--    `validar_proyecto_tarea_miembros` al mover la tarea). Sin la función, la
--    regla de sql/009 sigue igual.
--
-- `auth.uid()` NULL (postgres, service_role) no valida: mismo criterio que
-- `validar_responsable_tarea`.
-- ============================================================

-- ─── Fuente única: a qué proyecto puede ir trabajo ───────────────────────────
CREATE OR REPLACE FUNCTION tareas_proyecto_destino_valido(p_proyecto_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tareas_proyectos p
    WHERE p.id = p_proyecto_id
      AND p.activo
      AND (
        p.visibilidad = 'publico'
        OR es_miembro_proyecto(p.id, p_usuario)
        OR usuario_tiene_permiso(p_usuario, 'tareas_gestionar_ajenas')
      )
  );
$$;

REVOKE EXECUTE ON FUNCTION tareas_proyecto_destino_valido(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION tareas_proyecto_destino_valido(uuid, uuid) TO authenticated;

-- ─── 1 y 2 en tareas: trigger (cubre INSERT, UPDATE y las funciones) ─────────
CREATE OR REPLACE FUNCTION validar_destino_tarea()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.hilo_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.hilo_id IS DISTINCT FROM OLD.hilo_id)
     AND NOT EXISTS (
       SELECT 1 FROM tareas_hilos h
       WHERE h.id = NEW.hilo_id
         AND h.activo
         AND (
           puede_ver_hilo_de(h.id, v_uid)
           OR (
             h.creado_por = v_uid
             AND NOT EXISTS (
               SELECT 1 FROM tareas t
               WHERE t.hilo_id = h.id AND t.activo AND t.id <> NEW.id
             )
           )
         )
     ) THEN
    RAISE EXCEPTION 'El hilo no existe o no tenés acceso a él' USING ERRCODE = 'TA017';
  END IF;

  IF NEW.proyecto_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id)
     AND NOT tareas_proyecto_destino_valido(NEW.proyecto_id, v_uid) THEN
    RAISE EXCEPTION 'El proyecto no existe o no tenés acceso a él' USING ERRCODE = 'TA017';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION validar_destino_tarea() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validar_destino_tarea ON tareas;
CREATE TRIGGER trg_validar_destino_tarea
  BEFORE INSERT OR UPDATE OF hilo_id, proyecto_id ON tareas
  FOR EACH ROW EXECUTE FUNCTION validar_destino_tarea();

-- ─── 2 en hilos: policy de INSERT y sin UPDATE de proyecto ───────────────────
DROP POLICY IF EXISTS tareas_hilos_insert ON tareas_hilos;
CREATE POLICY tareas_hilos_insert ON tareas_hilos
  FOR INSERT
  WITH CHECK (
    creado_por = (SELECT auth.uid())
    AND (responsable_id = (SELECT auth.uid()) OR tiene_permiso('tareas_asignar'))
    AND (proyecto_id IS NULL OR tareas_proyecto_destino_valido(proyecto_id, (SELECT auth.uid())))
  );

REVOKE UPDATE ON tareas_hilos FROM authenticated;
GRANT UPDATE (titulo, descripcion, visibilidad, estado, responsable_id, posponer_desde, posponer_hasta, activo)
  ON tareas_hilos TO authenticated;

-- ─── 3: miembros solo en proyectos propios, salvo el administrador ───────────
DROP POLICY IF EXISTS tareas_proyectos_miembros_insert ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_insert ON tareas_proyectos_miembros
  FOR INSERT
  WITH CHECK (
    tiene_permiso('tareas_gestionar_ajenas')
    OR (tiene_permiso('tareas_proyectos_miembros') AND es_miembro_proyecto(proyecto_id, (SELECT auth.uid())))
    OR (es_creador_proyecto(proyecto_id) AND NOT proyecto_tiene_miembros(proyecto_id))
  );

DROP POLICY IF EXISTS tareas_proyectos_miembros_update ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_update ON tareas_proyectos_miembros
  FOR UPDATE
  USING (
    tiene_permiso('tareas_gestionar_ajenas')
    OR (tiene_permiso('tareas_proyectos_miembros') AND es_miembro_proyecto(proyecto_id, (SELECT auth.uid())))
  )
  WITH CHECK (
    tiene_permiso('tareas_gestionar_ajenas')
    OR (tiene_permiso('tareas_proyectos_miembros') AND es_miembro_proyecto(proyecto_id, (SELECT auth.uid())))
  );

CREATE OR REPLACE FUNCTION editar_proyecto(
  p_id uuid, p_nombre text, p_descripcion text, p_visibilidad visibilidad, p_miembros uuid[]
)
RETURNS void
LANGUAGE plpgsql
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

  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
  SELECT p_id, u
    FROM unnest(p_miembros) AS u
   WHERE NOT EXISTS (
     SELECT 1 FROM tareas_proyectos_miembros m
      WHERE m.proyecto_id = p_id AND m.usuario_id = u AND m.activo
   );

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
END;
$$;

-- ─── A: el administrador suma al proyecto a quien asigna ─────────────────────
-- INVOKER: el INSERT en miembros lo autoriza la policy (rama de
-- `tareas_gestionar_ajenas`). Va en su propia sentencia antes del INSERT de
-- asignados: la policy de asignados lee la membresía con una función STABLE,
-- que no vería un miembro sumado en la misma sentencia.
CREATE OR REPLACE FUNCTION tareas_sumar_miembros_admin(p_tarea_id uuid, p_usuarios uuid[])
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_proyecto uuid;
BEGIN
  IF NOT tiene_permiso('tareas_gestionar_ajenas') THEN
    RETURN;
  END IF;

  SELECT COALESCE(t.proyecto_id, h.proyecto_id) INTO v_proyecto
    FROM tareas t
    LEFT JOIN tareas_hilos h ON h.id = t.hilo_id
   WHERE t.id = p_tarea_id;

  IF v_proyecto IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
  SELECT DISTINCT v_proyecto, u
    FROM unnest(p_usuarios) AS u
   WHERE NOT es_miembro_proyecto(v_proyecto, u);
END;
$$;

REVOKE EXECUTE ON FUNCTION tareas_sumar_miembros_admin(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION tareas_sumar_miembros_admin(uuid, uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION validar_proyecto_tarea_miembros()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proyecto_id uuid;
BEGIN
  v_proyecto_id := COALESCE(
    NEW.proyecto_id,
    (SELECT h.proyecto_id FROM tareas_hilos h WHERE h.id = NEW.hilo_id)
  );

  IF v_proyecto_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM tareas_asignados ta
    WHERE ta.tarea_id = NEW.id AND ta.activo
      AND NOT es_miembro_proyecto(v_proyecto_id, ta.usuario_id)
  ) THEN
    IF NOT tiene_permiso('tareas_gestionar_ajenas') THEN
      RAISE EXCEPTION 'Hay asignados que no son miembros del proyecto destino'
        USING ERRCODE = 'TA002';
    END IF;

    INSERT INTO tareas_proyectos_miembros (proyecto_id, usuario_id)
    SELECT DISTINCT v_proyecto_id, ta.usuario_id
      FROM tareas_asignados ta
     WHERE ta.tarea_id = NEW.id AND ta.activo
       AND NOT es_miembro_proyecto(v_proyecto_id, ta.usuario_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION crear_tarea(
  p_titulo text, p_descripcion text, p_hilo_id uuid, p_proyecto_id uuid, p_paso_anterior_id uuid,
  p_visibilidad visibilidad, p_responsable_id uuid, p_asignados uuid[], p_fecha_vencimiento date,
  p_temperatura integer, p_recurrencia_cantidad integer, p_recurrencia_unidad recurrencia_unidad,
  p_modo_completado modo_completado, p_origen_app text, p_origen_punto text,
  p_vence_dias_tras_previo integer, p_vinculos jsonb DEFAULT '[]'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
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

  PERFORM tareas_sumar_miembros_admin(v_id, v_asignados);

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

CREATE OR REPLACE FUNCTION sincronizar_asignados(p_tarea_id uuid, p_asignados uuid[], p_responsable_id uuid)
RETURNS void
LANGUAGE plpgsql
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

  PERFORM tareas_sumar_miembros_admin(p_tarea_id, v_agregar);

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
