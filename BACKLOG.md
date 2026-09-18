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

## Resto de la auditoría de compartir/transferir (2026-09-18)

Las cuatro vulnerabilidades se cerraron en `sql/090` (`decisiones/obras/visibilidad.md` → *El grant
contextual muere con el ancla*). Lo que queda son inconsistencias, ninguna con acceso indebido
detrás. Ordenadas por lo que cuesta dejarlas.

- **`obras_compartir_obra` no valida que el receptor tenga `obras_ver`.** Transferir sí lo hace
  (`OB006`). Compartir con alguien sin acceso al módulo crea un grant que no abre nada: la obra no le
  aparece (`obras_select` exige `obras_ver`) y, desde `sql/090`, los contextuales que cuelgan tampoco.
  Una línea: `usuario_tiene_permiso(p_usuario_id, 'obras_ver')` junto al chequeo de `usuarios.activo`.
  Decidir primero si el error es `OB006` o uno nuevo — no es "el destino", es "el receptor".

- **`NULL` degrada en silencio en los arrays.** `id = ANY(NULL)` es NULL, no false, y los `DEFAULT
  '{}'` no aplican si el cliente manda `null` explícito. `obras_compartir_obra` con `p_personas:
  null` no otorga **ni destilda** — la limpieza `NOT (persona_id = ANY(p_personas))` también da NULL,
  así que el reparto queda congelado. `obras_transferir` con `p_migran: null` transfiere la obra y
  deja al receptor sin ningún contacto. Fix: `COALESCE(p_migran, '{}')` al entrar en las cuatro
  funciones, y `.default([])` en los schemas Zod. Hoy la UI siempre manda array, así que es blindaje.

- **La agenda se recorta en la query, no en la policy.** `obras_personas_select` y
  `obras_empresas_select` dejan pasar el grant contextual **sin ancla** (`_ctx_vigente`); lo que
  mantiene al contacto fuera del listado es `.eq("creado_por", me)` en `queries.ts` (`getPersonas`,
  `getEmpresas`). Un GET directo a PostgREST devuelve igual las filas contextuales. Solo identidad
  —el contacto está protegido a nivel columna desde `sql/039`/`sql/085`— pero contradice *la interfaz
  nunca es barrera*. Está comentado en el código como decisión deliberada: o se escribe como tal en
  `visibilidad.md`, o la policy pasa a pedir ancla y el recorte de la query sobra.

- **`obras_migrar_agenda` conserva la copia del gate `OB006`.** `sql/090` pasó las otras tres a
  `usuario_tiene_permiso(destino, 'obras_ver')`; esta quedó con el `EXISTS` sobre `usuario_submodulos`
  porque no se reescribía en esa migración. Misma regla, cuarta copia.

- **`revocarObra` y `revocarContextual` no tienen `safeParse`** (`actions.ts`). La base gatea, pero
  rompe la regla de validar en dos lugares y un uuid malformado sale como genérico (22P02) en vez de
  mensaje. **`contarVinculosReceptor`** traga el error y devuelve `0`: el panel anuncia "se van a caer
  0 vínculos" cuando la consulta falló.

- **El buscador marca `es_ajeno` a quien sí se puede abrir.** `obras_buscar_personas` / `_empresas`
  resuelven con `obras_puede_ver_*`, que no cuenta contextuales. Correcto para no meterlo en la
  agenda, pero al receptor le muestra "de Fulano, sin link" a un contacto que abre normal desde la
  obra. Si se toca, el link va con `?ctx=`, que es la misma reparación del chip de tarea de la
  entrada de arriba.

- **`OB022` significa dos cosas** —"sin acceso a esta persona" y "sin acceso a esta obra"— y `OB009`
  quedó como código muerto. Funciona porque `mensajeError()` pasa el texto de la base, así que el
  costo es que el código dejó de identificar. Anotado en la tabla de `db_schema/obras.md`.

- **Grants activos que ya no abren nada.** El estado 3 (`p_sacar`) desactiva los vínculos pero deja
  `activo = true` en los grants contextuales de terceros que colgaban de ellos. El acceso muere bien
  —`_vigente` exige vínculo vivo—, pero las filas siguen apareciendo en Compartido simulando un
  reparto que no existe. Cosmético; ensucia la lectura de la vista.

- **`sql/tests/obras_085.sql` está obsoleto.** Usa `obras_empresa_compartida`, `obras_compartir_empresa`
  y `obras_empresa_grant_directo`, dropeadas por `sql/086`. Falla con `42P01` y no por regresión. Los
  casos que siguen valiendo (A: el contacto sin `GRANT SELECT`; L: la empresa destildada no entra a la
  agenda) están cubiertos por `obras_086` y `obras_087`: probablemente se borre en vez de portarse.
