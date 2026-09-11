# La vista Lista

## La vista Lista es de tareas, el hilo agrupa (sin SQL)

Pedido de usuario: *"si tengo una tarea en hilo ajeno asignado me aparece el hilo entero en mi menú y eso me trae confusión"*, más *"a veces necesito ver los otros trabajos para realizar el mío"*. Solo UI: cero SQL, cero queries nuevas, RLS intacta.

**Revierte parcialmente** la sección *"Módulo tareas — isla compartida, panel de proyecto y edición de hilo"*, donde quedó escrito que la vista Lista no muestra tareas del hilo, solo el panel. No es el mismo diseño volviendo: aquella decisión mostraba **todos** los pasos y por eso molestaba; ahora la Lista muestra **solo los tuyos**, con los ajenos plegados detrás de un toggle.

**Un rol por nivel, sin superposición:** el proyecto es etiqueta (badge), el hilo es agrupador (encabezado de grupo, nunca fila) y la tarea es la única fila accionable. De ahí sale todo lo demás:

- **Se van las secciones `Hilos` / `Tareas sueltas`.** Un solo stream ordenado por temperatura, con filas sueltas y grupos intercalados. Conservarlas dejaba al usuario navegando por contenedor en vez de por urgencia, que era el bug.
- **El grupo se ordena por la temperatura de su paso propio más caliente**, así lo urgente sube tenga hilo o no. Eso necesitó exponer `comparar` desde `useOrdenTemperatura` (`ordenar` no sirve: las dos cosas a comparar viven en listas distintas). Un grupo sin pasos propios no compite y cae al fondo.
- **El contador dice `N tareas`**, no `3 hilos · 9 sueltas`. El hilo agrupa, no cuenta como ítem.
- **Colapsado se ven solo tus pasos; expandido, todos en orden de secuencia** (`created_at` asc, **no** por temperatura) — la pregunta que contesta el expandido es "¿ya está listo lo que necesito para arrancar el mío?", y eso es cronología, no urgencia. No hay columna `orden` en `tareas` y `agregarTareasDesdePlantilla` inserta en orden de plantilla, así que `created_at` **es** la secuencia. No se agrega `depende_de` ni `orden`: la vista contesta la pregunta sin modelar dependencias.
- **Los pasos ajenos van como línea fina de solo lectura (`PasoAjeno.tsx`), no como isla.** La diferencia de peso visual es lo que impide que vuelva el problema original: con el hilo expandido, los tuyos son los únicos que parecen tareas.
- El estado de expansión es local y se pierde al recargar. Persistirlo se agrega cuando moleste.

**Nada de esto necesitó backend.** Los pasos ajenos ya llegaban al cliente (`puede_ver_hilo`, `sql/013`: una asignación activa en cualquier paso te da el hilo entero) y sus notas también (`getListaTareas` las precarga embebidas). Leer la nota de un paso ajeno sí, escribirla no — lo resuelve `tareas_notas_insert` (`sql/013`) más el `puedeAgregar={esAsignado}` que ya estaba. Por eso el preload de `tareas_notas` en `queries.ts`, marcado como desperdicio en la auditoría previa, **se conserva**: es exactamente lo que evita un request por paso ajeno.

### `relacion.ts` — fuente única de "de quién es este trabajo"

`relacionTarea` / `relacionHilo` reemplazan `esDeUsuario()` de `TareasListaView` y el bloque de badge duplicado en `TareaCard`. `creado_por` **no** cuenta (espejo del `USING` de `tareas_select`), así que se borró la rama `Creador` del badge — contradecía `sql/013`, donde crear dejó de dar autoridad y visibilidad. El dueño del hilo es un rol, no una asignación: estar involucrado en el hilo es tener alguna de sus tareas.

### Filtro: segmented control Míos / Involucrado / Todos

Segundo eje, independiente del select de usuario: el select dice *de qué usuario*, el segmented dice *qué relación*. El modelo ya daba el corte gratis — `crearTareaSchema` obliga `responsable ∈ asignados`, así que "responsable" y "asignado" son disjuntos. Solo aparece con un usuario elegido; sin filtro de usuario no hay relación que recortar.

**Arregla un bug de paso.** `hilosFiltrados` mezclaba los dos ejes (`textoMatch && h.responsable_id === asignadoId`): buscar el título de un hilo donde estás involucrado pero no sos dueño lo escondía, salvo que alguna de sus tareas matcheara el texto también. Separar `coincideTexto` de `coincideRelacion` lo elimina.

**Sin filtro de usuario ("Todos los usuarios") la vista no tiene perspectiva**: las filas aparecen porque son visibles, no por tu relación con ellas. Entonces `relacionCon` pasa a `null` — no hay paso ajeno que plegar, no hay badge de relación que explicar y el encabezado del grupo muestra solo `M/N completados`. Antes caía a `usuarioActualId`, que contradecía "pediste ver todo".

