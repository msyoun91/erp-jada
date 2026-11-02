# Catálogo

**Se arma de cero: no se trae nada de la v1 ni de la v2 (2026-10-26).** La ficha y las decisiones de
este módulo salen solo de preguntas nuevas al usuario. No se lee `obsoletos/catalogo-descartado-2026-10-22/`,
no se compara con lo descartado y no se recupera nada de ahí: ni nombres, ni entes, ni estados, ni
tablas, ni soluciones del tipo "como estaba antes". Si una sesión sabe algo de esas versiones, no lo
propone. Si algo nuevo termina pareciéndose, tiene que ser porque volvió a salir de las preguntas.
El usuario descartó el diseño entero el 2026-10-22 y pidió fichar el módulo sin basarse en él. Lo que
este archivo no dice, no está decidido.

## Ficha del módulo

En armado, punto por punto con el usuario. Objetivo y personas aprobados el 2026-10-27; sin entes el
2026-10-30 (*Sin entes*), con los registros, los avisos y el árbol de vistas y funciones (*Pestañas*).
Sin `catalogo_ver`: cada pestaña tiene su código, y `/catalogo` abre la primera que el usuario tiene.

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
Entes: ninguno — nada tiene dueño ni chip; lo que ve cada uno lo da el permiso (*Sin entes*)
Registros
├── paquete       — por qué está de baja: a mano, o el insumo o servicio fijo que lo bajó
│   └── versión   — borrador → en revisión → publicado → obsoleto · nombre y categoría · una sola
│       │           abierta por paquete · el gerente la devuelve con motivo
│       └── pieza armada → fórmula: un insumo o servicio fijo y cuánto lleva según las medidas
├── insumo        — categoría de insumo, unidad (mm, m2, u), peso y espesor · costo con fecha y
│                   moneda · todo se edita hasta que un paquete lo usa; después, solo el costo y si
│                   está activo
├── servicio fijo — como el insumo, sin peso ni espesor, en una categoría de servicio
├── categoría     — de paquete y de insumo (las define Técnica), de servicio (Administración) · se
│                   edita hasta tener algo adentro; de baja, solo sin nada activo adentro
└── servicio en % — su %, su paso (1: el despiece o ciertas categorías · 2: el subtotal · 3: el precio
                    final), mínimo con moneda, por paquete o por presupuesto, si es opcional · cada
                    cambio es un valor nuevo con fecha
Eventos: ninguno (sin entes). Los avisos van por notificaciones:
├── insumo nuevo                → quienes cargan costos · desaparece cuando tiene costo
├── categoría de insumo nueva   → quienes definen los servicios en %
├── baja de insumo              → gerente, si sacó algo de la venta: los paquetes que siguen de baja
│                                 por ella y lo que dejaron de ofrecer
├── baja de servicio fijo       → gerente y Técnica, si sacó algo de la venta
├── cambio en un servicio en %  → gerente: apunta al cambio en la historia, para revertirlo
├── cambio revertido            → quien hizo el cambio
├── versión enviada a revisión  → quienes aprueban · desaparece al aprobarla, devolverla o retirarla
└── versión aprobada o devuelta → quien la envió · con el motivo si fue devuelta

Catálogo
├── Paquetes (vista, catalogo_paquetes)          — técnica, gerente, quien revisa cortes: por
│   │                                              categoría, con versiones y despiece, sin precio
│   ├── catalogo_armar (funcion)                 — técnica: paquetes y sus categorías, versiones;
│   │                                              envía, retira, da de baja y reactiva
│   └── catalogo_aprobar (funcion)               — gerente: "Por revisar", el precio y su detalle
│                                                  de cualquier versión, aprueba y devuelve
├── Insumos (vista, catalogo_insumos)            — técnica, administración, gerente: sin costo
│   ├── catalogo_cargar (funcion)                — técnica: alta y categorías de insumo, edición
│   │                                              mientras nadie lo usa, baja y reactivación
│   └── catalogo_costos (funcion)                — administración, gerente: ve y carga el costo
├── Servicios fijos (vista, catalogo_fijos)      — técnica, administración, gerente: sin costo
│   └── catalogo_fijos_editar (funcion)          — administración, gerente: alta con costo, edición
│                                                  mientras nadie lo usa, costo, baja, categorías
└── Servicios en % (vista, catalogo_porcentajes) — administración, gerente: con su historia
    └── catalogo_porcentajes_editar (funcion)    — administración, gerente: alta, cambios, baja y
                                                   reactivación, revertir
