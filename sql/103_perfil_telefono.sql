-- `/perfil` — el celular propio.
--
-- Una sola columna, no `telefono` + `telefono_norm` como tenía obras: ahí el
-- par existía para buscar por número conservando lo tecleado, y acá nadie
-- busca. Se guarda normalizado (solo dígitos) porque el destino del dato es un
-- `tel:` y un `wa.me/<numero>`, que no aceptan paréntesis, guiones ni espacios.
--
-- El teléfono es dato de contacto, nunca credencial: nadie verifica que el
-- número exista (no hay SMS ni OTP). No sirve como segundo factor.

CREATE OR REPLACE FUNCTION public.normalizar_telefono(t text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT nullif(regexp_replace(coalesce(t, ''), '[^0-9]', '', 'g'), '');
$$;

COMMENT ON FUNCTION public.normalizar_telefono(text) IS
  'Solo dígitos. "11 4567-8900" y "+54 11 4567 8900" son el mismo teléfono.';

ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS telefono text;

-- El CHECK corre después del trigger: valida lo normalizado, no lo tecleado.
-- 15 dígitos es el máximo de E.164; 8 es el mínimo de un fijo con característica.
ALTER TABLE public.usuarios DROP CONSTRAINT IF EXISTS usuarios_telefono_formato;
ALTER TABLE public.usuarios ADD CONSTRAINT usuarios_telefono_formato
  CHECK (telefono IS NULL OR telefono ~ '^[0-9]{8,15}$');

CREATE OR REPLACE FUNCTION public.usuarios_normalizar_telefono()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.telefono = public.normalizar_telefono(NEW.telefono);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS usuarios_telefono_normalizado ON public.usuarios;
CREATE TRIGGER usuarios_telefono_normalizado
  BEFORE INSERT OR UPDATE OF telefono ON public.usuarios
  FOR EACH ROW EXECUTE FUNCTION public.usuarios_normalizar_telefono();

-- `sql/022` dio `GRANT UPDATE (nombre)`: sin sumar la columna acá, la policy
-- `usuarios_update_propio` dejaría pasar el UPDATE y el GRANT lo rechazaría.
-- Los grants por columna se acumulan, así que esto no toca el de `nombre`.
GRANT UPDATE (telefono) ON public.usuarios TO authenticated;
