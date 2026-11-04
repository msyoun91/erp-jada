-- Verificación de sql/159: registros del catálogo. NO es una migración: todo corre dentro de una
-- transacción que revierte. Termina en un DO que lanza "N / M ok" y los casos que fallan.
--
-- Mundo: Lucia (Técnica: Paquetes con armar, Insumos con cargar, Servicios fijos), Ana (Administración:
-- Insumos con costos, Servicios fijos con editar, Servicios en % con editar), Carlos (gerente: todas las
-- vistas, aprobar, costos, editar fijos y %), Marta (solo Insumos con costos), Rodrigo (solo Paquetes,
-- revisa cortes) y Juan (nada). Lo creado lleva Zqx159.
--
-- now() es el mismo en toda la transacción, y dos valores de lo mismo cargados acá empatarían. Por eso,
-- después de cada operación, lo recién cargado se manda a un día del pasado, cada vez más cerca de hoy.

BEGIN;

CREATE TEMP TABLE r (caso text, esperado text, obtenido text, ok boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (nombre text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON r, ids TO authenticated;
CREATE TEMP SEQUENCE pasos;

CREATE FUNCTION pg_temp.id(p_nombre text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM ids WHERE nombre = p_nombre;
$f$;

CREATE FUNCTION pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO r VALUES (p_caso, p_esperado, p_obtenido, p_esperado IS NOT DISTINCT FROM p_obtenido);
$f$;

CREATE FUNCTION pg_temp.atrasar() RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  v_fecha timestamptz := now() - (1000 - nextval('pasos')) * interval '1 day';
BEGIN
  UPDATE catalogo_costos SET created_at = v_fecha WHERE created_at = now();
  UPDATE catalogo_porcentajes_valores SET created_at = v_fecha WHERE created_at = now();
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
  PERFORM pg_temp.atrasar();
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
  PERFORM pg_temp.atrasar();
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', v_rol, true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN SQLSTATE;
END;
$f$;

CREATE FUNCTION pg_temp.ve(p_sql text, p_como text) RETURNS text LANGUAGE sql AS $f$
  SELECT pg_temp.consultar(format('SELECT count(*)::text FROM (%s) x', p_sql), p_como);
$f$;

-- Corre como p_como, guarda el uuid que devuelve p_sql con el nombre p_nombre y anota si salió.
CREATE FUNCTION pg_temp.crear(p_nombre text, p_sql text, p_como text) RETURNS void LANGUAGE plpgsql AS $f$
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

-- La variante de un insumo: sin color, la indistinta.
CREATE FUNCTION pg_temp.variante(p_insumo text, p_color text DEFAULT NULL) RETURNS uuid LANGUAGE sql AS $f$
  SELECT v.id FROM catalogo_variantes v
  WHERE v.insumo_id = pg_temp.id(p_insumo) AND v.color_id IS NOT DISTINCT FROM pg_temp.id(p_color);
$f$;

-- Un servicio en %: la llamada a guardar, con lo que no se pasa sin mínimo, general y no opcional.
CREATE FUNCTION pg_temp.guardar(p_id uuid, p_nombre text, p_pct numeric, p_paso int, p_confirmar boolean DEFAULT false)
RETURNS text LANGUAGE sql AS $f$
  SELECT format($q$SELECT catalogo_porcentaje_guardar(%L, %L, %s, %s, '{}', NULL, NULL, NULL, false, %L)$q$,
                p_id, p_nombre, p_pct, p_paso, p_confirmar);
$f$;

-- El último valor de un servicio: su id, para revertirlo.
CREATE FUNCTION pg_temp.ultimo(p_servicio text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT v.id FROM catalogo_porcentajes_valores v
  WHERE v.porcentaje_id = pg_temp.id(p_servicio) AND v.activo
  ORDER BY v.created_at DESC LIMIT 1;
$f$;

CREATE FUNCTION pg_temp.vigente(p_servicio text) RETURNS text LANGUAGE sql AS $f$
  SELECT v.porcentaje::numeric(7,1) || CASE WHEN v.de_baja THEN ' de baja' ELSE '' END
  FROM catalogo_porcentajes_vigentes() v WHERE v.porcentaje_id = pg_temp.id(p_servicio);
$f$;

-- ============================================================
-- Montaje
-- ============================================================
UPDATE catalogo_porcentajes_valores SET activo = false WHERE activo;

INSERT INTO ids (nombre, id)
SELECT n, gen_random_uuid() FROM unnest(ARRAY['Lucia','Ana','Carlos','Marta','Rodrigo','Juan']) AS n;

INSERT INTO ids (nombre, id) SELECT codigo, id FROM submodulos WHERE activo AND modulo = 'catalogo';

INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT id, lower(nombre) || '.' || id || '@test159.local', jsonb_build_object('nombre', 'test159 ' || nombre)
FROM ids WHERE nombre IN ('Lucia','Ana','Carlos','Marta','Rodrigo','Juan');

INSERT INTO usuario_submodulos (usuario_id, submodulo_id)
SELECT pg_temp.id(u), pg_temp.id(s) FROM (VALUES
  ('Lucia','catalogo_paquetes'), ('Lucia','catalogo_armar'), ('Lucia','catalogo_insumos'),
  ('Lucia','catalogo_cargar'), ('Lucia','catalogo_fijos'),
  ('Ana','catalogo_insumos'), ('Ana','catalogo_costos'), ('Ana','catalogo_fijos'),
  ('Ana','catalogo_fijos_editar'), ('Ana','catalogo_porcentajes'), ('Ana','catalogo_porcentajes_editar'),
  ('Carlos','catalogo_paquetes'), ('Carlos','catalogo_aprobar'), ('Carlos','catalogo_insumos'),
  ('Carlos','catalogo_costos'), ('Carlos','catalogo_fijos'), ('Carlos','catalogo_fijos_editar'),
  ('Carlos','catalogo_porcentajes'), ('Carlos','catalogo_porcentajes_editar'),
  ('Marta','catalogo_insumos'), ('Marta','catalogo_costos'),
  ('Rodrigo','catalogo_paquetes')
) AS p (u, s);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO monedas_tipos_cambio (moneda, valor, fecha, origen, vigente_desde) VALUES
  ('USD_OFICIAL', 1450, now(), 'monedapi', now()),
  ('USD_BLUE',    1500, now(), 'monedapi', now());

-- ============================================================
-- 01. Permisos sembrados
-- ============================================================
SELECT pg_temp.caso('01 cuatro vistas', '4', (SELECT count(*)::text FROM submodulos
  WHERE modulo = 'catalogo' AND activo AND tipo = 'vista' AND vista_id IS NULL));
SELECT pg_temp.caso('01 seis funciones', '6', (SELECT count(*)::text FROM submodulos
  WHERE modulo = 'catalogo' AND activo AND tipo = 'funcion' AND vista_id IS NOT NULL));
SELECT pg_temp.caso('01 solo aprobar no se delega', 'catalogo_aprobar', (SELECT string_agg(codigo, ',') FROM submodulos
  WHERE modulo = 'catalogo' AND activo AND NOT delegable));
SELECT pg_temp.caso('01 costos cuelga de Insumos', 'catalogo_insumos', (SELECT v.codigo FROM submodulos f
  JOIN submodulos v ON v.id = f.vista_id WHERE f.codigo = 'catalogo_costos' AND f.activo));

-- ============================================================
-- 02. Categorías: cada tipo, quien la define
-- ============================================================
SELECT pg_temp.crear('Vidrios', $q$INSERT INTO catalogo_categorias (tipo, nombre)
  VALUES ('insumo', 'Zqx159 Vidrios') RETURNING id$q$, 'Lucia');
SELECT pg_temp.crear('Herrajes', $q$INSERT INTO catalogo_categorias (tipo, nombre)
  VALUES ('insumo', 'Zqx159 Herrajes') RETURNING id$q$, 'Lucia');
SELECT pg_temp.crear('Ventanas', $q$INSERT INTO catalogo_categorias (tipo, nombre)
  VALUES ('paquete', 'Zqx159 Ventanas') RETURNING id$q$, 'Lucia');
SELECT pg_temp.crear('Instalacion', $q$INSERT INTO catalogo_categorias (tipo, nombre)
  VALUES ('servicio', 'Zqx159 Instalación') RETURNING id$q$, 'Ana');

SELECT pg_temp.caso('02 Lucia no crea categorías de servicio', '42501', pg_temp.intentar(
  $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('servicio', 'Zqx159 No')$q$, 'Lucia'));
SELECT pg_temp.caso('02 Ana no crea categorías de insumo', '42501', pg_temp.intentar(
  $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx159 No')$q$, 'Ana'));
SELECT pg_temp.caso('02 Ana no crea categorías de paquete', '42501', pg_temp.intentar(
  $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('paquete', 'Zqx159 No')$q$, 'Ana'));
SELECT pg_temp.caso('02 Juan no crea', '42501', pg_temp.intentar(
  $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx159 No')$q$, 'Juan'));

SELECT pg_temp.caso('02 Juan no las ve', '0', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_categorias WHERE nombre LIKE 'Zqx159%'$q$, 'Juan'));
SELECT pg_temp.caso('02 Rodrigo, con solo Paquetes, las ve', '4', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_categorias WHERE nombre LIKE 'Zqx159%'$q$, 'Rodrigo'));

SELECT pg_temp.caso('02 nombre repetido en el tipo', '23505', pg_temp.intentar(
  $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'Zqx159 Vidrios')$q$, 'Lucia'));
SELECT pg_temp.caso('02 repetido sin distinguir mayúsculas', '23505', pg_temp.intentar(
  $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', 'ZQX159 VIDRIOS')$q$, 'Lucia'));
SELECT pg_temp.crear('Vidrios paquete', $q$INSERT INTO catalogo_categorias (tipo, nombre)
  VALUES ('paquete', 'Zqx159 Vidrios') RETURNING id$q$, 'Lucia');
SELECT pg_temp.caso('02 nombre con espacios sobrantes', '23514', pg_temp.intentar(
  $q$INSERT INTO catalogo_categorias (tipo, nombre) VALUES ('insumo', ' Zqx159 Espacios')$q$, 'Lucia'));

SELECT pg_temp.caso('02 no se cambia el tipo', '42501', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET tipo = 'paquete' WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('02 no se borra', '42501', pg_temp.intentar(format(
  $q$DELETE FROM catalogo_categorias WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));

SELECT pg_temp.caso('02 vacía se renombra', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET nombre = 'Zqx159 Vidrio' WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('02 Ana no la toca: 0 filas, sin error', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET nombre = 'Zqx159 Ana' WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Ana'));
SELECT pg_temp.caso('02 sigue como la dejó Lucia', 'Zqx159 Vidrio', (SELECT nombre FROM catalogo_categorias
  WHERE id = pg_temp.id('Vidrios')));
SELECT pg_temp.caso('02 Lucia no toca una de servicio: 0 filas', 'Zqx159 Instalación', (
  SELECT CASE WHEN pg_temp.intentar(format(
    $q$UPDATE catalogo_categorias SET nombre = 'Zqx159 Lucia' WHERE id = %L$q$, pg_temp.id('Instalacion')), 'Lucia') = 'ok'
  THEN (SELECT nombre FROM catalogo_categorias WHERE id = pg_temp.id('Instalacion')) END));

-- ============================================================
-- 03. Colores: lista común de Técnica
-- ============================================================
SELECT pg_temp.crear('Blanco', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx159 Blanco') RETURNING id$q$, 'Lucia');
SELECT pg_temp.crear('Negro', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx159 Negro') RETURNING id$q$, 'Lucia');
SELECT pg_temp.crear('Anodizado', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx159 Anodizado') RETURNING id$q$, 'Lucia');
SELECT pg_temp.caso('03 Ana no crea colores', '42501', pg_temp.intentar(
  $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx159 No')$q$, 'Ana'));
SELECT pg_temp.caso('03 color repetido', '23505', pg_temp.intentar(
  $q$INSERT INTO catalogo_colores (nombre) VALUES ('zqx159 blanco')$q$, 'Lucia'));
SELECT pg_temp.caso('03 Ana los ve', '3', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_colores WHERE nombre LIKE 'Zqx159%'$q$, 'Ana'));
SELECT pg_temp.caso('03 sin usar se renombra', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_colores SET nombre = 'Zqx159 Anodizado natural' WHERE id = %L$q$, pg_temp.id('Anodizado')), 'Lucia'));

-- ============================================================
-- 04. El insumo: nace con sus variantes
-- ============================================================
SELECT pg_temp.crear('Float', format(
  $q$SELECT catalogo_insumo_alta('Zqx159 Float 4mm', %L, 'm2', 10, 4)$q$, pg_temp.id('Vidrios')), 'Lucia');
SELECT pg_temp.crear('Perfil', format(
  $q$SELECT catalogo_insumo_alta('Zqx159 Perfil hoja', %L, 'mm', 0.7, NULL, ARRAY[%L, %L]::uuid[])$q$,
  pg_temp.id('Herrajes'), pg_temp.id('Blanco'), pg_temp.id('Negro')), 'Lucia');

SELECT pg_temp.caso('04 indistinto: una variante sin color', '1', (SELECT count(*)::text FROM catalogo_variantes v
  WHERE v.insumo_id = pg_temp.id('Float') AND v.color_id IS NULL AND v.activo));
SELECT pg_temp.caso('04 indistinto: sin marca de color', 'false', (SELECT con_color::text FROM catalogo_insumos
  WHERE id = pg_temp.id('Float')));
SELECT pg_temp.caso('04 con colores: dos variantes', '2', (SELECT count(*)::text FROM catalogo_variantes v
  WHERE v.insumo_id = pg_temp.id('Perfil') AND v.color_id IS NOT NULL AND v.activo));
SELECT pg_temp.caso('04 con colores: ninguna indistinta', '0', (SELECT count(*)::text FROM catalogo_variantes v
  WHERE v.insumo_id = pg_temp.id('Perfil') AND v.color_id IS NULL));

SELECT pg_temp.caso('04 Ana no da de alta insumos', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('Zqx159 No', %L, 'u', NULL, NULL)$q$, pg_temp.id('Vidrios')), 'Ana'));
SELECT pg_temp.caso('04 en una categoría de paquete, no', '23503', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('Zqx159 No', %L, 'u', NULL, NULL)$q$, pg_temp.id('Ventanas')), 'Lucia'));
SELECT pg_temp.caso('04 en una categoría de servicio, no', '23503', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('Zqx159 No', %L, 'u', NULL, NULL)$q$, pg_temp.id('Instalacion')), 'Lucia'));
SELECT pg_temp.caso('04 nombre repetido', '23505', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('zqx159 float 4MM', %L, 'm2', NULL, NULL)$q$, pg_temp.id('Herrajes')), 'Lucia'));
SELECT pg_temp.caso('04 peso negativo', '23514', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('Zqx159 No', %L, 'u', -1, NULL)$q$, pg_temp.id('Herrajes')), 'Lucia'));
SELECT pg_temp.crear('Tornillo', format(
  $q$SELECT catalogo_insumo_alta('Zqx159 Tornillo', %L, 'u', 0, NULL)$q$, pg_temp.id('Herrajes')), 'Lucia');
SELECT pg_temp.caso('04 peso 0 es un dato: no queda vacío', '0.0000', (SELECT peso::text FROM catalogo_insumos
  WHERE id = pg_temp.id('Tornillo')));
SELECT pg_temp.caso('04 unidad que no existe', '22P02', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('Zqx159 No', %L, 'barra', NULL, NULL)$q$, pg_temp.id('Herrajes')), 'Lucia'));
SELECT pg_temp.caso('04 no se cambia el tipo', '42501', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET tipo = 'servicio' WHERE id = %L$q$, pg_temp.id('Float')), 'Lucia'));

