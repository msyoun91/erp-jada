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

**~~Plantillas por evento esperan a su primer emisor.~~** → Obras emite; `disparar_plantillas`
conectado en `sql/152` (*El disparo sigue al registro*).

**`{dato}`, condiciones por rol y pasos condicionados llegan con el disparo (2026-09-24).** Leen un
registro, y a mano no hay registro: `master` tampoco los usaba fuera de un disparo. `sql/118` guarda
el texto tal cual; las columnas (`condicion`, datos) se suman con el primer emisor, junto con
`disparar_plantillas` y las activaciones. Con "Sobre", usarla a mano elige el registro, así que
`{dato}`, condiciones y pasos que se completan solos valen igual a mano que en el disparo (2026-09-29).

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

**La activación va en la plantilla, sin tabla aparte (2026-09-29).** Decisión del usuario.
`tareas_plantillas` suma `sobre` (ente, nullable), `disparo_evento` (`alta` | `estado`, uno de
`entes.disparos` del ente de "Sobre"), `disparo_estado` (con `estado`) y `disparo_activo`. Un disparo
por plantilla. La tabla de activaciones de `master` existía porque las plantillas se compartían y
cada usuario prendía la suya. Hoy toda plantilla es personal (*Toda plantilla es personal*) y la
activa solo su dueño. La copia del Catálogo trae evento y estado con `disparo_activo = false`. Si
hace falta la *Puerta abierta* ("cualquier registro del ente"), es otro valor acá.

**Prende el disparo su dueño; lo apaga también el admin (2026-09-29).** Como publicar: el admin
edita y despublica lo ajeno, pero no lo pone a correr en nombre de otro (TA025). Editar sin tocar el
disparo no cuenta como prenderlo. `sql/149`.

**Qué marca vale para qué ente lo dice una función, y la hacen valer dos triggers (2026-09-29).**
`tareas_plantilla_vale(sobre, evento, valor)`: rol de `entes.roles`, valor del enum de
`entes.estados`, `alta` sin valor. La usan el disparo, la condición del paso y "se completa cuando",
así que un ente nuevo con roles o estados vale sin tocar Tareas. Los pasos se validan al insertarse
(solo se insertan: guardar reemplaza) y cambiar "Sobre" rechaza si algún paso activo no le vale
(TA024); por eso `guardar_plantilla` apaga los pasos viejos antes de tocar la plantilla. "Sobre" pide
el submódulo del ente solo cuando cambia (TA023): el admin edita una plantilla sobre un ente que no
ve sin perder su "Sobre". Las marcas del texto se validan igual, al insertar el paso (`sql/150`,
*Las marcas valen al guardar*). `sql/149`.

**El ciclo siguiente de un hilo recurrente sigue sobre el mismo registro y plantilla (2026-09-29).**
La recurrencia copia `registro_ente`, `registro_id` y `plantilla_id`: es el caso por el que "no se
repite" es un chequeo y no un unique index. `sql/149`.

**Las marcas valen al guardar, y cada una en su lugar (2026-09-29).** La misma validación que la
condición (`tareas_plantillas_paso_vale`), así que una plantilla guardada nunca tiene una marca que
`usar_plantilla` no sepa leer. En el título solo `{dato}`: el título no lleva referencias
(`registro.md`) y un `{si…}` podía dejarlo vacío. `{si…}…{fin}` no se anida: un nivel alcanza para
"si hay arquitecto, coordinar con él". Sin "Sobre", ninguna marca —como la condición—; otras llaves
(`{Hola}`, `{X}`) son texto. Archivos: `sql/150`, `sql/tests/tareas_usar_plantilla_registro.sql`.

**Las marcas se resuelven con lo que ve quien la usa (2026-09-29).** A mano, quien la usa (el
responsable del hilo nuevo); en el disparo, el dueño del registro: la misma interna DEFINER,
`tareas_usar_plantilla_de(..., usuario)`. "Hay rol" (`{si hay}`, condición del paso) es que el
registro tenga el vínculo abierto; `{@rol}` nombra solo lo que el usuario ve. Hoy da lo mismo: quien
ve el registro ve sus contactos (`contactos_puede_ver_persona_de`). Un paso que no entra no corta la
cadena: el siguiente espera al anterior que sí entró. Sumar a un hilo existente pide el registro
para leer las marcas, pero no se lo cambia. `sql/150`.

**Un paso se completa solo cuando el registro cumple (2026-09-29).** "Vincular {rol}" y "pasar a
{estado}" (`decisiones/obras.md` → *Dos acciones*) se copian de la plantilla al paso y se evalúan al
llegar el evento, al nacer el paso, al aceptarlo y al habilitarse: rol = el registro tiene un vínculo
abierto con ese rol, sea quien sea que lo vea; estado = está en ese estado ahora (si ya avanzó, lo
completa el asignado). Un pedido sin aceptar o un paso bloqueado esperan. Es la excepción a
*completar es solo del asignado* (`participacion.md`): lo escribe la base en cascada (`escrituras.md`
→ *Las reglas de actor valen para lo que escribe una persona*) y lo pidió el usuario; el asignado lo
puede completar a mano igual. Reabrir no lo vuelve a evaluar —si no, un paso cerrado solo no se
podría reabrir— y desvincular no lo reabre. El resultado queda vacío (decisión del usuario): la base
no tiene los labels de roles y estados, así que la pantalla muestra la condición. Sumada a un hilo
que no es sobre ese registro, la plantilla no copia la condición. Archivos: `sql/153`,
`sql/tests/tareas_pasos_se_completan.sql`.

