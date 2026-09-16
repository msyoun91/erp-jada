# Decisiones globales — Entes y eventos

## Un módulo se describe en entes, estados, propiedades, relaciones, acciones y eventos (2026-09-16)

Pedido del usuario: el ERP se armó módulo por módulo sin un modelo común, y Tareas ya consume registros
de Obras —chips, disparadores, roles, compartir al asignar— por piezas que fueron apareciendo una a una
(`sql/055`–`063`). Antes del próximo módulo, fijar el modelo para que lo que hoy Tareas le pide a Obras
se lo pueda pedir igual a cualquiera, y que un módulo nuevo nazca cumpliéndolo.

**Decidido: `.claude/guides/GUIDE_ENTES.md`.** El catálogo `entes` más `ENTES` (`lib/entes.ts`) es el
registro; las seis funciones genéricas de core (`etiqueta_registro`, `puede_abrir_registro`,
`puede_compartir_registro`, `compartir_registros`, `buscar_registros`, `relacionados_de_registro`) son
el contrato, y cada módulo suma su rama. La guía no inventa piezas: nombra lo que Obras ya cumple
entero y lo que Tareas no cumple todavía (abajo). Verificado contra el código antes de escribirla:
todo lo que pide existe una vez en `sql/059`–`062` y `db_schema/core.md`.

**Por qué una guía y no un framework.** La alternativa era una capa genérica —una tabla única de
registros, un motor de relaciones— que representara todo ente en un solo lugar. Descartada por
*Simplicidad antes que abstracción*: cada ente sigue en su tabla con su RLS, y lo cross-módulo es una
rama por módulo en seis funciones, que es exactamente lo que ya funciona. La ficha del módulo (§1 de
la guía) es la lista que el usuario aprueba antes del SQL, como ya lo era el árbol de vistas y
funciones.

**Un módulo no está obligado a tener entes** (aclarado por el usuario el 2026-09-16). El dashboard, un
módulo de reportes o uno de configuración no tienen; la ficha lo declara con `Entes: ninguno` y, sin
entes, no hay eventos que emitir. La ficha sigue siendo obligatoria: lo que se aprueba es la respuesta,
aunque sea "ninguno".

