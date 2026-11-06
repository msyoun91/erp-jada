# Módulo presupuestos

Ficha y decisiones: `decisiones/presupuestos.md`. Tests: `sql/tests/presupuestos_registros.sql` (tramo 1),
`sql/tests/presupuestos_renglones.sql` (2a), `sql/tests/presupuestos_opcionales.sql` (2b), `sql/tests/presupuestos_ciclo.sql` (3a),
`sql/tests/presupuestos_autorizaciones.sql` (3b).

**Estado:** tramo 1 — `sql/185` (permisos, configuración, presupuesto, versiones, secciones, ente), aplicado el 2026-11-06.
Tramo 2a — `sql/186` (renglones de Catálogo y a mano, descuento, totales; el precio de Catálogo para quien arma), aplicado el
2026-11-06. Tramo 2b — `sql/187` (lo que suma cada opcional, cómo se ve, el renglón aparte y los mínimos), aplicado el
2026-11-06. Tramo 3a — `sql/188` (copiar una versión, mantener o actualizar, lo que frena publicar, publicar y quitar una
variante), aplicado el 2026-11-06. Tramo 3b — `sql/189` (pedir, autorizar, devolver y retirar; lo que frena separado de lo que
pide autorización; la lectura de Técnica), aplicado el 2026-11-06. Siguen: aprobar, rechazar y la obra (4), avisos (5).

## Ver y armar: decide la obra

| | quién | función |
|---|---|---|
| **Ve** | con `presupuestos_ver`: quien ve la obra (`obras_puede_ver_obra_de`), o `presupuestos_administrar`. No mira `activo` del presupuesto: un desactivado lo sigue viendo quien ve la obra | `presupuestos_ve_de(obra, usuario)` |
| **Arma** (crea, edita el borrador, desactiva) | con `presupuestos_ver`: `presupuestos_armar` y trabaja la obra (`obras_trabaja_de`), o `presupuestos_administrar` | `presupuestos_arma_de(obra, usuario)` |
| **Autoriza** | lo del jefe: con `presupuestos_ver`, `presupuestos_autorizar` y la obra a cargo (`obras_a_cargo_de`); lo de Técnica: `presupuestos_revision` y `presupuestos_autorizar_tecnica`; los dos, con `presupuestos_ver`, `presupuestos_administrar` | `presupuestos_puede_autorizar(tipo, obra)` |

Las dos `_de` son DEFINER STABLE sin GRANT. Envoltorios con `auth.uid()`, DEFINER con GRANT `authenticated`, para las
policies: `presupuestos_ve(obra)` y `presupuestos_arma(obra)`. `presupuestos_puede_autorizar` es DEFINER con GRANT, con
`auth.uid()`. Técnica no tiene `presupuestos_ver`: lee por `presupuestos_revision_*`, sin precios (*Funciones*).

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
| descuento | numeric(5,2) | 0–100, default 0: % sobre el total de cada moneda (`sql/186`). Por encima del tope, pide autorización |
| estado | enum `estado_version_presupuesto` (`borrador`\|`en_revision`\|`publicado`\|`obsoleto`) | default `borrador`. Sin GRANT: lo cambian pedir, retirar, devolver, publicar y quitar |
| origen_id | uuid FK → presupuestos_versiones, nullable | la versión de la que se copió (`presupuestos_version_copiar`): otra activa del mismo presupuesto (23503). No cambia |
| vence | date, nullable | lo pone publicar: hoy (Buenos Aires) + el plazo vigente. Sin GRANT |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | false = descartada. Solo un borrador (PR005), nunca la única activa del presupuesto (PR006); no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

Únicos parciales `WHERE activo`: una abierta (`borrador`, `en_revision`) y una `publicado` por (`presupuesto_id`, `variante`).

Trigger `presupuestos_versiones_validar` (BEFORE INSERT OR UPDATE): al crear, toma el presupuesto `FOR UPDATE`, exige que esté
activo y en `borrador` o `publicado` (PR003), valida el origen, pone el número y valida la variante. Al editar, nombre, IVA y
descuento solo en `borrador` (PR005).

RLS: SELECT si se ve el presupuesto; INSERT y UPDATE si se arma y el presupuesto está activo. GRANT: SELECT; INSERT (`id,
presupuesto_id, variante, variante_nombre, iva_discriminado, descuento, origen_id`); UPDATE (`variante_nombre, iva_discriminado,
descuento, activo`).

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
| origen_id | uuid FK → presupuestos_renglones, nullable | el renglón del que se copió, de la versión de origen (23503). Se inserta, no cambia. El mínimo lo toma el trigger: el de su servicio en la versión de origen |
| mantener | boolean | default false. Recalcular con la versión y la fecha del origen (`sql/188`); a hoy si no. Solo de Catálogo o mínimo con origen (PR013); de Catálogo, con el mismo paquete que su origen (PR013) |
| activo | boolean | no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

