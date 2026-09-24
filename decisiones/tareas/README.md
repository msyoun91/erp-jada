# Decisiones — módulo tareas

Rediseño desde cero (2026-09-23). La versión anterior vive en `master` (su `decisiones/tareas/` y
`db_schema/tareas.md`); de ahí se trae lo listado en *Qué se trae de `master`* y nada más. Los
archivos de esta carpeta no repiten nombres de los de `master`: los punteros viejos de
`decisiones/global/` (`plantillas.md`, `visibilidad.md`, `integracion.md`…) siguen siendo de allá.

> **Estado: ficha aprobada (2026-09-24); SQL en curso desde `sql/112` (ver `BACKLOG.md`).** Las revisiones de agujeros (2026-09-23 y
> 2026-09-24, por escenarios) quedaron volcadas en la ficha y en los archivos por tema; lo del 24
> lleva fecha en cada decisión. Lo que cambie se corrige acá primero. Leer este índice y después
> solo el archivo del tema.

## Índice

| Archivo | Tema |
|---|---|
| `modelo.md` | Todo es un hilo · hilo híbrido · el asignado suma pasos · desactivar hilo y paso · `tarea` es ente · espera · resultado y cierre · reabrir en cascada · cancelado transparente · plazo relativo desde la habilitación · insertar antes de · abrir un paso es una sola regla |
| `participacion.md` | Visibilidad por hilo · el equipo participa · el delegador es el de usuarios · el admin asigna directo · un solo asignado · equipo participante guardado · columnas del que pide y del que hace · reasignar avisa · el admin completa lo ajeno · agente IA |
| `pedidos.md` | "Pedido" calculado · pedir es del responsable · `tareas_pedir` · sin `tareas_pedir` · devolver · volver a pedir · editar un pedido aceptado · reabrir un pedido |
| `bajas.md` | Solo se asigna a quien puede recibirlo · baja · los hilos se mueven todos · cambio de equipo · sin destino, huérfano · transferir a otro equipo |
| `registro.md` | `tareas_ediciones` y congelado · ocultar nota o historial · referencias en el texto · RLS de `tareas_vinculos` · ficha al lado |
| `catalogo.md` | Toda plantilla es personal · copia independiente · pasos sin asignado · plantilla que pide afuera · nunca falla por un asignado · "a revisar" · plantillas por evento |
| `recurrencia.md` | Recurrencia por hilo · intervalo · cada cierre genera · preguntar si sigue · qué copia el siguiente |

## Ficha del módulo

Armada con el usuario el 2026-09-23, revisada el 23 y el 24, aprobada el 2026-09-24.

