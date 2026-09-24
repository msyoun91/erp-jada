# Decisiones — módulo tareas

Rediseño desde cero (2026-09-23). La versión anterior vive en `master` (`decisiones/tareas/`,
`db_schema/tareas.md`); de ahí se trae lo listado en *Qué se trae de `master`* y nada más.

> **Estado: ficha armada y revisada, sin SQL.** Las revisiones de agujeros (2026-09-23 y
> 2026-09-24, por escenarios) quedaron volcadas en la ficha y en *Decisiones del diseño*; lo del
> 24 lleva fecha en cada decisión. Lo que cambie se corrige acá primero.

## Ficha del módulo

Armada con el usuario el 2026-09-23. Revisada el mismo día; falta la aprobación final.

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
├── Admin del módulo  — ve todo · hace todo (completar lo ajeno: nota obligatoria, firmado), reactiva,
│                       plantillas globales, despublica, otorga tareas_pedir · —
├── Agente IA         — sin persona propia: trabaja como persona, con sus funciones y las mismas
│                       restricciones; todo queda firmado con su cuenta
├── Supervisor        — NO existe
└── Cliente           — NO usa el módulo

Entes
├── hilo  — dueño responsable_id (transferible) · estado estado_hilo: abierto · cerrado
│           · datos {titulo} · ruta /tareas/{id} · submódulo tareas_ver
│           · resultado opcional al cerrar · recurrencia opcional: cada cierre crea el siguiente,
│             con los pasos copiados sin completar
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
                rechazada  → cancelada
                completada | cancelada → pendiente (reabrir) | solicitada (reabrir un pedido,
                  si no lo reabre el asignado)
                nacer y reasignar cualquier abierto: adentro del equipo del responsable =
                  pendiente; afuera = solicitada
                repartir o reasignar del delegador dentro de su equipo: conserva el estado
                  (el equipo ya decidió o decide)
            · derivados, no guardados: bloqueada (previo sin completar) · en espera
              (espera_hasta futura) · vencida
            · datos {titulo} · ruta /tareas/paso/{id} (abre el hilo en ese paso)
            · submódulo tareas_ver · visibilidad = la de su hilo · no se comparte · emite, no dispara
            · campos del responsable del hilo: título · descripción con referencias · asignado ·
              paso anterior · vence (fecha, o N días corridos tras completar el previo;
              lo segundo solo con paso anterior) · prioridad
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
│                        se copia como personal (o de equipo, con tareas_plantillas_equipo), sin
│                        asignados fijos y con el disparo apagado; datos, condiciones y pasos
│                        condicionados, tal cual
│                      · la copia es independiente: ni el original ni ella se afectan después;
│                        se puede editar y publicar como cualquier otra
│                      · copiada_de guarda el origen, solo como dato: link si el original sigue
│                        visible en el Catálogo, texto plano si no
│                      · paso asignado fuera del equipo de quien la usa: nace solicitado, exige
│                        tareas_pedir; sin él, la plantilla no se muestra
│                      · paso sin asignado fijo: se elige al usarla
├── notas            — de paso y de hilo, solo se agregan · anota quien ve el hilo (insert =
│                      select; también en pasos congelados)
├── tareas_ediciones — log de contenido de hilo y paso: campo, anterior, nuevo, quién, cuándo ·
│                      lo escribe un trigger; nadie inserta, edita ni borra
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
├── tarea → tarea            — paso anterior: mismo hilo, inmutable, sin ciclos; vacío = paralelo
├── tarea → cualquier ente   — referencia {ente:uuid} + copia del nombre en el texto
│                              · link ↗ (ficha al lado) si lo puede abrir; texto plano si no
│                              · tareas_vinculos derivada (rol + plantilla si vino de un disparo)
└── plantilla → equipo | usuario — alcance

