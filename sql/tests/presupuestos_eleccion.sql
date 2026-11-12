-- Verificación de sql/204: el código de la elección, leerla y aplicarla. NO es una migración: todo corre dentro de una
-- transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo, como sql/tests/presupuestos_portal_copia.sql: Juan responsable de Belgrano y vendedor, Ana vendedora sin la obra, Jefe
-- con la obra a cargo, T Técnica, Lucia y Carlos de Catálogo. V es la ventana de $200.000 con 1000 × 1000 y Mosquitero opcional
-- de $5.000; desde 3000 de ancho da la alerta "Ancho grande". Servicios opcionales: Colocacion (10 %, paso 1, mínimo de $100.000
-- por presupuesto) y Recargo (10 %, paso 2). Casillas de V: Mosquitero (bit 1), Colocacion (2), Recargo (3): ancho 3. Lo creado
-- lleva Zqx204.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE TEMP TABLE res (nombre text PRIMARY KEY, j jsonb) ON COMMIT DROP;
GRANT ALL ON r, ids, res TO authenticated;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.l(p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT quote_literal(pg_temp.id(p_nombre));
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

-- Como alguien: lo que devuelve (o "ok" si no devuelve nada), o el SQLSTATE.
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
  RETURN coalesce(nullif(v_out, ''), 'ok');
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

-- Lo mismo, con el mensaje del error: "PR031 La v1 fue reemplazada por la v2".
CREATE FUNCTION pg_temp.mensaje(p_sql text, p_como text) RETURNS text LANGUAGE plpgsql AS $f$
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
  RETURN SQLSTATE || ' ' || SQLERRM;
END;
$f$;

-- ---------- Catálogo ----------
CREATE FUNCTION pg_temp.crear(p_nombre text, p_sql text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.consultar(p_sql, p_como);
BEGIN
  PERFORM pg_temp.caso('crear ' || p_nombre, 'uuid', CASE WHEN v ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE v END);
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

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text, p_costo numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)',
    'Zqx204 ' || p_nombre, pg_temp.l(p_categoria), p_unidad));
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, p_costo, 'ARS', pg_temp.id('Carlos'), now() - interval '10 days'
  FROM catalogo_variantes va WHERE va.insumo_id = pg_temp.id(p_nombre) AND va.color_id IS NULL;
END;
$f$;

CREATE FUNCTION pg_temp.serv(p_clave text, p_pct numeric, p_paso int, p_cats uuid[], p_min numeric DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO catalogo_porcentajes DEFAULT VALUES RETURNING id INTO v_id;
  INSERT INTO ids VALUES (p_clave, v_id);
  INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda,
    minimo_por, opcional, de_baja, creado_por, created_at)
  VALUES (v_id, 'Zqx204 ' || p_clave, p_pct, p_paso, p_cats, p_min, CASE WHEN p_min IS NOT NULL THEN 'ARS'::moneda END,
    CASE WHEN p_min IS NOT NULL THEN 'presupuesto'::alcance_minimo END, true, false, pg_temp.id('Carlos'), now() - interval '10 days');
END;
$f$;

