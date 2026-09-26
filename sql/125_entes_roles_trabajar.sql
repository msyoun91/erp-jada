-- sql/125 — core, antes de Contactos y Obras: roles por ente, "lo trabaja" y
-- los emisores que aprenden lo que la puente de contactos necesita.
--
-- - `entes.roles`: los roles que un contacto puede tener en un registro del
--   ente. Los declara el módulo del ente; los valida `contactos_vinculos`.
-- - `trabaja_registro(ente, id)`: si quien pregunta trabaja el registro (no
--   solo lo ve). Sin rama, false. Obras suma la suya en `sql/126`.
-- - `puede_abrir_registro(ente, id, usuario)`: "lo ve", por usuario explícito.
--   La pide "Ver contacto" (DEFINER), donde `etiqueta_registro` respondería
--   por el dueño de la función. Sin rama, false.
-- - `emitir_eventos_relacion`: un ente que varía por fila se pasa como el
--   nombre de su columna, y un vínculo con `hasta` está cerrado: cerrarlo es
--   la baja de sus roles.
-- - `emitir_eventos_registro`: un tercer argumento opcional con columnas que
--   se suman al `detalle` del evento `estado` (el motivo de pérdida de la obra).
--
-- Decisiones: `decisiones/contactos.md` (*Los roles de un vínculo los declara
-- el ente*, *El contacto en dos columnas*), `decisiones/global/entes.md` (*Ver
-- un registro no es trabajarlo*), `decisiones/obras.md` (*El motivo de
-- pérdida*). Verificado con `sql/tests/entes_eventos.sql`.

-- ============================================================
-- 1. entes.roles
-- ============================================================
ALTER TABLE public.entes ADD COLUMN IF NOT EXISTS roles text[] NOT NULL DEFAULT '{}';

-- ============================================================
-- 2. trabaja_registro — la genérica, sin ramas
-- ============================================================
-- Cada módulo reemplaza el cuerpo con su `CASE e.modulo`, como en
-- `etiqueta_registro`; el que no tiene rama contesta false.
CREATE OR REPLACE FUNCTION public.trabaja_registro(p_ente text, p_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT false;
$$;

REVOKE EXECUTE ON FUNCTION public.trabaja_registro(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.trabaja_registro(text, uuid) TO authenticated;

-- ============================================================
-- 3. puede_abrir_registro — "lo ve", por usuario explícito
-- ============================================================
-- La rama es `{modulo}_puede_ver_{ente}_de`, el mismo cuerpo que usan las
-- policies (GUIDE_ENTES §2.3). Sin GRANT: la llaman funciones DEFINER.
CREATE OR REPLACE FUNCTION public.puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT false;
$$;

REVOKE EXECUTE ON FUNCTION public.puede_abrir_registro(text, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. emitir_eventos_registro — columnas extra en el evento `estado`
-- ============================================================
-- TG_ARGV = (ente[, columna del dueño[, columnas del estado]]). La tercera,
-- separadas por coma: se suman al `detalle` si tienen valor. Un ente sin
-- dueño y con columnas pasa '' como segunda.
CREATE OR REPLACE FUNCTION public.emitir_eventos_registro()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ente    text    := TG_ARGV[0];
  v_dueno   text    := nullif(TG_ARGV[1], '');
  v_extras  text[]  := string_to_array(nullif(TG_ARGV[2], ''), ',');
  v_nueva   jsonb   := to_jsonb(NEW);
  v_vieja   jsonb   := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_activo  boolean := (v_nueva->>'activo')::boolean;
  v_estaba  boolean := (v_vieja->>'activo')::boolean;
  v_detalle jsonb;
  v_col     text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT v_activo THEN
      RETURN NULL;
    END IF;
    PERFORM emitir_evento(v_ente, NEW.id, 'alta');
  ELSIF v_activo AND NOT v_estaba THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'reactivacion');
  END IF;

  IF v_nueva ? 'estado' AND v_nueva->>'estado' IS DISTINCT FROM v_vieja->>'estado' THEN
    v_detalle := jsonb_build_object('estado', v_nueva->>'estado', 'anterior', v_vieja->>'estado');
    FOREACH v_col IN ARRAY coalesce(v_extras, '{}') LOOP
      IF v_nueva->>v_col IS NOT NULL THEN
        v_detalle := v_detalle || jsonb_build_object(v_col, v_nueva->v_col);
      END IF;
    END LOOP;
    PERFORM emitir_evento(v_ente, NEW.id, 'estado', v_detalle);
  END IF;

  IF TG_OP = 'UPDATE' AND v_dueno IS NOT NULL AND v_nueva->>v_dueno IS DISTINCT FROM v_vieja->>v_dueno THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'transferencia',
      jsonb_build_object('de', v_vieja->>v_dueno, 'a', v_nueva->>v_dueno));
  END IF;

  IF v_estaba AND NOT v_activo THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'baja');
  END IF;

  RETURN NULL;
END;
$$;

-- ============================================================
-- 5. emitir_eventos_relacion — el ente, de la fila; `hasta` cierra
-- ============================================================
-- TG_ARGV = (ente, su columna, ente relacionado, su columna). Un ente que
-- varía por fila se pasa como el nombre de su columna (`'ente'`): si la fila
-- la tiene, vale su valor. Por eso un código de ente nunca coincide con una
-- columna de la puente (GUIDE_ENTES §2.6). Un evento por rol que aparece o se
-- va: vincular con dos roles son dos altas, sacarle uno a un vínculo es una
-- baja, desactivarlo o cerrarlo (`hasta`, si la puente la tiene) es la baja de
-- todos. El evento es del ente, no del relacionado: "la obra suma un
-- arquitecto".
CREATE OR REPLACE FUNCTION public.emitir_eventos_relacion()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_nueva    jsonb  := to_jsonb(NEW);
  v_vieja    jsonb  := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_ente     text   := coalesce(v_nueva->>TG_ARGV[0], TG_ARGV[0]);
  v_ente_rel text   := coalesce(v_nueva->>TG_ARGV[2], TG_ARGV[2]);
  v_registro uuid   := (v_nueva->>TG_ARGV[1])::uuid;
  v_otro     uuid   := (v_nueva->>TG_ARGV[3])::uuid;
  v_antes    text[] := CASE WHEN (v_vieja->>'activo')::boolean AND v_vieja->>'hasta' IS NULL
                            THEN ARRAY(SELECT jsonb_array_elements_text(v_vieja->'roles')) ELSE '{}' END;
  v_despues  text[] := CASE WHEN (v_nueva->>'activo')::boolean AND v_nueva->>'hasta' IS NULL
                            THEN ARRAY(SELECT jsonb_array_elements_text(v_nueva->'roles')) ELSE '{}' END;
  v_rol      text;
BEGIN
  FOR v_rol IN SELECT unnest(v_antes) EXCEPT SELECT unnest(v_despues) LOOP
    PERFORM emitir_evento(v_ente, v_registro, 'relacion_baja',
      jsonb_build_object('ente', v_ente_rel, 'registro_id', v_otro, 'rol', v_rol));
  END LOOP;

  FOR v_rol IN SELECT unnest(v_despues) EXCEPT SELECT unnest(v_antes) LOOP
    PERFORM emitir_evento(v_ente, v_registro, 'relacion_alta',
      jsonb_build_object('ente', v_ente_rel, 'registro_id', v_otro, 'rol', v_rol));
  END LOOP;

  RETURN NULL;
END;
$$;
