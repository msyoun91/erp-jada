-- ============================================================
-- 055 — Plantillas disparadas por el estado de un registro (fase 2)
--
-- La fase 1 (sql/053) dejó las plantillas completas y usadas a mano. Esta las
-- conecta con los módulos: un registro entra a un estado y corren solas las
-- plantillas que quien lo cambió tiene activadas. Primer y único ente: la obra.
-- Ver decisiones/tareas/plantillas.md → "Plantillas disparadas por estado".
--
--   1. Tres tipos de notificación. Van en su propia transacción: un valor de
--      enum recién agregado no se puede usar antes del COMMIT.
--   2. Catálogo `entes`: cada módulo registra ahí lo que puede disparar.
--   3. La plantilla gana disparador (ente + estado) y se ve y se arma solo con
--      el submódulo del ente.
--   4. `tareas_plantillas_activaciones`: el sí de cada usuario.
--   5. `tareas_vinculos`: qué tareas salieron de cada (plantilla, registro).
--   6. `guardar_plantilla` / `usar_plantilla` aceptan disparador y datos.
--   7. `disparar_plantillas()` y el trigger de obras.
--   8. Campanita: guardar o archivar una plantilla activada, y el disparo que
--      no pudo correr.
-- ============================================================

-- ============================================================
-- 1. Tipos de notificación (aplicar solo, antes del resto)
-- ============================================================
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_modificada';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_archivada';
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_fallida';

-- ============================================================
-- 2. Catálogo de entes
-- ============================================================
-- Infra cross-módulo como `submodulos`, sin prefijo. Cada módulo con un
-- registro que tiene estado agrega su fila en su migración, más un trigger de
-- una línea sobre esa columna (§7). Desde la app no se configura nada.
--
--   modulo / ruta  `origen_app` / `origen_punto` de las tareas que genera: el
--                  panel de la tarea ya muestra "Generado por obras — ir".
--   submodulo      el que pide. Sin él, la plantilla no se ve ni se arma.
--                  Texto y no FK: `submodulos.codigo` es único parcial.
--   estados        el enum de la columna de estado; `guardar_plantilla` valida
--                  contra él.
--   datos          columnas que la plantilla puede citar como `{columna}`.
--                  Nunca contacto: el texto se copia en la tarea y lo lee quien
--                  la recibe, vea o no el registro.
--
-- `codigo` UNIQUE simple y no parcial: es destino de FK, y un ente no se
-- reutiliza para otra cosa.
CREATE TABLE IF NOT EXISTS entes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo     text NOT NULL UNIQUE,
  modulo     text NOT NULL,
  submodulo  text NOT NULL,
  estados    regtype NOT NULL,
  datos      text[] NOT NULL DEFAULT '{}',
  ruta       text NOT NULL CHECK (ruta ~ '^/[^/]'),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS set_updated_at ON entes;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON entes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE entes ENABLE ROW LEVEL SECURITY;

-- Lo que no podés usar no existe para vos: las policies de plantillas se
-- apoyan en esta.
DROP POLICY IF EXISTS entes_select ON entes;
CREATE POLICY entes_select ON entes FOR SELECT
  USING (activo AND tiene_permiso(submodulo));

GRANT SELECT ON public.entes TO authenticated;

-- Obras registra la obra. El trigger va en §7, después de la función.
INSERT INTO entes (codigo, modulo, submodulo, estados, datos, ruta)
VALUES ('obra', 'obras', 'obras_ver', 'estado_obra', '{nombre}', '/obras/{id}')
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================
-- 3. La plantilla gana disparador
-- ============================================================
ALTER TABLE tareas_plantillas
  ADD COLUMN IF NOT EXISTS disparo_ente   text REFERENCES entes(codigo),
  ADD COLUMN IF NOT EXISTS disparo_estado text;

ALTER TABLE tareas_plantillas DROP CONSTRAINT IF EXISTS tareas_plantillas_disparo_completo;
ALTER TABLE tareas_plantillas ADD CONSTRAINT tareas_plantillas_disparo_completo
  CHECK ((disparo_ente IS NULL) = (disparo_estado IS NULL));

CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_disparo
  ON tareas_plantillas (disparo_ente, disparo_estado);

-- Con disparador hace falta además el submódulo del ente: EXISTS contra
-- `entes`, cuya RLS lo decide. Quien no ve obras no ve "Cobrar obra {nombre}",
-- y activarla no le serviría — nunca cambia el estado de una obra.
DROP POLICY IF EXISTS tareas_plantillas_select ON tareas_plantillas;
CREATE POLICY tareas_plantillas_select ON tareas_plantillas FOR SELECT
  USING (
    tiene_permiso('tareas_plantillas')
    AND (alcance = 'sistema' OR creado_por = (select auth.uid()))
    AND (disparo_ente IS NULL
         OR EXISTS (SELECT 1 FROM entes e WHERE e.codigo = tareas_plantillas.disparo_ente))
  );

DROP POLICY IF EXISTS tareas_plantillas_insert ON tareas_plantillas;
CREATE POLICY tareas_plantillas_insert ON tareas_plantillas FOR INSERT
  WITH CHECK (
    creado_por = (select auth.uid())
    AND tiene_permiso('tareas_plantillas')
    AND (alcance = 'privada' OR tiene_permiso('tareas_plantillas_sistema'))
    AND (disparo_ente IS NULL
         OR EXISTS (SELECT 1 FROM entes e WHERE e.codigo = tareas_plantillas.disparo_ente))
  );

-- `puede_gestionar_plantilla` lee la fila vieja; el disparador sí cambia, así
-- que el ente nuevo se mira acá, sobre la fila nueva.
DROP POLICY IF EXISTS tareas_plantillas_update ON tareas_plantillas;
CREATE POLICY tareas_plantillas_update ON tareas_plantillas FOR UPDATE
  USING (puede_gestionar_plantilla(id))
  WITH CHECK (
    puede_gestionar_plantilla(id)
    AND (disparo_ente IS NULL
         OR EXISTS (SELECT 1 FROM entes e WHERE e.codigo = tareas_plantillas.disparo_ente))
  );

GRANT UPDATE (disparo_ente, disparo_estado) ON public.tareas_plantillas TO authenticated;

-- ============================================================
-- 4. Activaciones
-- ============================================================
-- El sí de cada usuario a una plantilla con disparador. Corre solo para quien
-- cambia el estado y la tiene activada: las tareas nacen a su nombre y con sus
-- permisos, así que tiene que haber un sí suyo. `activo` es el interruptor.
-- UNIQUE simple por upsert (excepción de GUIDE_DB, como `usuario_submodulos`).
--
-- La de sistema arranca apagada (sin fila). La privada arranca prendida: la
-- fila la crea `guardar_plantilla` cuando la plantilla tiene disparador.
CREATE TABLE IF NOT EXISTS tareas_plantillas_activaciones (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_id uuid NOT NULL REFERENCES tareas_plantillas(id),
  usuario_id   uuid NOT NULL REFERENCES usuarios(id),
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tareas_plantillas_activaciones_unica UNIQUE (plantilla_id, usuario_id)
);

CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_activaciones_usuario_id
  ON tareas_plantillas_activaciones (usuario_id);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_plantillas_activaciones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_plantillas_activaciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_plantillas_activaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tareas_plantillas_activaciones_select ON tareas_plantillas_activaciones;
CREATE POLICY tareas_plantillas_activaciones_select ON tareas_plantillas_activaciones FOR SELECT
  USING (usuario_id = (select auth.uid()));

-- Activar pide ver la plantilla (su RLS: vista, alcance y submódulo del ente)
-- y que tenga disparador.
DROP POLICY IF EXISTS tareas_plantillas_activaciones_insert ON tareas_plantillas_activaciones;
CREATE POLICY tareas_plantillas_activaciones_insert ON tareas_plantillas_activaciones FOR INSERT
  WITH CHECK (
    usuario_id = (select auth.uid())
    AND EXISTS (
      SELECT 1 FROM tareas_plantillas p
      WHERE p.id = tareas_plantillas_activaciones.plantilla_id AND p.disparo_ente IS NOT NULL
    )
  );