-- ---------- Presupuestos ----------
CREATE FUNCTION pg_temp.alta(p_nombre text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO ids VALUES (p_nombre, pg_temp.consultar(format(
    $s$SELECT presupuestos_alta(%L, %L, 'ARS', 21)::text$s$, pg_temp.id('Belgrano'), 'Zqx204 ' || p_nombre), 'Juan')::uuid);
  INSERT INTO ids VALUES (p_nombre || 'v1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id(p_nombre)));
  INSERT INTO ids VALUES (p_nombre || 's', (SELECT id FROM presupuestos_secciones WHERE version_id = pg_temp.id(p_nombre || 'v1')));
END;
$f$;

CREATE FUNCTION pg_temp.fila(p_tabla text, p_nombre text, p_version text, p_j jsonb) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := gen_random_uuid();
  v_cols text;
  v text;
BEGIN
  SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p_j) k;
  v := pg_temp.consultar(format(
    $s$INSERT INTO %1$I (id, version_id, %2$s) SELECT %3$L, %4$L, %2$s FROM jsonb_populate_record(NULL::%1$I, %5$L) RETURNING 'ok'$s$,
    p_tabla, v_cols, v_id, pg_temp.id(p_version), p_j), 'Juan');
  IF v = 'ok' THEN INSERT INTO ids VALUES (p_nombre, v_id); END IF;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.ventana(p_seccion text, p_ancho numeric, p_piezas jsonb, p_opcionales text[], p_extra jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('seccion_id', pg_temp.id(p_seccion), 'tipo', 'catalogo',
    'paquete_id', (SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id('V')),
    'entrada', jsonb_build_object('variables', jsonb_build_object('ancho', p_ancho, 'alto', 1000)) || p_piezas,
    'opcionales', ARRAY(SELECT pg_temp.id(o) FROM unnest(p_opcionales) o)) || p_extra;
$f$;

CREATE FUNCTION pg_temp.llamar(p_funcion text, p_nombre text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT %I(%L)::text', p_funcion, pg_temp.id(p_nombre)), p_como);
$f$;

CREATE FUNCTION pg_temp.version(p_presupuesto text, p_numero int) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id(p_presupuesto) AND numero = p_numero;
$f$;

-- El código que arma el portal (lo que hará erp-cliente): un `n` por ventana con casillas, en el orden de la copia.
CREATE FUNCTION pg_temp.codigo(p_presupuesto text, p_version int, p_ns int[]) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  c_alfabeto CONSTANT text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_p presupuestos;
  v_anchos int[];
  v_bits text := '';
  v_letras text := '';
BEGIN
  SELECT * INTO v_p FROM presupuestos WHERE id = pg_temp.id(p_presupuesto);
  SELECT array_agg((x->>'ancho')::int ORDER BY i) INTO v_anchos
  FROM jsonb_array_elements(presupuestos_portal_version(pg_temp.version(p_presupuesto, p_version), true)->'renglones')
         WITH ORDINALITY t(x, i)
  WHERE (x->>'ancho')::int > 0;
  FOR i IN 1 .. coalesce(array_length(p_ns, 1), 0) LOOP
    v_bits := v_bits || right(p_ns[i]::bit(31)::text, coalesce(v_anchos[i], 5));
  END LOOP;
  v_bits := rpad(v_bits, ((length(v_bits) + 4) / 5) * 5, '0');
  FOR i IN 0 .. length(v_bits) / 5 - 1 LOOP
    v_letras := v_letras || substr(c_alfabeto, lpad(substr(v_bits, i * 5 + 1, 5), 31, '0')::bit(31)::int + 1, 1);
  END LOOP;
  RETURN v_p.codigo || '-V' || p_version || '-' ||
         coalesce(nullif(rtrim(regexp_replace(v_letras, '(.{4})', '\1-', 'g'), '-'), '') || '-', '') ||
         presupuestos_eleccion_digito(v_p.numero || 'V' || p_version || v_letras);
END;
$f$;

-- Leer o aplicar como Juan, y guardar lo que devolvió con un nombre.
CREATE FUNCTION pg_temp.leer(p_nombre text, p_funcion text, p_texto text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.consultar(format('SELECT %I(%L)::text', p_funcion, p_texto), p_como);
BEGIN
  IF v LIKE '{%' THEN
    INSERT INTO res VALUES (p_nombre, v::jsonb);
    RETURN 'ok';
  END IF;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.j(p_nombre text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT j FROM res WHERE nombre = p_nombre;
$f$;

-- Una ventana de lo leído: "antes → después", con los nombres cortos.
CREATE FUNCTION pg_temp.cambio(p_res text, p_renglon text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce((SELECT string_agg(coalesce((SELECT i.nombre FROM ids i WHERE 'servicio:' || i.id = k), replace(k, 'pieza:', '')), ',')
                   FROM jsonb_array_elements_text(w->'antes') k), '') || ' → ' ||
         coalesce((SELECT string_agg(coalesce((SELECT i.nombre FROM ids i WHERE 'servicio:' || i.id = k), replace(k, 'pieza:', '')), ',')
                   FROM jsonb_array_elements_text(w->'despues') k), '')
  FROM jsonb_array_elements(pg_temp.j(p_res)->'ventanas') w WHERE (w->>'renglon_id')::uuid = pg_temp.id(p_renglon);
$f$;

CREATE FUNCTION pg_temp.total(p_j jsonb) RETURNS numeric LANGUAGE sql AS $f$
  SELECT (t->>'total')::numeric FROM jsonb_array_elements(p_j) t WHERE t->>'moneda' = 'ARS';
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE presupuestos_configuracion SET activo = false WHERE activo;
UPDATE catalogo_porcentajes_valores SET activo = false WHERE activo;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Juan','Ana','Jefe','T','Lucia','Carlos','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo IN ('catalogo', 'presupuestos') OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test204.local', jsonb_build_object('nombre', 'test204 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Ana','Jefe','T','Lucia','Carlos');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('Jefe','contactos_ver'), ('Jefe','obras_ver'), ('Jefe','obras_todas'), ('Jefe','obras_administrar'),
    ('Jefe','presupuestos_ver'), ('Jefe','presupuestos_administrar'), ('Jefe','presupuestos_configuracion'),
  ('T','presupuestos_revision'), ('T','presupuestos_autorizar_tecnica'),
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx204 Torre Belgrano', 'Zqx204 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx204 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx204 Vidrios') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx204 Ventanas') RETURNING id$q$);
SELECT pg_temp.insumo('Perfil', 'Perfiles', 'mm', 70000);
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2', 60000);
SELECT pg_temp.insumo('Tela', 'Perfiles', 'm2', 5000);

SELECT pg_temp.serv('Colocacion', 10, 1, '{}', 100000);
SELECT pg_temp.serv('Recargo', 10, 2, '{}');

SELECT pg_temp.crear('V', format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx204 V', pg_temp.l('Ventanas')));
SELECT pg_temp.mete('V.ancho', 'catalogo_variables', 'V', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1200"}');
SELECT pg_temp.mete('V.alto', 'catalogo_variables', 'V', '{"nombre": "alto", "orden": 2, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1000"}');
SELECT pg_temp.mete('V.Marco', 'catalogo_piezas', 'V', '{"nombre": "Marco", "orden": 1}');
SELECT pg_temp.mete(NULL, 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Marco'), 'orden', 1,
  'tipo', 'unico', 'insumo_id', pg_temp.id('Perfil'), 'medida', 'ancho', 'cantidad', '2'));
SELECT pg_temp.mete('V.Hoja', 'catalogo_piezas', 'V', '{"nombre": "Hoja", "orden": 2}');
SELECT pg_temp.mete(NULL, 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Hoja'), 'orden', 1,
  'tipo', 'unico', 'insumo_id', pg_temp.id('Float'), 'ancho', 'ancho', 'alto', 'alto'));
SELECT pg_temp.mete('V.Mosquitero', 'catalogo_piezas', 'V', '{"nombre": "Mosquitero", "orden": 3, "opcional": true}');
SELECT pg_temp.mete(NULL, 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Mosquitero'), 'orden', 1,
  'tipo', 'unico', 'insumo_id', pg_temp.id('Tela'), 'ancho', 'ancho', 'alto', 'alto'));
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.ancho'), 'condicion', 'ancho > 3000', 'mensaje', 'Ancho grande', 'bloquea', false));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'V', '{"nombre": "base", "entrada": {"variables": {"ancho": 1000, "alto": 1000}}}');
SELECT pg_temp.caso('enviar V', 'ok', pg_temp.llamar('catalogo_version_enviar', 'V', 'Lucia'));
SELECT pg_temp.caso('aprobar V', 'ok', pg_temp.llamar('catalogo_version_aprobar', 'V', 'Carlos'));
SELECT pg_temp.consultar('SELECT presupuestos_configurar(10, 15, ''[]'')::text', 'Jefe');

-- P1, v1: L1 (V1, cantidad 2) con Mosquitero y Colocacion, L3 (V3) sin nada, el flete a mano. La Colocacion de L1 aporta 41.000:
-- el mínimo pone 59.000.
SELECT pg_temp.alta('P1');
SELECT pg_temp.caso('montaje L1', 'ok', pg_temp.fila('presupuestos_renglones', 'L1', 'P1v1', pg_temp.ventana('P1s', 1000,
  '{"piezas": {"Mosquitero": true}}', ARRAY['Colocacion'], '{"cantidad": 2, "designacion": "V1", "orden": 1}')));
SELECT pg_temp.caso('montaje L3', 'ok', pg_temp.fila('presupuestos_renglones', 'L3', 'P1v1',
  pg_temp.ventana('P1s', 1000, '{}', '{}', '{"designacion": "V3", "ubicacion": "Lavadero", "orden": 2}')));
SELECT pg_temp.caso('montaje flete', 'ok', pg_temp.fila('presupuestos_renglones', 'F', 'P1v1',
  jsonb_build_object('seccion_id', pg_temp.id('P1s'), 'tipo', 'mano', 'descripcion', 'Flete', 'precio', 1000, 'orden', 3)));
SELECT pg_temp.caso('montaje publicar v1', 'ok', pg_temp.llamar('presupuestos_version_publicar', 'P1v1'));

-- ============================================================
-- 01. La copia lleva `n` y `ancho`
-- ============================================================
CREATE FUNCTION pg_temp.renglon(p_renglon text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT x FROM jsonb_array_elements(presupuestos_portal_version(pg_temp.id('P1v1'), true)->'renglones') x
  WHERE x->>'id' = pg_temp.id(p_renglon)::text;
$f$;
SELECT pg_temp.caso('01 L1: tres casillas, la publicada es Mosquitero + Colocacion (1 + 2)', '3/3/true', (
  SELECT concat_ws('/', x->>'ancho', x->'combinaciones'->0->>'n', x->'combinaciones'->0->>'publicada') FROM pg_temp.renglon('L1') x));
SELECT pg_temp.caso('01 L3: lo publicado es sin nada (0)', '3/0', (
  SELECT concat_ws('/', x->>'ancho', x->'combinaciones'->0->>'n') FROM pg_temp.renglon('L3') x));
SELECT pg_temp.caso('01 cada combinación tiene su n, distinto', '8/8', (
  SELECT count(*) || '/' || count(DISTINCT c->>'n') FROM jsonb_array_elements(pg_temp.renglon('L1')->'combinaciones') c));
SELECT pg_temp.caso('01 el flete y el mínimo: ancho 0', '0/0', (
  SELECT string_agg(x->>'ancho', '/') FROM jsonb_array_elements(presupuestos_portal_version(pg_temp.id('P1v1'), true)->'renglones') x
  WHERE x->>'tipo' IN ('mano', 'minimo')));

-- ============================================================
-- 02. Leer: lo que cambia y lo que vio el cliente
-- ============================================================
-- Carlos saca el Mosquitero de V1 (n = 2) y se lo pone a V3 (n = 1). Mismo código en el link y dentro del mensaje.
SELECT pg_temp.caso('02 el código', 'true', (pg_temp.codigo('P1', 1, ARRAY[2, 1]) ~ '^P-\d{4,}-V1-[0-9A-Z]{2}-[0-9A-Z]$')::text);
SELECT pg_temp.caso('02 leer el link', 'ok', pg_temp.leer('leido', 'presupuestos_eleccion_leer',
  'https://erp/presupuestos/eleccion/' || pg_temp.codigo('P1', 1, ARRAY[2, 1])));
SELECT pg_temp.caso('02 la versión, sin nada que descartar', 'true/1/null', (
  SELECT concat_ws('/', (j->>'version_id' = pg_temp.id('P1v1')::text)::text, j->>'numero', coalesce(j->>'descarta', 'null'))
  FROM res WHERE nombre = 'leido'));
SELECT pg_temp.caso('02 V1 pierde el Mosquitero', 'mosquitero,Colocacion → Colocacion', pg_temp.cambio('leido', 'L1'));
SELECT pg_temp.caso('02 V3 lo gana', ' → mosquitero', pg_temp.cambio('leido', 'L3'));
SELECT pg_temp.caso('02 la etiqueta', 'V3 · Lavadero', (
  SELECT w->>'etiqueta' FROM jsonb_array_elements(pg_temp.j('leido')->'ventanas') w WHERE (w->>'renglon_id')::uuid = pg_temp.id('L3')));
-- Lo que vio el cliente: L1 sin Mosquitero 440.000, L3 con Mosquitero 205.000, flete 1.000 y el mínimo como se publicó, 59.000.
SELECT pg_temp.caso('02 lo que vio el cliente, con IVA', '705000/148050/853050', (
  SELECT concat_ws('/', trim_scale((t->>'subtotal')::numeric), trim_scale((t->'iva'->0->>'monto')::numeric), trim_scale((t->>'total')::numeric))
  FROM jsonb_array_elements(pg_temp.j('leido')->'cliente') t));
SELECT pg_temp.caso('02 pegando el mensaje entero, en minúscula', 'ok', pg_temp.leer('pegado', 'presupuestos_eleccion_leer',
  E'Mosquitero: V3\nColocación: V1\nTotal $ 853.050\n' || lower(pg_temp.codigo('P1', 1, ARRAY[2, 1]))));
SELECT pg_temp.caso('02 da lo mismo', 'true', (pg_temp.j('pegado') = pg_temp.j('leido'))::text);
SELECT pg_temp.caso('02 sin cambios también se lee', 'ok', pg_temp.leer('igual', 'presupuestos_eleccion_leer', pg_temp.codigo('P1', 1, ARRAY[3, 0])));
SELECT pg_temp.caso('02 y no cambia nada', ' → ', pg_temp.cambio('igual', 'L3'));

-- ============================================================
-- 03. Lo que no se lee
-- ============================================================
CREATE FUNCTION pg_temp.roto(p_codigo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_eleccion_leer(%L)::text', p_codigo), 'Juan');
$f$;
SELECT pg_temp.caso('03 sin código', 'PR030', pg_temp.roto('Hola Juan, me quedo con todo'));
SELECT pg_temp.caso('03 otro dígito', 'PR030', (
  SELECT pg_temp.roto(left(c, -1) || CASE WHEN right(c, 1) = 'A' THEN 'B' ELSE 'A' END) FROM pg_temp.codigo('P1', 1, ARRAY[2, 1]) c));
SELECT pg_temp.caso('03 una letra cambiada', 'PR030', (
  SELECT pg_temp.roto(overlay(c PLACING CASE WHEN substr(c, length(c) - 3, 1) = 'A' THEN 'B' ELSE 'A' END FROM length(c) - 3 FOR 1))
  FROM pg_temp.codigo('P1', 1, ARRAY[2, 1]) c));
SELECT pg_temp.caso('03 cortado: le falta una ventana', 'PR030', pg_temp.roto(pg_temp.codigo('P1', 1, ARRAY[2])));
SELECT pg_temp.caso('03 le sobra una letra', 'PR030', pg_temp.roto(pg_temp.codigo('P1', 1, ARRAY[2, 1, 7])));
SELECT pg_temp.caso('03 quien no trabaja la obra', '42501', pg_temp.consultar(format('SELECT presupuestos_eleccion_leer(%L)::text',
  pg_temp.codigo('P1', 1, ARRAY[2, 1])), 'Ana'));
SELECT pg_temp.caso('03 Técnica, sin armar', '42501', pg_temp.consultar(format('SELECT presupuestos_eleccion_leer(%L)::text',
  pg_temp.codigo('P1', 1, ARRAY[2, 1])), 'T'));

-- Una combinación que no se ofrece: W1 mide 3500 (alerta) y Técnica la autorizó sin Mosquitero. Con Mosquitero, nadie la vio.
SELECT pg_temp.alta('P2');
SELECT pg_temp.caso('03 W1', 'ok', pg_temp.fila('presupuestos_renglones', 'W1', 'P2v1',
  pg_temp.ventana('P2s', 3500, '{}', ARRAY['Colocacion'], '{"designacion": "V9"}')));
SELECT pg_temp.caso('03 con la alerta, espera a Técnica', 'en_revision', pg_temp.llamar('presupuestos_version_pedir', 'P2v1'));
SELECT pg_temp.caso('03 Técnica autoriza', 'ok', pg_temp.consultar(format('SELECT presupuestos_pedido_resolver(%L, true)',
  (SELECT a.id FROM presupuestos_autorizaciones a WHERE a.version_id = pg_temp.id('P2v1') AND a.tipo = 'tecnica')), 'T'));
SELECT pg_temp.caso('03 publicar P2', 'ok', pg_temp.llamar('presupuestos_version_publicar', 'P2v1'));
SELECT pg_temp.caso('03 sin Colocacion, sí (0)', 'ok', pg_temp.leer('p2', 'presupuestos_eleccion_leer', pg_temp.codigo('P2', 1, ARRAY[0])));
SELECT pg_temp.caso('03 con Mosquitero, no (3)', 'PR032 V9: esa combinación no se ofrece', pg_temp.mensaje(format(
  'SELECT presupuestos_eleccion_leer(%L)', pg_temp.codigo('P2', 1, ARRAY[3])), 'Juan'));

-- ============================================================
-- 04. Aplicar: descarta lo abierto y arma la corrección
-- ============================================================
-- Juan había arrancado la v2 para sumar una ventana. Llega la elección sobre la v1: la v2 se descarta y nace la v3.
SELECT pg_temp.caso('04 Juan arranca la v2', 'true', (pg_temp.llamar('presupuestos_version_copiar', 'P1v1') ~ '^[0-9a-f-]{36}$')::text);
INSERT INTO ids SELECT 'P1v2', pg_temp.version('P1', 2);
INSERT INTO ids SELECT 'P1v2s', id FROM presupuestos_secciones WHERE version_id = pg_temp.id('P1v2');
SELECT pg_temp.caso('04 y le suma una ventana', 'ok', pg_temp.fila('presupuestos_renglones', 'Nueva', 'P1v2',
  pg_temp.ventana('P1v2s', 1500, '{}', '{}', '{"designacion": "V5", "orden": 4}')));
SELECT pg_temp.caso('04 leer', 'ok', pg_temp.leer('antes', 'presupuestos_eleccion_leer', pg_temp.codigo('P1', 1, ARRAY[2, 1])));
SELECT pg_temp.caso('04 leer avisa que descarta la v2', '2/borrador', (
  SELECT (pg_temp.j('antes')->'descarta'->>'numero') || '/' || (pg_temp.j('antes')->'descarta'->>'estado')));
SELECT pg_temp.caso('04 aplicar', 'ok', pg_temp.leer('aplicado', 'presupuestos_eleccion_aplicar', pg_temp.codigo('P1', 1, ARRAY[2, 1])));
SELECT pg_temp.caso('04 la v2 descartada, la v3 en borrador desde la v1', 'false/3/borrador/true', (
  SELECT concat_ws('/', (SELECT activo::text FROM presupuestos_versiones WHERE id = pg_temp.version('P1', 2)),
    pg_temp.j('aplicado')->>'numero', v.estado, (v.origen_id = pg_temp.id('P1v1'))::text)
  FROM presupuestos_versiones v WHERE v.id = (pg_temp.j('aplicado')->>'version_id')::uuid));
SELECT pg_temp.caso('04 devuelve qué descartó', '2', pg_temp.j('aplicado')->>'descartada');
SELECT pg_temp.caso('04 V1 sin Mosquitero, con Colocacion', 'false/true', (
  SELECT (r.entrada->'piezas'->>'Mosquitero') || '/' || (r.opcionales = ARRAY[pg_temp.id('Colocacion')])::text
  FROM presupuestos_renglones r WHERE r.version_id = pg_temp.version('P1', 3) AND r.origen_id = pg_temp.id('L1') AND r.activo));
SELECT pg_temp.caso('04 V3 con Mosquitero, sin servicios', 'true/{}', (
  SELECT (r.entrada->'piezas'->>'Mosquitero') || '/' || r.opcionales::text
  FROM presupuestos_renglones r WHERE r.version_id = pg_temp.version('P1', 3) AND r.origen_id = pg_temp.id('L3') AND r.activo));
SELECT pg_temp.caso('04 todo queda a hoy', '0', (
  SELECT count(*)::text FROM presupuestos_renglones WHERE version_id = pg_temp.version('P1', 3) AND activo AND mantener));
SELECT pg_temp.caso('04 lo que vio el cliente es lo que leyó', 'true', (pg_temp.j('aplicado')->'cliente' = pg_temp.j('antes')->'cliente')::text);
-- Sin Mosquitero en V1, la Colocacion aporta 40.000: el mínimo pasa de 59.000 a 60.000. El cliente vio 853.050; con los precios de
-- la v1 y el mínimo exacto, 704.000 + 1.000 de IVA más: 854.260.
SELECT pg_temp.caso('04 con los precios de la v1 difiere por el mínimo', '1000', (
  SELECT trim_scale((t->>'subtotal')::numeric - 705000)::text FROM jsonb_array_elements(pg_temp.j('aplicado')->'publicada') t));
SELECT pg_temp.caso('04 Catálogo no cambió: a hoy da lo mismo', 'true', (pg_temp.j('aplicado')->'hoy' = pg_temp.j('aplicado')->'publicada')::text);
SELECT pg_temp.caso('04 y es lo que dice la versión', pg_temp.total(pg_temp.j('aplicado')->'hoy')::text, pg_temp.consultar(format(
  $s$SELECT total::text FROM presupuestos_version_totales(%L) WHERE moneda = 'ARS'$s$, pg_temp.version('P1', 3)), 'Juan'));
SELECT pg_temp.caso('04 la v1 sigue publicada', 'publicado', (SELECT estado::text FROM presupuestos_versiones WHERE id = pg_temp.id('P1v1')));

-- ============================================================
-- 05. Una versión en revisión se retira antes de descartarla
-- ============================================================
-- La v3 con V1 mantenida pide al jefe: queda en revisión. Otra elección sobre la v1 la retira (pedido retirado) y la descarta.
SELECT pg_temp.caso('05 mantener V1', 'ok', pg_temp.consultar(format(
  $s$UPDATE presupuestos_renglones SET mantener = true WHERE version_id = %L AND origen_id = %L RETURNING 'ok'$s$,
  pg_temp.version('P1', 3), pg_temp.id('L1')), 'Juan'));
SELECT pg_temp.caso('05 pide al jefe', 'en_revision', pg_temp.consultar(format('SELECT presupuestos_version_pedir(%L)::text',
  pg_temp.version('P1', 3)), 'Juan'));
SELECT pg_temp.caso('05 aplicar otra elección', 'ok', pg_temp.leer('otra', 'presupuestos_eleccion_aplicar', pg_temp.codigo('P1', 1, ARRAY[0, 0])));
SELECT pg_temp.caso('05 la v3 descartada, su pedido retirado; la v4 en borrador', 'false/retirada/4/borrador', (
  SELECT concat_ws('/', v.activo::text, (SELECT string_agg(a.estado::text, ',') FROM presupuestos_autorizaciones a WHERE a.version_id = v.id),
    pg_temp.j('otra')->>'numero', (SELECT estado::text FROM presupuestos_versiones WHERE id = pg_temp.version('P1', 4)))
  FROM presupuestos_versiones v WHERE v.id = pg_temp.version('P1', 3)));

-- ============================================================
-- 06. Una versión reemplazada, o un presupuesto que ya no está publicado
-- ============================================================
SELECT pg_temp.caso('06 publicar la v4', 'ok', pg_temp.consultar(format('SELECT presupuestos_version_publicar(%L)', pg_temp.version('P1', 4)), 'Juan'));
SELECT pg_temp.caso('06 la elección sobre la v1', 'PR031 La v1 fue reemplazada por la v4', pg_temp.mensaje(format(
  'SELECT presupuestos_eleccion_leer(%L)', pg_temp.codigo('P1', 1, ARRAY[2, 1])), 'Juan'));
SELECT pg_temp.caso('06 aplicar tampoco', 'PR031', pg_temp.consultar(format(
  'SELECT presupuestos_eleccion_aplicar(%L)::text', pg_temp.codigo('P1', 1, ARRAY[2, 1])), 'Juan'));
SELECT pg_temp.caso('06 una versión que no existe', 'PR031 La v9 ya no está publicada', pg_temp.mensaje(format(
  'SELECT presupuestos_eleccion_leer(%L)', (SELECT 'P-' || lpad(numero::text, 4, '0') || '-V9-' || presupuestos_eleccion_digito(numero || 'V9')
  FROM presupuestos WHERE id = pg_temp.id('P2'))), 'Juan'));
SELECT pg_temp.caso('06 aprobar P2', 'ok', pg_temp.llamar('presupuestos_aprobar', 'P2v1'));
SELECT pg_temp.caso('06 P2 aprobado', 'PR031 El presupuesto está aprobado: la elección ya no se aplica', pg_temp.mensaje(format(
  'SELECT presupuestos_eleccion_leer(%L)', pg_temp.codigo('P2', 1, ARRAY[0])), 'Juan'));

-- ============================================================
-- 07. Privilegios y los totales de siempre
-- ============================================================
SELECT pg_temp.caso('07 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_eleccion_leer(text)', 'presupuestos_eleccion_aplicar(text)', 'presupuestos_eleccion_digito(text)',
  'presupuestos_totales_de(uuid,jsonb)']) AS f;
SELECT pg_temp.caso('07 el dígito no lo llama un usuario', 'false',
  has_function_privilege('authenticated', 'public.presupuestos_eleccion_digito(text)', 'EXECUTE')::text);
-- La v4, de la elección "nada": V1 400.000, V3 200.000, flete 1.000, sin Colocacion no hay mínimo. 601.000 × 1,21.
SELECT pg_temp.caso('07 los totales de la versión, sobre sus importes', '727210', pg_temp.consultar(format(
  $s$SELECT trim_scale(total)::text FROM presupuestos_version_totales(%L) WHERE moneda = 'ARS'$s$, pg_temp.version('P1', 4)), 'Juan'));
SELECT pg_temp.caso('07 quien no ve la obra no ve totales', 'ok', pg_temp.consultar(format(
  $s$SELECT string_agg(moneda::text, ',') FROM presupuestos_version_totales(%L)$s$, pg_temp.version('P1', 4)), 'Ana'));

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
