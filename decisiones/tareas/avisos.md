# Tareas — avisos

La campanita del módulo: de dónde sale cada aviso y los casos que la ficha no resolvía. Quién
recibe qué: ficha (`README.md` → *Eventos que emite*). Archivos: `sql/115`, test
`sql/tests/tareas_avisos.sql`.

**Los avisos salen de los triggers de tareas con OLD y NEW, no de un consumidor de `eventos`
(2026-09-24).** La ficha decía "a partir de esos eventos". Pero una sola sentencia emite varios
(relación que se va, relación que llega, estado), y el aviso depende de la combinación: volver a
pedirle a otro es "pedido recibido" para el nuevo y "paso quitado" para el anterior, no "reabierto".
Rearmar eso desde filas de `eventos` era volver a deducir lo que el trigger ya sabe. Los eventos
se emiten igual, para la auditoría y las plantillas.

**Lo que el destinatario perdió se muestra con título y sin link (2026-09-24, decisión del
usuario).** "Paso quitado", "paso dado de baja" e "hilo dado de baja" avisan de algo que el
destinatario ya no ve; con "apunta, no copia" al pie de la letra se borraban solos antes de que
alguien los leyera. `tareas_avisos_salida()` (DEFINER) da el título solo para esos tres tipos y solo
de los avisos propios, como `notificaciones_actores` con los nombres; hay link solo si todavía lo
ve. Se descartaron el aviso sin título (no sirve) y sacarlos de la ficha.

**Todo lo que entra a `solicitada` es "pedido recibido" (2026-09-24).** Nacer, reasignar afuera,
volver a pedir, editar un pedido aceptado y también reabrir un pedido: en todos hay que decidir
de nuevo, así que va al asignado y al delegador de la persona. La ficha listaba "paso reabierto"
para reabrir; queda para lo que vuelve a `pendiente`.

**Una sola vez por persona y cambio (2026-09-24).** Quien recibe el paso recibe "tarea asignada"
o "pedido recibido" y nada más: si es también el responsable (transferencia, baja con el hilo y el
paso yendo al mismo delegador), no recibe además "paso reasignado"; si pierde y recibe a la vez
(de la persona al equipo que delega), solo recibe. En una transferencia o una baja el nuevo
responsable recibe "hilo transferido" y un aviso por cada paso que le quedó: dice qué le llegó.

**"Paso quitado" no avisa a quien se fue (2026-09-24).** No lo recibe quien ya no puede recibir
(baja, pérdida de `tareas_ver`) ni quien ya no está en el equipo del paso (cambio de equipo): esos
no siguen lo que tenían. Se mide en el trigger, no por quién escribió, para que valga igual si la
baja algún día la hace un RPC.

**"Paso bloqueado" solo al insertar antes (2026-09-24).** Como dice la ficha. Reabrir el previo
también bloquea al siguiente, pero ese ya recibe "paso reabierto" si estaba completado, y si estaba
abierto un aviso por cada vaivén de la cadena sería ruido.

**"Hilo transferido" solo si el hilo está abierto y activo (2026-09-24).** La baja mueve también
los cerrados (*Los hilos se mueven todos*, `bajas.md`), y ahí el aviso es solo por los abiertos.

**"Paso sumado" cuando lo suma cualquiera que no sea el responsable (2026-09-24).** La ficha decía
"un asignado"; el admin también suma pasos en hilos ajenos, y el responsable tiene que enterarse
igual.

**Los huérfanos se avisan al cierre de la transacción (2026-09-24).** Salir de un equipo apaga lo
delegado (`tareas_ver` incluido) en el BEFORE de `equipos_miembros`, antes de que
`tareas_cambio_de_equipo` entregue: avisando en el momento se avisaba por pasos que un instante
después pasaban al delegador. El trigger sobre `usuario_submodulos` es diferido; la baja avisa
después de entregar. "Hilos huérfanos" reemplaza el aviso anterior sobre la misma persona y
desaparece cuando ya no le quedan hilos abiertos.

**"Nunca al que hizo la acción" gana (2026-09-24).** El responsable que reabre un paso cuyo
asignado ya no puede recibir no recibe "paso a reasignar": el paso queda a su nombre y lo ve.

**`transferencia` lleva `{de, a}`, no `{anterior, nuevo}` (2026-09-24).** Es el vocabulario de
`GUIDE_ENTES.md` §2.8, que manda sobre la ficha. Lo emite `emitir_eventos_registro` con la columna
del dueño como segundo argumento: el próximo ente que se transfiera lo reusa.

**Pendiente: "paso a reasignar" al crear un paso desde plantillas o recurrencia.**
`tareas_al_crear` deja el paso en el responsable si el asignado no puede recibir, y el trigger de
después no ve el asignado original. Va con plantillas y recurrencia (`BACKLOG.md`).
