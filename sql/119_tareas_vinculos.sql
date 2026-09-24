-- sql/119 — tareas: referencias en la descripción y `tareas_vinculos`.
--
-- Un ente mencionado en la descripción de un paso se guarda como
-- `{ente:uuid|nombre}`: la referencia y la copia del nombre que vio quien la
-- escribió. Se muestra como link si quien lee lo ve, y como texto plano si no.
-- `tareas_vinculos` no se escribe a mano: la deriva un trigger de la
-- descripción, una sola fuente. Sumar una referencia pide ver lo referenciado
-- (TA021); lo que copia la base (recurrencia) no se vuelve a revisar.
-- Ve un vínculo quien ve el paso: la RLS es la del hilo, no la del ente.
-- Rol y plantilla del vínculo esperan al disparo, con el primer emisor.
-- Decisión: `decisiones/tareas/registro.md`. Verificado con
-- `sql/tests/tareas_vinculos.sql`.

-- ============================================================
-- 1. Tabla
-- ============================================================
CREATE TABLE IF NOT EXISTS public.tareas_vinculos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tarea_id    uuid NOT NULL REFERENCES public.tareas(id),
  ente        text NOT NULL REFERENCES public.entes(codigo),
  registro_id uuid NOT NULL,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tareas_vinculos_unico
  ON public.tareas_vinculos (tarea_id, ente, registro_id) WHERE activo;
CREATE INDEX IF NOT EXISTS idx_tareas_vinculos_registro
  ON public.tareas_vinculos (ente, registro_id) WHERE activo;

DROP TRIGGER IF EXISTS set_updated_at ON public.tareas_vinculos;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.tareas_vinculos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE public.tareas_vinculos ENABLE ROW LEVEL SECURITY;

-- EXISTS con la RLS de `tareas`: la del hilo.
DROP POLICY IF EXISTS tareas_vinculos_select ON public.tareas_vinculos;
CREATE POLICY tareas_vinculos_select ON public.tareas_vinculos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.tareas t WHERE t.id = tarea_id));

-- Solo desde el trigger (INVOKER, para revisar la referencia como quien escribe).
DROP POLICY IF EXISTS tareas_vinculos_insert ON public.tareas_vinculos;
CREATE POLICY tareas_vinculos_insert ON public.tareas_vinculos FOR INSERT TO authenticated
  WITH CHECK (pg_trigger_depth() > 0);

DROP POLICY IF EXISTS tareas_vinculos_update ON public.tareas_vinculos;
CREATE POLICY tareas_vinculos_update ON public.tareas_vinculos FOR UPDATE TO authenticated
  USING (pg_trigger_depth() > 0)
  WITH CHECK (pg_trigger_depth() > 0);

GRANT SELECT, INSERT (tarea_id, ente, registro_id), UPDATE (activo) ON public.tareas_vinculos TO authenticated;

-- ============================================================
-- 2. Referencias del texto
-- ============================================================
CREATE OR REPLACE FUNCTION public.tareas_referencias(p_texto text)
RETURNS TABLE (ente text, registro_id uuid)
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT DISTINCT m[1], m[2]::uuid
  FROM regexp_matches(coalesce(p_texto, ''),
    '\{([a-z_]+):([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\|[^}]*\}',
    'g') AS m;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_referencias(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tareas_referencias(text) TO authenticated;

-- INVOKER: `etiqueta_registro` responde por quien escribe. Desde un trigger
-- DEFINER (recurrencia) corre como dueño y ve todo: la copia no se revisa.
CREATE OR REPLACE FUNCTION public.tareas_derivar_vinculos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v record;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.descripcion IS NOT DISTINCT FROM OLD.descripcion THEN
    RETURN NULL;
  END IF;

  UPDATE tareas_vinculos x SET activo = false
  WHERE x.tarea_id = NEW.id AND x.activo
    AND NOT EXISTS (SELECT 1 FROM tareas_referencias(NEW.descripcion) r
                    WHERE r.ente = x.ente AND r.registro_id = x.registro_id);

  FOR v IN
    SELECT r.ente, r.registro_id FROM tareas_referencias(NEW.descripcion) r
    WHERE NOT EXISTS (SELECT 1 FROM tareas_vinculos x
                      WHERE x.tarea_id = NEW.id AND x.activo
                        AND x.ente = r.ente AND x.registro_id = r.registro_id)
  LOOP
    IF etiqueta_registro(v.ente, v.registro_id) IS NULL THEN
      RAISE EXCEPTION 'La descripción menciona algo que no existe o no podés ver' USING ERRCODE = 'TA021';
    END IF;
    INSERT INTO tareas_vinculos (tarea_id, ente, registro_id) VALUES (NEW.id, v.ente, v.registro_id);
  END LOOP;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_derivar_vinculos() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_derivar_vinculos ON public.tareas;
CREATE TRIGGER tareas_derivar_vinculos
  AFTER INSERT OR UPDATE OF descripcion ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION tareas_derivar_vinculos();
