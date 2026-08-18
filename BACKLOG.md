# BACKLOG — ERP JADA

Pendientes con la referencia ya localizada, para no re-explorar en la próxima sesión.
Al cerrar un ítem: borrarlo de acá y, si la decisión no era obvia, registrarla en `DECISIONES.md`.

---

## P1 — responsive y legibilidad

Cerrado (ver `DECISIONES.md`, sección "P1 responsive y legibilidad"). Queda pendiente verificar en dispositivo real a 390px y ~820px — los fixes se hicieron leyendo el código, sin correr la app.

---

## Features pedidas

- [ ] **#3 Miembros de proyecto = quién puede recibir tareas.** Decisión ya tomada y registrada en `DECISIONES.md` (sección "Decidido, pendiente de implementar"). Alcance: `sql/009` con helper `SECURITY DEFINER` `es_miembro_proyecto_de_tarea` + condición nueva en `tareas_asignados_insert`/`update` (`sql/005:609`); `crearProyectoSchema` pasa a exigir miembros siempre; query nueva mapa proyecto→miembros para `tareas/page.tsx` (hoy no carga miembros); filtro en `AsignadosPicker`/`TareaFormPanel`/`ReasignarPanel`/`UsarPlantillaPanel`; bloquear quitar miembro con tareas activas; backfill de proyectos públicos sin miembros.
- [ ] **#2a Proyecto con cara de hilo.** Progreso "X/Y completadas" + métricas ("hace N días", "próxima vence en X") en `ProyectoDetailPanel` — cálculo puro sobre datos que ya llegan al panel, 0 SQL. Notas de proyecto (tabla `tareas_proyectos_notas` copiando `tareas_hilos_notas`) solo si se pide. Decidido: el proyecto **no** gana `estado` abierto/cerrado.
- [ ] **Historial de acciones + deshacer** (conversación previa, sin decidir alcance). Hoy `tareas_eventos` (`sql/005:231`) solo loguea cambios de estado — el trigger es `AFTER UPDATE OF estado`. Camino barato: ampliar a `AFTER INSERT OR UPDATE` + columnas `datos_anteriores`/`datos_nuevos` jsonb, y "deshacer" = restaurar el snapshot. Techo real: sirve para ediciones de una fila; las acciones estructurales (convertir en hilo, reasignar, plantilla → N tareas) necesitan su inverso escrito a mano, como ya lo tiene `deshacerConversionHilo`.
