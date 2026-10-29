# Catálogo

**Se arma de cero: no se trae nada de la v1 ni de la v2 (2026-10-26).** La ficha y las decisiones de
este módulo salen solo de preguntas nuevas al usuario. No se lee `obsoletos/catalogo-descartado-2026-10-22/`,
no se compara con lo descartado y no se recupera nada de ahí: ni nombres, ni entes, ni estados, ni
tablas, ni soluciones del tipo "como estaba antes". Si una sesión sabe algo de esas versiones, no lo
propone. Si algo nuevo termina pareciéndose, tiene que ser porque volvió a salir de las preguntas.
El usuario descartó el diseño entero el 2026-10-22 y pidió fichar el módulo sin basarse en él. Lo que
este archivo no dice, no está decidido.

## Ficha del módulo

En armado, punto por punto con el usuario. Objetivo y personas aprobados el 2026-10-27. Entes,
estados, relaciones, acciones, eventos y el árbol de vistas: sin armar. Los entes se discutieron y se
descartaron para retomarlos de cero.

```
Módulo: catalogo
Objetivo: definir qué se puede vender y cómo se calcula: los paquetes, cada uno un despiece (sus
piezas armadas y las fórmulas de cada una), y su precio (los costos de insumos y servicios, y los
servicios en %).
Personas                qué ve · qué hace · qué NO ve
├── Técnica        — insumos, servicios fijos y fórmulas · carga insumos, define las categorías
│                    de insumo y de paquete, arma los paquetes (le pone a cada uno su categoría) y
│                    envía cada versión a revisión, da de baja insumos y paquetes · servicios en %,
│                    costos ni precios
├── Administración — insumos y servicios fijos con su costo, y las categorías · carga los costos de
│                    insumos, da de alta y de baja los servicios fijos y sus categorías, define los
│                    servicios en % y sobre qué categorías se cobran · paquetes ni fórmulas
├── Gerente        — todo: paquetes, fórmulas, costos, % y precios · aprueba o devuelve cada versión
│                    de un paquete · —
├── Vendedor       — NO entra: elige categoría y paquete desde Presupuestos · el precio final ·
│                    costos, % ni fórmulas
├── Cliente        — NO entra: lo mismo que el vendedor, desde erp-cliente
├── Producción     — NO entra: ve las piezas y sus medidas, servicios incluidos, desde Producción
│                    (módulo a hacer) · costos, % ni precios
└── Compras        — NO entra: ve los insumos y su costo desde Compras (módulo a hacer), para
                     comparar con las cotizaciones · %, precios ni fórmulas
Entes
└── a definir
```

Pendientes de la ficha:
- **Entes**: el insumo y el servicio fijo ya están (*El insumo*, *El servicio fijo*); siguen los
  demás.
- **Árbol de vistas y funciones**: la función que ve y hace todo (con ella se revierte un cambio en un
  servicio en %), quién edita un insumo que ningún paquete usa, y si las funciones de Técnica y las de
  Administración se excluyen: un usuario con las dos ve paquete y precio sin pasar por el gerente
  (2026-10-29).
- **Editor de paquete**: qué medidas tiene un paquete y su mínimo y máximo, si las fórmulas llevan
  condicionales o redondeo hacia arriba (barras enteras), y evaluarlas sin SQL dinámico (2026-10-29).

## Al catálogo entran solo los que definen (2026-10-27)

**Técnica, Administración y el gerente (*Versiones y aprobación*) entran al módulo; vendedor, cliente,
producción y compras consumen lo que el catálogo fija desde su propio módulo.** Si alguien de otro módulo necesita ver algo de acá (ej:
producción, las fórmulas), se le da ese permiso a ese usuario: sin persona ni regla nueva. Quien carga
algo lo da de baja: Técnica, también cuando se decide dejar de vender un paquete; Administración, los
servicios fijos (*El servicio fijo*).

**El catálogo guarda el despiece y los precios con fecha; lo que otro módulo hace con eso se decide en
su ficha (2026-10-29).** Ej: qué fecha lleva cada ítem de un presupuesto, si vence, los descuentos, qué
nombre de insumo lee Producción, cómo Compras vincula proveedores.

## Qué es un paquete (2026-10-27)

**Todo lo que se vende es un paquete: un conjunto de piezas armadas. Cada pieza armada es un conjunto
de fórmulas, y cada fórmula es un insumo o un servicio fijo con el cálculo de cuánto lleva según las
medidas del paquete.** Los nombres son los que usa la empresa.

