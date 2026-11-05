-- El admin sigue reactivando o desactivando un paso de un hilo desactivado, pero
-- ya no edita lo demás: con la ficha abierta, guardar decía "Paso guardado" y
-- cambiaba una fila inactiva. Antes de esto, la exención de TA013 era total.

CREATE OR REPLACE FUNCTION public.tareas_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_directo boolean := pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL;
  v_h public.tareas_hilos;
  v_adm boolean;
  v_resp boolean;
  v_asig boolean;
  v_deleg boolean;
  v_abiertos constant estado_tarea[] := '{solicitada,pendiente,rechazada}';
  v_congelado boolean := OLD.estado IN ('completada', 'cancelada');
  v_reabre boolean := OLD.estado IN ('completada', 'cancelada') AND NEW.estado = ANY (v_abiertos);
  v_reasigna boolean := NEW.asignado_id IS DISTINCT FROM OLD.asignado_id
                        OR NEW.asignado_equipo_id IS DISTINCT FROM OLD.asignado_equipo_id;
  v_contenido boolean := NEW.titulo IS DISTINCT FROM OLD.titulo
                         OR NEW.descripcion IS DISTINCT FROM OLD.descripcion
                         OR NEW.vence IS DISTINCT FROM OLD.vence
                         OR NEW.vence_dias IS DISTINCT FROM OLD.vence_dias;
  v_prioridad boolean := NEW.prioridad IS DISTINCT FROM OLD.prioridad;
  v_previo boolean := NEW.paso_anterior_id IS DISTINCT FROM OLD.paso_anterior_id;
  v_ejecucion boolean := NEW.espera_hasta IS DISTINCT FROM OLD.espera_hasta
                         OR NEW.espera_motivo IS DISTINCT FROM OLD.espera_motivo
                         OR NEW.resultado IS DISTINCT FROM OLD.resultado;
  v_estado boolean := NEW.estado IS DISTINCT FROM OLD.estado;
