# DECISIONES DE ARQUITECTURA — ERP JADA (erp-new)

Registro de decisiones no obvias tomadas durante el desarrollo. Leer antes de modificar cualquier módulo existente.

---

## Design system — JADA

Spec completa extraída y volcada en `.claude/guides/design-system/JADA-design-system.md`. El sistema fuente es un dashboard desktop; para el ERP (mobile-first, uso en obra) hubo que extrapolar piezas que no existen en el original, siguiendo su misma lógica visual:

- **Breakpoints**: no definidos en el fuente. Se usan defaults de Tailwind (sm 640/md 768/lg 1024/xl 1280).
- **Tabs (ModuleTabs)**: no existe componente fuente. Replica patrón de nav-item (underline horizontal o pill).
- **Paginación**: no existe. Replica jx-icon-btn + números con mismo patrón de estado activo que sidebar/tabs.
- **List-item mobile** (reemplazo de tablas en mobile, regla ya existente): no existe. Deriva de los tokens de fila de tabla del sistema (jd-table row).
- **Touch targets 44px**: el fuente es desktop (~34px). Se fuerza min-height 44px solo en mobile (`@media max-width:767px`), sin cambiar el look visual.
- **Toast (Sonner)**: no hay skin custom en el fuente. Deriva de Alert (mismos tokens semánticos).
- **Dark mode**: sí es first-class en el sistema fuente, activado con `<html data-theme="dark">` (no clase `.dark`). Pensado como modo alto-contraste/exterior, no solo nocturno — relevante para uso en obra con sol.

**Por qué:** el JADA Design System fue creado para un dashboard de escritorio; el ERP necesita mobile-first en obra, así que hay piezas sin precedente en el spec. Se prioriza mantener coherencia visual con lo que sí existe antes que inventar un patrón nuevo.

---

## `middleware.ts` → `proxy.ts` (Next.js 16)

Next 16 deprecó la convención `middleware.ts` en la raíz (`src/`) — se renombró a `proxy.ts` con función exportada `proxy` (no `middleware`). El archivo `src/lib/supabase/middleware.ts` (helper `updateSession`, nombre fijado por `GUIDE_DB.md`) no cambia — solo el entry point de Next en `src/proxy.ts` lo importa y expone.

**Por qué:** `erp-app/AGENTS.md` (autogenerado por `next dev`) advierte que esta versión de Next tiene breaking changes vs. el training data. Toda lógica de proxy/middleware futura va en `src/proxy.ts`, no crear `src/middleware.ts`.

---

## Dashboard = ruta `/`, no `/dashboard`

`/` ya estaba gateado por el proxy (redirect a `/login` si no hay sesión) y solo mostraba un placeholder estático fuera del grupo `(erp-app)` (sin sidebar). Se reemplazó `app/page.tsx` por `app/(erp-app)/page.tsx` con el dashboard real — mismo route, ahora dentro del grupo con sidebar. `SidebarNav` suma un ítem "Inicio" (`href: "/"`) siempre visible, sin gating por `modulosVisibles` (el dashboard no es un módulo con submódulos propios, es la landing).

**Por qué:** evitar una ruta `/dashboard` redundante cuando `/` ya cumplía el rol de landing autenticada.

## `usuario_widgets` — RLS directo, sin `service_role`

A diferencia de `usuarios`/`usuario_submodulos` (server actions con `service_role` porque la autorización pasa por `tiene_permiso`), el toggle de widgets es una preferencia estrictamente propia del usuario. RLS con `usuario_id = auth.uid()` alcanza para SELECT/INSERT/UPDATE — el server action de `modules/dashboard/actions.ts` usa el cliente normal (`lib/supabase/server.ts`), no cliente admin.

**Por qué:** usar `service_role` acá sería una elevación de privilegio innecesaria para un dato sin lógica de negocio — regla "simplicidad antes que abstracción". Precedente para futuros módulos: `service_role` solo cuando RLS no puede expresar la regla de autorización (ej: chequeos vía `tiene_permiso`), no por default en todo server action de escritura.

---

## RLS no alcanza sin `GRANT` — regla para toda tabla nueva

Activar RLS y crear policies no basta. Postgres verifica primero el privilegio a nivel de tabla del rol (`anon`/`authenticated`); sin `GRANT`, la query falla con `permission denied for table x` (código `42501`) — el error no menciona RLS ni políticas, así que se puede perder tiempo revisando la policy cuando el problema es el GRANT faltante. Se detectó recién ahora (primera prueba real en browser logueado) porque este proyecto Supabase no auto-otorga privilegios en tablas nuevas del schema `public`.

**Regla:** toda tabla nueva con RLS necesita, además de las policies, `GRANT <ops> ON public.<tabla> TO authenticated;` — solo las operaciones que el cliente normal (no `service_role`) ejecuta directo. Si toda escritura pasa por `service_role` (patrón de `usuarios`/`usuario_submodulos`), alcanza con `GRANT SELECT`. Aplicado retroactivamente en `sql/001_usuarios_permisos.sql` y `sql/002_dashboard.sql` — **hay que re-correr ambos en Supabase**.

---

## Funciones `SECURITY DEFINER` — siempre `SET search_path = public`

`supabase_auth_admin` (el rol que ejecuta el trigger `on_auth_user_created` al crear un usuario) no tiene `public` en su `search_path` por defecto. Una función `SECURITY DEFINER` que referencia tablas sin schema (ej: `INSERT INTO usuarios ...`) falla con `relation "usuarios" does not exist` aunque la tabla exista — el error no menciona permisos ni search_path, así que es fácil perder tiempo pensando que la tabla no se creó.

**Regla:** toda función `SECURITY DEFINER` nueva debe declarar `SET search_path = public` y preferir tablas schema-calificadas (`public.tabla`). Aplica ya en `handle_new_user()` y `tiene_permiso()` (`sql/001_usuarios_permisos.sql`).

**Por qué:** además de evitar este bug, es la mitigación estándar de Postgres contra search_path injection en funciones `SECURITY DEFINER`.

---

## Sidebar: `Sidebar.tsx` (server) + `SidebarNav.tsx` (client) + `MobileNav.tsx` (client)

