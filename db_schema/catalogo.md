# Catálogo (`sql/158_catalogo_formulas.sql`, `sql/159_catalogo_registros.sql`, `sql/160_catalogo_paquetes.sql`, `sql/161_catalogo_despiece.sql`, `sql/162_catalogo_ciclo.sql`, `sql/163_catalogo_precio.sql`, `sql/164_catalogo_avisos_enums.sql`, `sql/165_catalogo_avisos.sql`, `sql/167_catalogo_segun_y_cambiar.sql` — corridas en Supabase vía MCP)

Ficha y decisiones: `decisiones/catalogo/README.md`. Tests: `sql/tests/catalogo_formulas.sql`,
`sql/tests/catalogo_registros.sql`, `sql/tests/catalogo_paquetes.sql`, `sql/tests/catalogo_despiece.sql`,
`sql/tests/catalogo_ciclo.sql`, `sql/tests/catalogo_precio.sql`, `sql/tests/catalogo_avisos.sql`, `sql/tests/catalogo_segun.sql`.

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
| paquetes, versiones y su contenido | `catalogo_paquetes` | `catalogo_armar`. El estado y el número de una versión y por qué está de baja un paquete, nadie directo |
| historia de una versión | `catalogo_paquetes` | solo por las funciones del ciclo |

## Enums

| enum | valores | notas |
|---|---|---|
| `tipo_catalogo` | `paquete` \| `insumo` \| `servicio` | las categorías usan los tres; `catalogo_insumos`, los dos últimos |
| `unidad_insumo` | `mm` \| `m2` \| `u` | |
| `alcance_minimo` | `paquete` \| `presupuesto` | contra qué se compara el mínimo de un servicio en % |
| `estado_version_catalogo` | `borrador` \| `en_revision` \| `publicado` \| `obsoleto` \| `descartado` | |
| `tipo_material` | `unico` \| `elige_vendedor` \| `elige_sistema` \| `sigue` | |
| `accion_version_catalogo` | `enviada` \| `retirada` \| `devuelta` \| `aprobada` \| `obsoleta` \| `descartada` | las filas de la historia de una versión |

## catalogo_categorias

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | UNIQUE (`id`, `tipo`), para la FK compuesta de los insumos |
| tipo | `tipo_catalogo` | no se cambia: sin GRANT de UPDATE |
| nombre | text | sin espacios sobrantes. Único por `tipo` entre las activas, sin distinguir mayúsculas |
| activo, created_at, updated_at | | |

Trigger `catalogo_categorias_validar` (DEFINER): con un insumo adentro, aun de baja, o con una versión enviada, el nombre
queda fijo (CA006); con un insumo activo o la versión publicada de un paquete activo, no se da de baja (CA007).

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

CHECK `catalogo_insumos_servicio`: un servicio no lleva peso, espesor ni color. Triggers: `catalogo_insumos_validar`
(DEFINER: no entra ni se reactiva en una categoría de baja, CA008; usado por una versión enviada, en un material o una
opción activos, nombre, categoría, unidad y `con_color` quedan fijos y un peso o espesor solo se completa si estaba vacío,
CA006) y `catalogo_insumos_variantes_alta` / `_cambio` (nace la variante indistinta; cambiar `con_color` apaga las del
otro tipo).

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
CA006 nombre o dato fijo · CA007 baja con algo activo adentro · CA008 adentro de una categoría o color de baja · CA009 la
variante no corresponde al insumo · CA010 nombre de servicio en % repetido · CA011 categoría que no es de insumo ni de servicio.

## Paquetes y versiones

El contenido de un borrador se escribe directo, con RLS y triggers. Alta, versión nueva y duplicar son funciones. El estado
lo cambian las funciones del ciclo (*El ciclo*). Un borrador puede estar a medias: acá solo se frena lo que no tiene sentido
en ningún momento.

