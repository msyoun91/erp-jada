# Tareas — plantillas y Catálogo

Plantillas personales, Catálogo, copias, asignados y disparos.

**~~Plantillas en tres alcances y Catálogo~~** → *Toda plantilla es personal*.

**Toda plantilla es personal; se comparte por el Catálogo (2026-09-24).** Decisión del usuario:
cada uno usa solo las suyas, y lo ajeno se copia primero —nunca se usa directo, para no depender
de ediciones ajenas—. Con eso los alcances global y de equipo solo servían para copiarse, que ya lo
hace publicar: se fueron, con `tareas_plantillas_equipo`, `tareas_plantillas_globales` y su regla.
El dueño decide publicarla; se copia sin asignados fijos y con el disparo apagado; `copiada_de`
guarda el origen. Costo aceptado: si el delegador cambia el proceso del equipo, cada miembro vuelve
a copiarlo.

**La copia del Catálogo es independiente y `copiada_de` es solo historia.** Sin aviso de "el
original cambió": pediría versión y destinatarios, y se suma sin tocar el esquema si hace falta. El
origen se muestra como link si sigue visible en el Catálogo y como texto plano si no, como las
referencias. La copia se publica si su dueño quiere; las casi duplicadas las despublica el admin.
Sin asignados fijos,
un pedido del original no se hereda: se elige al usarla y rige `tareas_pedir`.

**Los pasos sin asignado fijo se asignan al usar la plantilla.** El formulario pide uno por paso
vacío, con quien la usa como valor por defecto. Nunca nace un paso sin dueño.

**Una plantilla que pide afuera no se usa sin `tareas_pedir`.** Decisión del usuario. Como toda
plantilla es personal, ya no se oculta: su dueño la ve "a revisar". `usar_plantilla` lo rechaza en
la base: la UI no autoriza. Si un asignado
elegido al usar la plantilla cae afuera, se aplica la regla de siempre: pedido con `tareas_pedir`.

**Una plantilla nunca falla por un asignado (2026-09-24).** Manual: el fijo que ya no puede recibir
se trata como paso vacío (se elige, con quien la usa por defecto, y se avisa). Disparo: el asignado
inválido, el paso vacío o el pedido sin `tareas_pedir` quedan en quien activó el disparo —el
responsable del hilo creado— con aviso "paso a reasignar", como la recurrencia. Si el activador ya
no puede recibir, el disparo se saltea; la baja apaga sus activaciones. Un disparo nunca voltea la
transacción del emisor: lo inesperado se registra y se avisa al activador, y la obra se crea igual.

**Una plantilla que dejó de valer se marca "a revisar" para su dueño (2026-09-24).** Calculado al
leer, en Mis plantillas: "Pedro ya no es del equipo" o "ya no puede recibir". Si el fijo se va a
otro equipo sigue pudiendo recibir, pero pasa a ser pedido: si el dueño no tiene `tareas_pedir`, no
la puede usar y no sabía por qué. Sin columnas ni triggers.

**Plantillas por evento esperan a su primer emisor.** Hoy ningún módulo emite; se construyen las
manuales y `disparar_plantillas` se conecta después.

**`{dato}`, condiciones por rol y pasos condicionados llegan con el disparo (2026-09-24).** Leen un
registro, y a mano no hay registro: `master` tampoco los usaba fuera de un disparo. `sql/118` guarda
el texto tal cual; las columnas (`condicion`, datos) se suman con el primer emisor, junto con
`disparar_plantillas` y las activaciones.

**La cadena de la plantilla es "espera al anterior" por paso (2026-09-24).** Un booleano sobre el
orden arma exactamente lo que admite un hilo —cadenas sin bifurcar, en paralelo entre sí— sin ids
entre pasos que guardar reemplaza. Usada en un hilo existente, cada cadena arranca sin previo.
`sql/118`.

**El elegido al usarla gana sobre el fijo (2026-09-24).** Una sola regla en `usar_plantilla`: el
elegido; si no, el fijo si puede recibir (`tareas_asignables()`); si no, quien la usa. La UI pregunta
por los vacíos y los "a revisar"; si pregunta por otro, es el dueño cambiando su propia plantilla.
El admin ve, edita y usa las ajenas (*Función admin por módulo*), pero no las publica: publicar es
del dueño. `sql/118`.
