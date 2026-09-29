-- sql/153 — tareas, tramo 5, paso 5: pasos que se completan solos.
--
--   1. `tareas.completa_evento` / `completa_valor`: la condición de la
--      plantilla, copiada al paso. Fuera de los GRANT: las escriben
--      `usar_plantilla` y la recurrencia, que las copia al ciclo siguiente.
--   2. `tareas_completar_sola(paso)` (DEFINER): un paso pendiente, habilitado,
--      de un hilo activo con registro, se completa si el registro cumple la
--      condición ahora: tiene un vínculo abierto con ese rol, o está en ese
--      estado. Corre en cascada: las reglas de actor no aplican. El resultado
--      queda vacío: la pantalla muestra la condición.
--   3. Se evalúa al llegar el evento (`completar_pasos`, AFTER INSERT ON
--      eventos), y en `tareas_propagar` al nacer el paso, al aceptarlo (o
--      volver a pendiente desde un rechazo) y al habilitarse. Reabrir no
--      evalúa: si no, el asignado no podría reabrir un paso que se cerró solo.
--
-- Decisiones: `decisiones/tareas/catalogo.md` → *Un paso se completa solo
-- cuando el registro cumple*; `decisiones/obras.md` → *Dos acciones*.

-- ============================================================
-- 1. La condición en el paso
-- ============================================================
ALTER TABLE public.tareas
  ADD COLUMN IF NOT EXISTS completa_evento tipo_evento,
  ADD COLUMN IF NOT EXISTS completa_valor text;

ALTER TABLE public.tareas DROP CONSTRAINT IF EXISTS tareas_completa;
ALTER TABLE public.tareas ADD CONSTRAINT tareas_completa
  CHECK ((completa_evento IS NULL) = (completa_valor IS NULL));
ALTER TABLE public.tareas DROP CONSTRAINT IF EXISTS tareas_completa_evento;
ALTER TABLE public.tareas ADD CONSTRAINT tareas_completa_evento
  CHECK (completa_evento IN ('relacion_alta', 'estado'));

