# Decisiones — módulo catálogo

**Estado (2026-09-29): ficha en borrador, sin aprobar. Sin SQL.** Retomar desde *Pendiente*, de a un
punto. Referencia del motor de paquetes: `C:\dev\Archivos antiguos\spec_plantillas_5.md` (módulo
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
  mosquitera, que la vidriería cobra y el paquete usa por superficie), peso por unidad (para el
  peso de la abertura y logística), unidad de comercialización / presentación (ej: barra de 6 m),
  **tipo** y **categoría** (ver *Categorías*).
- **La presentación sirve para vender suelto y para comprar, no para el paquete** (2026-10-14). Suelto
  se vende por presentación entera (2 barras = 12 ml × costo), no por fracción. Compras compra barras
  enteras y Taller podrá calcular cuántas salen del despiece. En el paquete el insumo va en su unidad
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
  entera (2 barras = 12 ml, no 12,96). Por qué: un `× 1,10` en la fórmula se sumaba al 8 % (18,8 %).
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
- **El % de un servicio del paquete no incluye vidrio, cámara ni panel** (2026-10-14): va sobre perfiles,
  herrajes y accesorios del grupo, separados por el tipo del insumo. El trabajo con el vidrio es un
  servicio fijo por m² (*Colocación de vidrio* × `superficie_pano_izq`), con condición sobre `espesor_pano_*`
  si un DVH lleva más; el servicio comercial sobre el vidrio sigue por categoría (Vidrios 10 %). Por qué: con un
  laminado 3× más caro, la mano de obra del 15 % subía $ 9.000 por la misma hoja. El panel ciego,
  igual: se compra hecho y se coloca como un vidrio. Descartado: casilla
  "incluye vidrio" por servicio — no hay caso que lo pida.
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
  y la usan todos los paquetes; el paquete solo dice qué colores ofrece. Descartado: mapear en cada
  paquete como el mockup — el mismo perfil se remapearía en cada plantilla y los mapeos podrían
  contradecirse. Y **vidrios compuestos**: el paquete define cada paño (medidas por variable, espesor
  máximo del canal) y el vendedor arma la composición al presupuestar (simple, DVH, TVH: vidrios +
  cámaras); el sistema saca la cantidad de cada vidrio y cada cámara. Si la composición supera el espesor del
  canal, **advierte, no frena** (como una restricción que avisa). Después: reglas, simulador, grafo.
- **Lo imposible deja la línea sin precio** (2026-10-14), como un insumo sin costo: se arma pero no
  se envía. El sistema frena solo pieza o paño ≤ 0 y cantidad < 0 (0 vale: no lleva); el mensaje dice
  qué falla y, si viene de una medida pisada, ofrece volver al automático (*hoja der mide −56 mm:
  hoja izq pisada en 900*). **Cada restricción del técnico avisa o frena** (por defecto avisa): frena
  lo que no se fabrica (*Corrediza económica: más de 2400 de ancho el perfil no aguanta, usar
  reforzada*), avisa lo que se fabrica pero no conviene. Por qué: el ancho cargado en cm (150) daba un
  paño negativo que restaba vidrio, y un aviso no impedía vender lo que la línea no soporta. El
  trabajo especial fuera de línea pasa por el técnico.
- **El aviso es parte del resultado de la línea** (2026-10-14), con el precio, el despiece y por qué
  entró cada material: no algo que se ve una vez al cargar. Presupuestos lo deja marcado en la línea
  y lo lista al enviar o aprobar, para confirmarlo sin frenar. Por qué: *más de 1800 de alto conviene
  reforzada* se veía al cargar y quien enviaba no se enteraba. Descartado: aceptarlo línea por línea —
  es un freno más, y para eso está "frena".
- **Un perfil se carga por piezas: nombre, cantidad y largo por fórmula** (2026-10-14), ej. marco:
  2 travesaños de `ancho` y 2 jambas de `alto`, a 45°. Los ml salen de sumar las piezas, no de otra
  fórmula: una sola fuente, y "Probar paquete" muestra el despiece para taller (piezas a cortar en
  mm, con el color elegido, y la medida de cada vidrio por paño) para que el técnico lo verifique.
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
  con ese número sale todo: despiece, ml cobrados, peso, `superficie_pano_*`, `perimetro_pano_*` y el aviso
  de barra. Las variables intermedias (`ancho_hoja_izq`) no se redondean: solo lo que se corta o se
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
- **La composición del vidrio es por paño** (2026-10-14): todos arrancan con la misma y el vendedor
  cambia solo el que difiere ("usar en todos" copia una a las demás). Una puerta con fijo superior
  laminado y hoja en DVH, o un paño bajo de seguridad, se cobra bien sin armar otro paquete.
