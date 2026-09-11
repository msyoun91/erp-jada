-- ============================================================
-- 053 — Plantillas: sistema y privadas, tres tipos, pasos completos
--
-- Fase 1 del rediseño de plantillas (la fase 2 las conecta con disparadores
-- de otros módulos). Ver decisiones/tareas.md → "Plantillas de sistema y
-- privadas".
--
--   1. Fix de siembra: crear una tarea con OTRO como responsable fallaba para
--      quien tiene `tareas_asignar` sin `tareas_gestionar_ajenas`.
--   2. `tareas.vence_dias_tras_previo`: el plazo corre desde que se completa
--      el paso anterior.
--   3. `crear_tarea` / `editar_tarea` aceptan ese plazo.
--   4. La plantilla gana alcance (sistema | privada), tipo (tarea | hilo |
--      proyecto) y pasos completos; los hilos de una plantilla de proyecto
--      viven en `tareas_plantillas_hilos`.
--   5. Función `tareas_plantillas_sistema` y policies por alcance.
--   6. `guardar_plantilla` / `usar_plantilla` reemplazan a las escrituras de
--      actions.ts y a `agregar_tareas_desde_plantilla`.
--
-- 0 plantillas activas al aplicar: no hay datos que migrar. Las inactivas
-- quedan `sistema`, que es lo que eran (recurso de equipo).
-- ============================================================

-- ============================================================
-- 1. Siembra de asignados al crear una tarea
-- ============================================================
-- `tareas_asignados_insert` pedía ser responsable de la tarea (o
-- gestionar_ajenas) para cargarle asignados. Crear una tarea con otro como
-- responsable — lo que `tareas_asignar` habilita desde sql/014 — dejaba a quien
-- la crea sin poder cargar ninguno: 42501 y la tarea no nacía. No se veía
-- porque el backfill de sql/014 le dio la función solo a quien ya tenía
-- gestionar_ajenas.
--
-- Misma salida que la siembra de miembros de proyecto (sql/013): el creador
-- carga los asignados mientras la tarea no tuvo NUNCA ninguno. "Nunca" y no
-- "ninguno activo": por activos, el creador que quedó afuera podría volver a
-- meterse cuando el último asignado se saca solo — el hueco que cerró sql/013.
CREATE OR REPLACE FUNCTION es_siembra_tarea(p_tarea_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
           SELECT 1 FROM public.tareas t
           WHERE t.id = p_tarea_id AND t.creado_por = auth.uid()
         )
     AND NOT EXISTS (
           SELECT 1 FROM public.tareas_asignados a
           WHERE a.tarea_id = p_tarea_id
         );
$$;

DROP POLICY IF EXISTS tareas_asignados_insert ON tareas_asignados;
CREATE POLICY tareas_asignados_insert ON tareas_asignados FOR INSERT
  WITH CHECK (
    (
      tiene_permiso('tareas_gestionar_ajenas')
      OR es_responsable_tarea(tarea_id)
      OR es_siembra_tarea(tarea_id)
    )
    AND (usuario_id = (select auth.uid()) OR tiene_permiso('tareas_asignar'))
    AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))
  );

-- ============================================================
-- 2. Vencimiento que corre desde el paso anterior
-- ============================================================
-- Mientras el paso anterior no esté completado, la tarea no tiene fecha: el
-- plazo todavía no corre. La fecha es derivada — la escriben los dos triggers
-- de abajo, nadie más la calcula.
ALTER TABLE tareas ADD COLUMN IF NOT EXISTS vence_dias_tras_previo int;

ALTER TABLE tareas DROP CONSTRAINT IF EXISTS tareas_vence_tras_previo;
ALTER TABLE tareas ADD CONSTRAINT tareas_vence_tras_previo CHECK (
  vence_dias_tras_previo IS NULL
  OR (vence_dias_tras_previo > 0 AND paso_anterior_id IS NOT NULL)
);

