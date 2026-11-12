-- Portal (erp-cliente), tramo 2: la base del portal (proyecto gprkjktlbtemzzjanijn, MCP supabase-portal). Numeración propia.
-- Ficha y decisiones: decisiones/erp-cliente.md (→ La base). Esquema: db_schema/portal.md. Test: sql/portal/tests/portal_base.sql.
--
-- Nadie lee las tablas: no hay usuarios. El servidor del portal (clave publicable, `anon`) solo lee una copia y anota visitas
-- por huella; el servidor del ERP (`service_role`) copia, corta y lee visitas. El portal no sabe qué presupuesto es cada link.

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_updated_at() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 1. Tablas
-- ============================================================
-- Un link por huella (SHA-256 del link, en hexa). `copia`: el presupuesto cifrado con la llave derivada del link, en base64, tal
-- cual lo arma el ERP. `versiones`: los números que muestra, para validar visitas. Cortado: `activo = false`, sin copia, y no vuelve.
CREATE TABLE IF NOT EXISTS public.portal_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  huella text NOT NULL UNIQUE CHECK (huella ~ '^[0-9a-f]{64}$'),
  revision integer NOT NULL CHECK (revision >= 1),
  copia text CHECK (length(copia) <= 10000000 AND copia ~ '^[A-Za-z0-9+/]+={0,2}$'),
  versiones integer[] NOT NULL DEFAULT '{}' CHECK (array_position(versiones, NULL) IS NULL),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT portal_links_copia CHECK (activo = (copia IS NOT NULL) AND (activo OR versiones = '{}'))
);

-- Una visita: las aperturas de un dispositivo a una versión sin 30 min de pausa. `created_at`, la primera; `ultima`, la última.
CREATE TABLE IF NOT EXISTS public.portal_visitas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id uuid NOT NULL REFERENCES public.portal_links (id),
  version integer NOT NULL,
  dispositivo uuid NOT NULL,
  ultima timestamptz NOT NULL DEFAULT now(),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS portal_visitas_link ON public.portal_visitas (link_id, dispositivo, version, ultima);

DROP TRIGGER IF EXISTS set_updated_at ON public.portal_links;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.portal_links FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS set_updated_at ON public.portal_visitas;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.portal_visitas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- RLS sin policies: solo las funciones de abajo y service_role.
ALTER TABLE public.portal_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.portal_visitas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.portal_links, public.portal_visitas FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 2. El ERP: copiar, cortar y leer visitas (service_role)
-- ============================================================
-- Con `p_copia` copia la revisión; sin ella corta el link. Una revisión que no es más nueva que la guardada no cambia nada (un
-- reintento, o una copia vieja que llega tarde), y un link cortado no vuelve. Lo inválido falla: el ERP no confirma la copia.
CREATE OR REPLACE FUNCTION public.portal_copiar(p_huella text, p_revision integer, p_copia text, p_versiones integer[])
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_copia IS NULL AND coalesce(p_versiones, '{}') <> '{}' THEN
    RAISE EXCEPTION 'Un link cortado no muestra versiones' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.portal_links (huella, revision, copia, versiones, activo)
  VALUES (p_huella, p_revision, p_copia, coalesce(p_versiones, '{}'), p_copia IS NOT NULL)
  ON CONFLICT (huella) DO UPDATE
    SET revision = EXCLUDED.revision, copia = EXCLUDED.copia, versiones = EXCLUDED.versiones, activo = EXCLUDED.activo
    WHERE portal_links.activo AND EXCLUDED.revision > portal_links.revision;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.portal_copiar(text, integer, text, integer[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.portal_copiar(text, integer, text, integer[]) TO service_role;

-- Por huella y versión: visitas, dispositivos, primera y última. Las huellas que no están, o sin visitas, no vuelven.
CREATE OR REPLACE FUNCTION public.portal_visitas_de(p_huellas text[])
RETURNS TABLE(huella text, version integer, visitas integer, dispositivos integer, primera timestamptz, ultima timestamptz)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT l.huella, v.version, count(*)::integer, count(DISTINCT v.dispositivo)::integer, min(v.created_at), max(v.ultima)
  FROM public.portal_links l
  JOIN public.portal_visitas v ON v.link_id = l.id AND v.activo
  WHERE l.huella = ANY (p_huellas)
  GROUP BY l.huella, v.version;
$$;

REVOKE EXECUTE ON FUNCTION public.portal_visitas_de(text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.portal_visitas_de(text[]) TO service_role;

-- ============================================================
-- 3. El servidor del portal: leer y anotar (anon)
-- ============================================================
-- La copia cifrada del link vigente; cortado o inexistente: NULL, sin distinguir.
CREATE OR REPLACE FUNCTION public.portal_leer(p_huella text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.copia FROM public.portal_links l WHERE l.huella = p_huella AND l.activo;
$$;

REVOKE EXECUTE ON FUNCTION public.portal_leer(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.portal_leer(text) TO anon, service_role;

-- Una apertura. Dentro de los 30 min de la última del mismo dispositivo a la misma versión, la estira; si no, es otra visita.
-- Link cortado o versión que no muestra: no anota y no avisa. El bloqueo del link ordena dos aperturas simultáneas.
CREATE OR REPLACE FUNCTION public.portal_visitar(p_huella text, p_version integer, p_dispositivo uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link uuid;
BEGIN
  SELECT l.id INTO v_link FROM public.portal_links l
  WHERE l.huella = p_huella AND l.activo AND p_version = ANY (l.versiones) AND p_dispositivo IS NOT NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  UPDATE public.portal_visitas SET ultima = now()
  WHERE link_id = v_link AND dispositivo = p_dispositivo AND version = p_version AND activo
    AND ultima > now() - interval '30 minutes';
  IF NOT FOUND THEN
    INSERT INTO public.portal_visitas (link_id, version, dispositivo) VALUES (v_link, p_version, p_dispositivo);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.portal_visitar(text, integer, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.portal_visitar(text, integer, uuid) TO anon, service_role;