- **La composición de un paño es vidrios y cámaras, o un panel solo** (2026-10-14). Panel es un tipo
  fijo de insumo, por m², con espesor y peso por m² como el vidrio; el vendedor lo elige por paño y el
  técnico puede dejarlo como composición por defecto (puerta: DVH arriba, panel abajo). Así el paño
  da `espesor_pano_*`, `peso_pano_*` y `superficie_pano_*`, y burlete, contravidrio y colocación entran sin
  nada nuevo. Por defecto es *de la ventana* (puerta negra, panel negro). Por qué: como material por
  fórmula el paño quedaba sin espesor y sin burlete, y no se podía cambiar a vidrio.
- **En la composición, lo que elige el vendedor se filtra y lo que declara el técnico cuenta como
  material fijo** (2026-10-14). El selector del paño ofrece solo vidrios, cámaras y paneles activos y,
  si son *de la ventana*, en el color de la ventana (en blanco no aparece un panel sin blanco). La
  composición por defecto cuenta como material fijo: su panel sin blanco saca el blanco del paquete;
  su laminado dado de baja deja el paquete sin ofrecer hasta que el técnico lo reemplace. Lo ya elegido
  en una línea sin enviar que queda sin color o de baja deja la línea sin precio con el motivo (*Panel
  ciego PAN-01: no viene en negro mate, cambiá la composición del paño hoja izquierda*); lo enviado no
  cambia. Por qué: el panel se elige entre todos los del catálogo, así que con la regla de las
  alternativas cualquier panel sin blanco sacaba el blanco de toda abertura con paños. Descartado:
  reemplazarlo solo por la composición por defecto — el vendedor armó ese paño a propósito y se
  cotizaría otra cosa sin aviso.
- **Cada pieza de la composición se cobra en su unidad** (2026-10-14). Hoy vidrios y cámaras se
  compran sueltos a la vidriería, con el armado del DVH incluido en su precio: la cámara es un insumo
  por m² y se cobra por el m² del paño (DVH 4+12+4 de 1,4 m² → 1,4 m² de float 4, de cámara 12 y de
  float 4). Si se arma en fábrica, la cámara pasa a un separador por ml, que sale del perímetro, y el
  sellador entra como material por perímetro: se cambia el insumo, no el paquete. Sin mínimo por paño
  por ahora: se cobra el m² real.
- **Un color se ofrece solo si todos los insumos *de la ventana* del paquete lo tienen** (2026-10-14). Si
  al perfil hoja le falta el blanco, la ventana no se ofrece en blanco: el técnico ve qué falta y el
  vendedor no ve ese color hasta que se cargue el equivalente, sea material fijo, alternativa o
  condicional (la composición del paño, ver *En la composición, lo que elige el vendedor se filtra*).
  Los sin color y los de herrajes no cuentan. Descartado: dejar el insumo en natural con aviso — una ventana blanca con una hoja
  natural no se vende — y frenar el presupuesto, que lleva el problema al vendedor.
- **El insumo declara su color: sin color, de la ventana o de herrajes** (2026-10-14). *Sin color*
  (felpa, tornillos, vidrio) no cambia. *De la ventana* (perfiles, tapas a la vista) va en el color de
  la ventana y sin el equivalente ese color no se ofrece (*ART-2410 sin negro mate*). *De herrajes*
  (manijas, cierres, kit central) sigue al color de herrajes de la línea; si no lo tiene, va en su
  color base y no bloquea. Por defecto sale del tipo (perfil y panel: de la ventana; el resto: sin color) y el
  técnico lo cambia. Por qué: un perfil recién cargado sin variantes parecía "sin color" como la felpa
  y salía natural en una ventana negra; y el kit central plateado, que va en blanco y en negro, sacaba
  el blanco de toda la corrediza. Descartado: deducirlo solo del tipo — "otro" mezcla manijas y
  tornillos; y reglas de color por clase de material (fijo, alternativa, condicional) — sacados los
  herrajes, la regla estricta ya no bloquea de más.
- **El color de herrajes es una opción secundaria de la línea, por defecto "como la ventana"**
  (2026-10-14): lo normal es negro en ventana negra, pero el cliente lo cambia. Uno por línea, no por
  herraje. El plegado dice lo que no se pudo (*herrajes: negro · kit central: plateado (no hay en
  negro)*). La opción del vendedor elige el modelo (manija, embutida, cierre central); el color sale
  de acá.
- **El técnico edita un borrador y "Publicar" crea la versión que ve el vendedor** (2026-10-14). El
  borrador se guarda a medias y Probar lo usa; lo que antes "no se guardaba" (fórmula mal escrita,
  material que mira el peso y suma al peso, secundaria sin default) ahora no se publica. Un
  presupuesto sin enviar sigue a la última versión publicada, como sigue al costo de hoy, con aviso en
  la línea (*el paquete cambió: v3 → v4*); se congela al enviar. Por qué: la rueda doble guardada sin
  su condición cotizaba las dos ruedas mientras el técnico terminaba. Descartado: que la línea quede
  en la v3 hasta actualizarla a mano — saldría con lo que el técnico ya corrigió.
