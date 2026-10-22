# Catálogo — motor del paquete

Cómo arma el técnico un paquete: fórmulas, piezas, condiciones, grupos y peso. Lo que carga el
vendedor (medidas, opciones, vidrio), en `opciones.md`; la función que lo evalúa y quién ve qué, en
`calculo.md`; versiones y aprobación, en `versiones.md`.

## Qué es un paquete

Plantilla con nombre (*Modena · Corrediza 2 hojas*) que lista insumos y servicios con su **cantidad o
coeficiente**. El técnico pone *cuánto* (soldadura × 4, perfil = 2×ancho + 2×alto); administración y
Compras ponen *cuánto vale*; el sistema multiplica. Es el motor paramétrico del ERP viejo, recortado
(2026-10-14): variables que carga el vendedor y calculadas, grupos (con opcionales, ej: mosquitero),
materiales con cantidad fija o calculada, **servicios con cantidad** (nuevo: la spec vieja no los
tenía), peso, versiones, **restricciones** (condición con su mensaje: avisan o frenan, *Cada
restricción del técnico avisa o frena*), **corte** por pieza (ángulo: 90°, 45°; no cambia el precio,
es para el despiece de producción — se carga desde ya aunque Producción no exista) y **colores** (el
vendedor elige el color y cada insumo se cambia solo por su equivalente: `colores.md`). Lo que quedó
afuera del ERP viejo (reglas generales, simulador, grafo): `calculo.md` → *El motor va en Postgres*.

**Pantalla de referencia:** `C:\dev\Archivos antiguos\mockup_plantillas_v4.html` (lista con versiones y
estado; detalle en pestañas: grupos, variables, materiales, restricciones, vidrios, reglas, colores,
sandbox, auditoría). *Vidrios* y *colores* no van (2026-10-21): el vidrio es una opción (`opciones.md`
→ *El vidrio es un material de la hoja con una opción*) y los colores salen de los insumos
(`colores.md`). Se le suma una pestaña Servicios al lado de Materiales (`servicios.md` → *En el
paquete, cada servicio va en un grupo*).

## Fórmulas

- **Las fórmulas se validan al guardar y se evalúan en la base** (2026-10-14): solo números,
  variables del paquete, `+ − × ÷`, paréntesis y funciones de una lista (redondear, redondear.mas,
  redondear.menos, máximo, mínimo — `redondear.mas(alto / 600; 0)` = 3 grampas). **Coma decimal y
  punto y coma entre argumentos, como Excel en castellano** (`* 1,15`, `redondear(ancho / 1000; 0)`);
  el punto decimal también se acepta, para que pegar `1.15` no sea un error, **salvo seguido de
  exactamente tres cifras**: `2.400` se rechaza al guardar (*¿2400 o 2,4?*), que si no queda en 2,4
  mm. Una variable que no existe es fórmula mal escrita.
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
  `espesor_*` ml, `con_<grupo>` unidad). El valor sigue en mm y mm² (*Las fórmulas trabajan en mm*):
  la unidad dice qué mide, no cambia la cuenta. El parser que valida la fórmula al guardar saca
  también su unidad: largo × largo = m², m² ÷ largo = ml, largo ÷ largo = unidad, unidad × algo = ese
  algo; un número suma o resta en la unidad del otro lado (`ancho − 6`) y multiplica o divide sin
  cambiarla (`× 1,15`, `/ 2`); `redondear` la conserva y `máximo`/`mínimo` piden la misma en todo. Lo
  que no da una de las cuatro (ml × kg) es fórmula mal escrita. Si no coincide con la del insumo o el
  servicio, no se manda a aprobar, y en el borrador se marca en el campo (*`= 850.000 mm² · Felpa va
  por ml`*): *Tela mosquitera* (m²) × `perimetro_hoja_izq` da ml; *Felpa* (ml) × `ancho_hoja_izq ×
  alto_hoja` da m²; *Tornillo* (unidad) × `alto` da ml. La fórmula de una calculada, y el default de
  una medida, también tienen que dar lo que declaran, **salvo unidad, que acepta cualquiera**: es como
  se dice "una cada 600 mm". *Grampa* × `redondear.mas(alto / 600; 0)` frena (da ml); se carga
  `fijaciones_jamba` con esa fórmula, declarada unidad, y la usan grampas, tornillos y tarugos. El
  largo de cada pieza tiene que dar ml, y un material por piezas da ml: *Marco corrediza 70 mm* dado
  de alta por unidad frena (*va por unidad y las piezas dan ml*), en vez de cobrar 5.200 barras. Una
  cantidad fija no se controla: ya está en la unidad del insumo. Por qué: la conversión pasa a la
  unidad del insumo lo que dé la fórmula sin preguntar qué mide; la tela por perímetro cobraba 0,0038
  m² y la Corrediza salía $ 591.000 en vez de $ 600.000 sin que el técnico ni administración lo
  notaran. Descartado: controlar solo la cantidad que es una variable sola — la mayoría de las
  fórmulas se escriben en el material y quedaban afuera de un control que parece cubrir todo.
