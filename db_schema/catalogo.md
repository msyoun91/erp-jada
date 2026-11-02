# Catálogo (`sql/158_catalogo_formulas.sql` — corrida en Supabase vía MCP)

Ficha y decisiones: `decisiones/catalogo/README.md`. Test: `sql/tests/catalogo_formulas.sql`.

Todavía sin tablas: el SQL va por tramos (`BACKLOG.md` → *Catálogo*).

## Fórmulas

Técnica escribe texto, la base lo convierte en un árbol, y calcular recorre el árbol sin ejecutar SQL
(`decisiones/catalogo/despiece.md` → *Las fórmulas se calculan sin SQL dinámico*). Nada de esto lee tablas.
Todas son INVOKER e IMMUTABLE, con EXECUTE para `authenticated` y sin `anon`.

| función | qué hace |
|---|---|
| `catalogo_formula_parsear(texto, tipo = 'formula') → jsonb` | del texto al árbol. `tipo`: `formula` (da un número), `condicion` (cierto o falso) o `eleccion` (qué opción, para un material que define el sistema). NULL con texto NULL. IMMUTABLE para ir en una columna generada: lo que no se entiende no se guarda |
| `catalogo_formula_evaluar(arbol, valores) → numeric` | calcula una `formula`. `valores` es un jsonb `{nombre: número}` |
| `catalogo_condicion_evaluar(arbol, valores) → boolean` | calcula una `condicion`. `y` y `o` no evalúan el lado derecho si no hace falta |
| `catalogo_eleccion_evaluar(arbol, valores) → text` | nombre de la opción; NULL es "ninguno" |
| `catalogo_formula_usa(arbol) → text[]` | los nombres de los que depende, sin las opciones de una elección |
| `catalogo_formula_tokens`, `_factor`, `_termino`, `_aritmetica`, `_comparacion`, `_condicion`, `_expresion` | los pasos del parser, que no se llaman sueltos. Tienen EXECUTE porque `parsear` es INVOKER |

**Lo que se puede escribir:** números con coma decimal; nombres sueltos o `[entre corchetes]`; `+ − × /` (también
`- *`); paréntesis; `> < >= <= = <>`; `y`, `o`; `si … entonces … si no …`; `redondear_arriba(…)`, `arcoseno(…)`;
`pi`. En una `eleccion`, las ramas terminan en un nombre de opción o en `ninguno`.

**Palabras reservadas**, sin distinguir mayúsculas: `si`, `entonces`, `no`, `y`, `o`, `pi`. Entre corchetes son
un nombre. Los nombres sí distinguen mayúsculas: `Ancho` no encuentra a `ancho`.

**El árbol.** `{op, …}`, con `op`: `num` (`v`), `var` (`v`), `pi`, `neg` (`a`), `+ - * /` (`a`, `b`), `si` (`c`, `a`,
`b`), `redondear_arriba` y `arcoseno` (`a`), `cmp` (`o`, `a`, `b`), `y` y `o` (`a`, `b`), `opcion` (`v`), `ninguno`.

**Errores:** CA001 no se entiende la fórmula (el mensaje dice qué falta) · CA002 falta el valor de un nombre. Al
calcular también salen los de Postgres: 22012 división por cero, 22003 `arcoseno` fuera de rango.
