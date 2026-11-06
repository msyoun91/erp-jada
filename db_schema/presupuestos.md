# Módulo presupuestos

Ficha y decisiones: `decisiones/presupuestos.md`. Tests: `sql/tests/presupuestos_registros.sql` (tramo 1),
`sql/tests/presupuestos_renglones.sql` (2a), `sql/tests/presupuestos_opcionales.sql` (2b).

**Estado:** tramo 1 — `sql/185` (permisos, configuración, presupuesto, versiones, secciones, ente), aplicado el 2026-11-06.
Tramo 2a — `sql/186` (renglones de Catálogo y a mano, descuento, totales; el precio de Catálogo para quien arma), aplicado el
2026-11-06. Tramo 2b — `sql/187` (lo que suma cada opcional, cómo se ve, el renglón aparte y los mínimos), aplicado el
2026-11-06. Siguen: ciclo de la versión (3), aprobar, rechazar y la obra (4), avisos (5).

## Ver y armar: decide la obra

| | quién | función |
|---|---|---|
| **Ve** | con `presupuestos_ver`: quien ve la obra (`obras_puede_ver_obra_de`), o `presupuestos_administrar`. No mira `activo` del presupuesto: un desactivado lo sigue viendo quien ve la obra | `presupuestos_ve_de(obra, usuario)` |
| **Arma** (crea, edita el borrador, desactiva) | con `presupuestos_ver`: `presupuestos_armar` y trabaja la obra (`obras_trabaja_de`), o `presupuestos_administrar` | `presupuestos_arma_de(obra, usuario)` |

Las dos `_de` son DEFINER STABLE sin GRANT. Envoltorios con `auth.uid()`, DEFINER con GRANT `authenticated`, para las
policies: `presupuestos_ve(obra)` y `presupuestos_arma(obra)`. Técnica no tiene `presupuestos_ver`: lee por una función sin
precios (tramo 3).

## presupuestos — ente `presupuesto`

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| numero | integer | `presupuestos_numero_seq`, correlativo de toda la empresa. Nadie lo escribe. Unique parcial `WHERE activo` |
| codigo | text, generada | `P-0142`: el número con al menos 4 cifras |
| nombre | text | 1–200, lo escribe el vendedor |
| obra_id | uuid FK → obras | obligatoria, no cambia |
| estado | enum `estado_presupuesto` (`borrador`\|`publicado`\|`aprobado`\|`rechazado`) | default `borrador`. Sin GRANT: lo cambian las funciones del ciclo |
| creado_por | uuid FK → usuarios | default `auth.uid()`. Dueño para el disparo de plantillas |
| activo | boolean | desactivar solo en `borrador` (PR001); no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

RLS: SELECT `presupuestos_ve(obra_id)`; INSERT `presupuestos_arma(obra_id)`; UPDATE USING `activo AND presupuestos_arma(obra_id)`.
GRANT: SELECT; INSERT (`id, nombre, obra_id`); UPDATE (`nombre, activo`); USAGE de la secuencia.

## presupuestos_versiones

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| presupuesto_id | uuid FK → presupuestos | no cambia |
| numero | integer | lo pone el trigger: el siguiente del presupuesto, contando las descartadas. UNIQUE (`presupuesto_id`, `numero`) |
| variante | integer | ≥ 1; una que ya existe o la siguiente (PR004). Corregir o actualizar es otra versión de la misma variante |
| variante_nombre | text, nullable | 1–100. "Aluminio" |
| iva_discriminado | boolean | default true; false = incluido |
| descuento | numeric(5,2) | 0–100, default 0: % sobre el total de cada moneda (`sql/186`). Si pide autorización, tramo 3 |
| estado | enum `estado_version_presupuesto` (`borrador`\|`en_revision`\|`publicado`\|`obsoleto`) | default `borrador`. Sin GRANT |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | false = descartada. Solo un borrador (PR005), nunca la única activa del presupuesto (PR006); no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

Únicos parciales `WHERE activo`: una abierta (`borrador`, `en_revision`) y una `publicado` por (`presupuesto_id`, `variante`).

Trigger `presupuestos_versiones_validar` (BEFORE INSERT OR UPDATE): al crear, toma el presupuesto `FOR UPDATE`, exige que esté
activo y en `borrador` o `publicado` (PR003), pone el número y valida la variante. Al editar, nombre, IVA y descuento solo en
`borrador` (PR005).