- **Lo que va por unidad se redondea hacia arriba solo** (2026-10-14), insumo o servicio: `alto / 250`
  = 4,4 → 5 tornillos. Por abertura y antes del desperdicio (5 con 5 % se cobran 5,25; el despiece dice
  5). ml y m² quedan con decimales. Lo que se usa en fracción va en otra unidad (silicona en ml, no
  ½ cartucho).

## Piezas

- **Un perfil se carga por piezas: nombre, cantidad y largo por fórmula** (2026-10-14), ej. marco:
  2 travesaños de `ancho` y 2 jambas de `alto`, a 45°. Los ml salen de sumar las piezas, no de otra
  fórmula: una sola fuente, y "Probar paquete" muestra el despiece para taller (piezas a cortar en
  mm, con el color elegido, y la medida de cada vidrio) para que el técnico lo verifique.
- **La cantidad de piezas lleva el redondeo escrito en la fórmula** (2026-10-22): tiene que dar
  entero por construcción (un número entero, un redondeo, o sumas, restas y productos de eso, directo
  o por una calculada); si no, no se manda a aprobar. Travesaños intermedios: `redondear.mas(alto /
  1000; 0) − 1` da 0, 1, 1 y 2 con 900, 1100, 2000 y 2100 de alto. Por qué: `alto / 1000` da 1,1
  barras, y ninguna dirección automática acierta (para arriba sobra una en los cuatro; para abajo
  falla en 2000), mientras que en tornillos lo correcto es para arriba. Lo decide el técnico, que
  sabe cómo se arma. Descartado: redondear solo, como lo que va por unidad.
- **Cada pieza lleva un ángulo por extremo, por defecto 90° / 90°** (2026-10-14). El mismo perfil
  hoja da travesaños a 45/45 y un travesaño intermedio a 90/90, y un parante puede ir 45/90. El
  despiece dice *Travesaño intermedio × 1 — 1270 mm — 90/90*. Por qué: con un ángulo por material el
  intermedio salía a 45° y la pieza se perdía.
- **Una pieza más larga que la barra da aviso** (2026-10-14). El sistema compara cada pieza con el
  contenido de la presentación del insumo (barra = 6 ml = 6000 mm): *Travesaño marco 6500 mm: más
  largo que la barra de 6000 mm*. Aviso y no freno: se hace con barra especial o empalme, y lo que no
  se fabrica ya lo frena una restricción del técnico. Por qué: se cobraba 6,5 ml y taller se enteraba
  al cortar, con el presupuesto aprobado. Descartado: la restricción a mano en cada paquete — se
  olvida y el largo ya está en el insumo. **Un material por piezas pide presentación en su insumo
  para mandar a aprobar** (2026-10-22): sin ella no hay con qué comparar y el travesaño de 6500 del
  *Marco Herrero 60* pasaba sin aviso. Solo lo que va por piezas; en uso, cargarla espera a
  administración (cambia la conversión del costo). Descartado: presentación obligatoria en el alta
  de todo insumo (pide un dato a lo que no se corta).
