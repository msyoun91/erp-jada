# Hilos, pasos y cadenas

## Pasos de tarea y vista Misión (`sql/017`)

Pedido: botón "crear siguiente paso" además de "crear tarea", ver los pasos previos al abrir una tarea, y una vista Misión que muestre la tarea actual de a una ordenada por temperatura.

**Pasos ≠ hilo.** El hilo agrupa tareas que corren en paralelo; la cadena de pasos las ordena. Son ejes ortogonales, así que un hilo puede tener tareas sueltas y cadenas al mismo tiempo. Riesgo asumido: dos formas de relacionar tareas en el mismo módulo. Se mitiga en UI — dentro del hilo la cadena se renderiza como cadena (1→2→3), no como filas planas mezcladas con las paralelas.

**Una columna, no una tabla.** `tareas.paso_anterior_id`. La regla es "se puede hacer si se cumple **el** previo" — un solo predecesor, cadena lineal. Una tabla `tareas_dependencias` sería un DAG genérico para un problema que no existe.

**La cadena vive dentro de un hilo** (`CHECK paso_anterior_id IS NULL OR hilo_id IS NOT NULL` + trigger de mismo `hilo_id`). Esta es la decisión que más ahorró: `tareas_select` ya cascadea visibilidad por `puede_ver_hilo`, así que "ver los pasos previos" no necesitó **ninguna** regla de visibilidad nueva. Encadenar tareas sueltas hubiera obligado a una función `SECURITY DEFINER` que devolviera stubs de los pasos invisibles, o a una UI que miente ("Paso 3 de 5" con 2 pasos que no se ven). Costo aceptado: crear un siguiente paso desde una tarea suelta obliga a tener hilo.

**"Bloqueada" es derivado, no un estado.** `paso_anterior.estado <> 'completada'`. Sumarlo a `estado_tarea` obligaba a sincronizarlo en cada completar/cancelar/reabrir — la duplicación de lógica que prohíbe la regla. La barrera de servidor es el trigger `validar_paso_previo` (`TA004`), no el enum.

**`cancelada` no bloquea.** El trigger solo corta el paso a `en_progreso`/`completada`. Si un paso se cancela la cadena queda trabada, y cancelar los que siguen tiene que seguir siendo posible o el hilo no cierra nunca.

**Ciclos: imposibles por construcción, sin validación.** `paso_anterior_id` es inmutable después del INSERT (`TA005`), y una fila nueva nunca puede ser ancestro de otra → el grafo es siempre un bosque. Recorrer la cadena buscando ciclos hubiera sido código para un caso que la inmutabilidad ya cierra.

**Recurrencia + pasos: prohibido de los dos lados** (opción b, elegida por el usuario). CHECK del lado siguiente, trigger del lado previo. Una instancia recurrente nace al completar la anterior; un paso de una cadena no tiene "próxima instancia" que signifique algo. Consecuencia buscada: `generar_recurrencia` no necesitó tocarse, porque nunca dispara sobre una tarea encadenada.

**Desactivar un paso del medio se bloquea, no se relinkea** (`TA007`, mismo criterio que `validar_quitar_miembro`). Va `AFTER` y no `BEFORE`: `deshacerConversionHilo` desactiva la cadena entera en un solo `.in(...)`, y un `BEFORE` por fila la vería a medio desactivar según el orden. Los `AFTER ROW` corren al final de la sentencia, con todas las filas ya actualizadas — verificado: desactivar la cadena completa pasa, desactivar solo el del medio falla. El `DEFERRABLE INITIALLY DEFERRED` **no** es lo que resuelve ese caso (el `AFTER` solo ya alcanza); suma desmantelar una cadena en varias sentencias dentro de una transacción, que hoy ningún caller hace. Escape hatch de una cadena: desactivar desde la cola.

**Mover de hilo una tarea encadenada se bloquea** (`TA006`). Sin eso el invariante "misma cadena, mismo hilo" se rompe por la puerta de al lado. Efecto colateral aceptado: `deshacerConversionHilo` falla sobre un hilo cuya primera tarea es parte de una cadena — semánticamente correcto (un hilo multi-paso no se puede colapsar en una tarea suelta) y falla antes de tocar nada.

**Los triggers son `SECURITY DEFINER` aunque no llamen a `tiene_permiso()`.** Un guard que la RLS puede dejar ciego no es un guard: si el `EXISTS` del paso siguiente se filtrara por RLS, un usuario que no lo ve rompería la cadena sin que el trigger se entere.

