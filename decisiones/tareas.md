# Decisiones — módulo tareas

Rediseño desde cero (2026-09-23). La versión anterior vive en `master` (`decisiones/tareas/`,
`db_schema/tareas.md`); de ahí se trae lo listado en *Qué se trae de `master`* y nada más.

> **Estado: ficha armada, sin SQL.** Antes de la migración se revisan agujeros contra esta ficha
> (visibilidad, escrituras por columna, pedidos, plantillas). Lo que cambie se corrige acá primero.

## Ficha del módulo

Armada con el usuario el 2026-09-23. Aprobación final pendiente de la revisión de agujeros.

```
Módulo: tareas
Objetivo: coordinar el trabajo individual, dentro de un equipo y entre equipos; seguir los
          pendientes propios y dejar registro de lo que implicó cada trabajo y del resultado que dio.

Personas
├── Miembro de equipo — ve los hilos donde participa, enteros: responsable, asignado de algún
│                       paso, o completó uno
│                     · crea hilos y pasos; asigna a sí mismo o a un compañero; con tareas_pedir
│                       pide a una persona de otro equipo o a otro equipo; acepta o rechaza lo
│                       que le piden; completa lo suyo (resultado opcional), pone en espera,
│                       agrega notas; edita y transfiere sus hilos; usa Misión; arma, publica y
│                       copia plantillas personales
│                     · no ve hilos de su equipo donde no participa; nada de otros equipos fuera
│                       de los hilos donde participa
├── Delegador         — lo del miembro + todo hilo donde participe su equipo + la bandeja de
│                       pedidos y de lo asignado "al equipo"
│                     · acepta o rechaza los pedidos al equipo y a sus miembros; reparte lo del
│                       equipo; reasigna dentro del equipo; arma y publica plantillas de equipo;
│                       pide a otros equipos solo con tareas_pedir
│                     · no ve hilos de otros equipos donde el suyo no participa
├── Independiente     — ve lo mismo que el miembro
│                     · se asigna solo a sí mismo; con tareas_pedir pide a otros; acepta o
│                       rechaza lo que le piden
│                     · lo mismo que el miembro; sin bandeja
├── Admin del módulo  — ve todo · hace todo (completar lo ajeno queda registrado), reactiva,
│                       plantillas globales, despublica, otorga tareas_pedir · —
├── Agente IA         — sin persona propia: trabaja como persona, con sus funciones y las mismas
│                       restricciones; todo queda firmado con su cuenta
├── Supervisor        — NO existe
└── Cliente           — NO usa el módulo

Entes
├── hilo  — dueño responsable_id (transferible) · estado estado_hilo: abierto · cerrado
│           · datos {titulo} · ruta /tareas/{id} · submódulo tareas_ver
│           · resultado opcional al cerrar · recurrencia opcional: al cerrarse nace el siguiente
│           · no cierra con pasos pendientes, solicitados o rechazados sin resolver;
│             sumar un paso lo reabre
│           · no se comparte: visibilidad por participación · emite, no dispara
└── tarea — paso de un hilo · dueño: el responsable de su hilo (heredado); el asignado ejecuta
            · estado estado_tarea: solicitada · pendiente · rechazada · completada · cancelada
                solicitada → pendiente (aceptar) | rechazada (rechazar, motivo obligatorio)
                rechazada → solicitada (el responsable reasigna) | cancelada
                pendiente de un pedido → solicitada si cambian título, descripción o vencimiento
                completada | cancelada → pendiente (reabrir)
                dentro del propio equipo nace pendiente; hacia afuera nace solicitada
            · derivados, no guardados: bloqueada (previo sin completar) · en espera
              (espera_hasta futura) · vencida
            · datos {titulo} · ruta /tareas/paso/{id} (abre el hilo en ese paso)
            · submódulo tareas_ver · visibilidad = la de su hilo · no se comparte · emite, no dispara
            · campos del responsable del hilo: título · descripción con referencias · asignado ·
              paso anterior · vence (fecha, o N días tras completar el previo) · prioridad
            · campos del asignado: estado (aceptar/rechazar/completar) · espera_hasta + motivo ·
              resultado opcional · motivo de rechazo · notas
            · responsable = asignado → escribe todo
            · completada o cancelada = congelada: se corrige con nota o se reabre

No son entes
├── plantilla        — alcance global (admin) · equipo (delegador) · personal (cada uno)
│                      · crea un hilo o suma pasos a uno existente
│                      · {dato} y {si hay ente:rol}…{fin}; pasos condicionados por rol
│                      · manual ahora; por evento cuando haya un emisor (activación por usuario)
│                      · publicada (la decide el dueño; el admin despublica) → Catálogo: se lee y
│                        se copia como personal, sin asignados fijos y con el disparo apagado
│                      · copiada_de guarda el origen
│                      · paso asignado fuera del equipo de quien la usa: nace solicitado, exige
│                        tareas_pedir
├── notas            — de paso y de hilo, solo se agregan
├── tareas_ediciones — log de contenido de hilo y paso: campo, anterior, nuevo, quién, cuándo ·
│                      lo escribe un trigger; nadie inserta, edita ni borra
└── vínculos         — tareas_vinculos, derivada por la base de las referencias del texto

Relaciones
├── hilo → usuario           — responsable (columna)
├── tarea → hilo             — pertenece (obligatoria)
├── tarea → usuario | equipo — asignado, exactamente uno
│                              · fuera del propio equipo (o cualquier otro, para un
│                                independiente) = pedido, exige tareas_pedir
├── tarea → tarea            — paso anterior: mismo hilo, inmutable, sin ciclos; vacío = paralelo
├── tarea → cualquier ente   — referencia {ente:uuid} + copia del nombre en el texto
│                              · link ↗ (ficha al lado) si lo puede abrir; texto plano si no
│                              · tareas_vinculos derivada (rol + plantilla si vino de un disparo)
└── plantilla → equipo | usuario — alcance

Acciones
├── hilo: crear (vacío o desde plantilla) · editar · transferir responsable · cerrar · reabrir
│         · desactivar (se lleva sus pasos) · reactivar (admin)
├── tarea: sumar paso · editar · asignar (en el equipo) · pedir (afuera, tareas_pedir) · aceptar
│          · rechazar (motivo) · reasignar · repartir (equipo → persona) · poner en espera
│          · completar · reabrir · cancelar · agregar nota · referenciar ente · desactivar
│          (desde el último)
│          ├── asignado: acepta, rechaza, espera, completa, reabre lo suyo
│          ├── delegador del equipo receptor: decide también los pedidos a sus miembros
│          ├── responsable del hilo: edita, reasigna, cancela, reabre, resuelve rechazados;
│          │   NO completa pasos de otro
│          └── tareas_administrar: todo, registrado
└── plantilla: crear · editar · desactivar · usar · activar disparo · publicar/despublicar
               · copiar del Catálogo

Eventos que emite
├── hilo:  alta · estado · baja · reactivacion
├── tarea: alta · estado (aceptar, rechazar, reabrir, volver a solicitada) · baja · reactivacion
│          · relacion_alta / relacion_baja (asignado) — el valor anterior del contenido va en
│          tareas_ediciones
└── campanita, a partir de esos eventos:
    ├── tarea asignada    → la persona
    ├── pedido recibido   → la persona o su delegador; al equipo, quien tiene tareas_equipo ahí
    │                       (también cuando un pedido editado vuelve a solicitada)
    ├── pedido aceptado   → quien pidió
    ├── pedido rechazado  → quien pidió y el responsable del hilo
    ├── paso reabierto    → el asignado
    ├── hilo transferido  → el nuevo responsable
    └── paso habilitado   → el asignado, al completarse el previo
Eventos que consume
└── de otros módulos → disparar_plantillas. Sin emisor todavía: se conecta con el primero.
```

