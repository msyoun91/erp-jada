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
(CA006, CA007); quien no edita ve la lista sin acciones.

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

**La lista filtra por categoría y por estado (a la venta, sin publicar, de baja) en vez de agrupar, y cada fila lleva a una
versión: la abierta si hay, si no la publicada.** Es el mismo patrón que Insumos, con paginado y total. Arriba, para quien
aprueba, "Por revisar": las versiones en revisión. Archivos: `PaquetesView.tsx`, `PaqueteAltaModal.tsx`.

**El paquete no tiene página propia: su detalle es el de una versión (`/catalogo/paquetes/versiones/<id>`), la ruta de los
avisos.** Ahí están las otras versiones para saltar entre ellas, la causa de la baja y los botones del paquete (baja,
reactivación, duplicar), además de los del ciclo de esa versión. Una sola ruta de detalle, la que ya usan los avisos.
Archivos: `VersionView.tsx`, `VersionAcciones.tsx`.

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
(`catalogo_version_revisar`). Archivos: `components/editor/`.

**Cada cosa se guarda sola, en su panel, sin un "guardar todo".** Un borrador puede quedar a medias (*Lo que nunca tiene
sentido se frena al guardar*): guardar de a una deja ver el error de cada fórmula (CA001) en el momento en que se escribe.
Un material múltiple nuevo deja su panel abierto para sumarle las opciones.

**Los schemas limpian lo que no corresponde al tipo antes de guardar: las piezas fijas sin requisito ni secundario, las
variables que no carga el vendedor sin rango ni lista, el material único sin nombre.** Así el formulario puede esconder campos
sin que un valor escondido haga saltar un CHECK de la base. Un nombre repetido (23505) se traduce por tabla en `actions.ts`:
la base no dice de qué.

**El orden se cambia con flechas, que renumeran a los hermanos; sacar pide confirmación y dice que se lleva lo que depende.**
No vuelve (CA015).

**Las parejas de un material que sigue a otro se eligen en una lista, una por cada opción del que elige: insumo, "ninguna" o
vacía. "Mismas opciones" las llena para el sincronizado.** En la base son un solo mecanismo (*Un material múltiple puede
seguir la elección de otro*).

**El primer color que se suma a una versión queda como base; hacer base a otro apaga el anterior.**

**Los casos de prueba se guardan desde la calculadora de la ficha ("Guardar como caso"), con lo cargado tal cual, y se sacan
desde su lista.** La calculadora ya arma la entrada de un vendedor; un formulario aparte la repetía.

**No se construyó copiar una pieza suelta.** Sus variables chocarían con los nombres únicos (*Qué es un paquete*), y duplicar
el paquete o sacar una versión nueva desde otra ya ahorran la recarga. Se suma si una carga real lo pide.

## Ejemplos en los campos difíciles (2026-11-03)

**Las fórmulas, los tipos de material, las parejas, las condiciones, la unidad, el peso y espesor, el % en bloque, el paso y
el mínimo llevan un "?" con un ejemplo (`Ayuda`).** Los textos viven todos en `modules/catalogo/ejemplos.tsx`, con la misma
ventana corrediza y los números de esta carpeta: si una regla cambia, el ejemplo se corrige en un solo lugar. Las fórmulas de
ejemplo van sin punto de miles, como las acepta la base (`despiece.md` → *Las fórmulas se calculan sin SQL dinámico*). Los campos simples
(nombre de un insumo, categoría, moneda) no lo llevan: un "?" en cada campo deja de mirarse.

**En la opción, ancho, alto y área dicen mm, no m2.** Decían "(m2)" por el tipo de insumo que los usa, y se leía como la
unidad de la fórmula, que siempre da mm. Archivos: `components/editor/OpcionPanel.tsx`.
