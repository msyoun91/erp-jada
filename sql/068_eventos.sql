-- ============================================================
-- 068 — El bus de eventos
--
-- BACKLOG.md → "Tareas sobre el modelo de entes" y GUIDE_ENTES.md §2.8.
-- Hasta acá el único evento era "una obra entró a un estado", con
-- `disparar_plantillas` colgado directo de `obras`, y la auditoría de Tareas
-- vivía aparte en `tareas_eventos`.
--
--   1. `eventos` + `emitir_evento`: el log y el punto donde escuchan los
--      consumidores. Lo que no ves, no pasó.
--   2. `entes` gana `tabla` (de dónde lee un consumidor los datos del
--      registro) y `disparos` (qué eventos pueden disparar una plantilla).
--   3. Dos triggers genéricos: uno sobre la tabla del ente (alta, baja,
--      reactivación, estado) y uno sobre cada tabla puente (un rol que
--      aparece o se va). Obras los cuelga de `obras` y de sus dos puentes;
--      Tareas, de `tareas`.
--   4. `tareas_eventos` pasa a ser filas de `eventos` con `ente = 'tarea'`.
--   5. Las plantillas escuchan `eventos`: `disparo_evento` y `disparo_rol`.
--
-- `baja` y `reactivacion` de una obra se registran pero no disparan:
-- `obras_set_activo` es DEFINER, y el disparo solo corre como quien actúa
-- (la guarda de `current_user` de sql/055). Por eso no están en
-- `entes.disparos`. `transferencia`, `compartido` y `revocado` se suman al
-- enum cuando alguien los emita.
--
-- Ver decisiones/global/entes.md → "Los eventos van a una tabla `eventos`".
-- ============================================================

-- ============================================================
-- 1. eventos
-- ============================================================
CREATE TYPE tipo_evento AS ENUM ('alta', 'baja', 'reactivacion', 'estado', 'relacion_alta', 'relacion_baja');

-- Sin `activo` ni `updated_at`: una auditoría no oculta ni reescribe sus
-- filas (misma excepción que tenía `tareas_eventos`). `clock_timestamp()` y
-- no `now()`: una misma sentencia emite varios (reactivación y estado) y el
-- orden tiene que quedar.
CREATE TABLE eventos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ente        text NOT NULL REFERENCES entes(codigo),
  registro_id uuid NOT NULL,
  evento      tipo_evento NOT NULL,
  detalle     jsonb NOT NULL DEFAULT '{}',
  actor_id    uuid REFERENCES usuarios(id),
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX idx_eventos_registro ON eventos (ente, registro_id, created_at);
CREATE INDEX idx_eventos_actor ON eventos (actor_id);

ALTER TABLE eventos ENABLE ROW LEVEL SECURITY;

CREATE POLICY eventos_select ON eventos FOR SELECT TO authenticated
  USING (etiqueta_registro(ente, registro_id) IS NOT NULL);

-- Solo desde un trigger, como los vínculos de un disparo (sql/055): un evento
-- inventado por el cliente dispararía plantillas.
CREATE POLICY eventos_insert ON eventos FOR INSERT TO authenticated
  WITH CHECK (pg_trigger_depth() > 0);

GRANT SELECT, INSERT ON eventos TO authenticated;

-- INVOKER: con DEFINER, `current_user` sería `postgres` y el disparo, que
-- corre con la RLS de quien actúa, no correría nunca.
CREATE OR REPLACE FUNCTION emitir_evento(p_ente text, p_registro_id uuid, p_evento tipo_evento, p_detalle jsonb DEFAULT '{}')
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
  INSERT INTO eventos (ente, registro_id, evento, detalle, actor_id)
  VALUES (p_ente, p_registro_id, p_evento, p_detalle, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.emitir_evento(text, uuid, tipo_evento, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.emitir_evento(text, uuid, tipo_evento, jsonb) TO authenticated;

-- ============================================================
-- 2. entes: tabla y disparos
-- ============================================================
ALTER TABLE entes
  ADD COLUMN tabla regclass,
  ADD COLUMN disparos tipo_evento[] NOT NULL DEFAULT '{}';

UPDATE entes SET tabla = 'obras', disparos = '{alta,estado,relacion_alta,relacion_baja}' WHERE codigo = 'obra';
UPDATE entes SET tabla = 'obras_empresas' WHERE codigo = 'empresa';
UPDATE entes SET tabla = 'obras_personas' WHERE codigo = 'persona';
UPDATE entes SET tabla = 'tareas' WHERE codigo = 'tarea';

ALTER TABLE entes ALTER COLUMN tabla SET NOT NULL;

-- ============================================================
-- 3. Los emisores
-- ============================================================

-- TG_ARGV = (ente). La columna de estado se llama `estado` (GUIDE_ENTES §2.1);
-- sin ella, solo alta, baja y reactivación. Reactivación antes que estado y
-- baja después: quien escucha el estado encuentra el registro como quedó.
CREATE OR REPLACE FUNCTION emitir_eventos_registro()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ente   text    := TG_ARGV[0];
  v_nueva  jsonb   := to_jsonb(NEW);
  v_vieja  jsonb   := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_activo boolean := (v_nueva->>'activo')::boolean;
  v_estaba boolean := (v_vieja->>'activo')::boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT v_activo THEN
      RETURN NULL;
    END IF;
    PERFORM emitir_evento(v_ente, NEW.id, 'alta');
  ELSIF v_activo AND NOT v_estaba THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'reactivacion');
  END IF;

  IF v_nueva ? 'estado' AND v_nueva->>'estado' IS DISTINCT FROM v_vieja->>'estado' THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'estado',
      jsonb_build_object('estado', v_nueva->>'estado', 'anterior', v_vieja->>'estado'));
  END IF;

  IF v_estaba AND NOT v_activo THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'baja');
  END IF;

  RETURN NULL;