SELECT pg_temp.caso('04 Rodrigo lee el nombre', '1', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_insumos WHERE nombre = 'Zqx159 Float 4mm'$q$, 'Rodrigo'));
SELECT pg_temp.caso('04 Juan no', '0', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_insumos WHERE nombre = 'Zqx159 Float 4mm'$q$, 'Juan'));
SELECT pg_temp.caso('04 Ana no lo edita: 0 filas', 'Zqx159 Float 4mm', (
  SELECT CASE WHEN pg_temp.intentar(format(
    $q$UPDATE catalogo_insumos SET nombre = 'Zqx159 Ana' WHERE id = %L$q$, pg_temp.id('Float')), 'Ana') = 'ok'
  THEN (SELECT nombre FROM catalogo_insumos WHERE id = pg_temp.id('Float')) END));

-- ============================================================
-- 05. Categorías y colores con algo adentro
-- ============================================================
SELECT pg_temp.caso('05 categoría con insumos: nombre fijo', 'CA006', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET nombre = 'Zqx159 Cristales' WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('05 categoría con insumos activos: sin baja', 'CA007', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET activo = false WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('05 color en uso: nombre fijo', 'CA006', pg_temp.intentar(format(
  $q$UPDATE catalogo_colores SET nombre = 'Zqx159 Negro mate' WHERE id = %L$q$, pg_temp.id('Negro')), 'Lucia'));
SELECT pg_temp.caso('05 color con variantes activas: sin baja', 'CA007', pg_temp.intentar(format(
  $q$UPDATE catalogo_colores SET activo = false WHERE id = %L$q$, pg_temp.id('Negro')), 'Lucia'));

SELECT pg_temp.caso('05 Float de baja', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET activo = false WHERE id = %L$q$, pg_temp.id('Float')), 'Lucia'));
SELECT pg_temp.caso('05 con el insumo de baja, el nombre sigue fijo', 'CA006', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET nombre = 'Zqx159 Cristales' WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('05 sin nada activo adentro: baja', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET activo = false WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('05 no se reactiva adentro de una categoría de baja', 'CA008', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET activo = true WHERE id = %L$q$, pg_temp.id('Float')), 'Lucia'));
SELECT pg_temp.caso('05 no se da de alta adentro', 'CA008', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('Zqx159 No', %L, 'u', NULL, NULL)$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('05 no se mueve adentro', 'CA008', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET categoria_id = %L WHERE id = %L$q$, pg_temp.id('Vidrios'), pg_temp.id('Tornillo')), 'Lucia'));
SELECT pg_temp.caso('05 se reactiva la categoría', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET activo = true WHERE id = %L$q$, pg_temp.id('Vidrios')), 'Lucia'));
SELECT pg_temp.caso('05 y después el insumo', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET activo = true WHERE id = %L$q$, pg_temp.id('Float')), 'Lucia'));

