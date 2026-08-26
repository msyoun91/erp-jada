-- Editar un usuario: el email vive en dos lados y lo sincroniza un trigger.
--
-- `auth.users.email` es la credencial de login; `usuarios.email` es lo que
-- muestra el ERP. Cambiarlo con dos writes desde la action deja abierta la
-- puerta a que el segundo falle y queden distintos — y ahí el usuario entra
-- con un email que la pantalla no muestra en ningún lado.
--
-- El INSERT ya se resolvía así (`handle_new_user`, `sql/001`); faltaba el
-- UPDATE. Como el trigger corre dentro de la transacción del cambio de email,
-- si `usuarios` rechaza el valor la modificación de `auth.users` se revierte
-- entera: no hay estado intermedio.

CREATE OR REPLACE FUNCTION handle_user_email_updated()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.usuarios SET email = NEW.email WHERE id = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- `WHEN` y no un IF adentro: el trigger no corre si el email no cambió, así
-- un cambio de contraseña o el ban de `sql/020` no tocan `usuarios`.
DROP TRIGGER IF EXISTS on_auth_user_email_updated ON auth.users;
CREATE TRIGGER on_auth_user_email_updated
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  WHEN (NEW.email IS DISTINCT FROM OLD.email AND NEW.email IS NOT NULL)
  EXECUTE FUNCTION handle_user_email_updated();