END;
$$;

-- TG_ARGV = (ente, su columna, ente relacionado, su columna). Un evento por rol
-- que aparece o se va: vincular con dos roles son dos altas, sacarle uno a un
-- vínculo es una baja, desactivarlo es la baja de todos. El evento es del ente,
-- no del relacionado: "la obra suma un arquitecto".
CREATE OR REPLACE FUNCTION emitir_eventos_relacion()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_nueva    jsonb  := to_jsonb(NEW);
  v_vieja    jsonb  := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_registro uuid   := (v_nueva->>TG_ARGV[1])::uuid;
  v_otro     uuid   := (v_nueva->>TG_ARGV[3])::uuid;
  v_antes    text[] := CASE WHEN (v_vieja->>'activo')::boolean
                            THEN ARRAY(SELECT jsonb_array_elements_text(v_vieja->'roles')) ELSE '{}' END;
  v_despues  text[] := CASE WHEN (v_nueva->>'activo')::boolean
                            THEN ARRAY(SELECT jsonb_array_elements_text(v_nueva->'roles')) ELSE '{}' END;
  v_rol      text;
BEGIN
  FOR v_rol IN SELECT unnest(v_antes) EXCEPT SELECT unnest(v_despues) LOOP
    PERFORM emitir_evento(TG_ARGV[0], v_registro, 'relacion_baja',
      jsonb_build_object('ente', TG_ARGV[2], 'registro_id', v_otro, 'rol', v_rol));
  END LOOP;

  FOR v_rol IN SELECT unnest(v_despues) EXCEPT SELECT unnest(v_antes) LOOP
    PERFORM emitir_evento(TG_ARGV[0], v_registro, 'relacion_alta',
      jsonb_build_object('ente', TG_ARGV[2], 'registro_id', v_otro, 'rol', v_rol));
  END LOOP;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.emitir_eventos_registro() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emitir_eventos_relacion() FROM PUBLIC;

CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado ON obras
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('obra');

CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, roles ON obras_obra_empresa
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_relacion('obra', 'obra_id', 'empresa', 'empresa_id');

CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, roles ON obras_obra_persona
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_relacion('obra', 'obra_id', 'persona', 'persona_id');

-- ============================================================
-- 4. tareas_eventos → eventos
-- ============================================================
INSERT INTO eventos (ente, registro_id, evento, detalle, actor_id, created_at)
SELECT 'tarea', tarea_id, 'estado',
       jsonb_build_object('estado', estado_nuevo, 'anterior', estado_anterior),
       usuario_id, created_at
FROM tareas_eventos;

DROP TRIGGER trg_log_evento_tarea ON tareas;
DROP FUNCTION log_evento_tarea();
DROP TABLE tareas_eventos;

-- Una tarea no dispara plantillas (`entes.disparos` vacío): una que se
-- disparara con el alta de una tarea crearía otra, que dispararía otra.
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado ON tareas
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('tarea');

-- ============================================================
-- 5. Las plantillas escuchan eventos
-- ============================================================
ALTER TABLE tareas_plantillas
  ADD COLUMN disparo_evento tipo_evento,
  ADD COLUMN disparo_rol text;

UPDATE tareas_plantillas SET disparo_evento = 'estado' WHERE disparo_ente IS NOT NULL;