Portado el patrón de `erp-old-2`. `Sidebar.tsx` es server component: trae `nombre` (tabla `usuarios`, sin `avatar_url` — ese campo no existe en el schema nuevo, avatar es solo iniciales) y `modulosVisibles` (reusa `getUserSubmodulos()` de `lib/permissions`, ya cacheado). `SidebarNav.tsx` es un solo componente que sirve tanto al `<aside>` desktop como al drawer mobile (`MobileNav.tsx`) — incluye footer con iniciales + nombre + logout. Sin `grupo` (agrupación de nav) — con 2 módulos no hace falta, agregar cuando haya 3+.

`signOutAction` vive en `modules/auth/actions.ts` — módulo mínimo sin `permissions.ts`/`types.ts` porque cerrar sesión no tiene gate de permiso ni validación.

**Dark mode:** `--brand-50`, `--brand-700` y `--neutral-100` (usados por `.nav-item-active` y `.badge-brand`) pasaron a ser custom properties en `:root`/`[data-theme="dark"]` (mismo patrón que `--bg-*`/`--text-*`) en vez de hex fijo en `@theme inline` — sin esto, el ítem de nav activo quedaba con el celeste claro del light mode también en dark.

---

## Permisos: `funcion` ligada a su `vista` puntual (`vista_id`), no solo a `modulo`

Modelo anterior (`sql/001`): `submodulos.tipo` era `seccion`/`funcion`, y una función se consideraba del módulo entero — sin relación a una sección específica. Funcionaba porque `usuarios` solo tiene 1 sección. No escala a un módulo con 2+ vistas: no había forma de saber a cuál pertenece cada función.

**Cambio (`sql/003_vistas_funciones.sql`, corrido en Supabase):**
- Enum renombrado `seccion` → `vista` (`ALTER TYPE ... RENAME VALUE`).
- Columna `submodulos.vista_id` (FK a `submodulos.id`, nullable). `CHECK`: vista → `vista_id NULL`; función → `vista_id NOT NULL`. Trigger `validar_vista_id()` valida que la vista referenciada exista, sea `tipo='vista'` y comparta `modulo`.
- Una vista puede tener 0 funciones (permiso de solo-lectura, se asigna directo, sin función que la sincronice).
- `PermisosModal.tsx` ahora anida funciones bajo su vista (antes: funciones listadas flat bajo el módulo). `syncVista()` reemplaza `syncSeccion()` — sincroniza la vista dueña específica, no todas las secciones del módulo.
- `getSeccionesDeModulo()` renombrado `getVistasDeModulo()`.

**Por qué:** pedido explícito de restructurar el modelo de permisos para soportar módulos multi-vista donde cada vista tiene su propio set de funciones — regla "no crear permisos por módulo" no aplica acá, esto sigue siendo autorización 100% por submódulo, solo se hace explícita la relación jerárquica vista→función que antes era implícita (y rota) por `modulo` compartido.

**Nota de ejecución:** el CHECK constraint se agregó antes del backfill en el primer intento — falló porque la fila `usuarios_gestionar` (funcion, sin `vista_id` todavía) lo violaba. Reordenado: backfill primero, constraint después. `supabase db query -f` corre el archivo como una sola transacción — el fallo revirtió todo (enum rename incluido), sin dejar estado a medio migrar.

---

## UI: panel lateral derecho reemplaza modal para crear/editar

`RightPanel.tsx` (`components/ui/`) es el patrón para formularios de creación/edición — no modal. Confirmaciones (borrar, desactivar, acciones destructivas) siguen usando modal.

**Por qué:** decisión explícita de UX — crear/editar es una tarea de mayor foco/duración, panel lateral no bloquea el contexto de la lista detrás. Confirmación es una interrupción corta, modal sigue siendo más directo.

**Sin excepciones vigentes.** `PermisosModal.tsx` figuraba como una (creado antes de la regla) pero ya usa `RightPanel`; solo el nombre del archivo quedó viejo.

---

## Módulo tareas — UI (Lista, Proyectos, Plantillas, Auditoría)

Backend (SQL + `types.ts`/`permissions.ts`/`queries.ts`/`actions.ts`) venía de una sesión anterior, ya corrido en Supabase. Esta sesión agregó la UI completa (`modules/tareas/components/` + `app/(erp-app)/tareas/`).

**"Usar plantilla" vive en `HiloCard`, no en la vista Plantillas.** `agregarTareasDesdePlantilla` siempre necesita un `hilo_id` destino — la vista Plantillas quedó como catálogo puro (crear/listar/desactivar), sin función propia de "usar" (coincide con el seed de `submodulos`: `tareas_plantillas` no tiene función separada).

**`agregarTareasDesdePlantilla` no tenía `safeParse` server-side** (actions.ts pre-existente) — regla "Validar en dos lugares" es de las Reglas Siempre Activas. Se agregó `agregarDesdePlantillaSchema` en `types.ts` y se cambió la firma de la action a recibir un solo objeto validado, mismo patrón que el resto de `actions.ts`.

**Forms con campos `.default()` en el schema: tipar `useForm<T>` con `z.input<schema>`, no `z.infer`/`z.output`.** `zodResolver` espera el tipo de *entrada* (pre-default) como `FieldValues`; usar el tipo de salida rompe la inferencia de `Resolver<...>` con un error de TS que no deja ver la causa real. `crearTareaSchema` ya tenía este patrón (`CrearTareaForm = z.input<...>`); se replicó en `CrearHiloForm`, `CrearProyectoForm`, `CrearPlantillaForm` (los tres tienen `visibilidad`/`orden` con `.default()`).

**`<select>` con opción "vacía" sobre un campo `uuid().nullish()`: falla la validación con `""`, no con `undefined`.** Mismo motivo que `fechaOpcional` (ya documentado en `types.ts`) — se agregó `uuidOpcional` (`z.union([uuid, literal(""), null, undefined]).transform(v => v || null)`) para `proyecto_id` en `crearTareaSchema`/`crearHiloSchema`.

**Gate de UI para acciones de tarea (`TareaRow`) es una aproximación a la RLS, no un espejo exacto.** `esAsignado` (creador/responsable/asignado activo/`tareas_gestionar_ajenas`) habilita estado/temperatura/completar/posponer/mover-hilo/desactivar; `puedeGestionar` (creador/responsable/`tareas_gestionar_ajenas`, sin asignado simple) habilita reasignar — porque `tareas_asignados_insert/update` en RLS no incluye "ser un asignado más". Ocultar el botón es solo UX; el servidor rechaza igual si algo queda mal calculado acá.

