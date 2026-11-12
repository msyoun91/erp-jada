-- Portal (erp-cliente), tramo 1b, en el ERP: lo que se copia de cada link, y las monedas de referencia en la configuración.
-- Ficha y decisiones: decisiones/erp-cliente.md (→ La base). Esquema: db_schema/presupuestos.md.
-- Test: sql/tests/presupuestos_portal_copia.sql. Sigue el tramo 2: la base del portal.

-- ============================================================
-- 1. Monedas de referencia: las elige gerencia, para todos
-- ============================================================
ALTER TABLE public.presupuestos_configuracion
  ADD COLUMN IF NOT EXISTS monedas_referencia public.moneda[] NOT NULL DEFAULT '{ARS,USD_OFICIAL}'
  CHECK (array_position(monedas_referencia, NULL) IS NULL);

GRANT INSERT (monedas_referencia) ON public.presupuestos_configuracion TO authenticated;

-- Sin `p_monedas`, siguen las que estaban: la pantalla de hoy configura tope y plazo sin tocarlas.
DROP FUNCTION IF EXISTS public.presupuestos_configurar(numeric, integer);
CREATE OR REPLACE FUNCTION public.presupuestos_configurar(p_tope numeric, p_plazo integer, p_monedas public.moneda[] DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_monedas public.moneda[];
BEGIN
  IF NOT public.tiene_permiso('presupuestos_configuracion') THEN
    RAISE EXCEPTION 'Sin permiso para configurar Presupuestos' USING ERRCODE = '42501';
  END IF;
  SELECT c.monedas_referencia INTO v_monedas FROM public.presupuestos_configuracion c WHERE c.activo;
  UPDATE public.presupuestos_configuracion SET activo = false WHERE activo;
  INSERT INTO public.presupuestos_configuracion (id, tope_descuento, plazo_dias, monedas_referencia)
  VALUES (v_id, p_tope, p_plazo, coalesce(p_monedas, v_monedas, '{ARS,USD_OFICIAL}'));
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer, public.moneda[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_configurar(numeric, integer, public.moneda[]) TO authenticated;

-- ============================================================
-- 2. Los importes de unos renglones, sin mirar quién pregunta
-- ============================================================
-- La cuenta de presupuestos_version_importes (sql/195), sobre los renglones que le pasan: `[{id, seccion_id, moneda, cantidad,
-- precio, lineas, nombre}]`. Así la copia del portal le da una combinación que no está guardada y sale con la misma regla.
-- Sin GRANT: el permiso lo mira quien la llama.
CREATE OR REPLACE FUNCTION public.presupuestos_importes_de(p_version uuid, p_renglones jsonb)
RETURNS TABLE(renglon_id uuid, seccion_id uuid, moneda public.moneda, alicuota numeric, clave text, nombre text, importe numeric,
              importe_con_iva numeric, debajo jsonb)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH r AS (
    SELECT x.id, x.seccion_id, x.moneda, x.cantidad, x.precio, x.lineas, x.nombre, s.alicuota
    FROM jsonb_to_recordset(p_renglones) AS x (id uuid, seccion_id uuid, moneda public.moneda, cantidad numeric, precio numeric,
                                               lineas jsonb, nombre text)
    JOIN public.presupuestos_secciones s ON s.id = x.seccion_id
  ),
  f AS (SELECT 1 - public.presupuestos_recargo_de(p_version) / 100 AS factor),
  ap AS (
    SELECT r.id, r.cantidad, o.clave, s.id AS seccion_id, s.moneda, s.alicuota,
           (SELECT (l->>'monto')::numeric FROM jsonb_array_elements(r.lineas) l
            WHERE l->>'clave' = o.clave AND l->>'moneda' = r.moneda::text) AS propio,
           (SELECT l FROM jsonb_array_elements(r.lineas) l
            WHERE l->>'clave' = o.clave AND l->>'moneda' = s.moneda::text) AS linea
    FROM r
    JOIN public.presupuestos_opcionales o ON o.version_id = p_version AND o.activo AND o.forma = 'aparte'
    JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
    WHERE r.precio IS NOT NULL AND r.lineas @> jsonb_build_array(jsonb_build_object('clave', o.clave))
  ),
  de AS (
    SELECT d.id, jsonb_agg(jsonb_build_object('clave', d.clave, 'nombre', d.nombre, 'importe', d.importe,
             'importe_con_iva', public.catalogo_precio_redondear(d.importe * (1 + d.alicuota / 100), d.moneda)) ORDER BY d.n) AS lineas
    FROM (
      SELECT r.id, r.moneda, r.alicuota, x.n, o.clave, x.l->>'nombre' AS nombre,
             public.catalogo_precio_redondear((x.l->>'monto')::numeric * r.cantidad / f.factor, r.moneda) AS importe
      FROM r CROSS JOIN f
      CROSS JOIN LATERAL jsonb_array_elements(r.lineas) WITH ORDINALITY AS x (l, n)
      JOIN public.presupuestos_opcionales o
        ON o.version_id = p_version AND o.activo AND o.forma = 'debajo' AND o.clave = x.l->>'clave'
      WHERE r.precio IS NOT NULL AND x.l->>'moneda' = r.moneda::text
    ) d
    GROUP BY d.id
  ),
  i AS (
    SELECT r.id AS renglon_id, r.seccion_id, r.moneda, r.alicuota, NULL::text AS clave, r.nombre,
           public.catalogo_precio_redondear(
             (r.precio - coalesce((SELECT sum(ap.propio) FROM ap WHERE ap.id = r.id), 0)) * r.cantidad / f.factor, r.moneda) AS importe,
           coalesce((SELECT de.lineas FROM de WHERE de.id = r.id), '[]'::jsonb) AS debajo
    FROM r, f
    UNION ALL
    SELECT ap.id, ap.seccion_id, ap.moneda, ap.alicuota, ap.clave, ap.linea->>'nombre',
           public.catalogo_precio_redondear((ap.linea->>'monto')::numeric * ap.cantidad / f.factor, ap.moneda),
           NULL::jsonb
    FROM ap, f
  )
  SELECT i.renglon_id, i.seccion_id, i.moneda, i.alicuota, i.clave, i.nombre, i.importe,
         public.catalogo_precio_redondear(i.importe * (1 + i.alicuota / 100), i.moneda), i.debajo
  FROM i;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_importes_de(uuid, jsonb) FROM PUBLIC, anon, authenticated;

-- Lo guardado en la versión, para quien ve el presupuesto.
CREATE OR REPLACE FUNCTION public.presupuestos_version_importes(p_version uuid)
RETURNS TABLE(renglon_id uuid, seccion_id uuid, moneda public.moneda, alicuota numeric, clave text, nombre text, importe numeric,
              importe_con_iva numeric, debajo jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT i.*
  FROM public.presupuestos_importes_de(p_version, (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'id', r.id, 'seccion_id', r.seccion_id, 'moneda', r.moneda, 'cantidad', r.cantidad, 'precio', r.precio,
             'lineas', r.lineas, 'nombre', coalesce(cv.nombre, r.descripcion))), '[]')
    FROM public.presupuestos_renglones r
    LEFT JOIN public.catalogo_versiones cv ON cv.id = r.catalogo_version_id
    WHERE r.version_id = p_version AND r.activo
      AND EXISTS (SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
                  WHERE v.id = p_version AND public.presupuestos_ve(p.obra_id)))) i;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_importes(uuid) TO authenticated;

