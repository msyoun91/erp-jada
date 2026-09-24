# Tareas — bajas, cambios de equipo, transferencias y huérfanos

A quién va el trabajo cuando alguien se va, cambia de equipo, pierde `tareas_ver` o se transfiere un hilo.

**Solo se asigna a quien puede recibirlo.** Asignar, pedir, repartir, reasignar y transferir el
hilo (sumado el 2026-09-24: sin eso nacía un responsable que no ve su hilo) exigen en la base
que la persona esté activa y tenga `tareas_ver`, y que el equipo tenga delegador activo (el único
con `tareas_equipo`); si no, el paso queda invisible o sin quien lo decida. El selector ofrece solo a
quien cumple. Si el receptor pierde `tareas_ver` después, sus pasos quedan huérfanos y se avisa al
responsable (*Sin destino, queda huérfano*); si lo recupera, vuelve a verlos.

**La baja de un usuario pasa sus pasos abiertos y sus hilos al delegador de su equipo.** El
delegador de usuarios (`usuarios_delegar`), que es uno solo; si el que se va es el delegador, a su
heredero. Sin delegador, o si es independiente, no se mueve nada (*Sin destino, queda huérfano*). Para que el
destino cumpla *Solo se asigna a quien puede recibirlo*, el delegador tiene que tener `tareas_ver`
(decisión del usuario). Trigger de tareas
sobre `usuarios.activo`; completados y cancelados no se tocan (son registro).

**Los hilos se mueven todos, abiertos y cerrados (2026-09-24).** En la baja y en el cambio de
equipo. Un hilo cerrado se reabre cuando un asignado reabre o suma un paso, y quedaba con un
responsable inactivo (nadie lo gestiona, la recurrencia no nace) o de otro equipo (vuelve a tener
trabajo abierto del anterior). `responsable_id` es quién lo gestiona hoy; quién lo gestionó, en
`eventos`. Los pasos cerrados no se tocan. Aviso solo por los abiertos; el filtro "huérfanos"
muestra solo hilos abiertos.

**Quien cambia de equipo entrega todo lo abierto al anterior (2026-09-24).** Sus hilos y todos sus
pasos abiertos —también los pedidos de otros equipos que aceptó— pasan al delegador del equipo
anterior, como en la baja. Lo que aceptó lo aceptó como miembro de ese equipo: es compromiso del
equipo, no de la persona, y quien cambia no sigue lo del equipo anterior. Así tampoco importa que al
cambiar pierda lo delegado (`tareas_ver` incluido): no le queda nada abierto. Trigger de tareas
sobre `equipos_miembros`. Quien entra desde independiente no entrega nada (no hay anterior), pero lo
abierto suyo —hilos que lleva, pasos asignados— toma `equipo_id` = el equipo nuevo; si no, el
delegador nuevo no veía el trabajo en curso. Lo cerrado queda `NULL` (2026-09-24).

**Sin destino, queda huérfano (2026-09-24).** Si el equipo no tiene delegador (se creó sin
designarlo, o salió sin heredero) o la persona es independiente, la baja y el cambio de equipo no
mueven nada: hilos y pasos quedan con ella. Todas suma el filtro "huérfanos" (responsable o
asignado inactivo o sin `tareas_ver`) y el admin transfiere desde ahí. Perder `tareas_ver` a mano
también deja huérfano, sin mover nada. El responsable de cada hilo con un paso huérfano recibe aviso: puede reasignarlo él sin esperar al admin. Un hilo huérfano no tiene a quién avisar, así que
avisa a quienes tienen `tareas_administrar`: uno agrupado por hecho, no uno por hilo (2026-09-24). Se descartó exigir
delegador en todo equipo: tocaba `usuarios` y la baja del último miembro activo seguía sin destino
—bloquearla no sirve, a un despedido se lo banea en el acto—.

**Transferir un hilo a otro equipo lo entrega al delegador de ese equipo.** El responsable pasa a
ser el delegador del equipo destino, y los pasos abiertos con `equipo_id` = equipo de origen
—personas y el equipo mismo; precisado el 2026-09-24, antes quedaba afuera lo asignado "al
equipo" sin repartir— pasan también a él para que los reparta o los vuelva a pedir. Los pasos de terceros equipos no
cambian. Exige `tareas_pedir` y es inmediata, sin aceptación: el delegador recibe el aviso. A un
independiente, las mismas reglas con él como destino.

**El destino se mide contra el `equipo_id` guardado de cada fila, no contra el equipo actual
(2026-09-24).** Cada hilo y cada paso abierto va al delegador de su propio `equipo_id`: es el equipo
del que es el compromiso. Así lo que quedó huérfano de un equipo anterior (salió cuando no tenía
delegador) llega a ese equipo si hoy lo tiene, y baja y cambio de equipo son una sola función. Un
hilo cerrado sin equipo (de cuando era independiente) no tiene destino: queda con él.
Archivos: `sql/114` → `tareas_entregar`, `tareas_usuario_baja`, `tareas_cambio_de_equipo`.