**Sincronizar estado local con props sin `useEffect(setState)`:** React Compiler (`react-hooks/set-state-in-effect`) lo marca error, no warning. Patrón usado en `TareaRow` para `estadoLocal`/`tempLocal` (optimistic UI que debe reconciliar tras `revalidatePath`): guardar el último valor de prop visto en un state paralelo (`estadoBase`) y comparar/actualizar durante el render, no en un efecto — es el patrón "adjusting state during render" de la doc de React.

**RLS: dos tablas cuyas policies se consultan mutuamente → `42P17 infinite recursion detected in policy`.** Se dio en `tareas_proyectos` ↔ `tareas_proyectos_miembros` (el SELECT de una hace `EXISTS` sobre la otra y viceversa) y en `tareas` ↔ `tareas_asignados` (mismo patrón, más un caso de `tareas_asignados_select` con `EXISTS` sobre sí misma). Recién apareció al testear en browser porque es la primera vez que se ejercita `/tareas` logueado — `npx tsc` y los checks de código no detectan recursión de RLS. **Fix:** envolver el lado "de vuelta" del `EXISTS` en una función `SECURITY DEFINER STABLE SET search_path = public` (mismo criterio que `puede_ver_hilo`) — `es_creador_proyecto`, `es_responsable_o_creador_tarea`, `es_asignado_tarea` (`sql/005`, corregido directo en el archivo + migración aplicada en Supabase). Regla para toda policy nueva que necesite mirar otra tabla RLS-protegida: si esa otra tabla puede necesitar mirar hacia atrás, usar función `SECURITY DEFINER`, no `EXISTS` directo.

**`INSERT ... RETURNING` (`.insert().select()` de supabase-js) sobre una tabla cuya policy de SELECT es una función `SECURITY DEFINER` que vuelve a consultar esa misma tabla → `new row violates row-level security policy`, aunque la misma función devuelva `true` llamada aparte.** Pasó en `crearHilo` (`tareas_hilos_insert` pasa, pero el RETURNING re-chequea `tareas_hilos_select` → `puede_ver_hilo(id)` → `SELECT ... FROM tareas_hilos WHERE id = ...` — esa sub-consulta no ve la fila recién insertada dentro del mismo statement, aunque una consulta aparte sí la vea). No pasa con `tareas`/`tareas_proyectos` porque sus funciones de apoyo (`puede_ver_hilo`, `es_creador_proyecto`) consultan una tabla *distinta* a la que se está insertando. **Fix:** en `crearHilo` (`actions.ts`), generar el `id` con `crypto.randomUUID()` antes del insert y no pedir `.select()` — evita el RETURNING por completo. Regla: un INSERT sobre una tabla cuya SELECT policy se apoya en una función que relee esa misma tabla no puede pedir `.select()` en el mismo insert; si se necesita el id, generarlo client-side.

---

## Módulo tareas — retoques contra `resumen-todo-app-erp.md` (auditoría de spec)

Sesión posterior comparó el módulo ya construido contra la spec funcional original y encontró gaps. Confirmados con el usuario los puntos ambiguos, se implementó lo siguiente (sin tocar SQL — todo reusa columnas/tablas existentes):

**§1 Conversión tarea→hilo (Opción A):** se mantiene el botón "Nuevo hilo" explícito (lo necesitan las plantillas, que exigen `hilo_id` destino) y se suma `agregarPasoATarea` — botón "Agregar paso" en una tarea suelta que crea el hilo *por detrás* (mismo resultado que la spec, sin pantalla de "convertir" separada). El `creado_por` del hilo y del nuevo paso es siempre quien ejecuta la acción, no el `creado_por` de la tarea original — `tareas_hilos_insert`/`tareas_insert` exigen `creado_por = auth.uid()` en su `WITH CHECK`, así que copiar el `creado_por` original rompería la inserción si no coinciden. Gateado a `puedeGestionar` (creador/responsable/`tareas_gestionar_ajenas`) por el mismo motivo que ya aplica a Reasignar/mover-hilo — la inserción también exige `responsable_id = auth.uid()` salvo `ajenas`.

**§1 Deshacer conversión:** `deshacerConversionHilo` — decisión confirmada con el usuario: se conserva como tarea suelta la más antigua del hilo (por `created_at`), el resto se desactiva (`activo = false`, nunca DELETE). Siempre disponible (no bloqueada); `DeshacerConversionModal.tsx` muestra el checklist de qué se conserva/desactiva y solo agrega el aviso de pérdida cuando hay 2+ tareas o alguna completada.

**§4 Métricas de hilo:** `HiloCard` calcula "Hace X días" (desde `created_at`) y "Próxima tarea vence en X días" (mínimo `fecha_vencimiento` entre tareas activas del hilo, ignorando pospuestas — las ocultas por privacidad ya las filtra RLS antes de llegar al array).

**§5 Modal de cierre automático:** `CerrarHiloModal` (checklist visual) se dispara solo, sin `useEffect`, comparando una "firma" de estados de las tareas del hilo contra la última vista (mismo patrón de `estadoBase`/`estadoLocal` que ya usa `TareaRow` para no violar `react-hooks/set-state-in-effect`). Se muestra una sola vez por transición a "todo completo"; "Mantener abierto" la descarta hasta el próximo cambio real de estado. El botón manual "Cerrar hilo" reusa el mismo componente.

**§9 Auditoría:** se agregó fecha de creación (`tareas.created_at`) y fecha de asignación por evento. Esta última no tiene FK directa a `tareas_eventos` — se resuelve con una segunda consulta a `tareas_asignados` (sin filtrar `activo`, para no perder el dato si después reasignaron la tarea) armando un mapa `tarea_id:usuario_id → primera fecha`. Se agregó `getPendientesUsuario` — panorama de tareas incompletas del usuario filtrado, visible en `AuditoriaView` solo cuando hay un usuario seleccionado (con "todos" seleccionado no se arma, sería una lista completa del equipo sin foco claro). El rediseño a heatmap/Kanban que sugiere la spec (§10) se dejó sin tocar — es "preferir", no requisito, y la lista plana ya cubre los datos duros pedidos.