- **El paquete guarda casos de prueba, y al publicar muestra qué cambia en cada uno** (2026-10-14).
  Un caso es lo que carga el vendedor (medidas, opciones, composición por paño, color), con nombre;
  se guarda desde Probar y se carga con un clic. "Publicar" corre los casos con el borrador y con la
  versión publicada y lista las diferencias sin precios: materiales que entran o salen, piezas,
  cantidades, avisos (*"3000 hoja pisada": rueda simple → doble (hoja der) · Travesaño hoja der 1460 →
  1510 mm*). Una opción que ya no existe sigue *Lo elegido se guarda* y se marca. Por qué: cargar a
  mano 4 casos de 8 campos en cada edición termina en probar uno, y lo roto lo encuentra el vendedor.
  Descartado: resultado esperado por caso — habría que cargar el despiece entero a mano.
- **Un insumo dado de baja cuenta como que no está** (2026-10-14): material fijo o condicional → el
  paquete no se ofrece hasta que el técnico lo reemplace; alternativa → deja de ofrecerse y entra lo
  que dice *Lo elegido se guarda* (Paquetes); variante de la ventana → ese color no se ofrece; variante de herrajes → color base con
  aviso; vidrio, cámara o panel → *En la composición, lo que elige el vendedor se filtra*. La baja no se frena: antes de confirmar muestra dónde se usa (*12 paquetes: 3 dejan de
  ofrecerse, 9 pierden una alternativa*) y el técnico ve esos paquetes marcados. Lo enviado no cambia:
  guarda su versión. Por qué: si no, se sigue cotizando un perfil que ya no se consigue.
- **La variante de color solo tiene código, nombre y costo; lo físico es del insumo base**
  (2026-10-14): peso, unidad, presentación, desperdicio, tipo, categoría y su clase de color no se cargan
  en la variante. El $/kg del negro se multiplica por el kg/ml del natural. Por qué: el negro con peso
  0 bajaba la hoja de 43 a 30 kg y salía con rueda simple, y su costo por kg quedaba sin costo.
  Descartado: desperdicio por variante — la barra que se corta es la misma.
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
  tirador 5) y `embutido_izq` (embutida 1); el *Mecanizado de embutido* entra si `embutido_izq` = 1.
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
- **Los herrajes de cierre son una opción por hoja, y una alternativa puede llevar condiciones**
  (2026-10-14). La corrediza cierra con un cierre central o con un herraje en cada hoja, que pueden
  ser distintos (manija en una, cierre embutido en la otra) y el lado importa para taller. El
  vendedor elige "Cierre" (opción que pone `cierre`: 0 por hoja, 1 central con cuerpo a la izquierda,
  2 a la derecha) y el herraje de cada hoja (`herraje_izq`, `herraje_der`, cada uno con su
  `desc_herraje_*`). Cada alternativa se ofrece si se cumplen sus condiciones, en las mismas casillas
  que los materiales condicionales: manijas y cierres con `cierre` = 0; tiradores y "sin herraje" con
  `cierre` ≥ 1. Por hoja siempre lleva herraje; con central es configurable. Si la elegida deja de
  ofrecerse, entra lo que dice *Lo elegido se guarda*. Descartado: una opción que oculta a otra — es un concepto
  nuevo, y las condiciones y las variables de opción ya existían.
- **El cierre central es un kit y entra en la hoja que lleva el cuerpo** (2026-10-14), como material
  condicional: en `hoja_izq` si `cierre` = 1, en `hoja_der` si `cierre` = 2. El lado lo pide el
  cliente. Así taller lo ve en su hoja y la mano de obra y el peso suman ahí. Un insumo es lo que se
  compra: el kit no se parte en cuerpo y contracierre. Descartado: cargarlo en el marco (no se
  mecaniza). Sigue con un código 0/1/2: una variable alcanza. ~~Que una alternativa ponga varias
  variables~~ → *Una opción puede poner varias variables*.
- ~~Todo lo que carga el vendedor tiene default~~ → *El default es obligatorio solo en lo secundario*.
- **El default es obligatorio solo en lo secundario** (2026-10-14). Opción: el técnico marca la
  alternativa por defecto; si su condición no se cumple, la primera que se ofrezca (*Lo elegido se
  guarda*). Medida: el
  default por fórmula de arriba, o un número fijo. Grupo opcional: arranca puesto o sacado
  (mosquitero: no). **Una principal sin default arranca vacía y es obligatoria**: la línea queda sin
  precio con *Falta alto*; una secundaria sin default toma la primera alternativa si es opción, y si
  es medida no se publica. Ancho y alto van siempre sin default; el color de la ventana es principal y
  sin default; el vidrio del primer paño es principal y el técnico decide si lo lleva (float 4 en una
  línea que casi siempre va así). Por qué: con 1000 por defecto, el alto olvidado en una de 6
  ventanas se cotizaba 1000 y tenía precio, así que nadie lo veía.
