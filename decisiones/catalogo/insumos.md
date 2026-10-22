# Catálogo — insumos

Qué compramos y usamos para trabajar: perfiles, tornillos, burletes, vidrios, silicona. Todo insumo
está en una subcategoría (`ficha.md` → *Categorías en dos niveles fijos*). Datos: código, nombre,
**unidad** (ml, m², kg o unidad — cada insumo una; m² para vidrio y tela mosquitera, que la vidriería
cobra y el paquete usa por superficie), **presentación** con su contenido (barra de 6 m = 6 ml),
peso, desperdicio, espesor opcional (`opciones.md` → *El espesor lo pone el sistema desde el
insumo*), clase de color y color base (`colores.md`), los servicios que trae (`servicios.md` → *Un
insumo puede traer sus servicios*) y si se vende suelto. Sin costo: vive en Compras, con su moneda
(`precio.md` → *El costo sigue fuera del catálogo, en Compras*). Es ente, con el rol `proveedor`
(`ficha.md` → *Entes*).

**En uso** es lo que se vende hoy: la vigente de un paquete activo lo usa, también por subcategoría, o
se vende suelto (*Lo que falta costear se ve en filtros*, `precio.md`).

- **Sin tipo fijo de insumo** (2026-10-20). Lo que hacía el tipo ya tiene dueño: cobrar por m² o ml lo
  dice la unidad del insumo; el % de los servicios del paquete deja afuera las categorías que marca
  administración (`servicios.md`); el corte por piezas lo decide el técnico al cargar el material; la
  clase de color se elige al crear el insumo, sin default (`colores.md`); qué vidrios acepta cada
  línea, la opción del paquete (`opciones.md` → *Una opción puede ofrecer subcategorías enteras*).
  Por qué: un concepto menos. Descartado: el tipo fijo de la v1 (vidrio, cámara, panel, perfil, otro).
- **La unidad del insumo queda fija desde que entra en un paquete o se vende suelto** (2026-10-21).
  Antes se corrige libre (el error de carga recién hecho). Desde que está en alguna versión de un
  paquete, borradores incluidos, o marcado suelto, no se edita y el campo dice por qué (*Felpa 7×5:
  en 20 paquetes · para otra unidad, insumo nuevo*); Compras y Stock suman su condición (costo o
  existencias cargados) al construirse. Otra unidad es un producto distinto: insumo nuevo y baja del
  viejo, y en cada borrador el control de unidad marca las fórmulas a corregir (`motor.md` → *Cada
  variable declara su unidad*). Por qué: el insumo no se versiona, así que pasar la felpa de ml a
  unidad hacía que las 20 vigentes, ya aprobadas, calcularan 5.980 felpas en vez de 5,98 ml, y las
  órdenes viejas el mismo despiece; la presentación y el costo quedaban en la unidad anterior.
  Descartado: permitirlo mostrando el alcance — cambia precio y despiece de versiones aprobadas sin
  revisión.
- **Nombre y código del insumo los corrige el técnico sin uso; en uso, administración** (2026-10-22),
  como mover (`ficha.md` → *La subcategoría la elige el técnico al crear*) y el nombre del paquete
  (`versiones.md`). Antes de confirmar se ve el alcance (*Float 4 mm → Float incoloro 4 mm: en 40
  paquetes · se vende suelto · lo ven 3 clientes*); Compras y Stock suman su condición (costo o
  existencias cargados) al construirse. Lo que lo nombra apunta, no copia, así que nada queda viejo; no
  es evento. Por qué: Marcos pasaba *Float 4 mm* (ART-3104) a *Float incoloro 4 mm* (VID-104) y al
  instante el selector de vidrio de 40 paquetes y el buscador del suelto decían otra cosa a vendedores
  y clientes, mientras depósito seguía con 30 placas rotuladas ART-3104; la persona administración
  decía *renombra lo que ya se vende* y la acción no lo tenía. Descartado: libre para el técnico (lo
  que ve el vendedor cambia sin que administración se entere), fijo como la unidad (un tipeo pediría
  insumo nuevo y baja con reemplazo) y aprobación como el cambio de cálculo (no cambia precio ni
  despiece).