**El link de acción es una marca de la descripción: `{@accion|texto}` (2026-09-29).** Decisión del
usuario, sobre hacer link la fila "Se completa sola": quien arma la plantilla elige dónde va el link
y con qué palabras. Vale solo en la descripción de un paso con "Se completa" (la acción sale de esa
condición: `?vincular={rol}` o `?estado={valor}`), sin llaves adentro (TA024). La base no la
resuelve y pasa tal cual al paso; la pantalla la vuelve link a la ficha del registro del hilo: con el
panel abierto si quien lee trabaja el registro y el paso está abierto, a la ficha sola si lo ve sin
trabajarlo o el paso ya cerró, y texto plano si no lo ve, si el paso no se completa solo (sumada a un
hilo que no es sobre ese registro) y fuera del panel del paso (Misión). El formulario la ofrece como
chip "Link de acción" con "Vincular {rol}" / "Pasar a {estado}". Archivos: `sql/154`,
`sql/tests/tareas_marca_accion.sql`, `derivados.ts` (`hrefAccion`), `TextoConReferencias.tsx`,
`PlantillaFormPanel.tsx`, `e2e/tareas.spec.ts`. Con la pestaña del registro en el paso, el link
no sale del hilo (`registro.md` → *El link de acción se resuelve en la pestaña*).

**Un disparo no se repite por plantilla y registro (2026-09-24).** Si hay un hilo `activo` de esa
plantilla sobre ese registro, no corre. Cerrado cuenta: no vuelve a crearse. Desactivado no cuenta.
Chequeo en `disparar_plantillas`, no unique index: la recurrencia deja el cerrado y el siguiente
activos a la vez. Por plantilla y no por registro, para no bloquear plantillas distintas sobre la
misma obra.

**Referencias relativas, solo en plantillas (2026-09-24).** `{@registro}` (el de "Sobre"; en la
UI, "El registro") y `{@rol}` (quien tenga ese rol en él; *Marcas de rol sin ente*). Al usarla pasan a
`{ente:uuid|nombre}`, la referencia de siempre. Rol vacío → desaparece (para la frase,
`{si hay rol}…{fin}` o paso condicionado); varios → todos, separados por coma. Cuenta lo que
ve el dueño del hilo, no quien disparó: si no lo ve, desaparece sin nombre. El asignado que no lo
ve lo lee en texto plano, como hoy. "Relacionar" en la plantilla ofrece solo estas: "El registro"
y los roles del ente de "Sobre".

**Marcas de rol sin ente: `{@arquitecto}`, no `{@persona:arquitecto}` (2026-09-29).** Decisión del
usuario, al arrancar el tramo 5. En una obra, un rol lo puede tener una persona (Laura) o una empresa
(un estudio): `contactos_vinculos` lleva una o la otra con los mismos `roles`. Con el ente adelante,
`{@persona:arquitecto}` no encontraba al estudio y había que escribir las dos marcas. Los roles son
los de `entes.roles` del ente de "Sobre", así que el rol solo alcanza para `{@rol}`,
`{si hay rol}…{fin}` / `{si no hay rol}…{fin}`, la condición del paso (`rol` / `!rol`) y "vincular
{rol}" (se completa con cualquier `relacion_alta` de ese rol, sea persona o empresa).

**Sin referencias fijas `{ente:uuid|…}` en plantillas (2026-09-24).** Una plantilla es reusable y
una referencia a un registro concreto casi nunca lo es; además, publicada, mostraba en el Catálogo
el nombre de un registro a quien no lo ve. `guardar_plantilla` las rechaza; las guardadas pasan a
texto plano (el nombre). Trigger en las dos tablas y no chequeo en `guardar_plantilla`:
`authenticated` inserta pasos directo. Archivos: `sql/123_tareas_plantillas_sin_referencias.sql`,
`sql/tests/tareas_plantillas.sql`, `types.ts` (`textoPlantilla`).

**Sin el submódulo del ente, la plantilla no se ve (2026-09-24).** Ni en Mis plantillas ni en el
Catálogo, ni se arma con ese "Sobre": sale de la RLS de `entes`; recuperado el submódulo,
reaparece. `tareas_administrar` la ve igual (función admin): la edita, despublica y desactiva, pero
no la usa —el buscador del ente le sale vacío y los roles quedan como marca, sin nombres—.
Administra Tareas sin ganar nada del otro módulo.