SELECT pg_temp.caso('05 de baja, el nombre se reutiliza', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET activo = false WHERE id = %L;
     SELECT catalogo_insumo_alta('Zqx159 Tornillo', %L, 'u', NULL, NULL)$q$,
  pg_temp.id('Tornillo'), pg_temp.id('Herrajes')), 'Lucia'));
SELECT pg_temp.caso('05 reactivar con el nombre ocupado', '23505', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET activo = true WHERE id = %L$q$, pg_temp.id('Tornillo')), 'Lucia'));

-- ============================================================
-- 06. Variantes: se suman y se bajan, una fila por color para siempre
-- ============================================================
SELECT pg_temp.caso('06 Ana no suma colores', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Perfil'), pg_temp.id('Anodizado')), 'Ana'));
SELECT pg_temp.caso('06 Lucia suma Anodizado', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Perfil'), pg_temp.id('Anodizado')), 'Lucia'));
SELECT pg_temp.caso('06 a un indistinto no se le suma color', 'CA009', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Float'), pg_temp.id('Blanco')), 'Lucia'));
SELECT pg_temp.caso('06 a uno con colores no se le suma indistinta', 'CA009', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, NULL)$q$, pg_temp.id('Perfil')), 'Lucia'));
SELECT pg_temp.caso('06 la indistinta no se baja sola', 'CA009', pg_temp.intentar(format(
  $q$UPDATE catalogo_variantes SET activo = false WHERE id = %L$q$, pg_temp.variante('Float')), 'Lucia'));
SELECT pg_temp.caso('06 no se cambia el color de una variante', '42501', pg_temp.intentar(format(
  $q$UPDATE catalogo_variantes SET color_id = %L WHERE id = %L$q$,
  pg_temp.id('Blanco'), pg_temp.variante('Perfil', 'Negro')), 'Lucia'));

INSERT INTO ids VALUES ('Perfil negro', pg_temp.variante('Perfil', 'Negro'));
SELECT pg_temp.caso('06 Negro de baja', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_variantes SET activo = false WHERE id = %L$q$, pg_temp.id('Perfil negro')), 'Lucia'));
SELECT pg_temp.caso('06 el insumo sigue activo', 'true', (SELECT activo::text FROM catalogo_insumos
  WHERE id = pg_temp.id('Perfil')));
SELECT pg_temp.caso('06 volver a sumarlo reactiva la misma fila', 'true', (
  SELECT (pg_temp.consultar(format($q$SELECT catalogo_variante_sumar(%L, %L)$q$,
          pg_temp.id('Perfil'), pg_temp.id('Negro')), 'Lucia')::uuid = pg_temp.id('Perfil negro'))::text));
SELECT pg_temp.caso('06 y queda activa', 'true', (SELECT activo::text FROM catalogo_variantes
  WHERE id = pg_temp.id('Perfil negro')));