```
Módulo: tareas
Objetivo: coordinar el trabajo individual, dentro de un equipo y entre equipos; seguir los
          pendientes propios y dejar registro de lo que implicó cada trabajo y del resultado que dio.

Personas
├── Miembro de equipo — ve los hilos donde participa, enteros: responsable, asignado de algún
│                       paso
│                     · crea hilos y pasos; asigna a sí mismo o a un compañero; con tareas_pedir
│                       pide a una persona de otro equipo o a otro equipo; acepta o rechaza lo
│                       que le piden; completa lo suyo (resultado opcional), pone en espera,
│                       agrega notas; edita y transfiere sus hilos; usa Misión; arma, usa y
│                       publica sus plantillas; copia del Catálogo
│                     · no ve hilos de su equipo donde no participa; nada de otros equipos fuera
│                       de los hilos donde participa
├── Delegador         — lo del miembro + todo hilo donde participe su equipo + la bandeja de
│                       pedidos y de lo asignado "al equipo"
│                     · acepta o rechaza los pedidos al equipo y a sus miembros; reparte lo del
│                       equipo; reasigna dentro del equipo; pide a otros equipos solo con tareas_pedir
│                     · no ve hilos de otros equipos donde el suyo no participa
├── Independiente     — ve lo mismo que el miembro
│                     · se asigna solo a sí mismo; con tareas_pedir pide a otros; acepta o
│                       rechaza lo que le piden
│                     · lo mismo que el miembro; sin bandeja
├── Admin del módulo  — ve todo · hace todo (completar lo ajeno: nota obligatoria, firmado), reactiva,
│                       despublica plantillas, otorga tareas_pedir · —
├── Agente IA         — sin persona propia: trabaja como persona, con sus funciones y las mismas
│                       restricciones; todo queda firmado con su cuenta
├── Supervisor        — NO existe
└── Cliente           — NO usa el módulo

Entes
├── hilo  — dueño responsable_id (transferible) · estado estado_hilo: abierto · cerrado
│           · datos {titulo} · ruta /tareas/{id} · submódulo tareas_ver
│           · resultado opcional al cerrar · recurrencia opcional (cada N días o meses): cada
│             cierre crea el siguiente, con los pasos copiados sin completar
│           · lo cierra el responsable, a mano, nunca solo · cerrado = congelado: se corrige con
│             nota o se reabre
│           · no cierra con pasos pendientes, solicitados o rechazados sin resolver;
│             sumar o reabrir un paso lo reabre
│           · no se comparte: visibilidad por participación · emite, no dispara
└── tarea — paso de un hilo · dueño: el responsable de su hilo (heredado); el asignado ejecuta
            · estado estado_tarea: solicitada · pendiente · rechazada · completada · cancelada
                solicitada → pendiente (aceptar) | rechazada (rechazar, motivo obligatorio)
                             | cancelada (el responsable retira)
                pendiente  → completada | cancelada
                             | solicitada (pedido: cambian título, descripción o vencimiento)
                             | rechazada (pedido: el receptor lo devuelve, motivo obligatorio)
                rechazada  → solicitada (volver a pedir: mismo u otro asignado afuera)
                             | pendiente (reasignar adentro del equipo del responsable)
                             | cancelada
                completada | cancelada → pendiente (reabrir) | solicitada (reabrir un pedido,
                  si no lo reabre el asignado)
                nacer y reasignar cualquier abierto: adentro del equipo del responsable =
                  pendiente; afuera = solicitada
                repartir o reasignar del delegador dentro de su equipo: conserva el estado
                  (el equipo ya decidió o decide)
            · derivados, no guardados: bloqueada (el primer previo no cancelado, subiendo la
              cadena, sin completar) · en espera
              (espera_hasta futura) · vencida
            · datos {titulo} · ruta /tareas/paso/{id} (abre el hilo en ese paso)
            · submódulo tareas_ver · visibilidad = la de su hilo · no se comparte · emite, no dispara
            · campos del responsable del hilo: título · descripción con referencias · asignado ·
              paso anterior · vence (fecha, o N días corridos desde que se habilita;
              lo segundo solo con paso anterior) · prioridad
            · campos del asignado: estado (aceptar/rechazar/completar) · espera_hasta + motivo ·
              resultado opcional · motivo de rechazo · notas
            · responsable = asignado → escribe todo
            · completada o cancelada = congelada: se corrige con nota o se reabre

No son entes
├── plantilla        — personal: la usa solo su dueño · compartir = publicar en el Catálogo
│                      · crea un hilo o suma pasos a uno existente
│                      · {dato} y {si hay ente:rol}…{fin}; pasos condicionados por rol
│                      · manual ahora; por evento cuando haya un emisor (activación por usuario)
│                      · publicada (la decide el dueño; el admin despublica) → Catálogo: se lee y
│                        se copia, sin asignados fijos y con el disparo apagado; datos, condiciones y pasos
│                        condicionados, tal cual
│                      · la copia es independiente: ni el original ni ella se afectan después;
│                        se puede editar y publicar como cualquier otra
│                      · copiada_de guarda el origen, solo como dato: link si el original sigue
│                        visible en el Catálogo, texto plano si no
│                      · paso asignado fuera del equipo de quien la usa: nace solicitado, exige
│                        tareas_pedir; sin él, queda "a revisar" y no se usa
│                      · paso sin asignado fijo: se elige al usarla
├── notas            — de paso y de hilo, solo se agregan · anota quien ve el hilo (insert =
│                      select; también en pasos congelados) · tareas_administrar las oculta
├── tareas_ediciones — log de contenido de hilo y paso: campo, anterior, nuevo, quién, cuándo ·
│                      lo escribe un trigger; nadie inserta, edita ni borra · tareas_administrar
│                      oculta una entrada
└── vínculos         — tareas_vinculos, derivada por la base de las referencias del texto

Relaciones
├── hilo → usuario           — responsable (columna) · transferir a otro equipo = a su delegador,
│                              con los pasos abiertos del equipo de origen
├── tarea → hilo             — pertenece (obligatoria)
├── tarea → usuario | equipo — asignado, exactamente uno
│                              · fuera del propio equipo (o cualquier otro, para un
│                                independiente) = pedido, exige tareas_pedir
│                              · la persona: activa y con tareas_ver · el equipo: con
│                                delegador activo
├── tarea → tarea            — paso anterior: mismo hilo, inmutable (salvo "insertar antes de"),
│                              sin ciclos; vacío = paralelo
│                              · no bifurca: un solo siguiente por paso (unique de sql/017)
├── tarea → cualquier ente   — referencia {ente:uuid} + copia del nombre en el texto
│                              · link ↗ (ficha al lado) si lo puede abrir; texto plano si no
│                              · tareas_vinculos derivada (rol + plantilla si vino de un disparo)
└── plantilla → usuario      — dueño

Acciones
├── hilo: crear (vacío o desde plantilla) · editar · transferir responsable · cerrar · reabrir
│         · cancelar pendientes y cerrar · desactivar (sin pasos completados; se lleva sus
│         pasos) · reactivar (admin)
├── tarea: sumar paso · insertar antes de · editar · asignar (en el equipo) · pedir (afuera, tareas_pedir) · aceptar
│          · rechazar (motivo) · volver a pedir · reasignar · repartir (equipo → persona) · poner en espera
│          · completar · reabrir · cancelar · agregar nota · referenciar ente · desactivar
│          (desde el último)
│          ├── asignado: acepta, rechaza, espera, completa, reabre lo suyo; suma pasos
│          │   asignados a sí mismo, en paralelo (sin previo)
│          ├── delegador del equipo receptor: decide también los pedidos a sus miembros
│          ├── responsable del hilo: edita, inserta, reasigna, cancela, reabre, resuelve rechazados;
│          │   NO completa pasos de otro
│          └── tareas_administrar: todo, registrado
└── plantilla: crear · editar · desactivar · usar · activar disparo · publicar/despublicar
               · copiar del Catálogo

Eventos que emite
├── hilo:  alta · estado · baja · reactivacion · transferencia ({anterior, nuevo}; entra al enum
│          tipo_evento con este emisor)
├── tarea: alta · estado (todo cambio, detalle {anterior, nuevo}) · baja · reactivacion
│          · relacion_alta / relacion_baja (asignado) — el valor anterior del contenido va en
│          tareas_ediciones
└── campanita, a partir de esos eventos:
    ├── (nunca al que hizo la acción)
    ├── (asignado = equipo → le llega a su delegador, en todos los avisos "al asignado")
    ├── tarea asignada    → el asignado
    ├── pedido recibido   → el asignado, y el delegador de la persona
    │                       (también cuando un pedido editado vuelve a solicitada, y al volver
    │                       a pedir un rechazado) · lo que asigna tareas_administrar nace
    │                       pendiente: "tarea asignada", solo al asignado
    ├── paso editado      → el asignado, por título, descripción o vencimiento, si no volvió a
    │                       solicitada (ahí va "pedido recibido"); sale de
    │                       tareas_ediciones (el contenido no emite evento)
    ├── pedido aceptado   → el responsable actual del hilo
    ├── pedido rechazado  → el responsable actual del hilo
    ├── paso reabierto    → el asignado
    ├── hilo transferido  → el nuevo responsable
    ├── paso habilitado   → el asignado, al habilitarse (se completa o se cancela el previo)
    ├── paso bloqueado    → el asignado, cuando un paso insertado antes lo bloquea
    ├── paso reasignado   → el responsable del hilo, cuando lo movió el delegador, la baja o el
    │                       cambio de equipo
    ├── paso quitado      → el asignado anterior, en toda reasignación hecha por una persona
    ├── paso a reasignar  → el responsable, cuando abrir el paso (recurrencia, disparo, reabrir,
    │                       reactivar) no pudo usar el asignado
    ├── paso sumado       → el responsable, cuando lo sumó un asignado
    ├── paso huérfano     → el responsable, cuando su asignado se fue sin delegador que lo reciba
    │                       o perdió tareas_ver
    ├── hilos huérfanos   → quienes tienen tareas_administrar, uno por hecho (la baja, la pérdida
    │                       de tareas_ver), no por hilo: "Pedro dejó 5 hilos huérfanos" → Todas filtrada
    ├── hilo dado de baja → los asignados de pasos abiertos
    ├── paso dado de baja → el asignado, si no lo desactivó él
    ├── paso completado   → el responsable del hilo
    └── paso cancelado    → el asignado
Eventos que consume
└── de otros módulos → disparar_plantillas. Sin emisor todavía: se conecta con el primero.
```

