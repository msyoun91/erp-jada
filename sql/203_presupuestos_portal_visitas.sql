-- Portal, tramo 3, 2 de 2: las visitas leídas del portal, su aviso y los tipos de cambio que se le mandan.
-- Decisiones: decisiones/erp-cliente.md → Visitas y La base. Test: sql/tests/presupuestos_portal_visitas.sql. El tipo sale de sql/202.

-- ============================================================
-- 1. Las visitas: una fila por link y versión, lo último que dijo el portal
-- ============================================================
CREATE TABLE IF NOT EXISTS public.presupuestos_links_visitas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id uuid NOT NULL REFERENCES public.presupuestos_links (id),
  version_id uuid NOT NULL REFERENCES public.presupuestos_versiones (id),
  visitas integer NOT NULL CHECK (visitas >= 1),
  dispositivos integer NOT NULL CHECK (dispositivos BETWEEN 1 AND visitas),
  primera timestamptz NOT NULL,
  ultima timestamptz NOT NULL CHECK (ultima >= primera),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS presupuestos_links_visitas_version
  ON public.presupuestos_links_visitas (link_id, version_id) WHERE activo;
CREATE INDEX IF NOT EXISTS presupuestos_links_visitas_de_version ON public.presupuestos_links_visitas (version_id);

ALTER TABLE public.presupuestos_links_visitas ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_updated_at ON public.presupuestos_links_visitas;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.presupuestos_links_visitas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP POLICY IF EXISTS presupuestos_links_visitas_select ON public.presupuestos_links_visitas;
CREATE POLICY presupuestos_links_visitas_select ON public.presupuestos_links_visitas FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.presupuestos_links l WHERE l.id = link_id));

REVOKE ALL ON public.presupuestos_links_visitas FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.presupuestos_links_visitas TO authenticated;

-- ============================================================
-- 2. El servidor del ERP: qué leer y guardar lo leído (service_role)
-- ============================================================
-- Los links que el portal alguna vez tuvo: los únicos que pueden tener visitas.
-- shortcut: lee todos en cada pasada; si pasan de unos miles, dejar afuera los cortados hace tiempo.
CREATE OR REPLACE FUNCTION public.presupuestos_portal_links()
RETURNS TABLE (link_id uuid, llave text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.id, l.llave FROM public.presupuestos_links l WHERE l.copia_revision IS NOT NULL ORDER BY l.created_at;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_links() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.presupuestos_portal_links() TO service_role;

-- Recibe [{link, version (número), visitas, dispositivos, primera, ultima}] como los da portal_visitas_de. Pisa lo anterior: el
-- portal guarda la cuenta entera. Una versión que no es del presupuesto del link no entra.
CREATE OR REPLACE FUNCTION public.presupuestos_portal_visitas(p_visitas jsonb)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.presupuestos_links_visitas (link_id, version_id, visitas, dispositivos, primera, ultima)
  SELECT l.id, v.id, (x->>'visitas')::integer, (x->>'dispositivos')::integer, (x->>'primera')::timestamptz,
         (x->>'ultima')::timestamptz
  FROM jsonb_array_elements(p_visitas) x
  JOIN public.presupuestos_links l ON l.id = (x->>'link')::uuid
  JOIN public.presupuestos_versiones v ON v.presupuesto_id = l.presupuesto_id AND v.numero = (x->>'version')::integer
  ON CONFLICT (link_id, version_id) WHERE activo DO UPDATE
    SET visitas = EXCLUDED.visitas, dispositivos = EXCLUDED.dispositivos, primera = EXCLUDED.primera, ultima = EXCLUDED.ultima
    WHERE (presupuestos_links_visitas.visitas, presupuestos_links_visitas.dispositivos, presupuestos_links_visitas.ultima)
      IS DISTINCT FROM (EXCLUDED.visitas, EXCLUDED.dispositivos, EXCLUDED.ultima);
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_visitas(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.presupuestos_portal_visitas(jsonb) TO service_role;

-- Los tipos de cambio que el portal usa para las referencias: todas las monedas con valor vigente, y cuáles muestra según la
-- configuración. ARS vale 1 con fecha fija, para que el portal no la reemplace en cada pasada.
CREATE OR REPLACE FUNCTION public.presupuestos_portal_monedas()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH ref AS (
    SELECT coalesce((SELECT c.monedas_referencia FROM public.presupuestos_configuracion c WHERE c.activo),
                    '{ARS,USD_OFICIAL}'::public.moneda[]) AS monedas
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('moneda', m.moneda, 'valor', m.valor, 'fecha', m.fecha,
                                               'referencia', m.moneda = ANY (ref.monedas)) ORDER BY m.moneda), '[]')
  FROM ref,
       (SELECT 'ARS'::public.moneda AS moneda, 1::numeric AS valor, '2000-01-01T00:00:00Z'::timestamptz AS fecha
        UNION ALL
        SELECT h.moneda, h.valor, h.fecha FROM public.monedas_hoy() h WHERE h.valor IS NOT NULL) m;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_monedas() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.presupuestos_portal_monedas() TO service_role;

-- ============================================================
-- 3. El aviso: la primera visita de cada versión, al responsable de la obra
-- ============================================================
-- Una versión que ya tuvo visitas por otro link (anulado) no avisa de nuevo.
CREATE OR REPLACE FUNCTION public.presupuestos_links_visitas_avisar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.notificar(o.responsable_id, 'presupuesto_visto', 'presupuestos_versiones', x.version_id, NULL)
  FROM (SELECT DISTINCT n.version_id FROM nuevas n) x
  JOIN public.presupuestos_versiones v ON v.id = x.version_id
  JOIN public.presupuestos p ON p.id = v.presupuesto_id
  JOIN public.obras o ON o.id = p.obra_id
  WHERE o.responsable_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.presupuestos_links_visitas a
                    WHERE a.version_id = x.version_id AND a.id NOT IN (SELECT n.id FROM nuevas n));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS presupuestos_links_visitas_avisar ON public.presupuestos_links_visitas;
