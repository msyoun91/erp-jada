# Catálogo — colores

El vendedor elige el color de la ventana y cada insumo se cambia solo por su equivalente en ese color;
el que no tiene color, como la felpa, queda igual. **La equivalencia vive en el insumo**, una sola vez
(ART-2301 en negro mate es ART-2301-NM), y la usan todos los paquetes (2026-10-14). Descartado:
mapear en cada paquete como el mockup — el mismo perfil se remapearía en cada plantilla y los mapeos
podrían contradecirse.

- **Los colores son de administración: la lista y las variantes de cada insumo** (2026-10-21).
  - *Lista de colores*: una sola, para la ventana y los herrajes (Natural · Negro mate · Blanco ·
    Bronce), así "como la ventana" encuentra el mismo color. El nombre no se repite aunque cambien
    mayúsculas o acentos (índice único parcial `WHERE activo`): "Negro Mate" no entra al lado de
    "Negro mate". Administración la crea, renombra, da de baja y reactiva; renombrar no rompe nada.
  - *Variante*: código y color de la lista, sin nombre propio (el texto lo pone el color; lo físico es
    del insumo: *La variante de color solo tiene código y color*). La carga administración
    (`catalogo_insumos_administrar`), en uno o en varios insumos a la vez: para la Modena en bronce
    marca los 16 insumos, elige *Bronce*, escribe una vez el sufijo `-BZ` y ve la tabla con el código
    propuesto de cada uno (ART-2410-BZ), corregible fila por fila; se saltean los que ya lo tienen y
    los sin color. Todo o nada, en una función de Postgres: un código que choca se marca en la tabla
    antes de confirmar. El alcance se ve una vez para toda la carga (*Bronce: Corrediza 2 hojas y
    Corrediza 3 hojas se ofrecen en bronce · 15 variantes sin costo*).
  - El paquete no guarda sus colores: los calcula de sus insumos *de la ventana* (*Las alternativas se
    filtran por color*). Cargar la variante es decidir venderlo, y el alcance de la carga lo muestra
    antes de confirmar; colores excluidos por paquete, recién con un caso real (un perfil compartido
    que pone en bronce una línea que no se vende así).
  - Vale al instante, porque el insumo no se versiona: si era el único insumo *de la ventana* sin
    ese color, el paquete pasa a ofrecerlo sin aprobación. Sin costo, la línea sale sin precio y
    Compras lo ve en *sin costo y en uso*. Dar de baja un color en un insumo sigue `bajas.md` → *La
    baja depende de cómo se usa lo que se da de baja*. **En la lista, la baja no toca las variantes:
    el color deja de ofrecerse, y reactivarlo lo vuelve a ofrecer** (2026-10-22). El color va por
    línea entera (si un perfil viene en bronce, viene toda la línea), así que la baja de una variante
    suelta queda para el error de carga. Un color base también se da de baja (*no vendemos más
    natural*): deja de ofrecerse y el insumo sigue siendo de su color; el alcance lo dice (*Natural:
    deja de ofrecerse en 30 paquetes · es base de 140 insumos*). Por qué: darlo de baja en cada
    variante obligaba, al reactivar, a decidir cuáles volvían, y no tenía qué hacer con el base.
  - El técnico no crea colores ni carga variantes: elige la clase y el color base al crear el insumo
    (*El insumo declara su color*). Si el color no está en la lista, se lo pide a administración.
  - El costo de cada color, las existencias por color y la línea suelta en un color apuntan al
    insumo o a su variante; el proveedor, al insumo.

  Por qué: en qué colores se vende cada cosa lo decide administración, y el técnico los cargaba por
  pedido suyo hecho por fuera del sistema; con todo en administración no hace falta aviso. La lista
  evita que un "Negro Mate" de más saque el negro mate de un paquete sin que nadie se entere.
  Descartado: que el técnico cargue las variantes con aviso a administración (el primer planteo).
