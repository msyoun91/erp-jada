# Plantillas

## Plantillas de sistema y privadas, tres tipos (`sql/053`)

Pedido de usuario, en dos fases acordadas: esta (plantillas completas, usadas a mano desde Tareas) y la de disparadores desde otros módulos, que está en `BACKLOG.md`.

**Dos alcances; la función nueva es la del pedido.** "Las plantillas de sistema son administradas por aquellos que tienen función plantillas de sistema": `tareas_plantillas_sistema`, submódulo-función de la vista `tareas_plantillas`. La privada la ve, modifica y usa solo su dueño. Backfill de la función a quien tenía la vista, que hasta acá administraba todas — mismo criterio que `sql/013`/`014`.

**El alcance no cambia después de crear.** `alcance` y `creado_por` quedan fuera del `GRANT UPDATE`: una privada no se vuelve de sistema ni cambia de dueño por PostgREST, y `puede_gestionar_plantilla` puede leer la fila vieja en el `WITH CHECK` sin tener que mirar la nueva.

**Tres tipos, y el de proyecto con hilos adentro** (elegido por el usuario frente a "proyecto + referencias a otras plantillas" y "proyecto + tareas sueltas"). Los hilos viven en `tareas_plantillas_hilos` y cada paso apunta al suyo: ni un texto de agrupación repetido en cada paso (un typo parte el hilo) ni plantillas anidadas (desactivar una rompería la que la contiene).

**Miembros y asignados de la plantilla son arrays**, no tablas: es configuración que se copia al usarla, no una relación viva. Lo que pudo cambiar desde que se guardó (usuario desactivado, ya no miembro) se revalida al usar.

**Quien use la plantilla es un asignado más.** En la base, `incluir_ejecutor` + `responsable_id` NULL; en el form, el valor `EJECUTOR` dentro de los mismos arrays, para que el picker sea el mismo de siempre. El mapeo es `pasoPlantillaDb()` en `types.ts` y lo llama la action: es representación, no regla.

**Guardar reemplaza los pasos.** Nada referencia a un paso de plantilla (usar copia), así que ids estables no compraban nada: `guardar_plantilla` desactiva lo activo e inserta lo nuevo, en una transacción. Antes eran dos a cuatro statements de `actions.ts` sin atomicidad y un diff por paso.

**Usar es `SECURITY INVOKER`: decide la RLS de quien la usa**, igual que si armara todo con los formularios (crear proyecto pide `tareas_proyectos_crear`, asignar a otro `tareas_asignar`, recibir ser miembro). Hacerla `DEFINER` obligaba a copiar esas reglas adentro. En la fase 2 el disparo automático sí va a necesitar que la autoridad sea la plantilla; se decide ahí.

**Si un asignado no puede recibir el paso, se descarta; si no queda nadie, el paso va a quien la usa con una nota.** Decisión del usuario (preguntado por el caso automático: "se crea para quien dispara"); se aplica igual al uso manual para que la regla sea una sola. Si quedan otros asignados no hay nota: el paso sigue en manos de alguien que la plantilla eligió. `usar_plantilla` devuelve cuántos cayeron y el toast lo dice. La vista previa de "Usar" muestra lo que la plantilla pide y explica la regla en texto — no calcula quién va a recibir, porque esa regla vive en la función.

**Vencimiento tras el paso anterior: una columna y dos triggers.** `tareas.vence_dias_tras_previo`; la fecha queda NULL hasta que el previo se completa y ahí la ponen los triggers — única fuente, `editar_tarea` no la pisa (corregido en la misma tanda: primero la sobrescribía con lo que el form traía oculto). Reabrir el previo la vuelve a NULL: el siguiente vuelve a estar bloqueado y un plazo corriendo sobre algo bloqueado mentiría. En el primer paso de una cadena vale como "desde la creación". Se ofrece también en "Crear siguiente paso", no solo en plantillas.

**Dos defectos latentes que las plantillas iban a pisar**, arreglados en la misma migración:

- *Siembra de asignados.* Crear una tarea con otro como responsable daba `42501` a quien tenía `tareas_asignar` sin `gestionar_ajenas` (`tareas_asignados_insert` pedía ser el responsable). Nadie lo sufría porque hoy la función solo la tiene quien tiene las dos. Se reprodujo en una transacción revertida antes de tocar nada. Salida: `es_siembra_tarea()`, el creador carga asignados mientras la tarea no tuvo **nunca** ninguno — "nunca" para no reabrir el hueco de `sql/013`.
- *`created_at` con `now()`.* Es el orden de los pasos en la Lista y `now()` es la hora de la transacción: la cadena que crea una función quedaba toda con el mismo instante (desde `sql/023`). Pasa a `clock_timestamp()`.

**UI.**

- **Asignados por buscador** (pedido): `SelectorUsuarios` — chips con ×, búsqueda y hasta seis sugerencias visibles sin foco (sin popover que abrir y cerrar); Enter agrega la primera en vez de mandar el form. Lo usan `AsignadosPicker` (nueva tarea, reasignar, pasos de plantilla) y los miembros de `ProyectoFormPanel` y de la plantilla de proyecto: misma pregunta, misma cara.
- `AsignadosPicker` nombra sus campos por prop (`pasos.2.asignados`) y suma "Quien la use" con `conEjecutor`.
- `Segmentado.tsx`: tercera copia del segmented de la Lista, extraída al módulo.
- La vista Plantillas monta `TareasContextoProvider` (el picker y el destino de "Usar" lo necesitan).
- El editor pliega cada paso en una línea de resumen y lo abre solo si tiene error. Cambiar de tipo reacomoda en vez de tirar: hilo → proyecto envuelve la cadena en un hilo, proyecto → hilo la aplana, → tarea conserva el primer paso y avisa.
- "Usar" de una plantilla de proyecto se deshabilita sin `tareas_proyectos_crear` y lo dice en texto (en touch no hay tooltip).

**Tests** (`sql/tests/`): `plantillas.sql` 22/22 (nuevo); `atomicidad_tareas.sql` 15/15 — los casos 09-13 pasaron a `usar_plantilla`: el 12 cambia de "rechazo" a "se descarta y queda ADMIN", y el 13 prueba que una cadena rechazada en el paso 2 no deja el 1, exigiendo `42501` (un `TA008` querría decir que falló antes de empezar); `atomicidad_edicion_tareas.sql` 18/18; `rls_miembros_asignables.sql` sin cambios de resultado con la siembra (en todos sus casos el creador es también responsable).