SELECT pg_temp.crear('Rojo', $q$INSERT INTO catalogo_colores (nombre) VALUES ('Zqx159 Rojo') RETURNING id$q$, 'Lucia');
SELECT pg_temp.caso('06 Rojo en el perfil', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Perfil'), pg_temp.id('Rojo')), 'Lucia'));
SELECT pg_temp.caso('06 baja de la variante Rojo', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_variantes SET activo = false WHERE id = %L$q$, pg_temp.variante('Perfil', 'Rojo')), 'Lucia'));
SELECT pg_temp.caso('06 color sin variantes activas: baja', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_colores SET activo = false WHERE id = %L$q$, pg_temp.id('Rojo')), 'Lucia'));
SELECT pg_temp.caso('06 no se reactiva una variante de un color de baja', 'CA008', pg_temp.intentar(format(
  $q$UPDATE catalogo_variantes SET activo = true WHERE id = %L$q$, pg_temp.variante('Perfil', 'Rojo')), 'Lucia'));
SELECT pg_temp.caso('06 ni sumándola de nuevo', 'CA008', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Perfil'), pg_temp.id('Rojo')), 'Lucia'));
SELECT pg_temp.caso('06 en un color de baja no se da de alta', 'CA008', pg_temp.intentar(format(
  $q$SELECT catalogo_insumo_alta('Zqx159 No', %L, 'u', NULL, NULL, ARRAY[%L]::uuid[])$q$,
  pg_temp.id('Herrajes'), pg_temp.id('Rojo')), 'Lucia'));
SELECT pg_temp.caso('06 el alta frenada no deja el insumo', '0', (SELECT count(*)::text FROM catalogo_insumos
  WHERE nombre = 'Zqx159 No'));

-- Tener color o ser indistinto se cambia, hasta que sql/160 lo fije.
SELECT pg_temp.crear('Bisagra', format(
  $q$SELECT catalogo_insumo_alta('Zqx159 Bisagra', %L, 'u', NULL, NULL)$q$, pg_temp.id('Herrajes')), 'Lucia');
INSERT INTO ids VALUES ('Bisagra indistinta', pg_temp.variante('Bisagra'));
SELECT pg_temp.caso('06 pasa a tener colores', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET con_color = true WHERE id = %L$q$, pg_temp.id('Bisagra')), 'Lucia'));
SELECT pg_temp.caso('06 se apaga la indistinta', 'false', (SELECT activo::text FROM catalogo_variantes
  WHERE id = pg_temp.id('Bisagra indistinta')));
SELECT pg_temp.caso('06 suma Blanco', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Bisagra'), pg_temp.id('Blanco')), 'Lucia'));
SELECT pg_temp.caso('06 vuelve a indistinto', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET con_color = false WHERE id = %L$q$, pg_temp.id('Bisagra')), 'Lucia'));
SELECT pg_temp.caso('06 se apaga el Blanco', 'false', (SELECT activo::text FROM catalogo_variantes
  WHERE id = pg_temp.variante('Bisagra', 'Blanco')));
SELECT pg_temp.caso('06 vuelve la misma indistinta', 'true', (SELECT activo::text FROM catalogo_variantes
  WHERE id = pg_temp.id('Bisagra indistinta')));

-- ============================================================
-- 07. El servicio fijo: nace con su costo, de la mano de Administración
-- ============================================================
SELECT pg_temp.crear('Soldado', format(
  $q$SELECT catalogo_fijo_alta('Zqx159 Soldado', %L, 'u', 1000, 'ARS')$q$, pg_temp.id('Instalacion')), 'Ana');
SELECT pg_temp.caso('07 una variante sin color', '1', (SELECT count(*)::text FROM catalogo_variantes
  WHERE insumo_id = pg_temp.id('Soldado') AND color_id IS NULL));
SELECT pg_temp.caso('07 con su costo', '1000.0000', (SELECT c.costo::text FROM catalogo_costos c
  WHERE c.variante_id = pg_temp.variante('Soldado')));
SELECT pg_temp.caso('07 quién lo cargó', 'true', (SELECT (c.creado_por = pg_temp.id('Ana'))::text FROM catalogo_costos c
  WHERE c.variante_id = pg_temp.variante('Soldado')));
SELECT pg_temp.caso('07 Lucia no da de alta servicios', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_fijo_alta('Zqx159 No', %L, 'u', 1000, 'ARS')$q$, pg_temp.id('Instalacion')), 'Lucia'));
SELECT pg_temp.caso('07 Marta tampoco', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_fijo_alta('Zqx159 No', %L, 'u', 1000, 'ARS')$q$, pg_temp.id('Instalacion')), 'Marta'));
SELECT pg_temp.caso('07 en una categoría de insumo, no', '23503', pg_temp.intentar(format(
  $q$SELECT catalogo_fijo_alta('Zqx159 No', %L, 'u', 1000, 'ARS')$q$, pg_temp.id('Vidrios')), 'Ana'));
SELECT pg_temp.caso('07 sin costo no nace', '23502', pg_temp.intentar(format(
  $q$SELECT catalogo_fijo_alta('Zqx159 No', %L, 'u', NULL, 'ARS')$q$, pg_temp.id('Instalacion')), 'Ana'));
SELECT pg_temp.caso('07 frenado, no queda el servicio', '0', (SELECT count(*)::text FROM catalogo_insumos
  WHERE nombre = 'Zqx159 No'));
SELECT pg_temp.caso('07 no lleva peso', '23514', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET peso = 1 WHERE id = %L$q$, pg_temp.id('Soldado')), 'Ana'));
SELECT pg_temp.caso('07 no lleva colores', '23514', pg_temp.intentar(format(
  $q$UPDATE catalogo_insumos SET con_color = true WHERE id = %L$q$, pg_temp.id('Soldado')), 'Ana'));
SELECT pg_temp.caso('07 sumarle un color, tampoco', 'CA009', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Soldado'), pg_temp.id('Blanco')), 'Ana'));
SELECT pg_temp.caso('07 Lucia lo ve', '1', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_insumos WHERE nombre = 'Zqx159 Soldado'$q$, 'Lucia'));
SELECT pg_temp.caso('07 Lucia no lo edita: 0 filas', 'Zqx159 Soldado', (
  SELECT CASE WHEN pg_temp.intentar(format(
    $q$UPDATE catalogo_insumos SET nombre = 'Zqx159 Lucia' WHERE id = %L$q$, pg_temp.id('Soldado')), 'Lucia') = 'ok'
  THEN (SELECT nombre FROM catalogo_insumos WHERE id = pg_temp.id('Soldado')) END));
SELECT pg_temp.caso('07 mismo nombre que un insumo: vale', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_fijo_alta('Zqx159 Bisagra', %L, 'u', 1, 'ARS')$q$, pg_temp.id('Instalacion')), 'Ana'));

-- ============================================================
-- 08. Costos: quién los ve y quién los carga
-- ============================================================
INSERT INTO ids VALUES ('v Float', pg_temp.variante('Float'));
INSERT INTO ids VALUES ('v Soldado', pg_temp.variante('Soldado'));
INSERT INTO ids VALUES ('v Blanco', pg_temp.variante('Perfil', 'Blanco'));
INSERT INTO ids VALUES ('v Negro', pg_temp.variante('Perfil', 'Negro'));

SELECT pg_temp.caso('08 nadie inserta directo', '42501', pg_temp.intentar(format(
  $q$INSERT INTO catalogo_costos (variante_id, costo, moneda, creado_por) VALUES (%L, 1, 'ARS', %L)$q$,
  pg_temp.id('v Float'), pg_temp.id('Ana')), 'Ana'));
