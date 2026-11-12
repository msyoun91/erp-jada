-- Portal (erp-cliente), tramo 1a, en el ERP: el link de cada presupuesto y el estado de su copia.
-- Ficha y decisiones: decisiones/erp-cliente.md (→ La base). Esquema: db_schema/presupuestos.md. Test: sql/tests/presupuestos_links.sql.
-- Sigue el 1b: la función que arma lo que se copia (combinaciones, pisos, orden de casillas).
-- Errores, clase PR (siguen a sql/194): PR029 el presupuesto no tiene link: nunca se publicó.

-- ============================================================
-- 1. presupuestos_links
-- ============================================================
-- Uno activo por presupuesto. `revision` sube cada vez que cambia lo que el portal tiene que mostrar; `copia_revision` es la
-- última que el portal confirmó. Iguales: al día. Uno anulado sigue pendiente hasta que el portal confirma que lo cortó.
CREATE TABLE IF NOT EXISTS public.presupuestos_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  presupuesto_id uuid NOT NULL REFERENCES public.presupuestos(id),
  llave text NOT NULL DEFAULT encode(extensions.gen_random_bytes(16), 'hex') CHECK (llave ~ '^[0-9a-f]{32}$'),
  revision integer NOT NULL DEFAULT 1 CHECK (revision >= 1),
  copia_revision integer,
  copia_en timestamptz,
  copia_versiones integer[],
  link_copiado_en timestamptz,
  creado_por uuid DEFAULT auth.uid() REFERENCES public.usuarios(id),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT presupuestos_links_copia CHECK (
    (copia_revision IS NULL) = (copia_en IS NULL) AND (copia_revision IS NULL) = (copia_versiones IS NULL)
    AND copia_revision BETWEEN 1 AND revision)
);

CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_links_llave ON public.presupuestos_links (llave);
CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_links_vigente ON public.presupuestos_links (presupuesto_id) WHERE activo;
CREATE INDEX IF NOT EXISTS presupuestos_links_presupuesto ON public.presupuestos_links (presupuesto_id);

ALTER TABLE public.presupuestos_links ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_links;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_links
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS presupuestos_links_no_reactivar ON public.presupuestos_links;
CREATE TRIGGER presupuestos_links_no_reactivar
  BEFORE UPDATE OF activo ON public.presupuestos_links
  FOR EACH ROW EXECUTE FUNCTION public.presupuestos_no_reactivar();

-- Quien ve el presupuesto ve el estado de la copia. La llave no tiene GRANT: la da presupuestos_link_llave a quien arma.
DROP POLICY IF EXISTS presupuestos_links_select ON public.presupuestos_links;
CREATE POLICY presupuestos_links_select ON public.presupuestos_links FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.id = presupuesto_id));

REVOKE ALL ON public.presupuestos_links FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, presupuesto_id, revision, copia_revision, copia_en, copia_versiones, link_copiado_en, activo, created_at,
              updated_at) ON public.presupuestos_links TO authenticated;

-- ============================================================
-- 2. Cuándo nace el link y cuándo cambia lo que el portal muestra
-- ============================================================
-- El presupuesto: al salir de borrador nace el link; después, cada cambio de estado, de nombre o de versión elegida es otra
-- revisión. La versión: cuando entra o sale de `publicado` (publicar, corregir, quitar una variante). En la primera publicación
-- la versión cambia antes que el presupuesto: todavía no hay link y no sube nada. Una autorización de Técnica: vale para las
-- ventanas iguales de todo el presupuesto, así que puede habilitar una combinación en lo ya publicado.
CREATE OR REPLACE FUNCTION public.presupuestos_links_cambio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n jsonb := to_jsonb(NEW);
  v_presupuesto uuid := coalesce(
    (v_n->>'presupuesto_id')::uuid,
    (SELECT v.presupuesto_id FROM public.presupuestos_versiones v WHERE v.id = (v_n->>'version_id')::uuid),
    NEW.id);
BEGIN
  UPDATE public.presupuestos_links SET revision = revision + 1 WHERE presupuesto_id = v_presupuesto AND activo;
  IF NOT FOUND AND TG_TABLE_NAME = 'presupuestos' AND NEW.estado::text <> 'borrador' THEN
    INSERT INTO public.presupuestos_links (presupuesto_id) VALUES (NEW.id);
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_links_cambio() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS presupuestos_links_cambio ON public.presupuestos;
CREATE TRIGGER presupuestos_links_cambio
  AFTER UPDATE OF estado, nombre, version_aprobada_id ON public.presupuestos
  FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado OR OLD.nombre IS DISTINCT FROM NEW.nombre
                     OR OLD.version_aprobada_id IS DISTINCT FROM NEW.version_aprobada_id)
  EXECUTE FUNCTION public.presupuestos_links_cambio();

