# Catálogo — Pantallas

## Insumos y Servicios fijos (2026-11-03)

**Las dos pestañas son una sola vista con el tipo (`InsumosView`): lista con buscador, categoría, estado y, para quien ve
costos, el orden "costo más viejo primero"; tocar una fila abre su ficha en un panel lateral.** Son la misma tabla y las
mismas reglas (*El servicio fijo*): cambian el permiso que edita, que el servicio no tiene peso, espesor ni color, y que nace
con su costo. Archivos: `modules/catalogo/components/InsumosView.tsx`, `InsumoFicha.tsx`, `InsumoFormPanel.tsx`,
`FijoFormPanel.tsx`.

**La pantalla no marca qué datos de un insumo quedaron fijos: deja editar y la base frena con CA006, cuyo mensaje dice qué
hacer.** Técnica no siempre tiene la vista Paquetes, así que no puede saber qué versión lo usa; el control vive en un trigger
DEFINER (*El control de los datos fijos mira todas las versiones*). Un peso o espesor vacío se completa por la misma edición.

**Pasar un insumo a colores, o volver a indistinto, es una tilde de la edición; los colores se suman y se quitan en la ficha.**
Entre las dos cosas el insumo queda con colores y sin ninguno, que la base admite: la ficha lo avisa ("sumá al menos uno").
Quitar un color es la baja de su variante y pasa por el mismo aviso que la baja del insumo; sumar uno que estuvo lo reactiva
con sus costos (`catalogo_variante_sumar`).

**Los costos se cargan en un panel, uno o la lista filtrada entera, en dos pasos: se escriben y se revisan antes de guardar.**
La revisión es `catalogo_costos_niveles`: cada fila con su anterior y su nivel (15/25/50 %), y si hay rojas se confirman de una
vez con un modal. Una fila vacía no se guarda; "Cambiar todos (%)" aplica el % sobre el costo vigente de cada fila, en su
moneda, y deja sin tocar las que no tienen. Pegar desde una planilla no se construyó: hoy no hay un caso que lo pida.
Archivos: `CostosPanel.tsx`.

**Categorías y colores se manejan en un panel lateral de la pestaña de lo que contienen, el mismo para los dos
(`ListaNombresPanel`).** Siguen la misma regla (nombre fijo con algo adentro, baja sin nada activo) y la frena la base
(CA006, CA007); quien no edita ve la lista sin acciones. Se abren desde el menú ⋯ de la barra, no con un botón cada
uno: en mobile, junto a los filtros, eran cinco renglones antes del primer insumo.

**La baja de un insumo, de un color o de un servicio fijo muestra antes lo que va a pasar (`catalogo_baja_aviso`), y se
confirma aunque no afecte nada.** Con la vista Paquetes se ven los nombres; sin ella, los números (*Antes de confirmar la
baja…*). Archivos: `BajaModal.tsx`.

## Servicios en % (2026-11-03)

**La lista agrupa por paso, que es el orden del cálculo, y dice cuánto suman los del paso 3; cada servicio abre su página
(`/catalogo/porcentajes/<id>`), que es adonde llevan los avisos de un cambio.** Ahí están el valor que rige, cambiar, baja y
reactivación, y la historia. Archivos: `PorcentajesView.tsx`, `PorcentajeFicha.tsx`, `PorcentajeFormPanel.tsx`.

**La historia muestra cada valor entero, no una lista de qué cambió.** El texto de qué cambió vive en la base
(`catalogo_porcentaje_cambio`, el `motivo` del aviso); repetirlo en la pantalla era la misma regla dos veces. El % lleva su
nivel contra el anterior, como los costos.

**"Revertir" está solo en la fila del último cambio.** La base frena cualquier otro (CA005); mostrarlo en todas invitaba a
tocar uno que no se puede.

**El formulario esconde las categorías fuera del paso 1 y el mínimo en el paso 3, y el schema las limpia al guardar.** Cambiar
de paso y volver no borra lo escrito; lo que no corresponde no llega a la base.

