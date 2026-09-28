# Decisiones — módulo obras

> **Estado: ficha aprobada (2026-09-25), después de revisarla punto por punto con el usuario. Tramo 1
> del SQL (`sql/126`, `sql/128`) aplicado el 2026-09-26; lo que sigue, en `BACKLOG.md`.** Rediseño desde cero: el usuario pidió no partir de lo que había en `master`. Los
> contactos son de otro módulo: `decisiones/contactos.md`. Orden de construcción en `BACKLOG.md`.

## La obra es del equipo comercial (2026-09-25)

**Obras sigue la obra del lado comercial; los demás equipos trabajan la etapa, no la obra.**
Administración, producción y logística actúan según el estado de cada presupuesto (módulo futuro), y
post-venta tiene su módulo aparte. Así la obra y sus contactos comerciales no salen de comercial, sin
marcas por contacto. Se había propuesto antes que logística y colocación vieran la obra; el usuario lo
cambió al definir que el módulo es de comercial.

**La visibilidad copia la de Tareas.** Allá, un hilo lo ve quien participa, el delegador de un
equipo participante y el admin. Acá, una obra la ven el responsable, sus participantes, el jefe comercial
sobre las del equipo, y `obras_todas`. El equipo se guarda en el momento (`obra.equipo_id` al crear
y al transferir; el de cada participante al sumarlo), como `hilo.equipo_id`. Compartir una obra es sumar
un participante: no hay tabla `_compartida` ni cascada, porque los contactos se ven con el registro
(`decisiones/contactos.md`).

**Un segundo vendedor entra como participante (2026-09-25).** Pedido del usuario: una obra puede
trabajarla más de un vendedor. Mismo modelo que el asignado de Tareas: la persona sumada la ve y la
trabaja sin ser la responsable.

**El jefe comercial es el delegador del equipo: `obras_equipo` requiere `usuarios_delegar`.** Igual
que `tareas_equipo`, una sola persona por equipo. No va al revés: los delegadores de logística o
producción no usan Obras.

**El jefe actúa solo sobre `obra.equipo_id`; el del equipo de un participante solo la ve (2026-09-26).**
Juan (Norte) es responsable de Belgrano y suma a Pedro (Sur): Laura, jefa de Sur, la ve y nada más; no
edita, no cambia el estado, no vincula, no ve la comisión. Los poderes de responsable (transferir,
desactivar, comisión) son del jefe de Norte. Si Pedro se va de Sur, la participación se cierra por la
baja o el cambio de equipo, no por Laura. Tampoco toca los contactos de la obra: no vincula, no cierra
vínculos ni corrige a la arquitecta; Contactos le pregunta a Obras quién trabaja la obra
(`decisiones/contactos.md` → *Ver no es trabajar*, 2026-09-26).

**La comisión del referente se registra ya, y la ven solo el vendedor responsable y el jefe comercial
(2026-09-25).** Más el admin. Va sobre el vínculo con rol referente (`obras_comisiones`), así "ser
referente" sigue siendo el rol del vínculo y no se duplica; varios referentes, una comisión cada uno.
Es la única sección de la obra con regla propia: su RLS es responsable, `obras_equipo` sobre el equipo
de la obra, u `obras_administrar`, sin submódulo nuevo. El participante ve la obra, pero no la comisión.
Porcentaje o monto, uno de los dos por referente, a elección de quien la carga (CHECK: exactamente uno).

**El monto lleva moneda, USD por defecto; la comisión no se edita, se reemplaza (2026-09-28).** En
general se pacta en dólares, pero un monto sin moneda se lee mal el día que uno se pacta en pesos:
`moneda` (ARS · USD) obligatoria con monto, nula con porcentaje (CHECK). El porcentaje es "de lo
contratado", sin base hasta que existan Presupuestos. Cambiarla desactiva la fila y crea otra
(`created_by`, `created_at`): las inactivas son el historial ("Antes: 3 % — Juan, 12/10"), con la misma
RLS que la vigente, sin tabla de log. Una activa por vínculo (unique parcial `WHERE activo`).