CHECK `presupuestos_renglones_forma` (compara `tipo::text`): de Catálogo, paquete, versión, condiciones, entrada, opcionales, mensajes
y líneas, sin descripción; a mano, descripción y precio, sin nada de Catálogo; mínimo, servicio, descripción, precio y condiciones,
sin nada de Catálogo. CHECK `presupuestos_renglones_mantener`: mantener pide origen y no es a mano.

Trigger `presupuestos_renglones_validar` (BEFORE INSERT OR UPDATE, INVOKER): versión activa en `borrador` (PR005, `FOR SHARE`),
sección de esa versión (23503) y activa (PR008). A mano: toma la moneda de la sección al crearse y no cambia de moneda (PR009).
De Catálogo: se calcula a hoy con `catalogo_precio_lineas` al crearlo, al cambiar `paquete_id`, `entrada` u `opcionales`, cuando la
moneda de su sección ya no es la suya y cuando a un opcional aparte le falta la línea en la moneda de su renglón aparte; si no, el
precio queda como estaba aunque se escriba. Las monedas que pide son la de su sección y las de los renglones aparte de la versión.
Un paquete que no está a la venta no entra ni se elige (PR010); uno que estaba y salió queda con su versión, sin precio y con el
mensaje. Mínimo: lo crea y lo saca la base; directo, quien arma no lo crea ni lo saca (PR012, `pg_trigger_depth() = 1`), pero lo
mueve de sección. Cada vez que se toca se recalcula con `presupuestos_minimos_calcular` en la moneda de su sección, con cantidad 1;
el de un opcional aparte vuelve a la sección de su renglón aparte.

Desde `sql/188`: el precio de Catálogo sale de `presupuestos_precio_lineas`, a hoy o, con `mantener`, con la versión y la fecha
del origen (`condiciones_en` queda la del origen). También recalcula al cambiar `mantener` y al escribirlo aunque no cambie:
`presupuestos_renglones_a_hoy` (BEFORE UPDATE OF mantener, corre antes por orden alfabético) marca `condiciones_en` NULL, y así
"actualizar" trae a hoy una ventana que ya estaba a hoy. Uno copiado cuyo paquete salió de la venta entra sin precio, con la
versión de su origen (sin origen, PR010). Un mínimo nuevo toma el origen de su servicio y arranca en la sección de igual nombre
que la de su origen; mantenido, toma el umbral a la fecha del origen.

`presupuestos_renglones_minimos` (AFTER INSERT y AFTER UPDATE, por sentencia, con la tabla de transición): por cada versión con
renglones de Catálogo cambiados, pide los mínimos en la moneda principal; el que hace falta y tiene renglón se toca, el que no
tiene se crea en la sección que más aporta, y el que ya no hace falta se desactiva.

RLS: como las secciones. GRANT: SELECT; INSERT (`id, version_id, seccion_id, tipo, designacion, ubicacion, cantidad, orden,
paquete_id, entrada, opcionales, descripcion, precio, porcentaje_id, origen_id, mantener`); UPDATE (`seccion_id, designacion,
ubicacion, cantidad, orden, paquete_id, entrada, opcionales, descripcion, precio, mantener, activo`). `porcentaje_id` se inserta
porque el trigger de mínimos crea el renglón como quien arma. "Mantener todas": UPDATE `mantener = true` por `version_id` con
`origen_id IS NOT NULL AND tipo <> 'mano'`; "todas a hoy", `mantener = false`.

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

## presupuestos_autorizaciones

Un pedido de autorización y cómo se resolvió (`sql/189`). Del jefe, uno por versión; de Técnica, uno por renglón. Pedir de nuevo es
otra fila: el historial.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| version_id | uuid FK → presupuestos_versiones | la versión en que se pidió |
| tipo | enum `tipo_autorizacion_presupuesto` (`comercial`\|`tecnica`) | del jefe comercial o de Técnica |
| renglon_id | uuid FK → presupuestos_renglones, nullable | de Técnica sí, del jefe no (CHECK `_forma`) |
| pedido | jsonb | qué se pidió, como lo dio `presupuestos_version_pedido` (sin `estado`), con su `texto`. Del jefe: `renglones` (cada mantenido con `precio`, `hoy`, `diferencia`, `condiciones_en`), `diferencia` por moneda, `descuento` (NULL si no pasa el tope), `tope`. De Técnica: `etiqueta`, `paquete_id`, `catalogo_version_id`, `entrada` y `motivos` (las alertas y lo que ya no se ofrece), sin precios |
| estado | enum `estado_autorizacion_presupuesto` (`pendiente`\|`autorizada`\|`devuelta`\|`retirada`) | default `pendiente` |
| pedido_por | uuid FK → usuarios | default `auth.uid()` |
| resuelto_por / resuelto_en | uuid FK → usuarios / timestamptz | los dos, y solo, fuera de `pendiente` (CHECK `_resuelta`). Quien pidió, si ya podía autorizar |
| motivo | text, nullable | 1–500; solo y siempre en `devuelta` (CHECK `_motivo`) |
| activo | boolean | false: una autorización del jefe que dejó de valer porque la versión volvió a borrador |
| created_at / updated_at | timestamptz | `created_at` es cuándo se pidió |

