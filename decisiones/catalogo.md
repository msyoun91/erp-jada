# Decisiones — módulo catálogo

**Estado (2026-10-21): ficha v2 aprobada, sin SQL.** Antes del SQL, *Pendiente* → *Auditoría v2*, de
a un punto. Referencia del motor de paquetes: `C:\dev\Archivos antiguos\spec_plantillas_5.md` (módulo
Plantillas del ERP viejo) y `plan_plantillas.md` — se adapta, no se copia.

## Un solo módulo con tres vistas: Insumos · Servicios · Paquetes (2026-09-29)

**Catálogo es un módulo con tres pestañas, no tres módulos.** La visibilidad por persona se resuelve
por vista (cada pestaña es su submódulo), no por módulo; el técnico trabaja en las tres a la vez (arma
un paquete eligiendo insumos y servicios), y un paquete no existe sin sus insumos. Descartado: Paquetes
como módulo aparte (el ERP viejo tenía Lista de precios + Plantillas + Márgenes) — un layout, una ficha
y un ir y venir de más para la misma persona.

Fuera de Catálogo (`BACKLOG.md`): el **costo** (Compras), las **existencias** (Stock), el **proveedor**
(empresa de Contactos con rol `proveedor` sobre el insumo, `decisiones/contactos.md`) y el **precio
final** (Presupuestos: es donde se cargan las medidas).

## Qué es y qué hace cada vista

### Insumos — qué compramos y usamos para trabajar

- Perfiles, tornillos, burletes, vidrios, silicona.
- Datos: nombre, **unidad de compra** (ml, m², kg o unidad — cada insumo una; m² para vidrio y tela
  mosquitera, que la vidriería cobra y el paquete usa por superficie), peso por unidad (para
  condicionar herrajes y pasar el costo por kg a la unidad), unidad de comercialización /
  presentación (ej: barra de 6 m), **categoría** (ver *Categorías*). Sin tipo fijo (*Sin tipo fijo
  de insumo*, ficha v2).
- **La presentación sirve para vender suelto y para comprar, no para el paquete** (2026-10-14). Suelto
  se vende por presentación entera (2 barras = 12 ml × costo) o por unidad del insumo, según elija
  administración (*El suelto se vende por presentación o por unidad del insumo*, ficha v2). Compras
  compra barras enteras y Taller podrá calcular cuántas salen del despiece. En el paquete el insumo va en su unidad
  (ml); el sobrante de barra entra por el desperdicio.
- **El costo se carga como se cotiza y el sistema lo pasa a la unidad del insumo** (2026-10-14).
  Compras dice por qué es el monto: por unidad del insumo ($ 5.000 / ml), por presentación
  ($ 30.000 / barra → ÷ 6 = $ 5.000 / ml) o por kg ($ 8.000 / kg × 0,85 kg/ml = $ 6.800 / ml). Para
  eso **la presentación lleva su contenido en la unidad del insumo** (barra = 6 ml, caja = 100
  unidades). La pantalla muestra la conversión; si falta el dato (por kg sin peso cargado) queda sin
  costo (*Sin costo no es $ 0*). El costo por kg es de cada variante de color (el negro mate no vale
  lo que el natural). Por qué: la barra cargada como ml cobraba 6× el perfil, y el $/ml hecho a mano
  queda viejo cuando cambia el kg.
- **El desperdicio es un % del insumo, uno solo para todos los paquetes** (2026-10-14): perfil 8 %
  (6,60 ml → se cobran 7,13), vidrio 5 % sobre m², felpa 0 %. Lo carga el técnico con lo que informa
  taller (el parámetro del que sale no hace falta en esta fase): es cantidad, no precio. Un paquete no
  desperdicia más que otro. Descartado: % por paquete — el mismo perfil tendría 8 % en uno y 10 % en otro.
- **La fórmula dice lo que queda puesto; el desperdicio, lo que se tira** (2026-10-14). Fórmulas y
  largos de pieza llevan la medida real (el `× 1,15` de la felpa vale: da vuelta en las esquinas y
  queda puesta); el desperdicio sale solo del insumo, se aplica para cobrar sobre la cantidad y no
  toca el despiece (taller corta 1500, no 1650) ni el peso (*El sistema pone una variable de peso por
  grupo*). Suelto no lleva desperdicio: se cobra la presentación
  entera (2 barras = 12 ml, no 12,96) o la cantidad pedida (1,4 m² de Float, no 1,47). Por qué:
  un `× 1,10` en la fórmula se sumaba al 8 % (18,8 %).
- **"Se vende suelto"**: solo los marcados le aparecen al vendedor como producto. Lo marca
  administración.
- Sin costo: el costo de reposición vive en Compras, con su moneda (ARS, US$, €).
- Ente: sí (vinculable a proveedores vía `contactos_vinculos`; declara el rol `proveedor`).

### Servicios — lo que no es material y se cobra

- Procesamiento, colocación de burlete, soldadura, mano de obra de instalación, y los **comerciales**:
  comercialización, manipulación.
- **Fijo**: monto por unidad del servicio — **cada servicio tiene unidad: ml, m² o unidad**
  (2026-10-14) (soldadura $ 1.500 c/u, colocación de burlete $ X por ml); la cantidad se convierte
  como la de un insumo (ver *Las fórmulas trabajan en mm*). **Porcentual**: % sobre la suma de los insumos
  **de su grupo** (no del paquete entero), con **precio mínimo** — el mínimo se aplica **una vez por
  servicio en el paquete**, sobre la suma de sus grupos, no en cada grupo (mano de obra 15 %, mín $ 5.000).
  Como el paquete calcula una abertura, el mínimo es **por ventana**: 4 chicas de $ 3.000 cobran
  4 × $ 5.000 (ver *La cantidad es de la línea*).
- ~~**El % de un servicio del paquete no incluye lo que entra por un paño (vidrio, cámara, panel)**~~
  → *El % de los servicios del paquete deja afuera las categorías de insumos que marca
  administración* (ficha v2, 2026-10-21).
- Montos, % y mínimos los pone **administración**; el técnico no los ve.
- **No hay margen:** el precio de venta es insumos a costo + servicios. La ganancia está en los
  servicios comerciales.
- ~~Servicios comerciales: generales, con excepción por paquete~~ → *Servicios por categoría*.

### Paquetes — cómo se arma y cuánto lleva

- Plantilla con nombre ("Ventana corrediza 2 hojas") que lista insumos y servicios con su **cantidad o
  coeficiente**. El técnico pone *cuánto* (soldadura × 4, perfil = 2×ancho + 2×alto); administración y
  compras ponen *cuánto vale*; el sistema multiplica.
- Es el motor paramétrico del ERP viejo, recortado. Primer tramo propuesto: variables que carga el
  vendedor (ancho, alto), variables calculadas, grupos (con opcionales, ej: mosquitero),
  materiales con cantidad fija o calculada, **servicios con cantidad** (nuevo: la spec vieja no los
  tenía), peso, versiones (un presupuesto no cambia si se edita el paquete) y **restricciones**
  (mín./máx. de una variable con su mensaje: **avisan o frenan**, ver *Lo imposible deja la línea sin
  precio*) y **corte** por pieza (ángulo: 90°, 45°; no cambia el precio, es para el despiece de
  Taller — se carga desde ya aunque Taller no exista) y **colores** (el vendedor elige el color y cada
  insumo se cambia solo por su equivalente en ese color; el que no tiene color, como la felpa, queda
  igual). **La equivalencia vive en el insumo**, una sola vez (ART-2301 en negro mate es ART-2301-NM),
  y la usan todos los paquetes; ~~el paquete solo dice qué colores ofrece~~ → los colores del paquete
  se calculan de sus insumos (*Los colores son de administración*, 2026-10-21). Descartado: mapear en cada
  paquete como el mockup — el mismo perfil se remapearía en cada plantilla y los mapeos podrían
  contradecirse. ~~Y **vidrios compuestos**~~ → *El DVH son opciones por capa* (ficha v2,
  2026-10-21). Después: reglas, simulador, grafo.
- **Lo imposible deja la línea sin precio** (2026-10-14), como un insumo sin costo: se arma pero no
  se envía. El sistema frena solo pieza o medida de vidrio ≤ 0 y cantidad < 0 (0 vale: no lleva); el mensaje dice
  qué falla y, si viene de una medida pisada, ofrece volver al automático (*hoja der mide −56 mm:
  hoja izq pisada en 900*). **Cada restricción del técnico avisa o frena** (por defecto avisa): frena
  lo que no se fabrica (*Corrediza económica: más de 2400 de ancho el perfil no aguanta, usar
  reforzada*), avisa lo que se fabrica pero no conviene. Por qué: el ancho cargado en cm (150) daba un
  paño negativo que restaba vidrio, y un aviso no impedía vender lo que la línea no soporta. El
  trabajo especial fuera de línea pasa por el técnico.
- **El aviso es parte del resultado de la línea** (2026-10-14), con el precio, el despiece y por qué
  entró cada material (cada persona ve su parte: *Precio y despiece se habilitan por separado*, ficha
  v2): no algo que se ve una vez al cargar. Presupuestos lo deja marcado en la línea
  y lo lista al enviar o aprobar, para confirmarlo sin frenar. Por qué: *más de 1800 de alto conviene
  reforzada* se veía al cargar y quien enviaba no se enteraba. Descartado: aceptarlo línea por línea —
  es un freno más, y para eso está "frena".
- **Un perfil se carga por piezas: nombre, cantidad y largo por fórmula** (2026-10-14), ej. marco:
  2 travesaños de `ancho` y 2 jambas de `alto`, a 45°. Los ml salen de sumar las piezas, no de otra
  fórmula: una sola fuente, y "Probar paquete" muestra el despiece para taller (piezas a cortar en
  mm, con el color elegido, y la medida de cada vidrio) para que el técnico lo verifique.
- **Cada pieza lleva un ángulo por extremo, por defecto 90° / 90°** (2026-10-14). El mismo perfil
  hoja da travesaños a 45/45 y un travesaño intermedio a 90/90, y un parante puede ir 45/90. El
  despiece dice *Travesaño intermedio × 1 — 1270 mm — 90/90*. Por qué: con un ángulo por material el
  intermedio salía a 45° y la pieza se perdía.
- **Una pieza más larga que la barra da aviso** (2026-10-14). El sistema compara cada pieza con el
  contenido de la presentación del insumo (barra = 6 ml = 6000 mm): *Travesaño marco 6500 mm: más
  largo que la barra de 6000 mm*. Aviso y no freno: se hace con barra especial o empalme, y lo que no
  se fabrica ya lo frena una restricción del técnico. Por qué: se cobraba 6,5 ml y taller se enteraba
  al cortar, con el presupuesto aprobado. Descartado: la restricción a mano en cada paquete — se
  olvida y el largo ya está en el insumo.
- **Lo que va por unidad se redondea hacia arriba solo** (2026-10-14), insumo o servicio: `alto / 250`
  = 4,4 → 5 tornillos. Por abertura y antes del desperdicio (5 con 5 % se cobran 5,25; el despiece dice
  5). ml y m² quedan con decimales. Lo que se usa en fracción va en otra unidad (silicona en ml, no
  ½ cartucho).
- **El largo de cada pieza y cada lado de un paño se redondean al mm, hacia abajo** (2026-10-14), y
  con ese número sale todo: despiece, ml cobrados, peso y el aviso de barra. El vidrio cobra y pesa
  por su variable de superficie, sin redondear; se redondean sus medidas del despiece (*El vidrio
  cobra por una variable de superficie*, ficha v2). Las variables intermedias (`ancho_hoja_izq`) no se redondean: solo lo que se corta o se
  pide. Por qué: con 1501 de ancho la hoja daba 772,5 mm y taller y vidriería redondeaban cada uno a
  su manera; hacia abajo, porque medio mm de menos entra y de más no. Descartado: redondear las
  variables intermedias — el error se acumula cuando una medida sale de otra.
- **La cantidad es de la línea del presupuesto, no del paquete** (2026-10-14). El paquete calcula
  una abertura; ninguna fórmula ve la cantidad. La línea multiplica el precio unitario y el despiece
  (4 corredizas → 8 travesaños de marco). Por qué: como variable del técnico, la felpa sin `× cantidad`
  daba 4 ventanas con felpa para 1. El mínimo de un servicio queda por ventana; lo que se hace una vez
  por pedido (traslado, flete, preparación) es un cargo del presupuesto entero, en Presupuestos.
  Descartado: mínimo por línea — con 3 renglones en la misma obra, cobraba 3 veces lo que se hace 1.
- **Las fórmulas trabajan en mm, como las medidas, y el sistema pasa el resultado a la unidad del
  insumo o del servicio** (2026-10-14): ml → mm (`(2×ancho + 2×alto) × 1,15` = 5980 mm → 5,98 ml de
  felpa), m² → mm² (`ancho × alto` = 1.650.000 mm² → 1,65 m² de tela), unidad y kg sin conversión.
  La cantidad fija también: en un insumo por ml, 6000 son 6 ml. El campo muestra la conversión al
  lado (`= 5.980 mm → 5,98 ml`) y Probar las dos cifras. Por qué: todas las variables ya están en
  mm, así que una fórmula escrita sin pensar en unidades da justo lo que el sistema espera.
  Descartado: escribir en la unidad del insumo (`/ 1000`) — olvidarlo cobra 1000× y no se nota.
- **Cada variable declara su unidad, y la fórmula de cada material y servicio tiene que dar la suya**
  (2026-10-21). El técnico elige ml, m², kg o unidad al crear una medida del vendedor, una variable
  de opción o una calculada, obligatoria y sin default; las del sistema ya la traen (`peso_*` kg,
  `espesor_*` ml, `con_<grupo>` unidad). El valor
  sigue en mm y mm² (*Las fórmulas trabajan en mm*): la unidad dice qué mide, no cambia la cuenta. El
  parser que valida la fórmula al guardar saca también su unidad: largo × largo = m², m² ÷ largo =
  ml, largo ÷ largo = unidad, unidad × algo = ese algo; un número suma o resta en la unidad del otro
  lado (`ancho − 6`) y multiplica o divide sin cambiarla (`× 1,15`, `/ 2`); `redondear` la conserva y
  `máximo`/`mínimo` piden la misma en todo. Lo que no da una de las cuatro (ml × kg) es fórmula mal
  escrita. Si no coincide con la del insumo o el servicio, no se manda a aprobar, y en el borrador se
  marca en el campo (*`= 850.000 mm² · Felpa va por ml`*): *Tela mosquitera* (m²) ×
  `perimetro_hoja_izq` da ml; *Felpa* (ml) × `ancho_hoja_izq × alto_hoja` da m²; *Tornillo* (unidad) ×
  `alto` da ml. La fórmula de una calculada, y el default de una medida, también tienen que dar lo que
  declaran, **salvo unidad, que acepta cualquiera**: es como se dice "una cada 600 mm". *Grampa* ×
  `redondear.mas(alto / 600; 0)` frena (da ml); se carga `fijaciones_jamba` con esa fórmula,
  declarada unidad, y la usan grampas, tornillos y tarugos. El largo de cada pieza tiene que dar ml,
  y un material por piezas da ml: *Marco corrediza 70 mm* dado de alta por unidad frena (*va por
  unidad y las piezas dan ml*), en vez de cobrar 5.200 barras. Una cantidad fija no se controla: ya
  está en la unidad del insumo. Por qué: la conversión pasa a la unidad del insumo lo que dé la fórmula sin
  preguntar qué mide; la tela por perímetro cobraba 0,0038 m² y la Corrediza salía $ 591.000 en vez
  de $ 600.000 sin que el técnico ni administración lo notaran. Descartado: controlar solo la
  cantidad que es una variable sola — la mayoría de las fórmulas se escriben en el material y
  quedaban afuera de un control que parece cubrir todo.
- ~~**La composición del vidrio es por paño**~~ → *Las opciones hermanas arrancan juntas* (ficha v2,
  2026-10-21).
- ~~**El panel ciego entra por la composición del paño, como el vidrio**~~ → es una alternativa más,
  como el vidrio (*El vidrio es un material de la hoja con una opción*, *El espesor lo pone el
  sistema desde el insumo*, *Las alternativas se filtran por color*, ficha v2, 2026-10-21).
