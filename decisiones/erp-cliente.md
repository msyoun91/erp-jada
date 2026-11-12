# Decisiones — erp-cliente (portal)

> **Estado: ficha aprobada (2026-11-11), revisada punto por punto con el usuario. SQL completo (tramos 1a–4, 2026-11-12); página del portal hecha
> (2026-11-12); faltan las pantallas del ERP.** Es la etapa 2 de
> Presupuestos (`decisiones/presupuestos.md` → *Etapas*). Lo que falta, en `BACKLOG.md` → *erp-cliente*.

## Ficha del módulo

```
Módulo: erp-cliente (portal)
Objetivo: que el cliente vea su presupuesto publicado y pruebe opcionales con el precio a la vista, sin
          esperar un PDF nuevo por cada cambio, y que el vendedor sepa si lo miraron. Sin autoridad:
          no calcula, no guarda decisiones, no le envía nada al ERP
Personas             qué ve · qué hace · qué NO ve
├── Invitado       — quien tenga el link, sin cuenta ni identidad (cliente, arquitecto, referente, o a
│                    quien se lo reenvíen) · la versión publicada vigente de cada variante, precio por
│                    ventana, referencias en otras monedas · compara, tilda opcionales por ventana, envía
│                    su elección por WhatsApp o la copia · costos, versiones reemplazadas, otros
│                    presupuestos, catálogo, la obra y sus contactos, que hay recargo de comisión
├── Vendedor       — NO entra como usuario: desde el ERP copia el link, lo anula, abre la vista previa,
│                    lee visitas y aplica la elección recibida (todo en Presupuestos)
├── Jefe comercial, gerencia — NO entran: ven las visitas en el ERP
└── Técnica, administración y el resto — NO usan el portal

Entes: ninguno (sin usuarios, sin dueño, sin compartir)
En la base del portal (proyecto de Supabase propio)
├── link         — uno por presupuesto, creado al publicar la primera versión · al azar, 128 bits · el
│                  portal guarda solo su huella · anular crea otro en el momento y corta al viejo
├── copia        — por versión publicada, cifrada con una llave derivada del link: secciones, renglones,
│                  precios, cada combinación de opcionales ya calculada, piso de cada mínimo, orden de cada
│                  casilla, vencimiento, monedas de referencia, WhatsApp del vendedor · la escribe solo el ERP
└── visita       — link, versión mostrada, dispositivo (identificador al azar del navegador, sin IP),
                   cuándo · dos aperturas a menos de 30 min son una · la vista previa no anota
En la base del ERP (Presupuestos)
├── link, cuándo se copió por primera vez ("Copiar link") y estado de la copia ("al día" / "sin
│   actualizar, muestra la v2")
└── visitas leídas, por versión

Acciones
├── invitado: ver · comparar variantes · tildar opcionales · enviar mi elección (texto + link al ERP con
│             código: versión, casillas, dígito de control)
├── vendedor (ERP, presupuestos_armar): copiar link · anular · ver como cliente (desde que publica) ·
│             aplicar elección desde el link o pegando el mensaje (el ERP recalcula, compara el total,
│             rechaza versión reemplazada, código roto o combinación no ofrecida; arma la corrección)
└── ERP: copiar al publicar, retirar, quitar variante y anular (si falla, reintenta: cada hora, al abrir
         una página, con un botón) · leer visitas en esos mismos momentos

Avisos: al vendedor, la primera visita de cada versión
Eventos: ninguno

Portal
└── Presupuesto (página /p#{link}, sin permiso: el link es la llave) — invitado
ERP — Presupuestos, sin submódulos nuevos
├── ficha: link, estado de la copia, visitas, Ver como cliente, Pegar elección — presupuestos_ver lee,
│          presupuestos_armar actúa
└── lista: columna de visitas y filtro "Sin abrir" (solo los que tuvieron "Copiar link")

Reglas entre permisos: ninguna nueva. Delegables: no aplica
```

