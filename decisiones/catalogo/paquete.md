# Catálogo — El paquete

## Qué es un paquete (2026-10-27)

**Todo lo que se fabrica es un paquete: un conjunto de piezas armadas. Cada pieza armada es un conjunto
de materiales, y cada material es un insumo o un servicio fijo con las fórmulas de cuánto lleva según
las variables del paquete (*Editor de paquete*).** Los nombres son los que usa la empresa.

```
Paquete: Ventana corrediza 2 hojas — variables: ancho, alto
├── Pieza armada: Marco × 1
│   ├── Perfil marco 20x40: medida ancho − 2, cantidad 2
│   ├── Perfil marco 20x40: medida alto − 2, cantidad 2
│   ├── Escuadra: cantidad 4
│   └── Soldado: cantidad 4
├── Pieza armada: Hoja × 2
│   └── …
└── Pieza armada: Colocación × 1
    └── Instalación: cantidad 1
```

- **Un material siempre está en una pieza armada.** Lo que es de todo el paquete va en una pieza
  armada propia (Colocación): con dos lugares posibles, cada pantalla y cada cálculo contemplaría los
  dos. Ancho y alto son variables por sí solas, así que cualquier fórmula calcula con ellas.
- **La fórmula es el despiece: lo que se corta, sin merma (2026-10-29).** Producción corta con ella
  (*Personas*): con un 10 % de merma en el perfil marco, la lista de corte diría 5.931 mm en vez de
  5.392. La merma la pone Administración en el precio, como ella decida: dentro del costo o como
  servicio en % sobre una categoría. El catálogo ya permite las dos, sin nada propio para la merma.
- **No se reutilizan piezas armadas entre paquetes: hay un paquete por combinación, y una compuesta es una
  sola ventana (2026-11-02).** Una obra real pidió 8: paño fijo, banderola, oscilobatiente, fijo + banderola,
  fijo + oscilobatiente, fijo + 2 oscilobatientes, corrediza y puerta. Las combinaciones son más o menos
  siempre las mismas. La hoja oscilobatiente queda en 3 paquetes: corregirla es una versión de cada uno, y se
  puede olvidar una. Costo aceptado, porque los paquetes cambian poco y duplicar ahorra la primera carga. Se
  descartó un solo paquete "Ventana de paños": el vendedor tenía que cargar "alto del fijo: 0", y un error
  afectaba a todas las combinaciones. También compartir piezas entre paquetes: un concepto nuevo, con su
  propia aprobación, para un problema que todavía no se vio (`BACKLOG.md`).
- **Un paquete se puede duplicar: `catalogo_armar` crea uno nuevo, con otro nombre y un borrador copiado de
  la versión que se está mirando (2026-11-02).** La Ventana de 3 hojas sale de la de 2 sin recargar sus 40
  fórmulas. Se copia todo lo de la versión; los costos son del insumo. No queda vínculo entre los dos, y el
  borrador se revisa como cualquier otro. Copiar una pieza suelta se ve al diseñar el editor: sus variables
  chocarían con los nombres únicos.
- **Cada paquete tiene una sola categoría, según qué es el producto** (ej: Ventanas corredizas →
  Ventana corrediza 2 hojas, Ventana corrediza 3 hojas; Paños fijos → sus tipos). Las define Técnica y
  le pone una a cada paquete al armarlo.
  El vendedor, en Presupuestos, elige primero la categoría y después el paquete. Sin subcategoría
  (Ventanas → Corrediza → 2 hojas), descartada el 2026-10-29 para paquetes e insumos.
- **El nombre y la categoría son de la versión: cambiarlos es sacar una versión nueva, que aprueba el
  gerente (2026-10-29).** Lo que ve el vendedor lo aprobó el gerente, y un presupuesto viejo muestra el
  nombre de su versión. Cuando exista el % por categoría (`BACKLOG.md`), mover un paquete de categoría
  ya pasa por el gerente. Se descartó que sean del paquete y se cambien sin aprobación: los
  presupuestos viejos mostraban el nombre nuevo, y la categoría movería el precio sin que el gerente
  lo viera.