- **Lo elegido se guarda; lo que entra se calcula** (2026-10-14). La línea guarda la alternativa
  que eligió el vendedor y entra: lo elegido si se ofrece; si no, el default si se ofrece; si no, la
  primera que se ofrezca. Nada se sobrescribe. Por qué: embutido → cierre central (entra tirador) →
  vuelta a `cierre` = 0 perdía el embutido, y la ficha decía "primera válida" en un lado y "default"
  en otro. Igual que la medida pisada: se respeta lo elegido y se muestra lo que entra hoy.
- **Cada medida, opción o grupo opcional es principal o secundaria** (2026-10-14). El vendedor ve las
  principales; las secundarias quedan en "Más opciones", que plegado ya muestra qué entra (*herraje
  izq: Manija · mosquitero: no*). Una medida secundaria sin default no se puede publicar, como una
  fórmula mal escrita (una opción siempre tiene la primera alternativa). Si una restricción avisa sobre una secundaria, el aviso se ve y "Más opciones"
  se abre solo. Por qué: el vendedor cotiza lo común sin recorrer cada herraje y abre el resto cuando
  el cliente lo pide. Descartado: que sea principal según una condición (herraje principal solo con
  `cierre` = 0) — más lógica para lo que ya resuelve el plegado.
- **El peso es para logística y condiciona herrajes** (2026-10-14): ej., pasado cierto peso de hoja
  va rueda doble.
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
  "mano de obra extra si `alto` > 2400"; el mecanizado del embutido entra si `embutido_izq` = 1, que
  pone la alternativa embutida de la opción del herraje (las demás, 0: *Una opción puede poner varias
  variables*). El despiece dice por qué
  entró. Puede mirar el peso: un servicio no suma al peso. Descartado: que la alternativa traiga su
  servicio — enganche nuevo para lo que ya resuelven la variable de opción y la condición.
- **Cada material dice si suma al peso** (2026-10-14). Por defecto suma; el técnico lo apaga en el
  material que no debe contar. Así la rueda queda fuera del peso del grupo: el peso que la elige no
  cambia según qué rueda salga (si no, una condición sobre el peso dependería de sí misma). **Solo
  saca el material del peso de su grupo: el peso de la abertura, para logística, suma todo.** Un
  herraje pesado que mire el peso dejaría mal el flete. ~~Un material que mira el peso no puede sumar
  al peso del grupo~~ → *Nada depende de sí mismo*.
- **Nada depende de sí mismo: un paquete con un ciclo no se publica** (2026-10-14). El sistema arma
  las dependencias (fórmulas, defaults, condiciones, variables de opción y de peso) y el mensaje
  muestra la cadena (*`ancho_hoja_izq` → `ancho_hoja_der` → `ancho_hoja_izq`*); en el borrador se
  marca al editar. La rueda que mira `peso_total_hoja_izq` y suma a `peso_hoja_izq` es un caso: el
  técnico le apaga "suma al peso". El refuerzo del marco que mira el peso de la hoja no cierra ciclo y
  suma. Por qué: la regla solo del peso dejaba pasar defaults cruzados que cuelgan el cálculo y
  frenaba el refuerzo sin motivo. Es error de armado y lo corrige el técnico; descartado: avisar al
  vendedor, que no puede hacer nada.
- **El sistema pone una variable de peso por grupo** (2026-10-14): `peso_hoja_izq`, `peso_marco`…,
  suma de los materiales del grupo que suman al peso (cantidad × peso del insumo). El técnico arma con
  ellas el peso que necesita. **El peso es de lo que queda puesto: cantidad sin desperdicio**, en
  grupos, paños y el peso de la abertura para logística — el sobrante queda en taller y no viaja. Por
  qué: una hoja de 38 kg (aluminio 14 + paño 24) con desperdicio pasaba a 40,3 y salía con rueda doble. Descartado: calcular el peso a mano en la fórmula (ml × kg/ml + m² ×
  espesor × 2,5) — repite el peso del insumo y queda viejo si cambia.
- **Cada grupo opcional pone `con_<grupo>`: 1 si el vendedor lo puso, 0 si no** (2026-10-14), como
  pone `peso_<grupo>`. Con mosquitero el marco va de 3 guías: dos materiales condicionales, marco 2
  guías si `con_mosquitero` = 0 y 3 guías si = 1. Los grupos fijos no la ponen. Descartado: que el
  vendedor elija las guías — puede poner mosquitero con marco de 2 — y un paquete aparte con
  mosquitero, que repite todo por un perfil.
- **El sistema también pone el peso de cada paño** (`peso_pano_izq`, `peso_pano_der`), porque la
  composición es por paño, **y su `superficie_pano_*` (mm²), `perimetro_pano_*` (mm) y
  `espesor_pano_*`** (total de la composición: 20 en un 4+12+4) (2026-10-14). Con ellas se condiciona
  el burlete y el contravidrio al espesor y se cobra la colocación por m² sin rehacer la medida del
  paño en cada fórmula.
