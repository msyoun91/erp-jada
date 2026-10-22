# Catálogo — servicios

Lo que no es material y se cobra: procesamiento, colocación de burlete, soldadura, mano de obra de
instalación, y los comerciales: comercialización, manipulación (⚠ choque 4, `pendiente.md`). No es
ente (`ficha.md` → *Entes*). Un servicio entra de tres maneras: cargado en el paquete, por regla, o
porque lo trae un insumo.

- **Fijo o porcentual, cada uno con su unidad** (2026-10-14). **Fijo**: monto por unidad del
  servicio — cada servicio tiene unidad: ml, m² o unidad (soldadura $ 1.500 c/u, colocación de
  burlete $ X por ml); la cantidad se convierte como la de un insumo (`motor.md` → *Las fórmulas
  trabajan en mm*). **Porcentual**: % sobre la suma de los insumos **de su grupo** (no del paquete
  entero), sin las categorías marcadas fuera del % (*El % de los servicios del paquete deja afuera…*),
  con mínimo opcional (`precio.md` → *El 0 se rechaza donde vacío es "falta"*) — el mínimo se aplica
  **una vez por servicio en el paquete**, sobre la suma de sus grupos, no en cada grupo (mano de obra
  15 %, mín $ 5.000). Como el paquete calcula una abertura, el mínimo es **por ventana**: 4 chicas de
  $ 3.000 cobran 4 × $ 5.000 (`motor.md` → *La cantidad es de la línea*).
- **Montos, % y mínimos los pone administración; el técnico no los ve.** Rigen al instante
  (`precio.md` → *Los cambios de plata de administración rigen al instante*).
- **El servicio se edita directo.** No está en el despiece: corregirlo cambia precios, no
  órdenes. **Unidad y tipo (fijo o porcentual) quedan fijos desde que está en una versión, borradores
  incluidos, en una regla o lo trae un insumo** (2026-10-21), como la unidad del insumo: antes se
  corrigen libres, y después el campo dice por qué (*Colocación de burlete: en 20 paquetes · para otra
  unidad, servicio nuevo*). Otra unidad u otro tipo es un servicio nuevo y la baja del viejo. Por qué:
  *Colocación de burlete* de ml a unidad cobraba 5.980 colocaciones en 20 vigentes; un fijo pasado a
  porcentual dejaba su cantidad sin sentido, y un porcentual pasado a fijo, sus reglas. Con los dos
  fijos al técnico le queda el nombre, así que el servicio no necesita el freno del insumo
  (`insumos.md` → *Lo que cambia el cálculo de un insumo en uso espera a administración*).
- **En el paquete, cada servicio va en un grupo, con su cantidad, y puede llevar condiciones**
  (2026-10-14). Pestaña Servicios al lado de Materiales: el técnico elige el servicio del catálogo y
  le pone cantidad fija o por variable (soldadura × 4); el monto no se ve. Como los materiales, va en
  un grupo: si el vendedor saca un grupo opcional (mosquitero), su mano de obra sale con él. Lleva
  condiciones en las mismas casillas que un material (`motor.md` → *La condición se carga en
  casillas*): "mano de obra extra si `alto` > 2400"; el despiece dice por qué entró. Puede mirar el
  peso: un servicio no suma al peso.
