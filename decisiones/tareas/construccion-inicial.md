# Construcción inicial

> **Único archivo cronológico de la carpeta: la construcción del módulo, 2026-08.** Leer solo si la
> tarea toca algo que nombran sus secciones. Partes de la UI que describe ya no existen; lo superado
> quedó como puntero de una línea y el texto original, en git. Las trampas generales que se
> descubrieron acá (RLS, forms, React Compiler) están en `GUIDE_DB.md` y `GUIDE_TYPESCRIPT.md`.
>
> **Renombres que atraviesan todo el archivo:** `TareaRow` se partió en `TareaCard` (isla)
> + `TareaDetailPanel` (acciones y detalle); `HiloCard` perdió el listado de tareas, que
> pasó a `HiloDetailPanel`. Un párrafo que dice `TareaRow` habla de los dos.
>
> **Antes de esto:** un primer intento (rama `tareas-v1`) se revirtió en `sql/004_rollback_tareas.sql`
> porque cambiaron los requisitos (proyectos + visibilidad en cascada, multi-asignado,
> `responsable_id`, `temperatura`). No comparte schema con lo actual.

## UI del módulo (Lista, Proyectos, Plantillas, Auditoría)

Backend (SQL + `types.ts`/`permissions.ts`/`queries.ts`/`actions.ts`) venía de una sesión anterior, ya corrido en Supabase. Esta sesión agregó la UI completa (`modules/tareas/components/` + `app/(erp-app)/tareas/`).

~~**"Usar plantilla" vive en `HiloCard`, no en la vista Plantillas.**~~ **Superado por `sql/053`** — ver *Plantillas de sistema y privadas, tres tipos* (`plantillas.md`).

**`agregarTareasDesdePlantilla` no tenía `safeParse` server-side** (actions.ts pre-existente) — regla "Validar en dos lugares" es de las Reglas Siempre Activas. Se agregó `agregarDesdePlantillaSchema` en `types.ts` y se cambió la firma de la action a recibir un solo objeto validado, mismo patrón que el resto de `actions.ts`.

**Forms con campos `.default()` → `useForm<z.input<schema>>`.** Regla general en `GUIDE_TYPESCRIPT.md`; acá se aplicó a `CrearTareaForm`, `CrearHiloForm`, `CrearProyectoForm` y `CrearPlantillaForm`.

**`<select>` con opción vacía sobre `uuid().nullish()` → `uuidOpcional`** (`types.ts`, mismo motivo que `fechaOpcional`). Regla general en `GUIDE_TYPESCRIPT.md`.

~~**Gate de UI para acciones de tarea (`TareaRow`) es una aproximación a la RLS, no un espejo exacto.**~~ **Superado por `sql/013`** — ver *Ser creador deja de dar visibilidad* (`visibilidad.md`).

**Sincronizar estado local con props sin `useEffect(setState)`** (patrón `estadoBase`/`estadoLocal`, nació en `TareaRow`). Regla general en `GUIDE_TYPESCRIPT.md`.

**RLS: `42P17` entre `tareas_proyectos` ↔ `tareas_proyectos_miembros` y `tareas` ↔ `tareas_asignados`.** Se rompió con funciones `SECURITY DEFINER` (`es_creador_proyecto`, `es_asignado_tarea` y la que hoy es `es_responsable_tarea`, `sql/005`). Apareció recién al usar `/tareas` logueado: `tsc` no detecta recursión de RLS. Regla general en `GUIDE_DB.md`.

**`crearHilo` genera el `id` antes del insert y no pide `.select()`**: la policy de SELECT pasa por `puede_ver_hilo`, que relee `tareas_hilos` y no ve la fila del mismo statement. Regla general en `GUIDE_DB.md` (*`INSERT … RETURNING`*).


## Retoques contra la spec funcional (`resumen-todo-app-erp.md`)

Sesión posterior comparó el módulo ya construido contra la spec funcional original y encontró gaps. Confirmados con el usuario los puntos ambiguos, se implementó lo siguiente (sin tocar SQL — todo reusa columnas/tablas existentes):

