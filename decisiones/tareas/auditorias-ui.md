# Auditorías de UI del módulo

Los hallazgos app-wide de estas mismas tandas están en `decisiones/global/ui.md`.

## Pasos previos legibles

**El panel de una tarea con pasos muestra los previos enteros y con sus notas.** `TareaDetailPanel` ya listaba la cadena completa (título + badge de estado); los pasos anteriores al actual dejan de truncar y cuelgan sus notas debajo. Los posteriores siguen siendo una línea: todavía no dicen nada. Las notas ya viajan precargadas por `getListaTareas` (`tareas_notas`), así que no hay query nueva — solo aplica a tareas encadenadas, no a tareas sueltas ni a pasos de hilo sin `paso_anterior_id`, que no tienen sección de cadena.

**La cadena ahora también existe en la vista Lista.** `HiloCard` calcula `cadenasDePasos(tareasDelHilo)` y se la pasa tanto a `TareaCard` como a `PasoAjeno`. Antes solo Misión y `HiloDetailPanel` la pasaban: abrir el mismo paso desde la Lista no mostraba ni "Paso 2/3", ni "Bloqueada", ni los pasos previos. Rompía la regla del propio módulo (`tareaLabels.ts`): la misma tarea no puede leerse distinto según dónde se la mire.

**El modal automático "¿Cerrar hilo?" respeta permisos.** `HiloCard` lo disparaba en cualquier card montada al completarse el último paso, incluso para un asignado sin autoridad sobre el hilo — `cerrarHilo` moría en la RLS. Ahora usa el mismo `puedeGestionar` que `HiloDetailPanel` para ofrecer la acción.

**Una sola definición de "terminada": `esTerminada()` en `tareaFiltros.ts`.** El contador de la isla contaba solo `completada` y el cierre automático del hilo miraba `completada || cancelada` — la card decía "2/3 completados" y saltaba igual el modal de cierre. `contarCompletadas` pasa a `contarTerminadas` y el copy a "N/M terminadas" en hilo y proyecto. Una cancelada no deja trabajo pendiente; contarla como faltante era mentir sobre lo que queda por hacer.

**El select de estado muestra "En progreso" aunque la tarea esté bloqueada, deshabilitado.** `reabrir_hilo_en_tarea` puede bloquear una tarea que ya estaba en progreso; sin su opción el `<select>` caía en "Pendiente" y mostraba un estado que la tarea no tenía. Se ve, no se puede elegir — espejo de `validar_paso_previo`, que corta la transición pero no borra el estado actual.

**`ESTADO_LABEL` deja de estar duplicado.** `DeshacerConversionModal` y `AuditoriaView` tenían copias locales (una de ellas parcial: sin `completada`/`cancelada`) mientras `tareaLabels.ts` es la fuente. `recurrencia_cantidad` en `TareaFormPanel` pintaba `input-error` sin renderizar nunca el mensaje: caja roja sin motivo.

## Feedback y formularios

**Toda acción que sale bien lo dice.** `quitarDeHilo`, `convertirEnHilo`, `moverAHilo` y las cuatro desactivaciones (tarea, hilo, proyecto, plantilla) solo toasteaban el error; el éxito era cerrar el panel — y `quitarDeHilo` ni eso, porque no cierra nada. Regla del guide: el usuario nunca se queda preguntando si funcionó.

**Cancelar una tarea pide confirmación.** Era un cambio de `<select>` y la tarea salía de todas las colas; completar, que es menos destructivo, ya tenía modal. Solo `cancelada` pasa por `ConfirmModal` — pendiente y en progreso son reversibles y no la sacan de ningún lado. El select vuelve solo al estado real al abrirse el modal porque es controlado (`value={estado}`).

## Jerarquía visual de la isla (auditoría de diseño, sin SQL)

**La temperatura ordena la lista y ahora se ve: barra izquierda de 3px en `Isla`.** `useOrdenTemperatura` es el eje primario de orden en Lista y Misión, pero la temperatura era un span gris más dentro de `meta` — y "Baja" no tenía color siquiera. Tarjetas idénticas apiladas sin decir por qué esa está arriba. La barra cuesta cero altura, se lee de un vistazo y reusa la escala semántica: `temperaturaRango()` pasa a devolver también `barra` (rampa neutro → ámbar → rojo, no verde: la temperatura es urgencia, no un estado que esté bien o mal). Solo la tarea la pasa — hilo y proyecto no tienen temperatura propia.