**§10 Badges:** recurrencia y vínculo con app externa pasan a ser ícono + tooltip (antes no existían); "pospuesta" pasa de badge de texto a ícono + tooltip (antes badge-warning) para no competir con el color de la fecha. Se sacó el badge "Vencida" — ahora el color (neutro/ámbar/rojo) va directo sobre el texto de la fecha de vencimiento. Tareas sin vencimiento muestran "Creada hace X días" con la misma lógica de color invertida. Umbrales (`PROXIMA_DIAS=3`, `ANTIGUEDAD_AMBAR_DIAS=14`, `ANTIGUEDAD_ROJO_DIAS=30`) quedaron como constantes fijas en `TareaRow.tsx`, no configurables — la spec pide "umbral configurable" pero no hay todavía un segundo caso real que justifique una UI de settings para esto (simplicidad antes que abstracción). Avatares de multi-asignado ahora se superponen (margin negativo) y el del usuario actual queda con outline propio.

**Deliberadamente no implementado — §6 (botón "Realizar tarea", deep link, `modo_completado` en la UI):** la spec ya marca este punto como "pendiente de definir con detalle... a retomar cuando exista una segunda aplicación real en el sistema", y hoy no existe ninguna. `origen_app`/`origen_punto`/`modo_completado` siguen en el schema y en `crearTareaSchema` pero no se exponen en `TareaFormPanel` — construir la UI de integración ahora sería adelantarse a un caso que todavía no existe (misma regla que ya frenó el diseño de una capa de integración genérica en la spec original). Retomar cuando haya una segunda app real.

---

## Módulo tareas — pedido de usuario: notas, panel de proyecto, "Mis tareas", islas (`sql/008`)

**Notas — historial, no campo único.** Confirmado con el usuario: `tareas_notas`/`tareas_hilos_notas` (`sql/008`), append-only (sin UPDATE de texto, `activo` solo para ocultar una nota propia). SELECT vía `EXISTS` directo sobre la tabla padre (`tareas`/`tareas_hilos`) — no hace falta función `SECURITY DEFINER` porque la referencia es de ida sola (la policy de la tabla padre no mira hacia las de notas), a diferencia de los pares que sí necesitaron romper recursión (`tareas_proyectos` ↔ `tareas_proyectos_miembros`, etc.). `listarNotasTarea`/`listarNotasHilo` viven en `actions.ts` (no en `queries.ts`) aunque son lecturas — `queries.ts` no tiene `"use server"`, así que no es invocable por RPC desde un Client Component; `NotasSection.tsx` (nuevo, reusado por `TareaRow` y `HiloDetailPanel`) necesita poder llamarlas. Fetch on-mount del componente (que solo se monta cuando el usuario abre la sección) — sin precarga de notas de todo lo visible en la página.

**Visibilidad por defecto: `privado` (antes `publico`).** `ALTER COLUMN ... SET DEFAULT` en `tareas`, `tareas_hilos`, `tareas_proyectos` (`sql/008`) + mismo default en los tres schemas Zod (`crearTareaSchema`/`crearHiloSchema`/`crearProyectoSchema`) + `defaultValues` de los tres FormPanel. Filas existentes no se tocan.

**Vista "Mis tareas" → vuelve a "Lista": se revirtió el filtro a propios.** El filtro `esPropia` de `TareasListaView` (restringía a creador/responsable/asignado activo, sin excepción para `tareas_gestionar_ajenas`) se sacó: la visibilidad la decide RLS y nada más. Un usuario sin `tareas_gestionar_ajenas` sigue viendo solo lo suyo porque la política de `tareas`/`tareas_hilos` no le devuelve el resto (`sql/005`); un manager ve todo, que es lo que el permiso significa. Motivo del rollback: el filtro era solo de nivel superior — `HiloCard` recibía `tareas` completo y listaba todas las tareas del hilo igual, así que la vista mostraba "propias" con contenido ajeno adentro. Label del tab vuelve a "Lista" en `layout.tsx` (`tareas_lista` sigue siendo el código de permiso — el label es un string local del layout, no viene de `submodulos.nombre`). El filtro "Todos los asignados" se restauró como `<select>` en la toolbar, con **default en el usuario actual** (`useState(usuarioActualId ?? "")`): "lo mío" pasa a ser un default, no una restricción — el panorama del equipo queda a un click y lo sigue acotando RLS. Semántica del filtro: **involucrado**, no solo asignado — `estaInvolucrado()` matchea `creado_por` OR `responsable_id` OR asignado activo, igual para cualquier usuario elegido. Con el default puesto en uno mismo, la semántica "solo asignado" escondía las tareas que el usuario creó o de las que es responsable sin auto-asignarse. Un hilo entra si coincide él mismo (título + `creado_por`/`responsable_id`) o si alguna de sus tareas coincide. La opción vacía se llama "Todos los usuarios" (no "Todos los asignados": el filtro ya no es solo por asignación).

**Orden por temperatura: solo UI, sin columna nueva.** El usuario aclaró explícitamente que no quería trackear "cuándo cambió" (eso hubiera pedido una columna `temperatura_actualizada_at`, porque `updated_at` ya se pisa con cualquier otra edición) — quería temperatura más alta arriba, reordenando en vivo mientras se arrastra el slider. `useOrdenTemperatura` (hook nuevo, sin persistencia) mantiene un mapa `id → valor en vivo` actualizado en cada `onChange` del range (no solo al soltar) y ordena `tareas sueltas` desc por ese valor (con fallback a `tarea.temperatura` para las no tocadas). Reusado en `TareasListaView` y `ProyectoDetailPanel`. Los hilos no tienen temperatura propia — no se reordenan.

**Completadas y canceladas al fondo + atenuadas.** `ordenar()` usa clave primaria `peso` (activa 0, cerrada 1) y desempata por temperatura: una tarea cerrada en 90 no debe competir con una pendiente en 40. `TareaRow` suma `opacity-60` cuando `!activa` — se sigue viendo lo hecho sin que gane la atención. Se descartó esconderlas por antigüedad ("completadas de hace +7 días"): `tareas` no tiene columna `completada_at`, habría que leer `tareas_eventos` o agregar columna, costo alto para el problema. También se descartó agruparlas en isla plegable: en un hilo rompe la lectura de la secuencia de pasos.

