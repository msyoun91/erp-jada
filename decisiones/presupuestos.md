# Decisiones — módulo Presupuestos

> **Estado: ficha aprobada (2026-11-05), revisada punto por punto con el usuario; revisada el 2026-11-06 (secciones con moneda e
> IVA, opcionales, auditoría de la ficha y revisión de UX). SQL por tramos: tramo 1 (`sql/185`: permisos, configuración,
> presupuesto, versiones y secciones), 2a (`sql/186`: renglones de Catálogo y a mano, descuento y totales), 2b (`sql/187`:
> opcionales y mínimos), 3a (`sql/188`: copiar, mantener, publicar y quitar variante) y 3b (`sql/189`: pedir, autorizar,
> devolver, retirar y la lectura de Técnica) aplicados el 2026-11-06, 3c (`sql/190`: recargo del referente) y 4 (`sql/191`: aprobar,
> rechazar, revertir y la obra) el 2026-11-10, con sus tests; ver *La base*. El tramo 5 (avisos, `sql/192`–`sql/193`) también, con sus tests. Pantallas definidas el 2026-11-10 (*Pantallas*), sin construir; la migración que piden (`sql/194`) ya está aplicada.**
> Se armó desde cero, sin partir del backlog, y se contrastó con él al final. Lo que falta, en `BACKLOG.md`
> → *Presupuestos*.

## Ficha del módulo

```
Módulo: Presupuestos
Objetivo: armar presupuestos sin cálculo a mano, que se puedan reproducir para ubicar un error y
          modificar manteniendo las condiciones de la cotización original o actualizándolas, y
          presentárselos al cliente de forma más interactiva que un PDF
Personas                qué ve · qué hace · qué NO ve
├── Vendedor       — los presupuestos de las obras que ve, con precios y comparación antes/después
│                    · en las obras que trabaja: arma, publica, corrige, registra aprobación y rechazo
│                    · costos, márgenes y presupuestos de obras ajenas
├── Jefe comercial — lo del vendedor, sobre las obras de su equipo · además autoriza "mantener" y
│                    descuentos sobre el tope, revierte, recibe aviso de renglón a mano · costos
├── Gerencia       — todos, con comparación y, con catalogo_aprobar, detalle con costos · actúa en todos,
│                    autoriza, revierte, configura · —
├── Técnica        — los presupuestos con alertas, completos · autoriza o devuelve · precios, la obra
│                    y sus contactos
├── Cliente        — (etapa 2; antes recibe el impreso)
│                    en erp-cliente, lo publicado con referencias en otras monedas · compara, elige
│                    opcionales por ventana, confirma · costos, comparación, versiones reemplazadas.
│                    No rechaza ni pide cambios: eso lo habla con el vendedor
├── Administración, producción, logística, colocación — NO usan el módulo: trabajan en el de
│                    ejecución y cobros (futuro), que toma lo aprobado. Producción y logística no ven precios
└── Post-venta     — NO usa el módulo: el suyo (futuro) apunta a los ítems del presupuesto aprobado

Entes
└── presupuesto — sin dueño propio: sigue a la obra; creado_por como registro · no se comparte aparte:
                  quien ve la obra ve sus presupuestos
                · estado estado_presupuesto: borrador → publicado → aprobado | rechazado · aprobado y rechazado
                  no admiten versiones ni quitar variantes: solo se revierten
                · datos {numero, nombre} · numero: P-0142, correlativo de la base, no se reutiliza
                · ruta /presupuestos/{id} · submódulo presupuestos_ver
                · disparos {alta, estado}
No son entes
├── versión — tipo: actualización o corrección | variante · variante: número y nombre, se copian al
│             corregir · vence (se guarda al publicar) · IVA discriminado o incluido · cómo se ve cada
│             opcional · estado: borrador → (en_revision) → publicado → obsoleto; en revisión y publicado
│             no se editan; autorizada, vuelve a quien arma, que publica; una publicada por variante
├── sección — nombre, único en la versión · moneda · alícuota · orden
├── renglón — designación y ubicación ("V4 · Lavadero") · sección · cantidad · precio escrito
│             de Catálogo: paquete y versión, fecha de condiciones, lo cargado, opcionales
│             a mano: descripción y precio · de mínimo: el que calcula Catálogo
│             de opcional aparte: la suma de ese opcional en todas las ventanas
├── autorización — del jefe, por versión; de Técnica, por renglón con alerta · qué se pidió (renglones
│                  y diferencia por moneda, descuento y tope), quién resolvió, cuándo, motivo si devolvió,
│                  o retirada por quien pidió
│                  · la de Técnica guarda lo cargado: vale mientras la ventana sea igual, también en una
│                  versión nueva del mismo presupuesto · historial: pedir de nuevo es otra fila
├── confirmación — (etapa 2) una por vez que el cliente confirma en el portal: versión, lo elegido por ventana,
│                  montos por moneda que vio, cuándo confirmó y cuándo la leyó el ERP · vale la última
└── configuración — una fila vigente: tope, plazo, monedas de referencia (etapa 2) · cambiar crea otra y desactiva
                    la anterior, como las comisiones de Obras: así queda el historial

Relaciones
└── presupuesto → obra (FK obra_id, obligatoria). Sin obra: calculadora sin guardar u obra mínima

Acciones
├── presupuesto: crear · aprobar · rechazar con motivo · revertir con causa · imprimir
│                · desactivar, solo si nunca se publicó (publicado, se aprueba o se rechaza)
├── versión: armar · publicar · corregir · sumar variante · quitar una variante (la publicada pasa a
│            obsoleto; no la última) · pedir autorización · autorizar · devolver
│            · retirar el pedido (vuelve a borrador) · descartar un borrador (activo = false; la publicada
│              se reemplaza con una corrección o se quita)
└── módulo: configurar (gerencia) · leer confirmaciones del portal (etapa 2; cada hora, al abrir, con un botón)

Eventos que emite
└── presupuesto: alta · estado — Obras escucha estado (se mueve al publicar, no al crear); los dos disparan
                 las plantillas de ejecución
Eventos que consume
└── ninguno

Presupuestos
├── Presupuestos (vista, presupuestos_ver)       — vendedor, jefe comercial, gerencia
│   ├── presupuestos_armar (funcion)             — vendedor, jefe comercial, gerencia: incluye la calculadora
│   ├── presupuestos_autorizar (funcion)         — jefe comercial: autoriza y revierte, en las obras que tiene a cargo
│   └── presupuestos_administrar (funcion)       — gerencia: ve y hace todo, en cualquier presupuesto
├── Revisión técnica (vista, presupuestos_revision)     — técnica: completos, sin precios, obra ni nombre
│   └── presupuestos_autorizar_tecnica (funcion)       — técnica
└── Configuración (vista, presupuestos_configuracion)  — gerencia: tope, plazo, monedas de referencia;
                                                         quien la ve, configura

Reglas entre permisos: presupuestos_ver requiere obras_ver · presupuestos_administrar requiere obras_administrar
Delegables: sí — presupuestos_ver · presupuestos_armar · presupuestos_revision
            no — presupuestos_autorizar · presupuestos_administrar · presupuestos_autorizar_tecnica
                 · presupuestos_configuracion
```
Aprobada el 2026-11-05; revisada el 2026-11-06.

Pendientes:
- **Reversión con la ejecución en marcha:** no se puede revertir si ya empezó, pero falta definirlo con ese módulo. Propuesta
  para el hilo ya generado: queda abierto con un aviso, y alguien lo cierra a mano; depende de Tareas.
- **Flete:** probar con un caso real que Catálogo arme los paquetes por km y por hora.
- **A qué contacto le llega en el portal:** espera la ficha de `erp-cliente` (base propia, cómo entra cada cliente). Pista: los
  contactos ya tienen rol en la obra (cliente, decisor, arquitecto…), así que probablemente sean los que elija el vendedor entre esos
  roles. No se suma relación hasta entonces.

## Etapas

**Se construye en dos etapas: primero todo `erp-app`, después el portal (decisión del usuario, 2026-11-06).** El portal no tiene ficha:
lo que se escribiera contra él se rehacía al definirlo, y la pantalla de todos los días esperaba.
- **Etapa 1:** presupuesto, versiones, secciones con moneda e IVA, mantener o actualizar con sus autorizaciones, descuento, mínimos,
  opcionales en sus tres formas, configuración de tope y plazo, e impreso. Juan manda el impreso y registra la aprobación a mano.
- **Etapa 2, con la ficha de `erp-cliente`:** todo *El cliente y el portal* salvo el impreso: confirmación, lectura cada hora,
  combinaciones ya calculadas, monedas de referencia, aviso y comparación del mínimo.

Costo: "más interactivo que un PDF", el objetivo, llega en la segunda. Se descartó recortar la etapa 1 (opcionales solo en el precio):
la colocación aparte resuelve el IVA, y lo que pesa es el cálculo, no la integración con otro sistema.

## Estados y versiones

**El presupuesto termina en `aprobado` o `rechazado`, no en `cerrado`.** Obras necesita saber si se aprobó, y "cerrado" no lo
dice. Un solo estado, sin segunda columna (`GUIDE_ENTES.md` §2.1).

**Hay dos tipos de versión: actualización o corrección, que reemplaza a la anterior al publicarse, y variante, que convive.**
Aluminio v1 a $100 pasa a v2 a $120: la v1 sigue valiendo hasta que se publica la v2. Aluminio y PVC se publican juntas.

