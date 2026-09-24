-- sql/117 — tareas: recurrencia y "paso a reasignar".
--
-- Cerrar un hilo con recurrencia genera el siguiente ciclo: un trigger, así
-- sus pasos se crean a profundidad 2 y rigen las reglas de sistema de
-- `tareas_al_crear` (un asignado que ya no vale deja el paso en el
-- responsable, con aviso; nunca falla). No generar es cerrar sacando la
-- recurrencia en el mismo UPDATE: "Terminar la recurrencia", y también "no"
-- a "¿generar otro?" cuando el ciclo ya tiene siguiente.
-- `tareas_cancelar_y_cerrar` la saca salvo `p_generar`.
-- Decisión: `decisiones/tareas/recurrencia.md`. Verificado con
-- `sql/tests/tareas_recurrencia.sql`.

-- ============================================================
-- 1. Al crear un paso — "paso a reasignar"
-- ============================================================
-- Desde un trigger (recurrencia, plantillas por evento), el asignado que no
-- puede recibir, o el pedido que el responsable ya no puede hacer sin
-- `tareas_pedir`, deja el paso en el responsable con aviso. El aviso va sin
-- actor: lo decidió la base, también si el que cerró es el responsable.
CREATE OR REPLACE FUNCTION public.tareas_al_crear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_directo boolean := pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL;
  v_h public.tareas_hilos;
BEGIN
  SELECT * INTO v_h FROM public.tareas_hilos WHERE id = NEW.hilo_id;

  IF NOT v_h.activo THEN
    RAISE EXCEPTION 'El hilo está desactivado' USING ERRCODE = 'TA013';
  END IF;

  IF NEW.paso_anterior_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.tareas WHERE id = NEW.paso_anterior_id AND activo
  ) THEN
    RAISE EXCEPTION 'El paso anterior no existe o está desactivado' USING ERRCODE = 'TA005';
  END IF;

  NEW.resultado := NULL;
  NEW.espera_hasta := NULL;
  NEW.espera_motivo := NULL;
  NEW.motivo_rechazo := NULL;
  NEW.activo := true;

  IF v_directo
     AND v_h.responsable_id IS DISTINCT FROM v_uid
     AND NOT public.usuario_tiene_permiso(v_uid, 'tareas_administrar')
     AND NOT (
       NEW.asignado_id IS NOT DISTINCT FROM v_uid
       AND NEW.paso_anterior_id IS NULL
       AND EXISTS (
         SELECT 1 FROM public.tareas t
         WHERE t.hilo_id = NEW.hilo_id AND t.activo AND t.asignado_id = v_uid
       )
     ) THEN
    RAISE EXCEPTION 'Los pasos los suma el responsable del hilo; el asignado, solo para sí y en paralelo' USING ERRCODE = 'TA001';
  END IF;

  IF NOT v_directo AND (
       NOT public.tareas_puede_recibir(NEW.asignado_id, NEW.asignado_equipo_id)
       OR (public.tareas_es_pedido(v_h.responsable_id, NEW.asignado_id, NEW.asignado_equipo_id)
           AND NOT public.usuario_tiene_permiso(v_h.responsable_id, 'tareas_pedir'))
     ) THEN
    NEW.asignado_id := v_h.responsable_id;
    NEW.asignado_equipo_id := NULL;
    PERFORM public.notificar(v_h.responsable_id, 'paso_a_reasignar', 'tareas', NEW.id, NULL);
  END IF;

  IF NOT public.tareas_puede_recibir(NEW.asignado_id, NEW.asignado_equipo_id) THEN
    RAISE EXCEPTION 'Solo se asigna a quien está activo y ve Tareas, o a un equipo con delegador' USING ERRCODE = 'TA003';
  END IF;

  NEW.equipo_id := public.tareas_equipo_de_asignado(NEW.asignado_id, NEW.asignado_equipo_id);
  NEW.estado := public.tareas_estado_al_abrir(v_h.responsable_id, NEW.asignado_id, NEW.asignado_equipo_id, v_directo);

  IF NEW.vence_dias IS NOT NULL THEN
    NEW.vence := CASE WHEN public.tareas_bloquea(NEW.paso_anterior_id) THEN NULL
                      ELSE public.tareas_hoy() + NEW.vence_dias END;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 2. El siguiente ciclo
