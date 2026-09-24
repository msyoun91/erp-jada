-- sql/112 — tareas: el esquema.
--
-- Tablas, estados, catálogo de permisos, entes y visibilidad. Las reglas
-- (quién escribe qué, transiciones, cadena, pedidos, bajas) son `sql/113`:
-- hasta que corra, solo hay GRANT SELECT y nadie escribe salvo `service_role`,
-- como `sql/104` → `sql/105`. Ficha y decisiones: `decisiones/tareas/`.

-- ============================================================
-- 1. Enums
-- ============================================================
DO $$ BEGIN
  CREATE TYPE estado_hilo AS ENUM ('abierto', 'cerrado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE estado_tarea AS ENUM ('solicitada', 'pendiente', 'rechazada', 'completada', 'cancelada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- En orden: `ORDER BY prioridad DESC` pone arriba lo urgente.
DO $$ BEGIN
  CREATE TYPE prioridad_tarea AS ENUM ('baja', 'media', 'alta');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE recurrencia_unidad AS ENUM ('dia', 'mes');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 2. tareas_hilos — ente `hilo`
-- ============================================================
-- `equipo_id`: el equipo del responsable al crear o transferir, guardado y no
-- calculado (*El equipo participante se guarda en el momento*). NULL si el
-- responsable no tiene equipo.
CREATE TABLE IF NOT EXISTS public.tareas_hilos (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo               text NOT NULL CHECK (length(btrim(titulo)) BETWEEN 1 AND 500),
  responsable_id       uuid NOT NULL REFERENCES public.usuarios(id),
  equipo_id            uuid REFERENCES public.equipos(id),
  estado               estado_hilo NOT NULL DEFAULT 'abierto',
  resultado            text CHECK (length(resultado) <= 5000),
  recurrencia_cantidad int CHECK (recurrencia_cantidad > 0),
  recurrencia_unidad   recurrencia_unidad,
  recurrencia_de       uuid REFERENCES public.tareas_hilos(id),
  activo               boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tareas_hilos_recurrencia_completa
    CHECK ((recurrencia_cantidad IS NULL) = (recurrencia_unidad IS NULL))
);

CREATE INDEX IF NOT EXISTS idx_tareas_hilos_responsable ON public.tareas_hilos (responsable_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_tareas_hilos_equipo ON public.tareas_hilos (equipo_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_tareas_hilos_recurrencia_de ON public.tareas_hilos (recurrencia_de);

DROP TRIGGER IF EXISTS set_updated_at ON public.tareas_hilos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.tareas_hilos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. tareas — ente `tarea`, el paso de un hilo
-- ============================================================
-- Asignado: persona o equipo, exactamente uno. `equipo_id`: el equipo del
-- asignado al asignar (o el equipo asignado), guardado como el del hilo.
--
-- El previo va por FK compuesta con `hilo_id`: mismo hilo sin trigger.
-- DEFERRABLE para *Insertar antes de*, que apunta el siguiente al paso nuevo
-- antes de crearlo (el unique de "no bifurca" no admite el orden inverso).
--
-- `vence_dias`: plazo relativo, solo con previo; `vence` es entonces derivada
-- y la escribe la base al habilitarse el paso (`sql/113`).
CREATE TABLE IF NOT EXISTS public.tareas (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hilo_id            uuid NOT NULL REFERENCES public.tareas_hilos(id),
  paso_anterior_id   uuid,
  titulo             text NOT NULL CHECK (length(btrim(titulo)) BETWEEN 1 AND 500),
  descripcion        text CHECK (length(descripcion) <= 5000),
  asignado_id        uuid REFERENCES public.usuarios(id),
  asignado_equipo_id uuid REFERENCES public.equipos(id),
  equipo_id          uuid REFERENCES public.equipos(id),
  estado             estado_tarea NOT NULL DEFAULT 'pendiente',
  prioridad          prioridad_tarea NOT NULL DEFAULT 'media',
  vence              date,
  vence_dias         int,
  espera_hasta       date,
  espera_motivo      text CHECK (length(espera_motivo) <= 500),
  resultado          text CHECK (length(resultado) <= 5000),
  motivo_rechazo     text CHECK (length(btrim(motivo_rechazo)) BETWEEN 1 AND 2000),
  activo             boolean NOT NULL DEFAULT true,
  -- `clock_timestamp()`: es el orden de los pasos, y una función que crea
  -- varios en una transacción les daría a todos el mismo `now()`.
  created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tareas_id_hilo UNIQUE (id, hilo_id),
  CONSTRAINT tareas_paso_anterior_fk FOREIGN KEY (paso_anterior_id, hilo_id)
    REFERENCES public.tareas (id, hilo_id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT tareas_paso_anterior_distinto CHECK (paso_anterior_id <> id),
  CONSTRAINT tareas_un_asignado CHECK (num_nonnulls(asignado_id, asignado_equipo_id) = 1),
  CONSTRAINT tareas_vence_dias CHECK (vence_dias IS NULL OR (vence_dias > 0 AND paso_anterior_id IS NOT NULL)),
  CONSTRAINT tareas_rechazo_con_motivo CHECK (estado <> 'rechazada' OR motivo_rechazo IS NOT NULL),
  CONSTRAINT tareas_espera_pendiente CHECK (espera_hasta IS NULL OR estado = 'pendiente'),
  CONSTRAINT tareas_espera_motivo CHECK (espera_motivo IS NULL OR espera_hasta IS NOT NULL)
);

-- La cadena no bifurca: un solo siguiente activo por paso.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tareas_siguiente ON public.tareas (paso_anterior_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_tareas_hilo ON public.tareas (hilo_id);
CREATE INDEX IF NOT EXISTS idx_tareas_asignado ON public.tareas (asignado_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_tareas_asignado_equipo ON public.tareas (asignado_equipo_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_tareas_equipo ON public.tareas (equipo_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.tareas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.tareas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. tareas_notas — de hilo (`tarea_id` NULL) o de paso; solo se agregan
-- ============================================================
-- `activo = false` es ocultar (`tareas_administrar`), con quién y cuándo.
CREATE TABLE IF NOT EXISTS public.tareas_notas (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hilo_id      uuid NOT NULL REFERENCES public.tareas_hilos(id),
  tarea_id     uuid,
  autor_id     uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  texto        text NOT NULL CHECK (length(btrim(texto)) BETWEEN 1 AND 5000),
  activo       boolean NOT NULL DEFAULT true,
  ocultada_por uuid REFERENCES public.usuarios(id),
  ocultada_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tareas_notas_tarea_fk FOREIGN KEY (tarea_id, hilo_id) REFERENCES public.tareas (id, hilo_id)
);

CREATE INDEX IF NOT EXISTS idx_tareas_notas_hilo ON public.tareas_notas (hilo_id, created_at);
CREATE INDEX IF NOT EXISTS idx_tareas_notas_tarea ON public.tareas_notas (tarea_id) WHERE tarea_id IS NOT NULL;

DROP TRIGGER IF EXISTS set_updated_at ON public.tareas_notas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.tareas_notas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.tareas_notas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. tareas_ediciones — valor anterior del contenido de hilo y paso
-- ============================================================
-- `eventos` no guarda valor anterior. La escribe un trigger (`sql/113`); nadie
-- inserta, edita ni borra. `activo = false` es ocultar, como en las notas.
CREATE TABLE IF NOT EXISTS public.tareas_ediciones (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hilo_id      uuid NOT NULL REFERENCES public.tareas_hilos(id),
  tarea_id     uuid,
  campo        text NOT NULL,
  anterior     text,
  nuevo        text,
  actor_id     uuid REFERENCES public.usuarios(id),
  activo       boolean NOT NULL DEFAULT true,
  ocultada_por uuid REFERENCES public.usuarios(id),
  ocultada_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tareas_ediciones_tarea_fk FOREIGN KEY (tarea_id, hilo_id) REFERENCES public.tareas (id, hilo_id)
);

CREATE INDEX IF NOT EXISTS idx_tareas_ediciones_hilo ON public.tareas_ediciones (hilo_id, created_at);
CREATE INDEX IF NOT EXISTS idx_tareas_ediciones_tarea ON public.tareas_ediciones (tarea_id) WHERE tarea_id IS NOT NULL;

DROP TRIGGER IF EXISTS set_updated_at ON public.tareas_ediciones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.tareas_ediciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.tareas_ediciones ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 6. Catálogo de permisos
-- ============================================================
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, delegable)
SELECT v.codigo, 'tareas', 'vista', v.nombre, v.orden, v.delegable
FROM (VALUES
  ('tareas_ver',        'Hilos',      1, true),
  ('tareas_mision',     'Misión',     2, true),
  ('tareas_equipo',     'Equipo',     3, false),
  ('tareas_plantillas', 'Plantillas', 4, true),
  ('tareas_todas',      'Todas',      5, false)
) AS v (codigo, nombre, orden, delegable)
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = v.codigo AND s.activo);

INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT f.codigo, 'tareas', 'funcion', f.nombre, 1, v.id, false
FROM (VALUES
  ('tareas_pedir',       'Pedir a otros equipos', 'tareas_ver'),
  ('tareas_administrar', 'Administrar',           'tareas_todas')
) AS f (codigo, nombre, vista)
JOIN public.submodulos v ON v.codigo = f.vista AND v.activo
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = f.codigo AND s.activo);

-- Reglas entre permisos: ficha → *Reglas entre permisos*.
INSERT INTO public.submodulo_reglas (submodulo_id, otro_id, tipo)
SELECT a.id, b.id, 'requiere'
FROM (VALUES
  ('tareas_equipo',      'usuarios_delegar'),
  ('usuarios_delegar',   'tareas_ver'),
  ('usuarios_delegar',   'tareas_equipo'),
  ('tareas_todas',       'tareas_administrar'),
  ('tareas_mision',      'tareas_ver'),
  ('tareas_plantillas',  'tareas_ver'),
  ('tareas_todas',       'tareas_ver'),
  ('tareas_administrar', 'tareas_pedir')
) AS r (submodulo, otro)
JOIN public.submodulos a ON a.codigo = r.submodulo AND a.activo
JOIN public.submodulos b ON b.codigo = r.otro AND b.activo
WHERE NOT EXISTS (
  SELECT 1 FROM public.submodulo_reglas x
  WHERE x.activo AND x.submodulo_id = a.id AND x.otro_id = b.id
);

-- ============================================================
-- 7. designar_delegador / quitar_delegador — `tareas_equipo` va con la delegación
-- ============================================================
-- `usuarios_delegar` y `tareas_equipo` se requieren mutuamente: se dan y se
-- quitan juntas. Ninguna da `tareas_ver`: si falta, el validador diferido
-- falla con US016 y el panel avisa.
CREATE OR REPLACE FUNCTION public.designar_delegador(p_admin uuid, p_usuario uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, otorgada_por, activo)
  SELECT p_usuario, s.id, p_admin, true
  FROM public.submodulos s
  WHERE s.codigo IN ('usuarios_equipo', 'usuarios_delegar', 'tareas_equipo') AND s.activo
  ON CONFLICT (usuario_id, submodulo_id) DO UPDATE
    SET activo = true, otorgada_por = EXCLUDED.otorgada_por
    WHERE NOT public.usuario_submodulos.activo;
END;
$$;

CREATE OR REPLACE FUNCTION public.quitar_delegador(
  p_admin uuid,
  p_saliente uuid,
  p_heredero uuid,
  p_no_copiar uuid[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_equipo uuid := public.equipo_de(p_saliente);
  v_delegar uuid;
  v_vista uuid;
  v_tareas_equipo uuid;
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT id, vista_id INTO v_delegar, v_vista
  FROM public.submodulos WHERE codigo = 'usuarios_delegar' AND activo;
  SELECT id INTO v_tareas_equipo
  FROM public.submodulos WHERE codigo = 'tareas_equipo' AND activo;

  IF v_equipo IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.usuario_submodulos
    WHERE usuario_id = p_saliente AND submodulo_id = v_delegar AND activo
  ) THEN
    RAISE EXCEPTION 'Ese usuario no es el delegador de un equipo' USING ERRCODE = 'US014';
  END IF;

  IF p_heredero IS NOT NULL THEN
    IF p_heredero = p_saliente
       OR public.equipo_de(p_heredero) IS DISTINCT FROM v_equipo
       OR NOT EXISTS (SELECT 1 FROM public.usuarios WHERE id = p_heredero AND activo) THEN
      RAISE EXCEPTION 'El heredero tiene que ser otro miembro activo del mismo equipo' USING ERRCODE = 'US012';
    END IF;
    IF v_delegar = ANY (p_no_copiar) OR v_vista = ANY (p_no_copiar) OR v_tareas_equipo = ANY (p_no_copiar) THEN
      RAISE EXCEPTION 'El heredero recibe siempre la delegación' USING ERRCODE = 'US013';
    END IF;

    -- Lo que el saliente le había delegado al heredero pasa a ser del admin.
    UPDATE public.usuario_submodulos SET otorgada_por = p_admin
    WHERE usuario_id = p_heredero AND otorgada_por = p_saliente AND activo;

    -- El heredero recibe una copia de los permisos del saliente.
    INSERT INTO public.usuario_submodulos (usuario_id, submodulo_id, otorgada_por, activo)
    SELECT p_heredero, submodulo_id, p_admin, true
    FROM public.usuario_submodulos
    WHERE usuario_id = p_saliente AND activo AND submodulo_id <> ALL (p_no_copiar)
    ON CONFLICT (usuario_id, submodulo_id) DO UPDATE
      SET activo = true, otorgada_por = EXCLUDED.otorgada_por
      WHERE NOT public.usuario_submodulos.activo;

    -- Lo que delegó el saliente pasa al heredero...
    UPDATE public.usuario_submodulos SET otorgada_por = p_heredero
    WHERE otorgada_por = p_saliente AND activo;

    -- ...salvo lo que el heredero no tiene: el techo sigue valiendo.
    UPDATE public.usuario_submodulos d SET activo = false
    WHERE d.otorgada_por = p_heredero
      AND d.activo
      AND NOT EXISTS (
        SELECT 1 FROM public.usuario_submodulos h
        WHERE h.usuario_id = p_heredero AND h.submodulo_id = d.submodulo_id AND h.activo
      );
  END IF;

  -- Sin heredero, la cascada revoca todo lo que delegó.
  UPDATE public.usuario_submodulos SET activo = false
  WHERE usuario_id = p_saliente AND submodulo_id IN (v_delegar, v_vista, v_tareas_equipo) AND activo;
END;
$$;

-- ============================================================
-- 8. Visibilidad — la unidad es el hilo
-- ============================================================
-- Ve el hilo: `tareas_administrar` (también desactivado), y con `tareas_ver`
-- sobre un hilo activo, el responsable, el asignado de algún paso activo, o el
-- delegador (`tareas_equipo`) de un equipo participante: el del hilo o el de
-- algún paso. DEFINER: lee `tareas` sin su RLS, que a su vez pregunta por el
-- hilo (42P17). Recibe las columnas del hilo y no el id: en un UPDATE la
-- policy mira la fila nueva (`GUIDE_ENTES.md` §2.3).
CREATE OR REPLACE FUNCTION public.tareas_puede_ver_hilo_de(
  p_hilo uuid, p_responsable uuid, p_equipo uuid, p_activo boolean, p_usuario uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'tareas_administrar')
    OR (
      p_activo
      AND public.usuario_tiene_permiso(p_usuario, 'tareas_ver')
      AND (
        p_responsable = p_usuario
        OR EXISTS (
          SELECT 1 FROM public.tareas t
          WHERE t.hilo_id = p_hilo AND t.activo AND t.asignado_id = p_usuario
        )
        OR (
          public.usuario_tiene_permiso(p_usuario, 'tareas_equipo')
          AND (
            p_equipo = public.equipo_de(p_usuario)
            OR EXISTS (
              SELECT 1 FROM public.tareas t
              WHERE t.hilo_id = p_hilo AND t.activo AND t.equipo_id = public.equipo_de(p_usuario)
            )
          )
        )
      )
    );
$$;

-- Un paso se ve si se ve su hilo; desactivado, solo con `tareas_administrar`.
CREATE OR REPLACE FUNCTION public.tareas_puede_ver_tarea_de(p_hilo uuid, p_activo boolean, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
      SELECT 1 FROM public.tareas_hilos h
      WHERE h.id = p_hilo
        AND public.tareas_puede_ver_hilo_de(h.id, h.responsable_id, h.equipo_id, h.activo, p_usuario)
    )
    AND (p_activo OR public.usuario_tiene_permiso(p_usuario, 'tareas_administrar'));
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_hilo_de(uuid, uuid, uuid, boolean, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_tarea_de(uuid, boolean, uuid) FROM PUBLIC, anon, authenticated;

-- Envoltorios con `auth.uid()` para las policies.
CREATE OR REPLACE FUNCTION public.tareas_puede_ver_hilo(p_hilo uuid, p_responsable uuid, p_equipo uuid, p_activo boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.tareas_puede_ver_hilo_de(p_hilo, p_responsable, p_equipo, p_activo, auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.tareas_puede_ver_tarea(p_hilo uuid, p_activo boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.tareas_puede_ver_tarea_de(p_hilo, p_activo, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_hilo(uuid, uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_puede_ver_hilo(uuid, uuid, uuid, boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.tareas_puede_ver_tarea(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_puede_ver_tarea(uuid, boolean) TO authenticated;

DROP POLICY IF EXISTS tareas_hilos_select ON public.tareas_hilos;
CREATE POLICY tareas_hilos_select ON public.tareas_hilos FOR SELECT TO authenticated
  USING (tareas_puede_ver_hilo(id, responsable_id, equipo_id, activo));

DROP POLICY IF EXISTS tareas_select ON public.tareas;
CREATE POLICY tareas_select ON public.tareas FOR SELECT TO authenticated
  USING (tareas_puede_ver_tarea(hilo_id, activo));

-- Notas e historial: los del hilo que se ve. EXISTS con la RLS del hilo, que no
-- mira hacia acá. Lo oculto, solo `tareas_administrar`.
DROP POLICY IF EXISTS tareas_notas_select ON public.tareas_notas;
CREATE POLICY tareas_notas_select ON public.tareas_notas FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tareas_hilos h WHERE h.id = hilo_id)
    AND (activo OR tiene_permiso('tareas_administrar'))
  );

DROP POLICY IF EXISTS tareas_ediciones_select ON public.tareas_ediciones;
CREATE POLICY tareas_ediciones_select ON public.tareas_ediciones FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.tareas_hilos h WHERE h.id = hilo_id)
    AND (activo OR tiene_permiso('tareas_administrar'))
  );

GRANT SELECT ON public.tareas_hilos, public.tareas, public.tareas_notas, public.tareas_ediciones TO authenticated;

-- ============================================================
-- 9. Entes y eventos
-- ============================================================
-- Emiten, no disparan: una plantilla disparada por un hilo crearía otro hilo.
INSERT INTO public.entes (codigo, modulo, submodulo, estados, datos, ruta, tabla, disparos)
VALUES
  ('hilo',  'tareas', 'tareas_ver', 'estado_hilo',  '{titulo}', '/tareas/{id}',      'public.tareas_hilos', '{}'),
  ('tarea', 'tareas', 'tareas_ver', 'estado_tarea', '{titulo}', '/tareas/paso/{id}', 'public.tareas',       '{}')
ON CONFLICT (codigo) DO NOTHING;

-- La rama de tareas: el título si quien pregunta lo ve (la RLS decide).
CREATE OR REPLACE FUNCTION public.tareas_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'hilo'  THEN (SELECT titulo FROM public.tareas_hilos WHERE id = p_id)
    WHEN 'tarea' THEN (SELECT titulo FROM public.tareas WHERE id = p_id)
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_etiqueta(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_etiqueta(text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.etiqueta_registro(p_ente text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE e.modulo
    WHEN 'tareas' THEN public.tareas_etiqueta(p_ente, p_id)
  END
  FROM public.entes e
  WHERE e.codigo = p_ente;
$$;

DROP TRIGGER IF EXISTS emitir_eventos ON public.tareas_hilos;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado ON public.tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('hilo');

DROP TRIGGER IF EXISTS emitir_eventos ON public.tareas;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('tarea');