- **El largo de cada pieza y cada medida del vidrio se redondean al mm, hacia abajo** (2026-10-14), y
  con ese número sale todo: despiece, ml cobrados, peso y el aviso de barra. El vidrio cobra y pesa
  por su variable de superficie, sin redondear; se redondean sus medidas del despiece (`opciones.md` →
  *El vidrio cobra por una variable de superficie*). Las variables intermedias (`ancho_hoja_izq`) no
  se redondean: solo lo que se corta o se pide. Por qué: con 1501 de ancho la hoja daba 772,5 mm y
  taller y vidriería redondeaban cada uno a su manera; hacia abajo, porque medio mm de menos entra y
  de más no. Descartado: redondear las variables intermedias — el error se acumula cuando una medida
  sale de otra.

## Condiciones

- **Materiales condicionales: los pone el sistema, el vendedor no elige** (2026-10-14). Un material
  puede llevar una condición sobre cualquier variable (medida o calculada): "si `ancho` > 1500 → se
  agrega el herraje X", "si `peso_hoja` > 40 kg → rueda doble". Si se cumple, entra; si no, no. Un
  reemplazo son dos materiales con condiciones opuestas (rueda simple si ≤ 40, doble si > 40). Como
  las alternativas, **usa la fórmula del material o trae la suya**. El despiece muestra por qué entró
  ("Rueda doble — `peso_hoja` 48 kg > 40"). Es el único tipo de regla del motor en el primer tramo;
  las reglas generales del ERP viejo siguen para después. Por qué: la rueda no es una preferencia del
  cliente, la decide la medida; dejarla al vendedor permitía armar una abertura que no anda.
- **La condición se carga en casillas, no se escribe** (2026-10-14): variable, comparación (> ≥ < ≤ =)
  y valor. Un material puede tener varias y entra si se cumplen todas ("ancho > 2000 y alto > 1800").
  Descartado: escribirla como fórmula (`ancho > 2000 y alto > 1800`) — obliga al motor en Postgres a
  interpretar comparaciones y y/o, y el técnico puede escribir algo que no se entiende.
- **El valor de la casilla se carga en la unidad en que se piensa su variable** (2026-10-22): un largo
  (ml) en mm, como las medidas y el espesor; una superficie (m²) en m²; el peso en kg; una unidad, tal
  cual. Se guarda en mm y mm² como todo valor (el motor compara crudo; convierte la pantalla), y la
  casilla muestra unidad y conversión al lado, como el campo de fórmula (`> 2 m² (2.000.000 mm²)`,
  `≤ 2,4 mm (0,0024 ml)`). Vale para condiciones y restricciones. `2.400` se rechaza como en las
  fórmulas (*¿2400 o 2,4?*). Por qué: *Laminado 5+5 si `superficie_pano_izq` > 2*, pensado en m²,
  era siempre verdad (el paño de la 1500 × 1100 son 714.000 mm²) y todas las corredizas salían con
  laminado; *ancho máx. 2,4* frenaba todo.

## Grupos y peso

- **Un grupo por hoja** (2026-10-14): `hoja_izq`, `hoja_der`, cada uno con sus materiales y su peso
  (`peso_hoja_izq`, con el vidrio). Cada hoja lleva la rueda que pide su peso, y el despiece sale por
  hoja, como se arma en taller. Por qué: con hojas asimétricas el `/2` le restaba aluminio a la
  ancha, justo la que puede pedir rueda doble; y como las piezas ya son por hoja, separar grupos casi
  no duplica. Lo repetido (felpa, rueda, manija) se alivia con **"duplicar grupo"**.
