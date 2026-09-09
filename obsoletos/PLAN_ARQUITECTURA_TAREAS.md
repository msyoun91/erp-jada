# PLAN — Auditoría de arquitectura, módulo tareas

Estado: **cerrada**. 1, 2, 4, 5, 6, 7 y 8 hechos; **3 descartado** (su premisa era falsa — ver ahí).
Queda solo una verificación en el navegador, anotada en `BACKLOG.md` (`Content-Range` en el PATCH).

Encontrado el 2026-08-26 durante la auditoría de diseño visual del módulo (esa tanda ya está hecha:
`decisiones/tareas.md` → "Jerarquía visual de la isla"). Son hallazgos de arquitectura, no de
diseño, y por eso no se mezclaron.

Antes de construir, verificar cada premisa contra el código: los números de línea son del 2026-08-26 y el
módulo se movió desde entonces — la tanda de 1 y 4 ya los movió otra vez.

El archivo se queda como mapa de la auditoría: cada punto apunta a dónde quedó escrita su decisión en
`decisiones/tareas.md`. No hay nada pendiente acá.


1. ~~**Un UPDATE que RLS rechaza devuelve `success: true`.**~~ **HECHO.** `errorDeUpdate()` + `{ count: "exact" }` en todos los updates de fila puntual. Quedan sin conteo, a propósito, la cascada de `desactivarHilo` y —ya con guarda— el desactivar de `sincronizarAsignados`. Falta confirmar en el navegador que PostgREST mande `Content-Range` en el PATCH.
2. ~~**Escrituras multi-statement sin transacción → filas huérfanas.**~~ **HECHO.** Las seis (`crearTarea`, `crearProyecto`, `convertirTareaEnHilo`, `deshacerConversionHilo`, `desactivarHilo`, `agregarTareasDesdePlantilla`) son funciones `SECURITY INVOKER` en `sql/023`, llamadas con `.rpc()`. Verificado con `sql/tests/atomicidad_tareas.sql` (15/15). Ver `decisiones/tareas.md` → "Las escrituras multi-tabla bajan a Postgres". La cola (`editarTarea`, `reasignarTarea`, `editarProyecto`, que son multi-statement pero dejan una fila inconsistente visible en vez de huérfana) bajó en `sql/024` con el mismo criterio, junto con `sincronizarAsignados` — ver `decisiones/tareas.md` → "Las ediciones multi-tabla siguen el mismo camino".
3. ~~**La no-atomicidad se filtró a una policy de RLS.**~~ **DESCARTADO — la premisa era falsa.** La rama de siembra `es_creador_proyecto(...) AND NOT proyecto_tiene_miembros(...)` (`sql/013:258`) no existe por los dos statements desde TS: existe porque insertar los miembros es inevitablemente un statement posterior al del proyecto, dentro de la misma transacción o no. En `crear_proyecto()` la policy se evalúa igual, con el proyecto ya insertado y todavía sin miembros — exactamente el estado que la rama contempla. Sacarla exigiría `SECURITY DEFINER`, que es mover la autorización adentro de la función y sacarla de las policies. Se queda.
4. ~~**Nueve actions sin `safeParse`**~~ **HECHO.** Las nueve más `listarNotasTarea` y `listarNotasHilo`. Schemas nuevos en `types.ts`: `uuidSchema`, `cambiarEstadoTareaSchema`, `asociarTareaHiloSchema`, `temperaturaSchema`.
5. ~~**N+1 en Plantillas.**~~ **HECHO.** `getPlantillaItems(plantillaId)` pasa a `getItemsPorPlantilla()`: una query agrupada por `plantilla_id`, como `getMiembrosPorProyecto`. La RLS de items es plana (`tiene_permiso('tareas_plantillas')`), así que la query única devuelve la misma unión que las N. Ver `decisiones/tareas.md` → "Los items de todas las plantillas llegan en una query".
6. ~~**Seis props viajan juntas por 12 archivos.**~~ **HECHO.** Eran 16 componentes y ~149 atributos JSX de reenvío, todos `x={x}` literal. Pasan a `TareasContextoProvider` + `useTareasContexto()` (`components/tareasContexto.tsx`), armado en las tres pages. `Bloqueadas` queda con 3 props. −367/+91 líneas. Ver `decisiones/tareas.md` → “Las seis props compartidas pasan a un Context”.
7. ~~**`ESTADO_LABEL` / `ESTADO_BADGE` tipados `Record<string, string>`.**~~ **HECHO.** Pasan a `Record<EstadoTarea, string>` con `EstadoTarea = Enums<"estado_tarea">` en `types.ts`. Arrastró `RECURRENCIA_LABEL`, `estadoVencimiento`, `TareaPendiente.estado` y la prop `estado` de `TareaDetailPanel`, todas tipadas `string` sobre datos que ya venían del enum. Ver `decisiones/tareas.md` → "Las etiquetas de estado se atan al enum".
8. ~~**`cadenaPasos.ts` no tiene test.**~~ **HECHO.** `components/cadenaPasos.test.ts`, 11 casos con `node --test` (11/11). Ver `decisiones/tareas.md` → "`cadenaPasos.ts` tiene test".
