-- sql/126 — obras, tramo 1: la obra, sus participantes y sus reglas.
--
-- Esquema, permisos, ver y trabajar, estados con motivo de pérdida y
-- reversión, transferir y desactivar, y el ente `obra` con sus ramas en las
-- genéricas. Los contactos de la obra son de Contactos (`sql/127`); el alta
-- con "¿Quién?", `sql/128`. Quedan para los tramos siguientes: bajas y
-- huérfanas, congelado y "Por aprobar", comisión, widget y campanitas.
-- Ficha y decisiones: `decisiones/obras.md`. Verificado con
-- `sql/tests/obras_reglas.sql`.
--
-- Directo o sistema, como Tareas (`sql/113`): las reglas de quién hace qué
-- valen a `pg_trigger_depth() = 1` con `auth.uid()`; lo que escribe un
-- trigger en cascada solo respeta las invariantes. Mensajes con clase `OB`.

-- ============================================================
-- 1. Enums
-- ============================================================
DO $$ BEGIN
  CREATE TYPE estado_obra AS ENUM ('idea', 'en_busqueda', 'en_cotizacion', 'contratada', 'perdida');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE motivo_perdida AS ENUM
    ('precio', 'plazo', 'producto', 'proveedor_habitual', 'obra_suspendida', 'sin_respuesta', 'otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE origen_obra AS ENUM ('referente', 'cartel', 'web_redes', 'cliente_anterior', 'llamado', 'otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE tipo_obra AS ENUM ('edificio_residencial', 'casa', 'oficinas_comercial', 'industrial', 'otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 2. obras — ente `obra`
-- ============================================================
-- `equipo_id`: el del responsable al crear y al transferir, guardado como el
-- del hilo. `estado_nota`: el texto del último cambio de estado (detalle de la
-- pérdida o causa de la reversión); junto con el motivo, va al evento `estado`.
-- `compra_estimada`: mes y año, guardado como el día 1.
CREATE TABLE IF NOT EXISTS public.obras (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          text NOT NULL CHECK (length(btrim(nombre)) BETWEEN 1 AND 200),
  direccion       text NOT NULL CHECK (length(btrim(direccion)) BETWEEN 1 AND 300),
  localidad       text CHECK (length(localidad) <= 120),
  notas           text CHECK (length(notas) <= 5000),
  origen          origen_obra NOT NULL,
  tipo            tipo_obra NOT NULL,
  compra_estimada date CHECK (extract(day FROM compra_estimada) = 1),
  estado          estado_obra NOT NULL DEFAULT 'idea',
  motivo_perdida  motivo_perdida,
  estado_nota     text CHECK (length(btrim(estado_nota)) BETWEEN 1 AND 2000),
  responsable_id  uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  equipo_id       uuid REFERENCES public.equipos(id),
  creado_por      uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT obras_perdida_con_motivo CHECK ((estado = 'perdida') = (motivo_perdida IS NOT NULL)),
  CONSTRAINT obras_otro_con_nota CHECK (motivo_perdida IS DISTINCT FROM 'otro' OR estado_nota IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_obras_responsable ON public.obras (responsable_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_equipo ON public.obras (equipo_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.obras;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.obras
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.obras ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. obras_participantes — quien la ve y la trabaja sin ser responsable
-- ============================================================
-- `equipo_id`: el del participante al sumarlo, guardado. Volver es una fila
-- nueva.
CREATE TABLE IF NOT EXISTS public.obras_participantes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id      uuid NOT NULL REFERENCES public.obras(id),
  usuario_id   uuid NOT NULL REFERENCES public.usuarios(id),
  equipo_id    uuid REFERENCES public.equipos(id),
  agregado_por uuid DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_obras_participantes_unico
  ON public.obras_participantes (obra_id, usuario_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_participantes_usuario
  ON public.obras_participantes (usuario_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_obras_participantes_equipo
  ON public.obras_participantes (equipo_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.obras_participantes;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.obras_participantes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.obras_participantes ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. Catálogo de permisos
-- ============================================================
-- `obras_ver requiere contactos_ver` la siembra `sql/127`, que crea
-- `contactos_ver`.
INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, delegable)
SELECT v.codigo, 'obras', 'vista', v.nombre, v.orden, v.delegable
FROM (VALUES
  ('obras_ver',   'Ver',   1, true),
  ('obras_todas', 'Todas', 2, false)
) AS v (codigo, nombre, orden, delegable)
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = v.codigo AND s.activo);

INSERT INTO public.submodulos (codigo, modulo, tipo, nombre, orden, vista_id, delegable)
SELECT f.codigo, 'obras', 'funcion', f.nombre, f.orden, v.id, f.delegable
FROM (VALUES
  ('obras_crear',       'Crear obras',  1, 'obras_ver',   true),
  ('obras_equipo',      'Jefe de equipo', 2, 'obras_ver', false),
  ('obras_administrar', 'Administrar',  1, 'obras_todas', false)
) AS f (codigo, nombre, orden, vista, delegable)
JOIN public.submodulos v ON v.codigo = f.vista AND v.activo
WHERE NOT EXISTS (SELECT 1 FROM public.submodulos s WHERE s.codigo = f.codigo AND s.activo);

INSERT INTO public.submodulo_reglas (submodulo_id, otro_id, tipo)
SELECT a.id, b.id, 'requiere'
FROM (VALUES
  ('obras_equipo', 'usuarios_delegar'),
  ('obras_todas',  'obras_administrar'),
  ('obras_todas',  'obras_ver')
) AS r (submodulo, otro)
JOIN public.submodulos a ON a.codigo = r.submodulo AND a.activo
JOIN public.submodulos b ON b.codigo = r.otro AND b.activo
WHERE NOT EXISTS (
  SELECT 1 FROM public.submodulo_reglas x
  WHERE x.activo AND x.submodulo_id = a.id AND x.otro_id = b.id
);

-- ============================================================
-- 5. quitar_delegador — `obras_equipo` se va con la delegación
-- ============================================================
-- `obras_equipo` requiere `usuarios_delegar` (US016), no al revés: se quita
-- junto, pero `designar_delegador` no la da. El resto, igual que `sql/112`.
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
  v_obras_equipo uuid;
BEGIN
  IF NOT public.usuario_tiene_permiso(p_admin, 'usuarios_gestionar') THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT id, vista_id INTO v_delegar, v_vista
  FROM public.submodulos WHERE codigo = 'usuarios_delegar' AND activo;
  SELECT id INTO v_tareas_equipo
  FROM public.submodulos WHERE codigo = 'tareas_equipo' AND activo;
  SELECT id INTO v_obras_equipo
  FROM public.submodulos WHERE codigo = 'obras_equipo' AND activo;

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
  WHERE usuario_id = p_saliente
    AND submodulo_id IN (v_delegar, v_vista, v_tareas_equipo, v_obras_equipo)
    AND activo;
END;
$$;

-- ============================================================
-- 6. Ver, trabajar, estar a cargo
-- ============================================================
-- Ve la obra: `obras_todas` (también desactivada), y con `obras_ver` sobre
-- una activa, el responsable, un participante, o el jefe (`obras_equipo`) del
-- equipo de la obra o del de un participante. DEFINER: lee los participantes
-- sin su RLS, que pregunta por la obra (42P17). Recibe las columnas de la obra
-- y no el id: en un UPDATE la policy mira la fila nueva (GUIDE_ENTES §2.3).
CREATE OR REPLACE FUNCTION public.obras_puede_ver_obra_de(
  p_obra uuid, p_responsable uuid, p_equipo uuid, p_activo boolean, p_usuario uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.usuario_tiene_permiso(p_usuario, 'obras_todas')
    OR (
      p_activo
      AND public.usuario_tiene_permiso(p_usuario, 'obras_ver')
      AND (
        p_responsable = p_usuario
        OR EXISTS (
          SELECT 1 FROM public.obras_participantes p
          WHERE p.obra_id = p_obra AND p.activo AND p.usuario_id = p_usuario
        )
        OR (
          public.usuario_tiene_permiso(p_usuario, 'obras_equipo')
          AND (
            p_equipo = public.equipo_de(p_usuario)
            OR EXISTS (
              SELECT 1 FROM public.obras_participantes p
              WHERE p.obra_id = p_obra AND p.activo AND p.equipo_id = public.equipo_de(p_usuario)
            )
          )
        )
      )
    );
$$;

-- La trabaja (edita, cambia el estado, vincula contactos): el responsable, un
-- participante, el jefe del equipo de la obra y `obras_administrar`. El jefe
-- del equipo de un participante solo la ve (*Ver no es trabajar*).
CREATE OR REPLACE FUNCTION public.obras_trabaja_de(p_obra uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras o
    WHERE o.id = p_obra
      AND o.activo
      AND public.usuario_tiene_permiso(p_usuario, 'obras_ver')
      AND (
        o.responsable_id = p_usuario
        OR EXISTS (
          SELECT 1 FROM public.obras_participantes p
          WHERE p.obra_id = o.id AND p.activo AND p.usuario_id = p_usuario
        )
        OR (public.usuario_tiene_permiso(p_usuario, 'obras_equipo') AND o.equipo_id = public.equipo_de(p_usuario))
        OR public.usuario_tiene_permiso(p_usuario, 'obras_administrar')
      )
  );
$$;

-- La tiene a cargo (transfiere, desactiva, suma y quita participantes): el
-- responsable, el jefe del equipo de la obra y `obras_administrar`.
CREATE OR REPLACE FUNCTION public.obras_a_cargo_de(p_obra uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.obras o
    WHERE o.id = p_obra
      AND o.activo
      AND public.usuario_tiene_permiso(p_usuario, 'obras_ver')
      AND (
        o.responsable_id = p_usuario
        OR (public.usuario_tiene_permiso(p_usuario, 'obras_equipo') AND o.equipo_id = public.equipo_de(p_usuario))
        OR public.usuario_tiene_permiso(p_usuario, 'obras_administrar')
      )
  );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_puede_ver_obra_de(uuid, uuid, uuid, boolean, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_trabaja_de(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_a_cargo_de(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Envoltorios con `auth.uid()`: la policy y `trabaja_registro`.
CREATE OR REPLACE FUNCTION public.obras_puede_ver_obra(p_obra uuid, p_responsable uuid, p_equipo uuid, p_activo boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.obras_puede_ver_obra_de(p_obra, p_responsable, p_equipo, p_activo, auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.obras_trabaja(p_obra uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.obras_trabaja_de(p_obra, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.obras_puede_ver_obra(uuid, uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_puede_ver_obra(uuid, uuid, uuid, boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_trabaja(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_trabaja(uuid) TO authenticated;

-- ============================================================
-- 7. obras — crear, editar, cambiar de estado, transferir, desactivar
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_al_crear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.activo := true;
  NEW.motivo_perdida := NULL;
  NEW.estado_nota := NULL;

  IF NEW.estado NOT IN ('idea', 'en_busqueda', 'en_cotizacion') THEN
    RAISE EXCEPTION 'Una obra nace en idea, en búsqueda o en cotización' USING ERRCODE = 'OB001';
  END IF;

  NEW.equipo_id := public.equipo_de(NEW.responsable_id);
  RETURN NEW;
END;
$$;

-- Estados (ficha): idea ↔ en_busqueda ↔ en_cotizacion, libre; de esos tres a
-- perdida (con motivo) o a contratada; perdida se reabre a los tres;
-- contratada vuelve a los tres con causa, no a perdida. La nota es del cambio:
-- si llega igual a la que tenía la fila, es la del cambio anterior y se
-- limpia. Sin cambio de estado, motivo y nota no se tocan.
CREATE OR REPLACE FUNCTION public.obras_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_abiertos estado_obra[] := '{idea,en_busqueda,en_cotizacion}';
BEGIN
  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL THEN
    IF (NEW.nombre, NEW.direccion, NEW.localidad, NEW.notas, NEW.origen, NEW.tipo, NEW.compra_estimada,
        NEW.estado, NEW.motivo_perdida, NEW.estado_nota)
       IS DISTINCT FROM
       (OLD.nombre, OLD.direccion, OLD.localidad, OLD.notas, OLD.origen, OLD.tipo, OLD.compra_estimada,
        OLD.estado, OLD.motivo_perdida, OLD.estado_nota)
       AND NOT public.obras_trabaja_de(OLD.id, v_uid) THEN
      RAISE EXCEPTION 'Solo quien trabaja la obra la edita' USING ERRCODE = 'OB002';
    END IF;

    IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id
       AND NOT public.obras_a_cargo_de(OLD.id, v_uid) THEN
      RAISE EXCEPTION 'Transfieren la obra su responsable, su jefe o el admin' USING ERRCODE = 'OB003';
    END IF;

    IF OLD.activo AND NOT NEW.activo AND NOT public.obras_a_cargo_de(OLD.id, v_uid) THEN
      RAISE EXCEPTION 'Desactivan la obra su responsable, su jefe o el admin' USING ERRCODE = 'OB004';
    END IF;

    IF NOT OLD.activo AND NEW.activo AND NOT public.usuario_tiene_permiso(v_uid, 'obras_administrar') THEN
      RAISE EXCEPTION 'Solo el admin reactiva una obra' USING ERRCODE = 'OB005';
    END IF;
  END IF;

  IF NEW.responsable_id IS DISTINCT FROM OLD.responsable_id THEN
    IF NOT public.usuario_tiene_permiso(NEW.responsable_id, 'obras_ver') THEN
      RAISE EXCEPTION 'La obra se transfiere a alguien activo que ve Obras' USING ERRCODE = 'OB006';
    END IF;
    NEW.equipo_id := public.equipo_de(NEW.responsable_id);
  END IF;

  IF OLD.activo AND NOT NEW.activo AND NEW.estado = 'contratada' THEN
    RAISE EXCEPTION 'Una obra contratada no se desactiva' USING ERRCODE = 'OB007';
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    IF NEW.estado_nota IS NOT DISTINCT FROM OLD.estado_nota THEN
      NEW.estado_nota := NULL;
    END IF;

    IF OLD.estado = 'contratada' THEN
      IF NEW.estado <> ALL (v_abiertos) THEN
        RAISE EXCEPTION 'Una obra contratada vuelve a idea, búsqueda o cotización, no a perdida' USING ERRCODE = 'OB008';
      END IF;
      IF NEW.estado_nota IS NULL THEN
        RAISE EXCEPTION 'Revertir una obra contratada pide la causa' USING ERRCODE = 'OB009';
      END IF;
    ELSIF OLD.estado = 'perdida' AND NEW.estado = 'contratada' THEN
      RAISE EXCEPTION 'Una obra perdida se reabre a idea, búsqueda o cotización' USING ERRCODE = 'OB010';
    END IF;

    IF NEW.estado = 'perdida' THEN
      IF NEW.motivo_perdida IS NULL THEN
        RAISE EXCEPTION 'Perder una obra pide el motivo' USING ERRCODE = 'OB011';
      END IF;
      IF NEW.motivo_perdida = 'otro' AND NEW.estado_nota IS NULL THEN
        RAISE EXCEPTION 'Con motivo "otro", contá qué pasó' USING ERRCODE = 'OB012';
      END IF;
    ELSE
      NEW.motivo_perdida := NULL;
      IF OLD.estado <> 'contratada' THEN
        NEW.estado_nota := NULL;
      END IF;
    END IF;
  ELSE
    NEW.motivo_perdida := OLD.motivo_perdida;
    NEW.estado_nota := OLD.estado_nota;
  END IF;

  RETURN NEW;
END;
$$;

-- El nuevo responsable no sigue como participante de su propia obra.
CREATE OR REPLACE FUNCTION public.obras_al_transferir()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.obras_participantes SET activo = false
  WHERE obra_id = NEW.id AND usuario_id = NEW.responsable_id AND activo;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_al_crear() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_al_editar() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_al_transferir() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS obras_al_crear ON public.obras;
CREATE TRIGGER obras_al_crear
  BEFORE INSERT ON public.obras
  FOR EACH ROW EXECUTE FUNCTION public.obras_al_crear();

DROP TRIGGER IF EXISTS obras_al_editar ON public.obras;
CREATE TRIGGER obras_al_editar
  BEFORE UPDATE ON public.obras
  FOR EACH ROW EXECUTE FUNCTION public.obras_al_editar();

DROP TRIGGER IF EXISTS obras_al_transferir ON public.obras;
CREATE TRIGGER obras_al_transferir
  AFTER UPDATE OF responsable_id ON public.obras
  FOR EACH ROW WHEN (OLD.responsable_id IS DISTINCT FROM NEW.responsable_id)
  EXECUTE FUNCTION public.obras_al_transferir();

-- ============================================================
-- 8. obras_participantes — sumar y quitar
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_participantes_al_crear()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  NEW.activo := true;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL AND NOT public.obras_a_cargo_de(NEW.obra_id, v_uid) THEN
    RAISE EXCEPTION 'Suman y quitan participantes el responsable, su jefe o el admin' USING ERRCODE = 'OB013';
  END IF;

  IF NOT public.usuario_tiene_permiso(NEW.usuario_id, 'obras_ver') THEN
    RAISE EXCEPTION 'Participa de una obra alguien activo que ve Obras' USING ERRCODE = 'OB014';
  END IF;

  NEW.equipo_id := public.equipo_de(NEW.usuario_id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.obras_participantes_al_editar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF NOT OLD.activo AND NEW.activo THEN
    RAISE EXCEPTION 'Volver a sumar a alguien es una participación nueva' USING ERRCODE = 'OB015';
  END IF;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL
     AND NEW.activo IS DISTINCT FROM OLD.activo
     AND NOT public.obras_a_cargo_de(OLD.obra_id, v_uid) THEN
    RAISE EXCEPTION 'Suman y quitan participantes el responsable, su jefe o el admin' USING ERRCODE = 'OB013';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_participantes_al_crear() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_participantes_al_editar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS obras_participantes_al_crear ON public.obras_participantes;
CREATE TRIGGER obras_participantes_al_crear
  BEFORE INSERT ON public.obras_participantes
  FOR EACH ROW EXECUTE FUNCTION public.obras_participantes_al_crear();

DROP TRIGGER IF EXISTS obras_participantes_al_editar ON public.obras_participantes;
CREATE TRIGGER obras_participantes_al_editar
  BEFORE UPDATE ON public.obras_participantes
  FOR EACH ROW EXECUTE FUNCTION public.obras_participantes_al_editar();

-- ============================================================
-- 9. Policies y GRANT
-- ============================================================
-- La policy dice sobre qué filas; el trigger, quién puede qué. Transferir y
-- desactivar sacan la obra de la vista de quien lo hace: van por las
-- funciones DEFINER de la sección 10.
DROP POLICY IF EXISTS obras_select ON public.obras;
CREATE POLICY obras_select ON public.obras FOR SELECT TO authenticated
  USING (obras_puede_ver_obra(id, responsable_id, equipo_id, activo));

DROP POLICY IF EXISTS obras_insert ON public.obras;
CREATE POLICY obras_insert ON public.obras FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('obras_crear'));

DROP POLICY IF EXISTS obras_update ON public.obras;
CREATE POLICY obras_update ON public.obras FOR UPDATE TO authenticated
  USING (obras_puede_ver_obra(id, responsable_id, equipo_id, activo))
  WITH CHECK (true);

-- EXISTS con la RLS de la obra, que no mira hacia acá.
DROP POLICY IF EXISTS obras_participantes_select ON public.obras_participantes;
CREATE POLICY obras_participantes_select ON public.obras_participantes FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.obras o WHERE o.id = obra_id));

DROP POLICY IF EXISTS obras_participantes_insert ON public.obras_participantes;
CREATE POLICY obras_participantes_insert ON public.obras_participantes FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.obras o WHERE o.id = obra_id));

DROP POLICY IF EXISTS obras_participantes_update ON public.obras_participantes;
CREATE POLICY obras_participantes_update ON public.obras_participantes FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.obras o WHERE o.id = obra_id))
  WITH CHECK (true);

GRANT SELECT ON public.obras, public.obras_participantes TO authenticated;
GRANT INSERT (id, nombre, direccion, localidad, notas, origen, tipo, compra_estimada, estado)
  ON public.obras TO authenticated;
GRANT UPDATE (nombre, direccion, localidad, notas, origen, tipo, compra_estimada, estado, motivo_perdida,
              estado_nota, activo)
  ON public.obras TO authenticated;
GRANT INSERT (id, obra_id, usuario_id), UPDATE (activo) ON public.obras_participantes TO authenticated;

-- ============================================================
-- 10. Transferir y desactivar — DEFINER, las reglas son los triggers
-- ============================================================
-- "Quedarme como participante" es de quien transfiere. Se suma antes de
-- transferir, mientras todavía la tiene a cargo; sin tildarlo, deja de
-- participar si participaba.
CREATE OR REPLACE FUNCTION public.obras_transferir(p_obra uuid, p_responsable uuid, p_quedarme boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_quedarme THEN
    INSERT INTO public.obras_participantes (obra_id, usuario_id)
    SELECT p_obra, auth.uid()
    WHERE NOT EXISTS (
      SELECT 1 FROM public.obras_participantes
      WHERE obra_id = p_obra AND usuario_id = auth.uid() AND activo
    );
  ELSE
    UPDATE public.obras_participantes SET activo = false
    WHERE obra_id = p_obra AND usuario_id = auth.uid() AND activo;
  END IF;

  UPDATE public.obras SET responsable_id = p_responsable WHERE id = p_obra AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa obra no existe o está desactivada' USING ERRCODE = 'OB016';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.obras_desactivar(p_obra uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.obras SET activo = false WHERE id = p_obra AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa obra no existe o está desactivada' USING ERRCODE = 'OB016';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_transferir(uuid, uuid, boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.obras_desactivar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_desactivar(uuid) TO authenticated;

-- ============================================================
-- 11. Ente `obra` y sus ramas
-- ============================================================
-- Emite alta, estado (con motivo y nota), transferencia y baja; dispara alta
-- y estado. `transferencia` y `baja` pasan por DEFINER: no disparan.
INSERT INTO public.entes (codigo, modulo, submodulo, estados, datos, roles, ruta, tabla, disparos)
VALUES ('obra', 'obras', 'obras_ver', 'estado_obra', '{nombre,direccion,localidad}',
        '{cliente,decisor,desarrolladora,constructora,comercializadora,arquitecto,director_obra,referente}',
        '/obras/{id}', 'public.obras', '{alta,estado}')
ON CONFLICT (codigo) DO NOTHING;

DROP TRIGGER IF EXISTS emitir_eventos ON public.obras;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo, estado, responsable_id ON public.obras
  FOR EACH ROW EXECUTE FUNCTION emitir_eventos_registro('obra', 'responsable_id', 'motivo_perdida,estado_nota');

-- El nombre si quien pregunta la ve (la RLS decide).
CREATE OR REPLACE FUNCTION public.obras_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra' THEN (SELECT nombre FROM public.obras WHERE id = p_id)
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_etiqueta(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_etiqueta(text, uuid) TO authenticated;

-- Activas cuyo nombre o dirección contiene el texto; las perdidas al final.
CREATE OR REPLACE FUNCTION public.obras_buscar(p_texto text)
RETURNS TABLE (tipo text, id uuid, titulo text, subtitulo text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(btrim(p_texto)) AS t
    WHERE length(btrim(p_texto)) >= 2
  )
  SELECT 'obra'::text, o.id, o.nombre, o.direccion
  FROM q
  JOIN public.obras o
    ON o.activo AND (strpos(lower(o.nombre), q.t) > 0 OR strpos(lower(o.direccion), q.t) > 0)
  ORDER BY o.estado = 'perdida', strpos(lower(o.nombre), q.t) <> 1, o.created_at DESC
  LIMIT 15;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_buscar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_buscar(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.etiqueta_registro(p_ente text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE e.modulo
    WHEN 'tareas' THEN public.tareas_etiqueta(p_ente, p_id)
    WHEN 'obras'  THEN public.obras_etiqueta(p_ente, p_id)
  END
  FROM public.entes e
  WHERE e.codigo = p_ente;
$$;

CREATE OR REPLACE FUNCTION public.trabaja_registro(p_ente text, p_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'obras' THEN public.obras_trabaja(p_id)
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), false);
$$;

-- "Lo ve", por usuario explícito. Sin GRANT: la llaman funciones DEFINER.
CREATE OR REPLACE FUNCTION public.obras_puede_abrir(p_tipo text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.obras_puede_ver_obra_de(o.id, o.responsable_id, o.equipo_id, o.activo, p_usuario)
  FROM public.obras o
  WHERE o.id = p_id AND p_tipo = 'obra';
$$;

REVOKE EXECUTE ON FUNCTION public.obras_puede_abrir(text, uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'obras' THEN public.obras_puede_abrir(p_ente, p_id, p_usuario)
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), false);
$$;

CREATE OR REPLACE FUNCTION public.buscar_registros(p_modulo text, p_texto text)
RETURNS TABLE (ente text, registro_id uuid, etiqueta text, detalle text, href text)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_modulo = 'tareas' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.tareas_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  ELSIF p_modulo = 'obras' THEN
    RETURN QUERY
      SELECT b.tipo, b.id, b.titulo, b.subtitulo, replace(e.ruta, '{id}', b.id::text)
      FROM public.obras_buscar(p_texto) WITH ORDINALITY b
      JOIN public.entes e ON e.codigo = b.tipo
      ORDER BY b.ordinality;
  END IF;
END;
$$;