-- ============================================================
-- Copia los pasos activos —completados y cancelados, que en un hilo cerrado
-- son todos— con título, descripción, cadena, asignado final y prioridad,
-- sin lo hecho, de la raíz a la cola de cada cadena. El vencimiento se corre
-- por el intervalo desde el anterior, fin de mes sigue siendo fin de mes; el
-- relativo al previo se copia tal cual. Estado y equipo, con las reglas de
-- hoy. Si el responsable ya no puede recibir, no hay siguiente: el cierre no
-- falla por eso.
CREATE OR REPLACE FUNCTION public.tareas_generar_siguiente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hilo uuid := gen_random_uuid();
  v_map jsonb := '{}';
  v_nuevo uuid;
  v_vence date;
  p record;
BEGIN
  IF NOT public.tareas_puede_recibir(NEW.responsable_id, NULL) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.tareas_hilos (id, titulo, responsable_id, recurrencia_cantidad, recurrencia_unidad, recurrencia_de)
  VALUES (v_hilo, NEW.titulo, NEW.responsable_id, NEW.recurrencia_cantidad, NEW.recurrencia_unidad, NEW.id);

  FOR p IN
    WITH RECURSIVE cadena AS (
      SELECT t.id, t.paso_anterior_id, t.titulo, t.descripcion, t.asignado_id,
             t.asignado_equipo_id, t.prioridad, t.vence, t.vence_dias, t.created_at AS raiz, 0 AS nivel
      FROM public.tareas t
      WHERE t.hilo_id = NEW.id AND t.activo AND t.paso_anterior_id IS NULL
      UNION ALL
      SELECT t.id, t.paso_anterior_id, t.titulo, t.descripcion, t.asignado_id,
             t.asignado_equipo_id, t.prioridad, t.vence, t.vence_dias, c.raiz, c.nivel + 1
      FROM cadena c
      JOIN public.tareas t ON t.paso_anterior_id = c.id AND t.activo
    )
    SELECT * FROM cadena ORDER BY raiz, nivel
  LOOP
    v_vence := CASE
      WHEN NEW.recurrencia_unidad = 'dia' THEN p.vence + NEW.recurrencia_cantidad
      WHEN p.vence = (date_trunc('month', p.vence) + interval '1 month - 1 day')::date
        THEN (date_trunc('month', p.vence) + make_interval(months => NEW.recurrencia_cantidad + 1) - interval '1 day')::date
      ELSE (p.vence + make_interval(months => NEW.recurrencia_cantidad))::date
    END;

    v_nuevo := gen_random_uuid();
    INSERT INTO public.tareas (id, hilo_id, paso_anterior_id, titulo, descripcion, asignado_id,
                               asignado_equipo_id, prioridad, vence, vence_dias)
    VALUES (v_nuevo, v_hilo, (v_map ->> p.paso_anterior_id::text)::uuid, p.titulo, p.descripcion, p.asignado_id,
            p.asignado_equipo_id, p.prioridad,
            CASE WHEN p.vence_dias IS NULL THEN v_vence END, p.vence_dias);
    v_map := v_map || jsonb_build_object(p.id, v_nuevo);
  END LOOP;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_generar_siguiente() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_generar_siguiente ON public.tareas_hilos;
CREATE TRIGGER tareas_generar_siguiente
  AFTER UPDATE OF estado ON public.tareas_hilos
  FOR EACH ROW
  WHEN (OLD.estado = 'abierto' AND NEW.estado = 'cerrado'
        AND NEW.recurrencia_cantidad IS NOT NULL AND NEW.activo)
  EXECUTE FUNCTION public.tareas_generar_siguiente();

-- ============================================================
-- 3. Cancelar pendientes y cerrar — por defecto termina la recurrencia
-- ============================================================
DROP FUNCTION IF EXISTS public.tareas_cancelar_y_cerrar(uuid, text);

CREATE OR REPLACE FUNCTION public.tareas_cancelar_y_cerrar(
  p_hilo uuid, p_resultado text DEFAULT NULL, p_generar boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.tareas SET estado = 'cancelada'
  WHERE hilo_id = p_hilo AND activo AND estado IN ('solicitada', 'pendiente', 'rechazada');

  UPDATE public.tareas_hilos
  SET estado = 'cerrado',
      resultado = p_resultado,
      recurrencia_cantidad = CASE WHEN p_generar THEN recurrencia_cantidad END,
      recurrencia_unidad = CASE WHEN p_generar THEN recurrencia_unidad END
  WHERE id = p_hilo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese hilo no existe o no lo ves' USING ERRCODE = 'TA001';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_cancelar_y_cerrar(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_cancelar_y_cerrar(uuid, text, boolean) TO authenticated;
