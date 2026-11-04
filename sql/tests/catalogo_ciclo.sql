-- Verificación de sql/162: el ciclo de una versión, lo que se ofrece, las bajas en cascada, el aviso previo y la
-- reactivación. NO es una migración: todo corre dentro de una transacción que revierte. Termina en un DO que lanza
-- "N / M ok" y los casos que fallan.
--
-- Mundo: Lucia (Técnica: Paquetes con armar, Insumos con cargar), Ana (Administración: Insumos con costos, Servicios fijos
-- con editar), Carlos (gerente: Paquetes con aprobar), Marta (Insumos con cargar, sin Paquetes), Rodrigo (solo Paquetes,
-- revisa cortes) y Juan (nada). Lo creado lleva Zqx162.

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

-- Lo mismo, pero devuelve el texto del error.
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
  RETURN SQLERRM;
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

CREATE FUNCTION pg_temp.ver(p_v text, p_categoria text DEFAULT 'Ventanas') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_v, format('SELECT catalogo_paquete_alta(%L, %s)', 'Zqx162 ' || p_v, pg_temp.l(p_categoria)));
$f$;

CREATE FUNCTION pg_temp.pz(p_v text, p_nombre text, p_orden int, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_piezas', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden) || p_extra);
$f$;

CREATE FUNCTION pg_temp.vr(p_v text, p_nombre text, p_orden int, p_formula text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_variables', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden, 'formula', p_formula) || p_extra);
$f$;

CREATE FUNCTION pg_temp.en(p_v text, p_nombre text, p_orden int, p_min numeric, p_max numeric, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_nombre, 'catalogo_variables', p_v,
    jsonb_build_object('nombre', p_nombre, 'orden', p_orden, 'ingresa_vendedor', true, 'minimo', p_min, 'maximo', p_max) || p_extra);
$f$;

CREATE FUNCTION pg_temp.un(p_v text, p_pieza text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_insumo || '.' || p_orden, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', 'unico',
                       'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.mu(p_v text, p_pieza text, p_orden int, p_tipo text, p_nombre text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_v || '.' || p_pieza || '.' || p_nombre, 'catalogo_materiales', p_v,
    jsonb_build_object('pieza_id', pg_temp.id(p_v || '.' || p_pieza), 'orden', p_orden, 'tipo', p_tipo, 'nombre', p_nombre) || p_extra);
$f$;

CREATE FUNCTION pg_temp.op(p_v text, p_material text, p_orden int, p_insumo text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_insumo, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden, 'insumo_id', pg_temp.id(p_insumo)) || p_extra);
$f$;

CREATE FUNCTION pg_temp.pareja(p_v text, p_material text, p_orden int, p_de text, p_insumo text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(p_material || '.' || p_de, 'catalogo_opciones', p_v,
    jsonb_build_object('material_id', pg_temp.id(p_material), 'orden', p_orden,
                       'sigue_opcion_id', pg_temp.id(p_de), 'insumo_id', pg_temp.id(p_insumo)));
$f$;

CREATE FUNCTION pg_temp.co(p_v text, p_col text, p_clave text, p_condicion text, p_bloquea boolean DEFAULT false) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.mete(NULL, 'catalogo_condiciones', p_v, jsonb_build_object(
    p_col, pg_temp.id(p_clave), 'condicion', p_condicion, 'mensaje', 'Aviso', 'bloquea', p_bloquea));
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

CREATE FUNCTION pg_temp.insumo(p_nombre text, p_categoria text, p_unidad text, p_peso text DEFAULT 'NULL', p_espesor text DEFAULT 'NULL')
RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, %s, %s)',
    'Zqx162 ' || p_nombre, pg_temp.l(p_categoria), p_unidad, p_peso, p_espesor));
$f$;

CREATE FUNCTION pg_temp.con_color(p_nombre text, p_categoria text, p_unidad text, p_peso numeric, VARIADIC p_colores text[]) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('SELECT catalogo_insumo_alta(%L, %s, %L, %s, NULL, ARRAY[%s]::uuid[])',
    'Zqx162 ' || p_nombre, pg_temp.l(p_categoria), p_unidad, p_peso,
    (SELECT string_agg(pg_temp.l(c), ', ') FROM unnest(p_colores) c)));
$f$;

CREATE FUNCTION pg_temp.categoria(p_nombre text, p_tipo text, p_como text DEFAULT 'Lucia') RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.crear(p_nombre, format('INSERT INTO catalogo_categorias (tipo, nombre) VALUES (%L, %L) RETURNING id',
    p_tipo, 'Zqx162 ' || p_nombre), p_como);
$f$;

-- Le pone costo a cada variante activa que no tenga, o solo a la de ese color.
CREATE FUNCTION pg_temp.costear(p_insumo text, p_solo_color text DEFAULT NULL) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por)
  SELECT va.id, 100, 'ARS'::moneda, pg_temp.id('Ana')
  FROM catalogo_variantes va
  WHERE va.insumo_id = pg_temp.id(p_insumo) AND va.activo
    AND (p_solo_color IS NULL OR va.color_id = pg_temp.id(p_solo_color))
    AND NOT EXISTS (SELECT 1 FROM catalogo_costos k WHERE k.variante_id = va.id);
$f$;

CREATE FUNCTION pg_temp.frena(p_v text, p_como text DEFAULT 'Rodrigo') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT array_to_string(catalogo_version_revisar(%s), %L)', pg_temp.l(p_v), ' | '), p_como);
$f$;

