-- ============================================================
-- 038 — Notificaciones
--
-- Tres cosas del sistema ya pedían un canal de aviso y no lo tenían: el
-- rechazo de un alta congelada (`BACKLOG.md`, el caso que la 033 dejó abierto:
-- la fila sale de los listados y el motivo solo se lee entrando por URL
-- directa), la transferencia de una obra, y la asignación de una tarea.
-- Ninguna se enteraba sola.
--
-- **No es un motor.** No hay reglas configurables, ni plantillas de mensaje,
-- ni suscripciones: una tabla, tres triggers colgados de escrituras que ya
-- ocurrían, y una función de lectura. Cada tipo nuevo es un `PERFORM
-- notificar(...)` más, no una entrada en un registro de reglas.
--
-- **Es infra, no módulo.** Mismo lugar que `usuario_widgets` y
-- `usuario_tutorial`: prefijo `usuario_`, RLS directo por `auth.uid()`, sin
-- submódulo y sin vista propia. Nadie necesita permiso para recibir avisos de
-- cosas que ya puede ver — el permiso lo puso la entidad, no la notificación.
--
-- **La notificación apunta, no copia.** Guarda `(entidad, entidad_id)` y el
-- texto se arma al leer, con la RLS del que lee. Si copiara el título, la
-- regla de `sql/013` —perder la asignación es dejar de ver— se rompería desde
-- la campanita: la notificación seguiría mostrando el título de una tarea que
-- ya no se puede abrir. Por eso `notificaciones_listar` es SECURITY INVOKER y
-- resuelve con INNER JOIN contra cada tabla: lo que la RLS no devuelve, no
-- aparece.
--
-- **Solo eventos, sin cron.** Lo que pasó una vez y tiene destinatario único
-- es una fila. Lo que es estado —"tenés 3 vencidas"— es una consulta al abrir
-- (`notificaciones_avisos`), no filas que alguien tenga que generar y limpiar.
-- Mismo criterio que `reactivar_posponer_vencidos()`: se calcula al leer.
--
-- **Al que le sacaron la obra no se le avisa.** `obras_transferencias` existe
-- para contestar "¿por qué no la veo más?", pero justamente ya no la ve:
-- `obras_transferencias_select` y `obras_select` son `obras_puede_ver_obra`.
-- Un aviso con el nombre de la obra sería la única grieta del módulo, y uno
-- sin el nombre no dice nada. Esa pregunta la contesta
-- `obras_auditoria_transferencias`, que ya existe.
-- ============================================================

