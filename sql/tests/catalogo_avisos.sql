-- Verificación de sql/164 y sql/165: los avisos del catálogo, leídos con notificaciones_listar como cada persona.
-- NO es una migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Lucia y Martin (Técnica: Paquetes con armar, Insumos con cargar), Ana (Administración: Insumos con costos, Servicios fijos
-- con editar, Servicios en % con editar), Carlos y Gerardo (gerentes: lo de Ana más Paquetes con aprobar), Sofia (Insumos con costos)
-- y Juan (nada). Lo creado lleva Zqx165.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;
CREATE TEMP SEQUENCE reloj;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.l(p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT quote_literal(pg_temp.id(p_nombre));
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
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
  SELECT pg_temp.crear(p_v, format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx165 ' || p_v, pg_temp.l('Ventanas')));
$f$;

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.un(p_v text, p_pieza text, p_orden int, p_insumo text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_insumo || '.' || p_orden, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', 'unico',
                       'insumo_id', pg_temp.id(p_insumo)));
$f$;

CREATE FUNCTION pg_temp.op(p_v text, p_material text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_insumo, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden, 'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.colores(p_v text, p_base text, VARIADIC p_otros text[] DEFAULT '{}') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  c text;
BEGIN
  PERFORM pg_temp.mete(NULL, 'catalogo_versiones_colores', p_v, jsonb_build_object('color_id', pg_temp.id(p_base), 'base', true));
  FOREACH c IN ARRAY p_otros LOOP
    PERFORM pg_temp.mete(NULL, 'catalogo_versiones_colores', p_v, jsonb_build_object('color_id', pg_temp.id(c)));
  END LOOP;
END;
$f$;

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text DEFAULT 'Perfiles') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format($q$SELECT catalogo_insumo_alta(%L, %s, 'u', 0.1, NULL)$q$,
    'Zqx165 ' || p_nombre, pg_temp.l(p_categoria)));
$f$;

CREATE FUNCTION pg_temp.con_color(p_nombre text, VARIADIC p_colores text[]) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format($q$SELECT catalogo_insumo_alta(%L, %s, 'u', 0.1, NULL, ARRAY[%s]::uuid[])$q$,
    'Zqx165 ' || p_nombre, pg_temp.l('Perfiles'), (SELECT string_agg(pg_temp.l(c), ', ') FROM unnest(p_colores) c)));
$f$;

CREATE FUNCTION pg_temp.categoria(p_nombre text, p_tipo text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('INSERT INTO catalogo_categorias (tipo, nombre) VALUES (%L, %L) RETURNING id',
    p_tipo, 'Zqx165 ' || p_nombre), p_como);
$f$;

CREATE FUNCTION pg_temp.costear(p_insumo text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por)
  SELECT va.id, 100, 'ARS'::moneda, pg_temp.id('Ana')
  FROM catalogo_variantes va
  WHERE va.insumo_id = pg_temp.id(p_insumo) AND va.activo
    AND NOT EXISTS (SELECT 1 FROM catalogo_costos k WHERE k.variante_id = va.id);
$f$;

CREATE FUNCTION pg_temp.variante(p_insumo text, p_color text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM catalogo_variantes WHERE insumo_id = pg_temp.id(p_insumo) AND color_id = pg_temp.id(p_color);
$f$;

CREATE FUNCTION pg_temp.cargar(p_insumo text, p_color text, p_como text DEFAULT 'Ana') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT catalogo_costos_cargar(%L::jsonb)',
    jsonb_build_array(jsonb_build_object('variante_id', pg_temp.variante(p_insumo, p_color), 'costo', 100, 'moneda', 'ARS'))::text), p_como);
$f$;

