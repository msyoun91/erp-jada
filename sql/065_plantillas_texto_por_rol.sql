-- ============================================================
-- 065 — Plantillas: texto y pasos que dependen de un rol
--
-- Venía en el borrador de sql/064 sin UI ni decisión escrita; quedó en
-- BACKLOG.md y se construye ahora con su editor.
--
--   1. `rellenar_datos` suma `p_roles`: resuelve los bloques
--      `{si hay ente:rol}…{fin}` y `{si no hay ente:rol}…{fin}` antes que los
--      `{dato}`, así un dato adentro de un bloque también se completa.
--   2. `condicion` acepta `!ente:rol`: el paso se crea solo si NO hay ese rol.
--   3. `usar_plantilla` calcula los roles del registro una sola vez y los usa
--      para la condición y para cada texto.
-- Ver decisiones/tareas/plantillas.md → "Texto y pasos que dependen de un rol".
-- ============================================================

-- ============================================================
-- 1. rellenar_datos(texto, datos, roles)
--
-- Sin anidar. El cuerpo no puede contener `{fin}` ni otro `{si `: un bloque
-- adentro de otro deja la cabecera de afuera como texto. Una cabecera que no
-- se entiende (`{si hay Arquitecto}`) también queda como está: mejor mostrar
-- de más que borrar una frase. Sin registro no hay ningún rol, así que
-- `si no hay` se muestra y `si hay` no.
--
-- `replace` pisa todas las copias idénticas de un bloque, que resuelven igual;
-- y como ningún bloque contiene a otro, no rompe el texto del siguiente.
-- ============================================================
DROP FUNCTION IF EXISTS public.rellenar_datos(text, jsonb);

CREATE FUNCTION public.rellenar_datos(p_texto text, p_datos jsonb, p_roles text[])
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_bloque text[];
  v_clave  text;
  v_valor  text;
BEGIN
  FOR v_bloque IN
    SELECT regexp_matches(p_texto, '(\{si (no )?hay ([a-z_]+:[a-z_]+)\}((?:[^{]|\{(?!fin\}|si ))*)\{fin\})', 'g')
  LOOP
    p_texto := replace(p_texto, v_bloque[1], CASE
      WHEN (v_bloque[3] = ANY (COALESCE(p_roles, '{}'))) = (v_bloque[2] IS NULL) THEN v_bloque[4]
      ELSE ''
    END);
  END LOOP;

  FOR v_clave, v_valor IN SELECT key, value FROM jsonb_each_text(COALESCE(p_datos, '{}'::jsonb)) LOOP
    p_texto := replace(p_texto, '{' || v_clave || '}', COALESCE(v_valor, ''));
  END LOOP;
  RETURN p_texto;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rellenar_datos(text, jsonb, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rellenar_datos(text, jsonb, text[]) TO authenticated;

-- ============================================================
-- 2. Condición negada
-- ============================================================
ALTER TABLE tareas_plantillas_items
  DROP CONSTRAINT tareas_plantillas_items_condicion_formato,
  ADD CONSTRAINT tareas_plantillas_items_condicion_formato
    CHECK (condicion IS NULL OR condicion ~ '^!?[a-z_]+:[a-z_]+$');

-- ============================================================
-- 3. usar_plantilla — igual que sql/063 salvo `v_roles`
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
        SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
                 'ente', x.ente, 'registro_id', x.registro_id, 'plantilla_id', v_p.id
               )), '[]'::jsonb)
        FROM relacionados_de_registro(p_ente, p_registro_id) x
        WHERE x.ente || ':' || x.rol = ANY (v_item.adjuntos)
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
