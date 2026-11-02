# Monedas

**Los tipos de cambio son un módulo propio, fuera del catálogo (2026-10-29).** El catálogo los lee para
convertir costos y precios (`decisiones/catalogo.md` → *Moneda*), y Compras los va a leer de acá. Las
decisiones de abajo se tomaron en el catálogo (2026-10-27 y 2026-10-29) y se mudaron sin cambios de
fondo.

## Ficha del módulo

```
Módulo: Monedas
Objetivo: que todo el ERP convierta entre ARS, USD oficial, USD blue y EUR con un tipo de cambio
          único y con fecha, que se actualiza solo desde MonedAPI
Personas                qué ve · qué hace · qué NO ve
├── Administración — tipos de cambio con su historial · corrige a mano, confirma o corrige un rojo de
│                    MonedAPI, elige la moneda principal · —
├── Gerente        — todo (función que ve y hace todo) · lo mismo; recibe aviso de cada valor que
│                    entra por una persona · —
├── Todo usuario   — los vigentes con su fecha, en la barra de menú · nada · el historial
└── Cliente        — NO entra: ve la moneda de su presupuesto en erp-cliente
Lo leen (módulos, no personas): Catálogo, Compras, los totales
Entes: ninguno — un tipo de cambio es un valor con fecha, sin ficha, dueño ni chip
Eventos: ninguno. Los avisos van por notificaciones

Monedas
└── Monedas (vista)                 — administración, gerente: vigentes + historial
    ├── monedas_corregir (funcion)  — administración, gerente: corrige a mano, confirma o corrige un rojo
    └── monedas_principal (funcion) — administración, gerente: elige la moneda principal
Barra de menú (sin submódulo)        — todo usuario: los vigentes
Delegación: no se delega · Reglas entre permisos: ninguna
```
Aprobada el 2026-10-29. La función que ve y hace todo es la vista con sus dos funciones: no hay filas
que alguien no vea.

Pendientes:
Ninguno.

**Monedas guarda solo el de venta; si un presupuesto cobrado en billetes usa el de compra lo decide
Presupuestos (2026-10-29).** Depende de cómo paga el cliente, que no es de este módulo. Si lo decide,
Monedas suma la compra entonces (`BACKLOG.md` → *Presupuestos*).

## Tipos de cambio (2026-10-27)

**Los tipos de cambio salen de MonedAPI, en venta: dólar oficial (`monedapi.ar/api/v2/usd/oficial`) y
euro oficial (`/api/v2/eur/bna`, el único euro que tiene).**

**Un solo enum `moneda` para todo el ERP: `ARS | USD_OFICIAL | USD_BLUE | EUR` (2026-10-29).** El que
ya existía (`ARS | USD`, la comisión del referente en Obras) se renombra: `USD` pasa a `USD_OFICIAL`, y
las comisiones ya cargadas en USD quedan al oficial. El mismo enum sirve para la serie de tipos de
cambio, la moneda principal y cada monto. Que la comisión pueda ser blue lo decide Obras cuando lo pida.

**El dólar no es uno: cada monto en USD dice si es oficial o blue, y el presupuesto también
(2026-10-29).** Cada monto se pasa a pesos con su dólar, se suma en pesos, y sale a la moneda del
presupuesto con el dólar del presupuesto. El perfil se compra al blue (USD 12 × 1.500 = $18.000) y el
cliente paga al oficial (1.450): el presupuesto en USD oficial lo lleva como USD 12,41, no USD 12. Se
descartó un solo dólar para todo: con el oficial, el perfil entraba a $17.400 y se perdían $600 por
perfil sin que nadie lo viera. El blue sale de MonedAPI (`/api/v2/usd/blue`) con las mismas reglas que
el oficial. El euro, solo oficial: no hace falta otro por ahora.