## Paquetes (2026-11-03)

**La lista filtra por categoría y por estado (a la venta, sin publicar, de baja), y cada fila lleva a una versión: la abierta
si hay, si no la publicada.** Agrupar es opcional (*Agrupar por categoría*). Es el mismo patrón que Insumos, con paginado y total. Arriba, para quien
aprueba, "Por revisar": las versiones en revisión. Archivos: `PaquetesView.tsx`, `PaqueteAltaModal.tsx`.

**El paquete no tiene página propia: su detalle es el de una versión (`/catalogo/paquetes/versiones/<id>`), la ruta de los
avisos.** Ahí están las otras versiones para saltar entre ellas, la causa de la baja y los botones del paquete (baja,
reactivación, duplicar), además de los del ciclo de esa versión. Una sola ruta de detalle, la que ya usan los avisos.
Archivos: `VersionView.tsx`, `VersionAcciones.tsx`.

**A la vista van los pasos del ciclo (editar, enviar, retirar, aprobar, devolver, versión nueva, reactivar); descartar,
duplicar y dar de baja van en el menú ⋯.** Con los cinco botones iguales, "Dar de baja el paquete" quedaba en rojo al lado de
"Editar". Con "Enviar a revisión" deshabilitado, abajo dice por qué: el `title` del botón no se ve en touch.

**El despiece se mira con una calculadora que abre con el primer caso de prueba, y es la misma para la vista sola y para
quien aprueba: con `catalogo_aprobar` el resultado es el detalle del precio, que incluye el despiece.** Cada cálculo es una
llamada a la base y no guarda nada. Una versión en revisión se calcula junto a la publicada con la misma entrada y la misma
fecha, y las filas que cambian, aparecen o faltan se marcan (*Al aprobar…*). Los servicios en % opcionales se tildan desde el
resultado: el gerente puede no tener la pestaña Servicios en %. Archivos: `Calculadora.tsx`, `DespieceResultado.tsx`,
`entrada.ts`.

**Los casos de prueba se ven con su resultado (se calcula, bloquea o no se puede, y por qué); se cargan en el editor.**

**Precios de referencia es una página de Paquetes (`/catalogo/paquetes/referencia`), en la moneda principal, con hoy contra
hace 7, 30 o 90 días.** Reusa `FiltroDias`. Archivos: `ReferenciaView.tsx`.

**En la historia de una versión, quién hizo cada paso se ve solo si la RLS de `usuarios` lo deja ver.** Lo que importa ahí es
el motivo de la devolución, que se ve siempre; sumar una función que devuelva nombres de otros equipos no tenía un caso.

## Editor del borrador (2026-11-03)

**El editor es una página aparte (`/catalogo/paquetes/versiones/<id>/editar`), solo para un borrador y con `catalogo_armar`;
cualquier otra versión vuelve a su ficha.** Arriba, lo que frena el envío, que la base recalcula con cada guardado
(`catalogo_version_revisar`). Con tres cosas o menos, la lista arranca abierta. Archivos: `components/editor/`.

**Cada cosa se guarda sola, en su panel, sin un "guardar todo".** Un borrador puede quedar a medias (*Lo que nunca tiene
sentido se frena al guardar*): guardar de a una deja ver el error de cada fórmula (CA001) en el momento en que se escribe.
Un material múltiple nuevo deja su panel abierto para sumarle las opciones.

**Los schemas limpian lo que no corresponde al tipo antes de guardar: las piezas fijas sin requisito ni secundario, las
variables que no carga el vendedor sin rango ni lista, el material único sin nombre.** Así el formulario puede esconder campos
sin que un valor escondido haga saltar un CHECK de la base. Un nombre repetido (23505) se traduce por tabla en `actions.ts`:
la base no dice de qué.