**§1 Conversión tarea→hilo (Opción A)** — ~~`agregarPasoATarea`~~ se reemplazó después por `convertirTareaEnHilo` (ver *Fixes de UI pedidos*), y el label del menú pasó a "Convertir en hilo" (ver *UI de pasos y vista Misión*): se mantiene el botón "Nuevo hilo" explícito (lo necesitan las plantillas, que exigen `hilo_id` destino) y se suma `agregarPasoATarea` — botón "Agregar paso" en una tarea suelta que crea el hilo *por detrás* (mismo resultado que la spec, sin pantalla de "convertir" separada). El `creado_por` del hilo y del nuevo paso es siempre quien ejecuta la acción, no el `creado_por` de la tarea original — `tareas_hilos_insert`/`tareas_insert` exigen `creado_por = auth.uid()` en su `WITH CHECK`, así que copiar el `creado_por` original rompería la inserción si no coinciden. Gateado a `puedeGestionar` (creador/responsable/`tareas_gestionar_ajenas`) por el mismo motivo que ya aplica a Reasignar/mover-hilo — la inserción también exige `responsable_id = auth.uid()` salvo `ajenas`.

**§1 Deshacer conversión:** `deshacerConversionHilo` — decisión confirmada con el usuario: se conserva como tarea suelta la más antigua del hilo (por `created_at`), el resto se desactiva (`activo = false`, nunca DELETE). Siempre disponible (no bloqueada); `DeshacerConversionModal.tsx` muestra el checklist de qué se conserva/desactiva y solo agrega el aviso de pérdida cuando hay 2+ tareas o alguna completada.

**§4 Métricas de hilo:** `HiloCard` calcula "Hace X días" (desde `created_at`) y "Próxima tarea vence en X días" (mínimo `fecha_vencimiento` entre tareas activas del hilo, ignorando pospuestas — las ocultas por privacidad ya las filtra RLS antes de llegar al array).

**§5 Modal de cierre automático:** `CerrarHiloModal` (checklist visual) se dispara solo, sin `useEffect`, comparando una "firma" de estados de las tareas del hilo contra la última vista (mismo patrón de `estadoBase`/`estadoLocal` que ya usa `TareaRow` para no violar `react-hooks/set-state-in-effect`). Se muestra una sola vez por transición a "todo completo"; "Mantener abierto" la descarta hasta el próximo cambio real de estado. El botón manual "Cerrar hilo" reusa el mismo componente.

**§9 Auditoría:** se agregó fecha de creación (`tareas.created_at`) y fecha de asignación por evento. Esta última no tiene FK directa a `tareas_eventos` — se resuelve con una segunda consulta a `tareas_asignados` (sin filtrar `activo`, para no perder el dato si después reasignaron la tarea) armando un mapa `tarea_id:usuario_id → primera fecha`. Se agregó `getPendientesUsuario` — panorama de tareas incompletas del usuario filtrado, visible en `AuditoriaView` solo cuando hay un usuario seleccionado (con "todos" seleccionado no se arma, sería una lista completa del equipo sin foco claro). El rediseño a heatmap/Kanban que sugiere la spec (§10) se dejó sin tocar — es "preferir", no requisito, y la lista plana ya cubre los datos duros pedidos.

**§10 Badges:** recurrencia y vínculo con app externa pasan a ser ícono + tooltip (antes no existían); "pospuesta" pasa de badge de texto a ícono + tooltip (antes badge-warning) para no competir con el color de la fecha. Se sacó el badge "Vencida" — ahora el color (neutro/ámbar/rojo) va directo sobre el texto de la fecha de vencimiento. Tareas sin vencimiento muestran "Creada hace X días" con la misma lógica de color invertida. Umbrales (`PROXIMA_DIAS=3`, `ANTIGUEDAD_AMBAR_DIAS=14`, `ANTIGUEDAD_ROJO_DIAS=30`) quedaron como constantes fijas en `TareaRow.tsx`, no configurables — la spec pide "umbral configurable" pero no hay todavía un segundo caso real que justifique una UI de settings para esto (simplicidad antes que abstracción). Avatares de multi-asignado ahora se superponen (margin negativo) y el del usuario actual queda con outline propio.