**`catalogo_paquetes`:** `id`, `activo`, `baja_insumo_id`, `baja_variante_id`, `created_at`, `updated_at`. GRANT de UPDATE solo
sobre `activo`, con `catalogo_armar`: dar de baja y reactivar es un UPDATE. Las dos `baja_*` las pone la cascada (*El ciclo*);
vacías y de baja es a mano. CHECK `catalogo_paquetes_baja`: a lo sumo una, y ninguna si está activo.

**`catalogo_versiones`**

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| paquete_id | uuid FK → paquetes | no se cambia |
| numero | integer | lo pone el trigger: el siguiente, contando las descartadas. UNIQUE (`paquete_id`, `numero`) |
| estado | `estado_version_catalogo` | `borrador` por defecto. Sin GRANT |
| enviada | boolean, generada | `en_revision`, `publicado` u `obsoleto`: lo que fija datos de insumos y categorías |
| nombre | text | se edita solo en borrador |
| categoria_id, categoria_tipo | uuid, `tipo_catalogo` generada | FK compuesta → categorías: solo de paquete (23503) |
| activo, created_at, updated_at | | dejar de vender es la baja del paquete, no de la versión |

Únicos parciales: una abierta por paquete (`borrador`, `en_revision`), una publicada por paquete, y el nombre entre las
publicadas de todos los paquetes, sin distinguir mayúsculas. Al aprobar, la anterior pasa a obsoleta antes.

**Toda tabla de contenido** lleva `version_id`, `activo`, `created_at` y `updated_at`. `version_id` no se cambia, y lo que
apunta a otra tabla de contenido es FK compuesta con él: no se apunta a algo de otra versión (23503). Cada fórmula `x`
tiene su `x_arbol`, generada con `catalogo_formula_parsear`: lo que no se entiende no se guarda (CA001).

| tabla | columnas | se frena al guardar |
|---|---|---|
| `catalogo_versiones_colores` | `color_id`, `base` | color repetido, dos bases |
| `catalogo_piezas` | `nombre`, `orden`, `cantidad` ('1'), `opcional`, `incluida`, `requiere_pieza_id`, `secundario`, `calcula_espesor`, `peso_a_produccion`, `espesor_a_produccion` | nombre repetido en la versión; una fija incluida, secundaria o con requisito; requerirse a sí misma |
| `catalogo_variables` | `pieza_id` (NULL: suelta), `nombre`, `orden`, `ingresa_vendedor`, `es_lista`, `formula`, `valores`, `valor_predeterminado`, `es_cantidad`, `minimo`, `maximo`, `secundario`, `a_produccion`, `segun_material_id` | nombre repetido en la versión; sin fórmula ni material si no la ingresa el vendedor; lista o mínimo, máximo, cantidad o secundaria si no la ingresa; lista con fórmula, mínimo o cantidad; predeterminado fuera de la lista; según un material si la ingresa el vendedor o con fórmula |
| `catalogo_variables_valores` | `variable_id`, `opcion_id`, `formula` | valor repetido para la opción; lo que no se entiende (CA001). Solo se miran los de las opciones de `segun_material_id`: lo cargado para otro material queda sin efecto |
| `catalogo_materiales` | `pieza_id`, `orden`, `tipo`, `nombre`, `insumo_id`, `medida`, `ancho`, `alto`, `area`, `cantidad` ('1'), `eleccion`, `sin_eleccion`, `sigue_material_id`, `secundario`, `cuenta_peso` (true), `cuenta_espesor` (false) | múltiple repetido en la pieza; `nombre` solo y siempre en el múltiple; `insumo_id` solo en `unico`; `eleccion` solo en `elige_sistema`; `sigue_material_id` solo en `sigue`, y no a sí mismo; `sin_eleccion` solo en `elige_vendedor`; `secundario` solo en `elige_vendedor` y `sigue` |
| `catalogo_opciones` | `material_id`, `orden`, `insumo_id`, `sigue_opcion_id`, `predeterminada`, `medida`, `ancho`, `alto`, `area`, `cantidad` (lo vacío se hereda) | insumo repetido en el material; dos predeterminadas; dos parejas para una opción; sin insumo ni pareja; una pareja predeterminada |
| `catalogo_condiciones` | `variable_id`, `material_id` u `opcion_id`, `condicion`, `mensaje`, `bloquea` | no ser de exactamente uno; sin mensaje |
| `catalogo_casos` | `nombre`, `entrada` (jsonb; forma en *El despiece*) | nombre repetido en la versión; una entrada con otra forma (CHECK `catalogo_casos_entrada_forma`) |