-- Al fijar o cambiar el plazo: si el previo ya está completado corre desde hoy,
-- si no, la fecha queda vacía hasta que se complete. Solo cuando el plazo
-- cambia — `editar_tarea` reescribe la columna en cada edición y recalcular
-- ahí correría la fecha con cualquier cambio de título.
CREATE OR REPLACE FUNCTION fijar_vencimiento_tras_previo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.vence_dias_tras_previo IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.vence_dias_tras_previo IS NOT DISTINCT FROM OLD.vence_dias_tras_previo THEN
    RETURN NEW;
  END IF;

  NEW.fecha_vencimiento := CASE
    WHEN (SELECT estado FROM public.tareas WHERE id = NEW.paso_anterior_id) = 'completada'
    THEN current_date + NEW.vence_dias_tras_previo
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fijar_vencimiento_tras_previo ON tareas;
CREATE TRIGGER trg_fijar_vencimiento_tras_previo
  BEFORE INSERT OR UPDATE OF vence_dias_tras_previo ON tareas
  FOR EACH ROW
  EXECUTE FUNCTION fijar_vencimiento_tras_previo();

-- Completar un paso arranca el plazo del siguiente; reabrirlo lo vuelve a
-- dejar sin fecha, porque el siguiente vuelve a estar bloqueado.
-- SECURITY DEFINER: quien completa el paso puede no tener UPDATE sobre el
-- siguiente (otro asignado) y la cascada no puede frenarse en silencio.
CREATE OR REPLACE FUNCTION arrancar_vencimiento_siguiente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.tareas
     SET fecha_vencimiento = CASE
           WHEN NEW.estado = 'completada' THEN current_date + vence_dias_tras_previo
         END
   WHERE paso_anterior_id = NEW.id
     AND activo
     AND vence_dias_tras_previo IS NOT NULL;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_arrancar_vencimiento_siguiente ON tareas;
CREATE TRIGGER trg_arrancar_vencimiento_siguiente
  AFTER UPDATE OF estado ON tareas
  FOR EACH ROW
  WHEN (
    NEW.estado IS DISTINCT FROM OLD.estado
    AND (NEW.estado = 'completada' OR OLD.estado = 'completada')
  )
  EXECUTE FUNCTION arrancar_vencimiento_siguiente();

-- `created_at` es el orden de los pasos en la Lista (HiloCard), y `now()` es
-- la hora de la transacción: todo lo que crea una plantilla en una llamada
-- quedaba con el mismo instante y el orden entre pasos era el que saliera.
-- Viene de sql/023, que ya creaba la cadena en un loop; con plantillas de
-- proyecto (varios hilos por llamada) pasa a ser lo normal.
ALTER TABLE tareas ALTER COLUMN created_at SET DEFAULT clock_timestamp();

-- ============================================================
-- 3. crear_tarea / editar_tarea aceptan el plazo tras el previo
-- ============================================================
-- Cambia la firma: se borra la vieja para no dejar una sobrecarga.
DROP FUNCTION IF EXISTS crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text);

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
  p_vence_dias_tras_previo int
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
    origen_app, origen_punto, vence_dias_tras_previo, creado_por
  ) VALUES (
    v_id, p_titulo, p_descripcion, p_hilo_id, p_proyecto_id, p_paso_anterior_id,
    p_visibilidad, p_responsable_id, p_fecha_vencimiento, p_temperatura,
    p_recurrencia_cantidad, p_recurrencia_unidad, p_modo_completado,
    p_origen_app, p_origen_punto, p_vence_dias_tras_previo, auth.uid()
  );

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT v_id, u FROM unnest(p_asignados) AS u;

  RETURN v_id;
END;
$$;

DROP FUNCTION IF EXISTS editar_tarea(uuid, text, text, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad);