SELECT pg_temp.caso('08 Lucia no carga', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":1000,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Float')), 'Lucia'));
SELECT pg_temp.caso('08 Marta carga el de un insumo', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":1000,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Float')), 'Marta'));
SELECT pg_temp.caso('08 Marta no carga el de un servicio', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":1100,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Soldado')), 'Marta'));
SELECT pg_temp.caso('08 una variante que no existe', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":1,"moneda":"ARS"}]')$q$,
  gen_random_uuid()), 'Ana'));
SELECT pg_temp.caso('08 en bloque: una prohibida frena todas', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":500,"moneda":"ARS"},
                                     {"variante_id":"%s","costo":1100,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Blanco'), pg_temp.id('v Soldado')), 'Marta'));
SELECT pg_temp.caso('08 no quedó la del insumo', '0', (SELECT count(*)::text FROM catalogo_costos
  WHERE variante_id = pg_temp.id('v Blanco')));
SELECT pg_temp.caso('08 costo 0, no', '23514', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":0,"moneda":"ARS"}]', true)$q$,
  pg_temp.id('v Blanco')), 'Ana'));
SELECT pg_temp.caso('08 sin moneda, no', '23502', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":1}]')$q$,
  pg_temp.id('v Blanco')), 'Ana'));

SELECT pg_temp.caso('08 Lucia no ve ningún costo', '0', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_costos WHERE variante_id IN (%L, %L)$q$, pg_temp.id('v Float'), pg_temp.id('v Soldado')), 'Lucia'));
SELECT pg_temp.caso('08 Lucia, tampoco por los vigentes', '0', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_costos_vigentes() WHERE variante_id IN (%L, %L)$q$, pg_temp.id('v Float'), pg_temp.id('v Soldado')), 'Lucia'));
SELECT pg_temp.caso('08 Rodrigo, tampoco', '0', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_costos WHERE variante_id IN (%L, %L)$q$, pg_temp.id('v Float'), pg_temp.id('v Soldado')), 'Rodrigo'));
SELECT pg_temp.caso('08 Marta ve el del insumo, no el del servicio', '1', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_costos WHERE variante_id IN (%L, %L)$q$, pg_temp.id('v Float'), pg_temp.id('v Soldado')), 'Marta'));
SELECT pg_temp.caso('08 Ana ve los dos', '2', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_costos WHERE variante_id IN (%L, %L)$q$, pg_temp.id('v Float'), pg_temp.id('v Soldado')), 'Ana'));

-- ============================================================
-- 09. Los tres niveles, y el rojo pide confirmar
-- ============================================================
-- Float vale 1000 ARS.
CREATE FUNCTION pg_temp.nivel(p_variante text, p_costo numeric, p_moneda text) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(pg_temp.consultar(format(
    $q$SELECT nivel FROM catalogo_costos_niveles('[{"variante_id":"%s","costo":%s,"moneda":"%s"}]')$q$,
    pg_temp.id(p_variante), p_costo, p_moneda), 'Ana'), 'sin color');
$f$;

SELECT pg_temp.caso('09 +10 %', 'sin color', pg_temp.nivel('v Float', 1100, 'ARS'));
SELECT pg_temp.caso('09 +15 %', 'amarillo', pg_temp.nivel('v Float', 1150, 'ARS'));
SELECT pg_temp.caso('09 +25 %', 'naranja', pg_temp.nivel('v Float', 1250, 'ARS'));
SELECT pg_temp.caso('09 +50 %', 'rojo', pg_temp.nivel('v Float', 1500, 'ARS'));
SELECT pg_temp.caso('09 −60 %', 'rojo', pg_temp.nivel('v Float', 400, 'ARS'));
SELECT pg_temp.caso('09 sin costo anterior no avisa', 'sin color', pg_temp.nivel('v Blanco', 99999, 'ARS'));

SELECT pg_temp.caso('09 rojo sin confirmar', 'CA003', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":10000,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Float')), 'Ana'));
SELECT pg_temp.caso('09 no se guardó', '1', (SELECT count(*)::text FROM catalogo_costos
  WHERE variante_id = pg_temp.id('v Float')));
SELECT pg_temp.caso('09 amarillo guarda sin pedir', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":1200,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Float')), 'Ana'));
SELECT pg_temp.caso('09 el anterior sigue', '2', (SELECT count(*)::text FROM catalogo_costos
  WHERE variante_id = pg_temp.id('v Float')));
SELECT pg_temp.caso('09 confirmado guarda', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":2000,"moneda":"ARS"}]', true)$q$,
  pg_temp.id('v Float')), 'Ana'));

-- En otra moneda se compara pasándolo a la nueva: USD 12 oficial son $17.400.
SELECT pg_temp.caso('09 Blanco en USD', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":12,"moneda":"USD_OFICIAL"}]')$q$,
  pg_temp.id('v Blanco')), 'Ana'));
SELECT pg_temp.caso('09 USD 12 → $18.000 es +3 %', 'sin color', pg_temp.nivel('v Blanco', 18000, 'ARS'));
SELECT pg_temp.caso('09 USD 12 → $180.000 es rojo', 'rojo', pg_temp.nivel('v Blanco', 180000, 'ARS'));
SELECT pg_temp.caso('09 USD 12 oficial → USD 12 blue es +3 %', 'sin color',
  pg_temp.nivel('v Blanco', 12, 'USD_BLUE'));

-- En bloque se guardan juntas, cada una con su moneda; el rojo frena la lista entera.
SELECT pg_temp.caso('09 bloque con un rojo', 'CA003', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":13,"moneda":"USD_OFICIAL"},
                                     {"variante_id":"%s","costo":800,"moneda":"ARS"},
                                     {"variante_id":"%s","costo":100,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Blanco'), pg_temp.id('v Negro'), pg_temp.id('v Float')), 'Ana'));
SELECT pg_temp.caso('09 no se guardó ninguna', '0', (SELECT count(*)::text FROM catalogo_costos
  WHERE variante_id = pg_temp.id('v Negro')));
SELECT pg_temp.caso('09 bloque confirmado: cuántas', '3', pg_temp.consultar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":13,"moneda":"USD_OFICIAL"},
                                     {"variante_id":"%s","costo":800,"moneda":"ARS"},
                                     {"variante_id":"%s","costo":100,"moneda":"ARS"}]', true)::text$q$,
  pg_temp.id('v Blanco'), pg_temp.id('v Negro'), pg_temp.id('v Float')), 'Ana'));
SELECT pg_temp.caso('09 el vigente del Float', '100.0000 ARS', pg_temp.consultar(format(
  $q$SELECT costo || ' ' || moneda FROM catalogo_costos_vigentes() WHERE variante_id = %L$q$, pg_temp.id('v Float')), 'Ana'));
SELECT pg_temp.caso('09 el vigente del Blanco, en su moneda', '13.0000 USD_OFICIAL', pg_temp.consultar(format(
  $q$SELECT costo || ' ' || moneda FROM catalogo_costos_vigentes() WHERE variante_id = %L$q$, pg_temp.id('v Blanco')), 'Ana'));

-- A una fecha rige el que valía entonces.
SELECT pg_temp.caso('09 cuatro valores del Float', '4', (SELECT count(*)::text FROM catalogo_costos
  WHERE variante_id = pg_temp.id('v Float')));
SELECT pg_temp.caso('09 a la fecha del segundo, el segundo', '1200.0000', pg_temp.consultar(format(
  $q$SELECT costo::text FROM catalogo_costos_vigentes(%L) WHERE variante_id = %L$q$,
  (SELECT c.created_at FROM catalogo_costos c WHERE c.variante_id = pg_temp.id('v Float') ORDER BY c.created_at OFFSET 1 LIMIT 1),
  pg_temp.id('v Float')), 'Ana'));
