-- Verificación de sql/188: copiar una versión, mantener o actualizar cada ventana y el mínimo, lo que frena publicar, publicar
-- y quitar una variante. NO es una migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza
-- "N / M ok" y los casos que fallan.
--
-- Mundo: Juan responsable de Belgrano y vendedor, Pedro participante, Ana vendedora sin la obra, Vero sin Presupuestos, G
-- gerencia (administra y configura), Lucia y Carlos de Catálogo. V es la ventana: con 1000 × 1000, $140.000 de perfil y $60.000
-- de Float, más la Comisión (10 %, paso 1, todo el despiece, mínimo de $300.000 por presupuesto): $220.000. Ancho de más de
-- 4000 bloquea; alto de más de 2000 es una alerta. La v1 se calcula hace 7 días; hace 5, el perfil pasa a $80.000 el metro y el
-- mínimo a $400.000. Lo creado lleva Zqx188.

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

-- ---------- Catálogo ----------
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

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.un(p_v text, p_pieza text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_insumo, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', 'unico',
                       'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)',
    'Zqx188 ' || p_nombre, pg_temp.l(p_categoria), p_unidad));
$f$;

CREATE FUNCTION pg_temp.costo(p_insumo text, p_costo numeric, p_desde timestamptz DEFAULT now() - interval '10 days')
RETURNS void LANGUAGE sql AS $f$
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, p_costo, 'ARS', pg_temp.id('Carlos'), p_desde
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
  VALUES (v_id, 'Zqx188 ' || p_clave, p_pct, p_paso, p_cats, p_min, CASE WHEN p_min IS NOT NULL THEN 'ARS'::moneda END,
    CASE WHEN p_min IS NOT NULL THEN 'presupuesto'::alcance_minimo END, p_opc, false, pg_temp.id('Carlos'), p_desde);
END;
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