Acciones
├── hilo: crear (vacío o desde plantilla) · editar · transferir responsable · cerrar · reabrir
│         · cancelar pendientes y cerrar · desactivar (sin pasos completados; se lleva sus
│         pasos) · reactivar (admin)
├── tarea: sumar paso · editar · asignar (en el equipo) · pedir (afuera, tareas_pedir) · aceptar
│          · rechazar (motivo) · reasignar · repartir (equipo → persona) · poner en espera
│          · completar · reabrir · cancelar · agregar nota · referenciar ente · desactivar
│          (desde el último)
│          ├── asignado: acepta, rechaza, espera, completa, reabre lo suyo; suma pasos
│          │   asignados a sí mismo, colgados del suyo
│          ├── delegador del equipo receptor: decide también los pedidos a sus miembros
│          ├── responsable del hilo: edita, reasigna, cancela, reabre, resuelve rechazados;
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
    │                       (también cuando un pedido editado vuelve a solicitada)
    ├── paso editado      → el asignado, por título, descripción o vencimiento, si no volvió a
    │                       solicitada (ahí va "pedido recibido"); sale de
    │                       tareas_ediciones (el contenido no emite evento)
    ├── pedido aceptado   → el responsable actual del hilo
    ├── pedido rechazado  → el responsable actual del hilo
    ├── paso reabierto    → el asignado
    ├── hilo transferido  → el nuevo responsable
    ├── paso habilitado   → el asignado, al completarse el previo
    ├── paso reasignado   → el responsable del hilo, cuando lo movió el delegador, la baja o el
    │                       cambio de equipo
    ├── paso quitado      → el asignado anterior, en toda reasignación hecha por una persona
    ├── paso a reasignar  → el responsable, cuando la recurrencia o un disparo no pudo usar el
    │                       asignado
    ├── paso sumado       → el responsable, cuando lo sumó un asignado
    ├── paso huérfano     → el responsable, cuando su asignado se fue sin delegador que lo reciba
    │                       o perdió tareas_ver
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
│   └── tareas_pedir (funcion, no delegable)    — los que elija el admin
├── Misión (vista, tareas_mision)               — miembro, delegador, independiente
├── Equipo (vista, tareas_equipo)               — delegador
│       bandeja: pedidos por decidir · asignado al equipo · hilos del equipo
│       · reparte y reasigna dentro del equipo (sin función aparte)
├── Plantillas (vista, tareas_plantillas)       — miembro, delegador, independiente, admin
│   │   pestañas: Mis plantillas · Catálogo
│   ├── tareas_plantillas_equipo (funcion)      — delegador
│   └── tareas_plantillas_globales (funcion)    — admin
└── Todas (vista, tareas_todas)                 — admin
    │   filtro huérfanos: responsable o asignado inactivo o sin tareas_ver
    └── tareas_administrar (funcion)            — admin

Delegables
├── sí — tareas_ver · tareas_mision · tareas_plantillas
└── no — tareas_pedir · tareas_equipo · tareas_plantillas_equipo
         · tareas_plantillas_globales · tareas_todas · tareas_administrar

Reglas entre permisos (filas de submodulo_reglas, en la migración de tareas)
├── tareas_equipo            requiere usuarios_delegar — un delegador por equipo
├── usuarios_delegar         requiere tareas_ver       — recibe bajas, cambios de equipo y transferencias
├── usuarios_delegar         requiere tareas_equipo    — todo delegador tiene bandeja
├── tareas_plantillas_equipo requiere tareas_equipo    — la plantilla de equipo es de quien lleva la bandeja
├── tareas_todas             requiere tareas_administrar — sola sería pestaña vacía o un supervisor,
│                                                        que no existe; con vista_id, van juntas
└── excluye: ninguna — admin vs. equipos sale de la membresía (US002), no de un par
    · vista → función no va como regla: ya la da vista_id
    · usuarios_delegar y tareas_equipo se requieren mutuamente: designar_delegador y
      quitar_delegador las dan y las quitan juntas
    · no otorgan tareas_ver: sin él, fallan con US016
