# Catálogo — Insumos y servicios fijos

## El insumo (2026-10-29)

~~**Cada insumo está en una subcategoría, y cada subcategoría en una categoría.**~~ Superada el
2026-10-29: sin subcategoría; ver la decisión siguiente.

**Cada insumo está en una sola categoría, sin subcategoría, como los paquetes (Vidrios → Float
incoloro 4mm, Float bronce 4mm; Herrajes → las ruedas 80kg de cada marca). El insumo tiene peso, espesor,
unidad de comercialización (mm, m2 o u) y sus variantes de color, cada una con su costo.** Son categorías de insumo, distintas de las de
paquete. La unidad de compra es de Compras, como los precios de cada proveedor (*El costo del
insumo vive en el catálogo*).

**Las categorías de insumo las define Técnica**, como las de paquete: carga los
insumos y sabe qué es cada uno. Riesgo aceptado: una categoría nueva no cobra ningún servicio en %
hasta que Administración se la sume (si Técnica crea "Laminados" y carga ahí un vidrio laminado, no
cobra la garantía de vidrio). Se descartó que las cree Administración: Técnica le tendría que pedir
cada categoría nueva.

**Crear una categoría de insumo les avisa a quienes definen los servicios en % (2026-10-29).** "Técnica
creó la categoría de insumo Laminados", y Administración decide si la suma a algún servicio. Es un
aviso común, que se marca leído: no desaparece al sumarla, porque hay categorías que no llevan ningún %
(Herrajes en la garantía de vidrio). Achica el riesgo aceptado de arriba sin sacarlo.

~~**Del insumo cambian el costo y el nombre; categoría, unidad y peso no se editan.**~~ Superada el
2026-10-29; ver la decisión siguiente.

~~**Cada nombre queda con su fecha, y renombrar un insumo ya publicado le avisa al gerente.**~~ Superada
el 2026-10-29: con el nombre fijo desde que un paquete usa el insumo, no queda renombre que avisar; ver
la decisión siguiente.

~~**Todo dato del insumo se edita mientras ningún paquete lo use, en ninguna versión.**~~ Superada el
2026-11-02: el borrador ya no cuenta; ver la decisión siguiente.

**Todo dato del insumo se edita hasta que se envía a revisión una versión que lo usa; el borrador no
cuenta (2026-11-02). Desde ahí solo cambian el costo (un valor nuevo con fecha) y si está activo: nombre,
categoría, unidad, peso y espesor quedan fijos, y si están mal se carga otro insumo; un peso o espesor
vacío se completa una vez (*Un peso o espesor vacío no es 0*).** Hasta ahí, ningún precio aprobado ni
presupuesto depende de él: un "Flaot 4mm" en 6 filas de un borrador o un peso de 1,2 en vez de 0,12 se
corrigen en el momento. Si la única versión enviada que lo usa se retira o se devuelve, vuelve a ser
editable. Después de enviada, la unidad cambia la cuenta, el peso y el espesor los de cada pieza armada
(*Editor de paquete*), la categoría qué servicios en % cobra, y el nombre es lo que el gerente leyó al
aprobar y lo que corta producción: "Float 4mm" → "Float 6mm" con el mismo costo hacía cortar vidrio de 6mm
cobrado como de 4mm. Un borrador que usa un insumo cambiado se revisa igual al enviarlo. Costos aceptados:
Martín puede cambiar un insumo del borrador de Lucía, y Lucía se entera al abrirlo o al enviarlo; un error
de tipeo en el nombre de un insumo ya enviado pide insumo nuevo, versión nueva de cada paquete que lo usa
y aprobación del gerente. Sin historial de nombres ni aviso de renombre.

**El nombre de un insumo es único entre los activos (2026-10-29).** Unique parcial `WHERE activo`: el
nombre de uno de baja se reutiliza. Costo aceptado: el reemplazo de un insumo ya usado, que convive
con él mientras se aprueban las versiones nuevas, lleva otro nombre ("Perfil 20x40 (mm)"), y como el
nombre queda fijo, lo lleva para siempre. Se descartó permitir repetidos con un aviso: en el editor,
Técnica elegía entre dos "Perfil 20x40". El servicio fijo, igual entre los suyos.

