-- ============================================================
-- 069 — Un evento de relación lo ve quien ve el vínculo
--
-- sql/068 dejó la RLS de `eventos` en "ves el ente". Para una relación no
-- alcanza: el receptor de una obra compartida ve la obra, pero de sus vínculos
-- solo los suyos y lo que le tildaron (sql/051). Por `eventos` leía además el
-- id y el rol de cada persona o empresa que no le compartieron.
--
--   1. `obras_puede_ver_relacion`: ¿quien pregunta ve algún vínculo de ese
--      par? Un EXISTS sobre la tabla puente con su RLS: la regla sigue siendo
--      la de las policies de vínculo, sin copia.
--   2. `puede_ver_relacion`: la genérica de core, una rama por módulo.
--   3. La policy de SELECT de `eventos` la pide para `relacion_alta` y
--      `relacion_baja`.
--
-- Por par y no por fila: `detalle` no guarda qué fila emitió, y un par
-- desvinculado y vuelto a vincular son dos filas. Quien ve una ve todos los
-- eventos del par. Las policies de vínculo no filtran `activo`, así que la
-- baja sigue viéndose.
--
-- Descartado: pedir que se vean los dos entes. Es una segunda regla, y erra
-- para los dos lados: el responsable dejaría de ver lo que sumó un receptor
-- con un contacto privado suyo, y el receptor vería un vínculo que la policy
-- le oculta si la persona es suya pero la vinculó el responsable.
--
-- Ver decisiones/global/entes.md → "Un evento de relación lo ve quien ve el
-- vínculo".
-- ============================================================

-- ============================================================
-- 1. La rama de Obras
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_ver_relacion(p_tipo text, p_id uuid, p_ente_rel text, p_id_rel uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE p_tipo || ':' || p_ente_rel
    WHEN 'obra:empresa' THEN EXISTS (
      SELECT 1 FROM obras_obra_empresa v WHERE v.obra_id = p_id AND v.empresa_id = p_id_rel
    )
    WHEN 'obra:persona' THEN EXISTS (
      SELECT 1 FROM obras_obra_persona v WHERE v.obra_id = p_id AND v.persona_id = p_id_rel
    )
    ELSE false
  END;
$$;

-- ============================================================
-- 2. La genérica
-- ============================================================
CREATE OR REPLACE FUNCTION puede_ver_relacion(p_ente text, p_id uuid, p_ente_rel text, p_id_rel uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT CASE e.modulo
              WHEN 'obras' THEN obras_puede_ver_relacion(e.codigo, p_id, p_ente_rel, p_id_rel)
            END
       FROM entes e
      WHERE e.codigo = p_ente),
    false
  );
$$;

-- INVOKER llamada desde una policy: las dos necesitan EXECUTE para quien lee,
-- como `obras_relacionados_obra` (sql/060).
REVOKE EXECUTE ON FUNCTION public.obras_puede_ver_relacion(text, uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_puede_ver_relacion(text, uuid, text, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.puede_ver_relacion(text, uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.puede_ver_relacion(text, uuid, text, uuid) TO authenticated;

-- ============================================================
-- 3. La policy
-- ============================================================
-- CASE y no OR: garantiza que el resto de los eventos no pague el EXISTS.
DROP POLICY eventos_select ON eventos;
CREATE POLICY eventos_select ON eventos FOR SELECT TO authenticated
  USING (
    etiqueta_registro(ente, registro_id) IS NOT NULL
    AND CASE WHEN evento IN ('relacion_alta', 'relacion_baja')
             THEN puede_ver_relacion(ente, registro_id, detalle->>'ente', (detalle->>'registro_id')::uuid)
             ELSE true
        END
  );
