# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## ~~erp-cliente — su `globals.css` quedó en la versión vieja de los tokens~~ — cerrada

Resuelta el 2026-09-18 copiando entero el `globals.css` de erp-app, que es lo que esta misma entrada
decidía. Queda escrito en `decisiones/global/ui.md` → *`erp-cliente/src/app/globals.css` es una copia
literal*.

**La entrada subestimaba la deriva.** Nombraba las cuatro familias semánticas; faltaban además nueve
cosas más, entre ellas `.icon-btn` nombrada en el media query de 44px sin estar definida y
`.input-error-text` todavía con `text-error` — el mismo defecto de contraste cuyo cierre en erp-app
destapó esta entrada. Eso no cambia el fix (era copiar entero de todos modos), pero sí el motivo:
la unidad de sincronización es el archivo, no el token.

**Y no vio que la rama dark sigue inalcanzable ahí**: `erp-cliente/src/app/layout.tsx` no tiene el
script inline que escribe `data-theme` en el `<html>`. Los tokens ahora son correctos; el app todavía
no puede entrar en dark. Va con el layout, cuando el portal arranque.

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

- ~~**`obras_compartir_obra` no valida que el receptor tenga `obras_ver`.**~~ — cerrada por `sql/091`
  (`decisiones/obras/visibilidad.md` → *Compartir exige lo mismo que transferir*). Se reusó `OB006`
  con texto propio, no un código nuevo.

- ~~**`NULL` degrada en silencio en los arrays.**~~ — cerrada por `sql/091`. Dos premisas de la
  entrada eran falsas y vale dejarlas escritas: **eran tres funciones, no cuatro** —la cuarta que
  recibe arrays, `obras_transferir_resolver_vinculos`, no tiene GRANT a `authenticated`, así que
  blindarla era código muerto—, y **los schemas Zod ya tenían `.default([])`**, con el tipo
  rechazando `null`: lo que faltaba blindaba el PostgREST directo, no la UI.

- **La misma puerta sigue abierta en `obras_compartir_registros`**, encontrada al cerrar la de arriba:
  chequea `usuarios.activo` y no `obras_ver`. No se sumó a `sql/091` a propósito. Esa función la llama
  `core.compartir_registros` al **asignar una tarea**, así que un `RAISE` haría fallar la asignación
  entera porque el asignado no tiene Obras — que no es lo que quiere el que asigna. Lo más probable
  es que el receptor sin `obras_ver` tenga que **saltearse** esos registros, no voltear la llamada;
  eso es una decisión de Tareas, no de Obras, y va con la reparación del chip `?ctx=` de más arriba.

- ~~**La agenda se recorta en la query, no en la policy.**~~ — cerrada el 2026-09-18 escribiéndola
  como decisión (`decisiones/obras/visibilidad.md` → *El listado de la agenda se recorta en la query,
  y es deliberado*). **La segunda salida que ofrecía la entrada no existe**: la RLS de
  `obras_personas` no recibe contexto, así que "la policy pide ancla" no es implementable, y sacarle
  la rama contextual rompe al receptor legítimo — `getEstadoPersona` deja de traer la fila y la ficha
  con `?ctx=` responde 404. Lo que la policy autoriza es identidad; el contacto sigue fuera del
  `GRANT SELECT`. El corte de listado es de producto, no de autorización.

- ~~**`obras_migrar_agenda` conserva la copia del gate `OB006`.**~~ — cerrada por `sql/091`.

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

- ~~**La suite de tests de Obras está podrida, no solo `obras_085.sql`.**~~ — cerrada el 2026-09-18
  (`decisiones/obras/visibilidad.md` → *La red de regresión de compartir se reconstruye alrededor del
  acto que quedó*). Los nueve corren: `acceso_registros` 19/19, `asignar_con_acceso` 24/24, `eventos`
  28/28, `obras_model_a` 6/6 y `obras_compartir` 6/6 (nuevo); `obras_047`, `049`, `052`, `082` y `085`
  se retiraron a `obsoletos/sql-tests-share-directo/`.

  **La entrada acertaba el diagnóstico y subestimaba el trabajo en un sentido y lo sobrestimaba en
  otro.** Sobrestimaba: "portarlos" no aplicaba a cinco de los nueve — su sujeto era el share directo,
  que `sql/086` cerró, y lo que seguía valiendo cabía en seis casos. Subestimaba: dos archivos tenían
  una segunda podredumbre que nada tenía que ver con `sql/086`, y solo apareció al correrlos.
  `obras_model_a` fallaba en el setup (INSERT de permisos sin `ON CONFLICT` contra el UNIQUE), y
  `acceso_registros` caso 05 afirmaba lo contrario de lo que la base contesta desde `sql/082` — nadie
  lo había visto porque el archivo abortaba en el 09. **Ese caso 05 queda ahora como marcador vivo de
  la reparación del chip `?ctx=`**: hoy espera `false` y, cuando se haga, vuelve a esperar `true`.

  **Sigue en pie el desfase que la entrada nombraba aparte**: `sql/tests/obras_032.sql` caso 09 espera
  `SQLSTATE = 'OB009'` y `obras_ficha_persona` levanta `OB022` desde `sql/039` — va con la entrada de
  `OB009` de abajo. ~~`sql/tests/rls_obras.sql` caso 10~~ — corregido al cerrar `sql/092`.

**Y dos cambios estructurales que `sql/090` dejó a mitad**, de la misma auditoría. No son bugs: son
la forma de que la clase entera no vuelva.

- ~~**La vigencia del grant sigue escrita seis veces.**~~ — cerrada por `sql/092`
  (`decisiones/obras/visibilidad.md` → *La vigencia del grant contextual se escribe una sola vez*).
  **Dos premisas de la entrada eran falsas, y de la segunda salió V3.** Eran **siete** lugares, no
  seis, y `sql/090` la había hecho correcta en **cuatro**, no en los seis: los tres
  `obras_*_grant_ctx_*_conmigo` no se tocaron. Dos de ellos estaban cubiertos por su llamador, pero
  `obras_persona_grant_ctx_empresa_conmigo` —en `obras_persona_empresa_select`— no verificaba el
  ancla en ningún lado: un grant anclado en una empresa que el receptor ya no ve seguía dejando leer
  `cargo`, `es_principal` y `observaciones` por PostgREST directo. Identidad, no contacto, pero la
  misma clase que `sql/090` cerró. La recursión que la entrada anticipaba existe y no cicla: se
  verificó antes de escribirla.

- **`otorgada_por` todavía es autoridad, no solo historia.** Es lo que hace que una transferencia
  mal apuntada mueva *quién puede revocar*, que es el mecanismo exacto de V1. `sql/090` lo acotó
  —`obras_revocar_obra` ya no lo mira, y `obras_revocar_contextual` acepta dueño-del-ancla **o**
  otorgante— pero no lo retiró: la vista Compartido sigue listando por `otorgada_por = auth.uid()`,
  así que quién ve la fila y quién puede revocarla siguen siendo dos respuestas distintas. Lo
  correcto es derivar las dos del ancla (responsable de la obra / dueño de la empresa) y dejar
  `otorgada_por` como dato de log, que es lo que un log debería ser. Toca `obras_compartidos_por_mi`
  y el CHECK `usuario_id <> otorgada_por` deja de proteger nada — revisarlo antes de sacarlo.
