# Catálogo

**Se arma de cero: no se trae nada de la v1 ni de la v2 (2026-10-26).** La ficha y las decisiones de
este módulo salen solo de preguntas nuevas al usuario. No se lee `obsoletos/catalogo-descartado-2026-10-22/`,
no se compara con lo descartado y no se recupera nada de ahí: ni nombres, ni entes, ni estados, ni
tablas, ni soluciones del tipo "como estaba antes". Si una sesión sabe algo de esas versiones, no lo
propone. Si algo nuevo termina pareciéndose, tiene que ser porque volvió a salir de las preguntas.
El usuario descartó el diseño entero el 2026-10-22 y pidió fichar el módulo sin basarse en él. Lo que
este archivo no dice, no está decidido.

## Ficha del módulo

En armado, punto por punto con el usuario. Objetivo y personas aprobados el 2026-10-27. Entes,
estados, relaciones, acciones, eventos y el árbol de vistas: sin armar. Los entes se discutieron y se
descartaron para retomarlos de cero.

```
Módulo: catalogo
Objetivo: definir qué se puede vender y cómo se calcula: los paquetes, cada uno un despiece (sus
piezas armadas y las fórmulas de cada una), y su precio (los costos de insumos y servicios, y los
servicios en %).
Personas                qué ve · qué hace · qué NO ve
├── Técnica        — insumos, fórmulas y qué servicios en % hay · carga insumos, define las
│                    categorías, arma los paquetes (le pone a cada uno su categoría y marca qué
│                    piezas llevan cada servicio en %), da de baja insumos y paquetes · costos, %
│                    ni precios
├── Administración — insumos con su costo y las categorías · carga los costos de insumos y servicios,
│                    define los servicios en % · paquetes ni fórmulas
├── Vendedor       — NO entra: elige categoría y paquete desde Presupuestos · el precio final ·
│                    costos, % ni fórmulas
├── Cliente        — NO entra: lo mismo que el vendedor, desde erp-cliente
├── Producción     — NO entra: ve las piezas y sus medidas, servicios incluidos, desde Producción
│                    (módulo a hacer) · costos, % ni precios
└── Compras        — NO entra: ve los insumos y su costo desde Compras (módulo a hacer), para
                     comparar con las cotizaciones · %, precios ni fórmulas
Entes
└── a definir
```

Pendientes de la ficha, en este orden:
- **Tipos de cambio** (ARS · USD · EUR): dónde viven y cuál se usa. No se pisan (*Un presupuesto se
  recalcula como era*).
- **Versiones y aprobación**, propuesta del usuario en discusión: estados borrador · publicado ·
  obsoleto; Técnica confirma las fórmulas y Administración los %; un gerente que ve todo, precios
  incluidos, aprueba, y la versión aprobada no se modifica hasta sacar otra. Resuelve que nadie
  dentro del catálogo vea el precio final (Técnica no ve precios, Administración no ve paquetes: una
  fórmula olvidada daba un precio creíble que llegaba al vendedor, o directo al cliente por
  erp-cliente). Abierto: qué confirma Administración, si no ve paquetes y los % son generales; un
  paso "en revisión" para que no se edite mientras el gerente mira; obsoleto junta reemplazado y
  dejado de vender.
- **Entes**, de cero.

## Al catálogo entran solo los que definen (2026-10-27)

**Técnica y Administración entran al módulo; vendedor, cliente, producción y compras consumen lo que
el catálogo fija desde su propio módulo.** Si alguien de otro módulo necesita ver algo de acá (ej:
producción, las fórmulas), se le da ese permiso a ese usuario: sin persona ni regla nueva. Quien carga
algo lo da de baja: Técnica, también cuando se decide dejar de vender un paquete.

## Qué es un paquete (2026-10-27)

**Todo lo que se vende es un paquete: un conjunto de piezas armadas. Cada pieza armada es un conjunto
de fórmulas, y cada fórmula es un insumo o un servicio fijo con el cálculo de cuánto lleva según las
medidas del paquete.** Los nombres son los que usa la empresa.

