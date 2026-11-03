# Catálogo (`sql/158_catalogo_formulas.sql`, `sql/159_catalogo_registros.sql` — corridas en Supabase vía MCP)

Ficha y decisiones: `decisiones/catalogo/README.md`. Tests: `sql/tests/catalogo_formulas.sql`,
`sql/tests/catalogo_registros.sql`.

Paquetes y versiones todavía no: el SQL va por tramos (`BACKLOG.md` → *Catálogo*). Por eso acá falta lo que depende
de las versiones: los datos del insumo que quedan fijos, las bajas en cascada y los avisos.

## Permisos

`catalogo_paquetes` (vista) → `catalogo_armar`, `catalogo_aprobar` · `catalogo_insumos` (vista) → `catalogo_cargar`,
`catalogo_costos` · `catalogo_fijos` (vista) → `catalogo_fijos_editar` · `catalogo_porcentajes` (vista) →
`catalogo_porcentajes_editar`. Se delega todo menos `catalogo_aprobar`. Sin reglas entre permisos.

| qué | leer | escribir |
|---|---|---|
| categorías | cualquiera de las cuatro vistas | por `tipo`: `paquete` → armar, `insumo` → cargar, `servicio` → fijos_editar |
| colores | cualquiera de las cuatro vistas | `catalogo_cargar` |
| insumos y variantes | cualquiera de las cuatro vistas | por `tipo`: `insumo` → cargar, `servicio` → fijos_editar |
| costos | por `tipo`: `insumo` → `catalogo_costos`, `servicio` → `catalogo_fijos_editar` | lo mismo, solo por `catalogo_costos_cargar` |
| servicios en % | `catalogo_porcentajes` | `catalogo_porcentajes_editar`, solo por funciones |

## Enums

| enum | valores | notas |
|---|---|---|
| `tipo_catalogo` | `paquete` \| `insumo` \| `servicio` | las categorías usan los tres; `catalogo_insumos`, los dos últimos |
| `unidad_insumo` | `mm` \| `m2` \| `u` | |
| `alcance_minimo` | `paquete` \| `presupuesto` | contra qué se compara el mínimo de un servicio en % |

## catalogo_categorias

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | UNIQUE (`id`, `tipo`), para la FK compuesta de los insumos |
| tipo | `tipo_catalogo` | no se cambia: sin GRANT de UPDATE |
| nombre | text | sin espacios sobrantes. Único por `tipo` entre las activas, sin distinguir mayúsculas |
| activo, created_at, updated_at | | |

Trigger `catalogo_categorias_validar`: con un insumo adentro, aun de baja, el nombre queda fijo (CA006); con uno activo,
no se da de baja (CA007). Lo de las categorías de paquete llega con las versiones.

## catalogo_colores

`id`, `nombre` (único entre los activos, sin distinguir mayúsculas), `activo`, `created_at`, `updated_at`. Trigger
`catalogo_colores_validar`: con una variante, aun de baja, el nombre queda fijo (CA006); con una activa, no se da de baja
(CA007).

## catalogo_insumos

Insumos y servicios fijos en una sola tabla.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tipo | `tipo_catalogo` | `insumo` o `servicio`. No se cambia: sin GRANT de UPDATE |
| nombre | text | único por `tipo` entre los activos, sin distinguir mayúsculas |
| categoria_id | uuid | FK compuesta (`categoria_id`, `tipo`) → categorías: no entra en una de otro tipo (23503) |
| unidad | `unidad_insumo` | |
| peso | numeric(10,4), nullable | kilos por metro, por m2 o por unidad. NULL es vacío, y 0 es un dato |
| espesor | numeric(8,2), nullable | |
| con_color | boolean | false: una sola variante, indistinta |
| activo, created_at, updated_at | | |

CHECK `catalogo_insumos_servicio`: un servicio no lleva peso, espesor ni color. Triggers: `catalogo_insumos_validar` (no
entra ni se reactiva en una categoría de baja, CA008) y `catalogo_insumos_variantes_alta` / `_cambio` (nace la variante
indistinta; cambiar `con_color` apaga las del otro tipo).

## catalogo_variantes

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| insumo_id | uuid FK → insumos | no se cambia |
| color_id | uuid FK → colores, nullable | NULL: indistinta. No se cambia |
| activo, created_at, updated_at | | |

UNIQUE NULLS NOT DISTINCT (`insumo_id`, `color_id`), sin `WHERE activo`: una fila por color para siempre, y volver a
sumarlo la reactiva con sus costos (`catalogo_variante_sumar`). Trigger `catalogo_variantes_validar`: tiene que coincidir
con `con_color` (CA009), la indistinta no se baja sola (CA009), y no entra ni se reactiva en un color de baja (CA008).

