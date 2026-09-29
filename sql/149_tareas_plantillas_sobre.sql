-- sql/149 — tareas, tramo 5, paso 2: "Sobre", disparo, condición y "se
-- completa cuando" en la plantilla; registro y plantilla en el hilo.
--
-- Solo columnas y su validez. Leerlas (`usar_plantilla` con registro, el
-- disparo, los pasos que se completan solos) viene en los pasos siguientes.
--
--   1. Una marca vale para un ente: `tareas_plantilla_vale(sobre, evento,
--      valor)` — rol de `entes.roles` o estado del enum de `entes.estados`.
--   2. `tareas_plantillas`: `sobre`, `disparo_evento`, `disparo_estado`,
--      `disparo_activo`. Sin tabla de activaciones: toda plantilla es de su
--      dueño, y la activa solo él (TA025).
--   3. `tareas_plantillas_pasos`: `condicion` (`rol` / `!rol`) y
--      `completa_evento` + `completa_valor` (`relacion_alta` + rol o
--      `estado` + valor, la misma forma que el disparo).
--   4. Sin el submódulo del ente, la plantilla no se ve ni se arma con ese
--      "Sobre" (TA023); `tareas_administrar` la ve igual. La regla vive en
--      `tareas_puede_ver_plantilla_de`, que usan la policy y `tareas_nombres`.
--   5. `guardar_plantilla` y `copiar_plantilla` con las columnas nuevas; la
--      copia trae el disparo apagado.
--   6. `tareas_hilos`: `registro_ente`, `registro_id`, `plantilla_id` —
--      los tres o ninguno, fuera de los GRANT. La recurrencia los copia.
--
-- Decisiones: `decisiones/tareas/catalogo.md` → *La plantilla dice "Sobre"*,
-- *La activación va en la plantilla*, *Marcas de rol sin ente*, *El hilo
-- guarda su registro*, *Sin el submódulo del ente*; `BACKLOG.md` → *Pasos que
-- se completan solos*.

-- ============================================================
-- 1. Una marca vale para un ente
-- ============================================================
-- `alta` no lleva valor; `relacion_alta`, un rol del ente; `estado`, un valor
-- de su enum. Sin RLS de `entes`: la llaman triggers DEFINER.
CREATE OR REPLACE FUNCTION public.tareas_plantilla_vale(p_sobre text, p_evento public.tipo_evento, p_valor text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.entes e
    WHERE e.codigo = p_sobre
      AND CASE p_evento
        WHEN 'alta'          THEN p_valor IS NULL
        WHEN 'relacion_alta' THEN p_valor = ANY (e.roles)
        WHEN 'estado'        THEN EXISTS (SELECT 1 FROM pg_enum x WHERE x.enumtypid = e.estados AND x.enumlabel = p_valor)
        ELSE false
      END
  );
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantilla_vale(text, public.tipo_evento, text) FROM PUBLIC, anon, authenticated;

