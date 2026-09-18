-- sql/099 — sacar un contacto de la obra corta, desactivar la obra archiva
--
-- Dos preguntas que el BACKLOG dejó abiertas en la segunda pasada de la
-- auditoría de compartir/transferir, resueltas por el usuario el 2026-09-18.
--
-- 1 · El grant contextual muere con el vínculo, de verdad.
--
-- MODEL A lo escribió como "muere con el vínculo — validado en vivo, sin
-- trigger de limpieza". Validado en vivo no muere: duerme. A comparte O con C
-- tildando P, saca a P de O (C deja de verlo), lo vuelve a vincular, y C
-- recupera el teléfono sin que nadie haya tildado nada. Mientras duerme no se
-- ve en ningún lado —el checklist solo ofrece lo vinculado y la vista
-- Compartido lo filtra desde sql/094—, así que nadie lo puede revocar. Ahora
-- apagar un vínculo apaga los grants anclados en él, y volver a vincular pide
-- volver a tildar. `obras_ctx_vinculo_vivo` sigue dentro de `obras_ctx_vigente`:
-- es la barrera de acceso, y la limpieza la vuelve redundante, no innecesaria.
--
-- 2 · Desactivar una obra es archivarla para todos.
--
-- El listado ya la escondía para todos, pero por URL, por el chip de una tarea
-- o desde la vista Compartido el receptor la seguía abriendo: veía teléfonos
-- con ?ctx= y sumaba vínculos, mientras el responsable no podía editar nada
-- (`obras_es_mi_obra` exige activa). Ahora "compartida conmigo" exige que la
-- obra esté activa, y esa regla vive en `obras_obra_compartida_con`: por ahí
-- pasan las policies de vínculos, la ficha y —vía `obras_puede_ver_obra_de`—
-- los grants contextuales y el chip. Validado en vivo y no en cascada, a
-- propósito: `modelo.md` decidió que desactivar no toca los vínculos "para
-- reactivar tal como estaba", y eso ahora incluye lo compartido.
--
-- `obras_select` NO cambia: el receptor sigue viendo la fila, que es identidad
-- (nombre, datos generales), no contenido. Es lo que deja resolver el aviso de
-- la sección 4 bajo su RLS —la notificación apunta, no copia— y lo que hace que
-- el chip de la tarea siga diciendo qué obra era. Misma separación que personas:
-- la policy autoriza identidad, la ficha es otra puerta.
--
-- 3 · Una obra rechazada no se reactiva.
--
-- Rechazar deja `activo = false` con `motivo_rechazo`, y `obras_set_activo`
-- aceptaba devolverla a `true`: salteaba la autorización. Nadie llegaba porque
-- la UI no tenía "Reactivar"; ahora lo tiene.
--
-- 4 · Aviso a quien la tenía compartida (`obra_desactivada`).
--
-- 5 · La vista Compartido deja de listar lo anclado en obras desactivadas, y no
-- nombra un ancla que quien mira no puede abrir. Ese nombre no se mostraba en
-- pantalla, pero viajaba al navegador en el payload del server component.

-- ── 1 · El grant contextual muere con el vínculo ─────────────────────────────

CREATE OR REPLACE FUNCTION obras_cascada_desactivar()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'obras_empresas' THEN
    UPDATE obras_persona_empresa SET activo = false
    WHERE empresa_id = OLD.id AND activo;

  ELSIF TG_TABLE_NAME = 'obras_personas' THEN
    UPDATE obras_persona_empresa SET activo = false
    WHERE persona_id = OLD.id AND activo;

  ELSIF TG_TABLE_NAME = 'obras_obra_persona' THEN
    UPDATE obras_obra_referente SET activo = false
    WHERE obra_id = OLD.obra_id AND persona_id = OLD.persona_id AND activo;

    -- El unique parcial `WHERE activo` garantiza que no queda otro vínculo vivo
    -- con el mismo par: apagado este, el ancla se fue.
    UPDATE obras_persona_grant_contextual SET activo = false
    WHERE obra_id = OLD.obra_id AND persona_id = OLD.persona_id AND activo;

  ELSIF TG_TABLE_NAME = 'obras_obra_empresa' THEN
    UPDATE obras_empresa_grant_contextual SET activo = false
    WHERE obra_id = OLD.obra_id AND empresa_id = OLD.empresa_id AND activo;

  ELSIF TG_TABLE_NAME = 'obras_persona_empresa' THEN
    UPDATE obras_persona_grant_contextual SET activo = false
    WHERE empresa_id = OLD.empresa_id AND persona_id = OLD.persona_id AND activo;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS cascada_desactivar ON obras_obra_empresa;