### Arrastre: umbrales deduplicados y estado optimista extraído

- `PROXIMA_DIAS` y `estadoVencimiento()` suben a `tareaLabels.ts`. El umbral estaba en tres lugares (`TareaCard`, `TareaDetailPanel`, hardcodeado en `MetricasResumen`) y el bloque de vencimiento duplicado verbatim entre isla y panel.
- **`useTareaOptimista` (nuevo)**: el estado/temperatura optimistas salieron de `TareaCard`. La misma tarea ahora se muestra de dos formas (isla y línea fina) y ambas abren el mismo panel; con una copia del optimismo por componente, un admin con `tareas_gestionar_ajenas` abriendo un paso ajeno habría visto la toolbar con handlers que no hacen nada. Una sola fuente para las dos caras.
- `Isla` gana slot de `children` (hoy solo los pasos de un hilo) — el grupo es la isla del hilo con su contenido adentro, no un contenedor nuevo.
- `relacion.test.ts` corre con `node --test` (Node despoja los tipos solo). Sin runner de tests en el repo y sin agregar uno: por eso `allowImportingTsExtensions` en `tsconfig.json`, que con `moduleResolution: bundler` no cambia nada del build.

### Efecto colateral aceptado

`ProyectoDetailPanel` usa el mismo `HiloCard`, así que sus hilos también muestran los pasos propios inline. No se tocó el archivo y el comportamiento es consistente con la Lista: el hilo agrupa en todos lados o en ninguno.

## Cierre de la auditoría de UI (Lista, plantillas, Misión)

**La Lista arranca ocultando lo terminado.** Toggle "Ocultar terminadas", prendido por defecto: sin él, el histórico completo se acumulaba en la vista para siempre — atenuado y al fondo, pero sin salida. Esconde tareas sueltas terminadas y hilos cerrados o con todos sus pasos terminados; un hilo vacío sigue siendo trabajo por empezar y se muestra.

**Adentro de un hilo no se filtra nada.** Los pasos hechos son el contexto que explica en qué anda la cadena — la pregunta que contesta el hilo expandido es "¿ya está listo lo que necesito?", y esconder lo completado la deja sin respuesta. El filtro es de filas de primer nivel, no de contenido.

**El filtro cuenta como filtro para el estado vacío.** Con todo escondido, la vista decía "Sin tareas todavía / Creá la primera" sobre una cuenta llena de trabajo terminado. Ahora `hayFiltro` incluye las filas ocultas y el mensaje dice cuántas hay y cómo verlas.

**`esTerminada` lee el estado del server, no el optimista.** Completar una tarea con el filtro prendido no la hace desaparecer abajo del dedo: se va con el `revalidatePath`, no con el click.

**La búsqueda de la Lista mira también la descripción**, como ya hacían Proyectos y Plantillas. `coincideTexto` pasa a variádica (`...textos: (string | null)[]`) en vez de duplicar la comparación por campo.

**Los pasos de una plantilla se reordenan con ↑↓** (`useFieldArray.move`). Desde que la plantilla encadena, el orden es la regla — y cambiarlo obligaba a retipear todos los títulos de ahí para abajo. Botones, no drag & drop: no hay librería de dnd en el proyecto y dos flechas resuelven el caso.

**Las bloqueadas de Misión son islas, no filas de texto.** Se renderiza `TareaCard` con su `cadena` y debajo la línea "Espera a «X»": saber qué te frena sin poder abrir lo que te frena era medio camino, y una tarjeta propia hubiera sido una segunda cara de la tarea para mantener sincronizada — el mismo motivo por el que Misión ya usaba `TareaCard`.

**`textoAntiguedad()` en `tareaLabels.ts`.** "Creada hace 0 días" es la fecha de hoy dicha mal y `TareaDetailPanel` además decía "hace 1 días". Un solo texto para la isla, el panel y `MetricasResumen` (que pasa de "Hace N días" a "Creado hoy / hace N días").

**Los estados vacíos de los paneles dicen qué hacer.** "Sin tareas todavía" pasa a nombrar el botón que las crea; en el panel de proyecto solo cuando el usuario puede trabajar ahí (si no, el botón no existe y la instrucción sería mentira).

**No se pone ventana temporal en `getListaTareas` — decidido, con motivo.** La query trae todas las tareas activas con todas sus notas en cada carga de Lista, Misión y Proyectos, y eso crece sin techo. Pero recortar por fecha rompe cosas que hoy funcionan: `cadenasDePasos` arma la cadena con las filas que recibe, así que dejar afuera un paso viejo ya completado corre las posiciones ("Paso 2 de 3" pasa a "Paso 1 de 2"), desalinea el bloqueo y falsea los contadores "N/M terminados". El filtro de terminadas resuelve el problema que se ve (la vista llena de historial) sin tocar los datos que la vista necesita para calcular. Cuando el volumen pese de verdad, el primer paso barato es acotar la **precarga de notas** (`tareas_notas` en `getListaTareas`), no las tareas: `NotasSection` ya sabe pedirlas sola cuando no llegan precargadas. Con el detalle de que los pasos previos del panel leen esas notas precargadas, así que ahí habría que pedirlas por paso al abrir.

