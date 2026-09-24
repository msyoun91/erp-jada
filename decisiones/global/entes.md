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

## Los eventos van a una tabla `eventos`, no a un trigger por consumidor (`sql/068`)

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
- **Se construyó con el primer consumidor que necesita más que `estado`** (2026-09-16): el selector de
  evento de las plantillas (`decisiones/tareas/plantillas.md` → *Plantillas disparadas por un evento*).
  `disparar_plantillas` se mudó a `eventos` y `tareas_eventos` pasó a ser filas de `eventos` con
  `ente = 'tarea'`. Los logs que ya existen (`obras_transferencias`, `obras_aprobaciones`,
  `obras_accesos_persona`) no se duplican mientras vivan.

Lo que se decidió al construirlo, verificado contra el código:

- **Mudar `tareas_eventos` cambia quién ve la Auditoría, y el usuario lo aceptó.** Su policy era
  `usuario_id = auth.uid() OR tareas_auditoria`; la de `eventos` es `etiqueta_registro`, que para una
  tarea pide verla y que esté activa. Un manager deja de ver lo completado en tareas archivadas o que no
  puede abrir. Alternativa ofrecida y descartada: dejar `tareas_eventos` hasta que un consumidor
  necesite eventos de tareas.
- **`entes` gana `tabla` y `disparos`.** El disparo, colgado de `eventos`, ya no tiene la fila en
  `NEW`: la lee de `entes.tabla` con la RLS de quien actuó (una lectura, no una séptima función
  cross-módulo). `disparos` separa "emite" de "puede disparar": `estados` NULL ya no alcanza para decirlo.
- **Baja y reactivación de una obra no disparan.** Pasan por `obras_set_activo`, DEFINER, y la guarda
  de `current_user` las deja afuera: ofrecerlas sería guardar una plantilla que nunca corre. Quedan en el
  log. Lo mismo vale para lo que cambie `obras_revocar_obra`.
- **Una tarea emite pero no dispara**: una plantilla colgada del alta de una tarea crearía otra que la
  volvería a disparar. `disparos` vacío, y las policies de INSERT/UPDATE de `tareas_plantillas` lo
  exigen además de `guardar_plantilla`.
- **Un evento de relación por rol**, del lado del primer ente de la tabla puente (la obra), con
  `{ente, registro_id, rol}` como decía la guía. Sumarle un rol a un vínculo que ya existe es un alta;
  sacarle uno, una baja. Así una plantilla elige "cuando la obra suma un arquitecto" sin mirar arrays.
- **El enum lleva solo lo que alguien emite.** `transferencia`, `compartido` y `revocado` se suman con
  su primer emisor: agregar un valor es una línea, y hasta entonces un editor no puede ofrecerlos.

Archivos: `sql/068_eventos.sql`, `sql/tests/eventos.sql`, `db_schema/core.md`.

## Un evento de relación lo ve quien ve el vínculo (`sql/069`)

**Para ver un `relacion_alta`/`relacion_baja` no alcanza con ver el ente: hay que ver algún vínculo del
par.** La RLS de `sql/068` pedía solo ver la obra, y el receptor de una obra compartida —que ve la obra
pero de sus vínculos solo los suyos y lo tildado (`sql/051`)— leía el id y el rol de cada contacto que
no le compartieron. `puede_ver_relacion` hace un EXISTS sobre la puente con su propia RLS: la regla
sigue en las policies de vínculo, sin copia.

Descartado: pedir que se vean los dos entes. Es una segunda regla y erra para los dos lados: el
responsable dejaría de ver lo que sumó un receptor con un contacto privado, y el receptor vería un
vínculo que la policy le oculta (su persona, vinculada por el responsable). Es por par y no por fila
porque `detalle` no guarda qué fila emitió; guardarla obligaba a completar a mano los eventos que ya
había.

Archivos: `sql/069_eventos_relacion_visible.sql`, `sql/tests/eventos.sql` (26–28), `db_schema/core.md`,
`db_schema/obras.md`, `.claude/guides/GUIDE_ENTES.md` §2.3 y §2.8.

## "No existe" antes que "sin permiso"

