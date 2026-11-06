-- Verificación de sql/189: lo que pide autorización, pedir, autorizar, devolver y retirar, y la lectura de Técnica. NO es una
-- migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Laura responsable de Belgrano y jefa (autoriza), Juan vendedor que participa, Marta jefa sin la obra, Ana vendedora
-- sin la obra, Sofía de Técnica (autoriza alertas), Rita de Técnica que solo mira, G gerencia, Lucia y Carlos de Catálogo.
-- V es la ventana: con 1000 × 1000, $140.000 de perfil y el vidrio (Float $60.000 el m², DVH $100.000), más la Comisión (10 %,
-- mínimo de $300.000 por presupuesto). Alto de más de 2000 es una alerta. La v1 se calcula hace 7 días; hace 5, el perfil pasa
-- a $80.000 y el mínimo a $400.000. Lo creado lleva Zqx189.

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

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v, jsonb_build_object('nombre', p_nombre, 'orden', p_orden));
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, 1, NULL)',
    'Zqx189 ' || p_nombre, pg_temp.l(p_categoria), p_unidad));
$f$;

CREATE FUNCTION pg_temp.costo(p_insumo text, p_costo numeric, p_desde timestamptz DEFAULT now() - interval '10 days')
RETURNS void LANGUAGE sql AS $f$
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por, created_at)
  SELECT va.id, p_costo, 'ARS', pg_temp.id('Carlos'), p_desde
  FROM catalogo_variantes va WHERE va.insumo_id = pg_temp.id(p_insumo) AND va.color_id IS NULL;
$f$;

CREATE FUNCTION pg_temp.serv(p_clave text, p_pct numeric, p_min numeric, p_desde timestamptz DEFAULT now() - interval '10 days')
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := pg_temp.id(p_clave);
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO catalogo_porcentajes DEFAULT VALUES RETURNING id INTO v_id;
    INSERT INTO ids VALUES (p_clave, v_id);
  END IF;
  INSERT INTO catalogo_porcentajes_valores (porcentaje_id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda,
    minimo_por, opcional, de_baja, creado_por, created_at)
  VALUES (v_id, 'Zqx189 ' || p_clave, p_pct, 1, '{}', p_min, 'ARS', 'presupuesto', false, false, pg_temp.id('Carlos'), p_desde);
END;
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

