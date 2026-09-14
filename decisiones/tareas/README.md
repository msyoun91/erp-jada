# Decisiones — módulo tareas

Índice. Leer este archivo y después **solo** los archivos del tema que toca la tarea. Ordenado por
tema, no por fecha; `construccion-inicial.md` es el único cronológico (la construcción del módulo,
2026-08) y se abre solo si la tarea toca algo que nombran sus secciones. Lo superado está tachado
con el puntero a lo que lo reemplaza.

---

## `visibilidad.md`

Quién ve y quién toca: los tres ejes (`tareas_gestionar_ajenas`, membresía del proyecto, `tareas_asignar`), el creador sin visibilidad, miembros de proyecto.

- Ser creador deja de dar visibilidad (`sql/013`)
- La visibilidad de una tarea con hilo deja de mostrarse
- Miembros de proyecto = quién puede recibir tareas (`sql/009`)
- Miembros de proyecto = función propia del módulo (`tareas_proyectos_miembros`)
- El selector de usuario se oculta sin la función
- Ver miembros exige proyecto activo (`sql/016`)
- Asignar usuarios a una tarea es una función (`sql/014`)
- Nombrar responsable de un hilo = `tareas_asignar` (`sql/015`)
- No se ofrece crear trabajo donde no podés trabajar

## `hilos-pasos.md`

Hilos, pasos encadenados (`sql/017`), isla compartida, panel de proyecto y edición de hilos y plantillas.

- Pasos de tarea y vista Misión (`sql/017`)
- Las plantillas generan una cadena
- Verificación con RLS real (`sql/tests/pasos_tarea.sql`, bloque 2)
- Desactivar un hilo se lleva sus tareas (sin SQL)
- Isla compartida, panel de proyecto y edición de hilo
- Editar hilo incluye la visibilidad
- Editar plantillas (sin SQL)
- Los items de todas las plantillas llegan en una query (sin SQL)

## `plantillas.md`

Plantillas de sistema y privadas, tres tipos (`sql/053`), y disparadas por el estado de un registro de otro módulo (`sql/055`).

- Plantillas de sistema y privadas, tres tipos (`sql/053`)
- Plantillas disparadas por estado (`sql/055`)

## `escrituras-postgres.md`

Escrituras y ediciones multi-tabla como funciones SQL (`sql/023`–`024`) y la cascada al archivar un proyecto (`sql/025`).

- Las escrituras multi-tabla bajan a Postgres
- Las ediciones multi-tabla siguen el mismo camino (`sql/024`)
- Archivar un proyecto se lleva lo que hay adentro (`sql/025`)

## `integracion.md`

Tareas generadas por otros módulos (`origen_app` / `origen_punto`) y deep link desde la notificación.

- Tareas generadas por otro módulo = `origen_app` + `origen_punto` (sin SQL)
- Deep link a una tarea desde la notificación (sin SQL)

## `vista-lista.md`

La vista Lista: de quién es el trabajo, filtros, arrastre, temperatura en tres niveles, descripción y plazo en la isla.

- La vista Lista es de tareas, el hilo agrupa (sin SQL) — `relacion.ts` — fuente única de "de quién es este trabajo" · Filtro: segmented control Míos / Involucrado / Todos · Arrastre: umbrales deduplicados y estado optimista extraído · Efecto colateral aceptado
- Cierre de la auditoría de UI (Lista, plantillas, Misión)
- Temperatura — De slider a tres niveles (sin SQL)
- Descripción y plazo en la isla (del prototipo `obras-tareas.html`, sin SQL)

## `vista-mision.md`

UI de pasos y la vista Misión.

- UI de pasos y vista Misión
- Retoques de UI de Misión

## `auditorias-ui.md`

Auditorías de UI del módulo: pasos previos, feedback y formularios, jerarquía visual de la isla.

- Pasos previos legibles
- Feedback y formularios
- Jerarquía visual de la isla (auditoría de diseño, sin SQL)

## `tutorial.md`

Tutorial guiado por vista (`sql/019`).

- El código del paso es también su selector
- Un paso sin ancla se saltea y queda sin ver
- Persistencia en Postgres, no en `localStorage`
- Un solo componente en el layout, no uno por vista
- El ancla de los tabs sale de la prop que ya existía
- Foco por sombra, no por recorte
- El guion explica lo que no se ve, no lo que se lee

## `codigo.md`

Código: UPDATE rechazado en `actions.ts`, Context de la UI, etiquetas atadas al enum, tests de lógica pura.

- Robustez de `actions.ts` — Un UPDATE rechazado deja de devolver `success` (sin SQL)
- Contexto de la UI del módulo — Las seis props compartidas pasan a un Context (sin SQL)
- Tipos y tests de la lógica pura — Las etiquetas de estado se atan al enum (sin SQL) · `cadenaPasos.ts` tiene test

## `construccion-inicial.md`

Historia (2026-08): UI inicial, retoques contra la spec, notas (`sql/008`), panel de proyecto, fixes de UI.

- UI del módulo (Lista, Proyectos, Plantillas, Auditoría)
- Retoques contra la spec funcional (`resumen-todo-app-erp.md`)
- Notas, panel de proyecto, "Mis tareas", islas (`sql/008`)
- Fixes de UI pedidos (editar tarea, presets, conversión, notas)
