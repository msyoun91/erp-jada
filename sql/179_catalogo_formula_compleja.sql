-- Catálogo: una fórmula demasiado anidada se rechaza al escribirla, y un número grande se lee (AUDITORIA_CATALOGO.md, hallazgo 12).
-- Decisiones: decisiones/catalogo/despiece.md → Las fórmulas se calculan sin SQL dinámico. Test: sql/tests/catalogo_formulas.sql y catalogo_despiece.sql.

-- p_tipo: 'formula' (un número), 'condicion' (cierto o falso) o 'eleccion' (qué opción).
-- Los paréntesis no dejan rastro en el árbol y solo gastan pila al parsear, por eso el 54001. Una suma larga parsea sin recursión
-- pero arma un árbol que después no se puede calcular: el tope de niveles la frena antes de guardarla.
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
  BEGIN
    v_r := CASE p_tipo
      WHEN 'condicion' THEN public.catalogo_formula_condicion(v_t, 1)
      WHEN 'eleccion' THEN public.catalogo_formula_expresion(v_t, 1, true)
      ELSE public.catalogo_formula_expresion(v_t, 1)
    END;
  EXCEPTION WHEN statement_too_complex THEN
    RAISE EXCEPTION 'La fórmula es demasiado compleja: separala en variables' USING ERRCODE = 'CA001';
  END;
  IF (v_r->>'p')::int <= coalesce(array_length(v_t, 1), 0) THEN
    RAISE EXCEPTION 'Sobra: %', v_t[(v_r->>'p')::int] USING ERRCODE = 'CA001';
  END IF;
  -- 100 operaciones una dentro de otra dan 101 niveles: el nivel 102 ya es de más.
  IF jsonb_path_exists(v_r->'n', '$.**{102}') THEN
    RAISE EXCEPTION 'La fórmula es demasiado compleja: separala en variables' USING ERRCODE = 'CA001';
  END IF;
  RETURN v_r->'n';
END;
$$;

-- 1500 → 1.500, -18 → −18, 666,666 → 666,67: se lee como en el resto del sistema. Sin to_char, cuya máscara da ### si no le alcanza.
CREATE OR REPLACE FUNCTION public.catalogo_numero_texto(p_n numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE WHEN round(p_n, 2) < 0 THEN '−' ELSE '' END
    || translate(regexp_replace(rtrim(rtrim(abs(round(p_n, 2))::text, '0'), '.'), '(\d)(?=(\d{3})+(\.|$))', '\1,', 'g'), ',.', '.,');
$$;