- **El nombre de un paquete no se repite en todo el catálogo: dos paquetes no pueden tener publicada una
  versión con el mismo nombre, sin distinguir mayúsculas, aunque uno esté de baja. Si está tomado, la base
  no deja enviar la versión (2026-11-02).** Martín le pone "Ventana corrediza 2 hojas" a una versión de la
  Ventana reforzada, el gerente la aprueba porque el despiece está bien, y el vendedor ve dos iguales con
  precios distintos. Al enviar se compara con lo publicado y lo que está en revisión en otros paquetes; un
  borrador no cuenta y una versión obsoleta no retiene su nombre. Un paquete de baja sí lo retiene, a
  diferencia del insumo: suele volver cuando se reemplaza una rueda, y otro con su nombre daría dos iguales
  al reactivarlo. Unique parcial sobre las versiones publicadas, sin control aparte al reactivar. Costo
  aceptado: para reutilizar el nombre de un paquete dado de baja a propósito, antes se le saca una versión
  con otro. Se descartó que no se repita solo dentro de cada categoría: dos "2 hojas" no se distinguían en
  un aviso, en "Por revisar" ni en un presupuesto.
- **Hoy no se vende nada suelto.** El catálogo de un proveedor alimenta insumos para usar dentro de
  los paquetes. Para cuando revendan perfiles ya hay camino decidido (`BACKLOG.md`).
