-- sql/098 — congelada quiere decir congelada
--
-- sql/040 dropeó `obras_guard_congelado` creyendo que su única razón viva era
-- "marcar referente exige ver a la persona", que pasó a la policy. No lo era:
-- la función también cortaba todo vínculo hacia o desde un alta congelada
-- (OB011 / OB012), y eso nadie lo repuso. Desde entonces el dueño de una obra,
-- empresa o persona que espera autorización le podía colgar vínculos, y si lo
-- hacía el rechazo quedaba trabado: rechazar desactiva la fila, y
-- `guard_desactivar` corta con OB001 / OB002 mientras participe en una obra.
--
-- Vuelve como trigger y no como WITH CHECK de las policies de insert: es una
-- regla sobre el estado de la fila, no sobre quién inserta, y una policy que
-- falla llega a la UI como 42501 — "No tenés permiso", que es falso. Así los
-- dos códigos vuelven con el texto que ya tenían y que la UI ya citaba.
--
-- Solo BEFORE INSERT, como en sql/033: `pendiente = true` nace únicamente en
-- el INSERT (`marcar_pendiente`) y ningún UPDATE lo prende, así que una fila
-- congelada nunca tuvo un vínculo que se pueda reactivar. Al aplicarla había
-- 0 filas pendientes y 0 vínculos colgados de alguna.
--
-- `obras_obra_persona.empresa_id` sigue afuera a propósito: es contexto ("a
-- quién representa acá"), no un vínculo con la empresa.
--
-- Los IF van anidados y no encadenados con AND: plpgsql planea la expresión
-- entera la primera vez, así que nombrar `NEW.obra_id` con un AND explota con
-- 42703 en `obras_persona_empresa`, que no tiene esa columna.

CREATE OR REPLACE FUNCTION obras_guard_congelado()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME IN ('obras_obra_empresa', 'obras_obra_persona', 'obras_obra_referente') THEN
    IF EXISTS (SELECT 1 FROM public.obras WHERE id = NEW.obra_id AND pendiente) THEN
      RAISE EXCEPTION 'La obra está pendiente de autorización: no se le pueden agregar vínculos hasta que la aprueben.'
        USING ERRCODE = 'OB011';
    END IF;
  END IF;

  IF TG_TABLE_NAME IN ('obras_obra_empresa', 'obras_persona_empresa') THEN
    IF EXISTS (SELECT 1 FROM public.obras_empresas WHERE id = NEW.empresa_id AND pendiente) THEN
      RAISE EXCEPTION 'Esa empresa está pendiente de autorización: no se puede vincular hasta que la aprueben.'
        USING ERRCODE = 'OB012';
    END IF;
  END IF;

  IF TG_TABLE_NAME IN ('obras_obra_persona', 'obras_persona_empresa', 'obras_obra_referente') THEN
    IF EXISTS (SELECT 1 FROM public.obras_personas WHERE id = NEW.persona_id AND pendiente) THEN
      RAISE EXCEPTION 'Esa persona está pendiente de autorización: no se puede vincular hasta que la aprueben.'
        USING ERRCODE = 'OB012';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_guard_congelado() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS guard_congelado ON obras_obra_empresa;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_obra_empresa
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();

DROP TRIGGER IF EXISTS guard_congelado ON obras_obra_persona;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_obra_persona
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();

DROP TRIGGER IF EXISTS guard_congelado ON obras_persona_empresa;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_persona_empresa
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();

DROP TRIGGER IF EXISTS guard_congelado ON obras_obra_referente;
CREATE TRIGGER guard_congelado BEFORE INSERT ON obras_obra_referente
  FOR EACH ROW EXECUTE FUNCTION obras_guard_congelado();