CREATE TRIGGER cascada_desactivar AFTER UPDATE ON obras_obra_empresa
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION obras_cascada_desactivar();

DROP TRIGGER IF EXISTS cascada_desactivar ON obras_persona_empresa;
CREATE TRIGGER cascada_desactivar AFTER UPDATE ON obras_persona_empresa
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION obras_cascada_desactivar();

-- Lo que ya estaba dormido al aplicar. 0 filas el 2026-09-18.
UPDATE obras_persona_grant_contextual g SET activo = false
WHERE g.activo
  AND NOT obras_ctx_vinculo_vivo('persona', g.persona_id,
        CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
        coalesce(g.obra_id, g.empresa_id));

UPDATE obras_empresa_grant_contextual g SET activo = false
WHERE g.activo
  AND NOT obras_ctx_vinculo_vivo('empresa', g.empresa_id, 'obra', g.obra_id);

-- ── 2 · Compartida conmigo exige obra activa ─────────────────────────────────

CREATE OR REPLACE FUNCTION obras_obra_compartida_con(p_obra_id uuid, p_usuario_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  -- Desactivar es archivar para todos (sql/099): la obra desactivada deja de
  -- estar compartida sin tocar la fila de grant, así reactivarla la devuelve.
  SELECT EXISTS (
    SELECT 1 FROM public.obras_obra_compartida c
    JOIN public.obras o ON o.id = c.obra_id
    WHERE c.obra_id = p_obra_id AND c.usuario_id = p_usuario_id AND c.activo
      AND o.activo
  );
$$;

CREATE OR REPLACE FUNCTION obras_puede_ver_obra_de(p_obra_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM obras o
    WHERE o.id = p_obra_id
      AND (
        (o.responsable_id = p_usuario AND usuario_tiene_permiso(p_usuario, 'obras_ver'))
        OR usuario_tiene_permiso(p_usuario, 'obras_transferir')
        OR (
          usuario_tiene_permiso(p_usuario, 'obras_ver')
          AND obras_obra_compartida_con(o.id, p_usuario)
        )
      )
  );
$$;

-- ── 3 · Una obra rechazada no se reactiva ────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_set_activo(p_obra_id uuid, p_activo boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_desactivar') THEN
    RAISE EXCEPTION 'Sin permiso para desactivar obras' USING ERRCODE = 'OB007';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM obras WHERE id = p_obra_id AND responsable_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'La obra no existe o no sos su responsable' USING ERRCODE = 'OB008';
  END IF;

  IF p_activo AND EXISTS (
    SELECT 1 FROM obras WHERE id = p_obra_id AND motivo_rechazo IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Esta obra fue rechazada: no se puede reactivar.' USING ERRCODE = 'OB035';
  END IF;

  UPDATE obras SET activo = p_activo WHERE id = p_obra_id;
END;
$$;

-- ── 4 · Aviso a quien la tenía compartida ────────────────────────────────────

ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'obra_desactivada';

-- También corre al rechazar un alta pendiente que ya estaba compartida: para el
-- receptor es lo mismo, la obra se archivó. `notificar` saltea al actor.
CREATE OR REPLACE FUNCTION notificar_obra_desactivada()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM notificar(c.usuario_id, 'obra_desactivada', 'obra', NEW.id, auth.uid())
  FROM obras_obra_compartida c
  WHERE c.obra_id = NEW.id AND c.activo;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notificar_obra_desactivada() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notificar_obra_desactivada ON obras;
CREATE TRIGGER trg_notificar_obra_desactivada AFTER UPDATE OF activo ON obras
  FOR EACH ROW WHEN (OLD.activo AND NOT NEW.activo)
  EXECUTE FUNCTION notificar_obra_desactivada();

-- ── 5 · Vista Compartido ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION obras_compartidos_por_mi()
RETURNS TABLE(tipo text, entidad_id uuid, entidad_nombre text, usuario_id uuid,
              usuario_nombre text, origen_tipo text, origen_id uuid, origen_nombre text,
              compartida_el timestamptz, puedo_abrir boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT tiene_permiso('obras_compartido') THEN
    RAISE EXCEPTION 'Sin acceso a la vista Compartido' USING ERRCODE = 'OB027';
  END IF;

  RETURN QUERY
  -- Una obra la comparte su responsable, así que siempre la puede abrir.
  -- Desactivada no se lista: no abre nada para el receptor (sql/099).
  SELECT 'obra'::text, c.obra_id, o.nombre, c.usuario_id, u.nombre,
         NULL::text, NULL::uuid, NULL::text, c.created_at, true
  FROM obras_obra_compartida c
  JOIN obras o     ON o.id = c.obra_id
  JOIN usuarios u  ON u.id = c.usuario_id
  WHERE o.responsable_id = auth.uid() AND c.activo AND o.activo

  UNION ALL
  -- Un contextual lo lista quien manda sobre él: el dueño del contacto o el del
  -- ancla (sql/093). `usuario_id <> auth.uid()` saca las filas donde soy el
  -- receptor. `_vinculo_vivo` saca las que el estado 3 de transferir dejó
  -- activas sin vínculo debajo: no abren nada y simulaban un reparto. El nombre
  -- del ancla sale solo si quien mira la puede abrir: el dueño del contacto no
  -- siempre puede (sql/099).
  SELECT 'empresa'::text, g.empresa_id, e.razon_social, g.usuario_id, u.nombre,
         'obra'::text, g.obra_id,
         CASE WHEN obras_puede_ver_obra(g.obra_id) THEN a.nombre END,
         g.created_at,
         obras_puede_ver_empresa(g.empresa_id)
  FROM obras_empresa_grant_contextual g
  JOIN obras_empresas e ON e.id = g.empresa_id
  JOIN usuarios u       ON u.id = g.usuario_id
  JOIN obras a          ON a.id = g.obra_id AND a.activo
  WHERE g.activo AND g.usuario_id <> auth.uid()
    AND obras_ctx_autoridad('empresa', g.empresa_id, 'obra', g.obra_id)
    AND obras_ctx_vinculo_vivo('empresa', g.empresa_id, 'obra', g.obra_id)

  UNION ALL
  SELECT 'persona'::text, g.persona_id,
         btrim(p.nombre || ' ' || coalesce(p.apellido, '')),
         g.usuario_id, u.nombre,
         CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
         coalesce(g.obra_id, g.empresa_id),
         CASE WHEN g.obra_id IS NOT NULL
              THEN CASE WHEN obras_puede_ver_obra(g.obra_id) THEN a.nombre END
              ELSE CASE WHEN obras_puede_ver_empresa(g.empresa_id)
                        THEN (SELECT razon_social FROM obras_empresas WHERE id = g.empresa_id) END
         END,
         g.created_at,
         obras_puede_ver_persona(g.persona_id)
  FROM obras_persona_grant_contextual g
  JOIN obras_personas p ON p.id = g.persona_id
  JOIN usuarios u       ON u.id = g.usuario_id
  LEFT JOIN obras a     ON a.id = g.obra_id
  WHERE g.activo AND g.usuario_id <> auth.uid()
    AND (g.obra_id IS NULL OR a.activo)
    AND obras_ctx_autoridad('persona', g.persona_id,
          CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
          coalesce(g.obra_id, g.empresa_id))
    AND obras_ctx_vinculo_vivo('persona', g.persona_id,
          CASE WHEN g.obra_id IS NOT NULL THEN 'obra' ELSE 'empresa' END,
          coalesce(g.obra_id, g.empresa_id))

  ORDER BY 9 DESC
  LIMIT 500;
END;
$$;