Delegables
├── sí — las cuatro vistas · catalogo_armar · catalogo_cargar · catalogo_costos ·
│        catalogo_fijos_editar · catalogo_porcentajes_editar
└── no — catalogo_aprobar
Reglas entre permisos: ninguna, ni requiere ni excluye
```

Pendientes de la ficha:
- **Editor de paquete**: en dictado del usuario desde el 2026-10-30 (*Editor de paquete*). Sigue:
  - **Opción sin pareja en un combo**: propuesto que la base no deje enviar la versión si una opción
    del que elige no tiene pareja (se suma "Perfil marco anodizado" y la hoja no tiene anodizado: el
    precio salía sin perfil de hoja). Explicado, sin confirmar.
  - Huecos marcados: el "si no" obligatorio cuando el sistema define el material; qué toma una
    referencia a un material con varios renglones (el total, un renglón o la medida de cada pieza).
  - Huecos de la auditoría del editor contra el objetivo de dar el despiece (2026-10-30), sin decidir:
    - **Peso y espesor del insumo**: en qué unidad va el peso de uno en mm (¿por metro, como el
      costo?); un DVH sin espesor suma 0 y "espesor > 24 → bloqueo" no salta, como la medida vacía.
    - **Errores de cálculo**: flecha 0 divide por cero, ancho 100 en vez de 1.000 da un área negativa
      que baja el precio, flecha > ancho / 2 calcula mal el arco. Propuesto: bloqueo de la base, sin
      que Técnica lo configure.
    - **Medida en u**: varilla roscada por u cortada a 300 mm, cantidad 2: ¿la medida informa el corte
      o multiplica?
    - Menores: el predeterminado de la pieza opcional (incluida o no), que marcarla secundaria exige;
      "Único: se selecciona un solo insumo" deja afuera al servicio fijo; datos sin material que
      Producción necesita (mano de apertura); lo que frena el envío está en unos seis lugares → una
      sola lista.
  - Al cerrar el dictado, conciliar: *Qué es un paquete* y el árbol de la ficha (pieza → fórmula),
    las "medidas" que quedan (función del precio, el gerente, el recálculo), "Felpa = Perfil hoja"
    frente a medida × cantidad, `BACKLOG.md` → *Presupuestos* (guarda lo escrito, las elecciones y
    las piezas opcionales) y *reventa de perfiles* (la lista sale del material múltiple), y que el
    vendedor ve los nombres de las opciones y los mensajes de alerta. Por el color: el costo pasa del
    insumo a cada variante (*El insumo*, *El costo del insumo vive en el catálogo*, los avisos de
    insumo nuevo y de 15/25/50 %), y la ficha suma el registro color y, en la versión, los colores que
    ofrece y el base.
  - Después: evaluar las fórmulas sin SQL dinámico.

## Al catálogo entran solo los que definen (2026-10-27)

**Técnica, Administración y el gerente (*Versiones y aprobación*) entran al módulo; vendedor, cliente,
producción y compras consumen lo que el catálogo fija desde su propio módulo.** Si alguien de otro módulo necesita ver algo de acá (ej:
producción, las fórmulas), se le da ese permiso a ese usuario: sin persona ni regla nueva. Quien carga
algo lo da de baja: Técnica, también cuando se decide dejar de vender un paquete; Administración, los
servicios fijos (*El servicio fijo*).

**El catálogo guarda el despiece y los precios con fecha; lo que otro módulo hace con eso se decide en
su ficha (2026-10-29).** Ej: qué fecha lleva cada ítem de un presupuesto, si vence, los descuentos, qué
nombre de insumo lee Producción, cómo Compras vincula proveedores.

## Sin entes (2026-10-30)

**El catálogo no tiene entes: paquete, versión, insumo, servicio fijo, categorías y servicios en % son
registros del módulo, sin dueño, sin privacidad por fila y sin chip.** Lo que ve cada uno lo da el
permiso, no quién lo cargó: Martín, de Técnica, saca una versión del paquete que armó Lucía.
Presupuestos, Compras y Producción apuntan con FK directa, el vendedor no entra al catálogo para abrir
un chip, y los avisos apuntan a cualquier tabla, como los de Monedas. Si una tarea tiene que
vincularse a un paquete, se lo registra como ente entonces: es sumar, no rehacer.

## Pestañas (2026-10-30)

**Cuatro pestañas, cada una una vista: Paquetes (técnica, gerente), Insumos y Servicios fijos
(técnica, administración, gerente) y Servicios en % (administración, gerente). Las categorías se
manejan en la pestaña de lo que contienen.**

**El costo se ve con una función, no con una pestaña: la tabla de costos la pide, y sin ella la base
no lo da.** Lucía, de Técnica, abre Insumos y ve "Float 4mm · m2 · 10 kg" sin costo; Ana, de
Administración, ve la misma lista con el costo y lo carga. Se descartó una pestaña Costos solo para
Administración: repetía la lista de insumos.

**Paquetes tiene dos funciones: armar (Técnica: crea paquetes y categorías de paquete, saca versiones,
edita el borrador, lo envía y lo retira, da de baja y reactiva) y aprobar (gerente: la lista "Por
revisar", el precio y su detalle de cualquier versión con las medidas que elige, aprueba y devuelve).
La vista sola muestra paquetes y despiece, sin precio ni botones.** Rodrigo, de producción, revisa cortes con la
vista sola. Armar no se divide: nadie arma paquetes sin poder enviarlos o darlos de baja.

**Insumos tiene dos funciones: cargar (Técnica: da de alta insumos y categorías de insumo, los edita
mientras ningún paquete los usa, los da de baja y los reactiva) y costos (Administración y gerente: ve
y carga el costo). Un insumo sin usar lo edita solo quien tiene cargar.** Lucía corrige su "Flaot
4mm"; Ana, que lo ve al cargarle el costo, le avisa: quien carga algo lo edita y lo da de baja. Se
descartó que Administración también lo edite mientras nadie lo usa: le cambiaría la categoría, que
define Técnica. El aviso de insumo nuevo va a quienes tienen costos, gerente incluido, y desaparece con
el costo.

**Servicios fijos tiene una sola función, fijos (Administración y gerente): da de alta con costo y
categoría, edita mientras ningún paquete los usa, carga el costo, da de baja y reactiva, y maneja las
categorías de servicio.** A diferencia del insumo, alta y costo los hace la misma persona y el servicio
nace con su costo: separarlas sumaba una función que nadie tendría sin la otra.

**Servicios en % tiene una sola función, porcentajes (Administración y gerente): da de alta, cambia
cualquier dato, da de baja y reactiva, y revierte un cambio de la historia. Revertir es un cambio más:
un valor nuevo con fecha que deja todo como estaba antes de ese cambio, y le avisa a quien lo hizo.**
Ana suma Herrajes a la Garantía de vidrio, el gerente lo revierte desde el aviso, y Ana se entera: sin
aviso, el lunes lo volvía a sumar.

**No hay función que ve y hace todo: no hay registros que alguien con la pestaña no vea (*Sin
entes*), como en Monedas.** El gerente tiene las cuatro pestañas con aprobar, costos, fijos y
porcentajes; no necesita armar ni cargar, y si arma, se le da armar (*Ningún permiso excluye a otro*).

**Ningún permiso del catálogo excluye a otro (2026-10-30).** En una empresa chica una persona arma y
aprueba, o arma y carga costos. Quien tiene armar y aprobar aprueba sus propias versiones: igual pasan
por "en revisión", donde ve el precio antes de publicar. Riesgo aceptado: nadie más revisa esa versión.
Se descartó que armar excluya aprobar: obligaba a dos personas donde hay una. Las de Técnica y las de
Administración tampoco se excluyen: con las dos no se ve ningún precio, que sale solo con aprobar, y
cada versión pasa por quien aprueba.

**Ningún permiso del catálogo requiere otro: nombre, unidad y categoría de insumos y servicios fijos se
leen desde cualquier pestaña del catálogo; lo protegido es el costo, que pide su función
(2026-10-30).** Rodrigo, de producción, con solo Paquetes, ve "Perfil marco 20x40 = 5.392 mm" en el
despiece. Se descartó que Paquetes requiera Insumos y Servicios fijos: le sumaba dos listas que no
usa, y una regla para algo que no esconde nada.

**Se delega todo menos aprobar (2026-10-30).** Lucía, delegadora de Técnica, le da a Martín Paquetes
con armar e Insumos con cargar sin pasar por el admin; el jefe de Administración reparte costos, fijos
y porcentajes igual. Aprobar es el control del catálogo: delegable, un gerente delegador hacía
aprobador a cualquiera de su equipo sin que lo decida el admin.

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

## Editor de paquete (2026-10-30)

**La pieza armada es un conjunto de materiales calculados mediante fórmulas aritméticas.**

**Variable: un valor que no está ligado a ningún material. Puede estar dentro de una pieza armada o por
sí sola, fuera de toda pieza armada.** Ancho y alto son variables por sí solas.

**De cada variable se elige si la ingresa el vendedor o no, y una variable puede llevar una fórmula
aritmética.**

**Una variable que ingresa el vendedor puede tener un predeterminado con fórmula; sin predeterminado
(ancho, alto) es obligatoria.** En una corrediza asimétrica, `ancho_hoja_1` se predetermina en
`(ancho + solape) / 2`: con ancho 2.000 aparece 1.025 y, si el vendedor no lo toca, sale simétrica. Lo
que escribe queda aunque cambie el ancho; si lo borra, vuelve al predeterminado. El presupuesto guarda
solo lo escrito, así un predeterminado sin tocar se recalcula con el ancho nuevo. Se descartó "0 =
hojas iguales" con un "si": era una convención que el vendedor tenía que conocer.

**A una variable se le pueden configurar condiciones (if) con comparadores, cada una con un mensaje de
alerta o un bloqueo. Con un bloqueo no se puede hacer uso del paquete.** Ej: ancho > 1000 → mensaje de
alerta o bloqueo. **Después del comparador va una operación aritmética** (ej: alto > ancho × 2).

**En toda operación aritmética se puede usar una variable u otro material del paquete: se toma su
resultado, no su fórmula, y se calcula a partir de él.** Ej: Felpa = Perfil hoja toma los 7.900 mm
que dio el perfil.

**Toda fórmula (de un material, de una opción o de una variable) puede llevar "si … entonces … si no
…", con los mismos comparadores de las condiciones, y redondear hacia arriba.** Una puerta con 3
bisagras hasta 2.100 de alto y 4 si pasa: `si alto > 2100 entonces 4 si no 3`, o una bisagra cada
700 mm: `redondear_arriba(alto / 700)`. Los "si" se encadenan para más escalones.

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

**El servicio fijo también es material: un material es un insumo o un servicio fijo.**

**Un material es único o múltiple.**
- **Único:** se selecciona un solo insumo.
- **Múltiple:** cualquiera de los insumos predeterminados en el paquete puede ocupar su lugar. Cuál lo
  ocupa se da de dos formas: lo elige el vendedor, o lo define el sistema con condicionales. Cuando
  elige el vendedor, se puede permitir "sin elección" y, al mismo tiempo, configurar el predeterminado.

**En un material múltiple, cada opción puede llevar su medida y su cantidad; la que no trae, la hereda
del material, cada una por separado. La medida solo se hereda con la misma unidad (2026-11-02).** En el
Mosquitero, la Tela (m2) hereda 1.500 × 1.200 y el Enrollable (u) no lleva medida: heredándola, cobraba
1.800.000 u. La Rueda simple hereda la cantidad 4 y la tándem trae 2, que también puede ser una fórmula.
Una opción de otra unidad en mm o m2 lleva su medida, y la base no deja enviar la versión sin ella.

**Un material múltiple puede seguir la elección de otro: sincronizado o en combo.**
- **Sincronizado:** con las mismas opciones. El vendedor elige en uno y los sincronizados quedan con
  la misma. Ej: en una corrediza asimétrica, el Vidrio de Hoja 2 sincronizado con el de Hoja 1.
- **Combo:** con opciones distintas, emparejadas. Elegir una en uno marca su pareja en el otro. Ej:
  Contravidrio en combo con Vidrio: Float 4mm → Contravidrio 4mm, Laminado 3+3 → Contravidrio 6mm.

Lo que sigue a otro no se le muestra al vendedor: elige una vez. En la base son un solo mecanismo: el
sincronizado es un combo donde cada opción tiene por pareja el mismo insumo.

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
- Reactivar la variante devuelve lo que había salido, sin versión nueva: se calcula con las variantes
  activas, sin guardar nada aparte.
- Los colores son una lista común (Blanco, Negro, Anodizado), para que el negro del perfil y el del
  accesorio sean el mismo. La define Técnica, como las categorías.
- Una variante nueva sin costo le avisa a Administración, como un insumo nuevo, y la base no deja
  enviar una versión que ofrezca un color con alguna variante sin costo.

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

**La pieza armada puede ser opcional.**

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
materiales; qué materiales entran en la suma lo define Técnica, como en el peso. La cantidad
multiplica el espesor.** El peso y el espesor
de cada material salen del insumo: el insumo suma el espesor a sus datos.

**Lo que toca el vendedor (una variable que ingresa, un material múltiple que elige, una pieza
opcional) Técnica lo marca primario o secundario. El primario aparece siempre al sumar el paquete; el
secundario va plegado en "Más opciones", resuelto con su predeterminado. La base deja marcar secundario
solo lo que tiene predeterminado: lo obligatorio es siempre primario.** Así no se carga al vendedor con
elecciones: en la corrediza carga ancho, alto y vidrio, y el ancho de hoja 1, el mosquitero y la
cortina quedan plegados. Si una alerta o un bloqueo salta por algo secundario, el mensaje se ve igual y
la sección se abre. El cliente, en erp-cliente, ve lo mismo.

**El paquete comienza vacío, y en ese estado no se puede publicar.** Lo frena la base.

## El insumo (2026-10-29)

~~**Cada insumo está en una subcategoría, y cada subcategoría en una categoría.**~~ Superada el
2026-10-29: sin subcategoría; ver la decisión siguiente.

**Cada insumo está en una sola categoría, sin subcategoría, como los paquetes (Vidrios → Float
incoloro 4mm, Float bronce 4mm; Herrajes → las ruedas 80kg de cada marca). El insumo tiene su costo,
peso, espesor y unidad de comercialización: mm, m2 o u.** Son categorías de insumo, distintas de las de
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
usa, solo cambian el costo (un valor nuevo con fecha) y si está activo: nombre, categoría, unidad, peso y
espesor quedan fijos, y si están mal se carga otro insumo (2026-10-29).** Mientras nadie lo usa, ningún precio,
versión ni presupuesto depende de él: un "Flaot 4mm" o un peso de 1,2 en vez de 0,12 se corrigen en el
momento. Una vez usado, la unidad cambia la cuenta, el peso y el espesor los de cada pieza armada
(*Editor de paquete*), la categoría qué servicios en % cobra, y el nombre
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

**Dar de baja un insumo saca de la venta solo lo que no se puede armar sin él (2026-11-02). Un paquete
activo cuya versión publicada lo usa se da de baja, en la misma operación, si el insumo es un material
único, si era la última opción de su material y este no permite "sin elección", o si lo elige el
sistema. Si no, el paquete sigue a la venta y se deja de ofrecer lo afectado. En una pieza opcional, lo
que bajaría el paquete deja de ofrecer solo esa pieza.** La regla anterior bajaba todo paquete que usara
el insumo: era anterior a las opciones, y el DVH bajaba la ventana con Float y Laminado disponibles.

```
Técnica da de baja                               En la Ventana corrediza
DVH, una opción del Vidrio                       no se ofrece más el DVH
Contravidrio 6mm, en combo con Laminado 3+3      no se ofrece más el Laminado 3+3, sin pareja
Tela, material único del Mosquitero opcional     no se ofrece más el Mosquitero
La última opción del Vidrio                      sale de la venta, salvo que permita "sin elección"
Escuadra, material único de una pieza fija       sale de la venta
Rueda 80kg, que el sistema elige según el peso   sale de la venta: nadie puede elegir otra
```

- **Lo que se deja de ofrecer se calcula, sin guardar nada, como el color.** La versión no cambia y se
  ofrecen las opciones con su insumo y su pareja activos. Reactivar el DVH lo devuelve, sin versión nueva.
- **Si era el predeterminado, la elección queda sin predeterminado y pasa a primaria**, como con el
  color base.
- **Dar de baja el paquete lo hace la base, no quien da la baja del insumo:** ningún paquete queda a la
  venta con un material que ya no se consigue. Las versiones en borrador o en revisión que usan el insumo
  no cambian, pero la base no deja enviarlas ni aprobarlas con él. Reactivar el insumo no reactiva los
  paquetes: cada uno vuelve cuando Técnica lo reactiva (*Versiones y aprobación*), como cualquier
  paquete de baja. Se descartó que el paquete también se calcule y vuelva solo, como la opción y el color
  (2026-11-02): que vuelva a la venta sigue siendo decisión de Técnica.

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
ninguna versión publicada lo usaba, no avisa: no cambia nada de lo que aprobó. También avisa cuando un
paquete solo deja de ofrecer una opción o una pieza opcional, y dice cuál (2026-11-02): esa oferta
también la aprobó el gerente.

**El paquete guarda por qué está de baja: a mano, o el insumo o servicio fijo que lo bajó
(2026-10-29).** Técnica ve "De baja por: Rueda 80kg Marca A" y sabe cuáles reactivar, sin confundirlos
con la "Ventana 4 hojas" que dio de baja a propósito en febrero. El aviso al gerente lista los que
siguen de baja por esa causa, y el que se reactiva sale de la lista. Se descartó no guardarlo: Técnica
buscaba a mano qué paquetes usaban la rueda, y el aviso no podía decir cuáles bajó esa baja.

~~**El peso por ahora solo se carga: cómo se usa se decide cuando un módulo lo necesite.**~~ Superada
el 2026-10-30: el peso y el espesor del insumo dan los de cada pieza armada (*Editor de paquete*).

**Las fórmulas se escriben en mm y el sistema pasa el resultado a la unidad de comercialización; el
costo de un insumo por mm se carga por metro.** Con una ventana de 1.500 × 1.200, el perfil marco da
5.392 mm y Administración carga $15.000 el metro; el vidrio 4mm lleva `ancho` y `alto` en sus dos
fórmulas (*Editor de paquete*) y el sistema pasa los 1.800.000 mm² a 1,8 m2. Nadie divide a mano. Costo aceptado: la fórmula no dice en
qué unidad sale, lo dice la unidad del insumo. Se descartó escribir todo en la unidad del insumo
(`ancho × alto / 1.000.000`, $15 por mm): un olvido multiplicaba el precio por mil o por un millón.

## El servicio fijo (2026-10-29)

**El servicio fijo (Instalación, Soldado) es un registro propio, no un insumo, y sigue las reglas del
insumo salvo el peso y el espesor, que no tiene.** Costo con fecha, unidad de comercialización (el soldado
por u), todo editable hasta que un paquete lo usa y después solo el costo y si
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
insumo*), y además le avisa a Técnica, también solo si bajó algún paquete. Antes de confirmar,
Administración ve cuántos paquetes lo usan: el número, no cuáles.** Un borrador que lo usa no avisa:
la base frena el envío (2026-10-30). Administración no ve paquetes y Técnica no hizo la baja: sin aviso, el
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

La función del precio usa el mismo cálculo que el despiece (*El despiece calculado*).

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

## El despiece calculado (2026-11-02)

**El despiece y el precio salen de un solo cálculo. Para un paquete con sus medidas y elecciones,
devuelve una fila por material (pieza, insumo elegido, color, medida, cantidad y total), todas las
variables, con el peso y el espesor de cada pieza, y los mensajes de alerta y bloqueo.** Con dos
cálculos, un arreglo en uno solo cobraba 4 bisagras y mandaba a cortar 3. La pestaña Paquetes ya
prometía el despiece, así que hace falta desde el primer día y no recién con Producción. Se descartó
marcar qué variables salen: era otra configuración, y el que curva el perfil necesita el radio (1.000),
no solo los 1.287 mm.

**Con un bloqueo, el despiece sale igual, con el mensaje, y el precio no da número.** Técnica ve qué dio
la cuenta que frenó el paquete, y nadie cotiza con él.

**Cada uno recibe una parte de ese cálculo.** Con la vista Paquetes, las filas sin costos. Con
`catalogo_aprobar`, además el detalle económico: el costo como se cargó (USD 14/m) y el importe de cada
fila, el subtotal de cada pieza y los servicios en %, paso por paso, hasta el precio de venta. Vendedor
y cliente, solo el número (*El precio sale de una función*).

**El detalle económico lo da `catalogo_aprobar`, no `catalogo_costos`.** El precio ya salía solo con
aprobar: Lucía con Paquetes y costos ve el despiece y los costos en sus pestañas, pero no el detalle ni
el precio. Aprobar no se delega, así que el detalle tampoco. Costo aceptado: quien aprueba ve los costos
en el detalle aunque no tenga `catalogo_costos`; hoy no cambia nada, porque el gerente tiene las dos.

**El despiece se pide de cualquier versión, borrador incluido, y sin fecha; el detalle económico, además,
a cualquier fecha.** La misma versión con las mismas medidas siempre da lo mismo: la enviada o publicada
no se edita, y los datos del insumo quedan fijos desde que un paquete lo usa. La fecha solo mueve los
costos. A diferencia del precio, elegir la versión no abre nada: el despiece no trae costos y la pestaña
ya las muestra todas (*Sin entes*). Tampoco depende de lo que hoy se vende: la baja del DVH no borra el
despiece de una versión que lo usa.

**La pestaña Paquetes abre en la versión publicada y cada versión muestra su estado.** Rodrigo, que
revisa cortes, no toma un borrador por lo vigente.

**A otros módulos, el catálogo solo les ofrece calcular cualquier versión con lo que le pasen.** Quién
lo pide, con qué permiso y qué versión usa se decide en la ficha de cada uno (*Al catálogo entran solo
los que definen*).

Ejemplo con datos inventados: https://claude.ai/artifact/6f2trHCaiVTdeqEa7bq4eS

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
sin fórmulas). El gerente ve el despiece, el precio con su detalle para las medidas que elige y qué cambió
respecto de la versión anterior, y la aprueba (publicado) o la devuelve (borrador). La publicada no se modifica: para
cambiarla se saca otra versión.

**Cada paquete tiene una sola versión abierta (borrador o en revisión) a la vez, y Técnica puede
retirarla de revisión: vuelve a borrador sin pasar por el gerente (2026-10-29).** Con la v3 en revisión
y una rueda discontinuada, Técnica la retira, le cambia la rueda y la reenvía: el gerente aprueba una
con los dos cambios, y "qué cambió" se compara siempre contra la publicada. Se descartó tener varias
abiertas, cada una copiada de la publicada: la v4 salía de la v2 sin el vidrio de la v3, y aprobar las
dos en orden publicaba la v4 sin él.

**El gerente devuelve una versión con un motivo escrito: la base no deja devolverla sin él
(2026-10-30).** El motivo queda en la historia de la versión y Técnica lo ve al abrir el borrador ("la
pieza Hoja sigue con Float 4mm"). Sin él, Lucía tenía la v3 de vuelta en borrador sin saber qué buscar.
Retirarla de revisión no pide motivo: la retira quien la va a cambiar.

**Enviar una versión a revisión les avisa a quienes aprueban, y el aviso desaparece cuando se
resuelve: aprobada, devuelta o retirada. Aprobarla o devolverla le avisa a quien la envió, con el
motivo si fue devuelta (2026-10-30).** Sin aviso, la v3 esperaba hasta que alguien le preguntara al
gerente, y un paquete bajado por un insumo seguía fuera de la venta hasta que Técnica se acordara de
mirar si se aprobó la versión nueva. Como `alta_por_aprobar` (`db_schema/notificaciones.md`). No le
avisa a todo Técnica: Martín no tiene nada que hacer con la v3 de Lucía.

**Obsoleto es solo la versión reemplazada: pasa sola cuando se publica la siguiente. Dejar de vender
es la baja del paquete (`activo = false`), y sus versiones quedan como estaban.** Reactivarlo vuelve a
vender su versión publicada sin pasar por el gerente, que ya la aprobó; la base no deja si no se
puede armar sin un insumo de baja (*El insumo*), y entonces va una versión nueva. Con el paquete de baja, aprobar una versión en
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
