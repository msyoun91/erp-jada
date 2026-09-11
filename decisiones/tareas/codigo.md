# Código del módulo: `actions.ts`, contexto, tipos y tests

## Robustez de `actions.ts`

### Un UPDATE rechazado deja de devolver `success` (sin SQL)

Auditoría de arquitectura, primera tanda (`obsoletos/PLAN_ARQUITECTURA_TAREAS.md`, puntos 1 y 4).

**Un UPDATE que RLS rechaza no tira error: afecta 0 filas y vuelve limpio.** Los 26 `.update()` del módulo miraban solo `error`, así que editar una tarea sin permiso mostraba el toast de éxito, cerraba el panel y dejaba la fila intacta — el peor modo de falla posible, porque el usuario no tiene motivo para dudar. Ahora los updates que apuntan a filas puntuales van con `{ count: "exact" }` y pasan por `errorDeUpdate()`, que devuelve mensaje si hubo error **o** si `count === 0`.

**Dónde no se aplica, a propósito:** la cascada de `desactivarHilo` sobre `tareas` (`.eq("hilo_id", …)`) — un hilo sin tareas afecta 0 filas y es correcto. En `sincronizarAsignados` el desactivar pasó a estar guardado por `previos.length > 0`: con esa guarda 0 filas ya no es ambiguo, y de paso deja de emitirse un statement que no tenía nada que desactivar.

**`sincronizarAsignados` devuelve mensaje, no `PostgrestError`.** Sus dos callers hacían `mensajeError(...)` sobre lo que devolvía; ahora el mapeo vive en un solo lado y la función puede reportar tanto un error de Supabase como el conteo en cero, que no es un `PostgrestError`.

**Las 9 actions que no validaban ahora lo hacen** (`convertirTareaEnHilo`, `desactivarProyecto`, `desactivarPlantilla`, `cambiarEstadoTarea`, `desactivarHilo`, `desactivarTarea`, `asociarTareaHilo`, `desasociarTareaHilo`, `actualizarTemperatura`), más `listarNotasTarea` y `listarNotasHilo`, que son lecturas pero también son `"use server"` invocables por RPC. Schemas nuevos en `types.ts`: `uuidSchema`, `cambiarEstadoTareaSchema`, `asociarTareaHiloSchema`, `temperaturaSchema`. Las firmas no cambian — reciben ids sueltos y se parsean adentro; convertirlas a objetos habría tocado 12 componentes sin ganar nada. La validación manual de `actualizarTemperatura` pasa a un `.refine()` con el mismo mensaje, para que la regla viva donde viven las demás.

---

## Contexto de la UI del módulo

### Las seis props compartidas pasan a un Context (sin SQL)

Auditoría de arquitectura, punto 6 de `obsoletos/PLAN_ARQUITECTURA_TAREAS.md`.

`usuarios`, `proyectos`, `miembrosPorProyecto`, `usuarioActualId`, `gestionarAjenas` y `puedeAsignar` viajaban idénticas por 16 componentes: ~149 atributos JSX de puro reenvío, y `Bloqueadas` en `MisionView` recibía nueve props para usar tres. Ninguna se transformaba en el camino — se verificó que los 149 reenvíos fueran `x={x}` literal antes de tocar nada.

Ahora las arma la page (server) y las entrega `TareasContextoProvider`; cada componente pide con `useTareasContexto()` solo lo que usa, y eso queda visible en la primera línea de su cuerpo. Neto: −367 líneas, +91.

**Por qué Context y no un solo prop objeto.** Agrupar las seis en `ctx` bajaba los 149 reenvíos a ~30 pero dejaba el drilling intacto: las hojas que usan dos de las seis seguían recibiendo el paquete entero, y agregar un séptimo dato seguía tocando la cadena. El Context es la primera capa nueva del módulo, y se paga sola: son datos de solo lectura que la page arma una vez por request y que **toda** la UI necesita.

**No es estado.** El provider recibe el valor ya calculado en el server y no lo muta: se renueva con el `revalidatePath`, igual que antes. Por eso no hay `useState` ni memo adentro — un objeto nuevo por render del server es exactamente lo que se quiere.

**`ReasignarPanel` pierde su `puedeAsignar` forzado.** Pasaba `puedeAsignar` literal a `AsignadosPicker`; ahora el picker lo lee del contexto. Da lo mismo: el panel entero **es** la función `tareas_asignar` — `TareaDetailPanel` no ofrece "Reasignar" sin ella, así que el valor del contexto ya es `true` cuando el panel existe.

**Límite:** los componentes del módulo solo renderizan dentro del provider. Hoy los únicos que los montan son las tres pages (`/tareas`, `/tareas/mision`, `/tareas/proyectos`); el hook tira error explícito si alguien los usa afuera, en vez de dibujar una lista de usuarios vacía.

---

## Tipos y tests de la lógica pura

### Las etiquetas de estado se atan al enum (sin SQL)

Auditoría de arquitectura, punto 7 de `obsoletos/PLAN_ARQUITECTURA_TAREAS.md`.

`ESTADO_LABEL` y `ESTADO_BADGE` eran `Record<string, string>`: cualquier string indexaba y el resultado era `string`, no `string | undefined`. Un typo o un valor nuevo del enum se renderizaba vacío sin que TS dijera nada. Ahora son `Record<EstadoTarea, string>`, con `EstadoTarea = Enums<"estado_tarea">` en `types.ts`. Agregar un valor a `estado_tarea` en Postgres rompe la compilación hasta que los dos mapas tengan su fila, que es el punto.

**Arrastre.** `TareaPendiente.estado` y la prop `estado` de `TareaDetailPanel` estaban tipadas `string` a mano sobre datos que ya venían del enum; bajaron a `EstadoTarea`, y el `?? p.estado` de `AuditoriaView` —un fallback que nunca podía dispararse— se fue con ellas. `RECURRENCIA_LABEL` y el parámetro `estado` de `estadoVencimiento` entraron por el mismo defecto, en el mismo archivo.

### `cadenaPasos.ts` tiene test

Punto 8. Once casos con `node --test`, mismo criterio que `relacion.test.ts` (sin runner ni dependencias nuevas).

Cubre lo que decide: `bloqueada` mira el paso previo inmediato y no el arranque de la cadena, `cancelada` no desbloquea al siguiente, una raíz cuyo `paso_anterior_id` no está en la lista visible arranca bloqueada, el orden de entrada no cambia la cadena, los pasos comparten el array `cadena` por referencia, y `agruparCadenas` deja cada cadena contigua sin repetir ni inventar filas.

**El ciclo no llega a recorrerse.** El test de datos cíclicos afirma que el mapa vuelve vacío, no que el `Set` de vistos frene el recorrido: como `siguiente` tiene una sola entrada por `paso_anterior_id`, un ciclo nunca es alcanzable desde una raíz — ninguno de sus miembros es raíz y la cadena entera queda afuera. La guarda del `for` sigue siendo barata y se queda, pero no es lo que evita el cuelgue.