## Quién entra

**Entra quien tiene el link, sin cuenta, y no hay un "solo mira" (decisión del usuario, 2026-11-11).** Un link por presupuesto,
no por contacto: Juan lo copia y lo manda por donde quiera, y el mismo link muestra la versión vigente. Se descartaron el link
por contacto (un link reenviado igual no dice quién abre) y el código por mail en cada dispositivo (el usuario no necesita saber
quién abrió, sino cuántas veces y desde cuántos dispositivos). Cierra el pendiente "a qué contacto le llega" de Presupuestos.

**El portal no muestra catálogo (2026-11-11).** Sin cuentas, el invitado ve el presupuesto del link y nada más.

## Sin confirmación

**El cliente no confirma en el portal (decisión del usuario, 2026-11-11).** La confirmación era constancia sin autoridad, y con
ella se van el ente, la lectura de confirmaciones, su aviso y casi todo el problema del link reenviado: sin confirmar, reenviarlo
solo muestra el precio, como reenviar el PDF.

**"Enviar mi elección" arma un mensaje con un link al ERP que lleva la elección en un código (decisión del usuario, 2026-11-11).**
Texto legible para las personas ("Mosquitero: V1, V3, V7 · Colocación: todas · Total US$ 21.400") y al final
`…/presupuestos/eleccion/V3-7K2M-9QX4-B`: versión, casilla por ventana y dígito de control. Juan lo toca, o pega el mensaje en
"Pegar elección", y el ERP muestra lo que va a cambiar antes de aplicar. Reglas: el total nunca sale del mensaje, lo recalcula el
ERP y avisa si un mínimo hace que difiera de lo que vio el cliente; código de versión reemplazada, roto o con una combinación no
ofrecida no aplica; nada se aplica solo. El portal no guarda nada. Pide una función en la base que aplique varias casillas de una
vez, y que la copia lleve el orden de cada casilla. Aceptado: el cliente ve la dirección del ERP.

**Aplicar una elección arma una corrección, con las reglas de siempre (decisión del usuario, 2026-11-11).** v3 publicada a
US$ 20.000, sube el aluminio, Carlos manda su elección por 21.400: en la v4 Juan actualiza (22.100) o mantiene (21.400, con
autorización de Laura). Se descartó guardar la elección aparte y aprobar la v3 con ella: dos lugares donde mirar qué se vendió, y
una puerta para cerrar a precio viejo sin la autorización de *Precio*. Sin cambios en Catálogo, actualizar es gratis y da lo mismo.

**El WhatsApp de "Enviar mi elección" es el del responsable de la obra (decisión del usuario, 2026-11-12).** Juan arma, se va de
vacaciones y Laura publica la v4: a Carlos le sigue apareciendo el número de Juan, el que ya tiene. Sale de `usuarios.telefono`
del `responsable_id` de la obra; si la obra se transfiere, cambia en la copia siguiente. Se descartó el de quien publicó.

## Visitas

**El portal anota visitas y dispositivos, sin identificar a nadie (decisión del usuario, 2026-11-11).** "Portal — 9 visitas,
4 dispositivos · última ayer 21:40", por versión mostrada. El dispositivo es un identificador al azar guardado en el navegador;
la pantalla dice "dispositivos", no "personas". Lo ve quien abre la ficha; en la lista, columna y filtro "Sin abrir"; un aviso a
Juan la primera visita de cada versión. La visita la anota el navegador, no la carga de la página: si no, la vista previa que
arma WhatsApp al pegar el link contaba como visita.

**"Ver como cliente" no cuenta (2026-11-11).** Abre el portal con una marca y el cartel "Vista previa — no cuenta como visita".
El link común abierto por Juan sí cuenta: no se distingue del cliente.

## Dos bases