- **La superficie del paño va en mm², como toda variable** (2026-10-14): paño de 712 × 1000 →
  `superficie_pano_izq` = 712.000; *Colocación de vidrio* × `superficie_pano_izq` → 0,712 m². Por qué:
  como `m2_pano_*` en m², el sistema la volvía a pasar a m² y la colocación cobraba un millonésimo.
  Una condición sobre la superficie se escribe en mm² (`superficie_pano_izq > 2000000`): es rara, las
  que se usan son espesor y peso. Descartado: `m2_pano_*` como excepción en m² — hay que acordarse de
  qué variable no está en mm, y el olvido no se nota.
- ~~El técnico usa la hoja más pesada (`peso_hojas / 2 + maximo(...)`)~~ → *Un grupo por hoja*.
- **Un grupo por hoja** (2026-10-14): `hoja_izq`, `hoja_der`, cada uno con sus materiales y su peso
  (`peso_total_hoja_izq = peso_hoja_izq + peso_pano_izq`). Cada hoja lleva la rueda que pide su peso,
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
  — taller y el cierre central hablan de izquierda y derecha.
- **El vendedor no agrega materiales a la composición del paquete** (2026-10-14). Lo que se pide
  seguido (traba de seguridad) el técnico lo suma como grupo opcional secundario, arrancando sacado,
  y entra en despiece, peso y cantidad de la línea. Lo puntual va como línea suelta del presupuesto,
  referida a la línea que acompaña (*Traba × 4 — para V4*). Descartado: agregados dentro de la línea —
  mecanismo nuevo que mete en la abertura material que nadie del lado técnico validó.
- Un insumo suelto se precia como un paquete de una línea: costo + servicios por categoría y generales,
  sin desperdicio (se cobra la presentación entera).
- **Pantalla de referencia:** `C:\dev\Archivos antiguos\mockup_plantillas_v4.html` (lista con versiones y
  estado; detalle en pestañas: grupos, variables, materiales, restricciones, vidrios, reglas, colores,
  sandbox, auditoría). **Se le suma una pestaña Servicios** al lado de Materiales: el técnico elige el
  servicio del catálogo y le pone cantidad fija o por variable (soldadura × 4); el monto no se ve.
  **Cada servicio va en un grupo**, como los materiales: si el vendedor saca un grupo opcional
  (mosquitero), su mano de obra sale con él.

## Categorías (2026-10-14)

**Insumos y paquetes tienen categorías que crea el usuario, de un solo nivel; servicios, no.** En
paquetes es como busca el vendedor (Ventana → corrediza 2 hojas, corrediza 3 hojas). Servicios son
pocos y ya se separan por fijo/porcentual y comercial; sumarla después es trivial. Subcategorías,
recién si una categoría se llena.

**La línea de perfiles va en el nombre del paquete, y el buscador del vendedor toma palabras en
cualquier orden** (2026-10-14): *Corrediza 2 hojas — Modena*, que *modena corr* encuentra; el resumen
de la línea del presupuesto muestra el nombre entero, así una Herrero entre Modenas se ve al revisar.
Por qué: con 3 líneas × 6 tipos el vendedor elegía entre tres corredizas parecidas en cada abertura.
Descartado: un campo Línea (otra clasificación que mantener), categorías por línea (un solo nivel,
se pierde buscar por tipo) y deducirla de los perfiles (hay paquetes que mezclan).

**En insumos, la categoría (libre) va separada del tipo (fijo: vidrio, cámara, panel, perfil, otro).** El
tipo lo usa el sistema (armado de DVH, corte, color) y no se toca desde la pantalla; la categoría solo
ordena y agrupa, y mezcla tipos: "Vidrios" tiene vidrios y cámaras porque se compran a varias
vidrierías y aumentan juntos. Si el sistema mirara la categoría, renombrarla rompería el cálculo.

**El aumento de costo se aplica por categoría o por insumo, en % o monto fijo, con motivo e
historial** — como en los dos ERP viejos (`erp_old` `lista_precios/AumentoModal.tsx`, `erp_old_2`
`precios/ActualizacionMasivaModal.tsx`). No por proveedor: a cada categoría le venden varios. Como el
costo vive en Compras, la acción es de Compras y usa la categoría del catálogo.

## Servicios por categoría (2026-10-14)

**Un servicio porcentual puede aplicarse por regla, sin cargarlo en cada paquete: general, por
categoría de paquete (Ventanas 30 %) o por categoría de insumo (Vidrios 10 %).** Se carga una vez
y alcanza a todo paquete o insumo de esa categoría, también al insumo suelto. Reemplaza a los
comerciales generales con excepción por paquete: son el caso de una regla general.

