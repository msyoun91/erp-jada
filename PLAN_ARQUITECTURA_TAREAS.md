# PLAN — Auditoría de arquitectura, módulo tareas

Estado: **1, 2, 4 y 5 hechos**; **3 descartado** (su premisa era falsa — ver ahí).
Pendientes: 6, 7 y 8.

Encontrado el 2026-08-26 durante la auditoría de diseño visual del módulo (esa tanda ya está hecha:
`decisiones/tareas.md` → "Jerarquía visual de la isla"). Son hallazgos de arquitectura, no de
diseño, y por eso no se mezclaron.

Antes de construir, verificar cada premisa contra el código: los números de línea son del 2026-08-26 y el
módulo se movió desde entonces — la tanda de 1 y 4 ya los movió otra vez.

**Para retomar después de un `/clear`:** leer este archivo y la sección de `decisiones/tareas.md` que cierra la
tanda anterior. Lo siguiente en la fila es el punto 6 (props que viajan juntas). Queda además
una verificación abierta del punto 1, anotada en `BACKLOG.md`.


1. ~~**Un UPDATE que RLS rechaza devuelve `success: true`.**~~ **HECHO.** `errorDeUpdate()` + `{ count: "exact" }` en todos los updates de fila puntual. Quedan sin conteo, a propósito, la cascada de `desactivarHilo` y —ya con guarda— el desactivar de `sincronizarAsignados`. Falta confirmar en el navegador que PostgREST mande `Content-Range` en el PATCH.
2. ~~**Escrituras multi-statement sin transacción → filas huérfanas.**~~ **HECHO.** Las seis (`crearTarea`, `crearProyecto`, `convertirTareaEnHilo`, `deshacerConversionHilo`, `desactivarHilo`, `agregarTareasDesdePlantilla`) son funciones `SECURITY INVOKER` en `sql/023`, llamadas con `.rpc()`. Verificado con `sql/tests/atomicidad_tareas.sql` (15/15). Ver `decisiones/tareas.md` → "Las escrituras multi-tabla bajan a Postgres". Quedan fuera `editarTarea` y `editarProyecto`, que también son multi-statement pero no producen huérfanas — anotadas en `BACKLOG.md`.
3. ~~**La no-atomicidad se filtró a una policy de RLS.**~~ **DESCARTADO — la premisa era falsa.** La rama de siembra `es_creador_proyecto(...) AND NOT proyecto_tiene_miembros(...)` (`sql/013:258`) no existe por los dos statements desde TS: existe porque insertar los miembros es inevitablemente un statement posterior al del proyecto, dentro de la misma transacción o no. En `crear_proyecto()` la policy se evalúa igual, con el proyecto ya insertado y todavía sin miembros — exactamente el estado que la rama contempla. Sacarla exigiría `SECURITY DEFINER`, que es mover la autorización adentro de la función y sacarla de las policies. Se queda.
4. ~~**Nueve actions sin `safeParse`**~~ **HECHO.** Las nueve más `listarNotasTarea` y `listarNotasHilo`. Schemas nuevos en `types.ts`: `uuidSchema`, `cambiarEstadoTareaSchema`, `asociarTareaHiloSchema`, `temperaturaSchema`.
5. ~~**N+1 en Plantillas.**~~ **HECHO.** `getPlantillaItems(plantillaId)` pasa a `getItemsPorPlantilla()`: una query agrupada por `plantilla_id`, como `getMiembrosPorProyecto`. La RLS de items es plana (`tiene_permiso('tareas_plantillas')`), así que la query única devuelve la misma unión que las N. Ver `decisiones/tareas.md` → "Los items de todas las plantillas llegan en una query".
6. **Seis props viajan juntas por 12 archivos** (`usuarios`, `proyectos`, `miembrosPorProyecto`, `usuarioActualId`, `gestionarAjenas`, `puedeAsignar`). `Bloqueadas` en `MisionView` recibe 9 props de las que no usa 6.
7. **`ESTADO_LABEL` / `ESTADO_BADGE` tipados `Record<string, string>`** (`tareaLabels.ts:7`, `:14`): cualquier string compila y devuelve `string`, no `string | undefined`. El enum existe: `Database["public"]["Enums"]["estado_tarea"]`.
8. **`cadenaPasos.ts` no tiene test** — decide `bloqueada` y `posicion/total`, es la lógica pura más riesgosa del módulo. `relacion.ts` y `proyectoTareas.ts`, las dos más simples, sí lo tienen.