---

## Temperatura

### De slider a tres niveles (sin SQL)

Reemplaza el mecanismo descrito en "Orden por temperatura: solo UI, sin columna nueva" y en "Temperatura con rango". El criterio de orden no cambia; cambia cómo se elige el valor.

**Se elige entre Alta / Media / Baja, no entre 100 valores.** El número nunca significó nada para el usuario — `temperaturaRango()` ya existía justo porque "🌡 61" no se lee, y la UI mostraba `Alta (61)`. Un control de 100 posiciones para elegir entre tres etiquetas era precisión inventada. Se va el `(61)` de la isla y del panel.

**La columna sigue siendo `int` 1-100 con su CHECK; cada nivel escribe el centro de su tercio (85 / 50 / 20).** Sin migración, sin tocar `actualizarTemperatura`, y los valores arbitrarios que ya están en la base siguen cayendo en el nivel que les toca. Por eso el botón activo se deriva de `temperaturaRango(temperatura).label`, **no** de `temperatura === nivel.valor`: un 61 histórico tiene que iluminar "Media", no ninguno. Se descartó migrar a enum: obligaba a SQL, backfill y a tocar la action, a cambio de nada que el usuario vea.

**`TEMPERATURA_NIVELES` vive en `tareaLabels.ts`, al lado de `temperaturaRango`.** Los tres niveles y sus umbrales son la misma regla mirada desde los dos lados (escribir / leer); separarlos deja abierta la puerta a que un botón escriba un valor que caiga en otro rango.

**Desempate explícito en `useOrdenTemperatura.comparar`: vence antes → más vieja.** Con 100 valores el orden era total de hecho; con tres niveles hay empates grandes y el desempate caía en el orden del query (`created_at` desc, la más nueva arriba). Lo que vence antes manda dentro del nivel, y entre las que no vencen gana la más vieja. Es más honesto que "la puse en 91 en vez de 90".

**`cambiarTemperatura` y `commitTemperatura` se funden en una sola función async.** Un clic *es* el cambio completo: no existe el "mientras se arrastra" que obligaba a separar input de commit y a colgar `onMouseUp`/`onTouchEnd`/`onKeyUp`/`onBlur` del `<input type="range">` (un range no tiene evento "listo"). El panel recibe `onTemperaturaChange` en vez de las dos props.

**El rollback ahora también revierte el override de orden.** `useTareaOptimista` reseteaba `temperatura` cuando el server rechazaba, pero no avisaba a `useOrdenTemperatura`: la fila quedaba ordenada por un valor que no existía. Se arregló al fundir las funciones, no antes, porque con el slider el commit fallaba después de N onChange y no había un "valor anterior" único.

**Costo aceptado: se pierde el ranking fino dentro de un nivel.** Nadie lo estaba usando como ranking; el desempate por vencimiento cubre el caso real ("de estas tres altas, ¿cuál primero?").

**En Misión las flechas ← → dejan de competir con nada.** Los botones no consumen flechas y solo existen dentro del panel (un `dialog`), que ya estaba excluido.

---

## Descripción y plazo en la isla (del prototipo `obras-tareas.html`, sin SQL)

**La descripción se ve en el listado.** `tareas.descripcion` existía, viajaba en el `select("*")`
y solo se leía abriendo el panel: dos tareas que se llaman parecido eran indistinguibles hasta
hacer click. Va abajo del título, 13px `text-secondary`, `line-clamp-2` — en un listado la
descripción ubica la tarea, no la explica. La pasan las tres islas (tarea, hilo, proyecto): la
cara compartida no se parte por un campo que las tres tienen.

**El plazo es una columna, no un dato más de la meta.** `plazo` se dibuja al final de la
cabecera, así que es lo único que alinea en vertical a lo largo del listado — que es lo que
permite escanear "qué se me viene" sin leer fila por fila. La fecha exacta sigue en la meta: no
es el mismo dato dos veces sino la misma cuenta (`estadoVencimiento().diasVencimiento`, fuente
única) contestando dos preguntas distintas —cuándo vence y cuánto falta—, y solo una de las dos
se puede escanear. Reusa `fechaClase`, así que no hay un segundo criterio de "vencida".

Solo mientras la tarea está activa: cuánto faltaba para vencer una tarea ya completada no cambia
ninguna decisión.

**Lo que no se trajo del prototipo:** el tick de completada a la izquierda del título —el badge
de estado ya lo dice, y un círculo no distingue `en_progreso` de `cancelada`— y los chips de
persona/obra vinculada, que necesitan columnas nuevas en `tareas`.