**Las categorías (de insumo, de paquete y de servicio) siguen la misma regla: una categoría se edita
mientras no tenga nada adentro; desde que tiene un insumo, un paquete o un servicio fijo, su nombre
queda fijo. Se da de baja solo sin nada activo adentro (2026-10-29).** Renombrar "Vidrios" a
"Herrajes" le mostraba a Administración una garantía de vidrio cobrándose sobre herrajes, y dar de baja
"Vidrios" con 30 insumos activos los dejaba en una categoría que no existe. Un servicio en % sobre una
categoría de baja no cobra nada, sin romper nada.

**No se reactiva nada dentro de una categoría o un color de baja: ni un insumo, ni un paquete, ni un
servicio fijo, ni una variante. La base lo frena y dice qué hay que reactivar primero (2026-11-02).**
Reactivar el Float 4mm con Vidrios de baja lo dejaba activo en una categoría que no existe.

**Dar de baja un insumo saca de la venta solo lo que no se puede armar sin él (2026-11-02). Un paquete
activo cuya versión publicada lo usa se da de baja, en la misma operación, si el insumo es un material
único, si era la última opción de su material y este no permite "sin elección", o si lo elige el
sistema. Si no, el paquete sigue a la venta y se deja de ofrecer lo afectado. En una pieza opcional, lo
que bajaría el paquete deja de ofrecer solo esa pieza.** La regla anterior bajaba todo paquete que usara
el insumo: era anterior a las opciones, y el DVH bajaba la ventana con Float y Laminado disponibles.

```
Técnica da de baja                               En la Ventana corrediza
DVH, una opción del Vidrio                       no se ofrece más el DVH
Contravidrio 6mm, en combo con Laminado 3+3      no se ofrece más el Laminado 3+3, sin pareja
Tela, material único del Mosquitero opcional     no se ofrece más el Mosquitero
La última opción del Vidrio                      sale de la venta, salvo que permita "sin elección"
Escuadra, material único de una pieza fija       sale de la venta
Rueda 80kg, que el sistema elige según el peso   sale de la venta: nadie puede elegir otra
```

- **Lo que se deja de ofrecer se calcula, sin guardar nada, como el color.** La versión no cambia y se
  ofrecen las opciones con su insumo y su pareja activos. Reactivar el DVH lo devuelve, sin versión nueva.
- **Si era el predeterminado, la elección queda sin predeterminado y pasa a primaria**, como con el
  color base.
- **Dar de baja el paquete lo hace la base, no quien da la baja del insumo:** ningún paquete queda a la
  venta con un material que ya no se consigue. Las versiones en borrador o en revisión que usan el insumo
  no cambian, pero la base no deja enviarlas ni aprobarlas con él. Reactivar el insumo no reactiva los
  paquetes: cada uno vuelve cuando Técnica lo reactiva (*Versiones y aprobación*), como cualquier
  paquete de baja. Se descartó que el paquete también se calcule y vuelva solo, como la opción y el color
  (2026-11-02): que vuelva a la venta sigue siendo decisión de Técnica.

```
Técnica da de baja "Rueda 80kg Marca A"
Ventana corrediza 2 hojas y 3 hojas (la usan en su versión publicada)  →  de baja
  El vendedor deja de verlas; los presupuestos que ya las tienen se recalculan con su versión
Técnica saca una versión de cada una con la rueda de Marca B → el gerente las aprueba
  → Técnica reactiva cada paquete
```

**Si la baja de un insumo da de baja algún paquete, el gerente recibe un aviso que apunta a la baja y
lista los paquetes que salieron de la venta (2026-10-29).** Sin aviso, dejaban de venderse paquetes que
él aprobó sin que se enterara; la baja de un servicio fijo le avisa igual (*El servicio fijo*). Si
ninguna versión publicada lo usaba, no avisa: no cambia nada de lo que aprobó. También avisa cuando un
paquete solo deja de ofrecer una opción o una pieza opcional, y dice cuál (2026-11-02): esa oferta
también la aprobó el gerente.