CREATE FUNCTION pg_temp.dice(p_v text, p_texto text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.frena(p_v);
BEGIN
  PERFORM pg_temp.caso(p_v || ' dice: ' || p_texto, 'sí', CASE WHEN position(p_texto IN v) > 0 THEN 'sí' ELSE v END);
END;
$f$;

CREATE FUNCTION pg_temp.no_dice(p_v text, p_texto text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := pg_temp.frena(p_v);
BEGIN
  PERFORM pg_temp.caso(p_v || ' no dice: ' || p_texto, 'no', CASE WHEN position(p_texto IN v) > 0 THEN v ELSE 'no' END);
END;
$f$;

CREATE FUNCTION pg_temp.limpia(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso(p_v || ' no frena', '', pg_temp.frena(p_v));
$f$;

CREATE FUNCTION pg_temp.fn(p_fn text, p_v text, p_como text, p_extra text DEFAULT '') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('SELECT catalogo_version_%s(%s%s)', p_fn, pg_temp.l(p_v), p_extra), p_como);
$f$;

CREATE FUNCTION pg_temp.estado(p_v text) RETURNS text LANGUAGE sql AS $f$
  SELECT estado::text FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

CREATE FUNCTION pg_temp.historia(p_v text) RETURNS text LANGUAGE sql AS $f$
  SELECT string_agg(h.accion::text || coalesce(':' || h.motivo, ''), ',' ORDER BY h.accion::text, h.motivo)
  FROM catalogo_versiones_historia h WHERE h.version_id = pg_temp.id(p_v);
$f$;

CREATE FUNCTION pg_temp.publicar(p_v text) RETURNS void LANGUAGE sql AS $f$
  SELECT pg_temp.caso('enviar ' || p_v, 'ok', pg_temp.fn('enviar', p_v, 'Lucia'));
  SELECT pg_temp.caso('aprobar ' || p_v, 'ok', pg_temp.fn('aprobar', p_v, 'Carlos'));
$f$;

CREATE FUNCTION pg_temp.paquete(p_v text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT paquete_id FROM catalogo_versiones WHERE id = pg_temp.id(p_v);
$f$;

-- Da de baja o reactiva. Sin permiso de RLS no toca ninguna fila y da 'ok': lo que importa se mira después.
CREATE FUNCTION pg_temp.paq(p_v text, p_activo boolean, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE catalogo_paquetes SET activo = %L WHERE id = %L', p_activo, pg_temp.paquete(p_v)), p_como);
$f$;

CREATE FUNCTION pg_temp.ins_activo(p_insumo text, p_activo boolean, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE catalogo_insumos SET activo = %L WHERE id = %s', p_activo, pg_temp.l(p_insumo)), p_como);
$f$;

CREATE FUNCTION pg_temp.variante(p_insumo text, p_color text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM catalogo_variantes WHERE insumo_id = pg_temp.id(p_insumo) AND color_id = pg_temp.id(p_color);
$f$;

CREATE FUNCTION pg_temp.var_activa(p_insumo text, p_color text, p_activo boolean, p_como text DEFAULT 'Lucia') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.intentar(format('UPDATE catalogo_variantes SET activo = %L WHERE id = %L', p_activo, pg_temp.variante(p_insumo, p_color)), p_como);
$f$;

CREATE FUNCTION pg_temp.causa(p_v text) RETURNS text LANGUAGE sql AS $f$
  SELECT CASE
    WHEN q.activo THEN 'activo'
    WHEN q.baja_insumo_id IS NOT NULL THEN i.nombre
    WHEN q.baja_variante_id IS NOT NULL THEN vi.nombre || ' · ' || c.nombre
    ELSE 'a mano' END
  FROM catalogo_versiones v
  JOIN catalogo_paquetes q ON q.id = v.paquete_id
  LEFT JOIN catalogo_insumos i ON i.id = q.baja_insumo_id
  LEFT JOIN catalogo_variantes va ON va.id = q.baja_variante_id
  LEFT JOIN catalogo_insumos vi ON vi.id = va.insumo_id
  LEFT JOIN catalogo_colores c ON c.id = va.color_id
  WHERE v.id = pg_temp.id(p_v);
$f$;

-- "armable | piezas que no se ofrecen | opciones que no se ofrecen" en un color.
CREATE FUNCTION pg_temp.ofrece(p_v text, p_color text, p_como text DEFAULT 'Rodrigo') RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format($q$
    SELECT o.armable::text
      || ' | ' || coalesce((SELECT string_agg(p.nombre, ',' ORDER BY p.nombre) FROM catalogo_piezas p WHERE p.id = ANY (o.piezas_fuera)), '-')
      || ' | ' || coalesce((SELECT string_agg(i.nombre, ',' ORDER BY i.nombre) FROM catalogo_opciones x
                            JOIN catalogo_insumos i ON i.id = x.insumo_id WHERE x.id = ANY (o.opciones_fuera)), '-')
    FROM catalogo_version_oferta(%s) o
    WHERE o.color IS NOT DISTINCT FROM %L
  $q$, pg_temp.l(p_v), 'Zqx162 ' || p_color), p_como);
$f$;

CREATE FUNCTION pg_temp.aviso(p_insumo text, p_variante uuid, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT catalogo_baja_aviso(%s, %L)::text', pg_temp.l(p_insumo), p_variante), p_como);
$f$;

-- El aviso con solo salen y dejan: lo que ve quien no tiene la vista Paquetes.
CREATE FUNCTION pg_temp.solo_numeros(p_salen int, p_dejan int) RETURNS text LANGUAGE sql AS $f$
  SELECT jsonb_build_object('salen', p_salen, 'dejan', p_dejan)::text;
$f$;

CREATE FUNCTION pg_temp.con_nombres(p_salen text[], p_dejan jsonb DEFAULT '[]') RETURNS text LANGUAGE sql AS $f$
  SELECT jsonb_build_object('salen', cardinality(p_salen), 'dejan', jsonb_array_length(p_dejan),
    'salen_nombres', to_jsonb(p_salen), 'dejan_detalle', p_dejan)::text;
$f$;

CREATE FUNCTION pg_temp.deja(p_v text, p_colores text[], p_piezas text[], p_opciones text[]) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT jsonb_build_object('nombre', 'Zqx162 ' || p_v, 'colores', to_jsonb(p_colores), 'piezas', to_jsonb(p_piezas), 'opciones', to_jsonb(p_opciones));
$f$;

-- Un paquete que pasa todo: el ejemplo de decisiones/catalogo. El Mosquitero y la Manija Premium son solo blancos.
CREATE FUNCTION pg_temp.armar(p_v text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v text := p_v || '.Hoja.';
BEGIN
  PERFORM pg_temp.ver(p_v);
  PERFORM pg_temp.colores(p_v, 'Blanco', 'Negro');
  PERFORM pg_temp.en(p_v, 'ancho', 1, 300, 3000);
  PERFORM pg_temp.en(p_v, 'alto', 2, 300, 3000);
  PERFORM pg_temp.pz(p_v, 'Marco', 1);
  PERFORM pg_temp.un(p_v, 'Marco', 1, 'PerfilMarco', '{"medida": "ancho", "cantidad": "2"}');
  PERFORM pg_temp.un(p_v, 'Marco', 2, 'Escuadra', '{"cantidad": "4"}');
  PERFORM pg_temp.un(p_v, 'Marco', 3, 'Soldado', '{"cantidad": "4"}');
  PERFORM pg_temp.pz(p_v, 'Hoja', 2, '{"cantidad": "2", "calcula_espesor": true}');
  PERFORM pg_temp.un(p_v, 'Hoja', 1, 'PerfilHoja', '{"medida": "alto", "cantidad": "2"}');
  PERFORM pg_temp.mu(p_v, 'Hoja', 2, 'elige_vendedor', 'Vidrio', '{"ancho": "ancho − 48", "alto": "alto − 48", "cuenta_espesor": true}');
  PERFORM pg_temp.op(p_v, v || 'Vidrio', 1, 'Float', '{"predeterminada": true}');
  PERFORM pg_temp.op(p_v, v || 'Vidrio', 2, 'Laminado');
  PERFORM pg_temp.op(p_v, v || 'Vidrio', 3, 'DVH');
  PERFORM pg_temp.mu(p_v, 'Hoja', 3, 'sigue', 'Contravidrio', jsonb_build_object(
    'sigue_material_id', pg_temp.id(v || 'Vidrio'), 'medida', 'ancho', 'cuenta_peso', false));
  PERFORM pg_temp.pareja(p_v, v || 'Contravidrio', 1, v || 'Vidrio.Float', 'Contra4');
  PERFORM pg_temp.pareja(p_v, v || 'Contravidrio', 2, v || 'Vidrio.Laminado', 'Contra6');
  PERFORM pg_temp.pareja(p_v, v || 'Contravidrio', 3, v || 'Vidrio.DVH', NULL);
  PERFORM pg_temp.mu(p_v, 'Hoja', 4, 'elige_sistema', 'Rueda', jsonb_build_object(
    'eleccion', 'si [peso Hoja] > 40 entonces [Zqx162 Rueda80] si no [Zqx162 Rueda40]', 'cantidad', '2', 'cuenta_peso', false));
  PERFORM pg_temp.op(p_v, v || 'Rueda', 1, 'Rueda40');
  PERFORM pg_temp.op(p_v, v || 'Rueda', 2, 'Rueda80');
  PERFORM pg_temp.mu(p_v, 'Hoja', 5, 'elige_vendedor', 'Manija');
  PERFORM pg_temp.op(p_v, v || 'Manija', 1, 'ManijaEstandar', '{"predeterminada": true}');
  PERFORM pg_temp.op(p_v, v || 'Manija', 2, 'ManijaPremium');
  PERFORM pg_temp.pz(p_v, 'Mosquitero', 3, '{"opcional": true}');
  PERFORM pg_temp.un(p_v, 'Mosquitero', 1, 'Tela', '{"ancho": "ancho", "alto": "alto"}');
  PERFORM pg_temp.un(p_v, 'Mosquitero', 2, 'PerfilMosq', '{"medida": "ancho"}');
  PERFORM pg_temp.pz(p_v, 'Cajon', 4, '{"opcional": true}');
  PERFORM pg_temp.un(p_v, 'Cajon', 1, 'Enrollable');
  PERFORM pg_temp.pz(p_v, 'Cortina', 5, jsonb_build_object('opcional', true, 'requiere_pieza_id', pg_temp.id(p_v || '.Cajon')));
  PERFORM pg_temp.un(p_v, 'Cortina', 1, 'Felpa', '{"medida": "ancho"}');
  PERFORM pg_temp.pz(p_v, 'Colocacion', 6);
  PERFORM pg_temp.un(p_v, 'Colocacion', 1, 'Instalacion');
  PERFORM pg_temp.mete(p_v || '.caso', 'catalogo_casos', p_v, '{"nombre": "base", "entrada": {"variables": {"ancho": 1500, "alto": 1200}}}');
END;
$f$;

-- Lo mínimo que se puede enviar: una pieza con un insumo y un caso.
CREATE FUNCTION pg_temp.chico(p_v text, p_insumo text DEFAULT 'Chico', p_categoria text DEFAULT 'Ventanas') RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM pg_temp.ver(p_v, p_categoria);
  PERFORM pg_temp.pz(p_v, 'Unica', 1);
  PERFORM pg_temp.un(p_v, 'Unica', 1, p_insumo);
  PERFORM pg_temp.mete(p_v || '.caso', 'catalogo_casos', p_v, '{"nombre": "base"}');
END;
$f$;

-- ============================================================
-- Montaje
-- ============================================================
INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Lucia','Ana','Carlos','Marta','Rodrigo','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND modulo = 'catalogo';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test162.local', jsonb_build_object('nombre', 'test162 ' || nombre)
FROM ids WHERE nombre IN ('Lucia','Ana','Carlos','Marta','Rodrigo','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'), ('Lucia','catalogo_cargar'),
  ('Ana','catalogo_insumos'), ('Ana','catalogo_costos'), ('Ana','catalogo_fijos'), ('Ana','catalogo_fijos_editar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar'),
  ('Marta','catalogo_insumos'), ('Marta','catalogo_cargar'),
  ('Rodrigo','catalogo_paquetes')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.categoria('Perfiles', 'insumo');
SELECT pg_temp.categoria('Vidrios', 'insumo');
SELECT pg_temp.categoria('Ventanas', 'paquete');
SELECT pg_temp.categoria('Puertas', 'paquete');
SELECT pg_temp.categoria('Manos', 'servicio', 'Ana');

SELECT pg_temp.crear('Blanco', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx162 Blanco') RETURNING id$q$);
SELECT pg_temp.crear('Negro', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx162 Negro') RETURNING id$q$);
SELECT pg_temp.crear('Rojo', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx162 Rojo') RETURNING id$q$);
SELECT pg_temp.crear('Verde', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx162 Verde') RETURNING id$q$);

SELECT pg_temp.con_color('PerfilMarco', 'Perfiles', 'mm', 0.9, 'Blanco', 'Negro');
SELECT pg_temp.con_color('PerfilHoja', 'Perfiles', 'mm', 0.7, 'Blanco', 'Negro');
SELECT pg_temp.con_color('PerfilMosq', 'Perfiles', 'mm', 0.3, 'Blanco');
SELECT pg_temp.con_color('ManijaEstandar', 'Perfiles', 'u', 0.1, 'Blanco', 'Negro');
SELECT pg_temp.con_color('ManijaPremium', 'Perfiles', 'u', 0.1, 'Blanco');
SELECT pg_temp.con_color('ColorSin', 'Perfiles', 'u', 0.1, 'Blanco', 'Negro', 'Rojo');
SELECT pg_temp.insumo('Escuadra', 'Perfiles', 'u', '0.02');
SELECT pg_temp.insumo('Rueda40', 'Perfiles', 'u', '0.05');
SELECT pg_temp.insumo('Rueda80', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('Enrollable', 'Perfiles', 'u', '2');
SELECT pg_temp.insumo('Felpa', 'Perfiles', 'mm', '0');
SELECT pg_temp.insumo('Contra4', 'Perfiles', 'mm', '0.2');
SELECT pg_temp.insumo('Contra6', 'Perfiles', 'mm', '0.2');
SELECT pg_temp.insumo('Curvo', 'Perfiles', 'mm', '0.9');
SELECT pg_temp.insumo('Tirador', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('Chico', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('SoloV1', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('Suelto', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('Viejo', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('SinCosto', 'Perfiles', 'u', '0.1');
SELECT pg_temp.insumo('SinPeso', 'Perfiles', 'u');
SELECT pg_temp.insumo('Float', 'Vidrios', 'm2', '10', '4');
SELECT pg_temp.insumo('Laminado', 'Vidrios', 'm2', '15', '6');
SELECT pg_temp.insumo('DVH', 'Vidrios', 'm2', '20', '20');
SELECT pg_temp.insumo('Tela', 'Vidrios', 'm2', '1');
SELECT pg_temp.crear('Soldado', format($q$SELECT catalogo_fijo_alta('Zqx162 Soldado', %s, 'u', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');
SELECT pg_temp.crear('Instalacion', format($q$SELECT catalogo_fijo_alta('Zqx162 Instalacion', %s, 'u', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');
SELECT pg_temp.crear('ServM2', format($q$SELECT catalogo_fijo_alta('Zqx162 ServM2', %s, 'm2', 1000, 'ARS')$q$, pg_temp.l('Manos')), 'Ana');

SELECT pg_temp.costear(n) FROM unnest(ARRAY['PerfilMarco','PerfilHoja','PerfilMosq','ManijaEstandar','ManijaPremium','Escuadra',
  'Rueda40','Rueda80','Enrollable','Felpa','Contra4','Contra6','Curvo','Tirador','Chico','SoloV1','Suelto','Viejo','SinPeso',
  'Float','Laminado','DVH','Tela']) AS n;
SELECT pg_temp.costear('ColorSin', 'Blanco');

-- ============================================================
-- 1. El paquete de ejemplo pasa, y cada cosa de la lista frena
-- ============================================================
SELECT pg_temp.armar('V1');
SELECT pg_temp.limpia('V1');

SELECT pg_temp.ver('Vacia');
SELECT pg_temp.dice('Vacia', 'El paquete está vacío');
SELECT pg_temp.dice('Vacia', 'La versión no tiene casos de prueba');

-- De baja y sin costo, con colores
SELECT pg_temp.ver('M');
SELECT pg_temp.colores('M', 'Blanco', 'Negro');
SELECT pg_temp.pz('M', 'P1', 1);
SELECT pg_temp.dice('M', 'P1: la pieza no tiene materiales');
SELECT pg_temp.no_dice('M', 'El paquete está vacío');
SELECT pg_temp.pz('M', 'P2', 2);
SELECT pg_temp.un('M', 'P2', 1, 'Viejo');
SELECT pg_temp.caso('01 baja de Viejo, sin nada publicado', 'ok', pg_temp.ins_activo('Viejo', false));
SELECT pg_temp.dice('M', 'Zqx162 Viejo está de baja');
SELECT pg_temp.un('M', 'P2', 2, 'SinCosto');
SELECT pg_temp.dice('M', 'Zqx162 SinCosto no tiene costo');
SELECT pg_temp.un('M', 'P2', 3, 'ColorSin');
SELECT pg_temp.dice('M', 'Zqx162 ColorSin · Zqx162 Negro no tiene costo');
SELECT pg_temp.no_dice('M', 'Zqx162 ColorSin · Zqx162 Blanco no tiene costo');
SELECT pg_temp.no_dice('M', 'Zqx162 ColorSin · Zqx162 Rojo');
SELECT pg_temp.no_dice('M', 'Zqx162 Soldado');

-- Medidas
SELECT pg_temp.ver('Me');
SELECT pg_temp.pz('Me', 'P', 1);
SELECT pg_temp.un('Me', 'P', 1, 'Felpa');
SELECT pg_temp.dice('Me', 'Zqx162 Felpa: falta la medida');
SELECT pg_temp.un('Me', 'P', 2, 'Float', '{"ancho": "100"}');
SELECT pg_temp.dice('Me', 'Zqx162 Float: falta el ancho o el alto');
SELECT pg_temp.un('Me', 'P', 3, 'Laminado', '{"area": "100"}');
SELECT pg_temp.dice('Me', 'Zqx162 Laminado: falta el ancho o el alto');
SELECT pg_temp.un('Me', 'P', 4, 'ServM2');
SELECT pg_temp.dice('Me', 'Zqx162 ServM2: falta el área');
SELECT pg_temp.un('Me', 'P', 5, 'Escuadra');
SELECT pg_temp.no_dice('Me', 'Zqx162 Escuadra: falta');
SELECT pg_temp.pz('Me', 'Q', 2);
SELECT pg_temp.mu('Me', 'Q', 1, 'elige_vendedor', 'MultiMm', '{"medida": "100"}');
SELECT pg_temp.op('Me', 'Me.Q.MultiMm', 1, 'Curvo');
SELECT pg_temp.mu('Me', 'Q', 2, 'elige_vendedor', 'MultiM2', '{"medida": "100"}');
SELECT pg_temp.op('Me', 'Me.Q.MultiM2', 1, 'DVH');
SELECT pg_temp.mu('Me', 'Q', 3, 'elige_vendedor', 'MultiU', '{"medida": "100"}');
SELECT pg_temp.op('Me', 'Me.Q.MultiU', 1, 'Tirador');
SELECT pg_temp.no_dice('Me', 'MultiMm (Zqx162 Curvo)');
SELECT pg_temp.dice('Me', 'MultiM2 (Zqx162 DVH): falta el ancho o el alto');
SELECT pg_temp.no_dice('Me', 'MultiU (Zqx162 Tirador)');

SELECT pg_temp.chico('Me2', 'ServM2');
SELECT pg_temp.dice('Me2', 'Zqx162 ServM2: falta el área');
SELECT pg_temp.caso('01 un servicio en m2 lleva solo el área', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_materiales SET area = '100' WHERE id = %s$q$, pg_temp.l('Me2.Unica.ServM2.1')), 'Lucia'));
SELECT pg_temp.limpia('Me2');

-- Parejas
SELECT pg_temp.ver('Pa');
SELECT pg_temp.pz('Pa', 'P', 1);
SELECT pg_temp.mu('Pa', 'P', 1, 'elige_vendedor', 'Vid', '{"ancho": "10", "alto": "10"}');
SELECT pg_temp.op('Pa', 'Pa.P.Vid', 1, 'Float');
SELECT pg_temp.op('Pa', 'Pa.P.Vid', 2, 'Laminado');
SELECT pg_temp.op('Pa', 'Pa.P.Vid', 3, 'DVH');
SELECT pg_temp.mu('Pa', 'P', 2, 'sigue', 'Cv', jsonb_build_object('sigue_material_id', pg_temp.id('Pa.P.Vid'), 'medida', '10'));
SELECT pg_temp.pareja('Pa', 'Pa.P.Cv', 1, 'Pa.P.Vid.Float', 'Contra4');
SELECT pg_temp.pareja('Pa', 'Pa.P.Cv', 2, 'Pa.P.Vid.DVH', NULL);
SELECT pg_temp.dice('Pa', 'Cv: falta la pareja de Zqx162 Laminado');
SELECT pg_temp.no_dice('Pa', 'Cv: falta la pareja de Zqx162 Float');
SELECT pg_temp.no_dice('Pa', 'Cv: falta la pareja de Zqx162 DVH');

-- Lo que usa una fórmula
SELECT pg_temp.ver('Re');
SELECT pg_temp.vr('Re', 'x', 1, 'noexiste + 1');
SELECT pg_temp.dice('Re', 'x: usa noexiste, que no existe');
SELECT pg_temp.pz('Re', 'Cajon', 1, '{"opcional": true}');
SELECT pg_temp.vr('Re', 'alto_cajon', 2, '100', jsonb_build_object('pieza_id', pg_temp.id('Re.Cajon')));
SELECT pg_temp.un('Re', 'Cajon', 1, 'Chico');
SELECT pg_temp.pz('Re', 'Fija', 2);
SELECT pg_temp.un('Re', 'Fija', 1, 'Felpa', '{"medida": "alto_cajon"}');
SELECT pg_temp.dice('Re', 'Zqx162 Felpa: usa alto_cajon, que puede no estar');
SELECT pg_temp.vr('Re', 'y', 3, 'alto_cajon');
SELECT pg_temp.dice('Re', 'y: usa alto_cajon, que puede no estar');
SELECT pg_temp.pz('Re', 'Cortina', 3, jsonb_build_object('opcional', true, 'requiere_pieza_id', pg_temp.id('Re.Cajon')));
SELECT pg_temp.un('Re', 'Cortina', 1, 'Contra4', '{"medida": "alto_cajon"}');
SELECT pg_temp.no_dice('Re', 'Zqx162 Contra4: usa');
SELECT pg_temp.pz('Re', 'Tapa', 4, jsonb_build_object('opcional', true, 'requiere_pieza_id', pg_temp.id('Re.Cortina')));
SELECT pg_temp.un('Re', 'Tapa', 1, 'Curvo', '{"medida": "alto_cajon"}');
SELECT pg_temp.no_dice('Re', 'Zqx162 Curvo: usa');
SELECT pg_temp.pz('Re', 'Otra', 5, '{"opcional": true}');
SELECT pg_temp.un('Re', 'Otra', 1, 'Contra6', '{"medida": "alto_cajon"}');
SELECT pg_temp.dice('Re', 'Zqx162 Contra6: usa alto_cajon, que puede no estar');

SELECT pg_temp.mu('Re', 'Fija', 2, 'elige_vendedor', 'Manija', '{"sin_eleccion": true}');
SELECT pg_temp.op('Re', 'Re.Fija.Manija', 1, 'Tirador');
SELECT pg_temp.vr('Re', 'z1', 4, '[Manija]');
SELECT pg_temp.dice('Re', 'z1: usa Manija, que puede no estar');
SELECT pg_temp.mu('Re', 'Fija', 3, 'elige_sistema', 'Reja', '{"eleccion": "si 1 > 2 entonces [Zqx162 Rueda40] si no ninguno"}');
SELECT pg_temp.op('Re', 'Re.Fija.Reja', 1, 'Rueda40');
SELECT pg_temp.vr('Re', 'z2', 5, '[Reja]');
SELECT pg_temp.dice('Re', 'z2: usa Reja, que puede no estar');
SELECT pg_temp.mu('Re', 'Fija', 4, 'elige_vendedor', 'Vid', '{"ancho": "10", "alto": "10"}');
SELECT pg_temp.op('Re', 'Re.Fija.Vid', 1, 'Float');
SELECT pg_temp.op('Re', 'Re.Fija.Vid', 2, 'DVH');
SELECT pg_temp.mu('Re', 'Fija', 5, 'sigue', 'Sinc', jsonb_build_object('sigue_material_id', pg_temp.id('Re.Fija.Vid'), 'medida', '10'));
SELECT pg_temp.pareja('Re', 'Re.Fija.Sinc', 1, 'Re.Fija.Vid.Float', 'Contra4');
SELECT pg_temp.pareja('Re', 'Re.Fija.Sinc', 2, 'Re.Fija.Vid.DVH', 'Contra6');
SELECT pg_temp.vr('Re', 'z3', 6, '[Sinc]');
SELECT pg_temp.no_dice('Re', 'z3: usa Sinc');
SELECT pg_temp.caso('01 una pareja "ninguna": la pone en duda', 'ok', pg_temp.intentar(format('UPDATE catalogo_opciones SET insumo_id = NULL WHERE id = %s', pg_temp.l('Re.Fija.Sinc.Re.Fija.Vid.DVH')), 'Lucia'));
SELECT pg_temp.dice('Re', 'z3: usa Sinc, que puede no estar');
SELECT pg_temp.mu('Re', 'Fija', 6, 'sigue', 'Sinc2', jsonb_build_object('sigue_material_id', pg_temp.id('Re.Fija.Manija'), 'medida', '10'));
SELECT pg_temp.vr('Re', 'z4', 7, '[Sinc2]');
SELECT pg_temp.dice('Re', 'z4: usa Sinc2, que puede no estar');

-- El mismo nombre en una fija y en una opcional: el total existe siempre. Solo en la opcional, no.
SELECT pg_temp.un('Re', 'Fija', 7, 'Soldado');
SELECT pg_temp.un('Re', 'Otra', 2, 'Soldado');
SELECT pg_temp.vr('Re', 'z5', 8, '[Zqx162 Soldado]');
SELECT pg_temp.no_dice('Re', 'z5: usa');
SELECT pg_temp.un('Re', 'Otra', 3, 'Enrollable');
SELECT pg_temp.vr('Re', 'z6', 9, '[Zqx162 Enrollable]');
SELECT pg_temp.dice('Re', 'z6: usa Zqx162 Enrollable, que puede no estar');

SELECT pg_temp.mete('Re.mano', 'catalogo_variables', 'Re', '{"nombre": "mano", "orden": 10, "ingresa_vendedor": true, "es_lista": true, "valores": ["Izq", "Der"]}');
SELECT pg_temp.vr('Re', 'z7', 11, 'mano + 1');
SELECT pg_temp.dice('Re', 'z7: usa mano, que es una lista de valores');
SELECT pg_temp.co('Re', 'variable_id', 'Re.z5', 'mano > 1');
SELECT pg_temp.dice('Re', 'z5: usa mano, que es una lista de valores');
SELECT pg_temp.co('Re', 'variable_id', 'Re.y', 'zzz > 1');
SELECT pg_temp.dice('Re', 'y: usa zzz, que no existe');
SELECT pg_temp.vr('Re', 'z8', 12, '[espesor Fija]');
SELECT pg_temp.dice('Re', 'z8: usa espesor Fija, que no existe');
SELECT pg_temp.vr('Re', 'z9', 13, '[peso Fija]');
SELECT pg_temp.no_dice('Re', 'z9: usa');
SELECT pg_temp.vr('Re', 'z10', 14, '[peso Otra]');
SELECT pg_temp.dice('Re', 'z10: usa peso Otra, que puede no estar');

SELECT pg_temp.caso('01 un "si" sin "si no" no se guarda', 'CA001', pg_temp.intentar(format($q$INSERT INTO catalogo_variables (version_id, nombre, formula) VALUES (%s, 'mal', 'si 1 > 2 entonces 3')$q$, pg_temp.l('Re')), 'Lucia'));

-- Sigue a uno de una pieza que puede no estar
SELECT pg_temp.ver('Sg');
SELECT pg_temp.pz('Sg', 'Op', 1, '{"opcional": true}');
SELECT pg_temp.mu('Sg', 'Op', 1, 'elige_vendedor', 'Vid', '{"medida": "10"}');
SELECT pg_temp.op('Sg', 'Sg.Op.Vid', 1, 'Curvo');
SELECT pg_temp.pz('Sg', 'Fija', 2);
SELECT pg_temp.mu('Sg', 'Fija', 1, 'sigue', 'Cv', jsonb_build_object('sigue_material_id', pg_temp.id('Sg.Op.Vid'), 'medida', '10'));
SELECT pg_temp.pareja('Sg', 'Sg.Fija.Cv', 1, 'Sg.Op.Vid.Curvo', 'Contra4');
SELECT pg_temp.dice('Sg', 'Cv: sigue a Vid, que puede no estar');

-- Círculos
SELECT pg_temp.ver('Ci');
SELECT pg_temp.vr('Ci', 'a', 1, 'b + 1');
SELECT pg_temp.vr('Ci', 'b', 2, 'a + 1');
SELECT pg_temp.dice('Ci', 'Referencia circular entre a, b');
SELECT pg_temp.ver('Ci2');
SELECT pg_temp.vr('Ci2', 'uno', 1, 'si 1 > 2 entonces dos si no 1');
SELECT pg_temp.vr('Ci2', 'dos', 2, 'uno');
SELECT pg_temp.dice('Ci2', 'Referencia circular entre dos, uno');
SELECT pg_temp.ver('Ci3');
SELECT pg_temp.pz('Ci3', 'P', 1);
SELECT pg_temp.un('Ci3', 'P', 1, 'Curvo', '{"medida": "[Zqx162 Felpa]"}');
SELECT pg_temp.un('Ci3', 'P', 2, 'Felpa', '{"medida": "[Zqx162 Curvo]"}');
SELECT pg_temp.dice('Ci3', 'Referencia circular entre Zqx162 Curvo, Zqx162 Felpa');
SELECT pg_temp.ver('Ci4');
SELECT pg_temp.pz('Ci4', 'Hoja', 1);
SELECT pg_temp.mu('Ci4', 'Hoja', 1, 'elige_sistema', 'Rueda', '{"eleccion": "si [peso Hoja] > 40 entonces [Zqx162 Rueda80] si no [Zqx162 Rueda40]"}');
SELECT pg_temp.op('Ci4', 'Ci4.Hoja.Rueda', 1, 'Rueda40');
SELECT pg_temp.op('Ci4', 'Ci4.Hoja.Rueda', 2, 'Rueda80');
SELECT pg_temp.dice('Ci4', 'Referencia circular entre peso Hoja, Rueda');
SELECT pg_temp.caso('01 sin contar la rueda', 'ok', pg_temp.intentar(format('UPDATE catalogo_materiales SET cuenta_peso = false WHERE id = %s', pg_temp.l('Ci4.Hoja.Rueda')), 'Lucia'));
SELECT pg_temp.no_dice('Ci4', 'Referencia circular');
SELECT pg_temp.ver('Ci5');
SELECT pg_temp.pz('Ci5', 'P', 1, '{"cantidad": "[Zqx162 Escuadra]"}');
SELECT pg_temp.un('Ci5', 'P', 1, 'Escuadra');
SELECT pg_temp.dice('Ci5', 'Referencia circular entre cantidad de P, Zqx162 Escuadra');
SELECT pg_temp.ver('Ci6');
SELECT pg_temp.vr('Ci6', 'tr', 1, '2');
SELECT pg_temp.pz('Ci6', 'P', 1, '{"cantidad": "tr"}');
SELECT pg_temp.un('Ci6', 'P', 1, 'Escuadra');
SELECT pg_temp.no_dice('Ci6', 'Referencia circular');

SELECT pg_temp.ver('Rq');
SELECT pg_temp.pz('Rq', 'A', 1, '{"opcional": true}');
SELECT pg_temp.pz('Rq', 'B', 2, jsonb_build_object('opcional', true, 'requiere_pieza_id', pg_temp.id('Rq.A')));
SELECT pg_temp.no_dice('Rq', 'Requisito circular');
SELECT pg_temp.caso('01 A requiere B y B requiere A', 'ok', pg_temp.intentar(format('UPDATE catalogo_piezas SET requiere_pieza_id = %s WHERE id = %s', pg_temp.l('Rq.B'), pg_temp.l('Rq.A')), 'Lucia'));
SELECT pg_temp.dice('Rq', 'Requisito circular entre A, B');

-- Peso y espesor vacíos
SELECT pg_temp.ver('Pe');
SELECT pg_temp.pz('Pe', 'P', 1);
SELECT pg_temp.un('Pe', 'P', 1, 'SinPeso');
SELECT pg_temp.dice('Pe', 'Zqx162 SinPeso: falta el peso, y la pieza P lo cuenta');
SELECT pg_temp.caso('01 un tornillo que no cuenta', 'ok', pg_temp.intentar(format('UPDATE catalogo_materiales SET cuenta_peso = false WHERE id = %s', pg_temp.l('Pe.P.SinPeso.1')), 'Lucia'));
SELECT pg_temp.no_dice('Pe', 'falta el peso');
SELECT pg_temp.caso('01 marca el espesor: la pieza no lo calcula', 'ok', pg_temp.intentar(format('UPDATE catalogo_materiales SET cuenta_espesor = true WHERE id = %s', pg_temp.l('Pe.P.SinPeso.1')), 'Lucia'));
SELECT pg_temp.no_dice('Pe', 'falta el espesor');
SELECT pg_temp.caso('01 la pieza lo calcula', 'ok', pg_temp.intentar(format('UPDATE catalogo_piezas SET calcula_espesor = true WHERE id = %s', pg_temp.l('Pe.P')), 'Lucia'));
SELECT pg_temp.dice('Pe', 'Zqx162 SinPeso: falta el espesor, y la pieza P lo cuenta');

-- Secundario sin predeterminado, mínimo y máximo, nombres y estructura
SELECT pg_temp.ver('Se');
SELECT pg_temp.en('Se', 's1', 1, 1, 2, '{"secundario": true}');
SELECT pg_temp.dice('Se', 's1: es secundaria y no tiene predeterminado');
SELECT pg_temp.en('Se', 's2', 2, 1, 2, '{"secundario": true, "formula": "1"}');
SELECT pg_temp.no_dice('Se', 's2: es secundaria');
SELECT pg_temp.mete('Se.s3', 'catalogo_variables', 'Se', '{"nombre": "s3", "ingresa_vendedor": true, "es_lista": true, "valores": ["a"], "secundario": true}');
SELECT pg_temp.dice('Se', 's3: es secundaria y no tiene predeterminado');
SELECT pg_temp.mete('Se.s4', 'catalogo_variables', 'Se', '{"nombre": "s4", "ingresa_vendedor": true, "es_lista": true, "valores": ["a"], "valor_predeterminado": "a", "secundario": true}');
SELECT pg_temp.no_dice('Se', 's4: es secundaria');
SELECT pg_temp.pz('Se', 'P', 1);
SELECT pg_temp.mu('Se', 'P', 1, 'elige_vendedor', 'M1', '{"secundario": true}');
SELECT pg_temp.op('Se', 'Se.P.M1', 1, 'Chico');
SELECT pg_temp.dice('Se', 'M1: es secundario y no tiene predeterminado');
SELECT pg_temp.mu('Se', 'P', 2, 'elige_vendedor', 'M2', '{"secundario": true}');
SELECT pg_temp.op('Se', 'Se.P.M2', 1, 'Chico', '{"predeterminada": true}');
SELECT pg_temp.no_dice('Se', 'M2: es secundario');
SELECT pg_temp.mu('Se', 'P', 3, 'elige_vendedor', 'M3', '{"secundario": true, "sin_eleccion": true}');
SELECT pg_temp.op('Se', 'Se.P.M3', 1, 'Chico');
SELECT pg_temp.no_dice('Se', 'M3: es secundario');

SELECT pg_temp.en('Se', 'r1', 3, NULL, 10);
SELECT pg_temp.dice('Se', 'r1: falta el mínimo o el máximo');
SELECT pg_temp.en('Se', 'r2', 4, 1, NULL);
SELECT pg_temp.dice('Se', 'r2: falta el mínimo o el máximo');
SELECT pg_temp.en('Se', 'r3', 5, 10, 1);
SELECT pg_temp.dice('Se', 'r3: el mínimo es mayor que el máximo');
SELECT pg_temp.no_dice('Se', 's4: falta');

SELECT pg_temp.un('Se', 'P', 4, 'Chico');
SELECT pg_temp.vr('Se', 'ZQX162 CHICO', 6, '1');
SELECT pg_temp.dice('Se', 'ZQX162 CHICO: una variable no se llama como un material');
SELECT pg_temp.vr('Se', 'PESO p', 7, '1');
SELECT pg_temp.dice('Se', 'PESO p: una variable no se llama como el peso o el espesor de una pieza');
SELECT pg_temp.vr('Se', 'espesor P', 8, '1');
SELECT pg_temp.dice('Se', 'espesor P: una variable no se llama como el peso o el espesor de una pieza');

SELECT pg_temp.ver('Es');
SELECT pg_temp.pz('Es', 'P', 1);
SELECT pg_temp.mete('Es.m', 'catalogo_materiales', 'Es', jsonb_build_object('pieza_id', pg_temp.id('Es.P'), 'tipo', 'unico'));
SELECT pg_temp.dice('Es', 'Un material de P no tiene insumo');
SELECT pg_temp.mu('Es', 'P', 2, 'elige_vendedor', 'SinOp');
SELECT pg_temp.dice('Es', 'SinOp: no tiene opciones');
SELECT pg_temp.mu('Es', 'P', 3, 'sigue', 'Solo');
SELECT pg_temp.dice('Es', 'Solo: no tiene a quién seguir');
SELECT pg_temp.mu('Es', 'P', 4, 'sigue', 'Cadena', jsonb_build_object('sigue_material_id', pg_temp.id('Es.P.Solo')));
SELECT pg_temp.dice('Es', 'Cadena: sigue a Solo, que no elige');
SELECT pg_temp.un('Es', 'P', 5, 'Chico');
SELECT pg_temp.mu('Es', 'P', 6, 'sigue', 'AUnico', jsonb_build_object('sigue_material_id', pg_temp.id('Es.P.Chico.5')));
SELECT pg_temp.dice('Es', 'AUnico: sigue a Zqx162 Chico, que no elige');
SELECT pg_temp.mete('Es.l', 'catalogo_variables', 'Es', '{"nombre": "vacia", "ingresa_vendedor": true, "es_lista": true}');
SELECT pg_temp.dice('Es', 'vacia: la lista no tiene valores');
SELECT pg_temp.mu('Es', 'P', 7, 'elige_sistema', 'SinRegla');
SELECT pg_temp.op('Es', 'Es.P.SinRegla', 1, 'Rueda40');
SELECT pg_temp.dice('Es', 'SinRegla: lo define el sistema y no tiene regla');
SELECT pg_temp.mu('Es', 'P', 8, 'elige_sistema', 'MalaRegla', '{"eleccion": "si 1 > 2 entonces [Zqx162 Rueda40] si no [Zqx162 Rueda80]"}');
SELECT pg_temp.op('Es', 'Es.P.MalaRegla', 1, 'Rueda40');
SELECT pg_temp.dice('Es', 'MalaRegla: la regla elige Zqx162 Rueda80, que no es una de sus opciones');
SELECT pg_temp.no_dice('Es', 'MalaRegla: la regla elige Zqx162 Rueda40');

-- Colores y categoría
SELECT pg_temp.chico('Co', 'PerfilMosq');
SELECT pg_temp.dice('Co', 'Zqx162 PerfilMosq: falta la medida');
SELECT pg_temp.dice('Co', 'Zqx162 PerfilMosq tiene colores y la versión no ofrece ninguno');
SELECT pg_temp.mete(NULL, 'catalogo_versiones_colores', 'Co', jsonb_build_object('color_id', pg_temp.id('Blanco')));
SELECT pg_temp.no_dice('Co', 'no ofrece ninguno');
SELECT pg_temp.dice('Co', 'Falta elegir el color base');
SELECT pg_temp.mete(NULL, 'catalogo_versiones_colores', 'Co', jsonb_build_object('color_id', pg_temp.id('Negro'), 'base', true));
SELECT pg_temp.no_dice('Co', 'Falta elegir el color base');
SELECT pg_temp.dice('Co', 'En Zqx162 Negro no se puede armar: falta Zqx162 PerfilMosq · Zqx162 Negro');
SELECT pg_temp.no_dice('Co', 'En Zqx162 Blanco no se puede armar');
SELECT pg_temp.mete(NULL, 'catalogo_versiones_colores', 'Co', jsonb_build_object('color_id', pg_temp.id('Verde')));
SELECT pg_temp.caso('01 baja del color Verde, sin variantes', 'ok', pg_temp.intentar(format('UPDATE catalogo_colores SET activo = false WHERE id = %s', pg_temp.l('Verde')), 'Lucia'));
SELECT pg_temp.dice('Co', 'El color Zqx162 Verde está de baja');
SELECT pg_temp.caso('01 reactivo Verde', 'ok', pg_temp.intentar(format('UPDATE catalogo_colores SET activo = true WHERE id = %s', pg_temp.l('Verde')), 'Lucia'));

SELECT pg_temp.chico('Ca', 'Chico', 'Puertas');
SELECT pg_temp.limpia('Ca');
SELECT pg_temp.caso('01 baja de Puertas: solo hay un borrador', 'ok', pg_temp.intentar(format('UPDATE catalogo_categorias SET activo = false WHERE id = %s', pg_temp.l('Puertas')), 'Lucia'));
SELECT pg_temp.dice('Ca', 'La categoría Zqx162 Puertas está de baja');
SELECT pg_temp.caso('01 enviar con la categoría de baja', 'CA019', pg_temp.fn('enviar', 'Ca', 'Lucia'));
SELECT pg_temp.caso('01 reactivo Puertas', 'ok', pg_temp.intentar(format('UPDATE catalogo_categorias SET activo = true WHERE id = %s', pg_temp.l('Puertas')), 'Lucia'));
SELECT pg_temp.limpia('Ca');

-- Casos de prueba
SELECT pg_temp.ver('Cs');
SELECT pg_temp.en('Cs', 'alto', 1, 300, 3000);
SELECT pg_temp.pz('Cs', 'P', 1);
SELECT pg_temp.un('Cs', 'P', 1, 'Felpa', '{"medida": "alto − 1200"}');
SELECT pg_temp.dice('Cs', 'La versión no tiene casos de prueba');
SELECT pg_temp.mete('Cs.c1', 'catalogo_casos', 'Cs', '{"nombre": "faltante"}');
SELECT pg_temp.no_dice('Cs', 'La versión no tiene casos de prueba');
SELECT pg_temp.dice('Cs', 'Caso faltante: alto: falta el valor');
SELECT pg_temp.mete('Cs.c2', 'catalogo_casos', 'Cs', '{"nombre": "chica", "entrada": {"variables": {"alto": 600}}}');
SELECT pg_temp.dice('Cs', 'Caso chica: Zqx162 Felpa: la medida dio −600 mm');
SELECT pg_temp.mete('Cs.c3', 'catalogo_casos', 'Cs', '{"nombre": "vieja", "entrada": {"variables": {"alto": 2000}, "elecciones": {"P": {"Ya no": null}}}}');
SELECT pg_temp.dice('Cs', 'Caso vieja: Ya no: esa elección ya no existe');

SELECT pg_temp.ver('Cs2');
SELECT pg_temp.en('Cs2', 'alto', 1, 300, 3000);
SELECT pg_temp.pz('Cs2', 'P', 1);
SELECT pg_temp.un('Cs2', 'P', 1, 'Felpa', '{"medida": "alto"}');
SELECT pg_temp.co('Cs2', 'variable_id', 'Cs2.alto', 'alto > 1000', true);
SELECT pg_temp.mete('Cs2.c1', 'catalogo_casos', 'Cs2', '{"nombre": "bloqueada", "entrada": {"variables": {"alto": 2000}}}');
SELECT pg_temp.mete('Cs2.c2', 'catalogo_casos', 'Cs2', '{"nombre": "fuera de rango", "entrada": {"variables": {"alto": 9000}}}');
SELECT pg_temp.limpia('Cs2');

-- El nombre del paquete
SELECT pg_temp.chico('D1');
SELECT pg_temp.chico('D2');
SELECT pg_temp.caso('01 D2 se llama como D1', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_versiones SET nombre = 'ZQX162 D1' WHERE id = %s$q$, pg_temp.l('D2')), 'Lucia'));
SELECT pg_temp.no_dice('D2', 'ya lo tiene otro paquete');
SELECT pg_temp.caso('01 D1 en revisión', 'ok', pg_temp.fn('enviar', 'D1', 'Lucia'));
SELECT pg_temp.dice('D2', 'El nombre ZQX162 D1 ya lo tiene otro paquete');
SELECT pg_temp.caso('01 D2 no se puede enviar', 'CA019', pg_temp.fn('enviar', 'D2', 'Lucia'));
SELECT pg_temp.caso('01 D1 publicada', 'ok', pg_temp.fn('aprobar', 'D1', 'Carlos'));
SELECT pg_temp.dice('D2', 'El nombre ZQX162 D1 ya lo tiene otro paquete');
SELECT pg_temp.caso('01 de baja también lo retiene', 'ok', pg_temp.paq('D1', false));
SELECT pg_temp.dice('D2', 'El nombre ZQX162 D1 ya lo tiene otro paquete');

-- ============================================================
-- 2. El ciclo: enviar, retirar, devolver, aprobar, descartar
-- ============================================================
SELECT pg_temp.caso('02 revisar: Rodrigo', '', pg_temp.frena('V1', 'Rodrigo'));
SELECT pg_temp.caso('02 revisar: Marta no tiene la vista', 'CA016', pg_temp.frena('V1', 'Marta'));
SELECT pg_temp.caso('02 revisar: Ana no tiene la vista', 'CA016', pg_temp.frena('V1', 'Ana'));
SELECT pg_temp.caso('02 revisar: Juan', 'CA016', pg_temp.frena('V1', 'Juan'));
SELECT pg_temp.caso('02 revisar lo que no existe', 'CA016', pg_temp.consultar(format('SELECT catalogo_version_revisar(%L)::text', gen_random_uuid()), 'Rodrigo'));

SELECT pg_temp.caso('02 enviar vacía', 'CA019', pg_temp.fn('enviar', 'Vacia', 'Lucia'));
SELECT pg_temp.caso('02 enviar vacía dice por qué', E'El paquete está vacío\nLa versión no tiene casos de prueba',
  pg_temp.mensaje(format('SELECT catalogo_version_enviar(%s)', pg_temp.l('Vacia')), 'Lucia'));
SELECT pg_temp.caso('02 sigue en borrador', 'borrador', pg_temp.estado('Vacia'));
SELECT pg_temp.caso('02 enviar lo que no existe', 'CA016', pg_temp.intentar(format('SELECT catalogo_version_enviar(%L)', gen_random_uuid()), 'Lucia'));

SELECT pg_temp.caso('02 enviar: Rodrigo no', '42501', pg_temp.fn('enviar', 'V1', 'Rodrigo'));
SELECT pg_temp.caso('02 enviar: Carlos no', '42501', pg_temp.fn('enviar', 'V1', 'Carlos'));
SELECT pg_temp.caso('02 enviar: Marta no', '42501', pg_temp.fn('enviar', 'V1', 'Marta'));
SELECT pg_temp.caso('02 enviar: Lucia', 'ok', pg_temp.fn('enviar', 'V1', 'Lucia'));
SELECT pg_temp.caso('02 en revisión', 'en_revision', pg_temp.estado('V1'));
SELECT pg_temp.caso('02 la historia dice quién la envió', 'enviada:' || pg_temp.id('Lucia'), (
  SELECT h.accion::text || ':' || h.creado_por FROM catalogo_versiones_historia h WHERE h.version_id = pg_temp.id('V1')));
SELECT pg_temp.caso('02 enviarla otra vez', 'CA012', pg_temp.fn('enviar', 'V1', 'Lucia'));

SELECT pg_temp.caso('02 en revisión no se edita el contenido', 'CA012', pg_temp.intentar(format($q$UPDATE catalogo_piezas SET nombre = 'Otro' WHERE id = %s$q$, pg_temp.l('V1.Marco')), 'Lucia'));
SELECT pg_temp.caso('02 ni el nombre', 'CA012', pg_temp.intentar(format($q$UPDATE catalogo_versiones SET nombre = 'Zqx162 Otro' WHERE id = %s$q$, pg_temp.l('V1')), 'Lucia'));
SELECT pg_temp.caso('02 enviada: el insumo queda fijo', 'CA006', pg_temp.intentar(format($q$UPDATE catalogo_insumos SET nombre = 'Zqx162 Felpa2' WHERE id = %s$q$, pg_temp.l('Felpa')), 'Lucia'));

SELECT pg_temp.caso('02 retirar: Carlos no', '42501', pg_temp.fn('retirar', 'V1', 'Carlos'));
SELECT pg_temp.caso('02 retirar: Rodrigo no', '42501', pg_temp.fn('retirar', 'V1', 'Rodrigo'));
SELECT pg_temp.caso('02 retirar: Lucia', 'ok', pg_temp.fn('retirar', 'V1', 'Lucia'));
SELECT pg_temp.caso('02 retirada: borrador', 'borrador', pg_temp.estado('V1'));
SELECT pg_temp.caso('02 retirarla otra vez', 'CA022', pg_temp.fn('retirar', 'V1', 'Lucia'));
SELECT pg_temp.caso('02 retirada: el insumo se edita de nuevo', 'ok', pg_temp.intentar(format($q$UPDATE catalogo_insumos SET peso = 0.01 WHERE id = %s$q$, pg_temp.l('Felpa')), 'Lucia'));
SELECT pg_temp.caso('02 aprobar un borrador', 'CA022', pg_temp.fn('aprobar', 'V1', 'Carlos'));
SELECT pg_temp.caso('02 devolver un borrador', 'CA022', pg_temp.fn('devolver', 'V1', 'Carlos', ', ''Mal'''));
SELECT pg_temp.limpia('V1');

SELECT pg_temp.caso('02 enviar de nuevo', 'ok', pg_temp.fn('enviar', 'V1', 'Lucia'));
SELECT pg_temp.caso('02 devolver: Lucia no', '42501', pg_temp.fn('devolver', 'V1', 'Lucia', ', ''Mal'''));
SELECT pg_temp.caso('02 devolver sin motivo', 'CA021', pg_temp.fn('devolver', 'V1', 'Carlos', ', NULL'));
SELECT pg_temp.caso('02 devolver con motivo en blanco', 'CA021', pg_temp.fn('devolver', 'V1', 'Carlos', ', ''   '''));
SELECT pg_temp.caso('02 sigue en revisión', 'en_revision', pg_temp.estado('V1'));
SELECT pg_temp.caso('02 devolver', 'ok', pg_temp.fn('devolver', 'V1', 'Carlos', ', '' La Hoja sigue con Float 4mm '''));
SELECT pg_temp.caso('02 devuelta: borrador', 'borrador', pg_temp.estado('V1'));
SELECT pg_temp.caso('02 la historia guarda el motivo', 'devuelta:La Hoja sigue con Float 4mm,enviada,enviada,retirada', pg_temp.historia('V1'));

SELECT pg_temp.caso('02 enviar otra vez', 'ok', pg_temp.fn('enviar', 'V1', 'Lucia'));
SELECT pg_temp.caso('02 aprobar: Lucia no', '42501', pg_temp.fn('aprobar', 'V1', 'Lucia'));
SELECT pg_temp.caso('02 aprobar: Rodrigo no', '42501', pg_temp.fn('aprobar', 'V1', 'Rodrigo'));
SELECT pg_temp.caso('02 aprobar: Carlos', 'ok', pg_temp.fn('aprobar', 'V1', 'Carlos'));
SELECT pg_temp.caso('02 publicada', 'publicado', pg_temp.estado('V1'));
SELECT pg_temp.caso('02 aprobarla otra vez', 'CA022', pg_temp.fn('aprobar', 'V1', 'Carlos'));
SELECT pg_temp.caso('02 retirar una publicada', 'CA022', pg_temp.fn('retirar', 'V1', 'Lucia'));
SELECT pg_temp.caso('02 descartar una publicada', 'CA012', pg_temp.fn('descartar', 'V1', 'Lucia'));

SELECT pg_temp.caso('02 el estado no se escribe directo', '42501', pg_temp.intentar(format($q$UPDATE catalogo_versiones SET estado = 'obsoleto' WHERE id = %s$q$, pg_temp.l('V1')), 'Lucia'));
SELECT pg_temp.caso('02 la historia no se escribe directo', '42501', pg_temp.intentar(format($q$INSERT INTO catalogo_versiones_historia (version_id, accion, creado_por) VALUES (%s, 'aprobada', %s)$q$, pg_temp.l('V1'), pg_temp.l('Lucia')), 'Lucia'));
SELECT pg_temp.caso('02 ni se cambia', '42501', pg_temp.intentar(format('UPDATE catalogo_versiones_historia SET activo = false WHERE version_id = %s', pg_temp.l('V1')), 'Carlos'));
SELECT pg_temp.caso('02 por qué está de baja no se escribe directo', '42501', pg_temp.intentar(format('UPDATE catalogo_paquetes SET baja_insumo_id = %s WHERE id = %L', pg_temp.l('Felpa'), pg_temp.paquete('V1')), 'Lucia'));
SELECT pg_temp.caso('02 la historia: Rodrigo la ve', '6', pg_temp.consultar(format('SELECT count(*)::text FROM catalogo_versiones_historia WHERE version_id = %s', pg_temp.l('V1')), 'Rodrigo'));
SELECT pg_temp.caso('02 la historia: Ana no', '0', pg_temp.consultar(format('SELECT count(*)::text FROM catalogo_versiones_historia WHERE version_id = %s', pg_temp.l('V1')), 'Ana'));
SELECT pg_temp.caso('02 la historia: Juan no', '0', pg_temp.consultar(format('SELECT count(*)::text FROM catalogo_versiones_historia WHERE version_id = %s', pg_temp.l('V1')), 'Juan'));

-- Versión nueva: reemplaza a la publicada y se descarta
SELECT pg_temp.crear('V2', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('V1')));
SELECT pg_temp.limpia('V2');
SELECT pg_temp.publicar('V2');
SELECT pg_temp.caso('02 la anterior pasa a obsoleta', 'obsoleto', pg_temp.estado('V1'));
SELECT pg_temp.caso('02 la nueva, publicada', 'publicado', pg_temp.estado('V2'));
SELECT pg_temp.caso('02 la anterior lo registra', true::text, (position('obsoleta' IN pg_temp.historia('V1')) > 0)::text);

SELECT pg_temp.crear('V3', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('V1')));
SELECT pg_temp.caso('02 descartar: Carlos no', '42501', pg_temp.fn('descartar', 'V3', 'Carlos'));
SELECT pg_temp.caso('02 descartar: Rodrigo no', '42501', pg_temp.fn('descartar', 'V3', 'Rodrigo'));
SELECT pg_temp.caso('02 en revisión se retira primero', 'ok', pg_temp.fn('enviar', 'V3', 'Lucia'));
SELECT pg_temp.caso('02 descartar en revisión', 'CA012', pg_temp.fn('descartar', 'V3', 'Lucia'));
SELECT pg_temp.caso('02 retirar', 'ok', pg_temp.fn('retirar', 'V3', 'Lucia'));
SELECT pg_temp.caso('02 descartar', 'ok', pg_temp.fn('descartar', 'V3', 'Lucia'));
SELECT pg_temp.caso('02 descartada', 'descartado', pg_temp.estado('V3'));
SELECT pg_temp.caso('02 la historia lo dice', true::text, (position('descartada' IN pg_temp.historia('V3')) > 0)::text);
SELECT pg_temp.crear('V4', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('V1')));
SELECT pg_temp.caso('02 la siguiente es la v4', '4', (SELECT numero::text FROM catalogo_versiones WHERE id = pg_temp.id('V4')));
SELECT pg_temp.caso('02 sin versión publicada no se descarta', 'CA023', pg_temp.fn('descartar', 'Vacia', 'Lucia'));

-- Se revisa de nuevo al aprobar
SELECT pg_temp.chico('Ap', 'SoloV1');
SELECT pg_temp.caso('02 Ap en revisión', 'ok', pg_temp.fn('enviar', 'Ap', 'Lucia'));
SELECT pg_temp.caso('02 cae el insumo de Ap', 'ok', pg_temp.ins_activo('SoloV1', false));
SELECT pg_temp.caso('02 aprobar con el insumo de baja', 'CA019', pg_temp.fn('aprobar', 'Ap', 'Carlos'));
SELECT pg_temp.caso('02 dice cuál', 'Zqx162 SoloV1 está de baja', pg_temp.mensaje(format('SELECT catalogo_version_aprobar(%s)', pg_temp.l('Ap')), 'Carlos'));
SELECT pg_temp.caso('02 sigue en revisión', 'en_revision', pg_temp.estado('Ap'));
SELECT pg_temp.caso('02 reactivo el insumo', 'ok', pg_temp.ins_activo('SoloV1', true));
SELECT pg_temp.caso('02 ahora se aprueba', 'ok', pg_temp.fn('aprobar', 'Ap', 'Carlos'));

-- Aprobar no pone a la venta un paquete de baja
SELECT pg_temp.chico('Ab');
SELECT pg_temp.publicar('Ab');
SELECT pg_temp.caso('02 Ab de baja', 'ok', pg_temp.paq('Ab', false));
SELECT pg_temp.crear('Ab2', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('Ab')));
SELECT pg_temp.publicar('Ab2');
SELECT pg_temp.caso('02 aprobada, sigue de baja', 'a mano', pg_temp.causa('Ab2'));
SELECT pg_temp.caso('02 la nueva está publicada', 'publicado', pg_temp.estado('Ab2'));

-- ============================================================
-- 3. Lo que se ofrece en cada color (decisiones/catalogo/paquete.md → El color)
-- ============================================================
UPDATE catalogo_paquetes SET activo = false WHERE id IN (SELECT pg_temp.paquete(n) FROM unnest(ARRAY['V1', 'Ap', 'D1']) AS n);

SELECT pg_temp.armar('B1');
SELECT pg_temp.publicar('B1');
SELECT pg_temp.caso('03 en blanco, todo', 'true | - | -', pg_temp.ofrece('B1', 'Blanco'));
SELECT pg_temp.caso('03 en negro, sin Mosquitero ni Premium', 'true | Mosquitero | Zqx162 ManijaPremium', pg_temp.ofrece('B1', 'Negro'));
SELECT pg_temp.caso('03 oferta: Lucia', 'true | Mosquitero | Zqx162 ManijaPremium', pg_temp.ofrece('B1', 'Negro', 'Lucia'));
SELECT pg_temp.caso('03 oferta: Ana no tiene la vista', 'CA016', pg_temp.ofrece('B1', 'Negro', 'Ana'));
SELECT pg_temp.caso('03 oferta: Juan', 'CA016', pg_temp.ofrece('B1', 'Negro', 'Juan'));
SELECT pg_temp.caso('03 oferta de lo que no existe', 'CA016', pg_temp.consultar(format('SELECT count(*)::text FROM catalogo_version_oferta(%L)', gen_random_uuid()), 'Rodrigo'));

SELECT pg_temp.crear('Premium Negro', format('SELECT catalogo_variante_sumar(%s, %s)', pg_temp.l('ManijaPremium'), pg_temp.l('Negro')));
SELECT pg_temp.caso('03 una variante nueva sin costo cuenta como que no está', 'true | Mosquitero | Zqx162 ManijaPremium', pg_temp.ofrece('B1', 'Negro'));
SELECT pg_temp.costear('ManijaPremium');
SELECT pg_temp.caso('03 con costo se ofrece, sin versión nueva', 'true | Mosquitero | -', pg_temp.ofrece('B1', 'Negro'));

-- Sin colores: una sola fila, sin color
SELECT pg_temp.chico('Sc');
SELECT pg_temp.caso('03 sin colores se arma', 'true', pg_temp.consultar(format('SELECT armable::text FROM catalogo_version_oferta(%s) WHERE color IS NULL', pg_temp.l('Sc')), 'Rodrigo'));
SELECT pg_temp.caso('03 sin colores, una fila', '1', pg_temp.consultar(format('SELECT count(*)::text FROM catalogo_version_oferta(%s)', pg_temp.l('Sc')), 'Rodrigo'));

-- La Manija sin ninguna opción en negro; con "sin elección", sí; la Rueda que elige el sistema, alguna sin negro
SELECT pg_temp.ver('Cn');
SELECT pg_temp.colores('Cn', 'Blanco', 'Negro');
SELECT pg_temp.pz('Cn', 'P', 1);
SELECT pg_temp.un('Cn', 'P', 1, 'PerfilHoja', '{"medida": "10"}');
SELECT pg_temp.mu('Cn', 'P', 2, 'elige_vendedor', 'Sola');
SELECT pg_temp.op('Cn', 'Cn.P.Sola', 1, 'PerfilMosq', '{"medida": "10"}');
SELECT pg_temp.mete('Cn.c', 'catalogo_casos', 'Cn', '{"nombre": "base", "entrada": {"elecciones": {"P": {"Sola": null}}}}');
SELECT pg_temp.caso('03 sin opción en negro no se ofrece', 'false | P | -', pg_temp.ofrece('Cn', 'Negro'));
SELECT pg_temp.caso('03 eso frena el envío', true::text, (position('En Zqx162 Negro no se puede armar' IN pg_temp.frena('Cn')) > 0)::text);
SELECT pg_temp.caso('03 permite "sin elección"', 'ok', pg_temp.intentar(format('UPDATE catalogo_materiales SET sin_eleccion = true WHERE id = %s', pg_temp.l('Cn.P.Sola')), 'Lucia'));
SELECT pg_temp.caso('03 entonces sí', 'true | - | Zqx162 PerfilMosq', pg_temp.ofrece('Cn', 'Negro'));
SELECT pg_temp.mu('Cn', 'P', 3, 'elige_sistema', 'Regla', '{"eleccion": "si 1 > 2 entonces [Zqx162 PerfilMosq] si no [Zqx162 PerfilMarco]", "medida": "10"}');
SELECT pg_temp.op('Cn', 'Cn.P.Regla', 1, 'PerfilMosq');
SELECT pg_temp.op('Cn', 'Cn.P.Regla', 2, 'PerfilMarco');
SELECT pg_temp.caso('03 el sistema no puede elegir otra', true::text, (pg_temp.ofrece('Cn', 'Negro') LIKE 'false | P | %')::text);
SELECT pg_temp.caso('03 en blanco se arma', 'true | - | -', pg_temp.ofrece('Cn', 'Blanco'));

-- ============================================================
-- 4. Bajas en cascada, aviso previo y reactivación (decisiones/catalogo/insumos.md → El insumo)
-- ============================================================
-- Una opción: no se ofrece más
SELECT pg_temp.caso('04 aviso DVH', pg_temp.con_nombres('{}', jsonb_build_array(pg_temp.deja('B1', '{}', '{}', ARRAY['Zqx162 DVH']))), pg_temp.aviso('DVH', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja DVH', 'ok', pg_temp.ins_activo('DVH', false));
SELECT pg_temp.caso('04 B1 sigue a la venta', 'activo', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 no se ofrece el DVH', 'true | - | Zqx162 DVH', pg_temp.ofrece('B1', 'Blanco'));
SELECT pg_temp.crear('B1n', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('B1')));
SELECT pg_temp.dice('B1n', 'Zqx162 DVH está de baja');
SELECT pg_temp.caso('04 una versión nueva con él no se envía', 'CA019', pg_temp.fn('enviar', 'B1n', 'Lucia'));
SELECT pg_temp.caso('04 descarto la nueva', 'ok', pg_temp.fn('descartar', 'B1n', 'Lucia'));
SELECT pg_temp.caso('04 reactivo DVH', 'ok', pg_temp.ins_activo('DVH', true));
SELECT pg_temp.caso('04 vuelve a ofrecerse, sin versión nueva', 'true | - | -', pg_temp.ofrece('B1', 'Blanco'));

-- La pareja de una opción: esa opción no se ofrece más
SELECT pg_temp.caso('04 aviso Contra6', pg_temp.con_nombres('{}', jsonb_build_array(pg_temp.deja('B1', '{}', '{}', ARRAY['Zqx162 Contra6', 'Zqx162 Laminado']))), pg_temp.aviso('Contra6', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja Contra6', 'ok', pg_temp.ins_activo('Contra6', false));
SELECT pg_temp.caso('04 sin pareja no se ofrece el Laminado', 'true | - | Zqx162 Contra6,Zqx162 Laminado', pg_temp.ofrece('B1', 'Blanco'));
SELECT pg_temp.caso('04 B1 sigue', 'activo', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 reactivo Contra6', 'ok', pg_temp.ins_activo('Contra6', true));

-- Un material único de una pieza opcional: esa pieza no se ofrece más, ni la que la requiere
SELECT pg_temp.caso('04 aviso Tela', pg_temp.con_nombres('{}', jsonb_build_array(pg_temp.deja('B1', '{}', ARRAY['Mosquitero'], '{}'))), pg_temp.aviso('Tela', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja Tela', 'ok', pg_temp.ins_activo('Tela', false));
SELECT pg_temp.caso('04 no se ofrece el Mosquitero', 'true | Mosquitero | -', pg_temp.ofrece('B1', 'Blanco'));
SELECT pg_temp.caso('04 reactivo Tela', 'ok', pg_temp.ins_activo('Tela', true));
SELECT pg_temp.caso('04 baja Enrollable', 'ok', pg_temp.ins_activo('Enrollable', false));
SELECT pg_temp.caso('04 sin Cajón no hay Cortina', 'true | Cajon,Cortina | -', pg_temp.ofrece('B1', 'Blanco'));
SELECT pg_temp.caso('04 B1 sigue', 'activo', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 reactivo Enrollable', 'ok', pg_temp.ins_activo('Enrollable', true));

-- La última opción: sale de la venta, y dice cuál fue la última
SELECT pg_temp.caso('04 baja Float', 'ok', pg_temp.ins_activo('Float', false));
SELECT pg_temp.caso('04 baja Laminado', 'ok', pg_temp.ins_activo('Laminado', false));
SELECT pg_temp.caso('04 quedan el DVH', 'activo', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 aviso: era la última', pg_temp.con_nombres(ARRAY['Zqx162 B1']), pg_temp.aviso('DVH', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja DVH, la última', 'ok', pg_temp.ins_activo('DVH', false));
SELECT pg_temp.caso('04 B1 de baja por el DVH', 'Zqx162 DVH', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 no se reactiva sin armarse', 'CA020', pg_temp.paq('B1', true));
SELECT pg_temp.caso('04 dice qué falta', 'No se puede reactivar: falta Zqx162 DVH, Zqx162 Float, Zqx162 Laminado',
  pg_temp.mensaje(format('UPDATE catalogo_paquetes SET activo = true WHERE id = %L', pg_temp.paquete('B1')), 'Lucia'));
SELECT pg_temp.caso('04 reactivo Float', 'ok', pg_temp.ins_activo('Float', true));
SELECT pg_temp.caso('04 B1 no vuelve solo', 'Zqx162 DVH', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 Rodrigo no lo reactiva: 0 filas', 'ok', pg_temp.paq('B1', true, 'Rodrigo'));
SELECT pg_temp.caso('04 Carlos tampoco', 'ok', pg_temp.paq('B1', true, 'Carlos'));
SELECT pg_temp.caso('04 Ana tampoco', 'ok', pg_temp.paq('B1', true, 'Ana'));
SELECT pg_temp.caso('04 sigue de baja', 'Zqx162 DVH', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 Lucia lo reactiva', 'ok', pg_temp.paq('B1', true));
SELECT pg_temp.caso('04 B1 activo, sin causa', 'activo', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 la causa se borra', NULL, (SELECT baja_insumo_id::text FROM catalogo_paquetes WHERE id = pg_temp.paquete('B1')));
SELECT pg_temp.caso('04 se ofrece solo lo que está', 'true | - | Zqx162 DVH,Zqx162 Laminado', pg_temp.ofrece('B1', 'Blanco'));
SELECT pg_temp.caso('04 reactivo Laminado', 'ok', pg_temp.ins_activo('Laminado', true));
SELECT pg_temp.caso('04 reactivo DVH', 'ok', pg_temp.ins_activo('DVH', true));

-- Un único de una pieza fija; lo que elige el sistema
SELECT pg_temp.caso('04 aviso Escuadra', pg_temp.con_nombres(ARRAY['Zqx162 B1']), pg_temp.aviso('Escuadra', NULL, 'Lucia'));
SELECT pg_temp.caso('04 aviso Escuadra a Marta: solo el número', pg_temp.solo_numeros(1, 0), pg_temp.aviso('Escuadra', NULL, 'Marta'));
SELECT pg_temp.caso('04 aviso Escuadra a Ana: no es suyo', '42501', pg_temp.aviso('Escuadra', NULL, 'Ana'));
SELECT pg_temp.caso('04 aviso a Juan', '42501', pg_temp.aviso('Escuadra', NULL, 'Juan'));
SELECT pg_temp.caso('04 aviso de lo que no existe', '42501', pg_temp.consultar(format('SELECT catalogo_baja_aviso(%L)::text', gen_random_uuid()), 'Lucia'));
SELECT pg_temp.caso('04 baja Escuadra', 'ok', pg_temp.ins_activo('Escuadra', false));
SELECT pg_temp.caso('04 B1 de baja por la Escuadra', 'Zqx162 Escuadra', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 otra más no cambia la causa', 'ok', pg_temp.ins_activo('Rueda40', false));
SELECT pg_temp.caso('04 sigue por la Escuadra', 'Zqx162 Escuadra', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 reactivo Rueda40', 'ok', pg_temp.ins_activo('Rueda40', true));
SELECT pg_temp.caso('04 reactivo Escuadra', 'ok', pg_temp.ins_activo('Escuadra', true));
SELECT pg_temp.caso('04 reactivo B1', 'ok', pg_temp.paq('B1', true));

SELECT pg_temp.caso('04 aviso Rueda80', pg_temp.con_nombres(ARRAY['Zqx162 B1']), pg_temp.aviso('Rueda80', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja Rueda80', 'ok', pg_temp.ins_activo('Rueda80', false));
SELECT pg_temp.caso('04 el sistema no puede elegir otra: sale', 'Zqx162 Rueda80', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 reactivo Rueda80', 'ok', pg_temp.ins_activo('Rueda80', true));
SELECT pg_temp.caso('04 reactivo B1', 'ok', pg_temp.paq('B1', true));

-- Variantes: deja de ofrecer un color; sin ninguno, sale y lo dice con el color
SELECT pg_temp.caso('04 aviso Perfil hoja · Negro', pg_temp.con_nombres('{}', jsonb_build_array(pg_temp.deja('B1', ARRAY['Zqx162 Negro'], '{}', '{}'))), pg_temp.aviso('PerfilHoja', pg_temp.variante('PerfilHoja', 'Negro'), 'Lucia'));
SELECT pg_temp.caso('04 aviso a Marta', pg_temp.solo_numeros(0, 1), pg_temp.aviso('PerfilHoja', pg_temp.variante('PerfilHoja', 'Negro'), 'Marta'));
SELECT pg_temp.caso('04 una variante de otro insumo', '42501', pg_temp.aviso('Felpa', pg_temp.variante('PerfilHoja', 'Negro'), 'Lucia'));
SELECT pg_temp.caso('04 baja Perfil hoja · Negro', 'ok', pg_temp.var_activa('PerfilHoja', 'Negro', false));
SELECT pg_temp.caso('04 B1 sigue', 'activo', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 en negro no se arma', true::text, (pg_temp.ofrece('B1', 'Negro') LIKE 'false | %')::text);
SELECT pg_temp.caso('04 en blanco sí', 'true | - | -', pg_temp.ofrece('B1', 'Blanco'));
SELECT pg_temp.caso('04 aviso Perfil hoja · Blanco', pg_temp.con_nombres(ARRAY['Zqx162 B1']), pg_temp.aviso('PerfilHoja', pg_temp.variante('PerfilHoja', 'Blanco'), 'Lucia'));
SELECT pg_temp.caso('04 baja Perfil hoja · Blanco', 'ok', pg_temp.var_activa('PerfilHoja', 'Blanco', false));
SELECT pg_temp.caso('04 de baja por la última variante', 'Zqx162 PerfilHoja · Zqx162 Blanco', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 dice qué variante falta', 'No se puede reactivar: falta Zqx162 PerfilHoja · Zqx162 Blanco, Zqx162 PerfilHoja · Zqx162 Negro',
  pg_temp.mensaje(format('UPDATE catalogo_paquetes SET activo = true WHERE id = %L', pg_temp.paquete('B1')), 'Lucia'));
SELECT pg_temp.caso('04 reactivar la variante negra', 'ok', pg_temp.var_activa('PerfilHoja', 'Negro', true));
SELECT pg_temp.caso('04 B1 no vuelve solo', 'Zqx162 PerfilHoja · Zqx162 Blanco', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 se reactiva en negro', 'ok', pg_temp.paq('B1', true));
SELECT pg_temp.caso('04 sin causa', NULL, (SELECT baja_variante_id::text FROM catalogo_paquetes WHERE id = pg_temp.paquete('B1')));
SELECT pg_temp.caso('04 en blanco todavía no', true::text, (pg_temp.ofrece('B1', 'Blanco') LIKE 'false | %')::text);
SELECT pg_temp.caso('04 reactivo la variante blanca', 'ok', pg_temp.var_activa('PerfilHoja', 'Blanco', true));
SELECT pg_temp.caso('04 en blanco, todo', 'true | - | -', pg_temp.ofrece('B1', 'Blanco'));

-- Servicio fijo: Administración lo baja sin ver los paquetes
SELECT pg_temp.caso('04 aviso Soldado a Ana: el número', pg_temp.solo_numeros(1, 0), pg_temp.aviso('Soldado', NULL, 'Ana'));
SELECT pg_temp.caso('04 aviso Soldado a Lucia: no es suyo', '42501', pg_temp.aviso('Soldado', NULL, 'Lucia'));
SELECT pg_temp.caso('04 Ana baja el Soldado', 'ok', pg_temp.ins_activo('Soldado', false, 'Ana'));
SELECT pg_temp.caso('04 B1 de baja por el Soldado', 'Zqx162 Soldado', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 no se reactiva', 'CA020', pg_temp.paq('B1', true));
SELECT pg_temp.caso('04 Ana lo reactiva', 'ok', pg_temp.ins_activo('Soldado', true, 'Ana'));
SELECT pg_temp.caso('04 Lucia reactiva B1', 'ok', pg_temp.paq('B1', true));

-- Con "sin elección" no sale
SELECT pg_temp.ver('B2');
SELECT pg_temp.pz('B2', 'P', 1);
SELECT pg_temp.un('B2', 'P', 1, 'Curvo', '{"medida": "10"}');
SELECT pg_temp.mu('B2', 'P', 2, 'elige_vendedor', 'Tir', '{"sin_eleccion": true}');
SELECT pg_temp.op('B2', 'B2.P.Tir', 1, 'Tirador');
SELECT pg_temp.mete('B2.c', 'catalogo_casos', 'B2', '{"nombre": "base"}');
SELECT pg_temp.publicar('B2');
SELECT pg_temp.caso('04 aviso Tirador', pg_temp.con_nombres('{}', jsonb_build_array(pg_temp.deja('B2', '{}', '{}', ARRAY['Zqx162 Tirador']))), pg_temp.aviso('Tirador', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja Tirador', 'ok', pg_temp.ins_activo('Tirador', false));
SELECT pg_temp.caso('04 B2 sigue con "sin elección"', 'activo', pg_temp.causa('B2'));
SELECT pg_temp.caso('04 reactivo Tirador', 'ok', pg_temp.ins_activo('Tirador', true));

-- A mano, y lo que ya estaba de baja
SELECT pg_temp.caso('04 Lucia da de baja B1', 'ok', pg_temp.paq('B1', false));
SELECT pg_temp.caso('04 a mano', 'a mano', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 una baja no le cambia el motivo', 'ok', pg_temp.ins_activo('Escuadra', false));
SELECT pg_temp.caso('04 sigue a mano', 'a mano', pg_temp.causa('B1'));
SELECT pg_temp.caso('04 aviso: de baja no cuenta', pg_temp.con_nombres('{}'), pg_temp.aviso('Enrollable', NULL, 'Lucia'));
SELECT pg_temp.caso('04 reactivo Escuadra', 'ok', pg_temp.ins_activo('Escuadra', true));
SELECT pg_temp.caso('04 reactivo B1', 'ok', pg_temp.paq('B1', true));

-- Sin nada que lo use, y lo obsoleto no cuenta
SELECT pg_temp.caso('04 aviso sin nada', pg_temp.con_nombres('{}'), pg_temp.aviso('Suelto', NULL, 'Lucia'));
SELECT pg_temp.chico('O', 'SoloV1');
SELECT pg_temp.publicar('O');
SELECT pg_temp.caso('04 aviso SoloV1', pg_temp.con_nombres(ARRAY['Zqx162 O']), pg_temp.aviso('SoloV1', NULL, 'Lucia'));
SELECT pg_temp.crear('O2', format('SELECT catalogo_version_nueva(%L)', pg_temp.paquete('O')));
SELECT pg_temp.caso('04 saca SoloV1', 'ok', pg_temp.intentar(format('UPDATE catalogo_materiales SET insumo_id = %s WHERE version_id = %s', pg_temp.l('Chico'), pg_temp.l('O2')), 'Lucia'));
SELECT pg_temp.publicar('O2');
SELECT pg_temp.caso('04 lo usa solo una obsoleta: nada', pg_temp.con_nombres('{}'), pg_temp.aviso('SoloV1', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja SoloV1', 'ok', pg_temp.ins_activo('SoloV1', false));
SELECT pg_temp.caso('04 O sigue', 'activo', pg_temp.causa('O2'));
SELECT pg_temp.caso('04 reactivo SoloV1', 'ok', pg_temp.ins_activo('SoloV1', true));

-- Un borrador o una en revisión no sacan nada de la venta: frena al enviar o al aprobar
SELECT pg_temp.chico('Br', 'Suelto');
SELECT pg_temp.chico('Rv', 'Suelto');
SELECT pg_temp.caso('04 Rv en revisión', 'ok', pg_temp.fn('enviar', 'Rv', 'Lucia'));
SELECT pg_temp.caso('04 aviso con borrador y en revisión', pg_temp.con_nombres('{}'), pg_temp.aviso('Suelto', NULL, 'Lucia'));
SELECT pg_temp.caso('04 baja Suelto', 'ok', pg_temp.ins_activo('Suelto', false));
SELECT pg_temp.caso('04 el borrador sigue', 'activo', pg_temp.causa('Br'));
SELECT pg_temp.caso('04 el otro también', 'activo', pg_temp.causa('Rv'));
SELECT pg_temp.dice('Br', 'Zqx162 Suelto está de baja');
SELECT pg_temp.caso('04 reactivo Suelto', 'ok', pg_temp.ins_activo('Suelto', true));

-- Sin publicada se reactiva sin revisar nada; dentro de una categoría de baja, no
SELECT pg_temp.ver('Sp');
SELECT pg_temp.caso('04 baja de un paquete sin publicada', 'ok', pg_temp.paq('Sp', false));
SELECT pg_temp.caso('04 se reactiva', 'ok', pg_temp.paq('Sp', true));
SELECT pg_temp.caso('04 activo', 'activo', pg_temp.causa('Sp'));

SELECT pg_temp.chico('Ct', 'Chico', 'Puertas');
SELECT pg_temp.publicar('Ct');
SELECT pg_temp.caso('04 Puertas con una publicada activa', 'CA007', pg_temp.intentar(format('UPDATE catalogo_categorias SET activo = false WHERE id = %s', pg_temp.l('Puertas')), 'Lucia'));
SELECT pg_temp.caso('04 Ct de baja', 'ok', pg_temp.paq('Ct', false));
SELECT pg_temp.caso('04 Puertas de baja', 'ok', pg_temp.intentar(format('UPDATE catalogo_categorias SET activo = false WHERE id = %s', pg_temp.l('Puertas')), 'Lucia'));
SELECT pg_temp.caso('04 Ct no se reactiva adentro de una de baja', 'CA008', pg_temp.paq('Ct', true));
SELECT pg_temp.caso('04 dice cuál', 'La categoría Zqx162 Puertas está de baja: reactivala primero',
  pg_temp.mensaje(format('UPDATE catalogo_paquetes SET activo = true WHERE id = %L', pg_temp.paquete('Ct')), 'Lucia'));
SELECT pg_temp.caso('04 reactivo Puertas', 'ok', pg_temp.intentar(format('UPDATE catalogo_categorias SET activo = true WHERE id = %s', pg_temp.l('Puertas')), 'Lucia'));
SELECT pg_temp.caso('04 ahora sí', 'ok', pg_temp.paq('Ct', true));

-- ============================================================
-- 5. Privilegios
-- ============================================================
SELECT pg_temp.caso('05 RLS en la historia', 'true', (SELECT c.relrowsecurity::text FROM pg_class c WHERE c.relname = 'catalogo_versiones_historia'));
SELECT pg_temp.caso('05 anon no llama ' || f, 'false', has_function_privilege('anon', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_version_revisar(uuid)', 'catalogo_version_oferta(uuid)', 'catalogo_version_enviar(uuid)',
                  'catalogo_version_retirar(uuid)', 'catalogo_version_devolver(uuid,text)', 'catalogo_version_aprobar(uuid)',
                  'catalogo_version_descartar(uuid)', 'catalogo_baja_aviso(uuid,uuid)']) AS f;
SELECT pg_temp.caso('05 authenticated no llama ' || f, 'false', has_function_privilege('authenticated', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_oferta(uuid,uuid,uuid)', 'catalogo_version_formulas(uuid)', 'catalogo_version_alcance(uuid)',
                  'catalogo_version_referencias(uuid)', 'catalogo_version_circular(uuid)', 'catalogo_version_insumos(uuid)',
                  'catalogo_version_frena(uuid)', 'catalogo_version_tomar(uuid,text,estado_version_catalogo)',
                  'catalogo_version_registrar(uuid,estado_version_catalogo,accion_version_catalogo,text)',
                  'catalogo_version_bloquear(uuid)', 'catalogo_version_exigir(uuid)', 'catalogo_baja_efecto(uuid,uuid)',
                  'catalogo_baja_cascada()', 'catalogo_paquete_reactivar()']) AS f;
SELECT pg_temp.caso('05 authenticated llama ' || f, 'true', has_function_privilege('authenticated', f, 'EXECUTE')::text)
FROM unnest(ARRAY['catalogo_version_revisar(uuid)', 'catalogo_version_oferta(uuid)', 'catalogo_version_enviar(uuid)',
                  'catalogo_version_retirar(uuid)', 'catalogo_version_devolver(uuid,text)', 'catalogo_version_aprobar(uuid)',
                  'catalogo_version_descartar(uuid)', 'catalogo_baja_aviso(uuid,uuid)']) AS f;

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