**Badge de relación (`relacionCon`) en `TareaRow`.** Badge `badge-neutral` "Responsable"/"Creador" al lado del estado, con `title` que incluye el nombre. Solo se muestra si ese usuario **no** está entre los asignados activos — si lo está, el avatar ya lo explica y el badge sería ruido. El prop es el usuario cuya relación se explica, no el actual: `TareasListaView` pasa `asignadoId || usuarioActualId` (sigue al filtro, así el badge dice por qué esa fila matcheó), `ProyectoDetailPanel` pasa `usuarioActualId`. Se drillea por `HiloCard` → `HiloDetailPanel` → `TareaRow`, igual que `gestionarAjenas`.

**HiloCard se parte en dos: `HiloCard` (isla resumen) + `HiloDetailPanel` (RightPanel nuevo).** Pedido explícito: la vista Lista no debe mostrar tareas ni acciones del hilo inline, solo en un panel lateral. `HiloCard` ahora solo header + métricas (días transcurridos, próxima fecha) y abre `HiloDetailPanel` al click — que es quien tiene el listado de `TareaRow`, los botones de acción (agregar tarea/plantilla/cerrar/posponer/deshacer/desactivar) y la sección de notas del hilo. El disparo automático del modal de cierre (`mostrarCierreAuto`, §5 spec) se queda en `HiloCard` (debe poder aparecer con el panel cerrado); el botón manual "Cerrar hilo" vive en `HiloDetailPanel` y reusa el mismo `CerrarHiloModal`.

**`TareaRow` perdió su borde propio — el contenedor decide el wrapping.** Antes tenía `border-b` fijo (pensado para una lista continua). Ahora se usa en 3 contextos con look distinto: isla propia con `rounded-lg border` (tareas sueltas en "Mis tareas" y en `ProyectoDetailPanel`) vs. fila con `border-b` dentro de una lista continua (`HiloDetailPanel`, tareas del hilo). Se sacó el borde de `TareaRow` y cada padre envuelve con el estilo que corresponde — evita una prop de estilo condicional dentro del componente.

**"Islas": `TareasListaView` separa hilos de tareas sueltas en dos grupos con label (`t-label`), cada item con su propio `rounded-lg border` — ya no una lista continua con `border-b` entre filas.** Mismo criterio aplicado en `ProyectoDetailPanel`.

**Panel de proyecto (`ProyectoDetailPanel`, nuevo) — confirmado con el usuario: muestra TODO lo visible del proyecto, no filtra a "propio".** Botón "Ver tareas" en cada fila de `ProyectosView` lo abre; reusa `HiloCard`/`TareaRow` (mismas islas que "Mis tareas") filtrando por `proyecto_id`. "Agregar tarea"/"Agregar hilo" reusan `TareaFormPanel`/`HiloFormPanel` con un `proyectoId` nuevo (prop opcional) que preselecciona y oculta el `<select>` de proyecto — mismo patrón que ya usaba `hiloId` en `TareaFormPanel`. Requirió que `proyectos/page.tsx` sume `getListaTareas()` + `getPlantillas()` (antes solo pedía proyectos/miembros).

---

## Módulo tareas — fixes de UI pedidos (panel, editar tarea, presets, conversión, notas)

**`RightPanel` pasa a `<dialog>` + `showModal()`, sin `fixed inset-0 z-50` propio.** El panel vive en el *top layer* del browser: ningún ancestro puede taparlo ni recortarlo (stacking context, `overflow`, `transform`), los paneles anidados (`TareaRow` dentro de `HiloDetailPanel` dentro de `ProyectoDetailPanel`) se apilan por orden de apertura sin manejar z-index, y `Escape` cierra solo el de arriba. El fondo es `backdrop:bg-[rgba(7,11,20,.55)]` (pseudo-elemento nativo) en vez de un div de overlay; el click afuera se detecta con `e.target === e.currentTarget` porque el backdrop no es un nodo propio. Los modales de confirmación (`CompletarModal`, `CerrarHiloModal`, etc.) siguen con `fixed`/z-50 — no se tocaron.

**Editar tarea: `TareaFormPanel` sirve crear y editar (prop `tarea`), no un componente nuevo.** El resolver sigue siendo `crearTareaSchema` (superset) y en modo edición `responsable_id`/`asignados` viajan como defaults ocultos: se cambian por "Reasignar", que ya es la única autoridad sobre `tareas_asignados`. El submit llama `editarTarea`, que valida con `editarTareaSchema` — extiende un `tareaEditableSchema` nuevo (base común con `crearTareaSchema`) y descarta las claves de más que manda el form. Gate de UI: `esAsignado` (creador/responsable/asignado activo/`ajenas`), que es exactamente el `USING` de `tareas_update`. El disparador es el título de la tarea, no toda la fila — la fila ya tiene select/range/botones adentro y anidar interactivos rompe accesibilidad.

**"Agregar paso" ya no pide un título: convierte y abre el panel del hilo.** `agregarPasoATarea` (creaba hilo + un 2do paso con título pedido en un panel) se reemplazó por `convertirTareaEnHilo(tareaId)`: crea el hilo con título/descripción/visibilidad/proyecto/responsable de la tarea, mueve la tarea adentro y no crea ningún paso extra — los pasos se agregan desde el panel del hilo, que la UI abre sola. `AgregarPasoPanel.tsx` y `agregarPasoSchema` se eliminaron. La apertura automática es una prop `autoAbrir` en `HiloCard`: la card del hilo nuevo puede montarse antes o después de que el padre marque el id (según cuándo llegue el `revalidatePath`), así que reacciona al cambio de prop **durante el render** con el patrón `autoAbrirBase` (mismo criterio que `estadoBase`/`sigBase` — `react-hooks/set-state-in-effect` es error, no warning).

**Notas de tarea visibles por defecto y precargadas en la query, no fetch por fila.** `mostrandoNotas` arranca en `true` (el botón "Notas" ahora colapsa, no carga), y `getListaTareas` trae `tareas_notas(...)` embebido — con la sección abierta en cada fila, el fetch on-mount de `NotasSection` serían N requests (cada uno con su `auth.getUser()`). `activo` y el orden de las notas se resuelven en JS: filtrar un embed en PostgREST lo convierte en inner join y se perderían las tareas sin notas. `NotasSection` acepta `notasIniciales` y saltea el fetch inicial cuando lo recibe; las notas de hilo siguen pidiéndose on-mount (el panel del hilo se abre de a uno).