**Cada versión guarda el número y el nombre de su variante, y al corregir los copia (decisión del usuario, 2026-11-06).** El impreso dice
"Aluminio US$ 7.180 · PVC US$ 6.300", y el número dice a qué variante reemplaza una corrección: "una publicada por variante" es un
unique parcial sobre presupuesto y número. El nombre es opcional con una sola variante y obligatorio al sumar una; sin nombre se muestra
"Variante 1". Cambiarlo en una publicada es una corrección, como cambiar cómo se ve un opcional. Costo: con ventanas mantenidas, renombrar
pide de nuevo la autorización, y una publicada sin nombre se nombra recién al corregirla. Se descartaron la variante como registro propio,
que renombraba sin versión nueva, y una letra automática (Opción A), que no dice qué es cada una.

**Una variante publicada se quita: su versión pasa a `obsoleto` y el presupuesto sigue con las demás (decisión del usuario,
2026-11-06).** Si el proveedor deja de entregar el PVC, Juan saca esa variante y el cliente ya no la elige; no mueve la obra ni cuenta como
rechazo. La última no se quita: para eso está rechazar. Se llama "quitar" y no "retirar", que es lo que se hace con el pedido de
autorización. En la etapa 2, quitar también escribe en el portal. Se descartó dejarlo como estaba: PVC seguía ofrecida.

**Un borrador de versión se descarta (2026-11-06).** Lo hace quien arma, también con una devuelta: queda `activo = false`, sin borrar.
Sin esto, Aluminio v2 a medio armar quedaba para siempre, y mientras exista no se abre otra versión de Aluminio. Una publicada no se
descarta: se reemplaza con una corrección.

**Una versión en revisión no se edita; quien arma la retira y vuelve a `borrador` (decisión del usuario, 2026-11-06).** La autorización
del jefe es sobre la diferencia que vio: si Juan sumaba ventanas mantenidas mientras Laura miraba, ella autorizaba US$ 800 y se publicaba
con US$ 1.400. Al retirar, los pedidos pendientes quedan como retirados en el historial; lo que Técnica ya autorizó sigue valiendo para
las ventanas que no cambiaron. Sin retirar, con Laura de vacaciones la versión quedaba trabada hasta que gerencia la devolviera. Se
descartó dejar editar y anular la autorización si cambiaba la diferencia: había que comparar en cada guardado, y el jefe recibía avisos
que se anulaban solos.

**Retirar no avisa: quien iba a resolver lo encuentra al actuar (decisión del usuario, 2026-11-06).** Si Laura autoriza un pedido ya
retirado, la base frena con "Juan retiró el pedido el 4/11: la versión volvió a borrador", y el filtro *Esperan mi autorización* ya no lo
muestra. Costo: si coinciden, Laura pierde lo que llevaba revisando. Se descartó un aviso al retirar: un tipo más, y dos avisos sobre
algo que ya no le toca.

**Cuando autorizan todos, la versión vuelve a quien arma, que publica (decisión del usuario, 2026-11-06).** Sigue `en_revision`, sin
editarse; "lista para publicar" se calcula: ningún pedido pendiente ni devuelto. Juan recibe un aviso y publica él, o Laura o gerencia,
que también trabajan la obra: así el cambio de la obra corre como alguien que la ve y dispara las plantillas. Si al pedir ya queda todo
autorizado, publica en el mismo paso. Se descartó publicar sola con la última autorización: si era la de Técnica, que no ve la obra,
Obras no podía moverla. Costo: un clic más, y si Juan no está, la versión espera a que publique otro.

**El número es un correlativo de toda la empresa (P-0142): lo asigna la base al crear, no se edita y no se reutiliza (2026-11-06).** Un
desactivado conserva el suyo, así "el 142" siempre es el mismo. Se descartó numerar por año (P-26-0142): en 2027 hay otro 142 y por
teléfono hay que decir el año; la fecha ya está en la ficha. Unique parcial `WHERE activo`, por la regla del proyecto; lo que impide reutilizarlo no es el índice sino el correlativo y que nadie
escribe la columna (sin GRANT de INSERT ni UPDATE), así que no hace falta excepción a la regla. El nombre lo
escribe el vendedor y es obligatorio.

**Lo que se aprueba junto va en presupuestos separados; lo que compite, en variantes.** Por eso aprobar y rechazar son decisiones
sobre el presupuesto entero: al aprobar una variante, el resto se inhabilita; al rechazar, caen todas. Así, `rechazado` significa
solo que el cliente dijo que no a todo, y una variante no elegida no cuenta como rechazo.

**Aprobado y rechazado congelan el presupuesto: sin versiones nuevas, sin corregir y sin quitar variantes; solo se revierten (decisión
del usuario, 2026-11-06).** Ejecución toma los renglones de la versión elegida y post-venta apunta a ellos: corregirla después los dejaba en
`obsoleto` y movía la base de la comisión sin que nadie lo aprobara. Lo que cambia en obra va en un presupuesto nuevo ("Adicional V4"),
que se aprueba aparte; un error en lo aprobado se revierte con causa y se corrige; si el cliente vuelve tras un rechazo, es otro
presupuesto, que al publicarse reabre la obra. Al aprobar o rechazar, los borradores y las versiones en revisión se descartan y sus
pedidos quedan retirados: Laura no autoriza algo ya cerrado. Se descartó corregir la elegida y que la nueva pasara a ser la elegida.

**La versión guarda solo su ciclo (`borrador`, `en_revision`, `publicado`, `obsoleto`); el presupuesto guarda cuál se eligió.**
"Aprobada" e "Inhabilitada" se calculan al mostrar: el mismo hecho en dos lugares podía desalinearse. Los nombres y el sentido son
los de Catálogo (`db_schema/catalogo.md` → *El ciclo*), salvo que acá hay varias publicadas a la vez, una por variante.

**Todo rechazo pide motivo, con la lista de Obras (`motivo_perdida`) y detalle.** Permite contar por qué se rechazan los
presupuestos, y la obra lo toma si queda perdida.

**Una aprobación o un rechazo equivocados se revierten, con causa escrita.** Vuelve a `publicado` y, si no queda otro aprobado, la obra
deja de estar `contratada`. Un clic equivocado no puede quedar para siempre, el mismo criterio de Obras.

**Revierte quien autoriza: `presupuestos_autorizar` con la obra a cargo, o `presupuestos_administrar` (decisión del usuario,
2026-11-06).** La misma regla, sin mecanismo nuevo; quien tiene la obra a cargo la trabaja, así que el cambio de la obra corre como quien
actúa. Se descartó una función `presupuestos_revertir`: otro permiso para las mismas personas. Se descartó que revirtiera quien trabaja la
obra: el vendedor deshacía sus propias aprobaciones sin que nadie se enterara.

## Efectos en la obra

**Obras lee el presupuesto, nunca las versiones.** Corregir o sumar una variante no la mueve: la mueve el estado del presupuesto. Si
está `contratada`, uno que se publica o se rechaza tampoco.

| En el presupuesto | En la obra |
|---|---|
| Se publica el primero | `en_cotizacion` |
| Se publica uno en una obra `perdida` | Se reabre a `en_cotizacion` |
| Se aprueba el primero | `contratada`, firme salvo reversión |
| Se rechaza y no quedan publicados ni aprobados | `perdida`, con el motivo del rechazo |
| Se revierte una aprobación y no queda otro aprobado | `en_cotizacion`, con la causa como nota (OB009) |
| Se revierte el rechazo que la dejó `perdida` | `en_cotizacion` |
| Tiene presupuestos activos, en cualquier estado | No se desactiva |

**La obra cambia cuando el presupuesto se publica, no cuando se crea (decisión del usuario, 2026-11-06).** Un presupuesto se desactiva
solo si nunca se publicó, así que nunca movió la obra y no hay nada que deshacer. Creado por error en una obra `perdida`, la reabría y
Obras le borraba el motivo; al desactivarlo, quedaba en cotización sin presupuestos. Se descartó volver al estado anterior al
desactivar: había que guardar y restaurar estado, motivo y nota. Costo: mientras se arma el primero, la obra no muestra que se cotiza;
quien quiera, la pasa a mano. Con la obra congelada (OB018) el presupuesto se arma igual, y solo publicar espera a que se apruebe.

**Con la obra `perdida`, el presupuestador lo avisa al abrir un borrador: "La obra está perdida (precio). Al publicar, se reabre."
(decisión del usuario, 2026-11-06).** Juan ve antes de armar si está en la obra equivocada, y sabe que publicar cambia la obra.

**~~Obras cambia la obra como quien actúa, escuchando los eventos del presupuesto (decisión del usuario, 2026-11-06).~~** Ver *La
base* → *Un trigger sobre `presupuestos` mueve la obra*.

**La obra pasa sola a `perdida` y vuelve sola (decisión del usuario).** Se evaluó que el sistema preguntara antes: el usuario
prefirió que la obra siga a sus presupuestos. Etapa 1 rechazada con la Etapa 2 abierta no la mueve.

**Un borrador no sostiene la obra ni frena perderla: solo cuentan los publicados (decisión del usuario, 2026-11-06).** El cliente
rechaza P-0142 mientras Juan arma P-0150, más barato: la obra pasa a `perdida` con el motivo, y si Juan publica P-0150 se reabre, con el
aviso de arriba. Si lo abandona, la obra ya quedó bien. Es el criterio de *La obra cambia cuando el presupuesto se publica*: lo que nunca
movió la obra no la retiene. Se descartó contar los borradores: uno olvidado dejaba la obra en cotización para siempre, sin nada enviado.