- **Un insumo puede traer sus servicios, y entran con él en todo paquete** (2026-10-21). En la
  *Manija embutida* el técnico carga una vez *lleva Mecanizado de embutido × 1 por unidad*: donde la
  manija entra, entra el mecanizado, en su mismo grupo, y el despiece dice por qué (*Mecanizado de
  embutido — por Manija embutida (hoja izq)*). Si el vendedor elige otra manija, no entra. La
  cantidad es la puesta del insumo, sin desperdicio (5,98 ml de burlete → 5,98 ml de *Colocación de
  burlete*). Solo servicios fijos: el % por insumo ya es la regla por categoría. **Solo de la misma
  unidad que el insumo** (2026-10-21): al cargarlo se eligen entre los de su unidad. El *Sellado
  perimetral* (ml) no lo trae el *Float 4 mm* (m²), que cobraba 0,714 ml de un perímetro de 3,44: va
  en cada paquete con su fórmula de perímetro. Descartado: un factor de ml por m² (el perímetro no es
  proporcional a la superficie). Solo en paquetes: la manija vendida suelta no lo lleva. Sin excepción
  por paquete: si en una puerta viene mecanizada de fábrica, es otro insumo. El técnico no ve el
  monto. Como el insumo no se versiona, entra en las vigentes sin versión nueva; en uso, cuando lo
  aprueba administración (`insumos.md` → *Lo que cambia el cálculo de un insumo en uso espera a
  administración*). Antes de proponerlo se ve el alcance (*Manija embutida: suma Mecanizado de
  embutido en 15 paquetes · en 3 ya está cargado a mano: se cobra una vez, el de la manija*). **Si el
  mismo servicio entra en un grupo por un insumo y a mano, se cobra una vez: el del insumo**
  (2026-10-21). El despiece lo dice (*Mecanizado de embutido (a mano): no se cobra, lo trae Manija
  embutida (hoja izq)*) y *mandar a aprobar* frena hasta sacar el manual. Por qué: aprobado el
  cambio, las 3 vigentes cobraban dos mecanizados hasta aprobarse una versión nueva de cada una.
  Contra aceptada: un manual que era por otra cosa (la cerradura embutida de la misma hoja) deja de
  cobrarse; se ve en el alcance y en el precio antes → después, y lo correcto es que la cerradura
  traiga el suyo. Por qué: "la manija lleva mecanizado" es un dato de la manija; con `embutido_izq` y
  la condición se cargaba en cada hoja de cada paquete, y el olvido en uno lo vendía sin mecanizar
  con un precio que parecía normal. Descartado: que entre solo en versiones nuevas (cada versión
  guardaría qué servicios traía cada insumo: el dato repetido otra vez). La baja de un servicio que
  trae un insumo no deja nada incompleto: deja de cobrarse, como el de una regla, que tampoco está en
  la versión del paquete (`bajas.md` → *La baja depende de cómo se usa lo que se da de baja*).
- **Servicios muestra hace cuánto cambió cada monto y mínimo, y administración los aumenta en masa**
  (2026-10-21). *Soldadura $ 1.500 · hace 7 meses*, ordenable; sale del registro de cambios. El
  aumento es en %, por categoría o subcategoría de servicios o marcando servicios, con motivo; antes
  de confirmar se ve cada monto antes → después. Toca montos fijos y mínimos, no el % de los
  porcentuales, que ya sigue al costo. Es el aumento de Compras sobre costos (`BACKLOG.md` →
  Compras). Por qué: Compras pone al día el costo y el % lo acompaña, pero los montos y mínimos
  cargados en marzo seguían igual en octubre sin que la pantalla lo dijera. Descartado: montos en
  US$ (el dólar no sigue a la mano de obra) e indexados (un sistema genérico para un aumento cada
  tanto).

## Servicios por categoría (2026-10-14)

**Un servicio porcentual puede aplicarse por regla, sin cargarlo en cada paquete: general, por
categoría de paquete (Ventanas 30 %) o por categoría de insumo (Vidrios 10 %).** Se carga una vez
y alcanza a todo paquete o insumo de esa categoría, también al insumo suelto. Reemplaza a los
comerciales generales con excepción por paquete: son el caso de una regla general.

**Si una línea cae en dos reglas del mismo servicio, gana la más específica, no se suman:**
subcategoría del insumo › categoría del insumo › excepción del paquete › subcategoría del paquete ›
categoría del paquete › general. Sumar cobraría dos veces el mismo servicio sobre el mismo vidrio de
una ventana. Dos servicios distintos sí se suman (Float suelto: Comercialización 10 % + Manipulación 5 %).

**La regla apunta a una categoría o a una subcategoría, como la habilitación de clientes**
(2026-10-21). Ventanas → Modena 35 %, Ventanas → Herrero 22 %, Vidrios → Laminados 15 %; un paquete
nuevo en Modena nace con el 35 %. Apunta al lugar del árbol, no al nombre: Puertas → Modena no toma la
de Ventanas → Modena (Modena en las dos son dos reglas). Por qué: en paquetes la subcategoría es la
línea de perfiles, y ahí cambia el margen; solo por categoría, cada Modena era una excepción a mano y
la nueva nacía en 30 %. Descartado: regla solo por categoría, más excepciones por paquete.

