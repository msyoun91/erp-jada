# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## Tareas — proyecto con cara de hilo

El proyecto **no se convierte en hilo** (sin `estado` abierto/cerrado ni cierre automático): se le da la *cara* de hilo — progreso "X/Y completadas" y métricas en `ProyectoDetailPanel`, que es cálculo puro sobre datos que ya llegan al panel. Si el proyecto tuviera estado propio, el nivel del medio (hilo) se quedaría sin razón de existir.

## Tareas — plantilla-checklist (items sin orden entre sí)

Desde `sql/017` toda plantilla genera una cadena: cada item espera al anterior (`agregarTareasDesdePlantilla`). Decidido no agregar flag ni checkbox hasta que exista una plantilla real cuyos items sean paralelos — ahí el camino barato es una columna `encadenada boolean` en `tareas_plantillas`, no una opción en "usar plantilla" (la plantilla sabe cómo es, quien la usa no debería tener que decidirlo cada vez).

## Tareas — verificar `Content-Range` en el PATCH

**Pendiente de verificar en el navegador** (alcance reducido tras `sql/023`: solo aplica a las actions de una sola tabla, que siguen usando `errorDeUpdate`)**:** que PostgREST devuelva `Content-Range` en un PATCH con `Prefer: return=minimal,count=exact`. No se pudo probar desde acá — ni `anon` ni `service_role` tienen `GRANT` sobre `tareas` (decisión "RLS no alcanza sin GRANT"), así que hace falta una sesión autenticada real. Si no lo devolviera, `count` llega `null` y `errorDeUpdate` no dispara: el fix quedaría inerte, nunca en falso positivo.

## Global — `.input-error-text` en `globals.css`

Mismo defecto de contraste que ya se corrigió en `text-error` / `text-warning` (ver *Tokens
y clases de `globals.css`* en `decisiones/global.md`): hex fijo sobre fondo tematizado, abajo
de AA en uno de los dos temas. Quedó afuera de aquella auditoría porque es app-wide y esa
pasada era del módulo tareas.

## ~~Obras — auditoría visual de la UI~~ — cerrada

29 hallazgos relevados el 2026-09-08: `AUDITORIA_OBRAS_UI.md`. 28 implementados y **B3 cerrado
sin tocar código: no reproduce.**

La segunda pasada de navegador midió el footer del sidebar con el usuario real (`nombre` =
`Admin`): el nombre ocupa 40.6px en una caja de 81.2px en escritorio y de 71.2px en el drawer
mobile, y el avatar 18.7px en 28px. Ni truncado ni solape en ninguno de los dos anchos. Lo que
se había leído como `A…dmin` era el puntero del mouse que dibuja la herramienta de captura,
apoyado sobre el avatar; en la segunda pasada el mismo círculo cayó sobre el logo y lo dejó en
`S⬤DA`. No hay nada que decidir, así que no va a `decisiones/global.md`.

Los cuatro app-wide reales están cerrados ahí (ThemeToggle flotante, `.card:hover` en lo no
clickeable, alturas de toolbar, el modal que no atenuaba el panel). El resto, en
`decisiones/obras.md`.

## Obras — el referente sobrevive a la desvinculación de la persona

`desvincularPersona` desactiva la fila de `obras_obra_persona` y nada más. La de
`obras_obra_referente` queda `activo = true`, y `getReferentes` la lee sin pasar por el vínculo.

Hoy no se ve —la fila de la persona desaparece de la ficha y el badge se va con ella— pero el
dato queda: si mañana se vuelve a vincular a la misma persona, reaparece la comisión vieja sin
que nadie la haya vuelto a cargar. Y mientras tanto es un referente que la UI no puede quitar,
porque `ReferentePanel` solo lista personas vinculadas.

Encontrado al implementar A6, el 2026-09-08. No se arregló ahí porque es una invariante de
datos, no de UI: va en la base —trigger sobre `obras_obra_persona` que baja el referente cuando
cae el vínculo— y no en `actions.ts`.

## Obras — buscador global obra/empresa/persona

Una sola barra que busque en las tres entidades y lleve a la ficha. Con las obras privadas por responsable y sin buscador, encontrar una obra vieja se vuelve incómodo rápido — el listado filtrado alcanza mientras la cartera de cada vendedor sea chica.

Cuando se haga: la búsqueda de personas tiene que respetar el alcance de `obras_puede_ver_persona` y devolver identidad mínima para las que no se ven, igual que `obras_buscar_duplicados_persona`. Un buscador global que devuelva contacto sin pasar por `obras_ficha_persona()` anula el registro de accesos — ese es el punto a cuidar, no la búsqueda en sí.

## Obras — avisarle al que cargó que le rechazaron el alta

Con `sql/033`, rechazar es desactivar con motivo: la fila sale de los listados y el motivo solo se lee entrando a la ficha por URL directa, o desde el historial de la vista Pendientes — que quien cargó no tiene por qué poder ver.

No se resolvió ahora porque el módulo no tiene ningún canal de aviso y armarlo para esto sería construir media notificación. Cuando exista uno (o cuando el ERP tenga notificaciones), el rechazo es el primer caso: `obras_aprobaciones` ya guarda quién, cuándo, qué y por qué.

Alternativa barata si urge antes: mostrar en el listado propio las filas rechazadas de los últimos N días con badge y motivo, en vez de esconderlas junto con las desactivadas a mano.
