# Tareas — pedidos

Asignar afuera del equipo: `tareas_pedir`, aceptar, rechazar, devolver, volver a pedir, editar y reabrir un pedido.

**"Pedido" se calcula en el momento, sin columna (2026-09-24).** Asignado afuera del equipo del
responsable, hoy. Tras transferir un hilo al equipo del asignado, lo que era pedido pasa a interno:
editarlo avisa ("paso editado") y no lo devuelve a `solicitada`.

**Pedir es un acto del responsable del hilo, y el aviso de la respuesta va al responsable actual.**
Sin columna `pedido_por`: quién pidió en su momento queda en `eventos`.

**Asignar fuera del equipo es un pedido, con función propia no delegable (`tareas_pedir`).** El
usuario quiere elegir qué líderes pueden pedir a otros equipos; delegable, cualquier delegador la
repartiría. El pedido nace `solicitada` y se acepta o rechaza (motivo obligatorio); decide el
receptor o el delegador de su equipo. Rechazar no cancela: el previo es inmutable y los siguientes
quedarían trabados, así que resuelve el responsable del hilo. Independiente: misma regla, todo otro
es "afuera" (opción a; la b era una excepción).

**Sin `tareas_pedir`, los pedidos vivos siguen pero no se reenvían (2026-09-24).** Todo lo que
genera `solicitada` —nacer, reasignar afuera, reabrir, volver a pedir, editar título, descripción
o vencimiento de un pedido— exige `tareas_pedir` en quien lo hace. Si el responsable lo pierde, el
receptor sigue con lo aceptado y el responsable puede cancelar, cambiar prioridad, anotar o
transferir el hilo. No se cancela nada: quitarle el permiso no anula lo que otro equipo ya aceptó.

**Un pedido aceptado se puede devolver (2026-09-24).** `pendiente → rechazada` con motivo, solo en
pedidos: sin salida, lo que el receptor ya no puede hacer figuraba como compromiso vigente y
trababa los siguientes. Reusa el rechazo, su resolución y su aviso. Dentro del equipo no hace
falta: el responsable es un compañero y reasigna.

**Un rechazado se vuelve a pedir con un botón (2026-09-24).** `rechazada → solicitada`, al mismo
u otro asignado afuera, con `tareas_pedir`; solo el responsable. Caso: "falta la medida" → se agrega
y se vuelve a pedir a Juan; antes solo se podía cancelar, y reasignar al mismo no era un cambio.
Editar un rechazado no lo reenvía: se corrige en varias ediciones y se reenvía una vez. El motivo
del rechazo se limpia; el anterior queda en `eventos`. Reasignar adentro del equipo (`pendiente`) y
cancelar quedan escritos como las otras salidas.

**Editar título, descripción o vencimiento de un pedido aceptado lo devuelve a `solicitada`.**
Elegido por el usuario sobre "solo avisar": lo aceptado no cambia sin volver a aceptarse. La
prioridad no lo devuelve: ordena, no cambia el trabajo.

**Reabrir un pedido lo vuelve a `solicitada`, salvo que lo reabra el asignado (2026-09-24).** Si
no, rechazar → cancelar → reabrir dejaba `pendiente` algo que el receptor había rechazado, y un
pedido cancelado antes de responderse volvía aceptado sin que nadie lo aceptara. Es la regla de
nacimiento aplicada al reabrir: afuera del equipo del responsable = pedido, exige `tareas_pedir`.
El asignado que reabre lo suyo lo retoma él: `pendiente`.