**La excepción del paquete reemplaza a su categoría y a la general, no a la del insumo** (2026-10-14).
Ventanas 30 %, Vidrios 10 %, "Corrediza económica" bajada a 20 %: su vidrio sigue en 10 %. Por qué:
con la excepción primero, bajar el paquete le subía el vidrio de 10 a 20 % sin que nadie lo pidiera.
No se puede bajar el vidrio solo en un paquete; si aparece el caso, excepción paquete × categoría de
insumo.

- El % va sobre los insumos que alcanza la regla (no sobre servicios). **Por regla no hay mínimo: el
  mínimo es del servicio cargado en un paquete**, al lado de su % propio (2026-10-22). Por qué:
  Comercialización con Ventanas 30 %, Vidrios 10 % y mínimo $ 20.000 cobraba $ 20.000 al Float 4
  suelto de $ 5.000, y en la ventana chica no se sabía cuál de las dos reglas ponía el piso; el piso
  de la ventana chica ya lo da la mano de obra (*Mano de obra 15 %, mín $ 5.000*). Descartado: mínimo
  por regla (otra tabla para un piso que ya existe).
- Los servicios fijos (soldadura × 4) no van por categoría: su cantidad depende del paquete.
- Demo: https://claude.ai/artifact/RK1y3Gs42DoNx4h8v7yfzW (pestaña Servicios y "Lo que recibe por
  categoría" en Paquetes).

**Reglas y excepciones se cargan desde el servicio; el paquete solo muestra lo que recibe**
(2026-10-21). En *Comercialización*: General 30 % · Ventanas → Modena 35 % · Vidrios → Laminados
15 % · excepción Corrediza económica 20 %, todo con `catalogo_servicios_administrar`. En el
paquete, *Lo que recibe por categoría* es de lectura: el técnico ve *Comercialización — por
Ventanas → Modena*, sin el %; administración, con el % y la regla. Antes de guardar se ve el
alcance (*Ventanas → Modena 35 %: 18 paquetes · 2 con excepción no cambian*); como la regla no está
en la versión, rige al instante y no avisa, como un costo de Compras. Por qué: los % de un servicio
en un solo lugar y una sola función. Descartado: la excepción desde el paquete (los % repartidos en
dos pantallas y en `catalogo_paquetes_administrar`).

**El % de los servicios del paquete deja afuera las categorías de insumos que marca
administración** (2026-10-21). En Servicios, con `catalogo_servicios_administrar`, al lado de las
reglas: *Fuera del % de los servicios del paquete: Vidrios · Paneles*. Una categoría marcada
incluye sus subcategorías futuras (*Vidrios → Templados*, creada después, entra sola), como la
habilitación de clientes. En la hoja izq de la Corrediza Modena (perfiles $ 45.000, herrajes
$ 15.000), la mano de obra del 15 % da $ 9.000 con Float 4 ($ 20.000) o con Laminado 3+3
($ 60.000); con el vidrio adentro daba $ 12.000 y $ 18.000. Probar lo dice (*Mano de obra 15 % —
sobre $ 60.000 · Float 4 afuera: Vidrios*). El trabajo con el vidrio va como servicio fijo por m²
(*Colocación de vidrio* × `superficie_pano_izq`) y lo comercial por su regla (Vidrios 10 %). Como
una regla, antes de guardar se ve el alcance (*Motores fuera del %: 6 paquetes*), rige al instante
y no avisa. Es general: el sistema no sabe qué es un vidrio (la *Persiana con motor* marca
*Motores*: $ 22.500 de mano de obra por el mismo trabajo). Por qué: sin paño, el vidrio es un
material más del grupo y el % lo incluía; marcado una vez, un vidrio nuevo queda bien sin que
nadie haga nada. Descartado: casilla por material en cada paquete (240 casillas en 40 paquetes, y
el olvido cobra de más sin que se note) y marca por insumo (se olvida en el próximo vidrio). Si un
servicio necesita incluir una categoría marcada, la marca pasa a ser por servicio; hoy no hay
caso.
