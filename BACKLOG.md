# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## Tareas — proyecto con cara de hilo

El proyecto **no se convierte en hilo** (sin `estado` abierto/cerrado ni cierre automático): se le da la *cara* de hilo — progreso "X/Y completadas" y métricas en `ProyectoDetailPanel`, que es cálculo puro sobre datos que ya llegan al panel. Si el proyecto tuviera estado propio, el nivel del medio (hilo) se quedaría sin razón de existir.

## Tareas — desactivar proyecto en cascada

`desactivarProyecto` desactiva solo la fila del proyecto. Sus hilos y sus tareas
sueltas quedan activos: el trabajo no desaparece de la Lista (el hilo sigue
siendo hilo, la tarea suelta sigue suelta), pero pierde la agrupación y queda
con `proyecto_id` apuntando a un proyecto archivado.

Decisión tomada: **cascada completa**, simétrica con `desactivarHilo` —
desactivar el proyecto desactiva sus hilos, y la cascada de hilos ya se lleva
las tareas de cada uno; faltan además las tareas sueltas del proyecto.
Archivar es "se va todo junto", no "se sueltan las partes".

Sin implementar todavía. Efecto secundario a resolver junto con esto: al editar
una tarea de un proyecto archivado, el select de `TareaFormPanel` no lista ese
proyecto (`puedeTrabajarEnProyecto` lo filtra) y el campo aparece vacío sobre un
valor que sigue seteado.

## Tareas — plantilla-checklist (items sin orden entre sí)

Desde `sql/017` toda plantilla genera una cadena: cada item espera al anterior (`agregarTareasDesdePlantilla`). Decidido no agregar flag ni checkbox hasta que exista una plantilla real cuyos items sean paralelos — ahí el camino barato es una columna `encadenada boolean` en `tareas_plantillas`, no una opción en "usar plantilla" (la plantilla sabe cómo es, quien la usa no debería tener que decidirlo cada vez).

## Tareas — verificar `Content-Range` en el PATCH

**Pendiente de verificar en el navegador** (alcance reducido tras `sql/023`: solo aplica a las actions de una sola tabla, que siguen usando `errorDeUpdate`)**:** que PostgREST devuelva `Content-Range` en un PATCH con `Prefer: return=minimal,count=exact`. No se pudo probar desde acá — ni `anon` ni `service_role` tienen `GRANT` sobre `tareas` (decisión "RLS no alcanza sin GRANT"), así que hace falta una sesión autenticada real. Si no lo devolviera, `count` llega `null` y `errorDeUpdate` no dispara: el fix quedaría inerte, nunca en falso positivo.

## Global — `.input-error-text` en `globals.css`

Mismo defecto de contraste que ya se corrigió en `text-error` / `text-warning` (ver *Tokens
y clases de `globals.css`* en `decisiones/global.md`): hex fijo sobre fondo tematizado, abajo
de AA en uno de los dos temas. Quedó afuera de aquella auditoría porque es app-wide y esa
pasada era del módulo tareas.