## catalogo_costos

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| variante_id | uuid FK → variantes | |
| costo | numeric(14,4) | > 0, sin IVA |
| moneda | `moneda` | la de cada carga |
| creado_por | uuid FK → usuarios | |
| created_at | timestamptz | desde cuándo rige. UNIQUE (`variante_id`, `created_at`) |
| activo, updated_at | | |

Sin GRANT de INSERT ni UPDATE: un costo no se pisa.

## catalogo_porcentajes y catalogo_porcentajes_valores

`catalogo_porcentajes` es a qué apunta otro módulo: `id`, `activo` (copia del `de_baja` del último valor), `created_at`,
`updated_at`. Lo demás está en la historia, que es la autoridad. Sin GRANT de INSERT ni UPDATE en ninguna de las dos.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| porcentaje_id | uuid FK → catalogo_porcentajes | |
| nombre | text | único entre los activos, sin distinguir mayúsculas (CA010) |
| porcentaje | numeric(7,3) | > 0 |
| paso | integer | 1 a 3 |
| categorias | uuid[] | de insumo o de servicio (CA011). Vacío: todo el despiece. Solo en el paso 1 |
| minimo, minimo_moneda, minimo_por | numeric(14,4), `moneda`, `alcance_minimo`, nullable | los tres o ninguno. Nunca en el paso 3 |
| opcional | boolean | |
| de_baja | boolean | dato de la historia: a una fecha se sabe si estaba activo |
| revierte_id | uuid FK → valores, nullable | qué valor revierte esta fila |
| creado_por | uuid FK → usuarios | |
| created_at | timestamptz | desde cuándo rige. UNIQUE (`porcentaje_id`, `created_at`) |
| activo, updated_at | | `activo` es de la fila, no del servicio |

## Funciones de los registros

| función | seguridad | qué hace |
|---|---|---|
| `catalogo_puede_ver()`, `catalogo_puede_editar(tipo)`, `catalogo_tipos_con_costo()` | INVOKER | los permisos de arriba, en un solo lugar |
| `catalogo_insumo_alta(nombre, categoria, unidad, peso, espesor, colores = '{}') → uuid` | INVOKER | sin colores, indistinto |
| `catalogo_fijo_alta(nombre, categoria, unidad, costo, moneda) → uuid` | INVOKER | nace con su costo; sin costo, no nace |
| `catalogo_variante_sumar(insumo, color) → uuid` | INVOKER | suma el color o reactiva su fila |
| `catalogo_costos_vigentes(en = now())` | INVOKER | el costo de cada variante a esa fecha. Respeta RLS |
| `catalogo_costos_niveles(filas)` | INVOKER | anterior y nivel de cada fila, antes de guardar. El anterior se pasa a la moneda nueva: sin tipo de cambio, MO001 |
| `catalogo_costos_cargar(filas, confirmar_rojo = false) → integer` | DEFINER | filas: `[{variante_id, costo, moneda}]`. Se guardan juntas o ninguna. 42501 si alguna no está permitida |
| `catalogo_porcentajes_vigentes(en = now())` | INVOKER | el último valor de cada servicio a esa fecha, de baja incluidos. Respeta RLS |
| `catalogo_porcentaje_guardar(id, nombre, porcentaje, paso, categorias, minimo, minimo_moneda, minimo_por, opcional, confirmar_rojo = false) → uuid` | DEFINER | `id` NULL: alta. Sin cambios, no suma fila. Devuelve el servicio |
| `catalogo_porcentaje_activar(id, activo)` | DEFINER | baja y reactivación |
| `catalogo_porcentaje_revertir(valor_id, confirmar_rojo = false) → uuid` | DEFINER | solo el último cambio. Revertir el alta lo deja de baja. Devuelve el valor nuevo |
| `catalogo_porcentajes_historia(id)` | DEFINER | filas con `cargado_por`, `nivel` y `ultimo`. Vacío sin la vista |
| `catalogo_porcentaje_empezar()`, `catalogo_porcentaje_registrar(valor, confirmar_rojo)` | INVOKER, sin EXECUTE | exigen el permiso con lock, y son el único camino a la historia: controles e inserción |

**Errores de los registros:** CA003 rojo sin confirmar · CA004 los del paso 3 llegan a 100 · CA005 no es el último cambio ·
CA006 nombre fijo · CA007 baja con algo activo adentro · CA008 adentro de una categoría o color de baja · CA009 la variante
no corresponde al insumo · CA010 nombre de servicio en % repetido · CA011 categoría que no es de insumo ni de servicio.

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