-- Con plazo tras el previo la fecha no se edita: la conserva (la escriben los
-- triggers) y `p_fecha_vencimiento` se ignora. Si el plazo cambia, el trigger
-- de arriba la recalcula.
CREATE OR REPLACE FUNCTION editar_tarea(
  p_id                     uuid,
  p_titulo                 text,
  p_descripcion            text,
  p_proyecto_id            uuid,
  p_visibilidad            visibilidad,
  p_responsable_id         uuid,
  p_asignados              uuid[],
  p_fecha_vencimiento      date,
  p_temperatura            int,
  p_recurrencia_cantidad   int,
  p_recurrencia_unidad     recurrencia_unidad,
  p_vence_dias_tras_previo int
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
    responsable_id         = p_responsable_id,
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

  PERFORM sincronizar_asignados(p_id, p_asignados);
END;
$$;

-- ============================================================
-- 4. Esquema de plantillas
-- ============================================================
DO $$ BEGIN
  CREATE TYPE alcance_plantilla AS ENUM ('sistema', 'privada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE tipo_plantilla AS ENUM ('tarea', 'hilo', 'proyecto');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- `alcance` nace con default `sistema` para rellenar las filas existentes y
-- después pasa a `privada`: lo que se crea sin decir nada es de uno.
-- `visibilidad` y `miembros` son del proyecto que crea una plantilla de tipo
-- proyecto. `miembros` es array y no tabla: es configuración que se copia al
-- usarla, no una relación viva — al usar se descartan los usuarios inactivos.
ALTER TABLE tareas_plantillas
  ADD COLUMN IF NOT EXISTS alcance     alcance_plantilla NOT NULL DEFAULT 'sistema',
  ADD COLUMN IF NOT EXISTS tipo        tipo_plantilla    NOT NULL DEFAULT 'hilo',
  ADD COLUMN IF NOT EXISTS visibilidad visibilidad       NOT NULL DEFAULT 'privado',
  ADD COLUMN IF NOT EXISTS miembros    uuid[]            NOT NULL DEFAULT '{}';

ALTER TABLE tareas_plantillas ALTER COLUMN alcance SET DEFAULT 'privada';

ALTER TABLE tareas_plantillas DROP CONSTRAINT IF EXISTS tareas_plantillas_miembros_de_proyecto;
ALTER TABLE tareas_plantillas ADD CONSTRAINT tareas_plantillas_miembros_de_proyecto
  CHECK (tipo = 'proyecto' OR cardinality(miembros) = 0);

CREATE TABLE IF NOT EXISTS tareas_plantillas_hilos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_id uuid NOT NULL REFERENCES tareas_plantillas(id),
  titulo       text NOT NULL,
  orden        int NOT NULL DEFAULT 0,
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_hilos_plantilla_id
  ON tareas_plantillas_hilos (plantilla_id);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_plantillas_hilos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_plantillas_hilos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_plantillas_hilos ENABLE ROW LEVEL SECURITY;

-- `responsable_id` NULL = quien usa la plantilla. `incluir_ejecutor` = quien la
-- usa queda entre los asignados, además de los fijos.
ALTER TABLE tareas_plantillas_items
  ADD COLUMN IF NOT EXISTS descripcion       text,
  ADD COLUMN IF NOT EXISTS hilo_id           uuid REFERENCES tareas_plantillas_hilos(id),
  ADD COLUMN IF NOT EXISTS asignados         uuid[]  NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS incluir_ejecutor  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS responsable_id    uuid REFERENCES usuarios(id),
  ADD COLUMN IF NOT EXISTS vence_dias        int,
  ADD COLUMN IF NOT EXISTS vence_tras_previo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS temperatura       int     NOT NULL DEFAULT 50;

CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_items_hilo_id
  ON tareas_plantillas_items (hilo_id);
CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_items_responsable_id
  ON tareas_plantillas_items (responsable_id);

ALTER TABLE tareas_plantillas_items
  DROP CONSTRAINT IF EXISTS plantillas_items_con_asignado,
  DROP CONSTRAINT IF EXISTS plantillas_items_responsable,
  DROP CONSTRAINT IF EXISTS plantillas_items_vencimiento,
  DROP CONSTRAINT IF EXISTS plantillas_items_temperatura;

ALTER TABLE tareas_plantillas_items
  ADD CONSTRAINT plantillas_items_con_asignado
    CHECK (incluir_ejecutor OR cardinality(asignados) > 0),
  ADD CONSTRAINT plantillas_items_responsable
    CHECK (CASE WHEN responsable_id IS NULL THEN incluir_ejecutor
                ELSE responsable_id = ANY(asignados) END),
  ADD CONSTRAINT plantillas_items_vencimiento
    CHECK ((vence_dias IS NULL OR vence_dias > 0) AND (NOT vence_tras_previo OR vence_dias IS NOT NULL)),
  ADD CONSTRAINT plantillas_items_temperatura
    CHECK (temperatura BETWEEN 1 AND 100);

-- ============================================================
-- 5. Permisos
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'tareas_plantillas_sistema', 'tareas', 'funcion', 'Plantillas de sistema', id, 1
FROM submodulos WHERE codigo = 'tareas_plantillas'
ON CONFLICT DO NOTHING;

-- Hasta acá cualquiera con la vista administraba todas las plantillas (eran
-- recurso de equipo): se le conserva la capacidad, mismo criterio que los
-- backfills de sql/013 y sql/014. Alta manual desde Usuarios para el resto.
INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT us.usuario_id, nueva.id
FROM usuario_submodulos us
JOIN submodulos v ON v.id = us.submodulo_id AND v.codigo = 'tareas_plantillas'
CROSS JOIN submodulos nueva
WHERE us.activo AND nueva.codigo = 'tareas_plantillas_sistema' AND nueva.activo
ON CONFLICT DO NOTHING;

-- Quién administra una plantilla: la de sistema, quien tiene la función; la
-- privada, su dueño. INVOKER a propósito — la lectura de tareas_plantillas
-- pasa por su propia policy de SELECT, que suma la vista y el alcance. No
-- recursa: las policies de tareas_plantillas no miran hilos ni items.
CREATE OR REPLACE FUNCTION puede_gestionar_plantilla(p_plantilla_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tareas_plantillas p
    WHERE p.id = p_plantilla_id
      AND CASE p.alcance
            WHEN 'sistema' THEN tiene_permiso('tareas_plantillas_sistema')
            ELSE p.creado_por = auth.uid()
          END
  );
$$;

DROP POLICY IF EXISTS tareas_plantillas_select ON tareas_plantillas;
CREATE POLICY tareas_plantillas_select ON tareas_plantillas FOR SELECT
  USING (
    tiene_permiso('tareas_plantillas')
    AND (alcance = 'sistema' OR creado_por = (select auth.uid()))
  );

DROP POLICY IF EXISTS tareas_plantillas_insert ON tareas_plantillas;
CREATE POLICY tareas_plantillas_insert ON tareas_plantillas FOR INSERT
  WITH CHECK (
    creado_por = (select auth.uid())
    AND tiene_permiso('tareas_plantillas')
    AND (alcance = 'privada' OR tiene_permiso('tareas_plantillas_sistema'))
  );

-- `alcance` y `creado_por` fuera del GRANT UPDATE (abajo): una privada no se
-- vuelve de sistema ni cambia de dueño, así que la función puede leer la fila
-- vieja sin mirar la nueva.
DROP POLICY IF EXISTS tareas_plantillas_update ON tareas_plantillas;
CREATE POLICY tareas_plantillas_update ON tareas_plantillas FOR UPDATE
  USING (puede_gestionar_plantilla(id))
  WITH CHECK (puede_gestionar_plantilla(id));

DROP POLICY IF EXISTS tareas_plantillas_hilos_select ON tareas_plantillas_hilos;
CREATE POLICY tareas_plantillas_hilos_select ON tareas_plantillas_hilos FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM tareas_plantillas p WHERE p.id = tareas_plantillas_hilos.plantilla_id
  ));