- **Lo que se fabrica siempre es un paquete; lo que no se fabrica no es del catálogo (2026-11-02).** Una
  ventana de 3.100 con un máximo de 3.000 se hace duplicando el paquete con otro máximo ("Ventana corrediza
  especial"): el gerente la aprueba y Producción recibe su despiece. Un flete es un renglón libre de
  Presupuestos (`BACKLOG.md`). Costos aceptados: el vendedor espera a Técnica y al gerente, y la especial
  queda a la vista de todos los vendedores hasta que Técnica la da de baja. Se descartó usar el renglón
  libre para la ventana: nadie revisaría las fórmulas y a Producción le llegaría sin despiece.

## Editor de paquete (2026-10-30)

**La pieza armada es un conjunto de materiales calculados mediante fórmulas aritméticas.**

**Variable: un valor que no está ligado a ningún material. Puede estar dentro de una pieza armada o por
sí sola, fuera de toda pieza armada.** Ancho y alto son variables por sí solas.

**De cada variable se elige si la ingresa el vendedor o no, y una variable puede llevar una fórmula
aritmética.**

**Una variable que ingresa el vendedor también puede ser una lista de valores con nombre (2026-11-02).**
La `mano` de una puerta: Izquierda o Derecha. Sin predeterminado es obligatoria, como cualquiera, y sale
en el despiece con las demás variables. No entra en las cuentas: no cambia el precio ni se usa en
fórmulas. Se descartó un número (1 = izquierda), una convención que el vendedor tenía que conocer; dos
insumos a $0, que ensuciaban la lista y el despiece; y una nota en el presupuesto, que se olvida sin que
nada la frene.

**Los valores de una lista se guardan en la variable, en orden, y no en una tabla aparte (2026-11-02).** Ninguna
fórmula los usa, así que nadie necesita apuntarles: un caso o un presupuesto guarda "Izquierda", que no cambia en una
versión enviada. Archivos: `sql/160`.

**Una variable que ingresa el vendedor puede tener un predeterminado con fórmula; sin predeterminado
(ancho, alto) es obligatoria.** En una corrediza asimétrica, `ancho_hoja_1` se predetermina en
`(ancho + solape) / 2`: con ancho 2.000 aparece 1.025 y, si el vendedor no lo toca, sale simétrica. Lo
que escribe queda aunque cambie el ancho; si lo borra, vuelve al predeterminado. El presupuesto guarda
solo lo escrito, así un predeterminado sin tocar se recalcula con el ancho nuevo. Se descartó "0 =
hojas iguales" con un "si": era una convención que el vendedor tenía que conocer.

**A una variable se le pueden configurar condiciones (if) con comparadores, cada una con un mensaje de
alerta o un bloqueo. Con un bloqueo no se puede hacer uso del paquete.** Ej: ancho > 1000 → mensaje de
alerta o bloqueo. **Después del comparador va una operación aritmética** (ej: alto > ancho × 2).

**Una variable numérica que ingresa el vendedor lleva mínimo y máximo, números fijos; sin ellos, la base no
deja enviar la versión (2026-11-02).** Sin condición sobre `ancho`, un 150 por 1.500 daba todas las medidas
positivas y un precio mucho más bajo, sin ningún aviso. Fuera de rango bloquea siempre, con un mensaje
estándar ("El ancho va de 300 a 3.000 mm"), también si el valor sale del predeterminado. Lo que depende de
otra variable sigue en una condición (`alto > ancho × 2`). No lo llevan las listas de valores ni las variables
que no carga el vendedor. Se descartó hacer obligatorias las condiciones: en una condición libre, la base no
puede saber si hay un tope por arriba y otro por abajo.

**Una variable numérica que ingresa el vendedor dice si es una medida (mm) o una cantidad (u); por defecto,
medida. Solo cambia lo que lee el vendedor: la etiqueta del campo y el mensaje de rango (2026-11-02).**
"Cantidad de travesaños", de 0 a 3, salía con "(mm)" y "va de 0 a 3 mm". Las fórmulas no cambian: toman el
número tal cual.

**En toda operación aritmética se puede usar una variable u otro material del paquete: se toma su
resultado, no su fórmula, y se calcula a partir de él.**

**Un material vale el total de sus filas: dentro de su misma pieza, lo de una pieza; desde otra pieza,
lo de todo el paquete (2026-11-02).** Con Hoja × 2 y 3.950 mm de Perfil hoja en cada una, `Felpa = Perfil
hoja` dentro de la Hoja toma 3.950 y el despiece da 3.950 × 2 = 7.900 mm; tomando 7.900, el × 2 daba
15.800. `Sellador = Perfil hoja` en Colocación toma 7.900. La medida de un solo corte sale de una variable
(`ancho_hoja`, 775). Un material múltiple vale lo de la opción elegida. La referencia da mm, como toda
fórmula: un vidrio de 1,68 m2 da 1.680.000 mm².

**Lo que hay en una versión tiene un nombre, y es lo que usan las fórmulas y lee el vendedor (2026-11-02).**
- **El material único se llama como su insumo o servicio fijo; el múltiple lleva el nombre que le pone
  Técnica,** que es lo que el vendedor lee al elegir: `Vidrio`, con las opciones Float 4mm y Laminado 3+3.
  No hay dos múltiples con el mismo nombre en una pieza.
- **El mismo nombre en varias piezas sigue la regla de arriba.** En una corrediza asimétrica, dentro de
  Hoja 1 `[Vidrio]` es el de Hoja 1; desde Colocación, la suma de los dos. Para usar uno solo se les ponen
  nombres distintos ("Vidrio hoja 1"), sin sintaxis nueva.
- **El nombre de una variable o de una pieza es único en la versión, y una variable no se llama como un
  material.** Dos `ancho_hoja` no tendrían valor: una variable no se suma como un material.
- **La variable tiene un solo nombre, y es el que ve el vendedor.** Técnica escribe "Ancho de hoja 1" y
  la fórmula queda `[Ancho de hoja 1]`; los `ancho_hoja_1` de esta carpeta lo abrevian. Se descartó un
  código con una etiqueta aparte: acortaba las fórmulas, pero sumaba un campo y dos nombres que podían
  quedar distintos.
- **Piezas, variables, materiales y opciones salen en el orden en que Técnica los deja en el editor.**

**Toda fórmula (de un material, de una opción o de una variable) puede llevar "si … entonces … si no
…", con los mismos comparadores de las condiciones, y redondear hacia arriba.** Una puerta con 3
bisagras hasta 2.100 de alto y 4 si pasa: `si alto > 2100 entonces 4 si no 3`, o una bisagra cada
700 mm: `redondear_arriba(alto / 700)`. Los "si" se encadenan para más escalones.

**Las condiciones y los "si" también llevan `y` y `o`; para mezclarlos, la base pide paréntesis
(2026-11-02).** `si ancho > 2000 o alto > 2400 entonces Laminado si no Float`, y un bloqueo con `ancho > 2000
y alto > 2400`, que con un solo comparador no se podía escribir. Sin paréntesis, `a y b o c` podía dar otra
cosa que la que Técnica quiso. `y` y `o` son palabras reservadas, como `si` y `pi`: una variable que se llame
así va entre corchetes. Sin `máximo` ni `mínimo`: se escriben con un "si" y no hay un caso que los pida.

**El "si no" es obligatorio: en toda fórmula con "si", y cuando el sistema define un material múltiple,
donde termina en un insumo o en "ninguno". Sin él, la base no deja enviar la versión (2026-11-02).** Con
`si peso_hoja > 40 entonces Rueda 80kg`, una hoja de 16 kg quedaba sin rueda y el precio salía más barato
sin que nadie lo notara. Si ninguna opción sirve para un caso, va una condición de bloqueo en el material
(`peso_hoja > 80`). Un material que puede dar "ninguno" no lo usa ninguna otra fórmula, como el que
permite "sin elección".

**Las fórmulas también llevan `pi` y `arcoseno`, para los arcos: se hacen de medio punto y rebajados
(2026-10-30).** Un arco rebajado de ancho 1.200 y flecha 200: `radio = flecha / 2 + ancho × ancho /
(8 × flecha)` da 1.000, el perfil curvo `2 × radio × arcoseno(ancho / (2 × radio))` da 1.287 mm, y el
vidrio del arco `radio × radio × arcoseno(ancho / (2 × radio)) − ancho / 2 × (radio − flecha)` da
163.501 mm². El medio punto es el caso flecha = ancho / 2 (arco = `pi × radio`). Sin raíz: el arco
rebajado no la necesita.

**Cada material lleva su medida, con fórmula, y la cantidad de piezas iguales. Si no necesita medida,
lleva solo la cantidad.** Las ruedas: cantidad 4, sin fórmula. El perfil del ancho de hoja: medida
`ancho_hoja` y cantidad 4.

**Un insumo en m2 lleva dos fórmulas, ancho y alto, en vez de una de área: el sistema las multiplica y
pasa el resultado a m2. La base no deja enviar la versión sin alguna de las dos (2026-11-02).** El
vidrio de la hoja lleva `ancho_hoja − 48` y `alto − 48`, y la fila dice 727 × 1.152 mm × 2 = 1,68 m2;
con el área sola decía 0,84 m2 y el vidriero no podía cortar. El costo y el peso salen del área. Una
opción con fórmula propia lleva las dos.
- **Una forma que no es rectángulo suma una fórmula de área propia.** El vidrio del arco: 1.200 × 200,
  el rectángulo del que sale, con 0,16 m2 (163.501 mm²). Sin ella se calcula el rectángulo entero, 0,24 m2.
- **Un servicio fijo en m2 lleva solo el área:** no hay nada que cortar.
- Se descartó un campo de medida de corte junto al área: podían cobrar 1,67 m2 y mandar a cortar otra
  medida. Tampoco alcanzaban las variables `ancho_vidrio` y `alto_vidrio`: la fila seguía diciendo 0,84 m2.

**La medida vacía es solo para insumos y servicios fijos en u; en mm o m2 la base no deja enviar la
versión.** Un perfil o un vidrio sin medida daban 0 mm o 0 m2, y el precio salía sin ese material sin
que nadie lo notara.

**En un insumo en u, la medida es opcional y solo le dice a Producción cómo cortar: lo que se cobra, y lo
que vale en otra fórmula, es la cantidad (2026-11-02).** Una varilla roscada en u, 300 mm × 2, son 2 u y
no 600. Si se paga lo que se usa y no la varilla entera, Técnica la carga en mm: 600 mm.

**El servicio fijo también es material: un material es un insumo o un servicio fijo.**

**Un material es único o múltiple.**
- **Único:** se selecciona un solo insumo o servicio fijo.
- **Múltiple:** cualquiera de los insumos o servicios fijos predeterminados en el paquete puede ocupar su lugar. Cuál lo
  ocupa se da de dos formas: lo elige el vendedor, o lo define el sistema con condicionales. Cuando
  elige el vendedor, se puede permitir "sin elección" y, al mismo tiempo, configurar el predeterminado.

**En un material múltiple, cada opción puede llevar su medida y su cantidad; la que no trae, la hereda
del material, cada una por separado (2026-11-02).** La Rueda simple hereda la cantidad 4 y la tándem trae 2,
que también puede ser una fórmula.

**Las opciones de un material van todas en la misma unidad; la primera la fija (2026-11-04).** Un mosquitero
de tela (m2) y uno enrollable (u) son dos piezas opcionales, no dos opciones. Mezclarlas dejaba cargar por
error un perfil entre los vidrios, y obligaba a medidas distintas en el mismo panel. Una pareja compara dos
materiales, así que el Vidrio en m2 sigue pudiendo tener un Contravidrio en mm. La unidad se cambia cuando
queda una sola opción. Archivos: `sql/169_catalogo_opciones_misma_unidad.sql`,
`components/editor/InsumoSelect.tsx`.

**Un material múltiple puede seguir la elección de otro: sincronizado o en combo.**
- **Sincronizado:** con las mismas opciones. El vendedor elige en uno y los sincronizados quedan con
  la misma. Ej: en una corrediza asimétrica, el Vidrio de Hoja 2 sincronizado con el de Hoja 1.
- **Combo:** con opciones distintas, emparejadas. Elegir una en uno marca su pareja en el otro. Ej:
  Contravidrio en combo con Vidrio: Float 4mm → Contravidrio 4mm, Laminado 3+3 → Contravidrio 6mm.

En la base son un solo mecanismo: el sincronizado es un combo donde cada opción tiene por pareja el mismo insumo.

**~~Lo que sigue a otro no se le muestra al vendedor: elige una vez~~: la pareja es una sugerencia, y el vendedor puede
cambiar cualquier material que sigue a otro (2026-11-04).** La idea es facilitar la carga sin impedir otras combinaciones: elige
Laminado 3+3, el Contravidrio se completa en 6mm, y quien no toca nada elige una sola vez. Costo aceptado: se puede armar algo
que no se fabrica, con un precio que parece correcto, y ninguna condición lo frena porque no mira otro material. Se descartó
una marca por material para dejar parejas fijas: el usuario quiere que se puedan cambiar todas.
- **Lo cambiado a mano queda aunque cambie el que elige; si se borra, vuelve a la pareja.** Con el Contravidrio en 6mm a mano,
  pasar el Vidrio a DVH (pareja 8mm) lo deja en 6mm. Igual que `ancho_hoja_1`, y el presupuesto guarda solo lo elegido a mano.
- **El vendedor ve las parejas y las opciones sueltas que sume Técnica.** Un Contravidrio 10mm no es pareja de nadie: se
  elige de la lista y nunca se completa solo. "Ninguna" se puede elegir si es la pareja de alguna opción.
- **Técnica decide con "secundario" si va plegado en "Más opciones".** Es la marca de los que elige el vendedor, y ahora vale
  también acá. No se puede plegar si el que elige no tiene predeterminada: no habría nada propuesto. Si lo define el sistema, sí se
  puede: su regla siempre propone.
- **Si el insumo elegido a mano es el de la pareja de lo elegido, vale esa fila, con sus fórmulas (2026-11-04).** Con Laminado → Contravidrio
  6mm × 3 y Templado → Contravidrio 6mm × 5, elegir 6mm a mano con el Templado da × 5, igual que no tocarlo. Si no es esa pareja, vale la
  primera fila de ese insumo. Por eso una suelta no repite una pareja: frena el envío (`versiones.md` → *Qué frena el envío*).
- **Elegida a mano, una opción sin su insumo no se ofrece, como cualquiera (2026-11-04).** Si se da de baja el Contravidrio 10mm suelto, el
  paquete sigue a la venta y solo quien lo eligió ve "Ya no se ofrece". Sigue valiendo que una opción sale si le falta su pareja, aunque se
  pueda elegir otra a mano: sin la pareja no hay qué completar, y el aviso de la baja lista la opción y la pareja. Archivos: `sql/167`.

**Un material sigue a uno que elige, no a otro que sigue; lo frena el envío (2026-11-02).** Si el Contravidrio y el
Burlete dependen del Vidrio, los dos apuntan al Vidrio. Sin cadenas no hay círculos que revisar ni un orden que resolver
al calcular. Archivos: `sql/160`.

**Cada opción del que elige tiene pareja en el que la sigue: un insumo, o "ninguna" si Técnica la elige.
Vacía, la base no deja enviar la versión (2026-11-02).** Si suman el DVH al Vidrio y se olvidan de la
pareja en el Contravidrio, el precio salía sin contravidrio sin que nadie lo note. Con "ninguna", el DVH
no da fila de contravidrio ni se cobra. Como el Contravidrio puede no
estar, ninguna fórmula lo usa (*Una fórmula solo puede usar lo que seguro existe*): esa medida sale de
una variable.

**Una variable que no carga el vendedor puede definirse según un material que se elige: lleva un valor por cada
opción, número o fórmula, en vez de su fórmula (2026-11-04).** `descuento_hoja`, según Herraje: Corredera simple 20,
Corredera oculta 35, Elevable 50. Elegir el herraje cambia `ancho_hoja = (ancho − descuento_hoja) / 2`, y con ella el
perfil, el vidrio y el precio; el vendedor no toca nada más y las demás fórmulas la usan como a cualquier variable. Se
descartó encadenar `si Herraje = [Corredera oculta] entonces 35 si no …`: una opción nueva caía en el último "si no" y daba
una medida mal sin que nadie lo notara, y cada variable repetía la cadena.
- **Una opción sin valor no deja enviar la versión,** como una pareja vacía. Sacar una opción saca sus valores.
- **Solo se calcula el valor de la opción elegida.** Para lo circular y lo que puede faltar cuentan todos: no se conoce la
  elección al revisar.
- **También vale un material que sigue a otro, con un valor por cada opción suya, sueltas incluidas:** el vendedor puede
  cambiarlo, así que no es la misma elección que la de aquel. La regla de un material que define el sistema no puede usar una
  variable que dependa de él: es circular.
- **Un material que permite "sin elección", puede dar "ninguno" o tiene la pareja "ninguna" pide un valor para ese caso, número o
  fórmula; sin él no se envía (2026-11-04).** `descuento_hoja`, según Herraje: si no hay elección, 0. Obligatorio para que nadie lo
  olvide y dé 0 sin que se note, el mismo problema del "si no". Va en `formula`, que en estas variables estaba vacía: la copia de
  versiones y la revisión de lo circular y lo que falta ya la cubren. Archivos: `sql/170_catalogo_segun_sin_eleccion.sql`.
- **No vale un material de una pieza que puede faltar para una variable de lo fijo** (*Una fórmula solo puede usar lo que seguro
  existe*). Se apunta al material, no a su nombre: con un Herraje en cada hoja, no hay duda de cuál es.
- **Sacar el material saca las variables según él, y sacar la variable o la opción saca sus valores (2026-11-04).** Sin el material la
  variable no tiene de dónde sacar un valor; una fórmula que la usaba frena el envío. Si Técnica cambia el material de la variable, lo
  cargado para el anterior ya no se mira y el envío pide los valores del nuevo. Archivos: `sql/167`.

**El color es por paquete. En un color se deja de ofrecer lo que no se puede armar en ese color, y el
color solo no se ofrece si el paquete no se puede armar sin eso (2026-11-02).** Un material de color
indistinto, como el tornillo, no afecta. Con la regla anterior, que pedía la variante en todos los
materiales, un marco de Mosquitero opcional solo en blanco impedía vender la ventana en negro.

```
Material                                                Ventana en negro
Marco del Mosquitero opcional, solo blanco              se ofrece, sin el Mosquitero
Manija: Estándar (blanca y negra), Premium (blanca)     se ofrece, solo con la Estándar
Vidrio, color indistinto                                se ofrece
Perfil hoja, material único de pieza fija, solo blanco  no se ofrece en negro
Manija sin ninguna opción en negro                      no se ofrece, salvo que permita "sin elección"
Rueda que elige el sistema, alguna sin negro            no se ofrece: nadie puede elegir otra
```

- **Se calcula, sin guardar nada.** La versión sigue diciendo qué colores ofrece y cuál es el base.
- **Lo ve quien aprueba.** Al marcar negro, Técnica ve "en negro no se ofrece: Mosquitero, Manija
  Premium", y el gerente ve lo mismo al aprobar.
- **Si el vendedor cambia de color después de elegir,** lo que ya no se ofrece se desmarca con un aviso,
  para que el precio no cambie sin que lo note.

**El color es un dato del insumo, no un insumo más: el insumo tiene variantes de color, cada una con
su costo.** "Perfil hoja" es un solo insumo con variantes blanco y negro; el paquete lo usa una vez y el
color se resuelve al calcular. Si el proveedor deja de fabricar el anodizado, se da de baja esa variante
y el paquete sigue a la venta en los demás colores; como insumo aparte, su baja sacaba de la venta todo
paquete que lo usara. Todo insumo tiene al menos una variante: el de color indistinto, una sola.

**La versión dice qué colores ofrece: los elige Técnica entre los posibles y los aprueba el gerente.**
Una variante de color nueva en un insumo no pone a la venta un color que nadie aprobó.

**Las variantes de color se suman y se dan de baja aunque el insumo ya se use: no son de los datos
fijos, se comportan como el costo.**
- Sumar un color a un insumo usado no cambia ninguna versión: cada una dice qué colores ofrece. Para
  vender el color nuevo, versión nueva que lo marque. Si la versión ya ofrece ese color, lo que no se
  armaba en él se ofrece solo cuando la variante tiene costo: sin costo, cuenta como que no está.
- Quitar un color es dar de baja la variante. Los paquetes dejan de ofrecer lo que no se arma sin ella,
  o ese color; si era el único que ofrecían, el paquete sale de la venta, como con la baja de un
  insumo. Avisa al gerente.
- Reactivar la variante devuelve las opciones y los colores que se dejaron de ofrecer, sin versión nueva:
  se calcula con las variantes activas, sin guardar nada aparte. Un paquete que salió de la venta por esa
  baja no vuelve solo: lo reactiva Técnica, como con la baja de un insumo (2026-11-02). Mientras no se pueda
  armar en ninguno de los colores que ofrece, la base no deja reactivarlo y dice qué variante falta.
- Los colores son una lista común (Blanco, Negro, Anodizado), para que el negro del perfil y el del
  accesorio sean el mismo. La define Técnica, y sigue la regla de las categorías (*El insumo*): se edita
  mientras ningún insumo lo use, después su nombre queda fijo, se da de baja solo sin variantes activas y
  el nombre es único entre los activos (2026-11-02). Renombrar "Negro" a "Negro mate" cambiaba lo que ven
  vendedor y cliente sin que nadie lo aprobara.
- **Tener color o ser indistinto queda fijo con la unidad, al enviarse una versión que usa el insumo
  (2026-11-02).** Sumarle Negro a un Tornillo indistinto podía dejar de ofrecer en blanco una ventana. Para
  un Tornillo negro se carga otro insumo, con versión nueva de cada paquete que lo use.
- Una variante nueva sin costo le avisa a Administración, como un insumo nuevo, y la base no deja
  enviar una versión que ofrezca un color con alguna variante sin costo.

**Un herraje de otro color que el paquete es otro insumo, de color indistinto (2026-11-02).** Se vende
pocas veces: una ventana blanca con manija negra lleva "Manija negra" como opción de la Manija. Costo
aceptado: la misma manija queda dos veces, con dos costos que pueden quedar distintos. Se descartó un
segundo color en el paquete: sumaba un dato a la versión, a los casos de prueba y al presupuesto para algo
poco frecuente.

**El color base es el predeterminado del paquete: la versión marca uno de sus colores como base, y el
vendedor ve el paquete con ese color elegido.** Con predeterminado, la elección de color puede ir
secundaria: si casi todo se vende en blanco, queda plegada en "Más opciones". Si el color base deja de
ofrecerse, la elección queda sin predeterminado y pasa a primaria: el vendedor elige entre los demás.

**Cada material lleva también las condiciones de alerta o bloqueo, como la variable.**

**Cada opción de un material múltiple lleva sus propias condiciones, además de las del material, que
valen para todas. Solo se evalúan las de la opción elegida (2026-11-02).** El Float 4mm llega hasta
2 m2 y el Laminado 3+3 hasta 3,5: con un vidrio de 2,06 m2, el Float bloquea y el Laminado da precio.
La opción bloqueada se sigue viendo, para que el vendedor lea por qué. Si era el predeterminado, no se
cambia sola por otra: cambiaría el precio sin que nadie lo note. Lo que sigue a otro también evalúa las
suyas, y el mensaje le aparece al vendedor.

**La pieza armada puede ser opcional, y entonces lleva su predeterminado: no incluida, o incluida si
Técnica la marca (2026-11-02).** El Mosquitero viene sin incluir y el vendedor lo suma; el Burlete viene
incluido y lo saca. Como siempre tiene predeterminado, toda pieza opcional se puede plegar. Una Cortina
incluida trae el Cajón que requiere, y una pieza que no se ofrece, por una baja o por el color, no viene
incluida.

**Una fórmula solo puede usar lo que seguro existe cuando se calcula: la base lo revisa al enviar la
versión y, si no se cumple, no la deja enviar (2026-11-02).** La Cortina con `alto_cajon` y sin el Cajón
no se podía calcular.
- Una pieza fija o una variable suelta no usa nada de una pieza opcional, ni variables ni materiales.
- Una pieza opcional usa lo fijo, lo suyo y lo de la opcional que requiere: la Cortina usa `alto_cajon`
  si requiere el Cajón.
- Nadie usa un material que permite "sin elección". Si varios materiales pueden faltar juntos, van en
  una pieza opcional; uno suelto, con "sin elección".
- No hay referencias circulares: el Perfil no usa la Felpa si la Felpa usa el Perfil.

**Una pieza armada puede requerir otra pieza opcional, pero no a sí misma ni en círculo, y una pieza
fija no requiere ninguna (2026-11-02).** Si la Cortina y el Cajón se requieren entre sí, son una sola
pieza; y una opcional que una fija requiere estaría siempre incluida, así que es fija.

**Una pieza requiere una sola pieza (2026-11-02).** Ningún caso pide dos, y la cadena sigue valiendo: A requiere B,
y B requiere C. Una columna alcanza; si aparece un caso real, se pasa a una tabla. Archivos: `sql/160`.

**Al vender, elegir la Cortina marca también el Cajón, a la vista y con un aviso ("La Cortina lleva
Cajón"), y destildar el Cajón destilda la Cortina. Si el Cajón no se ofrece, por una baja o por el
color, tampoco se ofrece la Cortina (2026-11-02).** Se descartó que bloquee: el vendedor tenía que
adivinar qué le faltaba, y el precio ya incluye los dos.

**La pieza armada lleva su cantidad, con fórmula y 1 por defecto, y lo que tiene adentro es para una
sola pieza (2026-11-02).** Técnica arma una hoja (Perfil hoja 775 mm × 2, vidrio × 1, rueda × 2) y
escribe Hoja × 2. El despiece muestra la cantidad total: 775 mm × 4, sin que Rodrigo multiplique. El peso
y el espesor son de una sola pieza: Hoja × 2 · 16 kg cada una · espesor 6 mm. Juntando las dos hojas
daba 32 kg y 12 mm, y la rueda y "espesor > 24" comparaban contra el doble. Si las hojas miden distinto
son dos piezas, con el vidrio sincronizado. Una rueda que se elige por el peso de la hoja no cuenta para
ese peso: sería circular, y la base lo frena al enviar. Se descartó armar piezas iguales sincronizadas:
cada fórmula se cargaba dos o cuatro veces, y un arreglo en una sola las dejaba distintas.

**Cada pieza armada lleva sus propias variables: el peso y el espesor de la pieza. El peso se calcula
siempre: por default cuenta cada material, y Técnica puede optar por que un material no cuente. El
espesor se calcula solo cuando la pieza armada está marcada para calcularlo, sumando el de sus
materiales. Al revés que en el peso, un material no entra en esa suma salvo que Técnica lo marque
(2026-11-02). La cantidad del material multiplica el espesor; la de la pieza, no.** El peso y el espesor
de cada material salen del insumo: el insumo suma el espesor a sus datos. En una hoja solo importa el
vidrio: contando todo por defecto, el Perfil hoja sin espesor frenaba el envío hasta destildar cada material.

**El servicio fijo nunca cuenta para el peso ni para el espesor, y el editor no muestra esa marca en su
fila (2026-11-02).** El Soldado del Marco no tiene peso que cargar: contándolo por defecto, frenaba el envío
por un dato que no existe. En un material múltiple con opciones de los dos tipos, el servicio elegido no
suma nada, y un insumo elegido cuenta como cualquier otro, con sus datos vacíos frenando el envío. La base
lo resuelve al leer, no apagando la marca al guardar: así el peso de la pieza no espera al servicio y una Instalación
puede depender de `[peso Hoja]`, y un material que pasa de servicio a insumo vuelve a contar (`sql/174`, 2026-11-04).

**En una fórmula, el peso y el espesor se escriben con el nombre de la pieza: `[peso Hoja 1]` y `[espesor
Hoja 1]` (2026-11-02).** El editor los ofrece en la lista y valen lo de una sola pieza; los `peso_hoja` de
esta carpeta lo abrevian. Si la pieza no calcula el espesor, `[espesor Hoja 1]` no existe.

**Lo que toca el vendedor (una variable que ingresa, un material múltiple que elige, una pieza
opcional) Técnica lo marca primario o secundario. El primario aparece siempre al sumar el paquete; el
secundario va plegado en "Más opciones", resuelto con su predeterminado. La base deja marcar secundario
solo lo que tiene predeterminado: lo obligatorio es siempre primario.** Así no se carga al vendedor con
elecciones: en la corrediza carga ancho, alto y vidrio, y el ancho de hoja 1, el mosquitero y la
cortina quedan plegados. Si una alerta o un bloqueo salta por algo secundario, el mensaje se ve igual y
la sección se abre. Qué ve el cliente se decide al fichar `erp-cliente`.

**El paquete comienza vacío, y en ese estado no se puede publicar.** Lo frena la base.
