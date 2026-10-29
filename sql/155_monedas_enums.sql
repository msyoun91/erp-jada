-- Monedas, 1 de 2: valores de enum. ADD VALUE va en su propia transacción: el valor no se puede
-- usar antes del commit (db_schema/notificaciones.md → Sumar un evento).
--
-- El enum moneda pasa a ARS | USD_OFICIAL | USD_BLUE | EUR (decisiones/monedas.md → Tipos de
-- cambio). USD se renombra, así que las comisiones en USD quedan al oficial; el trigger de
-- comisiones lo nombraba, y se recrea acá con el nombre nuevo.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'moneda' AND e.enumlabel = 'USD'
  ) THEN
    ALTER TYPE public.moneda RENAME VALUE 'USD' TO 'USD_OFICIAL';
  END IF;
END $$;

ALTER TYPE public.moneda ADD VALUE IF NOT EXISTS 'USD_BLUE';
ALTER TYPE public.moneda ADD VALUE IF NOT EXISTS 'EUR';

ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'tipo_cambio_corregido';
ALTER TYPE public.tipo_notificacion ADD VALUE IF NOT EXISTS 'tipo_cambio_confirmado';

CREATE OR REPLACE FUNCTION public.obras_comisiones_validar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_obra uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.activo := true;
    IF NEW.monto IS NOT NULL THEN
      NEW.moneda := coalesce(NEW.moneda, 'USD_OFICIAL');
    END IF;

    SELECT v.registro_id INTO v_obra
    FROM public.contactos_vinculos v
    WHERE v.id = NEW.vinculo_id AND v.activo AND v.hasta IS NULL AND v.ente = 'obra'
      AND 'referente' = ANY (v.roles);
    IF v_obra IS NULL THEN
      RAISE EXCEPTION 'La comisión va sobre un referente vigente de la obra' USING ERRCODE = 'OB036';
    END IF;
  ELSE
    IF NOT OLD.activo AND NEW.activo THEN
      RAISE EXCEPTION 'Una comisión reemplazada no vuelve: se registra otra' USING ERRCODE = 'OB038';
    END IF;
    SELECT v.registro_id INTO v_obra FROM public.contactos_vinculos v WHERE v.id = OLD.vinculo_id;
  END IF;

  IF pg_trigger_depth() = 1 AND v_uid IS NOT NULL AND NOT public.obras_a_cargo_de(v_obra, v_uid) THEN
    RAISE EXCEPTION 'La comisión la maneja el responsable de la obra' USING ERRCODE = 'OB037';
  END IF;

  RETURN NEW;
END;
$$;