CREATE FUNCTION pg_temp.sumar(p_insumo text, p_color text, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT catalogo_variante_sumar(%s, %s)', pg_temp.l(p_insumo), pg_temp.l(p_color)), p_como);
$f$;

CREATE FUNCTION pg_temp.var_activa(p_insumo text, p_color text, p_activo boolean, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE catalogo_variantes SET activo = %L WHERE id = %L', p_activo, pg_temp.variante(p_insumo, p_color)), p_como);
$f$;

CREATE FUNCTION pg_temp.ins_activo(p_insumo text, p_activo boolean, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = %L WHERE id = %s', p_activo, pg_temp.l(p_insumo)), p_como);
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

CREATE FUNCTION pg_temp.paq(p_v text, p_activo boolean, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE catalogo_paquetes SET activo = %L WHERE id = %L', p_activo, pg_temp.paquete(p_v)), p_como);
$f$;

-- Todo pasa en una transacción, con el mismo now(): acá pasa el tiempo, para que "el último" y "el anterior" signifiquen algo.
CREATE FUNCTION pg_temp.pasa_el_tiempo() RETURNS void LANGUAGE sql AS $f$
  UPDATE catalogo_porcentajes_valores SET created_at = now() - (100000 - nextval('reloj')) * interval '1 minute' WHERE created_at = now();
  UPDATE catalogo_versiones_historia SET created_at = now() - (100000 - nextval('reloj')) * interval '1 minute' WHERE created_at = now();
$f$;

CREATE FUNCTION pg_temp.fn(p_fn text, p_v text, p_como text, p_extra text DEFAULT '') RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.intentar(format('SELECT catalogo_version_%s(%s%s)', p_fn, pg_temp.l(p_v), p_extra), p_como);
BEGIN
  PERFORM pg_temp.pasa_el_tiempo();
  RETURN v;
END;
$f$;

CREATE FUNCTION pg_temp.publicar(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso('enviar ' || p_v, 'ok', pg_temp.fn('enviar', p_v, 'Lucia'));
  SELECT pg_temp.caso('aprobar ' || p_v, 'ok', pg_temp.fn('aprobar', p_v, 'Carlos'));
$f$;

-- Lo mínimo que se puede enviar: una pieza con un insumo y un caso.
CREATE FUNCTION pg_temp.chico(p_v text, p_insumo text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.ver(p_v);
  PERFORM pg_temp.pz(p_v, 'Unica', 1);
  PERFORM pg_temp.un(p_v, 'Unica', 1, p_insumo);
  PERFORM pg_temp.mete(p_v || '.caso', 'catalogo_casos', p_v, '{"nombre": "base"}');
END;
$f$;

-- "etiqueta | motivo | destino | actor" de cada aviso de ese tipo y ese nombre, sin los prefijos del test. "-" si no hay. Lee
-- catalogo_avisos con el mismo JOIN del actor que la bandeja: notificaciones_listar tarda unos 60 ms por aviso (BACKLOG → Notificaciones),
-- y con cientos de lecturas el test no termina. De punta a punta se prueba un caso de cada tipo, con pg_temp.listado.
CREATE FUNCTION pg_temp.bandeja(p_como text, p_tipo text, p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format($q$
    SELECT replace(replace(string_agg(concat_ws(' | ', x.etiqueta, x.motivo, x.destino, a.nombre), ' // ' ORDER BY x.etiqueta COLLATE "C", x.motivo COLLATE "C"),
                   'Zqx165 ', ''), 'test165 ', '')
    FROM catalogo_avisos() x
    JOIN usuario_notificaciones n ON n.id = x.notificacion_id
    LEFT JOIN notificaciones_actores() a ON a.id = n.actor_id
    WHERE n.tipo = %L AND x.etiqueta LIKE %L
  $q$, p_tipo, 'Zqx165 ' || p_nombre || '%'), p_como), '-');
$f$;

-- Lo mismo, leído con notificaciones_listar.
CREATE FUNCTION pg_temp.listado(p_como text, p_tipo text, p_nombre text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format($q$
    SELECT replace(replace(string_agg(concat_ws(' | ', etiqueta, motivo, destino, actor), ' // ' ORDER BY etiqueta COLLATE "C", motivo COLLATE "C"),
                   'Zqx165 ', ''), 'test165 ', '')
    FROM notificaciones_listar(500) WHERE tipo = %L AND etiqueta LIKE %L
  $q$, p_tipo, 'Zqx165 ' || p_nombre || '%'), p_como), '-');
$f$;

-- Cuántos avisos de ese tipo y ese nombre dicen exactamente este motivo.
CREATE FUNCTION pg_temp.cuenta(p_como text, p_tipo text, p_nombre text, p_motivo text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$
    SELECT count(*)::text
    FROM catalogo_avisos() x
    JOIN usuario_notificaciones n ON n.id = x.notificacion_id
    WHERE n.tipo = %L AND x.etiqueta LIKE %L AND replace(x.motivo, 'Zqx165 ', '') = %L
  $q$, p_tipo, 'Zqx165 ' || p_nombre || '%', p_motivo), p_como);
$f$;

CREATE FUNCTION pg_temp.destino(p_como text, p_tipo text, p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$
    SELECT x.destino_id::text
    FROM catalogo_avisos() x
    JOIN usuario_notificaciones n ON n.id = x.notificacion_id
    WHERE n.tipo = %L AND x.etiqueta LIKE %L
    LIMIT 1
  $q$, p_tipo, 'Zqx165 ' || p_nombre || '%'), p_como)::uuid;
$f$;

CREATE FUNCTION pg_temp.permiso(p_u text, p_s text, p_activo boolean) RETURNS void LANGUAGE sql AS $f$
  UPDATE usuario_submodulos SET activo = p_activo WHERE usuario_id = pg_temp.id(p_u) AND submodulo_id = pg_temp.id(p_s);
$f$;

-- Guarda un servicio en %. Sin la clave todavía, es un alta. Un mínimo siempre va en ARS y por paquete.
CREATE FUNCTION pg_temp.pct(p_clave text, p_nombre text, p_pct numeric, p_paso int, p_cats text[], p_min numeric DEFAULT NULL,
                            p_opc boolean DEFAULT false, p_como text DEFAULT 'Ana') RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.consultar(format('SELECT catalogo_porcentaje_guardar(%L, %L, %s, %s, %L, %L, %L, %L, %L, true)',
    pg_temp.id(p_clave), 'Zqx165 ' || p_nombre, p_pct, p_paso,
    (SELECT coalesce(array_agg(pg_temp.id(c)), '{}') FROM unnest(p_cats) c),
    p_min, CASE WHEN p_min IS NOT NULL THEN 'ARS' END, CASE WHEN p_min IS NOT NULL THEN 'paquete' END, p_opc), p_como);
BEGIN
  PERFORM pg_temp.caso('guardar ' || p_clave || ' ' || p_pct, 'uuid', CASE WHEN v ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE v END);
  IF v ~ '^[0-9a-f-]{36}$' THEN
    INSERT INTO ids VALUES (p_clave, v::uuid) ON CONFLICT DO NOTHING;
  END IF;
  PERFORM pg_temp.pasa_el_tiempo();
END;
$f$;

CREATE FUNCTION pg_temp.activar(p_clave text, p_activo boolean, p_como text DEFAULT 'Ana') RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.caso('activar ' || p_clave || ' ' || p_activo, 'ok', pg_temp.intentar(
    format('SELECT catalogo_porcentaje_activar(%s, %L)', pg_temp.l(p_clave), p_activo), p_como));
  PERFORM pg_temp.pasa_el_tiempo();
END;
$f$;

CREATE FUNCTION pg_temp.revertir(p_clave text, p_como text DEFAULT 'Carlos') RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.caso('revertir ' || p_clave, 'ok', pg_temp.intentar(format('SELECT catalogo_porcentaje_revertir(%L, true)', (
    SELECT x.id FROM catalogo_porcentajes_valores x WHERE x.porcentaje_id = pg_temp.id(p_clave) ORDER BY x.created_at DESC LIMIT 1)), p_como));
  PERFORM pg_temp.pasa_el_tiempo();
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Lucia','Martin','Ana','Carlos','Gerardo','Sofia','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND modulo = 'catalogo';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test165.local', jsonb_build_object('nombre', 'test165 ' || nombre)
FROM ids WHERE nombre IN ('Lucia','Martin','Ana','Carlos','Gerardo','Sofia','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Martin','catalogo_paquetes'), ('Martin','catalogo_armar'), ('Martin','catalogo_insumos'), ('Martin','catalogo_cargar'),
  ('Ana','catalogo_insumos'), ('Ana','catalogo_costos'), ('Ana','catalogo_fijos'), ('Ana','catalogo_fijos_editar'),
  ('Ana','catalogo_porcentajes'), ('Ana','catalogo_porcentajes_editar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar'), ('Carlos','catalogo_insumos'), ('Carlos','catalogo_costos'),
  ('Carlos','catalogo_fijos'), ('Carlos','catalogo_fijos_editar'), ('Carlos','catalogo_porcentajes'), ('Carlos','catalogo_porcentajes_editar'),
  ('Gerardo','catalogo_paquetes'), ('Gerardo','catalogo_aprobar'), ('Gerardo','catalogo_insumos'), ('Gerardo','catalogo_costos'),
  ('Gerardo','catalogo_fijos'), ('Gerardo','catalogo_fijos_editar'), ('Gerardo','catalogo_porcentajes'), ('Gerardo','catalogo_porcentajes_editar'),
  ('Sofia','catalogo_insumos'), ('Sofia','catalogo_costos')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.categoria('Perfiles', 'insumo');
SELECT pg_temp.categoria('Vidrios', 'insumo');
SELECT pg_temp.categoria('Herrajes', 'insumo');
SELECT pg_temp.categoria('Vacia', 'insumo');
SELECT pg_temp.categoria('Ventanas', 'paquete');
SELECT pg_temp.categoria('Manos', 'servicio', 'Ana');

SELECT pg_temp.crear('Blanco', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx165 Blanco') RETURNING id$q$);
SELECT pg_temp.crear('Negro', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx165 Negro') RETURNING id$q$);
SELECT pg_temp.crear('Rojo', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx165 Rojo') RETURNING id$q$);
SELECT pg_temp.crear('Verde', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx165 Verde') RETURNING id$q$);

-- ============================================================
-- Categoría de insumo nueva
-- ============================================================
SELECT pg_temp.caso('categoría de insumo: a Ana', 'Vidrios | catalogo_porcentajes | Lucia', pg_temp.bandeja('Ana', 'catalogo_categoria_nueva', 'Vidrios'));
SELECT pg_temp.caso('categoría de insumo: en la bandeja', 'Vidrios | catalogo_porcentajes | Lucia', pg_temp.listado('Ana', 'catalogo_categoria_nueva', 'Vidrios'));
SELECT pg_temp.caso('categoría de insumo: al gerente', 'Vidrios | catalogo_porcentajes | Lucia', pg_temp.bandeja('Carlos', 'catalogo_categoria_nueva', 'Vidrios'));
SELECT pg_temp.caso('categoría de insumo: no a quien la creó', '-', pg_temp.bandeja('Lucia', 'catalogo_categoria_nueva', 'Vidrios'));
SELECT pg_temp.caso('categoría de insumo: no a quien solo carga costos', '-', pg_temp.bandeja('Sofia', 'catalogo_categoria_nueva', 'Vidrios'));
SELECT pg_temp.caso('categoría de paquete: no avisa', '-', pg_temp.bandeja('Ana', 'catalogo_categoria_nueva', 'Ventanas'));
SELECT pg_temp.caso('categoría de servicio: no avisa', '-', pg_temp.bandeja('Carlos', 'catalogo_categoria_nueva', 'Manos'));

UPDATE usuario_notificaciones SET leida_at = now()
WHERE usuario_id = pg_temp.id('Ana') AND tipo = 'catalogo_categoria_nueva' AND entidad_id = pg_temp.id('Vidrios');
SELECT pg_temp.caso('categoría: leída no desaparece', 'Vidrios | catalogo_porcentajes | Lucia', pg_temp.bandeja('Ana', 'catalogo_categoria_nueva', 'Vidrios'));

SELECT pg_temp.caso('categoría: dar de baja la vacía', 'ok', pg_temp.intentar(
  format('UPDATE catalogo_categorias SET activo = false WHERE id = %s', pg_temp.l('Vacia')), 'Lucia'));
SELECT pg_temp.caso('categoría de baja: el aviso desaparece', '-', pg_temp.bandeja('Ana', 'catalogo_categoria_nueva', 'Vacia'));

-- ============================================================
-- Insumo sin costo
-- ============================================================
SELECT pg_temp.insumo('Float', 'Vidrios');
SELECT pg_temp.caso('insumo nuevo: a Ana', 'Float | catalogo_insumos | Lucia', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo nuevo: en la bandeja', 'Float | catalogo_insumos | Lucia', pg_temp.listado('Ana', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo nuevo: al gerente', 'Float | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo nuevo: a Sofia', 'Float | catalogo_insumos | Lucia', pg_temp.bandeja('Sofia', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo nuevo: no a quien lo cargó', '-', pg_temp.bandeja('Lucia', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo nuevo: no a otro de Técnica', '-', pg_temp.bandeja('Martin', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo nuevo: no a quien no tiene nada', '-', pg_temp.bandeja('Juan', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo nuevo: lleva al insumo', pg_temp.id('Float')::text, pg_temp.destino('Ana', 'catalogo_insumo_sin_costo', 'Float')::text);

SELECT pg_temp.caso('insumo de baja: dar de baja', 'ok', pg_temp.ins_activo('Float', false));
SELECT pg_temp.caso('insumo de baja: el aviso no se ve', '-', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('insumo reactivado sin costo: reactivar', 'ok', pg_temp.ins_activo('Float', true));
SELECT pg_temp.caso('insumo reactivado sin costo: vuelve', 'Float | catalogo_insumos | Lucia', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Float'));

SELECT pg_temp.permiso('Sofia', 'catalogo_costos', false);
SELECT pg_temp.caso('sin el permiso: el aviso no se ve', '-', pg_temp.bandeja('Sofia', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.caso('sin el permiso de otra: Ana lo sigue viendo', 'Float | catalogo_insumos | Lucia', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Float'));
SELECT pg_temp.permiso('Sofia', 'catalogo_costos', true);

SELECT pg_temp.con_color('Perfil', 'Blanco', 'Negro');
SELECT pg_temp.caso('con colores: un solo aviso, con lo que falta', 'Perfil | Blanco, Negro | catalogo_insumos | Lucia', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Perfil'));
SELECT pg_temp.caso('con colores: una sola fila activa', '1', (
  SELECT count(*)::text FROM usuario_notificaciones n
  WHERE n.usuario_id = pg_temp.id('Ana') AND n.entidad_id = pg_temp.id('Perfil') AND n.activo));

SELECT pg_temp.caso('cargar el costo de Blanco', 'ok', pg_temp.cargar('Perfil', 'Blanco'));
SELECT pg_temp.caso('falta uno: lo dice', 'Perfil | Negro | catalogo_insumos | Lucia', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Perfil'));
SELECT pg_temp.caso('cargar el costo de Negro', 'ok', pg_temp.cargar('Perfil', 'Negro'));
SELECT pg_temp.caso('todos con costo: desaparece', '-', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Perfil'));
SELECT pg_temp.caso('todos con costo: desaparece también para el gerente', '-', pg_temp.bandeja('Carlos', 'catalogo_insumo_sin_costo', 'Perfil'));

UPDATE usuario_notificaciones SET leida_at = now()
WHERE usuario_id = pg_temp.id('Ana') AND entidad_id = pg_temp.id('Perfil') AND activo;
SELECT pg_temp.caso('color nuevo: sumar', 'ok', pg_temp.sumar('Perfil', 'Rojo'));
SELECT pg_temp.caso('color nuevo: avisa', 'Perfil | Rojo | catalogo_insumos | Lucia', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Perfil'));
SELECT pg_temp.caso('color nuevo: vuelve a estar sin leer', 'false', pg_temp.consultar(
  $q$SELECT leida::text FROM notificaciones_listar(500) WHERE tipo = 'catalogo_insumo_sin_costo' AND etiqueta = 'Zqx165 Perfil'$q$, 'Ana'));
SELECT pg_temp.caso('color nuevo: una sola fila activa', '1', (
  SELECT count(*)::text FROM usuario_notificaciones n
  WHERE n.usuario_id = pg_temp.id('Ana') AND n.entidad_id = pg_temp.id('Perfil') AND n.activo));
SELECT pg_temp.costear('Perfil');

SELECT pg_temp.caso('reactivar con costo: dar de baja Blanco', 'ok', pg_temp.var_activa('Perfil', 'Blanco', false));
SELECT pg_temp.caso('reactivar con costo: volver a sumar', 'ok', pg_temp.sumar('Perfil', 'Blanco'));
SELECT pg_temp.caso('reactivar con costo: no avisa', '-', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Perfil'));

SELECT pg_temp.caso('reactivar sin costo: sumar Verde', 'ok', pg_temp.sumar('Perfil', 'Verde'));
SELECT pg_temp.caso('reactivar sin costo: dar de baja Verde', 'ok', pg_temp.var_activa('Perfil', 'Verde', false));
SELECT pg_temp.caso('variante sin costo de baja: no falta nada', '-', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Perfil'));
SELECT pg_temp.caso('reactivar sin costo: volver a sumar', 'ok', pg_temp.sumar('Perfil', 'Verde'));
SELECT pg_temp.caso('reactivar sin costo: avisa', 'Perfil | Verde | catalogo_insumos | Lucia', pg_temp.bandeja('Ana', 'catalogo_insumo_sin_costo', 'Perfil'));

SELECT pg_temp.crear('Soldado', format($q$SELECT catalogo_fijo_alta('Zqx165 Soldado', %s, 'u', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');
SELECT pg_temp.caso('servicio fijo: nace con su costo y no avisa', '-', pg_temp.bandeja('Carlos', 'catalogo_insumo_sin_costo', 'Soldado'));

-- ============================================================
-- Bajas
-- ============================================================
SELECT pg_temp.insumo('Rueda');
SELECT pg_temp.insumo('Solo');
SELECT pg_temp.insumo('Tela');
SELECT pg_temp.insumo('Mix');
SELECT pg_temp.insumo('Base');
SELECT pg_temp.insumo('FloatO');
SELECT pg_temp.insumo('LamO');
SELECT pg_temp.insumo('SoloBorrador');
SELECT pg_temp.insumo('SinUso');
SELECT pg_temp.con_color('PerfilC', 'Blanco', 'Negro');
SELECT pg_temp.costear(i) FROM unnest(ARRAY['Rueda','Solo','Tela','Mix','Base','FloatO','LamO','SoloBorrador','SinUso','PerfilC']) AS i;

SELECT pg_temp.chico('VenA', 'Rueda');
SELECT pg_temp.chico('VenB', 'Rueda');
SELECT pg_temp.chico('VenC', 'Solo');
SELECT pg_temp.pz('VenC', 'Mosq', 2, '{"opcional": true}');
SELECT pg_temp.un('VenC', 'Mosq', 1, 'Tela');
SELECT pg_temp.chico('VenD', 'Mix');
SELECT pg_temp.chico('VenE', 'Base');
SELECT pg_temp.pz('VenE', 'Opc', 2, '{"opcional": true}');
SELECT pg_temp.un('VenE', 'Opc', 1, 'Mix');
SELECT pg_temp.chico('VenF', 'PerfilC');
SELECT pg_temp.colores('VenF', 'Blanco', 'Negro');
SELECT pg_temp.chico('VenG', 'Soldado');
SELECT pg_temp.chico('VenH', 'SoloBorrador');
SELECT pg_temp.chico('VenO', 'Base');
SELECT pg_temp.mete('VenO.Vidrio', 'catalogo_materiales', 'VenO', jsonb_build_object(
  'pieza_id', pg_temp.id('VenO.Unica'), 'orden', 2, 'tipo', 'elige_vendedor', 'nombre', 'Vidrio'));
SELECT pg_temp.op('VenO', 'VenO.Vidrio', 1, 'FloatO', '{"predeterminada": true}');
SELECT pg_temp.op('VenO', 'VenO.Vidrio', 2, 'LamO');
SELECT pg_temp.publicar(v) FROM unnest(ARRAY['VenA','VenB','VenC','VenD','VenE','VenF','VenG','VenO']) AS v;

SELECT pg_temp.caso('baja: Rueda', 'ok', pg_temp.ins_activo('Rueda', false));
SELECT pg_temp.caso('baja: al gerente, con lo que salió', 'Rueda | Salieron de la venta: VenA, VenB | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('baja: en la bandeja', 'Rueda | Salieron de la venta: VenA, VenB | catalogo_insumos | Lucia', pg_temp.listado('Carlos', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('baja: a todos los gerentes', 'Rueda | Salieron de la venta: VenA, VenB | catalogo_insumos | Lucia', pg_temp.bandeja('Gerardo', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('baja: no a quien la hizo', '-', pg_temp.bandeja('Lucia', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('baja de insumo: no a Técnica', '-', pg_temp.bandeja('Martin', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('baja de insumo: no a Administración', '-', pg_temp.bandeja('Ana', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('baja: lleva al insumo', pg_temp.id('Rueda')::text, pg_temp.destino('Carlos', 'catalogo_baja', 'Rueda')::text);
SELECT pg_temp.caso('baja: guarda quién y qué salió', '1 2', (
  SELECT count(*)::text || ' ' || max(cardinality(b.salen))::text FROM catalogo_bajas b
  WHERE b.insumo_id = pg_temp.id('Rueda') AND b.creado_por = pg_temp.id('Lucia')));

SELECT pg_temp.caso('reactivar el insumo', 'ok', pg_temp.ins_activo('Rueda', true));
SELECT pg_temp.caso('insumo reactivado: los paquetes siguen de baja', 'Rueda | Salieron de la venta: VenA, VenB | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('reactivar VenA', 'ok', pg_temp.paq('VenA', true));
SELECT pg_temp.caso('el que se reactiva sale de la lista', 'Rueda | Salieron de la venta: VenB | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('reactivar VenB', 'ok', pg_temp.paq('VenB', true));
SELECT pg_temp.caso('sin nada que decir: desaparece', '-', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Rueda'));

SELECT pg_temp.caso('segunda baja: Rueda', 'ok', pg_temp.ins_activo('Rueda', false));
SELECT pg_temp.caso('segunda baja: un aviso nuevo, y el viejo vuelve a listar lo mismo (costo aceptado)', 'Rueda | Salieron de la venta: VenA, VenB | catalogo_insumos | Lucia // Rueda | Salieron de la venta: VenA, VenB | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Rueda'));
SELECT pg_temp.caso('dejar Rueda activa', 'ok', pg_temp.ins_activo('Rueda', true));
SELECT pg_temp.caso('dejar VenA activo', 'ok', pg_temp.paq('VenA', true));
SELECT pg_temp.caso('dejar VenB activo', 'ok', pg_temp.paq('VenB', true));

SELECT pg_temp.caso('dejan: baja de Tela', 'ok', pg_temp.ins_activo('Tela', false));
SELECT pg_temp.caso('dejan: dice la pieza', 'Tela | Dejaron de ofrecer: VenC (Mosq) | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Tela'));
SELECT pg_temp.caso('dejan: reactivar Tela', 'ok', pg_temp.ins_activo('Tela', true));
SELECT pg_temp.caso('dejan: reactivar lo devuelve y el aviso desaparece', '-', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Tela'));

SELECT pg_temp.caso('dejan: baja de LamO', 'ok', pg_temp.ins_activo('LamO', false));
SELECT pg_temp.caso('dejan: dice la opción', 'LamO | Dejaron de ofrecer: VenO (LamO) | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'LamO'));

SELECT pg_temp.caso('salen y dejan: baja de Mix', 'ok', pg_temp.ins_activo('Mix', false));
SELECT pg_temp.caso('salen y dejan: dice las dos cosas', 'Mix | Salieron de la venta: VenD · Dejaron de ofrecer: VenE (Opc) | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Mix'));

SELECT pg_temp.caso('variante: baja de Negro', 'ok', pg_temp.var_activa('PerfilC', 'Negro', false));
SELECT pg_temp.caso('variante: dice el color', 'PerfilC · Negro | Dejaron de ofrecer: VenF (Negro) | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'PerfilC'));
SELECT pg_temp.caso('variante: baja de Blanco', 'ok', pg_temp.var_activa('PerfilC', 'Blanco', false));
SELECT pg_temp.caso('variante: la última lo sacó de la venta', 'PerfilC · Blanco | Salieron de la venta: VenF | catalogo_insumos | Lucia // PerfilC · Negro | Dejaron de ofrecer: VenF (Negro) | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'PerfilC'));
SELECT pg_temp.caso('variante: reactivar Negro', 'ok', pg_temp.var_activa('PerfilC', 'Negro', true));
SELECT pg_temp.caso('variante: el de Negro desaparece y el de Blanco queda', 'PerfilC · Blanco | Salieron de la venta: VenF | catalogo_insumos | Lucia', pg_temp.bandeja('Carlos', 'catalogo_baja', 'PerfilC'));

SELECT pg_temp.caso('servicio fijo: baja', 'ok', pg_temp.ins_activo('Soldado', false, 'Ana'));
SELECT pg_temp.caso('servicio fijo: al gerente', 'Soldado | Salieron de la venta: VenG | catalogo_fijos | Ana', pg_temp.bandeja('Carlos', 'catalogo_baja', 'Soldado'));
SELECT pg_temp.caso('servicio fijo: a Técnica', 'Soldado | Salieron de la venta: VenG | catalogo_fijos | Ana', pg_temp.bandeja('Lucia', 'catalogo_baja', 'Soldado'));
SELECT pg_temp.caso('servicio fijo: a toda Técnica', 'Soldado | Salieron de la venta: VenG | catalogo_fijos | Ana', pg_temp.bandeja('Martin', 'catalogo_baja', 'Soldado'));
SELECT pg_temp.caso('servicio fijo: no a quien la hizo', '-', pg_temp.bandeja('Ana', 'catalogo_baja', 'Soldado'));
SELECT pg_temp.caso('servicio fijo: no a quien solo carga costos', '-', pg_temp.bandeja('Sofia', 'catalogo_baja', 'Soldado'));

SELECT pg_temp.permiso('Martin', 'catalogo_armar', false);
SELECT pg_temp.caso('servicio fijo: sin armar no lo ve', '-', pg_temp.bandeja('Martin', 'catalogo_baja', 'Soldado'));
SELECT pg_temp.permiso('Martin', 'catalogo_armar', true);

SELECT pg_temp.caso('solo en borrador: baja', 'ok', pg_temp.ins_activo('SoloBorrador', false));
SELECT pg_temp.caso('solo en borrador: no avisa', '-', pg_temp.bandeja('Carlos', 'catalogo_baja', 'SoloBorrador'));
SELECT pg_temp.caso('solo en borrador: no guarda nada', '0', (SELECT count(*)::text FROM catalogo_bajas b WHERE b.insumo_id = pg_temp.id('SoloBorrador')));
SELECT pg_temp.caso('sin uso: baja', 'ok', pg_temp.ins_activo('SinUso', false));
SELECT pg_temp.caso('sin uso: no guarda nada', '0', (SELECT count(*)::text FROM catalogo_bajas b WHERE b.insumo_id = pg_temp.id('SinUso')));

SELECT pg_temp.caso('catalogo_bajas: nadie la lee directo', '42501', pg_temp.consultar('SELECT count(*)::text FROM catalogo_bajas', 'Carlos'));

-- ============================================================
-- Servicios en %
-- ============================================================
SELECT pg_temp.pct('G', 'Garantia', 5, 1, ARRAY['Vidrios']);
SELECT pg_temp.caso('%: alta, al gerente', 'Garantia | Alta: 5 % | catalogo_porcentaje | Ana', pg_temp.bandeja('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia'));
SELECT pg_temp.caso('%: alta, en la bandeja', 'Garantia | Alta: 5 % | catalogo_porcentaje | Ana', pg_temp.listado('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia'));
SELECT pg_temp.caso('%: alta, a todos los gerentes', 'Garantia | Alta: 5 % | catalogo_porcentaje | Ana', pg_temp.bandeja('Gerardo', 'catalogo_porcentaje_cambiado', 'Garantia'));
SELECT pg_temp.caso('%: no a quien lo hizo', '-', pg_temp.bandeja('Ana', 'catalogo_porcentaje_cambiado', 'Garantia'));
SELECT pg_temp.caso('%: no a Técnica', '-', pg_temp.bandeja('Lucia', 'catalogo_porcentaje_cambiado', 'Garantia'));
SELECT pg_temp.caso('%: lleva al servicio', pg_temp.id('G')::text, pg_temp.destino('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia')::text);

SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY['Vidrios']);
SELECT pg_temp.caso('%: el número', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', '5 % → 6 %'));
SELECT pg_temp.caso('%: el anterior dice que hubo otro después', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Alta: 5 % · Hubo otro cambio después'));

SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY['Vidrios','Herrajes']);
SELECT pg_temp.caso('%: suma una categoría', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Suma Herrajes'));
SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY['Vidrios']);
SELECT pg_temp.caso('%: saca una categoría', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Saca Herrajes'));
SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY[]::text[]);
SELECT pg_temp.caso('%: pasa a todo el despiece', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Ahora sobre todo el despiece'));
SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY['Vidrios']);
SELECT pg_temp.caso('%: pasa a ciertas categorías', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Ahora solo sobre Vidrios'));
SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY['Vidrios'], 1000);
SELECT pg_temp.caso('%: el mínimo', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Cambió el mínimo'));
SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY['Vidrios'], 1000, true);
SELECT pg_temp.caso('%: ahora opcional', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Ahora es opcional'));
SELECT pg_temp.pct('G', 'Garantia', 6, 1, ARRAY['Vidrios'], 1000, false);
SELECT pg_temp.caso('%: ya no opcional', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', 'Ya no es opcional'));
SELECT pg_temp.pct('G', 'Garantia', 7, 1, ARRAY['Vidrios'], 1000, true);
SELECT pg_temp.caso('%: varios a la vez', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Garantia', '6 % → 7 % · Ahora es opcional'));

SELECT pg_temp.pct('O', 'Otro', 12.5, 1, ARRAY[]::text[]);
SELECT pg_temp.caso('%: decimales', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Otro', 'Alta: 12,5 %'));
SELECT pg_temp.pct('O', 'Otro', 12.5, 2, ARRAY[]::text[]);
SELECT pg_temp.caso('%: el paso', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Otro', 'Paso 1 → 2'));
SELECT pg_temp.pct('O', 'Otra cosa', 12.5, 2, ARRAY[]::text[]);
SELECT pg_temp.caso('%: el nombre', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Otra cosa', 'Se llamaba Otro'));
SELECT pg_temp.activar('O', false);
SELECT pg_temp.caso('%: de baja', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Otra cosa', 'De baja'));
SELECT pg_temp.activar('O', true);
SELECT pg_temp.caso('%: reactivado', '1', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Otra cosa', 'Reactivado'));

CREATE TEMP TABLE antes ON COMMIT DROP AS
  SELECT count(*) AS n FROM usuario_notificaciones WHERE tipo = 'catalogo_porcentaje_cambiado' AND usuario_id = pg_temp.id('Carlos');
SELECT pg_temp.pct('O', 'Otra cosa', 12.5, 2, ARRAY[]::text[]);
SELECT pg_temp.caso('%: sin cambios no avisa', (SELECT n::text FROM antes), (
  SELECT count(*)::text FROM usuario_notificaciones WHERE tipo = 'catalogo_porcentaje_cambiado' AND usuario_id = pg_temp.id('Carlos')));

SELECT pg_temp.pct('R', 'Rev', 5, 1, ARRAY[]::text[]);
SELECT pg_temp.pct('R', 'Rev', 6, 1, ARRAY[]::text[]);
SELECT pg_temp.revertir('R');
SELECT pg_temp.caso('revertido: a quien hizo el cambio', 'Rev | 6 % → 5 % | catalogo_porcentaje | Carlos', pg_temp.bandeja('Ana', 'catalogo_porcentaje_revertido', 'Rev'));
SELECT pg_temp.caso('revertido: en la bandeja', 'Rev | 6 % → 5 % | catalogo_porcentaje | Carlos', pg_temp.listado('Ana', 'catalogo_porcentaje_revertido', 'Rev'));
SELECT pg_temp.caso('revertido: no a quien revirtió', '-', pg_temp.bandeja('Carlos', 'catalogo_porcentaje_revertido', 'Rev'));
SELECT pg_temp.caso('revertido: es un cambio más para otro gerente', '1', pg_temp.cuenta('Gerardo', 'catalogo_porcentaje_cambiado', 'Rev', '6 % → 5 %'));
SELECT pg_temp.caso('revertido: el cambio revertido dice que hubo otro después', '1', pg_temp.cuenta('Gerardo', 'catalogo_porcentaje_cambiado', 'Rev', '5 % → 6 % · Hubo otro cambio después'));
SELECT pg_temp.caso('revertido: quien revirtió no se avisa a sí mismo', '0', pg_temp.cuenta('Carlos', 'catalogo_porcentaje_cambiado', 'Rev', '6 % → 5 %'));

SELECT pg_temp.pct('H', 'DeGerente', 5, 1, ARRAY[]::text[], NULL, false, 'Gerardo');
SELECT pg_temp.pct('H', 'DeGerente', 6, 1, ARRAY[]::text[], NULL, false, 'Gerardo');
SELECT pg_temp.revertir('H');
SELECT pg_temp.caso('revertido a un gerente: le llega la reversión', 'DeGerente | 6 % → 5 % | catalogo_porcentaje | Carlos', pg_temp.bandeja('Gerardo', 'catalogo_porcentaje_revertido', 'DeGerente'));
SELECT pg_temp.caso('revertido a un gerente: un solo aviso', '0', pg_temp.cuenta('Gerardo', 'catalogo_porcentaje_cambiado', 'DeGerente', '6 % → 5 %'));

SELECT pg_temp.pct('N', 'Nuevo', 5, 1, ARRAY[]::text[]);
SELECT pg_temp.revertir('N');
SELECT pg_temp.caso('revertir el alta: queda de baja', 'Nuevo | De baja | catalogo_porcentaje | Carlos', pg_temp.bandeja('Ana', 'catalogo_porcentaje_revertido', 'Nuevo'));

SELECT pg_temp.permiso('Ana', 'catalogo_porcentajes', false);
SELECT pg_temp.caso('revertido: sin la vista no lo ve', '-', pg_temp.bandeja('Ana', 'catalogo_porcentaje_revertido', 'Rev'));
SELECT pg_temp.permiso('Ana', 'catalogo_porcentajes', true);
SELECT pg_temp.permiso('Gerardo', 'catalogo_aprobar', false);
SELECT pg_temp.caso('cambiado: sin aprobar no lo ve', '-', pg_temp.bandeja('Gerardo', 'catalogo_porcentaje_cambiado', 'Rev'));
SELECT pg_temp.permiso('Gerardo', 'catalogo_aprobar', true);

-- ============================================================
-- El ciclo de una versión
-- ============================================================
SELECT pg_temp.chico('VenV', 'Rueda');
SELECT pg_temp.caso('enviar', 'ok', pg_temp.fn('enviar', 'VenV', 'Lucia'));
SELECT pg_temp.caso('enviada: al gerente', 'VenV · v1 | catalogo_version | Lucia', pg_temp.bandeja('Carlos', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.caso('enviada: en la bandeja', 'VenV · v1 | catalogo_version | Lucia', pg_temp.listado('Carlos', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.caso('enviada: a todos los que aprueban', 'VenV · v1 | catalogo_version | Lucia', pg_temp.bandeja('Gerardo', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.caso('enviada: no a quien la envió', '-', pg_temp.bandeja('Lucia', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.caso('enviada: no a toda Técnica', '-', pg_temp.bandeja('Martin', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.caso('enviada: lleva a la versión', pg_temp.id('VenV')::text, pg_temp.destino('Carlos', 'catalogo_version_enviada', 'VenV')::text);

SELECT pg_temp.permiso('Gerardo', 'catalogo_aprobar', false);
SELECT pg_temp.caso('enviada: sin aprobar no la ve', '-', pg_temp.bandeja('Gerardo', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.permiso('Gerardo', 'catalogo_aprobar', true);

SELECT pg_temp.caso('retirar', 'ok', pg_temp.fn('retirar', 'VenV', 'Lucia'));
SELECT pg_temp.caso('retirada: desaparece', '-', pg_temp.bandeja('Carlos', 'catalogo_version_enviada', 'VenV'));

SELECT pg_temp.caso('reenviar', 'ok', pg_temp.fn('enviar', 'VenV', 'Martin'));
SELECT pg_temp.caso('reenviada: un solo aviso, el nuevo', 'VenV · v1 | catalogo_version | Martin', pg_temp.bandeja('Carlos', 'catalogo_version_enviada', 'VenV'));

SELECT pg_temp.caso('devolver', 'ok', pg_temp.fn('devolver', 'VenV', 'Carlos', ', ''Falta el mosquitero'''));
SELECT pg_temp.caso('devuelta: desaparece para el otro gerente', '-', pg_temp.bandeja('Gerardo', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.caso('devuelta: a quien la envió, con el motivo', 'VenV · v1 | Falta el mosquitero | catalogo_version | Carlos', pg_temp.bandeja('Martin', 'catalogo_version_devuelta', 'VenV'));
SELECT pg_temp.caso('devuelta: en la bandeja', 'VenV · v1 | Falta el mosquitero | catalogo_version | Carlos', pg_temp.listado('Martin', 'catalogo_version_devuelta', 'VenV'));
SELECT pg_temp.caso('devuelta: no a quien la envió antes', '-', pg_temp.bandeja('Lucia', 'catalogo_version_devuelta', 'VenV'));

SELECT pg_temp.caso('enviar de nuevo', 'ok', pg_temp.fn('enviar', 'VenV', 'Lucia'));
SELECT pg_temp.caso('aprobar', 'ok', pg_temp.fn('aprobar', 'VenV', 'Gerardo'));
SELECT pg_temp.caso('aprobada: desaparece el pedido', '-', pg_temp.bandeja('Carlos', 'catalogo_version_enviada', 'VenV'));
SELECT pg_temp.caso('aprobada: al último que la envió', 'VenV · v1 | catalogo_version | Gerardo', pg_temp.bandeja('Lucia', 'catalogo_version_aprobada', 'VenV'));
SELECT pg_temp.caso('aprobada: en la bandeja', 'VenV · v1 | catalogo_version | Gerardo', pg_temp.listado('Lucia', 'catalogo_version_aprobada', 'VenV'));
SELECT pg_temp.caso('aprobada: no al que la envió antes', '-', pg_temp.bandeja('Martin', 'catalogo_version_aprobada', 'VenV'));
SELECT pg_temp.caso('aprobada: lleva a la versión', pg_temp.id('VenV')::text, pg_temp.destino('Lucia', 'catalogo_version_aprobada', 'VenV')::text);

SELECT pg_temp.permiso('Lucia', 'catalogo_paquetes', false);
SELECT pg_temp.caso('aprobada: sin la vista no la ve', '-', pg_temp.bandeja('Lucia', 'catalogo_version_aprobada', 'VenV'));
SELECT pg_temp.permiso('Lucia', 'catalogo_paquetes', true);

SELECT pg_temp.crear('VenV2', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('VenV')));
SELECT pg_temp.caso('enviar v2', 'ok', pg_temp.fn('enviar', 'VenV2', 'Martin'));
SELECT pg_temp.caso('aprobar v2', 'ok', pg_temp.fn('aprobar', 'VenV2', 'Carlos'));
SELECT pg_temp.caso('v2 aprobada: a quien la envió', 'VenV · v2 | catalogo_version | Carlos', pg_temp.bandeja('Martin', 'catalogo_version_aprobada', 'VenV'));
SELECT pg_temp.caso('obsoleta: la v1 no suma avisos', 'VenV · v1 | catalogo_version | Gerardo', pg_temp.bandeja('Lucia', 'catalogo_version_aprobada', 'VenV'));

SELECT pg_temp.crear('VenV3', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('VenV')));
SELECT pg_temp.caso('descartar', 'ok', pg_temp.fn('descartar', 'VenV3', 'Lucia'));
SELECT pg_temp.caso('descartada: no avisa', '0', (
  SELECT count(*)::text FROM usuario_notificaciones n
  JOIN catalogo_versiones_historia h ON h.id = n.entidad_id
  WHERE h.version_id = pg_temp.id('VenV3')));

-- ============================================================
-- Solo los propios, y privilegios
-- ============================================================
SELECT pg_temp.caso('catalogo_avisos: solo los propios', '0', pg_temp.consultar('SELECT count(*)::text FROM catalogo_avisos()', 'Juan'));
SELECT pg_temp.caso('catalogo_avisos: Juan no ve los de otro en la bandeja', '-', pg_temp.bandeja('Juan', 'catalogo_baja', 'Rueda'));

SELECT pg_temp.caso('catalogo_avisos: la pueden llamar los logueados', 'true', has_function_privilege('authenticated', 'catalogo_avisos()', 'EXECUTE')::text);
SELECT pg_temp.caso('catalogo_avisos: anon no', 'false', has_function_privilege('anon', 'catalogo_avisos()', 'EXECUTE')::text);
SELECT pg_temp.caso(f || ': sin EXECUTE', 'false', has_function_privilege('authenticated', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_variantes_avisar()', 'catalogo_categorias_avisar()', 'catalogo_porcentajes_valores_avisar()',
                  'catalogo_versiones_historia_avisar()', 'catalogo_porcentaje_cambio(uuid)', 'catalogo_baja_cascada()']) AS f;
SELECT pg_temp.caso('catalogo_bajas: RLS', 'true', (SELECT c.relrowsecurity::text FROM pg_class c WHERE c.oid = 'public.catalogo_bajas'::regclass));

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