```
Módulo: Tareas
├── Hilos (vista, tareas_ver)                   — miembro, delegador, independiente, admin
│   └── tareas_pedir (funcion, no delegable)    — los que elija el admin
├── Misión (vista, tareas_mision)               — miembro, delegador, independiente
├── Equipo (vista, tareas_equipo)               — delegador
│   │   bandeja: pedidos por decidir · asignado al equipo · hilos del equipo
│   └── tareas_repartir (funcion)               — delegador
├── Plantillas (vista, tareas_plantillas)       — miembro, delegador, independiente, admin
│   │   pestañas: Mis plantillas · Catálogo
│   ├── tareas_plantillas_equipo (funcion)      — delegador
│   └── tareas_plantillas_globales (funcion)    — admin
└── Todas (vista, tareas_todas)                 — admin
    └── tareas_administrar (funcion)            — admin

Delegables: todo salvo tareas_pedir, tareas_todas y tareas_administrar.
```

## Decisiones del diseño (2026-09-23)

**Todo es un hilo; no hay tareas sueltas.** "Comprar silicona" nace hilo de un paso y crece sin
conversión. En `master` la tarea suelta que se "convertía en hilo" eran dos modelos y un pasaje.

**Hilo híbrido: `paso_anterior_id` opcional.** Sin previo = paralelo; con previo = cadena. Una
columna; obligar a encadenar todo inventaba orden donde no lo hay.

**La unidad de visibilidad es el hilo, no el paso.** Quien ve un paso ve el hilo entero: sin
contexto el paso no se puede hacer bien. Ve el hilo quien participa (responsable, asignado, o quien
completó un paso), el que tiene `tareas_equipo` en un equipo participante, y `tareas_administrar`.
Un miembro no ve los hilos de su equipo donde no participa: lo propio queda privado sin flag.
Consecuencia: lo que un participante no debe leer va en otro hilo.

**Un solo asignado por paso, persona o equipo.** Dos personas = dos pasos: siempre claro quién
debe. Lo asignado al equipo lo reparte quien tiene `tareas_equipo` + `tareas_repartir`.

