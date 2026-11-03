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