**Los modales de confirmación también pasan a `<dialog>`: `components/ui/Modal.tsx` nuevo.** Verificado en browser: un modal lanzado desde `TareaRow` dentro de `HiloDetailPanel` (ej. "Completar tarea") era un `div fixed z-50` **dentro** del subtree del panel, que ya estaba en el top layer — el overlay del modal no oscurecía el panel y el modal quedaba centrado en el viewport, tapado por el panel según el ancho de ventana. `Modal` extrae el shell que `CompletarModal`/`CerrarHiloModal`/`DeshacerConversionModal`/`CrearUsuarioModal` duplicaban (overlay + card + header con X) y lo abre con `showModal()`, así el modal se promueve al top layer después del panel y queda arriba. `PermisosModal` sigue como estaba (excepción ya documentada).

**Notas: el `<textarea>` aparece recién al apretar "Agregar nota".** Con la lista de notas visible por defecto en cada tarea, un textarea por fila llenaba la vista de inputs vacíos. El historial se sigue viendo siempre; el input es on-demand y se cierra solo al guardar.

**Orden por temperatura también en `HiloDetailPanel`.** Mismo `useOrdenTemperatura` que "Mis tareas"/`ProyectoDetailPanel` — los pasos del hilo se reordenan en vivo al arrastrar el slider.

**`OverflowMenu` posiciona el dropdown con `fixed` + `getBoundingClientRect`, no `absolute`.** Dentro de un panel con `overflow-y-auto` un menú `absolute` lo recorta el contenedor (se veía cortado en `HiloDetailPanel`). `fixed` no lo recorta ningún ancestro con overflow; la posición se calcula al abrir y se decide arriba/abajo según el espacio libre (alto estimado por cantidad de ítems — ver comentario `ponytail:`). Contrapartida: al scrollear el contenedor el menú se despegaría del botón, así que un listener de `scroll` en captura lo cierra.

**`TareaRow`: se fue el botón "Notas" y las notas se muestran siempre.** Con la lista de notas + "Agregar nota" ya visibles en cada fila, el toggle no agregaba nada. En el menú de acciones "Posponer" pasó al primer lugar (antes "Reasignar") — es la acción más frecuente.

**Presets de vencimiento (1/3/7 días) en `TareaFormPanel`.** Botones que hacen `setValue("fecha_vencimiento", sumarDiasISO(hoyISO(), n))` sobre el mismo `<input type="date">` — sin campo ni estado nuevo. Los días viven en `VENCIMIENTO_PRESETS` en el componente; no se hizo configurable (mismo criterio que los umbrales de `TareaRow`).

---

## Módulo tareas — editar plantillas (sin SQL)

`editarPlantilla` reusa el mismo `PlantillaFormPanel` con prop `plantilla` (mismo patrón que `TareaFormPanel` para editar tarea) y **no necesitó migración**: `tareas_plantillas_update` / `tareas_plantillas_items_update` ya existían en `sql/005` (gateadas solo por `tiene_permiso('tareas_plantillas')` — la plantilla es un recurso de equipo, no del creador), y los items ya tenían `activo` y `orden`.

**Un solo schema para crear y editar: `id` opcional en cada item.** `plantillaItemSchema` lleva `id?` — presente = paso que ya existe (se actualiza `titulo`/`orden`), ausente = paso nuevo (insert). Los items activos que no vuelven en el submit se desactivan (`activo = false`, nunca DELETE). `crearPlantilla` ignora el `id` porque ya mapeaba columna por columna.

**El `orden` sale de la posición en el form, no de un campo editable** — `items.map((item, i) => ({ ...item, orden: i }))` en el submit, ya era así al crear.

**Editar una plantilla no toca las tareas ya generadas.** `agregarTareasDesdePlantilla` copia los títulos, no referencia los items — así que no hay nada que propagar. El panel lo dice explícito en modo edición para que no se espere lo contrario.

**Un `update` por paso existente en vez de un upsert masivo** — son un puñado de pasos por plantilla; armar un upsert con todas las columnas para ahorrar round-trips no se paga.

---

## Audit P0 UI/UX — errores, confirmaciones, foco, boundaries

- **Errores de Supabase nunca crudos.** `mensajeError(error)` en `lib/utils.ts`: mapa por código (`23505`, `23503`, `23514`, `42501`, `email_exists`, `weak_password`) y genérico para el resto. Todas las actions de `tareas` y `usuarios` lo usan. Los mensajes de Zod sí se muestran tal cual — ya están escritos para el usuario.
- **`ConfirmModal` vive en `components/ui/Modal.tsx`**, no en archivo propio: es una envoltura de 30 líneas sobre `Modal` y se usa en 5 lugares. Reemplaza los `confirm()` nativos (que no respetan el design system ni el `<dialog>` en top layer).
- **Foco visible: una sola regla global** en `@layer base` (`a, button, [tabindex]` → `outline-2 outline-offset-2 outline-brand-500`) en vez de un `:focus-visible` por clase. `select` queda afuera a propósito: usa `.input`, que ya tiene su propio `:focus`.
- **`loading.tsx` + `error.tsx` en `app/(erp-app)/`**, no por ruta: las 5 páginas del grupo son server components esperando Supabase y el feedback es el mismo. Bajar el boundary a cada ruta cuando alguna necesite un skeleton propio.
- **Hamburger y cerrar de `MobileNav` a 44×44**: la regla de 44px de `globals.css` solo aplica a `.btn`/`.input`/`.nav-item`/`.icon-btn` y esos dos botones no usan ninguna.

---

## P1 responsive y legibilidad