En un material que sigue a otro hay una opción por cada opción de aquel: `sigue_opcion_id` es esa opción e `insumo_id` su
pareja, NULL si es "ninguna". Sin fila, la pareja está vacía. Una fila con `sigue_opcion_id` NULL es una opción suelta: no es
pareja de nadie y solo se elige a mano. Los nombres repetidos no distinguen mayúsculas.

**Triggers.** `catalogo_versiones_validar`: pone el número; fuera de borrador, nombre y categoría no cambian (CA012).
`catalogo_contenido_validar`, en las ocho tablas: fuera de borrador no se edita (CA012), con `FOR SHARE` sobre la versión
para que no entre una edición mientras se envía; lo sacado no vuelve (CA015). `catalogo_contenido_baja`: sacar una pieza
saca sus variables y materiales; un material, sus opciones, condiciones y las variables según él; una opción, su pareja, sus
condiciones y sus valores; una variable, sus condiciones y sus valores. Lo que requería la pieza o seguía al material queda sin apuntar.

| función | seguridad | qué hace |
|---|---|---|
| `catalogo_paquete_alta(nombre, categoria) → uuid` | INVOKER | el paquete con su v1 vacía. Devuelve la versión |
| `catalogo_version_nueva(paquete, origen = NULL) → uuid` | INVOKER | sin origen, desde la publicada. Otra abierta: CA013. Origen que no está: CA014 |
| `catalogo_paquete_duplicar(version, nombre) → uuid` | INVOKER | paquete nuevo, v1 copiada de cualquier versión, sin vínculo. Origen que no está: CA014 |
| `catalogo_version_copiar(origen, paquete, nombre) → uuid` | INVOKER | la copia, solo lo activo. Las fórmulas apuntan por nombre y no cambian. Tiene EXECUTE porque las dos de arriba son INVOKER |

**Errores:** CA012 la versión no está en borrador · CA013 ya hay una versión abierta · CA014 no se encontró de qué versión
copiar · CA015 lo sacado de un borrador no vuelve.

## El despiece

Un solo cálculo, sin costos, para cualquier versión (`decisiones/catalogo/despiece.md`). Es INVOKER: lo abre quien tiene la
vista Paquetes, y una función DEFINER del precio lo llama como dueña.

| función | seguridad | qué hace |
|---|---|---|
| `catalogo_despiece(version, entrada = '{}') → jsonb` | INVOKER | el cálculo. Sin la vista o sin esa versión: CA016. Entrada con otra forma: CA017. Lo demás no es un error de la base: sale en `errores` |
| `catalogo_casos_calcular(version)` | INVOKER | `caso_id`, `nombre`, `resultado`: el mismo cálculo para cada caso activo |
| `catalogo_entrada_valida(entrada) → boolean` | INVOKER, IMMUTABLE | la forma de la entrada, en el CHECK de los casos y en el cálculo |
| `catalogo_numero_texto(n) → text` | INVOKER, IMMUTABLE | 1500 → `1.500`, -18 → `−18`, 666,666 → `666,67`: para los mensajes |
| `catalogo_despiece_entrada`, `_elegir`, `_segun`, `_medida`, `_fila`, `_sumas` | INVOKER | los pasos, que no se llaman sueltos. Tienen EXECUTE porque `catalogo_despiece` es INVOKER, y ninguno lee costos |

**La entrada.** Todo es opcional, y una clave que no sea de estas cuatro no se guarda:

```json
{"variables": {"ancho": 1500, "mano": "Izquierda"},
 "elecciones": {"Hoja": {"Vidrio": "<insumo_id>", "Manija": null}},
 "piezas": {"Mosquitero": true},
 "color": "<color_id>"}
```