-- ---------- Presupuestos ----------
-- La entrada: medidas y, si se elige, el vidrio.
CREATE FUNCTION pg_temp.e(p_ancho numeric DEFAULT 1000, p_alto numeric DEFAULT 1000, p_vidrio text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('variables', jsonb_build_object('ancho', p_ancho, 'alto', p_alto))
    || CASE WHEN p_vidrio IS NULL THEN '{}'::jsonb
       ELSE jsonb_build_object('elecciones', jsonb_build_object('Hoja', jsonb_build_object('Vidrio', pg_temp.id(p_vidrio)))) END;
$f$;

CREATE FUNCTION pg_temp.renglon(p_nombre text, p_version text, p_designacion text, p_entrada jsonb, p_como text DEFAULT 'Juan')
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v_id uuid := gen_random_uuid();
  v text;
BEGIN
  v := pg_temp.intentar(format(
    $q$INSERT INTO presupuestos_renglones (id, version_id, seccion_id, tipo, designacion, paquete_id, entrada)
       SELECT %L, %L, s.id, 'catalogo', %L, %L, %L FROM presupuestos_secciones s WHERE s.version_id = %2$L AND s.activo$q$,
    v_id, pg_temp.id(p_version), p_designacion, pg_temp.paquete('V'), p_entrada), p_como);
  IF v = 'ok' THEN INSERT INTO ids VALUES (p_nombre, v_id); END IF;
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.cambia(p_tabla text, p_nombre text, p_set text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE %I SET %s WHERE id = %L', p_tabla, p_set, pg_temp.id(p_nombre)), p_como);
$f$;

CREATE FUNCTION pg_temp.copiar(p_nombre text, p_desde text, p_como text DEFAULT 'Juan') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT presupuestos_version_copiar(%s)', pg_temp.l(p_desde)), p_como);
$f$;

CREATE FUNCTION pg_temp.mantener_todas(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format(
    $q$UPDATE presupuestos_renglones SET mantener = true WHERE version_id = %s AND origen_id IS NOT NULL AND tipo <> 'mano'$q$,
    pg_temp.l(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.revisar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT array_to_string(presupuestos_version_revisar(%s), %L)', pg_temp.l(p_version), '|'), p_como);
$f$;

-- Lo que pide autorización: "estado texto|…", por texto; "falta" si no se pidió.
CREATE FUNCTION pg_temp.pide(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$
    SELECT coalesce(string_agg(coalesce(x->>'estado', 'falta') || ' ' || (x->>'texto'), '|' ORDER BY x->>'texto'), '')
    FROM presupuestos_version_pedido(%s) p,
         jsonb_array_elements(jsonb_build_array(p->'comercial') || (p->'tecnica')) x
    WHERE jsonb_typeof(x) = 'object'$q$, pg_temp.l(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.pedido(p_version text, p_como text DEFAULT 'Juan') RETURNS jsonb LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_version_pedido(%s)::text', pg_temp.l(p_version)), p_como)::jsonb;
$f$;

CREATE FUNCTION pg_temp.publicar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT presupuestos_version_publicar(%s)', pg_temp.l(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.pedir(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT presupuestos_version_pedir(%s)::text', pg_temp.l(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.retirar(p_version text, p_como text DEFAULT 'Juan') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT presupuestos_version_retirar(%s)', pg_temp.l(p_version)), p_como);
$f$;

CREATE FUNCTION pg_temp.resolver(p_pedido text, p_autoriza boolean, p_como text, p_motivo text DEFAULT NULL) RETURNS text
LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT presupuestos_pedido_resolver(%L, %L, %L)', pg_temp.id(p_pedido), p_autoriza, p_motivo),
    p_como);
$f$;

-- Guarda el pedido pendiente de un tipo (y, de Técnica, de una ventana) con un nombre.
CREATE FUNCTION pg_temp.tomar(p_nombre text, p_version text, p_tipo text, p_designacion text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $f$
  INSERT INTO ids SELECT p_nombre, a.id FROM presupuestos_autorizaciones a
  WHERE a.version_id = pg_temp.id(p_version) AND a.tipo::text = p_tipo AND a.estado = 'pendiente'
    AND (p_designacion IS NULL OR a.pedido->>'etiqueta' = p_designacion);
$f$;

-- Los pedidos de una versión: "tipo estado,…".
CREATE FUNCTION pg_temp.pedidos(p_version text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(string_agg(a.tipo || ' ' || a.estado, ',' ORDER BY a.tipo, a.estado::text), '')
  FROM presupuestos_autorizaciones a WHERE a.version_id = pg_temp.id(p_version);
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
FROM unnest(ARRAY['Juan','Laura','Marta','Ana','Sofia','Rita','G','Lucia','Carlos','Belgrano','Palermo']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND (modulo IN ('catalogo', 'presupuestos') OR codigo IN
  ('contactos_ver','obras_ver','obras_todas','obras_administrar'));

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test189.local', jsonb_build_object('nombre', 'test189 ' || nombre)
FROM ids WHERE nombre IN ('Juan','Laura','Marta','Ana','Sofia','Rita','G','Lucia','Carlos');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Juan','contactos_ver'), ('Juan','obras_ver'), ('Juan','presupuestos_ver'), ('Juan','presupuestos_armar'),
  ('Laura','contactos_ver'), ('Laura','obras_ver'), ('Laura','presupuestos_ver'), ('Laura','presupuestos_armar'),
    ('Laura','presupuestos_autorizar'),
  ('Marta','contactos_ver'), ('Marta','obras_ver'), ('Marta','presupuestos_ver'), ('Marta','presupuestos_autorizar'),
  ('Ana','contactos_ver'), ('Ana','obras_ver'), ('Ana','presupuestos_ver'), ('Ana','presupuestos_armar'),
  ('Sofia','presupuestos_revision'), ('Sofia','presupuestos_autorizar_tecnica'),
  ('Rita','presupuestos_revision'),
  ('G','contactos_ver'), ('G','obras_ver'), ('G','obras_todas'), ('G','obras_administrar'),
    ('G','presupuestos_ver'), ('G','presupuestos_administrar'), ('G','presupuestos_configuracion'),
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO obras (id, nombre, direccion, origen, tipo, responsable_id, creado_por) VALUES
  (pg_temp.id('Belgrano'), 'Zqx189 Torre Belgrano', 'Zqx189 Calle 1', 'llamado', 'edificio_residencial',
   pg_temp.id('Laura'), pg_temp.id('Laura')),
  (pg_temp.id('Palermo'), 'Zqx189 Casa Palermo', 'Zqx189 Calle 2', 'llamado', 'edificio_residencial',
   pg_temp.id('Juan'), pg_temp.id('Juan'));
INSERT INTO obras_participantes (obra_id, usuario_id, agregado_por)
VALUES (pg_temp.id('Belgrano'), pg_temp.id('Juan'), pg_temp.id('Laura'));

SELECT pg_temp.crear('Perfiles', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx189 Perfiles') RETURNING id$q$);
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx189 Vidrios') RETURNING id$q$);
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx189 Ventanas') RETURNING id$q$);
SELECT pg_temp.insumo('Perfil', 'Perfiles', 'mm');
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2');
SELECT pg_temp.insumo('DVH', 'Vidrios', 'm2');
SELECT pg_temp.costo('Perfil', 70000);
SELECT pg_temp.costo('Float', 60000);
SELECT pg_temp.costo('DVH', 100000);
SELECT pg_temp.serv('Comision', 10, 300000);

SELECT pg_temp.crear('V', format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx189 V', pg_temp.l('Ventanas')));
SELECT pg_temp.mete('V.ancho', 'catalogo_variables', 'V', '{"nombre": "ancho", "orden": 1, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1200"}');
SELECT pg_temp.mete('V.alto', 'catalogo_variables', 'V', '{"nombre": "alto", "orden": 2, "ingresa_vendedor": true, "minimo": 100, "maximo": 5000, "formula": "1000"}');
SELECT pg_temp.pz('V', 'Marco', 1);
SELECT pg_temp.mete('V.Marco.Perfil', 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Marco'), 'orden', 1,
  'tipo', 'unico', 'insumo_id', pg_temp.id('Perfil'), 'medida', 'ancho', 'cantidad', '2'));
SELECT pg_temp.pz('V', 'Hoja', 2);
SELECT pg_temp.mete('V.Hoja.Vidrio', 'catalogo_materiales', 'V', jsonb_build_object('pieza_id', pg_temp.id('V.Hoja'), 'orden', 1,
  'tipo', 'elige_vendedor', 'nombre', 'Vidrio', 'ancho', 'ancho', 'alto', 'alto'));
SELECT pg_temp.mete('V.Hoja.Vidrio.Float', 'catalogo_opciones', 'V', jsonb_build_object('material_id', pg_temp.id('V.Hoja.Vidrio'),
  'orden', 1, 'insumo_id', pg_temp.id('Float'), 'predeterminada', true));
SELECT pg_temp.mete('V.Hoja.Vidrio.DVH', 'catalogo_opciones', 'V', jsonb_build_object('material_id', pg_temp.id('V.Hoja.Vidrio'),
  'orden', 2, 'insumo_id', pg_temp.id('DVH')));
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.ancho'), 'condicion', 'ancho > 4000', 'mensaje', 'Demasiado ancho', 'bloquea', true));
SELECT pg_temp.mete(NULL, 'catalogo_condiciones', 'V', jsonb_build_object(
  'variable_id', pg_temp.id('V.alto'), 'condicion', 'alto > 2000', 'mensaje', 'Muy alto', 'bloquea', false));
SELECT pg_temp.mete(NULL, 'catalogo_casos', 'V', jsonb_build_object('nombre', 'base', 'entrada', pg_temp.e()));
SELECT pg_temp.caso('enviar V', 'ok', pg_temp.intentar(format('SELECT catalogo_version_enviar(%s)', pg_temp.l('V')), 'Lucia'));
SELECT pg_temp.caso('aprobar V', 'ok', pg_temp.intentar(format('SELECT catalogo_version_aprobar(%s)', pg_temp.l('V')), 'Carlos'));

INSERT INTO ids VALUES ('P1', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx189 P1', 'ARS', 21)::text$s$, pg_temp.id('Belgrano')), 'Juan')::uuid);
INSERT INTO ids VALUES ('V1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P1')));
INSERT INTO ids VALUES ('P2', pg_temp.consultar(format(
  $s$SELECT presupuestos_alta(%L, 'Zqx189 P2', 'ARS', 21)::text$s$, pg_temp.id('Palermo')), 'Juan')::uuid);
INSERT INTO ids VALUES ('P2v1', (SELECT id FROM presupuestos_versiones WHERE presupuesto_id = pg_temp.id('P2')));

-- Una subconsulta no ve lo que escribió otra función en la misma sentencia: se lee en la siguiente.
SELECT pg_temp.caso('montaje: ventanas', 'ok/ok/ok', pg_temp.renglon('L4', 'V1', 'V4', pg_temp.e())
  || '/' || pg_temp.renglon('L7', 'V1', 'V7', pg_temp.e(1000, 1000, 'DVH'))
  || '/' || pg_temp.renglon('L9', 'V1', 'V9', pg_temp.e(1000, 2500)));
SELECT pg_temp.caso('montaje: precios', '220000,264000,319000', (
  SELECT string_agg(trim_scale(x.precio)::text, ',' ORDER BY x.designacion) FROM presupuestos_renglones x
  WHERE x.version_id = pg_temp.id('V1') AND x.tipo = 'catalogo'));
SELECT pg_temp.caso('montaje: el mínimo', 'Zqx189 Comision=227000', (
  SELECT string_agg(x.descripcion || '=' || trim_scale(x.precio), ',') FROM presupuestos_renglones x
  WHERE x.version_id = pg_temp.id('V1') AND x.tipo = 'minimo' AND x.activo));
SELECT pg_temp.caso('montaje: gerencia configura', 'ok', pg_temp.intentar('SELECT presupuestos_configurar(10, 15)', 'G'));

-- ============================================================
-- 01. Solo Técnica: una alerta
-- ============================================================
SELECT pg_temp.caso('01 revisar: lo que pide autorización no frena', '', pg_temp.revisar('V1'));
SELECT pg_temp.caso('01 lo que pide', 'falta autorización de Técnica: V9: Muy alto', pg_temp.pide('V1'));
SELECT pg_temp.caso('01 sin pedirla, publicar frena', 'PR014', pg_temp.publicar('V1'));
SELECT pg_temp.caso('01 Ana no lo ve', '42501', pg_temp.pide('V1', 'Ana'));
SELECT pg_temp.caso('01 Ana no pide', '42501', pg_temp.pedir('V1', 'Ana'));
SELECT pg_temp.caso('01 Juan pide', 'en_revision', pg_temp.pedir('V1'));
SELECT pg_temp.caso('01 un pedido de Técnica, de quien pidió', 'tecnica pendiente/true', pg_temp.pedidos('V1') || '/' || (
  SELECT (a.pedido_por = pg_temp.id('Juan'))::text FROM presupuestos_autorizaciones a WHERE a.version_id = pg_temp.id('V1')));
SELECT pg_temp.tomar('T1', 'V1', 'tecnica');
SELECT pg_temp.caso('01 pendiente', 'pendiente autorización de Técnica: V9: Muy alto', pg_temp.pide('V1'));
SELECT pg_temp.caso('01 en revisión no se edita', 'PR005', pg_temp.cambia('presupuestos_renglones', 'L4', 'cantidad = 2'));
SELECT pg_temp.caso('01 en revisión no se descarta', 'PR005', pg_temp.cambia('presupuestos_versiones', 'V1', 'activo = false'));
SELECT pg_temp.caso('01 no se pide dos veces', 'PR005', pg_temp.pedir('V1'));
SELECT pg_temp.caso('01 publicar espera', 'PR014', pg_temp.publicar('V1'));
SELECT pg_temp.caso('01 el pedido no se escribe', '42501', pg_temp.cambia('presupuestos_autorizaciones', 'T1', $s$estado = 'autorizada'$s$));

-- Lo que lee Técnica
SELECT pg_temp.caso('01 Juan no ve la cola de Técnica', '42501',
  pg_temp.consultar('SELECT count(*)::text FROM presupuestos_revision_pendientes()', 'Juan'));
SELECT pg_temp.caso('01 Sofía ve la cola, con el número', 'V9 ["Muy alto"] ' || (SELECT codigo FROM presupuestos WHERE id = pg_temp.id('P1')),
  pg_temp.consultar(format($q$SELECT string_agg(etiqueta || ' ' || motivos::text || ' ' || codigo, ',')
    FROM presupuestos_revision_pendientes() WHERE version_id = %s$q$, pg_temp.l('V1')), 'Sofia'));
SELECT pg_temp.caso('01 Sofía lee la versión completa', 'V4:-,V7:-,V9:pendiente', pg_temp.consultar(format($q$
  SELECT string_agg(designacion || ':' || coalesce(pedido_estado::text, '-'), ',' ORDER BY designacion)
  FROM presupuestos_revision_version(%s)$q$, pg_temp.l('V1')), 'Sofia'));
SELECT pg_temp.caso('01 sin precios', '0', pg_temp.consultar(format($q$
  SELECT count(*)::text FROM presupuestos_revision_version(%s) x WHERE row_to_json(x)::text ~ '220000|264000|319000|227000'$q$,
  pg_temp.l('V1')), 'Sofia'));
SELECT pg_temp.caso('01 Sofía no lee la tabla', '0', pg_temp.consultar(
  'SELECT count(*)::text FROM presupuestos_autorizaciones', 'Sofia'));
SELECT pg_temp.caso('01 Rita lee', '3', pg_temp.consultar(format(
  'SELECT count(*)::text FROM presupuestos_revision_version(%s)', pg_temp.l('V1')), 'Rita'));
SELECT pg_temp.caso('01 Rita no lee un presupuesto sin pedidos de Técnica', '42501', pg_temp.consultar(format(
  'SELECT count(*)::text FROM presupuestos_revision_version(%s)', pg_temp.l('P2v1')), 'Rita'));
SELECT pg_temp.caso('01 Juan no lee como Técnica', '42501', pg_temp.consultar(format(
  'SELECT count(*)::text FROM presupuestos_revision_version(%s)', pg_temp.l('V1')), 'Juan'));
SELECT pg_temp.caso('01 Rita no autoriza', '42501', pg_temp.resolver('T1', true, 'Rita'));
SELECT pg_temp.caso('01 la jefa no autoriza alertas', '42501', pg_temp.resolver('T1', true, 'Laura'));

SELECT pg_temp.caso('01 Sofía autoriza', 'ok', pg_temp.resolver('T1', true, 'Sofia'));
SELECT pg_temp.caso('01 queda registrado', 'autorizada/true', (
  SELECT a.estado || '/' || (a.resuelto_por = pg_temp.id('Sofia')) FROM presupuestos_autorizaciones a WHERE a.id = pg_temp.id('T1')));
SELECT pg_temp.caso('01 sigue en revisión, lista para publicar', 'en_revision/autorizada autorización de Técnica: V9: Muy alto',
  pg_temp.estado('V1') || '/' || pg_temp.pide('V1'));
SELECT pg_temp.caso('01 resolverlo de nuevo', 'PR018', pg_temp.resolver('T1', true, 'Sofia'));
SELECT pg_temp.caso('01 Juan publica', 'ok/publicado', pg_temp.publicar('V1') || '/' || pg_temp.estado('V1'));
SELECT pg_temp.caso('01 la cola queda vacía', '0', pg_temp.consultar(format(
  'SELECT count(*)::text FROM presupuestos_revision_pendientes() WHERE version_id = %s', pg_temp.l('V1')), 'Sofia'));

-- La v1 se calculó hace 7 días; hace 5, el perfil y el mínimo subieron. Ayer se dio de baja el DVH.
ALTER TABLE presupuestos_renglones DISABLE TRIGGER USER;
UPDATE presupuestos_renglones SET condiciones_en = now() - interval '7 days'
WHERE version_id = pg_temp.id('V1') AND condiciones_en IS NOT NULL;
ALTER TABLE presupuestos_renglones ENABLE TRIGGER USER;
SELECT pg_temp.costo('Perfil', 80000, now() - interval '5 days');
SELECT pg_temp.serv('Comision', 10, 400000, now() - interval '5 days');
SELECT pg_temp.caso('montaje: baja del DVH', 'ok', pg_temp.intentar(format(
  'UPDATE catalogo_insumos SET activo = false WHERE id = %s', pg_temp.l('DVH')), 'Lucia'));

-- ============================================================
-- 02. El jefe y Técnica: mantener, descuento y una opción dada de baja
-- ============================================================
SELECT pg_temp.copiar('V2', 'V1');
SELECT pg_temp.caso('02 mantener todas', 'ok', pg_temp.mantener_todas('V2'));
SELECT pg_temp.caso('02 descuento sobre el tope', 'ok', pg_temp.cambia('presupuestos_versiones', 'V2', 'descuento = 12'));
SELECT pg_temp.caso('02 revisar: nada frena', '', pg_temp.revisar('V2'));
SELECT pg_temp.caso('02 lo que pide',
  'falta autorización de Técnica: V7: Ya no se ofrece: Zqx189 DVH|'
  || 'autorizada autorización de Técnica: V9: Muy alto|'
  || 'falta autorización del jefe comercial: 4 renglones mantenidos · descuento de 12 % sobre el tope de 10 %', pg_temp.pide('V2'));
SELECT pg_temp.caso('02 mantenido contra a hoy, y lo que se resigna',
  'V4=220000>242000:22000,V7=264000>null:null,V9=319000>341000:22000,Zqx189 Comision=227000>327000:100000|ARS 144000', (
  SELECT string_agg(x->>'etiqueta' || '=' || trim_scale((x->>'precio')::numeric) || '>'
                    || coalesce(trim_scale((x->>'hoy')::numeric)::text, 'null') || ':'
                    || coalesce(trim_scale((x->>'diferencia')::numeric)::text, 'null'), ',' ORDER BY x->>'etiqueta')
  FROM jsonb_array_elements(pg_temp.pedido('V2')->'comercial'->'renglones') x) || '|' || (
  SELECT string_agg((d->>'moneda') || ' ' || trim_scale((d->>'monto')::numeric), ',')
  FROM jsonb_array_elements(pg_temp.pedido('V2')->'comercial'->'diferencia') d));
SELECT pg_temp.caso('02 sin pedirla, publicar frena', 'PR014', pg_temp.publicar('V2'));
SELECT pg_temp.caso('02 Juan pide', 'en_revision', pg_temp.pedir('V2'));
SELECT pg_temp.caso('02 la alerta ya autorizada no se pide', 'comercial pendiente,tecnica pendiente', pg_temp.pedidos('V2'));
SELECT pg_temp.tomar('C1', 'V2', 'comercial');
SELECT pg_temp.tomar('T2', 'V2', 'tecnica');
SELECT pg_temp.caso('02 guarda qué se pidió', '12/10/4/V7', (
  SELECT trim_scale((c.pedido->>'descuento')::numeric) || '/' || trim_scale((c.pedido->>'tope')::numeric) || '/'
         || jsonb_array_length(c.pedido->'renglones') || '/'
         || (t.pedido->>'etiqueta')
  FROM presupuestos_autorizaciones c, presupuestos_autorizaciones t WHERE c.id = pg_temp.id('C1') AND t.id = pg_temp.id('T2')));
SELECT pg_temp.caso('02 la jefa ve los pedidos; Ana no', '2/0', pg_temp.consultar(format(
  'SELECT count(*)::text FROM presupuestos_autorizaciones WHERE version_id = %s', pg_temp.l('V2')), 'Laura') || '/' ||
  pg_temp.consultar(format('SELECT count(*)::text FROM presupuestos_autorizaciones WHERE version_id = %s', pg_temp.l('V2')), 'Ana'));
SELECT pg_temp.caso('02 la jefa puede; Marta, sin la obra, no', 'true/false', pg_temp.consultar(format(
  $q$SELECT presupuestos_puede_autorizar('comercial', %s)::text$q$, pg_temp.l('Belgrano')), 'Laura') || '/' ||
  pg_temp.consultar(format($q$SELECT presupuestos_puede_autorizar('comercial', %s)::text$q$, pg_temp.l('Belgrano')), 'Marta'));
SELECT pg_temp.caso('02 Marta no autoriza', '42501', pg_temp.resolver('C1', true, 'Marta'));
SELECT pg_temp.caso('02 Juan no se autoriza', '42501', pg_temp.resolver('C1', true, 'Juan'));
SELECT pg_temp.caso('02 Sofía no autoriza lo del jefe', '42501', pg_temp.resolver('C1', true, 'Sofia'));
SELECT pg_temp.caso('02 devolver sin motivo', 'PR019', pg_temp.resolver('C1', false, 'Laura', '  '));
SELECT pg_temp.caso('02 Sofía autoriza la opción dada de baja', 'ok', pg_temp.resolver('T2', true, 'Sofia'));
SELECT pg_temp.caso('02 publicar espera a la jefa', 'PR014', pg_temp.publicar('V2'));
SELECT pg_temp.caso('02 la jefa devuelve', 'ok/borrador', pg_temp.resolver('C1', false, 'Laura', 'Mucho descuento')
  || '/' || pg_temp.estado('V2'));
SELECT pg_temp.caso('02 con el motivo; lo de Técnica sigue', 'devuelta Mucho descuento/autorizada', (
  SELECT c.estado || ' ' || c.motivo || '/' || t.estado
  FROM presupuestos_autorizaciones c, presupuestos_autorizaciones t WHERE c.id = pg_temp.id('C1') AND t.id = pg_temp.id('T2')));
SELECT pg_temp.caso('02 devuelta, se edita', 'ok', pg_temp.cambia('presupuestos_versiones', 'V2', 'descuento = 10'));
SELECT pg_temp.caso('02 lo que pide ahora',
  'autorizada autorización de Técnica: V7: Ya no se ofrece: Zqx189 DVH|autorizada autorización de Técnica: V9: Muy alto|'
  || 'falta autorización del jefe comercial: 4 renglones mantenidos', pg_temp.pide('V2'));
SELECT pg_temp.caso('02 pide de nuevo: otra fila', 'en_revision/comercial devuelta,comercial pendiente,tecnica autorizada',
  pg_temp.pedir('V2') || '/' || pg_temp.pedidos('V2'));
SELECT pg_temp.tomar('C2', 'V2', 'comercial');
SELECT pg_temp.caso('02 Ana no retira', '42501', pg_temp.retirar('V2', 'Ana'));
SELECT pg_temp.caso('02 Juan retira', 'ok/borrador', pg_temp.retirar('V2') || '/' || pg_temp.estado('V2'));
SELECT pg_temp.caso('02 el pedido queda retirado', 'retirada', (
  SELECT estado::text FROM presupuestos_autorizaciones WHERE id = pg_temp.id('C2')));
SELECT pg_temp.caso('02 retirar un borrador', 'PR017', pg_temp.retirar('V2'));
SELECT pg_temp.caso('02 autorizar lo retirado', 'PR018', pg_temp.resolver('C2', true, 'Laura'));
SELECT pg_temp.caso('02 pide otra vez', 'en_revision', pg_temp.pedir('V2'));
SELECT pg_temp.tomar('C3', 'V2', 'comercial');
SELECT pg_temp.caso('02 la jefa autoriza', 'ok', pg_temp.resolver('C3', true, 'Laura'));
SELECT pg_temp.caso('02 Juan publica', 'ok/obsoleto/publicado', pg_temp.publicar('V2') || '/' || pg_temp.estado('V1') || '/'
  || pg_temp.estado('V2'));
SELECT pg_temp.caso('02 el historial', 'comercial autorizada,comercial devuelta,comercial retirada,tecnica autorizada',
  pg_temp.pedidos('V2'));

-- ============================================================
-- 03. Quien pide ya puede autorizar
-- ============================================================
SELECT pg_temp.copiar('V3', 'V2', 'Laura');
SELECT pg_temp.caso('03 mantener todas', 'ok', pg_temp.mantener_todas('V3', 'Laura'));
SELECT pg_temp.caso('03 Laura pide y publica en el mismo paso', 'publicado/obsoleto', pg_temp.pedir('V3', 'Laura') || '/'
  || pg_temp.estado('V2'));
SELECT pg_temp.caso('03 queda autorizado por ella; Técnica ya valía', 'comercial autorizada/true', pg_temp.pedidos('V3') || '/' || (
  SELECT (a.resuelto_por = pg_temp.id('Laura') AND a.pedido_por = pg_temp.id('Laura'))::text
  FROM presupuestos_autorizaciones a WHERE a.version_id = pg_temp.id('V3')));

-- ============================================================
-- 04. Ventanas iguales, y gerencia
-- ============================================================
SELECT pg_temp.copiar('V4', 'V3');
SELECT pg_temp.caso('04 sacar la del DVH', 'ok', pg_temp.intentar(format(
  $q$UPDATE presupuestos_renglones SET activo = false WHERE version_id = %s AND designacion = 'V7'$q$, pg_temp.l('V4')), 'Juan'));
SELECT pg_temp.caso('04 dos ventanas iguales con alerta', 'ok/ok', pg_temp.renglon('L10', 'V4', 'V10', pg_temp.e(1000, 2600))
  || '/' || pg_temp.renglon('L11', 'V4', 'V11', pg_temp.e(1000, 2600)));
SELECT pg_temp.caso('04 Juan pide', 'en_revision/tecnica pendiente,tecnica pendiente', pg_temp.pedir('V4') || '/' || pg_temp.pedidos('V4'));
SELECT pg_temp.tomar('T10', 'V4', 'tecnica', 'V10');
SELECT pg_temp.caso('04 autorizar una autoriza la igual', 'ok/tecnica autorizada,tecnica autorizada',
  pg_temp.resolver('T10', true, 'Sofia') || '/' || pg_temp.pedidos('V4'));
SELECT pg_temp.caso('04 las dos, por Sofía', 'true', (
  SELECT bool_and(a.resuelto_por = pg_temp.id('Sofia'))::text FROM presupuestos_autorizaciones a WHERE a.version_id = pg_temp.id('V4')));
SELECT pg_temp.caso('04 Juan publica', 'ok', pg_temp.publicar('V4'));

SELECT pg_temp.copiar('V5', 'V4', 'G');
SELECT pg_temp.caso('04 una alerta nueva', 'ok', pg_temp.renglon('L12', 'V5', 'V12', pg_temp.e(1000, 2700), 'G'));
SELECT pg_temp.caso('04 gerencia autoriza también lo de Técnica', 'publicado/tecnica autorizada', pg_temp.pedir('V5', 'G')
  || '/' || pg_temp.pedidos('V5'));

-- ============================================================
-- 05. Lo que no se llama desde afuera
-- ============================================================
SELECT pg_temp.caso('05 sin EXECUTE: ' || f, 'false', has_function_privilege('authenticated', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_precio_fuera(uuid,jsonb)', 'presupuestos_tecnica_cubre(jsonb,jsonb)',
  'presupuestos_version_a_borrador(uuid)']) AS f;
SELECT pg_temp.caso('05 anon: ' || f, 'false', has_function_privilege('anon', 'public.' || f, 'EXECUTE')::text)
FROM unnest(ARRAY['presupuestos_version_pedido(uuid)', 'presupuestos_version_pedir(uuid)',
  'presupuestos_pedido_resolver(uuid,boolean,text)', 'presupuestos_version_retirar(uuid)', 'presupuestos_revision_pendientes()',
  'presupuestos_revision_version(uuid)', 'presupuestos_puede_autorizar(tipo_autorizacion_presupuesto,uuid)']) AS f;
SELECT pg_temp.caso('05 sin INSERT ni UPDATE', 'false/false',
  has_table_privilege('authenticated', 'public.presupuestos_autorizaciones', 'INSERT') || '/' ||
  has_table_privilege('authenticated', 'public.presupuestos_autorizaciones', 'UPDATE'));
SELECT pg_temp.caso('05 RLS', 'true', (SELECT relrowsecurity::text FROM pg_class WHERE oid = 'public.presupuestos_autorizaciones'::regclass));

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