- **Sidebar desde `md` (768px), no `lg`.** Un iPad portrait (~820px) recibía drawer mobile con densidad desktop. De las dos opciones (sidebar en `md` vs layout compacto hasta 1024px) se eligió bajar el breakpoint: 220px de sidebar dejan 548px de contenido a 768px, y el padding sigue en `p-4` hasta `lg`, así que la densidad compacta se mantiene en la franja tablet. Toca `Sidebar.tsx`, `MobileNav.tsx` y `app/(erp-app)/layout.tsx` — los tres tienen que usar el mismo breakpoint o el drawer y el aside conviven.
- **`max-w-[1280px] mx-auto` en el `<main>`.** A 2560px las filas medían ~2300px y el título quedaba a un vacío enorme de las acciones.
- **`formatFecha` / `formatFechaHora` en `lib/utils.ts`** reemplazan los tres formatos que convivían (ISO crudo, `slice(0,10)`, `toLocaleString("es-AR")`). `formatFecha` acepta las dos formas: un `date` de Postgres (`length <= 10`) se ancla a mediodía UTC para que la conversión de zona no lo corra un día; un `timestamptz` se convierte a hora AR. Ese anclaje es el motivo de que la función no sea un `toLocaleDateString` pelado.
- **Marcas de fila con texto, no solo `title=`.** `Lock`, `Repeat`, `ExternalLink` y `Clock` en `TareaRow` (y `Lock`/`Clock` en `HiloCard`) eran ícono solo con tooltip: en touch no hay hover, así que esa información no existía en celular ni tablet. Pasaron del renglón del título a la línea de metadatos (que ya hace `flex-wrap`) como ícono + texto: "Privada", "Cada 2 día(s)", nombre de la app, "Pospuesta hasta 20/8/26".
- **Temperatura con rango.** `temperaturaRango()` local en `TareaRow`: Baja / Media / Alta por tercios (34 y 67) con color, y el número entre paréntesis para el ajuste fino. Vive en el componente porque `TareaRow` es el único lugar que la muestra — si aparece un segundo consumidor, sube a `types.ts`.
- **Temperatura oculta si la tarea está completada o cancelada**: ni el dato en la línea de metadatos ni el slider. Reusa el `activa` que ya existía.
- **`HiloCard` muestra "N/M completadas"** en vez de un número pelado, y `t-caption` sube a 13px por debajo de 768px: era la clase que carga fecha, temperatura y asignados de cada fila.
- **`ModuleTabs` con `overflow-x-auto` + `shrink-0`** en los links: 4 tabs a 360px se cortaban.
- **Auditoría: una línea de fechas** (`Creada 17/8/26 → Asignada 17/8/26 → Completada 17/8/26 09:57`) armada con `.filter(Boolean).join(" → ")`, en vez de tres `<p>` con etiquetas repetidas.

---

## P1 responsive: acciones de fila siempre en `OverflowMenu`

Usuarios, Proyectos y Plantillas tenían las acciones como botones sueltos en la fila (incluido "Desactivar" en rojo), con un cluster derecho de ~250px que a 390px desbordaba porque el bloque de texto no podía encogerse. Ahora siguen el patrón de `TareaRow`: **badge + `OverflowMenu`**, y el bloque de texto es `min-w-0 flex-1` con `truncate`.

- Nombre de la fila clickeable = abre lo principal (detalle en Proyectos, edición en Plantillas), como ya hacía `TareaRow` con el título. En Proyectos eso reemplaza el botón "Ver tareas", que queda igual dentro del menú para no depender solo del click en el texto.
- El menú siempre tiene al menos un ítem: en Proyectos "Ver tareas" no depende de permisos, así que un usuario sin `gestionarAjenas` no ve un menú vacío.
- Ícono de desactivar: `Archive` en los tres, mismo que `TareaRow`.

---

## P2 — búsqueda, paginación y contador de resultados

Cierra los tres ítems P2 del backlog. Regla de `GUIDE_DESIGN.md`: >20 registros → paginar, y siempre mostrar el total encontrado.

- **Un solo componente cubre contador + paginador.** `components/ui/Paginacion.tsx` exporta `usePaginado(items)` (headless: devuelve `visibles` + el resto de las props) y `<Paginacion {...paginado} etiqueta="usuarios" />`. El contador de total se renderiza siempre; los botones anterior/siguiente solo cuando hay más de una página. Así un listado corto igual muestra el total sin código extra — que era el segundo ítem del backlog.
- **`POR_PAGINA = 20` constante del módulo, no prop.** Ningún listado pidió otro tamaño todavía.
- **La página fuera de rango se corrige durante el render** (`Math.min(pagina, totalPaginas - 1)`), no con `useEffect`: al filtrar, la página actual puede dejar de existir. Mismo patrón "adjusting state during render" que ya usan `TareaRow` y `CerrarHiloModal` por `react-hooks/set-state-in-effect`.
- **`components/ui/SearchInput.tsx`**: el buscador que ya tenía `TareasListaView` pasa a componente (4 usos, 2 módulos). Usa `type="search"` — la X nativa para limpiar sale gratis.
- **Búsqueda del lado del cliente, sobre los datos que la vista ya recibe.** Nombre + email en Usuarios, nombre + descripción en Proyectos y Plantillas. Filtrar en Supabase recién cuando un listado no entre completo en memoria; hoy todos llegan enteros a la vista.
- **Estado vacío con dos mensajes** ("Sin resultados / Probá con otro término" vs. "Sin X todavía / Creá el primero"), según haya o no texto de búsqueda.
- **"Mis tareas" queda sin paginar a propósito** (marcado con `ponytail:` en `TareasListaView`): la vista agrupa hilos (cards con tareas anidadas) y tareas sueltas, y paginar la concatenación de los dos grupos confunde. Sí tiene contador ("N hilos · M tareas sueltas"). Paginar por grupo cuando alguien pase de ~20 hilos.
- **Toaster: el problema no era el `position`, era el offset.** Sonner ya estira el toaster a ancho completo por debajo de 600px (su propio `@media (max-width: 600px)` le pone `width: 100%` y offsets laterales), así que `top-center` no habría cambiado nada visible en mobile; lo que tapaba el topbar (`h-14` = 56px, en flujo normal) era el `top: 16px` fijo. Fix: `mobileOffset={{ top: "72px" }}` en `app/layout.tsx`. `position` sigue en `top-right` para desktop, donde no hay topbar con qué chocar.

---

## Miembros de proyecto = quién puede recibir tareas (`sql/009`)

Implementado. **Todo proyecto exige al menos un miembro** (antes solo los privados) y los asignables de una tarea con proyecto se limitan a los miembros de ese proyecto. Los dos ejes quedan ortogonales: `visibilidad` decide **quién ve**, la membresía decide **quién trabaja**. Aplica a proyectos públicos y privados por igual — por eso la acción "Miembros" ya no se esconde en los públicos.

La regla vive en la base, en tres piezas, porque tiene tres caras y una sola no alcanza:

1. `tareas_asignados_insert`/`update` — cambian los asignados de una tarea. La condición se exige solo si la fila queda activa (`NOT activo OR es_miembro_proyecto_de_tarea(...)`): desactivar una asignación al reasignar tiene que seguir siendo posible aunque el usuario ya no sea miembro.
2. Trigger `validar_proyecto_tarea` — cambia el proyecto de la tarea (editarla, asociarla a un hilo de otro proyecto). Se valida en trigger y no en policy porque el dato que se compara vive en otra tabla.
3. Trigger `validar_quitar_miembro` — se quita un miembro que tiene tareas activas: error explícito (`TA001`), no desactivación silenciosa de sus asignaciones.

`tareas_gestionar_ajenas` **no** saltea la regla: es una regla de negocio ("quién trabaja"), no un nivel de permiso — un manager agrega el miembro primero. El filtro del picker es UX, no barrera.

Efectos colaterales que la implementación obligó a resolver:

- `tareas_proyectos_miembros_select` se extendió con `es_miembro_proyecto(proyecto_id, auth.uid())`. Sin eso, un miembro que no es creador del proyecto solo se ve a sí mismo y el picker de asignados le queda vacío.
- `gestionarMiembrosProyecto` pasó a guardar un **diff** (quitados/agregados) en vez de desactivar todo y reinsertar: el patrón viejo disparaba `TA001` sobre los miembros que se quedaban.
- `getProyectoMiembros(id)` (N+1, solo privados) se reemplazó por `getMiembrosPorProyecto()`: una query que devuelve `Record<proyecto_id, usuario_id[]>` para todos los proyectos visibles. Ese mapa se dropea por props junto a `proyectos`, igual que `plantillas`.
- El proyecto efectivo de una tarea es `COALESCE(tarea.proyecto_id, hilo.proyecto_id)` — de ahí el prop `proyectoHeredadoId` en `TareaFormPanel`/`TareaRow`: la tarea de un hilo no guarda proyecto propio (lo prohíbe un CHECK) pero igual hereda sus miembros.
- Backfill de proyectos sin miembros activos = creador + responsables de sus hilos + todo usuario con asignación activa en sus tareas, para no dejar bloqueada ninguna reasignación existente.

Verificado end-to-end con dos usuarios (`sql/tests/rls_miembros_asignables.sql`, 15/15). El test no es una migración: corre dentro de una transacción con `ROLLBACK`, cambia a rol `authenticated` y setea `request.jwt.claims` para mover `auth.uid()` entre los dos usuarios. Le desactiva `tareas_gestionar_ajenas` al usuario de prueba dentro de la tx — con el bypass puesto, las policies se cortan en la primera rama y no se prueba nada. Confirmado en la base, no solo por lectura del SQL:

- Un miembro que no es creador ve a **todos** los miembros del proyecto (el caso que dejaba el picker vacío); en un proyecto ajeno ve 0.
- La membresía se exige sobre el **asignado**, no sobre quien actúa, y también cuando el proyecto se hereda del hilo.
- `tareas_gestionar_ajenas` no saltea la regla ni siendo creador del proyecto.
- Desactivar la asignación de alguien que ya no es miembro sigue permitido; reactivarla, no.

Volver a correrlo entero después de tocar esas policies.

Fuera de alcance por ahora: `tareas_hilos.responsable_id` y `tareas.responsable_id` no se validan contra la membresía. El responsable siempre está entre los asignados por schema (`crearTareaSchema`), así que la policy de `tareas_asignados` ya lo cubre en la práctica; el responsable de un hilo no es una asignación.

## Decidido, pendiente de implementar: proyecto con cara de hilo

El proyecto **no se convierte en hilo** (sin `estado` abierto/cerrado ni cierre automático): se le da la *cara* de hilo — progreso "X/Y completadas" y métricas en `ProyectoDetailPanel`, que es cálculo puro sobre datos que ya llegan al panel. Si el proyecto tuviera estado propio, el nivel del medio (hilo) se quedaría sin razón de existir.

---

## Permisos: vista y función se autorizan por separado (`PermisosModal`)

Hasta ahora `syncVista()` derivaba el checkbox de la vista de sus funciones: marcar una función encendía la vista, desmarcar la última la apagaba. La vista no era un permiso que se pudiera tocar — era un cálculo. Pedido explícito de usuario: **vista y función son checkboxes independientes**.

- `syncVista()` y `toggleVista()` eliminados. `toggle()` es add/remove puro.
- Checkbox tri-state en el nombre del módulo: marca/desmarca todo. **Opera solo sobre los submódulos que la búsqueda deja visibles** — el contador `marcados/visibles` al lado del label se calcula sobre el mismo set. Marcar permisos fuera de pantalla sería un cambio invisible.
- Badge `Vista` (`badge-info`) / `Función` (`badge-neutral`) en cada fila. La indentación sola deja de alcanzar cuando la búsqueda filtra y rompe la jerarquía visual.
- El bulk-toggle por vista sobrevive pero como control aparte: botón de texto `Todas`/`Ninguna` a la derecha de la fila, solo si la vista tiene funciones visibles. Opera sobre `[vista, ...funciones visibles]` — incluye la vista a propósito: marcar solo las funciones generaría huérfanas y bloquearía el guardado. El checkbox de la vista queda libre para lo que es, su propio permiso.
- La fila de vista dejó de ser un `<label>` envolvente: un `<button>` dentro de un label dispara el checkbox al click. Ahora es un `div` con el label en `flex-1` y el botón afuera.

**Función sin su vista queda prohibida, y la barrera está en servidor.** El desacople hace posible un estado que antes era inalcanzable: función autorizada, vista no. Ese permiso no se ve en la UI (el botón vive dentro de una vista que el usuario no puede abrir) pero **sí se ejecuta por server action** — la action chequea el código de la función, nunca el de su vista. `asignarSubmodulos()` rechaza el payload consultando `submodulos.vista_id` de cada función entrante contra el set autorizado. La UI valida lo mismo (`huerfanas`): warning en la fila y `Guardar` deshabilitado.

**Orden en `asignarSubmodulos()`:** la validación va **antes** del `update activo:false`. Al revés, un payload inválido dejaba al usuario sin ningún permiso y después devolvía error — la desactivación y el upsert no comparten transacción.

Datos existentes verificados sin huérfanos antes del cambio (el modelo viejo los hacía imposibles), así que no hizo falta backfill.

**Corrección a la sección "UI: panel lateral derecho reemplaza modal":** la excepción anotada ahí ("`PermisosModal.tsx` sigue modal") está desactualizada — ya usa `RightPanel`. Solo el nombre del archivo quedó viejo.
