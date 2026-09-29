-- sql/148 — tareas, tramo 5, paso 1: lo que el disparo necesita del core.
--
-- `disparar_plantillas` es DEFINER: corre las plantillas del dueño del
-- registro, no de quien actuó, y lo que ve el dueño se mide a mano. Para eso:
--   1. `entes.dueno`: la columna del dueño en `entes.tabla`.
--   2. `puede_abrir_registro` suma la rama `tareas` (hilo y paso): "Sobre" un
--      hilo se usa a mano, y la interna de `usar_plantilla` mide por usuario.
--   3. `etiqueta_registro_de(ente, id, usuario)`: el nombre si ese usuario lo ve.
--   4. `relacionados_de_registro(ente, id)` y su `_de`: `(ente, registro_id,
--      rol)` de los vínculos abiertos. Hoy solo Contactos guarda roles
--      (`contactos_vinculos`), así que la rama es por el módulo de la puente,
--      no por el del registro: una obra se relaciona con personas y empresas.
--
-- Decisiones: `decisiones/tareas/catalogo.md` → *El disparo sigue al
-- registro*; `GUIDE_ENTES.md` §2.3 y §2.8.

-- 1. La columna del dueño --------------------------------------------------

ALTER TABLE public.entes ADD COLUMN dueno text;

-- `tarea` no tiene: su dueño es el responsable de su hilo (heredado).
UPDATE public.entes SET dueno = 'responsable_id' WHERE codigo IN ('hilo', 'obra', 'persona');
UPDATE public.entes SET dueno = 'creado_por' WHERE codigo = 'empresa';

-- La escribe cada migración a mano: se verifica acá que exista en su tabla.
DO $$
DECLARE
  v_malos text;
BEGIN
  SELECT string_agg(e.codigo, ', ') INTO v_malos
  FROM public.entes e
  WHERE e.dueno IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM pg_attribute a
      WHERE a.attrelid = e.tabla AND a.attname = e.dueno AND a.atttypid = 'uuid'::regtype AND NOT a.attisdropped
    );
  IF v_malos IS NOT NULL THEN
    RAISE EXCEPTION 'entes.dueno no es una columna uuid de su tabla: %', v_malos;
  END IF;
END;
$$;

-- 2. "Lo ve", por usuario: rama tareas -------------------------------------

CREATE OR REPLACE FUNCTION public.tareas_puede_abrir(p_tipo text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE p_tipo
    WHEN 'hilo' THEN (
      SELECT public.tareas_puede_ver_hilo_de(h.id, h.responsable_id, h.equipo_id, h.activo, p_usuario)
      FROM public.tareas_hilos h WHERE h.id = p_id
    )
    WHEN 'tarea' THEN (
      SELECT public.tareas_puede_ver_tarea_de(t.hilo_id, t.activo, p_usuario)
      FROM public.tareas t WHERE t.id = p_id
    )
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_puede_abrir(text, uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((
    SELECT CASE e.modulo
      WHEN 'tareas'    THEN public.tareas_puede_abrir(p_ente, p_id, p_usuario)
      WHEN 'obras'     THEN public.obras_puede_abrir(p_ente, p_id, p_usuario)
      WHEN 'contactos' THEN public.contactos_puede_abrir(p_ente, p_id, p_usuario)
    END
    FROM public.entes e
    WHERE e.codigo = p_ente
  ), false);
$$;

-- 3. El nombre, por usuario ------------------------------------------------

-- DEFINER: `etiqueta_registro` corre acá como el dueño de la función y lee
-- sin RLS; lo que decide es `puede_abrir_registro`.
CREATE OR REPLACE FUNCTION public.etiqueta_registro_de(p_ente text, p_id uuid, p_usuario uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN public.puede_abrir_registro(p_ente, p_id, p_usuario)
    THEN public.etiqueta_registro(p_ente, p_id)
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.etiqueta_registro_de(text, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- 4. Las propiedades relacionales ------------------------------------------

-- El cuerpo, una vez. INVOKER: desde `relacionados_de_registro` decide la RLS
-- de `contactos_vinculos` (ver el registro); desde la `_de`, el guard.
CREATE OR REPLACE FUNCTION public.contactos_relacionados(p_ente text, p_id uuid)
RETURNS TABLE (ente text, registro_id uuid, rol text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE WHEN v.persona_id IS NOT NULL THEN 'persona' ELSE 'empresa' END,
         coalesce(v.persona_id, v.empresa_id),
         r.rol
  FROM public.contactos_vinculos v
  CROSS JOIN unnest(v.roles) AS r (rol)
  WHERE v.ente = p_ente AND v.registro_id = p_id AND v.activo AND v.hasta IS NULL;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_relacionados(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_relacionados(text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.relacionados_de_registro(p_ente text, p_id uuid)
RETURNS TABLE (ente text, registro_id uuid, rol text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.contactos_relacionados(p_ente, p_id);
$$;

REVOKE EXECUTE ON FUNCTION public.relacionados_de_registro(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.relacionados_de_registro(text, uuid) TO authenticated;

-- Quien ve el registro ve sus vínculos abiertos (`contactos_vinculos_select`).
CREATE OR REPLACE FUNCTION public.relacionados_de_registro_de(p_ente text, p_id uuid, p_usuario uuid)
RETURNS TABLE (ente text, registro_id uuid, rol text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.* FROM public.relacionados_de_registro(p_ente, p_id) r
  WHERE public.puede_abrir_registro(p_ente, p_id, p_usuario);
$$;

REVOKE EXECUTE ON FUNCTION public.relacionados_de_registro_de(text, uuid, uuid) FROM PUBLIC, anon, authenticated;
