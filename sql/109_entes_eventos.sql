-- sql/109 — entes y eventos: la infra cross-módulo, sin ningún ente.
--
-- Vuelve lo de `sql/055`, `059`, `067`–`069` (en `master`) que no era de tareas
-- ni de obras; `sql/101` lo había borrado con ellas. El contrato es
-- `GUIDE_ENTES.md` §2.2 y §2.8, y los porqués, `decisiones/global/entes.md`.
-- Queda el mecanismo y nada que lo use: `entes` vacía, ningún trigger emisor,
-- ningún consumidor. El primer módulo con entes (Tareas) suma su fila, sus
-- triggers y su rama en las genéricas.
--
-- De las siete funciones cross-módulo vuelven solo las dos que pide la RLS de
-- `eventos`: `etiqueta_registro` y `puede_ver_relacion`. Sin ramas responden
-- "no" (nadie ve ningún evento), y el primer ente reemplaza el cuerpo con su
-- `CASE e.modulo WHEN ...`. `puede_abrir_registro` y `buscar_registros` vuelven
-- con su primer llamador; `compartir_registros`, `puede_compartir_registro` y
-- `sin_acceso`, cuando esté decidido cómo se comparte con un equipo.

-- ============================================================
-- 1. Vocabulario de eventos
--
-- `transferencia`, `compartido` y `revocado` entran con su primer emisor.
-- ============================================================
DO $$ BEGIN
  CREATE TYPE tipo_evento AS ENUM ('alta', 'baja', 'reactivacion', 'estado', 'relacion_alta', 'relacion_baja');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- 2. Catálogo de entes
--
-- `codigo` UNIQUE simple y no parcial: es destino de FK, y un código no se
-- reutiliza para otro ente. `submodulo` es texto y no FK porque
-- `submodulos.codigo` es único parcial.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.entes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      text NOT NULL UNIQUE,
  modulo      text NOT NULL,
  submodulo   text NOT NULL,
  estados     regtype,
  datos       text[] NOT NULL DEFAULT '{}',
  ruta        text NOT NULL CHECK (ruta ~ '^/[^/]' AND strpos(ruta, '{id}') > 0),
  tabla       regclass NOT NULL,
  disparos    tipo_evento[] NOT NULL DEFAULT '{}',
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS set_updated_at ON public.entes;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.entes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.entes ENABLE ROW LEVEL SECURITY;

-- Sin el submódulo del ente, el ente no existe para vos. Escribe solo la
-- migración de cada módulo.
DROP POLICY IF EXISTS entes_select ON public.entes;
CREATE POLICY entes_select ON public.entes FOR SELECT TO authenticated
  USING (activo AND tiene_permiso(submodulo));

GRANT SELECT ON public.entes TO authenticated;

-- ============================================================
-- 3. Las dos genéricas que pide la RLS de `eventos`, sin ramas
--
-- INVOKER llamadas desde una policy: necesitan EXECUTE para quien lee.
-- ============================================================