-- Estado solo con `estado`; rol (`ente:rol`, como `adjuntos`) solo con una
-- relación.
ALTER TABLE tareas_plantillas DROP CONSTRAINT tareas_plantillas_disparo_completo;
ALTER TABLE tareas_plantillas ADD CONSTRAINT tareas_plantillas_disparo_completo CHECK (
  CASE
    WHEN disparo_ente IS NULL THEN
      disparo_evento IS NULL AND disparo_estado IS NULL AND disparo_rol IS NULL
    ELSE
      disparo_evento IS NOT NULL
      AND (disparo_estado IS NOT NULL) = (disparo_evento = 'estado')
      AND (disparo_rol IS NOT NULL) = (disparo_evento IN ('relacion_alta', 'relacion_baja'))
      AND (disparo_rol IS NULL OR disparo_rol ~ '^[a-z_]+:[a-z_]+$')
  END
);

GRANT UPDATE (disparo_evento, disparo_rol) ON tareas_plantillas TO authenticated;

-- INSERT y UPDATE suman que el ente dispare con ese evento: sin eso, un PATCH
-- directo podría colgar una plantilla del alta de una tarea. El SELECT no
-- cambia.
DROP POLICY tareas_plantillas_insert ON tareas_plantillas;
CREATE POLICY tareas_plantillas_insert ON tareas_plantillas FOR INSERT TO authenticated
  WITH CHECK (
    creado_por = (SELECT auth.uid())
    AND tiene_permiso('tareas_plantillas')
    AND (alcance = 'privada' OR tiene_permiso('tareas_plantillas_sistema'))
    AND (
      disparo_ente IS NULL
      OR EXISTS (SELECT 1 FROM entes e WHERE e.codigo = tareas_plantillas.disparo_ente
                                         AND tareas_plantillas.disparo_evento = ANY (e.disparos))
    )
  );

DROP POLICY tareas_plantillas_update ON tareas_plantillas;
CREATE POLICY tareas_plantillas_update ON tareas_plantillas FOR UPDATE TO authenticated
  USING (puede_gestionar_plantilla(id))
  WITH CHECK (
    puede_gestionar_plantilla(id)
    AND (
      disparo_ente IS NULL
      OR EXISTS (SELECT 1 FROM entes e WHERE e.codigo = tareas_plantillas.disparo_ente
                                         AND tareas_plantillas.disparo_evento = ANY (e.disparos))
    )
  );

-- Firma nueva (dos parámetros al final): DROP + CREATE, y los GRANT de nuevo.
DROP FUNCTION guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text, text, boolean);

CREATE FUNCTION guardar_plantilla(
  p_id uuid,
  p_nombre text,
  p_descripcion text,
  p_alcance alcance_plantilla,
  p_tipo tipo_plantilla,
  p_visibilidad visibilidad,
  p_miembros uuid[],
  p_hilos jsonb,
  p_pasos jsonb,
  p_disparo_ente text DEFAULT NULL,
  p_disparo_estado text DEFAULT NULL,
  p_titulo_creado text DEFAULT NULL,
  p_encadenada boolean DEFAULT true,
  p_disparo_evento tipo_evento DEFAULT NULL,
  p_disparo_rol text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id            uuid := COALESCE(p_id, gen_random_uuid());
  v_hilo_ids      uuid[];
  v_titulo_creado text := CASE WHEN p_tipo <> 'tarea' THEN NULLIF(trim(p_titulo_creado), '') END;
  v_encadenada    boolean := p_tipo <> 'hilo' OR COALESCE(p_encadenada, true);
  -- Sin evento, el disparador de antes de sql/068: entrar a un estado.
  v_evento        tipo_evento := CASE WHEN p_disparo_ente IS NOT NULL THEN COALESCE(p_disparo_evento, 'estado') END;
  v_estado        text := CASE WHEN v_evento = 'estado' THEN p_disparo_estado END;
  v_rol           text := CASE WHEN v_evento IN ('relacion_alta', 'relacion_baja') THEN p_disparo_rol END;
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

  IF p_disparo_ente IS NOT NULL AND NOT EXISTS (
       SELECT 1
       FROM entes e
       WHERE e.codigo = p_disparo_ente
         AND v_evento = ANY (e.disparos)
         AND CASE v_evento
               WHEN 'estado' THEN EXISTS (
                 SELECT 1 FROM pg_enum en WHERE en.enumtypid = e.estados AND en.enumlabel = v_estado
               )
               WHEN 'relacion_alta' THEN v_rol ~ '^[a-z_]+:[a-z_]+$'
               WHEN 'relacion_baja' THEN v_rol ~ '^[a-z_]+:[a-z_]+$'
               ELSE true
             END
     ) THEN
    RAISE EXCEPTION 'El disparador no es válido' USING ERRCODE = 'TA012';
  END IF;

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
      disparo_ente, disparo_evento, disparo_estado, disparo_rol, titulo_creado, encadenada, creado_por
    )
    VALUES (
      v_id, p_nombre, p_descripcion, p_alcance, p_tipo, p_visibilidad, p_miembros,
      p_disparo_ente, v_evento, v_estado, v_rol, v_titulo_creado, v_encadenada, auth.uid()
    );
  ELSE
    UPDATE tareas_plantillas SET
      nombre         = p_nombre,
      descripcion    = p_descripcion,
      tipo           = p_tipo,
      visibilidad    = p_visibilidad,
      miembros       = p_miembros,
      disparo_ente   = p_disparo_ente,
      disparo_evento = v_evento,
      disparo_estado = v_estado,
      disparo_rol    = v_rol,
      titulo_creado  = v_titulo_creado,
      encadenada     = v_encadenada
    WHERE id = p_id AND activo;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La plantilla no existe o no tenés permiso para modificarla' USING ERRCODE = 'TA008';
    END IF;

    UPDATE tareas_plantillas_items SET activo = false WHERE plantilla_id = v_id AND activo;
    UPDATE tareas_plantillas_hilos SET activo = false WHERE plantilla_id = v_id AND activo;
  END IF;

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