**La obra no se desactiva con presupuestos activos, en cualquier estado (2026-11-06).** Un borrador se desactiva antes, porque nunca se
publicó. Con uno publicado, aprobado o rechazado, la obra no fue un error: queda en el embudo con su motivo, y el rechazo se sigue contando.

**Para marcarla `perdida` a mano, primero se resuelven sus presupuestos publicados.** Se descartó rechazarlos en cascada: reabrir la
obra no los recuperaba, y alguien podía rechazar un presupuesto ajeno por poder marcar la obra. Se descartó dejarlos como están:
uno publicado se podía aprobar en una obra perdida.

**Todo presupuesto tiene obra.** Toda la visibilidad y los efectos dependen de ella. Para "¿cuánto sale una ventana?": la
calculadora sin guardar (`catalogo_precio`). Para un presupuesto formal: una obra mínima, que después se completa, sin transferir
nada. Se descartó una obra genérica "Consultas": con el primer aprobado quedaba `contratada` para siempre, y mezclaba clientes,
contactos y números. Costo: la dirección es obligatoria, y una de relleno repetida congela el alta: el presupuesto se arma, pero no se publica
hasta que se apruebe la obra.

**"Llevar a un presupuesto", desde la calculadora, pide la obra y abre un borrador con la ventana cargada (decisión del usuario,
2026-11-06).** "¿Cuánto sale una de 150×110?" suele terminar en "mandámelo", y así no se carga dos veces. Si la obra no existe, se crea en
Obras y la ventana vuelve con ella; cómo vuelve se decide con las pantallas. Se descartó volver a cargarla a mano.

## Quién accede

**Quien trabaja la obra trabaja sus presupuestos.** Se trabaja en equipo y el equipo decide quién arma, así que el sistema no lo
asigna: se usan los niveles de Obras (ve, trabaja, a cargo; `db_schema/obras.md`), sumando un participante si hace falta. Se
descartó que todo el equipo vea todo (Obras oculta las obras ajenas) y una lista por presupuesto (una segunda forma de dar acceso).
Quien crea un presupuesto no gana poder sobre la obra: quien la trabaja ya puede cambiarle el estado.

**Quien ve la obra ve sus presupuestos, con precios; el presupuesto no se comparte aparte (decisión del usuario, 2026-11-06).** Excepción
registrada a `GUIDE_ENTES.md` §2.4 (compartir no arrastra lo relacionado): el presupuesto no tiene grants propios. Alcanza a quien ve sin
trabajar: el jefe del equipo de un participante, que supervisa lo que cotizó su vendedor en una obra ajena, y `obras_todas`. Para que
alguien no vea precios, no se le da `presupuestos_ver`. Se descartó que solo quien trabaja la obra viera sus presupuestos: cambiaba la
persona Vendedor y obligaba a pedirle a gerencia lo que cotizó un vendedor propio.

**Gerencia ve todo y actúa (decisión del usuario).** Autoriza también, cubre la ausencia del jefe y ubica los errores con el detalle
de costos, sin permiso nuevo: `catalogo_aprobar`. Actúa con `presupuestos_administrar` (abajo).

**`presupuestos_administrar` ve y hace todo, en cualquier presupuesto (decisión del usuario, 2026-11-06).**
Arma, publica, autoriza, revierte y desactiva. Toda regla de acceso del módulo la deja pasar, como `obras_administrar` en Obras. Sin ella,
con Laura de vacaciones nadie autorizaba, y un presupuesto de una obra huérfana no se podía cerrar. Reemplaza a la vista *Todos*: con la
función, la lista de Presupuestos muestra todo; la vista sola veía sin poder actuar ni abrir la ficha (que pide `presupuestos_ver`). Requiere
`obras_administrar`, que trabaja todas las obras, para que el cambio de la obra corra como quien actúa (*Efectos en la obra*). Se descartó
que `obras_administrar` sola alcanzara: administrar Obras no es poder autorizar descuentos.

**Autoriza quien tiene `presupuestos_autorizar` y la obra a cargo, o `presupuestos_administrar` (decisión del usuario, 2026-11-06).** "A
cargo" es la regla de Obras (`obras_a_cargo_de`: responsable, `obras_equipo` sobre el equipo de la obra, `obras_administrar`), sin
mecanismo nuevo. Si Juan, del Norte, participa de una obra del Sur, autoriza la jefa del Sur: en Obras, el jefe del equipo de un
participante solo ve. Se descartó el jefe de quien arma: autorizaba margen en una obra que no tiene a cargo. Si quien pide ya podría
autorizar, queda autorizado al pedir, y se registra así.

**Lo que espera autorización se encuentra con un filtro de la lista, "Esperan mi autorización", no con una vista (decisión del usuario,
2026-11-06).** Muestra solo lo pendiente, con quién pidió, hace cuánto y qué pide (mantenidas por moneda, descuento sobre el tope): lo que
resolvió otro o se retiró no aparece. Lo tiene quien tiene `presupuestos_autorizar` (sus obras a cargo) o `presupuestos_administrar`
(todo); el vendedor tiene "Devueltas", con el motivo. Se descartaron solo avisos, sin lista de lo pendiente, y una pestaña propia: un
submódulo más para las mismas personas.

**Técnica lee por una función que no devuelve precios, montos, totales ni la obra, y no tiene `presupuestos_ver` (2026-11-06).** El precio
escrito es una columna del renglón y la RLS filtra filas, no columnas: con `presupuestos_ver` y el precio oculto en pantalla, lo veía en la
respuesta de la API. La función devuelve el número del presupuesto y, por renglón, designación, paquete y versión, medidas, lo
cargado y las alertas; es el criterio de `catalogo_precio`. No devuelve el nombre (decisión del usuario, 2026-11-06): es texto libre, y
"Pérez – Nordelta – arq. Gómez" le mostraba la obra y sus contactos; Técnica y el vendedor hablan de "el 142". Su aviso lleva a *Revisión técnica*, no a la ficha.

**Se delega todo menos lo que autoriza o cambia las reglas: ver, armar y Revisión técnica (decisión del usuario, 2026-11-06).** Laura
suma a Pedro y le da ella misma Presupuestos y armar, como hoy le da Obras. Martín le da Revisión técnica a Sofía, pero autorizar alertas
lo asigna el admin: es el mismo criterio de Catálogo, donde aprobar no se delega. Configuración tampoco, porque el tope y el plazo valen
para todos.

**Armar es una sola función, sin una por parámetro (decisión del usuario, 2026-11-10).** Se evaluó separar mantener, descuento,
renglón a mano, variantes y formato (secciones, moneda, alícuota, IVA, opcionales) para que el editor de quien no los usa fuera más
simple. Se descartó al ver el costo: partía la persona Vendedor y obligaba a frenar cada parámetro en la base, sobre funciones ya aplicadas.

**Configuración es una vista sin función: quien la ve, configura (2026-11-06).** Es solo gerencia y nadie necesita mirarla sin cambiarla;
las escrituras se verifican en la base contra la vista. Se sacó `presupuestos_configurar`.

**El vendedor ve lo que cargó, el precio y los mensajes del paquete; no ve costos ni despiece.** Sus errores más probables están en
lo que carga, y Catálogo ya avisa ("No se puede calcular con estas medidas"). Lo demás lo deriva.

**Administración, producción, logística y colocación no usan el módulo.** Cobros y habilitaciones van en otro módulo, que toma lo
aprobado y muestra lo que cada área necesita. Sin acceso, no hay riesgo de que producción y logística vean precios. Se había
propuesto una vista Aprobados para administración: se sacó porque no tenía función. Costo: hasta que exista ese módulo, se lo piden
a ventas.

## Precio

**Mantener o actualizar se elige por ventana, y mantener trae la fecha, no solo la versión y el tipo de cambio.** Si el aluminio pasa
de USD 12 a USD 14 sin versión nueva del paquete, el precio cambia aunque se mantengan esos dos datos. La fecha trae juntos costos,
servicios y tipo de cambio (`decisiones/catalogo/precio.md` → *Un presupuesto se recalcula como era*). Solo hay dos valores, nunca una
fecha libre (`decisiones/catalogo/precio.md`, 2026-10-29). Por ventana porque un modelo nuevo puede no tener precio a la fecha vieja: por
versión, obligaba a mover las demás.

**Mantener pide autorización del jefe comercial, o de gerencia, dentro del sistema.** Resigna margen, así que queda registrado quién,
cuándo y qué diferencia. La versión pasa por `en_revision`, autoriza la versión entera, y si no está de acuerdo la devuelve con motivo.
Sin el permiso, las ventanas arrancan a hoy. Gerencia y ventas ven la comparación antes y después. Cada versión nueva se autoriza de
nuevo: la diferencia crece con el tiempo. Si quien pide ya puede autorizar, se autoriza solo (*Quién accede*).

**Publicar frena si una ventana a hoy cambió de precio desde que se cargó (decisión del usuario, 2026-11-06).** Juan carga el lunes,
el miércoles sube el aluminio, publica el viernes: "3 ventanas cambiaron de precio: actualizalas o mantenelas". Lo publicado es siempre
lo que alguien vio, y no se escapa margen sin autorización. Se descartaron recalcular al publicar (el número cambiaba sin que Juan lo
viera) y tomar el precio del día de carga (era mantener sin pedir permiso). Costo: un clic más cuando hubo cambios en Catálogo, y
publicar recalcula cada ventana para comparar.