- **El insumo declara su color: sin color, de la ventana o de herrajes** (2026-10-14). *Sin color*
  (felpa, tornillos, vidrio) no cambia. *De la ventana* (perfiles, tapas a la vista) va en el color de
  la ventana y sin el equivalente ese color no se ofrece (*ART-2410 sin negro mate*). *De herrajes*
  (manijas, cierres) sigue al color de herrajes de la línea; si no lo tiene, va en su color base y no
  bloquea. Sin default: el técnico la elige al crear el insumo (antes salía del tipo, descartado en
  la v2). **De la ventana o de herrajes, lleva su color base de la lista, obligatorio** (2026-10-21):
  el Marco corrediza 80 mm (ART-2420) es natural; la manija, plateada. El insumo sale solo en su
  color base hasta que administración le cargue los demás. Por qué: un perfil recién cargado sin
  variantes parecía "sin color" como la felpa y salía natural en una ventana negra; un herraje que
  solo viene plateado, que va en blanco y en negro, sacaba el blanco de toda la corrediza; y sin color
  base el código no decía de qué color es (como el peso es dato del insumo), el paquete que lo usa no
  se ofrecía en ningún color y el técnico no podía ni probarlo. Descartado: deducirlo solo del tipo —
  "otro" mezcla manijas y tornillos; y reglas de color por clase de material (fijo, alternativa,
  condicional) — sacados los herrajes, la regla estricta ya no bloquea de más.
- **Clase de color y color base quedan fijos como la unidad** (2026-10-22): desde que el insumo tiene
  variantes, está en una versión (borradores incluidos) o se vende suelto; antes, libres. El campo
  dice por qué (*Marco 80: 3 variantes · en 12 paquetes*) y la salida es insumo nuevo y baja con
  reemplazo; Compras y Stock suman su condición al construirse. Se editan solo en Insumos: el paquete
  no guarda colores. Por qué: el base de natural a negro dejaba dos negros (base y -NM), sacaba el
  natural de 12 paquetes y leía como negro el costo y las existencias del natural; a *sin color*, las
  variantes quedaban colgando y las corredizas ofrecían colores en los que el marco no existe.
- **La variante de color solo tiene código y color; lo físico es del insumo base** (2026-10-14): peso,
  unidad, presentación, desperdicio, categoría y su clase de color no se cargan en la variante. El
  $/kg del negro se multiplica por el kg/ml del natural. Por qué: el negro con peso 0 bajaba la hoja
  de 43 a 30 kg y salía con rueda simple, y su costo por kg quedaba sin costo. Descartado: desperdicio
  por variante — la barra que se corta es la misma. El nombre lo pone el color de la lista y el costo
  está en Compras.
- **El color de herrajes es una opción secundaria de la línea, por defecto "como la ventana"**
  (2026-10-14): lo normal es negro en ventana negra, pero el cliente lo cambia. Uno por línea, no por
  herraje. El plegado dice lo que no se pudo (*herrajes: negro · manija: plateado (no hay en
  negro)*). La opción del vendedor elige el modelo (manija, embutida, tirador); el color sale de acá.
- **Las alternativas se filtran por color** (2026-10-21). **Un color sale del paquete solo si** le
  falta a un material fijo o condicional *de la ventana*, o si una opción queda sin nada que ofrecer
  en ese color (sin *Sin material*), como en "con condición no salva al paquete" (`opciones.md` →
  *Una opción puede tener "Sin material"*). Si al perfil hoja le falta el blanco, la ventana no se
  ofrece en blanco: el técnico ve qué falta y el vendedor no ve ese color hasta que se cargue el
  equivalente (2026-10-14). Los sin color y los de herrajes no cuentan. En una alternativa, el color
  que le falta solo la saca a ella: en la Puerta rebatible, *Paño bajo* ofrece todo Paneles → Ciegos
  más Float 4; en blanco, PAN-01 (sin blanco) no se ofrece y PAN-02 y Float 4 sí. Si el default no
  viene en ese color, entra la primera que se ofrezca (`opciones.md` → *Lo elegido se guarda*). Vale
  para toda alternativa *de la ventana*: con la Hoja 42 reforzada sin blanco, en blanco se ofrece solo
  la Hoja 40. Por qué: una ventana blanca con una hoja natural no se vende; y con la regla del 14/10
  una alternativa sin el color sacaba ese color del paquete, y con subcategorías enteras un panel
  nuevo sin blanco se lo sacaba a todas las puertas sin que nadie lo notara. Descartado: dejar el
  insumo en natural con aviso; frenar el presupuesto, que lleva el problema al vendedor; y que el
  default cuente como material fijo (lo hacía la composición por defecto del paño).