**Misión es vista, sin función propia.** "Crear siguiente paso" es crear una tarea, y crear tareas ya lo gatea `tareas_lista` — una función nueva sería un permiso más fino sin necesidad demostrada. La vista no lee nada que la Lista no lea: reusa `getListaTareas()` (que ya corre `resolver_pospuestos`) y filtra en memoria a mis asignadas, `pendiente`/`en_progreso`, no bloqueadas; el orden sale de `useOrdenTemperatura`, sin query nueva. Backfill del submódulo a todo el que tenía `tareas_lista`, por el mismo motivo.

## Las plantillas generan una cadena

> **Sigue vigente para las plantillas de tipo hilo** (y los hilos de una de proyecto). `agregarTareasDesdePlantilla` pasó a ser `usar_plantilla` — ver *Plantillas de sistema y privadas, tres tipos*.

`agregarTareasDesdePlantilla` encadena los items en vez de crear N tareas sueltas: `paso_anterior_id` de cada uno apunta al anterior. `tareas_plantillas_items.orden` siempre significó "primero esto, después aquello" — hasta acá era una sugerencia visual sin consecuencia.

**Sin flag ni checkbox: la plantilla siempre encadena.** Una columna `encadenada` en `tareas_plantillas`, o un check en "usar plantilla", sería una opción que nadie pidió todavía. Si aparece un caso real de plantilla-checklist (items sin orden entre sí), se agrega ahí.

**Un solo INSERT multi-fila, no N inserts.** Depende de que el `BEFORE ROW` de `validar_paso_tarea` en la fila 2 vea la fila 1 de la **misma sentencia** — Postgres procesa las tuplas de a una y el trigger la encuentra. Verificado contra la base y fijado como caso 14 de `sql/tests/pasos_tarea.sql`, porque si esa semántica cambiara la plantilla tendría que insertar de a una fila (N round trips por PostgREST).

**No se puede armar la cadena en dos pasos** (insert plano + update de los `paso_anterior_id`): `paso_anterior_id` es inmutable en UPDATE, y aflojarlo a "NULL → valor" reabriría los ciclos (A sin previo, B con previo A, después A con previo B).

Copy: "Agregar tareas" pasó a "Agregar pasos", y tanto `UsarPlantillaPanel` como `PlantillaFormPanel` dicen que cada paso se habilita al completar el anterior — encadenar sin avisar convierte una plantilla conocida en algo que se comporta distinto.

## Verificación con RLS real (`sql/tests/pasos_tarea.sql`, bloque 2)

Los 14 casos de triggers corrían como `postgres`, que bypasea RLS: probaban los triggers pero no que un usuario común pudiera usar la feature. El bloque 2 cambia a rol `authenticated` con TESTER (sin `tareas_gestionar_ajenas` ni `tareas_asignar`) y verifica lo que faltaba. 5/5.

**La premisa del diseño quedó probada, no supuesta:** TESTER, asignado **solo** al paso 2, ve el paso 1 y la cadena entera — `puede_ver_hilo` cascadea. De eso dependía la decisión de no escribir ninguna regla de visibilidad nueva para los pasos. Si el caso 01 dejara de pasar, "ver las tareas previas" necesitaría una función `SECURITY DEFINER` que devuelva stubs y habría que replantear `sql/017`.

**Los casos de rechazo miran `ROW_COUNT`, no solo la excepción.** Un UPDATE denegado por RLS afecta 0 filas y no tira error: sin ese chequeo, "RLS se lo comió en silencio" se leería como "el trigger funcionó". Mismo problema que ya había motivado alinear los UPDATE con los SELECT en `sql/013`.

Un usuario común puede crear el siguiente paso y asignárselo sin ninguna función extra — confirma que `tareas_lista` alcanza y que no hacía falta un submódulo nuevo para "crear siguiente paso".

## Desactivar un hilo se lleva sus tareas (sin SQL)

`desactivarHilo` desactivaba solo `tareas_hilos`. Las tareas quedaban con
`activo = true` apuntando a un hilo que `getListaTareas` ya no trae, y la vista
Lista las perdía: no son sueltas (`hilo_id !== null`) y su grupo no existe.
RLS seguía devolviéndolas — el trabajo asignado desaparecía de la UI para
todos, incluido quien tiene `tareas_gestionar_ajenas`.