- **La presentación sirve para vender suelto y para comprar, no para el paquete** (2026-10-14). Lleva
  su contenido en la unidad del insumo (barra = 6 ml, caja = 100 unidades: `precio.md` → *El costo se
  carga como se cotiza*). Compras compra barras enteras y producción podrá calcular cuántas salen del
  despiece. En el paquete el insumo va en su unidad (ml); el sobrante de barra entra por el
  desperdicio. Un material por piezas la pide para mandar a aprobar (`motor.md` → *Una pieza más larga
  que la barra da aviso*).
- **El desperdicio es un % del insumo, uno solo para todos los paquetes** (2026-10-14): perfil 8 %
  (6,60 ml → se cobran 7,13), vidrio 5 % sobre m², felpa 0 %. Lo carga el técnico con lo que informa
  taller (el parámetro del que sale no hace falta en esta fase): es cantidad, no precio. Un paquete no
  desperdicia más que otro. **Es obligatorio en el alta: 0 explícito vale, vacío no** (2026-10-21),
  como el peso: vacío contaba 0 y el perfil olvidado cobraba 8 % menos en todo, con el despiece bien,
  así que nadie lo veía. Descartado: % por paquete — el mismo perfil tendría 8 % en uno y 10 % en otro.
- **La fórmula dice lo que queda puesto; el desperdicio, lo que se tira** (2026-10-14). Fórmulas y
  largos de pieza llevan la medida real (el `× 1,15` de la felpa vale: da vuelta en las esquinas y
  queda puesta); el desperdicio sale solo del insumo, se aplica para cobrar sobre la cantidad y no
  toca el despiece (taller corta 1500, no 1650) ni el peso (`motor.md` → *El sistema pone una variable
  de peso por grupo*). Suelto no lleva desperdicio: se cobra la presentación entera (2 barras = 12 ml,
  no 12,96) o la cantidad pedida (1,4 m² de Float, no 1,47). Por qué: un `× 1,10` en la fórmula se
  sumaba al 8 % (18,8 %).
- **El peso es del insumo y condiciona herrajes; la abertura no da peso** (2026-10-21). El técnico
  lo carga al dar de alta el insumo (Marco corrediza 70 mm: 0,85 kg/ml; Float 4 mm: 10 kg/m²) y
  sirve para dos cosas: las variables de peso de los grupos, con las que entra la rueda doble si
  `peso_hoja_izq` > 40 kg (`motor.md`), y el costo que Compras cotiza por kg ($ 8.000 / kg × 0,85
  kg/ml = $ 6.800 / ml). El peso de la abertura entera, que la v1 sumaba para logística, sale: nadie
  lo recibía. "Suma al peso" sigue, para que la rueda no dependa de sí misma. Si el flete o logística
  lo piden, la función lo suma de los grupos y entra como una parte más con su rama: no falta
  ningún dato. **Es obligatorio en el alta: 0 explícito vale, vacío no** (2026-10-21). Tornillos o
  silicona van con 0 (no se cuentan). El costo por kg pide peso mayor que 0: con 0, Compras no lo
  cotiza por kg. Por qué: vacío contaba 0 sin decirlo; un *Float 6 mm* sin peso entraba por
  subcategoría en 40 vigentes, la hoja de 45 kg salía con rueda simple y, por kg, costaba $ 0.
  Contra aceptada: quien no sabe el peso y pone 0 vuelve a la rueda simple. Descartado: guardarlo
  vacío y dejarlo fuera de la venta hasta cargarlo (un filtro más en lo que entra por subcategoría y
  un control más en *mandar a aprobar*, contra una sola regla en la tabla).
