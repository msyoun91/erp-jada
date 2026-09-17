-- ============================================================
-- 083 — Compartir y revocar son eventos
--
-- RECONSTRUIDO DESDE LA BASE (2026-09-17). Estos objetos ya estaban aplicados
-- y sin archivo: aparecieron al regenerar `database.types.ts` después de
-- sql/082 (BACKLOG.md → "Deriva base ↔ repo"). El archivo documenta lo que la
-- base ya tiene; correrlo de nuevo es idempotente y no cambia nada.
--
-- sql/068 dejó escrito que `compartido` y `revocado` se sumaban al enum
-- "cuando alguien los emita". Alguien los emitió:
--
--   1. El enum `tipo_evento` gana los dos valores.
--   2. `obras_emitir_eventos_grant`: un emisor genérico para las tres tablas
--      de grant directo. Solo cuando `activo` cambia de verdad.
--   3. `obras_puede_ver_compartido` / `puede_ver_compartido`: quién ve uno de
--      esos eventos.
--   4. La policy de SELECT de `eventos` suma la rama.
--
-- Quién ve el evento: el mismo criterio de sql/069, no uno nuevo. La policy
-- pregunta por el usuario **nombrado en el grant** (`detalle->>'usuario_id'`),
-- y el EXISTS corre INVOKER, o sea bajo la RLS de quien lee. Traducido: ves el
-- evento si ves la fila de grant que lo generó. Sin regla propia, sin copia.
--
-- No filtra `activo`: revocar apaga la fila, y si filtrara, el evento
-- `revocado` desaparecería junto con lo que informa. Misma razón que en
-- sql/069 con los vínculos dados de baja.
--
-- Ninguno de los tres entes declara estos eventos en `entes.disparos`, así que
-- hoy no disparan plantillas: `obras_compartir_*` y `obras_revocar_*` son
-- DEFINER, y el disparo solo corre como quien actúa (la guarda de
-- `current_user` de sql/055). Se registran, no disparan — igual que `baja` y
-- `reactivacion` de una obra.
--
-- Ver decisiones/global/entes.md → "Los eventos van a una tabla `eventos`".
-- ============================================================

-- ============================================================
-- 1. El enum
-- ============================================================
-- Fuera de transacción con el resto si el motor lo pide: un valor nuevo de
-- enum no se puede usar en la misma transacción que lo creó.
ALTER TYPE tipo_evento ADD VALUE IF NOT EXISTS 'compartido';
ALTER TYPE tipo_evento ADD VALUE IF NOT EXISTS 'revocado';

-- ============================================================
-- 2. El emisor
-- ============================================================
-- TG_ARGV = (ente, columna del registro). Uno solo para las tres tablas: lo
-- único que cambia entre ellas es de qué columna sale el id.
--
-- `activo` sin cambiar → nada. Compartir lo ya compartido reescribe
-- `otorgada_por` y `updated_at` (el ON CONFLICT de `obras_compartir_*`), y eso
-- no es un evento: el acceso no se movió.
CREATE OR REPLACE FUNCTION obras_emitir_eventos_grant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_nueva jsonb   := to_jsonb(NEW);
  v_vieja jsonb   := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_antes boolean := COALESCE((v_vieja->>'activo')::boolean, false);
  v_ahora boolean := COALESCE((v_nueva->>'activo')::boolean, false);
BEGIN
  IF v_antes = v_ahora THEN
    RETURN NULL;
  END IF;

  PERFORM emitir_evento(
    TG_ARGV[0],
    (v_nueva->>TG_ARGV[1])::uuid,
    CASE WHEN v_ahora THEN 'compartido' ELSE 'revocado' END::tipo_evento,
    jsonb_strip_nulls(jsonb_build_object(
      'usuario_id',        v_nueva->'usuario_id',
      'otorgada_por',      v_nueva->'otorgada_por',
      'origen_obra_id',    v_nueva->'origen_obra_id',
      'origen_empresa_id', v_nueva->'origen_empresa_id'
    ))
  );
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_emitir_eventos_grant() FROM PUBLIC;

DROP TRIGGER IF EXISTS emitir_eventos ON obras_obra_compartida;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo ON obras_obra_compartida
  FOR EACH ROW EXECUTE FUNCTION obras_emitir_eventos_grant('obra', 'obra_id');

DROP TRIGGER IF EXISTS emitir_eventos ON obras_empresa_compartida;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo ON obras_empresa_compartida
  FOR EACH ROW EXECUTE FUNCTION obras_emitir_eventos_grant('empresa', 'empresa_id');

DROP TRIGGER IF EXISTS emitir_eventos ON obras_persona_compartida;
CREATE TRIGGER emitir_eventos
  AFTER INSERT OR UPDATE OF activo ON obras_persona_compartida
  FOR EACH ROW EXECUTE FUNCTION obras_emitir_eventos_grant('persona', 'persona_id');

-- El grant contextual (sql/082) no emite: no es un acceso que alguien decidió
-- dar, es el reflejo de una obra o una empresa que ya se compartió, y esa sí
-- emitió su evento.

-- ============================================================
-- 3. Quién lo ve
-- ============================================================
CREATE OR REPLACE FUNCTION obras_puede_ver_compartido(p_tipo text, p_id uuid, p_usuario_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'obra' THEN EXISTS (
      SELECT 1 FROM obras_obra_compartida g WHERE g.obra_id = p_id AND g.usuario_id = p_usuario_id
    )
    WHEN 'empresa' THEN EXISTS (
      SELECT 1 FROM obras_empresa_compartida g WHERE g.empresa_id = p_id AND g.usuario_id = p_usuario_id
    )
    WHEN 'persona' THEN EXISTS (
      SELECT 1 FROM obras_persona_compartida g WHERE g.persona_id = p_id AND g.usuario_id = p_usuario_id
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION puede_ver_compartido(p_ente text, p_id uuid, p_usuario_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT CASE e.modulo
              WHEN 'obras' THEN obras_puede_ver_compartido(e.codigo, p_id, p_usuario_id)
            END
       FROM entes e
      WHERE e.codigo = p_ente),
    false
  );
$$;

-- INVOKER llamada desde una policy: las dos necesitan EXECUTE para quien lee,
-- como el par de sql/069.
REVOKE EXECUTE ON FUNCTION public.obras_puede_ver_compartido(text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obras_puede_ver_compartido(text, uuid, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.puede_ver_compartido(text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.puede_ver_compartido(text, uuid, uuid) TO authenticated;

-- ============================================================
-- 4. La policy
-- ============================================================
-- Una rama más del CASE de sql/069, por lo mismo: el resto de los eventos no
-- paga el EXISTS.
DROP POLICY eventos_select ON eventos;
CREATE POLICY eventos_select ON eventos FOR SELECT TO authenticated
  USING (
    etiqueta_registro(ente, registro_id) IS NOT NULL
    AND CASE
          WHEN evento IN ('relacion_alta', 'relacion_baja')
            THEN puede_ver_relacion(ente, registro_id, detalle->>'ente', (detalle->>'registro_id')::uuid)
          WHEN evento IN ('compartido', 'revocado')
            THEN puede_ver_compartido(ente, registro_id, (detalle->>'usuario_id')::uuid)
          ELSE true
        END
  );