```
Paquete: Ventana corrediza 2 hojas
├── Pieza armada: Marco
│   ├── Fórmula: Perfil marco 20x40 = (ancho − 2) × 2 + (alto − 2) × 2
│   ├── Fórmula: Escuadra           = 4
│   └── Fórmula: Soldado            = 4
├── Pieza armada: Hoja
│   └── …
└── Pieza armada: Colocación
    └── Fórmula: Instalación        = 1
```

- **Una fórmula siempre está en una pieza armada.** Lo que es de todo el paquete va en una pieza
  armada propia (Colocación): con dos lugares posibles, cada pantalla y cada cálculo contemplaría los
  dos. Las medidas son del paquete, así que cualquier fórmula calcula con ellas.
- **La fórmula es el despiece: lo que se corta, sin merma (2026-10-29).** Producción corta con ella
  (*Personas*): con un 10 % de merma en el perfil marco, la lista de corte diría 5.931 mm en vez de
  5.392. La merma la pone Administración en el precio, como ella decida: dentro del costo o como
  servicio en % sobre una categoría. El catálogo ya permite las dos, sin nada propio para la merma.
- **No se reutilizan piezas armadas entre paquetes.** Habrá pocos paquetes y cada uno se calcula
  distinto.
- **Cada paquete tiene una sola categoría, según qué es el producto** (ej: Ventana corrediza → 2
  hojas, 3 hojas; Paño fijo → sus tipos). Las define Técnica y le pone una a cada paquete al armarlo.
  El vendedor, en Presupuestos, elige primero la categoría y después el paquete. Sin subcategoría
  (Ventanas → Corrediza → 2 hojas), descartada el 2026-10-29 para paquetes e insumos.
- **El nombre y la categoría son de la versión: cambiarlos es sacar una versión nueva, que aprueba el
  gerente (2026-10-29).** Lo que ve el vendedor lo aprobó el gerente, y un presupuesto viejo muestra el
  nombre de su versión. Cuando exista el % por categoría (`BACKLOG.md`), mover un paquete de categoría
  ya pasa por el gerente. Se descartó que sean del paquete y se cambien sin aprobación: los
  presupuestos viejos mostraban el nombre nuevo, y la categoría movería el precio sin que el gerente
  lo viera.
- **Hoy no se vende nada suelto.** El catálogo de un proveedor alimenta insumos para usar dentro de
  los paquetes. Para cuando revendan perfiles ya hay camino decidido (`BACKLOG.md`).

## El insumo (2026-10-29)

~~**Cada insumo está en una subcategoría, y cada subcategoría en una categoría.**~~ Superada el
2026-10-29: sin subcategoría; ver la decisión siguiente.

**Cada insumo está en una sola categoría, sin subcategoría, como los paquetes (Vidrios → Float
incoloro 4mm, Float bronce 4mm; Herrajes → las ruedas 80kg de cada marca). El insumo tiene su costo,
peso y unidad de comercialización: mm, m2 o u.** Son categorías de insumo, distintas de las de
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

**Todo dato del insumo se edita mientras ningún paquete lo use, en ninguna versión. Desde que alguno lo
usa, solo cambian el costo (un valor nuevo con fecha) y si está activo: nombre, categoría, unidad y peso
quedan fijos, y si están mal se carga otro insumo (2026-10-29).** Mientras nadie lo usa, ningún precio,
versión ni presupuesto depende de él: un "Flaot 4mm" o un peso de 1,2 en vez de 0,12 se corrigen en el
momento. Una vez usado, la unidad cambia la cuenta, la categoría qué servicios en % cobra, y el nombre
es lo que el gerente leyó al aprobar y lo que corta producción: "Float 4mm" → "Float 6mm" con el mismo
costo hacía cortar vidrio de 6mm cobrado como de 4mm. Costo aceptado: un error de tipeo en el nombre
de un insumo ya usado pide insumo nuevo, versión nueva de cada paquete que lo usa y aprobación del
gerente. Sin historial de nombres ni aviso de renombre.

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

**Dar de baja un insumo da de baja, en la misma operación, cada paquete activo cuya versión publicada
lo usa.** Lo hace la base, no quien da la baja: ningún paquete queda a la venta con un material que ya
no se consigue. Las versiones en borrador o en revisión que lo usan no cambian, pero la base no deja
enviarlas ni aprobarlas con ese insumo. Reactivar el insumo no reactiva los paquetes: cada uno vuelve
cuando Técnica lo reactiva (*Versiones y aprobación*), como cualquier paquete de baja.

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
ninguna versión publicada lo usaba, no avisa: no cambia nada de lo que aprobó.

