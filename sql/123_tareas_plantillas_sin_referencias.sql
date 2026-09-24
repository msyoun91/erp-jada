-- sql/123 — tareas: sin referencias fijas `{ente:uuid|nombre}` en plantillas.
--
-- Una plantilla es reusable y una referencia a un registro concreto casi nunca
-- lo es; publicada, además mostraba en el Catálogo el nombre de un registro a
-- quien no lo ve. Trigger y no chequeo en `guardar_plantilla`: `authenticated`
-- inserta pasos directo, y así cubre también `copiar_plantilla`.
-- Decisión: `decisiones/tareas/catalogo.md` → *Sin referencias fijas*.
-- Verificado con `sql/tests/tareas_plantillas.sql`.

-- Lo guardado pasa a su nombre, en texto plano. Antes del trigger: lo rechazaría.
UPDATE public.tareas_plantillas_pasos
SET descripcion = regexp_replace(descripcion,
  '\{[a-z_]+:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\|([^}]*)\}',
  '\1', 'g')
WHERE EXISTS (SELECT 1 FROM public.tareas_referencias(descripcion));

UPDATE public.tareas_plantillas
SET descripcion = regexp_replace(descripcion,
  '\{[a-z_]+:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\|([^}]*)\}',
  '\1', 'g')
WHERE EXISTS (SELECT 1 FROM public.tareas_referencias(descripcion));

CREATE OR REPLACE FUNCTION public.tareas_plantillas_sin_referencias()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM tareas_referencias(NEW.descripcion)) THEN
    RAISE EXCEPTION 'Una plantilla no menciona registros concretos: escribí el nombre en texto' USING ERRCODE = 'TA022';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tareas_plantillas_sin_referencias() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tareas_plantillas_sin_referencias ON public.tareas_plantillas;
CREATE TRIGGER tareas_plantillas_sin_referencias
  BEFORE INSERT OR UPDATE OF descripcion ON public.tareas_plantillas
  FOR EACH ROW EXECUTE FUNCTION tareas_plantillas_sin_referencias();

DROP TRIGGER IF EXISTS tareas_plantillas_sin_referencias ON public.tareas_plantillas_pasos;
CREATE TRIGGER tareas_plantillas_sin_referencias
  BEFORE INSERT OR UPDATE OF descripcion ON public.tareas_plantillas_pasos
  FOR EACH ROW EXECUTE FUNCTION tareas_plantillas_sin_referencias();