Lo del jefe vale en la vuelta en que se dio: al volver a borrador (retirar o devolver), lo pendiente queda `retirada` y lo
`autorizada` del jefe, `activo = false`. Lo de Técnica vale en cualquier versión del presupuesto para una ventana igual:
mismo paquete, versión y `entrada`, por los mismos motivos o menos (`presupuestos_tecnica_cubre`).

RLS: SELECT si se ve la versión (quien ve el presupuesto, con los montos). Técnica no la lee. GRANT: SELECT. Se escribe solo por
las funciones del ciclo (DEFINER).

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
- `presupuestos_minimos_calcular(version, moneda, mantener = NULL) → (porcentaje_id, nombre, monto, seccion_id)` — DEFINER con
  GRANT; sin armar esa obra, 42501. Los mínimos por presupuesto desde los renglones de Catálogo activos con precio, cada uno con
  su versión y su fecha guardadas (`catalogo_precio_minimos_items`). El umbral, a hoy o, para los servicios de `mantener` (NULL:
  los mínimos guardados con `mantener`), a la fecha del mínimo de origen. `seccion_id`: la sección que más aporta a ese mínimo
  (empate: orden y nombre). Quien llama no elige la fecha ni ve lo que aporta cada ventana.
- `presupuestos_precio_lineas(version, origen, paquete, entrada, opcionales, monedas) → jsonb` — DEFINER con GRANT; sin armar,
  42501. `{precio, mensaje, mensajes, version_id, condiciones_en, lineas}`, listo para guardar: sin origen, a hoy; con origen
  (un renglón de Catálogo de la versión de la que se copió, con el mismo paquete; si no, PR013), con su versión y su fecha.
- `presupuestos_renglon_monedas(version, moneda) → moneda[]` — INVOKER: la de la sección y las de los renglones aparte en otra.
- `presupuestos_renglon_etiqueta(designacion, ubicacion, descripcion) → text` — "V4 · Lavadero".
- `presupuestos_version_copiar(desde, variante_nueva = false) → uuid` — INVOKER: la RLS y los triggers deciden. Corregir o
  actualizar (la misma variante) o sumar variante (la siguiente, sin nombre): copia IVA, descuento, nombre de la variante (si es
  la misma), secciones, cómo se ve cada opcional, ventanas y renglones a mano activos, con `origen_id`. Las ventanas arrancan a hoy;
  los mínimos los pone la base. Otra abierta de esa variante: 23505.
- `presupuestos_version_revisar(version) → text[]` — INVOKER; sin armar, 42501. Lo que frena pedir y publicar, una línea por cosa:
  sin configuración, sin renglones, variante sin nombre habiendo otra publicada, ventanas sin precio (con el porqué), lo que está a
  hoy y cambió desde que se calculó (precio, versión o líneas; el mínimo, su monto) y mínimos que faltan. Lo que pide autorización
  ya no está acá (`sql/189`): lo da `presupuestos_version_pedido`.
- `presupuestos_version_pedido(version) → jsonb` — DEFINER; sin armar, 42501. Lo que pide autorización y en qué está cada cosa
  (`estado`: NULL si falta pedirla, `pendiente` o `autorizada`), con su `texto`. `{comercial, tecnica}`: del jefe, si hay renglones
  mantenidos (ventanas y mínimos, aunque no resignen nada) o descuento sobre el tope (sin configuración, 0); cada mantenido con
  `hoy` (a hoy; NULL si ya no tiene precio; el mínimo, con el umbral de hoy) y `diferencia` = redondear(hoy × cantidad) −
  redondear(precio × cantidad), y la suma por moneda. De Técnica, por ventana con precio: sus alertas y, si está mantenida, lo
  elegido que ya no se ofrece en su versión (`catalogo_precio_fuera`). La del jefe cuenta como autorizada con una fila
  `autorizada` activa de la versión (y, si hoy pasa el tope, que haya autorizado descuento); la de Técnica, con cualquier fila
  `autorizada` del presupuesto que la cubra.