**El paquete guarda por qué está de baja: a mano, o el insumo o servicio fijo que lo bajó
(2026-10-29).** Técnica ve "De baja por: Rueda 80kg Marca A" y sabe cuáles reactivar, sin confundirlos
con la "Ventana 4 hojas" que dio de baja a propósito en febrero. El aviso al gerente lista los que
siguen de baja por esa causa, y el que se reactiva sale de la lista. Se descartó no guardarlo: Técnica
buscaba a mano qué paquetes usaban la rueda, y el aviso no podía decir cuáles bajó esa baja.

**El peso por ahora solo se carga: cómo se usa se decide cuando un módulo lo necesite.**

**Las fórmulas se escriben en mm y el sistema pasa el resultado a la unidad de comercialización; el
costo de un insumo por mm se carga por metro.** Con una ventana de 1.500 × 1.200, el perfil marco da
5.392 mm y Administración carga $15.000 el metro; el vidrio 4mm se escribe `ancho × alto` y el
sistema pasa los 1.800.000 mm² a 1,8 m2. Nadie divide a mano. Costo aceptado: la fórmula no dice en
qué unidad sale, lo dice la unidad del insumo. Se descartó escribir todo en la unidad del insumo
(`ancho × alto / 1.000.000`, $15 por mm): un olvido multiplicaba el precio por mil o por un millón.

## El servicio fijo (2026-10-29)

**El servicio fijo (Instalación, Soldado) es un ente propio, no un insumo, y sigue las reglas del
insumo salvo el peso, que no tiene.** Costo con fecha, unidad de comercialización (la instalación
por m2, el soldado por u), todo editable hasta que un paquete lo usa y después solo el costo y si
está activo, y su baja da de baja los
paquetes que lo usan en su versión publicada (*El insumo*). Una fórmula es un insumo o un servicio
fijo. Si va en una tabla o en dos se decide en el SQL: las reglas son las mismas y viven una vez.

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
insumo*), y además le avisa a Técnica. Antes de confirmar, Administración ve cuántos paquetes lo
usan: el número, no cuáles.** Administración no ve paquetes y Técnica no hizo la baja: sin aviso, el
vendedor dejaba de ver 8 ventanas sin que nadie supiera por qué. Técnica saca la versión con otro
servicio, el gerente la aprueba y Técnica reactiva cada paquete. Se descartó que la base no deje darlo
de baja mientras una versión publicada lo use: se seguía vendiendo una instalación que nadie iba a
hacer hasta que Técnica cambiara cada paquete.

## El costo del insumo vive en el catálogo (2026-10-27)

**Cada insumo tiene un solo costo, el que se usa para calcular el precio de venta, y vive acá. Los
precios que ofrece cada proveedor y las cotizaciones viven en Compras.** Son datos distintos: Compras
tiene muchos por insumo y lee el costo para comparar; el catálogo tiene uno, el elegido. Si viviera en
Compras, el catálogo no podría poner precio hasta que exista Compras, que no tiene ficha. Quién lo
carga es un permiso, no un lugar: hoy Administración; si alguien de compras tiene que actualizarlo, se
le da ese permiso, sin copia en Compras.

**Ningún precio de proveedor pasa solo a ser el costo: lo define Administración.** No hay regla que
elija entre lo que cotizan (el más barato, el último): si tres proveedores cotizan el perfil 20x40, el
costo es el que carga Administración, y cambia solo cuando lo vuelve a cargar.

Archivos: corrige `decisiones/contactos.md` → *Los proveedores son empresas de Contactos*.

**Un insumo nuevo le avisa a quienes cargan costos, y el aviso desaparece cuando tiene costo
(2026-10-29).** Técnica carga "Float 5mm" el lunes y arma la ventana; sin aviso, Administración se
enteraba el jueves, cuando la base frenaba el envío por el insumo sin costo. Como `alta_por_aprobar`
(`db_schema/notificaciones.md`). El servicio fijo nace con su costo y no avisa.

**Un costo rige desde que se carga, sin fecha futura (2026-10-29).** Cuando el proveedor anuncia una
suba, Administración decide en ese momento si la carga ya. Se descartó "rige desde": un campo más por
carga, costos que todavía no rigen en la lista, y el aviso de 15/25/50 % sin saber contra cuál
comparar.