**El portal tiene base propia, otro proyecto de Supabase (decisión del usuario, 2026-11-11).** Se ofreció una copia congelada en
la base del ERP con dos funciones abiertas a `anon` (sin desfase, aviso al instante) y el usuario eligió la separación. Costo
aceptado: el código de copia y lectura, y visitas y aviso hasta una hora tarde.

**Publicar no depende del portal (decisión del usuario, 2026-11-11).** Si la copia falla, la versión queda publicada en el ERP, se
reintenta sola (cada hora, al abrir una página, con un botón) y la ficha dice "Portal: sin actualizar, muestra la v2". Vale
también para retirar, quitar variante y anular. Se descartó no publicar si falla: una caída del portal frenaba al ERP.

**Todo lo publicado se copia, con su link ya creado, y lo no enviado es ilegible (decisión del usuario, 2026-11-11).** Cuatro
medidas: link de 128 bits al azar; el navegador nunca habla con la base, solo con el servidor del portal, que busca por link; la
base guarda la huella del link, no el link; y cada copia va cifrada con una llave derivada del link (cifrado de Node, sin librería).
Un presupuesto cuyo link nunca salió del ERP no se lee ni con la base entera del portal. La copia lleva solo lo que ve el cliente.
"Sin abrir" cuenta los que tuvieron "Copiar link", que el ERP anota la primera vez. Se descartó copiar recién al pedir el link.

**El link va después del `#` y descifra el navegador: `/p#{link}` (decisión del usuario, 2026-11-12).** Lo que sigue al `#` no
sale del navegador: el hosting registra solo `/p`, y el servidor del portal entrega la copia cifrada por huella sin ver el
presupuesto. El navegador deriva del link la huella y la llave (WebCrypto; el ERP cifra con lo mismo desde Node). Se descartó
`/p/{link}`: cada link abierto quedaba en los registros de acceso. Y `/p/{id}#{llave}`: la huella ya sale del link, un dato menos.
Aceptado: sin JavaScript no muestra nada, la vista previa de WhatsApp es genérica, y reenviar el texto sigue abriendo (el `#`
viaja con el link). Las visitas no cambian: ya las anotaba el navegador.

**Copiar y leer visitas es TypeScript: excepción explícita a "regla de negocio → Postgres" (2026-11-12).** Una función no escribe
en dos proyectos, y el cifrado necesita el link fuera de la base. El reparto: la base del ERP decide qué falta copiar y arma lo
que se copia; TypeScript solo cifra, lleva y trae, y le avisa a la base que llegó; la base del portal valida lo que recibe.
Corre como el pedido de Monedas: `after()` desde el Sidebar cada hora, y el botón espera para decir si anduvo.

**El SQL del portal vive en `sql/portal/` y se aplica con el MCP `supabase-portal` (2026-11-12).** Proyecto `gprkjktlbtemzzjanijn`,
segundo servidor en `.mcp.json`; el MCP `supabase` sigue atado al ERP. Misma regla que `sql/`: `apply_migration` con el texto
exacto del archivo. Numeración propia, para que un archivo no se aplique en la base equivocada por el número.

## La base

Tramo 1a, en el ERP (`sql/200_presupuestos_links.sql`, `sql/tests/presupuestos_links.sql`, `db_schema/presupuestos.md` →
*presupuestos_links*). Aplicado el 2026-11-11; el 2026-11-12 el archivo no estaba en el repo y se recuperó de la base, con el mismo
md5 que la migración aplicada. Lo de abajo se lee del SQL: el texto original de esta sección se perdió con los archivos.

**El link nace solo al salir de borrador, y cada cambio en lo que ve el cliente es una revisión.** `revision` sube con el estado, el
nombre o la versión elegida del presupuesto, y con cada versión que entra o sale de `publicado`. Al día es `copia_revision =
revision`: versión entera y monotónica, sin fechas (`GUIDE_SYNC.md`). Reintentar una copia no rompe nada.