~~La cascada va en el action, no en un filtro defensivo de la vista~~ — **superado
por *Las escrituras multi-tabla bajan a Postgres***: la cascada vive en
`desactivar_hilo()` (`sql/023`) y ya no depende del orden de dos requests. Sigue
en pie lo demás: el estado "hilo inactivo con tareas activas" no debe existir, y
no se resuelve con un filtro defensivo de la vista.

No hace falta permiso extra: `tareas_update` ya tiene la rama del responsable
del hilo, que es exactamente quien puede desactivarlo (`tareas_hilos_update`).

## Isla compartida, panel de proyecto y edición de hilo

> **Revertida en parte** por *La vista Lista es de tareas, el hilo agrupa*: la Lista sí
> muestra tareas del hilo, pero solo las propias. Lo demás de esta sección sigue vigente.

Pedido de usuario, siete puntos (uno — qué pasa con las asignaciones al quitar un miembro — quedó salteado a pedido). Todo se resolvió en UI/TS: **cero SQL**. `tareas_hilos_update` y `tareas_proyectos_update` (`sql/005`) ya autorizan creador / responsable / `tareas_gestionar_ajenas`, que es exactamente quién puede modificar.

**Las tres entidades del módulo comparten cara: `Isla.tsx`.** Hilo, tarea y proyecto se ven igual en cualquier listado (título clickeable + badges + fila de métricas) y el click abre su panel derecho. La isla no tiene acciones propias — todo lo que se hace sobre la entidad vive en su panel. Eso obligó a partir `TareaRow` en dos:

- `TareaCard.tsx` — la isla. Conserva el estado optimista (`estadoLocal`/`tempLocal`) porque la isla los sigue mostrando con el panel cerrado, y porque el orden por temperatura de la vista se refresca mientras se arrastra el slider (`useOrdenTemperatura`). Bajan al panel por props: una sola fuente para el badge y el control.
- `TareaDetailPanel.tsx` — acciones, detalle y notas. "Modificar tarea" pasó del click en el título (que ahora abre el panel) al menú del panel.

`ProyectosView` dejó de ser una lista de filas con `OverflowMenu`: son islas (`ProyectoCard`) y las acciones — modificar, desactivar, agregar hilo/tarea — viven en `ProyectoDetailPanel`. Se conservan búsqueda y paginación.

Piezas compartidas que salieron de ahí: `MetricasResumen.tsx` (antigüedad + próximo vencimiento, antes inline en `HiloCard`), `tareaLabels.ts` (labels/badges de estado, recurrencia, `temperaturaRango`, `iniciales`) y `proyectoTareas.ts` (`tareasDeProyecto`: las tareas de un hilo no guardan `proyecto_id`, lo heredan — isla y panel tienen que contar lo mismo).

**`ProyectoFormPanel` es panel único de crear/modificar y absorbió `MiembrosPanel.tsx`** (borrado): los miembros son una característica más del proyecto, no una pantalla aparte. `gestionarMiembrosProyecto` → `editarProyecto` (mismo diff de quitados/agregados, ver `db_schema/tareas.md`). Esto y `MetricasResumen` se recuperaron del stash `9cc8e8e` que se había descartado el 2026-08-18 — el `sql/010` de ese stash **no** se tocó, sigue revertido.

**Editar hilo = solo título y descripción** (ampliado después con visibilidad — ver la sección "Editar hilo incluye la visibilidad" al final). `HiloFormPanel` gana modo edición con el mismo patrón que `TareaFormPanel`: el schema del form sigue siendo `crearHiloSchema` (superset) y proyecto/visibilidad/responsable viajan como defaults ocultos; `editarHiloSchema` (título + descripción + id) es lo que valida el server. Mover un hilo de proyecto queda fuera a propósito: cambiaría quiénes pueden trabajar en sus tareas y esa validación existe sobre `tareas` (`validar_proyecto_tarea`, `sql/009`), no sobre `tareas_hilos`.

**Dueño del hilo visible.** El "owner" es `responsable_id` (no `creado_por`): es quien responde por el hilo. Se muestra en la isla y en el panel; el nombre sale del array `usuarios` que ya llega por props, sin query nueva.

**Visibilidad pública por defecto al elegir proyecto.** Es *default*, no regla: el select sigue ahí y el usuario puede volver a privada. Aplica al abrir el form desde un proyecto y también al elegir proyecto dentro del form, salvo que el usuario ya haya tocado visibilidad (`dirtyFields.visibilidad`) — un default no pisa una decisión explícita. Editar una tarea existente no cambia su visibilidad.