**Un vínculo con comisión activa lo toca solo quien ve la comisión (2026-09-26).** Si no, un participante
le saca "referente" o lo desactiva "por error" y la comisión queda colgada sin que el responsable se
entere. Sacar el rol referente, cerrar o desactivar ese vínculo: el participante no puede, la base lo
frena con "Este referente lo maneja el responsable de la obra" (sin nombrar la comisión). Responsable,
jefe de la obra y admin sí, y la comisión se desactiva junto, con aviso previo en pantalla. Trigger de
Obras sobre `contactos_vinculos`. Descartado: apagarla sola aunque lo haga el participante (el
responsable la pierde sin saber) y bloquear a todos (obliga a borrarla a mano primero).

**"Ve la comisión" es tener la obra a cargo: `obras_a_cargo_de`, sin regla propia (2026-09-28).**
Responsable, jefe sobre `obra.equipo_id` y admin son exactamente los de transferir y desactivar; una
segunda regla igual sería duplicación. Con la obra desactivada no la ve nadie, como sus vínculos.
Quien la registró va en `creado_por` (no `created_by`: nombre de dominio). Archivos: `sql/142`,
`sql/tests/obras_comisiones.sql`.

**La comisión se ve en la fila del referente, no en una sección aparte (2026-09-28).** Elegido por el
usuario: queda junto a quien la cobra, sin repetir su nombre. Contactos le deja a cada vínculo un
`extras` (lo que se ve y un aviso para cerrar, sacar o cambiar el rol), y `obras/[id]/page.tsx` lo llena
con `ComisionReferente`: Contactos no sabe qué es una comisión. Archivos:
`modules/obras/components/ComisionReferente.tsx`, `modules/contactos/components/VinculosSeccion.tsx`.

## Los nombres de lo que se ve (2026-09-28)

**`obras_nombres()` y `contactos_nombres()` dan el nombre de quienes figuran en lo que se ve;
`usuarios_con_permiso(codigo)`, a quién se transfiere o se suma.** `usuarios_select` no deja ver otros
equipos: la ficha de una obra quedaba sin responsable ni participantes, y transferir, sin candidatos.
Mismo patrón que `tareas_nombres()` y `tareas_asignables()` (`decisiones/tareas/participacion.md`).
Los candidatos son una sola función de core por permiso, no una por módulo: la regla es "tiene el
permiso", igual para obras (`obras_ver`) y personas (`contactos_ver`). `obras_a_cargo(obra)` es el
envoltorio con `auth.uid()` de `obras_a_cargo_de`, para mostrar los botones sin copiar la regla.
Archivos: `sql/130`, `sql/131`, `sql/tests/obras_nombres.sql`.

## Bajas y cambios de equipo (2026-09-25)

**La baja o el cambio de equipo de un vendedor pasa sus obras al jefe del equipo guardado en cada
obra, como los hilos de Tareas** (`decisiones/tareas/bajas.md`). Todas: abiertas, perdidas (se pueden
reabrir) y contratadas (siguen teniendo movimiento comercial). Sus participaciones se cierran. Si el que se
va es el jefe, van a su heredero. Sin jefe, o si era independiente, quedan a su nombre, huérfanas: Todas
tiene el filtro "huérfanas" y el admin transfiere desde ahí.

Por qué moverlas y no dejar que el jefe las reparta a mano, si igual las ve: las plantillas "Sobre: obra"
corren a nombre del responsable, y con uno inactivo fallan hasta que alguien reasigne. Y quien cambia de
equipo, como responsable, seguiría viendo obras comerciales desde el equipo nuevo.

**Huérfana es "el responsable ya no ve Obras", no solo "inactivo" (2026-09-28).** Como en Tareas:
perder `obras_ver` (a mano, o al cambiar de equipo y perder lo delegado) también deja la obra sin quien
la trabaje, y avisa a `obras_administrar` igual que la baja. **Quien entra a un equipo desde
independiente le pone ese equipo a sus obras y participaciones activas sin equipo**; si no, el jefe
nuevo no las ve. Archivos: `sql/133`.