Para recalcular se usa la copia guardada, nunca MonedAPI: si el servicio desaparece, los presupuestos
viejos se siguen recalculando. Sin clave ni registro; el euro puede quedar días sin actualizarse
(el 2026-10-27 seguía el del 20/10).

~~**Se traen cuando hacen falta, sin cron: el primer presupuesto del día los pide a MonedAPI.**~~
Superada el 2026-10-29; ver la decisión siguiente.

**Se traen sin cron, cada hora: si lo último que se pidió a MonedAPI tiene más de una hora, la próxima
página que abre cualquier usuario lo vuelve a pedir (2026-10-29).** Ana abre a las 08:30 y MonedAPI
todavía da el blue del lunes; el blue sube a las 11:00, a las 11:20 alguien abre una página y $1.600
vale desde ahí, y Juan presupuesta a las 15:00 con $1.600. Con una vez por día, Juan presupuestaba
todo el día con el de las 08:30. Si MonedAPI no responde, se usa el último guardado. Cada valor vale
desde que se guardó, no desde el día: el que se guarda a las 11:20 no cambia un presupuesto de las
09:40 hecho con el anterior.

**La barra tiene un botón actualizar para todos, que pide a MonedAPI a lo sumo una vez por minuto en
todo el sistema (2026-10-29).** Si el blue se mueve a las 11:05, Juan no espera a la hora. Juan toca a
las 11:10:20 y Pedro a las 11:10:40: Pedro recibe lo que trajo Juan. MonedAPI es gratis, sin clave, y
tiene Cloudflare adelante: no se sabe cuánto aguanta, y cinco vendedores tocando varias veces podían
hacer que bloqueara al ERP. Lo pide el servidor, igual que el pedido de cada hora.

**Si un pedido a MonedAPI falla (no responde, error o algo que no es un tipo de cambio), quienes
tienen `monedas_corregir` ven "MonedAPI no responde desde las 11:10" hasta que un pedido vuelve a
andar (2026-10-29).** Es estado, no evento (`decisiones/global/infra.md` → *Evento es fila, estado es
consulta*): diez toques con MonedAPI caído dan un aviso, no diez. Quien tocó ve "No se pudo actualizar:
se usa el de las 10:20. Administración ya está avisada". Que el valor no cambie no es una falla y no
avisa: eso lo cubre el aviso de 7 días (el euro, que MonedAPI deja quieto).

**Administración puede corregir uno a mano, y lo de MonedAPI entra solo si es más nuevo.** Cada valor
guarda su fecha: la que dice MonedAPI (`updatedAt`) o la de la carga a mano, y se muestra con ella
("euro $1.780, del 20/10"). Así el euro del 20/10 que MonedAPI sigue dando no pisa una corrección del
27/10, ni suma una fila igual cada día.

**Todo valor que entra por una persona les avisa a los demás que tienen `monedas_corregir` (el gerente
entre ellos): la corrección a mano y la confirmación de un rojo de MonedAPI (2026-10-29).** "Ana
corrigió el dólar blue: $1.565 → $1.700": un +8,6 % no da color y sube todo lo que se compra al blue en
los paquetes que el gerente aprobó, y él o Marta lo revierten. Lo que MonedAPI trae solo no avisa:
entra todos los días. Como los servicios en % (`decisiones/catalogo.md` → *Versiones y aprobación*). Se
descartó una función `monedas_avisos` solo para el gerente: un permiso más, y Marta, que también puede
atajar el error, no se enteraba.

**Los tipos de cambio tienen los tres niveles del costo (`decisiones/catalogo.md` → *Versiones y
aprobación*) (2026-10-29).** A mano, el rojo pide confirmación: $17.800 en vez de $1.780 multiplicaba
por 10 todo lo que cuesta en euros, sin color ni aviso. Lo de MonedAPI en rojo (50 % o más) no entra
solo: se sigue usando el último guardado y Administración recibe un aviso para confirmarlo o
corregirlo; confirmado, vale desde la confirmación. Amarillo y naranja entran y quedan marcados. Si
MonedAPI cambia el formato y da el dólar como 1,45, nada sale a precio de regalo. Costo aceptado: en
una devaluación de verdad (diciembre de 2023, el oficial más que se duplicó en un día) el dólar nuevo
no rige hasta que Administración lo confirma, y mientras tanto se presupuesta con el viejo.