**Antes de confirmar la baja de un insumo, una variante o un servicio fijo, se muestra lo que va a pasar
(2026-11-02).** Quien tiene la vista Paquetes ve "Salen de la venta (8): Ventana 2 hojas, Ventana 3 hojas…
Dejan de ofrecer (1): Puerta balcón"; quien no la tiene, solo los números (amplía *El servicio fijo*). Si
no afecta nada, se confirma como cualquier baja. Reactivar el insumo no reactiva los paquetes: sin esto, una
rueda equivocada dejaba 8 paquetes para reactivar a mano. La cuenta la hace la base con las mismas reglas
de la baja, sin guardar nada.

**El paquete guarda por qué está de baja: a mano, o el insumo o servicio fijo que lo bajó
(2026-10-29).** Técnica ve "De baja por: Rueda 80kg Marca A" y sabe cuáles reactivar, sin confundirlos
con la "Ventana 4 hojas" que dio de baja a propósito en febrero. El aviso al gerente lista los que
siguen de baja por esa causa, y el que se reactiva sale de la lista. Se descartó no guardarlo: Técnica
buscaba a mano qué paquetes usaban la rueda, y el aviso no podía decir cuáles bajó esa baja.

~~**El peso por ahora solo se carga: cómo se usa se decide cuando un módulo lo necesite.**~~ Superada
el 2026-10-30: el peso y el espesor del insumo dan los de cada pieza armada (*Editor de paquete*).

**Las fórmulas se escriben en mm y el sistema pasa el resultado a la unidad de comercialización; el
costo de un insumo por mm se carga por metro.** Con una ventana de 1.500 × 1.200, el perfil marco da
5.392 mm y Administración carga $15.000 el metro; el vidrio 4mm lleva `ancho` y `alto` en sus dos
fórmulas (*Editor de paquete*) y el sistema pasa los 1.800.000 mm² a 1,8 m2. Nadie divide a mano. Costo aceptado: la fórmula no dice en
qué unidad sale, lo dice la unidad del insumo. Se descartó escribir todo en la unidad del insumo
(`ancho × alto / 1.000.000`, $15 por mm): un olvido multiplicaba el precio por mil o por un millón.

**El peso se carga como el costo: kilos por metro, por m2 o por unidad, según la unidad del insumo
(2026-11-02).** Perfil hoja, 0,7 kg/m; Float 4mm, 10 kg/m2; Rueda, 0,05 kg.

**Un peso o espesor vacío no es 0: si una pieza cuenta ese material y el dato está vacío, la base no deja
enviar la versión. El dato vacío se completa una vez, aunque el insumo ya se use, y después queda fijo
(2026-11-02).** Un DVH sin espesor sumaba 0 y "espesor > 24" no saltaba nunca. Un tornillo sin peso no
frena si Técnica marca que no cuente, y con 0 kg escrito vale. Completarlo no cambia nada aprobado: ninguna
versión que contara ese dato pudo enviarse sin él. Sin esto, una versión publicada que no lo contaba y una
nueva que sí pedían otro insumo.

## El servicio fijo (2026-10-29)

**El servicio fijo (Instalación, Soldado) es un registro propio, no un insumo, y sigue las reglas del
insumo salvo el peso y el espesor, que no tiene.** Costo con fecha, unidad de comercialización (el soldado
por u), todo editable hasta que se envía una versión que lo usa y después solo el costo y si
está activo, y su baja saca de la venta solo lo que no se puede armar sin él (*El insumo*). Un material es
un insumo o un servicio fijo. Si va en una tabla o en dos se decide en el SQL: las reglas son las mismas y viven una vez.

Se descartó cargarlo como insumo de una categoría "Servicios": se comportaba igual, pero la empresa
dice "insumos y servicios", Técnica buscaría la Instalación entre los vidrios, el peso quedaba vacío
para siempre y Compras vería el Soldado, que es propio y no se compra.

**Cada servicio fijo está en una categoría de servicio, y esas categorías las define Administración**,
no Técnica como las de insumo. Un servicio en % se cobra sobre categorías de insumo o de servicio (ej:
un seguro de colocación sobre Instalación). Como las crea quien define los %, no corre el riesgo
aceptado con las de insumo: una categoría nueva que no cobra nada porque Administración no sabía que
existía.