-- ============================================================
-- 1. Enum
-- ============================================================
DO $$ BEGIN
  CREATE TYPE tipo_notificacion AS ENUM (
    'alta_aprobada', 'alta_rechazada', 'obra_transferida', 'tarea_asignada'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 2. La tabla
--
-- `entidad` es text con CHECK y no enum: es el discriminador de a qué tabla
-- apunta `entidad_id`, con el mismo vocabulario y la misma forma que
-- `obras_aprobaciones.tipo`. Los enums de este proyecto son estados, no
-- nombres de tabla.
-- ============================================================
CREATE TABLE IF NOT EXISTS usuario_notificaciones (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES usuarios(id),
  tipo        tipo_notificacion NOT NULL,
  entidad     text NOT NULL CHECK (entidad IN (
                'obra', 'empresa', 'persona', 'obra_empresa', 'obra_persona', 'tarea'
              )),
  entidad_id  uuid NOT NULL,
  actor_id    uuid REFERENCES usuarios(id),
  leida_at    timestamptz,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_usuario_notificaciones_bandeja
  ON usuario_notificaciones (usuario_id, created_at DESC) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_usuario_notificaciones_actor
  ON usuario_notificaciones (actor_id);

DROP TRIGGER IF EXISTS set_updated_at ON usuario_notificaciones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON usuario_notificaciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE usuario_notificaciones ENABLE ROW LEVEL SECURITY;

-- Sin policy ni GRANT de INSERT: la escribe `notificar()`, que es DEFINER y
-- solo se llama desde triggers. Una notificación que el cliente pudiera
-- insertar sería un canal para escribirle a otro usuario.
DROP POLICY IF EXISTS usuario_notificaciones_select ON usuario_notificaciones;
CREATE POLICY usuario_notificaciones_select ON usuario_notificaciones FOR SELECT
  USING (usuario_id = auth.uid());

DROP POLICY IF EXISTS usuario_notificaciones_update ON usuario_notificaciones;
CREATE POLICY usuario_notificaciones_update ON usuario_notificaciones FOR UPDATE
  USING (usuario_id = auth.uid())
  WITH CHECK (usuario_id = auth.uid());

GRANT SELECT ON public.usuario_notificaciones TO authenticated;
-- GRANT por columna: marcar leída y descartar son lo único que el dueño hace
-- sobre su propia fila. RLS no acota columnas, el GRANT sí.
GRANT UPDATE (leida_at, activo) ON public.usuario_notificaciones TO authenticated;

-- ============================================================
-- 3. Un solo lugar donde nace una notificación
--
-- Acá vive "no te notifiques a vos mismo": en cada trigger sería la misma
-- regla escrita tres veces. `IS DISTINCT FROM` y no `<>` porque con
-- `auth.uid()` NULL (service_role, SQL editor) la comparación daría NULL y la
-- notificación se perdería en silencio.
-- ============================================================
CREATE OR REPLACE FUNCTION notificar(
  p_usuario_id uuid,
  p_tipo       tipo_notificacion,
  p_entidad    text,
  p_entidad_id uuid,
  p_actor_id   uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_usuario_id IS NULL OR p_entidad_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT (p_usuario_id IS DISTINCT FROM p_actor_id) THEN
    RETURN;
  END IF;

  INSERT INTO usuario_notificaciones (usuario_id, tipo, entidad, entidad_id, actor_id)
  VALUES (p_usuario_id, p_tipo, p_entidad, p_entidad_id, p_actor_id);
END;
$$;

-- ============================================================
-- 4. Quién pidió el alta — extraído de `obras_pendientes()`
--
-- La cola ya sabía mapear las cinco tablas a su solicitante, pero adentro de
-- su propio UNION. El trigger de la decisión necesita el mismo mapa, y una
-- segunda copia sería la regla escrita dos veces. Va al lado de
-- `obras_etiqueta` (sql/033), que es la misma idea para el texto.
--
-- No filtra por `pendiente` ni por `activo`: se llama después de resolver,
-- cuando un rechazo ya dejó la fila desactivada.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_solicitante(p_tipo text, p_id uuid)
RETURNS uuid
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra'    THEN (SELECT o.responsable_id FROM obras o WHERE o.id = p_id)
    WHEN 'empresa' THEN (SELECT e.creado_por FROM obras_empresas e WHERE e.id = p_id)
    WHEN 'persona' THEN (SELECT p.creado_por FROM obras_personas p WHERE p.id = p_id)
    WHEN 'obra_empresa' THEN (
      SELECT o.responsable_id
      FROM obras_obra_empresa oe
      JOIN obras o ON o.id = oe.obra_id
      WHERE oe.id = p_id
    )
    WHEN 'obra_persona' THEN (
      SELECT o.responsable_id
      FROM obras_obra_persona op
      JOIN obras o ON o.id = op.obra_id
      WHERE op.id = p_id
    )
  END;
$$;

-- ============================================================
-- 4.1. `obras_etiqueta` pasa a SECURITY INVOKER
--
-- La bandeja necesita el texto de las cinco tablas, y ese lugar ya existe
-- (sql/033). Pero era DEFINER y sin GRANT: llamarla desde una función INVOKER
-- daba `42501 permission denied for function obras_etiqueta`, y otorgarle
-- EXECUTE tal como estaba habría hecho de ella un bypass — con el uuid de una
-- obra ajena (que el aviso ciego de `sql/037` devuelve con el nombre en NULL,
-- a propósito) cualquiera habría recuperado el nombre.
--
-- Como INVOKER devuelve NULL para lo que el que pregunta no ve, así que
-- otorgarla es inofensivo. Sus dos llamadores —`obras_pendientes` y
-- `obras_resolver_pendiente`— no cambian: son DEFINER de `postgres`, que tiene
-- BYPASSRLS, y una función INVOKER llamada desde ahí sigue corriendo como
-- `postgres`. Verificado contra las dos antes y después.
-- ============================================================
CREATE OR REPLACE FUNCTION obras_etiqueta(p_tipo text, p_id uuid)
RETURNS text
LANGUAGE sql STABLE SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra' THEN (SELECT o.nombre FROM obras o WHERE o.id = p_id)
    WHEN 'empresa' THEN (SELECT e.razon_social FROM obras_empresas e WHERE e.id = p_id)
    WHEN 'persona' THEN (
      SELECT btrim(p.nombre || ' ' || coalesce(p.apellido, ''))
      FROM obras_personas p WHERE p.id = p_id
    )
    WHEN 'obra_empresa' THEN (
      SELECT e.razon_social || ' → ' || o.nombre
      FROM obras_obra_empresa oe
      JOIN obras_empresas e ON e.id = oe.empresa_id
      JOIN obras o          ON o.id = oe.obra_id
      WHERE oe.id = p_id
    )
    WHEN 'obra_persona' THEN (
      SELECT btrim(p.nombre || ' ' || coalesce(p.apellido, '')) || ' → ' || o.nombre
      FROM obras_obra_persona op
      JOIN obras_personas p ON p.id = op.persona_id
      JOIN obras o          ON o.id = op.obra_id
      WHERE op.id = p_id
    )
  END;
$$;

-- `obras_pendientes()` pasa a usarla. Mismo resultado, sin el mapa duplicado.
CREATE OR REPLACE FUNCTION obras_pendientes()
RETURNS TABLE (
  tipo        text,
  registro_id uuid,
  etiqueta    text,
  motivo      text,
  solicitante text,
  created_at  timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_pendientes') THEN
    RAISE EXCEPTION 'Sin permiso para ver las autorizaciones pendientes' USING ERRCODE = 'OB013';
  END IF;

  RETURN QUERY
  WITH filas AS (
    SELECT 'obra'::text AS tipo, o.id, o.created_at,
           'Posible duplicado de una obra que ya existe'::text AS motivo
    FROM obras o WHERE o.pendiente AND o.activo
    UNION ALL
    SELECT 'empresa', e.id, e.created_at,
           'Posible duplicado de una empresa que ya existe'
    FROM obras_empresas e WHERE e.pendiente AND e.activo
    UNION ALL
    SELECT 'persona', p.id, p.created_at,
           'Posible duplicado de una persona que ya existe'
    FROM obras_personas p WHERE p.pendiente AND p.activo
    UNION ALL
    SELECT 'obra_empresa', oe.id, oe.created_at,
           'Empresa cargada por otro usuario'
    FROM obras_obra_empresa oe WHERE oe.pendiente AND oe.activo
    UNION ALL
    SELECT 'obra_persona', op.id, op.created_at,
           'Persona cargada por otro usuario'
    FROM obras_obra_persona op WHERE op.pendiente AND op.activo
  )
  SELECT f.tipo, f.id, obras_etiqueta(f.tipo, f.id), f.motivo, u.nombre, f.created_at
  FROM filas f
  JOIN usuarios u ON u.id = obras_solicitante(f.tipo, f.id)
  ORDER BY f.created_at
  LIMIT 500;
END;
$$;

-- ============================================================
-- 5. Los tres triggers
--
-- Cuelgan de escrituras que ya existían y cuyo destinatario ya está en la
-- fila: no hay fan-out ni cálculo de visibilidad al escribir.
-- ============================================================

-- 5.1 — La decisión sobre un alta congelada (sql/033).
-- Sobre `obras_aprobaciones` y no adentro de `obras_resolver_pendiente`: esa
-- tabla es el registro de que la decisión ocurrió, y ya trae tipo, registro y
-- quién decidió.
CREATE OR REPLACE FUNCTION notificar_decision_obra()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM notificar(
    obras_solicitante(NEW.tipo, NEW.registro_id),
    CASE WHEN NEW.aprobada THEN 'alta_aprobada' ELSE 'alta_rechazada' END::tipo_notificacion,
    NEW.tipo,
    NEW.registro_id,
    NEW.decidido_por
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_decision_obra ON obras_aprobaciones;
CREATE TRIGGER trg_notificar_decision_obra
  AFTER INSERT ON obras_aprobaciones
  FOR EACH ROW EXECUTE FUNCTION notificar_decision_obra();

-- 5.2 — Recibir una obra.
CREATE OR REPLACE FUNCTION notificar_transferencia_obra()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM notificar(NEW.a_usuario_id, 'obra_transferida', 'obra', NEW.obra_id, NEW.ejecutada_por);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_transferencia_obra ON obras_transferencias;
CREATE TRIGGER trg_notificar_transferencia_obra
  AFTER INSERT ON obras_transferencias
  FOR EACH ROW EXECUTE FUNCTION notificar_transferencia_obra();

-- 5.3 — Que te pongan en una tarea.
--
-- `pg_trigger_depth() > 1` filtra la copia de asignados que hace
-- `generar_recurrencia`: una tarea diaria mandaría un aviso por día a cada
-- asignado, y ahí nadie asignó a nadie — la fila se copió sola. Un INSERT de
-- la app (o de las funciones de `sql/023`, que no son triggers) entra en
-- profundidad 1.
--
-- Las guardas van en el cuerpo y no en un `WHEN`: Postgres rechaza referencias
-- a OLD en el WHEN de un trigger declarado INSERT OR UPDATE.
CREATE OR REPLACE FUNCTION notificar_tarea_asignada()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT NEW.activo THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.activo THEN
    RETURN NEW;
  END IF;

  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  PERFORM notificar(NEW.usuario_id, 'tarea_asignada', 'tarea', NEW.tarea_id, auth.uid());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notificar_tarea_asignada ON tareas_asignados;
CREATE TRIGGER trg_notificar_tarea_asignada
  AFTER INSERT OR UPDATE OF activo ON tareas_asignados
  FOR EACH ROW EXECUTE FUNCTION notificar_tarea_asignada();

-- ============================================================
-- 6. La bandeja
--
-- SECURITY INVOKER: cada rama es un INNER JOIN contra la tabla apuntada, así
-- que la RLS del que lee decide qué sobrevive. Una notificación cuya entidad
-- dejó de ser visible desaparece de la lista — no hay una segunda copia de la
-- regla de visibilidad que se pueda desincronizar con la primera.
--
-- El texto sale de `obras_etiqueta` (sql/033) y no de un CASE propio: ese es
-- el único lugar donde una fila de las cinco tablas se convierte en texto.
-- Llamarla es seguro acá aunque sea DEFINER — el JOIN de arriba ya probó que
-- el lector ve la fila.
--
-- Los vínculos llevan a la obra: no tienen ficha propia, y el motivo del
-- rechazo sale igual de la fila del vínculo.
-- ============================================================
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
    SELECT n.id, obras_etiqueta('obra_empresa', oe.id), oe.motivo_rechazo, 'obra', oe.obra_id
    FROM mias n JOIN obras_obra_empresa oe ON oe.id = n.entidad_id
    WHERE n.entidad = 'obra_empresa'
    UNION ALL
    SELECT n.id, obras_etiqueta('obra_persona', op.id), op.motivo_rechazo, 'obra', op.obra_id
    FROM mias n JOIN obras_obra_persona op ON op.id = n.entidad_id
    WHERE n.entidad = 'obra_persona'
    UNION ALL
    SELECT n.id, t.titulo, NULL::text, 'tarea', t.id
    FROM mias n JOIN tareas t ON t.id = n.entidad_id
    WHERE n.entidad = 'tarea'
  )
  SELECT n.id, n.tipo, r.etiqueta, r.motivo, u.nombre, r.destino, r.destino_id,
         n.leida_at IS NOT NULL, n.created_at
  FROM mias n
  JOIN resuelta r      ON r.notificacion_id = n.id
  LEFT JOIN usuarios u ON u.id = n.actor_id
  ORDER BY n.created_at DESC;
$$;

-- ============================================================
-- 7. Lo que no es un evento
--
-- "Tenés 3 vencidas" no es algo que pasó: es el estado de hoy. Como fila
-- necesitaría un cron que la cree a medianoche y otra pasada que la borre
-- cuando la tarea se completa. Como consulta es esto, y no puede quedar vieja.
--
-- INVOKER, pero el filtro por asignado va explícito: la RLS deja ver bastante
-- más que lo propio (lo público, lo del proyecto), y esto cuenta solo lo mío.
-- ============================================================
CREATE OR REPLACE FUNCTION notificaciones_avisos()
RETURNS TABLE (vencidas int, vencen_hoy int)
LANGUAGE sql STABLE SET search_path = public
AS $$
  SELECT
    count(*) FILTER (WHERE t.fecha_vencimiento < current_date)::int,
    count(*) FILTER (WHERE t.fecha_vencimiento = current_date)::int
  FROM tareas t
  JOIN tareas_asignados a ON a.tarea_id = t.id AND a.usuario_id = auth.uid() AND a.activo
  LEFT JOIN tareas_hilos h ON h.id = t.hilo_id
  WHERE t.activo
    AND t.estado IN ('pendiente', 'en_progreso')
    AND t.fecha_vencimiento IS NOT NULL
    AND t.fecha_vencimiento <= current_date
    AND (t.posponer_hasta IS NULL OR t.posponer_hasta < current_date)
    AND (h.id IS NULL OR h.posponer_hasta IS NULL OR h.posponer_hasta < current_date);
$$;

-- ============================================================
-- 8. GRANTs de ejecución
--
-- PostgREST expone toda función a PUBLIC por default. `notificar` y los tres
-- triggers no se llaman nunca por RPC (sql/006, mismo criterio).
-- ============================================================
REVOKE EXECUTE ON FUNCTION notificar(uuid, tipo_notificacion, text, uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION notificar_decision_obra()      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION notificar_transferencia_obra() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION notificar_tarea_asignada()     FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION obras_solicitante(text, uuid)  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION notificaciones_listar(int)     FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION notificaciones_avisos()        FROM PUBLIC;

GRANT EXECUTE ON FUNCTION notificaciones_listar(int) TO authenticated;
GRANT EXECUTE ON FUNCTION notificaciones_avisos()    TO authenticated;
-- Ahora sí: como INVOKER no devuelve nada que el que pregunta no vea (ver 4.1).
GRANT EXECUTE ON FUNCTION obras_etiqueta(text, uuid) TO authenticated;
