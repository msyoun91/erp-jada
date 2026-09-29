# Vistas

## Misión (2026-09-24)

**Misión = mis pasos por decidir o por hacer, de a uno.** `asignado_id = yo`, activos, `solicitada` o
`pendiente`, de hilos activos y abiertos. Lo asignado a mi equipo no entra: es la bandeja de Equipo.
`getMision` en `queries.ts`; vista en `MisionView.tsx`.

**Un pedido entra aunque espere al anterior; un pendiente bloqueado o en espera, no.** Decidir un
pedido se puede hacer ya; completar, no. Los que esperan van en una lista desplegable con el motivo
("Espera a «X»" o la fecha y el motivo de la espera): una cola vacía con trabajo detrás parece rota.

**Orden: prioridad, después vence (sin fecha al final), después lo más viejo** (`compararMision`,
con test). Reemplaza la temperatura de `master`, que no existe en este modelo. El vence relativo
sin fecha todavía (paso no habilitado) no ordena: solo le pasa a un bloqueado, que no está en la cola.

**Acciones del asignado en la tarjeta; el resto, en el hilo.** Aceptar/Rechazar o Completar/Poner
en espera reusan los modales de `PasoModales.tsx`; "Abrir en el hilo" lleva a `/tareas/paso/{id}`
para todo lo demás (notas, devolver, historial). Sin segundo panel del paso.

**Las fichas del paso, al lado de la tarjeta (2026-09-29).** Como en el panel del paso: el registro
del hilo y lo que nombra la descripción, en pestañas (`pestanasDePaso`). Solo las del paso que se
mira: cambiar de paso pasa por `?paso=` y muestra la ruedita hasta que llegan; descartado traer
también las del siguiente, que haría más lenta la entrada. Con `?paso=` arranca en ese paso. En
mobile, un botón por ficha y la ficha encima de la tarjeta, con "volver". El link de acción sigue
en texto plano (`catalogo.md`). Archivos: `tareas/mision/page.tsx`, `MisionView.tsx`, `Fichas.tsx`,
`queries.ts` (`getSobre`, `PasoMision`).

**De `master` se conserva:** columna `max-w-2xl`, flechas ← → (ignoradas con un `dialog[open]` o
foco en un campo), barra de posición, índice que se recorta en vez de resetearse, "Sigue: …".

## Equipo (2026-09-24)

**Equipo = la bandeja del delegador, en tres tipos: Pedidos · Al equipo · Hilos.** Pedidos: pasos
`solicitada` con `equipo_id` = su equipo (al equipo o a un miembro). Al equipo: `pendiente` con
`asignado_equipo_id` = su equipo, sin repartir. Hilos: los de `equipo_id` del equipo o con un paso
de ese `equipo_id`, como la RLS. `getEquipo` en `queries.ts`; vista en `EquipoView.tsx`.

**Filtro por miembro en Pedidos y en Hilos, no en Al equipo.** Lo del equipo no es de nadie
todavía. Los miembros salen de `tareas_asignables()` sin `pedido`.

**Acciones en la fila, como en Misión.** Pedido: Aceptar · Rechazar · Repartir. Al equipo: Completar
(si no espera al anterior) · Poner en espera · Repartir. Repartir = `ReasignarModal` con
`soloMiEquipo`. Hilos reusa `HilosView` sin "Nuevo hilo": un hilo nuevo es de quien lo crea.

## Plantillas (2026-09-24)

**Plantillas = Mis plantillas · Catálogo, y "De otros" para el admin.** Una sola lectura
(`getPlantillas`: la RLS recorta) y cada pestaña filtra. "De otros" es donde el admin ve, edita, usa y
desactiva las ajenas (*Función admin por módulo*); publicar sigue siendo del dueño. Vista en
`PlantillasView.tsx`; `?ver=catalogo` abre el Catálogo (el link de "Copia de «X»").

**"A revisar" es `motivoRevisar` sobre `tareas_asignables()`** (`derivados.ts`, con test): el fijo que
no figura o no puede recibir, o que sería pedido sin `tareas_pedir`. Al usarla, esos pasos y los
vacíos se preguntan con quien la usa por defecto (`UsarPlantillaPanel`); el resto lo resuelve
`usar_plantilla`.

**"Usar plantilla" desde el hilo: solo el responsable (o el admin), con sus plantillas activas.**
Suma los pasos en paralelo con lo que el hilo tiene.

**El formulario de la plantilla muestra todo a la vista (2026-09-29).** Decisión del usuario. "Sobre" y
"Corre sola" (un select: "Al crearse la obra", "Al pasar a {estado}"; con "Activa", que el admin solo
puede apagar) van bajo la descripción; cada paso suma "Entra" (siempre, si hay o no hay {rol}) y "Se
completa" (a mano, al vincular {rol}, al pasar a {estado}), y chips que insertan `{@registro}`,
`{@rol}` y `{dato}` en la descripción. Cambiar "Sobre" limpia disparo y condiciones. Los códigos
salen de `entes` (`getEntesSobre`, la RLS recorta); los labels, de `lib/entes.ts`, así que "Sobre"
ofrece solo los entes que la app sabe decir: obra, persona y empresa (hilo y paso, cuando tengan
labels ahí). Archivos: `PlantillaFormPanel.tsx`, `etiquetas.ts`, `e2e/tareas.spec.ts`.

**Usar una plantilla con "Sobre" pide el registro y tacha lo que no entra (2026-09-29).** Decisión
del usuario. Un buscador de ese ente solo (`buscarRegistrosDe`: `buscar_registros` del módulo,
filtrado por ente) y, sin elegir, no se crea. Elegido, los pasos cuya condición el registro no
cumple salen tachados con el porqué ("No entra: la obra no tiene arquitecto"), leyendo sus roles con
`relacionados_de_registro` —la misma lectura que `usar_plantilla`—; no se les pregunta asignado.
"Se completa sola…" se muestra al crear un hilo, no al sumar a uno (puede no ser sobre ese
registro). Archivos: `UsarPlantillaPanel.tsx`, `RegistroPicker.tsx`, `actions.ts`.

**El paso muestra "Se completa sola" con su condición (2026-09-29).** En el panel del paso, como
un dato más, mientras esté abierto y después: cerrado solo, el resultado queda vacío y esa fila
dice por qué. Archivos: `PasoPanel.tsx`, `e2e/tareas.spec.ts`.

## Todas (2026-09-24)

**Todas = todos los hilos, con filtro Huérfanos · Desactivados.** Huérfano (`esHuerfano`, con test):
abierto y activo, con responsable o asignado de un paso abierto que ya no puede recibir. El admin
transfiere o reasigna desde el hilo. `?responsable=` (del aviso "hilos huérfanos") suma el filtro
"De {persona}": lo que lleva o tiene abierto. Reusa `HilosView` sin "Nuevo hilo".
