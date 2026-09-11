# Tutorial guiado por vista (`sql/019_tutorial.sql`)

Tooltips en secuencia sobre los elementos reales de cada vista: la primera vez se abren solos, y el botón `?` al lado del `<h1>` los vuelve a pasar cuando el usuario quiera. Sin librería nueva — `<dialog>` + `showModal()`, el mismo mecanismo de top layer que `Modal.tsx` y `RightPanel.tsx`.

## El código del paso es también su selector

`PasoTutorial.codigo` es la clave que se guarda en `usuario_tutorial.paso` **y** el ancla en el DOM (`[data-tour="tareas_lista_isla"]`). Un solo identificador en vez de dos que puedan desincronizarse: renombrar el paso rompe el ancla en el mismo commit, no seis meses después.

El guion vive en `tutorialPasos.ts` (`PASOS_POR_RUTA`), al lado de `tareaLabels.ts` — texto, no lógica.

## Un paso sin ancla se saltea y queda sin ver

El tutorial no lista pasos: pregunta al DOM cuáles existen ahora. Un paso cuyo elemento no está — porque el permiso no está dado (`tareas_proyectos_crear`), porque el filtro que lo muestra está apagado (el segmentado de relación), o porque todavía no hay datos (la lista de tareas) — no se muestra **y no se marca como visto**.

Consecuencia buscada: cuando después se habilita el permiso, el paso aparece como pendiente y el tutorial se abre solo con eso. Explicar hoy un botón que el usuario no tiene sería enseñarle una función que no puede usar; guardar "ya lo vio" sería peor, porque se la perdería para siempre.

Es también la razón por la que el estado es *por paso* y no un booleano *por vista*: con un flag por vista, un permiso otorgado más tarde no tiene forma de volver a contarse.

## Persistencia en Postgres, no en `localStorage`

`usuario_tutorial` con RLS directa (`usuario_id = auth.uid()`), mismo criterio que `usuario_widgets`: preferencia estrictamente propia, sin `tiene_permiso` de por medio, así que el server action usa el cliente normal. `localStorage` era más barato pero cuenta por navegador — el mismo usuario en la máquina de la obra volvería a ver el tutorial entero.

Sin columna `activo`: la fila significa "visto" y nunca se borra ni se desactiva. Volver a ver el tutorial es el botón, no un reset de datos.

`marcarTutorialVisto` no llama a `revalidatePath`: los pasos vistos solo se leen al montar el layout y el cliente ya sabe cuáles marcó. Falla en silencio — no es una acción del usuario sino la contabilidad de qué se le mostró, y el peor caso es que el tutorial se vuelva a ofrecer.

## Un solo componente en el layout, no uno por vista

`Tutorial.tsx` se monta en `tareas/layout.tsx` y elige el guion con `usePathname`. El botón tiene que estar al lado del `<h1>`, que es del layout, y navegar entre tabs no vuelve a montarlo — de ahí la copia local de lo visto (`vistosLocal`), sin la cual volver a una tab recién vista lo reabría.

El `<h1>` pasa a vivir en un flex con el botón; el `mb-4` se mueve al contenedor. La estructura obligatoria del encabezado (ícono + nombre del `ICON_MAP`) no cambia.

## El ancla de los tabs sale de la prop que ya existía

`ModuleTabs` recibía `modulo` sin usarla. Ahora emite ``data-tour={`${modulo}_tabs`}`` — el componente sigue siendo genérico, no aprende nada de tareas, y cualquier módulo que sume tutorial tiene el ancla de sus tabs gratis. Cuando hay una sola tab el componente devuelve `null` y el paso se saltea solo.

## Foco por sombra, no por recorte

El elemento señalado se rodea con un `<div>` de `box-shadow: 0 0 0 9999px rgba(7,11,20,.55)` — el mismo color de backdrop del resto del sistema. Oscurece todo salvo el agujero y de paso intercepta los clicks a la página. Un ancla más alta que la pantalla (la lista entera) se recorta al viewport: sin eso el agujero se sale y el globo no tiene dónde apoyarse.

## El guion explica lo que no se ve, no lo que se lee

No hay paso para el buscador ni para la paginación: una lupa con placeholder no necesita tutorial. Los pasos son para lo que la interfaz no puede decir sola — que "Míos" e "Involucrado" son disjuntos, que ser miembro de un proyecto es quién puede recibir tareas y no quién lo ve, que el orden de los pasos de una plantilla es lo que encadena, que una tarea bloqueada no entra en la cola de Misión.

Efecto secundario buscado: ningún componente de `components/ui/` recibe un `data-tour`. Todas las anclas están en elementos que el módulo ya renderizaba.
