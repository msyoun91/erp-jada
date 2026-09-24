# Tareas — cómo se escriben las reglas

Decisiones de implementación de `sql/113` que no salen de la ficha. Índice y ficha: `README.md`.

**Las reglas de actor valen para lo que escribe una persona; lo que escribe la base en cascada, no
(2026-09-24).** Directo = `pg_trigger_depth() = 1` y `auth.uid()` presente, por PostgREST o por una
función INVOKER. Reabrir el siguiente, el plazo relativo o mover pasos al transferir corren a
profundidad 2 y solo respetan invariantes: si no, la cascada de un asignado fallaba por tocar pasos
ajenos. Mismo criterio que `current_user = 'authenticated'` en `master` (`sql/080`), que no sirve
con triggers DEFINER.
Archivos: `sql/113` (todos los triggers).

**Desactivar y transferir van por funciones DEFINER (2026-09-24).** Postgres pasa la fila nueva de
un UPDATE por la policy de SELECT: desactivar o transferir algo que después no ves fallaba con
42501. Las funciones solo hacen el UPDATE; quién puede lo sigue decidiendo el trigger. El lint 0029
de esas tres es esperado.
Archivos: `sql/113` → `tareas_desactivar_paso`, `tareas_desactivar_hilo`, `tareas_transferir_hilo`.

**La cascada no exige `tareas_pedir` (2026-09-24).** Reabrir un paso reabre sus siguientes
completados, y los que son pedidos vuelven a `solicitada` aunque quien reabrió no tenga el permiso:
no es un pedido nuevo. Si no, un asignado sin el permiso no podía reabrir lo suyo. Reabrir directo
un pedido ajeno sí lo exige (*Sin `tareas_pedir`…*, `pedidos.md`).

**Desactivar un hilo no toca sus pasos (2026-09-24).** Los esconde la visibilidad, que pide el hilo
activo, y reactivarlo devuelve todo como estaba. Marcar los pasos obligaba a distinguir, al
reactivar, los que se desactivaron con el hilo de los que ya estaban desactivados. Reactivar un
hilo no revisa si sus asignados todavía pueden recibir: lo que quedó huérfano lo muestra Todas.

**Reabrir cambia solo el estado, y el asignado reabre solo lo que completó (2026-09-24).** Editar
o reasignar va en la escritura siguiente: así el estado al reabrir sale de una sola regla. Lo
cancelado lo decidió el responsable; reabrirlo es suyo o del admin.

**No se completa un pedido sin aceptarlo (2026-09-24).** `solicitada → completada` no existe: son
dos pasos, así el evento de aceptar queda.

**Transferir "afuera" se mide contra el `equipo_id` guardado del hilo (2026-09-24).** No contra el
equipo actual del responsable: quien cambió de equipo sigue llevando el hilo del anterior hasta
que se mueva, y entregarlo al delegador de ese equipo no es transferir afuera. Los pasos del equipo
de origen se mueven solo si el hilo tenía equipo.

**Con plazo en días, `vence` lo calcula la base (2026-09-24).** Escribirlo a mano falla; cambiar
`vence_dias` lo recalcula desde hoy si el paso está habilitado. La base no guarda cuándo se
habilitó.

**El previo se cambia solo para *Insertar antes de*, y se verifica por la forma (2026-09-24).** El
nuevo previo no existe todavía al apuntarlo y, al cierre de la transacción, es un paso creado en
ella que tomó el previo viejo. Sin flags ni variables de sesión.

**La nota obligatoria del admin es una nota suya en ese paso, en la misma transacción
(2026-09-24).** `tareas_completar_con_nota` hace las dos cosas; el trigger la busca por
`created_at >= now()`.

**`tareas_ediciones` guarda lo que edita una persona (2026-09-24).** Título, descripción,
prioridad y vencimientos del paso; título y recurrencia del hilo. El vencimiento derivado y el
equipo que mueve la base no son ediciones; el resultado se escribe al completar y queda congelado.