**Toda ventana mantenida pide autorización, aunque no resigne nada (decisión del usuario, 2026-11-06).** Juan mantiene V1 (US$ 450
contra 500 a hoy), V2 (300 y 300) y V3 (300 contra 280): Laura recibe el pedido por las tres. Mantener es una decisión comercial y la
autoriza el jefe, sin que el sistema juzgue si conviene. Se descartaron pedir solo por las más baratas que a hoy y por el neto de cada
moneda, que dejaba pasar una ventana que resigna si otra cobraba de más. Costo: mantener todo en una corrección sin cambios en Catálogo
igual pasa por Laura; actualizar no pide nada.

**El renglón a mano no pide autorización: le avisa al jefe comercial al publicar (decisión del usuario).** Con descripción y precio, que
no se recalcula. Para lo que no está en Catálogo.

**El flete habitual va en Catálogo, como dos paquetes: por km y por hora.** Se carga la cantidad y la tarifa sale con fecha. Un precio
cerrado de un fletero va a mano. Si todo flete fuera a mano, el jefe recibiría un aviso por cada uno.

**El descuento es un % sobre el total de la versión, el mismo en cada moneda: hasta un tope, libre; por encima, autorización.** El
cliente lo ve como un renglón por moneda. Un
solo tope para toda la empresa, que cambia gerencia, con historial.

**Una alerta del paquete pide autorización de Técnica antes de publicar; un bloqueo no publica.** Las dos autorizaciones se piden juntas:
queda lista para publicar cuando autorizan todos (*Estados y versiones*), y si uno devuelve, vuelve a `borrador`. La de Técnica vale mientras la ventana no cambie: mismo
paquete, versión y datos cargados dan el mismo resultado. Técnica ve el presupuesto completo sin precios, porque una ventana puede
depender de la de al lado.

**Una opción dada de baja se puede mantener con autorización de Técnica, pero no elegir en una ventana nueva.** Distingue un material sin
stock de uno que queda para un caso puntual.

**Las versiones vencen, con un plazo único que define gerencia.** Al vencer, el portal no deja confirmar, y una versión nueva se
actualiza libre o se mantiene con autorización. "Vencido" se calcula, no se guarda: sigue `publicado`, la obra no cambia y no cuenta como
rechazo. La fecha de vencimiento sí se guarda al publicar, con el plazo vigente (2026-11-06): recalculada, bajar el plazo vencía
versiones que el cliente creía vigentes, y subirlo estiraba precios viejos sin autorización. Un plazo nuevo vale para lo que se publique
después; más tiempo para el cliente es una versión nueva.

**Una versión vencida se aprueba igual, con un aviso: "Vencida hace 3 días: los precios son del 1/10" (decisión del usuario,
2026-11-06).** El portal no deja confirmarla, pero en la etapa 1 Juan registra lo que el cliente firmó. Costo: nadie autoriza lo que se
resigna por los precios viejos, que mantener sí pide; se puede contar, porque el vencimiento queda guardado y la aprobación, en los
eventos del presupuesto. Se descartaron frenarla con un botón a "corregir manteniendo" y una autorización del jefe sobre la aprobación.

**Los mínimos son un renglón aparte, en una sección y con su mantener o actualizar.** Con mantener, autorización, como cualquier ventana.
`catalogo_precio_minimos` calcula hoy a la fecha de hoy: hay que ampliarla con la versión, la fecha y la moneda de cada renglón.

**Se guarda el precio escrito y los datos para recalcularlo, sin copiar costos ni porcentajes.** La versión sigue diciendo lo que vio el
cliente, aunque se corrija algo en Catálogo, y recalcular sirve para encontrar errores: si no coincide, hay algo para investigar.

**Las ventanas se cargan una por una, con duplicar.** Cada carga pasa por las validaciones de Catálogo. Importar planillas va al backlog:
cada arquitecto la arma distinto, y hay que resolver de qué paquete es cada renglón.

## Moneda e IVA

~~**La moneda es por versión, elegida por el vendedor.**~~ Superada el 2026-11-06: la moneda pasó a la sección (*Secciones y opcionales*
→ *Cada sección tiene su moneda*).

**El cliente ve referencias en otras monedas, al tipo de cambio del día, solo informativas.** Aprueba en la moneda de cada sección; la referencia convierte el total entero. Gerencia
elige cuáles se muestran, para todos; arrancan pesos y dólar oficial, para no exponer el blue. Cada vez que el ERP actualiza los tipos de
cambio, los escribe en el portal, y este solo los usa para mostrar.

**Siempre tipo de cambio de venta.** Lo que pase al cobrar en billetes se resuelve en el módulo de cobros (`BACKLOG.md`). Monedas no cambia.

~~**El IVA es por renglón: 21 %, 10,5 % o 0 %, discriminado o incluido, siempre después del descuento.**~~ Superada el 2026-11-06:
la alícuota pasó a la sección (*Secciones y opcionales*).

## Secciones y opcionales

**Los renglones van en secciones con nombre y alícuota (21 %, 10,5 % o 0 %); la alícuota vive solo en la sección (2026-11-06).** Un
edificio con un local al 21 % y departamentos al 10,5 % son dos secciones. Si el contador cambia el criterio, se corrige la sección
y no 40 renglones uno por uno. El cliente ve el subtotal de cada sección. La versión arranca con una sección, con la alícuota que se
elige al crearla y un nombre editable, así que una casa simple se arma igual que sin secciones. Mover un renglón de sección le
cambia la alícuota. Una versión nueva o una variante copia las secciones.

**Un renglón con otra alícuota va en otra sección; el renglón no tiene alícuota propia.** Se descartó la alícuota de la sección como
predeterminado que el renglón puede cambiar: al cambiar la sección había que decidir si pisaba las excepciones. El caso que lo pedía,
la colocación, lo resuelve el renglón aparte (abajo).

**Un botón de la versión pone todas las secciones a la misma alícuota.** Es "cambiar todo junto".

**El IVA va discriminado o incluido, siempre después del descuento: un renglón de IVA por alícuota.** El descuento va sobre el total
de cada moneda y se reparte proporcionalmente entre sus alícuotas. Lo que no lleva IVA va al 0 %. El precio de Catálogo llega sin IVA
(`decisiones/catalogo/precio.md` → *El IVA lo suma Presupuestos*).

**Los opcionales se pueden discriminar, y el vendedor elige cómo se ven: en el precio, debajo de cada ventana o en un renglón aparte
(decisión del usuario).** Se elige por opcional y por versión: la Colocación aparte y la Garantía de vidrio en el
precio, en la misma versión. Arranca en el precio, como hoy. Vale para piezas opcionales (Colocación) y servicios en % opcionales
(Garantía de vidrio). Cambiarlo en una publicada es una corrección. El impreso y el portal lo muestran igual. No deja ver ningún % ni
costo: el monto ya se deduce tildando y destildando en el portal.

**El monto de un opcional es lo que suma agregarlo, en el orden del cálculo: piezas, después servicios del paso 1, del 2 y del 3.**
Con los servicios en cascada, medir cada opcional sacándolo solo a él cuenta dos veces lo que se cruza (un Recargo del 10 % sobre el
subtotal también se cobra sobre la Colocación) y la suma no da el total. En orden siempre cierra: el recargo sobre la colocación queda
en la línea del Recargo. Se guarda el monto escrito de cada línea, como el precio.

**El renglón aparte es uno por opcional, en la sección que elige el vendedor (decisión del usuario).** Así la colocación puede llevar
otra alícuota que sus ventanas, en una sección "Colocación · 10,5 %", y el IVA y el total cambian con eso: no es solo cómo se ve. Se
descartó un renglón por sección de origen: seguía la alícuota de sus ventanas y no servía para darle otra. Costo: en un edificio
mixto, la colocación del local y la de los departamentos quedan con una sola alícuota. En el portal, destildar la colocación de una
ventana baja el renglón aparte, no el precio de esa ventana.

**Debajo de cada ventana, la línea del opcional es también el control para elegirlo (decisión del usuario).** Un botón Mosquitero y una
línea Mosquitero se leían como dos cosas. Donde se puede elegir (borrador y portal), se ven todos con su casilla, y los no elegidos sin
monto; donde no (publicada, impreso), solo los elegidos. En el precio y en renglón aparte sigue el botón. Se evaluó que el impreso
mostrara los no elegidos, con o sin monto, para la etapa 1, y queda así (decisión del usuario, 2026-11-06).

**El mínimo de un opcional que va en renglón aparte se suma a ese renglón (decisión del usuario).** Con la Colocación en el precio, el
cliente veía "Mínimo de colocación" de algo que no aparecía en ningún lado; aparte, ve una sola línea "Colocación $650.000". Es
presentación: el mínimo sigue con su mantener o actualizar y su autorización, y toma la sección del renglón aparte. Con las otras dos
formas sigue como renglón propio.

**La comparación antes/después compara el precio completo de cada ventana y el total, no las líneas (decisión del usuario).** Cambiar
cómo se ve un opcional no cambia el precio: pasar la Colocación del renglón aparte al precio hacía ver la ventana más cara a gerencia.
El renglón aparte no se compara, porque ya está en sus ventanas.