**Una autorización de Técnica también es una revisión.** Vale para las ventanas iguales de todo el presupuesto, así que puede
habilitar una combinación de opcionales en una versión ya publicada.

**La llave no se lee de la tabla: la da una función, solo a quien arma.** Quien ve el presupuesto lee el estado de la copia y las
visitas, pero no puede sacar el link. La misma función sirve a "Copiar link" (anota la primera vez) y a "Ver como cliente" (no anota).

**Anular deja al link viejo pendiente hasta que el portal confirma el corte.** Si el portal está caído, el corte se reintenta como
cualquier copia, y la ficha lo muestra.

**Lo que falta copiar y la confirmación son funciones solo para `service_role`.** El servidor del ERP copia sin usuario (cada hora),
como Monedas.

Tramo 1b (`sql/201_presupuestos_portal_copia.sql`, `sql/tests/presupuestos_portal_copia.sql`, 93 / 93), aplicado el 2026-11-12.

**La copia la arma `presupuestos_portal_copia(link)`, con la revisión que tenía el link al armarla.** Esa es la que el servidor
confirma: si sube otra mientras copia, el link sigue pendiente. TypeScript cifra el jsonb tal cual.

**Cada combinación sale de la versión de Catálogo y la fecha de la ventana, como lo publicado.** Juan publicó el lunes, el aluminio
subió el miércoles: el viernes Carlos destilda el mosquitero y ve el precio del lunes sin mosquitero, no uno de hoy. La publicada va
con el precio guardado, no recalculado.

**Las casillas son las de la versión de Catálogo de cada ventana, en orden fijo: piezas opcionales (orden, nombre), después servicios
opcionales vigentes a esa fecha (paso, nombre).** Es el orden del código de "Enviar mi elección". Un servicio que no aplica a esa
ventana ni con todo tildado no es casilla. Una combinación que el cálculo deja distinta de lo tildado (la Cortina sin su Cajón) no
se ofrece: es otra.

**Una combinación con alertas sale solo si la cubre una autorización de Técnica, y con otras piezas Técnica no la vio.** Mismas
piezas que lo publicado, cambiando servicios: es la ventana que Técnica autorizó. Con otra pieza, no se ofrece (*Elige opcionales
ventana por ventana*, `decisiones/presupuestos.md`). Aprobado: solo lo aprobado, sin casillas.

**El piso del renglón aparte es el mínimo del servicio, en la moneda de su sección y con el recargo, a la fecha de las ventanas.**
El portal lo compara con lo que suma el renglón; no calcula.

**Los importes de cada combinación salen de la misma función que los del ERP.** La cuenta de `presupuestos_version_importes` pasó a
`presupuestos_importes_de`, que recibe los renglones; la pública la envuelve. Verificado: los importes y los nombres de las 119
versiones de la base dieron el mismo md5 antes y después.

**Las monedas de referencia son de la configuración, para todos, y no van en la copia (2026-11-12).** Arrancan pesos y dólar oficial.
Van al portal con los tipos de cambio, cada vez que el ERP los actualiza (tramo 3): cambiarlas no revisa cada link.

Tramo 2, en la base del portal (`sql/portal/001_portal_base.sql`, `sql/portal/tests/portal_base.sql`, 46 / 46,
`db_schema/portal.md`), aplicado el 2026-11-12.

**El servidor del portal entra con la clave publicable y dos funciones; el del ERP, con `service_role` (2026-11-12).** `anon` solo
lee una copia por huella y anota visitas, sin GRANT en las tablas: si se filtra la clave del portal, no se escribe una copia ni se
leen visitas. Los avisos del linter (RLS sin policies, `SECURITY DEFINER` para `anon`) son esto, a propósito.