- **El suelto se vende por presentación o por unidad del insumo; lo elige administración**
  (2026-10-21). Solo lo marcado *se vende suelto* le aparece al vendedor como producto, y lo marca
  administración (2026-10-14). Al marcarlo elige una de las dos, obligatoria y sin default:
  *Marco corrediza 70 mm* por presentación (2 barras = 12 ml × costo); *Float 4 mm* por unidad del
  insumo (1,4 m² cortado), y el *Burlete* de rollo también (15 ml). La unidad del insumo sigue siendo
  del técnico y esto no la cambia: de ella dependen las fórmulas y la conversión del costo. En los
  dos casos va sin desperdicio (el Float cortado se cobra por el m² real, como en el paquete). Se
  precia como un paquete de una línea: costo + servicios por regla (`precio.md` → *Precio de venta*),
  sin los que trae el insumo, que son de paquetes. El cambio rige al instante, pero la línea sin
  enviar no se convierte: queda sin precio con el motivo (*Marco corrediza 70 mm: ahora se vende por
  ml, revisá la cantidad*), como con el color o la baja; lo enviado no cambia. Por qué: con la unidad
  libre de la v2 (m², ml, unidad o kg), pasar el marco de ml a kg rompía las fórmulas de sus
  paquetes, y la presentación entera de la v1 no sirve para el vidrio cortado. El perfil cotizado por
  kg se vende por presentación (barras). Descartado: convertir la cantidad de la línea (de ml a barras
  no da exacto: 7 ml = 1,17 barras, y redondear cotiza otra cosa sin avisar).
- **El insumo no se versiona: una corrección se edita en el mismo insumo.** Las fórmulas leen el peso,
  así que corregirlo recalcula las órdenes viejas — y eso se quiere: el dato viejo estaba mal. En uso, la
  corrección espera a administración (*Lo que cambia el cálculo de un insumo en uso espera a
  administración*). **Un producto distinto es un insumo nuevo** (alta del nuevo, baja del viejo,
  versión nueva de los paquetes). Por qué no inmutable: corregir un perfil usado en 15 paquetes
  obligaba a 15 versiones y a mudar costo, stock y proveedor, para un dato que casi nunca cambia. El
  paquete sí se versiona porque cambiar una fórmula es diseño, no corrección.
- **Lo que cambia el cálculo de un insumo en uso espera a administración** (2026-10-21). Desperdicio,
  peso, contenido de la presentación, espesor y servicios que trae: con el insumo en uso, el técnico
  no los guarda, los propone. Antes de confirmar ve las diferencias del caso de referencia de cada
  vigente que lo usa, sin plata y agrupadas (*40 paquetes: Marco 70 a cobrar 7,13 → 11,88 ml*; *12
  paquetes: rueda simple → doble*); el contenido no cambia el despiece y dice *cambia el costo en 40
  paquetes: lo revisa administración*. Hasta aprobarse, todo calcula con el valor vigente y el campo
  muestra el pendiente (*desperdicio 8 % · pendiente 80 % (Marcos)*). Administración recibe aviso y lo
  ve en Insumos, filtro *para aprobar*, con el precio de referencia de cada paquete y del suelto antes
  → después (*Corrediza 2 hojas Modena $ 412.000 → $ 453.000*): aprueba y rige desde ahí, o rechaza
  con motivo y avisa al técnico. Uno pendiente por insumo, como la versión abierta del paquete: se
  retira y se propone otro, no se edita mientras se revisa; retirarlo avisa a administración, como
  volver al borrador. Va aparte de la fila del insumo, así cálculo, Compras y Stock leen el vigente.
  Lo que no está en uso se corrige libre, como la unidad; Producción suma sus órdenes abiertas al
  ficharse. Si técnico y administración son la misma persona, aprueba su propio cambio (`ficha.md` →
  *`_editar` y `_administrar` pueden coexistir*). Por qué: el insumo no se versiona y el técnico no ve
  plata: 80 en vez de 8 de desperdicio subía el Marco 70 un 66 % en 40 paquetes al instante, y una
  barra de 60 ml en vez de 6 lo dejaba a un décimo sin que el técnico lo pudiera ver. Descartado: que
  rija al instante mostrando el alcance y avisando a administración (entre guardar y leer el aviso se
  envían presupuestos con el error) y topes fijos (arbitrarios por material).
