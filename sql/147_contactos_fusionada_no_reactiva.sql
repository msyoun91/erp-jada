-- sql/147 — contactos, cierre del tramo 4: una ficha fusionada no se reactiva.
--
-- Sus vínculos ya pasaron a la que queda y los choques ya se resolvieron:
-- reactivarla deja la misma persona dos veces, una vacía que igual dice "Se
-- fusionó con …". Si la fusión estuvo mal, se carga de nuevo. Vale para todos,
-- también el admin y el SQL directo: por eso no vive en `*_al_editar`, que
-- solo mira UPDATE de usuarios.
--
-- Decisión: `decisiones/contactos.md` → *Una fusionada no se reactiva*.

CREATE OR REPLACE FUNCTION public.contactos_fusionada_no_reactiva()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.fusionada_en IS NOT NULL AND NEW.activo THEN
    RAISE EXCEPTION 'Una ficha fusionada no se reactiva' USING ERRCODE = 'CO031';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER contactos_fusionada_no_reactiva
  BEFORE UPDATE ON public.contactos_personas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_fusionada_no_reactiva();

CREATE TRIGGER contactos_fusionada_no_reactiva
  BEFORE UPDATE ON public.contactos_empresas
  FOR EACH ROW EXECUTE FUNCTION public.contactos_fusionada_no_reactiva();