**Una copia es una fila por link, con la revisión del ERP; la más nueva gana y un cortado no vuelve.** Reintentar o que llegue tarde
una copia vieja no pisa nada, así el ERP puede repetir sin coordinar. Cortar borra la copia: lo cifrado ya no está ni para quien
tenga el link. Cortar un link que nunca se copió deja la fila cortada, para que una copia atrasada no lo abra.

**Una visita es un dispositivo con una versión, sin 30 min de pausa entre aperturas.** Abrir la v1 y después la v3 son dos. Una
versión que la copia no muestra, o un link cortado, no anota y no da error: el portal no confirma qué huellas existen.

Tramo 3: copiar y leer visitas (`sql/202`–`203`, test 11 / 11; `sql/portal/002`, test 5 / 5; `modules/presupuestos/portal.ts` y
`cifrado.ts`, check `erp-app/scripts/cifrado-check.mts` 6 / 6), aplicado el 2026-11-12.

**Huella y llave salen del link con SHA-256 y un prefijo: `huella:` y `llave:` (2026-11-12).** La huella va en hexadecimal; la llave
es la de AES-256-GCM, y la copia es base64 de iv (12) ‖ cifrado ‖ tag (16), lo que WebCrypto espera. Sin prefijos, la huella que
guarda el portal sería la llave. El link ya es de 128 bits al azar: no hace falta un derivador lento.

**El aviso de la primera visita le llega al responsable de la obra (decisión del usuario, 2026-11-12).** Juan armó, Laura publica la
v4 en sus vacaciones: el aviso de la v4 le llega a Juan, como el WhatsApp. Una versión ya vista por otro link (anulado) no avisa de
nuevo. Se descartaron quien publicó y los dos.

**Las visitas se guardan en el ERP por link y versión, con la cuenta entera del portal.** Cada lectura pisa la anterior; el aviso lo
da el alta de la fila, en la base.

**Los tipos de cambio van al portal todos, con la marca de cuáles son referencia (2026-11-12).** El portal necesita el de la moneda
de cada sección para convertir, no solo el de las referencias. ARS va con valor 1 y fecha fija, para no reemplazarla cada hora. Van
en la misma pasada horaria que las visitas: MonedAPI tampoco cambia más seguido.

**Copiar corre en cada página que se abre; leer visitas y monedas, una vez por hora por proceso (2026-11-12).** `after()` desde el
Sidebar, como Monedas. Lo pendiente es una consulta que casi siempre vuelve vacía; la hora se cuenta en memoria del servidor, sin
tabla (`shortcut` en `portal.ts`). Las variables `PORTAL_SUPABASE_URL` y `PORTAL_SUPABASE_SERVICE_ROLE_KEY`: solo servidor.

## Aplicar la elección

Tramo 4 (`sql/204_presupuestos_eleccion.sql`, `sql/tests/presupuestos_eleccion.sql`, 83 / 83), aplicado el 2026-11-12. El formato
del código, en el encabezado del SQL y en `db_schema/presupuestos.md` → *La elección del cliente*: lo arma erp-cliente con esa regla.

**El código lleva el número del presupuesto: `…/presupuestos/eleccion/P-0142-V3-7K2M-9QX4-B` (decisión del usuario, 2026-11-12).**
El número de versión es por presupuesto: sin el código, el link no sabía de cuál. "Pegar elección" en la ficha de otro presupuesto
lo dice. Se descartaron el id en la ruta (ilegible) y el link solo desde la ficha (se perdía tocar el link).