- **"Duplicar grupo" pide qué reemplazar y por qué, y muestra cada cambio antes de confirmar**
  (2026-10-14). Propone el par por los nombres (`hoja_izq` → `hoja_cen`: `_izq` → `_cen`) y lo aplica
  en fórmulas, condiciones y variables de opción; la lista marca las variables que no existen
  (*`desc_herraje_cen` ⚠ no existe*). Se confirma igual: es borrador, y una variable que no existe es
  fórmula mal escrita, que no se manda a aprobar. Por qué: con 3 hojas el `_izq` → `_der` fijo daba
  dos `hoja_der` y la central con las fórmulas de la derecha. Descartado: numerar hojas `_1`, `_2`,
  `_3` — taller habla de izquierda y derecha. **Cada opción de la copia entra como hermana de su
  original** (2026-10-22): *Vidrio hoja cen* se junta con izq y der en un selector; si eran dos con un
  par que no es el mismo, frena por *Los pares van solo entre dos hermanas* (`opciones.md`). Opciones
  con las mismas alternativas en grupos distintos sin hermanar avisan en el borrador y al mandar
  (*Vidrio banderola y Vidrio hoja: mismas alternativas, no son hermanas*), sin frenar: la banderola
  con otro default solo se arma sin hermanar. Por qué: la central suelta quedaba en Float 4 mientras
  el vendedor ponía DVH una vez en las otras dos, más barata y sin que nada lo marque.
- **Cada grupo opcional pone `con_<grupo>`: 1 si el vendedor lo puso, 0 si no** (2026-10-14), como
  pone `peso_<grupo>`. Con mosquitero el marco va de 3 guías: dos materiales condicionales, marco 2
  guías si `con_mosquitero` = 0 y 3 guías si = 1. Los grupos fijos no la ponen. Descartado: que el
  vendedor elija las guías — puede poner mosquitero con marco de 2 — y un paquete aparte con
  mosquitero, que repite todo por un perfil.
- **El sistema pone una variable de peso por grupo** (2026-10-14): `peso_hoja_izq`, `peso_marco`…,
  suma de los materiales del grupo que suman al peso (cantidad × peso del insumo: `insumos.md` → *El
  peso es del insumo*). El técnico arma con ellas el peso que necesita. **El peso es de lo que queda
  puesto: cantidad sin desperdicio**, en los grupos — el sobrante queda en taller, no en la hoja. Por
  qué: una hoja de 38 kg (aluminio 14 + vidrio 24) con desperdicio pasaba a 40,3 y salía con rueda
  doble. Descartado: calcular el peso a mano en la fórmula (ml × kg/ml + m² × espesor × 2,5) — repite
  el peso del insumo y queda viejo si cambia.
- **Cada material dice si suma al peso** (2026-10-14). Por defecto suma; el técnico lo apaga en el
  material que no debe contar. Así la rueda queda fuera del peso del grupo: el peso que la elige no
  cambia según qué rueda salga (si no, una condición sobre el peso dependería de sí misma: *Nada
  depende de sí mismo*).
- **Nada depende de sí mismo: un paquete con un ciclo no se manda a aprobar** (2026-10-14). El sistema
  arma las dependencias y el mensaje muestra la cadena (*`ancho_hoja_izq` → `ancho_hoja_der` →
  `ancho_hoja_izq`*); en el borrador se marca al editar. La rueda que mira `peso_hoja_izq` y suma a él
  es un caso: el técnico le apaga "suma al peso". El refuerzo del marco que mira el peso de la hoja no
  cierra ciclo y suma. Por qué: la regla solo del peso dejaba pasar defaults cruzados que cuelgan el
  cálculo y frenaba el refuerzo sin motivo. Es error de armado y lo corrige el técnico; descartado:
  avisar al vendedor, que no puede hacer nada. **El grafo de ciclos se arma por tipos de nodo**
  (2026-10-22). Nodos: cada variable (medida, calculada, `peso_<grupo>`, `con_<grupo>`,
  `espesor_<opción>`, las que pone una alternativa), cada material condicional y lo que entra en cada
  opción. Aristas: fórmula y default → las variables que leen; material condicional → las variables
  de su condición; lo que entra en una opción → las condiciones de sus alternativas y de las
  subcategorías que ofrece (el color es del vendedor, no es arista); `espesor_<opción>` y lo que pone
  una alternativa → lo que entra en esa opción; `peso_<grupo>` → los materiales del grupo que suman
  al peso (condición, cantidad y lo que entra en sus opciones). Restricciones y servicios quedan
  afuera: nada los lee. Toda variable nueva que ponga el sistema entra con lo que la produce. Por qué:
  Laminado 5+5 si `peso_hoja_izq` < 40 y el burlete si `espesor_pano_izq` > 20 cerraban *vidrio* →
  `espesor_vidrio_izq` → `espesor_pano_izq` → burlete → `peso_hoja_izq` → *vidrio*, y la lista de
  dependencias del 14/10 (fórmulas, defaults, condiciones, variables de opción y de peso) no lo veía:
  la línea colgaba u oscilaba.