**Cada sección tiene su moneda, y el total va por moneda: "US$ 7.180 + $ 1.240.000" (decisión del usuario).** Caso real: materiales en
dólares y mano de obra en pesos, y el cliente paga cada parte en su moneda. Se descartó un total convertido: pasaba el riesgo cambiario
al tipo de cambio de un día, justo lo que se evita cotizando en dólares. La versión arranca con todas las secciones en la principal;
"Todas las secciones en…" las cambia juntas, y "pasámelo en dólares" sigue siendo una versión nueva. Si las variantes publicadas quedan
con distintas monedas (una en dólares y pesos, otra solo en pesos), el sistema avisa antes de publicar.

**Por moneda: subtotal, descuento, un renglón de IVA por alícuota y total.** El descuento es el mismo % en cada moneda. El cliente
confirma los dos montos. La comparación antes/después se hace dentro de cada moneda: una ventana que cambió de moneda dice "antes en
pesos", sin diferencia.

**Un renglón de Catálogo se calcula en la moneda de su sección, a la fecha de sus condiciones. Un opcional en el precio o debajo de la
ventana va en la moneda de la ventana; uno en renglón aparte, en la de su sección.** Con la ventana en dólares y su colocación aparte en
pesos, Catálogo calcula dos veces, una en cada moneda, y cada una cierra exacto. El mínimo se compara en la moneda de su renglón.

**Un renglón a mano no cambia de moneda.** Su precio es escrito y no se recalcula: no se mueve a una sección en otra moneda, y su sección
no cambia de moneda mientras lo tenga. Para pasarlo, se carga de nuevo.

## El cliente y el portal

**Toda la comunicación la inicia el ERP: al publicar escribe en `erp-cliente`, y de ahí lee las confirmaciones.** `erp-cliente` no envía
nada y su confirmación queda allá como constancia, sin autoridad (`GUIDE_SYNC.md`). Se asume que el portal tiene base propia; lo define su
ficha, que hoy no existe.

**El ERP lee como Monedas: cada hora, al abrir una página, y con un botón.** Con una confirmación nueva, Juan recibe un aviso, la ve en la
ficha y registra `aprobado`. Si es de una versión reemplazada, no se puede aprobar: Juan habla con el cliente.

**El cliente ve, compara, elige opcionales y confirma.** Rechazos y cambios los habla con el vendedor, y Juan los registra. No cambia
medidas ni ve un precio nuevo: el portal no calcula ni le pide nada al ERP. Ve el precio de cada ventana, y no las versiones reemplazadas.

**Elige opcionales ventana por ventana, todos, y el ERP le envía cada combinación ya calculada.** El efecto de un opcional no se suma: los
servicios van en cascada. Lo elegido queda con la confirmación, y la versión no cambia. Una combinación con un bloqueo o una alerta no
autorizada no se ofrece, para no saltear a Técnica. Aceptado: destildando, puede ver menos que con el vendedor.

**Si un mínimo hace que el total exacto difiera, en alguna moneda, de lo que vio el cliente, Juan no puede aprobar hasta resolverlo.** Los mínimos dependen de
todas las ventanas juntas, así que no salen de la suma. El ERP compara al leer la confirmación.

**Con el mínimo dentro de un renglón aparte, el portal avisa antes de confirmar si la suma quedó por debajo (decisión del usuario,
2026-11-06).** El ERP manda, con el renglón, su piso; si al destildar la suma baja de ahí, el portal muestra "La colocación tiene un mínimo:
el total puede ajustarse. Juan te confirma el monto." No calcula precio: compara dos números que ya recibió. Sin el aviso, el cliente
confirmaba un total que después cambiaba.

**Una versión imprimible desde el ERP, además del portal.** Se imprime o guarda como PDF desde el navegador, sin librería nueva y sin costos
ni comparación. Permite usar el módulo sin el portal, y queda como respaldo.

## Avisos

Cuatro, en la campanita. Retirar no avisa (*Estados y versiones*); "Vencida hace 3 días" es un mensaje de la pantalla al aprobar; el
de una confirmación del portal espera a la etapa 2.

**El aviso de un pedido le llega a todos los que pueden autorizarlo, no solo a quien tiene la obra a cargo (decisión del usuario,
2026-11-10).** Juan pide por el 12 % de P-0142, del Sur: lo reciben Laura, jefa del Sur, y Gerardo, que administra. Una sola regla,
quien puede autorizar recibe, como `catalogo_version_enviada` y `alta_por_aprobar`; con Laura de vacaciones, Gerardo ya está avisado.
Uno por versión y por persona, no por renglón; desaparece cuando ya no le queda nada pendiente que pueda autorizar (autorizado,
devuelto o retirado), y a Técnica la lleva a *Revisión técnica*. Costo: gerencia recibe todos los pedidos de la empresa, también los
de Técnica. Se descartó avisar solo a quien tiene la obra a cargo: una segunda regla, y con el jefe ausente nadie se enteraba.

**"Lista para publicar" le llega a quien pidió (decisión del usuario, 2026-11-10).** Pedro arma la v2 y se va de viaje; Juan la
termina y pide; cuando autoriza la última, Laura, el aviso es para Juan, que es quien espera. Desaparece cuando la versión sale de
revisión. Si al pedir ya quedó todo autorizado, se publica en el mismo paso y no hay aviso. Se descartaron quien creó la versión
(Pedro, de viaje) y todos los que arman en la obra.

**La devolución le llega a quien pidió, con el motivo, y queda como noticia (decisión del usuario, 2026-11-10).** "Laura devolvió
P-0142 · v2: bajá el descuento al 10 %" sigue en la campanita aunque Juan corrija y vuelva a pedir: es un hecho con su motivo, como
`catalogo_version_devuelta`; lo pendiente lo muestra el filtro *Devueltas*. Apunta a la fila de la autorización devuelta. Se descartó
que desapareciera al pedir de nuevo: una condición más para sacar algo que Juan ya leyó.

**El renglón a mano avisa al publicar solo si es nuevo o cambió respecto del renglón del que se copió (decisión del usuario,
2026-11-10).** La v1 sale con "Flete cerrado, US$ 500" y avisa; la v2, que corrige la medida de la V4 con el flete igual, no; con el
flete a US$ 300 o un "Andamio" más, avisa y cuenta solo esos. Cambió: descripción, precio, cantidad o moneda. Uno por versión
publicada, a quienes pueden autorizar lo comercial en esa obra, menos quien publica; queda como noticia. Vale igual al sumar una
variante, que también copia. Se descartó avisar en cada publicación: el mismo flete en cada corrección, y el jefe deja de mirarlos.

## Pantallas

**Siete pantallas, revisadas de a una con el usuario (2026-11-10).** Lista `/presupuestos` (filtros Todos, *Esperan mi
autorización*, *Devueltas*) · ficha `/presupuestos/[id]` (una tarjeta por variante: publicada, la abierta y su estado, corregir,
quitar; encabezado según estado) · editor `/presupuestos/[id]/[version]` (secciones, renglones, opcionales, totales y *Antes de
publicar*; solo lectura fuera de borrador o sin armar; quien autoriza resuelve ahí) · impreso `/presupuestos/[id]/imprimir` ·
Revisión técnica `/presupuestos/revision` y `/presupuestos/revision/[version]` · Configuración · y la sección en la ficha de la obra,
por composición en `app/`. La calculadora sin guardar sigue en Catálogo; su formulario sube a `components/` para usarlo en los dos.

**La lista lee las tablas, sin función propia (2026-11-10).** *Esperan mi autorización*: pedidos `comercial` pendientes de versiones
`en_revision`, y `presupuestos_puede_autorizar` una vez por obra. *Devueltas*: versiones en borrador cuyo pedido más nuevo quedó
`devuelta`; pedir de nuevo crea filas más nuevas, así que retirar ese pedido no la vuelve a mostrar. Muestra todas las que se ven, no
solo las que pidió quien mira. Los nombres salen de `obras_nombres`: quien pidió en una obra donde no figura se ve "—". Si la lista
crece o eso molesta, una función. `modules/presupuestos/queries.ts`, `PresupuestosView.tsx`.

**El nombre del presupuesto se edita hasta aprobar o rechazar (decisión del usuario, 2026-11-10).** Lo ve el cliente, pero no cambia
precios. Hoy la base lo deja cambiar en cualquier estado (`GRANT UPDATE (nombre)` en `sql/185`, sin trigger): el freno va en la
migración de pantallas.

**Con IVA incluido, el precio con IVA de cada renglón lo da la base (decisión del usuario, 2026-11-10).** Editor, impreso y portal
mostrarían centavos distintos si cada uno redondeara. `presupuestos_version_importes` suma el importe con IVA, redondeado; en el pie,
el descuento es subtotal − total, así absorbe el redondeo y el total es el mismo que con IVA discriminado.

**El editor lee lo que ve el cliente de `presupuestos_version_importes`, sin multiplicar nada en pantalla (2026-11-11).** Quien arma no
lee Catálogo (la RLS de `catalogo_versiones` pide la vista Paquetes), así que el nombre del paquete de cada ventana sale de ahí, y también
las líneas de debajo: con el recargo, la cantidad y el IVA, el monto de una línea calculado en pantalla podía diferir en centavos del
impreso. Se descartó una función aparte para las líneas: repetía la cuenta del recargo y el redondeo. `sql/195`, `VersionView.tsx`.