SELECT pg_temp.caso('09 antes del primero, sin costo', '0', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_costos_vigentes(now() - interval '1001 days') WHERE variante_id = %L$q$, pg_temp.id('v Float')), 'Ana'));

-- Una variante de baja conserva su costo, y al volver lo trae.
SELECT pg_temp.caso('09 Negro de baja', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_variantes SET activo = false WHERE id = %L$q$, pg_temp.id('v Negro')), 'Lucia'));
SELECT pg_temp.caso('09 Negro de vuelta', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_variante_sumar(%L, %L)$q$, pg_temp.id('Perfil'), pg_temp.id('Negro')), 'Lucia'));
SELECT pg_temp.caso('09 con su costo', '800.0000', pg_temp.consultar(format(
  $q$SELECT costo::text FROM catalogo_costos_vigentes() WHERE variante_id = %L$q$, pg_temp.id('v Negro')), 'Ana'));

-- La misma variante dos veces no llega al 23505 del UNIQUE (sql/178).
SELECT pg_temp.caso('09 variante repetida', 'CA026', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":810,"moneda":"ARS"},
                                     {"variante_id":"%s","costo":820,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Negro'), pg_temp.id('v Negro')), 'Ana'));
SELECT pg_temp.caso('09 la repetida no guardó', '800.0000', pg_temp.consultar(format(
  $q$SELECT costo::text FROM catalogo_costos_vigentes() WHERE variante_id = %L$q$, pg_temp.id('v Negro')), 'Ana'));

-- Sin tipo de cambio, el nivel va sin color y no frena la carga (sql/178). En la base real EUR tiene tipos de cambio.
UPDATE monedas_tipos_cambio SET activo = false WHERE moneda = 'EUR';
SELECT pg_temp.caso('09 sin tipo de cambio: sin color', 'sin color', pg_temp.nivel('v Float', 1, 'EUR'));
SELECT pg_temp.caso('09 sin tipo de cambio: el rojo de otra fila frena igual', 'CA003', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":5,"moneda":"EUR"},
                                     {"variante_id":"%s","costo":10000,"moneda":"ARS"}]')$q$,
  pg_temp.id('v Blanco'), pg_temp.id('v Float')), 'Ana'));
SELECT pg_temp.caso('09 sin tipo de cambio: se guarda', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_costos_cargar('[{"variante_id":"%s","costo":5,"moneda":"EUR"}]')$q$,
  pg_temp.id('v Blanco')), 'Ana'));
SELECT pg_temp.caso('09 sin tipo de cambio: el vigente', '5.0000 EUR', pg_temp.consultar(format(
  $q$SELECT costo || ' ' || moneda FROM catalogo_costos_vigentes() WHERE variante_id = %L$q$, pg_temp.id('v Blanco')), 'Ana'));
SELECT pg_temp.caso('09 sin tipo de cambio del anterior: sin color', 'sin color', pg_temp.nivel('v Blanco', 1000, 'ARS'));
SELECT pg_temp.caso('09 en la misma moneda compara igual', 'rojo', pg_temp.nivel('v Blanco', 50, 'EUR'));

-- ============================================================
-- 10. Servicios en %: quién los ve y las reglas de cada dato
-- ============================================================
SELECT pg_temp.crear('Comercializacion', pg_temp.guardar(NULL, 'Zqx159 Comercialización', 10, 1), 'Ana');
SELECT pg_temp.crear('Garantia', format(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 Garantía', 5, 1, ARRAY[%L]::uuid[], 10000, 'ARS', 'presupuesto', false)$q$,
  pg_temp.id('Vidrios')), 'Ana');
SELECT pg_temp.crear('Transicion', pg_temp.guardar(NULL, 'Zqx159 Transición', 4, 2), 'Carlos');
SELECT pg_temp.crear('IIBB', pg_temp.guardar(NULL, 'Zqx159 IIBB', 60, 3), 'Ana');

SELECT pg_temp.caso('10 Lucia no da de alta', '42501', pg_temp.intentar(
  pg_temp.guardar(NULL, 'Zqx159 No', 1, 1), 'Lucia'));
SELECT pg_temp.caso('10 Marta tampoco', '42501', pg_temp.intentar(
  pg_temp.guardar(NULL, 'Zqx159 No', 1, 1), 'Marta'));
SELECT pg_temp.caso('10 nadie inserta directo', '42501', pg_temp.intentar(
  'INSERT INTO catalogo_porcentajes DEFAULT VALUES', 'Ana'));
SELECT pg_temp.caso('10 ni al registro privado', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_registrar(v) FROM catalogo_porcentajes_valores v WHERE v.id = %L$q$,
  pg_temp.ultimo('Comercializacion')), 'Ana'));
SELECT pg_temp.caso('10 Lucia no los ve', '0', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_porcentajes_valores WHERE nombre LIKE 'Zqx159%'$q$, 'Lucia'));
SELECT pg_temp.caso('10 Lucia, tampoco por los vigentes', '0', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_porcentajes_vigentes() WHERE nombre LIKE 'Zqx159%'$q$, 'Lucia'));
SELECT pg_temp.caso('10 Lucia, tampoco por la historia', '0', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_porcentajes_historia(%L)$q$, pg_temp.id('Garantia')), 'Lucia'));
SELECT pg_temp.caso('10 Ana los ve', '4', pg_temp.ve(
  $q$SELECT 1 FROM catalogo_porcentajes_vigentes() WHERE nombre LIKE 'Zqx159%'$q$, 'Ana'));

SELECT pg_temp.caso('10 sobre una categoría de paquete, no', 'CA011', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 No', 1, 1, ARRAY[%L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Ventanas')), 'Ana'));
SELECT pg_temp.caso('10 sobre una categoría que no existe, no', 'CA011', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 No', 1, 1, ARRAY[%L]::uuid[], NULL, NULL, NULL, false)$q$,
  gen_random_uuid()), 'Ana'));
SELECT pg_temp.caso('10 sobre una de servicio, sí', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 Seguro', 2, 1, ARRAY[%L]::uuid[], NULL, NULL, NULL, true)$q$,
  pg_temp.id('Instalacion')), 'Ana'));
SELECT pg_temp.caso('10 categorías solo en el paso 1', '23514', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 No', 1, 2, ARRAY[%L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Vidrios')), 'Ana'));
SELECT pg_temp.caso('10 paso 4 no existe', '23514', pg_temp.intentar(
  pg_temp.guardar(NULL, 'Zqx159 No', 1, 4), 'Ana'));
