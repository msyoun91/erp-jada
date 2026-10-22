# Catálogo — lo que elige el vendedor

Medidas, opciones y grupos opcionales que el técnico declara en el paquete; cómo entran el herraje, el
vidrio y el DVH. Lo que pasa con lo elegido cuando el catálogo deja de ofrecerlo, en `bajas.md`; el
color, en `colores.md`.

## Medidas, opciones y defaults

- **Lo que carga el vendedor lo define el paquete** (2026-10-14), no es un juego fijo de ancho y alto:
  el técnico declara cada variable del vendedor. Puede ser una **medida** (número, con su mínimo y
  máximo) o una **opción** entre insumos (manija o embutida): el técnico marca un material del
  paquete y le carga las alternativas; el vendedor elige y el material cambia por el elegido. **Cada
  alternativa usa la fórmula del material o trae la suya** (una manija de dos puntos de fijación lleva
  otros tornillos).
- **Toda medida del vendedor lleva mínimo y máximo, y fuera de rango frena** (2026-10-22). Principal o
  secundaria, de cualquier unidad; se cargan como las casillas (`motor.md` → *El valor de la casilla
  se carga en la unidad en que se piensa*) y sin ellos no se manda a aprobar. Fuera de rango la línea
  queda sin precio con el error típico a la vista (*ancho entre 600 y 3000 mm — cargaste 150: ¿en
  cm?*). Las restricciones quedan para avisos y combinaciones (ancho × alto); un "no aguanta más de
  2400" es el máximo del ancho (⚠ choque 3, `pendiente.md`). Por qué: 150 × 110 en cm en una corrediza
  sin restricciones da vidrio positivo y cotizaba una ventana de 15 cm; 15000 cotizaba millones, y el
  cliente empresa no lo nota. Descartado: el rango como restricción optativa (lo que hoy nadie carga).
- **Una medida del vendedor puede traer un valor por defecto por fórmula** (2026-10-14), para hojas
  asimétricas: `ancho_hoja_izq` propone `ancho / 2 + 25 - desc_herraje_izq` y el vendedor la pisa
  solo si hace falta; `ancho_hoja_der` es calculada (`ancho - ancho_hoja_izq + 50 - desc_herraje_izq -
  desc_herraje_der`). Si la pisó, se respeta aunque cambie `ancho`; si no, se recalcula. **La pisada
  muestra el automático al lado y vuelve con un botón o borrando el campo** (`900 · automático 925 ↺`),
  y el plegado de la línea la nombra (*hoja izq: 900, pisada*): pisada en 900 sobre 1500, al pasar a
  1800 salía asimétrica al revés y volver pedía calcular 925 a mano. Descartado: soltarla sola al
  cambiar `ancho` (pierde la pisada a propósito) y un aviso (no hay nada mal). Las piezas y el vidrio
  se cargan por hoja (`motor.md` → *Un grupo por hoja*). Descartado: un paquete "asimétrico" aparte —
  repite todos los materiales para el 10% de los casos.
- **Cada medida, opción o grupo opcional es principal o secundaria** (2026-10-14). El vendedor ve las
  principales; las secundarias quedan en "Más opciones", que plegado ya muestra qué entra (*herraje
  izq: Manija · mosquitero: no*). Una medida secundaria sin default no se manda a aprobar, como una
  fórmula mal escrita (una opción siempre tiene la primera alternativa).
  Si una restricción avisa sobre una secundaria, el aviso se ve y "Más opciones" se abre solo. Por
  qué: el vendedor cotiza lo común sin recorrer cada herraje y abre el resto cuando el cliente lo
  pide. Descartado: que sea principal según una condición — más lógica para lo que ya resuelve el
  plegado.