**Datos de la versión y secciones se editan en paneles, sin función nueva: UPDATE e INSERT directos, y la RLS y los triggers frenan
(2026-11-11).** *Editar* en el encabezado (variante, IVA, descuento con el tope al lado); *Todas las secciones…* en el `⋯`, con dos o
más, es un solo UPDATE por versión con "Como está cada una" en lo que no cambia. Cada sección: editar, subir, bajar y sacar. Sacar no
se ofrece con renglones ni en la única (la base frena lo primero con PR011; lo segundo es solo de pantalla, para no quedar sin dónde
cargar). La nueva va al final con la moneda y el IVA de la primera; subir y bajar renumeran `orden`. Lo ve armado quien arma la obra
(`presupuestos_arma`) con la versión en borrador. La clase PR entró a `mensajeError` (`lib/utils.ts`): hasta acá sus mensajes salían
con el genérico. `AccionesVersion.tsx`, `AccionesSeccion.tsx`.

**Los renglones a mano y de Catálogo se cargan en paneles, con INSERT y UPDATE directos: el precio, la moneda y los mínimos
los pone la base (2026-11-11).** Al pie de cada sección, *De Catálogo* y *A mano*; cada renglón, editar, duplicar y sacar; un mínimo
solo se mueve de sección (PR012). Duplicar abre el panel de uno nuevo con sus datos, para cambiar la designación y las medidas antes
de guardar. Al guardar una ventana, si quedó sin precio, el aviso dice por qué (`mensaje`). Editando, lo cargado (paquete, entrada,
opcionales) viaja solo si se tocó: reescribir lo mismo no recalcula, pero ida y vuelta por el formulario puede no dar el mismo
`jsonb`, y cambiar la ubicación traía la ventana a hoy. A mano, el panel ofrece solo las secciones en su moneda (PR009), y el precio va
como las medidas, en texto sin puntos: con `type="number"`, "150.000" quedaba en 150. Mantenida, el paquete se muestra fijo (PR013). Cambiar de paquete pasa lo cargado por nombre: el ancho y el alto no se escriben de nuevo. No hay
subir ni bajar renglones: cada UPDATE de una ventana recalcula los mínimos de la versión (*Del 2b, por si pesa*, en `BACKLOG.md`), y
reordenar 40 ventanas eran 40 vueltas; ordenan `orden` y la fecha de alta. `AccionesRenglon.tsx`, `RenglonPanel.tsx`.

**El formulario de la calculadora subió a `components/entrada/EntradaCampos.tsx` y la entrada a `lib/entrada.ts`, para Catálogo y
Presupuestos (2026-11-11).** Suma lo que la calculadora no hacía: lo secundario plegado en *Más opciones* (abierto si algo de adentro
tiene valor), la pieza que requiere otra (la Cortina marca el Cajón, sacar el Cajón saca la Cortina, con aviso) y, por color, la pieza
o la opción que no se ofrece (deshabilitada; al cambiar de color se saca con aviso). La calculadora de Catálogo ve así el formulario
del vendedor, sin la oferta por color (no la tiene). El color va siempre a la vista: la base no marca un color como secundario. El
predeterminado de una medida se muestra como se escribe ("1200", no "1.200"), porque el campo rechaza el punto.

**Cómo se ve cada opcional se elige en un panel de la versión; debajo de cada ventana, en borrador, la casilla de los que van
debajo y un botón por los demás, y cada clic guarda (2026-11-11).** *Cómo se ven los opcionales…*, en el `⋯`: un select por
opcional, "En el precio", "Debajo de cada ventana" o aparte en cada sección; escribe solo los que cambiaron, con INSERT y UPDATE
directos (volver al precio desactiva la fila). Tildar en una ventana es guardar lo cargado de esa ventana, con la regla de la
Cortina y el Cajón y lo que no se ofrece en su color (`lib/entrada.ts`, la misma del formulario): recalcula como guardar el panel,
sin acción nueva. La lista sale del formulario de venta de cada paquete, que la versión trae una vez por paquete y usa también el
panel del renglón (antes lo pedía al abrirlo); todo servicio en % opcional se ofrece en toda ventana, porque así lo da
`catalogo_venta_formulario`. La clave de cada opcional se arma en pantalla como `presupuestos_clave`, solo para cruzarla con las
filas y las líneas. Una sección con un opcional aparte no ofrece *Sacar*, aunque ya no esté en ninguna ventana (PR011 cuenta la
fila). Fuera de borrador siguen solo las líneas de lo elegido debajo. Para el e2e, el paquete Zqx197 de `e2e/datos-opcionales.sql`.
`Opcionales.tsx`, `AccionesVersion.tsx`.

***Antes de publicar* es una tarjeta al final del editor: en borrador, lo que frena y lo que se va a pedir, con un botón,
*Pedir autorización* o *Publicar*; en revisión, las filas del último pedido, y *Autorizar* y *Devolver* a quien resuelve ese
tipo (2026-11-11).** En borrador lee `revisar` y `pedido` (a hoy); en revisión, `pedido` guardado en cada fila: quien autoriza ve
lo que se pidió. Las filas de un pedido comparten `created_at` (el `now()` de su transacción), así que el último son las más
nuevas, y en borrador dicen si volvió devuelta, con el motivo. Quien arma, en revisión, retira o publica (sin pendientes); confirmar
en todo, y devolver pide motivo. Va al final: arriba, cada edición le cambiaba el alto, el navegador corría el scroll y se
cerraba el menú abierto de un renglón. Un pedido nuevo que surge en plena revisión (gerencia bajó el tope) no se muestra: lo dice
publicar al frenar (PR014). El nombre de quien pidió o resolvió sale de `obras_nombres`, y se omite si no figura en la obra. Costo:
en borrador cada carga corre `revisar`, que recalcula cada ventana a hoy (~45 ms con 2 ventanas). `AntesDePublicar.tsx`,
`getAntes` en `queries.ts`.

**La base de desarrollo tiene una configuración de prueba, tope 10 % y plazo 15 días, y Tester arma sin autorizar (decisión del
usuario, 2026-11-11).** Sin plazo, `revisar` frena todo, y Configuración no tiene pantalla; con `presupuestos_administrar`, Admin se
autoriza solo y nunca se ve un pedido pendiente. Gerencia carga la suya al abrir el módulo. `e2e/datos-autorizaciones.sql`.