```
Paquete: Ventana corrediza
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
- **No se reutilizan piezas armadas entre paquetes.** Habrá pocos paquetes y cada uno se calcula
  distinto.
- **Cada paquete tiene una sola categoría, según qué es el producto** (ej: Ventana corrediza → 2
  hojas, 3 hojas; Paño fijo → sus tipos). Las define Técnica y le pone una a cada paquete al armarlo.
  El vendedor, en Presupuestos, elige primero la categoría y después el paquete.
- **Hoy no se vende nada suelto.** El catálogo de un proveedor alimenta insumos para usar dentro de
  los paquetes. Para cuando revendan perfiles ya hay camino decidido (`BACKLOG.md`).

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

## Servicios: fijos o en % (2026-10-27)

**Un servicio fijo (ej: el soldado de los perfiles, propio) es una fórmula más: unidades × su costo.
Un servicio en % con mínimo (ej: comercialización) es monetario: no forma parte del despiece y entra
al armar el precio.** Cómo entra el de %: *Servicios en %*.

## Servicios en %: la base ordena el cálculo (2026-10-27)

**"El %" de Administración son los servicios en %, cada uno con su % y su base; cualquiera puede ser
opcional, y quien presupuesta decide si va. No hay ganancia aparte: va dentro de comercialización.**
Las bases, en el orden en que se calculan:

1. Todo el despiece (ej: comercialización), o las piezas armadas marcadas con ese servicio (ej:
   garantía de vidrio).
2. El subtotal: el despiece más los del paso 1 (ej: un recargo en la transición del modelo de negocio).
3. El precio final, despejado para que sea el % exacto (ej: IIBB). Varios se despejan juntos:
   monto / (1 − suma de los %).

```
Costo del despiece                                     $200.000
Garantía de vidrio    5 % de la pieza Vidrio ($60.000)   $3.000
Manipulación          5 % de la pieza Vidrio             $3.000
Comercialización     10 % del despiece (mín. $15.000)   $20.000
Subtotal                                               $226.000
Transición            4 % del subtotal                   $9.040
IIBB                  3 % del precio final               $7.269   (235.040 / 0,97)
Precio de venta                                        $242.309
```

Dentro de un paso ningún servicio se calcula sobre otro: el orden lo dan los pasos, así Administración
nunca ordena servicios y sacar un opcional solo cambia lo que se calcula después.

**La marca va en la pieza armada, no en el insumo ni en el renglón.** Los insumos no tienen
clasificación y Administración no ve las piezas: la marca la pone Técnica al armar la pieza (ve el
nombre del servicio, no su %). El % toma la pieza entera; para cobrarlo sobre un solo material, ese
material va en su propia pieza. Una pieza sin marcar no cobra el servicio, como una fórmula olvidada.

**Un servicio en % puede tener mínimo, y elige si lo compara por paquete o por presupuesto.** Por
paquete, contra el servicio de cada unidad, y la diferencia queda dentro de su precio. Por
presupuesto, contra la suma del servicio en todos los ítems, y la diferencia va en un renglón aparte
que pasa por los pasos siguientes: una obra con muchas piezas chicas no paga el mínimo en cada una.
Si el servicio no aplica (ninguna pieza marcada, opcional no elegido), no hay mínimo. Los que se
despejan no tienen: son el % exacto del precio. La cuenta del presupuesto entero la hace una función
del catálogo, así la regla vive en un solo lugar.

```
Garantía de vidrio 5 %, mínimo $10.000 por presupuesto
2 Ventanas corredizas   pieza Vidrio $60.000 c/u   →  $6.000
3 Paños fijos           pieza Vidrio $20.000 c/u   →  $3.000
1 Puerta ciega          sin pieza marcada          →  no cuenta
Mínimo de garantía de vidrio            $10.000 − $9.000 = $1.000, en renglón aparte
```

**Un servicio en % tiene un % general y, si hace falta, uno distinto por categoría** (*Qué es un
paquete*). La categoría dice qué es el producto, no cuánto se cobra, así que Técnica clasifica sin ver
el %, como cuando marca las piezas. Administración ve los nombres de las categorías y carga solo las
excepciones. Una categoría sin % propio usa el general, así ningún paquete queda sin %. Las
categorías ya existen para el vendedor; el % por categoría espera un caso real (`BACKLOG.md`).

## El precio sale de una función, sin despiece (2026-10-27)

**Vendedor y cliente reciben solo el precio de cada paquete y el renglón del mínimo por presupuesto:
ni despiece, ni costos, ni desglose de los servicios en %.** Una función del catálogo recibe el
paquete, las medidas y los opcionales elegidos, lee lo que quien llama no puede abrir y devuelve solo
el número, como `obras_contar`. Así lo que no ven (*Personas*) no depende de ocultarlo en pantalla. Ven
el nombre de cada opcional para elegirlo, no su %. El cliente, desde erp-cliente, recibe lo mismo.

## Un presupuesto se recalcula como era (2026-10-27)

**Un presupuesto se recalcula con las condiciones de su fecha: lo que forma el precio no se pisa.**
Cambiar un costo, un % o un tipo de cambio agrega un valor nuevo con fecha, y el anterior queda; la
versión publicada de un paquete no se edita, se saca otra. El presupuesto guarda su fecha y la versión
de cada paquete, y la función del precio usa lo que valía a esa fecha: si el cliente cambia una medida
en un presupuesto de marzo, se le respeta el precio de marzo.

Se descartó que cada presupuesto guarde copia de los costos y los %: la copia tendría que vivir en el
catálogo para que el vendedor no la lea, y un paquete sumado a un presupuesto viejo no tendría sus
insumos en ella.
