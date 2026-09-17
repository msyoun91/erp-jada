# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

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

## Tareas sobre el modelo de entes (`GUIDE_ENTES.md`, 2026-09-16)

Resultado de leer Tareas con la guía (`decisiones/global/entes.md` → *Tareas leída con la guía*). El
usuario pidió la guía y la prueba, no la modificación: nada de esto se construye hasta que lo pida.

- **Descripción con referencias `{ente:uuid}`** resueltas al mostrar (`etiqueta_registro`) → chip/link
  o nada. El editor de texto es librería nueva: consultar antes.
- **Chips arrastrables**: librería de dnd con soporte touch — consultar antes.
- **`VinculosChips` y `RelacionarRegistro` suben a `components/ui/`** cuando el segundo módulo los use
  (Obras ya los monta, pero vía `app/`).

## Sugerencia de tareas — sin caso real todavía

Pedida junto con las notificaciones y no construida (ver `decisiones/global/infra.md`). "¿Qué hago ahora?" ya lo contestan Misión y el orden de `useOrdenTemperatura`; lo que falta es "¿qué tarea debería existir y no existe?" — la obra sin movimiento hace 60 días.

~~**El bloqueante no es la regla, es el vínculo.**~~ — resuelto por `sql/055`: `tareas_vinculos` guarda `(tarea, ente, registro, plantilla)` de lo que genera un disparo, así que una sugerencia puede saber si la tarea ya existe. Ver `decisiones/tareas/plantillas.md` → *Plantillas disparadas por estado*.

Cuando aparezca un caso real, la sugerencia debería abrir el flujo de plantillas que ya existe, no un camino de creación nuevo. Un vínculo que no venga de un disparo pide revisar dos cosas de `sql/055`: `tareas_vinculos.plantilla_id` es NOT NULL, e insertar exige estar adentro de un trigger.


## Compartir al asignar una tarea quedó a medio camino (`sql/082` + `sql/085`, 2026-09-17)

`obras_compartir_registros` ahora otorga **grant contextual** anclado a la obra/empresa compartida
con ese usuario, igual que el resto de compartir (`decisiones/obras/visibilidad.md` → *Compartir una
obra o empresa no reparte contactos*). Pero el receptor **todavía no puede abrir la ficha desde la
tarea**: `obras_puede_ver_persona_de` —y por lo tanto `puede_abrir_registro` (`sql/062`)— no cuenta
contextuales, y el chip sale de `entes.ruta` sin `?ctx=`. Consecuencia visible: el flujo sigue
ofreciendo compartir esa persona aunque ya se le otorgó. Y si no hay obra/empresa en común, corta
con `OB029`.

Decidido con el usuario: se rompe a propósito ahora y se repara después.

**`sql/085` sumó la empresa al mismo problema.** Su rama en `obras_compartir_registros` pasó de
grant completo a contextual anclado a la obra, y corta con `OB029` si no hay ninguna compartida.
Hubo que tocarla igual aunque el usuario aceptó que Tareas se rompiera: seguía escribiendo
`origen_obra_id`, que esa migración dropea, así que no se degradaba — crasheaba al asignar
cualquier tarea con una empresa. Misma reparación pendiente, un ente más.

**La reparación, cuando se haga:** ancla `tarea_id` en `obras_persona_grant_contextual` (el CHECK
pasa a obra XOR empresa XOR tarea) **y en `obras_empresa_grant_contextual`** (que hoy tiene
`obra_id NOT NULL`: el ancla pasa a ser obra XOR tarea), su rama en `obras_ficha_persona` /
`obras_ficha_empresa` —"la tarea sigue vinculando a esta entidad y el usuario ve la tarea"—, el
chip con `?ctx=tarea:{id}`, y `obras_puede_abrir` aprendiendo esa rama. Es un tercer tipo de contexto y mete a Obras a validar contra `tareas`:
decidir dónde vive esa validación antes de escribirla.

## ~~Deriva base ↔ repo: `compartido` / `revocado` sin archivo SQL (2026-09-17)~~ — cerrada

Resuelta el 2026-09-17 con `sql/083_eventos_compartir.sql` y `sql/084_transferir_arrastra_compartido.sql`,
los dos reconstruidos desde la base, más `db_schema/core.md` y `db_schema/obras.md` sincronizados.

**Dos premisas de la entrada original eran falsas**, y vale dejarlas escritas porque las dos venían
de mirar `database.types.ts` en vez de la base:

1. *"No dispara nada hoy: ningún ente los declara en `entes.disparos`"* — `entes.disparos` gobierna
   qué **dispara plantillas**, no qué se **emite**. Los eventos se emitían desde el primer día:
   `obras_emitir_eventos_grant` colgado de las tres tablas de grant. Y `puede_ver_compartido` estaba
   viva dentro de la policy `eventos_select`. Nada de esto era código muerto.
2. *"el enum + dos funciones"* — eran tres funciones (faltaba `obras_emitir_eventos_grant`, que no
   aparece en `database.types.ts` por ser trigger function), tres triggers y la policy reescrita.

Y había una segunda deriva que la entrada no veía: **`obras_transferir` y `obras_transferir_empresa`
viven en la base con lógica que `sql/041` no tiene** (arrastre de lo compartido). El cuerpo vivo cita
un `sql/071` que nunca existió en el repo. Los números 071–075 quedan libres: renumerar reescribiría
historia por nada, y 083/084 reconstruyen en orden válido igual.

**Cómo se encontró, por si vuelve a pasar:** diff de los cuerpos (`pg_proc.prosrc`) contra el texto
de `sql/*.sql`, normalizando espacios. De 161 funciones, 14 no matchearon y 11 de esas eran solo
comentarios que la base no tiene — alguien aplicó una versión despojada. Un diff por **nombre** solo
habría encontrado 3 de las 5 reales.