-- La definición de "lo ve": el nombre del registro si quien pregunta lo ve,
-- NULL si no.
CREATE OR REPLACE FUNCTION public.etiqueta_registro(p_ente text, p_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT NULL::text;
$$;

-- Si quien pregunta ve algún vínculo del par, activo o no: ver el ente no es
-- ver todos sus vínculos.
CREATE OR REPLACE FUNCTION public.puede_ver_relacion(p_ente text, p_id uuid, p_ente_rel text, p_id_rel uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT false;
$$;

REVOKE EXECUTE ON FUNCTION public.etiqueta_registro(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.etiqueta_registro(text, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.puede_ver_relacion(text, uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.puede_ver_relacion(text, uuid, text, uuid) TO authenticated;

-- ============================================================
-- 4. eventos
--
-- Sin `activo` ni `updated_at`: una auditoría no oculta ni reescribe sus
-- filas. `clock_timestamp()` y no `now()`: una misma sentencia emite varios
-- (reactivación y estado) y el orden tiene que quedar.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.eventos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ente        text NOT NULL REFERENCES public.entes(codigo),
  registro_id uuid NOT NULL,
  evento      tipo_evento NOT NULL,
  detalle     jsonb NOT NULL DEFAULT '{}',
  actor_id    uuid REFERENCES public.usuarios(id),
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_eventos_registro ON public.eventos (ente, registro_id, created_at);
CREATE INDEX IF NOT EXISTS idx_eventos_actor ON public.eventos (actor_id);

ALTER TABLE public.eventos ENABLE ROW LEVEL SECURITY;

-- Lo que no ves, no pasó. CASE y no OR: el resto de los eventos no paga el
-- EXISTS de la relación.
DROP POLICY IF EXISTS eventos_select ON public.eventos;
CREATE POLICY eventos_select ON public.eventos FOR SELECT TO authenticated
  USING (
    etiqueta_registro(ente, registro_id) IS NOT NULL
    AND CASE
          WHEN evento IN ('relacion_alta', 'relacion_baja')
            THEN puede_ver_relacion(ente, registro_id, detalle->>'ente', (detalle->>'registro_id')::uuid)
          ELSE true
        END
  );

-- Solo desde un trigger: un evento inventado por el cliente dispararía
-- plantillas.
DROP POLICY IF EXISTS eventos_insert ON public.eventos;
CREATE POLICY eventos_insert ON public.eventos FOR INSERT TO authenticated
  WITH CHECK (pg_trigger_depth() > 0);

GRANT SELECT, INSERT ON public.eventos TO authenticated;

-- ============================================================
-- 5. Los emisores
-- ============================================================

-- INVOKER: con DEFINER, `current_user` sería `postgres` y un consumidor que
-- corre con la RLS de quien actúa no correría nunca.
CREATE OR REPLACE FUNCTION public.emitir_evento(p_ente text, p_registro_id uuid, p_evento tipo_evento, p_detalle jsonb DEFAULT '{}')
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
  INSERT INTO eventos (ente, registro_id, evento, detalle, actor_id)
  VALUES (p_ente, p_registro_id, p_evento, p_detalle, auth.uid());
$$;

-- TG_ARGV = (ente). La columna de estado se llama `estado` (GUIDE_ENTES §2.1);
-- sin ella, solo alta, baja y reactivación. Reactivación antes que estado y
-- baja después: quien escucha el estado encuentra el registro como quedó.
CREATE OR REPLACE FUNCTION public.emitir_eventos_registro()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ente   text    := TG_ARGV[0];
  v_nueva  jsonb   := to_jsonb(NEW);
  v_vieja  jsonb   := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_activo boolean := (v_nueva->>'activo')::boolean;
  v_estaba boolean := (v_vieja->>'activo')::boolean;
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
    PERFORM emitir_evento(v_ente, NEW.id, 'estado',
      jsonb_build_object('estado', v_nueva->>'estado', 'anterior', v_vieja->>'estado'));
  END IF;

  IF v_estaba AND NOT v_activo THEN
    PERFORM emitir_evento(v_ente, NEW.id, 'baja');
  END IF;

  RETURN NULL;
END;
$$;

-- TG_ARGV = (ente, su columna, ente relacionado, su columna). Un evento por rol
-- que aparece o se va: vincular con dos roles son dos altas, sacarle uno a un
-- vínculo es una baja, desactivarlo es la baja de todos. El evento es del ente,
-- no del relacionado: "la obra suma un arquitecto".
CREATE OR REPLACE FUNCTION public.emitir_eventos_relacion()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_nueva    jsonb  := to_jsonb(NEW);
  v_vieja    jsonb  := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END;
  v_registro uuid   := (v_nueva->>TG_ARGV[1])::uuid;
  v_otro     uuid   := (v_nueva->>TG_ARGV[3])::uuid;
  v_antes    text[] := CASE WHEN (v_vieja->>'activo')::boolean
                            THEN ARRAY(SELECT jsonb_array_elements_text(v_vieja->'roles')) ELSE '{}' END;
  v_despues  text[] := CASE WHEN (v_nueva->>'activo')::boolean
                            THEN ARRAY(SELECT jsonb_array_elements_text(v_nueva->'roles')) ELSE '{}' END;
  v_rol      text;
BEGIN
  FOR v_rol IN SELECT unnest(v_antes) EXCEPT SELECT unnest(v_despues) LOOP
    PERFORM emitir_evento(TG_ARGV[0], v_registro, 'relacion_baja',
      jsonb_build_object('ente', TG_ARGV[2], 'registro_id', v_otro, 'rol', v_rol));
  END LOOP;

  FOR v_rol IN SELECT unnest(v_despues) EXCEPT SELECT unnest(v_antes) LOOP
    PERFORM emitir_evento(TG_ARGV[0], v_registro, 'relacion_alta',
      jsonb_build_object('ente', TG_ARGV[2], 'registro_id', v_otro, 'rol', v_rol));
  END LOOP;

  RETURN NULL;
END;
$$;

-- `emitir_evento` la llaman los triggers como quien actúa: necesita EXECUTE
-- para `authenticated`. Llamada por RPC no inserta nada (`eventos_insert`).
REVOKE EXECUTE ON FUNCTION public.emitir_evento(text, uuid, tipo_evento, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.emitir_evento(text, uuid, tipo_evento, jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.emitir_eventos_registro() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.emitir_eventos_relacion() FROM PUBLIC, anon, authenticated;
