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

## Todas (2026-09-24)

**Todas = todos los hilos, con filtro Huérfanos · Desactivados.** Huérfano (`esHuerfano`, con test):
abierto y activo, con responsable o asignado de un paso abierto que ya no puede recibir. El admin
transfiere o reasigna desde el hilo. `?responsable=` (del aviso "hilos huérfanos") suma el filtro
"De {persona}": lo que lleva o tiene abierto. Reusa `HilosView` sin "Nuevo hilo".