-- ============================================================
-- 3. Los nombres de lo cargado, sin mirar quién pregunta
-- ============================================================
-- Lo de presupuestos_version_nombres (sql/198). Sin GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_nombres_de(p_version uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH r AS (
    SELECT r.catalogo_version_id, r.entrada
    FROM public.presupuestos_renglones r
    WHERE r.version_id = p_version AND r.activo AND r.tipo = 'catalogo'
  ),
  ids AS (
    SELECT r.entrada->>'color' AS id FROM r
    UNION
    SELECT m.value FROM r, jsonb_each(coalesce(r.entrada->'elecciones', '{}')) e, jsonb_each_text(e.value) m
  )
  SELECT jsonb_build_object(
    'nombres', coalesce((
      SELECT jsonb_object_agg(x.id, x.nombre) FROM (
        SELECT c.id, c.nombre FROM public.catalogo_colores c WHERE c.id::text IN (SELECT ids.id FROM ids)
        UNION ALL
        SELECT i.id, i.nombre FROM public.catalogo_insumos i WHERE i.id::text IN (SELECT ids.id FROM ids)) x), '{}'),
    'orden', coalesce((
      SELECT jsonb_object_agg(cv.version_id || ':' || cv.nombre, cv.orden)
      FROM public.catalogo_variables cv
      WHERE cv.activo AND cv.ingresa_vendedor AND cv.version_id IN (SELECT r.catalogo_version_id FROM r)), '{}'));
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_nombres_de(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_version_nombres(p_version uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM public.presupuestos_versiones v JOIN public.presupuestos p ON p.id = v.presupuesto_id
                           WHERE v.id = p_version AND public.presupuestos_ve(p.obra_id))
    THEN public.presupuestos_nombres_de(p_version)
    ELSE jsonb_build_object('nombres', '{}'::jsonb, 'orden', '{}'::jsonb) END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_version_nombres(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_version_nombres(uuid) TO authenticated;

-- ============================================================
-- 4. Las combinaciones de opcionales de una ventana
-- ============================================================
-- Cada combinación de casillas con precio, calculada con la versión de Catálogo y la fecha de la ventana, como lo publicado.
-- Las casillas, en su orden (el del código de "Enviar mi elección"): las piezas opcionales de esa versión, por orden y nombre, y
-- después los servicios opcionales vigentes a esa fecha, por paso y nombre. `n` lleva un bit por casilla; `casillas`, las
-- tildadas `[{n, clave, nombre}]`. Una combinación que el cálculo deja distinta de lo tildado (la Cortina sin su Cajón, un
-- servicio que no aplica) no sale: es otra. `motivos`: sus alertas; si Técnica las cubre lo decide quien llama. Sin GRANT.
-- shortcut: una tanda de cálculos por combinación (n · 2^n precios por ventana distinta, 13 ms cada uno); si una versión no
-- entra en los 8 s de una llamada, sacar las líneas de los precios de los subconjuntos (2^n).
CREATE OR REPLACE FUNCTION public.presupuestos_portal_combinaciones(p_paquete uuid, p_version uuid, p_fecha timestamptz,
                                                                    p_entrada jsonb, p_opcionales uuid[], p_monedas public.moneda[])
RETURNS TABLE(n integer, casillas jsonb, entrada jsonb, precio numeric, lineas jsonb, motivos jsonb)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_c jsonb;
  v_todo jsonb;
  v_fijos uuid[];
  v_opc uuid[];
  v_p jsonb;
  v_n integer;
BEGIN
  SELECT coalesce(jsonb_agg(x.c ORDER BY x.o), '[]') INTO v_c
  FROM (
    SELECT jsonb_build_object('clave', public.presupuestos_clave(p.nombre, NULL), 'nombre', p.nombre, 'pieza', p.nombre) AS c,
           row_number() OVER (ORDER BY p.orden, p.nombre) AS o
    FROM public.catalogo_piezas p
    WHERE p.version_id = p_version AND p.activo AND p.opcional
    UNION ALL
    SELECT jsonb_build_object('clave', public.presupuestos_clave(NULL, s.porcentaje_id), 'nombre', s.nombre,
                              'porcentaje_id', s.porcentaje_id),
           1000 + row_number() OVER (ORDER BY s.paso, s.nombre)
    FROM public.catalogo_porcentajes_vigentes(p_fecha) s
    WHERE s.opcional AND NOT s.de_baja) x;

  -- Con todo tildado, el servicio que no aplica no aplica nunca: no es casilla, y cada casilla duplica las cuentas.
  v_todo := public.catalogo_precio_en(p_paquete, p_version, p_fecha,
    p_entrada || jsonb_build_object('piezas', (
      SELECT coalesce(jsonb_object_agg(c->>'pieza', true), '{}') FROM jsonb_array_elements(v_c) c WHERE c ? 'pieza')),
    ARRAY(SELECT (c->>'porcentaje_id')::uuid FROM jsonb_array_elements(v_c) c WHERE c ? 'porcentaje_id'), p_monedas[1]);
  IF v_todo->>'precio' IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(t.c ORDER BY t.i), '[]') INTO v_c
    FROM jsonb_array_elements(v_c) WITH ORDINALITY AS t (c, i)
    WHERE t.c ? 'pieza' OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_todo->'servicios') s
      WHERE s->>'porcentaje_id' = t.c->>'porcentaje_id' AND (s->>'aplica')::boolean);
  END IF;

  v_fijos := ARRAY(SELECT o FROM unnest(p_opcionales) o
                   WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_c) c WHERE c->>'porcentaje_id' = o::text));

  FOR v_n IN 0 .. (1 << jsonb_array_length(v_c)) - 1 LOOP
    SELECT coalesce(jsonb_agg(jsonb_build_object('n', t.i, 'clave', t.c->'clave', 'nombre', t.c->'nombre') ORDER BY t.i)
                      FILTER (WHERE t.tilde), '[]'),
           p_entrada || jsonb_build_object('piezas', coalesce(p_entrada->'piezas', '{}')
             || coalesce(jsonb_object_agg(t.c->>'pieza', t.tilde) FILTER (WHERE t.c ? 'pieza'), '{}')),
           v_fijos || coalesce(array_agg((t.c->>'porcentaje_id')::uuid) FILTER (WHERE t.tilde AND t.c ? 'porcentaje_id'), '{}')
    INTO casillas, entrada, v_opc
    FROM (SELECT x.c, x.i::integer AS i, ((v_n >> (x.i::integer - 1)) & 1) = 1 AS tilde
          FROM jsonb_array_elements(v_c) WITH ORDINALITY AS x (c, i)) t;

    v_p := public.catalogo_precio_lineas_en(p_paquete, p_version, p_fecha, entrada, v_opc, p_monedas);
    CONTINUE WHEN v_p->>'precio' IS NULL;

    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'clave', public.presupuestos_clave(t.l->>'pieza', (t.l->>'porcentaje_id')::uuid),
             'nombre', t.l->'nombre', 'moneda', t.l->'moneda', 'monto', t.l->'monto') ORDER BY t.i), '[]')
    INTO lineas
    FROM jsonb_array_elements(v_p->'lineas') WITH ORDINALITY AS t (l, i);

    CONTINUE WHEN (SELECT coalesce(jsonb_agg(c->'clave' ORDER BY (c->>'n')::integer), '[]') FROM jsonb_array_elements(casillas) c)
      IS DISTINCT FROM (SELECT coalesce(jsonb_agg(t.c->'clave' ORDER BY t.i), '[]')
                        FROM jsonb_array_elements(v_c) WITH ORDINALITY AS t (c, i)
                        WHERE lineas @> jsonb_build_array(jsonb_build_object('clave', t.c->'clave')));

    n := v_n;
    precio := (v_p->>'precio')::numeric;
    SELECT coalesce(jsonb_agg(m->'mensaje'), '[]') INTO motivos
    FROM jsonb_array_elements(v_p->'mensajes') m WHERE NOT (m->>'bloquea')::boolean;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_combinaciones(uuid, uuid, timestamptz, jsonb, uuid[], public.moneda[])
  FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 5. Lo que el portal muestra de una versión