```

## Decisiones del diseño (2026-09-23)

**Todo es un hilo; no hay tareas sueltas.** "Comprar silicona" nace hilo de un paso y crece sin
conversión. En `master` la tarea suelta que se "convertía en hilo" eran dos modelos y un pasaje.

**Hilo híbrido: `paso_anterior_id` opcional.** Sin previo = paralelo; con previo = cadena. Una
columna; obligar a encadenar todo inventaba orden donde no lo hay.

**La unidad de visibilidad es el hilo, no el paso.** Quien ve un paso ve el hilo entero: sin
contexto el paso no se puede hacer bien. Ve el hilo quien participa (responsable o asignado de algún
paso), el que tiene `tareas_equipo` en un equipo participante, y `tareas_administrar`. "Completó un
paso" se sacó el 2026-09-24: un completado está congelado y sigue asignado; solo sumaba el caso
reabierto y reasignado a otro, y ese ya recibe "paso quitado".
Un miembro no ve los hilos de su equipo donde no participa: lo propio queda privado sin flag.
Consecuencia: lo que un participante no debe leer va en otro hilo.

**El equipo participa si participa cualquier miembro.** El delegador ve todo hilo cuyo `equipo_id`,
o el de alguno de sus pasos, es su equipo (*El equipo participante se guarda en el momento*). Incluye lo que
un miembro arma para sí. La vista Equipo filtra por miembro y por tipo (pedidos, al equipo, del
equipo). Lo asignado al equipo sin repartir lo ve solo el delegador, y mientras tanto él hace de
asignado: completa, pone en espera, agrega resultado.

**El delegador de tareas es el de usuarios.** `tareas_equipo` no es delegable,
y `tareas_equipo` y `usuarios_delegar` se exigen mutuamente. Así, una sola persona por equipo ve la
bandeja y recibe lo que dejan una baja, un cambio de equipo o una transferencia, y todo equipo con
delegador tiene quien reciba lo asignado "al equipo". Como ninguna de las dos se puede tener sola,
`designar_delegador` y `quitar_delegador` las mueven juntas; no es "marcar solo" en el panel, es el
mismo rol. Puede reasignar un paso abierto entre
miembros de su equipo, o desde el equipo a un miembro. Es una excepción por columna en el trigger, y
se avisa al responsable del hilo.

**Con `tareas_administrar` se asigna directo.** El admin del sistema no está en ningún equipo
(`US002`), así que sin esto todo lo suyo sería pedido; el paso nace `pendiente`.

**Pedir es un acto del responsable del hilo, y el aviso de la respuesta va al responsable actual.**
Sin columna `pedido_por`: quién pidió en su momento queda en `eventos`.

**El asignado puede sumar pasos para sí, colgados del suyo.** Sirve para subdividir su trabajo sin
pedírselo al responsable, que recibe el aviso. El contenido sigue siendo del responsable después de
creado.

**Desactivar un hilo con pasos abiertos de otros se puede, y les avisa.** Solo si no tiene pasos
completados (2026-09-24, misma regla que el paso): desactivar es error de carga, y lo desactivado lo
ve solo el admin en Todas, que lo reactiva. Si ya hubo trabajo, "ya no va" es cancelar lo abierto y
cerrar con resultado: queda como registro. Atajo "Cancelar pendientes y cerrar", una función.

**Un solo asignado por paso, persona o equipo.** Dos personas = dos pasos: siempre claro quién
debe. Lo asignado al equipo lo reparte quien tiene `tareas_equipo`: sin `tareas_repartir` aparte
(2026-09-24), que la tenía siempre la misma persona y olvidarla dejaba la bandeja sin reparto.

**Asignar fuera del equipo es un pedido, con función propia no delegable (`tareas_pedir`).** El
usuario quiere elegir qué líderes pueden pedir a otros equipos; delegable, cualquier delegador la
repartiría. El pedido nace `solicitada` y se acepta o rechaza (motivo obligatorio); decide el
receptor o el delegador de su equipo. Rechazar no cancela: el previo es inmutable y los siguientes
quedarían trabados, así que resuelve el responsable del hilo. Independiente: misma regla, todo otro
es "afuera" (opción a; la b era una excepción).

**Un pedido aceptado se puede devolver (2026-09-24).** `pendiente → rechazada` con motivo, solo en
pedidos: sin salida, lo que el receptor ya no puede hacer figuraba como compromiso vigente y
trababa los siguientes. Reusa el rechazo, su resolución y su aviso. Dentro del equipo no hace
falta: el responsable es un compañero y reasigna.

**Solo se asigna a quien puede recibirlo.** Asignar, pedir, repartir, reasignar y transferir el
hilo (sumado el 2026-09-24: sin eso nacía un responsable que no ve su hilo) exigen en la base
que la persona esté activa y tenga `tareas_ver`, y que el equipo tenga delegador activo (el único
con `tareas_equipo`); si no, el paso queda invisible o sin quien lo decida. El selector ofrece solo a
quien cumple. Si el receptor pierde `tareas_ver` después, sus pasos quedan huérfanos y se avisa al
responsable (*Sin destino, queda huérfano*); si lo recupera, vuelve a verlos.

**La baja de un usuario pasa sus pasos abiertos y sus hilos al delegador de su equipo.** El
delegador de usuarios (`usuarios_delegar`), que es uno solo; si el que se va es el delegador, a su
heredero. Sin delegador, o si es independiente, no se mueve nada (*Sin destino, queda huérfano*). Para que el
destino cumpla *Solo se asigna a quien puede recibirlo*, el delegador tiene que tener `tareas_ver`
(decisión del usuario). Trigger de tareas
sobre `usuarios.activo`; completados y cancelados no se tocan (son registro).

**Los hilos se mueven todos, abiertos y cerrados (2026-09-24).** En la baja y en el cambio de
equipo. Un hilo cerrado se reabre cuando un asignado reabre o suma un paso, y quedaba con un
responsable inactivo (nadie lo gestiona, la recurrencia no nace) o de otro equipo (vuelve a tener
trabajo abierto del anterior). `responsable_id` es quién lo gestiona hoy; quién lo gestionó, en
`eventos`. Los pasos cerrados no se tocan. Aviso solo por los abiertos; el filtro "huérfanos"
muestra solo hilos abiertos.

**Quien cambia de equipo entrega todo lo abierto al anterior (2026-09-24).** Sus hilos y todos sus
pasos abiertos —también los pedidos de otros equipos que aceptó— pasan al delegador del equipo
anterior, como en la baja. Lo que aceptó lo aceptó como miembro de ese equipo: es compromiso del
equipo, no de la persona, y quien cambia no sigue lo del equipo anterior. Así tampoco importa que al
cambiar pierda lo delegado (`tareas_ver` incluido): no le queda nada abierto. Trigger de tareas
sobre `equipos_miembros`.

**Sin destino, queda huérfano (2026-09-24).** Si el equipo no tiene delegador (se creó sin
designarlo, o salió sin heredero) o la persona es independiente, la baja y el cambio de equipo no
mueven nada: hilos y pasos quedan con ella. Todas suma el filtro "huérfanos" (responsable o
asignado inactivo o sin `tareas_ver`) y el admin transfiere desde ahí. Perder `tareas_ver` a mano
también deja huérfano, sin mover nada. El responsable de cada hilo con un paso huérfano recibe aviso: puede reasignarlo él sin esperar al admin. Se descartó exigir
delegador en todo equipo: tocaba `usuarios` y la baja del último miembro activo seguía sin destino
—bloquearla no sirve, a un despedido se lo banea en el acto—.

**Transferir un hilo a otro equipo lo entrega al delegador de ese equipo.** El responsable pasa a
ser el delegador del equipo destino, y los pasos abiertos con `equipo_id` = equipo de origen
—personas y el equipo mismo; precisado el 2026-09-24, antes quedaba afuera lo asignado "al
equipo" sin repartir— pasan también a él para que los reparta o los vuelva a pedir. Los pasos de terceros equipos no
cambian. Exige `tareas_pedir` y es inmediata, sin aceptación: el delegador recibe el aviso. A un
independiente, las mismas reglas con él como destino.

**~~"Equipo participante" se calcula con la membresía actual~~** → *El equipo participante se guarda
en el momento*.

**El equipo participante se guarda en el momento (2026-09-24).** `tarea.equipo_id` = equipo del
asignado al asignar (o el equipo asignado); `hilo.equipo_id` = equipo del responsable al crear o
transferir. Equipo participante = esos `equipo_id`, sin `equipo_de()`. Con la membresía actual, quien
cambiaba de equipo se llevaba la historia: el delegador nuevo veía los hilos (también abiertos) del
equipo viejo, y el viejo dejaba de ver su propio trabajo. Baja, cambio de equipo y transferencia
reescriben la columna en lo abierto; lo cerrado conserva el equipo con que se hizo. La persona sigue
viendo lo suyo por participación.

**`tarea` es ente, no solo `hilo`.** Se había propuesto sin ficha propia; no alcanza: completar es
el hecho central del registro y sin ente no llega a `eventos`, y otros módulos y la campanita
apuntan a un paso. Barato: dueño y visibilidad se heredan del hilo.

**Esperar es una fecha derivada, no un estado.** `espera_hasta` + motivo reemplaza a `en_espera` y
al posponer de `master`: la misma idea dos veces. Se deriva como "en espera", aparte de "bloqueada".

La espera se limpia cuando el paso deja de estar `pendiente` o cambia de asignado (2026-09-24):
si no, el nuevo asignado heredaba una espera ajena, un pedido vuelto a `solicitada` quedaba en
espera sin aceptarse y un reabierto volvía con fecha vieja. Trigger, sin estado nuevo.

**Resultado opcional**, en el paso y en el hilo.

**Quien pide y quien hace escriben columnas distintas, y completar es solo del asignado.**
Pedido del usuario: que nadie —persona o agente— cambie lo pedido y lo marque hecho. El contenido
es del responsable del hilo; estado, espera, resultado y notas, del asignado. `GRANT UPDATE` por
columna + trigger, como `validar_gestionar_tarea` en `master`.

**Reasignar avisa al que pierde el paso (2026-09-24).** El responsable puede reasignarse un paso
ajeno y completarlo: queda en `eventos` y `tareas_ediciones`, pero el asignado anterior no se
enteraba. Se descartó prohibirlo (Luis se enferma y Ana lo termina) y exigir motivo (fricción en
algo habitual). Vale igual para el delegador y el admin; no para la baja.

**Excepción: `tareas_administrar` puede editar y completar lo ajeno.** Lo exige *Siempre hay una
función que administra el módulo* (`decisiones/global/permisos.md`). Completar algo ajeno pide nota
obligatoria y queda firmado en `eventos`. Aplica igual si esa función la tiene un agente IA.

**Reabrir un paso reabre en cascada sus siguientes completados (2026-09-24).** Elegido por el
usuario sobre "reabrir desde el final". Si no, lo que siguió quedaba completado sobre un previo en
corrección, y el siguiente abierto seguía habilitado. Recorre la cadena entera; los cancelados no
se tocan. Cada asignado recibe "paso reabierto"; un pedido reabierto por otro vuelve a `solicitada`
(*Reabrir un pedido…*). Lo abierto más abajo queda bloqueado solo, por la regla de siempre.

**Solo se desactiva un paso no congelado (2026-09-24).** `solicitada`, `pendiente` o `rechazada`;
completado o cancelado, solo `tareas_administrar`. Desactivar es para un error de carga; cancelar es
decidir no hacerlo. Si no, el responsable borraba de la vista un trabajo que no puede editar. Para
sacar un completado, primero se reabre, y reabrir avisa al asignado.

**Toda edición de contenido deja historial (`tareas_ediciones`) y lo cerrado se congela.**
`eventos` no guarda valor anterior (`decisiones/global/entes.md`), por eso tabla aparte escrita por
trigger. Completado o cancelado no se edita: nota o reabrir, que emite y avisa.

**Editar título, descripción o vencimiento de un pedido aceptado lo devuelve a `solicitada`.**
Elegido por el usuario sobre "solo avisar": lo aceptado no cambia sin volver a aceptarse. La
prioridad no lo devuelve: ordena, no cambia el trabajo.

**Reabrir un pedido lo vuelve a `solicitada`, salvo que lo reabra el asignado (2026-09-24).** Si
no, rechazar → cancelar → reabrir dejaba `pendiente` algo que el receptor había rechazado, y un
pedido cancelado antes de responderse volvía aceptado sin que nadie lo aceptara. Es la regla de
nacimiento aplicada al reabrir: afuera del equipo del responsable = pedido, exige `tareas_pedir`.
El asignado que reabre lo suyo lo retoma él: `pendiente`.

**El agente IA trabaja como persona.** Sin reglas propias; la base no distingue agente de persona
(`decisiones/usuarios.md`) y el usuario no quiere que lo haga por ahora.

**Referencias en el texto en vez de chips.** `{nombre}` de la plantilla se guarda como
`{obra:uuid}` + copia del nombre; se ve como link ↗ que abre la ficha al lado si se puede abrir, y
como texto plano si no. Aplica *Un ente en un texto es una referencia* (`decisiones/global/entes.md`),
corregida para mostrar la copia en vez de nada: el paso tiene que entenderse, y el nombre lo contó
quien sí lo veía.
`tareas_vinculos` queda como dato (hilos de un registro, `plantilla_disparada`) y la escribe la
base desde el texto: una sola fuente. Vincular a mano: textarea + "Relacionar" que inserta la
marca, con vista previa; editor enriquecido solo si no alcanza (librería nueva, consultar).

**La RLS de `tareas_vinculos` es la del hilo, no la del ente referenciado (2026-09-24).** Quien ve
una obra pero no participa de un hilo que la nombra no ve ese hilo en la ficha de la obra. El título
sale siempre de `etiqueta_registro` (INVOKER, hereda la RLS), nunca de una copia.

**La ficha del ente se abre al lado del paso.** Split en desktop, encima con "volver" en mobile.
Cada módulo con entes aporta su ficha; el registro ente → componente vive en `app/`.

**Plantillas en tres alcances y Catálogo.** Global (admin), equipo (delegador), personal. El dueño
decide publicarla; del Catálogo se copia —nunca se usa directo, para no depender de ediciones
ajenas—, sin asignados fijos y con el disparo apagado. `copiada_de` guarda el origen.

**La copia del Catálogo es independiente y `copiada_de` es solo historia.** Sin aviso de "el
original cambió": pediría versión y destinatarios, y se suma sin tocar el esquema si hace falta. El
origen se muestra como link si sigue visible en el Catálogo y como texto plano si no, como las
referencias. La copia se publica si su dueño quiere; las casi duplicadas las despublica el admin.
El delegador copia directo como plantilla de equipo, sin pasar por personal. Sin asignados fijos,
un pedido del original no se hereda: se elige al usarla y rige `tareas_pedir`.

**Los pasos sin asignado fijo se asignan al usar la plantilla.** El formulario pide uno por paso
vacío, con quien la usa como valor por defecto. Nunca nace un paso sin dueño.

**Una plantilla que pide afuera no se le muestra a quien no tiene `tareas_pedir`.** Decisión del
usuario. `usar_plantilla` lo rechaza igual en la base: ocultarla no autoriza. Si un asignado
elegido al usar la plantilla cae afuera, se aplica la regla de siempre: pedido con `tareas_pedir`.

**Una plantilla nunca falla por un asignado (2026-09-24).** Manual: el fijo que ya no puede recibir
se trata como paso vacío (se elige, con quien la usa por defecto, y se avisa). Disparo: el asignado
inválido, el paso vacío o el pedido sin `tareas_pedir` quedan en quien activó el disparo —el
responsable del hilo creado— con aviso "paso a reasignar", como la recurrencia. Si el activador ya
no puede recibir, el disparo se saltea; la baja apaga sus activaciones. Un disparo nunca voltea la
transacción del emisor: lo inesperado se registra y se avisa al activador, y la obra se crea igual.

**Plantillas por evento esperan a su primer emisor.** Hoy ningún módulo emite; se construyen las
manuales y `disparar_plantillas` se conecta después.

**Recurrencia a nivel hilo**: al cerrarse nace el siguiente. Sin `pg_cron`, como en `master`.

**Cada cierre genera un siguiente, también tras reabrir.** Elegido por el usuario sobre guardar
`siguiente_id`: reabrir y volver a cerrar da otro ciclo, y el duplicado se cuida a mano.
Precisado el 2026-09-24: ahora reabre cualquier asignado, y en cascada, así que quien cierra no
sabe que ya se generó. El hilo nuevo guarda `recurrencia_de`; si ya existe un siguiente, el cierre
pregunta "ya generó <link> — ¿generar otro?", con "no" por defecto. De paso, navega entre ciclos.

**El siguiente copia los pasos, sin lo hecho.** Títulos, descripciones, cadena, asignados y
prioridad, todo sin completar; los vencimientos se corren por el intervalo desde el vencimiento
anterior, no desde el cierre, sin saltear ciclos: cada ciclo es un período, el atrasado nace
vencido y se descarta con "Cancelar pendientes y cerrar". Fin de mes sigue siendo fin de mes (si
el anterior era el último día, el siguiente también); el 29 o 30 que cae en febrero queda en 28.
Los relativos al previo se copian tal cual (precisado el 2026-09-24). Sin notas, resultados
ni historial. El estado no se copia: cada paso nace con las reglas de siempre, con la membresía
de hoy (precisado el 2026-09-24; copiar dejaba `pendiente` a un compañero que ya era de otro
equipo). Un paso cuyo asignado no puede recibir (*Solo se asigna a quien puede recibirlo*), o que
sería un pedido y el responsable ya no tiene `tareas_pedir`, nace asignado al responsable con aviso
para reasignarlo: la recurrencia nunca falla. Los pedidos válidos nacen `solicitada` y se vuelven a
aceptar. Se copia el asignado final: si el delegador repartió "al equipo" a Juan, el siguiente va
a Juan.

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
  `usuarios_select` no deja ver otros equipos. Por fila, además, si es de mi equipo y si puede
  recibir (*Solo se asigna a quien puede recibirlo*): la UI decide asignar o pedir sin otra consulta.
- Usuarios: las reglas del bloque *Reglas entre permisos* de la ficha, que la migración de tareas
  carga en `submodulo_reglas` (`sql/110`); el trigger y el panel de permisos ya las hacen valer.
  Quedan `designar_delegador` y `quitar_delegador`: mueven `tareas_equipo` junto con
  `usuarios_delegar`, al saliente se le apaga también `tareas_plantillas_equipo`, y el heredero
  o designado necesita `tareas_ver` (`BACKLOG.md`).
- Core: vuelven `puede_abrir_registro` y `buscar_registros`; ramas de `hilo` y `tarea` en
  `etiqueta_registro` y `puede_ver_relacion` (`sql/109`).
