-- sql/113 — tareas: escrituras y sus reglas.
--
-- `sql/112` dejó el esquema con GRANT SELECT; acá van los GRANT de escritura
-- por columna y los triggers que los hacen valer: quién escribe qué, las
-- transiciones de estado, pedidos, la cadena (bloqueo, cascada, plazo
-- relativo, insertar antes), cierre y desactivación, notas e historial.
-- Quedan para después: bajas y cambios de equipo, los avisos (con
-- `transferencia` y los `relacion_*` del asignado) y plantillas y recurrencia.
-- Ficha y decisiones: `decisiones/tareas/`. Verificado con
-- `sql/tests/tareas_reglas.sql`.
--
-- Directo o sistema. Las reglas de quién puede hacer qué valen para lo que
-- escribe una persona: `pg_trigger_depth() = 1` (el statement es suyo, por
-- PostgREST o por una función INVOKER) y `auth.uid()` presente. Lo que
-- escriben los triggers en cascada (reabrir el siguiente, el plazo relativo,
-- mover pasos al transferir) corre a profundidad 2 y solo respeta las
-- invariantes. Los triggers son DEFINER: leen hilo y cadena sin RLS y llaman
-- helpers que no se exponen por RPC.
--
-- Los mensajes van con clase `TA`: están escritos para el usuario y
-- `mensajeError()` los deja pasar.

-- ============================================================
-- 1. Helpers — sin GRANT: los llaman los triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_hoy()
RETURNS date
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
$$;