**El orden se cambia con Subir y Bajar, que renumeran a los hermanos; sacar pide confirmación y dice que se lleva lo que
depende.** No vuelve (CA015). Los tres van en el menú ⋯ de la fila, como pide *P1 — acciones de fila siempre en `OverflowMenu`*
(`decisiones/global/ui.md`): como íconos sueltos ocupaban un tercio del ancho en mobile y la fórmula de la fila se partía en
cuatro renglones.

**Las parejas de un material que sigue a otro se eligen en una lista, una por cada opción del que elige: insumo, "ninguna" o
vacía. "Mismas opciones" las llena para el sincronizado.** En la base son un solo mecanismo (*Un material múltiple puede
seguir la elección de otro*).

**El panel de un material múltiple muestra solo las fórmulas que usan sus opciones; sin opciones, todas, aclaradas.** El
múltiple no guarda unidad: la tiene cada opción. Con el Vidrio todo en m2, Medida no aparece; un campo que ya tiene un valor
sigue a la vista, para no esconder un dato. Archivo: `MaterialPanel.tsx`.

**La regla se arma con botones que escriben donde quedó el cursor: palabras, opciones del material y nombres; a mano se
puede seguir escribiendo.** Había que memorizar las opciones, y un nombre mal escrito recién se veía en lo que frena el
envío. Se descartó autocompletar (más código, incómodo en el celular) y armarla con listas (una regla anidada igual pide
texto, y quedaban dos formas de hacer lo mismo). Archivos: `Nombres.tsx`, `MaterialPanel.tsx`.

**El primer color que se suma a una versión queda como base; hacer base a otro apaga el anterior.**

**Los casos de prueba se guardan desde la calculadora de la ficha ("Guardar como caso"), con lo cargado tal cual, y se sacan
desde su lista.** La calculadora ya arma la entrada de un vendedor; un formulario aparte la repetía.

**No se construyó copiar una pieza suelta.** Sus variables chocarían con los nombres únicos (*Qué es un paquete*), y duplicar
el paquete o sacar una versión nueva desde otra ya ahorran la recarga. Se suma si una carga real lo pide.

**Una variable que no carga el vendedor elige en una sola lista de dónde sale: "De una fórmula" o "Según Vidrio · Hoja" (2026-11-04).**
Una lista evita un interruptor más y un estado "según, sin material". Lista todos los múltiples y la base dice por qué no vale alguno
(lo frena el envío): filtrarlos acá repetiría esa regla. Archivos: `components/editor/VariablePanel.tsx`.

**Los valores se cargan en el panel de la variable, uno por opción, y cada uno se guarda al salir del campo; borrarlo lo saca (2026-11-04).**
Cuelgan de la variable guardada y de ese material: al elegir o cambiar el material, Guardar deja el panel abierto para cargarlos. En un
material que sigue a otro, cada fila dice de dónde viene ("6mm · con Laminado", "10mm · suelta"), porque dos parejas pueden ser el mismo
insumo con valores distintos.

**La calculadora lista cada insumo una sola vez en lo que sigue a otro y arranca en "La pareja de lo elegido" (2026-11-04).** El vendedor
elige un insumo, y la base decide la fila (`paquete.md` → *la pareja es una sugerencia*). "Más opciones" no se pliega acá: es del
formulario de Presupuestos. Archivos: `components/Calculadora.tsx`, `entrada.ts`.

**La comparación al aprobar no pide nada propio (2026-11-04).** `calcular` manda la misma entrada a las dos versiones, y lo elegido a mano
va en ella.

## La calculadora se distingue de lo que solo se lee (2026-11-04)

**En la ficha de la versión, la calculadora va en una tarjeta titulada "Probar el despiece".** Con un rótulo igual al de las secciones
de solo lectura, no se notaba que ahí se podía cargar algo. Archivos: `VersionView.tsx`.

## Baja en el menú (2026-11-04)