**Si una línea cae en dos reglas del mismo servicio, gana la más específica, no se suman:** categoría
del insumo › excepción del paquete › categoría del paquete › general. Sumar cobraría dos veces el
mismo servicio sobre el mismo vidrio de una ventana.

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
Servicio %    % (administración) × suma de insumos de su grupo sin vidrio ni cámara; mínimo (administración) una vez
              por servicio en el paquete, sobre la suma de sus grupos
Por categoría % (administración) sobre los insumos que alcanza; gana la regla más específica
              (ver *Servicios por categoría*)
Precio        insumos + servicios, de una abertura — se calcula en Presupuestos, con las medidas
Línea         precio × cantidad (de la línea, nunca de las fórmulas)
Descuento     no es de Catálogo: va en Presupuestos (BACKLOG.md), sobre el precio de lista
```

**Sin costo no es $ 0: la línea queda sin precio** (2026-10-14). El costo de un insumo (Compras) o el
monto de un servicio (administración) puede faltar, pero no vale 0: un 0 se rechaza. Si en la línea
entra algo sin costo, el motor no da precio y dice qué falta (*sin precio: falta costear Kit cierre
central*); cuenta solo lo que entra (con cierre por hoja el kit no está y hay precio). El presupuesto
se arma igual pero no se envía con una línea sin precio. Compras y administración ven la lista "sin
costo y en uso" con los paquetes donde está. Por qué: con $ 0 la corrediza con cierre central salía
sin el kit y el precio parecía normal. Descartado: no ofrecer la alternativa (el vendedor no sabe por
qué falta) y avisar cobrando $ 0.

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
llama**: despiece, avisos y precio a quien ve precios; sin precio al resto (el técnico en Probar).
Quién ve precios se define en el árbol de vistas y funciones. Descartado: una vista que oculte
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

**El servicio no es ente: vive solo dentro del catálogo** (paquetes y reglas). Un cargo del presupuesto
(flete, traslado) no sale de servicios: es un renglón libre, con descripción y monto que calcula el
vendedor (`BACKLOG.md` → Presupuestos). Si algún día un cargo apunta a un servicio, alcanza una FK.

## Ficha del módulo (borrador)

```
Módulo: catalogo
Objetivo: definir qué compramos (insumos), qué hacemos (servicios) y cómo se combinan en lo que vendemos
          (paquetes), para que un presupuesto se arme eligiendo un paquete o un insumo suelto y cargando
          sus medidas.
Personas
├── Técnico / ingeniería — ve insumos, servicios (sin montos) y paquetes · crea insumos y servicios,
│                          arma paquetes (quien tenga la función, no la persona) · no ve costos ni
│                          precios
├── Administración       — ve todo, con costos (de Compras) y precios · pone montos, % y mínimos de
│                          servicios, reglas por categoría y excepciones, "se vende suelto" · —
├── Vendedor             — ve paquetes (despiece sin precios), insumos sueltos y precio de venta
│                          · los elige al presupuestar (en Presupuestos) · no ve costos
├── Depósito             — ve insumos · — · no ve costos, paquetes ni precios
├── Compras              — NO usa Catálogo · ve los insumos desde Compras, para costearlos
└── Taller               — NO usa Catálogo · ve el despiece ya procesado, por plantillas
Entes
├── insumo   — dueño, estado, ruta y submódulo: pendientes
└── paquete  — ídem
Relaciones, acciones, eventos: pendientes
```

## Pendiente

- **Para aprobar la ficha:** entes, relaciones, acciones, eventos; árbol de vistas y funciones;
  delegables y reglas entre permisos.

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
14. ~~**Insumo dado de baja en paquetes.**~~ → *Un insumo dado de baja cuenta como que no está*
    (Paquetes).
15. ~~**Cuándo llega una edición al vendedor.**~~ → *El técnico edita un borrador y "Publicar" crea
    la versión* (Paquetes).
16. ~~**Ciclos.**~~ → *Nada depende de sí mismo* (Paquetes).

*Vendedor*

17. ~~**Ancho y alto con default.**~~ → *El default es obligatorio solo en lo secundario* (Paquetes).
18. ~~**El aviso se pierde.**~~ → *El aviso es parte del resultado de la línea* (Paquetes).
19. ~~**Mano de obra % sobre el vidrio.**~~ → *El % de un servicio del paquete no incluye vidrio ni
    cámara* (Servicios).
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
27. ~~**Panel ciego en el paño.**~~ → *La composición de un paño es vidrios y cámaras, o un panel
    solo* (Paquetes).
28. ~~**Casos de prueba guardados en Probar.**~~ → *El paquete guarda casos de prueba* (Paquetes).
29. ~~**Redondeo del largo de corte.**~~ → *El largo de cada pieza y cada lado de un paño se
    redondean al mm, hacia abajo* (Paquetes).
30. ~~**Filtro por línea de perfiles.**~~ → *La línea de perfiles va en el nombre del paquete*
    (Categorías).

## Ficha del módulo — v2, desde cero (borrador, 2026-10-14)

Se arma de nuevo, de a un punto, sin partir del borrador anterior; al terminar se comparan.

```
Módulo: catálogo
Objetivo: definir qué se puede vender y la base de cómputo de su precio — los datos y las fórmulas
          que el presupuestador usa para calcular el precio de cada ítem