- `variables`: por nombre, número o texto (lista). Solo se leen las que ingresa el vendedor. Sin valor: su predeterminado.
- `elecciones`: pieza → material múltiple → insumo. `null` es "sin elección". Sin valor: la opción predeterminada. En un
  material que sigue a otro es lo elegido a mano: `null` es "ninguna", si es la pareja de alguna opción, y sin valor, la pareja.
- `piezas`: solo las opcionales. Sin valor: como esté marcada. Destildar una saca las que la requieren, y una incluida trae
  la que requiere.
- `color`: sin valor, el base.

**El resultado:**

| clave | qué es |
|---|---|
| `calculable` | false si hay `errores`: entonces `filas` y `piezas` salen vacías |
| `bloqueado` | algún mensaje bloquea. El despiece sale igual |
| `mensaje` | `No se puede calcular con estas medidas`, lo único de esto que lee el vendedor; NULL si se pudo |
| `errores` | text[]: `Vidrio: el alto dio −18 mm`, `x: usa y, que no existe o no se pudo calcular`, `Referencia circular entre a, b` |
| `mensajes` | `[{mensaje, bloquea, variable_id \| material_id \| opcion_id}]`: rango primero, después las condiciones, variables antes que materiales. Salen también si no se pudo calcular |
| `color` | `{id, nombre}` o NULL |
| `variables` | `[{id, nombre, pieza_id?, valor, a_produccion}]`: las sueltas y las de piezas que están y con cantidad mayor que 0 |
| `piezas` | `[{id, nombre, cantidad, peso?, espesor?, peso_a_produccion, espesor_a_produccion}]`: peso y espesor de una sola pieza. Sin la clave: dato vacío o pieza que no calcula espesor |
| `filas` | `[{pieza_id, pieza, material_id, opcion_id?, material, insumo_id, insumo, tipo, categoria_id, unidad, color_id?, color?, medida?, ancho?, alto?, area?, cantidad, total}]` |

En una fila, `cantidad` ya lleva la de la pieza y `total` va en la unidad del insumo (mm, m2 o u). `medida`, `ancho` y `alto`
van en mm; `area`, en m2. Nada va redondeado.

**Errores:** CA016 no se encontró la versión · CA017 la entrada no tiene la forma esperada · CA018 interno: una medida o
cantidad que no se puede usar, no sale de `catalogo_despiece`.

## El ciclo

Decisiones: `decisiones/catalogo/versiones.md` → *El ciclo en la base*. Las funciones son DEFINER o se llaman desde una: Técnica
no ve los costos que frenan el envío, y Administración da de baja servicios sin ver los paquetes que los usan.

**`catalogo_versiones_historia`:** `id`, `version_id` FK, `accion` (`accion_version_catalogo`), `motivo`, `creado_por` FK →
usuarios, `activo`, `created_at`, `updated_at`. CHECK `catalogo_versiones_historia_motivo`: el motivo va solo y siempre en
`devuelta`. Sin GRANT de escritura. Quién envió una versión es la última fila `enviada`.

```
borrador → en_revision (enviar) → publicado (aprobar) → obsoleto (al aprobar la siguiente)
            en_revision → borrador (retirar, sin motivo; devolver, con motivo)
borrador → descartado (solo si el paquete tiene una publicada)
```

