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
- **El desperdicio es un % del insumo, uno solo para todos los paquetes** (2026-10-14): perfil 8 %
  (6,60 ml → se cobran 7,13), vidrio 5 % sobre m², felpa 0 %. Lo carga el técnico: es cantidad, no
  precio. Si un paquete necesita otro, va en la fórmula de esa línea (`(2×ancho + 2×alto) × 1,15`), sin
  campo de excepción. Descartado: % por paquete — el mismo perfil tendría 8 % en uno y 10 % en otro.
- **"Se vende suelto"**: solo los marcados le aparecen al vendedor como producto. Lo marca
  administración.
- Sin costo: el costo de reposición vive en Compras, con su moneda (ARS, US$, €).
- Ente: sí (vinculable a proveedores vía `contactos_vinculos`; declara el rol `proveedor`).

### Servicios — lo que no es material y se cobra

- Procesamiento, colocación de burlete, soldadura, mano de obra de instalación, y los **comerciales**:
  comercialización, manipulación.
- **Fijo**: monto por unidad (soldadura $ 1.500 c/u). **Porcentual**: % sobre la suma de los insumos
  **de su grupo** (no del paquete entero), con **precio mínimo** — el mínimo se aplica **una vez por
  servicio en el paquete**, sobre la suma de sus grupos, no en cada grupo (mano de obra 15 %, mín $ 5.000).
- Montos, % y mínimos los pone **administración**; el técnico no los ve.
- **No hay margen:** el precio de venta es insumos a costo + servicios. La ganancia está en los
  servicios comerciales.
- ~~Servicios comerciales: generales, con excepción por paquete~~ → *Servicios por categoría*.

### Paquetes — cómo se arma y cuánto lleva

- Plantilla con nombre ("Ventana corrediza 2 hojas") que lista insumos y servicios con su **cantidad o
  coeficiente**. El técnico pone *cuánto* (soldadura × 4, perfil = 2×ancho + 2×alto); administración y
  compras ponen *cuánto vale*; el sistema multiplica.
- Es el motor paramétrico del ERP viejo, recortado. Primer tramo propuesto: variables que carga el
  vendedor (ancho, alto, cantidad), variables calculadas, grupos (con opcionales, ej: mosquitero),
  materiales con cantidad fija o calculada, **servicios con cantidad** (nuevo: la spec vieja no los
  tenía), peso, versiones (un presupuesto no cambia si se edita el paquete) y **restricciones**
  (mín./máx. de una variable con su mensaje: **advierten, no frenan** — el vendedor ve el aviso y puede
  seguir) y **corte** por material (ángulo: 90°, 45°; no cambia el precio, es para el despiece de
  Taller — se carga desde ya aunque Taller no exista) y **colores** (el vendedor elige el color y cada
  insumo se cambia solo por su equivalente en ese color; el que no tiene color, como la felpa, queda
  igual). **La equivalencia vive en el insumo**, una sola vez (ART-2301 en negro mate es ART-2301-NM),
  y la usan todos los paquetes; el paquete solo dice qué colores ofrece. Descartado: mapear en cada
  paquete como el mockup — el mismo perfil se remapearía en cada plantilla y los mapeos podrían
  contradecirse. Y **vidrios compuestos**: el paquete define cada paño (medidas por variable, espesor
  máximo del canal) y el vendedor arma la composición al presupuestar (simple, DVH, TVH: vidrios +
  cámaras); el sistema saca m² por vidrio y ml de separador. Si la composición supera el espesor del
  canal, **advierte, no frena** (como las restricciones). Después: reglas, simulador, grafo.
- **Un perfil se carga por piezas: nombre, cantidad y largo por fórmula** (2026-10-14), ej. marco:
  2 travesaños de `ancho` y 2 jambas de `alto`, a 45°. Los ml salen de sumar las piezas, no de otra
  fórmula: una sola fuente, y "Probar paquete" muestra el despiece para taller (piezas a cortar en
  mm, con el color elegido, y la medida de cada vidrio por paño) para que el técnico lo verifique.
- **La composición del vidrio es por paño** (2026-10-14): todos arrancan con la misma y el vendedor
  cambia solo el que difiere ("usar en todos" copia una a las demás). Una puerta con fijo superior
  laminado y hoja en DVH, o un paño bajo de seguridad, se cobra bien sin armar otro paquete. El
  separador sale del perímetro de cada paño, uno por cámara.
- **Un color se ofrece solo si todos los insumos con color del paquete lo tienen** (2026-10-14). Si
  al perfil hoja le falta el blanco, la ventana no se ofrece en blanco: el técnico ve qué falta y el
  vendedor no ve ese color hasta que se cargue el equivalente. Los insumos sin color (felpa, vidrio)
  no cuentan. Descartado: dejar el insumo en natural con aviso — una ventana blanca con una hoja
  natural no se vende — y frenar el presupuesto, que lleva el problema al vendedor.
- **Lo que carga el vendedor lo define el paquete** (2026-10-14), no es un juego fijo de ancho, alto y
  cantidad: el técnico declara cada variable del vendedor. Puede ser una **medida** (número, con sus
  restricciones) o una **opción** entre insumos (manija plateada o marrón): el técnico marca un
  material del paquete y le carga las alternativas; el vendedor elige y el material cambia por el
  elegido. **Cada alternativa usa la fórmula del material o trae la suya** (una manija de dos puntos
  de fijación lleva otros tornillos).