**Transferir (2026-09-25).** Pueden transferir el responsable (sus obras), el jefe (las del equipo) y el
admin, y solo a alguien activo y con `obras_ver`. El `equipo_id` pasa a ser el del nuevo responsable:
si es de otro equipo comercial, deja de verla el jefe anterior y la ve el del nuevo. Participantes y
contactos no cambian; la comisión la ve el nuevo responsable. Quien transfiere deja de verla, salvo que
marque "quedarme como participante" (desmarcado por defecto).

**Desactivar es para lo cargado por error, no reemplaza a "perdida" (2026-09-25).** La perdida
queda en el embudo y se reabre; la desactivada desaparece salvo para el admin. Desactivan el
responsable, el jefe y el admin; reactiva el admin. Una contratada no se desactiva (con Presupuestos,
tampoco una con presupuestos activos). Vínculos, comisión y participantes quedan y dejan de verse por
esa obra; los hilos que la nombran siguen, sin el link. Reactivar devuelve todo.

## Altas parecidas: congeladas hasta que se aprueban (2026-09-25)

**Una obra que se parece a otra existente (nombre y dirección, contra todas las obras) entra congelada,
y la resuelve quien tenga `obras_aprobar`.** Pedido del usuario, sobre el sistema que había en `master`
(`decisiones/obras/duplicados-aprobaciones.md` de esa rama). Se evaluó solo avisar y dejar que el jefe
resolviera después, y el usuario eligió congelar. Contactos hace lo mismo con personas y empresas
(`decisiones/contactos.md`).

- **Qué es parecida (2026-09-28): el criterio de `master`, con la dirección atada a sus números.**
  Trigramas sobre el texto normalizado (minúsculas, sin acentos). Obra: nombre ≥ 0,45, o dirección
  ≥ 0,45 **con los mismos números** ("Libertador 1200" y "Av. del Libertador 1200" sí; "Libertador 1250",
  no: sin eso, cualquier obra sobre la misma avenida se congelaba). Persona: mismo teléfono, mismo email,
  o nombre ≥ 0,55. Empresa: nombre ≥ 0,45. Contra todo lo activo, congeladas incluidas (dos cargas de la
  misma obra mientras espera también se frenan).
- **Aviso a ciegas antes de guardar:** de lo parecido que no ve, solo el nombre de la obra y el de su
  responsable.
- **El aviso ordena por parecido (2026-09-28).** Corta en 10: primero lo que ve, después (contactos) mismo
  teléfono o email, después el nombre más parecido, y el nombre como desempate. Ordenado solo por nombre,
  la igual podía quedar afuera detrás de diez parecidas que ordenaban antes. `sql/141`.
- **Editar también congela (2026-09-26).** Si no, se esquiva: cargar "Obra X" en "Calle 1" y
  renombrarla. Solo cuando la edición cambia un dato comparado (obra: nombre, dirección; persona:
  nombre, teléfono, email; empresa: nombre) y el valor nuevo coincide con otro registro; notas u otros
  campos, no. La ven los que ya la veían, y sus vínculos siguen; se frena lo mismo que en el alta (no se
  vincula, no cambia de estado, no se transfiere). Salidas: aprobar (homónima) · rechazar con motivo,
  que vuelve el dato a su valor anterior sin desactivar (el registro era válido, no el cambio).
  Descartado: aceptarlo (el aviso a ciegas no alcanza) y avisar sin congelar. ~~"Es la misma"~~, ver
  abajo *"Es la misma" es solo para un alta*.
- **Lo que se congela, en la fila (2026-09-28).** Obra, persona y empresa llevan `congelada boolean`,
  `congelada_antes jsonb` (los datos comparados como estaban aprobados; NULL si es un alta) y
  `rechazo_motivo`. Rechazar un alta la desactiva; rechazar una edición restaura `congelada_antes` y
  descongela. Editar de nuevo mientras espera no pisa `congelada_antes`; si deja de parecerse, se
  descongela sola y sale de "Por aprobar". Descartado: un historial de ediciones de obras solo para esto.
- **"Ver todo" incluye las congeladas (2026-09-28).** `obras_todas` y el admin (y `contactos_todas`, si
  llega) las ven, marcadas "por aprobar": su permiso es ver todo. Resolverlas sigue siendo solo de
  `obras_aprobar` / `contactos_aprobar`.