-- ============================================================
-- Secciones y renglones en su orden, y de cada renglón sus combinaciones: la publicada primero, siempre, con el precio y las
-- líneas guardados; las demás (`p_casillas`), las que tienen precio y cuyas alertas cubre una autorización de Técnica del
-- presupuesto. Si lo publicado no sale del cálculo, la ventana va sin casillas. Cada combinación trae los importes que ve el
-- cliente, con la regla de siempre (presupuestos_importes_de): el del renglón, lo de debajo y lo que suma a cada renglón aparte.
-- `aparte`: los renglones aparte, con el piso del mínimo de su servicio en la moneda de su sección; el portal avisa si lo que
-- suma el renglón queda por debajo. `entrada`, `nombres` y `orden`: lo cargado, para el texto de cada ventana. Sin GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_portal_version(p_version uuid, p_casillas boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_v public.presupuestos_versiones;
  v_r record;
  v_k text;
  v_cache jsonb := '{}';
  v_tildadas jsonb;
  v_combos jsonb;
  v_casillas jsonb;
  v_renglones jsonb := '[]';
BEGIN
  SELECT * INTO v_v FROM public.presupuestos_versiones WHERE id = p_version;

  FOR v_r IN
    SELECT r.*, coalesce(cv.nombre, r.descripcion) AS nombre
    FROM public.presupuestos_renglones r
    JOIN public.presupuestos_secciones s ON s.id = r.seccion_id
    LEFT JOIN public.catalogo_versiones cv ON cv.id = r.catalogo_version_id
    WHERE r.version_id = p_version AND r.activo
    ORDER BY s.orden, s.nombre, r.orden, r.created_at, r.id
  LOOP
    -- Las ventanas iguales, calculadas en el mismo momento, comparten la cuenta.
    v_k := NULL;
    IF p_casillas AND v_r.tipo = 'catalogo' AND v_r.precio IS NOT NULL THEN
      v_k := md5(concat_ws('|', v_r.paquete_id, v_r.catalogo_version_id, v_r.condiciones_en, v_r.entrada, v_r.opcionales, v_r.moneda));
      IF NOT v_cache ? v_k THEN
        v_cache := v_cache || jsonb_build_object(v_k, (
          SELECT coalesce(jsonb_agg(to_jsonb(c)), '[]')
          FROM public.presupuestos_portal_combinaciones(v_r.paquete_id, v_r.catalogo_version_id, v_r.condiciones_en, v_r.entrada,
                 v_r.opcionales, public.presupuestos_renglon_monedas(p_version, v_r.moneda)) c));
      END IF;
    END IF;

    SELECT coalesce(jsonb_agg(DISTINCT l->'clave'), '[]') INTO v_tildadas FROM jsonb_array_elements(v_r.lineas) l;

    WITH k AS (
      SELECT k.n, k.casillas, k.entrada, k.precio, k.lineas, k.motivos,
             (SELECT coalesce(jsonb_agg(c->'clave' ORDER BY (c->>'n')::integer), '[]') FROM jsonb_array_elements(k.casillas) c) AS claves
      FROM jsonb_to_recordset(coalesce(v_cache->v_k, '[]'))
             AS k (n integer, casillas jsonb, entrada jsonb, precio numeric, lineas jsonb, motivos jsonb)
    ),
    kk AS (SELECT k.*, (k.claves @> v_tildadas AND k.claves <@ v_tildadas) AS publicada FROM k),
    c AS (
      SELECT kk.n, kk.publicada, kk.casillas, kk.claves,
             CASE WHEN kk.publicada THEN v_r.precio ELSE kk.precio END AS precio,
             CASE WHEN kk.publicada THEN v_r.lineas ELSE kk.lineas END AS lineas
      FROM kk
      WHERE EXISTS (SELECT 1 FROM kk p WHERE p.publicada)
        AND (kk.publicada OR kk.motivos = '[]' OR EXISTS (
              SELECT 1
              FROM public.presupuestos_autorizaciones a
              JOIN public.presupuestos_versiones av ON av.id = a.version_id
              WHERE av.presupuesto_id = v_v.presupuesto_id AND a.tipo = 'tecnica' AND a.estado = 'autorizada' AND a.activo
                -- Con las mismas piezas que lo publicado es la ventana que vio Técnica: los servicios no cambian el despiece.
                AND public.presupuestos_tecnica_cubre(a.pedido, jsonb_build_object(
                      'paquete_id', v_r.paquete_id, 'catalogo_version_id', v_r.catalogo_version_id, 'motivos', kk.motivos,
                      'entrada', CASE WHEN jsonb_path_query_array(kk.claves, '$[*] ? (@ starts with "pieza:")')
                                           @> jsonb_path_query_array(v_tildadas, '$[*] ? (@ starts with "pieza:")')
                                       AND jsonb_path_query_array(kk.claves, '$[*] ? (@ starts with "pieza:")')
                                           <@ jsonb_path_query_array(v_tildadas, '$[*] ? (@ starts with "pieza:")')
                                      THEN v_r.entrada ELSE kk.entrada END))))
      UNION ALL
      SELECT 0, true, '[]'::jsonb, '[]'::jsonb, v_r.precio, v_r.lineas
      WHERE NOT EXISTS (SELECT 1 FROM kk p WHERE p.publicada)
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object('casillas', c.claves, 'publicada', c.publicada) || (
             SELECT jsonb_build_object(
               'importe', max(i.importe) FILTER (WHERE i.clave IS NULL),
               'importe_con_iva', max(i.importe_con_iva) FILTER (WHERE i.clave IS NULL),
               'debajo', coalesce((jsonb_agg(i.debajo) FILTER (WHERE i.clave IS NULL))->0, '[]'),
               'aparte', coalesce(jsonb_agg(jsonb_build_object('clave', i.clave, 'nombre', i.nombre, 'seccion_id', i.seccion_id,
                           'importe', i.importe, 'importe_con_iva', i.importe_con_iva)) FILTER (WHERE i.clave IS NOT NULL), '[]'))
             FROM public.presupuestos_importes_de(p_version, jsonb_build_array(jsonb_build_object(
                    'id', v_r.id, 'seccion_id', v_r.seccion_id, 'moneda', v_r.moneda, 'cantidad', v_r.cantidad,
                    'precio', c.precio, 'lineas', c.lineas, 'nombre', v_r.nombre))) i)
             ORDER BY c.publicada DESC, c.n), '[]'),
           coalesce((SELECT jsonb_agg(d.x - 'n' ORDER BY (d.x->>'n')::integer)
                     FROM (SELECT DISTINCT x FROM c c2, jsonb_array_elements(c2.casillas) x) d), '[]')
    INTO v_combos, v_casillas
    FROM c;

    v_renglones := v_renglones || jsonb_build_object(
      'id', v_r.id, 'seccion_id', v_r.seccion_id, 'tipo', v_r.tipo, 'designacion', v_r.designacion, 'ubicacion', v_r.ubicacion,
      'cantidad', v_r.cantidad, 'nombre', v_r.nombre, 'entrada', v_r.entrada - 'piezas',
      'minimo_de', CASE WHEN v_r.tipo = 'minimo' THEN public.presupuestos_clave(NULL, v_r.porcentaje_id) END,
      'casillas', v_casillas, 'combinaciones', v_combos);
  END LOOP;

  RETURN jsonb_build_object(
    'numero', v_v.numero, 'variante', v_v.variante, 'variante_nombre', v_v.variante_nombre,
    'iva_discriminado', v_v.iva_discriminado, 'descuento', v_v.descuento, 'vence', v_v.vence,
    'secciones', (
      SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre, 'moneda', s.moneda, 'alicuota', s.alicuota)
                                ORDER BY s.orden, s.nombre), '[]')
      FROM public.presupuestos_secciones s WHERE s.version_id = p_version AND s.activo),
    'aparte', (
      SELECT coalesce(jsonb_agg(jsonb_build_object('clave', o.clave, 'seccion_id', o.seccion_id,
               'piso', public.presupuestos_recargar(p_version,
                         public.catalogo_precio_convertir(x.minimo, x.minimo_moneda, s.moneda, f.fecha), s.moneda)) ORDER BY o.clave), '[]')
      FROM public.presupuestos_opcionales o
      JOIN public.presupuestos_secciones s ON s.id = o.seccion_id
      CROSS JOIN (SELECT max(r.condiciones_en) AS fecha FROM public.presupuestos_renglones r
                  WHERE r.version_id = p_version AND r.activo AND r.tipo = 'catalogo') f
      LEFT JOIN LATERAL public.catalogo_porcentajes_vigentes(f.fecha) x
        ON x.porcentaje_id = o.porcentaje_id AND NOT x.de_baja AND x.minimo_por = 'presupuesto'
      WHERE o.version_id = p_version AND o.activo AND o.forma = 'aparte'),
    'renglones', v_renglones) || public.presupuestos_nombres_de(p_version);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_version(uuid, boolean) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 6. Lo que se copia de un link (service_role, como lo demás del portal)