```
Módulo: Tareas
├── Hilos (vista, tareas_ver)                   — miembro, delegador, independiente, admin
│   └── tareas_pedir (funcion, no delegable)    — los que elija el admin, y el admin
├── Misión (vista, tareas_mision)               — miembro, delegador, independiente
├── Equipo (vista, tareas_equipo)               — delegador
│       bandeja: pedidos por decidir · asignado al equipo · hilos del equipo
│       · reparte y reasigna dentro del equipo (sin función aparte)
├── Plantillas (vista, tareas_plantillas)       — miembro, delegador, independiente, admin
│       pestañas: Mis plantillas · Catálogo
└── Todas (vista, tareas_todas)                 — admin
    │   filtro huérfanos: responsable o asignado inactivo o sin tareas_ver
    └── tareas_administrar (funcion)            — admin

Delegables
├── sí — tareas_ver · tareas_mision · tareas_plantillas
└── no — tareas_pedir · tareas_equipo · tareas_todas · tareas_administrar

Reglas entre permisos (filas de submodulo_reglas, en la migración de tareas)
├── tareas_equipo            requiere usuarios_delegar — un delegador por equipo
├── usuarios_delegar         requiere tareas_ver       — recibe bajas, cambios de equipo y transferencias
├── usuarios_delegar         requiere tareas_equipo    — todo delegador tiene bandeja
├── tareas_todas             requiere tareas_administrar — sola sería pestaña vacía o un supervisor,
│                                                        que no existe; con vista_id, van juntas
├── tareas_mision            requiere tareas_ver       — hilo y paso se abren con tareas_ver: sin él,
├── tareas_plantillas        requiere tareas_ver         filas que no se abren, un hilo creado que su
├── tareas_todas             requiere tareas_ver         responsable no ve, huérfanos sin transferir
├── tareas_administrar       requiere tareas_pedir     — el admin no tiene equipo: todo lo suyo es afuera
└── excluye: ninguna — admin vs. equipos sale de la membresía (US002), no de un par
    · vista → función no va como regla: ya la da vista_id
    · usuarios_delegar y tareas_equipo se requieren mutuamente: designar_delegador y
      quitar_delegador las dan y las quitan juntas
    · no otorgan tareas_ver: sin él, fallan con US016
```