- **Una opción puede poner una variable que usan las fórmulas** (2026-10-14): la manija define
  `desc_manija` (plateada 3, marrón 0, embutida 5) y el técnico escribe `ancho_hoja = ancho / 2 + 25 -
  desc_manija`. Así lo que cambia una medida se ve en la fórmula de esa medida, en un solo lugar.
  Descartado: que cada alternativa le "ajuste" la variable (−5 mm al ancho de hoja) — el ajuste
  quedaría escondido en la opción y la fórmula de `ancho_hoja` no diría la verdad.
- **Una medida del vendedor puede traer un valor por defecto por fórmula** (2026-10-14), para hojas
  asimétricas: `ancho_hoja_izq` propone `ancho / 2 + 25 - desc_herraje_izq` y el vendedor la pisa
  solo si hace falta; `ancho_hoja_der` es calculada (`ancho - ancho_hoja_izq + 50 - desc_herraje_izq -
  desc_herraje_der`). Si la pisó, se respeta aunque cambie `ancho`; si no, se recalcula. Las piezas y
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
  ofrecerse, pasa a la primera válida. Descartado: una opción que oculta a otra — es un concepto
  nuevo, y las condiciones y las variables de opción ya existían.
- **El cierre central es un kit y entra en la hoja que lleva el cuerpo** (2026-10-14), como material
  condicional: en `hoja_izq` si `cierre` = 1, en `hoja_der` si `cierre` = 2. El lado lo pide el
  cliente. Así taller lo ve en su hoja y la mano de obra y el peso suman ahí. Un insumo es lo que se
  compra: el kit no se parte en cuerpo y contracierre. Descartado: cargarlo en el marco (no se
  mecaniza) y que una alternativa ponga varias variables (`cierre_central` + `lado`) — se lee mejor,
  pero es una extensión nueva para lo que resuelve un código 0/1/2.
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
- **Cada material dice si suma al peso** (2026-10-14). Por defecto suma; el técnico lo apaga en el
  material que no debe contar. Así la rueda queda fuera del peso del grupo: el peso que la elige no
  cambia según qué rueda salga (si no, una condición sobre el peso dependería de sí misma). **Solo
  saca el material del peso de su grupo: el peso de la abertura, para logística, suma todo.** Un
  herraje pesado que mire el peso dejaría mal el flete. **Un material que mira el peso (por condición
  o fórmula) no puede sumar al peso del grupo: el paquete no se guarda así**, como una fórmula mal
  escrita. Es un error de armado y lo corrige el técnico; descartado: ignorarlo y avisar al vendedor,
  que no puede hacer nada.
- **El sistema pone una variable de peso por grupo** (2026-10-14): `peso_hoja_izq`, `peso_marco`…,
  suma de los materiales del grupo que suman al peso (cantidad × peso del insumo). El técnico arma con
  ellas el peso que necesita. Descartado: calcular el peso a mano en la fórmula (ml × kg/ml + m² ×
  espesor × 2,5) — repite el peso del insumo y queda viejo si cambia.
- **El sistema también pone el peso de cada paño** (`peso_pano_izq`, `peso_pano_der`), porque la
  composición es por paño.
- ~~El técnico usa la hoja más pesada (`peso_hojas / 2 + maximo(...)`)~~ → *Un grupo por hoja*.
- **Un grupo por hoja** (2026-10-14): `hoja_izq`, `hoja_der`, cada uno con sus materiales y su peso
  (`peso_total_hoja_izq = peso_hoja_izq + peso_pano_izq`). Cada hoja lleva la rueda que pide su peso,
  y el despiece sale por hoja, como se arma en taller. Por qué: con hojas asimétricas el `/2` le
  restaba aluminio a la ancha, justo la que puede pedir rueda doble; y como las piezas ya son por
  hoja, separar grupos casi no duplica. Lo repetido (felpa, rueda, manija) se alivia con **"duplicar
  grupo"**, que copia el grupo cambiando `_izq` por `_der` en las fórmulas.
- Un insumo suelto se precia como un paquete de una línea: costo + servicios por categoría y generales.
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

**En insumos, la categoría (libre) va separada del tipo (fijo: vidrio, cámara, perfil, otro).** El
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

**Si una línea cae en dos reglas del mismo servicio, gana la más específica, no se suman:** excepción
del paquete › categoría del insumo › categoría del paquete › general. Sumar cobraría dos veces el
mismo servicio sobre el mismo vidrio de una ventana.

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
Servicio %    % (administración) × suma de insumos de su grupo; mínimo (administración) una vez
              por servicio en el paquete, sobre la suma de sus grupos
Por categoría % (administración) sobre los insumos que alcanza; gana la regla más específica
              (ver *Servicios por categoría*)
Precio        insumos + servicios — se calcula en Presupuestos, con las medidas
Descuento     no es de Catálogo: va en Presupuestos (BACKLOG.md), sobre el precio de lista
```

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

**Las fórmulas se validan al guardar y se evalúan en la base**: solo números, variables del paquete,
`+ − × ÷`, paréntesis y funciones de una lista (redondear, máximo, mínimo). **Coma decimal y punto
y coma entre argumentos, como Excel en castellano** (`* 1,15`, `redondear(ancho / 1000; 0)`); el punto
decimal también se acepta, para que pegar `1.15` no sea un error. Descartado: el motor en
TypeScript del ERP viejo — más rico (reglas, simulador, grafo), pero eso quedó para después.

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
Entes, relaciones, acciones, eventos: pendientes
```

## Pendiente

1. Entes, relaciones, acciones, eventos; árbol de vistas y funciones; delegables y reglas entre
   permisos. Con eso la ficha se aprueba.