DROP POLICY IF EXISTS tareas_plantillas_activaciones_update ON tareas_plantillas_activaciones;
CREATE POLICY tareas_plantillas_activaciones_update ON tareas_plantillas_activaciones FOR UPDATE
  USING (usuario_id = (select auth.uid()))
  WITH CHECK (
    usuario_id = (select auth.uid())
    AND EXISTS (
      SELECT 1 FROM tareas_plantillas p
      WHERE p.id = tareas_plantillas_activaciones.plantilla_id AND p.disparo_ente IS NOT NULL
    )
  );

GRANT SELECT, INSERT, UPDATE ON public.tareas_plantillas_activaciones TO authenticated;

-- ============================================================
-- 5. Vínculos tarea ↔ registro
-- ============================================================
-- Qué tareas salieron de cada (plantilla, registro): es lo que hace "una vez
-- para siempre, salvo archivadas" (`plantilla_disparada`, abajo). Misma forma
-- que `usuario_notificaciones`: ente + id sin FK. `plantilla_id` NOT NULL
-- porque hoy el único que vincula es un disparo.
CREATE TABLE IF NOT EXISTS tareas_vinculos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tarea_id     uuid NOT NULL REFERENCES tareas(id),
  ente         text NOT NULL REFERENCES entes(codigo),
  registro_id  uuid NOT NULL,
  plantilla_id uuid NOT NULL REFERENCES tareas_plantillas(id),
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_vinculos_registro ON tareas_vinculos (ente, registro_id);
CREATE INDEX IF NOT EXISTS idx_tareas_vinculos_tarea_id ON tareas_vinculos (tarea_id);
CREATE INDEX IF NOT EXISTS idx_tareas_vinculos_plantilla_id ON tareas_vinculos (plantilla_id);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_vinculos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_vinculos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_vinculos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tareas_vinculos_select ON tareas_vinculos;
CREATE POLICY tareas_vinculos_select ON tareas_vinculos FOR SELECT
  USING (EXISTS (SELECT 1 FROM tareas t WHERE t.id = tareas_vinculos.tarea_id));

-- Solo lo escribe un disparo, que corre adentro de un trigger. Si el cliente
-- pudiera insertarlo, un vínculo inventado —(plantilla, obra) con una tarea
-- cualquiera— bloquearía el disparo real para todos.
DROP POLICY IF EXISTS tareas_vinculos_insert ON tareas_vinculos;
CREATE POLICY tareas_vinculos_insert ON tareas_vinculos FOR INSERT
  WITH CHECK (pg_trigger_depth() > 0);

GRANT SELECT, INSERT ON public.tareas_vinculos TO authenticated;

-- ============================================================
-- 6. Helpers, guardar_plantilla y usar_plantilla
-- ============================================================