CREATE TRIGGER presupuestos_links_visitas_avisar AFTER INSERT ON public.presupuestos_links_visitas
  REFERENCING NEW TABLE AS nuevas
  FOR EACH STATEMENT EXECUTE FUNCTION public.presupuestos_links_visitas_avisar();

REVOKE EXECUTE ON FUNCTION public.presupuestos_links_visitas_avisar() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. Leer los avisos: suma presupuesto_visto, mientras el lector vea el presupuesto
-- ============================================================
CREATE OR REPLACE FUNCTION public.presupuestos_avisos(p_ids uuid[])
RETURNS TABLE (notificacion_id uuid, etiqueta text, motivo text, destino text, destino_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH n AS (
    SELECT n.id, n.tipo, n.entidad, n.entidad_id
    FROM public.usuario_notificaciones n
    WHERE n.usuario_id = auth.uid() AND n.activo AND n.id = ANY (p_ids)
      AND n.entidad IN ('presupuestos_versiones', 'presupuestos_autorizaciones')
  )
  SELECT n.id,
         p.codigo || ' · v' || v.numero,
         CASE WHEN n.tipo = 'presupuesto_a_mano' THEN m.cuantos || CASE WHEN m.cuantos = 1 THEN ' renglón a mano' ELSE ' renglones a mano' END END,
         CASE WHEN n.tipo = 'presupuesto_pedido' AND NOT public.presupuestos_ve_de(p.obra_id, auth.uid())
              THEN 'presupuestos_revision' ELSE 'presupuesto' END,
         CASE WHEN n.tipo = 'presupuesto_pedido' AND NOT public.presupuestos_ve_de(p.obra_id, auth.uid()) THEN NULL ELSE p.id END
  FROM n
  JOIN public.presupuestos_versiones v ON v.id = n.entidad_id
  JOIN public.presupuestos p ON p.id = v.presupuesto_id
  CROSS JOIN LATERAL (SELECT count(*) AS cuantos FROM public.presupuestos_mano_nuevos(v.id)) m
  WHERE n.entidad = 'presupuestos_versiones'
    AND CASE n.tipo
      WHEN 'presupuesto_pedido' THEN EXISTS (
        SELECT 1 FROM public.presupuestos_autorizaciones a
        WHERE a.version_id = v.id AND a.estado = 'pendiente'
          AND public.presupuestos_puede_autorizar_de(a.tipo, p.obra_id, auth.uid()))
      WHEN 'presupuesto_autorizado' THEN v.estado = 'en_revision' AND public.presupuestos_ve_de(p.obra_id, auth.uid())
      WHEN 'presupuesto_a_mano' THEN m.cuantos > 0 AND public.presupuestos_puede_autorizar_de('comercial', p.obra_id, auth.uid())
      WHEN 'presupuesto_visto' THEN public.presupuestos_ve_de(p.obra_id, auth.uid())
    END

  UNION ALL

  SELECT n.id, p.codigo || ' · v' || v.numero, a.motivo, 'presupuesto', p.id
  FROM n
  JOIN public.presupuestos_autorizaciones a ON a.id = n.entidad_id
  JOIN public.presupuestos_versiones v ON v.id = a.version_id
  JOIN public.presupuestos p ON p.id = v.presupuesto_id
  WHERE n.tipo = 'presupuesto_devuelto' AND public.presupuestos_ve_de(p.obra_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_avisos(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_avisos(uuid[]) TO authenticated;
