-- sql/122 — tareas: los vínculos siguen al `activo` del paso.
--
-- Un paso desactivado apaga sus vínculos: no es mención viva para el admin ni
-- para lo que lea `tareas_vinculos` después ("mencionado en", el disparo).
-- Reactivarlo los vuelve a derivar sin TA021: lo reactiva el admin, y la
-- referencia ya se revisó al escribirla.
-- Decisión: `decisiones/tareas/registro.md`. Verificado con
-- `sql/tests/tareas_vinculos.sql`.

CREATE OR REPLACE FUNCTION public.tareas_derivar_vinculos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v record;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.descripcion IS NOT DISTINCT FROM OLD.descripcion
     AND NEW.activo = OLD.activo THEN
    RETURN NULL;
  END IF;

  UPDATE tareas_vinculos x SET activo = false
  WHERE x.tarea_id = NEW.id AND x.activo
    AND (NOT NEW.activo
         OR NOT EXISTS (SELECT 1 FROM tareas_referencias(NEW.descripcion) r
                        WHERE r.ente = x.ente AND r.registro_id = x.registro_id));

  IF NOT NEW.activo THEN
    RETURN NULL;
  END IF;

  FOR v IN
    SELECT r.ente, r.registro_id FROM tareas_referencias(NEW.descripcion) r
    WHERE NOT EXISTS (SELECT 1 FROM tareas_vinculos x
                      WHERE x.tarea_id = NEW.id AND x.activo
                        AND x.ente = r.ente AND x.registro_id = r.registro_id)
  LOOP
    IF (TG_OP = 'INSERT' OR OLD.activo) AND etiqueta_registro(v.ente, v.registro_id) IS NULL THEN
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
  AFTER INSERT OR UPDATE OF descripcion, activo ON public.tareas
  FOR EACH ROW EXECUTE FUNCTION tareas_derivar_vinculos();

-- Lo que quedó vivo de pasos desactivados antes de este trigger.
UPDATE public.tareas_vinculos v SET activo = false
FROM public.tareas t
WHERE t.id = v.tarea_id AND v.activo AND NOT t.activo;