**Deliberadamente no implementado — §6 (botón "Realizar tarea", ~~deep link~~, `modo_completado` en la UI):** la spec ya marca este punto como "pendiente de definir con detalle... a retomar cuando exista una segunda aplicación real en el sistema", y hoy no existe ninguna. `origen_app`/`origen_punto`/`modo_completado` siguen en el schema y en `crearTareaSchema` pero no se exponen en `TareaFormPanel` — construir la UI de integración ahora sería adelantarse a un caso que todavía no existe (misma regla que ya frenó el diseño de una capa de integración genérica en la spec original). Retomar cuando haya una segunda app real. **El deep link sí se implementó** — ver *Tareas generadas por otro módulo* en `integracion.md`.


## Notas, panel de proyecto, "Mis tareas", islas (`sql/008`)

**Notas — historial, no campo único.** Confirmado con el usuario: `tareas_notas`/`tareas_hilos_notas` (`sql/008`), append-only (sin UPDATE de texto, `activo` solo para ocultar una nota propia). SELECT vía `EXISTS` directo sobre la tabla padre (`tareas`/`tareas_hilos`) — no hace falta función `SECURITY DEFINER` porque la referencia es de ida sola (la policy de la tabla padre no mira hacia las de notas), a diferencia de los pares que sí necesitaron romper recursión (`tareas_proyectos` ↔ `tareas_proyectos_miembros`, etc.). `listarNotasTarea`/`listarNotasHilo` viven en `actions.ts` (no en `queries.ts`) aunque son lecturas — `queries.ts` no tiene `"use server"`, así que no es invocable por RPC desde un Client Component; `NotasSection.tsx` (nuevo, reusado por `TareaRow` y `HiloDetailPanel`) necesita poder llamarlas. Fetch on-mount del componente (que solo se monta cuando el usuario abre la sección) — sin precarga de notas de todo lo visible en la página.

**Visibilidad por defecto: `privado` (antes `publico`).** `ALTER COLUMN ... SET DEFAULT` en `tareas`, `tareas_hilos`, `tareas_proyectos` (`sql/008`) + mismo default en los tres schemas Zod (`crearTareaSchema`/`crearHiloSchema`/`crearProyectoSchema`) + `defaultValues` de los tres FormPanel. Filas existentes no se tocan.

**Vista "Mis tareas" → vuelve a "Lista": se revirtió el filtro a propios.** **Parcialmente superado** — el segmentado Míos / Involucrado / Todos y el corte de pasos ajenos son de *La vista Lista es de tareas, el hilo agrupa*; `esDeUsuario()` se movió a `relacion.ts` y ya no vive en la vista. Sigue valiendo el motivo del rollback: El filtro `esPropia` de `TareasListaView` (restringía a creador/responsable/asignado activo, sin excepción para `tareas_gestionar_ajenas`) se sacó: la visibilidad la decide RLS y nada más. Un usuario sin `tareas_gestionar_ajenas` sigue viendo solo lo suyo porque la política de `tareas`/`tareas_hilos` no le devuelve el resto (`sql/005`); un manager ve todo, que es lo que el permiso significa. Motivo del rollback: el filtro era solo de nivel superior — `HiloCard` recibía `tareas` completo y listaba todas las tareas del hilo igual, así que la vista mostraba "propias" con contenido ajeno adentro. Label del tab vuelve a "Lista" en `layout.tsx` (`tareas_lista` sigue siendo el código de permiso — el label es un string local del layout, no viene de `submodulos.nombre`). El filtro "Todos los asignados" se restauró como `<select>` en la toolbar, con **default en el usuario actual** (`useState(usuarioActualId ?? "")`): "lo mío" pasa a ser un default, no una restricción — el panorama del equipo queda a un click y lo sigue acotando RLS. Semántica del filtro: `esDeUsuario()` matchea `responsable_id` OR asignado activo, igual para cualquier usuario elegido (ver más abajo: nació como `estaInvolucrado()` con `creado_por` y se corrigió). Un hilo entra si coincide él mismo (título + `responsable_id`) o si alguna de sus tareas coincide. La opción vacía se llama "Todos los usuarios" (no "Todos los asignados": el filtro ya no es solo por asignación).

