# Catálogo — Versiones y aprobación

## Versiones y aprobación (2026-10-27)

**Cada paquete tiene versiones; una versión pasa por borrador → en revisión → publicado → obsoleto, y
la aprueba solo el gerente.** Técnica la envía a revisión y desde ahí no se edita, así el gerente
aprueba lo que vio. La base no deja enviarla si falta algo (*Qué frena el envío*). El gerente ve el despiece, el precio con su detalle para las medidas que elige y qué cambió
respecto de la versión anterior, y la aprueba (publicado) o la devuelve (borrador). La publicada no se modifica: para
cambiarla se saca otra versión.

**Al aprobar, con las medidas que elige el gerente, se ven juntas la versión publicada y la que está en
revisión, con la misma fecha (2026-11-02).** Las filas que cambian se resaltan: un `ancho − 20` por `ancho −
2` da 5.320 mm contra 5.392, y sin comparar el gerente veía un solo precio creíble. Con la misma fecha, la
diferencia sale solo de la versión y no de un costo que subió. Lo que está en una sola versión se indica, y
una variable obligatoria nueva se pide. Un paquete nuevo muestra solo su precio. Son dos cálculos, sin
guardar nada. Sin medidas de referencia guardadas: se suman si repetirlas se vuelve pesado.

**Qué frena el envío (2026-11-02).** Es la única lista: las decisiones de cada regla explican el porqué,
y lo que se suma se suma acá. La base lo revisa al enviar y de nuevo al aprobar, porque algo pudo darse
de baja en el medio.
- El paquete vacío, o una pieza sin materiales.
- Un insumo o servicio fijo de baja, o sin costo; un color ofrecido con alguna variante sin costo.
- Un material en mm o m2 sin su medida: un insumo en m2, sin ancho o sin alto; una opción de otra unidad,
  sin la suya.
- Una opción sin pareja en el material que la sigue (vacía; "ninguna" vale).
- Una fórmula con "si" sin "si no", o un material que define el sistema sin "si no".
- Una fórmula que usa lo que puede faltar o lo que ya no existe, o una referencia o un requisito circular.
- Un peso o espesor vacío en un material que la pieza cuenta.
- Algo marcado secundario sin predeterminado.
- Un nombre repetido: dos múltiples en una pieza, dos variables o dos piezas en la versión, o una variable
  que se llama como un material o como el peso o el espesor de una pieza.
- Un material sin insumo, un múltiple sin opciones o una lista de valores vacía.
- Un insumo con colores en una versión sin colores ofrecidos. Si todo es de color indistinto, no lleva.
- Colores ofrecidos sin base, o con una base que no está entre ellos.
- Un color ofrecido en el que el paquete no se puede armar. Si deja de poder armarse después de publicada,
  se deja de ofrecer, sin tocar la versión.
- Una categoría o un color de baja.

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
igual para el costo de una variante de insumo o de un servicio fijo y para el % de un servicio, medido contra el %
anterior (12 → 15 % es +25 %, naranja; 12 → 120 % es ×10, rojo): un % mal cargado mueve el precio de
todos los paquetes que lo llevan. El cambio se muestra escrito junto al color. Los errores típicos (un cero de más o de
menos, otra unidad) mueven el costo 5 veces o más y caen en rojo; el amarillo deja ver dígitos
invertidos ($1.250 → $1.520, +22 %). Que los cambios reales de lista (15–50 %) no pidan confirmar evita
que se confirme todo sin leer. Una variante sin costo anterior no avisa. Se descartó un solo umbral
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
