-- Catálogo: las fórmulas. Técnica escribe texto; al guardarlo se convierte en un árbol, y calcular recorre
-- el árbol: el texto nunca se ejecuta como SQL (decisiones/catalogo/despiece.md → Las fórmulas se calculan
-- sin SQL dinámico). Esquema: db_schema/catalogo.md. Test: sql/tests/catalogo_formulas.sql.
--
-- Nada de esto lee tablas, así que una fórmula no puede leer un costo, y por eso authenticated puede
-- ejecutarlas todas. Parsear es IMMUTABLE para poder guardar el árbol en una columna generada: lo que no se
-- entiende no se guarda.

-- ============================================================
-- 1. Del texto a los tokens
-- ============================================================
CREATE OR REPLACE FUNCTION public.catalogo_formula_tokens(p_texto text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_texto text := replace(replace(p_texto, '−', '-'), '×', '*');
  v_tokens text[];
BEGIN
  IF char_length(p_texto) > 2000 THEN
    RAISE EXCEPTION 'La fórmula es demasiado larga' USING ERRCODE = 'CA001';
  END IF;

  SELECT coalesce(array_agg(m.x[1] ORDER BY m.i), '{}') INTO v_tokens
  FROM regexp_matches(
    v_texto,
    '(\d+(?:,\d+)?|\[[^\]]+\]|[[:alpha:]_][[:alnum:]_]*|<=|>=|<>|[-+*/()<>=])',
    'g'
  ) WITH ORDINALITY AS m(x, i);

  -- Lo que el patrón no reconoce queda afuera de los tokens, y entonces no reconstruyen el texto.
  IF regexp_replace(array_to_string(v_tokens, ''), '\s', '', 'g')
     IS DISTINCT FROM regexp_replace(v_texto, '\s', '', 'g') THEN
    RAISE EXCEPTION 'Caracter no permitido. El decimal va con coma y el punto no se acepta'
      USING ERRCODE = 'CA001';
  END IF;

  RETURN v_tokens;
END;
$$;

-- ============================================================
-- 2. De los tokens al árbol. Cada función devuelve {n: nodo, p: próximo token}
-- ============================================================
CREATE OR REPLACE FUNCTION public.catalogo_formula_factor(p_t text[], p_i int)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_tk text := p_t[p_i];
  v_r jsonb;
BEGIN
  IF v_tk IS NULL THEN
    RAISE EXCEPTION 'Falta un valor' USING ERRCODE = 'CA001';
  END IF;
  IF v_tk ~ '^\d' THEN
    RETURN jsonb_build_object('n', jsonb_build_object('op', 'num', 'v', replace(v_tk, ',', '.')), 'p', p_i + 1);
  END IF;
  IF v_tk = '-' THEN
    v_r := public.catalogo_formula_factor(p_t, p_i + 1);
    RETURN jsonb_build_object('n', jsonb_build_object('op', 'neg', 'a', v_r->'n'), 'p', v_r->'p');
  END IF;
  IF v_tk = '(' THEN
    v_r := public.catalogo_formula_expresion(p_t, p_i + 1);
    IF p_t[(v_r->>'p')::int] IS DISTINCT FROM ')' THEN
      RAISE EXCEPTION 'Falta cerrar un paréntesis' USING ERRCODE = 'CA001';
    END IF;
    RETURN jsonb_build_object('n', v_r->'n', 'p', (v_r->>'p')::int + 1);
  END IF;
  IF v_tk ~ '^\[' THEN
    RETURN jsonb_build_object(
      'n', jsonb_build_object('op', 'var', 'v', btrim(substr(v_tk, 2, length(v_tk) - 2))),
      'p', p_i + 1
    );
  END IF;
  IF v_tk ~ '^[[:alpha:]_]' THEN
    IF lower(v_tk) IN ('si', 'entonces', 'no', 'y', 'o') THEN
      RAISE EXCEPTION 'Palabra inesperada: %', v_tk USING ERRCODE = 'CA001';
    END IF;
    IF p_t[p_i + 1] = '(' THEN
      IF lower(v_tk) NOT IN ('redondear_arriba', 'arcoseno') THEN
        RAISE EXCEPTION 'Función no permitida: %', v_tk USING ERRCODE = 'CA001';
      END IF;
      v_r := public.catalogo_formula_expresion(p_t, p_i + 2);
      IF p_t[(v_r->>'p')::int] IS DISTINCT FROM ')' THEN
        RAISE EXCEPTION 'Falta cerrar un paréntesis' USING ERRCODE = 'CA001';
      END IF;
      RETURN jsonb_build_object(
        'n', jsonb_build_object('op', lower(v_tk), 'a', v_r->'n'),
        'p', (v_r->>'p')::int + 1
      );
    END IF;
    IF lower(v_tk) = 'pi' THEN
      RETURN jsonb_build_object('n', jsonb_build_object('op', 'pi'), 'p', p_i + 1);
    END IF;
    RETURN jsonb_build_object('n', jsonb_build_object('op', 'var', 'v', v_tk), 'p', p_i + 1);
  END IF;
  RAISE EXCEPTION 'Valor inesperado: %', v_tk USING ERRCODE = 'CA001';
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_formula_termino(p_t text[], p_i int)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_a jsonb := public.catalogo_formula_factor(p_t, p_i);
  v_b jsonb;
  v_op text;
BEGIN
  LOOP
    v_op := p_t[(v_a->>'p')::int];
    EXIT WHEN v_op IS NULL OR v_op NOT IN ('*', '/');
    v_b := public.catalogo_formula_factor(p_t, (v_a->>'p')::int + 1);
    v_a := jsonb_build_object('n', jsonb_build_object('op', v_op, 'a', v_a->'n', 'b', v_b->'n'), 'p', v_b->'p');
  END LOOP;
  RETURN v_a;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_formula_aritmetica(p_t text[], p_i int)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_a jsonb := public.catalogo_formula_termino(p_t, p_i);
  v_b jsonb;
  v_op text;
BEGIN
  LOOP
    v_op := p_t[(v_a->>'p')::int];
    EXIT WHEN v_op IS NULL OR v_op NOT IN ('+', '-');
    v_b := public.catalogo_formula_termino(p_t, (v_a->>'p')::int + 1);
    v_a := jsonb_build_object('n', jsonb_build_object('op', v_op, 'a', v_a->'n', 'b', v_b->'n'), 'p', v_b->'p');
  END LOOP;
  RETURN v_a;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_formula_comparacion(p_t text[], p_i int)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_a jsonb;
  v_b jsonb;
  v_op text;
  v_nivel int := 0;
  v_j int := p_i;
  v_siguiente text;
BEGIN
  -- Un paréntesis abre una condición o una cuenta: `(a > b) y c > d` o `(a + b) × 2 > c`. Lo dice lo que
  -- viene después de cerrarlo.
  IF p_t[p_i] = '(' THEN
    LOOP
      v_nivel := v_nivel + CASE p_t[v_j] WHEN '(' THEN 1 WHEN ')' THEN -1 ELSE 0 END;
      EXIT WHEN v_nivel = 0 OR v_j > array_length(p_t, 1);
      v_j := v_j + 1;
    END LOOP;
    IF v_nivel <> 0 THEN
      RAISE EXCEPTION 'Falta cerrar un paréntesis' USING ERRCODE = 'CA001';
    END IF;
    v_siguiente := lower(p_t[v_j + 1]);
    IF v_siguiente IS NULL OR v_siguiente IN ('y', 'o', 'entonces', ')') THEN
      v_a := public.catalogo_formula_condicion(p_t, p_i + 1);
      IF p_t[(v_a->>'p')::int] IS DISTINCT FROM ')' THEN
        RAISE EXCEPTION 'Falta cerrar un paréntesis' USING ERRCODE = 'CA001';
      END IF;
      RETURN jsonb_build_object('n', v_a->'n', 'p', (v_a->>'p')::int + 1);
    END IF;
  END IF;

  v_a := public.catalogo_formula_aritmetica(p_t, p_i);
  v_op := p_t[(v_a->>'p')::int];
  IF v_op IS NULL OR v_op NOT IN ('>', '<', '>=', '<=', '=', '<>') THEN
    RAISE EXCEPTION 'Falta un comparador' USING ERRCODE = 'CA001';
  END IF;
  v_b := public.catalogo_formula_aritmetica(p_t, (v_a->>'p')::int + 1);
  RETURN jsonb_build_object(
    'n', jsonb_build_object('op', 'cmp', 'o', v_op, 'a', v_a->'n', 'b', v_b->'n'),
    'p', v_b->'p'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_formula_condicion(p_t text[], p_i int)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_a jsonb := public.catalogo_formula_comparacion(p_t, p_i);
  v_b jsonb;
  v_op text;
  v_siguiente text;
BEGIN
  LOOP
    v_siguiente := lower(p_t[(v_a->>'p')::int]);
    EXIT WHEN v_siguiente IS NULL OR v_siguiente NOT IN ('y', 'o');
    IF v_op IS NOT NULL AND v_siguiente <> v_op THEN
      RAISE EXCEPTION 'Para mezclar "y" con "o" hacen falta paréntesis' USING ERRCODE = 'CA001';
    END IF;
    v_op := v_siguiente;
    v_b := public.catalogo_formula_comparacion(p_t, (v_a->>'p')::int + 1);
    v_a := jsonb_build_object('n', jsonb_build_object('op', v_op, 'a', v_a->'n', 'b', v_b->'n'), 'p', v_b->'p');
  END LOOP;
  RETURN v_a;
END;
$$;

-- p_eleccion: la regla con que el sistema define un material múltiple, cuyas ramas terminan en una opción
-- o en "ninguno" en vez de en una cuenta (decisiones/catalogo/paquete.md → Editor de paquete).
CREATE OR REPLACE FUNCTION public.catalogo_formula_expresion(p_t text[], p_i int, p_eleccion boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_c jsonb;
  v_a jsonb;
  v_b jsonb;
  v_q int;
BEGIN
  IF lower(p_t[p_i]) = 'si' THEN
    v_c := public.catalogo_formula_condicion(p_t, p_i + 1);
    v_q := (v_c->>'p')::int;
    IF lower(p_t[v_q]) IS DISTINCT FROM 'entonces' THEN
      RAISE EXCEPTION 'Falta "entonces"' USING ERRCODE = 'CA001';
    END IF;
    v_a := public.catalogo_formula_expresion(p_t, v_q + 1, p_eleccion);
    v_q := (v_a->>'p')::int;
    IF lower(p_t[v_q]) IS DISTINCT FROM 'si' OR lower(p_t[v_q + 1]) IS DISTINCT FROM 'no' THEN
      RAISE EXCEPTION 'Falta "si no"' USING ERRCODE = 'CA001';
    END IF;
    v_b := public.catalogo_formula_expresion(p_t, v_q + 2, p_eleccion);
    RETURN jsonb_build_object(
      'n', jsonb_build_object('op', 'si', 'c', v_c->'n', 'a', v_a->'n', 'b', v_b->'n'),
      'p', v_b->'p'
    );
  END IF;

  IF NOT p_eleccion THEN
    RETURN public.catalogo_formula_aritmetica(p_t, p_i);
  END IF;

  v_a := public.catalogo_formula_factor(p_t, p_i);
  IF v_a->'n'->>'op' <> 'var' THEN
    RAISE EXCEPTION 'Valor inesperado: va una opción o "ninguno"' USING ERRCODE = 'CA001';
  END IF;
  RETURN jsonb_build_object(
    'n', CASE WHEN lower(p_t[p_i]) = 'ninguno'
              THEN jsonb_build_object('op', 'ninguno')
              ELSE jsonb_build_object('op', 'opcion', 'v', v_a->'n'->'v') END,
    'p', v_a->'p'
  );
END;
$$;

-- p_tipo: 'formula' (un número), 'condicion' (cierto o falso) o 'eleccion' (qué opción).
CREATE OR REPLACE FUNCTION public.catalogo_formula_parsear(p_texto text, p_tipo text DEFAULT 'formula')
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = public
AS $$
DECLARE
  v_t text[] := public.catalogo_formula_tokens(p_texto);
  v_r jsonb;
BEGIN
  v_r := CASE p_tipo
    WHEN 'condicion' THEN public.catalogo_formula_condicion(v_t, 1)
    WHEN 'eleccion' THEN public.catalogo_formula_expresion(v_t, 1, true)
    ELSE public.catalogo_formula_expresion(v_t, 1)
  END;
  IF (v_r->>'p')::int <= coalesce(array_length(v_t, 1), 0) THEN
    RAISE EXCEPTION 'Sobra: %', v_t[(v_r->>'p')::int] USING ERRCODE = 'CA001';
  END IF;
  RETURN v_r->'n';
END;
$$;

-- De qué depende: con esto se revisa lo que puede faltar y lo circular (decisiones/catalogo/versiones.md →
-- Qué frena el envío). Las opciones de una elección no cuentan: no son valores de la cuenta.
CREATE OR REPLACE FUNCTION public.catalogo_formula_usa(p_arbol jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT coalesce(array_agg(DISTINCT x #>> '{}'), '{}')
  FROM jsonb_path_query(p_arbol, '$.** ? (@.op == "var").v') AS x;
$$;

-- ============================================================
-- 3. Calcular: recorre el árbol con los valores que le pasan
-- ============================================================
CREATE OR REPLACE FUNCTION public.catalogo_condicion_evaluar(p_n jsonb, p_v jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_a numeric;
  v_b numeric;
BEGIN
  -- Con IF y no con AND/OR: `flecha > 0 y ancho / flecha > 2` no tiene que dividir si la flecha es 0.
  IF p_n->>'op' = 'y' THEN
    IF NOT public.catalogo_condicion_evaluar(p_n->'a', p_v) THEN
      RETURN false;
    END IF;
    RETURN public.catalogo_condicion_evaluar(p_n->'b', p_v);
  END IF;
  IF p_n->>'op' = 'o' THEN
    IF public.catalogo_condicion_evaluar(p_n->'a', p_v) THEN
      RETURN true;
    END IF;
    RETURN public.catalogo_condicion_evaluar(p_n->'b', p_v);
  END IF;

  v_a := public.catalogo_formula_evaluar(p_n->'a', p_v);
  v_b := public.catalogo_formula_evaluar(p_n->'b', p_v);
  RETURN CASE p_n->>'o'
    WHEN '>' THEN v_a > v_b
    WHEN '<' THEN v_a < v_b
    WHEN '>=' THEN v_a >= v_b
    WHEN '<=' THEN v_a <= v_b
    WHEN '=' THEN v_a = v_b
    ELSE v_a <> v_b
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogo_formula_evaluar(p_n jsonb, p_v jsonb)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_op text := p_n->>'op';
  v_a numeric;
  v_b numeric;
BEGIN
  CASE v_op
    WHEN 'num' THEN
      RETURN (p_n->>'v')::numeric;
    WHEN 'var' THEN
      v_a := (p_v->>(p_n->>'v'))::numeric;
      IF v_a IS NULL THEN
        RAISE EXCEPTION 'Falta el valor de %', p_n->>'v' USING ERRCODE = 'CA002';
      END IF;
      RETURN v_a;
    WHEN 'pi' THEN
      RETURN pi()::numeric;
    WHEN 'neg' THEN
      RETURN -public.catalogo_formula_evaluar(p_n->'a', p_v);
    WHEN 'si' THEN
      IF public.catalogo_condicion_evaluar(p_n->'c', p_v) THEN
        RETURN public.catalogo_formula_evaluar(p_n->'a', p_v);
      END IF;
      RETURN public.catalogo_formula_evaluar(p_n->'b', p_v);
    WHEN 'redondear_arriba' THEN
      -- 2 / 3 × 3 da 2,00000000000000000001: sin redondear antes, subiría a 3.
      RETURN ceil(round(public.catalogo_formula_evaluar(p_n->'a', p_v), 12));
    WHEN 'arcoseno' THEN
      RETURN asin(public.catalogo_formula_evaluar(p_n->'a', p_v)::float8)::numeric;
    ELSE
      v_a := public.catalogo_formula_evaluar(p_n->'a', p_v);
      v_b := public.catalogo_formula_evaluar(p_n->'b', p_v);
      CASE v_op
        WHEN '+' THEN RETURN v_a + v_b;
        WHEN '-' THEN RETURN v_a - v_b;
        WHEN '*' THEN RETURN v_a * v_b;
        WHEN '/' THEN RETURN v_a / v_b;
      END CASE;
  END CASE;
END;
$$;

-- El nombre de la opción; NULL es "ninguno".
CREATE OR REPLACE FUNCTION public.catalogo_eleccion_evaluar(p_n jsonb, p_v jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_n jsonb := p_n;
BEGIN
  WHILE v_n->>'op' = 'si' LOOP
    v_n := CASE WHEN public.catalogo_condicion_evaluar(v_n->'c', p_v) THEN v_n->'a' ELSE v_n->'b' END;
  END LOOP;
  RETURN CASE WHEN v_n->>'op' = 'opcion' THEN v_n->>'v' END;
END;
$$;

-- ============================================================
-- 4. Privilegios
-- ============================================================
REVOKE EXECUTE ON FUNCTION
  public.catalogo_formula_tokens(text),
  public.catalogo_formula_factor(text[], int),
  public.catalogo_formula_termino(text[], int),
  public.catalogo_formula_aritmetica(text[], int),
  public.catalogo_formula_comparacion(text[], int),
  public.catalogo_formula_condicion(text[], int),
  public.catalogo_formula_expresion(text[], int, boolean),
  public.catalogo_formula_parsear(text, text),
  public.catalogo_formula_usa(jsonb),
  public.catalogo_condicion_evaluar(jsonb, jsonb),
  public.catalogo_formula_evaluar(jsonb, jsonb),
  public.catalogo_eleccion_evaluar(jsonb, jsonb)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.catalogo_formula_tokens(text),
  public.catalogo_formula_factor(text[], int),
  public.catalogo_formula_termino(text[], int),
  public.catalogo_formula_aritmetica(text[], int),
  public.catalogo_formula_comparacion(text[], int),
  public.catalogo_formula_condicion(text[], int),
  public.catalogo_formula_expresion(text[], int, boolean),
  public.catalogo_formula_parsear(text, text),
  public.catalogo_formula_usa(jsonb),
  public.catalogo_condicion_evaluar(jsonb, jsonb),
  public.catalogo_formula_evaluar(jsonb, jsonb),
  public.catalogo_eleccion_evaluar(jsonb, jsonb)
TO authenticated;
