-- Test de sql/158_catalogo_formulas.sql. Termina en RAISE, así que no deja nada en la base y el resultado
-- vuelve en una línea. Lo circular y lo que puede faltar se prueban con el despiece y el envío.
DO $test$
DECLARE
  ok int := 0;
  tot int := 0;
  fallas text := '';
  c record;
  r numeric;
  b boolean;
  e text;
  err text;
  usa text[];
  t0 timestamptz;
  ast jsonb;
  ms_parse numeric;
  ms_eval numeric;
  i int;
  f_vidrio text := 'radio × radio × arcoseno(ancho / (2 × radio)) − ancho / 2 × (radio − flecha)';
BEGIN
  -- ============================================================
  -- Fórmulas: un número
  -- ============================================================
  FOR c IN SELECT * FROM (VALUES
    ('marco', 'ancho - 2', '{"ancho":1500}'::jsonb, 1498::numeric, NULL::text),
    ('signos de la ficha', 'ancho − 2 × 3', '{"ancho":1500}', 1494, NULL),
    ('radio', 'flecha / 2 + ancho * ancho / (8 * flecha)', '{"ancho":1200,"flecha":200}', 1000, NULL),
    ('perfil curvo', '2 * radio * arcoseno(ancho / (2 * radio))', '{"ancho":1200,"radio":1000}', 1287.002, NULL),
    ('vidrio arco', f_vidrio, '{"ancho":1200,"flecha":200,"radio":1000}', 163501.109, NULL),
    ('medio punto', '2 * radio * arcoseno(ancho / (2 * radio))', '{"ancho":1200,"radio":600}', 1884.956, NULL),
    ('pi', 'pi * radio', '{"radio":600}', 1884.956, NULL),
    ('bisagras 2000', 'si alto > 2100 entonces 4 si no 3', '{"alto":2000}', 3, NULL),
    ('bisagras 2200', 'si alto > 2100 entonces 4 si no 3', '{"alto":2200}', 4, NULL),
    ('redondear', 'redondear_arriba(alto / 700)', '{"alto":2000}', 3, NULL),
    ('redondear exacto', 'redondear_arriba(alto / 700)', '{"alto":2100}', 3, NULL),
    ('redondear sin ruido de la division', 'redondear_arriba(2 / 3 * 3)', '{}', 2, NULL),
    ('si encadenado', 'si peso > 80 entonces 3 si no si peso > 40 entonces 2 si no 1', '{"peso":50}', 2, NULL),
    ('si dentro de una cuenta', '(si alto > 2100 entonces 4 si no 3) + 1', '{"alto":2000}', 4, NULL),
    ('decimal con coma', '0,5 * 3', '{}', 1.5, NULL),
    ('nombre con espacio', '[Perfil hoja] * 2', '{"Perfil hoja":3950}', 7900, NULL),
    ('nombre con acento', 'año + 1', '{"año":1}', 2, NULL),
    ('peso de una pieza', '[peso Hoja 1] + 1', '{"peso Hoja 1":16}', 17, NULL),
    ('prioridad', '2 + 3 * 4', '{}', 14, NULL),
    ('parentesis', '(2 + 3) * 4', '{}', 20, NULL),
    ('asociatividad', '10 - 2 - 3', '{}', 5, NULL),
    ('negativo', '-2 + 5', '{}', 3, NULL),
    ('y', 'si ancho > 2000 y alto > 2400 entonces 1 si no 0', '{"ancho":2500,"alto":2500}', 1, NULL),
    ('y, falta una', 'si ancho > 2000 y alto > 2400 entonces 1 si no 0', '{"ancho":2500,"alto":2000}', 0, NULL),
    ('o', 'si ancho > 2000 o alto > 2400 entonces 1 si no 0', '{"ancho":1000,"alto":2500}', 1, NULL),
    ('o, ninguna', 'si ancho > 2000 o alto > 2400 entonces 1 si no 0', '{"ancho":1000,"alto":1000}', 0, NULL),
    ('tres y', 'si a > 1 y b > 1 y c > 1 entonces 1 si no 0', '{"a":2,"b":2,"c":0}', 0, NULL),
    ('tres o', 'si a > 1 o b > 1 o c > 1 entonces 1 si no 0', '{"a":0,"b":0,"c":2}', 1, NULL),
    ('mezcla con parentesis a la izquierda', 'si (a > 1 y b > 1) o c > 1 entonces 1 si no 0', '{"a":0,"b":0,"c":2}', 1, NULL),
    ('mezcla con parentesis a la derecha', 'si a > 1 y (b > 1 o c > 1) entonces 1 si no 0', '{"a":0,"b":2,"c":2}', 0, NULL),
    ('doble parentesis', 'si ((a > 1)) y b > 1 entonces 1 si no 0', '{"a":2,"b":2}', 1, NULL),
    ('parentesis de una cuenta', 'si (a + b) * 2 > 10 entonces 1 si no 0', '{"a":3,"b":3}', 1, NULL),
    ('parentesis de una cuenta, con y', 'si (a + b) > 5 y c > 1 entonces 1 si no 0', '{"a":3,"b":3,"c":2}', 1, NULL),
    ('y no divide si no hace falta', 'si flecha > 0 y ancho / flecha > 2 entonces 1 si no 0', '{"ancho":1,"flecha":0}', 0, NULL),
    ('o no divide si no hace falta', 'si flecha = 0 o ancho / flecha > 2 entonces 1 si no 0', '{"ancho":1,"flecha":0}', 1, NULL),
    ('mayusculas', 'SI a > 1 Y b > 1 ENTONCES 1 SI NO 0', '{"a":2,"b":2}', 1, NULL),
    ('y entre corchetes', '[y] + 1', '{"y":2}', 3, NULL),
    ('o entre corchetes', '[o] + 1', '{"o":2}', 3, NULL),
    ('si entre corchetes', '[si] + 1', '{"si":2}', 3, NULL),
    ('mezcla sin parentesis', 'si a > 1 y b > 1 o c > 1 entonces 1 si no 0', '{"a":2,"b":2,"c":2}', NULL, 'paréntesis'),
    ('mezcla sin parentesis, al reves', 'si a > 1 o b > 1 y c > 1 entonces 1 si no 0', '{"a":2,"b":2,"c":2}', NULL, 'paréntesis'),
    ('y suelta', 'y + 1', '{"y":2}', NULL, 'Palabra inesperada'),
    ('o suelta', 'o + 1', '{"o":2}', NULL, 'Palabra inesperada'),
    ('condicion sin comparador', 'si (a + b) entonces 1 si no 0', '{"a":1,"b":1}', NULL, 'comparador'),
    ('division por cero', 'flecha / 2 + ancho * ancho / (8 * flecha)', '{"ancho":1200,"flecha":0}', NULL, '22012'),
    ('arcoseno fuera de rango', 'arcoseno(2)', '{}', NULL, '22003'),
    ('sin si no', 'si alto > 2100 entonces 4', '{"alto":2000}', NULL, 'si no'),
    ('sin entonces', 'si alto > 2100 4 si no 3', '{"alto":2000}', NULL, 'entonces'),
    ('variable desconocida', 'ancho - 2', '{}', NULL, 'CA002'),
    ('punto de miles', '1.500', '{}', NULL, 'Caracter no permitido'),
    ('punto de miles en si', 'si ancho > 1.500 entonces 1 si no 0', '{"ancho":2000}', NULL, 'Caracter no permitido'),
    ('inyeccion punto y coma', '1; drop table usuarios', '{}', NULL, 'Caracter no permitido'),
    ('inyeccion comilla', 'ancho'' or 1=1', '{"ancho":1}', NULL, 'Caracter no permitido'),
    ('inyeccion select', 'select 1', '{}', NULL, 'Sobra'),
    ('inyeccion subconsulta', '(select 1)', '{}', NULL, 'paréntesis'),
    ('funcion ajena', 'pg_sleep(10)', '{}', NULL, 'Función no permitida'),
    ('vacia', '', '{}', NULL, 'Falta un valor'),
    ('demasiado larga', repeat('1 + ', 600) || '1', '{}', NULL, 'demasiado larga')
  ) AS x(nombre, f, v, esp, error) LOOP
    tot := tot + 1;
    BEGIN
      r := public.catalogo_formula_evaluar(public.catalogo_formula_parsear(c.f), c.v);
      err := NULL;
    EXCEPTION WHEN OTHERS THEN
      r := NULL;
      err := sqlstate || ':' || sqlerrm;
    END;
    IF c.error IS NULL THEN
      IF r IS NOT NULL AND abs(r - c.esp) < 0.01 THEN ok := ok + 1;
      ELSE fallas := fallas || c.nombre || ' (dio ' || coalesce(r::text, err) || '); ';
      END IF;
    ELSE
      IF err LIKE '%' || c.error || '%' THEN ok := ok + 1;
      ELSE fallas := fallas || c.nombre || ' (dio ' || coalesce(err, r::text) || '); ';
      END IF;
    END IF;
  END LOOP;

  -- ============================================================
  -- Condiciones: cierto o falso
  -- ============================================================
  FOR c IN SELECT * FROM (VALUES
    ('condicion', 'ancho > 1000', '{"ancho":1500}'::jsonb, true, NULL::text),
    ('condicion con cuenta', 'alto > ancho × 2', '{"ancho":1000,"alto":1500}', false, NULL),
    ('condicion con y', 'ancho > 2000 y alto > 2400', '{"ancho":2500,"alto":2500}', true, NULL),
    ('condicion entre parentesis', '(ancho > 2000) o alto > 2400', '{"ancho":2500,"alto":0}', true, NULL),
    ('flecha mayor que medio ancho', 'flecha > ancho / 2', '{"ancho":1200,"flecha":800}', true, NULL),
    ('comparador >=', 'a >= 2', '{"a":2}', true, NULL),
    ('comparador <=', 'a <= 1', '{"a":2}', false, NULL),
    ('comparador =', 'a = 2', '{"a":2}', true, NULL),
    ('comparador <>', 'a <> 2', '{"a":2}', false, NULL),
    ('condicion sin comparador', 'ancho + 1', '{"ancho":1}', NULL, 'comparador'),
    ('condicion con si', 'si a > 1 entonces 1 si no 0', '{"a":2}', NULL, 'Palabra inesperada'),
    ('condicion que sobra', 'a > 1 2', '{"a":2}', NULL, 'Sobra')
  ) AS x(nombre, f, v, esp, error) LOOP
    tot := tot + 1;
    BEGIN
      b := public.catalogo_condicion_evaluar(public.catalogo_formula_parsear(c.f, 'condicion'), c.v);
      err := NULL;
    EXCEPTION WHEN OTHERS THEN
      b := NULL;
      err := sqlstate || ':' || sqlerrm;
    END;
    IF c.error IS NULL THEN
      IF b IS NOT DISTINCT FROM c.esp AND err IS NULL THEN ok := ok + 1;
      ELSE fallas := fallas || c.nombre || ' (dio ' || coalesce(b::text, err) || '); ';
      END IF;
    ELSE
      IF err LIKE '%' || c.error || '%' THEN ok := ok + 1;
      ELSE fallas := fallas || c.nombre || ' (dio ' || coalesce(err, b::text) || '); ';
      END IF;
    END IF;
  END LOOP;

  -- ============================================================
  -- Elecciones: qué opción pone el sistema
  -- ============================================================
  FOR c IN SELECT * FROM (VALUES
    ('rueda chica', 'si [peso Hoja] > 40 entonces [Rueda 80kg] si no [Rueda 40kg]', '{"peso Hoja":16}'::jsonb, 'Rueda 40kg', NULL::text),
    ('rueda grande', 'si [peso Hoja] > 40 entonces [Rueda 80kg] si no [Rueda 40kg]', '{"peso Hoja":50}', 'Rueda 80kg', NULL),
    ('vidrio con o', 'si ancho > 2000 o alto > 2400 entonces Laminado si no Float', '{"ancho":1000,"alto":2500}', 'Laminado', NULL),
    ('encadenada', 'si p > 80 entonces A si no si p > 40 entonces B si no C', '{"p":50}', 'B', NULL),
    ('ninguno', 'si p > 80 entonces ninguno si no Rueda', '{"p":81}', '(ninguno)', NULL),
    ('ninguno es palabra, entre corchetes es un nombre', 'si p > 80 entonces [ninguno] si no Rueda', '{"p":81}', 'ninguno', NULL),
    ('sin si no', 'si p > 40 entonces [Rueda 80kg]', '{"p":50}', NULL, 'si no'),
    ('un numero no es una opcion', 'si p > 40 entonces 4 si no 3', '{"p":50}', NULL, 'Valor inesperado'),
    ('una cuenta no es una opcion', 'si p > 40 entonces A + 1 si no B', '{"p":50}', NULL, 'si no')
  ) AS x(nombre, f, v, esp, error) LOOP
    tot := tot + 1;
    BEGIN
      e := coalesce(public.catalogo_eleccion_evaluar(public.catalogo_formula_parsear(c.f, 'eleccion'), c.v), '(ninguno)');
      err := NULL;
    EXCEPTION WHEN OTHERS THEN
      e := NULL;
      err := sqlstate || ':' || sqlerrm;
    END;
    IF c.error IS NULL THEN
      IF e IS NOT DISTINCT FROM c.esp THEN ok := ok + 1;
      ELSE fallas := fallas || c.nombre || ' (dio ' || coalesce(e, err) || '); ';
      END IF;
    ELSE
      IF err LIKE '%' || c.error || '%' THEN ok := ok + 1;
      ELSE fallas := fallas || c.nombre || ' (dio ' || coalesce(err, e) || '); ';
      END IF;
    END IF;
  END LOOP;

  -- ============================================================
  -- De qué depende
  -- ============================================================
  tot := tot + 1;
  usa := public.catalogo_formula_usa(public.catalogo_formula_parsear('[Perfil hoja] * ancho + (si alto > [peso Hoja] entonces alto si no redondear_arriba(ancho / 2))'));
  IF usa @> ARRAY['Perfil hoja', 'ancho', 'alto', 'peso Hoja'] AND usa <@ ARRAY['Perfil hoja', 'ancho', 'alto', 'peso Hoja'] THEN ok := ok + 1;
  ELSE fallas := fallas || 'usa en una formula (dio ' || usa::text || '); ';
  END IF;

  tot := tot + 1;
  usa := public.catalogo_formula_usa(public.catalogo_formula_parsear('si [peso Hoja] > 40 entonces [Rueda 80kg] si no ninguno', 'eleccion'));
  IF usa = ARRAY['peso Hoja'] THEN ok := ok + 1;
  ELSE fallas := fallas || 'usa en una eleccion (dio ' || usa::text || '); ';
  END IF;

  tot := tot + 1;
  usa := public.catalogo_formula_usa(public.catalogo_formula_parsear('2 + 2'));
  IF usa = '{}'::text[] THEN ok := ok + 1;
  ELSE fallas := fallas || 'usa sin nada (dio ' || usa::text || '); ';
  END IF;

  -- ============================================================
  -- El árbol en una columna generada: lo que no se entiende no se guarda
  -- ============================================================
  CREATE TEMP TABLE prueba_formula (
    texto text,
    arbol jsonb GENERATED ALWAYS AS (public.catalogo_formula_parsear(texto)) STORED
  ) ON COMMIT DROP;
  GRANT ALL ON prueba_formula TO authenticated;

  tot := tot + 1;
  INSERT INTO prueba_formula (texto) VALUES ('ancho - 2');
  IF (SELECT arbol->>'op' FROM prueba_formula) = '-' THEN ok := ok + 1;
  ELSE fallas := fallas || 'columna generada; ';
  END IF;

  tot := tot + 1;
  BEGIN
    INSERT INTO prueba_formula (texto) VALUES ('1.500');
    fallas := fallas || 'guardo una formula que no entiende; ';
  EXCEPTION WHEN SQLSTATE 'CA001' THEN ok := ok + 1;
  END;

  tot := tot + 1;
  INSERT INTO prueba_formula (texto) VALUES (NULL);
  IF (SELECT count(*) FROM prueba_formula WHERE texto IS NULL AND arbol IS NULL) = 1 THEN ok := ok + 1;
  ELSE fallas := fallas || 'formula vacia en columna generada; ';
  END IF;

  -- ============================================================
  -- Demasiado anidada: CA001, y lo que se guarda se puede calcular
  -- ============================================================
  FOR c IN SELECT * FROM (VALUES
    ('600 parentesis', repeat('(', 600) || '1' || repeat(')', 600), 'formula'),
    ('999 parentesis', repeat('(', 999) || '1' || repeat(')', 999), 'formula'),
    ('900 parentesis en condicion', repeat('(', 900) || 'a > 1' || repeat(')', 900), 'condicion'),
    ('1999 menos', repeat('-', 1999) || '1', 'formula'),
    ('101 menos', repeat('-', 101) || '1', 'formula'),
    ('999 sumas', '1' || repeat('+1', 999), 'formula'),
    ('101 sumas', '1' || repeat('+1', 101), 'formula')
  ) AS t(n, f, tipo) LOOP
    tot := tot + 1;
    BEGIN
      ast := public.catalogo_formula_parsear(c.f, c.tipo);
      fallas := fallas || c.n || ' se guardo; ';
    EXCEPTION
      WHEN SQLSTATE 'CA001' THEN ok := ok + 1;
      WHEN OTHERS THEN fallas := fallas || c.n || ' dio ' || SQLSTATE || '; ';
    END;
  END LOOP;

  FOR c IN SELECT * FROM (VALUES
    ('100 sumas', '1' || repeat('+1', 100), 101::numeric),
    ('100 menos', repeat('-', 100) || '1', 1::numeric),
    ('100 parentesis', repeat('(', 100) || '1' || repeat(')', 100), 1::numeric),
    ('80 si', repeat('si a>1 entonces ', 80) || '1' || repeat(' si no 2', 80), 2::numeric)
  ) AS t(n, f, r) LOOP
    tot := tot + 1;
    IF public.catalogo_formula_evaluar(public.catalogo_formula_parsear(c.f), '{"a":1}') = c.r THEN ok := ok + 1;
    ELSE fallas := fallas || c.n || ' calcula mal; ';
    END IF;
  END LOOP;

  -- ============================================================
  -- Privilegios
  -- ============================================================
  tot := tot + 1;
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO prueba_formula (texto) VALUES ('alto - 2');
    IF public.catalogo_formula_evaluar(public.catalogo_formula_parsear('si a > 1 entonces 2 si no 3'), '{"a":2}') = 2 THEN ok := ok + 1;
    ELSE fallas := fallas || 'authenticated calcula mal; ';
    END IF;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    fallas := fallas || 'authenticated (' || sqlerrm || '); ';
  END;

  tot := tot + 1;
  BEGIN
    SET LOCAL ROLE anon;
    ast := public.catalogo_formula_parsear('1 + 1');
    RESET ROLE;
    fallas := fallas || 'anon pudo parsear; ';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
    ok := ok + 1;
  END;

  -- ============================================================
  -- Cuánto tarda (decisiones/catalogo/despiece.md: 0,42 ms al guardar y 0,15 ms al calcular)
  -- ============================================================
  t0 := clock_timestamp();
  FOR i IN 1..200 LOOP ast := public.catalogo_formula_parsear(f_vidrio); END LOOP;
  ms_parse := extract(epoch FROM clock_timestamp() - t0) * 1000 / 200;
  t0 := clock_timestamp();
  FOR i IN 1..1000 LOOP r := public.catalogo_formula_evaluar(ast, '{"ancho":1200,"flecha":200,"radio":1000}'); END LOOP;
  ms_eval := extract(epoch FROM clock_timestamp() - t0) * 1000 / 1000;

  RAISE EXCEPTION '% / % ok | parsear % ms | evaluar % ms | fallan: %', ok, tot, round(ms_parse, 3), round(ms_eval, 4), fallas;
END $test$;