~~**Orden por temperatura: solo UI, sin columna nueva.**~~ **Superado** — el slider se fue, ver *De slider a tres niveles* (`vista-lista.md`). `useOrdenTemperatura` sobrevive y la decisión de no agregar columna sigue en pie.

**Completadas y canceladas al fondo + atenuadas.** `ordenar()` usa clave primaria `peso` (activa 0, cerrada 1) y desempata por temperatura: una tarea cerrada en 90 no debe competir con una pendiente en 40. `TareaRow` suma `opacity-60` cuando `!activa` — se sigue viendo lo hecho sin que gane la atención. Se descartó esconderlas por antigüedad ("completadas de hace +7 días"): `tareas` no tiene columna `completada_at`, habría que leer `tareas_eventos` o agregar columna, costo alto para el problema. También se descartó agruparlas en isla plegable: en un hilo rompe la lectura de la secuencia de pasos.

**Badge de relación (`relacionCon`) en `TareaRow`.** Badge `badge-neutral` "Responsable"/"Creador" al lado del estado, con `title` que incluye el nombre. Solo se muestra si ese usuario **no** está entre los asignados activos — si lo está, el avatar ya lo explica y el badge sería ruido. El prop es el usuario cuya relación se explica, no el actual: `TareasListaView` pasa `asignadoId || usuarioActualId` (sigue al filtro, así el badge dice por qué esa fila matcheó), `ProyectoDetailPanel` pasa `usuarioActualId`. Se drillea por `HiloCard` → `HiloDetailPanel` → `TareaRow`, igual que `gestionarAjenas`.

**HiloCard se parte en dos: `HiloCard` (isla resumen) + `HiloDetailPanel` (RightPanel nuevo).** **Parcialmente revertido** — la Lista volvió a mostrar tareas del hilo, pero solo las propias (ver *La vista Lista es de tareas, el hilo agrupa*). La partición en dos componentes se mantiene. Pedido explícito: la vista Lista no debe mostrar tareas ni acciones del hilo inline, solo en un panel lateral. `HiloCard` ahora solo header + métricas (días transcurridos, próxima fecha) y abre `HiloDetailPanel` al click — que es quien tiene el listado de `TareaRow`, los botones de acción (agregar tarea/plantilla/cerrar/posponer/deshacer/desactivar) y la sección de notas del hilo. El disparo automático del modal de cierre (`mostrarCierreAuto`, §5 spec) se queda en `HiloCard` (debe poder aparecer con el panel cerrado); el botón manual "Cerrar hilo" vive en `HiloDetailPanel` y reusa el mismo `CerrarHiloModal`.

**`TareaRow` perdió su borde propio — el contenedor decide el wrapping.** Antes tenía `border-b` fijo (pensado para una lista continua). Ahora se usa en 3 contextos con look distinto: isla propia con `rounded-lg border` (tareas sueltas en "Mis tareas" y en `ProyectoDetailPanel`) vs. fila con `border-b` dentro de una lista continua (`HiloDetailPanel`, tareas del hilo). Se sacó el borde de `TareaRow` y cada padre envuelve con el estilo que corresponde — evita una prop de estilo condicional dentro del componente.

**"Islas": `TareasListaView` separa hilos de tareas sueltas en dos grupos con label (`t-label`), cada item con su propio `rounded-lg border` — ya no una lista continua con `border-b` entre filas.** Mismo criterio aplicado en `ProyectoDetailPanel`.

**Panel de proyecto (`ProyectoDetailPanel`, nuevo) — confirmado con el usuario: muestra TODO lo visible del proyecto, no filtra a "propio".** Botón "Ver tareas" en cada fila de `ProyectosView` lo abre; reusa `HiloCard`/`TareaRow` (mismas islas que "Mis tareas") filtrando por `proyecto_id`. "Agregar tarea"/"Agregar hilo" reusan `TareaFormPanel`/`HiloFormPanel` con un `proyectoId` nuevo (prop opcional) que preselecciona y oculta el `<select>` de proyecto — mismo patrón que ya usaba `hiloId` en `TareaFormPanel`. Requirió que `proyectos/page.tsx` sume `getListaTareas()` + `getPlantillas()` (antes solo pedía proyectos/miembros).


