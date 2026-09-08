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

## Obras — auditoría visual de la UI

29 hallazgos relevados el 2026-09-08: `AUDITORIA_OBRAS_UI.md`. Van 2 implementados, quedan 27.

Los dos críticos —el nombre de la fila colapsando en mobile y la metadata ragged en desktop—
salieron juntos el 2026-09-08: eran el mismo refactor de fila. Ver `decisiones/obras.md`.

Lo que sigue, en orden: la ficha como bloque (A1 + A4 + A3, que es el `OverflowMenu` para
Editar/Quitar/Referente y saca "Desactivar" del header), después A2 + A5, y A6 —desvincular sin
confirmación ni bloqueo de doble click— que es corrección de comportamiento y puede ir aparte.

Cinco de los 29 son app-wide (ThemeToggle flotante tapando contenido, avatar del sidebar pisando
el nombre, `.card:hover` en lo no clickeable, alturas de toolbar, el modal que no atenúa el
panel): esos se deciden en `decisiones/global.md`, no en el módulo.

## Obras — buscador global obra/empresa/persona

Una sola barra que busque en las tres entidades y lleve a la ficha. Con las obras privadas por responsable y sin buscador, encontrar una obra vieja se vuelve incómodo rápido — el listado filtrado alcanza mientras la cartera de cada vendedor sea chica.

Cuando se haga: la búsqueda de personas tiene que respetar el alcance de `obras_puede_ver_persona` y devolver identidad mínima para las que no se ven, igual que `obras_buscar_duplicados_persona`. Un buscador global que devuelva contacto sin pasar por `obras_ficha_persona()` anula el registro de accesos — ese es el punto a cuidar, no la búsqueda en sí.

## Obras — avisarle al que cargó que le rechazaron el alta

Con `sql/033`, rechazar es desactivar con motivo: la fila sale de los listados y el motivo solo se lee entrando a la ficha por URL directa, o desde el historial de la vista Pendientes — que quien cargó no tiene por qué poder ver.

No se resolvió ahora porque el módulo no tiene ningún canal de aviso y armarlo para esto sería construir media notificación. Cuando exista uno (o cuando el ERP tenga notificaciones), el rechazo es el primer caso: `obras_aprobaciones` ya guarda quién, cuándo, qué y por qué.

Alternativa barata si urge antes: mostrar en el listado propio las filas rechazadas de los últimos N días con badge y motivo, en vez de esconderlas junto con las desactivadas a mano.