SELECT pg_temp.caso('10 mínimo sin moneda', '23514', pg_temp.intentar(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 No', 1, 1, '{}', 100, NULL, 'paquete', false)$q$, 'Ana'));
SELECT pg_temp.caso('10 mínimo en el paso 3', '23514', pg_temp.intentar(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 No', 1, 3, '{}', 100, 'ARS', 'paquete', false)$q$, 'Ana'));
SELECT pg_temp.caso('10 los frenados no dejan el servicio', '0', (
  SELECT count(*)::text FROM catalogo_porcentajes_valores WHERE nombre = 'Zqx159 No'));
SELECT pg_temp.caso('10 % en 0, no', '23514', pg_temp.intentar(
  pg_temp.guardar(NULL, 'Zqx159 No', 0, 1), 'Ana'));
SELECT pg_temp.caso('10 nombre repetido entre los activos', 'CA010', pg_temp.intentar(
  pg_temp.guardar(NULL, 'zqx159 COMERCIALIZACIÓN', 1, 1), 'Ana'));

-- ============================================================
-- 11. Cada cambio es un valor nuevo; el rojo pide confirmar
-- ============================================================
SELECT pg_temp.caso('11 sube de 10 a 12: valor nuevo', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Comercializacion'), 'Zqx159 Comercialización', 12, 1), 'Ana'));
SELECT pg_temp.caso('11 dos valores', '2', (SELECT count(*)::text FROM catalogo_porcentajes_valores
  WHERE porcentaje_id = pg_temp.id('Comercializacion')));
SELECT pg_temp.caso('11 rige el nuevo', '12.0', pg_temp.vigente('Comercializacion'));
SELECT pg_temp.caso('11 sin cambios no suma fila', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Comercializacion'), 'Zqx159 Comercialización', 12.000, 1), 'Ana'));
SELECT pg_temp.caso('11 siguen dos', '2', (SELECT count(*)::text FROM catalogo_porcentajes_valores
  WHERE porcentaje_id = pg_temp.id('Comercializacion')));
SELECT pg_temp.caso('11 12 → 15 es naranja: guarda', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Comercializacion'), 'Zqx159 Comercialización', 15, 1), 'Ana'));
SELECT pg_temp.caso('11 la historia dice naranja', 'naranja', pg_temp.consultar(format(
  $q$SELECT nivel FROM catalogo_porcentajes_historia(%L) WHERE ultimo$q$, pg_temp.id('Comercializacion')), 'Ana'));
SELECT pg_temp.caso('11 y quién lo cargó', 'test159 Ana', pg_temp.consultar(format(
  $q$SELECT cargado_por FROM catalogo_porcentajes_historia(%L) WHERE ultimo$q$, pg_temp.id('Comercializacion')), 'Carlos'));
SELECT pg_temp.caso('11 solo uno es el último', '1', pg_temp.ve(format(
  $q$SELECT 1 FROM catalogo_porcentajes_historia(%L) WHERE ultimo$q$, pg_temp.id('Comercializacion')), 'Ana'));
SELECT pg_temp.caso('11 15 → 150 sin confirmar', 'CA003', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Comercializacion'), 'Zqx159 Comercialización', 150, 1), 'Ana'));
SELECT pg_temp.caso('11 sigue el 15', '15.0', pg_temp.vigente('Comercializacion'));
SELECT pg_temp.caso('11 confirmado', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Comercializacion'), 'Zqx159 Comercialización', 150, 1, true), 'Ana'));
SELECT pg_temp.caso('11 rige el 150', '150.0', pg_temp.vigente('Comercializacion'));
SELECT pg_temp.caso('11 alta sobre dos categorías', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(%L, 'Zqx159 Multi', 3, 1, ARRAY[%L, %L]::uuid[], NULL, NULL, NULL, false)$q$,
  NULL, pg_temp.id('Vidrios'), pg_temp.id('Herrajes')), 'Ana'));
INSERT INTO ids SELECT 'Multi', v.porcentaje_id FROM catalogo_porcentajes_valores v WHERE v.nombre = 'Zqx159 Multi' LIMIT 1;
SELECT pg_temp.caso('11 categorías en otro orden: sin fila nueva', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(%L, 'Zqx159 Multi', 3, 1, ARRAY[%L, %L, %L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Multi'), pg_temp.id('Herrajes'), pg_temp.id('Vidrios'), pg_temp.id('Herrajes')), 'Ana'));
SELECT pg_temp.caso('11 sigue un solo valor', '1', (SELECT count(*)::text FROM catalogo_porcentajes_valores
  WHERE porcentaje_id = pg_temp.id('Multi')));
SELECT pg_temp.crear('Colocacion', $q$INSERT INTO catalogo_categorias (tipo, nombre)
  VALUES ('servicio', 'Zqx159 Colocación') RETURNING id$q$, 'Ana');
SELECT pg_temp.crear('Seguro', format(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 Seguro obra', 2, 1, ARRAY[%L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Colocacion')), 'Ana');
SELECT pg_temp.caso('11 una categoría sin nada adentro se baja, aunque un servicio la use', 'ok', pg_temp.intentar(format(
  $q$UPDATE catalogo_categorias SET activo = false WHERE id = %L$q$, pg_temp.id('Colocacion')), 'Ana'));
SELECT pg_temp.caso('11 el servicio se sigue pudiendo cambiar', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(%L, 'Zqx159 Seguro obra', 2.2, 1, ARRAY[%L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Seguro'), pg_temp.id('Colocacion')), 'Ana'));

-- ============================================================
-- 12. Baja y paso 3: los % sobre el precio final suman menos de 100
-- ============================================================
-- IIBB está en 60.
SELECT pg_temp.crear('Otro', pg_temp.guardar(NULL, 'Zqx159 Otro', 39.9, 3), 'Ana');
SELECT pg_temp.caso('12 llevaría a 100', 'CA004', pg_temp.intentar(
  pg_temp.guardar(NULL, 'Zqx159 No', 0.1, 3), 'Ana'));
SELECT pg_temp.caso('12 subirlo a 100 tampoco', 'CA004', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Otro'), 'Zqx159 Otro', 40, 3), 'Ana'));
SELECT pg_temp.caso('12 pasar uno de otro paso tampoco', 'CA004', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Transicion'), 'Zqx159 Transición', 4, 3), 'Ana'));
SELECT pg_temp.caso('12 los de otros pasos no cuentan', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Transicion'), 'Zqx159 Transición', 4.5, 2), 'Ana'));

SELECT pg_temp.caso('12 baja de Otro', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_activar(%L, false)$q$, pg_temp.id('Otro')), 'Ana'));
SELECT pg_temp.caso('12 queda de baja, con su %', '39.9 de baja', pg_temp.vigente('Otro'));
SELECT pg_temp.caso('12 el registro lo dice', 'false', (SELECT activo::text FROM catalogo_porcentajes
  WHERE id = pg_temp.id('Otro')));
SELECT pg_temp.caso('12 a la fecha anterior estaba activo', 'false', (SELECT v.de_baja::text
  FROM catalogo_porcentajes_vigentes((SELECT x.created_at FROM catalogo_porcentajes_valores x
    WHERE x.porcentaje_id = pg_temp.id('Otro') ORDER BY x.created_at LIMIT 1)) v
  WHERE v.porcentaje_id = pg_temp.id('Otro')));
SELECT pg_temp.caso('12 dar de baja de nuevo no suma fila', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_activar(%L, false)$q$, pg_temp.id('Otro')), 'Ana'));
SELECT pg_temp.caso('12 siguen dos valores', '2', (SELECT count(*)::text FROM catalogo_porcentajes_valores
  WHERE porcentaje_id = pg_temp.id('Otro')));
SELECT pg_temp.crear('Tercero', pg_temp.guardar(NULL, 'Zqx159 Tercero', 39.95, 3), 'Ana');
SELECT pg_temp.caso('12 reactivarlo llevaría a 100', 'CA004', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_activar(%L, true)$q$, pg_temp.id('Otro')), 'Ana'));
SELECT pg_temp.caso('12 sigue de baja', '39.9 de baja', pg_temp.vigente('Otro'));
SELECT pg_temp.caso('12 cambiarlo de baja lo deja de baja', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Otro'), 'Zqx159 Otro', 39, 3), 'Ana'));
SELECT pg_temp.caso('12 sigue de baja, con otro %', '39.0 de baja', pg_temp.vigente('Otro'));
SELECT pg_temp.caso('12 de baja, el nombre se reutiliza', 'ok', pg_temp.intentar(
  pg_temp.guardar(NULL, 'Zqx159 Otro', 1, 1), 'Ana'));
SELECT pg_temp.caso('12 reactivarlo con el nombre ocupado', 'CA010', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_activar(%L, true)$q$, pg_temp.id('Otro')), 'Ana'));

-- ============================================================
-- 13. Revertir: solo el último cambio, por los mismos controles
-- ============================================================
SELECT pg_temp.crear('Vidrio', format(
  $q$SELECT catalogo_porcentaje_guardar(NULL, 'Zqx159 Vidrio', 5, 1, ARRAY[%L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Vidrios')), 'Ana');
INSERT INTO ids VALUES ('Vidrio alta', pg_temp.ultimo('Vidrio'));
SELECT pg_temp.caso('13 Ana suma Herrajes', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(%L, 'Zqx159 Vidrio', 5, 1, ARRAY[%L, %L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Vidrio'), pg_temp.id('Vidrios'), pg_temp.id('Herrajes')), 'Ana'));
INSERT INTO ids VALUES ('Vidrio herrajes', pg_temp.ultimo('Vidrio'));
SELECT pg_temp.caso('13 y sube el %', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(%L, 'Zqx159 Vidrio', 6, 1, ARRAY[%L, %L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Vidrio'), pg_temp.id('Vidrios'), pg_temp.id('Herrajes')), 'Ana'));
INSERT INTO ids VALUES ('Vidrio seis', pg_temp.ultimo('Vidrio'));

SELECT pg_temp.caso('13 Lucia no revierte', '42501', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.id('Vidrio seis')), 'Lucia'));
SELECT pg_temp.caso('13 lo del lunes no: hubo otro cambio', 'CA005', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.id('Vidrio herrajes')), 'Carlos'));
SELECT pg_temp.caso('13 uno que no existe', 'CA005', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, gen_random_uuid()), 'Carlos'));
SELECT pg_temp.caso('13 Carlos revierte lo del martes', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.id('Vidrio seis')), 'Carlos'));
SELECT pg_temp.caso('13 vuelve al 5', '5.0', pg_temp.vigente('Vidrio'));
SELECT pg_temp.caso('13 con Herrajes todavía', '2', (SELECT cardinality(v.categorias)::text
  FROM catalogo_porcentajes_vigentes() v WHERE v.porcentaje_id = pg_temp.id('Vidrio')));
SELECT pg_temp.caso('13 es un cambio más: valor nuevo', '4', (SELECT count(*)::text FROM catalogo_porcentajes_valores
  WHERE porcentaje_id = pg_temp.id('Vidrio')));
SELECT pg_temp.caso('13 dice qué revierte', 'true', (SELECT (v.revierte_id = pg_temp.id('Vidrio seis'))::text
  FROM catalogo_porcentajes_vigentes() v WHERE v.porcentaje_id = pg_temp.id('Vidrio')));
SELECT pg_temp.caso('13 y quién', 'true', (SELECT (v.creado_por = pg_temp.id('Carlos'))::text
  FROM catalogo_porcentajes_vigentes() v WHERE v.porcentaje_id = pg_temp.id('Vidrio')));
SELECT pg_temp.caso('13 lo revertido ya no es lo último', 'CA005', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.id('Vidrio seis')), 'Carlos'));

-- Revertir la reversión vuelve al cambio. Otra vez sobre el último, ya con el 6.
SELECT pg_temp.caso('13 se revierte la reversión', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.ultimo('Vidrio')), 'Carlos'));
SELECT pg_temp.caso('13 vuelve el 6', '6.0', pg_temp.vigente('Vidrio'));
SELECT pg_temp.caso('13 también dice qué revierte', 'true', (SELECT (v.revierte_id IS NOT NULL)::text
  FROM catalogo_porcentajes_vigentes() v WHERE v.porcentaje_id = pg_temp.id('Vidrio')));
SELECT pg_temp.caso('13 guardar después no hereda la marca', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_guardar(%L, 'Zqx159 Vidrio', 6.5, 1, ARRAY[%L, %L]::uuid[], NULL, NULL, NULL, false)$q$,
  pg_temp.id('Vidrio'), pg_temp.id('Vidrios'), pg_temp.id('Herrajes')), 'Ana'));
SELECT pg_temp.caso('13 sin marca', 'true', (SELECT (v.revierte_id IS NULL)::text
  FROM catalogo_porcentajes_vigentes() v WHERE v.porcentaje_id = pg_temp.id('Vidrio')));

-- Antes del alta no se cobraba.
SELECT pg_temp.crear('Nuevo', pg_temp.guardar(NULL, 'Zqx159 Nuevo', 7, 1), 'Ana');
SELECT pg_temp.caso('13 revertir el alta', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.ultimo('Nuevo')), 'Carlos'));
SELECT pg_temp.caso('13 lo deja de baja', '7.0 de baja', pg_temp.vigente('Nuevo'));
SELECT pg_temp.caso('13 el registro también', 'false', (SELECT activo::text FROM catalogo_porcentajes
  WHERE id = pg_temp.id('Nuevo')));
SELECT pg_temp.caso('13 revertirlo lo devuelve', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.ultimo('Nuevo')), 'Carlos'));
SELECT pg_temp.caso('13 activo', '7.0', pg_temp.vigente('Nuevo'));