## Servicios: fijos o en % (2026-10-27)

**Un servicio fijo (ej: el soldado de los perfiles, propio) es una fórmula más: unidades × su costo.
Un servicio en % con mínimo (ej: comercialización) es monetario: no forma parte del despiece y entra
al armar el precio.** Cómo entra el de %: *Servicios en %*.

## Servicios en %: la base ordena el cálculo (2026-10-27)

**"El %" de Administración son los servicios en %, cada uno con su % y su base; cualquiera puede ser
opcional, y quien presupuesta decide si va. No hay ganancia aparte: va dentro de comercialización.**
Las bases, en el orden en que se calculan:

1. Todo el despiece (ej: comercialización), o los insumos y servicios fijos de ciertas categorías
   (ej: garantía de vidrio, sobre Vidrios).
2. El subtotal: el despiece más los del paso 1 (ej: un recargo en la transición del modelo de negocio).
3. El precio final, despejado para que sea el % exacto (ej: IIBB). Varios se despejan juntos:
   monto / (1 − suma de los %).

```
Costo del despiece                                     $200.000
Garantía de vidrio    5 % de los Vidrios ($60.000)       $3.000
Manipulación          5 % de los Vidrios                 $3.000
Comercialización     10 % del despiece (mín. $15.000)   $20.000
Subtotal                                               $226.000
Transición            4 % del subtotal                   $9.040
IIBB                  3 % del precio final               $7.269   (235.040 / 0,97)
Precio de venta                                        $242.309
```

Dentro de un paso ningún servicio se calcula sobre otro: el orden lo dan los pasos, así Administración
nunca ordena servicios y sacar un opcional solo cambia lo que se calcula después.

**Los % del paso 3 suman menos de 100: la base no deja cargar uno que los lleve a 100 o más
(2026-10-29).** Con 100 la cuenta divide por cero, y con más da un precio negativo.

~~**La marca va en la pieza armada, no en el insumo ni en el renglón.**~~ Superada el 2026-10-29: los
insumos ahora tienen categoría (*El insumo*); ver la decisión siguiente.

**Un servicio en % se cobra sobre categorías de insumo, no sobre piezas marcadas (2026-10-29).**
Administración elige las categorías de cada servicio (garantía de vidrio → Vidrios; también de
servicio, *El servicio fijo*) y el % toma el costo de esos insumos en todo el paquete, en la pieza
que estén. Técnica no marca nada ni ve los
servicios: un paquete nuevo cobra la garantía de su vidrio sin que nadie se acuerde, y ningún material
va a una pieza propia solo para cobrarle un %. Con la marca en la pieza, un olvido dejaba el servicio
sin cobrar y solo lo atajaba el gerente. Lo que no da: un servicio sobre una pieza por lo que es y no
por sus materiales; ese va sobre todo el despiece.

**Un servicio en % puede tener mínimo, y elige si lo compara por paquete o por presupuesto.** Por
paquete, contra el servicio de cada unidad, y la diferencia queda dentro de su precio. Por
presupuesto, contra la suma del servicio en todos los ítems, y la diferencia va en un renglón aparte
que pasa por los pasos siguientes: una obra con muchas piezas chicas no paga el mínimo en cada una.
Si el servicio no aplica (nada de sus categorías, opcional no elegido), no hay mínimo. Los que se
despejan no tienen: son el % exacto del precio. La cuenta del presupuesto entero la hace una función
del catálogo, así la regla vive en un solo lugar.

```
Garantía de vidrio 5 %, mínimo $10.000 por presupuesto
2 Ventanas corredizas   vidrio $60.000 c/u         →  $6.000
3 Paños fijos           vidrio $20.000 c/u         →  $3.000
1 Puerta ciega          sin vidrio                 →  no cuenta
Mínimo de garantía de vidrio            $10.000 − $9.000 = $1.000, en renglón aparte
```

**Un servicio en % tiene un % general y, si hace falta, uno distinto por categoría de paquete**
(*Qué es un paquete*). La categoría dice qué es el producto, no cuánto se cobra, así que Técnica
clasifica sin ver el %. Administración ve los nombres de las categorías y carga solo las
excepciones. Una categoría sin % propio usa el general, así ningún paquete queda sin %. Las
categorías ya existen para el vendedor; el % por categoría espera un caso real (`BACKLOG.md`).

## El precio sale de una función, sin despiece (2026-10-27)

