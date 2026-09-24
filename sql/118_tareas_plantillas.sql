-- sql/118 — tareas: plantillas personales y Catálogo.
--
-- Toda plantilla es de su dueño: la ve, la edita y la usa él (y el admin).
-- Publicarla la pone en el Catálogo, donde se lee y se copia; nunca se usa
-- lo ajeno directo. La copia es independiente: sin asignados fijos, con
-- `copiada_de` como historia.
-- Usarla crea un hilo o suma pasos a uno existente, con INSERT comunes: las
-- reglas son las de siempre (`sql/113`), y un pedido sin `tareas_pedir` falla.
-- Un fijo que ya no puede recibir se trata como paso vacío: el elegido al
-- usarla, o quien la usa.
-- `{dato}`, condiciones por rol y disparo esperan al primer emisor: sin un
-- registro no tienen de dónde leer.
-- Decisión: `decisiones/tareas/catalogo.md`. Verificado con
-- `sql/tests/tareas_plantillas.sql`.

-- ============================================================
-- 1. Tablas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.tareas_plantillas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 500),
  descripcion text CHECK (length(descripcion) <= 5000),
  dueno_id    uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  publicada   boolean NOT NULL DEFAULT false,
  copiada_de  uuid REFERENCES public.tareas_plantillas(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_dueno ON public.tareas_plantillas (dueno_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_publicada ON public.tareas_plantillas (created_at) WHERE activo AND publicada;

DROP TRIGGER IF EXISTS set_updated_at ON public.tareas_plantillas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.tareas_plantillas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.tareas_plantillas ENABLE ROW LEVEL SECURITY;

-- `espera_anterior`: el paso sigue al de `orden` anterior; en el primero no
-- cuenta. Así la plantilla solo arma cadenas sin bifurcar, como el hilo.
CREATE TABLE IF NOT EXISTS public.tareas_plantillas_pasos (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_id       uuid NOT NULL REFERENCES public.tareas_plantillas(id),
  orden              int NOT NULL,
  espera_anterior    boolean NOT NULL DEFAULT true,
  titulo             text NOT NULL CHECK (length(btrim(titulo)) BETWEEN 1 AND 500),
  descripcion        text CHECK (length(descripcion) <= 5000),
  asignado_id        uuid REFERENCES public.usuarios(id),
  asignado_equipo_id uuid REFERENCES public.equipos(id),
  prioridad          prioridad_tarea NOT NULL DEFAULT 'media',
  vence_dias         int CHECK (vence_dias > 0),
  activo             boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tareas_plantillas_pasos_un_asignado CHECK (num_nonnulls(asignado_id, asignado_equipo_id) <= 1)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tareas_plantillas_pasos_orden
  ON public.tareas_plantillas_pasos (plantilla_id, orden) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.tareas_plantillas_pasos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.tareas_plantillas_pasos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.tareas_plantillas_pasos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2. Policies y GRANT
-- ============================================================
-- El dueño ve también las desactivadas (desactivar no lo saca de su vista).
DROP POLICY IF EXISTS tareas_plantillas_select ON public.tareas_plantillas;
CREATE POLICY tareas_plantillas_select ON public.tareas_plantillas FOR SELECT TO authenticated
  USING (
    tiene_permiso('tareas_administrar')
    OR (tiene_permiso('tareas_plantillas') AND (dueno_id = (select auth.uid()) OR (publicada AND activo)))
  );

DROP POLICY IF EXISTS tareas_plantillas_insert ON public.tareas_plantillas;
CREATE POLICY tareas_plantillas_insert ON public.tareas_plantillas FOR INSERT TO authenticated
  WITH CHECK (dueno_id = (select auth.uid()) AND tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_update ON public.tareas_plantillas;
CREATE POLICY tareas_plantillas_update ON public.tareas_plantillas FOR UPDATE TO authenticated
  USING (
    tiene_permiso('tareas_administrar')
    OR (dueno_id = (select auth.uid()) AND tiene_permiso('tareas_plantillas'))
  )
  WITH CHECK (true);

DROP POLICY IF EXISTS tareas_plantillas_pasos_select ON public.tareas_plantillas_pasos;
CREATE POLICY tareas_plantillas_pasos_select ON public.tareas_plantillas_pasos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.tareas_plantillas p WHERE p.id = plantilla_id));

DROP POLICY IF EXISTS tareas_plantillas_pasos_insert ON public.tareas_plantillas_pasos;
CREATE POLICY tareas_plantillas_pasos_insert ON public.tareas_plantillas_pasos FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.tareas_plantillas p
    WHERE p.id = plantilla_id
      AND (p.dueno_id = (select auth.uid()) OR tiene_permiso('tareas_administrar'))
  ));

