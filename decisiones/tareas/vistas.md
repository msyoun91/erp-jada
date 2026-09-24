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

## Todas (2026-09-24)

**Todas = todos los hilos, con filtro Huérfanos · Desactivados.** Huérfano (`esHuerfano`, con test):
abierto y activo, con responsable o asignado de un paso abierto que ya no puede recibir. El admin
transfiere o reasigna desde el hilo. `?responsable=` (del aviso "hilos huérfanos") suma el filtro
"De {persona}": lo que lleva o tiene abierto. Reusa `HilosView` sin "Nuevo hilo".