Personas
├── Técnico         — insumos, servicios y paquetes, sin plata · crea y edita los tres (la parte
│                     técnica); en paquetes escribe fórmulas y despieces, verifica que funcionen y
│                     los manda a aprobar · no ve plata
├── Administración  — ve todo, con costos (de Compras); prueba paquetes con medidas y ve el precio ·
│                     aprueba paquetes; crea categorías, pone montos, % y mínimos
│                     de servicios, marca qué insumo se vende suelto y en qué unidad; habilita a cada
│                     cliente empresa qué ve y si ve precios · —
│                     (los costos los carga en Compras, fuera del catálogo)
├── Vendedor        — NO usa el módulo: por el presupuestador elige paquetes aprobados e insumos
│                     sueltos y ve su precio · — · no ve despiece, costo ni servicios
├── Producción      — NO usa el módulo: el módulo de producción guarda medidas y configuración y
│                     pide el despiece cuando lo necesita · — · no ve plata ni fórmulas
└── Cliente empresa — NO usa el módulo: por el presupuestador de erp-cliente elige lo que administración
                      le habilitó; ve el precio solo si se lo habilitó · — · no ve despiece, costo ni servicios
Entes
├── paquete — dueño creado_por (solo dato) · estado por versión: borrador · para aprobar · aprobada · lo señalan la línea del presupuesto y la orden de producción
└── insumo  — dueño creado_por (solo dato) · sin estado (solo activo), sin versiones · lo señalan la línea del presupuesto (suelto), Compras, Stock y Contactos
Relaciones (del catálogo)
├── versión del paquete → insumos y servicios con sus fórmulas — interior del paquete, no puente entre entes
└── empresa cliente (Contactos) → categorías o subcategorías habilitadas + ve precio — configuración, FK a la empresa
Relaciones (de otros módulos, apuntan al catálogo)
├── insumo ← proveedor (Contactos) · costo (Compras) · existencias (Stock)
├── versión del paquete o insumo suelto ← línea del presupuesto (Presupuestos)
└── versión del paquete ← orden de producción, con medidas y herrajes (Producción)
Acciones
├── paquete: crear · editar borrador · mandar a aprobar (con qué cambió) · aprobar · rechazar (con motivo)
│            · versión nueva · probar con medidas · mover de subcategoría · dar de baja · reactivar
├── insumo: crear · editar · marcar suelto y unidad · dar de baja · reactivar
├── servicio: crear · editar · poner monto, % y mínimo · dar de baja · reactivar
├── categorías: crear · renombrar · dar de baja (administración)
└── clientes: habilitar categoría o subcategoría · ve precio sí/no (administración)
Eventos que emite
├── paquete: estado de la versión (para aprobar · rechazada → borrador · aprobada) — aviso a administración
│            y al técnico; la primera aprobada avisa a vendedores del producto nuevo
├── paquete: baja — aviso a vendedores de que sale de venta
├── insumo: baja — aviso al técnico: "reemplazar Marco 70 mm: 15 paquetes incompletos"
└── servicio: ninguno (no es ente; su baja se ve en los paquetes incompletos)
Eventos que consume
└── ninguno
```

```
Módulo: Catálogo
├── Insumos (vista)                              — técnico, administración
│   ├── catalogo_insumos_editar (funcion)        — técnico: crear y editar
│   └── catalogo_insumos_administrar (funcion)   — administración: ve costos, suelto y unidad,
│                                                  categorías, baja y reactivar
├── Servicios (vista)                            — técnico, administración
│   ├── catalogo_servicios_editar (funcion)      — técnico: crear y editar
│   └── catalogo_servicios_administrar (funcion) — administración: monto, % y mínimo, categorías, baja
├── Paquetes (vista)                             — técnico, administración
│   ├── catalogo_paquetes_editar (funcion)       — técnico: borradores, versión nueva, mandar a aprobar,
│   │                                              reemplazar material, probar sin plata
│   └── catalogo_paquetes_administrar (funcion)  — administración: aprobar y rechazar, probar
│                                                  con plata, categorías, mover, baja
└── Clientes (vista)                             — administración
    └── catalogo_clientes_habilitar (funcion)    — administración: qué ve cada empresa y si ve precio