REVOKE EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text, text, boolean, tipo_evento, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text, text, boolean, tipo_evento, text) TO authenticated;

-- El disparo se muda de `obras` a `eventos`. Mismo cuerpo que sql/063, salvo:
-- las plantillas se filtran por evento, estado y rol del detalle; la fila del
-- registro se lee de `entes.tabla` con la RLS de quien actúa, y solo si alguna
-- plantilla coincide; y `tareas.disparo` vuelve a lo que tenía, porque ahora
-- un disparo anida otro (la tarea que crea emite su alta).
DROP TRIGGER disparar_plantillas ON obras;

CREATE OR REPLACE FUNCTION disparar_plantillas()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_plantillas uuid[];
  v_ente       entes%ROWTYPE;
  v_fila       jsonb;
  v_datos      jsonb;
  v_disparo    text := current_setting('tareas.disparo', true);
  v_pl         uuid;
  v_antes      int;
BEGIN
  IF current_user <> 'authenticated' THEN
    RETURN NULL;
  END IF;

  v_plantillas := ARRAY(
    SELECT p.id
      FROM tareas_plantillas p
      JOIN tareas_plantillas_activaciones a
        ON a.plantilla_id = p.id AND a.usuario_id = v_uid AND a.activo
     WHERE p.activo
       AND p.disparo_ente = NEW.ente
       AND p.disparo_evento = NEW.evento
       AND (p.disparo_estado IS NULL OR p.disparo_estado = NEW.detalle->>'estado')
       AND (p.disparo_rol IS NULL OR p.disparo_rol = (NEW.detalle->>'ente') || ':' || (NEW.detalle->>'rol'))
     ORDER BY p.created_at
  );

  IF cardinality(v_plantillas) = 0 THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_ente FROM entes WHERE codigo = NEW.ente;
  EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE t.id = $1', v_ente.tabla)
    INTO v_fila USING NEW.registro_id;

  IF NOT COALESCE((v_fila->>'activo')::boolean, false) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_object_agg(d.dato, v_fila->>d.dato)
    INTO v_datos
    FROM unnest(v_ente.datos) AS d(dato);

  PERFORM set_config('tareas.disparo', 'on', true);

  FOREACH v_pl IN ARRAY v_plantillas LOOP
    BEGIN
      IF NOT plantilla_disparada(v_pl, NEW.ente, NEW.registro_id) THEN
        v_antes := jsonb_array_length(sin_acceso_registrado());
        PERFORM usar_plantilla(v_pl, NULL, NULL, NULL, NEW.ente, NEW.registro_id, v_datos);
        PERFORM notificar_disparo(v_pl, true, jsonb_array_length(sin_acceso_registrado()) > v_antes);
      END IF;
    EXCEPTION
      WHEN SQLSTATE 'TA014' THEN
        NULL;
      WHEN OTHERS THEN
        PERFORM notificar_disparo(v_pl, false);
    END;
  END LOOP;

  PERFORM set_config('tareas.disparo', COALESCE(v_disparo, ''), true);
  RETURN NULL;
END;
$$;

CREATE TRIGGER disparar_plantillas
  AFTER INSERT ON eventos
  FOR EACH ROW EXECUTE FUNCTION disparar_plantillas();