DROP POLICY IF EXISTS tareas_plantillas_pasos_update ON public.tareas_plantillas_pasos;
CREATE POLICY tareas_plantillas_pasos_update ON public.tareas_plantillas_pasos FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.tareas_plantillas p
    WHERE p.id = plantilla_id
      AND (p.dueno_id = (select auth.uid()) OR tiene_permiso('tareas_administrar'))
  ))
  WITH CHECK (true);

GRANT SELECT ON public.tareas_plantillas, public.tareas_plantillas_pasos TO authenticated;
GRANT INSERT (id, nombre, descripcion, copiada_de) ON public.tareas_plantillas TO authenticated;
GRANT UPDATE (nombre, descripcion, publicada, activo) ON public.tareas_plantillas TO authenticated;
GRANT INSERT (id, plantilla_id, orden, espera_anterior, titulo, descripcion, asignado_id,
              asignado_equipo_id, prioridad, vence_dias)
  ON public.tareas_plantillas_pasos TO authenticated;
GRANT UPDATE (activo) ON public.tareas_plantillas_pasos TO authenticated;

-- ============================================================
-- 3. Publicar es del dueño; reactivar, del admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_plantillas_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.publicada AND NOT OLD.publicada AND NEW.dueno_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Publicar una plantilla es de su dueño' USING ERRCODE = 'TA018';
  END IF;

  IF NEW.activo AND NOT OLD.activo AND NOT public.usuario_tiene_permiso(auth.uid(), 'tareas_administrar') THEN
    RAISE EXCEPTION 'Solo el admin reactiva una plantilla' USING ERRCODE = 'TA019';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantillas_al_editar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_plantillas_al_editar ON public.tareas_plantillas;
CREATE TRIGGER tareas_plantillas_al_editar
  BEFORE UPDATE OF publicada, activo ON public.tareas_plantillas
  FOR EACH ROW EXECUTE FUNCTION public.tareas_plantillas_al_editar();

-- ============================================================
-- 4. Escrituras — INVOKER, la RLS decide
-- ============================================================
-- `usar_plantilla` calcula el vencimiento del primer paso de cada cadena.
GRANT EXECUTE ON FUNCTION public.tareas_hoy() TO authenticated;