- `presupuestos_version_pedir(version) → estado_version_presupuesto` — DEFINER; sin armar, 42501. Presupuesto activo en
  `borrador` o `publicado` (PR003), versión en `borrador` (PR005), sin nada en `revisar` (PR014). Crea una fila por lo que falta
  pedir: `autorizada` (resuelta por quien pide) si quien pide ya puede autorizarla, `pendiente` si no. La versión pasa a
  `en_revision`; si no queda nada pendiente, publica en el mismo paso. Devuelve el estado en que quedó.
- `presupuestos_pedido_resolver(pedido, autoriza, motivo = NULL)` — DEFINER; sin `presupuestos_puede_autorizar` para ese tipo y esa
  obra, 42501. Solo un pedido `pendiente` (PR018, que dice quién lo resolvió o retiró, y cuándo). Autorizar: también los pendientes
  de Técnica de la versión que esa autorización cubre (las ventanas iguales). La versión sigue `en_revision`: publica quien arma.
  Devolver: pide motivo (PR019), y la versión vuelve a borrador (`presupuestos_version_a_borrador`).
- `presupuestos_version_retirar(version)` — DEFINER; sin armar, 42501. Versión activa en `en_revision` (PR017): vuelve a
  borrador. No avisa.
- `presupuestos_version_a_borrador(version)` — sin GRANT. Lo pendiente queda `retirada` (por quien actúa), lo autorizado por el
  jefe `activo = false` y la versión `borrador`.
- `presupuestos_tecnica_cubre(autorizado, pedido) → boolean` — IMMUTABLE, sin GRANT. Mismo `paquete_id`, `catalogo_version_id` y
  `entrada`, y los `motivos` del autorizado contienen los del pedido.
- `presupuestos_version_publicar(version)` — DEFINER; sin armar, 42501. Presupuesto activo en `borrador` o `publicado` (PR003),
  versión en `borrador` o `en_revision` (PR005). Frena (PR014, con las líneas) lo de `revisar`, lo que pide autorización sin
  pedirla ("Pide …") y los pedidos pendientes ("Espera la …"). Guarda `vence`, la publicada de esa variante pasa a `obsoleto`, la
  versión a `publicado` y el presupuesto a `publicado`.
- `presupuestos_revision_pendientes()` — DEFINER; con `presupuestos_revision`, o `presupuestos_ver` y `presupuestos_administrar`;
  si no, 42501. Los pedidos de Técnica pendientes: `pedido_id`, `version_id`, `codigo`, `etiqueta`, `motivos`, `pedido_por`,
  `pedido_en`, los más viejos primero.
- `presupuestos_revision_version(version)` — DEFINER; con `presupuestos_revision` si el presupuesto tiene algún pedido de Técnica,
  o `presupuestos_ver` y `presupuestos_administrar`; si no, 42501. Por renglón de Catálogo o a mano: `codigo`, `tipo`,
  `designacion`, `ubicacion`, `cantidad`, `paquete_id`, `paquete` (nombre de su versión), `catalogo_version_id`, `catalogo_version`
  (número), `entrada`, `mensajes`, `descripcion`, y el último pedido de Técnica del renglón (`pedido_id`, `pedido_estado`,
  `motivos`; el pendiente primero). Sin precios, montos, obra ni nombre.
- `presupuestos_variante_quitar(version)` — DEFINER; sin armar, 42501. Presupuesto `publicado` (PR003), versión `publicado`
  (PR015), y queda otra publicada (PR016): pasa a `obsoleto`.
- `presupuestos_clave(pieza, porcentaje) → text` — IMMUTABLE: la clave de un opcional, en `presupuestos_opcionales.clave` y en
  `lineas`.

Catálogo, para quien arma (`db_schema/catalogo.md` → *El precio*): `catalogo_precio` (trae `version_id`), `catalogo_precio_lineas`,
`catalogo_venta()` y `catalogo_venta_formulario(paquete)`. Sin GRANT, desde las de arriba: `catalogo_precio_fuera(version, r)`.

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
sección tiene renglones (o el renglón aparte de un opcional) · PR012 el mínimo lo pone y lo saca la base · PR013 solo se
mantiene lo copiado, con su paquete · PR014 algo frena publicar · PR015 solo se quita una variante publicada · PR016 la última
variante no se quita · PR017 la versión no está en revisión · PR018 el pedido ya no está pendiente · PR019 devolver pide motivo.