**Vendedor y cliente reciben solo el precio de cada paquete y el renglón del mínimo por presupuesto:
ni despiece, ni costos, ni desglose de los servicios en %.** Una función del catálogo recibe el
paquete, las medidas y los opcionales elegidos, lee lo que quien llama no puede abrir y devuelve solo
el número, como `obras_contar`. Así lo que no ven (*Personas*) no depende de ocultarlo en pantalla. Ven
el nombre de cada opcional para elegirlo, no su %. El cliente, desde erp-cliente, recibe lo mismo.

**La versión y la fecha con que se calcula un precio nunca las elige quien llama (2026-10-29).**
Vendedor y cliente reciben la versión publicada con los valores de hoy, o al recalcular, los que la
base lee del presupuesto guardado. El gerente, que ve todo, puede pedir cualquier versión y fecha (para
aprobar, una en revisión). Si la función aceptara una fecha, un vendedor pedía "marzo" y cotizaba con
los costos de marzo, y desde erp-cliente se cotizaba un borrador.

## El IVA lo suma Presupuestos (2026-10-29)

**El precio del catálogo es sin IVA: lo suma quien presupuesta, en Presupuestos. Por eso los costos de
insumos y servicios fijos se cargan sin IVA**: con IVA, el presupuesto lo cobraría dos veces. El IIBB
del paso 3 se despeja sobre ese precio sin IVA (*Servicios en %*).

Archivos: `BACKLOG.md` → *Presupuestos*.

## Un presupuesto se recalcula como era (2026-10-27)

**Un presupuesto se recalcula con las condiciones de su fecha: lo que forma el precio no se pisa.**
Cambiar un costo, un servicio en % (cualquier dato, no solo el %) o un tipo de cambio (en Monedas)
agrega un valor nuevo con fecha, y el anterior queda; la
versión publicada de un paquete no se edita, se saca otra. El presupuesto guarda su fecha y la versión
de cada paquete, y la función del precio usa lo que valía a esa fecha: si el cliente cambia una medida
en un presupuesto de marzo, se le respeta el precio de marzo.

Se descartó que cada presupuesto guarde copia de los costos y los %: la copia tendría que vivir en el
catálogo para que el vendedor no la lea, y un paquete sumado a un presupuesto viejo no tendría sus
insumos en ella.

## Moneda (2026-10-29)

**El presupuesto elige en qué moneda sale el precio (en USD, también si oficial o blue), y el catálogo
convierte todo a esa moneda con los tipos de cambio de la fecha del presupuesto, que lee de Monedas
(`decisiones/monedas.md`), mínimos incluidos.** El vendedor marca USD y la ventana
sale "USD 182" sin que nadie convierta a mano. La función del precio recibe la moneda junto con el
paquete y las medidas (*El precio sale de una función*).

**Cada monto que carga Administración lleva su moneda, elegida en cada carga: el costo de un insumo o
de un servicio fijo y el mínimo de un servicio en %.** Si el proveedor del perfil 20x40 deja de cotizar
USD 12 y pasa a $18.000, Administración carga los $18.000 y listo; el aviso de 15/25/50 % compara contra
el anterior pasado a la moneda nueva con el tipo de cambio del día (USD 12 × 1.450 = $17.400 → +3 %,
sin color). Cada valor guarda su moneda con su fecha, así que los presupuestos viejos no cambian. Un
monto en USD dice además si es oficial o blue, y todo se convierte pasando por el peso, cada monto con
su dólar (`decisiones/monedas.md` → *Tipos de cambio*). Se descartó la moneda fija en el insumo, como la unidad:
la unidad cambia la cuenta de lo que el gerente aprobó y la moneda no (USD 12 y $17.400 son el mismo
costo), y fija obligaba a convertir a mano o a cargar otro insumo, con versión nueva de cada paquete.

## ~~Tipos de cambio~~ (2026-10-27)

Mudados al módulo Monedas el 2026-10-29: `decisiones/monedas.md`. **El catálogo lee de ahí el tipo de
cambio vigente a la fecha y hora del cálculo, y no guarda ninguno.**

## Versiones y aprobación (2026-10-27)

**Cada paquete tiene versiones; una versión pasa por borrador → en revisión → publicado → obsoleto, y
la aprueba solo el gerente.** Técnica la envía a revisión y desde ahí no se edita, así el gerente
aprueba lo que vio. La base no deja enviarla si falta algo (un insumo sin costo o de baja, una pieza
sin fórmulas). El gerente ve el despiece, el precio para las medidas que elige y qué cambió respecto de la
versión anterior, y la aprueba (publicado) o la devuelve (borrador). La publicada no se modifica: para
cambiarla se saca otra versión.

