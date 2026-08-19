# BACKLOG — ERP JADA

Pendientes con la referencia ya localizada, para no re-explorar en la próxima sesión.
Al cerrar un ítem: borrarlo de acá y, si la decisión no era obvia, registrarla en `DECISIONES.md`.

---

## P1 — responsive y legibilidad

Cerrado (ver `DECISIONES.md`, sección "P1 responsive y legibilidad"). Queda pendiente verificar en dispositivo real a 390px y ~820px — los fixes se hicieron leyendo el código, sin correr la app.

---

## Features pedidas

- [ ] **Notas de proyecto** (tabla `tareas_proyectos_notas` copiando `tareas_hilos_notas`) — lo único que quedó fuera del ítem "#2a Proyecto con cara de hilo", cerrado el 2026-08-19 (progreso, métricas e islas: ver `DECISIONES.md`, "isla compartida, panel de proyecto y edición de hilo"). Decidido: el proyecto **no** gana `estado` abierto/cerrado.
- [ ] **Quitar un miembro con asignaciones sobre tareas cerradas.** Salteado a pedido del usuario el 2026-08-19. Hoy `validar_quitar_miembro` solo bloquea (`TA001`) si el miembro tiene tareas `pendiente`/`en_progreso`: sobre tareas completadas/canceladas su asignación queda activa, y reabrir esa tarea le devuelve trabajo vivo a alguien que ya no es miembro. Opciones evaluadas: bloquear siempre, desasignar las cerradas, o traspasar al dueño (`sql/010`, revertido).
- [ ] **Historial de acciones + deshacer** (conversación previa, sin decidir alcance). Hoy `tareas_eventos` (`sql/005:231`) solo loguea cambios de estado — el trigger es `AFTER UPDATE OF estado`. Camino barato: ampliar a `AFTER INSERT OR UPDATE` + columnas `datos_anteriores`/`datos_nuevos` jsonb, y "deshacer" = restaurar el snapshot. Techo real: sirve para ediciones de una fila; las acciones estructurales (convertir en hilo, reasignar, plantilla → N tareas) necesitan su inverso escrito a mano, como ya lo tiene `deshacerConversionHilo`.

---

## Trabajo descartado — recuperable por tiempo limitado

Stash de la sesión del 2026-08-18, dropeado a pedido. Nunca se commiteó: el SHA es la única vía de vuelta.

```
9cc8e8ede68ff028e8f910d55222d22ecc6f8f9f

git show 9cc8e8e --stat     # ver contenido
git stash apply 9cc8e8e     # recuperar todo
```

**Caduca pronto.** Al dropear el stash se borró su entrada de reflog, así que el commit quedó inalcanzable y lo que manda es `gc.pruneExpire` (default `2.weeks.ago`), no los 90 días de `gc.reflogExpire`. Cualquier `git gc` — y corre solo cuando se acumulan objetos sueltos — lo borra definitivo a partir del ~2026-09-01.

Para volverlo permanente, hacerlo ya: `git branch rescate/sesion-010 9cc8e8e`.

Contenía tres bloques, revertidos en `06f812b`. **Los dos primeros ya se recuperaron** el 2026-08-19 (están en el árbol, no hace falta el stash para ellos):

- ~~Progreso y métricas del proyecto en `ProyectoDetailPanel` + `MetricasResumen.tsx` extraído de `HiloCard`.~~ Recuperado.
- ~~`ProyectoFormPanel` como panel único de crear/modificar proyecto, absorbiendo `MiembrosPanel.tsx`; `gestionarMiembrosProyecto` → `editarProyecto`.~~ Recuperado.
- `sql/010`: trigger `validar_estado_tarea` (`TA003`, solo responsable o asignado cambia el estado) + traspaso al dueño de las asignaciones sobre tareas cerradas al salir un miembro, con `sql/tests/rls_estado_y_salida_miembro.sql` (14 casos). Dropeado de la base en `sql/011` y `sql/012`; el backfill de datos no se revirtió.