Ya era la regla del sidebar (`GUIDE_DESIGN.md`) y de `etiqueta_registro` NULL (`sql/059`); se eleva a
regla de todo ente visto desde otro módulo: el chip no se dibuja, la ficha da `notFound()`, la búsqueda
no lo devuelve, el aviso queda sin nombre. Un solo `if()` y es esa función. La única excepción
registrada sigue siendo `sin_acceso` — deja confirmar que un uuid conocido no se puede abrir, sin
devolver el nombre (`decisiones/obras/visibilidad.md`).

## Un ente en un texto es una referencia, no un nombre (decidido, no construido)

Pedido para la descripción de tareas: un editor con hipervínculos a la ficha de cada ente. Se guarda
`{ente:uuid}` en el texto y se resuelve al mostrar con `etiqueta_registro`: link si lo ve, nada si no.
**Corregido el 2026-09-23 (rediseño de tareas):** se guarda también la copia del nombre, y quien no lo
ve lee esa copia como texto plano, sin link. Es la excepción a "no existe antes que sin permiso": el
nombre lo escribió alguien que sí lo veía y eligió contarlo, igual que un `{dato}` de plantilla
(`decisiones/tareas/registro.md` → *Referencias en el texto en vez de chips*).
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
├── tarea    — dueño: los asignados (sql/013), no el creador · estado estado_tarea · ruta /tareas?tarea={id} · submódulo tareas_lista · en entes desde sql/067, no se comparte, no dispara
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
├── tarea: alta · baja · reactivacion · estado → eventos (sql/068; audita, nadie lo consume)
└── tarea: relacion_alta usuario → notificación tarea_asignada (un consumidor fijo, sin evento)
Eventos que consume
└── obra: alta · estado · relacion_alta · relacion_baja → disparar_plantillas (sql/068)
```

**Cumple:** acciones en Postgres; "no existe" (`vinculos_de_tareas` descarta el chip sin etiqueta);
consumo de entes ajenos por composición en `app/` (`TareasDeRegistro` en las fichas de Obras);
`useConfirmarAcceso` y `lib/accesos.ts` ya reutilizables; visibilidad que se amplía solo por acto
explícito (asignar), con el dueño definido por el módulo.

**No cumple:** ~~`tarea` no está en `entes` — ningún módulo puede relacionarse con una tarea, preguntar
`puede_abrir_registro('tarea', …)` ni buscarla~~ (entró en `sql/067`, `decisiones/tareas/integracion.md`); ~~emite un solo evento y sin bus~~ (`sql/068`, abajo); ~~el vínculo con un
registro no guarda rol~~ (`sql/066`); la descripción es texto plano; los chips son clic.
`hilo` y `proyecto` no se registran hasta que un módulo los necesite. `sql/064` se cerró el mismo día,
solo con los bugs de asignar y compartir (`decisiones/tareas/visibilidad.md`). El texto condicional de
las plantillas que traía se construyó después en `sql/065` (`decisiones/tareas/plantillas.md`), y el rol
del vínculo en `sql/066` (`decisiones/tareas/integracion.md`).

## `entes` y `eventos` vuelven antes que Tareas, sin ningún ente (`sql/109`, 2026-09-23)

**La infra cross-módulo vuelve sola, antes que el módulo que la usa.** Pedido del usuario al arrancar el
rediseño de Tareas: el diseño ya estaba escrito (`GUIDE_ENTES.md`, las secciones de arriba) y solo
faltaba el código que `sql/101` se llevó. `sql/109` trae `entes` (con `tabla` y `disparos` desde el
nacimiento), `tipo_evento`, `eventos` y los tres emisores con los cuerpos de `sql/068`.

**De las siete genéricas vuelven dos, y sin ramas.** `etiqueta_registro` y `puede_ver_relacion` porque las
pide la RLS de `eventos`; responden "no" hasta que un ente les sume su rama. Las demás esperan a su
primer llamador: `puede_abrir_registro` y `buscar_registros` vienen con Tareas, y
`compartir_registros`, `puede_compartir_registro` y `sin_acceso` cuando esté decidido cómo se comparte
con un equipo — el rediseño de Tareas suma tareas de equipo e interequipo, y escribirlas antes sería
escribirlas dos veces. `disparar_plantillas` no es infra: es el consumidor que trae Tareas.

**`entes.ruta` exige `{id}` por CHECK.** En `master` era convención de la guía; un ente sin `{id}` en la
ruta rompe todo chip y todo link, y es una línea.

Archivos: `sql/109_entes_eventos.sql`, `sql/tests/entes_eventos.sql`, `db_schema/core.md`,
`database.types.ts`.
