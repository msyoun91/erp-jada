# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## erp-cliente — falta el `ThemeToggle`

Vive en `SidebarNav` y el portal no tiene sidebar todavía. Va cuando el portal arranque de verdad
(`decisiones/global/ui.md` → *El script de tema va en `<script>` plano*).

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

El vínculo ya no es bloqueante: `sql/055` hace que `tareas_vinculos` guarde `(tarea, ente, registro, plantilla)` de lo que genera un disparo, así que una sugerencia puede saber si la tarea ya existe. Ver `decisiones/tareas/plantillas.md` → *Plantillas disparadas por estado*.

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

**Marcador vivo:** `sql/tests/acceso_registros.sql` caso 05 hoy espera `false`; cuando se haga la
reparación vuelve a esperar `true`.

**Dos cosas más van con esta reparación**, de la auditoría de compartir/transferir (2026-09-18):

- **`obras_compartir_registros` chequea `usuarios.activo` y no `obras_ver`.** No se sumó a `sql/091`
  a propósito: un `RAISE` haría fallar la asignación entera porque el asignado no tiene Obras — que no
  es lo que quiere el que asigna. Lo más probable es que el receptor sin `obras_ver` tenga que
  **saltearse** esos registros, no voltear la llamada; eso es una decisión de Tareas, no de Obras.
- **El buscador marca `es_ajeno` a quien sí se puede abrir.** `obras_buscar_personas` / `_empresas`
  resuelven con `obras_puede_ver_*`, que no cuenta contextuales. Correcto para no meterlo en la
  agenda, pero al receptor le muestra "de Fulano, sin link" a un contacto que abre normal desde la
  obra. Si se toca, el link va con `?ctx=`.

## Segunda pasada de la auditoría de compartir/transferir (2026-09-18)

Todo verificado contra la base en transacción revertida; exposición real al escribirla, 0 filas. Lo
cerrado está en `decisiones/obras/visibilidad.md` (`sql/095`, `sql/096`, `sql/099`).

**Decidido, sin implementar:**

- **`sql/tests/obras_033.sql` no corre desde `sql/040`**: lee `obras_obra_persona.pendiente`, que
  esa migración dropeó. No está muerto entero: solo perdieron su sujeto los casos del vínculo
  pendiente (04–07 y 24–25; el 15 usa como montaje la fila del 05). Altas pendientes, cola,
  aprobar/rechazar, el UPDATE bloqueado y el referente ajeno siguen vigentes. Se arregla sacando esos
  casos y corriéndolo.