- ~~**En la composición, lo que elige el vendedor se filtra y lo que declara el técnico cuenta como
  material fijo**~~ → *Las alternativas se filtran por color* y *Lo que el catálogo deja de ofrecer
  deja la línea sin precio* (ficha v2, 2026-10-21).
- ~~**Cada pieza de la composición se cobra en su unidad**~~ → *El DVH son opciones por capa* (ficha
  v2, 2026-10-21).
- **Un color se ofrece solo si todos los insumos *de la ventana* del paquete lo tienen** (2026-10-14). Si
  al perfil hoja le falta el blanco, la ventana no se ofrece en blanco: el técnico ve qué falta y el
  vendedor no ve ese color hasta que se cargue el equivalente, sea material fijo o condicional. Una
  alternativa sin el color solo deja de ofrecerse en ese color (*Las alternativas se filtran por
  color*, ficha v2, 2026-10-21).
  Los sin color y los de herrajes no cuentan. Descartado: dejar el insumo en natural con aviso — una ventana blanca con una hoja
  natural no se vende — y frenar el presupuesto, que lleva el problema al vendedor.
- **El insumo declara su color: sin color, de la ventana o de herrajes** (2026-10-14). *Sin color*
  (felpa, tornillos, vidrio) no cambia. *De la ventana* (perfiles, tapas a la vista) va en el color de
  la ventana y sin el equivalente ese color no se ofrece (*ART-2410 sin negro mate*). *De herrajes*
  (manijas, cierres) sigue al color de herrajes de la línea; si no lo tiene, va en su
  color base y no bloquea. Sin default: el técnico la elige al crear el
  insumo (antes salía del tipo, descartado en la v2). Por qué: un perfil recién cargado sin variantes parecía "sin color" como la felpa
  y salía natural en una ventana negra; y un herraje que solo viene plateado, que va en blanco y en
  negro, sacaba el blanco de toda la corrediza. Descartado: deducirlo solo del tipo — "otro" mezcla manijas y
  tornillos; y reglas de color por clase de material (fijo, alternativa, condicional) — sacados los
  herrajes, la regla estricta ya no bloquea de más.
- **El color de herrajes es una opción secundaria de la línea, por defecto "como la ventana"**
  (2026-10-14): lo normal es negro en ventana negra, pero el cliente lo cambia. Uno por línea, no por
  herraje. El plegado dice lo que no se pudo (*herrajes: negro · manija: plateado (no hay en
  negro)*). La opción del vendedor elige el modelo (manija, embutida, tirador); el color sale
  de acá.
- ~~**El técnico edita un borrador y "Publicar" crea la versión que ve el vendedor**~~ → *Mandar a
  aprobar frena; aprobar pone a la venta* (ficha v2, 2026-10-21).
- ~~**El paquete guarda casos de prueba, y al publicar muestra qué cambia en cada uno**~~ → *Los
  casos de prueba corren cuando alguien los mira; uno es el de referencia* (ficha v2, 2026-10-21).
- ~~**Un insumo dado de baja cuenta como que no está**~~ → *La baja depende de cómo se usa lo que se
  da de baja* (ficha v2, 2026-10-21).
- **La variante de color solo tiene código, nombre y costo; lo físico es del insumo base**
  (2026-10-14): peso, unidad, presentación, desperdicio, categoría y su clase de color no se cargan
  en la variante. El $/kg del negro se multiplica por el kg/ml del natural. Por qué: el negro con peso
  0 bajaba la hoja de 43 a 30 kg y salía con rueda simple, y su costo por kg quedaba sin costo.
  Descartado: desperdicio por variante — la barra que se corta es la misma. En la v2 el nombre lo
  pone el color de la lista y el costo está en Compras (*Los colores son de administración*).
- **Lo que carga el vendedor lo define el paquete** (2026-10-14), no es un juego fijo de ancho y alto: el técnico declara cada variable del vendedor. Puede ser una **medida** (número, con sus
  restricciones) o una **opción** entre insumos (manija o embutida): el técnico marca un
  material del paquete y le carga las alternativas; el vendedor elige y el material cambia por el
  elegido. **Cada alternativa usa la fórmula del material o trae la suya** (una manija de dos puntos
  de fijación lleva otros tornillos).
- **Una opción puede poner una variable que usan las fórmulas** (2026-10-14): la manija define
  `desc_manija` (manija 3, tirador 0, embutida 5) y el técnico escribe `ancho_hoja = ancho / 2 + 25 -
  desc_manija`. Así lo que cambia una medida se ve en la fórmula de esa medida, en un solo lugar.
  Descartado: que cada alternativa le "ajuste" la variable (−5 mm al ancho de hoja) — el ajuste
  quedaría escondido en la opción y la fórmula de `ancho_hoja` no diría la verdad.
- **Una opción puede poner varias variables: cada alternativa carga un valor en cada una, y lo que no
  carga vale 0** (2026-10-14). El herraje pone `desc_herraje_izq` (manija 3, embutida 5, cierre 0,
  tirador 5) y `embutido_izq` (embutida 1); ~~el *Mecanizado de embutido* entra si `embutido_izq` = 1~~
  → lo trae la *Manija embutida* (*Un insumo puede traer sus servicios*, ficha v2, 2026-10-21).
  Por qué: con una sola variable no había cómo hacerlo entrar — `desc_herraje_izq` = 5 también lo
  metía con el tirador. Descartado: un código por posición con `elegir(herraje_izq; 3; 5; 0; 5; 0)`
  — reordenar las alternativas rompe las fórmulas sin que se note; y una condición sobre qué insumo
  entró — tipo de condición nuevo.
- **Una medida del vendedor puede traer un valor por defecto por fórmula** (2026-10-14), para hojas
  asimétricas: `ancho_hoja_izq` propone `ancho / 2 + 25 - desc_herraje_izq` y el vendedor la pisa
  solo si hace falta; `ancho_hoja_der` es calculada (`ancho - ancho_hoja_izq + 50 - desc_herraje_izq -
  desc_herraje_der`). Si la pisó, se respeta aunque cambie `ancho`; si no, se recalcula. **La pisada
  muestra el automático al lado y vuelve con un botón o borrando el campo** (`900 · automático 925 ↺`),
  y el plegado de la línea la nombra (*hoja izq: 900, pisada*): pisada en 900 sobre 1500, al pasar a
  1800 salía asimétrica al revés y volver pedía calcular 925 a mano. Descartado: soltarla sola al
  cambiar `ancho` (pierde la pisada a propósito) y un aviso (no hay nada mal). Las piezas y
  los paños se cargan por hoja. Descartado: un paquete "asimétrico" aparte — repite todos los
  materiales para el 10% de los casos.
- **El herraje es una opción por hoja, y una alternativa puede llevar condiciones** (2026-10-14).
  Cada hoja lleva el suyo y pueden ser distintos (manija en una, cierre embutido en la otra): el lado
  importa para taller. El vendedor elige el herraje de cada hoja (`herraje_izq`, `herraje_der`, cada
  uno con su `desc_herraje_*`). Cada alternativa se ofrece si se cumplen sus condiciones, en las
  mismas casillas que los materiales condicionales (el *Vidrio interior* solo con cámara: *El DVH son
  opciones por capa*). Si la elegida deja de ofrecerse, entra lo que dice *Lo elegido se guarda*.
  Descartado: una opción que oculta a otra — es un concepto nuevo, y las condiciones y las variables
  de opción ya existían.
- ~~**El cierre central es un kit y entra en la hoja que lleva el cuerpo**~~ → *El cierre central no
  tiene decisiones propias* (ficha v2, 2026-10-21).
- ~~Todo lo que carga el vendedor tiene default~~ → *El default es obligatorio solo en lo secundario*.
- **El default es obligatorio solo en lo secundario** (2026-10-14). Opción: el técnico marca la
  alternativa por defecto; si su condición no se cumple, la primera que se ofrezca (*Lo elegido se
  guarda*). Medida: el
  default por fórmula de arriba, o un número fijo. Grupo opcional: arranca puesto o sacado
  (mosquitero: no). **Una principal sin default arranca vacía y es obligatoria**: la línea queda sin
  precio con *Falta alto*; una secundaria sin default toma la primera alternativa si es opción, y si
  es medida no se publica. **Una medida principal no lleva default, ni fijo ni por fórmula**
  (2026-10-21): con uno no se manda a aprobar. El sistema no sabe cuál es el ancho y cuál el alto, y
  `alto` principal con 1000 volvía a cotizar el alto olvidado; la que necesita default es secundaria
  (`ancho_hoja_izq` con su automático, en "Más opciones"). El color de la ventana es principal y
  sin default; la opción de vidrio es principal y el técnico decide si lleva default (float 4 en una
  línea que casi siempre va así). Por qué: con 1000 por defecto, el alto olvidado en una de 6
  ventanas se cotizaba 1000 y tenía precio, así que nadie lo veía.
- **Lo elegido se guarda; lo que entra se calcula** (2026-10-14). La línea guarda la alternativa
  que eligió el vendedor y entra: lo elegido si se ofrece; si no, el default si se ofrece; si no, la
  primera que se ofrezca. Nada se sobrescribe. Una principal sin default no pasa a la primera: queda
  vacía, como al arrancar (2026-10-21). El vendedor cambia la Puerta rebatible a blanco, PAN-01 no
  viene en blanco y la línea queda sin precio con *PAN-01 no viene en blanco: elegí paño bajo*; con
  la primera, entraba Float 4 mientras él miraba el color. Por qué: vidrio interior Float 5 → sin cámara (entra
  *Sin material*) → vuelta a Cámara 12 perdía el Float 5, y la ficha decía "primera válida" en un
  lado y "default" en otro. Igual que la medida pisada: se respeta lo elegido y se muestra lo que entra hoy. Vale
  cuando lo causa la misma línea; si lo deja de ofrecer el catálogo, *Lo que el catálogo deja de
  ofrecer deja la línea sin precio* (ficha v2, 2026-10-21).
- **Cada medida, opción o grupo opcional es principal o secundaria** (2026-10-14). El vendedor ve las
  principales; las secundarias quedan en "Más opciones", que plegado ya muestra qué entra (*herraje
  izq: Manija · mosquitero: no*). Una medida secundaria sin default no se puede publicar, como una
  fórmula mal escrita (una opción siempre tiene la primera alternativa). Si una restricción avisa sobre una secundaria, el aviso se ve y "Más opciones"
  se abre solo. Por qué: el vendedor cotiza lo común sin recorrer cada herraje y abre el resto cuando
  el cliente lo pide. Descartado: que sea principal según una condición — más lógica para lo que ya
  resuelve el plegado.
- ~~**El peso es para logística y condiciona herrajes**~~ → *El peso es del insumo y condiciona
  herrajes; la abertura no da peso* (ficha v2).
- ~~Una opción puede tomar su insumo por una variable calculada~~ → *Materiales condicionales*.
- **Materiales condicionales: los pone el sistema, el vendedor no elige** (2026-10-14). Un material
  puede llevar una condición sobre cualquier variable (medida o calculada): "si `ancho` > 1500 → se
  agrega el herraje X", "si `peso_hoja` > 40 kg → rueda doble". Si se cumple, entra; si no, no. Un
  reemplazo son dos materiales con condiciones opuestas (rueda simple si ≤ 40, doble si > 40). Como
  las alternativas, **usa la fórmula del material o trae la suya**. El despiece muestra por qué entró
  ("Rueda doble — `peso_hoja` 48 kg > 40"). Es el único tipo de regla del primer tramo; las reglas
  generales siguen para después.
  Por qué: la rueda no es una preferencia del cliente, la decide la medida; dejarla al vendedor
  permitía armar una abertura que no anda.
- **La condición se carga en casillas, no se escribe** (2026-10-14): variable, comparación (> ≥ < ≤ =)
  y valor. Un material puede tener varias y entra si se cumplen todas ("ancho > 2000 y alto > 1800").
  Descartado: escribirla como fórmula (`ancho > 2000 y alto > 1800`) — obliga al motor en Postgres a
  interpretar comparaciones y y/o, y el técnico puede escribir algo que no se entiende.
- **Un servicio del paquete también puede llevar condiciones**, en las mismas casillas (2026-10-14):
  "mano de obra extra si `alto` > 2400". ~~El mecanizado del embutido entra si `embutido_izq` = 1~~ →
  lo trae la manija (*Un insumo puede traer sus servicios*, ficha v2). El despiece dice por qué
  entró. Puede mirar el peso: un servicio no suma al peso. ~~Descartado: que la alternativa traiga su
  servicio~~ → *Un insumo puede traer sus servicios* (2026-10-21).
- **Cada material dice si suma al peso** (2026-10-14). Por defecto suma; el técnico lo apaga en el
  material que no debe contar. Así la rueda queda fuera del peso del grupo: el peso que la elige no
  cambia según qué rueda salga (si no, una condición sobre el peso dependería de sí misma).
  ~~**Solo saca el material del peso de su grupo: el peso de la abertura, para logística, suma
  todo.**~~ → la abertura no da peso (*El peso es del insumo y condiciona herrajes*, ficha v2).
  ~~Un material que mira el peso no puede sumar al peso del grupo~~ → *Nada depende de sí mismo*.
- **Nada depende de sí mismo: un paquete con un ciclo no se publica** (2026-10-14). El sistema arma
  las dependencias (fórmulas, defaults, condiciones, variables de opción y de peso) y el mensaje
  muestra la cadena (*`ancho_hoja_izq` → `ancho_hoja_der` → `ancho_hoja_izq`*); en el borrador se
  marca al editar. La rueda que mira `peso_hoja_izq` y suma a él es un caso: el
  técnico le apaga "suma al peso". El refuerzo del marco que mira el peso de la hoja no cierra ciclo y
  suma. Por qué: la regla solo del peso dejaba pasar defaults cruzados que cuelgan el cálculo y
  frenaba el refuerzo sin motivo. Es error de armado y lo corrige el técnico; descartado: avisar al
  vendedor, que no puede hacer nada.
- **El sistema pone una variable de peso por grupo** (2026-10-14): `peso_hoja_izq`, `peso_marco`…,
  suma de los materiales del grupo que suman al peso (cantidad × peso del insumo). El técnico arma con
  ellas el peso que necesita. **El peso es de lo que queda puesto: cantidad sin desperdicio**, en
  los grupos — el sobrante queda en taller, no en la hoja. Por
  qué: una hoja de 38 kg (aluminio 14 + paño 24) con desperdicio pasaba a 40,3 y salía con rueda doble. Descartado: calcular el peso a mano en la fórmula (ml × kg/ml + m² ×
  espesor × 2,5) — repite el peso del insumo y queda viejo si cambia.
- **Cada grupo opcional pone `con_<grupo>`: 1 si el vendedor lo puso, 0 si no** (2026-10-14), como
  pone `peso_<grupo>`. Con mosquitero el marco va de 3 guías: dos materiales condicionales, marco 2
  guías si `con_mosquitero` = 0 y 3 guías si = 1. Los grupos fijos no la ponen. Descartado: que el
  vendedor elija las guías — puede poner mosquitero con marco de 2 — y un paquete aparte con
  mosquitero, que repite todo por un perfil.
- ~~**El sistema también pone el peso de cada paño, y su superficie, perímetro y espesor**~~ → *El
  vidrio es un material de la hoja con una opción, como el herraje* (ficha v2, 2026-10-21).
- ~~**La superficie del paño va en mm², como toda variable**~~ → la escribe el técnico como calculada
  y vale en mm², como toda variable (*Las fórmulas trabajan en mm*; *El vidrio es un material de la
  hoja con una opción*, ficha v2, 2026-10-21).
- ~~El técnico usa la hoja más pesada (`peso_hojas / 2 + maximo(...)`)~~ → *Un grupo por hoja*.
- **Un grupo por hoja** (2026-10-14): `hoja_izq`, `hoja_der`, cada uno con sus materiales y su peso
  (`peso_hoja_izq`, con el vidrio). Cada hoja lleva la rueda que pide su peso,
  y el despiece sale por hoja, como se arma en taller. Por qué: con hojas asimétricas el `/2` le
  restaba aluminio a la ancha, justo la que puede pedir rueda doble; y como las piezas ya son por
  hoja, separar grupos casi no duplica. Lo repetido (felpa, rueda, manija) se alivia con **"duplicar
  grupo"**.