**Asignar fuera del equipo es un pedido, con función propia no delegable (`tareas_pedir`).** El
usuario quiere elegir qué líderes pueden pedir a otros equipos; delegable, cualquier delegador la
repartiría. El pedido nace `solicitada` y se acepta o rechaza (motivo obligatorio); decide el
receptor o el delegador de su equipo. Rechazar no cancela: el previo es inmutable y los siguientes
quedarían trabados, así que resuelve el responsable del hilo. Independiente: misma regla, todo otro
es "afuera" (opción a; la b era una excepción).

**`tarea` es ente, no solo `hilo`.** Se había propuesto sin ficha propia; no alcanza: completar es
el hecho central del registro y sin ente no llega a `eventos`, y otros módulos y la campanita
apuntan a un paso. Barato: dueño y visibilidad se heredan del hilo.

**Esperar es una fecha derivada, no un estado.** `espera_hasta` + motivo reemplaza a `en_espera` y
al posponer de `master`: la misma idea dos veces. Se deriva como "bloqueada".

**Resultado opcional**, en el paso y en el hilo.

**Quien pide y quien hace escriben columnas distintas, y completar es solo del asignado.**
Pedido del usuario: que nadie —persona o agente— cambie lo pedido y lo marque hecho. El contenido
es del responsable del hilo; estado, espera, resultado y notas, del asignado. `GRANT UPDATE` por
columna + trigger, como `validar_gestionar_tarea` en `master`.

**Toda edición de contenido deja historial (`tareas_ediciones`) y lo cerrado se congela.**
`eventos` no guarda valor anterior (`decisiones/global/entes.md`), por eso tabla aparte escrita por
trigger. Completado o cancelado no se edita: nota o reabrir, que emite y avisa.

**Editar título, descripción o vencimiento de un pedido aceptado lo devuelve a `solicitada`.**
Elegido por el usuario sobre "solo avisar": lo aceptado no cambia sin volver a aceptarse. La
prioridad no lo devuelve: ordena, no cambia el trabajo.

**El agente IA trabaja como persona.** Sin reglas propias; la base no distingue agente de persona
(`decisiones/usuarios.md`) y el usuario no quiere que lo haga por ahora.

**Referencias en el texto en vez de chips.** `{nombre}` de la plantilla se guarda como
`{obra:uuid}` + copia del nombre; se ve como link ↗ que abre la ficha al lado si se puede abrir, y
como texto plano si no. Aplica *Un ente en un texto es una referencia* (`decisiones/global/entes.md`).
`tareas_vinculos` queda como dato (hilos de un registro, `plantilla_disparada`) y la escribe la
base desde el texto: una sola fuente. Vincular a mano: textarea + "Relacionar" que inserta la
marca, con vista previa; editor enriquecido solo si no alcanza (librería nueva, consultar).

**La ficha del ente se abre al lado del paso.** Split en desktop, encima con "volver" en mobile.
Cada módulo con entes aporta su ficha; el registro ente → componente vive en `app/`.

**Plantillas en tres alcances y Catálogo.** Global (admin), equipo (delegador), personal. El dueño
decide publicarla; del Catálogo se copia —nunca se usa directo, para no depender de ediciones
ajenas—, sin asignados fijos y con el disparo apagado. `copiada_de` guarda el origen.

**Plantillas por evento esperan a su primer emisor.** Hoy ningún módulo emite; se construyen las
manuales y `disparar_plantillas` se conecta después.

**Recurrencia a nivel hilo**: al cerrarse nace el siguiente. Sin `pg_cron`, como en `master`.

## Qué se trae de `master`

- Triggers de la cadena (`sql/017`): bloqueada derivada, `cancelada` no traba, previo inmutable,
  desactivar desde la cola.
- Vencimiento tras el previo (`sql/053`) y fecha de Argentina en las funciones (`sql/078`).
- Notas append-only (`sql/008`, `sql/077`).
- Motor de plantillas: `guardar_plantilla`, `usar_plantilla`, `rellenar_datos`, condiciones por
  rol, activaciones, `disparar_plantillas`, `plantilla_disparada`.
- Escrituras multi-tabla como función `SECURITY INVOKER` (`sql/023`), id generado antes del
  INSERT, largos por CHECK.
- UI: `Isla`, paneles de hilo y paso, `NotasSection`, `CompletarModal`, `CerrarHiloModal`,
  `cadenaPasos.ts` (con test), `tareaLabels.ts`, `useTareaOptimista`, vista Misión.

**No se trae:** proyectos y su visibilidad pública/privada, tareas sueltas y la conversión,
multi-asignado (`tareas_asignados`), `modo_completado`, `origen_app`, `tareas_gestionar_ajenas`,
`tareas_asignar`, chips.

## Lo que el módulo necesita de afuera

- Una función que devuelva solo nombre de usuarios y equipos activos, para asignar y pedir:
  `usuarios_select` no deja ver otros equipos.
- Core: vuelven `puede_abrir_registro` y `buscar_registros`; ramas de `hilo` y `tarea` en
  `etiqueta_registro` y `puede_ver_relacion` (`sql/109`).
