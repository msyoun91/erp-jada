-- Portal (erp-cliente), tramo 4, en el ERP: aplicar la elección que el cliente envía desde el portal.
-- Ficha y decisiones: decisiones/erp-cliente.md (→ Aplicar la elección). Esquema: db_schema/presupuestos.md.
-- Test: sql/tests/presupuestos_eleccion.sql.
--
-- El código: `P-0142-V3-7K2M-9QX4-B`. El número del presupuesto, el de la versión, la elección y un dígito de control. La
-- elección son bits en Crockford base32 (5 por letra, el primero el más alto): por cada ventana con casillas (`ancho` > 0), en el
-- orden de la copia, el `n` de la combinación elegida en `ancho` bits, el más alto primero; al final, ceros hasta completar la
-- letra. Los grupos de 4 letras van separados por guiones. El dígito: Σ peso × valor de cada letra de `<numero>V<version><bits>`
-- (`142V37K2M9QX4`), con pesos 1..30 que se repiten, módulo 31, como letra del mismo alfabeto.

-- ============================================================
-- 1. Los totales de unos importes, con la regla de siempre
-- ============================================================
-- La cuenta de presupuestos_version_totales (sql/187), sobre `[{moneda, alicuota, importe}]`: así "lo que vio el cliente" sale
-- con la misma regla que el ERP. INVOKER: lee el descuento de la versión con la RLS de quien llama.
CREATE OR REPLACE FUNCTION public.presupuestos_totales_de(p_version uuid, p_importes jsonb)
RETURNS TABLE(moneda public.moneda, subtotal numeric, descuento numeric, iva jsonb, total numeric, sin_precio integer)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH a AS (
    SELECT i.moneda, i.alicuota, coalesce(sum(i.importe), 0) AS base, count(*) FILTER (WHERE i.importe IS NULL) AS sin_precio
    FROM jsonb_to_recordset(p_importes) AS i (moneda public.moneda, alicuota numeric, importe numeric)
    GROUP BY i.moneda, i.alicuota
  ),
  b AS (
    SELECT a.*, public.catalogo_precio_redondear(a.base * v.descuento / 100, a.moneda) AS rebaja
    FROM a JOIN public.presupuestos_versiones v ON v.id = p_version
  ),
  c AS (
    SELECT b.*, public.catalogo_precio_redondear((b.base - b.rebaja) * b.alicuota / 100, b.moneda) AS impuesto FROM b
  )
  SELECT c.moneda, sum(c.base), sum(c.rebaja),
         jsonb_agg(jsonb_build_object('alicuota', c.alicuota, 'monto', c.impuesto) ORDER BY c.alicuota DESC),
         sum(c.base - c.rebaja + c.impuesto), sum(c.sin_precio)::integer
  FROM c
  GROUP BY c.moneda
  ORDER BY c.moneda;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_totales_de(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_totales_de(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.presupuestos_version_totales(p_version uuid)
RETURNS TABLE(moneda public.moneda, subtotal numeric, descuento numeric, iva jsonb, total numeric, sin_precio integer)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT t.*
  FROM public.presupuestos_totales_de(p_version, (
    SELECT coalesce(jsonb_agg(jsonb_build_object('moneda', i.moneda, 'alicuota', i.alicuota, 'importe', i.importe)), '[]')
    FROM public.presupuestos_version_importes(p_version) i)) t;
$$;

-- ============================================================
-- 2. La copia lleva el `n` de cada combinación y el `ancho` de cada ventana
-- ============================================================
-- `n` es la de presupuestos_portal_combinaciones: un bit por casilla de la lista entera, no solo de las ofrecidas. `ancho`: la
-- casilla más alta de todas las combinaciones con precio, ofrecidas o no (0 si lo publicado no sale del cálculo). Las dos salen
-- de la versión de Catálogo y la fecha de la ventana: una autorización de Técnica posterior suma combinaciones, no corre bits.
-- Lo demás, como en sql/201.
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
  v_ancho integer;
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
    SELECT coalesce(jsonb_agg(jsonb_build_object('n', c.n, 'casillas', c.claves, 'publicada', c.publicada) || (
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
                     FROM (SELECT DISTINCT x FROM c c2, jsonb_array_elements(c2.casillas) x) d), '[]'),
           (SELECT coalesce(max((x->>'n')::integer), 0)
            FROM kk, jsonb_array_elements(kk.casillas) x
            WHERE EXISTS (SELECT 1 FROM kk p WHERE p.publicada))
    INTO v_combos, v_casillas, v_ancho
    FROM c;

    v_renglones := v_renglones || jsonb_build_object(
      'id', v_r.id, 'seccion_id', v_r.seccion_id, 'tipo', v_r.tipo, 'designacion', v_r.designacion, 'ubicacion', v_r.ubicacion,
      'cantidad', v_r.cantidad, 'nombre', v_r.nombre, 'entrada', v_r.entrada - 'piezas',
      'minimo_de', CASE WHEN v_r.tipo = 'minimo' THEN public.presupuestos_clave(NULL, v_r.porcentaje_id) END,
      'casillas', v_casillas, 'ancho', v_ancho, 'combinaciones', v_combos);
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

-- Lo ya copiado no lleva `n` ni `ancho`: todos los links se vuelven a copiar.
UPDATE public.presupuestos_links SET revision = revision + 1 WHERE activo;

-- ============================================================
-- 3. El dígito de control del código
-- ============================================================
-- Crockford base32. Con pesos distintos (1..30) y módulo primo, cambiar una letra o permutar dos vecinas cambia el dígito, salvo
-- 0 ↔ Z (valen 0 y 31). Sin GRANT.
CREATE OR REPLACE FUNCTION public.presupuestos_eleccion_digito(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', (
    SELECT coalesce(sum(((t.i - 1) % 30 + 1) * (strpos('0123456789ABCDEFGHJKMNPQRSTVWXYZ', t.c) - 1)), 0)::integer % 31
    FROM unnest(string_to_array(p_texto, NULL)) WITH ORDINALITY AS t (c, i)) + 1, 1);
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_eleccion_digito(text) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. Leer una elección: qué cambia, sin escribir nada
-- ============================================================
-- Busca el código en el texto (el link o el mensaje entero pegado). Solo quien arma ese presupuesto (42501 si no). PR030 código
-- roto, PR031 la versión ya no es la publicada (o el presupuesto ya no está publicado), PR032 una combinación que no se ofrece.
-- `ventanas`: cada ventana con casillas, con lo publicado (`antes`) y lo elegido (`despues`), como claves. `cliente`: los
-- totales de lo que vio el cliente, con las combinaciones elegidas y los mínimos como se publicaron. `descarta`: la versión
-- abierta de esa variante, que aplicar descarta.
CREATE OR REPLACE FUNCTION public.presupuestos_eleccion_leer(p_texto text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_alfabeto CONSTANT text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_m text[];
  v_letras text;
  v_bits text := '';
  v_pos integer := 1;
  v_p public.presupuestos;
  v_v public.presupuestos_versiones;
  v_actual integer;
  v_j jsonb;
  v_r jsonb;
  v_combo jsonb;
  v_n integer;
  v_secciones jsonb;
  v_ventanas jsonb := '[]';
  v_importes jsonb := '[]';
BEGIN
  v_m := regexp_match(upper(coalesce(p_texto, '')), 'P-(\d{1,9})-V(\d{1,6})-([0-9A-Z]{1,4}(?:-[0-9A-Z]{1,4})*)');
  IF v_m IS NULL THEN
    RAISE EXCEPTION 'No se encontró un código de elección' USING ERRCODE = 'PR030';
  END IF;
  v_letras := translate(v_m[3], 'OIL-', '011');
  IF v_letras !~ '^[0-9A-HJKMNP-TV-Z]+$'
     OR right(v_letras, 1) <> public.presupuestos_eleccion_digito(v_m[1]::integer || 'V' || v_m[2]::integer || left(v_letras, -1)) THEN
    RAISE EXCEPTION 'El código está roto: revisá que se haya copiado entero' USING ERRCODE = 'PR030';
  END IF;

  SELECT * INTO v_p FROM public.presupuestos WHERE numero = v_m[1]::integer AND activo;
  IF NOT FOUND OR NOT public.presupuestos_arma(v_p.obra_id) THEN
    RAISE EXCEPTION 'No se encontró el presupuesto' USING ERRCODE = '42501';
  END IF;
  IF v_p.estado <> 'publicado' THEN
    RAISE EXCEPTION 'El presupuesto está %: la elección ya no se aplica', v_p.estado USING ERRCODE = 'PR031';
  END IF;
  SELECT * INTO v_v FROM public.presupuestos_versiones WHERE presupuesto_id = v_p.id AND numero = v_m[2]::integer;
  IF NOT FOUND OR NOT v_v.activo OR v_v.estado <> 'publicado' THEN
    SELECT v.numero INTO v_actual FROM public.presupuestos_versiones v
    WHERE v.presupuesto_id = v_p.id AND v.variante = v_v.variante AND v.activo AND v.estado = 'publicado';
    RAISE EXCEPTION '%', CASE WHEN v_actual IS NOT NULL THEN format('La v%s fue reemplazada por la v%s', v_m[2]::integer, v_actual)
                              ELSE format('La v%s ya no está publicada', v_m[2]::integer) END
      USING ERRCODE = 'PR031';
  END IF;

  SELECT string_agg(((strpos(c_alfabeto, t.c) - 1)::bit(5))::text, '' ORDER BY t.i) INTO v_bits
  FROM unnest(string_to_array(left(v_letras, -1), NULL)) WITH ORDINALITY AS t (c, i);
  v_bits := coalesce(v_bits, '');

  v_j := public.presupuestos_portal_version(v_v.id, true);
  SELECT jsonb_object_agg(s->>'id', s) INTO v_secciones FROM jsonb_array_elements(v_j->'secciones') s;

  FOR v_r IN SELECT x FROM jsonb_array_elements(v_j->'renglones') x LOOP
    v_combo := v_r->'combinaciones'->0;
    IF (v_r->>'ancho')::integer > 0 THEN
      IF length(v_bits) - v_pos + 1 < (v_r->>'ancho')::integer THEN
        RAISE EXCEPTION 'El código está roto: revisá que se haya copiado entero' USING ERRCODE = 'PR030';
      END IF;
      v_n := lpad(substr(v_bits, v_pos, (v_r->>'ancho')::integer), 31, '0')::bit(31)::integer;
      v_pos := v_pos + (v_r->>'ancho')::integer;
      SELECT c INTO v_combo FROM jsonb_array_elements(v_r->'combinaciones') c WHERE (c->>'n')::integer = v_n;
      IF NOT FOUND THEN
        RAISE EXCEPTION '%: esa combinación no se ofrece',
          public.presupuestos_renglon_etiqueta(v_r->>'designacion', v_r->>'ubicacion', v_r->>'nombre') USING ERRCODE = 'PR032';
      END IF;
      v_ventanas := v_ventanas || jsonb_build_object(
        'renglon_id', v_r->'id',
        'etiqueta', public.presupuestos_renglon_etiqueta(v_r->>'designacion', v_r->>'ubicacion', v_r->>'nombre'),
        'casillas', v_r->'casillas',
        'antes', (v_r->'combinaciones'->0)->'casillas',
        'despues', v_combo->'casillas');
    END IF;

    v_importes := v_importes || jsonb_build_object('moneda', v_secciones->(v_r->>'seccion_id')->'moneda',
      'alicuota', v_secciones->(v_r->>'seccion_id')->'alicuota', 'importe', v_combo->'importe');
    SELECT v_importes || coalesce(jsonb_agg(jsonb_build_object('moneda', v_secciones->(a->>'seccion_id')->'moneda',
             'alicuota', v_secciones->(a->>'seccion_id')->'alicuota', 'importe', a->'importe')), '[]')
    INTO v_importes
    FROM jsonb_array_elements(v_combo->'aparte') a;
  END LOOP;

  -- Lo que sobra son los ceros que completan la última letra.
  IF length(v_bits) - v_pos + 1 >= 5 OR substr(v_bits, v_pos) ~ '1' THEN
    RAISE EXCEPTION 'El código está roto: revisá que se haya copiado entero' USING ERRCODE = 'PR030';
  END IF;

  RETURN jsonb_build_object(
    'presupuesto_id', v_p.id, 'codigo', v_p.codigo, 'version_id', v_v.id, 'numero', v_v.numero, 'variante', v_v.variante,
    'variante_nombre', v_v.variante_nombre,
    'descarta', (SELECT jsonb_build_object('version_id', v.id, 'numero', v.numero, 'estado', v.estado)
                 FROM public.presupuestos_versiones v
                 WHERE v.presupuesto_id = v_p.id AND v.variante = v_v.variante AND v.activo
                   AND v.estado IN ('borrador', 'en_revision')),
    'ventanas', v_ventanas,
    'cliente', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]') FROM public.presupuestos_totales_de(v_v.id, v_importes) t));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_eleccion_leer(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_eleccion_leer(text) TO authenticated;

-- ============================================================
-- 5. Aplicar una elección: la corrección
-- ============================================================
-- Descarta la versión abierta de esa variante (la en revisión se retira antes: sus pedidos quedan retirados), copia la publicada
-- y le pone a cada ventana lo elegido. Calcula con los precios de la publicada (todo mantenido) y deja todo a hoy, como cualquier
-- copia. Devuelve la versión nueva y tres totales: `cliente` (lo que vio), `publicada` (con sus precios y los mínimos exactos) y
-- `hoy`. INVOKER: la RLS, los triggers y las funciones del ciclo deciden, como si Juan lo hiciera a mano.
CREATE OR REPLACE FUNCTION public.presupuestos_eleccion_aplicar(p_texto text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_e jsonb := public.presupuestos_eleccion_leer(p_texto);
  v_id uuid;
  v_publicada jsonb;
BEGIN
  IF v_e->'descarta'->>'estado' = 'en_revision' THEN
    PERFORM public.presupuestos_version_retirar((v_e->'descarta'->>'version_id')::uuid);
  END IF;
  IF v_e->'descarta' <> 'null' THEN
    UPDATE public.presupuestos_versiones SET activo = false WHERE id = (v_e->'descarta'->>'version_id')::uuid;
  END IF;

  v_id := public.presupuestos_version_copiar((v_e->>'version_id')::uuid);

  -- Las piezas de las casillas, tildadas o no; los servicios de las casillas, solo los elegidos; los que no son casilla, igual.
  UPDATE public.presupuestos_renglones r
  SET mantener = true,
      entrada = CASE WHEN w.w IS NULL THEN r.entrada ELSE r.entrada || jsonb_build_object('piezas',
                  coalesce(r.entrada->'piezas', '{}') || coalesce((
                    SELECT jsonb_object_agg(k->>'nombre', w.w->'despues' ? (k->>'clave'))
                    FROM jsonb_array_elements(w.w->'casillas') k WHERE k->>'clave' LIKE 'pieza:%'), '{}')) END,
      opcionales = CASE WHEN w.w IS NULL THEN r.opcionales ELSE
                  ARRAY(SELECT o FROM unnest(r.opcionales) o WHERE NOT w.w->'casillas' @> jsonb_build_array(jsonb_build_object(
                          'clave', public.presupuestos_clave(NULL, o))))
                  || ARRAY(SELECT substr(d, 10)::uuid FROM jsonb_array_elements_text(w.w->'despues') d WHERE d LIKE 'servicio:%') END
  FROM (SELECT r2.id, (SELECT x FROM jsonb_array_elements(v_e->'ventanas') x WHERE (x->>'renglon_id')::uuid = r2.origen_id) AS w
        FROM public.presupuestos_renglones r2
        WHERE r2.version_id = v_id AND r2.activo AND r2.tipo <> 'mano' AND r2.origen_id IS NOT NULL) w
  WHERE r.id = w.id;

  SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]') INTO v_publicada FROM public.presupuestos_version_totales(v_id) t;

  UPDATE public.presupuestos_renglones SET mantener = false WHERE version_id = v_id AND activo AND tipo <> 'mano';

  RETURN jsonb_build_object(
    'version_id', v_id,
    'numero', (SELECT numero FROM public.presupuestos_versiones WHERE id = v_id),
    'descartada', v_e->'descarta'->'numero',
    'cliente', v_e->'cliente',
    'publicada', v_publicada,
    'hoy', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]') FROM public.presupuestos_version_totales(v_id) t));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.presupuestos_eleccion_aplicar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.presupuestos_eleccion_aplicar(text) TO authenticated;
