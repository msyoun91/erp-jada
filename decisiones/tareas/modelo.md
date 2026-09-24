# Tareas — hilo, paso y cadena

Qué es un hilo y un paso, sus estados, la cadena y cómo se abre, se cierra y se desactiva. Índice y ficha: `README.md`.

**Todo es un hilo; no hay tareas sueltas.** "Comprar silicona" nace hilo de un paso y crece sin
conversión. En `master` la tarea suelta que se "convertía en hilo" eran dos modelos y un pasaje.

**Hilo híbrido: `paso_anterior_id` opcional.** Sin previo = paralelo; con previo = cadena. Una
columna; obligar a encadenar todo inventaba orden donde no lo hay.

**El asignado puede sumar pasos para sí, en paralelo.** Sirve para subdividir su trabajo sin
pedírselo al responsable, que recibe el aviso. El contenido sigue siendo del responsable después de
creado. Corregido el 2026-09-24: eran "colgados del suyo", que los ponía después (bloqueados hasta
completar lo que querían subdividir) y bifurcaba la cadena si el suyo ya tenía siguiente. Sin
previo no bloquean nada y la cadena no se toca.

**Desactivar un hilo con pasos abiertos de otros se puede, y les avisa.** Solo si no tiene pasos
completados (2026-09-24, misma regla que el paso): desactivar es error de carga, y lo desactivado lo
ve solo el admin en Todas, que lo reactiva. Si ya hubo trabajo, "ya no va" es cancelar lo abierto y
cerrar con resultado: queda como registro. Atajo "Cancelar pendientes y cerrar", una función.

**`tarea` es ente, no solo `hilo`.** Se había propuesto sin ficha propia; no alcanza: completar es
el hecho central del registro y sin ente no llega a `eventos`, y otros módulos y la campanita
apuntan a un paso. Barato: dueño y visibilidad se heredan del hilo.

**Esperar es una fecha derivada, no un estado.** `espera_hasta` + motivo reemplaza a `en_espera` y
al posponer de `master`: la misma idea dos veces. Se deriva como "en espera", aparte de "bloqueada".

La espera se limpia cuando el paso deja de estar `pendiente` o cambia de asignado (2026-09-24):
si no, el nuevo asignado heredaba una espera ajena, un pedido vuelto a `solicitada` quedaba en
espera sin aceptarse y un reabierto volvía con fecha vieja. Trigger, sin estado nuevo.

**Resultado opcional**, en el paso y en el hilo.

**El hilo lo cierra el responsable, a mano (2026-09-24).** Cerrar pide el resultado y, si es
recurrente, si sigue; un cierre automático al terminar el último paso se saltaba las dos cosas.
Cuando no queda nada abierto, el hilo muestra "Todo completado — cerrar". Cerrado, se congela como
un paso completado: título y resultado se corrigen con nota o reabriendo.

**Reabrir un paso reabre en cascada sus siguientes completados (2026-09-24).** Elegido por el
usuario sobre "reabrir desde el final". Si no, lo que siguió quedaba completado sobre un previo en
corrección, y el siguiente abierto seguía habilitado. Recorre la cadena entera; los cancelados no
se reabren pero se atraviesan.

**Un cancelado es transparente en la cadena (2026-09-24).** "Bloqueada" mira el primer previo no
cancelado subiendo la cadena, y la cascada sigue de largo. Con Medir → Revisar (cancelado) →
Comprar, mirar solo el previo directo habilitaba Comprar con Medir pendiente, y la cascada se
frenaba en Revisar. `master` miraba solo el directo; `cancelada no traba` se trae con este ajuste. Cada asignado recibe "paso reabierto"; un pedido reabierto por otro vuelve a `solicitada`
(*Reabrir un pedido…*). Lo abierto más abajo queda bloqueado solo, por la regla de siempre.

**El plazo relativo corre desde que el paso se habilita (2026-09-24).** No desde que se completa
el previo: `sql/053` lo calculaba solo en `completada`, y con el cancelado transparente un paso cuyo
previo se cancelaba quedaba habilitado y sin vencimiento para siempre. Habilitarse = dejar de estar
bloqueada, por completarse o cancelarse el previo; volver a bloquearse (reabrir, insertar antes)
borra la fecha y se recalcula en la próxima habilitación. Se descartó contar desde el primer previo
completado: nacía vencido si ese se había completado hace un mes. El aviso "paso habilitado" sale
en el mismo momento.

**Insertar antes de: el único cambio de previo (2026-09-24).** Con el previo inmutable y un solo
siguiente por paso, no se podía meter un paso entre dos (Medir → Comprar, faltaba Revisar) ni
reemplazar uno del medio. Función en la base: crea el paso con el previo del siguiente y mueve el
previo del siguiente al nuevo, en una transacción; el trigger de inmutabilidad deja pasar solo eso.
Sin chequeo de ciclos (el nuevo no tiene descendientes). Solo el responsable del hilo, y antes de un
paso no completado (si no, se reabre primero). Si el siguiente estaba habilitado queda bloqueado y
su asignado recibe "paso bloqueado"; su vencimiento relativo se recalcula cuando se vuelva a
habilitar (*El plazo relativo corre desde que el paso se habilita*).
Reemplazar = cancelar (transparente) e insertar. Se descartó previo editable con chequeo de ciclos:
reordenar no apareció en ningún escenario.

**Solo se desactiva un paso no congelado (2026-09-24).** `solicitada`, `pendiente` o `rechazada`;
completado o cancelado, solo `tareas_administrar`. Desactivar es para un error de carga; cancelar es
decidir no hacerlo. Si no, el responsable borraba de la vista un trabajo que no puede editar. Para
sacar un completado, primero se reabre, y reabrir avisa al asignado.

**Abrir un paso es una sola regla: crear, reabrir (también en cascada), reactivar y copiar en la
recurrencia (2026-09-24).** Estado de nacimiento y chequeo de receptor: si el asignado no puede
recibir, queda en el responsable con "paso a reasignar". Si no, la cascada o la reactivación
abrían en silencio pasos de alguien que ya se fue. "Paso huérfano" queda para lo que pasa después:
la baja o la pérdida de permiso de quien ya lo tenía.