- **Una medida secundaria lleva default; una principal, no** (2026-10-14; título del 2026-10-22: el
  orden de las alternativas cuenta como cambio, `versiones.md`).
  Opción: el técnico marca la alternativa por defecto; si su condición no se cumple, la primera que
  se ofrezca (*Lo elegido se guarda*). Medida: el default por fórmula de arriba, o un número fijo.
  Grupo opcional: arranca puesto o sacado (mosquitero: no). **Una principal sin default arranca vacía
  y es obligatoria**: la línea queda sin precio con *Falta alto*; una secundaria sin default toma la
  primera alternativa si es opción, y si es medida no se manda a aprobar. **Una medida principal no
  lleva default, ni fijo ni por fórmula** (2026-10-21): con uno no se manda a aprobar. El sistema no
  sabe cuál es el ancho y cuál el alto, y `alto` principal con 1000 volvía a cotizar el alto
  olvidado; la que necesita default es secundaria (`ancho_hoja_izq` con su automático, en "Más
  opciones"). El color de la ventana es principal y sin default; la opción de vidrio es principal y
  el técnico decide si lleva default (float 4 en una línea que casi siempre va así). Por qué: con 1000
  por defecto, el alto olvidado en una de 6 ventanas se cotizaba 1000 y tenía precio, así que nadie
  lo veía.
- **Lo elegido se guarda; lo que entra se calcula** (2026-10-14). La línea guarda la alternativa
  que eligió el vendedor y entra: lo elegido si se ofrece; si no, el default si se ofrece; si no, la
  primera que se ofrezca. Nada se sobrescribe. Una principal sin default no pasa a la primera: queda
  vacía, como al arrancar (2026-10-21). El vendedor cambia la Puerta rebatible a blanco, PAN-01 no
  viene en blanco y la línea queda sin precio con *PAN-01 no viene en blanco: elegí paño bajo*; con
  la primera, entraba Float 4 mientras él miraba el color. Por qué: vidrio interior Float 5 → sin
  cámara (entra *Sin material*) → vuelta a Cámara 12 perdía el Float 5, y la ficha decía "primera
  válida" en un lado y "default" en otro. Igual que la medida pisada: se respeta lo elegido y se
  muestra lo que entra hoy. Vale cuando lo causa la misma línea; si lo deja de ofrecer el catálogo,
  `bajas.md` → *Lo que el catálogo deja de ofrecer deja la línea sin precio*. Cómo cruza lo guardado
  de una versión a otra: `versiones.md` → *Lo guardado cruza versiones por nombre y por insumo*.

## Opciones

- **Una opción puede poner una variable que usan las fórmulas** (2026-10-14): la manija define
  `desc_manija` (manija 3, tirador 0, embutida 5) y el técnico escribe `ancho_hoja = ancho / 2 + 25 -
  desc_manija`. Así lo que cambia una medida se ve en la fórmula de esa medida, en un solo lugar.
  Descartado: que cada alternativa le "ajuste" la variable (−5 mm al ancho de hoja) — el ajuste
  quedaría escondido en la opción y la fórmula de `ancho_hoja` no diría la verdad.
- **Una opción puede poner varias variables: cada alternativa carga un valor en cada una, y lo que no
  carga vale 0** (2026-10-14). El herraje pone `desc_herraje_izq` (manija 3, embutida 5, cierre 0,
  tirador 5) y `embutido_izq` (embutida 1). Por qué: con una sola variable no había cómo distinguir la
  embutida — `desc_herraje_izq` = 5 también es el tirador (el *Mecanizado de embutido*, que fue el
  caso, hoy lo trae la *Manija embutida*: `servicios.md` → *Un insumo puede traer sus servicios*).
  Descartado: un código por posición con `elegir(herraje_izq; 3; 5; 0; 5; 0)` — reordenar las
  alternativas rompe las fórmulas sin que se note; y una condición sobre qué insumo entró — tipo de
  condición nuevo.
- **El herraje es una opción por hoja, y una alternativa puede llevar condiciones** (2026-10-14).
  Cada hoja lleva el suyo y pueden ser distintos (manija en una, cierre embutido en la otra): el lado
  importa para taller. El vendedor elige el herraje de cada hoja (`herraje_izq`, `herraje_der`, cada
  uno con su `desc_herraje_*`), juntos mientras son hermanas (*Las opciones hermanas arrancan
  juntas*). Cada alternativa se ofrece si se cumplen sus condiciones, en las mismas casillas que los
  materiales condicionales (el *Vidrio interior* solo con cámara: *El DVH son opciones por capa*). Si
  la elegida deja de ofrecerse, entra lo que dice *Lo elegido se guarda*. Descartado: una opción que
  oculta a otra — es un concepto nuevo, y las condiciones y las variables de opción ya existían.
- **Una opción puede tener "Sin material"** (2026-10-21): una alternativa sin insumo (*Sin herraje*)
  que nunca se da de baja. Si se dan de baja todas las alternativas con material, la opción ofrece solo
  esa y el paquete se sigue vendiendo, con aviso al técnico (*Corrediza 2 hojas: herraje hoja izq solo
  ofrece Sin herraje*); sin ella, queda incompleto (Puerta rebatible sin cerradura). Como toda
  alternativa puede llevar condiciones y poner variables, pero **con condición no salva al paquete**:
  si en alguna combinación no queda nada que ofrecer, incompleto (sin Floats, con cámara el *Vidrio
  interior* no tiene qué ofrecer). Por qué: es lo que pasa con un material condicional dado de baja, y
  así un paquete no se vende con unas opciones sí y con otras no. "Alguna combinación" es de opciones
  y color: lo que depende de medidas, en `bajas.md` → *Lo que depende de medidas se resuelve en la
  línea* (2026-10-22). **Una opción que en ese momento solo ofrece *Sin material* no se muestra**, sea
  de vidrio o de herraje: no hay qué elegir (2026-10-21). **Solo si lo dejan condiciones del
  técnico** (2026-10-22): si lo dejan bajas o el color, el plegado lo dice (*herraje hoja izq: sin
  herraje (no hay otro)* · *(no hay en blanco)*) y la línea lleva un aviso; con las dos manijas de
  baja, las corredizas se vendían sin manija y nada lo decía.
- **Una opción puede ofrecer subcategorías enteras, insumos sueltos o las dos cosas** (2026-10-21).
  *Vidrio: todo Vidrios → Float, más Laminado 3+3*: un Float nuevo entra solo en todas las vigentes,
  sin versión ni aprobación; un laminado nuevo no. Lo que entra por subcategoría usa la fórmula y las
  medidas del material (solo un suelto trae las suyas), es par de sí mismo (los pares van entre
  sueltos: Manija ↔ Embutida) y toma las condiciones que lleve la subcategoría. Las hermanas ofrecen
  lo mismo, subcategorías y sueltos; si no, no se manda a aprobar. **Lo que entra solo se ofrece si
  cumple lo que pide el paquete**: la unidad de la fórmula y el espesor, si la opción lo usa; si no,
  no se ofrece y el técnico lo ve en el insumo (*Laminado 4+4: sin espesor · no se ofrece en 12
  paquetes*). Sin costo se ofrece y la línea queda sin precio (`precio.md` → *Sin costo no es $ 0*).
  Lo que entra solo no es cambio de versión, como un color nuevo. Por qué: el vidrio nuevo llegaba a
  los 40 paquetes que ofrecen vidrio sin 40 borradores ni 40 aprobaciones; el filtro, porque un vidrio
  dado de alta por ml o sin espesor entraba a una vigente cuyo control de *mandar a aprobar* ya había
  pasado. Contra aceptada: puede entrar en una línea donde no cabe en el canal, y solo avisa.
  Descartado: solo alternativas sueltas, con "agregar alternativa" masivo en la ventana de
  *Reemplazar material* (versión y aprobación por paquete).
- **Las opciones hermanas arrancan juntas y el vendedor las separa si hace falta** (2026-10-21). El
  técnico marca como hermanas opciones de distintos grupos: *Vidrio hoja izq* y *Vidrio hoja der*,
  lo mismo *Cámara* y *Vidrio interior*, y sirve igual para herrajes. Tienen los mismos insumos como
  alternativas, cada una con las fórmulas de su grupo. Juntas, el vendedor ve un selector (*Vidrio:
  Float 4*) que vale para todas: pone Cámara 12 una vez y queda en las dos hojas. "Distinto por
  hoja" las separa en un selector cada una (fijo laminado y hoja en DVH en una puerta); "usar en
  todas" las vuelve a juntar con la elegida. Plegado: *vidrio: Float 4* juntas, *vidrio: hoja izq
  Laminado 3+3 · hoja der Float 4* separadas.
  - **Cada alternativa tiene su par en las hermanas; por defecto, ella misma.** El técnico carga
    Manija ↔ Embutida en los herrajes de la corrediza: juntas, el vendedor pone Manija en la hoja
    izq (venga de Sin herraje o de Tirador) y la der pasa sola a Embutida; Tirador queda en las dos.
    Con "distinto por hoja" cada una es independiente (Manija en las dos). El par es de ida y vuelta
    (Embutida en cualquier hoja pone Manija en la otra) y es del paquete, en la versión, no del
    insumo: otra línea puede no tener pares. El vidrio es el mismo mecanismo con cada par igual a sí
    mismo.
  - **Los pares van solo entre dos hermanas** (2026-10-22). Con tres o más, cada alternativa es par de
    sí misma: juntas van todas iguales y lo distinto va con "distinto por hoja"; un par entre tres o
    más no se manda a aprobar (*los pares van entre dos hermanas: herraje (3 hojas)*). Por qué: en la
    Corrediza 3 hojas, Manija en la izq podía poner Embutida en las otras dos o alternar, y Embutida
    en la central no tenía "la otra". Descartado: el par a todas las demás, alternado por orden
    (adivinan cómo se arma la línea) y una tabla por hermana (mecanismo nuevo sin caso).
  - **Los defaults son par uno del otro** (*Embutida* a la izq, *Manija* a la der); si no, o si las
    alternativas difieren, no se manda a aprobar.
  - **Si el par no se ofrece en la hermana** (lo saca una condición o el color), entra
    lo que dice *Lo elegido se guarda*. **Y se ve** (2026-10-22): el plegado las separa con el motivo
    (*vidrio: hoja izq Laminado 5+5 · hoja der Float 4 (Laminado 5+5 no va en esta hoja)*) y la línea
    lleva un aviso; el selector sigue junto y lo elegido no cambia. Por qué: con la der en 950 y el
    laminado hasta 900, el plegado decía *vidrio: Laminado 5+5* y una hoja iba con float común.
    Descartado: la línea sin precio hasta separarlas (el sistema sabe armarla).

  Por qué: como antes con los paños, todas arrancan iguales y se cambia la que difiere; con un
  selector por hoja y un botón para copiar, olvidar el botón cotizaba una hoja en DVH y otra simple,
  más barata, sin que nada lo frene. Descartado: una opción para varios materiales (la corrediza no
  podía tener hojas distintas), la derecha "como la izquierda" (una hoja manda sobre la otra) y el
  botón solo. Al duplicar un grupo, sus opciones entran como hermanas de las originales (`motor.md` →
  *"Duplicar grupo" pide qué reemplazar*).
- **El cierre central no tiene decisiones propias: lo arma el técnico con lo que ya existe**
  (2026-10-21). Si una línea lo lleva, es un material condicional y alternativas con condición, como
  cualquier otra cosa; Tirador y Sin herraje son alternativas comunes del herraje. Por qué: no pide
  nada que el motor no tenga, y la opción `cierre` (0/1/2) y dónde va el kit decían cómo se carga un
  producto, no reglas del módulo.

## Vidrio

- **El vidrio es un material de la hoja con una opción, como el herraje; el paño sale** (2026-10-21). El
  técnico escribe las medidas del paño como calculadas, cada una con su unidad: `ancho_pano_izq =
  ancho_hoja_izq − 62` (ml), `alto_pano_izq = alto − 98` (ml), `superficie_pano_izq =
  ancho_pano_izq × alto_pano_izq` (m²), `perimetro_pano_izq = 2 × (ancho_pano_izq + alto_pano_izq)`
  (ml). En `hoja_izq` va *Float 4 mm* × `superficie_pano_izq` (0,714 m² en 1500 × 1100), marcado
  opción *Vidrio* con alternativas Float 4 (default), Float 5 y Laminado 3+3; *Burlete* ×
  `perimetro_pano_izq` y *Colocación de vidrio* × `superficie_pano_izq` entran como cualquier material
  o servicio. El vidrio suma al peso de su hoja: `peso_hoja_izq` trae sus 7,1 kg y la rueda doble lo
  mira directo. Salen el paño como objeto (medidas, espesor máximo, subcategorías elegibles,
  composición por defecto), las variables que ponía el sistema (`superficie_pano_*`,
  `perimetro_pano_*`, `espesor_pano_*`, `peso_pano_*`, y con ellas `peso_total_hoja_*`), la
  composición libre del vendedor y "usar en todos". Por qué: un solo mecanismo para todo lo que elige
  el vendedor, y el técnico decide qué vidrios acepta cada línea. El panel ciego es una alternativa
  más, como el vidrio.
- **El vidrio cobra por una variable de superficie y lleva sus medidas para el despiece**
  (2026-10-21). Lo que se cobra y el peso salen de la variable: *Float 4 mm* ×
  `superficie_pano_izq`. Además, todo material por m² lleva ancho y alto por fórmula (cada uno da
  ml), obligatorios para mandar a aprobar (2026-10-22: todo lo que va por m² en una abertura se corta,
  y sin ellas el despiece decía *Float 4 mm — 0,715 m²*), solo para el despiece: `ancho_pano_izq` y
  `alto_pano_izq`, cada lado redondeado al mm hacia abajo. En 1501 × 1100 el despiece dice *Float 4
  mm — 0,715 m² — 713 × 1002 mm*. Las medidas son del material, para todas sus alternativas, y una
  medida ≤ 0 frena como una pieza. Por qué: producción pide el vidrio cortado con la medida del
  sistema; si la calculara por su cuenta, la fórmula del paño quedaría en dos lugares. Superficie y
  medidas pueden no coincidir si el técnico cambia una sola: el despiece las muestra juntas.
  Descartado, por decisión del usuario: el vidrio por piezas con los m² sacados de las medidas, como
  los ml del perfil. También: solo la variable (el despiece quedaba en m²).
- **El DVH son opciones por capa, con lo que ya existe** (2026-10-21). En `hoja_izq`, tres
  materiales × `superficie_pano_izq` con las mismas medidas: *Vidrio* (Float 4 default, Float 5,
  Laminado 3+3); *Cámara* (*Sin cámara* como *Sin material* y default, Cámara 9, Cámara 12; las
  cámaras ponen `dvh_izq` = 1); *Vidrio interior* (Float 4 y Float 5 con `dvh_izq` = 1, *Sin
  material* con `dvh_izq` = 0). El despiece da cada capa con su medida (*Float 4 mm — 713 × 1002* ·
  *Cámara 12 — 713 × 1002* · *Float 4 mm — 713 × 1002*) y las tres suman al peso de la hoja. La cámara
  sigue por m², con el armado en el precio de la vidriería; si se arma en fábrica, versión nueva con
  separador × `perimetro_pano_izq` y sellador. Un TVH suma otro par cámara + vidrio, en las líneas
  que lo admiten. Sin cámara, el *Vidrio interior* solo ofrece *Sin material* y no se muestra (*Una
  opción puede tener "Sin material"*). Por qué: el DVH se arma con las piezas de los herrajes, sin
  nada propio del vidrio. Descartado: el DVH como un insumo (cada combinación un insumo, con su costo
  en Compras) y una opción de varias capas (el paño por otra puerta).
- **El espesor lo pone el sistema desde el insumo: `espesor_<opción>`** (2026-10-21). Es un dato
  opcional de cualquier insumo, en mm (Float 4 mm: 4 · Cámara 12: 12 · Panel ciego: 24). Por cada
  opción el sistema pone el del insumo que entró (*Sin material* = 0), como pone `peso_<grupo>`, y el
  técnico arma lo que necesita: `espesor_pano_izq = espesor_vidrio_izq + espesor_camara_izq +
  espesor_vidrio_interior_izq` (ml), 20 en un 4+12+4. El burlete entra por condición sobre esa
  variable y el canal es una restricción que avisa (máximo 24: *Laminado 5+5 + Cámara 12 + Float 4:
  26 mm*). El vidrio interior puede mirar `espesor_camara_izq` > 0 en vez de un `dvh_izq`. Si una
  alternativa de una opción cuyo espesor se usa no lo tiene, no se manda a aprobar; mientras alguna
  versión lo use, se corrige pero no se borra, y corregirlo rige al instante, como el peso (en uso,
  espera a administración: `insumos.md` → *Lo que cambia el cálculo de un insumo en uso*). Por qué:
  el espesor es del vidrio, no del paquete; puesto por la alternativa, el 4 del Float 4 se tipeaba en
  cada paquete y un 5 cambiaba el burlete sin que nadie lo viera. Descartado: que lo ponga la
  alternativa, como `desc_herraje_*` (ese sí depende de la línea).