**Lo de MonedAPI lo pide y lo guarda el servidor, nunca el navegador de quien presupuesta
(2026-10-29).** Lo dispara un vendedor o un cliente, pero el número no pasa por sus manos: si la base
aceptara el valor que manda el navegador, cualquiera guardaba un dólar inventado.

**Si un tipo de cambio lleva 7 días sin actualizarse, se le avisa a quien puede corregirlo.** Es
estado, no evento: se calcula al mirar, sin cron (`decisiones/global/infra.md` → *Evento es fila,
estado es consulta*).

## Moneda principal (2026-10-29)

**Administración elige la moneda principal: ARS, USD oficial, USD blue o EUR. Viene preseleccionada en
un presupuesto nuevo y al cargar un monto (se puede cambiar en cada uno), y los totales del ERP se
muestran en ella.** El gerente ve "vendido en octubre" en USD blue aunque haya presupuestos en pesos.
Cambiarla no toca nada cargado: cada monto guarda su moneda.

**Un total pasa cada monto a la moneda principal con el tipo de cambio de su fecha, no con el de hoy
(2026-10-29).** Octubre: $1.565.000 del 1/10 (blue $1.400) + USD 1.000 blue → USD 2.117,86, y en marzo
sigue dando eso. Se descartó el de hoy: con el blue a $2.000, octubre bajaba solo a USD 1.782,50, y
con inflación todo mes viejo parecía peor.

## Quién los ve (2026-10-29)

**Los tipos de cambio vigentes los ve todo usuario del sistema, en la barra de menú: "USD oficial
$1.560 · USD blue $1.565 · EUR $1.780", cada uno con su fecha. Los cambia solo Administración (y la
función que ve y hace todo), en el módulo Monedas.** Juan, con un cliente en el teléfono, dice el mismo
dólar que va a usar el presupuesto, desde cualquier pantalla y sin navegar. En el celular va dentro del
menú. Se descartaron Monedas en el menú de todos (una entrada más para ver tres números) y un widget en
Inicio (solo se ve al entrar). Excepción de permisos: `decisiones/global/permisos.md` → *Lo que ve todo
usuario*.

## Construcción (2026-10-29)

**Los avisos de estado (MonedAPI no responde, rojo por confirmar, 7 días sin actualizar) se ven en la
barra de menú, debajo de los tipos de cambio, y en Monedas; no en la campanita.** Son estado y la
campanita lista eventos (`decisiones/global/infra.md` → *Evento es fila, estado es consulta*); la
barra está en todas las pantallas, al lado del número que avisan. Solo los ve quien tiene
`monedas_corregir`. La corrección a mano y la confirmación sí van a la campanita: son eventos.

**El pedido de cada hora corre con `after()` desde el Sidebar, una vez enviada la página.** Nadie
espera a MonedAPI (hasta 5 s por moneda); lo que trae se ve en la navegación siguiente. El botón sí
espera, para decir si anduvo.

**`monedas_convertir` no redondea:** redondea quien muestra o guarda el monto, que sabe a cuántos
decimales.

Archivos: `sql/155_monedas_enums.sql`, `sql/156_monedas.sql`, `sql/tests/monedas.sql`,
`db_schema/monedas.md`, `erp-app/src/modules/monedas/`, `erp-app/src/lib/monedas.ts`,
`erp-app/src/lib/supabase/admin.ts` (el cliente `service_role`, antes dentro de
`modules/usuarios/actions.ts`), `components/layout/Sidebar.tsx`, `SidebarNav.tsx`, `MobileNav.tsx`.