DROP POLICY IF EXISTS tareas_plantillas_hilos_insert ON tareas_plantillas_hilos;
CREATE POLICY tareas_plantillas_hilos_insert ON tareas_plantillas_hilos FOR INSERT
  WITH CHECK (puede_gestionar_plantilla(plantilla_id));

DROP POLICY IF EXISTS tareas_plantillas_hilos_update ON tareas_plantillas_hilos;
CREATE POLICY tareas_plantillas_hilos_update ON tareas_plantillas_hilos FOR UPDATE
  USING (puede_gestionar_plantilla(plantilla_id))
  WITH CHECK (puede_gestionar_plantilla(plantilla_id));

-- Poner a otro como asignado o responsable de un paso es asignar: la misma
-- regla de sql/014, exigida al guardar la plantilla.
DROP POLICY IF EXISTS tareas_plantillas_items_select ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_select ON tareas_plantillas_items FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM tareas_plantillas p WHERE p.id = tareas_plantillas_items.plantilla_id
  ));

DROP POLICY IF EXISTS tareas_plantillas_items_insert ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_insert ON tareas_plantillas_items FOR INSERT
  WITH CHECK (
    puede_gestionar_plantilla(plantilla_id)
    AND (
      tiene_permiso('tareas_asignar')
      OR (
        asignados <@ ARRAY[(select auth.uid())]
        AND (responsable_id IS NULL OR responsable_id = (select auth.uid()))
      )
    )
  );