-- `{dato}` → valor, en los textos que la plantilla copia a lo que crea.
CREATE OR REPLACE FUNCTION rellenar_datos(p_texto text, p_datos jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_clave text;
  v_valor text;
BEGIN
  FOR v_clave, v_valor IN SELECT key, value FROM jsonb_each_text(COALESCE(p_datos, '{}'::jsonb)) LOOP
    p_texto := replace(p_texto, '{' || v_clave || '}', COALESCE(v_valor, ''));
  END LOOP;
  RETURN p_texto;
END;
$$;

-- Las dos que siguen son DEFINER y quedan con EXECUTE para `authenticated`,
-- porque el disparo es INVOKER y las llama. Fuera de un trigger no hacen nada:
-- por RPC no se pregunta por plantillas ajenas ni se fabrican avisos.

-- DEFINER: "ya se disparó" vale para todos, y quien cambia el estado puede no
-- ver lo que generó otro (una tarea de Cobranzas, un proyecto privado).
-- Completadas y canceladas siguen activas: no la reabren.
CREATE OR REPLACE FUNCTION plantilla_disparada(p_plantilla_id uuid, p_ente text, p_registro_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pg_trigger_depth() > 0
     AND EXISTS (
       SELECT 1
       FROM public.tareas_vinculos v
       JOIN public.tareas t ON t.id = v.tarea_id AND t.activo
       WHERE v.plantilla_id = p_plantilla_id
         AND v.ente = p_ente
         AND v.registro_id = p_registro_id
         AND v.activo
     );
$$;

-- `notificar` no se otorga a nadie: esta solo le escribe a quien disparó.
CREATE OR REPLACE FUNCTION notificar_plantilla_fallida(p_plantilla_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() = 0 THEN
    RETURN;
  END IF;

  PERFORM notificar(auth.uid(), 'plantilla_fallida', 'plantilla', p_plantilla_id, NULL);
END;
$$;

-- Cambia la firma: suma el disparador al final, con DEFAULT para que las
-- llamadas de sql/053 sigan valiendo.
DROP FUNCTION IF EXISTS guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb);

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
  p_disparo_ente   text DEFAULT NULL,
  p_disparo_estado text DEFAULT NULL
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
      disparo_ente, disparo_estado, creado_por
    )
    VALUES (
      v_id, p_nombre, p_descripcion, p_alcance, p_tipo, p_visibilidad, p_miembros,
      p_disparo_ente, p_disparo_estado, auth.uid()
    );
  ELSE
    UPDATE tareas_plantillas SET
      nombre         = p_nombre,
      descripcion    = p_descripcion,
      tipo           = p_tipo,
      visibilidad    = p_visibilidad,
      miembros       = p_miembros,
      disparo_ente   = p_disparo_ente,
      disparo_estado = p_disparo_estado
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

-- Cambia la firma: suma el registro que la dispara, con DEFAULT para que el
-- uso a mano no cambie. `p_ente` NULL = a mano.
--
-- Una plantilla con disparador no se usa a mano, ni una sin disparador se
-- dispara (TA013): sus textos citan `{nombre}` y a mano quedarían literales.
-- Con registro: los textos se rellenan con `p_datos`, las tareas llevan el
-- origen del ente y cada una queda vinculada a (plantilla, registro).
DROP FUNCTION IF EXISTS usar_plantilla(uuid, text, uuid, uuid);

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

  v_titulo := rellenar_datos(COALESCE(NULLIF(trim(p_titulo), ''), v_p.nombre), p_datos);

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
        VALUES (v_hilo, rellenar_datos(v_item.hilo_titulo, p_datos), v_proyecto, 'publico', v_uid, v_uid);
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
-- 7. El disparo
-- ============================================================
-- Trigger genérico: `TG_ARGV[0]` es el ente y `TG_ARGV[1]` su columna de
-- estado. Corre cuando un registro entra a un estado —al crearlo ya en ese
-- estado o al cambiarlo de verdad—, sin mirar de dónde viene.
--
-- INVOKER, como usarla a mano: las tareas nacen con la RLS de quien cambió el
-- estado, que es quien la activó. De ahí la guarda de `current_user`: si el
-- cambio lo hiciera una función DEFINER (o el SQL editor), `usar_plantilla`
-- correría como `postgres`, con BYPASSRLS, y crearía lo que su usuario no
-- puede. Ahí no corre.
--
-- Cada plantilla en su propio bloque: si una falla (perdió un permiso, quedó
-- mal armada) se revierte solo lo suyo, el cambio de estado pasa igual y la
-- campanita se lo dice a quien la activó. Una plantilla mal configurada no
-- traba una venta.
--
-- `tareas.disparo` le avisa a `notificar_tarea_asignada` que estas
-- asignaciones sí las hizo alguien (§8).
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
      END IF;
    EXCEPTION WHEN OTHERS THEN
      PERFORM notificar_plantilla_fallida(v_pl);
    END;
  END LOOP;

  PERFORM set_config('tareas.disparo', '', true);
  RETURN NULL;
END;
$$;

-- Obras avisa cuando una obra entra a un estado. Nada más: sin funciones ni
-- botones nuevos de su lado.
DROP TRIGGER IF EXISTS disparar_plantillas ON obras;
CREATE TRIGGER disparar_plantillas
  AFTER INSERT OR UPDATE OF estado ON obras
  FOR EACH ROW EXECUTE FUNCTION disparar_plantillas('obra', 'estado');

-- ============================================================
-- 8. Notificaciones
-- ============================================================

-- 8.1 — Las asignaciones de un disparo sí avisan.
-- `pg_trigger_depth() > 1` filtraba la copia de asignados de
-- `generar_recurrencia` (sql/038). Un disparo también crea sus tareas adentro
-- de un trigger, pero ahí alguien sí asignó: "Cobrar obra X" le tiene que
-- llegar a Cobranzas.
CREATE OR REPLACE FUNCTION notificar_tarea_asignada()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT NEW.activo THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.activo THEN
    RETURN NEW;
  END IF;

  IF pg_trigger_depth() > 1 AND current_setting('tareas.disparo', true) IS DISTINCT FROM 'on' THEN
    RETURN NEW;
  END IF;

  PERFORM notificar(NEW.usuario_id, 'tarea_asignada', 'tarea', NEW.tarea_id, auth.uid());
  RETURN NEW;
END;
$$;

-- 8.2 — La plantilla como entidad apuntada.
ALTER TABLE usuario_notificaciones DROP CONSTRAINT IF EXISTS usuario_notificaciones_entidad_check;
ALTER TABLE usuario_notificaciones ADD CONSTRAINT usuario_notificaciones_entidad_check
  CHECK (entidad IN ('obra', 'empresa', 'persona', 'obra_empresa', 'obra_persona', 'tarea', 'plantilla'));

-- 8.3 — Guardar o archivar una plantilla que tenés activada.
-- Guardar siempre hace UPDATE, así que guardar sin cambios también avisa:
-- `guardar_plantilla` reemplaza los pasos y no sabe si algo cambió. Solo la de
-- sistema: una privada tiene un único activador, que es quien la edita.
-- `notificar` ya excluye al actor.
CREATE OR REPLACE FUNCTION notificar_cambio_plantilla()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.alcance <> 'sistema' OR NOT OLD.activo THEN
    RETURN NULL;
  END IF;

  PERFORM notificar(
    a.usuario_id,
    CASE WHEN NEW.activo THEN 'plantilla_modificada' ELSE 'plantilla_archivada' END::tipo_notificacion,
    'plantilla',
    NEW.id,
    auth.uid()
  )
  FROM tareas_plantillas_activaciones a
  WHERE a.plantilla_id = NEW.id AND a.activo;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_cambio_plantilla ON tareas_plantillas;
CREATE TRIGGER trg_notificar_cambio_plantilla
  AFTER UPDATE ON tareas_plantillas
  FOR EACH ROW EXECUTE FUNCTION notificar_cambio_plantilla();

-- 8.4 — La bandeja suma la rama de plantilla (resto igual a sql/040).
-- INNER JOIN bajo la RLS del lector, como las demás: si ya no ve la plantilla,
-- el aviso no aparece. `tareas_plantillas_select` no filtra `activo`, así que
-- el aviso de archivada sobrevive; como la vista Plantillas no lista
-- archivadas, ese aviso sale sin destino.
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
    SELECT n.id, pl.nombre, NULL::text, CASE WHEN pl.activo THEN 'plantilla' END, pl.id
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
-- 9. GRANTs — mismo criterio que sql/006 / sql/053
-- ============================================================
-- Las que llama el disparo (INVOKER) necesitan EXECUTE para `authenticated`.
REVOKE EXECUTE ON FUNCTION public.rellenar_datos(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rellenar_datos(text, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.plantilla_disparada(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.plantilla_disparada(uuid, text, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.notificar_plantilla_fallida(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notificar_plantilla_fallida(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.disparar_plantillas() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notificar_cambio_plantilla() FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, alcance_plantilla, tipo_plantilla, visibilidad, uuid[], jsonb, jsonb, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, uuid, text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, uuid, text, uuid, jsonb) TO authenticated;