-- Crea (`p_id` NULL) o edita. Guardar reemplaza los pasos: nada los referencia.
-- `p_pasos`: [{titulo, descripcion, asignado_id, asignado_equipo_id,
-- prioridad, vence_dias, espera_anterior}], en orden.
CREATE OR REPLACE FUNCTION public.guardar_plantilla(
  p_id          uuid,
  p_nombre      text,
  p_descripcion text,
  p_pasos       jsonb
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
    INSERT INTO public.tareas_plantillas (id, nombre, descripcion)
    VALUES (v_id, p_nombre, p_descripcion);
  ELSE
    UPDATE public.tareas_plantillas SET nombre = p_nombre, descripcion = p_descripcion
    WHERE id = p_id AND activo;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La plantilla no existe o no es tuya' USING ERRCODE = 'TA017';
    END IF;

    UPDATE public.tareas_plantillas_pasos SET activo = false WHERE plantilla_id = v_id AND activo;
  END IF;

  INSERT INTO public.tareas_plantillas_pasos (plantilla_id, orden, espera_anterior, titulo, descripcion,
                                              asignado_id, asignado_equipo_id, prioridad, vence_dias)
  SELECT v_id, a.o, COALESCE(p.espera_anterior, true), p.titulo, p.descripcion,
         p.asignado_id, p.asignado_equipo_id, COALESCE(p.prioridad, 'media'), p.vence_dias
  FROM jsonb_array_elements(p_pasos) WITH ORDINALITY AS a (e, o),
       jsonb_populate_record(NULL::public.tareas_plantillas_pasos, a.e) AS p;

  RETURN v_id;
END;
$$;

-- Del Catálogo a Mis plantillas: sin asignados fijos, sin publicar.
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

  INSERT INTO public.tareas_plantillas (id, nombre, descripcion, copiada_de)
  VALUES (v_id, v_p.nombre, v_p.descripcion, v_p.id);

  INSERT INTO public.tareas_plantillas_pasos (plantilla_id, orden, espera_anterior, titulo, descripcion,
                                              prioridad, vence_dias)
  SELECT v_id, orden, espera_anterior, titulo, descripcion, prioridad, vence_dias
  FROM public.tareas_plantillas_pasos
  WHERE plantilla_id = v_p.id AND activo;

  RETURN v_id;
END;
$$;

-- Crea un hilo (`p_hilo` NULL; título `p_titulo` o el nombre) o suma los
-- pasos a `p_hilo`, en paralelo con lo que ya tiene. `p_asignados`:
-- {paso_id: {asignado_id | asignado_equipo_id}}, lo elegido al usarla.
-- Asignado: el elegido; si no, el fijo si puede recibir; si no, quien la usa.
CREATE OR REPLACE FUNCTION public.usar_plantilla(
  p_plantilla uuid,
  p_titulo    text DEFAULT NULL,
  p_hilo      uuid DEFAULT NULL,
  p_asignados jsonb DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_p public.tareas_plantillas;
  v_hilo uuid := COALESCE(p_hilo, gen_random_uuid());
  v_paso public.tareas_plantillas_pasos;
  v_elegido jsonb;
  v_usuario uuid;
  v_equipo uuid;
  v_id uuid;
  v_anterior uuid;
  v_previo uuid;
BEGIN
  SELECT * INTO v_p FROM public.tareas_plantillas
  WHERE id = p_plantilla AND activo
    AND (dueno_id = v_uid OR tiene_permiso('tareas_administrar'));
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La plantilla no existe o no es tuya' USING ERRCODE = 'TA017';
  END IF;

  IF p_hilo IS NULL THEN
    INSERT INTO public.tareas_hilos (id, titulo)
    VALUES (v_hilo, COALESCE(NULLIF(btrim(p_titulo), ''), v_p.nombre));
  END IF;

  FOR v_paso IN
    SELECT * FROM public.tareas_plantillas_pasos
    WHERE plantilla_id = v_p.id AND activo
    ORDER BY orden
  LOOP
    v_elegido := p_asignados -> v_paso.id::text;
    v_usuario := (v_elegido ->> 'asignado_id')::uuid;
    v_equipo := (v_elegido ->> 'asignado_equipo_id')::uuid;

    IF v_usuario IS NULL AND v_equipo IS NULL THEN
      IF EXISTS (
        SELECT 1 FROM public.tareas_asignables() a
        WHERE a.puede_recibir
          AND (a.usuario_id = v_paso.asignado_id OR a.equipo_id = v_paso.asignado_equipo_id)
      ) THEN
        v_usuario := v_paso.asignado_id;
        v_equipo := v_paso.asignado_equipo_id;
      ELSE
        v_usuario := v_uid;
      END IF;
    END IF;

    v_previo := CASE WHEN v_paso.espera_anterior THEN v_anterior END;
    v_id := gen_random_uuid();

    INSERT INTO public.tareas (id, hilo_id, paso_anterior_id, titulo, descripcion, asignado_id,
                               asignado_equipo_id, prioridad, vence, vence_dias)
    VALUES (v_id, v_hilo, v_previo, v_paso.titulo, v_paso.descripcion, v_usuario, v_equipo,
            v_paso.prioridad,
            CASE WHEN v_previo IS NULL THEN public.tareas_hoy() + v_paso.vence_dias END,
            CASE WHEN v_previo IS NOT NULL THEN v_paso.vence_dias END);

    v_anterior := v_id;
  END LOOP;

  RETURN v_hilo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_plantilla(uuid, text, text, jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.copiar_plantilla(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.copiar_plantilla(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.usar_plantilla(uuid, text, uuid, jsonb) TO authenticated;