DROP TRIGGER IF EXISTS presupuestos_links_cambio ON public.presupuestos_versiones;
CREATE TRIGGER presupuestos_links_cambio
  AFTER UPDATE OF estado ON public.presupuestos_versiones
  FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado AND 'publicado' IN (OLD.estado::text, NEW.estado::text))
  EXECUTE FUNCTION public.presupuestos_links_cambio();

DROP TRIGGER IF EXISTS presupuestos_links_cambio ON public.presupuestos_autorizaciones;
CREATE TRIGGER presupuestos_links_cambio
  AFTER INSERT OR UPDATE OF estado ON public.presupuestos_autorizaciones
  FOR EACH ROW WHEN (NEW.tipo = 'tecnica' AND NEW.estado = 'autorizada')
  EXECUTE FUNCTION public.presupuestos_links_cambio();

-- Lo que ya estaba publicado o aprobado antes de esta migración.
INSERT INTO public.presupuestos_links (presupuesto_id, creado_por)
SELECT p.id, NULL
FROM public.presupuestos p
WHERE p.activo AND p.estado IN ('publicado', 'aprobado')
  AND NOT EXISTS (SELECT 1 FROM public.presupuestos_links l WHERE l.presupuesto_id = p.id AND l.activo);

-- ============================================================
-- 3. Quien arma: la llave y anular
-- ============================================================
-- La llave del link vigente. "Copiar link" (`p_copiar`) anota la primera vez; "Ver como cliente" la pide sin anotar.
CREATE OR REPLACE FUNCTION public.presupuestos_link_llave(p_presupuesto uuid, p_copiar boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_l public.presupuestos_links;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.id = p_presupuesto AND public.presupuestos_arma(p.obra_id)) THEN
    RAISE EXCEPTION 'No se encontró el presupuesto' USING ERRCODE = '42501';
  END IF;
  SELECT l.* INTO v_l FROM public.presupuestos_links l WHERE l.presupuesto_id = p_presupuesto AND l.activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El presupuesto no tiene link: nunca se publicó' USING ERRCODE = 'PR029';
  END IF;
  IF p_copiar AND v_l.link_copiado_en IS NULL THEN
    UPDATE public.presupuestos_links SET link_copiado_en = now() WHERE id = v_l.id AND link_copiado_en IS NULL;
  END IF;
  RETURN v_l.llave;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_link_llave(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_link_llave(uuid, boolean) TO authenticated;

-- Anular corta el link y crea otro en el momento. El viejo queda con una revisión más: pendiente hasta que el portal lo corte.
CREATE OR REPLACE FUNCTION public.presupuestos_link_anular(p_presupuesto uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.presupuestos p WHERE p.id = p_presupuesto AND public.presupuestos_arma(p.obra_id)) THEN
    RAISE EXCEPTION 'No se encontró el presupuesto' USING ERRCODE = '42501';
  END IF;
  UPDATE public.presupuestos_links SET activo = false, revision = revision + 1
  WHERE presupuesto_id = p_presupuesto AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El presupuesto no tiene link: nunca se publicó' USING ERRCODE = 'PR029';
  END IF;
  INSERT INTO public.presupuestos_links (presupuesto_id) VALUES (p_presupuesto);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_link_anular(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_link_anular(uuid) TO authenticated;

-- ============================================================
-- 4. El servidor que copia al portal (service_role, como Monedas)
-- ============================================================
-- Lo que falta copiar o cortar, lo más viejo primero.
CREATE OR REPLACE FUNCTION public.presupuestos_portal_pendientes()
RETURNS TABLE(link_id uuid, presupuesto_id uuid, llave text, revision integer, activo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.id, l.presupuesto_id, l.llave, l.revision, l.activo
  FROM public.presupuestos_links l
  WHERE l.copia_revision IS DISTINCT FROM l.revision
  ORDER BY l.updated_at, l.id;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_pendientes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.presupuestos_portal_pendientes() TO service_role;

-- El portal confirmó la revisión `p_revision`, que muestra esas versiones (vacío: cortado, o ya no disponible). Una revisión
-- más vieja que la confirmada no pisa nada; si mientras tanto subió otra, el link sigue pendiente.
CREATE OR REPLACE FUNCTION public.presupuestos_portal_copiada(p_link uuid, p_revision integer, p_versiones integer[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.presupuestos_links
  SET copia_revision = p_revision, copia_en = now(), copia_versiones = coalesce(p_versiones, '{}')
  WHERE id = p_link AND p_revision BETWEEN greatest(coalesce(copia_revision, 1), 1) AND revision;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_copiada(uuid, integer, integer[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.presupuestos_portal_copiada(uuid, integer, integer[]) TO service_role;