-- El delegador de un equipo: el único miembro con `tareas_equipo`.
CREATE OR REPLACE FUNCTION public.tareas_delegador_de(p_equipo uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT m.usuario_id
  FROM public.equipos_miembros m
  JOIN public.equipos e ON e.id = m.equipo_id AND e.activo
  WHERE m.equipo_id = p_equipo
    AND m.activo
    AND public.usuario_tiene_permiso(m.usuario_id, 'tareas_equipo')
  LIMIT 1;
$$;

-- *Solo se asigna a quien puede recibirlo*: la persona, activa y con
-- `tareas_ver` (`usuario_tiene_permiso` ya pide `usuarios.activo`); el equipo,
-- con delegador.
CREATE OR REPLACE FUNCTION public.tareas_puede_recibir(p_usuario uuid, p_equipo uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_usuario IS NOT NULL THEN public.usuario_tiene_permiso(p_usuario, 'tareas_ver')
    ELSE public.tareas_delegador_de(p_equipo) IS NOT NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.tareas_equipo_de_asignado(p_usuario uuid, p_equipo uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT coalesce(p_equipo, public.equipo_de(p_usuario));
$$;

-- *"Pedido" se calcula en el momento*: asignado afuera del equipo del
-- responsable, hoy. Para un independiente, todo otro es afuera.
CREATE OR REPLACE FUNCTION public.tareas_es_pedido(p_responsable uuid, p_usuario uuid, p_equipo uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT p_usuario IS DISTINCT FROM p_responsable
    AND (
      public.equipo_de(p_responsable) IS NULL
      OR public.tareas_equipo_de_asignado(p_usuario, p_equipo) IS DISTINCT FROM public.equipo_de(p_responsable)
    );
$$;

-- Lo asignado al equipo lo hace, hasta que se reparte, su delegador.
CREATE OR REPLACE FUNCTION public.tareas_actua_como_asignado(p_actor uuid, p_usuario uuid, p_equipo uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT coalesce(
    p_actor = p_usuario OR (p_equipo IS NOT NULL AND public.tareas_delegador_de(p_equipo) = p_actor),
    false
  );
$$;

-- ¿Este paso, como previo, traba a su siguiente? Un cancelado es transparente:
-- se sube hasta el primer previo no cancelado, y traba si no está completado.
CREATE OR REPLACE FUNCTION public.tareas_bloquea(p_paso uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH RECURSIVE sube AS (
    SELECT t.estado, t.paso_anterior_id FROM public.tareas t WHERE t.id = p_paso
    UNION ALL
    SELECT t.estado, t.paso_anterior_id
    FROM sube s JOIN public.tareas t ON t.id = s.paso_anterior_id
    WHERE s.estado = 'cancelada'
  )
  SELECT coalesce(bool_or(estado NOT IN ('completada', 'cancelada')), false) FROM sube;
$$;

-- El primer siguiente activo no cancelado, bajando la cadena.
CREATE OR REPLACE FUNCTION public.tareas_siguiente_efectivo(p_paso uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH RECURSIVE baja AS (
    SELECT t.id, t.estado FROM public.tareas t WHERE t.paso_anterior_id = p_paso AND t.activo
    UNION ALL
    SELECT t.id, t.estado
    FROM baja b JOIN public.tareas t ON t.paso_anterior_id = b.id AND t.activo
    WHERE b.estado = 'cancelada'
  )
  SELECT id FROM baja WHERE estado <> 'cancelada';
$$;

-- *Abrir un paso es una sola regla*: el estado con que nace, se reabre o se
-- reasigna. Adentro del equipo del responsable, `pendiente`; afuera, pedido:
-- `solicitada`, salvo que lo abra el asignado mismo (retoma lo suyo) o
-- `tareas_administrar` (nunca genera `solicitada`). Generar `solicitada` exige
-- `tareas_pedir` a quien lo hace; a la cascada, no: no es un pedido nuevo.
CREATE OR REPLACE FUNCTION public.tareas_estado_al_abrir(
  p_responsable uuid, p_usuario uuid, p_equipo uuid, p_directo boolean
)
RETURNS estado_tarea
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF NOT public.tareas_es_pedido(p_responsable, p_usuario, p_equipo)
     OR public.tareas_actua_como_asignado(v_actor, p_usuario, p_equipo)
     OR public.usuario_tiene_permiso(v_actor, 'tareas_administrar') THEN
    RETURN 'pendiente';
  END IF;

  IF p_directo AND NOT public.usuario_tiene_permiso(v_actor, 'tareas_pedir') THEN
    RAISE EXCEPTION 'Pedir a otro equipo requiere el permiso Pedir a otros equipos' USING ERRCODE = 'TA010';
  END IF;

  RETURN 'solicitada';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_hoy() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_delegador_de(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_puede_recibir(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_equipo_de_asignado(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_es_pedido(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_actua_como_asignado(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_bloquea(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_siguiente_efectivo(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_estado_al_abrir(uuid, uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 2. tareas_hilos — crear, editar, transferir, cerrar, desactivar
-- ============================================================
ALTER TABLE public.tareas_hilos ALTER COLUMN responsable_id SET DEFAULT auth.uid();

CREATE OR REPLACE FUNCTION public.tareas_hilos_al_crear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  NEW.estado := 'abierto';
  NEW.resultado := NULL;
  NEW.activo := true;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL
     AND NEW.responsable_id IS DISTINCT FROM v_uid
     AND NOT public.usuario_tiene_permiso(v_uid, 'tareas_administrar') THEN
    RAISE EXCEPTION 'El hilo nace con vos como responsable' USING ERRCODE = 'TA002';
  END IF;

  IF NOT public.tareas_puede_recibir(NEW.responsable_id, NULL) THEN
    RAISE EXCEPTION 'Solo se asigna a quien está activo y ve Tareas' USING ERRCODE = 'TA003';
  END IF;

  NEW.equipo_id := public.equipo_de(NEW.responsable_id);
  RETURN NEW;
END;
$$;

-- Transferir a otro equipo exige `tareas_pedir` y va a su delegador (o a un
-- independiente); "otro" se mide contra el `equipo_id` guardado del hilo, así
-- la baja y el cambio de equipo, que lo entregan al delegador de ese mismo
-- equipo, no cuentan como transferencia afuera.
CREATE OR REPLACE FUNCTION public.tareas_hilos_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adm boolean;
  v_equipo_nuevo uuid;
  v_transfiere boolean := NEW.responsable_id IS DISTINCT FROM OLD.responsable_id;
BEGIN
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL THEN
    v_adm := public.usuario_tiene_permiso(v_uid, 'tareas_administrar');

    IF OLD.responsable_id IS DISTINCT FROM v_uid AND NOT v_adm THEN
      RAISE EXCEPTION 'Solo el responsable del hilo lo edita' USING ERRCODE = 'TA001';
    END IF;

    IF NOT OLD.activo AND NEW.activo AND NOT v_adm THEN
      RAISE EXCEPTION 'Solo el admin reactiva un hilo' USING ERRCODE = 'TA011';
    END IF;

    IF OLD.estado = 'cerrado' AND NEW.estado = 'cerrado' AND (
      NEW.titulo IS DISTINCT FROM OLD.titulo
      OR NEW.resultado IS DISTINCT FROM OLD.resultado
      OR NEW.recurrencia_cantidad IS DISTINCT FROM OLD.recurrencia_cantidad
      OR NEW.recurrencia_unidad IS DISTINCT FROM OLD.recurrencia_unidad
    ) THEN
      RAISE EXCEPTION 'Un hilo cerrado no se edita: se corrige con una nota o se reabre' USING ERRCODE = 'TA007';
    END IF;

    IF v_transfiere THEN
      v_equipo_nuevo := public.equipo_de(NEW.responsable_id);
      IF OLD.equipo_id IS NULL OR v_equipo_nuevo IS DISTINCT FROM OLD.equipo_id THEN
        IF NOT public.usuario_tiene_permiso(v_uid, 'tareas_pedir') THEN
          RAISE EXCEPTION 'Transferir a otro equipo requiere el permiso Pedir a otros equipos' USING ERRCODE = 'TA010';
        END IF;
        IF v_equipo_nuevo IS NOT NULL
           AND public.tareas_delegador_de(v_equipo_nuevo) IS DISTINCT FROM NEW.responsable_id THEN
          RAISE EXCEPTION 'A otro equipo, el hilo se transfiere a su delegador' USING ERRCODE = 'TA015';
        END IF;
      END IF;
    END IF;
  END IF;

  IF v_transfiere THEN
    IF NOT public.tareas_puede_recibir(NEW.responsable_id, NULL) THEN
      RAISE EXCEPTION 'Solo se asigna a quien está activo y ve Tareas' USING ERRCODE = 'TA003';
    END IF;
    NEW.equipo_id := public.equipo_de(NEW.responsable_id);
  END IF;

  IF OLD.estado = 'abierto' AND NEW.estado = 'cerrado' AND EXISTS (
    SELECT 1 FROM public.tareas t
    WHERE t.hilo_id = NEW.id AND t.activo AND t.estado IN ('solicitada', 'pendiente', 'rechazada')
  ) THEN
    RAISE EXCEPTION 'El hilo tiene pasos sin resolver: completalos o cancelalos antes de cerrar' USING ERRCODE = 'TA008';
  END IF;

  IF OLD.activo AND NOT NEW.activo AND EXISTS (
    SELECT 1 FROM public.tareas t WHERE t.hilo_id = NEW.id AND t.activo AND t.estado = 'completada'
  ) THEN
    RAISE EXCEPTION 'Un hilo con pasos completados no se desactiva: cancelá lo pendiente y cerralo' USING ERRCODE = 'TA009';
  END IF;

  RETURN NEW;
END;
$$;

-- *Transferir un hilo a otro equipo*: los pasos abiertos del equipo de origen
-- —personas y el equipo mismo— pasan al nuevo responsable.
CREATE OR REPLACE FUNCTION public.tareas_hilos_transferir()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.equipo_id IS NOT NULL AND NEW.equipo_id IS DISTINCT FROM OLD.equipo_id THEN
    UPDATE public.tareas
    SET asignado_id = NEW.responsable_id, asignado_equipo_id = NULL
    WHERE hilo_id = NEW.id
      AND activo
      AND equipo_id = OLD.equipo_id
      AND estado IN ('solicitada', 'pendiente', 'rechazada');
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_hilos_al_crear() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_hilos_al_editar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_hilos_transferir() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_hilos_al_crear ON public.tareas_hilos;
CREATE TRIGGER tareas_hilos_al_crear
  BEFORE INSERT ON public.tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION public.tareas_hilos_al_crear();

DROP TRIGGER IF EXISTS tareas_hilos_al_editar ON public.tareas_hilos;
CREATE TRIGGER tareas_hilos_al_editar
  BEFORE UPDATE ON public.tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION public.tareas_hilos_al_editar();

DROP TRIGGER IF EXISTS tareas_hilos_transferir ON public.tareas_hilos;
CREATE TRIGGER tareas_hilos_transferir
  AFTER UPDATE OF responsable_id ON public.tareas_hilos
  FOR EACH ROW WHEN (OLD.responsable_id IS DISTINCT FROM NEW.responsable_id)
  EXECUTE FUNCTION public.tareas_hilos_transferir();

-- ============================================================
-- 3. tareas — el paso
-- ============================================================
-- Al crear: estado, equipo y vencimiento relativo los pone la base. Suma
-- pasos el responsable (o el admin); el asignado de algún paso, solo para sí y
-- en paralelo. Desde un trigger (recurrencia, plantillas) un asignado que no
-- puede recibir deja el paso en el responsable, en vez de fallar.
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

  IF NOT public.tareas_puede_recibir(NEW.asignado_id, NEW.asignado_equipo_id) THEN
    IF v_directo OR NOT public.tareas_puede_recibir(v_h.responsable_id, NULL) THEN
      RAISE EXCEPTION 'Solo se asigna a quien está activo y ve Tareas, o a un equipo con delegador' USING ERRCODE = 'TA003';
    END IF;
    NEW.asignado_id := v_h.responsable_id;
    NEW.asignado_equipo_id := NULL;
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

-- Al editar. Columnas del responsable del hilo: contenido, asignado, previo
-- (solo *Insertar antes de*), desactivar. Del asignado: estado, espera,
-- resultado. `tareas_administrar`, todo; completar lo ajeno, con nota.
-- Delegador del equipo del asignado: acepta, rechaza y devuelve pedidos, y
-- reparte dentro del equipo conservando el estado.
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

    IF NOT (v_h.activo AND OLD.activo) AND NOT v_adm THEN
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

-- Después de crear, cambiar de estado o reactivar: el hilo se reabre si
-- vuelve a tener algo abierto; reabrir un paso reabre el siguiente completado
-- (y su propio trigger sigue la cascada); habilitarse o bloquearse el
-- siguiente fija o borra su vencimiento relativo.
CREATE OR REPLACE FUNCTION public.tareas_propagar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sig uuid;
  v_trababa boolean;
  v_traba boolean;
BEGIN
  IF NEW.activo AND NEW.estado IN ('solicitada', 'pendiente', 'rechazada') THEN
    UPDATE public.tareas_hilos SET estado = 'abierto' WHERE id = NEW.hilo_id AND estado = 'cerrado';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
    RETURN NULL;
  END IF;

  v_sig := public.tareas_siguiente_efectivo(NEW.id);
  IF v_sig IS NULL THEN
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.estado IN ('completada', 'cancelada')
     AND NEW.estado IN ('solicitada', 'pendiente', 'rechazada') THEN
    UPDATE public.tareas SET estado = 'pendiente' WHERE id = v_sig AND estado = 'completada';
  END IF;

  -- En un INSERT solo hay siguiente si es *Insertar antes de*: antes lo
  -- trababa el previo del paso nuevo.
  v_trababa := CASE
    WHEN TG_OP = 'INSERT' OR OLD.estado = 'cancelada' THEN public.tareas_bloquea(NEW.paso_anterior_id)
    ELSE OLD.estado <> 'completada'
  END;
  v_traba := public.tareas_bloquea(NEW.id);

  IF v_trababa IS DISTINCT FROM v_traba THEN
    UPDATE public.tareas
    SET vence = CASE WHEN v_traba THEN NULL ELSE public.tareas_hoy() + vence_dias END
    WHERE id = v_sig AND vence_dias IS NOT NULL AND estado IN ('solicitada', 'pendiente', 'rechazada');
  END IF;

  RETURN NULL;
END;
$$;

-- Al cierre de la transacción: se desactiva desde la cola, y el previo solo
-- cambia en *Insertar antes de* — el nuevo previo es un paso creado en esta
-- misma transacción que tomó el lugar del viejo. Diferido porque la función
-- apunta el siguiente al paso nuevo antes de crearlo.
CREATE OR REPLACE FUNCTION public.tareas_validar_cadena()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.activo AND NOT NEW.activo AND EXISTS (
    SELECT 1 FROM public.tareas s WHERE s.paso_anterior_id = NEW.id AND s.activo
  ) THEN
    RAISE EXCEPTION 'Ese paso tiene un siguiente activo: se desactiva desde el último' USING ERRCODE = 'TA006';
  END IF;

  IF NEW.paso_anterior_id IS DISTINCT FROM OLD.paso_anterior_id AND NOT EXISTS (
    SELECT 1 FROM public.tareas n
    WHERE n.id = NEW.paso_anterior_id
      AND n.activo
      AND n.hilo_id = NEW.hilo_id
      AND n.paso_anterior_id IS NOT DISTINCT FROM OLD.paso_anterior_id
      AND n.created_at >= now()
  ) THEN
    RAISE EXCEPTION 'El paso anterior no se cambia: se inserta un paso antes' USING ERRCODE = 'TA005';
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_al_crear() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_al_editar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_propagar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_validar_cadena() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_al_crear ON public.tareas;
CREATE TRIGGER tareas_al_crear
  BEFORE INSERT ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_al_crear();

DROP TRIGGER IF EXISTS tareas_al_editar ON public.tareas;
CREATE TRIGGER tareas_al_editar
  BEFORE UPDATE ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_al_editar();

DROP TRIGGER IF EXISTS tareas_propagar ON public.tareas;
CREATE TRIGGER tareas_propagar
  AFTER INSERT OR UPDATE OF estado, activo ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_propagar();

DROP TRIGGER IF EXISTS tareas_validar_cadena ON public.tareas;
CREATE CONSTRAINT TRIGGER tareas_validar_cadena
  AFTER UPDATE ON public.tareas
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN ((OLD.activo AND NOT NEW.activo) OR OLD.paso_anterior_id IS DISTINCT FROM NEW.paso_anterior_id)
  EXECUTE FUNCTION public.tareas_validar_cadena();

-- ============================================================
-- 4. tareas_ediciones — el valor anterior de lo que edita una persona
-- ============================================================
-- TG_ARGV = las columnas de contenido. Lo derivado por la base (vencimiento
-- al habilitarse, equipo al mover) no es una edición.
CREATE OR REPLACE FUNCTION public.tareas_registrar_ediciones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viejo jsonb := to_jsonb(OLD);
  v_nuevo jsonb := to_jsonb(NEW);
  v_campo text;
BEGIN
  IF pg_trigger_depth() > 1 OR auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  FOREACH v_campo IN ARRAY TG_ARGV LOOP
    IF v_viejo -> v_campo IS DISTINCT FROM v_nuevo -> v_campo THEN
      INSERT INTO public.tareas_ediciones (hilo_id, tarea_id, campo, anterior, nuevo, actor_id)
      VALUES (
        coalesce((v_nuevo ->> 'hilo_id')::uuid, NEW.id),
        CASE WHEN TG_TABLE_NAME = 'tareas' THEN NEW.id END,
        v_campo, v_viejo ->> v_campo, v_nuevo ->> v_campo, auth.uid()
      );
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_registrar_ediciones() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_registrar_ediciones ON public.tareas_hilos;
CREATE TRIGGER tareas_registrar_ediciones
  AFTER UPDATE OF titulo, recurrencia_cantidad, recurrencia_unidad ON public.tareas_hilos
  FOR EACH ROW
  EXECUTE FUNCTION public.tareas_registrar_ediciones('titulo', 'recurrencia_cantidad', 'recurrencia_unidad');

DROP TRIGGER IF EXISTS tareas_registrar_ediciones ON public.tareas;
CREATE TRIGGER tareas_registrar_ediciones
  AFTER UPDATE OF titulo, descripcion, prioridad, vence, vence_dias ON public.tareas
  FOR EACH ROW
  EXECUTE FUNCTION public.tareas_registrar_ediciones('titulo', 'descripcion', 'prioridad', 'vence', 'vence_dias');

-- ============================================================
-- 5. Ocultar una nota o una edición — `tareas_administrar`, firmado
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_firmar_ocultar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.activo THEN
    NEW.ocultada_por := NULL;
    NEW.ocultada_at := NULL;
  ELSIF OLD.activo THEN
    NEW.ocultada_por := auth.uid();
    NEW.ocultada_at := now();
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_firmar_ocultar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_firmar_ocultar ON public.tareas_notas;
CREATE TRIGGER tareas_firmar_ocultar
  BEFORE UPDATE OF activo ON public.tareas_notas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_firmar_ocultar();

DROP TRIGGER IF EXISTS tareas_firmar_ocultar ON public.tareas_ediciones;
CREATE TRIGGER tareas_firmar_ocultar
  BEFORE UPDATE OF activo ON public.tareas_ediciones
  FOR EACH ROW EXECUTE FUNCTION public.tareas_firmar_ocultar();

-- ============================================================
-- 6. Policies y GRANT de escritura
-- ============================================================
-- La policy dice sobre qué filas; el trigger, quién puede qué. Lo que deja la
-- fila fuera de la vista de quien lo hace (desactivar, transferir) va por las
-- funciones DEFINER de la sección 7.
DROP POLICY IF EXISTS tareas_hilos_insert ON public.tareas_hilos;
CREATE POLICY tareas_hilos_insert ON public.tareas_hilos FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('tareas_ver'));

DROP POLICY IF EXISTS tareas_hilos_update ON public.tareas_hilos;
CREATE POLICY tareas_hilos_update ON public.tareas_hilos FOR UPDATE TO authenticated
  USING (tareas_puede_ver_hilo(id, responsable_id, equipo_id, activo))
  WITH CHECK (true);

DROP POLICY IF EXISTS tareas_insert ON public.tareas;
CREATE POLICY tareas_insert ON public.tareas FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.tareas_hilos h WHERE h.id = hilo_id));

DROP POLICY IF EXISTS tareas_update ON public.tareas;
CREATE POLICY tareas_update ON public.tareas FOR UPDATE TO authenticated
  USING (tareas_puede_ver_tarea(hilo_id, activo))
  WITH CHECK (true);

-- Anota quien ve el hilo, también en pasos congelados.
DROP POLICY IF EXISTS tareas_notas_insert ON public.tareas_notas;
CREATE POLICY tareas_notas_insert ON public.tareas_notas FOR INSERT TO authenticated
  WITH CHECK (
    autor_id = (select auth.uid())
    AND EXISTS (SELECT 1 FROM public.tareas_hilos h WHERE h.id = hilo_id)
    AND (tarea_id IS NULL OR EXISTS (SELECT 1 FROM public.tareas t WHERE t.id = tarea_id))
  );

DROP POLICY IF EXISTS tareas_notas_update ON public.tareas_notas;
CREATE POLICY tareas_notas_update ON public.tareas_notas FOR UPDATE TO authenticated
  USING (tiene_permiso('tareas_administrar'))
  WITH CHECK (true);

DROP POLICY IF EXISTS tareas_ediciones_update ON public.tareas_ediciones;
CREATE POLICY tareas_ediciones_update ON public.tareas_ediciones FOR UPDATE TO authenticated
  USING (tiene_permiso('tareas_administrar'))
  WITH CHECK (true);

GRANT INSERT (id, titulo, responsable_id, recurrencia_cantidad, recurrencia_unidad)
  ON public.tareas_hilos TO authenticated;
GRANT UPDATE (titulo, responsable_id, estado, resultado, recurrencia_cantidad, recurrencia_unidad, activo)
  ON public.tareas_hilos TO authenticated;

GRANT INSERT (id, hilo_id, paso_anterior_id, titulo, descripcion, asignado_id, asignado_equipo_id,
              prioridad, vence, vence_dias)
  ON public.tareas TO authenticated;
GRANT UPDATE (paso_anterior_id, titulo, descripcion, asignado_id, asignado_equipo_id, estado, prioridad,
              vence, vence_dias, espera_hasta, espera_motivo, resultado, motivo_rechazo, activo)
  ON public.tareas TO authenticated;

GRANT INSERT (id, hilo_id, tarea_id, texto) ON public.tareas_notas TO authenticated;
GRANT UPDATE (activo) ON public.tareas_notas, public.tareas_ediciones TO authenticated;

-- ============================================================
-- 7. Escrituras de más de un statement — INVOKER, las reglas son los triggers
-- ============================================================
-- *Insertar antes de*: el siguiente apunta al paso nuevo, y el nuevo toma su
-- previo viejo. En ese orden por el unique de "no bifurca"; la FK se difiere.
CREATE OR REPLACE FUNCTION public.tareas_insertar_antes(
  p_siguiente          uuid,
  p_titulo             text,
  p_descripcion        text,
  p_asignado_id        uuid,
  p_asignado_equipo_id uuid,
  p_prioridad          prioridad_tarea DEFAULT 'media',
  p_vence              date DEFAULT NULL,
  p_vence_dias         int DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_sig public.tareas;
BEGIN
  SELECT * INTO v_sig FROM public.tareas WHERE id = p_siguiente AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese paso no existe o no lo ves' USING ERRCODE = 'TA005';
  END IF;

  SET CONSTRAINTS public.tareas_paso_anterior_fk DEFERRED;

  UPDATE public.tareas SET paso_anterior_id = v_id WHERE id = p_siguiente;

  INSERT INTO public.tareas (id, hilo_id, paso_anterior_id, titulo, descripcion, asignado_id,
                             asignado_equipo_id, prioridad, vence, vence_dias)
  VALUES (v_id, v_sig.hilo_id, v_sig.paso_anterior_id, p_titulo, p_descripcion, p_asignado_id,
          p_asignado_equipo_id, p_prioridad, p_vence, p_vence_dias);

  RETURN v_id;
END;
$$;

-- *Cancelar pendientes y cerrar*: lo que ya no va, con trabajo hecho.
CREATE OR REPLACE FUNCTION public.tareas_cancelar_y_cerrar(p_hilo uuid, p_resultado text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.tareas SET estado = 'cancelada'
  WHERE hilo_id = p_hilo AND activo AND estado IN ('solicitada', 'pendiente', 'rechazada');

  UPDATE public.tareas_hilos SET estado = 'cerrado', resultado = p_resultado WHERE id = p_hilo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese hilo no existe o no lo ves' USING ERRCODE = 'TA001';
  END IF;
END;
$$;

-- `tareas_administrar` completa lo ajeno con nota obligatoria: las dos cosas
-- en una transacción, y el trigger busca la nota de esta transacción.
CREATE OR REPLACE FUNCTION public.tareas_completar_con_nota(p_tarea uuid, p_nota text, p_resultado text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.tareas_notas (hilo_id, tarea_id, texto)
  SELECT hilo_id, id, p_nota FROM public.tareas WHERE id = p_tarea;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese paso no existe o no lo ves' USING ERRCODE = 'TA005';
  END IF;

  UPDATE public.tareas
  SET estado = 'completada', resultado = coalesce(p_resultado, resultado)
  WHERE id = p_tarea;
END;
$$;

-- Desactivar y transferir dejan la fila fuera de la vista de quien lo hace, y
-- Postgres pasa la fila nueva de un UPDATE por la policy de SELECT: por
-- PostgREST fallaría con 42501. DEFINER solo para eso; quién puede, lo decide
-- el trigger (el statement sigue siendo de la persona: profundidad 1).
CREATE OR REPLACE FUNCTION public.tareas_desactivar_paso(p_paso uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.tareas SET activo = false WHERE id = p_paso AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese paso no existe o ya está desactivado' USING ERRCODE = 'TA005';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.tareas_desactivar_hilo(p_hilo uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.tareas_hilos SET activo = false WHERE id = p_hilo AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese hilo no existe o ya está desactivado' USING ERRCODE = 'TA001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.tareas_transferir_hilo(p_hilo uuid, p_responsable uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.tareas_hilos SET responsable_id = p_responsable WHERE id = p_hilo AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese hilo no existe o está desactivado' USING ERRCODE = 'TA001';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_desactivar_paso(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_desactivar_paso(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_desactivar_hilo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_desactivar_hilo(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_transferir_hilo(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_transferir_hilo(uuid, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.tareas_insertar_antes(uuid, text, text, uuid, uuid, prioridad_tarea, date, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_insertar_antes(uuid, text, text, uuid, uuid, prioridad_tarea, date, int) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_cancelar_y_cerrar(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_cancelar_y_cerrar(uuid, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_completar_con_nota(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_completar_con_nota(uuid, text, text) TO authenticated;