RLS: SELECT si se ve el presupuesto; INSERT y UPDATE si se arma y el presupuesto está activo. GRANT: SELECT; INSERT (`id,
presupuesto_id, variante, variante_nombre, iva_discriminado, descuento`); UPDATE (`variante_nombre, iva_discriminado, descuento,
activo`).

## presupuestos_secciones

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| version_id | uuid FK → presupuestos_versiones | no cambia |
| nombre | text | 1–100. Unique parcial (`version_id`, `lower(btrim(nombre))`) `WHERE activo` |
| moneda | enum `moneda` | |
| alicuota | numeric(3,1) | 0, 10,5 o 21 |
| orden | integer | default 0 |
| activo | boolean | no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

Trigger `presupuestos_secciones_validar`: solo en una versión activa en `borrador` (PR005), con `FOR SHARE` sobre la versión;
con renglones activos o con el renglón aparte de un opcional no se saca (PR011). `presupuestos_secciones_moneda` (AFTER UPDATE
OF moneda, si cambió): toca sus renglones activos y los de Catálogo de la versión (por si tienen un opcional aparte ahí), y el
trigger de renglones recalcula los que lo necesitan; uno a mano en la sección frena el cambio (PR009).
"Todas al 10,5" o "todas en pesos" es un UPDATE por `version_id`. Unique (`id, version_id`), para la FK compuesta de los
renglones. RLS: como las versiones, por la versión y su presupuesto.
GRANT: SELECT; INSERT (`id, version_id, nombre, moneda, alicuota, orden`); UPDATE (`nombre, moneda, alicuota, orden, activo`).

## presupuestos_renglones

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| version_id | uuid FK → presupuestos_versiones | no cambia |
| seccion_id | uuid | FK compuesta (`seccion_id, version_id`) → secciones: solo de la misma versión (23503) |
| tipo | enum `tipo_renglon_presupuesto` (`catalogo`\|`mano`\|`minimo`) | no cambia. El renglón aparte no se guarda: sale de las líneas (`presupuestos_version_importes`) |
| designacion | text, nullable | 1–30. "V4" |
| ubicacion | text, nullable | 1–100. "Lavadero" |
| cantidad | numeric | > 0, default 1. El precio es por unidad |
| orden | integer | default 0 |
| paquete_id | uuid FK → catalogo_paquetes | de Catálogo |
| catalogo_version_id | uuid FK → catalogo_versiones | de Catálogo. La pone el trigger: la publicada con que se calculó |
| condiciones_en | timestamptz | de Catálogo. La pone el trigger: cuándo se calculó |
| entrada | jsonb | de Catálogo: lo cargado (`db_schema/catalogo.md` → *La entrada*) |
| opcionales | uuid[] | de Catálogo: los servicios en % opcionales elegidos |
| mensajes | jsonb | de Catálogo. Lo pone el trigger: alertas y bloqueos del paquete, como los da `catalogo_precio` |
| lineas | jsonb | de Catálogo. Lo pone el trigger: lo que suma cada opcional elegido, `[{clave, nombre, moneda, monto}]`, en el orden del cálculo, en la moneda del renglón y, si va aparte en otra moneda, también en esa. `[]` sin opcionales o sin precio |
| descripcion | text | a mano, 1–500. Mínimo: el nombre del servicio, lo pone el trigger |
| porcentaje_id | uuid FK → catalogo_porcentajes | mínimo: su servicio. Unique parcial (`version_id`, `porcentaje_id`) `WHERE activo AND porcentaje_id IS NOT NULL` |
| moneda | enum `moneda` | la del precio escrito. La pone el trigger con la de la sección |
| precio | numeric, nullable | ≥ 0, por unidad, redondeado. A mano lo escribe quien arma; de Catálogo y mínimo lo pone el trigger; de Catálogo, NULL si no da número |
| mensaje | text, nullable | de Catálogo. Lo pone el trigger: por qué no hay precio, lo que lee el vendedor |
| activo | boolean | no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

CHECK `presupuestos_renglones_forma` (compara `tipo::text`): de Catálogo, paquete, versión, condiciones, entrada, opcionales, mensajes
y líneas, sin descripción; a mano, descripción y precio, sin nada de Catálogo; mínimo, servicio, descripción, precio y condiciones,
sin nada de Catálogo.

