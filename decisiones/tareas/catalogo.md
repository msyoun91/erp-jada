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
dueño del registro y responsable del hilo creado (*El disparo sigue al registro*)— con aviso "paso a reasignar", como la recurrencia. Si el activador ya
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

**La plantilla dice "Sobre" qué registro trabaja: un ente o ninguno (2026-09-24).** Aparte del
disparo: "Sobre" define qué se puede referenciar y qué se pide al usarla; el disparo solo agrega que
corra sola. Usarla a mano con "Sobre" pide elegir el registro (buscador, lo que quien la usa ve);
sin elegir, no se usa. Desde un hilo siempre suma a ese hilo y pide el registro igual, sin
precargar el actual ("Sobre: Hilo" desde el hilo A puede hablar del hilo B). "Sobre: Ninguno" es la
plantilla de hoy. Los hilos no disparan: se eligen a mano; el proceso que encadena trabajo vive en
el ente de negocio (la obra). Espera al primer emisor (`BACKLOG.md`).

**El hilo guarda su registro (ente e id) y su plantilla (2026-09-24).** Solo si nació de una
plantilla con "Sobre". El ente va en el hilo y no se deduce del "Sobre", que se puede editar
después. Es la única fuente de "hilo sobre un registro" y "vino de esta plantilla":
`tareas_vinculos` no lleva rol ni plantilla (`registro.md`). Sumar pasos a un hilo existente no le
cambia el registro. La ficha del registro lista sus hilos; el encabezado del hilo muestra
"Sobre: X ↗" si quien lee lo ve, y nada si no. Hilo "sobre X" a mano, sin plantilla: no, hasta que
haga falta.

**El disparo sigue al registro, no a quien actúa (2026-09-24).** Corren las plantillas que activó
el dueño del registro, lo cambie quien lo cambie; el hilo nace suyo. Dueño que no puede recibir: no
corre (la baja ya apaga sus activaciones). Transferido el registro, corren las del nuevo dueño.
- **Transferir el registro no toca sus hilos.** El creado sigue con quien lo tenía; si el nuevo
  dueño lo necesita, se transfiere a mano. Moverlo solo acoplaba el emisor con tareas, y el nuevo
  dueño puede no tener Tareas. Si después corre otra plantilla del nuevo dueño, la obra queda con
  dos hilos, visibles en su ficha.
- **Quien no es dueño no dispara (costo aceptado).** El jefe de taller que quiere "cada obra
  aprobada → Preparar materiales" publica una plantilla con ese paso asignado al equipo Taller;
  cada dueño la copia y la activa, y el paso le llega por asignación. Si un dueño no la activa, el
  taller no se entera: se corrige por proceso. Una sola regla, que da siempre lo mismo: el dueño
  siempre ve su registro.
- **Puerta abierta: activación "cualquier registro del ente".** Si aparece un caso que lo de arriba
  no cubre: una activación por ente, sin importar el dueño, solo para quien tenga la vista `_todas`
  del ente; el hilo nace de quien la activó. Se suma sin tocar lo demás: otro valor en la
  activación y una rama más en `disparar_plantillas`. Descartado: "corren las de todos los que ven
  el registro" — las copias activadas de una plantilla del Catálogo daban un hilo igual cada una, y
  disparar o no dependía de lo compartido en ese momento.
- **`disparar_plantillas` es DEFINER** y chequea a mano lo que la RLS no puede: el dueño puede
  recibir, tiene el submódulo del ente, y lo que ve se mide con funciones `_de(id, usuario)`. Con
  INVOKER corría como quien actuó: no encontraba la plantilla del dueño (`usar_plantilla` filtra
  `dueno_id = auth.uid()`, TA017), el INSERT del hilo pedía `tareas_ver` a quien actuó
  (`tareas_hilos_insert`) y TA021 medía lo que ve él. Supera `GUIDE_ENTES.md` §2.8;
  `emitir_evento` sigue INVOKER.

**Un disparo no se repite por plantilla y registro (2026-09-24).** Si hay un hilo `activo` de esa
plantilla sobre ese registro, no corre. Cerrado cuenta: no vuelve a crearse. Desactivado no cuenta.
Chequeo en `disparar_plantillas`, no unique index: la recurrencia deja el cerrado y el siguiente
activos a la vez. Por plantilla y no por registro, para no bloquear plantillas distintas sobre la
misma obra.

**Referencias relativas, solo en plantillas (2026-09-24).** `{@registro}` (el de "Sobre"; en la
UI, "El registro") y `{@ente:rol}` (quien tenga ese rol en él). Al usarla pasan a
`{ente:uuid|nombre}`, la referencia de siempre. Rol vacío → desaparece (para la frase,
`{si hay ente:rol}…{fin}` o paso condicionado); varios → todos, separados por coma. Cuenta lo que
ve el dueño del hilo, no quien disparó: si no lo ve, desaparece sin nombre. El asignado que no lo
ve lo lee en texto plano, como hoy. "Relacionar" en la plantilla ofrece solo estas: "El registro"
y los roles del ente de "Sobre".

**Sin referencias fijas `{ente:uuid|…}` en plantillas (2026-09-24).** Una plantilla es reusable y
una referencia a un registro concreto casi nunca lo es; además, publicada, mostraba en el Catálogo
el nombre de un registro a quien no lo ve. `guardar_plantilla` las rechaza; las guardadas pasan a
texto plano (el nombre). Cierra el punto 4 de tareas en `BACKLOG.md`.

**Sin el submódulo del ente, la plantilla no se ve (2026-09-24).** Ni en Mis plantillas ni en el
Catálogo, ni se arma con ese "Sobre": sale de la RLS de `entes`; recuperado el submódulo,
reaparece. `tareas_administrar` la ve igual (función admin): la edita, despublica y desactiva, pero
no la usa —el buscador del ente le sale vacío y los roles quedan como marca, sin nombres—.
Administra Tareas sin ganar nada del otro módulo.