**Con la barra, el span de temperatura sale de la meta.** No es un `title=` encubierto ni contradice "en touch no hay hover" (`P1 responsive y legibilidad`): la barra es permanente, no un estado de hover, y el nivel sigue existiendo como texto y como control en el panel, a un tap de distancia. Lo que se saca es la repetición, no la información.

**Dos niveles en la meta de `TareaCard`.** Podía llevar 7 spans `t-caption` grises del mismo peso: nada distinguía "vence mañana" de "vino de la app X", y `flex-wrap` no es jerarquía — es la misma información en más líneas. Ahora arriba va lo que cambia la decisión de qué hacer ahora (vencimiento o antigüedad, pospuesta, avatares) a 13px `font-medium`; abajo el contexto (privada, recurrencia, origen) unido en una sola línea `t-caption` con `·`. Sigue siendo texto — un ícono pelado habría revertido de callado la decisión de P1.

**Un conteo no es un estado.** `Paso N/M` deja de ser badge y pasa a texto `t-caption`, igual que "N/M terminados" en hilo y proyecto. Los badges quedan para estado y bloqueo, que sí son la situación de la tarea; cuatro pills del mismo tamaño en la misma fila no jerarquizaban nada.

**Misión usa la misma isla con `grande`, no una tarjeta propia.** Título en `t-h2`, más aire, contexto desplegado en vez de comprimido en una línea. Es una variante de `Isla`, no un componente nuevo: la razón por la que Misión ya usaba `TareaCard` (no mantener una segunda cara de la tarea sincronizada) sigue valiendo.

**La isla avisa que se abre: chevron permanente.** Era un `<button>` sin borde de hover, sin ícono, sin nada — y `GUIDE_DESIGN` prohíbe el hover como única señal. De paso el título deja de ser un `<p>` dentro de un `<button>`, que no es HTML válido.

**Atenuar con color, no con `opacity`.** `opacity-60` bajaba junto el contraste de texto, borde y badges: una tarea terminada quedaba con texto a ~2.8:1, abajo de AA. Ahora la isla atenuada cambia a `bg-bg-subtle` y su título a `text-text-tertiary`.

**El selector de nivel usa la escala semántica, no el navy de marca.** Elegir "Alta" lo pintaba `btn-primary` (#011F51) y al cerrar el panel la tarjeta lo mostraba rojo: dos lenguajes de color para el mismo valor. El estado activo sale de `temperaturaRango(nivel.valor).selector`, así que la escala tiene un solo dueño.

**El contador de la Lista sale de `Paginacion`, como sus tres tabs hermanas.** Proyectos, Plantillas y Auditoría lo renderizan dentro del componente (fila `justify-between`); la Lista lo tenía como un `<p>` suelto, a otra altura y otra alineación. Las props de paginado pasan a ser opcionales: sin ellas el componente es solo el contador. **La Lista sigue sin paginar** — decidido en "P2 — búsqueda, paginación y contador", esto toca dónde se dibuja el contador, no si se pagina.

**Formularios en dos columnas para los campos cortos** (design system §8: grid 2 columnas / 14px gap). `TareaFormPanel` apilaba ocho campos full-width en un panel de 448px. Proyecto + Visibilidad y Vencimiento + Temperatura entran de a dos y cortan el scroll a la mitad; en `HiloFormPanel`, Proyecto + Visibilidad. Abajo de `sm` vuelven a apilarse. Los otros paneles de form del módulo (proyecto, plantilla, usar plantilla, posponer) quedan en una columna: tienen uno o dos campos cortos y una lista alta, y apretar el campo principal a 197px no compra nada.

**Los presets de vencimiento son chips, no botones.** `btn btn-secondary btn-sm` los dejaba con el mismo peso que el "Cancelar" del footer del mismo panel. Son atajos de relleno del campo de arriba, no acciones del formulario.

**La fila de Auditoría se apila abajo de `sm`.** A 390px la cadena `Creada → Asignada → Completada` tomaba tres líneas y truncaba el título a ~10 caracteres.
