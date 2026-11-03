# Catálogo — El precio

## Servicios: fijos o en % (2026-10-27)

**Un servicio fijo (ej: el soldado de los perfiles, propio) es un material más: unidades × su costo.
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
paquete y lo que carga el vendedor (variables, elecciones, piezas opcionales y color) y los servicios en
% opcionales elegidos, lee lo que quien llama no puede abrir y devuelve solo
el número, como `obras_contar`. Así lo que no ven (*Personas*) no depende de ocultarlo en pantalla. Ven
el nombre de cada servicio opcional para elegirlo, no su %, los nombres de las opciones y los mensajes
de alerta y bloqueo. Qué paquetes ve el cliente, si ve el precio y si elige los servicios opcionales se
decide al fichar `erp-cliente` (`BACKLOG.md`).

**La versión y la fecha con que se calcula un precio nunca las elige quien llama (2026-10-29).**
Vendedor y cliente reciben la versión publicada con los valores de hoy, o al recalcular, los que la
base lee del presupuesto guardado. El gerente, que ve todo, puede pedir cualquier versión y fecha (para
aprobar, una en revisión). Si la función aceptara una fecha, un vendedor pedía "marzo" y cotizaba con
los costos de marzo, y desde erp-cliente se cotizaba un borrador.

## El IVA lo suma Presupuestos (2026-10-29)

**El precio del catálogo es sin IVA: lo suma quien presupuesta, en Presupuestos. Por eso los costos de
insumos y servicios fijos se cargan sin IVA**: con IVA, el presupuesto lo cobraría dos veces. El IIBB
del paso 3 se despeja sobre ese precio sin IVA (*Servicios en %*).

Archivos: `BACKLOG.md` → *Presupuestos*.

## Un presupuesto se recalcula como era (2026-10-27)

**Un presupuesto se recalcula con las condiciones de su fecha: lo que forma el precio no se pisa.**
Cambiar un costo, un servicio en % (cualquier dato, no solo el %) o un tipo de cambio (en Monedas)
agrega un valor nuevo con fecha, y el anterior queda; la
versión publicada de un paquete no se edita, se saca otra. El presupuesto guarda su fecha y, de cada
paquete, la versión y lo que cargó el vendedor, y la función del precio usa lo que valía a esa fecha: si el cliente cambia una medida
en un presupuesto de marzo, se le respeta el precio de marzo.

Se descartó que cada presupuesto guarde copia de los costos y los %: la copia tendría que vivir en el
catálogo para que el vendedor no la lea, y un paquete sumado a un presupuesto viejo no tendría sus
insumos en ella.

**Cada fila de la historia de un servicio en % es el servicio entero, baja incluida (2026-11-02).** `catalogo_porcentajes`
es solo a qué apuntan otros módulos; el resto está en `catalogo_porcentajes_valores`. Un presupuesto de marzo cobra lo que
en marzo estaba activo aunque el servicio se haya dado de baja en abril: con la baja fuera de la historia, no se podía
saber. Las categorías van en un arreglo, como foto de ese momento: no hay tabla aparte que copiar en cada cambio y cada
reversión.

**El nombre de un servicio en % es único entre los activos (2026-11-02).** Como el resto del catálogo, y porque el vendedor
elige los opcionales por su nombre.

**Sin costo a la fecha pedida, no hay precio: el cálculo nunca toma 0 ni busca el costo más cercano
(2026-11-02).** A un presupuesto de marzo se le suma en noviembre una Ventana cuya v3 usa el Float 5mm,
cargado en abril: con $0 el precio salía barato sin que nadie lo notara. El vendedor lee "Este paquete no
tiene precio a la fecha del presupuesto"; quien tiene `catalogo_aprobar` ve qué insumo falló, también al
pedir el detalle de una fecha vieja. El despiece no usa costos y sale igual. Qué versión y fecha lleva un
paquete sumado a un presupuesto viejo lo decide Presupuestos (`BACKLOG.md`).

## Moneda (2026-10-29)

**El presupuesto elige en qué moneda sale el precio (en USD, también si oficial o blue), y el catálogo
convierte todo a esa moneda con los tipos de cambio de la fecha del presupuesto, que lee de Monedas
(`decisiones/monedas.md`), mínimos incluidos.** El vendedor marca USD y la ventana
sale "USD 182" sin que nadie convierta a mano. La función del precio recibe la moneda junto con el
paquete y lo que cargó el vendedor (*El precio sale de una función*).

**Cada monto que carga Administración lleva su moneda, elegida en cada carga: el costo de una variante de insumo o
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