-- ============================================================
-- 2. Completar sola
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_completar_sola(p_tarea uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t public.tareas;
  h public.tareas_hilos;
  v_tabla text;
  v_cumple boolean;
BEGIN
  SELECT * INTO t FROM public.tareas WHERE id = p_tarea;
  IF t.completa_evento IS NULL OR NOT t.activo OR t.estado <> 'pendiente'
     OR public.tareas_bloquea(t.paso_anterior_id) THEN
    RETURN;
  END IF;

  SELECT * INTO h FROM public.tareas_hilos WHERE id = t.hilo_id;
  IF NOT h.activo OR h.registro_id IS NULL THEN
    RETURN;
  END IF;

  IF t.completa_evento = 'relacion_alta' THEN
    v_cumple := EXISTS (
      SELECT 1 FROM public.relacionados_de_registro(h.registro_ente, h.registro_id) r
      WHERE r.rol = t.completa_valor);
  ELSE
    SELECT e.tabla INTO v_tabla FROM public.entes e WHERE e.codigo = h.registro_ente;
    EXECUTE format('SELECT estado::text = $2 FROM public.%I WHERE id = $1', v_tabla)
      INTO v_cumple USING h.registro_id, t.completa_valor;
  END IF;

  IF v_cumple THEN
    UPDATE public.tareas SET estado = 'completada' WHERE id = p_tarea;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_completar_sola(uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 3a. Al llegar el evento
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_completar_pasos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.evento NOT IN ('relacion_alta', 'estado') THEN
    RETURN NULL;
  END IF;

  PERFORM public.tareas_completar_sola(t.id)
  FROM public.tareas t
  JOIN public.tareas_hilos h ON h.id = t.hilo_id
  WHERE h.registro_ente = NEW.ente AND h.registro_id = NEW.registro_id AND h.activo
    AND t.activo AND t.estado = 'pendiente' AND t.completa_evento = NEW.evento
    AND t.completa_valor = NEW.detalle ->> CASE WHEN NEW.evento = 'estado' THEN 'estado' ELSE 'rol' END;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_completar_pasos() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS completar_pasos ON public.eventos;
CREATE TRIGGER completar_pasos
  AFTER INSERT ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.tareas_completar_pasos();

-- ============================================================
-- 3b. Al nacer, al aceptarse y al habilitarse
-- ============================================================
-- Al final, después de propagar: el paso que se completa corre su propia
-- propagación, y con la de afuera avisaría "habilitado" dos veces.
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
  v_habilitado uuid;
BEGIN
  IF NEW.activo AND NEW.estado IN ('solicitada', 'pendiente', 'rechazada') THEN
    UPDATE public.tareas_hilos SET estado = 'abierto' WHERE id = NEW.hilo_id AND estado = 'cerrado';
  END IF;

  <<propagar>>
  BEGIN
    IF TG_OP = 'UPDATE' AND NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
      EXIT propagar;
    END IF;

    v_sig := public.tareas_siguiente_efectivo(NEW.id);
    IF v_sig IS NULL THEN
      EXIT propagar;
    END IF;

    IF TG_OP = 'UPDATE'
       AND OLD.estado IN ('completada', 'cancelada')
       AND NEW.estado IN ('solicitada', 'pendiente', 'rechazada') THEN
      UPDATE public.tareas SET estado = 'pendiente' WHERE id = v_sig AND estado = 'completada';
    END IF;

    v_trababa := CASE
      WHEN TG_OP = 'INSERT' OR OLD.estado = 'cancelada' THEN public.tareas_bloquea(NEW.paso_anterior_id)
      ELSE OLD.estado <> 'completada'
    END;
    v_traba := public.tareas_bloquea(NEW.id);

    IF v_trababa IS DISTINCT FROM v_traba THEN
      UPDATE public.tareas
      SET vence = CASE WHEN v_traba THEN NULL ELSE public.tareas_hoy() + vence_dias END
      WHERE id = v_sig AND vence_dias IS NOT NULL AND estado IN ('solicitada', 'pendiente', 'rechazada');

      IF NOT v_traba OR TG_OP = 'INSERT' THEN
        PERFORM public.notificar(public.tareas_destinatario(t.asignado_id, t.asignado_equipo_id),
          CASE WHEN v_traba THEN 'paso_bloqueado' ELSE 'paso_habilitado' END::tipo_notificacion,
          'tareas', t.id, auth.uid())
        FROM public.tareas t
        WHERE t.id = v_sig AND t.estado IN ('solicitada', 'pendiente');
      END IF;

      IF NOT v_traba THEN
        v_habilitado := v_sig;
      END IF;
    END IF;
  END;

  IF NEW.estado = 'pendiente' AND (TG_OP = 'INSERT' OR OLD.estado IN ('solicitada', 'rechazada')) THEN
    PERFORM public.tareas_completar_sola(NEW.id);
  END IF;
  IF v_habilitado IS NOT NULL THEN
    PERFORM public.tareas_completar_sola(v_habilitado);
  END IF;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_propagar() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 1b. usar_plantilla copia la condición
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_usar_plantilla_de(
  p_plantilla uuid,
  p_titulo    text,
  p_hilo      uuid,
  p_asignados jsonb,
  p_registro  uuid,
  p_usuario   uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p public.tareas_plantillas;
  v_hilo uuid := COALESCE(p_hilo, gen_random_uuid());
  v_tiene text[];
  v_paso public.tareas_plantillas_pasos;
  v_elegido jsonb;
  v_usuario uuid;
  v_equipo uuid;
  v_id uuid;
  v_anterior uuid;
  v_previo uuid;
BEGIN
  SELECT * INTO v_p FROM public.tareas_plantillas p
  WHERE p.id = p_plantilla AND p.activo
    AND (p.dueno_id = p_usuario OR public.usuario_tiene_permiso(p_usuario, 'tareas_administrar'))
    AND public.tareas_puede_ver_plantilla_de(p.dueno_id, p.publicada, p.activo, p.sobre, p_usuario);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La plantilla no existe o no es tuya' USING ERRCODE = 'TA017';
  END IF;

  IF (v_p.sobre IS NULL) <> (p_registro IS NULL)
     OR (p_registro IS NOT NULL AND NOT public.puede_abrir_registro(v_p.sobre, p_registro, p_usuario)) THEN
    RAISE EXCEPTION 'Elegí un registro que veas' USING ERRCODE = 'TA026';
  END IF;

  IF p_hilo IS NULL THEN
    INSERT INTO public.tareas_hilos (id, titulo, responsable_id, registro_ente, registro_id, plantilla_id)
    VALUES (v_hilo, COALESCE(NULLIF(btrim(p_titulo), ''), v_p.nombre), p_usuario,
            v_p.sobre, p_registro, CASE WHEN v_p.sobre IS NOT NULL THEN v_p.id END);
  ELSIF NOT EXISTS (
    SELECT 1 FROM public.tareas_hilos h
    WHERE h.id = p_hilo AND public.tareas_puede_ver_hilo_de(h.id, h.responsable_id, h.equipo_id, h.activo, p_usuario)
  ) THEN
    RAISE EXCEPTION 'El hilo no existe o no lo ves' USING ERRCODE = '42501';
  END IF;

  IF v_p.sobre IS NOT NULL THEN
    v_tiene := ARRAY(SELECT DISTINCT r.rol FROM public.relacionados_de_registro_de(v_p.sobre, p_registro, p_usuario) r);
  END IF;

  FOR v_paso IN
    SELECT * FROM public.tareas_plantillas_pasos
    WHERE plantilla_id = v_p.id AND activo
    ORDER BY orden
  LOOP
    v_previo := CASE WHEN v_paso.espera_anterior THEN v_anterior END;

    -- Un paso que no entra no corta la cadena: el siguiente espera al previo.
    IF v_paso.condicion IS NOT NULL
       AND (ltrim(v_paso.condicion, '!') = ANY (v_tiene)) = (v_paso.condicion LIKE '!%') THEN
      v_anterior := v_previo;
      CONTINUE;
    END IF;

    v_elegido := p_asignados -> v_paso.id::text;
    v_usuario := (v_elegido ->> 'asignado_id')::uuid;
    v_equipo := (v_elegido ->> 'asignado_equipo_id')::uuid;

    IF v_usuario IS NULL AND v_equipo IS NULL THEN
      IF (v_paso.asignado_id IS NOT NULL OR v_paso.asignado_equipo_id IS NOT NULL)
         AND public.tareas_puede_recibir(v_paso.asignado_id, v_paso.asignado_equipo_id) THEN
        v_usuario := v_paso.asignado_id;
        v_equipo := v_paso.asignado_equipo_id;
      ELSE
        v_usuario := p_usuario;
      END IF;
    END IF;

    v_id := gen_random_uuid();

    -- Sumada a un hilo sin registro, la condición no tiene sobre qué leer.
    INSERT INTO public.tareas (id, hilo_id, paso_anterior_id, titulo, descripcion, asignado_id,
                               asignado_equipo_id, prioridad, vence, vence_dias,
                               completa_evento, completa_valor)
    SELECT v_id, v_hilo, v_previo,
           left(public.tareas_plantilla_texto(v_paso.titulo, v_p.sobre, p_registro, p_usuario), 500),
           left(public.tareas_plantilla_texto(v_paso.descripcion, v_p.sobre, p_registro, p_usuario), 5000),
           v_usuario, v_equipo, v_paso.prioridad,
           CASE WHEN v_previo IS NULL THEN public.tareas_hoy() + v_paso.vence_dias END,
           CASE WHEN v_previo IS NOT NULL THEN v_paso.vence_dias END,
           CASE WHEN h.registro_id = p_registro THEN v_paso.completa_evento END,
           CASE WHEN h.registro_id = p_registro THEN v_paso.completa_valor END
    FROM public.tareas_hilos h WHERE h.id = v_hilo;

    v_anterior := v_id;
  END LOOP;

  RETURN v_hilo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_usar_plantilla_de(uuid, text, uuid, jsonb, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 1c. La recurrencia copia la condición
-- ============================================================
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

  INSERT INTO public.tareas_hilos (id, titulo, responsable_id, recurrencia_cantidad, recurrencia_unidad, recurrencia_de,
                                   registro_ente, registro_id, plantilla_id)
  VALUES (v_hilo, NEW.titulo, NEW.responsable_id, NEW.recurrencia_cantidad, NEW.recurrencia_unidad, NEW.id,
          NEW.registro_ente, NEW.registro_id, NEW.plantilla_id);

  FOR p IN
    WITH RECURSIVE cadena AS (
      SELECT t.id, t.paso_anterior_id, t.titulo, t.descripcion, t.asignado_id,
             t.asignado_equipo_id, t.prioridad, t.vence, t.vence_dias,
             t.completa_evento, t.completa_valor, t.created_at AS raiz, 0 AS nivel
      FROM public.tareas t
      WHERE t.hilo_id = NEW.id AND t.activo AND t.paso_anterior_id IS NULL
      UNION ALL
      SELECT t.id, t.paso_anterior_id, t.titulo, t.descripcion, t.asignado_id,
             t.asignado_equipo_id, t.prioridad, t.vence, t.vence_dias,
             t.completa_evento, t.completa_valor, c.raiz, c.nivel + 1
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
                               asignado_equipo_id, prioridad, vence, vence_dias,
                               completa_evento, completa_valor)
    VALUES (v_nuevo, v_hilo, (v_map ->> p.paso_anterior_id::text)::uuid, p.titulo, p.descripcion, p.asignado_id,
            p.asignado_equipo_id, p.prioridad,
            CASE WHEN p.vence_dias IS NULL THEN v_vence END, p.vence_dias,
            p.completa_evento, p.completa_valor);
    v_map := v_map || jsonb_build_object(p.id, v_nuevo);
  END LOOP;

  RETURN NULL;
END;
$$;