- **"Duplicar grupo" pide qué reemplazar y por qué, y muestra cada cambio antes de confirmar**
  (2026-10-14). Propone el par por los nombres (`hoja_izq` → `hoja_cen`: `_izq` → `_cen`) y lo aplica
  en fórmulas, condiciones y variables de opción; la lista marca las variables que no existen
  (*`desc_herraje_cen` ⚠ no existe*). Se confirma igual: es borrador, y una variable que no existe es
  fórmula mal escrita, que no se publica. Por qué: con 3 hojas el `_izq` → `_der` fijo daba dos
  `hoja_der` y la central con las fórmulas de la derecha. Descartado: numerar hojas `_1`, `_2`, `_3`
  — taller habla de izquierda y derecha.
- **El vendedor no agrega materiales a la composición del paquete** (2026-10-14). Lo que se pide
  seguido (traba de seguridad) el técnico lo suma como grupo opcional secundario, arrancando sacado,
  y entra en despiece, peso y cantidad de la línea. Lo puntual va como línea suelta del presupuesto,
  referida a la línea que acompaña (*Traba × 4 — para V4*). Descartado: agregados dentro de la línea —
  mecanismo nuevo que mete en la abertura material que nadie del lado técnico validó.
- Un insumo suelto se precia como un paquete de una línea: costo + servicios por categoría y generales,
  sin desperdicio (*El suelto se vende por presentación o por unidad del insumo*, ficha v2).
- **Pantalla de referencia:** `C:\dev\Archivos antiguos\mockup_plantillas_v4.html` (lista con versiones y
  estado; detalle en pestañas: grupos, variables, materiales, restricciones, vidrios, reglas, colores,
  sandbox, auditoría). **Se le suma una pestaña Servicios** al lado de Materiales: el técnico elige el
  servicio del catálogo y le pone cantidad fija o por variable (soldadura × 4); el monto no se ve.
  **Cada servicio va en un grupo**, como los materiales: si el vendedor saca un grupo opcional
  (mosquitero), su mano de obra sale con él.

## Categorías (2026-10-14)

~~**Insumos y paquetes tienen categorías que crea el usuario, de un solo nivel; servicios, no.**~~ →
*Categorías en dos niveles fijos, en las tres vistas* (ficha v2).

~~**La línea de perfiles va en el nombre del paquete, y el buscador del vendedor toma palabras en
cualquier orden**~~ → *En paquetes, la subcategoría es la línea de perfiles* (ficha v2, 2026-10-19).

~~**En insumos, la categoría (libre) va separada del tipo (fijo: vidrio, cámara, panel, perfil,
otro).**~~ → *Sin tipo fijo de insumo* (ficha v2, 2026-10-20).

~~**El aumento de costo se aplica por categoría o por insumo, en % o monto fijo, con motivo e
historial**~~ → no es del catálogo: es de Compras (`BACKLOG.md` → Compras, 2026-10-21).

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

- El % va sobre los insumos que alcanza la regla (no sobre servicios) y no lleva mínimo.
- Los servicios fijos (soldadura × 4) no van por categoría: su cantidad depende del paquete.
- Reglas y excepciones las pone administración; el técnico ve qué recibe el paquete, sin el %.
- Demo: https://claude.ai/artifact/RK1y3Gs42DoNx4h8v7yfzW (pestaña Servicios y "Lo que recibe por
  categoría" en Paquetes).

## Precio de venta

```
Insumo        cantidad (técnico, fija o fórmula) × (1 + desperdicio del insumo) × costo de reposición
              (Compras) → a pesos, oficial BNA venta
Servicio fijo cantidad (técnico) × monto (administración)
Por insumo    cantidad puesta del insumo (sin desperdicio) × lo que lleva por unidad (técnico) × monto
              (administración) — ver *Un insumo puede traer sus servicios*
Servicio %    % (administración) × suma de insumos de su grupo, sin las categorías marcadas fuera del %; mínimo (administración) una vez
              por servicio en el paquete, sobre la suma de sus grupos
Por categoría % (administración) sobre los insumos que alcanza; gana la regla más específica
              (ver *Servicios por categoría*)
Precio        insumos + servicios, de una abertura — se calcula en Presupuestos, con las medidas
Línea         precio × cantidad (de la línea, nunca de las fórmulas)
Descuento     no es de Catálogo: va en Presupuestos (BACKLOG.md), sobre el precio de lista
```

**Sin costo no es $ 0: la línea queda sin precio** (2026-10-14). El costo de un insumo (Compras) o el
monto de un servicio (administración) puede faltar, pero no vale 0: un 0 se rechaza. Si en la línea
entra algo sin costo, el motor no da precio y dice qué falta (*sin precio: falta costear Rueda
doble*); cuenta solo lo que entra (con hojas de hasta 40 kg va la simple y hay precio). El presupuesto
se arma igual pero no se envía con una línea sin precio. Compras y administración ven la lista "sin
costo y en uso" con los paquetes donde está. Por qué: con $ 0 la corrediza de hojas pesadas salía
sin la rueda doble y el precio parecía normal. Descartado: no ofrecer lo que no tiene costo (el
vendedor no sabe por qué falta) y avisar cobrando $ 0.

Cotización: oficial BNA venta de USD y EUR, automática con corrección manual (como `erp_old`: dolarapi,
ventana 10–15 h, cierre del día, lo manual no lo pisa el automático; `erp_old_2`: monedapi.ar).

**La cotización es una vista de Compras, no un módulo** (2026-10-14). Una tabla, una pantalla y una
persona (administración la corrige); Compras es dueño de los costos en moneda extranjera y Catálogo y
Presupuestos solo la leen, como leen el costo. Si crece (más monedas, índices), se separa.

## El motor va en Postgres (2026-10-14)

**El precio lo calcula una función de Postgres `SECURITY DEFINER` que devuelve el precio y nunca el
costo.** RLS filtra filas, no columnas: el vendedor no puede leer la tabla de costos, así que una
función `INVOKER` no podría calcular, y hacerlo en TypeScript exigiría `service_role`. Excepción
explícita a `SECURITY INVOKER`, acotada a esta función.

**Monto, %, mínimo, reglas por categoría y excepciones por paquete van en tablas propias, como el
costo** (2026-10-14). `servicios` guarda solo lo que ve el técnico (nombre, unidad, fijo/porcentual,
comercial); si el 15 % fuera columna de `servicios` o la excepción columna de `paquetes`, el técnico
los leería por API. Como la función de precio es `DEFINER` y salta RLS, **verifica adentro quién
llama**: precio y despiece por separado, avisos y plegado a todos (*Precio y despiece se habilitan
por separado*, ficha v2). Quién ve cada parte, y de qué versiones: *La función de cálculo decide qué parte ve cada uno* (ficha v2). Descartado: una vista que oculte
columnas — segunda puerta a la misma tabla, y un `select` olvidado sobre la base filtra todo.

**Las fórmulas se validan al guardar y se evalúan en la base**: solo números, variables del paquete,
`+ − × ÷`, paréntesis y funciones de una lista (redondear, redondear.mas, redondear.menos, máximo,
mínimo — `redondear.mas(alto / 600; 0)` = 3 grampas). **Coma decimal y punto
y coma entre argumentos, como Excel en castellano** (`* 1,15`, `redondear(ancho / 1000; 0)`); el punto
decimal también se acepta, para que pegar `1.15` no sea un error, **salvo seguido de exactamente tres
cifras**: `2.400` se rechaza al guardar (*¿2400 o 2,4?*), que si no queda en 2,4 mm. Descartado: el motor en
TypeScript del ERP viejo — más rico (reglas, simulador, grafo), pero eso quedó para después.

## Entes (2026-10-14)

**Dos entes: insumo y paquete.** Son lo que otro módulo usa: Compras costea el insumo, Stock lleva sus
existencias, Contactos le vincula el proveedor, y la línea del presupuesto apunta a un paquete o a un
insumo suelto. Lo demás es parte de un ente o configuración: la variante de color es del insumo (Compras
la costea por FK); la versión es del paquete (la línea congelada la guarda por FK, el chip muestra el
paquete); grupos, piezas, materiales, variables, opciones y casos de prueba son el interior del paquete;
categorías, montos, % y reglas de servicios son configuración.

**El servicio no es ente: vive solo dentro del catálogo** (paquetes, reglas y los insumos que lo traen). Un cargo del presupuesto
(flete, traslado) no sale de servicios: es un renglón libre, con descripción y monto que calcula el
vendedor (`BACKLOG.md` → Presupuestos). Si algún día un cargo apunta a un servicio, alcanza una FK.

## ~~Ficha del módulo (borrador)~~

→ *Ficha del módulo — v2*.

## Pendiente

- ~~**Vidrio como opción**~~ (2026-10-21), resueltos los ocho:
  1. ~~**El paño sale.**~~ → *El vidrio es un material de la hoja con una opción, como el herraje*
     (ficha v2).
  2. ~~**Medidas del vidrio para la vidriería.**~~ → *El vidrio cobra por una variable de superficie
     y lleva sus medidas para el despiece* (ficha v2).
  3. ~~**DVH.**~~ → *El DVH son opciones por capa, con lo que ya existe* (ficha v2).
  4. ~~**El mismo vidrio en varias hojas.**~~ → *Las opciones hermanas arrancan juntas y el vendedor
     las separa si hace falta* (ficha v2).
  5. ~~**Espesor.**~~ → *El espesor lo pone el sistema desde el insumo: `espesor_<opción>`* (ficha
     v2).
  6. ~~**Vidrio nuevo.**~~ → *Una opción puede ofrecer subcategorías enteras* (ficha v2).
  7. ~~**Color del panel como alternativa.**~~ → *Las alternativas se filtran por color* y *Lo que
     el catálogo deja de ofrecer deja la línea sin precio* (ficha v2).
  8. ~~**El % de los servicios del paquete sin el vidrio.**~~ → *El % de los servicios del paquete
     deja afuera las categorías de insumos que marca administración* (ficha v2).
- ~~**Para aprobar la ficha v2**~~ — aprobada el 2026-10-21:
  - ~~Delegables~~ (2026-10-21): en el árbol y en *Se delegan las vistas y lo del técnico*.
  - ~~Servicios por categoría en las acciones~~ (2026-10-21): en Acciones, en el árbol y en *Reglas y
    excepciones se cargan desde el servicio*.
  - ~~Presupuesto enviado~~ (2026-10-21): en *Un presupuesto enviado se mantiene o se actualiza*.
  - ~~Lo que la v1 tenía y la v2 no~~ (2026-10-21), los doce resueltos: el 1 (la baja: *La baja
    depende de cómo se usa lo que se da de baja* y siguientes), el 2 (despiece y vendedor: *Precio y
    despiece se habilitan por separado*), el 3 (unidad del suelto: *El suelto se vende por
    presentación o por unidad del insumo*), el 4 (depósito: *Depósito no usa el catálogo*), el 5
    (Compras: *Compras no usa el catálogo*), el 6 (listas: *Lo que falta costear se ve en filtros*),
    el 7 (permisos de afuera: *La función de cálculo decide qué parte ve cada uno* y *Stock y Compras
    leen la tabla del insumo*) y el 8 (variante de color: *Los colores son de administración*), los
    ocho en la ficha v2. El 9 (aumento de costo por categoría) no es del catálogo: es una acción de
    Compras sobre sus costos, que lee las categorías como lee el insumo (`BACKLOG.md` → Compras).
    El 10 (peso de la abertura para logística) sale: *El peso es del insumo y condiciona herrajes*.
    El 11 (casos de prueba), en Acciones y en *Los casos de prueba son del paquete*. El 12 (ruta,
    submódulo, datos y roles), en Entes y en *Paquete e insumo se registran con su vista*.

### Auditoría v2 (2026-10-21) — resolver de a uno, en orden

Sobre la ficha v2 y lo de arriba que sigue valiendo. Caso base: Corrediza 2 hojas Modena 1500 × 1100,
negro mate, DVH 4+12+4, 4 iguales; Marcos es técnico y Laura, administración. Cada punto: el caso que
falla y una propuesta a discutir, no decidida. Los escenarios del final encadenan varios.

*El texto se contradice*

1. ~~**Quién carga el costo.**~~ → Compras (2026-10-21): corregido en *El costo sigue fuera del
   catálogo, en Compras*.
2. ~~**¿El paquete dice qué colores ofrece?**~~ → no, se calculan (2026-10-21): en *Los colores son
   de administración*, y tachado lo de la v1 en *Paquetes*.
3. ~~**"Material que mira el peso y suma al peso" sigue en los controles**~~ → sacado de *Mandar a
   aprobar frena* (2026-10-21); lo cubre "ciclo".
4. ~~**"Lo que apunta a sus versiones se sigue calculando"**~~ → la vigente de un paquete que no está
   a la venta da sin precio (2026-10-21), en *El estado es de cada versión*; la línea, de
   Presupuestos.
5. ~~**Una principal sin default que deja de ofrecerse.**~~ → queda vacía (2026-10-21), en *Lo
   elegido se guarda* y en *Lo que el catálogo deja de ofrecer*.
6. ~~**"Ancho y alto van siempre sin default" no lo hace cumplir nadie.**~~ → una medida principal no
   lleva default (2026-10-21), en *El default es obligatorio solo en lo secundario* y en los controles
   de *Mandar a aprobar frena*.
7. ~~**Cambiar de unidad choca con el reemplazo "de la misma unidad".**~~ → el reemplazo acepta otra
   unidad (2026-10-21), en *La baja de un insumo puede designar su reemplazo* y en *"Reemplazar
   material" es un solo botón*.
8. ~~**El reemplazo de la baja lo decide administración con una herramienta del técnico.**~~ → lo
   reciben todos los paquetes, sin desmarcar (2026-10-21), en *La baja de un insumo puede designar su
   reemplazo*.
9. ~~**El catálogo sí depende de Compras.**~~ → SQL en tres partes (2026-10-21), en *El catálogo no
   apunta con FK a otro módulo* y en el orden de `BACKLOG.md`.
10. **Menores de texto.** El título *La variante de color solo tiene código, nombre y costo* (v2:
    código y color de la lista). *El motor va en Postgres*: "nunca el costo" (a administración le da
    las bases: *sobre $ 60.000*). "Configuración de herrajes" y "medidas y herrajes": se guarda todo lo
    que carga el vendedor (medidas, pisadas, opciones, hermanas juntas o separadas, color, color de
    herrajes, grupos opcionales). Relaciones: la línea sin enviar apunta al paquete, no a la versión.
    El mockup de referencia con pestañas *vidrios* y *colores*. `BACKLOG.md`: "el vidrio no tiene
    default" (puede tenerlo; ¿gana el default o el de la línea anterior?). "El kg no es unidad de
    venta" con insumos por kg vendidos por unidad del insumo. *Fuera del %* es general, pero está en las
    acciones del servicio, "al lado de las reglas".

*Cobra mal sin que nadie se entere*

11. **Editar el insumo cambia precio y despiece al instante, y solo lo ve quien edita.** Los servicios
    que trae avisan a administración; desperdicio, peso, contenido de la presentación y espesor, no.
    Marcos tipea 80 en vez de 8 en el desperdicio del Marco 70 y las Modenas suben 66 %; 8,5 kg/ml en
    vez de 0,85 y todas salen con rueda doble. Propuesta: esos campos muestran el alcance con el caso de
    referencia antes → después y avisan a administración, como los servicios que trae.
12. **Peso que falta.** Lo que entra por subcategoría se filtra por unidad y espesor, no por peso. Un
    Float 6 sin peso entra en 40 vigentes y la hoja de 45 kg sale con rueda simple. Igual una
    alternativa suelta al mandar a aprobar. Propuesta: peso obligatorio en el insumo (0 explícito vale,
    vacío no), como *Sin costo no es $ 0*.
13. **Desperdicio vacío.** No dice si es obligatorio; si vacío cuenta 0, el perfil olvidado cobra 8 %
    menos en todo. Propuesta: obligatorio, con 0 explícito (felpa).