DROP POLICY IF EXISTS tareas_plantillas_items_update ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_update ON tareas_plantillas_items FOR UPDATE
  USING (puede_gestionar_plantilla(plantilla_id))
  WITH CHECK (puede_gestionar_plantilla(plantilla_id));

GRANT SELECT, INSERT, UPDATE ON public.tareas_plantillas_hilos TO authenticated;

REVOKE UPDATE ON public.tareas_plantillas FROM authenticated;
GRANT UPDATE (nombre, descripcion, tipo, visibilidad, miembros, activo)
  ON public.tareas_plantillas TO authenticated;

-- ============================================================
-- 6. guardar_plantilla — la plantilla y sus pasos, juntos o nada
-- ============================================================
-- Guardar reemplaza: desactiva los hilos y pasos activos y carga los nuevos.
-- Nada referencia a un paso de plantilla (usar copia, no apunta), así que
-- mantener ids estables no compra nada y el diff por paso de actions.ts se va.
--
-- `p_hilos` = [{ titulo, pasos: [...] }] (solo tipo proyecto) y `p_pasos` =
-- los pasos sin hilo. Cada paso: titulo, descripcion, asignados, incluir_ejecutor,
-- responsable_id, vence_dias, vence_tras_previo, temperatura.
-- `p_alcance` solo se lee al crear.
CREATE OR REPLACE FUNCTION guardar_plantilla(
  p_id          uuid,
  p_nombre      text,
  p_descripcion text,
  p_alcance     alcance_plantilla,
  p_tipo        tipo_plantilla,
  p_visibilidad visibilidad,
  p_miembros    uuid[],
  p_hilos       jsonb,
  p_pasos       jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id       uuid := COALESCE(p_id, gen_random_uuid());
  v_hilo_ids uuid[];
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

  IF p_id IS NULL THEN
    INSERT INTO tareas_plantillas (id, nombre, descripcion, alcance, tipo, visibilidad, miembros, creado_por)
    VALUES (v_id, p_nombre, p_descripcion, p_alcance, p_tipo, p_visibilidad, p_miembros, auth.uid());
  ELSE
    UPDATE tareas_plantillas SET
      nombre      = p_nombre,
      descripcion = p_descripcion,
      tipo        = p_tipo,
      visibilidad = p_visibilidad,
      miembros    = p_miembros
    WHERE id = p_id AND activo;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La plantilla no existe o no tenés permiso para modificarla' USING ERRCODE = 'TA008';
    END IF;

    UPDATE tareas_plantillas_items SET activo = false WHERE plantilla_id = v_id AND activo;
    UPDATE tareas_plantillas_hilos SET activo = false WHERE plantilla_id = v_id AND activo;
  END IF;

  v_hilo_ids := ARRAY(SELECT gen_random_uuid() FROM jsonb_array_elements(p_hilos));

  INSERT INTO tareas_plantillas_hilos (id, plantilla_id, titulo, orden)
  SELECT v_hilo_ids[hn], v_id, hilo->>'titulo', hn
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
-- 7. usar_plantilla — lo que la plantilla describe, entero o nada
-- ============================================================
-- Reemplaza a `agregar_tareas_desde_plantilla`. INVOKER: se usa a mano, y la
-- RLS de quien la usa decide igual que si armara todo desde los formularios
-- (crear proyecto pide `tareas_proyectos_crear`, asignar a otro pide
-- `tareas_asignar`, recibir pide ser miembro).
--
-- Destino según el tipo:
--   tarea    → una tarea en `p_hilo_id`, o suelta (con `p_proyecto_id` o personal)
--   hilo     → pasos encadenados en `p_hilo_id`, o en un hilo nuevo (`p_titulo`)
--   proyecto → proyecto nuevo (`p_titulo`) con sus miembros + quien la usa, un
--              hilo por hilo de la plantilla y las tareas sueltas
--
-- Asignados de cada paso: los fijos que puedan recibirlo (activos, miembros
-- del proyecto, y otros solo si quien la usa tiene `tareas_asignar`), más quien
-- la usa si el paso lo incluye. Si no queda nadie, el paso va a quien la usa
-- con una nota que dice por qué — decisión del usuario: la tarea no se pierde.
--
-- Devuelve cuántos pasos quedaron para quien la usa por ese motivo.
CREATE OR REPLACE FUNCTION usar_plantilla(
  p_plantilla_id uuid,
  p_titulo       text,
  p_proyecto_id  uuid,
  p_hilo_id      uuid
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
BEGIN
  SELECT * INTO v_p FROM tareas_plantillas WHERE id = p_plantilla_id AND activo;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La plantilla no existe o no es visible' USING ERRCODE = 'TA008';
  END IF;

  v_titulo := COALESCE(NULLIF(trim(p_titulo), ''), v_p.nombre);

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
    SELECT i.*, h.titulo AS hilo_titulo
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
        VALUES (v_hilo, v_item.hilo_titulo, v_proyecto, 'publico', v_uid, v_uid);
      END IF;
    END IF;
    v_primero := false;

    v_encadena := v_hilo IS NOT NULL AND v_p.tipo <> 'tarea';

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
      v_item.titulo,
      v_item.descripcion,
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
      NULL, NULL, 'manual', NULL, NULL,
      CASE
        WHEN v_item.vence_tras_previo AND v_encadena AND v_anterior IS NOT NULL
        THEN v_item.vence_dias
      END
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
    RAISE EXCEPTION 'La plantilla no tiene pasos' USING ERRCODE = 'TA009';
  END IF;

  RETURN v_derivadas;
END;
$$;

DROP FUNCTION IF EXISTS agregar_tareas_desde_plantilla(uuid, uuid, uuid, uuid[]);

-- ============================================================
-- 8. GRANTs — mismo criterio que sql/006 / sql/023
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.es_siembra_tarea(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.es_siembra_tarea(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.puede_gestionar_plantilla(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.puede_gestionar_plantilla(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fijar_vencimiento_tras_previo() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.arrancar_vencimiento_siguiente() FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crear_tarea(text, text, uuid, uuid, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, modo_completado, text, text, int) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.editar_tarea(uuid, text, text, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.editar_tarea(uuid, text, text, uuid, visibilidad, uuid, uuid[], date, int, int, recurrencia_unidad, int) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, uuid) TO authenticated;