Reglas entre permisos: ninguna. _editar y _administrar pueden coexistir en la misma persona.
```

Decidido en la v2:

- **El costo sigue fuera del catálogo, en Compras** (como en la v1). Administración lo carga allá; el
  catálogo lo lee para calcular. El técnico no ve plata.
- ~~**Hay margen, y lo pone administración.**~~ → *No hay margen* de la v1 (*Servicios*), confirmado al
  comparar (2026-10-14): la ganancia está en los servicios comerciales.
- **Tres vistas: Insumos · Servicios · Paquetes.**
  - *Insumos*: los materiales que se pueden usar o vender. Todo insumo está en una subcategoría; las
    categorías las crea administración. Administración decide si se vende suelto y en qué unidad:
    m², metro lineal, unidad o kg.
  - *Servicios*: lo no material. Porcentual con monto mínimo, o fijo (corte, manipulación del material).
  - *Paquetes*: donde están las fórmulas, armadas con insumos y servicios. En categorías que crea
    administración (Ventanas PVC → Corrediza 2 hojas, Corrediza 3 hojas).
- **Categorías en dos niveles fijos, en las tres vistas**: categoría → subcategoría → ítem (Perfiles
  PVC → Marcos → Marco corrediza 70 mm · Ventanas → Ventanas PVC → Corrediza 2 hojas). Cada ítem está
  en una subcategoría. No se anida más. Servicios también, por decisión del usuario, aunque sean pocos
  (propuesta descartada: lista plana con búsqueda y filtro fijo/porcentual).
- ~~**El técnico crea, administración completa la plata y aprueba — en insumos, servicios y
  paquetes.**~~ → *Solo el paquete se aprueba*.
- **Al presupuestador le sale el precio, nunca el costo ni el despiece.** El vendedor elige entre
  paquetes aprobados e insumos marcados sueltos; lo que esté sin aprobar no aparece.
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
  apunta a sus versiones se sigue calculando.
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
- **El servicio se edita directo, como el insumo.** No está en el despiece: corregirlo cambia precios, no
  órdenes.
- **Los cambios de plata de administración rigen al instante, sin aprobación**: montos, %, mínimos,
  suelto y unidad de venta. El catálogo calcula siempre con los valores de hoy; cuándo se
  congela el precio de un presupuesto lo decide Presupuestos. Cada cambio queda registrado (quién,
  cuándo, valor anterior y nuevo).
- **El catálogo no apunta a ningún otro módulo salvo la empresa cliente**: solo es dueño del interior de
  los paquetes y de las habilitaciones de clientes. Los demás le apuntan. Se puede construir antes que
  Compras, Stock y Producción.
- **Solo el paquete se aprueba** (revertido para insumo y servicio, 2026-10-14). El técnico crea y edita
  insumos y servicios sin aprobación; administración completa la plata. Insumo y servicio no tienen
  estado, solo `activo`. El freno queda donde importa: un insumo nuevo no se vende suelto hasta que
  administración lo marca, y un paquete que lo usa no llega al vendedor hasta que administración lo
  aprueba probándolo con plata — ahí ve si falta un costo o un monto. Descartado: el mismo circuito de
  aprobación en las tres vistas (trabajo doble para administración sobre datos que el paquete ya revisa).
- **Dar de baja es de administración, en las tres vistas**: dejar de vender es una decisión comercial.
  El técnico puede pedirlo, no hacerlo.
- **La subcategoría la elige el técnico al crear; administración puede moverla después.**
- **Dar de baja un insumo o un servicio deja "incompletos" los paquetes que lo usan: dejan de venderse.**
  Incompleto se calcula (la versión vigente usa algo dado de baja), no se guarda. En el catálogo dice
  "falta reemplazar: Marco corrediza 70 mm"; el vendedor y el cliente no lo ven; las órdenes que ya
  apuntan a esa versión siguen calculando su despiece. Descartado: seguir vendiéndolo con aviso.
- **El técnico reemplaza por material o por paquete.** Por material: "reemplazar Marco 70 mm por Marco 72
  mm" crea una versión borrador en cada paquete que lo usa, con el qué cambió ya escrito. Por paquete: a
  mano, cuando el material nuevo obliga a tocar una fórmula. Las dos terminan en versión nueva y
  aprobación.
- **Administración aprueba varias versiones juntas con checkbox, viendo qué cambió de verdad.** Cada fila
  muestra el texto del técnico (el porqué), los cambios que detecta el sistema entre versiones (insumos
  que entran o salen, fórmulas modificadas) y el precio antes y después a la medida de referencia del
  paquete. El texto solo no alcanza: dice lo que el técnico cree que cambió. Cada paquete tiene una
  medida de referencia que carga el técnico (la misma con que prueba el despiece).
- **El producto nuevo se avisa al aprobarse la primera versión, no en el alta.** El alta ocurre cuando el
  técnico abre el borrador: avisar ahí a los vendedores sería avisar de algo que no se vende. "Incompleto"
  no emite (se calcula); lo que lo causa sí: la baja del insumo.
- **La plata va atada a las funciones `_administrar`**: sin una, esa vista no muestra costos, montos
  ni precios. El técnico, con la vista y `_editar`, nunca ve plata.
- **`_editar` y `_administrar` pueden coexistir**: en una empresa chica la misma persona es técnico y
  administración. Descartado: excluirlas para que nadie apruebe su propio paquete (obliga a dos personas).