**"Propiedad" no es una tabla.** Una propiedad escalar es una columna; una relacional ("la obra tiene
desarrollador") es una fila de la tabla puente con ese rol. No hace falta un modelo de propiedades:
`relacionados_de_registro` ya expone las relacionales con su rol, y `entes.datos` las escalares
citables.

## Los eventos van a una tabla `eventos`, no a un trigger por consumidor (decidido, no construido)

Hoy el único evento es "entró a un estado", el único emisor es `obras` y el único consumidor
`disparar_plantillas`, un trigger directo sobre la tabla de obras (`sql/055`). El usuario pide que un
módulo emita también alta/baja del ente y alta/baja de una propiedad relacional, y que Tareas elija
"módulo + evento" como disparador.

**Alternativa descartada:** extender `disparar_plantillas` para derivar `alta`/`baja`/`estado` de
`OLD`/`NEW` y colgar un segundo trigger por tabla puente. Menos piezas para el primer consumidor, pero
cada consumidor nuevo (notificaciones, sugerencia de tareas, auditoría) vuelve a colgar sus propios
triggers de cada tabla de cada módulo, y la auditoría que `GUIDE_DB.md` exige —quién, qué, cuándo,
valor anterior— se sigue escribiendo aparte, como hoy `tareas_eventos` y `obras_transferencias`.

**Decidido, confirmado por el usuario el 2026-09-16 junto con la lista de eventos:** una tabla
`eventos (ente, registro_id, evento tipo_evento, detalle jsonb, actor_id, created_at)` que es a la vez el log y el punto donde escuchan los consumidores. Cada módulo la escribe
desde sus propios triggers con `emitir_evento(...)`; los consumidores cuelgan de `AFTER INSERT ON
eventos`. Sin `activo`: una auditoría no oculta sus filas, como `tareas_eventos`. RLS SELECT por
`etiqueta_registro(ente, registro_id) IS NOT NULL` — lo que no ves, no pasó.

- **`emitir_evento` es INVOKER, con policy de INSERT `pg_trigger_depth() > 0`** — el truco de
  `tareas_vinculos`. Con DEFINER, `current_user` pasa a `postgres` adentro de la función y los
  consumidores que exigen `authenticated` para correr con la RLS de quien actúa (`disparar_plantillas`)
  no dispararían. La guarda de `current_user` se hereda tal cual: un cambio hecho desde una función
  DEFINER (`obras_transferir`) queda logueado pero no dispara plantillas, como hoy.
- **Vocabulario:** los tres del pedido (`alta`/`baja`, `estado`, `relacion_alta`/`relacion_baja`) más
  `reactivacion` (el inverso de `baja` en un sistema sin DELETE), `transferencia` y
  `compartido`/`revocado` — los actos de MODEL A que Obras ya loguea por separado. Sin evento por
  columna escalar: sin consumidor es ruido y `updated_at` ya lo dice.
- **Se construye con el primer consumidor que necesite más que `estado`**: el selector "módulo +
  evento" de las plantillas (`BACKLOG.md` → *Tareas sobre el modelo de entes*). Ahí
  `disparar_plantillas` se muda a `eventos`, la plantilla gana `disparo_evento`, y `tareas_eventos`
  pasa a ser filas de `eventos` con `ente = 'tarea'`. Los logs que ya existen
  (`obras_transferencias`, `obras_aprobaciones`, `obras_accesos_persona`) no se duplican mientras
  vivan.

## "No existe" antes que "sin permiso"

Ya era la regla del sidebar (`GUIDE_DESIGN.md`) y de `etiqueta_registro` NULL (`sql/059`); se eleva a
regla de todo ente visto desde otro módulo: el chip no se dibuja, la ficha da `notFound()`, la búsqueda
no lo devuelve, el aviso queda sin nombre. Un solo `if()` y es esa función. La única excepción
registrada sigue siendo `sin_acceso` — deja confirmar que un uuid conocido no se puede abrir, sin
devolver el nombre (`decisiones/obras/visibilidad.md`).

## Un ente en un texto es una referencia, no un nombre (decidido, no construido)

Pedido para la descripción de tareas: un editor con hipervínculos a la ficha de cada ente. Se guarda
`{ente:uuid}` en el texto y se resuelve al mostrar con `etiqueta_registro`: link si lo ve, nada si no.
Mismo principio que *la notificación apunta, no copia* (`infra.md`). Los `{dato}` de plantillas siguen
siendo copia por diseño: el texto lo lee quien no ve el registro, y por eso `entes.datos` nunca lleva
contacto. El editor enriquecido es librería nueva: se consulta cuando se construya. Los chips
arrastrables, igual — sin librería de dnd el arrastre nativo no anda en touch
(`decisiones/tareas/plantillas.md`).

## Tareas leída con la guía (2026-09-16)

Prueba pedida por el usuario al cerrar la guía: llenar la ficha del módulo para Tareas sin
modificarlo. Resultado: la guía se aplica y deja una lista concreta; lo que falta está en
`BACKLOG.md` → *Tareas sobre el modelo de entes*.

```
Módulo: tareas
Entes
├── tarea    — dueño: los asignados (sql/013), no el creador · estado estado_tarea (no dispara) · ruta /tareas?tarea={id} · submódulo tareas_lista · en entes desde sql/067, no se comparte
├── hilo     — dueño responsable_id · estado estado_hilo · sin ficha propia (panel en la Lista)
└── proyecto — dueño: los miembros · sin estado · sin ficha propia
Relaciones
├── tarea ↔ usuario        — asignado / responsable  (tareas_asignados, tareas.responsable_id)
├── tarea → tarea          — paso anterior           (tareas.paso_anterior_id)
├── tarea ↔ hilo ↔ proyecto                          (columnas)
└── tarea ↔ cualquier ente — rol solo si lo vinculó un disparo (tareas_vinculos: ente + registro_id + plantilla_id + roles, sql/066)
Acciones — todas ya en Postgres con clase TA: crear · editar · completar · reasignar · convertir en hilo ·
           posponer · relacionar · usar y activar plantilla · cerrar hilo · archivar proyecto
Eventos que emite
├── tarea: estado → tareas_eventos (solo audita; nadie lo consume)
└── tarea: relacion_alta usuario → notificación tarea_asignada (un consumidor fijo, sin evento)
Eventos que consume
└── obra.estado → disparar_plantillas (ente + estado; no módulo + evento)
```

**Cumple:** acciones en Postgres; "no existe" (`vinculos_de_tareas` descarta el chip sin etiqueta);
consumo de entes ajenos por composición en `app/` (`TareasDeRegistro` en las fichas de Obras);
`useConfirmarAcceso` y `lib/accesos.ts` ya reutilizables; visibilidad que se amplía solo por acto
explícito (asignar), con el dueño definido por el módulo.

**No cumple:** ~~`tarea` no está en `entes` — ningún módulo puede relacionarse con una tarea, preguntar
`puede_abrir_registro('tarea', …)` ni buscarla~~ (entró en `sql/067`, `decisiones/tareas/integracion.md`); emite un solo evento y sin bus; el vínculo con un
registro no guarda rol (la plantilla elige el registro por `ente:rol`, pero `tareas_vinculos` no sabe
si esa persona es "el arquitecto de" la tarea); la descripción es texto plano; los chips son clic.
`hilo` y `proyecto` no se registran hasta que un módulo los necesite. `sql/064` se cerró el mismo día,
solo con los bugs de asignar y compartir (`decisiones/tareas/visibilidad.md`). El texto condicional de
las plantillas que traía se construyó después en `sql/065` (`decisiones/tareas/plantillas.md`), y el rol
del vínculo en `sql/066` (`decisiones/tareas/integracion.md`).