Trigger `presupuestos_renglones_validar` (BEFORE INSERT OR UPDATE, INVOKER): versión activa en `borrador` (PR005, `FOR SHARE`),
sección de esa versión (23503) y activa (PR008). A mano: toma la moneda de la sección al crearse y no cambia de moneda (PR009).
De Catálogo: se calcula a hoy con `catalogo_precio_lineas` al crearlo, al cambiar `paquete_id`, `entrada` u `opcionales`, cuando la
moneda de su sección ya no es la suya y cuando a un opcional aparte le falta la línea en la moneda de su renglón aparte; si no, el
precio queda como estaba aunque se escriba. Las monedas que pide son la de su sección y las de los renglones aparte de la versión.
Un paquete que no está a la venta no entra ni se elige (PR010); uno que estaba y salió queda con su versión, sin precio y con el
mensaje. Mínimo: lo crea y lo saca la base; directo, quien arma no lo crea ni lo saca (PR012, `pg_trigger_depth() = 1`), pero lo
mueve de sección. Cada vez que se toca se recalcula con `presupuestos_minimos_calcular` en la moneda de su sección, con cantidad 1;
el de un opcional aparte vuelve a la sección de su renglón aparte.

`presupuestos_renglones_minimos` (AFTER INSERT y AFTER UPDATE, por sentencia, con la tabla de transición): por cada versión con
renglones de Catálogo cambiados, pide los mínimos en la moneda principal; el que hace falta y tiene renglón se toca, el que no
tiene se crea en la sección que más aporta, y el que ya no hace falta se desactiva.

RLS: como las secciones. GRANT: SELECT; INSERT (`id, version_id, seccion_id, tipo, designacion, ubicacion, cantidad, orden,
paquete_id, entrada, opcionales, descripcion, precio, porcentaje_id`); UPDATE (`seccion_id, designacion, ubicacion, cantidad,
orden, paquete_id, entrada, opcionales, descripcion, precio, activo`). `porcentaje_id` se inserta porque el trigger de mínimos
crea el renglón como quien arma.

## presupuestos_opcionales

Cómo se ve cada opcional en la versión. Sin fila, va en el precio; volver al precio es desactivar la fila.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| version_id | uuid FK → presupuestos_versiones | |
| pieza | text, nullable | 1–100: la pieza opcional, por nombre en todas las ventanas |
| porcentaje_id | uuid FK → catalogo_porcentajes, nullable | el servicio en % opcional. CHECK: pieza o servicio, uno |
| clave | text, generada | `presupuestos_clave(pieza, porcentaje_id)`: `pieza:mosquitero` o `servicio:<id>`; la de `lineas`. Unique parcial (`version_id`, `clave`) `WHERE activo` |
| forma | enum `forma_opcional_presupuesto` (`debajo`\|`aparte`) | |
| seccion_id | uuid, nullable | FK compuesta (`seccion_id, version_id`) → secciones. CHECK: con `aparte` sí, con `debajo` no |
| activo | boolean | no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

Trigger `presupuestos_opcionales_validar`: solo en una versión activa en `borrador` (PR005), aparte en una sección activa (PR008).
`presupuestos_opcionales_renglones` (AFTER INSERT OR UPDATE): toca las ventanas con ese opcional y su mínimo, y el trigger de
renglones decide si recalcular. RLS: como las secciones. GRANT: SELECT; INSERT (`id, version_id, pieza, porcentaje_id, forma,
seccion_id`); UPDATE (`forma, seccion_id, activo`).

## presupuestos_configuracion

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tope_descuento | numeric(5,2) | 0–100: hasta acá, el descuento no pide autorización |
| plazo_dias | integer | 1–365: el vencimiento que se guarda al publicar |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | unique parcial `(activo) WHERE activo`: una vigente; las demás son el historial. No vuelve (PR002) |
| created_at / updated_at | timestamptz | |

`presupuestos_configurar(tope, plazo) → uuid` (INVOKER): desactiva la vigente y crea otra; sin la vista
`presupuestos_configuracion`, 42501. Arranca sin fila: hasta que gerencia configure, no hay tope ni plazo. RLS: SELECT con
`presupuestos_ver` o `presupuestos_configuracion`; INSERT y UPDATE con `presupuestos_configuracion`. GRANT: SELECT; INSERT
(`id, tope_descuento, plazo_dias`); UPDATE (`activo`).

## Funciones

- `presupuestos_alta(obra, nombre, moneda, alicuota, seccion = 'General') → uuid` — INVOKER. El presupuesto, su v1 (variante 1)
  y una sección. Sin armar en esa obra, 42501.
- `presupuestos_obra_desactivar` — trigger DEFINER sobre `obras` (BEFORE UPDATE OF activo): la obra con presupuestos activos
  no se desactiva (PR007).