14. **Servicio que trae un insumo, en otra unidad.** *Lleva X por unidad* multiplica la cantidad puesta
    del insumo sin pedir que coincidan: el Float (m²) que trae *Sellado perimetral* (ml) cobra m² como
    ml. Propuesta: el servicio que trae un insumo va en su misma unidad.
15. **El doble cobro avisado queda.** El alcance dice *en 3 ya está cargado a mano: se cobraría dos
    veces*, pero guardar no lo corrige. Propuesta: el mismo servicio por el insumo y a mano en un grupo
    es control de *mandar a aprobar* y marca *a revisar* (29).
16. **Unidad y tipo de un servicio en uso.** Solo la unidad del insumo queda fija. *Colocación de
    burlete* de ml a unidad cobra 5.980 colocaciones; un fijo pasado a porcentual deja su cantidad sin
    sentido, y un porcentual pasado a fijo, sus reglas. Propuesta: unidad y fijo/porcentual quedan fijos
    desde que está en una versión o una regla; otra cosa es un servicio nuevo.
17. **Montos fijos y mínimos que envejecen.** El costo lo pone al día Compras y el % lo acompaña;
    *Soldadura $ 1.500* y el mínimo de $ 5.000 quedan como Laura los cargó en marzo. Propuesta:
    Servicios muestra cuándo cambió cada monto (*hace 7 meses*) y un aumento masivo de montos y mínimos
    en %, como el de Compras sobre costos.
18. **Cotización pegada.** Si el automático cae, todo lo de US$ sale con la de hace semanas sin decirlo;
    y "lo manual no lo pisa el automático" no dice hasta cuándo. Propuesta: lo manual vale para el día;
    sin cotización del día hábil, aviso a administración, y pasados N días la línea queda sin precio.
    Va con Compras.
19. **IVA.** No aparece en ninguna decisión. Si Compras carga una cotización con IVA y otra sin, unos
    insumos salen 21 % arriba. Propuesta: costo neto (al fichar Compras), precio del catálogo neto, el
    IVA en Presupuestos.

*Arma mal (técnico, taller, producción)*

20. **Casillas en otra unidad.** Condiciones y restricciones toman el valor crudo, en mm y mm².
    *Laminado si `superficie_pano_izq` > 2* (pensado en m²) es siempre verdad: 0,714 m² son 714.000 mm².
    *Ancho máx. 2,4* frena todo, y `2.400` en una casilla no tiene el rechazo de las fórmulas.
    Propuesta: la casilla muestra unidad y conversión como el campo de fórmula, el valor de una variable
    m² se carga en m², y el mismo rechazo de `2.400`.
21. **Medida sin límites.** Nada pide mín. y máx. en una medida del vendedor: el ancho en cm (150) en un
    paquete sin restricciones cotiza una ventana chiquita. Propuesta: toda medida del vendedor lleva
    mín. y máx. para mandar a aprobar.
22. **Vidrio sin medidas.** Las medidas de un material por m² son opcionales ("puede llevar"): sin ellas
    el despiece dice *Float 4 — 0,715 m²*, producción no lo puede pedir y el ≤ 0 no frena (dos lados
    negativos dan superficie positiva). Propuesta: un material por m² lleva medidas para mandar a aprobar.
23. **Hermanas juntas que no van iguales.** Juntas en *Laminado 5+5*; una condición no lo ofrece en la
    hoja der, que toma el default por *Lo elegido se guarda*, y el plegado sigue diciendo *vidrio:
    Laminado 5+5*. Propuesta: aviso en la línea y plegado separado (*hoja der: Float 4 — Laminado 5+5 no
    va en esta hoja*).
24. **Pares con tres hojas.** "Embutida en cualquier hoja pone Manija en la otra" supone dos. En la
    Corrediza 3 hojas, ¿Manija en la izq pone Embutida en la central y en la der? Propuesta: pares solo
    entre dos hermanas; con más, cada una par de sí misma.
25. **"Duplicar grupo" no copia la hermandad.** `hoja_izq` → `hoja_cen` deja *Vidrio hoja cen* suelto:
    DVH una vez pone las dos de afuera y la central sale Float 4, más barata. Propuesta: la copia entra
    como hermana de la original, y un control avisa opciones con las mismas alternativas en distintos
    grupos sin hermanar.
26. **Producción no puede caer en *Lo elegido se guarda*.** La orden vendida con Manija Roma, dada de
    baja después (o su variante negra, o movida de subcategoría), se despieza con el default y taller
    arma otra manija. En el presupuesto lo frena la línea sin precio; en producción no hay regla.
    Propuesta: para producción, lo elegido aunque esté de baja (es lo vendido) o error; nunca otro insumo.
27. **Producción elige una versión con otras entradas.** La orden de la v3 se fabrica con la v5, que
    suma `alto_banderola` (principal, sin default) o renombró `ancho_hoja_izq`. Propuesta: solo se
    ofrecen las versiones cuyas entradas cubre lo guardado; si no, el despiece dice qué falta.
28. **Clase de color y color base editables.** Pasar a *sin color* un insumo con 4 variantes costeadas y
    existencias por color, o el base de natural a negro, recolorea costo y stock. Propuesta: quedan fijos
    desde que tiene variantes o está en una versión, como la unidad.

*Depende de que alguien se acuerde*

29. **Lo que se avisa una vez.** Incompleto por una baja, *solo ofrece Sin herraje*, *Laminado 4+4: no
    se ofrece en 12 paquetes* (solo si abre el insumo), el doble cobro (15), el reemplazo sin mandar
    (31), el borrador viejo (32): una campanita y después nada. Propuesta: filtro *a revisar* en
    Paquetes e Insumos, calculado al leer, como el "a revisar" de las plantillas de Tareas. Sin tabla ni
    trigger.
30. **Sin herraje en silencio.** Con todas las manijas de baja la opción ofrece solo *Sin herraje*, y
    "una opción que solo ofrece Sin material no se muestra": las corredizas se venden sin manija y el
    plegado no lo dice. Propuesta: lo que queda en Sin material por condición (vidrio interior sin
    cámara) no se muestra; por bajas, sí, en el plegado (*herraje hoja izq: sin herraje (no hay otro)*).
31. **El reemplazo que nunca se manda.** Marcos reemplaza en 12 paquetes y manda 9. Las otras 3
    vigentes siguen "como si el viejo siguiera activo", sin plazo: al último costo de algo que ya no se
    compra, y producción solo tiene versiones aprobadas, que usan el viejo. Propuesta: marca *a revisar*
    con antigüedad y aviso a administración a los N días.
32. **Un borrador abandonado bloquea el paquete.** Una versión abierta por paquete y no hay *descartar*.
    La v5 a medias de Marcos (fórmula rota, de vacaciones) recibe el reemplazo de la baja y no se puede
    mandar hasta arreglarla. Propuesta: *descartar borrador* y la antigüedad en la lista (*v5 · borrador
    de Marcos · hace 34 días*).
33. **¿A qué técnico?** Rechazo, vuelta al borrador, baja con alcance, *solo Sin herraje*: "aviso al
    técnico", y el paquete lo editan varios (`creado_por` es solo dato). Propuesta: el rechazo, a quien
    mandó; lo de bajas, a todos los que tienen `catalogo_paquetes_editar`.
34. **Compras no se entera.** Lo que falta costear está en un filtro; si nadie lo abre, lo encuentra el
    vendedor. Propuesta: al aprobarse una versión que trae algo sin costo, aviso a Compras (su rama, al
    ficharlo).
35. **El cliente lee los mensajes del técnico.** Las restricciones se escriben pensando en el vendedor
    (*usar reforzada, deja más margen*) y el cliente empresa las ve tal cual. Propuesta: el editor dice
    "lo ven vendedor y cliente".

*Falta un flujo*

36. **Duplicar paquete.** No hay. La Corrediza 2 hojas Herrero se arma de cero aunque sea la Modena con
    otros perfiles, y con la subcategoría como línea es lo de todos los días. Propuesta: paquete nuevo
    con la v1 en borrador copiada de la vigente o de la abierta, y sus casos; después *Reemplazar
    material* solo sobre él.
37. **Reemplazar o dar de baja un servicio.** Dar de baja *Soldadura* (en 25 paquetes) los deja
    incompletos al instante, sin reemplazo ni "como si siguiera activo"; *Reemplazar material* busca
    insumos. Propuesta: el mismo botón y la misma baja con reemplazo, para servicios.
38. **Mover un insumo de subcategoría.** No dice quién. Cambia plata y oferta: la regla (Laminados 15 %
    → Float 10 %), lo que entra por subcategoría (40 paquetes más, o líneas sin precio) y lo que ve cada
    cliente. Propuesta: administración, con alcance; y mover un paquete (Modena → Herrero) también
    muestra el suyo (% que cambia, clientes que dejan de verlo).
39. **Dar de baja una categoría con cosas adentro.** ¿Y los 12 Float de *Vidrios → Float*, las opciones
    que la ofrecen, sus reglas, los clientes habilitados? Propuesta: no se da de baja con ítems activos;
    y *reactivar*, que categorías no tiene y colores sí.
40. **Un color de la lista dado de baja y reactivado.** "Darlo de baja en todos los insumos": al
    reactivar, ¿vuelve también la variante que Laura había dado de baja aparte? ¿Y si es el color base
    de un insumo? Propuesta: la baja de la lista no toca variantes, solo deja de ofrecerse; no se da de
    baja un color que es base de un insumo activo.
41. **Renombrar el paquete.** No está en Acciones ni en la versión. Propuesta: administración, como mover.
42. **Aprobar lo que ya no se vende.** Los controles corren al mandar. Si entre mandar y aprobar se da de
    baja un insumo fijo de la v5, la vigente nueva nace incompleta y la Corrediza sale de venta aunque la
    v4 estaba bien. Propuesta: al aprobar, lo que la dejaría incompleta se marca en pendientes y no se
    aprueba.
43. **La versión nueva que saca una alternativa.** *Lo que el catálogo deja de ofrecer* nombra bajas y
    subcategorías, no la v5 que saca el Laminado: la línea sin enviar con Laminado, ¿sin precio o
    default? Propuesta: sin precio, como las otras.
44. **El trabajo especial.** "Pasa por el técnico", sin decir cómo: la corrediza económica de 2500 frena,
    va como renglón libre y producción recibe una línea sin despiece. Propuesta: decidir si es un
    paquete especial (¿subcategoría sin clientes?) o queda fuera, y decirlo.
45. **Clientes fusionados o que no se ven.** Contactos fusiona dos empresas y no toca lo que apunta a la
    que se va: las habilitaciones quedan en la inactiva. Y las empresas son del equipo que las carga:
    Laura puede no ver la que tiene que habilitar. Propuesta: trigger del catálogo en la fusión (como
    Obras con las comisiones, `sql/146`) y la vista Clientes lista por función, no por la RLS de
    Contactos.

*Para el SQL*

46. **"Con condición no salva al paquete" no se calcula en general.** Saber si en alguna combinación una
    opción queda sin nada es finito con colores y opciones, no con `ancho > 1500` sobre calculadas.
    Propuesta: el incompleto estático mira solo condiciones sobre opciones y color; lo que depende de
    medidas se resuelve por línea (*herraje hoja izq: nada que ofrecer*, sin precio).
47. **Grafo de ciclos.** La lista de *Nada depende de sí mismo* es anterior a `espesor_<opción>` y a las
    condiciones de alternativas y subcategorías (el espesor depende de la alternativa, que puede mirar el
    peso, que incluye el vidrio). Sumarlas.
48. **Eventos.** *Cambian los servicios que lleva* no es ningún `tipo_evento` (el servicio no es ente), y
    el estado vive en la versión: el trigger genérico emitiría con el id de la versión. Propuesta:
    trigger propio en versiones con `paquete_id` (como `tareas_emitir_asignado`); lo de servicios,
    campanita directa o `dato`.
49. **Qué guarda "lo elegido".** Líneas, órdenes y casos cruzan versiones: nombre de variable u opción e
    insumo. Renombrar en la v5 deja *Falta*; reemplazar el insumo lo pierde. Propuesta: definir la
    clave, y que *Reemplazar material* lleve el par viejo → nuevo a lo elegido.

*Menores*

50. "ml" también se lee mililitro: la silicona cargada pensando en el cartucho de 300 ml cobra metros
    de cordón como mililitros. La pantalla dice "m lineal".
51. La cantidad de piezas por fórmula (travesaños intermedios = `alto / 1000`): ¿se redondea para
    arriba como lo que va por unidad?
52. ¿Vale una excepción de 0 % (*este paquete sin comercialización*) con "un 0 se rechaza"? ¿El mínimo
    de un porcentual es obligatorio, o vacío es sin mínimo?
53. Un material por piezas sin presentación no tiene aviso de barra: pedirla para cargar piezas.
54. Al cliente con precio, el motivo *falta costear Rueda doble* es interno: *lo cotiza tu vendedor*.
55. `/catalogo/paquetes/{id}` abre la vigente: sin aprobada, la abierta.
56. La calculada declarada unidad acepta cualquier fórmula: `fijaciones_jamba = alto` (sin `/ 600`)
    pasa y da 1100 grampas. Probar marca lo que va por unidad y da más de 100 por abertura.
57. Color nuevo, categoría nueva, pedir una baja: el técnico lo pide "por fuera". Es un pedido de
    Tareas; decirlo.
58. Para Presupuestos: la línea sin enviar cuyo precio cambió desde que se cargó (el cliente ya escuchó
    $ 600.000) muestra antes → después al enviar. La pisada que queda al cambiar el ancho es riesgo
    aceptado (*Una medida del vendedor puede traer un valor por defecto*).

*Escenarios*

- **Línea Herrero nueva.** Laura crea las subcategorías que pide Marcos (57); Marcos carga 16 insumos,
  dos sin peso y uno sin desperdicio (12, 13), arma la corrediza de cero (36), duplica la hoja y la
  central queda sin hermanar (25), pone *laminado si superficie > 2* (20); Laura aprueba y nadie avisa a
  Compras (34): el vendedor encuentra 16 sin costo.
- **Aluar discontinúa la Hoja 40.** Laura la da de baja con la 42 (7, 8); uno de los 12 tiene la v5 a
  medias de Marcos (32); Marcos manda 9 (31); llega a producción una orden de la v3 (26, 27).
- **La felpa pasa a unidad.** Insumo nuevo, baja del viejo, reemplazo de otra unidad (7, 49).
- **La puerta blanca.** Paño bajo en PAN-01 y el cliente la pide blanca (5); se da de baja el blanco en
  la lista y se reactiva (40); se dan de baja las manijas (30).
- **Seis meses de inflación.** Montos fijos de marzo (17), cotización manual de agosto (18), presupuesto
  armado en septiembre y enviado en octubre (58).
- **Corrediza 3 hojas.** Pares Manija ↔ Embutida (24), hoja central duplicada (25), travesaños
  intermedios por fórmula (51), laminado solo en hojas grandes (23).
- **Un tipeo.** 80 de desperdicio, 8,5 kg/ml, `2.400` en una casilla (11, 20).
- **Se unifica Soldadura.** Baja de un servicio en 25 paquetes y cambio de unidad de otro (16, 37).
- **Constructora duplicada.** Contactos la fusiona y el portal deja de ver Ventanas (45).

### Auditoría (2026-10-14) — resolver de a uno, en orden

Caso base: corrediza 2 hojas 1500 × 1100, negro mate, DVH, 4 iguales. Cada punto: el caso que falla
y una propuesta a discutir, no decidida.

*Cobra mal sin que nadie se entere*

1. ~~**Unidad de las fórmulas.**~~ → *Las fórmulas trabajan en mm* (Paquetes) y unidad del
   servicio.