| función | seguridad | quién | qué hace |
|---|---|---|---|
| `catalogo_version_revisar(version) → text[]` | DEFINER | `catalogo_paquetes` | lo que frena el envío, para mostrarlo mientras se arma. Vacío: se puede enviar. Sin la vista: CA016 |
| `catalogo_version_enviar(version)` | DEFINER | `catalogo_armar` | de borrador a revisión, si nada frena |
| `catalogo_version_retirar(version)` | DEFINER | `catalogo_armar` | de revisión a borrador |
| `catalogo_version_devolver(version, motivo)` | DEFINER | `catalogo_aprobar` | de revisión a borrador. Sin motivo: CA021 |
| `catalogo_version_aprobar(version)` | DEFINER | `catalogo_aprobar` | revisa de nuevo, pasa la anterior a obsoleta y publica. No toca `activo` del paquete |
| `catalogo_version_descartar(version)` | DEFINER | `catalogo_armar` | solo un borrador, y con una publicada en el paquete |
| `catalogo_version_oferta(version)` | DEFINER | `catalogo_paquetes` | una fila por color ofrecido (una con color NULL si no ofrece ninguno): `color_id`, `color`, `armable`, `piezas_fuera`, `opciones_fuera`, `faltan`. Sin la vista: CA016 |
| `catalogo_baja_aviso(insumo, variante = NULL) → jsonb` | DEFINER | `catalogo_cargar` o `catalogo_fijos_editar`, según el tipo | `{salen, dejan}`; con la vista Paquetes, también `salen_nombres` y `dejan_detalle` `[{nombre, colores, piezas, opciones}]` |

**Sin EXECUTE para nadie**, solo se llega por las de arriba: `catalogo_oferta(version, sin_insumo, sin_variante)` (la oferta, con
"¿y si esto se diera de baja?"), `catalogo_baja_efecto(insumo, variante)` (por paquete activo con publicada: `sale`, `colores`,
`piezas`, `opciones`; la usan el aviso y la cascada), `catalogo_version_frena` (la lista), `catalogo_version_formulas`, `_alcance`,
`_referencias`, `_circular`, `_insumos` (sus pasos), `catalogo_version_tomar` (permiso, `FOR UPDATE` y estado), `_registrar` (estado
e historia), `_bloquear` (`FOR SHARE` de insumos, variantes, categoría y colores), `_exigir` (bloquea y frena).

**Triggers.** `catalogo_insumos_baja` y `catalogo_variantes_baja`, BEFORE UPDATE OF `activo`, DEFINER (`catalogo_baja_cascada`): baja
los paquetes activos que dejan de armarse y guarda la causa. `catalogo_paquetes_reactivar`, BEFORE UPDATE OF `activo`, DEFINER: con
categoría de baja CA008; sin armarse en ningún color CA020, que dice qué falta; si no, borra la causa. Sin publicada no revisa nada.

**Errores:** CA019 hay algo que frena: el mensaje trae la lista, una línea por cada cosa · CA020 no se puede reactivar · CA021
devolver sin motivo · CA022 la versión no está en revisión · CA023 descartar sin publicada. Enviar o descartar fuera de borrador da
CA012, y sin permiso, 42501.

## El precio

Decisiones: `decisiones/catalogo/precio.md` → *El precio en la base*. Parte de `catalogo_despiece` y no guarda nada. Las públicas son
DEFINER, porque leen lo que quien llama no puede abrir. Sin permiso, 42501. `catalogo_precio` y `catalogo_precio_minimos` piden
`catalogo_aprobar` hasta que la ficha de Presupuestos nombre su permiso.

| función | qué hace |
|---|---|
| `catalogo_precio(paquete, entrada = '{}', opcionales = '{}', moneda = NULL) → jsonb` | lo que se vende hoy: la publicada de un paquete activo, a la fecha de hoy, si lo elegido se ofrece. `{precio, mensaje, mensajes}`, sin los `errores` del cálculo |
| `catalogo_precio_detalle(version, entrada = '{}', opcionales = '{}', moneda = NULL, en = now()) → jsonb` | cualquier versión a cualquier fecha, sin mirar la oferta |
| `catalogo_precio_minimos(items, moneda = NULL)` | `porcentaje_id`, `nombre`, `monto`: un renglón por mínimo que no se alcanzó, con los pasos siguientes aplicados y redondeado. Ítems: `[{paquete_id, cantidad, entrada?, opcionales?}]`. Sin cantidad o sin paquete: CA017 |
| `catalogo_precios_referencia(moneda = NULL, desde = hace 30 días, hasta = now())` | `paquete_id`, `version_id`, `numero`, `nombre`, `caso_id`, `caso`, `precio_desde`, `precio_hasta`, `cambio` (%), `sin_precio_desde`, `sin_precio_hasta`: lo que más cambió primero |

