-- Módulo tareas — tareas/hilos, proyectos con visibilidad en cascada,
-- multi-asignado, plantillas, auditoría append-only.
-- Reemplaza el intento anterior (tareas-v1, revertido en sql/004): requisitos
-- de negocio cambiaron (proyectos + visibilidad en cascada, multi-asignado,
-- responsable_id, temperatura en vez de prioridad fija). No hereda schema
-- de esa rama, sí algunos patrones técnicos ya probados (timezone AR queda
-- para queries.ts, no SQL; posponer y recurrencia sin pg_cron).
-- Correr en Supabase SQL Editor. Idempotente donde es posible.

-- ============================================================
-- Enums
-- ============================================================
DO $$
BEGIN
  CREATE TYPE visibilidad AS ENUM ('publico', 'privado');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE estado_hilo AS ENUM ('abierto', 'cerrado');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE estado_tarea AS ENUM ('pendiente', 'en_progreso', 'completada', 'cancelada');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE recurrencia_unidad AS ENUM ('dia', 'mes');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE modo_completado AS ENUM ('manual', 'automatico', 'hibrido');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- ============================================================
-- tareas_proyectos — contenedor organizacional. Techo de visibilidad
-- para los hilos/tareas que agrupa (ver cascada más abajo).
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_proyectos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre       text NOT NULL,
  descripcion  text,
  visibilidad  visibilidad NOT NULL DEFAULT 'publico',
  creado_por   uuid NOT NULL REFERENCES usuarios(id),
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_proyectos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_proyectos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_proyectos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas_proyectos_miembros — lista explícita de membresía,
-- solo relevante cuando el proyecto es privado.
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_proyectos_miembros (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proyecto_id uuid NOT NULL REFERENCES tareas_proyectos(id),
  usuario_id  uuid NOT NULL REFERENCES usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_proyectos_miembros_proyecto_id
  ON tareas_proyectos_miembros (proyecto_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tareas_proyectos_miembros_proyecto_usuario_activo
  ON tareas_proyectos_miembros (proyecto_id, usuario_id) WHERE activo;

ALTER TABLE tareas_proyectos_miembros ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas_hilos — agrupador de tareas relacionadas. Sin vencimiento
-- propio (se deriva de sus tareas en queries.ts). Visibilidad y
-- proyecto solo importan cuando la tarea individual no los define
-- por sí misma (ver tareas.hilo_id más abajo — fuente única).
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_hilos (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proyecto_id    uuid REFERENCES tareas_proyectos(id),
  titulo         text NOT NULL,
  descripcion    text,
  visibilidad    visibilidad NOT NULL DEFAULT 'publico',
  estado         estado_hilo NOT NULL DEFAULT 'abierto',
  responsable_id uuid NOT NULL REFERENCES usuarios(id),
  creado_por     uuid NOT NULL REFERENCES usuarios(id),
  posponer_desde date,
  posponer_hasta date,
  activo         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CHECK (posponer_desde IS NULL OR posponer_hasta IS NULL OR posponer_hasta > posponer_desde)
);

CREATE INDEX IF NOT EXISTS idx_tareas_hilos_proyecto_id ON tareas_hilos (proyecto_id);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_hilos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_hilos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas — unidad mínima. proyecto_id solo se usa cuando la tarea
-- está suelta (sin hilo); si tiene hilo_id, el proyecto/visibilidad
-- se heredan del hilo (fuente única, ver CHECK).
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hilo_id             uuid REFERENCES tareas_hilos(id),
  proyecto_id         uuid REFERENCES tareas_proyectos(id),
  titulo              text NOT NULL,
  descripcion         text,
  visibilidad         visibilidad NOT NULL DEFAULT 'publico',
  estado              estado_tarea NOT NULL DEFAULT 'pendiente',
  temperatura         int NOT NULL DEFAULT 50 CHECK (temperatura BETWEEN 1 AND 100),
  responsable_id      uuid NOT NULL REFERENCES usuarios(id),
  creado_por          uuid NOT NULL REFERENCES usuarios(id),
  fecha_vencimiento   date,
  posponer_desde      date,
  posponer_hasta      date,
  recurrencia_cantidad int CHECK (recurrencia_cantidad IS NULL OR recurrencia_cantidad > 0),
  recurrencia_unidad  recurrencia_unidad,
  nota_anterior       text,
  nota_siguiente      text,
  origen_app          text,
  origen_punto        text,
  modo_completado     modo_completado NOT NULL DEFAULT 'manual',
  activo              boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (hilo_id IS NULL OR proyecto_id IS NULL),
  CHECK ((recurrencia_cantidad IS NULL) = (recurrencia_unidad IS NULL)),
  CHECK (posponer_desde IS NULL OR posponer_hasta IS NULL OR posponer_hasta > posponer_desde)
);

CREATE INDEX IF NOT EXISTS idx_tareas_hilo_id ON tareas (hilo_id);
CREATE INDEX IF NOT EXISTS idx_tareas_proyecto_id ON tareas (proyecto_id);
CREATE INDEX IF NOT EXISTS idx_tareas_responsable_id ON tareas (responsable_id);

DROP TRIGGER IF EXISTS set_updated_at ON tareas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas_asignados — multi-asignado. Cualquiera de los asignados
-- puede completar la tarea (no hace falta que todos la marquen).
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_asignados (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tarea_id   uuid NOT NULL REFERENCES tareas(id),
  usuario_id uuid NOT NULL REFERENCES usuarios(id),
  activo     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_asignados_tarea_id ON tareas_asignados (tarea_id);
CREATE INDEX IF NOT EXISTS idx_tareas_asignados_usuario_id ON tareas_asignados (usuario_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tareas_asignados_tarea_usuario_activo
  ON tareas_asignados (tarea_id, usuario_id) WHERE activo;

ALTER TABLE tareas_asignados ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas_plantillas / tareas_plantillas_items — recurso compartido
-- del equipo, gateado por la vista (sin función separada de
-- lectura/escritura: no hay evidencia de necesitar dos audiencias).
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_plantillas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL,
  descripcion text,
  creado_por  uuid NOT NULL REFERENCES usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS set_updated_at ON tareas_plantillas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON tareas_plantillas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE tareas_plantillas ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS tareas_plantillas_items (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_id uuid NOT NULL REFERENCES tareas_plantillas(id),
  titulo       text NOT NULL,
  orden        int NOT NULL DEFAULT 0,
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_plantillas_items_plantilla_id
  ON tareas_plantillas_items (plantilla_id);

ALTER TABLE tareas_plantillas_items ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- tareas_eventos — auditoría append-only. Necesaria porque el
-- estado de una tarea recurrente se resetea a 'pendiente' en cada
-- ciclo y updated_at se mueve con cualquier edición — ninguna
-- columna sobre `tareas` puede reconstruir "qué se completó cuándo
-- y quién lo hizo". Excepción documentada a "nunca DELETE, siempre
-- activo": una auditoría no debe poder ocultar sus propias filas.
-- ============================================================
CREATE TABLE IF NOT EXISTS tareas_eventos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tarea_id        uuid NOT NULL REFERENCES tareas(id),
  usuario_id      uuid REFERENCES usuarios(id), -- NULL = evento del sistema
  estado_anterior estado_tarea,
  estado_nuevo    estado_tarea NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tareas_eventos_tarea_id ON tareas_eventos (tarea_id);
CREATE INDEX IF NOT EXISTS idx_tareas_eventos_usuario_id ON tareas_eventos (usuario_id);

ALTER TABLE tareas_eventos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- puede_ver_hilo(uuid) — visibilidad en cascada para un hilo.
-- SECURITY DEFINER: necesita leer tareas_asignados/tareas_proyectos
-- sin quedar atado a la RLS de quien llama (mismo criterio que
-- tiene_permiso()).
-- ============================================================
CREATE OR REPLACE FUNCTION puede_ver_hilo(p_hilo_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    tiene_permiso('tareas_gestionar_ajenas')
    OR h.creado_por = auth.uid()
    OR h.responsable_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM tareas t
      JOIN tareas_asignados ta ON ta.tarea_id = t.id AND ta.activo
      WHERE t.hilo_id = h.id AND ta.usuario_id = auth.uid()
    )
    OR (
      h.proyecto_id IS NOT NULL AND h.visibilidad = 'publico'
      AND (
        (SELECT pr.visibilidad FROM tareas_proyectos pr WHERE pr.id = h.proyecto_id) = 'publico'
        OR EXISTS (
          SELECT 1 FROM tareas_proyectos_miembros m
          WHERE m.proyecto_id = h.proyecto_id AND m.usuario_id = auth.uid() AND m.activo
        )
      )
    )
  FROM tareas_hilos h
  WHERE h.id = p_hilo_id;
$$;

-- ============================================================
-- Cierre de hilo: manual (modal en UI), bloqueado si queda alguna
-- tarea sin completar. SECURITY DEFINER para no depender de que
-- quien cierra vea TODAS las tareas del hilo vía RLS.
-- ============================================================
CREATE OR REPLACE FUNCTION validar_cierre_hilo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.estado = 'cerrado' AND OLD.estado <> 'cerrado' THEN
    IF EXISTS (
      SELECT 1 FROM tareas
      WHERE hilo_id = NEW.id AND activo AND estado NOT IN ('completada', 'cancelada')
    ) THEN
      RAISE EXCEPTION 'No se puede cerrar un hilo con tareas sin completar';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_cierre_hilo ON tareas_hilos;
CREATE TRIGGER trg_validar_cierre_hilo
  BEFORE UPDATE ON tareas_hilos
  FOR EACH ROW EXECUTE FUNCTION validar_cierre_hilo();

-- ============================================================
-- Reapertura de hilo: automática al agregar/mover una tarea a un
-- hilo cerrado. SECURITY DEFINER porque quien mueve la tarea puede
-- no tener UPDATE directo sobre tareas_hilos.
-- ============================================================
CREATE OR REPLACE FUNCTION reabrir_hilo_en_tarea()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE tareas_hilos SET estado = 'abierto'
  WHERE id = NEW.hilo_id AND estado = 'cerrado';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reabrir_hilo ON tareas;
CREATE TRIGGER trg_reabrir_hilo
  AFTER INSERT OR UPDATE OF hilo_id ON tareas
  FOR EACH ROW
  WHEN (NEW.hilo_id IS NOT NULL)
  EXECUTE FUNCTION reabrir_hilo_en_tarea();

-- ============================================================
-- Recurrencia sin cron: la próxima instancia se genera al completar
-- la actual (no por calendario), copiando asignados y nota_siguiente
-- -> nota_anterior de la nueva. SECURITY DEFINER porque quien
-- completa puede no ser el creado_por de la tarea original.
-- ============================================================
CREATE OR REPLACE FUNCTION generar_recurrencia()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intervalo interval;
  v_nueva_id  uuid;
BEGIN
  IF NEW.recurrencia_cantidad IS NULL THEN
    RETURN NEW;
  END IF;

  v_intervalo := CASE NEW.recurrencia_unidad
    WHEN 'dia' THEN (NEW.recurrencia_cantidad || ' days')::interval
    WHEN 'mes' THEN (NEW.recurrencia_cantidad || ' months')::interval
  END;

  INSERT INTO tareas (
    hilo_id, proyecto_id, titulo, descripcion, visibilidad,
    responsable_id, creado_por, fecha_vencimiento,
    recurrencia_cantidad, recurrencia_unidad, nota_anterior,
    modo_completado, origen_app, origen_punto
  ) VALUES (
    NEW.hilo_id, NEW.proyecto_id, NEW.titulo, NEW.descripcion, NEW.visibilidad,
    NEW.responsable_id, NEW.creado_por, (current_date + v_intervalo)::date,
    NEW.recurrencia_cantidad, NEW.recurrencia_unidad, NEW.nota_siguiente,
    NEW.modo_completado, NEW.origen_app, NEW.origen_punto
  ) RETURNING id INTO v_nueva_id;

  INSERT INTO tareas_asignados (tarea_id, usuario_id)
  SELECT v_nueva_id, usuario_id FROM tareas_asignados
  WHERE tarea_id = NEW.id AND activo;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_generar_recurrencia ON tareas;
CREATE TRIGGER trg_generar_recurrencia
  AFTER UPDATE OF estado ON tareas
  FOR EACH ROW
  WHEN (NEW.estado = 'completada' AND OLD.estado IS DISTINCT FROM 'completada')
  EXECUTE FUNCTION generar_recurrencia();

-- ============================================================
-- Log de auditoría: cada cambio de estado (no solo 'completada')
-- queda registrado — deja contestar "¿quién la reabrió?" también.
-- ============================================================
CREATE OR REPLACE FUNCTION log_evento_tarea()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO tareas_eventos (tarea_id, usuario_id, estado_anterior, estado_nuevo)
  VALUES (NEW.id, auth.uid(), OLD.estado, NEW.estado);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_evento_tarea ON tareas;
CREATE TRIGGER trg_log_evento_tarea
  AFTER UPDATE OF estado ON tareas
  FOR EACH ROW
  WHEN (NEW.estado IS DISTINCT FROM OLD.estado)
  EXECUTE FUNCTION log_evento_tarea();

-- ============================================================
-- RLS policies
-- ============================================================

-- tareas_proyectos: público visible a todo el sistema (el "techo"),
-- privado solo a miembros/creador/ajenas.
DROP POLICY IF EXISTS tareas_proyectos_select ON tareas_proyectos;
CREATE POLICY tareas_proyectos_select ON tareas_proyectos FOR SELECT
  USING (
    visibilidad = 'publico'
    OR creado_por = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR EXISTS (
      SELECT 1 FROM tareas_proyectos_miembros m
      WHERE m.proyecto_id = tareas_proyectos.id AND m.usuario_id = auth.uid() AND m.activo
    )
  );

DROP POLICY IF EXISTS tareas_proyectos_insert ON tareas_proyectos;
CREATE POLICY tareas_proyectos_insert ON tareas_proyectos FOR INSERT
  WITH CHECK (creado_por = auth.uid() AND tiene_permiso('tareas_proyectos_crear'));

DROP POLICY IF EXISTS tareas_proyectos_update ON tareas_proyectos;
CREATE POLICY tareas_proyectos_update ON tareas_proyectos FOR UPDATE
  USING (creado_por = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  WITH CHECK (creado_por = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'));

-- es_creador_proyecto(uuid) — SECURITY DEFINER: las políticas de
-- tareas_proyectos_miembros necesitan saber si el usuario creó el
-- proyecto, pero consultar tareas_proyectos directamente dispara su
-- propia política (que a su vez consulta tareas_proyectos_miembros),
-- generando recursión infinita. Igual criterio que puede_ver_hilo().
CREATE OR REPLACE FUNCTION es_creador_proyecto(p_proyecto_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tareas_proyectos p
    WHERE p.id = p_proyecto_id AND p.creado_por = auth.uid()
  );
$$;

-- tareas_proyectos_miembros: gestiona el líder del proyecto (creador) o ajenas.
DROP POLICY IF EXISTS tareas_proyectos_miembros_select ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_select ON tareas_proyectos_miembros FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_creador_proyecto(proyecto_id)
  );

DROP POLICY IF EXISTS tareas_proyectos_miembros_insert ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_insert ON tareas_proyectos_miembros FOR INSERT
  WITH CHECK (
    tiene_permiso('tareas_gestionar_ajenas')
    OR es_creador_proyecto(proyecto_id)
  );

DROP POLICY IF EXISTS tareas_proyectos_miembros_update ON tareas_proyectos_miembros;
CREATE POLICY tareas_proyectos_miembros_update ON tareas_proyectos_miembros FOR UPDATE
  USING (
    tiene_permiso('tareas_gestionar_ajenas')
    OR es_creador_proyecto(proyecto_id)
  )
  WITH CHECK (
    tiene_permiso('tareas_gestionar_ajenas')
    OR es_creador_proyecto(proyecto_id)
  );

-- tareas_hilos
DROP POLICY IF EXISTS tareas_hilos_select ON tareas_hilos;
CREATE POLICY tareas_hilos_select ON tareas_hilos FOR SELECT
  USING (puede_ver_hilo(id));

DROP POLICY IF EXISTS tareas_hilos_insert ON tareas_hilos;
CREATE POLICY tareas_hilos_insert ON tareas_hilos FOR INSERT
  WITH CHECK (
    creado_por = auth.uid()
    AND (responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  );

DROP POLICY IF EXISTS tareas_hilos_update ON tareas_hilos;
CREATE POLICY tareas_hilos_update ON tareas_hilos FOR UPDATE
  USING (creado_por = auth.uid() OR responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  WITH CHECK (creado_por = auth.uid() OR responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'));

-- tareas: visibilidad hereda del hilo si tiene_hilo; si está suelta, cascada
-- propia (proyecto -> visibilidad de la tarea -> membresía).
DROP POLICY IF EXISTS tareas_select ON tareas;
CREATE POLICY tareas_select ON tareas FOR SELECT
  USING (
    creado_por = auth.uid()
    OR responsable_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR EXISTS (
      SELECT 1 FROM tareas_asignados ta
      WHERE ta.tarea_id = tareas.id AND ta.usuario_id = auth.uid() AND ta.activo
    )
    OR (hilo_id IS NOT NULL AND puede_ver_hilo(hilo_id))
    OR (
      hilo_id IS NULL AND proyecto_id IS NOT NULL AND visibilidad = 'publico'
      AND (
        (SELECT pr.visibilidad FROM tareas_proyectos pr WHERE pr.id = tareas.proyecto_id) = 'publico'
        OR EXISTS (
          SELECT 1 FROM tareas_proyectos_miembros m
          WHERE m.proyecto_id = tareas.proyecto_id AND m.usuario_id = auth.uid() AND m.activo
        )
      )
    )
  );

DROP POLICY IF EXISTS tareas_insert ON tareas;
CREATE POLICY tareas_insert ON tareas FOR INSERT
  WITH CHECK (
    creado_por = auth.uid()
    AND (responsable_id = auth.uid() OR tiene_permiso('tareas_gestionar_ajenas'))
  );

-- UPDATE: quien puede tocar la fila (creador/responsable/asignado/ajenas), y
-- completar una tarea con modo_completado <> 'manual' exige ser responsable
-- (o ajenas) — el botón "Realizar tarea" solo transporta, no completa.
DROP POLICY IF EXISTS tareas_update ON tareas;
CREATE POLICY tareas_update ON tareas FOR UPDATE
  USING (
    creado_por = auth.uid()
    OR responsable_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR EXISTS (
      SELECT 1 FROM tareas_asignados ta
      WHERE ta.tarea_id = tareas.id AND ta.usuario_id = auth.uid() AND ta.activo
    )
  )
  WITH CHECK (
    (
      creado_por = auth.uid()
      OR responsable_id = auth.uid()
      OR tiene_permiso('tareas_gestionar_ajenas')
      OR EXISTS (
        SELECT 1 FROM tareas_asignados ta
        WHERE ta.tarea_id = tareas.id AND ta.usuario_id = auth.uid() AND ta.activo
      )
    )
    AND (
      estado <> 'completada'
      OR modo_completado = 'manual'
      OR responsable_id = auth.uid()
      OR tiene_permiso('tareas_gestionar_ajenas')
    )
  );

-- es_responsable_o_creador_tarea(uuid) — SECURITY DEFINER: rompe la
-- recursión entre tareas_select (consulta tareas_asignados) y las
-- políticas de tareas_asignados (consultaban tareas directamente).
-- Mismo criterio que es_creador_proyecto().
CREATE OR REPLACE FUNCTION es_responsable_o_creador_tarea(p_tarea_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tareas t
    WHERE t.id = p_tarea_id AND (t.creado_por = auth.uid() OR t.responsable_id = auth.uid())
  );
$$;

-- es_asignado_tarea(uuid) — SECURITY DEFINER: tareas_asignados_select
-- necesita ver si el usuario está entre los co-asignados de la misma
-- tarea, pero un EXISTS directo sobre tareas_asignados dentro de su
-- propia política dispara la política de nuevo sobre sí misma
-- (recursión infinita). Mismo criterio que es_creador_proyecto().
CREATE OR REPLACE FUNCTION es_asignado_tarea(p_tarea_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tareas_asignados ta
    WHERE ta.tarea_id = p_tarea_id AND ta.usuario_id = auth.uid() AND ta.activo
  );
$$;

-- tareas_asignados
DROP POLICY IF EXISTS tareas_asignados_select ON tareas_asignados;
CREATE POLICY tareas_asignados_select ON tareas_asignados FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_o_creador_tarea(tarea_id)
    OR es_asignado_tarea(tarea_id)
  );

DROP POLICY IF EXISTS tareas_asignados_insert ON tareas_asignados;
CREATE POLICY tareas_asignados_insert ON tareas_asignados FOR INSERT
  WITH CHECK (
    tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_o_creador_tarea(tarea_id)
  );

DROP POLICY IF EXISTS tareas_asignados_update ON tareas_asignados;
CREATE POLICY tareas_asignados_update ON tareas_asignados FOR UPDATE
  USING (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_o_creador_tarea(tarea_id)
  )
  WITH CHECK (
    usuario_id = auth.uid()
    OR tiene_permiso('tareas_gestionar_ajenas')
    OR es_responsable_o_creador_tarea(tarea_id)
  );

-- tareas_plantillas / items: gateadas solo por la vista (recurso de equipo).
DROP POLICY IF EXISTS tareas_plantillas_select ON tareas_plantillas;
CREATE POLICY tareas_plantillas_select ON tareas_plantillas FOR SELECT
  USING (tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_insert ON tareas_plantillas;
CREATE POLICY tareas_plantillas_insert ON tareas_plantillas FOR INSERT
  WITH CHECK (creado_por = auth.uid() AND tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_update ON tareas_plantillas;
CREATE POLICY tareas_plantillas_update ON tareas_plantillas FOR UPDATE
  USING (tiene_permiso('tareas_plantillas'))
  WITH CHECK (tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_items_select ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_select ON tareas_plantillas_items FOR SELECT
  USING (tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_items_insert ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_insert ON tareas_plantillas_items FOR INSERT
  WITH CHECK (tiene_permiso('tareas_plantillas'));

DROP POLICY IF EXISTS tareas_plantillas_items_update ON tareas_plantillas_items;
CREATE POLICY tareas_plantillas_items_update ON tareas_plantillas_items FOR UPDATE
  USING (tiene_permiso('tareas_plantillas'))
  WITH CHECK (tiene_permiso('tareas_plantillas'));

-- tareas_eventos: lectura para auditoría o de los propios eventos. Sin
-- policy de INSERT/UPDATE/DELETE — entra solo por el trigger SECURITY DEFINER.
DROP POLICY IF EXISTS tareas_eventos_select ON tareas_eventos;
CREATE POLICY tareas_eventos_select ON tareas_eventos FOR SELECT
  USING (usuario_id = auth.uid() OR tiene_permiso('tareas_auditoria'));

-- usuarios_select: extendida para que cualquiera con acceso al módulo tareas
-- pueda listar usuarios activos (picker de asignados / miembros de proyecto).
-- Mismo criterio ya usado antes: reutilizar la policy de una tabla de
-- infraestructura cross-módulo en vez de crear una RPC nueva solo para esto.
DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT
  USING (
    id = auth.uid()
    OR tiene_permiso('usuarios_ver')
    OR tiene_permiso('tareas_lista')
    OR tiene_permiso('tareas_proyectos')
  );

-- ============================================================
-- GRANTs — RLS no alcanza sin esto (ver DECISIONES.md).
-- ============================================================
GRANT SELECT, INSERT, UPDATE ON public.tareas_proyectos TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_proyectos_miembros TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_hilos TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_asignados TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_plantillas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tareas_plantillas_items TO authenticated;
GRANT SELECT ON public.tareas_eventos TO authenticated;

-- ============================================================
-- Seed — submódulos del módulo tareas
-- ============================================================
INSERT INTO submodulos (codigo, modulo, tipo, nombre, orden)
VALUES
  ('tareas_lista', 'tareas', 'vista', 'Lista', 1),
  ('tareas_proyectos', 'tareas', 'vista', 'Proyectos', 2),
  ('tareas_plantillas', 'tareas', 'vista', 'Plantillas', 3),
  ('tareas_auditoria', 'tareas', 'vista', 'Auditoría', 4)
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'tareas_gestionar_ajenas', 'tareas', 'funcion', 'Gestionar tareas ajenas', id, 1
FROM submodulos WHERE codigo = 'tareas_lista'
ON CONFLICT DO NOTHING;

INSERT INTO submodulos (codigo, modulo, tipo, nombre, vista_id, orden)
SELECT 'tareas_proyectos_crear', 'tareas', 'funcion', 'Crear proyecto', id, 1
FROM submodulos WHERE codigo = 'tareas_proyectos'
ON CONFLICT DO NOTHING;
