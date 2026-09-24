# Tareas — participación, equipos y quién escribe qué

Quién ve un hilo, qué es el equipo participante, el delegador, el admin y el agente IA, y qué columnas escribe cada uno.

**La unidad de visibilidad es el hilo, no el paso.** Quien ve un paso ve el hilo entero: sin
contexto el paso no se puede hacer bien. Ve el hilo quien participa (responsable o asignado de algún
paso), el que tiene `tareas_equipo` en un equipo participante, y `tareas_administrar`. "Completó un
paso" se sacó el 2026-09-24: un completado está congelado y sigue asignado; solo sumaba el caso
reabierto y reasignado a otro, y ese ya recibe "paso quitado".
Un miembro no ve los hilos de su equipo donde no participa: lo propio queda privado sin flag.
Consecuencia: lo que un participante no debe leer va en otro hilo.

**El equipo participa si participa cualquier miembro.** El delegador ve todo hilo cuyo `equipo_id`,
o el de alguno de sus pasos, es su equipo (*El equipo participante se guarda en el momento*). Incluye lo que
un miembro arma para sí. La vista Equipo filtra por miembro y por tipo (pedidos, al equipo, del
equipo). Lo asignado al equipo sin repartir lo ve solo el delegador, y mientras tanto él hace de
asignado: completa, pone en espera, agrega resultado.

**El delegador de tareas es el de usuarios.** `tareas_equipo` no es delegable,
y `tareas_equipo` y `usuarios_delegar` se exigen mutuamente. Así, una sola persona por equipo ve la
bandeja y recibe lo que dejan una baja, un cambio de equipo o una transferencia, y todo equipo con
delegador tiene quien reciba lo asignado "al equipo". Como ninguna de las dos se puede tener sola,
`designar_delegador` y `quitar_delegador` las mueven juntas; no es "marcar solo" en el panel, es el
mismo rol. Puede reasignar un paso abierto entre
miembros de su equipo, o desde el equipo a un miembro. Es una excepción por columna en el trigger, y
se avisa al responsable del hilo.

**Con `tareas_administrar` se asigna directo.** El admin del sistema no está en ningún equipo
(`US002`), así que sin esto todo lo suyo sería pedido; el paso nace `pendiente`. Ampliado el
2026-09-24: con `tareas_administrar` nunca se genera `solicitada` —ni al asignar, ni al reabrir, ni
al editar—; si no, cada edición del admin devolvía sus pasos a pedir. Avisos y firma, igual.
Precisado el 2026-09-24: sigue siendo un pedido (se calcula), solo que nace aceptado. El receptor
lo puede devolver como cualquier pedido aceptado; el aviso es "tarea asignada", solo al asignado
(no hay nada que decidir; el delegador lo ve en la bandeja). Pedir afuera exige `tareas_pedir`
también al admin: `tareas_administrar requiere tareas_pedir`, regla y no excepción en el trigger.

**Un solo asignado por paso, persona o equipo.** Dos personas = dos pasos: siempre claro quién
debe. Lo asignado al equipo lo reparte quien tiene `tareas_equipo`: sin `tareas_repartir` aparte
(2026-09-24), que la tenía siempre la misma persona y olvidarla dejaba la bandeja sin reparto.

**~~"Equipo participante" se calcula con la membresía actual~~** → *El equipo participante se guarda
en el momento*.

**El equipo participante se guarda en el momento (2026-09-24).** `tarea.equipo_id` = equipo del
asignado al asignar (o el equipo asignado); `hilo.equipo_id` = equipo del responsable al crear o
transferir. Equipo participante = esos `equipo_id`, sin `equipo_de()`. Con la membresía actual, quien
cambiaba de equipo se llevaba la historia: el delegador nuevo veía los hilos (también abiertos) del
equipo viejo, y el viejo dejaba de ver su propio trabajo. Baja, cambio de equipo y transferencia
reescriben la columna en lo abierto; lo cerrado conserva el equipo con que se hizo. La persona sigue
viendo lo suyo por participación.

**Quien pide y quien hace escriben columnas distintas, y completar es solo del asignado.**
Pedido del usuario: que nadie —persona o agente— cambie lo pedido y lo marque hecho. El contenido
es del responsable del hilo; estado, espera, resultado y notas, del asignado. `GRANT UPDATE` por
columna + trigger, como `validar_gestionar_tarea` en `master`.

**Reasignar avisa al que pierde el paso (2026-09-24).** El responsable puede reasignarse un paso
ajeno y completarlo: queda en `eventos` y `tareas_ediciones`, pero el asignado anterior no se
enteraba. Se descartó prohibirlo (Luis se enferma y Ana lo termina) y exigir motivo (fricción en
algo habitual). Vale igual para el delegador y el admin; no para la baja.

**Excepción: `tareas_administrar` puede editar y completar lo ajeno.** Lo exige *Siempre hay una
función que administra el módulo* (`decisiones/global/permisos.md`). Completar algo ajeno pide nota
obligatoria y queda firmado en `eventos`. Aplica igual si esa función la tiene un agente IA.

**A quién se asigna o se pide: `tareas_asignables()` (2026-09-24).** Devuelve el nombre de todo
usuario y equipo activo, a quien tenga `tareas_ver`: `usuarios_select` no deja ver otros equipos y
abrirla expondría email y teléfono. Por fila, `pedido` en lugar de "es de mi equipo": es lo que la
UI necesita, y para el admin (sin equipo, asigna directo) "de mi equipo" diría pedir siempre. Se
mide contra quien llama, que es el responsable al crear o reasignar; el delegador reparte dentro de
su equipo, donde nunca es pedido. `sql/116`.

**Los nombres de lo que se ve: `tareas_nombres()` (2026-09-24).** `usuarios_select` no deja ver
otros equipos y `tareas_asignables()` trae solo los activos: el responsable dado de baja de un
huérfano, o el autor de una nota que ya se fue, quedaban sin nombre. Devuelve id y nombre de quien
figura en hilos, pasos, notas, historial y plantillas que quien llama ve, con las reglas de sus
policies; mismo patrón que `notificaciones_actores()`. `sql/120`.

**El agente IA trabaja como persona.** Sin reglas propias; la base no distingue agente de persona
(`decisiones/usuarios.md`) y el usuario no quiere que lo haga por ahora.