**Filtro por usuario en Proyectos = membresía**, no "tiene tareas ahí": la membresía es quién trabaja en el proyecto (`visibilidad` es el otro eje, quién lo ve) y sale de `miembrosPorProyecto`, que ya llega por props — 0 queries nuevas. Arranca en el usuario actual, mismo default que la vista Lista.


## Editar hilo incluye la visibilidad

Corrige la sección "Módulo tareas — isla compartida…": ahí `visibilidad` quedó bloqueada **de arrastre**, en el mismo bloque que `proyecto_id`, pero el motivo registrado solo aplica al proyecto. Mover un hilo de proyecto cambia quiénes pueden trabajar en sus tareas y ningún trigger lo revalida sobre `tareas_hilos`; cambiar su visibilidad no toca la membresía, solo quién lo ve (`puede_ver_hilo` la lee directo). Con la regla más estricta de `sql/013`, un hilo creado privado no tenía forma de volverse compartible salvo recreándolo.

- `editarHiloSchema` = título + descripción + visibilidad + id. **`visibilidad` va sin `.default()`** ahí, a diferencia de `crearHiloSchema`: en un update, omitirla dejaría el hilo en `privado` sin que nadie lo pida.
- El select de visibilidad sale del bloque `{!hilo && …}` de `HiloFormPanel`. Proyecto y responsable siguen dentro (solo al crear).
- Sin SQL: `tareas_hilos_update` ya autoriza a responsable o `tareas_gestionar_ajenas`, que es el mismo set que muestra el botón "Modificar hilo" en `HiloDetailPanel`.
- Efecto en cascada, buscado: pasar un hilo a privado también esconde sus tareas de quien no esté asignado — `tareas_select` resuelve las tareas con hilo vía `puede_ver_hilo`.

## Editar plantillas (sin SQL)

> **Superada por *Plantillas de sistema y privadas, tres tipos* (`sql/053`).** La plantilla dejó de ser recurso de equipo (hay alcance), y guardar reemplaza los pasos enteros dentro de `guardar_plantilla` en vez del diff por paso de `actions.ts`. Sigue en pie que editar no toca lo ya generado.

`editarPlantilla` reusa el mismo `PlantillaFormPanel` con prop `plantilla` (mismo patrón que `TareaFormPanel` para editar tarea) y **no necesitó migración**: `tareas_plantillas_update` / `tareas_plantillas_items_update` ya existían en `sql/005` (gateadas solo por `tiene_permiso('tareas_plantillas')` — la plantilla es un recurso de equipo, no del creador), y los items ya tenían `activo` y `orden`.

**Un solo schema para crear y editar: `id` opcional en cada item.** `plantillaItemSchema` lleva `id?` — presente = paso que ya existe (se actualiza `titulo`/`orden`), ausente = paso nuevo (insert). Los items activos que no vuelven en el submit se desactivan (`activo = false`, nunca DELETE). `crearPlantilla` ignora el `id` porque ya mapeaba columna por columna.

**El `orden` sale de la posición en el form, no de un campo editable** — `items.map((item, i) => ({ ...item, orden: i }))` en el submit, ya era así al crear.

**Editar una plantilla no toca las tareas ya generadas.** `agregarTareasDesdePlantilla` copia los títulos, no referencia los items — así que no hay nada que propagar. El panel lo dice explícito en modo edición para que no se espere lo contrario.

**Un `update` por paso existente en vez de un upsert masivo** — son un puñado de pasos por plantilla; armar un upsert con todas las columnas para ahorrar round-trips no se paga.

## Los items de todas las plantillas llegan en una query (sin SQL)

> **Superada por *Plantillas de sistema y privadas, tres tipos*:** `getPlantillas()` trae ahora cada plantilla con sus hilos y pasos embebidos y `getItemsPorPlantilla` se borró. El criterio (una query, no N) es el mismo.

`getPlantillaItems(plantillaId)` se reemplaza por `getItemsPorPlantilla()`, que trae todos los items activos y los agrupa por `plantilla_id` — mismo patrón que `getMiembrosPorProyecto`. La página llamaba una query por plantilla dentro de un `Promise.all`: N requests para una vista que siempre los quiere todos.

**No cambia lo que ve cada usuario.** `tareas_plantillas_items_select` es plana (`tiene_permiso('tareas_plantillas')`, igual que la de `tareas_plantillas`): la query única devuelve exactamente la unión de las N. El mapa puede incluir items de plantillas desactivadas — `getPlantillas` solo trae las activas y la vista busca por id, así que nunca se leen.