**Los servicios fijos los da de alta, renombra y da de baja Administración; Técnica los ve sin costo
y los usa en las fórmulas.** Un servicio nace con su costo y su categoría, de la mano de quien los
define. Costo aceptado: si a un paquete nuevo le falta un servicio ("Colocación de puerta"), Técnica
se lo pide a Administración antes de poder usarlo en la fórmula.

**Dar de baja un servicio fijo funciona como la baja del insumo, aviso al gerente incluido (*El
insumo*), y además le avisa a Técnica, también solo si sacó algo de la venta. Antes de confirmar,
Administración ve cuántos paquetes lo usan: el número, no cuáles.** Un borrador que lo usa no avisa:
la base frena el envío (2026-10-30). Administración no ve paquetes y Técnica no hizo la baja: sin aviso, el
vendedor dejaba de ver 8 ventanas sin que nadie supiera por qué. Técnica saca la versión con otro
servicio, el gerente la aprueba y Técnica reactiva cada paquete. Se descartó que la base no deje darlo
de baja mientras una versión publicada lo use: se seguía vendiendo una instalación que nadie iba a
hacer hasta que Técnica cambiara cada paquete.

## El costo del insumo vive en el catálogo (2026-10-27)

**Cada variante de un insumo tiene un solo costo (el de color indistinto, uno solo), el que se usa para
calcular el precio de venta, y vive acá. Los
precios que ofrece cada proveedor y las cotizaciones viven en Compras.** Son datos distintos: Compras
tiene muchos por insumo y lee el costo para comparar; el catálogo tiene uno, el elegido. Si viviera en
Compras, el catálogo no podría poner precio hasta que exista Compras, que no tiene ficha. Quién lo
carga es un permiso, no un lugar: hoy Administración; si alguien de compras tiene que actualizarlo, se
le da ese permiso, sin copia en Compras.

**Ningún precio de proveedor pasa solo a ser el costo: lo define Administración.** No hay regla que
elija entre lo que cotizan (el más barato, el último): si tres proveedores cotizan el perfil 20x40, el
costo es el que carga Administración, y cambia solo cuando lo vuelve a cargar.

Archivos: corrige `decisiones/contactos.md` → *Los proveedores son empresas de Contactos*.

**Un insumo nuevo le avisa a quienes cargan costos, y el aviso desaparece cuando todas sus variantes tienen costo
(2026-10-29).** Técnica carga "Float 5mm" el lunes y arma la ventana; sin aviso, Administración se
enteraba el jueves, cuando la base frenaba el envío por el insumo sin costo. Como `alta_por_aprobar`
(`db_schema/notificaciones.md`). El servicio fijo nace con su costo y no avisa.

**Un costo rige desde que se carga, sin fecha futura (2026-10-29).** Cuando el proveedor anuncia una
suba, Administración decide en ese momento si la carga ya. Se descartó "rige desde": un campo más por
carga, costos que todavía no rigen en la lista, y el aviso de 15/25/50 % sin saber contra cuál
comparar.

**Los costos también se cargan en bloque: Administración filtra por categoría, escribe los valores o un
"+8 %", y se guardan juntos, cada uno como un valor nuevo con su fecha (2026-11-02).** Con 200 perfiles en 3
colores, una suba de lista eran 600 cargas. Los avisos de 15/25/50 % siguen fila por fila, y lo rojo se
confirma de una vez ("12 filas cambian 50 % o más"): un +80 % por +8 % se ve antes de guardar. Es
`catalogo_costos`, sin permiso nuevo. Pegar desde una planilla se decide al diseñar la pantalla.

**La fecha de cada costo se ve: "hace 9 meses" en la lista, que se ordena por el más viejo, y en el detalle
del gerente (2026-11-02).** Un Float 4mm en pesos de hace 9 meses daba un precio creíble y equivocado. Sin
vencimiento automático ni aviso: cualquier plazo sería inventado, porque un costo en USD aguanta más que uno
en pesos.