-- ============================================================
-- Con la `revision` que tenía el link al armarlo: es la que el servidor confirma con presupuestos_portal_copiada, así una
-- revisión que sube mientras copia deja al link pendiente. `cortado`: el link se anuló. `no_disponible`: rechazado o
-- desactivado. `publicado`: cada variante publicada, con sus casillas. `aprobado`: solo la elegida, sin casillas. El WhatsApp
-- es el del responsable de la obra. Un link que no existe: NULL.
CREATE OR REPLACE FUNCTION public.presupuestos_portal_copia(p_link uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_l public.presupuestos_links;
  v_p public.presupuestos;
BEGIN
  SELECT * INTO v_l FROM public.presupuestos_links WHERE id = p_link;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_p FROM public.presupuestos WHERE id = v_l.presupuesto_id;
  IF NOT v_l.activo THEN
    RETURN jsonb_build_object('revision', v_l.revision, 'estado', 'cortado');
  ELSIF NOT v_p.activo OR v_p.estado NOT IN ('publicado', 'aprobado') THEN
    RETURN jsonb_build_object('revision', v_l.revision, 'estado', 'no_disponible');
  END IF;

  RETURN jsonb_build_object(
    'revision', v_l.revision, 'estado', v_p.estado, 'codigo', v_p.codigo, 'nombre', v_p.nombre,
    'aprobado_en', CASE WHEN v_p.estado = 'aprobado' THEN (
      SELECT max(e.created_at) FROM public.eventos e
      WHERE e.ente = 'presupuesto' AND e.registro_id = v_p.id AND e.evento = 'estado' AND e.detalle->>'estado' = 'aprobado') END,
    'whatsapp', (SELECT u.telefono FROM public.obras o JOIN public.usuarios u ON u.id = o.responsable_id WHERE o.id = v_p.obra_id),
    'versiones', (
      SELECT coalesce(jsonb_agg(public.presupuestos_portal_version(v.id, v_p.estado = 'publicado') ORDER BY v.variante), '[]')
      FROM public.presupuestos_versiones v
      WHERE v.presupuesto_id = v_p.id AND v.activo
        AND CASE WHEN v_p.estado = 'aprobado' THEN v.id = v_p.version_aprobada_id ELSE v.estado = 'publicado' END));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_portal_copia(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.presupuestos_portal_copia(uuid) TO service_role;
