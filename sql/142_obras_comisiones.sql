-- sql/142 — obras, tramo 4: la comisión del referente.
--
-- - `obras_comisiones` va sobre el vínculo con rol `referente` de una obra:
--   porcentaje o monto (CHECK: uno), y el monto con moneda, USD si no se
--   dice. Una activa por vínculo.
-- - No se edita, se reemplaza: `obras_registrar_comision` desactiva la
--   vigente y crea otra. Las inactivas son el historial, con la misma RLS.
-- - La ven y la escriben quienes tienen la obra a cargo (responsable,
--   `obras_equipo` sobre `obra.equipo_id`, `obras_administrar`):
--   `obras_ve_comision`, sobre `obras_a_cargo_de`. El participante, no.
-- - Sacarle "referente" a ese vínculo, cerrarlo o desactivarlo lo hace solo
--   quien la ve (OB039), y la comisión se desactiva junto.
--
-- Decisiones: `decisiones/obras.md` → *La comisión del referente*, *El monto
-- lleva moneda* y *Un vínculo con comisión activa*. Test:
-- `sql/tests/obras_comisiones.sql`.

-- ============================================================
-- 1. obras_comisiones
-- ============================================================
DO $$ BEGIN
  CREATE TYPE moneda AS ENUM ('ARS', 'USD');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.obras_comisiones (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vinculo_id  uuid NOT NULL REFERENCES public.contactos_vinculos(id),
  porcentaje  numeric(5,2) CHECK (porcentaje > 0 AND porcentaje <= 100),
  monto       numeric(14,2) CHECK (monto > 0),
  moneda      moneda,
  creado_por  uuid NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT obras_comisiones_una CHECK (num_nonnulls(porcentaje, monto) = 1),
  CONSTRAINT obras_comisiones_moneda CHECK ((monto IS NULL) = (moneda IS NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS obras_comisiones_vigente
  ON public.obras_comisiones (vinculo_id) WHERE activo;
CREATE INDEX IF NOT EXISTS obras_comisiones_vinculo ON public.obras_comisiones (vinculo_id);

ALTER TABLE public.obras_comisiones ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.obras_comisiones;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.obras_comisiones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 2. Quién la ve
-- ============================================================
-- DEFINER: el vínculo desactivado solo lo lee el admin de Contactos, y el
-- historial de su comisión es del responsable igual.
CREATE OR REPLACE FUNCTION public.obras_ve_comision(p_vinculo uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.contactos_vinculos v
    WHERE v.id = p_vinculo AND v.ente = 'obra' AND public.obras_a_cargo_de(v.registro_id, auth.uid())
  );
$$;

REVOKE EXECUTE ON FUNCTION public.obras_ve_comision(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_ve_comision(uuid) TO authenticated;

DROP POLICY IF EXISTS obras_comisiones_select ON public.obras_comisiones;
CREATE POLICY obras_comisiones_select ON public.obras_comisiones FOR SELECT TO authenticated
  USING (obras_ve_comision(vinculo_id));

DROP POLICY IF EXISTS obras_comisiones_insert ON public.obras_comisiones;
CREATE POLICY obras_comisiones_insert ON public.obras_comisiones FOR INSERT TO authenticated
  WITH CHECK (obras_ve_comision(vinculo_id));

DROP POLICY IF EXISTS obras_comisiones_update ON public.obras_comisiones;
CREATE POLICY obras_comisiones_update ON public.obras_comisiones FOR UPDATE TO authenticated
  USING (obras_ve_comision(vinculo_id))
  WITH CHECK (true);

REVOKE ALL ON public.obras_comisiones FROM anon, authenticated;
GRANT SELECT ON public.obras_comisiones TO authenticated;
GRANT INSERT (id, vinculo_id, porcentaje, monto, moneda), UPDATE (activo)
  ON public.obras_comisiones TO authenticated;

-- ============================================================
-- 3. Reglas
-- ============================================================
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
      NEW.moneda := coalesce(NEW.moneda, 'USD');
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

REVOKE EXECUTE ON FUNCTION public.obras_comisiones_validar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS obras_comisiones_validar ON public.obras_comisiones;
CREATE TRIGGER obras_comisiones_validar
  BEFORE INSERT OR UPDATE ON public.obras_comisiones
  FOR EACH ROW EXECUTE FUNCTION public.obras_comisiones_validar();

-- ============================================================
-- 4. Registrar = reemplazar
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_registrar_comision(
  p_vinculo uuid, p_porcentaje numeric, p_monto numeric, p_moneda moneda DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  UPDATE public.obras_comisiones SET activo = false WHERE vinculo_id = p_vinculo AND activo;
  INSERT INTO public.obras_comisiones (vinculo_id, porcentaje, monto, moneda)
  VALUES (p_vinculo, p_porcentaje, p_monto, p_moneda)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_registrar_comision(uuid, numeric, numeric, moneda) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obras_registrar_comision(uuid, numeric, numeric, moneda) TO authenticated;

-- ============================================================
-- 5. El vínculo con comisión activa
-- ============================================================
-- Trigger de Obras sobre el puente de Contactos. Sacarle "referente",
-- cerrarlo o desactivarlo lo hace quien tiene la obra a cargo, y la comisión
-- se desactiva junto. El mensaje no nombra la comisión: el participante no
-- la ve.
CREATE OR REPLACE FUNCTION public.obras_vinculo_con_comision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.activo AND NEW.hasta IS NULL AND 'referente' = ANY (NEW.roles) THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.obras_comisiones c WHERE c.vinculo_id = NEW.id AND c.activo) THEN
    RETURN NULL;
  END IF;

  IF pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL
     AND NOT public.obras_a_cargo_de(NEW.registro_id, auth.uid()) THEN
    RAISE EXCEPTION 'Este referente lo maneja el responsable de la obra' USING ERRCODE = 'OB039';
  END IF;

  UPDATE public.obras_comisiones SET activo = false WHERE vinculo_id = NEW.id AND activo;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.obras_vinculo_con_comision() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS obras_vinculo_con_comision ON public.contactos_vinculos;
CREATE TRIGGER obras_vinculo_con_comision
  AFTER UPDATE OF roles, hasta, activo ON public.contactos_vinculos
  FOR EACH ROW WHEN (NEW.ente = 'obra')
  EXECUTE FUNCTION public.obras_vinculo_con_comision();

-- ============================================================
-- 6. Nombres: quien registró cada comisión que se ve
-- ============================================================
CREATE OR REPLACE FUNCTION public.obras_nombres()
RETURNS TABLE (id uuid, nombre text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH o AS (
    SELECT o.id, o.responsable_id, o.creado_por
    FROM obras o
    WHERE public.obras_puede_ver_obra_de(o.id, o.responsable_id, o.equipo_id, o.activo, auth.uid())
  ),
  ev AS (
    SELECT e.actor_id, e.evento, e.detalle
    FROM eventos e JOIN o ON o.id = e.registro_id
    WHERE e.ente = 'obra'
  ),
  refs AS (
    SELECT responsable_id AS id FROM o
    UNION SELECT creado_por FROM o
    UNION SELECT p.usuario_id FROM obras_participantes p JOIN o ON o.id = p.obra_id
    UNION SELECT p.agregado_por FROM obras_participantes p JOIN o ON o.id = p.obra_id
    UNION SELECT actor_id FROM ev
    UNION SELECT (detalle->>'de')::uuid FROM ev WHERE evento = 'transferencia'
    UNION SELECT (detalle->>'a')::uuid FROM ev WHERE evento = 'transferencia'
    UNION SELECT c.creado_por
          FROM obras_comisiones c
          JOIN contactos_vinculos v ON v.id = c.vinculo_id AND v.ente = 'obra'
          JOIN o ON o.id = v.registro_id
          WHERE public.obras_a_cargo_de(o.id, auth.uid())
  )
  SELECT u.id, u.nombre FROM usuarios u JOIN refs r ON r.id = u.id;
$$;