**Mantener o pasar a hoy se elige en el `⋯` de cada ventana y de cada mínimo; *Mantener todas…* y *Todas a hoy…*, en el `⋯` de
la versión, con confirmar (2026-11-11).** Copiada, *Mantener precios del 1/10/26* (la fecha del origen); mantenida, *Pasar a hoy*;
y toda ventana o mínimo a hoy, *Actualizar a hoy*: es lo que pide *Antes de publicar* cuando algo cambió desde que se calculó
("actualizala o mantenela"), y hasta acá un mínimo no tenía cómo. Cada clic guarda sin confirmar, como los opcionales: se deshace
con el otro. Todo escribe `mantener` en un UPDATE por ids, y escribirlo recalcula. *Todas a hoy* toma toda ventana y todo mínimo,
no solo lo copiado: también actualiza lo que cambió, y avisa cuántos mantenidos dejan de estarlo. Mantener se ofrece solo con el
paquete del origen (PR013): la versión trae el paquete y la fecha del origen de cada renglón. El resumen ("2 renglones mantenidos ·
a hoy, + $ 800") es el del pedido al jefe, en *Antes de publicar*: no se repite arriba. Copiar todavía no tiene pantalla: el e2e
arranca de `e2e/datos-mantener.sql`. `mantenerRenglones`, `AccionesRenglon.tsx`, `AccionesVersion.tsx`.

**El impreso: solo lo publicado, y los datos de la empresa en un archivo de la app (decisión del usuario, 2026-11-10).** Publicado,
todas las variantes; aprobado, la aprobada; rechazado, la última de cada una; un borrador no se imprime. Empresa: logo y datos fijos
como marcadores hasta tenerlos, sin tabla hasta que haga falta cambiarlos desde una pantalla. Cliente: nombre y dirección de la obra y
sus contactos con rol `cliente`.

**Las 2 obras contratadas sin presupuesto quedan como están (decisión del usuario, 2026-11-10).** El freno de `contratada` a mano
corre al pasar a ese estado, no sobre lo que ya está; son la excepción a "contratada si y solo si hay un aprobado", y publicar o
rechazar ya no las mueve. Se descartaron pasarlas a cotización (deshace algo que comercial marcó a propósito) y cargarles un
presupuesto (trabajo a mano sin valor).

## La base

Esquema: `db_schema/presupuestos.md`. Tramos: 1 registros (`sql/185`) · 2a renglones y precio (`sql/186`) · 2b opcionales y
mínimos (`sql/187`) · 3a versión nueva, mantener y publicar (`sql/188`) · 3b autorizaciones (`sql/189`) · 3c recargo del referente (`sql/190`) · 4 aprobar, rechazar y la
obra (`sql/191`) · 5 avisos (`sql/192`–`sql/193`) · 6 pantallas (`sql/194`: nombre congelado PR027, `importe_con_iva`, freno de `contratada` PR028; test `presupuestos_pantallas`; `sql/195`: nombre y líneas de debajo en los importes, test en `presupuestos_opcionales`; `sql/196`: todas las piezas en el formulario de venta, test en `presupuestos_renglones`). Los tests de Obras que ponían `contratada` a mano desactivan `presupuestos_obra_estado` dentro de su transacción; el selector de estado de la obra ya no ofrece `contratada`.

**El tramo 2 se parte: 2a los renglones de Catálogo y a mano, con su precio, el descuento y los totales; 2b los opcionales y los
mínimos (2026-11-06).** El 2b depende de todo el 2a (montos por línea, renglón aparte, mínimos en una sección) y cada mitad se
prueba sola.

**El tipo de versión no se guarda: se deduce de la variante (2026-11-06).** Una versión de una variante que ya existe es una
corrección o una actualización; una con la variante siguiente es una variante nueva. Guardar el tipo era el mismo dato dos veces.
`presupuestos_versiones.variante`.

**El número es un entero de una secuencia, y `P-0142` es una columna generada (2026-11-06).** Buscar "142" y ordenar usan el
entero; la etiqueta, el buscador y las plantillas (`{codigo}` en `entes.datos`) usan el código, sin formatearlo en dos lugares.
Pasado el 9999 sigue con cinco cifras. `presupuestos.numero`, `presupuestos.codigo`.

**Ver un presupuesto no depende de que esté activo (2026-11-06).** Desactivar es un UPDATE directo, y Postgres le pide a la fila
nueva que pase la policy de SELECT: si "ve" pidiera `activo`, nadie salvo administrar podía desactivar. Quien ve la obra ve también
los borradores desactivados; la lista los filtra. `presupuestos_ve_de`.

**Las plantillas que dispara un presupuesto son las de quien lo creó (2026-11-06).** El disparo corre las plantillas del dueño, y
el presupuesto no tiene dueño propio: `creado_por` es el registro de quién lo armó. `entes.dueno = 'creado_por'`.

**La configuración arranca vacía (2026-11-06).** Tope y plazo son números de gerencia, no del sistema; hasta que los cargue, el
tramo 3 frena publicar (no hay vencimiento) y todo descuento pide autorización. `presupuestos_configuracion`.

**El nombre del presupuesto se edita mientras esté activo, en cualquier estado (2026-11-06).** Es la etiqueta interna ("el 142 de
Belgrano"); congelar lo aprobado es sobre versiones y renglones, que es lo que toman ejecución y post-venta. `presupuestos_update`.

**La versión arranca con IVA discriminado y la sección se llama "General" si no se elige otro nombre (2026-11-06).** Son
predeterminados que el vendedor cambia en el borrador. `presupuestos_alta`.

**El precio de un renglón de Catálogo lo pone la base: se calcula a hoy al crearlo, al cambiar lo cargado y cuando su sección cambia
de moneda (2026-11-06).** Un trigger llama a `catalogo_precio` y guarda precio, versión, fecha y mensajes; si alguien escribe el precio,
queda el calculado. No hay un "guardar" aparte de "calcular". Cantidad, designación, ubicación y orden no recalculan. Mantener, desde
el 3a: *Mantener es recalcular con la versión y la fecha del renglón de origen*, abajo. `presupuestos_renglones_validar`.

**Un renglón de Catálogo sin precio se guarda, con el porqué; lo frena publicar (2026-11-06).** Un bloqueo, un paquete que salió de la
venta o una sección que pasa a una moneda sin tipo de cambio dejan sin número a un renglón que ya estaba; rechazarlo solo al crearlo
era una regla más que no protegía nada. Un paquete que no está a la venta no entra (PR010): no hay versión que guardar. Uno que ya
estaba queda con su versión. `presupuestos_renglones.precio`, `mensaje`.

**El renglón guarda la moneda de su precio, que el trigger iguala a la de su sección (2026-11-06).** No es otro dato: es parte del
precio escrito ("US$ 182"). Que no coincida es lo que recalcula al de Catálogo cuando la sección cambia, y lo que frena a uno a mano
(PR009, *Un renglón a mano no cambia de moneda*). `presupuestos_renglones.moneda`, `presupuestos_secciones_moneda`.

**Una sección con renglones no se saca: antes se mueven o se sacan (2026-11-06).** Sacarlos en cascada se llevaba ventanas sin que
nadie las mirara. PR011.

**El descuento se redondea por alícuota y el IVA va sobre lo que queda (2026-11-06).** Repartir un descuento ya redondeado entre las
alícuotas obligaba a elegir a cuál le toca el peso que sobra; por alícuota cada línea cierra y el total es la suma. Costo: puede
diferir en un peso del % sobre el total. `presupuestos_version_totales`.

**El precio de Catálogo lo pide quien arma: `presupuestos_armar` o `presupuestos_administrar`; `catalogo_aprobar` solo ya no
(2026-11-06).** Era lo pendiente de Catálogo (`decisiones/catalogo/precio.md` → *El precio sale de una función*). Vale para el precio,
los mínimos, la lista a la venta y el formulario; el gerente de Catálogo sigue con el detalle. `catalogo_precio_permitido`.

**El formulario de venta devuelve el contenido de la versión con las claves de la calculadora (2026-11-06).** Así la entrada se arma
con `aEntrada` sin cambios. Solo lo que pregunta: piezas opcionales, variables del vendedor con su predeterminado ya calculado (el
despiece sin entrada), materiales que elige el vendedor con sus opciones, y por color qué no se ofrece; sin fórmulas, costos ni
condiciones. `catalogo_venta_formulario`. **Corrección (2026-11-11, `sql/196`): trae todas las piezas, cada una con su `opcional`.** La
entrada nombra la pieza de cada elección (`{"Hoja": {"Vidrio": …}}`) y el material apunta a su pieza por id: con solo las opcionales,
el Vidrio de una Hoja fija no se podía cargar ni leer. El formulario sigue preguntando solo por las opcionales.

**`catalogo_precio_redondear` tiene EXECUTE (2026-11-06).** No lee nada, y los totales redondean igual que el precio sin copiar la
regla.

**La línea de cada opcional sale de pedir el precio encadenado: sin opcionales, y sumando de a uno en el orden del cálculo; la
pieza requerida va antes de la que la requiere (2026-11-06).** Cada paso tiene menos que el precio entero, y Catálogo no deja que
lo fijo use una pieza opcional: si el entero da número, cada paso también. La Cortina antes que su Cajón no se calculaba. Si igual
un paso falla, el renglón queda sin precio, y frena publicar. Se guarda en el renglón, como el precio. `catalogo_precio_lineas`,
`presupuestos_renglones.lineas`.

**Cómo se ve cada opcional es una fila por versión; sin fila, va en el precio (2026-11-06).** La pieza se reconoce por nombre,
porque cada paquete tiene la suya, y el servicio por id. `presupuestos_opcionales`.

**El renglón aparte no se guarda: sale de las líneas de las ventanas (2026-11-06).** Guardarlo era la misma suma dos veces, y
destildar en una ventana tendría que tocar otro renglón. La ventana resta su línea y la suma va a la sección del aparte; si esa
sección está en otra moneda, la ventana guarda también esa tanda. `presupuestos_version_importes`.

**Una sección con el renglón aparte de un opcional tampoco se saca (2026-11-06).** Como con renglones: se mueve antes. PR011.

**El mínimo arranca en la sección que más aporta a él (decisión del usuario, 2026-11-06).** El IVA y la moneda siguen al grueso
de lo que lo generó; la primera sección por orden erraba el IVA en un edificio mixto, y la primera de la versión podía caer en
pesos con las ventanas en dólares. Después Juan lo mueve, y no vuelve solo. `presupuestos_minimos_calcular`.

**El mínimo es un renglón que pone y saca la base, uno por servicio; quien arma solo lo mueve (2026-11-06).** Se recalcula cada
vez que cambia un renglón de Catálogo, con la versión y la fecha guardadas de cada renglón (las de su precio), en la moneda de su
sección. El que ya no hace falta se desactiva, y si vuelve, arranca de nuevo por la regla: un renglón en $0 escondido frenaba sacar
su sección sin que nadie lo viera. `presupuestos_renglones_minimos`, PR012.

**~~Hasta el tramo 3, que un opcional pase a aparte en otra moneda recalcula a hoy las ventanas que lo tienen (2026-11-06).~~**
Superada por el 3a: la ventana se recalcula como esté, a hoy o mantenida (*Mantener es recalcular…*, abajo).

**El tramo 3 se parte: 3a la versión nueva, mantener o actualizar y publicar; 3b pedir, autorizar, devolver y retirar, y la lectura
de Técnica (2026-11-06).** Como el 2, cada mitad se prueba sola. Hasta el 3b, lo que pide autorización frena publicar.

**Corregir, actualizar y sumar variante copian la versión que se mira; la versión y cada renglón guardan de dónde vienen
(2026-11-06).** Copia secciones, cómo se ve cada opcional, ventanas y renglones a mano; los mínimos los pone la base. Sumar variante
arranca sin nombre, y publicarla lo pide si hay otra publicada. Las ventanas arrancan a hoy (*Precio*: sin autorización, a hoy).
`presupuestos_version_copiar`, `origen_id`.

**Mantener es recalcular con la versión y la fecha del renglón de origen: solo hay dos valores, hoy o los de la versión de la que se
copió (2026-11-06).** El origen guarda lo que vio el cliente, y si él mismo estaba mantenido, su fecha es la de antes: la cadena
llega a la cotización original. Cambiar una medida de una mantenida respeta su fecha (`decisiones/catalogo/precio.md` → *Un
presupuesto se recalcula como era*); cambiarle el paquete frena (PR013): no hay versión vieja de otro paquete, se pasa a hoy antes.
La fecha la lee la base del origen; quien llama solo elige mantener o no. `presupuestos_renglones.mantener`,
`presupuestos_precio_lineas`.

**Escribir `mantener`, aunque no cambie, recalcula (2026-11-06).** "Actualizar" una ventana que ya estaba a hoy y cambió de precio es
el mismo gesto que actualizar una mantenida, sin una función aparte. Un trigger que corre antes marca el renglón para recalcular.
`presupuestos_renglones_a_hoy`.

**El umbral de un mínimo es el valor del servicio a la fecha del mínimo: hoy, o la del mínimo de origen si se mantiene
(2026-11-06).** Lo que aporta cada ventana sigue a la fecha de la ventana. Antes el umbral era el mayor de los de cada ventana, a su
fecha: con mantenidas y a hoy mezcladas no era ni el de antes ni el de hoy. `catalogo_precio_minimos_items`,
`presupuestos_minimos_calcular`.

**Un mínimo copiado arranca en la sección de igual nombre que la de su origen (2026-11-06).** Si Juan lo había movido a
Colocación, la corrección no lo devuelve a la sección que más aporta. Sin esa sección, arranca por la regla.

**Una ventana copiada cuyo paquete salió de la venta entra sin precio, con la versión de su origen (2026-11-06).** Es la regla del 2a
(uno que ya estaba queda con su versión). Mantenida tiene precio, con la autorización de siempre; una nueva de ese paquete no entra
(PR010).

**~~Lo que frena publicar es una lista, como en Catálogo, y publicar la exige entera (2026-11-06).~~** Superada por el 3b: *Lo que
frena y lo que pide autorización van separados*, abajo.

**Lo que frena y lo que pide autorización van separados: `revisar` frena pedir y publicar; `pedido` dice qué pide autorización y
en qué está (2026-11-06).** Frena: sin configuración, sin renglones, variante sin nombre, ventanas sin precio, lo que cambió desde que
se calculó y mínimos que faltan. Con las dos listas la pantalla elige el primario ("Publicar" o "Pedir autorización"); publicar exige
las dos, y frena con "Pide …" lo que falta pedir y "Espera la …" lo pendiente. `presupuestos_version_revisar`,
`presupuestos_version_pedido`, `presupuestos_version_publicar` (PR014).

**Lo que autorizó el jefe vale solo en la vuelta en que se dio; lo de Técnica, para toda ventana igual del presupuesto
(2026-11-06).** El jefe autorizó una diferencia que, de vuelta en borrador, puede cambiar; Técnica, un resultado que solo depende de
paquete, versión y lo cargado. Al volver a borrador (retirar o devolver) lo pendiente queda retirado y lo del jefe deja de valer
(`activo = false`). `presupuestos_version_a_borrador`, `presupuestos_tecnica_cubre`.

**Si uno devuelve, lo demás pendiente queda retirado (2026-11-06).** La versión vuelve a borrador y se edita: Laura no autoriza una
diferencia que Juan va a cambiar. Pedir de nuevo arma otro pedido. Si Laura llega tarde, la base dice quién devolvió y cuándo (PR018).
`presupuestos_pedido_resolver`.

**Autorizar una ventana de Técnica autoriza también las pendientes iguales de la versión (2026-11-06).** Por la regla de arriba su
autorización ya valía para ellas; dejarlas pendientes trababa publicar y dejaba en la cola de Técnica algo resuelto. Es lo que pedía
la revisión de UX ("Técnica autoriza juntos los renglones iguales"), en la base. `presupuestos_pedido_resolver`.

**Una opción dada de baja mantenida es algo elegido en la ventana que su propia versión ya no ofrece: color, pieza u opción
(2026-11-06).** Se pregunta a la versión de la ventana, no a la publicada, que puede no tener esa opción. Pide Técnica, junto con las
alertas; un paquete que salió de la venta sin nada dado de baja pide solo al jefe, por mantener. `catalogo_precio_fuera`, que sale de
`catalogo_precio_venta` sin copiar la regla.

**La diferencia que ve el jefe es a hoy menos mantenido, por renglón y sumada por moneda (2026-11-06).** Cada renglón en la moneda de
su sección; un opcional aparte en otra moneda va dentro del precio de su ventana. Una ventana sin precio a hoy va sin diferencia. El
mínimo se compara con el umbral de hoy. Se guarda al pedir: el jefe ve lo que se pidió. `presupuestos_version_pedido`,
`presupuestos_autorizaciones.pedido`.

**Gerencia autoriza también lo de Técnica (2026-11-06).** `presupuestos_administrar` deja pasar toda regla del módulo (*Quién
accede*); si pide ella, todo queda autorizado y publica en el mismo paso. `presupuestos_puede_autorizar`.

**Técnica ve los presupuestos con algún pedido suyo, en cualquier versión (2026-11-06).** Son "los presupuestos con alertas" de la
ficha: así ve también la versión siguiente, donde lo que autorizó ya vale y no hay pedido nuevo. `presupuestos_revision_version`.

**El recargo se aplica al leer los importes, no se guarda en cada renglón (2026-11-10).** El precio del renglón sigue siendo el de
Catálogo, así que mantener, actualizar y lo que compara publicar no cambian; `presupuestos_version_importes` lo divide por
`1 − %` y de ahí lo heredan los totales. Un cambio de comisión en borrador no obliga a recalcular renglones. El % de la versión sale
de `presupuestos_recargo_de`: el vigente en borrador, y al salir queda en `presupuestos_recargos`, que lee solo quien tiene la obra
a cargo. Por eso `presupuestos_version_importes` pasó a DEFINER, con su propio control de `presupuestos_ve`. Suma de comisiones en %
desde 100: PR020. `sql/190`.

**Un trigger sobre `presupuestos` mueve la obra, sin consumidor de eventos (decisión del usuario, 2026-11-10; reemplaza la del
2026-11-06).** La premisa vieja ya no valía: desde `sql/152` las plantillas corren por el dueño del registro, actúe quien actúe, y
publicar es DEFINER, así que un consumidor tampoco corría como quien actúa. Tras cada cambio de estado: con algún aprobado,
`contratada`; si no, con algún publicado, `en_cotizacion`; si no, y fue un rechazo, `perdida` con su motivo. Las siete filas de
*Efectos en la obra* salen de esas tres preguntas. El evento de la obra lleva a quien actuó. `presupuestos_mover_obra`, `sql/191`.

**El motivo del rechazo y la nota del último cambio de estado son columnas del presupuesto (2026-11-10).** `emitir_eventos_registro`
solo copia columnas al `detalle` del evento, como en Obras. `estado_nota` es el detalle del rechazo o la causa de la reversión;
aprobar la limpia. `presupuestos.motivo_rechazo`, `estado_nota`, `version_aprobada_id`.

**Con la obra congelada, frena lo que la movería (2026-11-10).** OB018 solo corre a profundidad 1 y el cambio llega desde un
trigger, así que lo controla `presupuestos_mover_obra` con el mismo código. Publicar un segundo presupuesto en una obra que ya está
en cotización no la mueve, y pasa.

**A mano, la obra no sale de `contratada` con un aprobado ni pasa a `perdida` con publicados; pasar a `contratada` a mano todavía se
puede (2026-11-10).** Frenarlo hoy dejaba a comercial sin forma de marcar una obra contratada hasta que Presupuestos tenga
pantallas, y hay 2 obras así. Una contratada a mano no la mueven publicar ni rechazar: solo aprobar. Se cierra con las pantallas
(`BACKLOG.md`). `presupuestos_obra_estado` (PR025, PR026).

**El tramo 5 son cuatro tipos de aviso, con triggers sobre las tablas del ciclo y sin tocar las funciones que ya existen (plan aprobado,
2026-11-10).** `sql/192` agrega los tipos (`presupuesto_pedido`, `presupuesto_autorizado`, `presupuesto_devuelto`, `presupuesto_a_mano`) y
`sql/193` el resto. Un trigger sobre `presupuestos_autorizaciones` emite los tres primeros (al insertar pendientes, al autorizarse la
última pendiente, al devolverse) y uno sobre `presupuestos_versiones`, el del renglón a mano, cuando pasa a `publicado`. Los
destinatarios salen de `presupuestos_puede_autorizar_de(tipo, obra, usuario)`, la regla actual por usuario, que `presupuestos_puede_autorizar`
pasa a envolver: una sola regla. Los resuelve `presupuestos_avisos(ids)` (DEFINER, como `catalogo_avisos`) porque Técnica no lee
versiones por RLS: a ella le da solo "P-0142 · v2" y el destino *Revisión técnica*. Gerencia, que puede autorizar las dos cosas,
recibe un aviso por versión, no uno por tipo; pedir de nuevo desactiva el aviso anterior de esa versión y emite otro. Test:
`sql/tests/presupuestos_avisos.sql`; regresión: autorizaciones, ciclo, aprobación y `catalogo_avisos`. Fuera del SQL:
`NotificacionesBell` (`/presupuestos/<id>` y la de Revisión técnica, aunque las pantallas no existan), `database.types.ts`,
`db_schema/presupuestos.md` y `db_schema/notificaciones.md`.

**Los avisos de un pedido y de "lista para publicar" apuntan a la versión; el de la devolución, a la fila devuelta (2026-11-10).** Pedir de
nuevo desactiva los anteriores de esa versión (si no, al volver a `en_revision` reaparecerían), y la devolución, que es un hecho, sigue.
Los triggers de `presupuestos_autorizaciones` son por sentencia con tabla de transición: Técnica autoriza varias ventanas juntas y
avisa una sola vez. El texto del renglón a mano es el conteo ("2 renglones a mano"); qué cambió se ve en la versión. `sql/192`, `sql/193`.

**El bloqueo por mínimos al aprobar espera a la etapa 2 (2026-11-10).** Compara contra lo que confirmó el cliente en el portal, que
todavía no existe.
