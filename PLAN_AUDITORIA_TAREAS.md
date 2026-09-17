# Plan — cierre de la auditoría de tareas (2026-09-17)

Hallazgos numerados como en la auditoría. Regla transversal: **siempre hay una función que administra** — en tareas, `tareas_gestionar_ajenas`; toda restricción nueva la deja pasar (ver `decisiones/global/permisos.md`).

Decisiones del usuario: A (el administrador asigna a un no miembro → se lo suma al proyecto) sí · B y D se quedan en `tareas_asignar` · C (el administrador ve plantillas privadas ajenas, sin editarlas) sí · E (activaciones personales) sin cambio.

Cada fase: SQL en `sql/` corrido vía MCP → test en `sql/tests/` → tests existentes que toca → `db_schema/tareas.md` + decisiones → `npx tsc --noEmit`.

---

## Fase 1 — Dónde se puede escribir (`sql/076`)

- [x] 1 · Trigger en `tareas`: el hilo destino tiene que ser visible (o un hilo propio todavía vacío, para `convertir_tarea_en_hilo`).
- [x] 2 · Mismo trigger: el proyecto destino activo y visible. `tareas_hilos_insert` pide lo mismo; `tareas_hilos` pierde UPDATE de `proyecto_id`, `creado_por`, `id`, `created_at`.
- [x] 3 · `tareas_proyectos_miembros` insert/update: con `tareas_proyectos_miembros`, solo en proyectos donde es miembro; `tareas_gestionar_ajenas` en cualquiera.
- [x] A · El administrador asigna a un no miembro: `crear_tarea`, `sincronizar_asignados` y `validar_proyecto_tarea_miembros` lo suman al proyecto en vez de rechazar.
- [x] Test `sql/tests/auditoria_tareas.sql` (bloque F1) + `rls_miembros_asignables`, `rls_visibilidad_tareas`, `atomicidad_*`, `pasos_tarea`, `plantillas*`, `cascada_proyecto`.

Resultado: `auditoria_tareas` F1 17/17 · `atomicidad_tareas` 15/15 · `atomicidad_edicion_tareas` 18/18 · `rls_miembros_asignables` 24/24 · `rls_visibilidad_tareas` 18/18. `cascada_proyecto`, `pasos_tarea` y `plantillas` revisados por lectura: no pasan por lo que cambió.

**Commitear.**

## Fase 2 — Qué columnas se pueden tocar (`sql/077`)

- [x] 4/5 · Grants de UPDATE por columna en `tareas` (sin `id`, `creado_por`, `created_at`, `modo_completado`, `origen_*`, `paso_anterior_id`, `nota_anterior`), notas / asignados / miembros (solo `activo`), `tareas_proyectos` (sin `id`, `creado_por`, `created_at`), hilos e items de plantillas (sin `plantilla_id`, `id`, `created_at`).
- [x] 6 · Reactivar una tarea archivada: solo el administrador.
- [x] 7 · `tareas_vinculos` insert/update manual: quien puede gestionar la tarea (responsable, asignado o administrador), no quien solo la ve.
- [x] 8 · `tareas_asignados_insert/update`: nadie queda asignado sin poder abrir lo relacionado (misma regla que `sql/063`, ahora en la policy).
- [x] Test (bloque F2) + los de F1.

Resultado: `auditoria_tareas` F2 14/14. Tests existentes revisados: ninguno escribe columnas sin grant, reactiva por UPDATE ni asigna por fuera de las funciones sobre tareas con vínculos.

**Commitear.**

## Fase 3 — Bugs de base (`sql/078`)

- [ ] 13 · `deshacer_conversion_hilo` con pasos encadenados (TA006).
- [ ] 14 · Fecha de Argentina en `reactivar_posponer_vencidos`, `fijar_vencimiento_tras_previo`, `arrancar_vencimiento_siguiente`, `generar_recurrencia`; índice parcial sobre `posponer_hasta` (20).
- [ ] 11 · CHECK de largo en títulos, descripciones y notas (mismos máximos que Zod).
- [ ] 16 · `crear_tarea` / `sincronizar_asignados` con asignados NULL.
- [ ] Test (bloque F3) + `pasos_tarea`, `atomicidad_*`.

**Commitear.**

## Fase 4 — Plantillas (`sql/079`)

- [ ] C · `tareas_plantillas_select` (y la de hijos por cascada): el administrador ve las privadas; editar sigue siendo del dueño.
- [ ] 18 · `tareas_plantillas_items_update` suma la regla de `tareas_asignar` que ya tiene el insert.
- [ ] Test (bloque F4) + `plantillas*`.

**Commitear.**

## Fase 5 — App

- [ ] 15 · Auditoría: validar `desde` / `hasta` / `usuario` y no mandar cientos de ids por URL.
- [ ] 16 · `posponerSchema.hasta` como fecha; `max` en arrays de asignados, miembros y pasos del tutorial (23).
- [ ] 19 · Comentario de `actions.ts` sobre quién autoriza.
- [ ] 22 · Borrar `getHiloTareas`, `filtrosTareasSchema`, `FiltrosTareas`.
- [ ] `npx tsc --noEmit` + tests de `erp-app`.

**Commitear.**

## Fase 6 — Pendiente de decisión

- [ ] 10 · Crear tareas/hilos/notas sin la vista `tareas_lista` (hoy la base no la pide).
- [ ] 17 · Posponer / desactivar / convertir: la UI lo limita al responsable, la base se lo deja a cualquier asignado.
- [ ] 9 · Oráculos de acceso (`sin_acceso`, `es_miembro_proyecto`): se aceptan o se rediseñan.
- [ ] 21 · Paginado de la Lista para el administrador.

**Commitear.**
