# BACKLOG — ERP JADA

Pendientes con la referencia ya localizada, para no re-explorar en la próxima sesión.
Al cerrar un ítem: borrarlo de acá y, si la decisión no era obvia, registrarla en `DECISIONES.md`.

---

## P1 — responsive y legibilidad

Cerrado (ver `DECISIONES.md`, sección "P1 responsive y legibilidad"). Queda pendiente verificar en dispositivo real a 390px y ~820px — los fixes se hicieron leyendo el código, sin correr la app.

---

## Verificaciones pendientes

- [ ] **Policies RLS de miembros de proyecto, end-to-end** (`sql/009`, ya corrido). Los triggers `TA001`/`TA002` y el helper `es_miembro_proyecto_de_tarea` quedaron probados contra la base; lo que falta es el camino RLS real de `tareas_asignados_insert`/`update` y de `tareas_proyectos_miembros_select`, que como `postgres` no se ejercita (el owner bypasea RLS). Dos formas: desde la app con dos usuarios (uno miembro, otro no), o en SQL con `SET LOCAL ROLE authenticated` + `SET LOCAL request.jwt.claims = '{"sub":"<uuid>"}'`. Caso clave: un miembro que **no** es creador del proyecto tiene que ver a los demás miembros — si no, el picker de asignados le queda vacío.

---

## Features pedidas

- [ ] **#2a Proyecto con cara de hilo.** Progreso "X/Y completadas" + métricas ("hace N días", "próxima vence en X") en `ProyectoDetailPanel` — cálculo puro sobre datos que ya llegan al panel, 0 SQL. Notas de proyecto (tabla `tareas_proyectos_notas` copiando `tareas_hilos_notas`) solo si se pide. Decidido: el proyecto **no** gana `estado` abierto/cerrado.
- [ ] **Historial de acciones + deshacer** (conversación previa, sin decidir alcance). Hoy `tareas_eventos` (`sql/005:231`) solo loguea cambios de estado — el trigger es `AFTER UPDATE OF estado`. Camino barato: ampliar a `AFTER INSERT OR UPDATE` + columnas `datos_anteriores`/`datos_nuevos` jsonb, y "deshacer" = restaurar el snapshot. Techo real: sirve para ediciones de una fila; las acciones estructurales (convertir en hilo, reasignar, plantilla → N tareas) necesitan su inverso escrito a mano, como ya lo tiene `deshacerConversionHilo`.
