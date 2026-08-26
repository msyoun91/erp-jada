# PLAN — Auditoría de arquitectura, módulo tareas

Estado: **1 y 4 hechos** — ver `DECISIONES.md` → "un UPDATE rechazado deja de devolver `success`".
Pendientes: 2, 3, 5, 6, 7 y 8.

Encontrado el 2026-08-26 durante la auditoría de diseño visual del módulo (esa tanda ya está hecha:
`DECISIONES.md` → "Módulo tareas — jerarquía visual de la isla"). Son hallazgos de arquitectura, no de
diseño, y por eso no se mezclaron.

Antes de construir, verificar cada premisa contra el código: los números de línea son del 2026-08-26 y el
módulo se movió desde entonces — la tanda de 1 y 4 ya los movió otra vez.

**Para retomar después de un `/clear`:** leer este archivo y la sección de `DECISIONES.md` que cierra la
tanda anterior. Lo siguiente en la fila es el punto 2 (transacciones), que arrastra al 3. Queda además
una verificación abierta del punto 1, anotada ahí mismo.


1. ~~**Un UPDATE que RLS rechaza devuelve `success: true`.**~~ **HECHO.** `errorDeUpdate()` + `{ count: "exact" }` en todos los updates de fila puntual. Quedan sin conteo, a propósito, la cascada de `desactivarHilo` y —ya con guarda— el desactivar de `sincronizarAsignados`. Falta confirmar en el navegador que PostgREST mande `Content-Range` en el PATCH.
2. **Escrituras multi-statement sin transacción → filas huérfanas.** `crearTarea:100` deja una tarea `activo = true` invisible para todos si falla el insert de asignados (`tareas_select` no mira `creado_por`, sql/013:49). Igual en `crearProyecto:296`, `convertirTareaEnHilo:192`, `deshacerConversionHilo:236`, `desactivarHilo:650`, `agregarTareasDesdePlantilla:485`. `DECISIONES.md` ya lo registra como deuda, pero sin el modo de falla y sin incluir `crearTarea` ni `crearProyecto`.
3. **La no-atomicidad se filtró a una policy de RLS.** `sql/013:258` tiene la rama de siembra `es_creador_proyecto(...) AND NOT proyecto_tiene_miembros(...)` más su función `SECURITY DEFINER`, que existen solo porque crear un proyecto son dos statements desde TS.
4. ~~**Nueve actions sin `safeParse`**~~ **HECHO.** Las nueve más `listarNotasTarea` y `listarNotasHilo`. Schemas nuevos en `types.ts`: `uuidSchema`, `cambiarEstadoTareaSchema`, `asociarTareaHiloSchema`, `temperaturaSchema`.
5. **N+1 en Plantillas.** `app/(erp-app)/tareas/plantillas/page.tsx` llama `getPlantillaItems(p.id)` por plantilla; el módulo ya decidió lo contrario en `getMiembrosPorProyecto`.
6. **Seis props viajan juntas por 12 archivos** (`usuarios`, `proyectos`, `miembrosPorProyecto`, `usuarioActualId`, `gestionarAjenas`, `puedeAsignar`). `Bloqueadas` en `MisionView` recibe 9 props de las que no usa 6.
7. **`ESTADO_LABEL` / `ESTADO_BADGE` tipados `Record<string, string>`** (`tareaLabels.ts:7`, `:14`): cualquier string compila y devuelve `string`, no `string | undefined`. El enum existe: `Database["public"]["Enums"]["estado_tarea"]`.
8. **`cadenaPasos.ts` no tiene test** — decide `bloqueada` y `posicion/total`, es la lógica pura más riesgosa del módulo. `relacion.ts` y `proyectoTareas.ts`, las dos más simples, sí lo tienen.
