# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## Tareas ↔ entes — vínculos, chips, condiciones y compartir

Decidido con el usuario el 2026-09-14. Queda compartir al asignar (lo demás está en `decisiones/tareas/`).

- **Compartir al asignar.** Si un asignado no puede abrir lo vinculado, se pregunta con el checklist de compartir de Obras (solo se ofrece lo que es de quien asigna). Regla única, a mano y en el disparo: quien no puede abrirlo no queda asignado; si no queda nadie, la tarea va a quien asigna, con nota. En el disparo se pregunta al guardar el cambio de estado, y cerrar el panel es no compartir.

  Relevado antes de construir (2026-09-14):
  - **Saber si otro usuario puede abrir un registro.** La regla de Obras está escrita para `auth.uid()`: `obras_puede_ver_obra` (sql/047), `obras_puede_ver_persona` (sql/039), la policy inline `obras_empresas_select` (sql/047) y `tiene_permiso`. Para no copiarla: funciones con el usuario como parámetro, que las actuales envuelvan con `auth.uid()`, y correr los tests de RLS de Obras (`rls_obras`, `obras_047`–`052`) antes y después. Los grants de contexto (`obras_persona_grant_contextual`) no alcanzan: el chip abre la ficha sin contexto.
  - **Solo el dueño comparte** (`OB026`): `obras_compartir_obra(obra, usuario, empresas[], personas[])` y `obras_relaciones_compartibles_obra(obra, usuario)`, que ya marca `ya_compartida`. Si quien asigna no es el dueño, no hay nada que preguntar: se aplica la regla y se avisa.
  - **El checklist vive en `modules/obras/components/CompartirPanel.tsx`** y lo van a necesitar Tareas (asignar a mano, "Relacionar" con asignados que no lo ven) y Obras (el cambio de estado que dispara): son dos módulos, así que va a `components/`.
  - **Orden en `usar_plantilla`:** hoy `crear_tarea` inserta los asignados y después se insertan los vínculos del disparo. Para que la regla viva en la base (un asignado sin acceso a un vínculo no entra) hay que vincular primero.

## Tareas — verificar `Content-Range` en el PATCH

**Pendiente de verificar en el navegador** (alcance reducido tras `sql/023`: solo aplica a las actions de una sola tabla, que siguen usando `errorDeUpdate`)**:** que PostgREST devuelva `Content-Range` en un PATCH con `Prefer: return=minimal,count=exact`. No se pudo probar desde acá — ni `anon` ni `service_role` tienen `GRANT` sobre `tareas` (decisión "RLS no alcanza sin GRANT"), así que hace falta una sesión autenticada real. Si no lo devolviera, `count` llega `null` y `errorDeUpdate` no dispara: el fix quedaría inerte, nunca en falso positivo.

## erp-cliente — su `globals.css` quedó en la versión vieja de los tokens

Encontrado al cerrar `.input-error-text` en erp-app, el 2026-09-09. `erp-cliente/src/app/globals.css`
tiene `--color-error-bg`/`--color-error-text` (y las otras tres familias) como hex fijos en `@theme`,
que es de donde erp-app salió cuando se hizo el bloque dark-aware de `:root` / `[data-theme="dark"]`.
El `@custom-variant dark` sí está, así que el defecto viaja igual: `text-error` sobre superficie
oscura da 3.8:1, y `text-error-text` (#5C0A0A) sobre esa misma superficie sería peor.

No se arregló ahora porque ahí el fix no es un token: hay que portar el bloque entero de las cuatro
familias, y el app tiene tres archivos —`layout.tsx`, `page.tsx`, `globals.css`— sin un solo
formulario que muestre el defecto. Cuando erp-cliente arranque de verdad, el `globals.css` se trae
de erp-app y no se edita el que está.

Las apps no se importan entre sí, así que los tokens del design system son la duplicación que el
repo ya aceptó (`GUIDE_SYNC.md` cubre schemas y tipos, no CSS). Lo que falta no es una abstracción:
es acordarse de sincronizar cuando el segundo app exista.

## ~~Obras — auditoría visual de la UI~~ — cerrada

29 hallazgos relevados el 2026-09-08: `obsoletos/AUDITORIA_OBRAS_UI.md`. 28 implementados y **B3 cerrado
sin tocar código: no reproduce.**

La segunda pasada de navegador midió el footer del sidebar con el usuario real (`nombre` =
`Admin`): el nombre ocupa 40.6px en una caja de 81.2px en escritorio y de 71.2px en el drawer
mobile, y el avatar 18.7px en 28px. Ni truncado ni solape en ninguno de los dos anchos. Lo que
se había leído como `A…dmin` era el puntero del mouse que dibuja la herramienta de captura,
apoyado sobre el avatar; en la segunda pasada el mismo círculo cayó sobre el logo y lo dejó en
`S⬤DA`. No hay nada que decidir, así que no va a `decisiones/global/`.

Los cuatro app-wide reales están cerrados ahí (ThemeToggle flotante, `.card:hover` en lo no
clickeable, alturas de toolbar, el modal que no atenuaba el panel). El resto, en
`decisiones/obras/ui.md`.

## Sugerencia de tareas — sin caso real todavía

Pedida junto con las notificaciones y no construida (ver `decisiones/global/infra.md`). "¿Qué hago ahora?" ya lo contestan Misión y el orden de `useOrdenTemperatura`; lo que falta es "¿qué tarea debería existir y no existe?" — la obra sin movimiento hace 60 días.

~~**El bloqueante no es la regla, es el vínculo.**~~ — resuelto por `sql/055`: `tareas_vinculos` guarda `(tarea, ente, registro, plantilla)` de lo que genera un disparo, así que una sugerencia puede saber si la tarea ya existe. Ver `decisiones/tareas/plantillas.md` → *Plantillas disparadas por estado*.

Cuando aparezca un caso real, la sugerencia debería abrir el flujo de plantillas que ya existe, no un camino de creación nuevo. Un vínculo que no venga de un disparo pide revisar dos cosas de `sql/055`: `tareas_vinculos.plantilla_id` es NOT NULL, e insertar exige estar adentro de un trigger.

