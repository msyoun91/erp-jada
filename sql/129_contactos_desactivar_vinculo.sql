-- sql/129 — contactos: desactivar un vínculo por función.
--
-- Un vínculo (o una persona ↔ empresa) desactivado lo ve solo el admin, y
-- Postgres pide que la fila que deja un UPDATE siga pasando la policy de
-- SELECT: desactivarlo por UPDATE directo falla con 42501 para cualquier otro.
-- Como en `obras_desactivar`, va por una función DEFINER y las reglas siguen
-- en los triggers (`contactos_vinculos_validar`,
-- `contactos_persona_empresa_validar`). Lo encontró
-- `sql/tests/contactos_reglas.sql` (caso 14).

CREATE OR REPLACE FUNCTION public.contactos_desactivar_vinculo(p_vinculo uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.contactos_vinculos SET activo = false WHERE id = p_vinculo AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese vínculo no existe o ya está desactivado' USING ERRCODE = 'CO018';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.contactos_desactivar_persona_empresa(p_relacion uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.contactos_persona_empresa SET activo = false WHERE id = p_relacion AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa relación no existe o ya está desactivada' USING ERRCODE = 'CO018';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.contactos_desactivar_vinculo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_desactivar_vinculo(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.contactos_desactivar_persona_empresa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contactos_desactivar_persona_empresa(uuid) TO authenticated;