-- ---------- Presupuestos ----------
CREATE FUNCTION pg_temp.e(p_ancho numeric DEFAULT 1000, p_alto numeric DEFAULT 1000, p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('variables', jsonb_build_object('ancho', p_ancho, 'alto', p_alto)) || p_extra;
$f$;

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

CREATE FUNCTION pg_temp.renglon(p_nombre text, p_seccion text, p_j jsonb, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO ids VALUES ('_v ' || p_nombre, (SELECT version_id FROM presupuestos_secciones WHERE id = pg_temp.id(p_seccion)))
  ON CONFLICT (nombre) DO UPDATE SET id = EXCLUDED.id;
  RETURN pg_temp.fila('presupuestos_renglones', p_nombre, '_v ' || p_nombre,
    jsonb_build_object('seccion_id', pg_temp.id(p_seccion)) || p_j, p_como);
END;
$f$;

CREATE FUNCTION pg_temp.ventana(p_entrada jsonb DEFAULT pg_temp.e(), p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('tipo', 'catalogo', 'paquete_id', pg_temp.paquete('V'), 'entrada', p_entrada) || p_extra;
$f$;

CREATE FUNCTION pg_temp.cambia(p_tabla text, p_nombre text, p_set text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE %I SET %s WHERE id = %L', p_tabla, p_set, pg_temp.id(p_nombre)), p_como);
$f$;

CREATE FUNCTION pg_temp.precio(p_renglon text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(trim_scale(precio)::text, 'null') || ' ' || moneda FROM presupuestos_renglones WHERE id = pg_temp.id(p_renglon);
$f$;

-- Los mínimos activos: "Servicio@Sección=precio moneda,…".
CREATE FUNCTION pg_temp.minimos(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(string_agg(replace(x.descripcion, 'Zqx188 ', '') || '@' || replace(s.nombre, 'Zqx188 ', '') || '=' ||
         trim_scale(x.precio) || ' ' || x.moneda, ',' ORDER BY x.descripcion), '')
  FROM presupuestos_renglones x JOIN presupuestos_secciones s ON s.id = x.seccion_id
  WHERE x.version_id = pg_temp.id(p_version) AND x.activo AND x.porcentaje_id IS NOT NULL;
$f$;

CREATE FUNCTION pg_temp.cambia_minimo(p_version text, p_set text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE presupuestos_renglones SET %s WHERE version_id = %L AND activo AND tipo = %L',
    p_set, pg_temp.id(p_version), 'minimo'), 'Juan');
$f$;

-- Lo que frena publicar, separado por "|", como lo ve alguien.
CREATE FUNCTION pg_temp.revisar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT array_to_string(presupuestos_version_revisar(%s), %L)', pg_temp.l(p_version), '|'), p_como);
$f$;

-- Lo que pide autorización (sql/189): "estado texto|…", por texto; "falta" si no se pidió.
CREATE FUNCTION pg_temp.pide(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$
    SELECT coalesce(string_agg(coalesce(x->>'estado', 'falta') || ' ' || (x->>'texto'), '|' ORDER BY x->>'texto'), '')
    FROM presupuestos_version_pedido(%s) p,
         jsonb_array_elements(jsonb_build_array(p->'comercial') || (p->'tecnica')) x
    WHERE jsonb_typeof(x) = 'object'$q$, pg_temp.l(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.publicar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT presupuestos_version_publicar(%s)', pg_temp.l(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.quitar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT presupuestos_variante_quitar(%s)', pg_temp.l(p_version)), p_como);
$f$;

-- El renglón copiado de otro.
CREATE FUNCTION pg_temp.copia_de(p_nombre text, p_origen text, p_version text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO ids SELECT p_nombre, x.id FROM presupuestos_renglones x
  WHERE x.origen_id = pg_temp.id(p_origen) AND x.version_id = pg_temp.id(p_version);
$f$;

CREATE FUNCTION pg_temp.general(p_nombre text, p_version text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO ids SELECT p_nombre, s.id FROM presupuestos_secciones s WHERE s.version_id = pg_temp.id(p_version) AND s.nombre = 'General';
$f$;

CREATE FUNCTION pg_temp.estado(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT estado::text FROM presupuestos_versiones WHERE id = pg_temp.id(p_version);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE catalogo_porcentajes_valores SET activo = false WHERE activo;
UPDATE monedas_tipos_cambio SET activo = false WHERE activo;
UPDATE presupuestos_configuracion SET activo = false WHERE activo;
INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde) VALUES
  ('USD_OFICIAL', 1000, now(), 'monedapi', now() - interval '20 days');

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid()
FROM unnest(ARRAY['Juan','Vero','Pedro','Ana','G','Lucia','Carlos','Belgrano']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo IN ('catalogo', 'presupuestos') OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test188.local', jsonb_build_object('nombre', 'test188 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Vero','Pedro','Ana','G','Lucia','Carlos');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Pedro','contactos_ver'), ('Pedro','obras_ver'), ('Pedro','presupuestos_ver'), ('Pedro','presupuestos_armar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('Vero','contactos_ver'), ('Vero','obras_ver'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion'),
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por)
VALUES (pg_temp.id('Belgrano'), 'Zqx188 Torre Belgrano', 'Zqx188 Calle 1', 'llamado', 'edificio_residencial',
        pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Pedro'), pg_temp.id('Juan'));

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx188 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx188 Vidrios') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx188 Ventanas') RETURNING id$q$);
SELECT pg_temp.insumo('Perfil', 'Perfiles', 'mm');
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2');
SELECT pg_temp.costo('Perfil', 70000);
SELECT pg_temp.costo('Float', 60000);
SELECT pg_temp.serv('Comision', 10, 1, '{}', false, 300000);

SELECT pg_temp.crear('V', format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx188 V', pg_temp.l('Ventanas')));
SELECT pg_temp.mete('V.ancho', 'catalogo_variables', 'V', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1200"}');
SELECT pg_temp.mete('V.alto', 'catalogo_variables', 'V', '{"nombre": "alto", "orden": 2, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1000"}');
SELECT pg_temp.pz('V', 'Marco', 1);
SELECT pg_temp.un('V', 'Marco', 1, 'Perfil', '{"medida": "ancho", "cantidad": "2"}');
SELECT pg_temp.pz('V', 'Hoja', 2);
SELECT pg_temp.un('V', 'Hoja', 1, 'Float', '{"ancho": "ancho", "alto": "alto"}');
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.ancho'), 'condicion', 'ancho > 4000', 'mensaje', 'Demasiado ancho', 'bloquea', true));
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.alto'), 'condicion', 'alto > 2000', 'mensaje', 'Muy alto', 'bloquea', false));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'V', jsonb_build_object('nombre', 'base', 'entrada', pg_temp.e()));
SELECT pg_temp.caso('enviar V', 'ok', pg_temp.intentar(format('SELECT catalogo_version_enviar(%s)', pg_temp.l('V')), 'Lucia'));
SELECT pg_temp.caso('aprobar V', 'ok', pg_temp.intentar(format('SELECT catalogo_version_aprobar(%s)', pg_temp.l('V')), 'Carlos'));

INSERT INTO ids VALUES ('P1', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx188 P1', 'ARS', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('V1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1')));
INSERT INTO ids VALUES ('General', (SELECT id FROM presupuestos_secciones WHERE version_id = pg_temp.id('V1')));
SELECT pg_temp.caso('montaje: sección Col', 'ok', pg_temp.fila('presupuestos_secciones', 'Col', 'V1',
  '{"nombre": "Zqx188 Col", "moneda": "ARS", "alicuota": 10.5}'));
SELECT pg_temp.caso('montaje: ventana', 'ok/220000 ARS', pg_temp.renglon('L1', 'General',
  pg_temp.ventana(pg_temp.e(), '{"designacion": "V4", "ubicacion": "Lavadero"}')) || '/' || pg_temp.precio('L1'));
SELECT pg_temp.caso('montaje: a mano', 'ok', pg_temp.renglon('M1', 'General',
  '{"tipo": "mano", "descripcion": "Zqx188 Flete", "precio": 50000}'));
SELECT pg_temp.caso('montaje: opcional', 'ok', pg_temp.fila('presupuestos_opcionales', 'O1', 'V1',
  '{"pieza": "Mosquitero", "forma": "debajo"}'));
SELECT pg_temp.caso('montaje: el mínimo, movido a Col', 'ok/Comision@Col=280000 ARS',
  pg_temp.cambia_minimo('V1', format('seccion_id = %L', pg_temp.id('Col'))) || '/' || pg_temp.minimos('V1'));

-- ============================================================
-- 01. Publicar
-- ============================================================
SELECT pg_temp.caso('01 sin configuración', 'Falta configurar el plazo de vencimiento, en Presupuestos → Configuración',
  pg_temp.revisar('V1'));
SELECT pg_temp.caso('01 sin configuración no publica', 'PR014', pg_temp.publicar('V1'));
SELECT pg_temp.caso('01 gerencia configura', 'ok', pg_temp.intentar('SELECT presupuestos_configurar(10, 15)', 'G'));
SELECT pg_temp.caso('01 revisar: nada', '', pg_temp.revisar('V1'));
SELECT pg_temp.caso('01 revisar: Ana no arma la obra', '42501', pg_temp.revisar('V1', 'Ana'));
SELECT pg_temp.caso('01 Ana no publica', '42501', pg_temp.publicar('V1', 'Ana'));
SELECT pg_temp.caso('01 Vero no publica', '42501', pg_temp.publicar('V1', 'Vero'));
SELECT pg_temp.caso('01 Juan publica', 'ok', pg_temp.publicar('V1'));
SELECT pg_temp.caso('01 publicada, vence en el plazo, el presupuesto publicado', 'publicado/15/publicado', (
  SELECT v.estado || '/' || (v.vence - (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date) || '/' || p.estado
  FROM presupuestos_versiones v JOIN presupuestos p ON p.id = v.presupuesto_id WHERE v.id = pg_temp.id('V1')));
SELECT pg_temp.caso('01 publicada no se edita', 'PR005', pg_temp.cambia('presupuestos_renglones', 'L1', 'cantidad = 2'));
SELECT pg_temp.caso('01 publicada no se publica', 'PR005', pg_temp.publicar('V1'));
SELECT pg_temp.caso('01 el vencimiento no se escribe', '42501', pg_temp.cambia('presupuestos_versiones', 'V1', 'vence = now()'));

-- La v1 se calculó hace 7 días; hace 5, el perfil y el mínimo subieron.
ALTER TABLE presupuestos_renglones DISABLE TRIGGER USER;
UPDATE presupuestos_renglones SET condiciones_en = now() - interval '7 days'
WHERE version_id = pg_temp.id('V1') AND condiciones_en IS NOT NULL;
ALTER TABLE presupuestos_renglones ENABLE TRIGGER USER;
SELECT pg_temp.costo('Perfil', 80000, now() - interval '5 days');
SELECT pg_temp.serv('Comision', 10, 1, '{}', false, 400000, now() - interval '5 days');

-- ============================================================
-- 02. Copiar: corregir o actualizar
-- ============================================================
SELECT pg_temp.crear('V2', format('SELECT presupuestos_version_copiar(%s)', pg_temp.l('V1')), 'Juan');
SELECT pg_temp.general('General2', 'V2');
SELECT pg_temp.caso('02 la versión', '2/1/true/borrador/General,Zqx188 Col', (
  SELECT v.numero || '/' || v.variante || '/' || (v.origen_id = pg_temp.id('V1')) || '/' || v.estado || '/'
         || (SELECT string_agg(s.nombre, ',' ORDER BY s.nombre) FROM presupuestos_secciones s
             WHERE s.version_id = v.id AND s.activo)
  FROM presupuestos_versiones v WHERE v.id = pg_temp.id('V2')));
SELECT pg_temp.caso('02 cómo se ve cada opcional', 'Mosquitero/debajo', (
  SELECT string_agg(o.pieza || '/' || o.forma, ',') FROM presupuestos_opcionales o WHERE o.version_id = pg_temp.id('V2')));
SELECT pg_temp.copia_de('L1b', 'L1', 'V2');
SELECT pg_temp.copia_de('M1b', 'M1', 'V2');
SELECT pg_temp.caso('02 a mano, con su precio', '50000 ARS', pg_temp.precio('M1b'));
SELECT pg_temp.caso('02 la ventana arranca a hoy', 'V4 · Lavadero/242000 ARS/false', (
  SELECT x.designacion || ' · ' || x.ubicacion FROM presupuestos_renglones x WHERE x.id = pg_temp.id('L1b'))
  || '/' || pg_temp.precio('L1b') || '/' || (SELECT mantener::text FROM presupuestos_renglones WHERE id = pg_temp.id('L1b')));
SELECT pg_temp.caso('02 el mínimo, a hoy y en la sección de su origen', 'Comision@Col=378000 ARS', pg_temp.minimos('V2'));
SELECT pg_temp.caso('02 el mínimo tiene su origen', 'true', (
  SELECT (o.version_id = pg_temp.id('V1'))::text FROM presupuestos_renglones x JOIN presupuestos_renglones o ON o.id = x.origen_id
  WHERE x.version_id = pg_temp.id('V2') AND x.tipo = 'minimo' AND x.activo));
SELECT pg_temp.caso('02 otra abierta de la misma variante', '23505',
  pg_temp.intentar(format('SELECT presupuestos_version_copiar(%s)', pg_temp.l('V1')), 'Juan'));
SELECT pg_temp.caso('02 Ana no copia', '42501',
  pg_temp.intentar(format('SELECT presupuestos_version_copiar(%s)', pg_temp.l('V1')), 'Ana'));

-- ============================================================
-- 03. Mantener o actualizar
-- ============================================================
SELECT pg_temp.caso('03 mantener la ventana', 'ok/220000 ARS', pg_temp.cambia('presupuestos_renglones', 'L1b', 'mantener = true')
  || '/' || pg_temp.precio('L1b'));
SELECT pg_temp.caso('03 con la versión y la fecha del origen', 'true/true', (
  SELECT (x.condiciones_en = o.condiciones_en) || '/' || (x.catalogo_version_id = o.catalogo_version_id)
  FROM presupuestos_renglones x JOIN presupuestos_renglones o ON o.id = x.origen_id WHERE x.id = pg_temp.id('L1b')));
SELECT pg_temp.caso('03 el mínimo a hoy, con la ventana mantenida', 'Comision@Col=380000 ARS', pg_temp.minimos('V2'));
SELECT pg_temp.caso('03 mantener el mínimo', 'ok/Comision@Col=280000 ARS',
  pg_temp.cambia_minimo('V2', 'mantener = true') || '/' || pg_temp.minimos('V2'));
SELECT pg_temp.caso('03 cambiar la medida respeta la fecha', 'ok/264000 ARS/Comision@Col=276000 ARS',
  pg_temp.cambia('presupuestos_renglones', 'L1b', format('entrada = %L', pg_temp.e(1200, 1000)))
  || '/' || pg_temp.precio('L1b') || '/' || pg_temp.minimos('V2'));
SELECT pg_temp.caso('03 y vuelve', 'ok/220000 ARS', pg_temp.cambia('presupuestos_renglones', 'L1b', format('entrada = %L', pg_temp.e()))
  || '/' || pg_temp.precio('L1b'));
SELECT pg_temp.caso('03 a mano no se mantiene', 'PR013', pg_temp.cambia('presupuestos_renglones', 'M1b', 'mantener = true'));
SELECT pg_temp.caso('03 una ventana nueva no se mantiene', 'PR013', pg_temp.renglon('X', 'General2', pg_temp.ventana(pg_temp.e(),
  '{"mantener": true}')));
SELECT pg_temp.caso('03 el origen es de la versión copiada', '23503', pg_temp.renglon('X', 'General2', pg_temp.ventana(pg_temp.e(),
  jsonb_build_object('origen_id', pg_temp.id('L1b')))));
SELECT pg_temp.caso('03 el origen no se cambia', '42501', pg_temp.cambia('presupuestos_renglones', 'L1b',
  format('origen_id = %L', pg_temp.id('L1'))));
SELECT pg_temp.caso('03 mantener pide el mismo paquete', 'PR013', pg_temp.consultar(format(
  'SELECT presupuestos_precio_lineas(%s, %s, gen_random_uuid(), %L, %L, %L)::text',
  pg_temp.l('V2'), pg_temp.l('L1'), pg_temp.e(), '{}', '{ARS}'), 'Juan'));
SELECT pg_temp.caso('03 actualizar la ventana; el mínimo sigue mantenido', 'ok/242000 ARS/Comision@Col=278000 ARS',
  pg_temp.cambia('presupuestos_renglones', 'L1b', 'mantener = false') || '/' || pg_temp.precio('L1b') || '/' || pg_temp.minimos('V2'));
SELECT pg_temp.caso('03 mantener todas', 'ok/220000 ARS/Comision@Col=280000 ARS', pg_temp.intentar(format(
  $q$UPDATE presupuestos_renglones SET mantener = true WHERE version_id = %s AND origen_id IS NOT NULL AND tipo <> 'mano'$q$,
  pg_temp.l('V2')), 'Juan') || '/' || pg_temp.precio('L1b') || '/' || pg_temp.minimos('V2'));

-- ============================================================
-- 04. Lo que frena publicar
-- ============================================================
SELECT pg_temp.caso('04 lo mantenido no frena revisar: pide autorización',
  '/falta autorización del jefe comercial: 2 renglones mantenidos', pg_temp.revisar('V2') || '/' || pg_temp.pide('V2'));
SELECT pg_temp.caso('04 y frena', 'PR014', pg_temp.publicar('V2'));
SELECT pg_temp.caso('04 todas a hoy', 'ok/242000 ARS/Comision@Col=378000 ARS/', pg_temp.intentar(format(
  'UPDATE presupuestos_renglones SET mantener = false WHERE version_id = %s AND mantener', pg_temp.l('V2')), 'Juan')
  || '/' || pg_temp.precio('L1b') || '/' || pg_temp.minimos('V2') || '/' || pg_temp.revisar('V2'));
SELECT pg_temp.caso('04 descuento sobre el tope', 'ok/falta autorización del jefe comercial: descuento de 12 % sobre el tope de 10 %',
  pg_temp.cambia('presupuestos_versiones', 'V2', 'descuento = 12') || '/' || pg_temp.pide('V2'));
SELECT pg_temp.caso('04 hasta el tope, no', 'ok/', pg_temp.cambia('presupuestos_versiones', 'V2', 'descuento = 10') || '/' || pg_temp.pide('V2'));

-- Ayer el perfil subió otra vez: lo que estaba a hoy quedó viejo.
SELECT pg_temp.costo('Perfil', 90000, now() - interval '1 day');
SELECT pg_temp.caso('04 cambió desde que se calculó',
  'V4 · Lavadero: cambió desde que se calculó (242000 → 264000 ARS): actualizala o mantenela|'
  || 'Mínimo de Zqx188 Comision: cambió desde que se calculó (378000 → 376000 ARS): actualizalo', pg_temp.revisar('V2'));
SELECT pg_temp.caso('04 y frena publicar', 'PR014', pg_temp.publicar('V2'));
SELECT pg_temp.caso('04 actualizar la que ya estaba a hoy', 'ok/264000 ARS/Comision@Col=376000 ARS/',
  pg_temp.cambia('presupuestos_renglones', 'L1b', 'mantener = false') || '/' || pg_temp.precio('L1b') || '/' || pg_temp.minimos('V2')
  || '/' || pg_temp.revisar('V2'));
SELECT pg_temp.caso('04 una alerta pide Técnica', 'ok/falta autorización de Técnica: V5: Muy alto',
  pg_temp.renglon('L5', 'General2', pg_temp.ventana(pg_temp.e(1000, 2500), '{"designacion": "V5"}')) || '/' || pg_temp.pide('V2'));
SELECT pg_temp.caso('04 sacarla', 'ok/', pg_temp.cambia('presupuestos_renglones', 'L5', 'activo = false') || '/' || pg_temp.revisar('V2'));
SELECT pg_temp.caso('04 un bloqueo, sin precio', 'ok/V6: Demasiado ancho',
  pg_temp.renglon('L6', 'General2', pg_temp.ventana(pg_temp.e(4500, 1000), '{"designacion": "V6"}')) || '/' || pg_temp.revisar('V2'));
SELECT pg_temp.caso('04 sacarlo', 'ok/', pg_temp.cambia('presupuestos_renglones', 'L6', 'activo = false') || '/' || pg_temp.revisar('V2'));

-- ============================================================
-- 05. Publicar la corrección
-- ============================================================
SELECT pg_temp.caso('05 Pedro, que trabaja la obra, publica', 'ok', pg_temp.publicar('V2', 'Pedro'));
SELECT pg_temp.caso('05 la anterior pasa a obsoleto', 'obsoleto/publicado', pg_temp.estado('V1') || '/' || pg_temp.estado('V2'));

-- ============================================================
-- 06. Sumar una variante y quitarla
-- ============================================================
SELECT pg_temp.crear('V3', format('SELECT presupuestos_version_copiar(%s, true)', pg_temp.l('V2')), 'Juan');
SELECT pg_temp.caso('06 la variante siguiente, sin nombre', '3/2/null', (
  SELECT v.numero || '/' || v.variante || '/' || coalesce(v.variante_nombre, 'null')
  FROM presupuestos_versiones v WHERE v.id = pg_temp.id('V3')));
SELECT pg_temp.caso('06 pide nombre', 'La variante necesita nombre: el presupuesto tiene más de una', pg_temp.revisar('V3'));
SELECT pg_temp.caso('06 con nombre, publica', 'ok/ok', pg_temp.cambia('presupuestos_versiones', 'V3', $s$variante_nombre = 'PVC'$s$)
  || '/' || pg_temp.publicar('V3'));
SELECT pg_temp.caso('06 conviven', 'publicado/publicado', pg_temp.estado('V2') || '/' || pg_temp.estado('V3'));
SELECT pg_temp.caso('06 Ana no quita', '42501', pg_temp.quitar('V3', 'Ana'));
SELECT pg_temp.caso('06 quitar PVC', 'ok/obsoleto/publicado', pg_temp.quitar('V3') || '/' || pg_temp.estado('V3') || '/' || (
  SELECT estado::text FROM presupuestos WHERE id = pg_temp.id('P1')));
SELECT pg_temp.caso('06 la última no se quita', 'PR016', pg_temp.quitar('V2'));
SELECT pg_temp.caso('06 una obsoleta no se quita', 'PR015', pg_temp.quitar('V1'));

-- ============================================================
-- 07. Copiar con el paquete fuera de la venta
-- ============================================================
UPDATE catalogo_paquetes SET activo = false WHERE id = pg_temp.paquete('V');
SELECT pg_temp.crear('V4', format('SELECT presupuestos_version_copiar(%s)', pg_temp.l('V2')), 'Juan');
SELECT pg_temp.copia_de('L1c', 'L1b', 'V4');
SELECT pg_temp.general('General4', 'V4');
SELECT pg_temp.caso('07 entra sin precio, con su versión', 'null ARS/true/Este paquete no está a la venta', pg_temp.precio('L1c') || '/' || (
  SELECT (x.catalogo_version_id = o.catalogo_version_id) || '/' || x.mensaje
  FROM presupuestos_renglones x JOIN presupuestos_renglones o ON o.id = x.origen_id WHERE x.id = pg_temp.id('L1c')));
SELECT pg_temp.caso('07 mantenida tiene precio', 'ok/264000 ARS', pg_temp.cambia('presupuestos_renglones', 'L1c', 'mantener = true')
  || '/' || pg_temp.precio('L1c'));
SELECT pg_temp.caso('07 una nueva no entra', 'PR010', pg_temp.renglon('X', 'General4', pg_temp.ventana()));

-- ============================================================
-- 08. Lo que no se llama desde afuera
-- ============================================================
SELECT pg_temp.caso('08 sin EXECUTE: ' || f, 'false', has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_precio_en(uuid,uuid,timestamptz,jsonb,uuid[],moneda)',
  'catalogo_precio_lineas_en(uuid,uuid,timestamptz,jsonb,uuid[],moneda[])', 'catalogo_precio_minimos_items(jsonb,moneda,jsonb)',
  'presupuestos_renglones_a_hoy()']) AS f;
SELECT pg_temp.caso('08 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_version_copiar(uuid,boolean)', 'presupuestos_version_revisar(uuid)',
  'presupuestos_version_publicar(uuid)', 'presupuestos_variante_quitar(uuid)',
  'presupuestos_precio_lineas(uuid,uuid,uuid,jsonb,uuid[],moneda[])', 'presupuestos_minimos_calcular(uuid,moneda,uuid[])']) AS f;

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
