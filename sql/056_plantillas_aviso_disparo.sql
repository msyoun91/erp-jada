-- ============================================================
-- 056 — Quien dispara una plantilla se entera de que corrió
--
-- Hasta sql/055 solo avisaba el disparo que fallaba: el que andaba no le
-- decía nada a quien cambió el estado, porque `notificar()` excluye al actor.
-- Un aviso por plantilla que corrió, no por tarea: es informativo y lleva a la
-- vista general de Tareas.
-- Ver decisiones/tareas/plantillas.md → "Aviso de que la plantilla corrió".
--
--   1. Tipo de notificación. Va en su propia transacción: un valor de enum
--      recién agregado no se puede usar antes del COMMIT.
--   2. `notificar_disparo` reemplaza a `notificar_plantilla_fallida`.
--   3. `disparar_plantillas()` avisa en los dos casos.
--   4. La bandeja lleva el aviso nuevo a Tareas.
-- ============================================================

-- ============================================================
-- 1. Tipo de notificación (aplicar solo, antes del resto)
-- ============================================================
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_disparada';

-- ============================================================
-- 2. Un solo helper para los dos avisos del disparo
-- ============================================================
-- Apunta a la plantilla y no a lo creado: quien dispara siempre la ve (la
-- tiene activada), y puede no ver la tarea — una plantilla de tarea asignada
-- solo a Cobranzas le crea algo que `tareas_select` no le muestra (sql/013),
-- y un aviso apuntado ahí desaparecería de su bandeja.
--
-- Mismo resguardo que la anterior: DEFINER con EXECUTE para `authenticated`
-- porque la llama el disparo (INVOKER), y fuera de un trigger no hace nada.
-- El tipo sale del booleano para que por acá no se escriba otro aviso.
CREATE OR REPLACE FUNCTION notificar_disparo(p_plantilla_id uuid, p_corrio boolean)
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
    CASE WHEN p_corrio THEN 'plantilla_disparada' ELSE 'plantilla_fallida' END::tipo_notificacion,
    'plantilla',
    p_plantilla_id,
    NULL
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notificar_disparo(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notificar_disparo(uuid, boolean) TO authenticated;

-- ============================================================
-- 3. El disparo avisa si corrió o si no pudo (resto igual a sql/055)
-- ============================================================
-- El aviso de que corrió va adentro del bloque: si fallara, se revierte con
-- lo creado y sale el de fallo.
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
    EXCEPTION WHEN OTHERS THEN
      PERFORM notificar_disparo(v_pl, false);
    END;
  END LOOP;

  PERFORM set_config('tareas.disparo', '', true);
  RETURN NULL;
END;
$$;

DROP FUNCTION IF EXISTS notificar_plantilla_fallida(uuid);

-- ============================================================
-- 4. La bandeja lleva el aviso de que corrió a Tareas (resto igual a sql/055)
-- ============================================================
-- `destino = 'tareas'` no lleva id: es la vista general, no lo creado. Sale
-- aunque después archiven la plantilla, porque las tareas siguen ahí.
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
           CASE WHEN n.tipo = 'plantilla_disparada' THEN 'tareas'
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
