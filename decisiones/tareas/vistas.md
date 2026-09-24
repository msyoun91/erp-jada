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