BEGIN
  IF NEW.hilo_id IS DISTINCT FROM OLD.hilo_id THEN
    RAISE EXCEPTION 'Un paso no cambia de hilo' USING ERRCODE = 'TA005';
  END IF;

  SELECT * INTO v_h FROM public.tareas_hilos WHERE id = NEW.hilo_id;

  IF v_directo THEN
    v_adm := public.usuario_tiene_permiso(v_uid, 'tareas_administrar');
    v_resp := v_h.responsable_id = v_uid;
    v_asig := public.tareas_actua_como_asignado(v_uid, OLD.asignado_id, OLD.asignado_equipo_id);
    v_deleg := public.usuario_tiene_permiso(v_uid, 'tareas_equipo')
               AND coalesce(OLD.equipo_id = public.equipo_de(v_uid), false);

    IF NOT (v_h.activo AND OLD.activo)
       AND (NOT v_adm OR NEW.activo IS NOT DISTINCT FROM OLD.activo) THEN
      RAISE EXCEPTION 'El paso o su hilo están desactivados' USING ERRCODE = 'TA013';
    END IF;

    IF NEW.activo IS DISTINCT FROM OLD.activo THEN
      IF NOT (v_resp OR v_adm) THEN
        RAISE EXCEPTION 'Desactivar un paso es del responsable del hilo' USING ERRCODE = 'TA001';
      END IF;
      IF NOT v_adm AND v_congelado THEN
        RAISE EXCEPTION 'Un paso completado o cancelado no se desactiva: se reabre primero' USING ERRCODE = 'TA007';
      END IF;
    END IF;

    IF v_congelado AND NOT v_reabre AND (v_reasigna OR v_contenido OR v_prioridad OR v_previo OR v_ejecucion) THEN
      RAISE EXCEPTION 'Un paso completado o cancelado no se edita: se corrige con una nota o se reabre' USING ERRCODE = 'TA007';
    END IF;

    IF v_reabre AND (v_reasigna OR v_contenido OR v_prioridad OR v_ejecucion) THEN
      RAISE EXCEPTION 'Reabrir cambia solo el estado; lo demás, después' USING ERRCODE = 'TA016';
    END IF;

    IF (v_contenido OR v_prioridad OR v_previo) AND NOT (v_resp OR v_adm) THEN
      RAISE EXCEPTION 'El contenido del paso es del responsable del hilo' USING ERRCODE = 'TA001';
    END IF;

    IF v_ejecucion AND NOT (v_asig OR v_adm) THEN
      RAISE EXCEPTION 'Espera y resultado son del asignado' USING ERRCODE = 'TA011';
    END IF;

    IF v_reasigna THEN
      IF v_resp OR v_adm THEN
        NULL;
      ELSIF v_deleg
            AND OLD.estado IN ('solicitada', 'pendiente')
            AND public.tareas_equipo_de_asignado(NEW.asignado_id, NEW.asignado_equipo_id) IS NOT DISTINCT FROM OLD.equipo_id THEN
        IF v_estado THEN
          RAISE EXCEPTION 'Repartir conserva el estado del paso' USING ERRCODE = 'TA014';
        END IF;
      ELSE
        RAISE EXCEPTION 'Reasignar es del responsable del hilo; el delegador, dentro de su equipo' USING ERRCODE = 'TA014';
      END IF;

      IF NOT public.tareas_puede_recibir(NEW.asignado_id, NEW.asignado_equipo_id) THEN
        RAISE EXCEPTION 'Solo se asigna a quien está activo y ve Tareas, o a un equipo con delegador' USING ERRCODE = 'TA003';
      END IF;

      IF v_resp OR v_adm THEN
        NEW.estado := public.tareas_estado_al_abrir(v_h.responsable_id, NEW.asignado_id, NEW.asignado_equipo_id, true);
      END IF;

    ELSIF v_estado THEN
      IF OLD.estado = 'solicitada' AND NEW.estado IN ('pendiente', 'rechazada') THEN
        IF NOT (v_asig OR v_deleg OR v_adm) THEN
          RAISE EXCEPTION 'Aceptar o rechazar un pedido es de quien lo recibe' USING ERRCODE = 'TA011';
        END IF;

      ELSIF OLD.estado = 'pendiente' AND NEW.estado = 'completada' THEN
        IF NOT (v_asig OR v_adm) THEN
          RAISE EXCEPTION 'Completar un paso es de su asignado' USING ERRCODE = 'TA011';
        END IF;
        IF NOT v_asig AND NOT EXISTS (
          SELECT 1 FROM public.tareas_notas n
          WHERE n.tarea_id = NEW.id AND n.autor_id = v_uid AND n.activo AND n.created_at >= now()
        ) THEN
          RAISE EXCEPTION 'Completar un paso ajeno pide una nota' USING ERRCODE = 'TA012';
        END IF;

      ELSIF OLD.estado = 'pendiente' AND NEW.estado = 'rechazada' THEN
        IF NOT public.tareas_es_pedido(v_h.responsable_id, OLD.asignado_id, OLD.asignado_equipo_id) THEN
          RAISE EXCEPTION 'Solo un pedido se devuelve; dentro del equipo, el responsable lo reasigna' USING ERRCODE = 'TA011';
        END IF;
        IF NOT (v_asig OR v_deleg OR v_adm) THEN
          RAISE EXCEPTION 'Devolver un pedido es de quien lo recibió' USING ERRCODE = 'TA011';
        END IF;

      ELSIF OLD.estado = ANY (v_abiertos) AND NEW.estado = 'cancelada' THEN
        IF NOT (v_resp OR v_adm) THEN
          RAISE EXCEPTION 'Cancelar un paso es del responsable del hilo' USING ERRCODE = 'TA011';
        END IF;

      ELSIF OLD.estado = 'rechazada' AND NEW.estado IN ('solicitada', 'pendiente') THEN
        IF NOT (v_resp OR v_adm) THEN
          RAISE EXCEPTION 'Un rechazado lo resuelve el responsable del hilo' USING ERRCODE = 'TA011';
        END IF;
        NEW.estado := public.tareas_estado_al_abrir(v_h.responsable_id, NEW.asignado_id, NEW.asignado_equipo_id, true);

      ELSIF v_reabre THEN
        IF NOT (v_resp OR v_adm OR (v_asig AND OLD.estado = 'completada')) THEN
          RAISE EXCEPTION 'Reabrir es del responsable del hilo, o del asignado si lo completó' USING ERRCODE = 'TA011';
        END IF;

      ELSE
        RAISE EXCEPTION 'Ese cambio de estado no existe' USING ERRCODE = 'TA011';
      END IF;
    END IF;

    -- *Editar un pedido aceptado lo devuelve a `solicitada`*: título,
    -- descripción o vencimiento; la prioridad no.
    IF v_contenido AND NOT v_estado AND NOT v_reasigna AND NOT v_adm
       AND OLD.estado = 'pendiente'
       AND public.tareas_es_pedido(v_h.responsable_id, OLD.asignado_id, OLD.asignado_equipo_id) THEN
      IF NOT public.usuario_tiene_permiso(v_uid, 'tareas_pedir') THEN
        RAISE EXCEPTION 'Editar un pedido requiere el permiso Pedir a otros equipos' USING ERRCODE = 'TA010';
      END IF;
      NEW.estado := 'solicitada';
    END IF;

    IF NEW.vence_dias IS NOT NULL AND NEW.vence IS DISTINCT FROM OLD.vence
       AND NEW.vence_dias IS NOT DISTINCT FROM OLD.vence_dias THEN
      RAISE EXCEPTION 'Con plazo en días, el vencimiento lo calcula la base' USING ERRCODE = 'TA011';
    END IF;
  END IF;

  -- Desde acá, también para lo que escriben los triggers.

  -- *Insertar antes de* apunta el siguiente a un paso que todavía no existe;
  -- el resto de la forma la verifica `tareas_validar_cadena` al cierre.
  IF v_previo AND EXISTS (SELECT 1 FROM public.tareas WHERE id = NEW.paso_anterior_id) THEN
    RAISE EXCEPTION 'El paso anterior no se cambia: se inserta un paso antes' USING ERRCODE = 'TA005';
  END IF;

  -- Reabrir y reactivar abren el paso: si el asignado ya no puede recibir,
  -- queda en el responsable (el aviso "paso a reasignar" llega con los avisos).
  IF (v_reabre OR (NOT OLD.activo AND NEW.activo AND NEW.estado = ANY (v_abiertos)))
     AND NOT public.tareas_puede_recibir(NEW.asignado_id, NEW.asignado_equipo_id)
     AND public.tareas_puede_recibir(v_h.responsable_id, NULL) THEN
    NEW.asignado_id := v_h.responsable_id;
    NEW.asignado_equipo_id := NULL;
  END IF;

  IF v_reabre THEN
    NEW.estado := public.tareas_estado_al_abrir(v_h.responsable_id, NEW.asignado_id, NEW.asignado_equipo_id, v_directo);
  END IF;

  IF NOT OLD.activo AND NEW.activo AND NEW.paso_anterior_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.tareas WHERE id = NEW.paso_anterior_id AND activo
  ) THEN
    RAISE EXCEPTION 'El paso anterior está desactivado' USING ERRCODE = 'TA005';
  END IF;

  IF NEW.asignado_id IS DISTINCT FROM OLD.asignado_id
     OR NEW.asignado_equipo_id IS DISTINCT FROM OLD.asignado_equipo_id THEN
    NEW.equipo_id := public.tareas_equipo_de_asignado(NEW.asignado_id, NEW.asignado_equipo_id);
    NEW.espera_hasta := NULL;
    NEW.espera_motivo := NULL;
    -- Lo que mueve el sistema a quien no se lo pidió deja de ser pedido.
    IF NOT v_directo AND NEW.estado = 'solicitada'
       AND NOT public.tareas_es_pedido(v_h.responsable_id, NEW.asignado_id, NEW.asignado_equipo_id) THEN
      NEW.estado := 'pendiente';
    END IF;
  END IF;

  IF NEW.estado <> 'pendiente' THEN
    NEW.espera_hasta := NULL;
    NEW.espera_motivo := NULL;
  END IF;

  IF NEW.estado <> 'rechazada' THEN
    NEW.motivo_rechazo := NULL;
  END IF;

  IF NEW.estado = 'completada' AND OLD.estado <> 'completada' AND public.tareas_bloquea(NEW.paso_anterior_id) THEN
    RAISE EXCEPTION 'El paso anterior todavía no está completado' USING ERRCODE = 'TA004';
  END IF;

  IF NEW.vence_dias IS NOT NULL AND NEW.vence_dias IS DISTINCT FROM OLD.vence_dias THEN
    NEW.vence := CASE WHEN public.tareas_bloquea(NEW.paso_anterior_id) THEN NULL
                      ELSE public.tareas_hoy() + NEW.vence_dias END;
  END IF;

  RETURN NEW;
END;
$$;