2. ~~**Insumo o servicio sin costo = $ 0.**~~ → *Sin costo no es $ 0* (Precio de venta).
3. ~~**Unidad del costo.**~~ → *El costo se carga como se cotiza* (Insumos).
4. ~~**Cantidad de aberturas iguales.**~~ → *La cantidad es de la línea* (Paquetes).
5. ~~**Desperdicio.**~~ → *La fórmula dice lo que queda puesto* (Insumos).
6. ~~**La excepción del paquete pisa Vidrios.**~~ → *Servicios por categoría*.
7. ~~**Medidas negativas o cero restan plata.**~~ → *Lo imposible deja la línea sin precio* (Paquetes).
8. ~~**Redondeo en fórmulas.**~~ → *Lo que va por unidad se redondea* (Paquetes) y funciones en
   *El motor va en Postgres*.

*Arma mal (técnico y taller)*

9. ~~**Color.**~~ → *El insumo declara su color*, *El color de herrajes* y *La variante de color
   solo tiene código, nombre y costo* (Paquetes).
10. ~~**El paño solo da el peso.**~~ → *El sistema también pone el peso de cada paño* y *Cada pieza
    de la composición se cobra en su unidad* (Paquetes).
11. ~~**Grupo opcional sin variable.**~~ → *Cada grupo opcional pone `con_<grupo>`* (Paquetes).
12. ~~**Servicios sin condiciones.**~~ → *Un servicio del paquete también puede llevar condiciones*
    (Paquetes).
13. ~~**Ángulo por material.**~~ → *Cada pieza lleva un ángulo por extremo* (Paquetes).
14. ~~**Insumo dado de baja en paquetes.**~~ → *La baja depende de cómo se usa lo que se da de baja*
    (ficha v2).
15. ~~**Cuándo llega una edición al vendedor.**~~ → *Mandar a aprobar frena; aprobar pone a la venta*
    (ficha v2).
16. ~~**Ciclos.**~~ → *Nada depende de sí mismo* (Paquetes).

*Vendedor*

17. ~~**Ancho y alto con default.**~~ → *El default es obligatorio solo en lo secundario* (Paquetes).
18. ~~**El aviso se pierde.**~~ → *El aviso es parte del resultado de la línea* (Paquetes).
19. ~~**Mano de obra % sobre el vidrio.**~~ → *El % de un servicio del paquete no incluye lo que entra
    por un paño* (Servicios).
20. ~~**Extra fuera del paquete.**~~ → *El vendedor no agrega materiales a la composición del
    paquete* (Paquetes).

*Seguridad (para el SQL)*

21. ~~**Montos, % y reglas de servicios en tabla aparte.**~~ → *Monto, %, mínimo… van en tablas
    propias* (El motor va en Postgres).

*Menores*

22. ~~**Peso sin desperdicio.**~~ → *El peso es de lo que queda puesto* (Paquetes, en *El sistema pone
    una variable de peso por grupo*).
23. ~~**"Duplicar grupo" con 3 hojas.**~~ → *"Duplicar grupo" pide qué reemplazar y por qué*
    (Paquetes).
24. ~~**Pieza más larga que la barra.**~~ → *Una pieza más larga que la barra da aviso* (Paquetes).
25. ~~**Volver al automático.**~~ → *Una medida del vendedor puede traer un valor por defecto por
    fórmula* (Paquetes).
26. ~~**Opción que vuelve.**~~ → *Lo elegido se guarda; lo que entra se calcula* (Paquetes).
27. ~~**Panel ciego en el paño.**~~ → *El panel ciego entra por la composición del paño, como el
    vidrio* (Paquetes).
28. ~~**Casos de prueba guardados en Probar.**~~ → *Los casos de prueba corren cuando alguien los
    mira* (ficha v2).
29. ~~**Redondeo del largo de corte.**~~ → *El largo de cada pieza y cada lado de un paño se
    redondean al mm, hacia abajo* (Paquetes).
30. ~~**Filtro por línea de perfiles.**~~ → *En paquetes, la subcategoría es la línea de perfiles*
    (ficha v2).

## Ficha del módulo — v2, desde cero (aprobada 2026-10-21)

Se armó de nuevo, sin partir del borrador anterior, y es la vigente. No se compara punto por punto con
lo anterior (2026-10-20): lo de arriba sigue valiendo salvo donde la v2 dice otra cosa, y lo que choca
se corrige cuando aparece. Lo que la v1 tenía y la v2 no, listado el 2026-10-21, está en *Pendiente*.

```
Módulo: catálogo
Objetivo: definir qué se puede vender y la base de cómputo de su precio — los datos y las fórmulas
          que el presupuestador usa para calcular el precio de cada ítem
Personas
├── Técnico         — insumos, servicios y paquetes, sin plata · crea y edita los tres (la parte
│                     técnica); en paquetes escribe fórmulas y despieces, verifica que funcionen y
│                     los manda a aprobar; ve qué servicios recibe cada paquete por regla, sin el %
│                     · no ve plata
├── Administración  — ve todo, con costos (de Compras); prueba paquetes con medidas y ve el precio ·
│                     aprueba paquetes; crea categorías y colores, carga las variantes de color,
│                     pone montos, % y mínimos
│                     de servicios, marca qué insumo se vende suelto, por presentación o por
│                     unidad; habilita a cada cliente empresa qué ve y si ve precios · —
│                     (los costos los carga Compras, en su módulo)
├── Vendedor        — NO usa el módulo: por el presupuestador elige paquetes aprobados e insumos
│                     sueltos y ve su precio · — · no ve despiece, costo ni servicios
├── Depósito        — NO usa el módulo: en Stock ve cada insumo (nombre, presentación, color) junto
│                     a sus existencias · — · no ve paquetes, fórmulas ni precios
├── Compras         — NO usa el módulo: en Compras ve cada insumo (nombre, unidad, presentación con
│                     su contenido, peso, variantes de color, categoría) con sus existencias de
│                     Stock, y ahí lo costea · — · no ve paquetes, fórmulas, servicios ni precios
├── Producción      — NO usa el módulo: el módulo de producción guarda medidas y configuración y
│                     pide el despiece cuando lo necesita · — · no ve plata ni fórmulas
└── Cliente empresa — NO usa el módulo: por el presupuestador de erp-cliente elige lo que administración
                      le habilitó; ve el precio solo si se lo habilitó · — · no ve despiece, costo ni servicios
Entes
├── paquete — dueño creado_por (solo dato) · estado por versión: borrador · para aprobar · aprobada · lo señalan la línea del presupuesto y la orden de producción
│             · datos {nombre} · ruta /catalogo/paquetes/{id} (abre la vigente) · submódulo catalogo_paquetes · roles {}
└── insumo  — dueño creado_por (solo dato) · sin estado (solo activo), sin versiones · lo señalan la línea del presupuesto (suelto), Compras, Stock y Contactos
              · datos {codigo, nombre} · ruta /catalogo/insumos/{id} · submódulo catalogo_insumos · roles {proveedor}
Relaciones (del catálogo)
├── versión del paquete → insumos y servicios con sus fórmulas — interior del paquete, no puente entre entes
└── empresa cliente (Contactos) → categorías o subcategorías habilitadas + ve precio — configuración, FK a la empresa
Relaciones (de otros módulos, apuntan al catálogo)
├── insumo ← proveedor (Contactos)
├── insumo o su variante de color ← costo (Compras) · existencias (Stock)
├── versión del paquete o insumo suelto (con su variante) ← línea del presupuesto (Presupuestos)
└── versión del paquete ← orden de producción, con medidas y herrajes (Producción)
Acciones
├── paquete: crear · editar borrador · mandar a aprobar (con qué cambió) · volver al borrador · aprobar
│            · rechazar (con motivo) · versión nueva · reemplazar material · probar con medidas
│            · mover de subcategoría · dar de baja · reactivar
│            · casos de prueba: guardar desde Probar (nuevo o pisando uno) · renombrar · marcar
│              referencia · dar de baja
├── insumo: crear (sin color, o de la ventana o de herrajes con su color base) · editar · cargar los
│           servicios que lleva · marcar suelto (por presentación o por unidad) · dar de baja (con
│           reemplazo opcional) · reactivar · cargar variantes de color, en uno o en varios a la vez
│           · dar de baja o reactivar una variante (administración)
├── servicio: crear · editar · poner monto, % y mínimo · dar de baja · reactivar
│             · regla (solo porcentuales): aplicar a todo, o a una categoría o subcategoría de
│               paquetes o de insumos, con su % · cambiar el % · quitarla
│             · excepción: otro % para un paquete · quitarla
│             · categoría de insumos fuera del % de los servicios del paquete: marcar · desmarcar
├── categorías: crear · renombrar · dar de baja (administración)
├── colores: crear · renombrar · dar de baja · reactivar (administración)
└── clientes: habilitar categoría o subcategoría · ve precio sí/no (administración)
Eventos que emite
├── paquete: estado de la versión (para aprobar · vuelta al borrador · rechazada → borrador · aprobada)
│            — aviso a administración y al técnico; la primera aprobada avisa a vendedores del producto nuevo
├── paquete: baja — aviso a vendedores de que sale de venta
├── insumo: baja — aviso al técnico con el alcance: "Marco 70 mm: 3 paquetes incompletos · 9 pierden
│            una alternativa"; con reemplazo, "12 borradores para revisar y mandar a aprobar"
├── insumo: cambian los servicios que lleva — aviso a administración con el alcance: "Manija embutida:
│            suma Mecanizado de embutido en 15 paquetes"
└── servicio: ninguno (no es ente; su baja se ve en los paquetes incompletos)
Eventos que consume
└── ninguno
```

```
Módulo: Catálogo
├── Insumos (vista, catalogo_insumos)            — técnico, administración
│   ├── catalogo_insumos_editar (funcion)        — técnico: crear y editar, con los servicios que lleva
│   └── catalogo_insumos_administrar (funcion)   — administración: ve costos (y el filtro sin costo y en
│                                                  uso), suelto y cómo se vende, categorías, colores y
│                                                  variantes, baja (con reemplazo) y reactivar
├── Servicios (vista, catalogo_servicios)        — técnico, administración
│   ├── catalogo_servicios_editar (funcion)      — técnico: crear y editar
│   └── catalogo_servicios_administrar (funcion) — administración: monto, % y mínimo (y el filtro sin
│                                                  monto), reglas y excepciones por paquete,
│                                                  categorías fuera del % de los servicios del paquete,
│                                                  categorías, baja y reactivar
├── Paquetes (vista, catalogo_paquetes)          — técnico, administración
│   ├── catalogo_paquetes_editar (funcion)       — técnico: borradores, versión nueva, mandar a aprobar,
│   │                                              reemplazar material, volver al borrador, probar sin plata
│   │                                              y guardar casos de prueba
│   └── catalogo_paquetes_administrar (funcion)  — administración: aprobar y rechazar, probar
│                                                  con plata y guardar casos de prueba, categorías, mover,
│                                                  baja y reactivar
└── Clientes (vista, catalogo_clientes)          — administración
    └── catalogo_clientes_habilitar (funcion)    — administración: qué ve cada empresa y si ve precio
Delegables
├── sí — catalogo_insumos · catalogo_insumos_editar · catalogo_servicios · catalogo_servicios_editar
│        · catalogo_paquetes · catalogo_paquetes_editar
└── no — catalogo_insumos_administrar · catalogo_servicios_administrar · catalogo_paquetes_administrar
         · catalogo_clientes · catalogo_clientes_habilitar
Reglas entre permisos: ninguna. _editar y _administrar pueden coexistir en la misma persona.
Permisos de otros módulos que mira el catálogo (cada uno entra con su módulo): Presupuestos y
erp-cliente → precio de la vigente · Producción → despiece de las aprobadas · Stock y Compras →
leer el insumo.
```

Decidido en la v2:

- **El costo sigue fuera del catálogo, en Compras** (como en la v1). Compras lo carga allá
  (*Compras no usa el catálogo*); el catálogo lo lee para calcular. El técnico no ve plata.
- ~~**Hay margen, y lo pone administración.**~~ → *No hay margen* de la v1 (*Servicios*), confirmado al
  comparar (2026-10-14): la ganancia está en los servicios comerciales.
- **Tres vistas: Insumos · Servicios · Paquetes.**
  - *Insumos*: los materiales que se pueden usar o vender. Todo insumo está en una subcategoría; las
    categorías las crea administración. Administración decide si se vende suelto, y si por
    presentación o por unidad del insumo (*El suelto se vende por presentación o por unidad del
    insumo*).
  - *Servicios*: lo no material. Porcentual con monto mínimo, o fijo (corte, manipulación del material).
  - *Paquetes*: donde están las fórmulas, armadas con insumos y servicios. En categorías que crea
    administración (Ventanas → Modena → Corrediza 2 hojas, Corrediza 3 hojas).
- **Categorías en dos niveles fijos, en las tres vistas**: categoría → subcategoría → ítem (Perfiles
  PVC → Marcos → Marco corrediza 70 mm · Ventanas → Modena → Corrediza 2 hojas). Cada ítem está
  en una subcategoría. No se anida más. Servicios también, por decisión del usuario, aunque sean pocos
  (propuesta descartada: lista plana con búsqueda y filtro fijo/porcentual).
- **En paquetes, la subcategoría es la línea de perfiles** (2026-10-19): Ventanas → Modena → Corrediza
  2 hojas, Corrediza 3 hojas; Ventanas → Herrero → Corrediza 2 hojas. La línea sale del nombre. Por qué:
  es lo único que el buscador por nombre no da — habilitar a un cliente empresa solo Modena. Para no
  perder lo que daba la línea en el nombre (v1, *Categorías*): el buscador del vendedor busca también
  en la subcategoría (*modena corr* encuentra) y la línea del presupuesto muestra subcategoría y nombre
  (*Modena · Corrediza 2 hojas*), así una Herrero entre Modenas se ve al revisar. Descartado:
  subcategoría por material (Ventanas → Aluminio) o por tipo (Ventanas → Corredizas) con la línea en el
  nombre — administración no podría habilitar una sola línea.
- **Sin tipo fijo de insumo** (2026-10-20). ~~Cada paño ofrece las subcategorías que marca el
  técnico~~ → *Una opción puede ofrecer subcategorías enteras* (2026-10-21). Lo que hacía el tipo ya
  tiene dueño: cobrar por m² o ml lo dice la unidad del insumo; el % de los servicios del paquete
  deja afuera las categorías que marca administración; el corte por piezas lo decide el técnico al cargar el
  material; la clase de color se elige al crear el insumo, sin default. Por qué: un concepto menos.
  Descartado: el tipo fijo de la v1 (vidrio, cámara, panel, perfil, otro).
- ~~**El técnico crea, administración completa la plata y aprueba — en insumos, servicios y
  paquetes.**~~ → *Solo el paquete se aprueba*.
- **Al presupuestador le sale el precio, nunca el costo ni el despiece.** El vendedor elige entre
  paquetes aprobados e insumos marcados sueltos; lo que esté sin aprobar no aparece.
- **Precio y despiece se habilitan por separado; avisos y plegado van a todos** (2026-10-21). La
  función devuelve cuatro partes: precio, avisos, plegado (*herrajes: negro · manija: plateado
  (no hay en negro)*) y despiece (piezas con largo y ángulos, medida de cada vidrio y por qué entró
  cada material). El vendedor ve precio, avisos y plegado; el cliente empresa, lo mismo, con precio
  solo si se lo habilitaron; el técnico en Probar y producción, todo menos el precio; administración,
  todo. Un aviso va tal cual aunque nombre una pieza (*Travesaño marco 6500 mm: más largo que la
  barra de 6000 mm*): el vendedor lo necesita para cotizar barra especial o empalme, y un largo
  suelto no muestra las fórmulas. Qué permiso habilita cada parte: *La función de cálculo decide
  qué parte ve cada uno*. Por qué: *El motor va en Postgres* daba el despiece a quien ve precios, y
  el vendedor ve precio sin despiece y producción despiece sin precio. Descartado: un texto sin la
  pieza para vendedor y cliente (cada aviso del sistema escrito dos veces).
- **El despiece no se guarda: se calcula cuando se pide.** Quien lo usa guarda solo las entradas
  (paquete, ancho, alto, configuración de herrajes) y pide el despiece al catálogo. Una sola función del
  catálogo evalúa las fórmulas: la llaman producción, el presupuestador (para el precio) y la prueba del
  técnico. Si cada módulo evaluara por su cuenta, la regla viviría en dos lugares.