- **Congelada:** la ve solo quien la cargó, y la puede editar. No se vincula, no cambia de estado, no se
  transfiere y no dispara plantillas: para Tareas, el alta cuenta desde que se aprueba. El bloqueo va en
  la base, con triggers y error de clase propia, no con policies (el 42501 diría "sin permiso"). Es lo
  que en `master` recién quedó firme con `sql/098`.
- **Aprueba `obras_aprobar`, no el jefe** (decisión del usuario). Es una función que asigna el admin y no
  se delega. En "Por aprobar" ve todas las altas congeladas: la nueva completa y, de cada parecida, nombre,
  dirección y responsable, sin contactos. Las altas de quien tiene la función no se congelan.
- **Tres salidas:** aprobar · rechazar con motivo (se desactiva, no se fusiona) · "es la misma"
  (se rechaza y quien la cargó queda como participante de la existente: dos vendedores sobre el mismo
  edificio siguen trabajándolo juntos).
- **"Es la misma" lleva a la existente el vínculo guardado del alta (2026-09-26).** Marta, referente de
  Pedro, lo llama por Torre Belgrano; la carga con "¿Quién? = Marta", entra congelada porque Juan ya la
  tenía, y el aprobador marca "es la misma": Marta queda como referente de la de Juan, sin preguntarle
  al aprobador. No cruza dueños: Marta es de Pedro, que ya participa y trabaja la obra; es lo que haría
  él a mano. Si la existente ya tenía a Marta abierta, se suman los roles, y un paso "vincular referente"
  se completa solo. Rechazar descarta el vínculo; Marta sigue en la agenda de Pedro. La comisión la
  registra Juan, y Pedro no la ve (participante); si el responsable tiene que ser Pedro, se transfiere.
- **"Es la misma" es solo para un alta (2026-09-28, al escribir `sql/139`).** En una edición, las dos
  obras ya existían, con vínculos, historial y quizás presupuestos: unirlas es fusionar (tramo 4), no
  desactivar una. La edición parecida se aprueba o se rechaza. `obras_resolver`, OB022.
- **La existente queda en la fila: `misma_que` (2026-09-28).** Obra, persona y empresa. Es lo que
  permite a "es la misma" sumar a quien cargó como participante sin tener la obra a cargo (la fila con
  `misma_que`, en la misma transacción, autoriza OB013), y al aviso linkear a la existente.
- **El vínculo con una punta congelada: se guarda solo en el paso en que nace (2026-09-28).** Crear y
  vincular, o el "¿Quién?" del alta, van a `contactos_vinculos_guardados` si la obra o el contacto
  nacen congelados en esa misma transacción (`created_at = now()`: el cliente no lo escribe). Vincular
  después a algo congelado es CO020. Así `obras_alta` y `contactos_crear_y_vincular` no cambiaron: el
  trigger de vincular decide. Archivos: `sql/139`.
- **El aviso de la decisión va al dueño (2026-09-28).** Al responsable de la obra o la persona, y a
  quien cargó la empresa. En un alta es quien la cargó; en una edición, el dueño y no quien editó (no
  se guarda quién editó). Con "es la misma", Pedro recibe además "te sumaron a Torre Belgrano".
- **Avisos:** "alta por aprobar" a quienes tienen `obras_aprobar`; la decisión, con motivo, a quien la
  cargó. Con "es la misma", también al responsable de la existente: "Pedro se sumó a Torre Belgrano, con
  Marta Gómez como referente". La acción es del aprobador, así que "sumado a una obra" solo avisaba a
  Pedro.

- **Las pantallas (2026-09-28).** "Por aprobar" es un botón con el conteo en la barra de Obras (y de
  Contactos), no una tab: `obras_aprobar` es función, y la guía da tabs solo a las vistas. Abre
  `/obras/por-aprobar` (`/contactos/por-aprobar`), que valida la función en el `page.tsx`. El aviso a
  ciegas frena el primer "Crear" o "Guardar" y lo cambia a "Crear igual"; el segundo intento con los
  mismos datos pasa y la base congela. Editar solo pregunta si cambió un dato comparado. En el
  "¿Quién?" del alta el aviso va en vivo mientras se escribe, con "Elegir esa" si es tuya. Una persona
  con mismo teléfono o email no muestra "Aprobar" habilitado (CO023). Archivos:
  `modules/{obras,contactos}/components/PorAprobarView.tsx`, `modules/contactos/components/Parecidas.tsx`,
  `ObraFormPanel.tsx`.