-- Por los mismos controles: el rojo pide confirmar, y el paso 3 no llega a 100.
SELECT pg_temp.caso('13 volver de 150 a 15 es rojo', 'CA003', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.ultimo('Comercializacion')), 'Carlos'));
SELECT pg_temp.caso('13 sigue el 150', '150.0', pg_temp.vigente('Comercializacion'));
SELECT pg_temp.caso('13 confirmado', 'ok', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L, true)$q$, pg_temp.ultimo('Comercializacion')), 'Carlos'));
SELECT pg_temp.caso('13 vuelve al 15', '15.0', pg_temp.vigente('Comercializacion'));

-- IIBB 60 + Tercero 39,95. Bajar IIBB a 50 y subir Tercero a 45: volver a 60 llevaría a 105.
SELECT pg_temp.caso('13 IIBB baja a 50', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('IIBB'), 'Zqx159 IIBB', 50, 3), 'Ana'));
INSERT INTO ids VALUES ('IIBB 50', pg_temp.ultimo('IIBB'));
SELECT pg_temp.caso('13 Tercero sube a 45', 'ok', pg_temp.intentar(
  pg_temp.guardar(pg_temp.id('Tercero'), 'Zqx159 Tercero', 45, 3), 'Ana'));
SELECT pg_temp.caso('13 volver a 60 llevaría a 105', 'CA004', pg_temp.intentar(format(
  $q$SELECT catalogo_porcentaje_revertir(%L)$q$, pg_temp.id('IIBB 50')), 'Carlos'));
SELECT pg_temp.caso('13 sigue el 50', '50.0', pg_temp.vigente('IIBB'));

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