- **Consecuencia: una fórmula aprobada no se edita.** Si el despiece se recalcula cuando se pide, cambiar
  `ancho − 6` por `ancho − 8` después de vendida cambiaría la ventana vendida. Editar crea una versión
  nueva, y lo guardado apunta a la versión (*Estados*).
- **Cada cliente empresa ve lo que administración le habilita, y el precio es opcional por cliente.**
  Nace sin nada habilitado. Se habilita por categoría o subcategoría, no por ítem: lo que se aprueba
  después en una subcategoría habilitada lo ve solo (una categoría incluye sus subcategorías futuras).
  De los insumos ve solo los sueltos. Ve lo mismo que el vendedor: nunca despiece, costo ni servicios. Sin
  precio, el cliente arma el pedido con medidas y el precio lo pone el vendedor. Descartado: marcar ítem
  por ítem (cada producto nuevo obliga a tocar cada cliente).
- **Dos entes: paquete e insumo.** Son lo que otro módulo señala. El servicio no es ente: nadie de afuera
  lo elige, lo suma la función de precio. La versión es parte del paquete (lo guardado apunta a la versión,
  el chip muestra el paquete); categorías y habilitaciones de clientes son configuración.
- **Lo que no está en el catálogo es un renglón libre del presupuesto** (flete, algo que no vale la pena
  cargar): descripción y monto a mano. No sale de servicios.
- **El catálogo es compartido: no nace privado.** Todo técnico ve y edita los borradores de cualquier
  otro; quien tiene la vista ve todo lo de esa vista. `creado_por` es un dato, no da visibilidad.
  Excepción a *Todo ente nace privado* (`GUIDE_ENTES.md` §2.4): el catálogo es de la empresa y entre
  técnicos no hay competencia que proteger. Descartado: borrador privado hasta mandarlo a aprobar
  (suma compartir y transferir sin necesidad).
- **El estado es de cada versión del paquete: borrador · para aprobar · aprobada.** La vigente (última
  aprobada) se calcula, no se guarda. Mientras v2 está en borrador o en revisión se sigue vendiendo v1.
  Rechazar vuelve a borrador con motivo obligatorio. Dar de baja el paquete lo saca de la venta; lo que
  apunta a una versión (lo enviado, las órdenes) se sigue calculando. Pedirle la vigente a un paquete
  que no está a la venta (de baja o incompleto) da sin precio (*Corrediza 2 hojas: no está a la
  venta*), sin decir cuál de las dos; qué hace la línea con eso es de Presupuestos (2026-10-21).
- ~~**Un borrador puede usar insumos y servicios sin aprobar, pero no se manda a aprobar hasta que todos
  lo estén.**~~ → *Solo el paquete se aprueba*.
- **Producción puede elegir con qué versión aprobada fabrica**, no solo con la que se vendió. El catálogo
  le ofrece solo las versiones aprobadas del paquete y calcula el despiece de la que elija. Cambiar de
  versión cambia los materiales, no el precio: el precio es del presupuesto. Por eso cada versión dice qué
  cambió, obligatorio al mandarla a aprobar ("v2: agrega burlete inferior en la hoja").
- **El insumo no se versiona: una corrección se edita en el mismo insumo.** Las fórmulas leen el peso,
  así que corregirlo recalcula las órdenes viejas — y eso se quiere: el dato viejo estaba mal. Antes de
  guardar, quien corrige ve a cuántos paquetes y órdenes abiertas toca. **Un producto distinto es un insumo
  nuevo** (alta del nuevo, baja del viejo, versión nueva de los paquetes). Por qué no inmutable: corregir
  un perfil usado en 15 paquetes obligaba a 15 versiones y a mudar costo, stock y proveedor, para un dato
  que casi nunca cambia. El paquete sí se versiona porque cambiar una fórmula es diseño, no corrección.
- **La unidad del insumo queda fija desde que entra en un paquete o se vende suelto** (2026-10-21).
  Antes se corrige libre (el error de carga recién hecho). Desde que está en alguna versión de un
  paquete, borradores incluidos, o marcado suelto, no se edita y el campo dice por qué (*Felpa 7×5:
  en 20 paquetes · para otra unidad, insumo nuevo*); Compras y Stock suman su condición (costo o
  existencias cargados) al construirse. Otra unidad es un producto distinto: insumo nuevo y baja del
  viejo, y en cada borrador el control de unidad marca las fórmulas a corregir (*Cada variable
  declara su unidad*). Por qué: el insumo no se versiona, así que pasar la felpa de ml a unidad
  hacía que las 20 vigentes, ya aprobadas, calcularan 5.980 felpas en vez de 5,98 ml, y las órdenes
  viejas el mismo despiece; la presentación y el costo quedaban en la unidad anterior. Descartado:
  permitirlo mostrando el alcance — cambia precio y despiece de versiones aprobadas sin revisión.
- **El servicio se edita directo, como el insumo.** No está en el despiece: corregirlo cambia precios, no
  órdenes.
- **Los cambios de plata de administración rigen al instante, sin aprobación**: montos, %, mínimos,
  suelto y cómo se vende. El catálogo calcula siempre con los valores de hoy; cuándo se
  congela el precio de un presupuesto lo decide Presupuestos. Cada cambio queda registrado (quién,
  cuándo, valor anterior y nuevo).
- **El suelto se vende por presentación o por unidad del insumo; lo elige administración**
  (2026-10-21). Al marcar un insumo como suelto elige una de las dos, obligatoria y sin default:
  *Marco corrediza 70 mm* por presentación (2 barras = 12 ml × costo); *Float 4 mm* por unidad del
  insumo (1,4 m² cortado), y el *Burlete* de rollo también (15 ml). La unidad del insumo sigue siendo
  del técnico y esto no la cambia: de ella dependen las fórmulas y la conversión del costo. En los
  dos casos va sin desperdicio (el Float cortado se cobra por el m² real, como en el paquete). El
  cambio rige al instante, pero la línea sin enviar no se convierte: queda sin precio con el motivo
  (*Marco corrediza 70 mm: ahora se vende por ml, revisá la cantidad*), como con el color o la baja;
  lo enviado no cambia. Por qué: con la unidad libre de la v2 (m², ml, unidad o kg), pasar el marco
  de ml a kg rompía las fórmulas de sus paquetes, y la presentación entera de la v1 no sirve para el
  vidrio cortado. El kg no es unidad de venta: el perfil cotizado por kg se lleva en barras.
  Descartado: convertir la cantidad de la línea (de ml a barras no da exacto: 7 ml = 1,17 barras, y
  redondear cotiza otra cosa sin avisar).
- **El catálogo no apunta con FK a otro módulo salvo la empresa cliente**: solo es dueño del interior de
  los paquetes y de las habilitaciones de clientes. Los demás le apuntan. ~~Se puede construir antes que
  Compras~~ (2026-10-21): para el precio lee costo y cotización de Compras —probar con plata, *sin
  costo*, los costos en Insumos—. El SQL va en tres partes: catálogo sin plata (insumos, servicios,
  paquetes, versiones, fórmulas, despiece, controles, probar sin precio), Compras mínimo (su ficha,
  costo y cotización) y la rama de plata de la función de cálculo. Stock y Producción, después.
  Descartado: crear las tablas de Compras en el SQL del catálogo (tablas de un módulo sin ficha).
- **Solo el paquete se aprueba** (revertido para insumo y servicio, 2026-10-14). El técnico crea y edita
  insumos y servicios sin aprobación; administración completa la plata. Insumo y servicio no tienen
  estado, solo `activo`. El freno queda donde importa: un insumo nuevo no se vende suelto hasta que
  administración lo marca, y un paquete que lo usa no llega al vendedor hasta que administración lo
  aprueba probándolo con plata — ahí ve si falta un costo o un monto. Descartado: el mismo circuito de
  aprobación en las tres vistas (trabajo doble para administración sobre datos que el paquete ya revisa).
- **Dar de baja es de administración, en las tres vistas**: dejar de vender es una decisión comercial.
  El técnico puede pedirlo, no hacerlo.
- **La subcategoría la elige el técnico al crear; administración puede moverla después.**
- ~~**Dar de baja un insumo o un servicio deja "incompletos" los paquetes que lo usan: dejan de
  venderse.**~~ → *La baja depende de cómo se usa lo que se da de baja* (2026-10-21).
- **La baja depende de cómo se usa lo que se da de baja** (2026-10-21). *Incompleto* es uno de los
  casos: el paquete deja de venderse; se calcula (la vigente usa algo dado de baja), no se guarda; en
  el catálogo dice *falta reemplazar: Marco corrediza 70 mm*, y el vendedor y el cliente no lo ven.
  - Insumo como material fijo o condicional → incompleto.
  - Como alternativa, suelta o por subcategoría → solo ella deja de ofrecerse, y la línea sin enviar
    que la tenía elegida queda sin precio (*Lo que el catálogo deja de ofrecer deja la línea sin
    precio*); si era la última de la opción, incompleto, salvo *Sin material*.
  - Variante de la ventana → en un material fijo o condicional, ese color no se ofrece; en una
    alternativa, ella no se ofrece en ese color (*Las alternativas se filtran por color*); variante
    de herrajes → color base con aviso.
  - Servicio cargado en el paquete, fijo o condicional (Soldadura × 4, mano de obra extra si `alto` >
    2400) → incompleto.
  - Servicio aplicado por regla (general, categoría, subcategoría, excepción) o que trae un insumo
    (2026-10-21) → nada queda incompleto: deja de cobrarse al instante en todo lo que alcanzaba (la
    Modena de $ 600.000 pasa a $ 460.000 sin Comercialización; la Manija embutida entra sin
    Mecanizado de embutido). Sus reglas y los insumos que lo traen no se borran: reactivarlo vuelve a
    cobrar con los mismos.

  Reactivar devuelve a la venta lo que quedó incompleto por esa baja. Lo enviado no cambia y las
  órdenes siguen calculando el despiece de su versión. Por qué: lo que ya no se consigue no se cotiza,
  pero con *incompleto* para todo la baja de la Manija embutida sacaba de venta 15 corredizas que se
  venden con manija; y la regla de un servicio no está en la versión del paquete. Descartado: frenar la
  baja de un servicio con reglas activas (un freno más, y la confirmación ya muestra el alcance); y
  seguir vendiendo un paquete incompleto con aviso, salvo con el reemplazo en curso (*La baja de un
  insumo puede designar su reemplazo*).
- **Toda baja de algo en uso muestra el alcance antes de confirmar** (2026-10-21), deje o no algo
  incompleto: *Manija embutida: 3 paquetes dejan de venderse · 15 pierden una alternativa · 2 quedan
  solo con Sin herraje*; *Comercialización: se deja de cobrar en 120 paquetes y 40 insumos sueltos*.
  La baja no se frena. La de un insumo avisa al técnico con las mismas cifras y deja los paquetes
  marcados; la de un servicio no avisa (no es ente y no emite): el técnico ve marcados los incompletos.
- **Una opción puede tener "Sin material"** (2026-10-21): una alternativa sin insumo (*Sin herraje*)
  que nunca se da de baja. Si se dan de baja todas las alternativas con material, la opción ofrece solo
  esa y el paquete se sigue vendiendo, con aviso al técnico (*Corrediza 2 hojas: herraje hoja izq solo
  ofrece Sin herraje*); sin ella, queda incompleto (Puerta rebatible sin cerradura). Como toda
  alternativa puede llevar condiciones y poner variables, pero **con condición no salva al paquete**:
  si en alguna combinación no queda nada que ofrecer, incompleto (sin Floats, con cámara el *Vidrio
  interior* no tiene qué ofrecer). Por qué: es lo que pasa con un material condicional dado de baja, y así un paquete no se
  vende con unas opciones sí y con otras no.
- **La baja de un insumo puede designar su reemplazo, y lo reciben todos los paquetes que lo usan**
  (2026-10-21). Opcional (sin reemplazo rige *La baja depende de cómo se usa*) y de cualquier unidad;
  lo elige administración, que da la baja. Cada paquete lo recibe en su versión abierta, como con
  *"Reemplazar material"*, con el qué cambió escrito (*reemplaza Hoja corrediza 40 mm por Hoja
  corrediza 42 mm (baja)*); el técnico revisa, corrige fórmulas —o en ese paquete pone otro— y manda a
  aprobar. Antes de confirmar se ve el alcance (*Hoja 40 → Hoja 42: 12 paquetes la reciben en su
  borrador*; con otra unidad, *las 12 fórmulas se corrigen a mano antes de mandar*).
  ~~De la misma unidad~~ (2026-10-21): la felpa que pasa de ml a unidad no tenía salida y sus 20
  paquetes quedaban incompletos al instante; el control de unidad ya frena cada borrador hasta
  corregir la fórmula. ~~Abre "Reemplazar material" con los paquetes a desmarcar~~ (2026-10-21):
  Laura, sin `catalogo_paquetes_editar`, decidía qué paquete salía de venta; qué se compra es de
  administración, cómo entra en cada paquete es del técnico. **No se aprueba solo**: lo que hay que corregir no se ve en las diferencias
  de los casos (HOJ-42 con 2 mm más de solape pide `+ 27` en `ancho_hoja_izq`; sin tocar la fórmula
  las piezas no cambian, y administración aprobaría hojas cortas). **Mientras la versión abierta tiene
  el reemplazo, la vigente se vende como si el viejo siguiera activo**, venga de la baja o de
  *"Reemplazar material"*. Lo vendido sobre la vigente se fabrica con la nueva (*Producción puede
  elegir con qué versión aprobada fabrica*); hasta aprobar se cotiza con el costo del viejo. Lo que el
  reemplazo cambia solo (más peso → rueda doble, un color que no tiene) se ve en los casos de prueba al
  mandar a aprobar y en pendientes. Descartado: aprobar las versiones al confirmar la baja (sin revisión
  técnica) y que dejen de venderse hasta aprobar (se pierden ventas en el medio).
- ~~**El técnico reemplaza por material o por paquete.**~~ → *"Reemplazar material" es un solo botón
  de Paquetes* (2026-10-21).
- **Administración aprueba varias versiones juntas con checkbox, viendo qué cambió de verdad.** Cada fila
  muestra el texto del técnico (el porqué), los cambios que detecta el sistema entre versiones (*Cuenta
  como cambio todo lo que está en la versión*) y el precio antes y después en el caso de referencia del
  paquete (*Los casos de prueba corren cuando alguien los mira*). El texto solo no alcanza: dice lo
  que el técnico cree que cambió.
- **Mandar a aprobar frena; aprobar pone a la venta** (2026-10-21). Reemplaza a "Publicar" de la v1.
  El borrador se guarda a medias y Probar lo usa. Al mandar a aprobar corren los controles (fórmula
  mal escrita, ciclo, secundaria sin default, medida principal con default, unidad que no coincide, hermanas que no ofrecen lo mismo o con defaults que no son par, espesor que falta en
  una alternativa): si falla uno, no se manda. Donde la v1 dice "no se publica", se lee "no se manda a aprobar". Recién al
  aprobar, la versión pasa a ser la vigente y la ve el vendedor. Un presupuesto sin enviar sigue a la
  vigente, con aviso en la línea que suma el texto del técnico (*el paquete cambió: v3 → v4 · agrega
  burlete inferior en la hoja*); al enviar, se congela. Por qué: con aprobación, mandar no puede
  cambiar lo que se vende. Descartado: que la línea quede en la versión vieja hasta actualizarla a
  mano (v1). Diagrama: https://claude.ai/artifact/BLhKnFktuJWyEpHGQedVoa
- **Lo que está para aprobar no se edita: el técnico lo vuelve al borrador** (2026-10-21). "Volver al
  borrador" saca la versión de la revisión sin perder nada y sigue siendo la misma (v4, no v5: nunca
  se aprobó). Se corrige y se vuelve a mandar: corren otra vez los controles y el texto de qué cambió
  se puede ajustar. Administración deja de verla en pendientes y recibe aviso; el vendedor sigue con
  la vigente. Por qué: lo que administración revisa no cambia mientras lo revisa. Descartado: el
  nombre "Revertir" (se lee como volver a la versión anterior o deshacer los cambios).