## Fixes de UI pedidos (editar tarea, presets, conversión, notas)

Los tres cambios de `components/ui/` de esta tanda (`RightPanel` y `Modal` a `<dialog>`,
`OverflowMenu` con `fixed`) están en `decisiones/global/ui.md`.

**Editar tarea: `TareaFormPanel` sirve crear y editar (prop `tarea`), no un componente nuevo.** El resolver sigue siendo `crearTareaSchema` (superset) y en modo edición `responsable_id`/`asignados` viajan como defaults ocultos: se cambian por "Reasignar", que ya es la única autoridad sobre `tareas_asignados`. El submit llama `editarTarea`, que valida con `editarTareaSchema` — extiende un `tareaEditableSchema` nuevo (base común con `crearTareaSchema`) y descarta las claves de más que manda el form. Gate de UI: `esAsignado` (creador/responsable/asignado activo/`ajenas`), que es exactamente el `USING` de `tareas_update`. El disparador es el título de la tarea, no toda la fila — la fila ya tiene select/range/botones adentro y anidar interactivos rompe accesibilidad.

**"Agregar paso" ya no pide un título: convierte y abre el panel del hilo.** `agregarPasoATarea` (creaba hilo + un 2do paso con título pedido en un panel) se reemplazó por `convertirTareaEnHilo(tareaId)`: crea el hilo con título/descripción/visibilidad/proyecto/responsable de la tarea, mueve la tarea adentro y no crea ningún paso extra — los pasos se agregan desde el panel del hilo, que la UI abre sola. `AgregarPasoPanel.tsx` y `agregarPasoSchema` se eliminaron. La apertura automática es una prop `autoAbrir` en `HiloCard`: la card del hilo nuevo puede montarse antes o después de que el padre marque el id (según cuándo llegue el `revalidatePath`), así que reacciona al cambio de prop **durante el render** con el patrón `autoAbrirBase` (mismo criterio que `estadoBase`/`sigBase` — `react-hooks/set-state-in-effect` es error, no warning).

**Notas de tarea visibles por defecto y precargadas en la query, no fetch por fila.** `mostrandoNotas` arranca en `true` (el botón "Notas" ahora colapsa, no carga), y `getListaTareas` trae `tareas_notas(...)` embebido — con la sección abierta en cada fila, el fetch on-mount de `NotasSection` serían N requests (cada uno con su `auth.getUser()`). `activo` y el orden de las notas se resuelven en JS: filtrar un embed en PostgREST lo convierte en inner join y se perderían las tareas sin notas. `NotasSection` acepta `notasIniciales` y saltea el fetch inicial cuando lo recibe; las notas de hilo siguen pidiéndose on-mount (el panel del hilo se abre de a uno).

**Notas: el `<textarea>` aparece recién al apretar "Agregar nota".** Con la lista de notas visible por defecto en cada tarea, un textarea por fila llenaba la vista de inputs vacíos. El historial se sigue viendo siempre; el input es on-demand y se cierra solo al guardar.

**Orden por temperatura también en `HiloDetailPanel`.** Mismo `useOrdenTemperatura` que "Mis tareas"/`ProyectoDetailPanel` — los pasos del hilo se reordenan en vivo al arrastrar el slider.

**`TareaRow`: se fue el botón "Notas" y las notas se muestran siempre.** Con la lista de notas + "Agregar nota" ya visibles en cada fila, el toggle no agregaba nada. En el menú de acciones "Posponer" pasó al primer lugar (antes "Reasignar") — es la acción más frecuente.

**Presets de vencimiento (1/3/7 días) en `TareaFormPanel`.** Botones que hacen `setValue("fecha_vencimiento", sumarDiasISO(hoyISO(), n))` sobre el mismo `<input type="date">` — sin campo ni estado nuevo. Los días viven en `VENCIMIENTO_PRESETS` en el componente; no se hizo configurable (mismo criterio que los umbrales de `TareaRow`).