**Cada paquete tiene una sola versión abierta (borrador o en revisión) a la vez, y Técnica puede
retirarla de revisión: vuelve a borrador sin pasar por el gerente (2026-10-29).** Con la v3 en revisión
y una rueda discontinuada, Técnica la retira, le cambia la rueda y la reenvía: el gerente aprueba una
con los dos cambios, y "qué cambió" se compara siempre contra la publicada. Se descartó tener varias
abiertas, cada una copiada de la publicada: la v4 salía de la v2 sin el vidrio de la v3, y aprobar las
dos en orden publicaba la v4 sin él.

**Obsoleto es solo la versión reemplazada: pasa sola cuando se publica la siguiente. Dejar de vender
es la baja del paquete (`activo = false`), y sus versiones quedan como estaban.** Reactivarlo vuelve a
vender su versión publicada sin pasar por el gerente, que ya la aprobó; la base no deja si uno de sus
insumos está de baja, y entonces va una versión nueva. Con el paquete de baja, aprobar una versión en
revisión no lo pone a la venta, y los presupuestos que ya lo tienen se recalculan con su versión. Se
descartó un solo estado obsoleto para las dos cosas: la baja tendría dos formas, y una versión
aprobada después de dejar de vender volvía a poner el paquete a la venta sin que nadie lo decidiera.

Técnica no ve precios y Administración no ve paquetes: una fórmula olvidada daba un precio creíble que
llegaba al vendedor, o directo al cliente por erp-cliente. El gerente es el único que ve paquete y
precio juntos, y como los paquetes cambian poco, aprobar cada versión no frena a nadie.

**Administración no confirma nada por paquete.** Los % son generales y tienen su historia; lo que
podía faltar de su lado, un costo, lo frena la base al enviar.

Se descartaron: aprobar solo si el precio se mueve más de un % (un olvido chico pasa, y con pocos
cambios se ahorra poco), publicar a prueba para vendedores (un presupuesto puede salir mal antes de la
revisión) y un segundo técnico sin precios (no ve lo que solo aparece en el precio, como fórmula en
metros contra costo por barra).

**Los costos no pasan por aprobación, pero al cargarse avisan si se mueven mucho** ("subió 900 %
respecto del anterior, ¿confirmás?"). Cambian seguido, y un error de tipeo cambiaría el precio de
todos los paquetes con ese insumo sin que nadie lo revise.

**Tres niveles contra el valor anterior, para subas y bajas: desde 15 % amarillo, desde 25 %
naranja, desde 50 % rojo. Amarillo y naranja solo marcan y guardan; rojo pide confirmación.** Vale
igual para el costo de un insumo o servicio fijo y para el % de un servicio, medido contra el %
anterior (12 → 15 % es +25 %, naranja; 12 → 120 % es ×10, rojo): un % mal cargado mueve el precio de
todos los paquetes que lo llevan. El cambio se muestra escrito junto al color. Los errores típicos (un cero de más o de
menos, otra unidad) mueven el costo 5 veces o más y caen en rojo; el amarillo deja ver dígitos
invertidos ($1.250 → $1.520, +22 %). Que los cambios reales de lista (15–50 %) no pidan confirmar evita
que se confirme todo sin leer. Un insumo sin costo anterior no avisa. Se descartó un solo umbral
("doble o mitad"): atajaba los errores grandes pero no mostraba los medianos.

**Cualquier cambio en un servicio en % le avisa al gerente: su %, sus categorías, su base,
su mínimo y cómo lo compara, si es opcional, y su alta o baja (2026-10-29).** Rige al instante: el
aviso apunta al cambio en la historia del servicio ("Ana
sumó Herrajes a Garantía de vidrio") y el gerente lo revierte si está mal. Un servicio mueve el precio
de todos los paquetes que el gerente aprobó, y los colores solo miden el número del %: sumar Herrajes
a la garantía de vidrio por error no daba color ni le llegaba a nadie. Los servicios cambian poco, así
que el aviso no se vuelve ruido; los costos cambian seguido y no le avisan, porque dejaría de leerlos.
Se descartó que el gerente apruebe cada cambio antes de que rija: Administración lo esperaría para
cada ajuste. Riesgo aceptado: un presupuesto hecho entre el cambio y la reversión queda con el cambio,
porque se recalcula como era (*Un presupuesto se recalcula como era*).