**Aplicar descarta la versión abierta de esa variante (decisión del usuario, 2026-11-12).** v3 publicada, Juan arrancó la v4 para
sumar la ventana del lavadero y llega la elección de Carlos sobre la v3: la v4 se descarta (si estaba en revisión, se retira antes y
sus pedidos quedan retirados) y la elección queda en la v5, desde la v3. Lo dice la vista previa antes de aplicar ("Se descarta la
v4"). Se descartaron aplicar sobre la v4 (mezclaba lo de Juan con lo de Carlos) y frenar siempre.

**La corrección queda a hoy, y Juan ve tres totales (decisión del usuario, 2026-11-12).** "Carlos vio 21.400 · con precios de la v3
da 21.650 (mínimo de colocación) · a hoy 22.100". A hoy no le pide nada a Laura; si Juan quiere sostener el precio, "Mantener
todas" y la autorización de siempre. Sin cambios en Catálogo, los dos últimos dan igual. Se descartó arrancar mantenida: pedía
autorización aunque no hubiera subido nada.

**El código guarda el `n` de cada ventana, no el orden de las combinaciones ofrecidas (2026-11-12).** Una autorización de Técnica
posterior suma combinaciones y corría las posiciones; el `n` y el `ancho` salen de la versión de Catálogo y la fecha de la ventana,
fijos para una versión publicada. Por eso la copia los lleva y los links se volvieron a copiar.

**El dígito de control es una suma con pesos módulo 31, no un hash (2026-11-12).** Detecta siempre una letra cambiada o dos vecinas
permutadas (salvo 0 ↔ Z), y es una línea en SQL y en el navegador. No es seguridad: lo que entra lo valida el ERP igual
(versión publicada, combinación ofrecida, permiso de armar).

**"Lo que vio el cliente" se calcula en el ERP, con la regla de los totales (2026-11-12).** Las combinaciones elegidas tal como
estaban en la copia, y los mínimos como se publicaron (el portal no los recalcula). La cuenta de los totales pasó a
`presupuestos_totales_de`, que también usa `presupuestos_version_totales`.

## La pantalla de la elección

Hecha el 2026-11-12 (`erp-app/src/app/(erp-app)/presupuestos/eleccion/[codigo]/`, `EleccionView.tsx`, `PegarEleccion` en `AccionesFicha.tsx`).
Sin probar en el navegador.

**El segmento de la ruta es el código o el mensaje entero (2026-11-12).** Ni la ruta ni "Pegar elección" extraen el código: la base
lo busca en el texto (`presupuestos_eleccion_leer`), así la regla vive en un solo lugar. "Pegar elección" es un modal en la ficha que
llama a la misma lectura y avisa si la elección es de otro presupuesto; la ruta es para tocar el link, y su "Volver" lleva a la ficha
del presupuesto de la elección.

**Después de aplicar, la diferencia entre lo que vio el cliente y a hoy va en un aviso, por moneda: "A hoy da US$ 700 más que lo que
vio el cliente (21.400 → 22.100)"; sin diferencia, "Mismo total que vio el cliente" (2026-11-12).** Los tres totales siguen; el aviso
dice si hay que decidir mantener.

**En el celular, "Copiar link" abre el menú de compartir del teléfono (`navigator.share`); en la compu, copia (2026-11-12).** Juan en
obra lo manda por WhatsApp sin pasar por el portapapeles. Anota "copiado" igual.

**Lo que lee el cliente usa "US$ 7.180,00" y "$ 1.240.000", en el portal, el impreso y el editor (2026-11-12).** `formatMontoCliente`
en `lib/monedas.ts`: "USD oficial" es una palabra interna y el cliente veía dos formatos para el mismo presupuesto. Lo interno
(*Antes de publicar*, calculadora, Monedas) sigue con `formatMonto`.

**Las visitas de la tarjeta nombran la variante y marcan la que el portal muestra hoy: "Aluminio · v3 (la que ve hoy)"; las
reemplazadas, abajo y en gris (2026-11-12).** "Hoy" es lo que el portal confirmó (`copia_versiones`); sin copia, la publicada. Sin `presupuestos_armar` o `administrar`, 404; un código roto, versión reemplazada o combinación no
ofrecida (PR030–PR032) se muestra en la página. Los tres totales (lo que vio el cliente, con los precios de la publicada, a hoy) salen
al aplicar, en el aviso: la vista previa solo trae lo que vio el cliente.

## La página del portal

Hecha el 2026-11-12 (`erp-cliente/src/app/p/`, `src/lib/`, `src/app/api/`). Probada con una base simulada y Playwright en celular; sin
probar contra el portal real (falta cargar las variables, ver `BACKLOG.md`).

**El navegador descifra y el servidor del portal solo reparte (2026-11-12).** `/p` lee el `#`, deriva huella y llave con WebCrypto
(`lib/cifrado.ts`), pide la copia a `/api/copia` (`portal_leer` + `portal_monedas_leer`, con `fetch` a PostgREST: sin librería nueva)
y anota la visita en `/api/visita`. Ambas rutas validan la forma de lo que reciben; el permiso lo da la base.

**La vista previa es `#{link}?previa` (2026-11-12).** No anota visitas y muestra "Vista previa — no cuenta como visita". El ERP la
arma al construir "Ver como cliente".

**El total que ve el cliente lo suma el navegador con la regla del ERP (`lib/totales.ts`); el que vale lo recalcula el ERP al aplicar
(2026-11-12).** Duplica a propósito la cuenta de `presupuestos_totales_de`: sin ella el cliente no vería el total mientras tilda. Un
tilde solo se permite si da una combinación ofrecida, y el `n` del código sale de esa combinación.

**El link al ERP sale de `NEXT_PUBLIC_ERP_URL`, que se lee al compilar.** Sin ella, "Enviar mi elección" queda apagado.

**Cada ventana se ve como en el impreso: designación, paquete, ubicación, cantidad y lo cargado; con IVA incluido, los importes con
IVA (2026-11-12).** El cliente controla contra el plano lo que compra, y las ventanas suman el total. `textoCargado` está copiado en
`lib/cargado.ts` (las apps no se importan); la copia no trae la versión de Catálogo del renglón, así que el orden de las medidas se
toma por nombre. Se descartó restaurar `sync-contracts` por una sola función.

**La lista va por sección, como el impreso: nombre, moneda e IVA, y el subtotal con dos secciones o más (2026-11-12).** El renglón
aparte es una línea en su sección ("Colocación · De 12 ventanas"), con el mínimo sumado si está en la misma sección, y sigue a lo
tildado; el otro mínimo sale como "Mínimo de Colocación". Debajo de la ventana, la casilla tildada muestra su monto. Sin esto el
cliente veía la colocación repetida en cada ventana y el mínimo como si fuera la colocación entera.

**El pie es el del impreso: subtotal, descuento con su %, IVA por alícuota (o "Total con IVA") y total; "Válido hasta el …" siempre
arriba; la referencia convierte el total entero, con la fecha del cambio: "Todo en pesos ≈ $ 19.940.000 (cambio del 12/11/26)"
(2026-11-12).** Es lo decidido en *Moneda e IVA*; antes convertía cada moneda por separado. Fechas como el ERP (30/11/26) y en hora
argentina: con UTC, después de las 21 la versión se veía vencida un día antes.

**Tocar una casilla que no da una combinación ofrecida aplica la ofrecida más parecida y lo dice: "Sacamos también Cortina: no se
ofrece sin Cajón" (2026-11-12).** Lo mismo que hace el formulario del ERP (`lib/entrada.ts`); antes la casilla quedaba atenuada y el
cliente no sabía por qué. Más parecida: respeta lo tocado y cambia lo menos del resto; en empate, menos casillas. Elige solo entre
las que trae la copia, así que nunca saltea a Técnica. Sin ninguna, "No disponible en esta ventana". `cercana` en `lib/eleccion.ts`.

Sin hacer: el piso de los renglones aparte, `ThemeToggle`, y el cartel de "Aprobado" con casillas para variantes ya aprobadas más allá
de lo que trae la copia.

## Qué muestra según el estado

~~**Vencida: muestra todo con "Venció el 30/11: los precios pueden cambiar", y "Enviar mi elección" apagado (2026-11-11).**~~ Ver
la siguiente.

**Vencida: muestra todo con el aviso, y en lugar de "Enviar mi elección", "Pedir precios actualizados por WhatsApp" (2026-11-12).**
El mensaje dice el número, el nombre y cuándo venció; sin WhatsApp, "Pedile los precios actualizados a quien te lo mandó". Sigue sin
dejar elegir sobre una vencida, pero el cliente ya no queda con dos botones apagados sin explicación. Se descartó esconder los
precios: el impreso de la misma versión los sigue mostrando.

**El mensaje va por opcional, como lo pide *Sin confirmación*: "Mosquitero: V1, V3, V7 · Colocación: todas · Cortina: ninguna"
(2026-11-12).** Hasta acá iba una línea por ventana, 24 con "sin opcionales". Todas y ninguna cuentan solo donde el opcional existe;
la ventana se nombra por designación, ubicación o paquete. El encabezado suma el número ("P-0142 · Torre Belgrano"); el código del
link no cambia y el ERP lo busca igual (la regex pide `-V`).

**Para el que tiene 24 ventanas: "En todas las ventanas" (Todas / Ninguna por opcional), el total fijo abajo en el celular con
*Enviar*, y "+ US$ 45" al lado de cada casilla sin tildar (2026-11-12).** "Todas" pasa cada ventana por `cercana`, como un tilde a
mano, y dice dónde no se ofrece. El "+" es lo que cambia el total, ventana y renglón aparte, por moneda: no muestra nada que no se
dedujera tildando (*Secciones y opcionales*: ningún % ni costo).

**Lo tildado queda en el navegador, por presupuesto y revisión, con "Volver a lo cotizado" (2026-11-12).** Recargar o volver mañana
no lo pierde; una copia nueva arranca de lo publicado, y lo guardado que ya no se ofrece se descarta. `localStorage`, como el
dispositivo: sin él, arranca de lo publicado.

**Las variantes se eligen con un `.segmented` que muestra el total de cada una con lo tildado, y cada una recuerda sus tildes
(2026-11-12).** Carlos compara Aluminio y PVC sin perder los mosquiteros que tildó en una al pasar a la otra. Se descartó ponerlas
lado a lado en pantalla grande: con el total en el selector ya se compara, y era mucho más código.

**Vigente, arriba de los botones: "No confirma la compra: te contactamos para cerrarla" (2026-11-12).** Sin confirmación
(*Sin confirmación*), el cliente podía creer que enviar era comprar. Si copiar falla, el mensaje queda en un campo para copiarlo a
mano.

**Sin copia, el portal dice "No encontramos este presupuesto. Si te lo acaban de mandar, probá en unos minutos; si no, pedile el link
actualizado a quien te lo mandó" (2026-11-12).** No distingue un link anulado de una copia que todavía no llegó (no confirma qué
huellas existen), y "ya no está disponible" le hacía creer al cliente que lo habían retirado. El error de red ofrece "Probar de nuevo".

**"Copiar link" con el portal sin actualizar fuerza la copia antes; si no llega, copia igual y avisa (2026-11-12).** Juan publica y
copia al instante: sin esto, Carlos abría antes de la copia. "Sin actualizar" es un aviso con *Reintentar* a la vista, no texto gris
con el botón en el `⋯`. `PortalFicha.tsx`.

**Aprobado: lo aprobado, sin casillas, con "Aprobado el 14/11". Rechazado o desactivado: no se muestra (2026-11-11).** El
texto es el de un link sin copia (arriba, 2026-11-12).

## A decidir al construir

- ~~**La llave en la dirección**~~ → *Dos bases*, *El link va después del `#`*.
- ~~**Migraciones del proyecto del portal**~~ → *Dos bases*, la última.
- ~~**La copia entre dos bases**~~ → *Dos bases*, *Copiar y leer visitas es TypeScript*.