**En la ficha de un insumo, un servicio fijo o un servicio en %, "Dar de baja" va en el menú ⋯.** En rojo al lado de "Editar" pesaba más
que lo que se hace todos los días, igual que en la versión del paquete. Archivos: `InsumoFicha.tsx`, `PorcentajeFicha.tsx`.

## Selector de versiones (2026-11-04)

**Las versiones del paquete se eligen con botones, no con badges; la actual va marcada con el color de marca.** Eran iguales a los
badges de estado, que no se tocan. Archivos: `VersionView.tsx`.

## Acciones antes que filtros (2026-11-04)

**En Paquetes, Insumos y Servicios fijos, las acciones van arriba y los filtros debajo, y las categorías siempre en el menú ⋯.** Con
los filtros primero, "Nuevo…" quedaba enterrado, y cada pestaña ponía "Categorías" en otro lado. "Precios de referencia" queda a la
vista porque es una pantalla aparte. Archivos: `PaquetesView.tsx`, `InsumosView.tsx`.

## Un solo botón primario en el borrador (2026-11-04)

**"Editar" es el primario mientras algo frena el envío; sin nada que lo frene, lo es "Enviar a revisión".** Con los dos iguales, la
ficha no decía cuál era el paso que sigue. Archivos: `VersionAcciones.tsx`.

## Filas que se abren (2026-11-04)

**Toda fila que abre algo lleva una flecha `›` a la derecha.** El cambio de fondo al pasar el mouse era la única señal, y en touch
no existe: las listas parecían texto. Archivos: `PaquetesView.tsx`, `InsumosView.tsx`, `PorcentajesView.tsx`, `ReferenciaView.tsx`,
`editor/Fila.tsx`.

## Sin "?" en los campos (2026-11-03)

**~~Los campos difíciles llevan un "?" con un ejemplo~~: se retiró a pedido del usuario, con `components/ui/Ayuda.tsx` y
`modules/catalogo/ejemplos.tsx`.** Quedan las aclaraciones que están siempre a la vista en cada formulario. El texto viejo
queda en git.

**En la opción, ancho, alto y área dicen mm, no m2.** Decían "(m2)" por el tipo de insumo que los usa, y se leía como la
unidad de la fórmula, que siempre da mm. Archivos: `components/editor/OpcionPanel.tsx`.

## Opciones del material a la vista (2026-11-03)

**Las opciones de un múltiple se ven desde que se elige el tipo, debajo del nombre y antes de la regla; "Sumar opción" guarda
solo el material si hace falta.** Antes aparecían después de guardar y abajo de todo, y parecía que no había dónde cargarlas.
Antes de la regla porque la regla nombra opciones, y sus botones ya las muestran. El formulario se parte en dos alrededor de
la sección: los botones de `Fila` lo enviarían. Archivos: `components/editor/MaterialPanel.tsx`.

**La unidad del insumo decide qué medidas se ven, en el material y en la opción; lo opcional se agrega a pedido.** En u solo la
cantidad (+ Medida de corte), en mm la medida, en m2 ancho y alto (+ Área), en un servicio en m2 el área (+ Ancho y alto). Lo
que ya tiene un valor se ve siempre. Todo a pedido dejaba olvidarse un campo obligatorio hasta el envío; todo a la vista
parecía obligar a cargar ancho y alto en una rueda. Sin opciones todavía, un múltiple no muestra medidas. Archivos:
`components/editor/CamposMedida.tsx`.

## Agrupar por categoría (2026-11-03)

**Insumos, Servicios fijos y Paquetes tienen un toggle "Agrupar por categoría": la lista se ordena por categoría y cada una es
un plegable con su total.** Arranca agrupada (2026-11-04: pedido del usuario; antes arrancaba sin agrupar); destildar vuelve a la lista corrida. Se ordena antes de paginar, así una
página corta un grupo como mucho en sus bordes, y el total del grupo es el de todas las páginas. Agrupada, la fila no repite
su categoría. El paquete se agrupa por la categoría de la versión que muestra la fila. Archivos:
`components/PorCategoria.tsx`.