## Los estados son solo comerciales (2026-09-25)

**El estado de la obra dice en qué punto está la relación comercial, no qué se está haciendo.** Lo
operativo es el estado de cada presupuesto, leído al mostrarlo. La ficha de la obra lista sus
presupuestos con su estado actual y un link ("Etapa 1 ↗ — en producción", "Etapa 2 ↗ — en
cotización"): composición en `app/` (`GUIDE_ENTES.md` §2.7), sin columnas en Obras.

**Con un presupuesto en producción y otro en cotización, la obra está `contratada`.** Contratada es
final. Cotizar la etapa 2 no la devuelve atrás: la cotización se ve en su presupuesto y sus tareas
salen de ahí. En la lista, un contador calculado al mostrar ("contratada · 1 en cotización") evita
perderla de vista.

Descartado: un estado de obra que resuma sus etapas (en ejecución, post-venta), guardado y movido por la
base. Iba y venía con cada etapa, pedía una tabla de prioridades, y las plantillas de un estado se
disparan una sola vez por obra (`decisiones/tareas/catalogo.md` → *Un disparo no se repite*): la etapa
2 no habría generado sus tareas de ejecución.

**El motivo de pérdida es de lista cerrada, con detalle libre, y queda en el historial
(2026-09-25).** Pedido del usuario, para poder medir por qué se pierden las obras. Enum
`motivo_perdida`: precio · plazo · producto (no ofrecemos lo que piden) · proveedor habitual ·
obra suspendida · sin respuesta · otro. Al lado, el detalle en texto libre ("estuvimos 10% más caros"):
opcional, obligatorio con "otro", y con un ejemplo por motivo como guía en la pantalla. La obra guarda
el motivo actual, que se limpia al reabrirla. Cada pérdida queda en el evento `estado` (`detalle` suma
motivo y texto), así que perderla dos veces no borra la primera. Descartado: guardar solo el último,
que no permitía contar.

**`contratada` se revierte con causa, mientras no haya presupuesto aprobado (2026-09-26).** Un clic
equivocado no puede quedar para siempre. La revierten los mismos que cambian el estado, a cualquiera de
los tres abiertos, con causa en texto libre y obligatoria (caso raro, no se cuenta: sin lista). La causa
queda en el evento `estado` (`detalle`), como el motivo de pérdida, sin columna nueva. Con Presupuestos,
el trigger suma la condición "ningún presupuesto aprobado"; con uno aprobado, contratada es final.

**Datos de la obra (2026-09-25):** nombre, dirección, localidad, notas, origen, tipo de obra y fecha
estimada de compra (mes y año). Origen y tipo son listas cerradas, para poder contar, igual que el motivo
de pérdida. `origen_obra`: referente · cartel en obra · web o redes · cliente anterior · llamado · otro.
`tipo_obra`: edificio residencial · casa · oficinas o comercial · industrial · otro. Se evaluaron y se
descartaron avance de la construcción, monto potencial y unidades o m² estimados. Citables en
plantillas: `{nombre}`, `{direccion}`, `{localidad}`.

**Los números, en un widget del dashboard; `obras_numeros` lo abre a todas las obras (2026-09-26).**
Origen, tipo y motivo se guardaban "para contar" y nadie contaba: la única vista con todas las obras,
Todas, pide `obras_administrar`. El widget "Obras" muestra cuántas hay en cada estado, las perdidas del
período por motivo (del historial, evento `estado`) y las contratadas por origen y por tipo; el período,
con `FiltroDias`. Solo números: sin nombres de obras, contactos ni el detalle libre. Cuenta lo que cada
uno ve (el vendedor las suyas, el jefe su equipo, el admin todo) y, con `obras_numeros`, todas: una
función que asigna el admin y no se delega, para quien mira los números sin trabajar las obras (el
dueño, un gerente). Cuelga de la vista Obras, así que pide `obras_ver` y con él `contactos_ver`: sus
listas quedan vacías si no es responsable ni participante de nada. Descartado: un supervisor que vea
todas las obras (Todas sin `obras_administrar`); el usuario pidió los números.

**El período del widget cuenta lo que pasó en él; "por estado" es la foto de hoy (2026-09-28).** Por
estado: cómo están ahora, sin período. Perdidas por motivo y contratadas por origen y tipo: las que
pasaron a ese estado dentro del período (evento `estado`) y siguen ahí; una contratada y revertida no
cuenta. Responde "¿de dónde vienen las que cerramos este trimestre?". Una sola función,
`obras_contar(dias)`, DEFINER: con `obras_numeros` cuenta obras que quien llama no ve, y solo devuelve
cantidades (`sql/143`).
Pantalla (2026-09-28, elegida por el usuario): "Hoy" con los cinco estados en una línea; debajo,
contratadas por origen y por tipo y perdidas por motivo, con barras de un color relativas al máximo del
grupo. Lo dibuja Obras (`WidgetObras.tsx`) y el dashboard lo compone desde `app/`; período en `?dias=`,
30 por defecto.

**Motivo y causa viajan en la fila: `estado_nota` (2026-09-26).** La obra guarda `motivo_perdida` y
`estado_nota`, el texto del último cambio de estado: el detalle de la pérdida o la causa de la
reversión. `emitir_eventos_registro` suma al `detalle` del evento `estado` las columnas que recibe como
tercer argumento, así cada pérdida y cada reversión quedan en el historial. La causa usa la columna
del detalle, no una propia. Descartado: pasar el texto por `set_config` (invisible, se pierde si
alguien actualiza sin la función, y la base no lo puede exigir).
Archivos: `sql/125`, `sql/126`, `db_schema/obras.md`.

**Con origen "referente", el alta pregunta quién (2026-09-26).** Pedido del usuario: el caso típico
es un referente que llama con una obra nueva, y la obra tiene que nacer con él vinculado. Campo "¿Quién?"
opcional, con el buscador de Contactos: busca y crea como el panel de vincular, sin el campo empresa (ya
es el nivel anidado; `decisiones/contactos.md` → *Vincular: buscar o crear*). Obra, contacto nuevo y
vínculo con rol referente se guardan en una sola función, todo o nada. Si la obra o el contacto entran
congelados, el vínculo queda guardado y se crea al aprobarse; con "es la misma", en la existente
(*Altas parecidas*). La página compone el buscador en el
formulario desde `app/`.

**Las tareas de cada estado de la obra son de comercial. Las de ejecución cuelgan del presupuesto.**
Cada presupuesto aprobado genera su propio hilo, que sabe de qué etapa es. Lo mismo el seguimiento
comercial al entregarse una etapa.

**Rol `decisor` (2026-09-25).** "En búsqueda" es buscar a quien decide la compra, y ningún rol lo
nombraba: sin él, "vincular a quien decide" no tenía cómo completarse solo, ni quedaba registrado quién
es.

**Dos acciones para los pasos de plantilla que se completan solos (2026-09-25; es de Tareas, en
`BACKLOG.md`).** Obras solo lleva el seguimiento, así que ofrece dos, las dos sobre eventos que ya
emite: **vincular {rol}** (se completa cuando la obra suma ese rol) y **pasar a {estado}** (cuando pasa
a ese estado). El link de acción abre la ficha al lado, con `?vincular={rol}` (el panel de Contactos) o
`?estado={estado}` (el cambio de estado de la obra, que con "perdida" pide el motivo). Afuera a
propósito: todo lo de cotizar (plantillas de Presupuestos), completar datos (editar un campo no es
evento) y registrar la comisión (el asignado puede ser un participante, que no la ve).

## Ficha del módulo

Aprobada el 2026-09-25, después de revisarla punto por punto con el usuario.

```
Módulo: obras
Objetivo: seguir cada obra del lado comercial, desde la idea hasta que se contrata, y generar las
          tareas de cada estado.
Personas
├── Vendedor        — ve las obras donde es responsable o participante
│                   · crea, edita, cambia el estado, vincula contactos; en las suyas, además, registra
│                     la comisión del referente, suma participantes y transfiere
│                   · no ve obras de otros vendedores donde no participa; como participante, no ve
│                     la comisión
├── Jefe comercial  — el delegador del equipo · lo del vendedor + todas las obras donde participa su
│                     equipo (solo ver, si no son de su equipo) · transfiere entre vendedores
│                   · no ve obras de otros equipos donde el suyo no participa
├── Aprobador de altas — quien elija el admin (obras_aprobar) · ve las altas congeladas y lo parecido
│                     (nombre, dirección, responsable) · aprueba, rechaza con motivo, "es la misma"
│                   · no ve las obras ajenas enteras ni sus contactos, salvo por otro permiso
├── Quien mira los números — quien elija el admin (obras_numeros), p. ej. el dueño · en el widget
│                     "Obras", los números de todas: por estado, perdidas por motivo, contratadas por
│                     origen y tipo · — · no ve ninguna obra ni contacto, salvo por otro permiso
├── Admin           — ve todo · hace todo, reactiva · —
├── Administración, producción, logística, colocación — NO usan Obras: trabajan la etapa en
│                     Presupuestos (futuro) · no ven la obra ni sus contactos comerciales
├── Post-venta      — NO usa Obras: módulo aislado (futuro), que apunta a la obra y a los ítems
└── Cliente         — NO usa el módulo
Entes
└── obra — dueño responsable_id (transferible) · equipo_id del responsable, guardado al crear y
           al transferir · ruta /obras/{id} · submódulo obras_ver
           · columnas: nombre, dirección, localidad, notas, origen (origen_obra), tipo (tipo_obra),
             fecha estimada de compra (mes y año) · datos {nombre, direccion, localidad}
           · estado estado_obra: idea · en_busqueda · en_cotizacion · contratada · perdida
               idea           se detectó la obra, sin contacto todavía
               en_busqueda    se busca a quien decide
               en_cotizacion  hay al menos un presupuesto armándose o enviado
               contratada     hay al menos un presupuesto aprobado; final salvo reversión
               perdida        no se concretó; motivo (lista cerrada) + detalle libre, en el
                              historial de eventos
             idea ↔ en_busqueda ↔ en_cotizacion: libre, se puede saltear
             cualquiera de esos tres → perdida → reabrir a cualquiera de los tres
             contratada → cualquiera de los tres, con causa (texto libre), mientras no haya
               presupuesto aprobado; no pasa directo a perdida
             con Presupuestos: el primero lleva a en_cotizacion y el primero aprobado a contratada;
               desde ahí contratada la pone solo la base
           · la ven: responsable, participantes, obras_equipo sobre obra.equipo_id o el equipo_id de
             un participante, obras_todas
           · la trabajan (editar, cambiar el estado, vincular; lo pregunta también Contactos):
             responsable, participantes, obras_equipo sobre obra.equipo_id, obras_administrar
           · se comparte sumando participantes · emite y dispara: alta, estado
           · congelada (no es un estado: un flag aparte) si el alta se parece a otra obra; la ve solo
             quien la cargó, no se vincula, no cambia de estado ni se transfiere; el alta cuenta al
             aprobarse · también la edición que la hace parecida: la siguen viendo los de antes, y
             rechazar vuelve el dato anterior
No son entes
├── participante — obras_participantes (obra, usuario, equipo_id guardado); con obras_ver
└── comisión     — obras_comisiones (vinculo_id → contactos_vinculos, porcentaje | monto + moneda): el
                   vínculo es de una obra y tiene el rol referente; una activa por referente;
                   no se edita: cambiarla desactiva la fila y crea otra (las inactivas, historial)
                   · la ven y la escriben: responsable, obras_equipo sobre obra.equipo_id,
                     obras_administrar
Relaciones
├── obra → usuario           — responsable (columna)
├── obra ↔ usuario           — participante (obras_participantes)
├── obra ↔ persona | empresa — en Contactos (contactos_vinculos), roles de la obra: cliente,
│                              decisor, desarrolladora, constructora, comercializadora, arquitecto,
│                              director de obra, referente
└── futuras, del otro lado   — presupuesto → obra (FK en Presupuestos); unidad → obra (FK en Post-venta)
Acciones
├── obra: crear (con origen referente, "¿Quién?" lo vincula) · editar · cambiar estado · vincular contacto · registrar comisión · sumar y quitar
│         participante · transferir · desactivar (no contratada) · reactivar (admin)
│         · aprobar alta · rechazar alta (motivo) · "es la misma" — obras_aprobar
│         ├── responsable: todo lo de la obra
│         ├── participante: editar, cambiar estado, vincular contactos (no ve la comisión ni toca
│         │   el vínculo de un referente con comisión; no
│         │   suma participantes, no transfiere, no desactiva)
│         ├── jefe comercial: lo del responsable, en las obras de su equipo (obra.equipo_id);
│         │   en las que solo participa alguien de su equipo, solo ver
│         └── obras_administrar: todo, en cualquier obra
Eventos que emite
├── obra: alta (al aprobarse, si entró congelada) · estado (a perdida: + motivo y detalle; desde contratada: + causa) · baja
│         · reactivacion · transferencia ({de, a})
├── obra: relacion_alta / relacion_baja por contacto (los emite el trigger de contactos_vinculos)
└── campanita (nunca al que hizo la acción):
    ├── obra transferida       → el nuevo responsable
    ├── sumado a una obra      → el participante
    ├── quitado de una obra    → el ex participante
    ├── obras recibidas        → el jefe, por baja o cambio de equipo de un vendedor; una por hecho,
    │                            con la cantidad
    ├── obras huérfanas        → quienes tienen obras_administrar, cuando no hay jefe que las
    │                            reciba; una por hecho
    ├── alta por aprobar       → quienes tienen obras_aprobar
    └── alta resuelta          → quien la cargó: aprobada, rechazada (con motivo) o "es la misma";
                                 con "es la misma", también el responsable de la existente
                                 (quién se sumó y con qué vínculo)
    · descartado: "cambiaron el estado de tu obra" (ruido entre quienes trabajan la misma obra)
Eventos que consume
└── ninguno hoy · con Presupuestos: presupuesto creado y aprobado mueven el estado
Tareas
├── plantillas "Sobre: obra" por estado, para comercial; una vez por plantilla y obra
└── pasos de plantilla que se completan solos: vincular {rol} · pasar a {estado}; el link de
    acción abre la ficha al lado con ?vincular={rol} o ?estado={estado}
```

```
Módulo: Obras
├── Obras (vista, obras_ver)                   — vendedor, jefe comercial, admin
│   ├── obras_crear (funcion)                  — vendedor, jefe comercial
│   ├── obras_equipo (funcion)                 — jefe comercial
│   ├── obras_aprobar (funcion)                — aprobador de altas: lista "Por aprobar"
│   └── obras_numeros (funcion)                — quien mira los números: el widget cuenta todas
│                                                (sin ella, cuenta lo que ve)
└── Todas (vista, obras_todas)                 — admin
    │   filtro huérfanas: responsable sin obras_ver; "De {quien}" desde el aviso
    └── obras_administrar (funcion)            — admin

Delegables
├── sí — obras_ver · obras_crear
└── no — obras_equipo · obras_aprobar · obras_numeros · obras_todas · obras_administrar
Reglas entre permisos
├── obras_equipo  requiere usuarios_delegar  — el jefe comercial es el delegador
├── obras_ver     requiere contactos_ver     — sin él, los contactos de la ficha no existen para
│                                              quien la abre, y la obra se trabaja vinculándolos
├── obras_todas   requiere obras_administrar — como en Tareas: sola sería un supervisor
├── obras_todas   requiere obras_ver         — la ficha se abre con obras_ver: sin él, lista que no abre
└── excluye: ninguna
    · quitar_delegador tiene que sacar obras_equipo junto con usuarios_delegar (US016); al
      escribir el SQL, correr sql/tests/usuarios_equipos.sql
```
