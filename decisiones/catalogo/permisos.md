# Catálogo — Permisos

## Al catálogo entran solo los que definen (2026-10-27)

**Técnica, Administración y el gerente (*Versiones y aprobación*) entran al módulo; vendedor, cliente,
producción y compras consumen lo que el catálogo fija desde su propio módulo.** Si alguien de otro módulo necesita ver algo de acá (ej:
producción, las fórmulas), se le da ese permiso a ese usuario: sin persona ni regla nueva. Quien carga
algo lo da de baja: Técnica, también cuando se decide dejar de vender un paquete; Administración, los
servicios fijos (*El servicio fijo*).

**El catálogo guarda el despiece y los precios con fecha; lo que otro módulo hace con eso se decide en
su ficha (2026-10-29).** Ej: qué fecha lleva cada ítem de un presupuesto, si vence, los descuentos, qué
nombre de insumo lee Producción, cómo Compras vincula proveedores.

**Cada función que el catálogo ofrece a otro módulo pide el permiso de ese módulo, que se nombra en su
ficha; hasta entonces, el precio solo se pide con `catalogo_aprobar` y el despiece con `catalogo_paquetes`
(2026-11-02).** La función del precio lee lo que quien llama no puede abrir: sin esta regla, quedaba abierta
a cualquiera que la llamara. La de paquetes a la venta y su formulario se escribe con Presupuestos, que
define su forma (`BACKLOG.md`).

## Sin entes (2026-10-30)

**El catálogo no tiene entes: paquete, versión, insumo, servicio fijo, categorías y servicios en % son
registros del módulo, sin dueño, sin privacidad por fila y sin chip.** Lo que ve cada uno lo da el
permiso, no quién lo cargó: Martín, de Técnica, saca una versión del paquete que armó Lucía.
Presupuestos, Compras y Producción apuntan con FK directa, el vendedor no entra al catálogo para abrir
un chip, y los avisos apuntan a cualquier tabla, como los de Monedas. Si una tarea tiene que
vincularse a un paquete, se lo registra como ente entonces: es sumar, no rehacer.

## Pestañas (2026-10-30)

**Cuatro pestañas, cada una una vista: Paquetes (técnica, gerente, quien revisa cortes), Insumos y Servicios fijos
(técnica, administración, gerente) y Servicios en % (administración, gerente). Las categorías se
manejan en la pestaña de lo que contienen.**

**El costo se ve con una función, no con una pestaña: la tabla de costos la pide, y sin ella la base
no lo da.** Lucía, de Técnica, abre Insumos y ve "Float 4mm · m2 · 10 kg" sin costo; Ana, de
Administración, ve la misma lista con el costo y lo carga. Se descartó una pestaña Costos solo para
Administración: repetía la lista de insumos.

**Paquetes tiene dos funciones: armar (Técnica: crea paquetes y categorías de paquete, saca versiones,
edita el borrador, lo envía, lo retira y lo descarta, da de baja y reactiva) y aprobar (gerente: la lista "Por
revisar", el precio y su detalle de cualquier versión con las medidas que elige, aprueba y devuelve).
La vista sola muestra paquetes y despiece, sin precio ni botones.** Rodrigo, de producción, revisa cortes con la
vista sola. Armar no se divide: nadie arma paquetes sin poder enviarlos o darlos de baja.

**Insumos tiene dos funciones: cargar (Técnica: da de alta insumos y categorías de insumo, los edita
hasta que se envía una versión que los usa, los da de baja y los reactiva) y costos (Administración y gerente: ve
y carga el costo). Un insumo sin usar lo edita solo quien tiene cargar.** Lucía corrige su "Flaot
4mm"; Ana, que lo ve al cargarle el costo, le avisa: quien carga algo lo edita y lo da de baja. Se
descartó que Administración también lo edite mientras nadie lo usa: le cambiaría la categoría, que
define Técnica. El aviso de insumo nuevo va a quienes tienen costos, gerente incluido, y desaparece con
el costo.

**Servicios fijos tiene una sola función, `catalogo_fijos_editar` (Administración y gerente): da de alta con costo y
categoría, edita hasta que se envía una versión que los usa, carga el costo, da de baja y reactiva, y maneja las
categorías de servicio.** A diferencia del insumo, alta y costo los hace la misma persona y el servicio
nace con su costo: separarlas sumaba una función que nadie tendría sin la otra.

**Servicios en % tiene una sola función, `catalogo_porcentajes_editar` (Administración y gerente): da de alta, cambia
cualquier dato, da de baja y reactiva, y revierte un cambio de la historia. Revertir es un cambio más:
un valor nuevo con fecha que deja todo como estaba antes de ese cambio, y le avisa a quien lo hizo.**
Ana suma Herrajes a la Garantía de vidrio, el gerente lo revierte desde el aviso, y Ana se entera: sin
aviso, el lunes lo volvía a sumar.

**Solo se revierte el último cambio de cada servicio, y pasa por los mismos controles que cualquier cambio
(2026-11-02).** Ana suma Herrajes el lunes y sube el % de 5 a 6 el martes; revertir lo del lunes volvía
también a 5 % sin que el gerente lo viera. El aviso del lunes dice "hubo otro cambio después" y lleva a la
historia: se revierte el del martes y después el del lunes. Si volver a un % de paso 3 lleva la suma a 100
o más, la base no lo deja. Costo aceptado: para sacar solo Herrajes se revierten los dos y se vuelve a
cargar el 6 %. Se descartó revertir solo los datos de ese cambio: si dos cambios tocaban el mismo dato, no
quedaba claro a qué valor volver.

**No hay función que ve y hace todo: no hay registros que alguien con la pestaña no vea (*Sin
entes*), como en Monedas.** El gerente tiene las cuatro pestañas con aprobar, costos,
`catalogo_fijos_editar` y `catalogo_porcentajes_editar`; no necesita armar ni cargar, y si arma, se le da
armar (*Ningún permiso excluye a otro*).

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
con armar e Insumos con cargar sin pasar por el admin; el jefe de Administración reparte costos,
`catalogo_fijos_editar` y `catalogo_porcentajes_editar` igual. Aprobar es el control del catálogo: delegable, un gerente delegador hacía
aprobador a cualquiera de su equipo sin que lo decida el admin.