-- Un paso vale para el "Sobre" de su plantilla: sin "Sobre", sin marcas.
CREATE OR REPLACE FUNCTION public.tareas_plantillas_paso_vale(p_sobre text, p_condicion text,
                                                             p_completa_evento public.tipo_evento, p_completa_valor text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (p_condicion IS NULL OR public.tareas_plantilla_vale(p_sobre, 'relacion_alta', ltrim(p_condicion, '!')))
     AND (p_completa_evento IS NULL OR public.tareas_plantilla_vale(p_sobre, p_completa_evento, p_completa_valor));
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantillas_paso_vale(text, text, public.tipo_evento, text) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 2. y 3. Columnas
-- ============================================================
ALTER TABLE public.tareas_plantillas
  ADD COLUMN sobre text REFERENCES public.entes (codigo),
  ADD COLUMN disparo_evento public.tipo_evento,
  ADD COLUMN disparo_estado text,
  ADD COLUMN disparo_activo boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT tareas_plantillas_disparo_evento CHECK (disparo_evento IN ('alta', 'estado')),
  ADD CONSTRAINT tareas_plantillas_disparo_estado CHECK ((disparo_evento IS NOT DISTINCT FROM 'estado') = (disparo_estado IS NOT NULL)),
  ADD CONSTRAINT tareas_plantillas_disparo_activo CHECK (NOT disparo_activo OR disparo_evento IS NOT NULL);

ALTER TABLE public.tareas_plantillas_pasos
  ADD COLUMN condicion text,
  ADD COLUMN completa_evento public.tipo_evento,
  ADD COLUMN completa_valor text,
  ADD CONSTRAINT tareas_plantillas_pasos_condicion CHECK (condicion ~ '^!?[a-z_]+$'),
  ADD CONSTRAINT tareas_plantillas_pasos_completa_evento CHECK (completa_evento IN ('relacion_alta', 'estado')),
  ADD CONSTRAINT tareas_plantillas_pasos_completa CHECK ((completa_evento IS NULL) = (completa_valor IS NULL));

-- "Sobre" solo con el ente a la vista; cambiarlo no deja pasos que no le
-- valen; el disparo es uno de `entes.disparos`; activarlo, del dueño.
CREATE OR REPLACE FUNCTION public.tareas_plantillas_sobre()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.sobre IS DISTINCT FROM OLD.sobre THEN
    IF NEW.sobre IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.entes e
      WHERE e.codigo = NEW.sobre AND e.activo AND public.usuario_tiene_permiso(auth.uid(), e.submodulo)
    ) THEN
      RAISE EXCEPTION 'No ves ese ente' USING ERRCODE = 'TA023';
    END IF;

    IF TG_OP = 'UPDATE' AND EXISTS (
      SELECT 1 FROM public.tareas_plantillas_pasos p
      WHERE p.plantilla_id = NEW.id AND p.activo
        AND NOT public.tareas_plantillas_paso_vale(NEW.sobre, p.condicion, p.completa_evento, p.completa_valor)
    ) THEN
      RAISE EXCEPTION 'Un paso no vale para ese ente' USING ERRCODE = 'TA024';
    END IF;
  END IF;

  IF NEW.disparo_evento IS NOT NULL AND NOT (
    EXISTS (SELECT 1 FROM public.entes e WHERE e.codigo = NEW.sobre AND NEW.disparo_evento = ANY (e.disparos))
    AND public.tareas_plantilla_vale(NEW.sobre, NEW.disparo_evento, NEW.disparo_estado)
  ) THEN
    RAISE EXCEPTION 'Ese disparo no vale para el ente' USING ERRCODE = 'TA024';
  END IF;

  IF NEW.disparo_activo AND (TG_OP = 'INSERT' OR NOT OLD.disparo_activo)
     AND NEW.dueno_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Activar el disparo es de su dueño' USING ERRCODE = 'TA025';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantillas_sobre() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER tareas_plantillas_sobre
  BEFORE INSERT OR UPDATE OF sobre, disparo_evento, disparo_estado, disparo_activo ON public.tareas_plantillas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_plantillas_sobre();

-- Los pasos solo se insertan (guardar reemplaza): se validan al nacer.
CREATE OR REPLACE FUNCTION public.tareas_plantillas_pasos_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.tareas_plantillas_paso_vale(
    (SELECT sobre FROM public.tareas_plantillas WHERE id = NEW.plantilla_id),
    NEW.condicion, NEW.completa_evento, NEW.completa_valor
  ) THEN
    RAISE EXCEPTION 'Un paso no vale para el ente de la plantilla' USING ERRCODE = 'TA024';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantillas_pasos_validar() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER tareas_plantillas_pasos_validar
  BEFORE INSERT ON public.tareas_plantillas_pasos
  FOR EACH ROW EXECUTE FUNCTION public.tareas_plantillas_pasos_validar();

GRANT INSERT (sobre, disparo_evento, disparo_estado, disparo_activo) ON public.tareas_plantillas TO authenticated;
GRANT UPDATE (sobre, disparo_evento, disparo_estado, disparo_activo) ON public.tareas_plantillas TO authenticated;
GRANT INSERT (condicion, completa_evento, completa_valor) ON public.tareas_plantillas_pasos TO authenticated;

