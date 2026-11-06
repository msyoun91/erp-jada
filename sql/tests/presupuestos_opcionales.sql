-- Verificación de sql/187: lo que suma cada opcional, cómo se ve (debajo o aparte, en otra sección y otra moneda), los totales
-- con el renglón aparte y los mínimos. NO es una migración: todo corre dentro de una transacción que revierte. Termina en un DO
-- que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: el de presupuestos_renglones.sql (Juan responsable de Belgrano y vendedor, Pedro participante, Ana vendedora sin la
-- obra, JN jefe sin armar, G gerencia, T Técnica, Lucia y Carlos de Catálogo). V es la ventana de $200.000 con 1000 × 1000
-- ($140.000 de perfil, $60.000 de Float) y Mosquitero opcional de $5.000; Garantía (5 % de los vidrios, paso 1) y Recargo
-- (10 %, paso 2) son servicios opcionales. C tiene la Cortina, que requiere el Cajón y va antes por orden. Dólar a $1.000,
-- euro a $1.200. Para los mínimos se suma la Comisión (10 %, paso 1) con mínimo de $100.000 por presupuesto. Lo creado lleva
-- Zqx187.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.l(p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT quote_literal(pg_temp.id(p_nombre));
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

CREATE FUNCTION pg_temp.intentar(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.consultar(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_rol text := current_user;
  v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', pg_temp.id(p_como)), true);
  PERFORM set_config('role', 'authenticated', true);
  EXECUTE p_sql INTO v_out;
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_out;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT count(*)::text FROM (%s) x', p_sql), p_como);
$f$;

-- ---------- Catálogo, como en sql/tests/presupuestos_renglones.sql ----------
CREATE FUNCTION pg_temp.crear(p_nombre text, p_sql text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.consultar(p_sql, p_como);
BEGIN
  PERFORM pg_temp.caso('crear ' || p_nombre, 'uuid',
    CASE WHEN v ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE v END);
  IF v ~ '^[0-9a-f-]{36}$' THEN
    INSERT INTO ids VALUES (p_nombre, v::uuid);
  END IF;
END;
$f$;

CREATE FUNCTION pg_temp.mete(p_clave text, p_tabla text, p_version text, p_j jsonb) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_cols text;
BEGIN
  SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p_j) k;
  PERFORM pg_temp.crear(coalesce(p_clave, p_tabla || ' ' || gen_random_uuid()), format(
    'INSERT INTO %1$I (version_id, %2$s) SELECT %3$s::uuid, %2$s FROM jsonb_populate_record(NULL::%1$I, %4$L) RETURNING id',
    p_tabla, v_cols, pg_temp.l(p_version), p_j::text));
END;
$f$;

CREATE FUNCTION pg_temp.ver(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_v, format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx187 ' || p_v, pg_temp.l('Ventanas')));
$f$;

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.un(p_v text, p_pieza text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_insumo, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', 'unico',
                       'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.op(p_v text, p_material text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_insumo, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden, 'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)',
    'Zqx187 ' || p_nombre, pg_temp.l(p_categoria), p_unidad));
$f$;

CREATE FUNCTION pg_temp.costo(p_insumo text, p_costo numeric) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, p_costo, 'ARS', pg_temp.id('Carlos'), now() - interval '10 days'
  FROM catalogo_variantes va WHERE va.insumo_id = pg_temp.id(p_insumo) AND va.color_id IS NULL;
$f$;

-- Un servicio en % con su fecha. La misma clave suma un valor nuevo al mismo servicio.
CREATE FUNCTION pg_temp.serv(p_clave text, p_pct numeric, p_paso int, p_cats uuid[], p_opc boolean, p_min numeric DEFAULT NULL,
  p_desde timestamptz DEFAULT now() - interval '10 days') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := pg_temp.id(p_clave);
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO catalogo_porcentajes DEFAULT VALUES RETURNING id INTO v_id;
    INSERT INTO ids VALUES (p_clave, v_id);
  END IF;
  INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda,
    minimo_por, opcional, de_baja, creado_por, created_at)
  VALUES (v_id, 'Zqx187 ' || p_clave, p_pct, p_paso, p_cats, p_min, CASE WHEN p_min IS NOT NULL THEN 'ARS'::moneda END,
    CASE WHEN p_min IS NOT NULL THEN 'presupuesto'::alcance_minimo END, p_opc, false, pg_temp.id('Carlos'), p_desde);
END;
$f$;

CREATE FUNCTION pg_temp.publicar(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso('enviar ' || p_v, 'ok', pg_temp.intentar(format('SELECT catalogo_version_enviar(%s)', pg_temp.l(p_v)), 'Lucia'));
  SELECT pg_temp.caso('aprobar ' || p_v, 'ok', pg_temp.intentar(format('SELECT catalogo_version_aprobar(%s)', pg_temp.l(p_v)), 'Carlos'));
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

-- ---------- Presupuestos ----------
CREATE FUNCTION pg_temp.e(p_ancho numeric DEFAULT 1000, p_alto numeric DEFAULT 1000, p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('variables', jsonb_build_object('ancho', p_ancho, 'alto', p_alto)) || p_extra;
$f$;

CREATE FUNCTION pg_temp.alta(p_nombre text, p_version text, p_seccion text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO ids VALUES (p_nombre, pg_temp.consultar(format(
    $s$SELECT presupuestos_alta(%L, %L, 'ARS', 21)::text$s$, pg_temp.id('Belgrano'), 'Zqx187 ' || p_nombre), 'Juan')::uuid);
  INSERT INTO ids VALUES (p_version, (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id(p_nombre)));
  INSERT INTO ids VALUES (p_seccion, (SELECT id FROM presupuestos_secciones WHERE version_id = pg_temp.id(p_version)));
END;
$f$;

CREATE FUNCTION pg_temp.seccion(p_nombre text, p_version text, p_moneda text, p_alicuota numeric, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := gen_random_uuid();
  v text;
BEGIN
  v := pg_temp.intentar(format(
    'INSERT INTO presupuestos_secciones (id, version_id, nombre, moneda, alicuota) VALUES (%L, %s, %L, %L, %s)',
    v_id, pg_temp.l(p_version), 'Zqx187 ' || p_nombre, p_moneda, p_alicuota), p_como);
  IF v = 'ok' THEN INSERT INTO ids VALUES (p_nombre, v_id); END IF;
  RETURN v;
END;
$f$;

-- Una fila nueva en una tabla de la versión, como alguien. Guarda el id con su nombre.
CREATE FUNCTION pg_temp.fila(p_tabla text, p_nombre text, p_version text, p_j jsonb, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := gen_random_uuid();
  v_cols text;
  v text;
BEGIN
  SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p_j) k;
  v := pg_temp.intentar(format(
    'INSERT INTO %1$I (id, version_id, %2$s) SELECT %3$L, %4$L, %2$s FROM jsonb_populate_record(NULL::%1$I, %5$L)',
    p_tabla, v_cols, v_id, pg_temp.id(p_version), p_j), p_como);
  IF v = 'ok' THEN INSERT INTO ids VALUES (p_nombre, v_id) ON CONFLICT (nombre) DO UPDATE SET id = EXCLUDED.id; END IF;
  RETURN v;
END;
$f$;

-- Un renglón en una sección, en la versión de esa sección.
CREATE FUNCTION pg_temp.renglon(p_nombre text, p_seccion text, p_j jsonb, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO ids VALUES ('_v ' || p_nombre, (SELECT version_id FROM presupuestos_secciones WHERE id = pg_temp.id(p_seccion)))
  ON CONFLICT (nombre) DO UPDATE SET id = EXCLUDED.id;
  RETURN pg_temp.fila('presupuestos_renglones', p_nombre, '_v ' || p_nombre,
    jsonb_build_object('seccion_id', pg_temp.id(p_seccion)) || p_j, p_como);
END;
$f$;

CREATE FUNCTION pg_temp.opcional(p_nombre text, p_version text, p_j jsonb, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.fila('presupuestos_opcionales', p_nombre, p_version, p_j, p_como);
$f$;

CREATE FUNCTION pg_temp.ventana(p_entrada jsonb DEFAULT pg_temp.e(), p_extra jsonb DEFAULT '{}', p_paquete text DEFAULT 'V') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('tipo', 'catalogo', 'paquete_id', pg_temp.paquete(p_paquete), 'entrada', p_entrada) || p_extra;
$f$;

CREATE FUNCTION pg_temp.mosq(p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.ventana(pg_temp.e(1000, 1000, '{"piezas": {"Mosquitero": true}}'), p_extra);
$f$;

-- Mosquitero, Garantía y Recargo.
CREATE FUNCTION pg_temp.todo(p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.mosq(jsonb_build_object('opcionales', ARRAY[pg_temp.id('Garantia'), pg_temp.id('Recargo')]) || p_extra);
$f$;

CREATE FUNCTION pg_temp.cambia(p_tabla text, p_nombre text, p_set text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE %I SET %s WHERE id = %L', p_tabla, p_set, pg_temp.id(p_nombre)), p_como);
$f$;

CREATE FUNCTION pg_temp.precio(p_renglon text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(trim_scale(precio)::text, 'null') || ' ' || moneda FROM presupuestos_renglones WHERE id = pg_temp.id(p_renglon);
$f$;

-- "Nombre=monto,…" en el orden del cálculo; con moneda, solo las de esa.
CREATE FUNCTION pg_temp.lineas(p_renglon text, p_moneda text DEFAULT NULL) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(string_agg(replace(t.l->>'nombre', 'Zqx187 ', '') || '=' || trim_scale((t.l->>'monto')::numeric), ',' ORDER BY t.i), '')
  FROM presupuestos_renglones x, jsonb_array_elements(x.lineas) WITH ORDINALITY AS t(l, i)
  WHERE x.id = pg_temp.id(p_renglon) AND (p_moneda IS NULL OR t.l->>'moneda' = p_moneda);
$f$;

-- "moneda subtotal/descuento/alícuota=IVA,…/total/sin precio | …", como lo ve alguien.
CREATE FUNCTION pg_temp.tot(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format($q$
    SELECT string_agg(t.moneda || ' ' || trim_scale(t.subtotal) || '/' || trim_scale(t.descuento) || '/' ||
      (SELECT string_agg((i->>'alicuota') || '=' || (i->>'monto'), ',') FROM jsonb_array_elements(t.iva) i) || '/' ||
      trim_scale(t.total) || '/' || t.sin_precio, ' | ')
    FROM presupuestos_version_totales(%L) t$q$, pg_temp.id(p_version)), p_como), 'nada');
$f$;

-- Los renglones aparte: "Nombre@Sección=suma moneda,…".
CREATE FUNCTION pg_temp.aparte(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format($q$
    SELECT string_agg(x, ',' ORDER BY x) FROM (
      SELECT replace(i.nombre, 'Zqx187 ', '') || '@' || replace(s.nombre, 'Zqx187 ', '') || '=' || trim_scale(sum(i.importe))
             || ' ' || i.moneda AS x
      FROM presupuestos_version_importes(%L) i JOIN presupuestos_secciones s ON s.id = i.seccion_id
      WHERE i.clave IS NOT NULL
      GROUP BY i.nombre, s.nombre, i.moneda) q$q$, pg_temp.id(p_version)), 'Juan'), '');
$f$;

-- Los mínimos activos: "Servicio@Sección=precio moneda,…".
CREATE FUNCTION pg_temp.minimos(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(string_agg(replace(x.descripcion, 'Zqx187 ', '') || '@' || replace(s.nombre, 'Zqx187 ', '') || '=' ||
         trim_scale(x.precio) || ' ' || x.moneda, ',' ORDER BY x.descripcion), '')
  FROM presupuestos_renglones x JOIN presupuestos_secciones s ON s.id = x.seccion_id
  WHERE x.version_id = pg_temp.id(p_version) AND x.activo AND x.porcentaje_id IS NOT NULL;
$f$;

CREATE FUNCTION pg_temp.minimo(p_version text, p_servicio text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM presupuestos_renglones
  WHERE version_id = pg_temp.id(p_version) AND activo AND porcentaje_id = pg_temp.id(p_servicio);
$f$;

CREATE FUNCTION pg_temp.cambia_minimo(p_version text, p_servicio text, p_set text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE presupuestos_renglones SET %s WHERE id = %L', p_set, pg_temp.minimo(p_version, p_servicio)), 'Juan');
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE catalogo_porcentajes_valores SET activo = false WHERE activo;
UPDATE monedas_tipos_cambio SET activo = false WHERE activo;
INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde) VALUES
  ('USD_OFICIAL', 1000, now(), 'monedapi', now() - interval '20 days'),
  ('USD_BLUE',    2000, now(), 'monedapi', now() - interval '20 days'),
  ('EUR',         1200, now(), 'monedapi', now() - interval '20 days');

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','JN','Vero','Pedro','Ana','G','T','Lucia','Carlos','Norte','Sur','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo IN ('catalogo', 'presupuestos') OR codigo IN
  ('contactos_ver','obras_ver','obras_equipo','obras_todas','obras_administrar','usuarios_delegar','usuarios_equipo',
   'tareas_ver','tareas_equipo'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test187.local', jsonb_build_object('nombre', 'test187 ' || nombre)
FROM ids WHERE nombre IN ('Juan','JN','Vero','Pedro','Ana','G','T','Lucia','Carlos');

INSERT INTO equipos (id, nombre)
SELECT id, 'test187 ' || nombre || ' ' || id FROM ids WHERE nombre IN ('Norte','Sur');

INSERT INTO equipos_miembros (equipo_id, usuario_id)
SELECT pg_temp.id(e), pg_temp.id(n)
FROM (VALUES ('Norte','Juan'),('Norte','JN'),('Norte','Vero'),('Sur','Pedro'),('Sur','Ana')) AS m (e, n);

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','presupuestos_ver'), ('Pedro','presupuestos_armar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('Vero','contactos_ver'), ('Vero','obras_ver'),
  ('JN','contactos_ver'), ('JN','obras_ver'), ('JN','usuarios_equipo'), ('JN','usuarios_delegar'), ('JN','obras_equipo'),
    ('JN','tareas_ver'), ('JN','tareas_equipo'), ('JN','presupuestos_ver'), ('JN','presupuestos_autorizar'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion'),
  ('T','presupuestos_revision'), ('T','presupuestos_autorizar_tecnica'),
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx187 Torre Belgrano', 'Zqx187 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Pedro'), pg_temp.id('Juan'));

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx187 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx187 Vidrios') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx187 Ventanas') RETURNING id$q$);
SELECT pg_temp.insumo('Perfil', 'Perfiles', 'mm');
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2');
SELECT pg_temp.insumo('Tela', 'Perfiles', 'm2');
SELECT pg_temp.insumo('Manija', 'Perfiles', 'u');
SELECT pg_temp.costo('Perfil', 70000);
SELECT pg_temp.costo('Float', 60000);
SELECT pg_temp.costo('Tela', 5000);
SELECT pg_temp.costo('Manija', 1000);

SELECT pg_temp.serv('Garantia', 5, 1, ARRAY[pg_temp.id('Vidrios')], true);
SELECT pg_temp.serv('Recargo', 10, 2, '{}', true);

SELECT pg_temp.ver('V');
SELECT pg_temp.mete('V.ancho', 'catalogo_variables', 'V', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1200"}');
SELECT pg_temp.mete('V.alto', 'catalogo_variables', 'V', '{"nombre": "alto", "orden": 2, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1000"}');
SELECT pg_temp.pz('V', 'Marco', 1);
SELECT pg_temp.un('V', 'Marco', 1, 'Perfil', '{"medida": "ancho", "cantidad": "2"}');
SELECT pg_temp.pz('V', 'Hoja', 2);
SELECT pg_temp.mete('V.Hoja.Vidrio', 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Hoja'),
  'orden', 1, 'tipo', 'elige_vendedor', 'nombre', 'Vidrio', 'ancho', 'ancho', 'alto', 'alto'));
SELECT pg_temp.op('V', 'V.Hoja.Vidrio', 1, 'Float', '{"predeterminada": true}');
SELECT pg_temp.pz('V', 'Mosquitero', 3, '{"opcional": true}');
SELECT pg_temp.un('V', 'Mosquitero', 1, 'Tela', '{"ancho": "ancho", "alto": "alto"}');
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.ancho'), 'condicion', 'ancho > 4000', 'mensaje', 'Demasiado ancho', 'bloquea', true));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'V', jsonb_build_object('nombre', 'base', 'entrada', pg_temp.e()));
SELECT pg_temp.publicar('V');

-- C: $1.000 fijos; el Cajón suma $1.000 y la Cortina, que lo requiere, $2.000.
SELECT pg_temp.ver('C');
SELECT pg_temp.pz('C', 'Unica', 1);
SELECT pg_temp.un('C', 'Unica', 1, 'Manija', '{"cantidad": "1"}');
SELECT pg_temp.pz('C', 'Cajon', 3, '{"opcional": true}');
SELECT pg_temp.un('C', 'Cajon', 1, 'Manija', '{"cantidad": "1"}');
SELECT pg_temp.pz('C', 'Cortina', 2, jsonb_build_object('opcional', true, 'requiere_pieza_id', pg_temp.id('C.Cajon')));
SELECT pg_temp.un('C', 'Cortina', 1, 'Manija', '{"cantidad": "2"}');
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'C', '{"nombre": "base"}');
SELECT pg_temp.publicar('C');

-- ============================================================
-- 01. Lo que suma cada opcional, en el orden del cálculo
-- ============================================================
SELECT pg_temp.alta('P1', 'V1', 'S1');
SELECT pg_temp.caso('montaje: sección en dólares', 'ok', pg_temp.seccion('Dolares', 'V1', 'USD_OFICIAL', 21));

SELECT pg_temp.caso('01 alta con los tres', 'ok', pg_temp.renglon('L1', 'S1', pg_temp.todo()));
SELECT pg_temp.caso('01 precio', '228800 ARS', pg_temp.precio('L1'));
SELECT pg_temp.caso('01 el recargo sobre el mosquitero va en el recargo', 'Mosquitero=5000,Garantia=3000,Recargo=20800',
  pg_temp.lineas('L1'));
SELECT pg_temp.caso('01 las líneas y el precio sin opcionales cierran', '228800', (
  SELECT trim_scale(200000 + sum((l->>'monto')::numeric))::text
  FROM presupuestos_renglones x, jsonb_array_elements(x.lineas) l WHERE x.id = pg_temp.id('L1')));
SELECT pg_temp.caso('01 la pieza por nombre, el servicio por id', 'pieza:mosquitero/true', (
  SELECT (x.lineas->0->>'clave') || '/' || (x.lineas->1->>'clave' = 'servicio:' || pg_temp.id('Garantia'))
  FROM presupuestos_renglones x WHERE x.id = pg_temp.id('L1')));
SELECT pg_temp.caso('01 en dólares', 'ok', pg_temp.renglon('L2', 'Dolares', pg_temp.todo()));
SELECT pg_temp.caso('01 en dólares: líneas', 'Mosquitero=5,Garantia=3,Recargo=20.8', pg_temp.lineas('L2', 'USD_OFICIAL'));
SELECT pg_temp.caso('01 sin opcionales, sin líneas', 'ok/', pg_temp.renglon('L3', 'S1', pg_temp.ventana()) || '/' || pg_temp.lineas('L3'));
SELECT pg_temp.caso('01 la Cortina trae el Cajón', 'ok', pg_temp.renglon('L4', 'S1', pg_temp.ventana('{"piezas": {"Cortina": true}}', '{}', 'C')));
SELECT pg_temp.caso('01 la requerida va antes, aunque el orden diga otra cosa', 'Cajon=1000,Cortina=2000/4000 ARS',
  pg_temp.lineas('L4') || '/' || pg_temp.precio('L4'));
SELECT pg_temp.caso('01 bloqueado: sin precio ni líneas', 'ok/null ARS/', pg_temp.renglon('L5', 'S1', pg_temp.mosq(
  jsonb_build_object('entrada', pg_temp.e(4500, 1000, '{"piezas": {"Mosquitero": true}}')))) || '/' || pg_temp.precio('L5') || '/' || pg_temp.lineas('L5'));
SELECT pg_temp.caso('01 sacar un opcional recalcula las líneas', 'ok/Mosquitero=5000,Recargo=20500', pg_temp.cambia('presupuestos_renglones', 'L1',
  format('opcionales = ARRAY[%L]::uuid[]', pg_temp.id('Recargo'))) || '/' || pg_temp.lineas('L1'));
SELECT pg_temp.caso('01 las líneas no se escriben', '42501', pg_temp.renglon('X', 'S1', pg_temp.ventana(pg_temp.e(), '{"lineas": []}')));

SELECT pg_temp.caso('01 en dos monedas, una tanda por moneda', 'Mosquitero ARS=5000,Mosquitero USD_OFICIAL=5', pg_temp.consultar(format(
  $q$SELECT string_agg((l->>'nombre') || ' ' || (l->>'moneda') || '=' || trim_scale((l->>'monto')::numeric), ',')
     FROM jsonb_array_elements(catalogo_precio_lineas(%L, %L::jsonb, '{}', ARRAY['ARS', 'USD_OFICIAL']::moneda[])->'lineas') l$q$,
  pg_temp.paquete('V'), pg_temp.e(1000, 1000, '{"piezas": {"Mosquitero": true}}')), 'Juan'));
SELECT pg_temp.caso('01 lineas: Carlos no', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_precio_lineas(%L, '{}'::jsonb, '{}', ARRAY['ARS']::moneda[])$q$, pg_temp.paquete('V')), 'Carlos'));

-- ============================================================
-- 02. Debajo y aparte
-- ============================================================
-- V2: T1 con los tres (2 u.), T2 con mosquitero, T3 sin nada. Aparte, el mosquitero sale de la ventana y va a su sección.
SELECT pg_temp.alta('P2', 'V2', 'A');
SELECT pg_temp.caso('02 secciones', 'ok/ok', pg_temp.seccion('Col', 'V2', 'ARS', 10.5) || '/' || pg_temp.seccion('ColUSD', 'V2', 'USD_OFICIAL', 10.5));
SELECT pg_temp.caso('02 renglones', 'ok/ok/ok', pg_temp.renglon('T1', 'A', pg_temp.todo('{"cantidad": 2}')) || '/' ||
  pg_temp.renglon('T2', 'A', pg_temp.mosq()) || '/' || pg_temp.renglon('T3', 'A', pg_temp.ventana()));
SELECT pg_temp.caso('02 todo en el precio', 'ARS 862600/0/21.0=181146/1043746/0', pg_temp.tot('V2'));

SELECT pg_temp.caso('02 debajo', 'ok', pg_temp.opcional('OM', 'V2', '{"pieza": "Mosquitero", "forma": "debajo"}'));
SELECT pg_temp.caso('02 debajo no cambia los totales', 'ARS 862600/0/21.0=181146/1043746/0', pg_temp.tot('V2'));
SELECT pg_temp.caso('02 debajo con sección no', '23514', pg_temp.opcional('X', 'V2', jsonb_build_object(
  'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'debajo', 'seccion_id', pg_temp.id('Col'))));
SELECT pg_temp.caso('02 aparte sin sección no', '23514', pg_temp.opcional('X', 'V2', jsonb_build_object(
  'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'aparte')));
SELECT pg_temp.caso('02 pieza y servicio juntos no', '23514', pg_temp.opcional('X', 'V2', jsonb_build_object(
  'pieza', 'Otra', 'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'debajo')));
SELECT pg_temp.caso('02 el mismo opcional dos veces no', '23505', pg_temp.opcional('X', 'V2', '{"pieza": " mosquitero", "forma": "debajo"}'));
SELECT pg_temp.caso('02 sección de otra versión no', '23503', pg_temp.opcional('X', 'V2', jsonb_build_object(
  'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'aparte', 'seccion_id', pg_temp.id('S1'))));
SELECT pg_temp.caso('02 Ana no', '42501', pg_temp.opcional('X', 'V2', jsonb_build_object(
  'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'debajo'), 'Ana'));
SELECT pg_temp.caso('02 JN no', '42501', pg_temp.opcional('X', 'V2', jsonb_build_object(
  'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'debajo'), 'JN'));
SELECT pg_temp.caso('02 G sí', 'ok', pg_temp.opcional('OG', 'V2', jsonb_build_object(
  'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'debajo'), 'G'));

SELECT pg_temp.caso('02 el mosquitero aparte, en Colocación al 10,5', 'ok', pg_temp.cambia('presupuestos_opcionales', 'OM',
  format($q$forma = 'aparte', seccion_id = %L$q$, pg_temp.id('Col'))));
SELECT pg_temp.caso('02 aparte: el subtotal no cambia, el IVA sí', 'ARS 862600/0/21.0=177996,10.5=1575/1042171/0', pg_temp.tot('V2'));
SELECT pg_temp.caso('02 el renglón aparte suma las ventanas', 'Mosquitero@Col=15000 ARS', pg_temp.aparte('V2'));
SELECT pg_temp.caso('02 la ventana sin el mosquitero', '447600', pg_temp.consultar(format(
  'SELECT trim_scale(importe)::text FROM presupuestos_version_importes(%L) WHERE renglon_id = %L AND clave IS NULL',
  pg_temp.id('V2'), pg_temp.id('T1')), 'Juan'));
SELECT pg_temp.caso('02 la sección del aparte no se saca', 'PR011', pg_temp.cambia('presupuestos_secciones', 'Col', 'activo = false'));

SELECT pg_temp.caso('02 aparte en dólares', 'ok', pg_temp.cambia('presupuestos_opcionales', 'OM',
  format('seccion_id = %L', pg_temp.id('ColUSD'))));
SELECT pg_temp.caso('02 en dólares: las ventanas suman su tanda', 'Mosquitero=5,Garantia=3,Recargo=20.8/Mosquitero=5/',
  pg_temp.lineas('T1', 'USD_OFICIAL') || '/' || pg_temp.lineas('T2', 'USD_OFICIAL') || '/' || pg_temp.lineas('T3', 'USD_OFICIAL'));
SELECT pg_temp.caso('02 en dólares: el precio de la ventana no cambia', '228800 ARS', pg_temp.precio('T1'));
SELECT pg_temp.caso('02 en dólares: totales por moneda', 'ARS 847600/0/21.0=177996/1025596/0 | USD_OFICIAL 15/0/10.5=1.58/16.58/0',
  pg_temp.tot('V2'));
SELECT pg_temp.caso('02 la sección del aparte pasa a euros', 'ok', pg_temp.cambia('presupuestos_secciones', 'ColUSD', $q$moneda = 'EUR'$q$));
SELECT pg_temp.caso('02 en euros', 'Mosquitero@ColUSD=12.48 EUR', pg_temp.aparte('V2'));

SELECT pg_temp.caso('02 de vuelta al precio', 'ok', pg_temp.cambia('presupuestos_opcionales', 'OM', 'activo = false'));
SELECT pg_temp.caso('02 de vuelta al precio: totales', 'ARS 862600/0/21.0=181146/1043746/0', pg_temp.tot('V2'));
SELECT pg_temp.caso('02 lo desactivado no vuelve', 'PR002', pg_temp.cambia('presupuestos_opcionales', 'OM', 'activo = true'));
SELECT pg_temp.caso('02 ve: JN sí, Ana no', '1/0',
  pg_temp.ve(format('SELECT 1 FROM presupuestos_opcionales WHERE version_id = %L AND activo', pg_temp.id('V2')), 'JN') || '/' ||
  pg_temp.ve(format('SELECT 1 FROM presupuestos_opcionales WHERE version_id = %L AND activo', pg_temp.id('V2')), 'Ana'));
UPDATE presupuestos_versiones SET estado = 'en_revision' WHERE id = pg_temp.id('V2');
SELECT pg_temp.caso('02 en revisión no', 'PR005', pg_temp.opcional('X', 'V2', '{"pieza": "Otra", "forma": "debajo"}'));
UPDATE presupuestos_versiones SET estado = 'borrador' WHERE id = pg_temp.id('V2');

-- ============================================================
-- 03. Mínimos
-- ============================================================
-- La Comisión: 10 % de todo, con mínimo de $100.000 por presupuesto. M1 (2 u.) en General y M2 en Local, que va primero:
-- aportan $40.000 y $20.000, así que falta $40.000.
SELECT pg_temp.serv('Comision', 10, 1, '{}', false, 100000);
SELECT pg_temp.alta('P3', 'V3', 'General');
SELECT pg_temp.caso('03 secciones', 'ok/ok/ok', pg_temp.seccion('Local', 'V3', 'ARS', 21) || '/' ||
  pg_temp.seccion('Dol3', 'V3', 'USD_OFICIAL', 21) || '/' || pg_temp.seccion('Col3', 'V3', 'ARS', 10.5));
SELECT pg_temp.caso('03 Local primero', 'ok', pg_temp.cambia('presupuestos_secciones', 'Local', 'orden = -1'));
SELECT pg_temp.caso('03 renglones', 'ok/ok', pg_temp.renglon('M1', 'General', pg_temp.ventana(pg_temp.e(), '{"cantidad": 2}')) || '/' ||
  pg_temp.renglon('M2', 'Local', pg_temp.ventana()));
SELECT pg_temp.caso('03 con la comisión', '220000 ARS', pg_temp.precio('M1'));
SELECT pg_temp.caso('03 el mínimo, donde más aporta', 'Comision@General=40000 ARS', pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 suma en los totales', 'ARS 700000/0/21.0=147000/847000/0', pg_temp.tot('V3'));

SELECT pg_temp.caso('03 quien arma no lo crea', 'PR012', pg_temp.renglon('X', 'General', jsonb_build_object(
  'tipo', 'minimo', 'porcentaje_id', pg_temp.id('Recargo'), 'descripcion', 'x')));
SELECT pg_temp.caso('03 ni lo saca', 'PR012', pg_temp.cambia_minimo('V3', 'Comision', 'activo = false'));
SELECT pg_temp.caso('03 ni lo escribe', 'ok/Comision@General=40000 ARS', pg_temp.cambia_minimo('V3', 'Comision',
  $q$precio = 1, cantidad = 5, descripcion = 'Regalo'$q$) || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 cantidad 1', '1', (SELECT cantidad::text FROM presupuestos_renglones WHERE id = pg_temp.minimo('V3', 'Comision')));
SELECT pg_temp.caso('03 lo mueve', 'ok/Comision@Local=40000 ARS', pg_temp.cambia_minimo('V3', 'Comision',
  format('seccion_id = %L', pg_temp.id('Local'))) || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 cambia una ventana: se queda donde lo puso', 'ok/Comision@Local=20000 ARS',
  pg_temp.cambia('presupuestos_renglones', 'M2', 'cantidad = 2') || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 en dólares se calcula en dólares', 'ok/Comision@Dol3=20 USD_OFICIAL', pg_temp.cambia_minimo('V3', 'Comision',
  format('seccion_id = %L', pg_temp.id('Dol3'))) || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 y se recalcula en dólares', 'ok/Comision@Dol3=40 USD_OFICIAL',
  pg_temp.cambia('presupuestos_renglones', 'M2', 'cantidad = 1') || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 superado, se va', 'ok/', pg_temp.cambia('presupuestos_renglones', 'M1', 'cantidad = 5') || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 vuelve por la regla, no donde estaba', 'ok/Comision@General=40000 ARS',
  pg_temp.cambia('presupuestos_renglones', 'M1', 'cantidad = 2') || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 sacar una ventana lo mueve', 'ok/Comision@General=60000 ARS',
  pg_temp.cambia('presupuestos_renglones', 'M2', 'activo = false') || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 calcular: Ana no', '42501', pg_temp.intentar(format(
  $q$SELECT * FROM presupuestos_minimos_calcular(%L, 'ARS')$q$, pg_temp.id('V3')), 'Ana'));

-- La Garantía con mínimo de $10.000, aparte en Colocación: su mínimo va con su renglón aparte.
SELECT pg_temp.serv('Garantia', 5, 1, ARRAY[pg_temp.id('Vidrios')], true, 10000, now() - interval '5 days');
SELECT pg_temp.caso('03 garantía aparte', 'ok', pg_temp.opcional('OG3', 'V3', jsonb_build_object(
  'porcentaje_id', pg_temp.id('Garantia'), 'forma', 'aparte', 'seccion_id', pg_temp.id('Col3'))));
SELECT pg_temp.caso('03 M2 de nuevo y garantía en M1', 'ok/ok', pg_temp.renglon('M2b', 'Local', pg_temp.ventana()) || '/' ||
  pg_temp.cambia('presupuestos_renglones', 'M1', format('opcionales = ARRAY[%L]::uuid[]', pg_temp.id('Garantia'))));
SELECT pg_temp.caso('03 el de la garantía, con su aparte', 'Comision@General=40000 ARS,Garantia@Col3=4000 ARS', pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 moverlo lo devuelve al aparte', 'ok/Comision@General=40000 ARS,Garantia@Col3=4000 ARS',
  pg_temp.cambia_minimo('V3', 'Garantia', format('seccion_id = %L', pg_temp.id('General'))) || '/' || pg_temp.minimos('V3'));
SELECT pg_temp.caso('03 aparte y mínimos en los totales', 'ARS 710000/0/21.0=147000,10.5=1050/858050/0', pg_temp.tot('V3'));
SELECT pg_temp.caso('03 el renglón aparte', 'Garantia@Col3=6000 ARS', pg_temp.aparte('V3'));

-- ============================================================
-- Resultado
-- ============================================================
DO $$
DECLARE
  v_ok int;
  v_total int;
  v_fallan text;
BEGIN
  SELECT count(*) FILTER (WHERE ok), count(*),
         string_agg(caso || ' → esperado ' || coalesce(esperado, 'NULL') || ', obtenido ' || coalesce(obtenido, 'NULL'),
                    E'\n' ORDER BY caso) FILTER (WHERE NOT ok)
  INTO v_ok, v_total, v_fallan
  FROM r;
  RAISE EXCEPTION '% / % ok%', v_ok, v_total, coalesce(E'\n' || v_fallan, '');
END;
$$;

ROLLBACK;