## La línea

- **Lo imposible deja la línea sin precio** (2026-10-14), como un insumo sin costo: se arma pero no
  se envía. El sistema frena solo pieza o medida de vidrio ≤ 0 y cantidad < 0 (0 vale: no lleva),
  además de la medida fuera de rango (`opciones.md` → *Toda medida del vendedor lleva mínimo y
  máximo*); el mensaje dice qué falla y, si viene de una medida pisada, ofrece volver al automático
  (*hoja der mide −56 mm: hoja izq pisada en 900*). **Cada restricción del técnico avisa o frena**
  (por defecto avisa): frena lo que no se fabrica (*`superficie_hoja` > 2 m²: la hoja no aguanta*),
  avisa lo que se fabrica pero no conviene (*`alto` > 1800: conviene reforzada*). **La restricción es
  una condición con su mensaje** (2026-10-22): se carga en casillas como la de un material
  (*Condiciones*) y, si tiene varias, vale cuando se cumplen todas. Sirve para combinaciones (varias
  casillas, o una calculada como `superficie_hoja`), calculadas y avisos; el tope que frena sobre una
  sola medida del vendedor es su máximo o su mínimo, con su mensaje (`opciones.md` → *Toda medida del
  vendedor lleva mínimo y máximo*). El sistema no lo controla: queda como regla. Por qué: el ancho
  cargado en cm (150) daba un vidrio de medida negativa que restaba m², y un aviso no impedía vender
  lo que la línea no soporta. La condición, porque como mín./máx. de una variable la restricción ponía
  un segundo tope sobre la medida que ya tiene el suyo. El trabajo especial fuera de línea pasa por el
  técnico (`pendiente.md` → 44).
- **El aviso es parte del resultado de la línea** (2026-10-14), con el precio, el despiece y por qué
  entró cada material (cada persona ve su parte: `calculo.md` → *Precio y despiece se habilitan por
  separado*): no algo que se ve una vez al cargar. Presupuestos lo deja marcado en la línea y lo lista
  al enviar o aprobar, para confirmarlo sin frenar. Por qué: *más de 1800 de alto conviene reforzada*
  se veía al cargar y quien enviaba no se enteraba. Descartado: aceptarlo línea por línea — es un
  freno más, y para eso está "frena".
- **La cantidad es de la línea del presupuesto, no del paquete** (2026-10-14). El paquete calcula
  una abertura; ninguna fórmula ve la cantidad. La línea multiplica el precio unitario y el despiece
  (4 corredizas → 8 travesaños de marco). Por qué: como variable del técnico, la felpa sin `× cantidad`
  daba 4 ventanas con felpa para 1. El mínimo de un servicio queda por ventana; lo que se hace una vez
  por pedido (traslado, flete, preparación) es un cargo del presupuesto entero, en Presupuestos.
  Descartado: mínimo por línea — con 3 renglones en la misma obra, cobraba 3 veces lo que se hace 1.
- **El vendedor no agrega materiales a la composición del paquete** (2026-10-14). Lo que se pide
  seguido (traba de seguridad) el técnico lo suma como grupo opcional secundario, arrancando sacado,
  y entra en despiece, peso y cantidad de la línea. Lo puntual va como línea suelta del presupuesto,
  referida a la línea que acompaña (*Traba × 4 — para V4*). Descartado: agregados dentro de la línea —
  mecanismo nuevo que mete en la abertura material que nadie del lado técnico validó.