- **Los casos de prueba corren cuando alguien los mira; uno es el de referencia** (2026-10-21).
  Reemplaza a los casos que corría "Publicar" en la v1. Un caso es lo que carga el vendedor (medidas,
  opciones, color), con nombre; se guarda desde Probar y se carga con un clic.
  Uno se marca *referencia* (reemplaza a la medida de referencia): sin él no se manda a aprobar. El
  resultado no se guarda, como el despiece. Al mandar a aprobar, el técnico ve las diferencias de
  cada caso contra la vigente, sin precios (materiales que entran o salen, piezas, cantidades, avisos:
  *"Grande 3000 × 1800": rueda simple → doble (hoja der) · Travesaño hoja der 1460 → 1510 mm*), y
  confirma. Administración, en pendientes, ve las mismas con precio antes y después; la fila muestra
  el del caso de referencia. En la primera versión no hay antes: cada caso con su despiece y precio.
  Una opción que ya no existe sigue *Lo elegido se guarda* y se marca. Por qué: cargar a mano 4 casos
  de 8 campos en cada edición termina en probar uno, y lo roto lo encuentra el vendedor; medida de
  referencia y caso eran dos conceptos para lo mismo. Descartado: resultado esperado por caso (habría
  que cargar el despiece entero a mano).
- **Los casos de prueba son del paquete, no de la versión, y los guarda quien prueba** (2026-10-21).
  La Corrediza 2 hojas tiene *Referencia 1500 × 1100*, *Grande 3000 × 1800* y *Chica 600 × 600 con
  mosquitero*: el técnico los encuentra en la v5 y, al mandarla a aprobar, cada uno corre en la v4 y
  en la v5. Los guardan desde Probar el técnico (`catalogo_paquetes_editar`) y administración
  (`catalogo_paquetes_administrar`), que suma el *Balcón 2400 × 2200* que vio en un presupuesto: un
  caso no tiene plata. Si se da de baja la referencia, no se manda a aprobar hasta marcar otra. Se
  tocan aunque haya una versión para aprobar, porque no son parte de lo que se aprueba: si cambia la
  referencia, a administración le cambian las cifras que mira. Por qué: comparar pide correr el mismo
  caso en dos versiones; siendo de la versión, la v5 copiaría los de la v4 y uno nuevo no tendría
  contra qué compararse. Descartado: congelarlos mientras haya una versión para aprobar.
- **Cada paquete tiene como mucho una versión abierta (borrador o para aprobar)** (2026-10-21).
  Mientras haya una, "versión nueva" no crea otra: muestra la abierta (*v4 · Marcos · agrega burlete
  inferior en la hoja*). Si está en borrador, cualquier técnico la edita y suma su cambio al texto;
  si está para aprobar, la vuelve al borrador o espera. Por qué: con dos borradores que parten de la
  v3, aprobar la v4 (burlete) y después la v5 (rueda doble) deja vigente una versión sin el burlete, y
  nadie lo nota. Descartado: borradores en paralelo (obliga a combinarlos).
- **El paquete muestra su historial versión por versión, como apoyo del técnico** (2026-10-21). Cada
  versión dice qué cambió respecto de la anterior: el texto del técnico, los cambios que detecta el
  sistema (los de pendientes, sin precio) y su recorrido en una línea (*v5 · baja el umbral de rueda
  doble a 35 kg · `rueda_hoja_izq`: `peso > 40` → `peso > 35` · mandada 12/09 (Marcos) → rechazada
  13/09 (Laura: falta probar el caso grande) → mandada 15/09 → aprobada 15/09 (Laura)*). La abierta
  encabeza la lista con lo que lleva cambiado. Lo ven técnico y administración con la vista Paquetes.
  No se guarda una copia: los cambios se calculan desde las versiones, que no cambian al aprobarse, y
  cada una parte de la anterior (*una versión abierta por paquete*); el recorrido sale de los eventos
  de estado, con el motivo del rechazo. Por qué: le explica al técnico por qué el paquete es como es
  (la orden de la v3 que hoy saldría con rueda doble) sin depender de que el texto lo diga todo.
  Descartado: comparar dos versiones cualquiera (v3 contra v6 se lee de v4 a v6) y precio en el
  historial (la plata se mira al aprobar).
- **Cuenta como cambio todo lo que está en la versión** (2026-10-21): variables (medidas del vendedor,
  calculadas, opciones con sus alternativas), grupos, materiales (cantidad o fórmula, condición,
  piezas con largo y ángulos, si suma al peso), servicios con su cantidad y restricciones. Se muestra por pestaña, solo lo
  que cambió, con antes → después (*Restricciones: ancho máx. 2400 mm · frena → avisa*). No entra lo
  que no es de la versión: nombre y subcategoría del paquete, casos de prueba, reglas y excepciones de
  servicios, datos del insumo, plata. Es una sola comparación para el historial y para pendientes, y
  sin plata: técnico y administración ven lo mismo. Por qué: la v5 de la Corrediza económica decía
  *baja el umbral de rueda doble a 35 kg* y en el mismo borrador la restricción de ancho pasó a
  avisar; con solo insumos y fórmulas se aprobaba sin verla y se vendía lo que la línea no soporta.
  Descartado: solo lo que cambia el resultado de los casos (frena → avisa no cambia un caso dentro
  del límite).
- **"Reemplazar material" es un solo botón de Paquetes: masivo, con los paquetes a elegir, y cada
  borrador se ajusta después a mano** (2026-10-21). Dos buscadores (material actual y nuevo) y la
  tabla de los paquetes que usan el actual, todos marcados: el técnico desmarca los que no quiere
  tocar y ve qué pasa en cada uno antes de confirmar. El nuevo puede ser de otra unidad (*La baja de
  un insumo puede designar su reemplazo*). Sin versión abierta, crea un borrador; con
  borrador, se suma a él; para aprobar, vuelve al borrador y se suma (aviso a administración). Si la
  versión abierta ya no usa el material, dice *ya no lo usa* y no se toca. El qué cambió va escrito
  (*reemplaza Marco corrediza 70 mm por Marco 72 mm*) y se suma al que hubiera. Lo que el material
  nuevo obliga a cambiar en un paquete (una fórmula) se corrige en su borrador; después cada uno se
  manda a aprobar. El aviso de baja (*falta reemplazar: Marco corrediza 70 mm*) abre la misma ventana
  con el material actual cargado; la baja con reemplazo no la abre: lo pone en todos (*La baja de un
  insumo puede designar su reemplazo*). Por qué: con una versión abierta por paquete, el reemplazo no puede
  crear otra. Descartado: saltear los que están para aprobar y avisar (queda a mano y, con la baja,
  el paquete queda incompleto).
- **El producto nuevo se avisa al aprobarse la primera versión, no en el alta.** El alta ocurre cuando el
  técnico abre el borrador: avisar ahí a los vendedores sería avisar de algo que no se vende. "Incompleto"
  no emite (se calcula); lo que lo causa sí: la baja del insumo.
- **La plata va atada a las funciones `_administrar`**: sin una, esa vista no muestra costos, montos
  ni precios. El técnico, con la vista y `_editar`, nunca ve plata.
- **`_editar` y `_administrar` pueden coexistir**: en una empresa chica la misma persona es técnico y
  administración. Descartado: excluirlas para que nadie apruebe su propio paquete (obliga a dos personas).
- **Depósito no usa el catálogo: ve el insumo desde Stock** (2026-10-21). Para contar y guardar 20
  barras de Marco 70 mm negro mate le alcanza con nombre, presentación y color, y siempre los mira
  junto a las existencias. Corrige la v1, que le daba la vista Insumos: esa vista es para crear y
  editar, y suma desperdicio, peso y dónde se usa, que no necesita. Con qué permiso Stock lee el
  insumo: *Stock y Compras leen la tabla del insumo*.
- **Compras no usa el catálogo: ve el insumo desde Compras, con sus existencias de Stock, y ahí lo
  costea** (2026-10-21). Para cargar *Marco corrediza 70 mm negro mate: $ 32.000 / barra* o
  *Perfiles PVC +8 %* le alcanza con nombre, unidad, presentación con su contenido, peso, variantes
  de color y categoría; paquetes, fórmulas, servicios y precio no los necesita. Vuelve la persona de
  la v1, que la v2 había juntado con administración, y coincide con Compras en Contactos (equipo
  propio). Administración sigue viendo costos en el catálogo; si la misma persona compra y
  administra, tiene los dos permisos. Por qué: juntas, quien solo compra quedaba como
  administración, y con `_administrar` daba de baja, marcaba suelto, aprobaba y veía el % de los
  servicios. Con qué permiso Compras lee el insumo: *Stock y Compras leen la tabla del insumo*.
- **Lo que falta costear se ve en filtros, y lo que entra sin plata se marca al aprobar**
  (2026-10-21). En Compras, la lista *sin costo y en uso*, con dónde se usa cada insumo (*Rueda
  doble — 3 paquetes: Corrediza 2 hojas, Corrediza 3 hojas, Puerta corrediza*; *Burlete 9 mm gris
  — 1 paquete · se vende suelto*). En uso es lo que se vende hoy: la vigente de un paquete activo o el
  insumo suelto. El dónde se usa lo da una función del catálogo, la misma del alcance de la baja, y
  Compras la lee. Administración tiene el mismo filtro en Insumos (`catalogo_insumos_administrar`,
  que ya ve costos) y *sin monto* en Servicios (`catalogo_servicios_administrar`: *Mecanizado de
  embutido · sin monto · 3 paquetes*); el técnico no ve ninguno. En pendientes se marca lo que entra
  sin plata (*entra Rueda doble (sin costo) · Mecanizado de embutido (sin monto)*), sin frenar
  la aprobación: el freno es la línea sin precio, que no se envía. Por qué: con el caso de referencia
  en hojas livianas, la v4 se aprobaba con precio normal y el faltante lo encontraba el vendedor dos
  semanas después. Son filtros de vistas que ya existen: ni vista ni función nueva.
- **Un insumo puede traer sus servicios, y entran con él en todo paquete** (2026-10-21). En la
  *Manija embutida* el técnico carga una vez *lleva Mecanizado de embutido × 1 por unidad*: donde la
  manija entra, entra el mecanizado, en su mismo grupo, y el despiece dice por qué (*Mecanizado de
  embutido — por Manija embutida (hoja izq)*). Si el vendedor elige otra manija, no entra. La
  cantidad es la puesta del insumo, sin desperdicio (5,98 ml de burlete → 5,98 ml de *Colocación de
  burlete*). Solo servicios fijos: el % por insumo ya es la regla por categoría. Solo en paquetes: la
  manija vendida suelta no lo lleva. Sin excepción por paquete: si en una puerta viene mecanizada de
  fábrica, es otro insumo. El técnico no ve el monto. Como el insumo no se versiona, rige al instante
  en las vigentes: antes de guardar se ve el alcance (*Manija embutida: suma Mecanizado de embutido
  en 15 paquetes · en 3 ya está cargado a mano: se cobraría dos veces*) y administración recibe aviso.
  Por qué: "la manija lleva mecanizado" es un dato de la manija; con `embutido_izq` y la condición se
  cargaba en cada hoja de cada paquete, y el olvido en uno lo vendía sin mecanizar con un precio que
  parecía normal. Descartado: que entre solo en versiones nuevas (cada versión guardaría qué servicios
  traía cada insumo: el dato repetido otra vez). La baja de un servicio que trae un insumo no deja
  nada incompleto: deja de cobrarse, como el de una regla, que tampoco está en la versión del paquete
  (*La baja depende de cómo se usa lo que se da de baja*).
- **La función de cálculo decide qué parte ve cada uno y qué versiones calcula, también fuera del
  catálogo** (2026-10-21). Mira los permisos del catálogo y los de los módulos que la llaman; cada
  uno suma su rama al construirse, como las de `entes`, y hoy existen las dos del catálogo. Con dos
  permisos se suman partes y versiones; sin ninguno, error.
  - `catalogo_paquetes_editar` (técnico, en Probar) → avisos, plegado y despiece de cualquier
    versión, borradores incluidos.
  - `catalogo_paquetes_administrar` → todo, de cualquier versión.
  - Vendedor, con el permiso de Presupuestos que arma líneas (se nombra al fichar Presupuestos) →
    precio, avisos y plegado, solo de la vigente de un paquete a la venta.
  - Producción, con su permiso de órdenes (al fichar Producción) → avisos, plegado y despiece de
    cualquier versión aprobada, aunque el paquete esté de baja.
  - Cliente empresa, por su empresa (al fichar erp-cliente) → avisos y plegado de la vigente en lo
    que tiene habilitado, y el precio si se lo habilitaron.

  Con la Corrediza 2 hojas (v3 aprobada, v4 vigente, v5 en borrador): el vendedor pide 1500 × 1100
  sobre la v4 y recibe $ 600.000, avisos y plegado, sin despiece; la v5 por API le da error.
  Producción pide la orden hecha con la v3: despiece y avisos, sin precio. El técnico prueba la v5:
  todo menos el precio. El mismo permiso le abre al vendedor y al cliente lo que eligen —lo que está
  a la venta y las opciones de cada paquete (medidas, alternativas, colores)— por funciones
  del catálogo, sin fórmulas; nunca las tablas. Por qué: qué versión calcula cada uno sale de reglas
  del catálogo (vigente, a la venta, incompleto, habilitación); si cada módulo envolviera la función
  con su permiso, Presupuestos tendría que saber qué está a la venta y la regla quedaría en dos
  lugares. La lista la escribe una vez el módulo del ente (`decisiones/global/entes.md` → *Ver un
  registro no es trabajarlo*). Descartado: una vista del catálogo para el vendedor (le aparece un
  módulo que no usa, y no hay función sin vista).
- **Stock y Compras leen la tabla del insumo del catálogo; lo suyo va en tablas propias con FK**
  (2026-10-21). Hay una sola tabla de insumos. Compras guarda el costo (`insumo_id` → $ 32.000 /
  barra) y Stock las existencias (`insumo_id` + negro mate → 20 barras), sin copiar nombre,
  presentación ni color. La policy de lectura del insumo, de sus variantes de color y de las
  categorías suma la vista de Stock y la de Compras, cada una al construirse su módulo. Leen la fila
  entera, desperdicio y peso incluidos: no tiene plata (el costo está en Compras; montos y % en
  tablas propias). Paquetes, fórmulas y servicios están en tablas que piden las vistas del catálogo:
  depósito pide los paquetes por API y recibe 0 filas. El *dónde se usa* de *sin costo y en uso* es
  la función del catálogo, con la rama de Compras. **Todo lo que Compras compra y Stock cuenta es un
  insumo del catálogo, y el alta es del técnico**: no manejan nada que no vaya a un paquete o se
  venda suelto (confirmado por el usuario). Por qué: con copias, corregir el peso en el catálogo deja
  viejas las otras; con costo o existencias en la fila del insumo, el técnico los leería (RLS filtra
  filas, no columnas). Descartado: una función que devuelva solo las columnas de cada uno (segunda
  puerta a la tabla para ocultar datos que no son sensibles) y una tabla de insumos común, sin dueño
  (el alta igual es del técnico, y suma un módulo).
- ~~**El técnico agrega un color al insumo; darlo de baja o reactivarlo es de administración**~~ →
  *Los colores son de administración: la lista y las variantes de cada insumo* (2026-10-21).
