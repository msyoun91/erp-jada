# Decisiones — erp-cliente (portal)

> **Estado: ficha aprobada (2026-11-11), revisada punto por punto con el usuario. Sin SQL ni pantallas.** Es la etapa 2 de
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

## Qué muestra según el estado

**Vencida: muestra todo con "Venció el 30/11: los precios pueden cambiar", y "Enviar mi elección" apagado (2026-11-11).** Sigue
lo decidido en Presupuestos (el portal no deja avanzar sobre una vencida; Juan puede aprobarla igual). Se descartó esconder los
precios: el impreso de la misma versión los sigue mostrando.

**Aprobado: lo aprobado, sin casillas, con "Aprobado el 14/11". Rechazado o desactivado: "Este presupuesto ya no está
disponible" (2026-11-11).**

## A decidir al construir

- ~~**La llave en la dirección**~~ → *Dos bases*, *El link va después del `#`*.
- ~~**Migraciones del proyecto del portal**~~ → *Dos bases*, la última.
- ~~**La copia entre dos bases**~~ → *Dos bases*, *Copiar y leer visitas es TypeScript*.