- `presupuestos_version_importes(version) → (renglon_id, seccion_id, moneda, alicuota, clave, nombre, importe)` — INVOKER. Una
  fila por importe que ve el cliente: cada renglón (`clave` NULL) sin sus opcionales aparte, redondear((precio − líneas aparte) ×
  cantidad); y cada opcional aparte de cada ventana, en la sección y la moneda de su renglón aparte, redondear(línea × cantidad).
  El renglón aparte es la suma por `clave`; su mínimo es el renglón de mínimo con ese servicio. `importe` NULL: sin precio, o sin la
  línea en esa moneda.
- `presupuestos_version_totales(version) → (moneda, subtotal, descuento, iva, total, sin_precio)` — INVOKER, la RLS decide. Una
  fila por moneda, sobre `presupuestos_version_importes`. Por alícuota: base = Σ importes, descuento = redondear(base × %), IVA =
  redondear((base − descuento) × alícuota); `iva` es `[{alicuota, monto}]`, la mayor primero. Lo sin precio no suma: `sin_precio`
  lo cuenta. Redondea con `catalogo_precio_redondear` (ARS a entero, el resto a 2 decimales). Con IVA incluido los números son los
  mismos.
- `presupuestos_minimos_calcular(version, moneda) → (porcentaje_id, nombre, monto, seccion_id)` — DEFINER con GRANT; sin armar
  esa obra, 42501. Los mínimos por presupuesto desde los renglones de Catálogo activos con precio, cada uno con su versión y su
  fecha guardadas (`catalogo_precio_minimos_items`). `seccion_id`: la sección que más aporta a ese mínimo (empate: orden y
  nombre). Quien llama no elige la fecha ni ve lo que aporta cada ventana.
- `presupuestos_clave(pieza, porcentaje) → text` — IMMUTABLE: la clave de un opcional, en `presupuestos_opcionales.clave` y en
  `lineas`.

Catálogo, para quien arma (`db_schema/catalogo.md` → *El precio*): `catalogo_precio` (trae `version_id`), `catalogo_precio_lineas`,
`catalogo_venta()` y `catalogo_venta_formulario(paquete)`.

## Permisos (`submodulos`, `modulo = 'presupuestos'`)

| codigo | tipo | vista | delegable |
|---|---|---|---|
| `presupuestos_ver` | vista "Presupuestos" | — | sí |
| `presupuestos_armar` | función "Armar" | `presupuestos_ver` | sí |
| `presupuestos_autorizar` | función "Autorizar" | `presupuestos_ver` | no |
| `presupuestos_administrar` | función "Administrar" | `presupuestos_ver` | no |
| `presupuestos_revision` | vista "Revisión técnica" | — | sí |
| `presupuestos_autorizar_tecnica` | función "Autorizar alertas" | `presupuestos_revision` | no |
| `presupuestos_configuracion` | vista "Configuración" | — | no |

`submodulo_reglas` (requiere): `presupuestos_ver` → `obras_ver`; `presupuestos_administrar` → `obras_administrar`.

## Ente y eventos

Fila `presupuesto` en `entes`: `estados` `estado_presupuesto`, `datos` `{codigo,nombre}`, `roles` `{}`, ruta
`/presupuestos/{id}`, `disparos` `{alta,estado}`, `dueno` `creado_por`. Trigger `emitir_eventos` (AFTER INSERT OR UPDATE OF
activo, estado): `emitir_eventos_registro('presupuesto')`.

Ramas: `presupuestos_etiqueta` (`P-0142 · Nombre`; INVOKER, GRANT), `presupuestos_puede_abrir` (DEFINER, sin GRANT),
`presupuestos_buscar(texto)` (activos por código o nombre, la obra de subtítulo; INVOKER, GRANT). Sin rama en
`trabaja_registro` ni `relacionados_de_registro`: al presupuesto no se le vinculan contactos.

**Errores (clase PR):** PR001 un presupuesto publicado no se desactiva · PR002 lo desactivado no vuelve · PR003 el presupuesto
no admite versiones (aprobado, rechazado o desactivado; quien no es DEFINER recibe 42501 si está desactivado) · PR004 variante
que no sigue · PR005 la versión no está en borrador · PR006 la única versión no se descarta · PR007 la obra tiene presupuestos ·
PR008 la sección fue sacada · PR009 un renglón a mano no cambia de moneda · PR010 el paquete no está a la venta · PR011 la
sección tiene renglones (o el renglón aparte de un opcional) · PR012 el mínimo lo pone y lo saca la base.