## Qué se trae de `master`

- Triggers de la cadena (`sql/017`): bloqueada derivada, `cancelada` no traba (ahora transparente:
  *Un cancelado es transparente en la cadena*), previo inmutable (salvo *Insertar antes de*), no
  bifurca, desactivar desde la cola.
- Vencimiento tras el previo (`sql/053`, ahora desde la habilitación: *El plazo relativo corre
  desde que el paso se habilita*) y fecha de Argentina en las funciones (`sql/078`).
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
  `usuarios_select` no deja ver otros equipos. Por fila, además, si es de mi equipo y si puede
  recibir (*Solo se asigna a quien puede recibirlo*): la UI decide asignar o pedir sin otra consulta.
- Usuarios: las reglas del bloque *Reglas entre permisos* de la ficha, que la migración de tareas
  carga en `submodulo_reglas` (`sql/110`); el trigger y el panel de permisos ya las hacen valer.
  Quedan `designar_delegador` y `quitar_delegador`: mueven `tareas_equipo` junto con
  `usuarios_delegar`, y el heredero
  o designado necesita `tareas_ver` (`BACKLOG.md`).
- Core: vuelven `puede_abrir_registro` y `buscar_registros`; ramas de `hilo` y `tarea` en
  `etiqueta_registro` y `puede_ver_relacion` (`sql/109`).