- **Los colores son de administración: la lista y las variantes de cada insumo** (2026-10-21).
  - *Lista de colores*: una sola, para la ventana y los herrajes (Natural · Negro mate · Blanco ·
    Bronce), así "como la ventana" encuentra el mismo color. El nombre no se repite aunque cambien
    mayúsculas o acentos (índice único parcial `WHERE activo`): "Negro Mate" no entra al lado de
    "Negro mate". Administración la crea, renombra, da de baja y reactiva; renombrar no rompe nada.
  - *Variante*: código y color de la lista, sin nombre propio (el texto lo pone el color). La carga
    administración (`catalogo_insumos_administrar`), en uno o en varios insumos a la vez: para la
    Modena en bronce marca los 16 insumos, elige *Bronce*, escribe una vez el sufijo `-BZ` y ve la
    tabla con el código propuesto de cada uno (ART-2410-BZ), corregible fila por fila; se saltean
    los que ya lo tienen y los sin color. Todo o nada, en una función de Postgres: un código que
    choca se marca en la tabla antes de confirmar. El alcance se ve una vez para toda la carga
    (*Bronce: Corrediza 2 hojas y Corrediza 3 hojas se ofrecen en bronce · 15 variantes sin costo*).
  - El paquete no guarda sus colores: ofrece cada color que tienen todos sus insumos *de la
    ventana*. Cargar la variante es decidir venderlo, y el alcance de la carga lo muestra antes de
    confirmar; colores excluidos por paquete, recién con un caso real (un perfil compartido que
    pone en bronce una línea que no se vende así).
  - Vale al instante, porque el insumo no se versiona: si era el único insumo *de la ventana* sin
    ese color, el paquete pasa a ofrecerlo sin aprobación. Sin costo, la línea sale sin precio y
    Compras lo ve en *sin costo y en uso*. Dar de baja un color en un insumo sigue *La baja depende
    de cómo se usa lo que se da de baja*; en la lista, es darlo de baja en todos los insumos.
  - El técnico no crea colores ni carga variantes, pero al crear el insumo elige si es *sin color*
    (felpa) o, si es *de la ventana* o *de herrajes*, su color base de la lista, obligatorio: el
    Marco corrediza 80 mm (ART-2420) es natural; la manija, plateada. Si el color no está en la
    lista, se lo pide a administración. El insumo sale solo en su color base hasta que
    administración le cargue los demás. Por qué: el código ya es ese color, como el peso es dato del
    insumo; sin color base, el paquete que lo usa no se ofrece en ningún color y el técnico no puede
    ni probarlo.
  - El costo de cada color, las existencias por color y la línea suelta en un color apuntan al
    insumo o a su variante; el proveedor, al insumo.

  Por qué: en qué colores se vende cada cosa lo decide administración, y el técnico los cargaba por
  pedido suyo hecho por fuera del sistema; con todo en administración no hace falta aviso. La lista
  evita que un "Negro Mate" de más saque el negro mate de un paquete sin que nadie se entere.
  Descartado: que el técnico cargue las variantes con aviso a administración (el primer planteo).
- **El peso es del insumo y condiciona herrajes; la abertura no da peso** (2026-10-21). El técnico
  lo carga al dar de alta el insumo (Marco corrediza 70 mm: 0,85 kg/ml; Float 4 mm: 10 kg/m²) y
  sirve para dos cosas: las variables de peso de los grupos, con las que entra la rueda doble si
  `peso_hoja_izq` > 40 kg, y el costo que Compras cotiza por kg ($ 8.000 / kg × 0,85 kg/ml =
  $ 6.800 / ml). El peso de la abertura entera, que la v1 sumaba para logística, sale: nadie lo
  recibía. "Suma al peso" sigue, para que la rueda no dependa de sí misma. Si el flete o logística
  lo piden, la función lo suma de los grupos y entra como una parte más con su rama: no falta
  ningún dato.
- **Paquete e insumo se registran con su vista; para quien solo compra, el insumo no es ente**
  (2026-10-21). Paquete: datos `{nombre}`, ruta `/catalogo/paquetes/{id}` (abre la vigente),
  submódulo `catalogo_paquetes`, sin roles; chip *Modena · Corrediza 2 hojas*. Insumo: datos
  `{codigo, nombre}` (depósito y Compras hablan por código), ruta `/catalogo/insumos/{id}`, submódulo
  `catalogo_insumos`, roles `{proveedor}`; chip *ART-2410 · Marco 70 mm*. Como el ente existe solo
  para quien tiene su vista (RLS de `entes`), quien solo compra no ve en *Aluar* el chip *proveedor
  de: ART-2410 · Marco 70 mm* ni encuentra el insumo en el buscador de Contactos: lo vincula desde
  Compras. El rol lo valida un trigger `DEFINER` que lee `entes` igual, y quién vincula lo dice la
  rama del catálogo en `trabaja_registro`, a la que Compras suma su permiso. Vendedor y producción
  tampoco ven el chip del paquete: la línea muestra lo que da la función de cálculo. Por qué: chip y
  buscador para Compras piden que `entes.submodulo` acepte varias vistas y una ruta según quién mira,
  un cambio de core que hoy nadie necesita; si Compras los pide, se decide al ficharlo (`BACKLOG.md`).
- **Se delegan las vistas y lo del técnico; lo de administración, no** (2026-10-21). El jefe técnico
  le da a uno nuevo *Paquetes* + `catalogo_paquetes_editar` sin pasar por el admin: arma borradores
  y manda a aprobar. Los `_administrar` (aprobar, poner a la venta, costos, montos y %) y *Clientes*
  entera los asigna el admin: la vista sola ya dice qué empresa ve precio. Como en Contactos y Obras.
- **Reglas y excepciones se cargan desde el servicio; el paquete solo muestra lo que recibe**
  (2026-10-21). En *Comercialización*: General 30 % · Ventanas → Modena 35 % · Vidrios → Laminados
  15 % · excepción Corrediza económica 20 %, todo con `catalogo_servicios_administrar`. En el
  paquete, *Lo que recibe por categoría* es de lectura: el técnico ve *Comercialización — por
  Ventanas → Modena*, sin el %; administración, con el % y la regla. Antes de guardar se ve el
  alcance (*Ventanas → Modena 35 %: 18 paquetes · 2 con excepción no cambian*); como la regla no está
  en la versión, rige al instante y no avisa, como un costo de Compras. Por qué: los % de un servicio
  en un solo lugar y una sola función. Descartado: la excepción desde el paquete (los % repartidos en
  dos pantallas y en `catalogo_paquetes_administrar`).
- **Un presupuesto enviado se mantiene o se actualiza; actualizar vuelve a la vigente** (2026-10-21).
  Un cambio de costo (Compras) o de % no lo toca solo. Mantener deja el precio enviado entero, con
  los costos y % de entonces: la Corrediza sigue en $ 600.000 porque hay sobrante comprado al costo
  viejo. Actualizar es como si la línea no se hubiera enviado: la vigente con costos y % de hoy (v3
  → v4, $ 667.250, con el aviso del técnico); si el paquete salió de venta, queda sin precio hasta
  reemplazarlo. Sin mezcla (costo viejo con % nuevo). La función no cambia: el vendedor calcula solo
  la vigente, la línea mantenida no se recalcula (lleva su precio copiado y su versión) y producción
  despieza esa versión aunque el paquete esté de baja (la Banderola con sobrante del perfil
  discontinuado). Descartado: la versión enviada con plata de hoy (v3 a $ 653.750): cotiza lo que
  el catálogo ya no vende, con el último costo de algo que ya no se compra. Por línea o entero, y
  quién puede mantener, al fichar Presupuestos (`BACKLOG.md`). Sin versiones de %, costos ni
  cotización: la línea guarda su precio, y si se quiere ver de dónde salió, una foto completa al
  enviar, con la cotización del día (`BACKLOG.md` → Presupuestos). Recalcular lo enviado por fecha
  pedía versionar las tres cosas y un motor que calcule igual que entonces.
- **El vidrio es un material de la hoja con una opción, como el herraje; el paño sale** (2026-10-21).
  El técnico escribe las medidas del paño como calculadas, cada una con su unidad: `ancho_pano_izq =
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
  el vendedor, y el técnico decide qué vidrios acepta cada línea. Lo que abrió, resuelto en las
  decisiones que siguen (*Pendiente* → *Vidrio como opción*).
- **El vidrio cobra por una variable de superficie y lleva sus medidas para el despiece**
  (2026-10-21). Lo que se cobra y el peso salen de la variable: *Float 4 mm* ×
  `superficie_pano_izq`. Además, un material por m² puede llevar ancho y alto por fórmula (cada uno
  da ml), solo para el despiece: `ancho_pano_izq` y `alto_pano_izq`, cada lado redondeado al mm
  hacia abajo. En 1501 × 1100 el despiece dice *Float 4 mm — 0,715 m² — 713 × 1002 mm*. Las medidas
  son del material, para todas sus alternativas, y una medida ≤ 0 frena como una pieza. Por qué:
  producción pide el vidrio cortado con la medida del sistema; si la calculara por su cuenta, la
  fórmula del paño quedaría en dos lugares. Superficie y medidas pueden no coincidir si el técnico
  cambia una sola: el despiece las muestra juntas. Descartado, por decisión del usuario: el vidrio
  por piezas con los m² sacados de las medidas, como los ml del perfil. También: solo la variable
  (el despiece quedaba en m²).
- **El DVH son opciones por capa, con lo que ya existe** (2026-10-21). En `hoja_izq`, tres
  materiales × `superficie_pano_izq` con las mismas medidas: *Vidrio* (Float 4 default, Float 5,
  Laminado 3+3); *Cámara* (*Sin cámara* como *Sin material* y default, Cámara 9, Cámara 12; las
  cámaras ponen `dvh_izq` = 1); *Vidrio interior* (Float 4 y Float 5 con `dvh_izq` = 1, *Sin
  material* con `dvh_izq` = 0). El despiece da cada capa con
  su medida (*Float 4 mm — 713 × 1002* · *Cámara 12 — 713 × 1002* · *Float 4 mm — 713 × 1002*) y las
  tres suman al peso de la hoja. La cámara sigue por m², con el armado en el precio de la vidriería;
  si se arma en fábrica, versión nueva con separador × `perimetro_pano_izq` y sellador. Un TVH suma
  otro par cámara + vidrio, en las líneas que lo admiten. **Una opción que en ese momento solo
  ofrece *Sin material* no se muestra**, sea de vidrio o de herraje: no hay qué elegir. Por qué: el DVH se arma con las piezas de los
  herrajes, sin nada propio del vidrio. Descartado: el DVH como un insumo (cada combinación un
  insumo, con su costo en Compras) y una opción de varias capas (el paño por otra puerta).
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
  - **Los defaults son par uno del otro** (*Embutida* a la izq, *Manija* a la der); si no, o si las
    alternativas difieren, no se manda a aprobar.
  - **Si el par no se ofrece en la hermana** (lo saca una condición o el color), entra
    lo que dice *Lo elegido se guarda*.

  Por qué: como antes con los paños, todas arrancan iguales y se cambia la que difiere; con un
  selector por hoja y un botón para copiar, olvidar el botón cotizaba una hoja en DVH y otra simple,
  más barata, sin que nada lo frene. Descartado: una opción para varios materiales (la corrediza no
  podía tener hojas distintas), la derecha "como la izquierda" (una hoja manda sobre la otra) y el
  botón solo.
- **El espesor lo pone el sistema desde el insumo: `espesor_<opción>`** (2026-10-21). Es un dato
  opcional de cualquier insumo, en mm (Float 4 mm: 4 · Cámara 12: 12 · Panel ciego: 24). Por cada
  opción el sistema pone el del insumo que entró (*Sin material* = 0), como pone `peso_<grupo>`, y el
  técnico arma lo que necesita: `espesor_pano_izq = espesor_vidrio_izq + espesor_camara_izq +
  espesor_vidrio_interior_izq` (ml), 20 en un 4+12+4. El burlete entra por condición sobre esa
  variable y el canal es una restricción que avisa (máximo 24: *Laminado 5+5 + Cámara 12 + Float 4:
  26 mm*). El vidrio interior puede mirar `espesor_camara_izq` > 0 en vez de un `dvh_izq`. Si una
  alternativa de una opción cuyo espesor se usa no lo tiene, no se manda a aprobar; mientras alguna
  versión lo use, se corrige pero no se borra, y corregirlo rige al instante, como el peso. Por qué:
  el espesor es del vidrio, no del paquete; puesto por la alternativa, el 4 del Float 4 se tipeaba en
  cada paquete y un 5 cambiaba el burlete sin que nadie lo viera. Descartado: que lo ponga la
  alternativa, como `desc_herraje_*` (ese sí depende de la línea).
- **Una opción puede ofrecer subcategorías enteras, insumos sueltos o las dos cosas** (2026-10-21).
  *Vidrio: todo Vidrios → Float, más Laminado 3+3*: un Float nuevo entra solo en todas las vigentes,
  sin versión ni aprobación; un laminado nuevo no. Lo que entra por subcategoría usa la fórmula y las
  medidas del material (solo un suelto trae las suyas), es par de sí mismo (los pares van entre
  sueltos: Manija ↔ Embutida) y toma las condiciones que lleve la subcategoría. Las hermanas ofrecen
  lo mismo, subcategorías y sueltos; si no, no se manda a aprobar. **Lo que entra solo se ofrece si
  cumple lo que pide el paquete**: la unidad de la fórmula y el espesor, si la opción lo usa; si no,
  no se ofrece y el técnico lo ve en el insumo (*Laminado 4+4: sin espesor · no se ofrece en 12
  paquetes*). Sin costo se ofrece y la línea queda sin precio (*Sin costo no es $ 0*). Lo que entra
  solo no es cambio de versión, como un color nuevo. Por qué: el vidrio nuevo llegaba a los 40
  paquetes que ofrecen vidrio sin 40 borradores ni 40 aprobaciones; el filtro, porque un vidrio dado
  de alta por ml o sin espesor entraba a una vigente cuyo control de *mandar a aprobar* ya había
  pasado. Contra aceptada: puede entrar en una línea donde no cabe en el canal, y solo avisa.
  Descartado: solo alternativas sueltas, con "agregar alternativa" masivo en la ventana de
  *Reemplazar material* (versión y aprobación por paquete).
- **Las alternativas se filtran por color** (2026-10-21). En la Puerta rebatible, *Paño bajo*
  ofrece todo Paneles → Ciegos más Float 4; en blanco, PAN-01 (sin blanco) no se ofrece y PAN-02 y
  Float 4 sí. **Un color sale del paquete solo si** le falta a un material fijo o condicional *de la
  ventana*, o si una opción queda sin nada que ofrecer en ese color (sin *Sin material*), como en
  "con condición no salva al paquete". Si el default no viene en ese color, entra la primera que se
  ofrezca (*Lo elegido se guarda*). Vale para toda alternativa *de la ventana*: con la Hoja 42
  reforzada sin blanco, en blanco se ofrece solo la Hoja 40. Por qué: con la regla anterior una
  alternativa sin el color sacaba ese color del paquete, y con subcategorías enteras un panel nuevo
  sin blanco se lo sacaba a todas las puertas sin que nadie lo notara. Descartado: que el default
  cuente como material fijo (lo hacía la composición por defecto del paño).
- **Lo que el catálogo deja de ofrecer deja la línea sin precio; lo que cambia la misma línea sigue
  *Lo elegido se guarda*** (2026-10-21). Presupuesto sin enviar con 6 corredizas en Laminado 3+3 y
  administración lo da de baja: las 6 quedan sin precio con el motivo (*Laminado 3+3: dado de baja,
  elegí otro vidrio*) y no se envían hasta que el vendedor elija. Vale para toda opción, vidrio o
  herraje, y para todo lo que viene del catálogo: baja del insumo o de su variante, o el insumo que
  sale de la subcategoría. Si lo causa la misma línea (saca la cámara, o cambia el color y
  PAN-01 no viene en blanco), sigue *Lo elegido se guarda* —una principal sin default queda vacía—
  y volver atrás devuelve lo elegido. Lo enviado no cambia. Por qué: pasando solas al default, las 6 bajaban de precio y se
  enviaban en Float 4 sin que nadie notara que el cliente pidió laminado; lo que hace el vendedor en
  su línea, en cambio, lo está viendo. Es lo que ya pasaba con el suelto, el color y el paño.
  Descartado: *Lo elegido se guarda* también para la baja (lo que decía *La baja depende de cómo se
  usa* para el herraje).
- **El % de los servicios del paquete deja afuera las categorías de insumos que marca
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
- **El cierre central no tiene decisiones propias: lo arma el técnico con lo que ya existe**
  (2026-10-21). Si una línea lo lleva, es un material condicional y alternativas con condición, como
  cualquier otra cosa; Tirador y Sin herraje son alternativas comunes del herraje. Por qué: no pide
  nada que el motor no tenga, y la opción `cierre` (0/1/2) y dónde va el kit decían cómo se carga un
  producto, no reglas del módulo.
