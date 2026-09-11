# Vista Misión

## UI de pasos y vista Misión

**"Agregar paso" pasó a llamarse "Convertir en hilo".** El menú de una tarea suelta ya usaba ese label para `convertirTareaEnHilo`, que no agrega ningún paso: convierte la tarea en hilo para poder sumarle tareas. Con pasos reales en el módulo el nombre viejo pasaba a mentir. Tercera colisión del mismo término — las plantillas también llaman "pasos" a sus items (`plantillaItemSchema`), que son títulos ordenados sin bloqueo; eso quedó sin tocar.

**"Crear siguiente paso" aparece solo en la cola de la cadena** (`posicion === total`) y solo si la tarea tiene hilo. La unique parcial de `paso_anterior_id` no deja bifurcar, así que ofrecerlo en el medio sería ofrecer un `23505`.

**Bloqueada esconde "Completar" y la opción "En progreso", no "Cancelada".** Espejo exacto de `validar_paso_previo`, que solo corta esas dos transiciones. Cancelar tiene que seguir disponible o una cadena con un paso trabado no se cierra nunca. El panel además dice cuál es el paso que la traba, en vez de dejar el botón gris sin explicación.

**El panel muestra la cadena entera, no solo la previa.** El pedido era "ver tareas previas"; mostrar la lista completa con la posición marcada cuesta lo mismo y contesta también "cuánto falta". El estado del paso actual sale del estado optimista del panel y no de la fila del server — misma regla que `tareaLabels.ts`: la misma tarea no puede leerse distinto según dónde se la mire.

**`agruparCadenas()` mantiene contigua cada cadena dentro del hilo.** El orden por temperatura se respeta para elegir dónde arranca la cadena, pero sus miembros salen juntos y en orden. Sin eso una cadena se lee como tareas sueltas y pierde lo único que la distingue de un hilo.

**`esDeUsuario` y `esActiva` salieron a `tareaFiltros.ts`.** El primero vivía en `TareasListaView`, el segundo inline en `MetricasResumen`; Misión necesitaba los dos. Regla de "si existe en más de un lugar, se extrae" — no se duplicó para la vista nueva.

**Misión renderiza `TareaCard`, no una tarjeta propia.** Toda la superficie de acciones (completar, estado, temperatura, panel de detalle) ya vive ahí; una tarjeta "de misión" sería una segunda cara de la misma tarea para mantener sincronizada. Lo propio de la vista es el recorte y la navegación de a uno.

**El índice de Misión se recorta, no se resetea.** Al completar la tarea actual la cola se acorta y la misma posición pasa a mostrar la siguiente — que es lo que se espera de una vista "de a una". Un `useEffect` que resetee a 0 mandaría al usuario de vuelta al principio en cada completada.

**Misión esconde las tareas de hilos pospuestos**, no solo las tareas pospuestas: si el hilo espera, su contenido no es "lo que toca ahora". El estado vacío dice cuántas tareas están esperando un paso previo — si no, una Misión vacía con trabajo bloqueado se lee como una vista rota.

## Retoques de UI de Misión

Todo en `MisionView.tsx`. No se tocó `TareaCard` ni ninguna query: la vista sigue siendo recorte + navegación sobre lo que ya lee la Lista.

**Columna centrada `max-w-2xl`.** Una isla sola estirada a los 1280px del `<main>` no se lee como foco, se lee como una lista de un elemento. Misión es la única vista del módulo con un solo item en pantalla, así que el ancho lo pone ella y no el layout.

**Flechas ← → recorren la cola.** Se ignoran si hay un `dialog[open]` (el panel de detalle y los modales viven en el top layer, fuera de este árbol) o si el foco está en un `INPUT`/`SELECT`/`TEXTAREA`. El clamp del índice usa `total`, no el `posicion` del render: apretar de más al final dejaría el índice colgado lejos y habría que apretar N veces para volver.

**Barra de progreso = posición en la cola, no trabajo hecho.** No hay dato de "cuánto del total completé" sin leer `tareas_eventos`; la barra dice dónde estoy parado en la cola de hoy, que es lo mismo que el contador de texto y evita que el contador sea el único ancla visual.

**Línea de contexto (proyecto · hilo) arriba de la tarjeta.** Ni la isla ni su meta lo muestran — no es duplicación, es dato que en la Lista aporta el agrupamiento y acá no existe. El proyecto sale del hilo cuando la tarea tiene hilo (`CHECK (hilo_id IS NULL OR proyecto_id IS NULL)`: la tarea con hilo no guarda `proyecto_id`).

**La descripción se muestra en la vista, no solo en el panel.** Es la única excepción a "Misión renderiza `TareaCard` y nada más" y es deliberada: texto plano de solo lectura, sin estado ni acciones, así que no hay una segunda cara que sincronizar (el motivo real de aquella decisión). Una vista de a una que obliga a abrir un panel para leer qué hay que hacer no es una vista de a una.

**"Sigue: <título>" debajo de la tarjeta.** Una tarjeta sola no comunica que hay una cola detrás; el contador lo dice en número y esto en contenido.

**Las bloqueadas pasan de contador a lista desplegable (`Bloqueadas`, local al archivo).** Antes el estado vacío decía "N tareas esperan un paso previo" sin decir cuáles ni a qué esperan — el dato está en `PasoEnCadena.cadena[posicion - 2]`, que ya se calcula. El mismo bloque aparece con cola llena y con cola vacía; es el único caso del módulo donde saber qué te frena importa más que la tarea que tenés adelante.

**El estado vacío pasa a `.empty-state`.** Era el único del módulo con markup propio (texto centrado suelto). Ícono según el caso: `CircleCheck` verde si de verdad no queda nada, `Lock` ámbar si lo que queda está todo bloqueado — no son la misma noticia.