-- ============================================================
-- 4. Quién ve una plantilla
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_puede_ver_plantilla_de(p_dueno uuid, p_publicada boolean, p_activo boolean,
                                                               p_sobre text, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'tareas_administrar')
      OR (public.usuario_tiene_permiso(p_usuario, 'tareas_plantillas')
          AND (p_dueno = p_usuario OR (p_publicada AND p_activo))
          AND (p_sobre IS NULL OR EXISTS (
            SELECT 1 FROM public.entes e
            WHERE e.codigo = p_sobre AND e.activo AND public.usuario_tiene_permiso(p_usuario, e.submodulo)
          )));
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_plantilla_de(uuid, boolean, boolean, text, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.tareas_puede_ver_plantilla(p_dueno uuid, p_publicada boolean, p_activo boolean, p_sobre text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.tareas_puede_ver_plantilla_de(p_dueno, p_publicada, p_activo, p_sobre, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_plantilla(uuid, boolean, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_puede_ver_plantilla(uuid, boolean, boolean, text) TO authenticated;

DROP POLICY IF EXISTS tareas_plantillas_select ON public.tareas_plantillas;
CREATE POLICY tareas_plantillas_select ON public.tareas_plantillas FOR SELECT TO authenticated
  USING (tareas_puede_ver_plantilla(dueno_id, publicada, activo, sobre));

CREATE OR REPLACE FUNCTION public.tareas_nombres()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH yo AS (
    SELECT auth.uid() AS id, public.tiene_permiso('tareas_administrar') AS adm
  ),
  h AS (
    SELECT h.id, h.responsable_id
    FROM tareas_hilos h, yo
    WHERE public.tareas_puede_ver_hilo_de(h.id, h.responsable_id, h.equipo_id, h.activo, yo.id)
  ),
  t AS (
    SELECT t.asignado_id, t.asignado_equipo_id
    FROM tareas t JOIN h ON h.id = t.hilo_id, yo
    WHERE t.activo OR yo.adm
  ),
  n AS (
    SELECT n.autor_id, n.ocultada_por
    FROM tareas_notas n JOIN h ON h.id = n.hilo_id, yo
    WHERE n.activo OR yo.adm
  ),
  e AS (
    SELECT e.actor_id, e.ocultada_por
    FROM tareas_ediciones e JOIN h ON h.id = e.hilo_id, yo
    WHERE e.activo OR yo.adm
  ),
  p AS (
    SELECT p.id, p.dueno_id
    FROM tareas_plantillas p, yo
    WHERE public.tareas_puede_ver_plantilla_de(p.dueno_id, p.publicada, p.activo, p.sobre, yo.id)
  ),
  refs AS (
    SELECT responsable_id AS id FROM h
    UNION SELECT asignado_id FROM t
    UNION SELECT asignado_equipo_id FROM t
    UNION SELECT autor_id FROM n
    UNION SELECT ocultada_por FROM n
    UNION SELECT actor_id FROM e
    UNION SELECT ocultada_por FROM e
    UNION SELECT dueno_id FROM p
    UNION SELECT pp.asignado_id FROM tareas_plantillas_pasos pp JOIN p ON p.id = pp.plantilla_id WHERE pp.activo
    UNION SELECT pp.asignado_equipo_id FROM tareas_plantillas_pasos pp JOIN p ON p.id = pp.plantilla_id WHERE pp.activo
  )
  SELECT u.id, u.nombre FROM usuarios u JOIN refs r ON r.id = u.id
  WHERE public.tiene_permiso('tareas_ver')
  UNION ALL
  SELECT q.id, q.nombre FROM equipos q JOIN refs r ON r.id = q.id
  WHERE public.tiene_permiso('tareas_ver');
$$;

-- ============================================================
-- 5. Guardar y copiar
-- ============================================================
-- La firma cambia: se reemplaza. Los parámetros nuevos tienen default, así
-- que quien la llamaba sin "Sobre" sigue igual. Los pasos viejos se apagan
-- antes de tocar la plantilla: cambiar "Sobre" no choca con ellos (TA024).
DROP FUNCTION IF EXISTS public.guardar_plantilla(uuid, text, text, jsonb);

-- Crea (`p_id` NULL) o edita. Guardar reemplaza los pasos: nada los referencia.
-- `p_pasos`: [{titulo, descripcion, asignado_id, asignado_equipo_id,
-- prioridad, vence_dias, espera_anterior, condicion, completa_evento,
-- completa_valor}], en orden.
CREATE OR REPLACE FUNCTION public.guardar_plantilla(
  p_id             uuid,
  p_nombre         text,
  p_descripcion    text,
  p_pasos          jsonb,
  p_sobre          text DEFAULT NULL,
  p_disparo_evento public.tipo_evento DEFAULT NULL,
  p_disparo_estado text DEFAULT NULL,
  p_disparo_activo boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := COALESCE(p_id, gen_random_uuid());
BEGIN
  IF jsonb_array_length(COALESCE(p_pasos, '[]')) = 0 THEN
    RAISE EXCEPTION 'Una plantilla necesita al menos un paso' USING ERRCODE = 'TA020';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.tareas_plantillas (id, nombre, descripcion, sobre, disparo_evento, disparo_estado, disparo_activo)
    VALUES (v_id, p_nombre, p_descripcion, p_sobre, p_disparo_evento, p_disparo_estado, p_disparo_activo);
  ELSE
    UPDATE public.tareas_plantillas_pasos SET activo = false WHERE plantilla_id = v_id AND activo;

    UPDATE public.tareas_plantillas
    SET nombre = p_nombre, descripcion = p_descripcion, sobre = p_sobre, disparo_evento = p_disparo_evento,
        disparo_estado = p_disparo_estado, disparo_activo = p_disparo_activo
    WHERE id = p_id AND activo;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La plantilla no existe o no es tuya' USING ERRCODE = 'TA017';
    END IF;
  END IF;

  INSERT INTO public.tareas_plantillas_pasos (plantilla_id, orden, espera_anterior, titulo, descripcion,
                                              asignado_id, asignado_equipo_id, prioridad, vence_dias,
                                              condicion, completa_evento, completa_valor)
  SELECT v_id, a.o, COALESCE(p.espera_anterior, true), p.titulo, p.descripcion,
         p.asignado_id, p.asignado_equipo_id, COALESCE(p.prioridad, 'media'), p.vence_dias,
         p.condicion, p.completa_evento, p.completa_valor
  FROM jsonb_array_elements(p_pasos) WITH ORDINALITY AS a (e, o),
       jsonb_populate_record(NULL::public.tareas_plantillas_pasos, a.e) AS p;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, jsonb, text, public.tipo_evento, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, jsonb, text, public.tipo_evento, text, boolean) TO authenticated;

-- Del Catálogo a Mis plantillas: sin asignados fijos, sin publicar, con el
-- disparo apagado; "Sobre", condiciones y "se completa cuando", tal cual.
CREATE OR REPLACE FUNCTION public.copiar_plantilla(p_plantilla uuid)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_p public.tareas_plantillas;
BEGIN
  SELECT * INTO v_p FROM public.tareas_plantillas WHERE id = p_plantilla AND activo AND publicada;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La plantilla no está en el Catálogo' USING ERRCODE = 'TA017';
  END IF;

  INSERT INTO public.tareas_plantillas (id, nombre, descripcion, copiada_de, sobre, disparo_evento, disparo_estado)
  VALUES (v_id, v_p.nombre, v_p.descripcion, v_p.id, v_p.sobre, v_p.disparo_evento, v_p.disparo_estado);

  INSERT INTO public.tareas_plantillas_pasos (plantilla_id, orden, espera_anterior, titulo, descripcion,
                                              prioridad, vence_dias, condicion, completa_evento, completa_valor)
  SELECT v_id, orden, espera_anterior, titulo, descripcion, prioridad, vence_dias,
         condicion, completa_evento, completa_valor
  FROM public.tareas_plantillas_pasos
  WHERE plantilla_id = v_p.id AND activo;

  RETURN v_id;
END;
$$;

-- ============================================================
-- 6. El hilo guarda su registro y su plantilla
-- ============================================================
-- Solo si nació de una plantilla con "Sobre". Fuera de los GRANT: lo escriben
-- `usar_plantilla` (paso siguiente) y la recurrencia, ambas DEFINER.
ALTER TABLE public.tareas_hilos
  ADD COLUMN registro_ente text REFERENCES public.entes (codigo),
  ADD COLUMN registro_id uuid,
  ADD COLUMN plantilla_id uuid REFERENCES public.tareas_plantillas (id),
  ADD CONSTRAINT tareas_hilos_registro CHECK (num_nonnulls(registro_ente, registro_id, plantilla_id) IN (0, 3));

-- "No se repite": hay un hilo activo de esta plantilla sobre este registro.
CREATE INDEX idx_tareas_hilos_plantilla_registro ON public.tareas_hilos (plantilla_id, registro_id) WHERE activo;
CREATE INDEX idx_tareas_hilos_registro ON public.tareas_hilos (registro_ente, registro_id) WHERE activo;

-- Copia los pasos activos —completados y cancelados, que en un hilo cerrado
-- son todos— con título, descripción, cadena, asignado final y prioridad,
-- sin lo hecho, de la raíz a la cola de cada cadena. El vencimiento se corre
-- por el intervalo desde el anterior, fin de mes sigue siendo fin de mes; el
-- relativo al previo se copia tal cual. Estado y equipo, con las reglas de
-- hoy. Si el responsable ya no puede recibir, no hay siguiente: el cierre no
-- falla por eso. El registro y la plantilla siguen al ciclo (`sql/149`).
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