**Sin EXECUTE para nadie:** `catalogo_precio_calcular(version, entrada, opcionales, moneda, en)` (la cuenta: de acá sale todo),
`catalogo_precio_venta(paquete, entrada, opcionales, moneda)` (lo que se vende hoy), `catalogo_precio_convertir` (NULL sin tipo de
cambio) y `catalogo_precio_redondear(monto, moneda)` (ARS a entero, el resto a 2 decimales).

**Lo que lee el vendedor en `mensaje`:** `No se puede calcular con estas medidas` · `Este paquete no tiene precio a la fecha del presupuesto`
· `Este paquete no está a la venta` · `Este paquete no se ofrece en este color` · `Ya no se ofrece: DVH, Mosquitero` ·
`Un servicio opcional elegido ya no está`. Con un bloqueo `mensaje` es NULL, y el porqué está en `mensajes`.

**El resultado del detalle** es el del despiece (*El despiece*), con esto de más:

| clave | qué es |
|---|---|
| `moneda`, `fecha` | en qué moneda y a qué fecha se calculó |
| `filas` | además: `costo`, `costo_moneda` y `costo_desde`, como se cargó; `importe`, en la moneda pedida. Sin costo o sin tipo de cambio, falta lo que no se pudo |
| `piezas` | además: `subtotal`, la suma de sus filas |
| `costo_despiece`, `subtotal` | el costo de todas las filas, y ese más los del paso 1. NULL si no se pudieron calcular los servicios |
| `servicios` | `[{porcentaje_id, nombre, porcentaje, paso, opcional, aplica, desde, categorias (nombres), base, monto, minimo?, minimo_moneda?, minimo_por?, minimo_convertido?}]`, por paso y nombre. Un opcional sin elegir o sin nada de sus categorías: `aplica` false, base y monto 0. Vacío si falta un costo o no se pudo calcular |
| `sin_precio` | text[]: por qué no da número, para quien tiene `catalogo_aprobar`. Los errores del cálculo, los bloqueos, lo que no tiene costo o tipo de cambio a esa fecha, y un opcional que no está. Vacío si hay precio |
| `precio_exacto`, `precio` | sin redondear y redondeado. NULL si y solo si `sin_precio` trae algo |

## Los avisos

Decisiones: `decisiones/catalogo/versiones.md` → *Los avisos en la base*. Quién recibe cada uno y qué dice:
`db_schema/notificaciones.md` → *Catálogo*.

**`catalogo_bajas`:** una fila por cada baja que sacó algo de la venta. `id`, `insumo_id` FK, `variante_id` FK nullable (NULL: el insumo
o servicio fijo entero), `salen` uuid[] (los paquetes que sacó), `dejan` text[] (`Puerta balcón (Negro, DVH)`), `creado_por` FK nullable,
`activo`, `created_at`, `updated_at`. RLS sin policy ni GRANT: la escribe `catalogo_baja_cascada` y la lee `catalogo_avisos`.

| función | seguridad | qué hace |
|---|---|---|
| `catalogo_avisos()` | DEFINER, EXECUTE para `authenticated` | `notificacion_id`, `etiqueta`, `motivo`, `destino`, `destino_id` de los avisos propios del catálogo que todavía valen. La usa `notificaciones_listar` |
| `catalogo_porcentaje_cambio(valor) → text` | INVOKER, sin EXECUTE | qué cambió contra el valor anterior: `5 % → 6 % · Suma Herrajes`, `Alta: 5 %`, `De baja` |

**Triggers**, DEFINER y sin EXECUTE: `catalogo_variantes_avisar_alta` y `_vuelve`, `catalogo_categorias_avisar`,
`catalogo_porcentajes_valores_avisar`, `catalogo_versiones_historia_avisar`. La baja avisa desde `catalogo_baja_cascada` (*El ciclo*).

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
