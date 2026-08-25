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

**Vista "Mis tareas" → vuelve a "Lista": se revirtió el filtro a propios.** El filtro `esPropia` de `TareasListaView` (restringía a creador/responsable/asignado activo, sin excepción para `tareas_gestionar_ajenas`) se sacó: la visibilidad la decide RLS y nada más. Un usuario sin `tareas_gestionar_ajenas` sigue viendo solo lo suyo porque la política de `tareas`/`tareas_hilos` no le devuelve el resto (`sql/005`); un manager ve todo, que es lo que el permiso significa. Motivo del rollback: el filtro era solo de nivel superior — `HiloCard` recibía `tareas` completo y listaba todas las tareas del hilo igual, así que la vista mostraba "propias" con contenido ajeno adentro. Label del tab vuelve a "Lista" en `layout.tsx` (`tareas_lista` sigue siendo el código de permiso — el label es un string local del layout, no viene de `submodulos.nombre`). El filtro "Todos los asignados" se restauró como `<select>` en la toolbar, con **default en el usuario actual** (`useState(usuarioActualId ?? "")`): "lo mío" pasa a ser un default, no una restricción — el panorama del equipo queda a un click y lo sigue acotando RLS. Semántica del filtro: `esDeUsuario()` matchea `responsable_id` OR asignado activo, igual para cualquier usuario elegido (ver más abajo: nació como `estaInvolucrado()` con `creado_por` y se corrigió). Un hilo entra si coincide él mismo (título + `responsable_id`) o si alguna de sus tareas coincide. La opción vacía se llama "Todos los usuarios" (no "Todos los asignados": el filtro ya no es solo por asignación).

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

---

## Módulo tareas — isla compartida, panel de proyecto y edición de hilo

Pedido de usuario, siete puntos (uno — qué pasa con las asignaciones al quitar un miembro — quedó salteado a pedido). Todo se resolvió en UI/TS: **cero SQL**. `tareas_hilos_update` y `tareas_proyectos_update` (`sql/005`) ya autorizan creador / responsable / `tareas_gestionar_ajenas`, que es exactamente quién puede modificar.

**Las tres entidades del módulo comparten cara: `Isla.tsx`.** Hilo, tarea y proyecto se ven igual en cualquier listado (título clickeable + badges + fila de métricas) y el click abre su panel derecho. La isla no tiene acciones propias — todo lo que se hace sobre la entidad vive en su panel. Eso obligó a partir `TareaRow` en dos:

- `TareaCard.tsx` — la isla. Conserva el estado optimista (`estadoLocal`/`tempLocal`) porque la isla los sigue mostrando con el panel cerrado, y porque el orden por temperatura de la vista se refresca mientras se arrastra el slider (`useOrdenTemperatura`). Bajan al panel por props: una sola fuente para el badge y el control.
- `TareaDetailPanel.tsx` — acciones, detalle y notas. "Modificar tarea" pasó del click en el título (que ahora abre el panel) al menú del panel.

`ProyectosView` dejó de ser una lista de filas con `OverflowMenu`: son islas (`ProyectoCard`) y las acciones — modificar, desactivar, agregar hilo/tarea — viven en `ProyectoDetailPanel`. Se conservan búsqueda y paginación.

Piezas compartidas que salieron de ahí: `MetricasResumen.tsx` (antigüedad + próximo vencimiento, antes inline en `HiloCard`), `tareaLabels.ts` (labels/badges de estado, recurrencia, `temperaturaRango`, `iniciales`) y `proyectoTareas.ts` (`tareasDeProyecto`: las tareas de un hilo no guardan `proyecto_id`, lo heredan — isla y panel tienen que contar lo mismo).

**`ProyectoFormPanel` es panel único de crear/modificar y absorbió `MiembrosPanel.tsx`** (borrado): los miembros son una característica más del proyecto, no una pantalla aparte. `gestionarMiembrosProyecto` → `editarProyecto` (mismo diff de quitados/agregados, ver `db_schema.md`). Esto y `MetricasResumen` se recuperaron del stash `9cc8e8e` que se había descartado el 2026-08-18 — el `sql/010` de ese stash **no** se tocó, sigue revertido.

**Editar hilo = solo título y descripción** (ampliado después con visibilidad — ver la sección "Editar hilo incluye la visibilidad" al final). `HiloFormPanel` gana modo edición con el mismo patrón que `TareaFormPanel`: el schema del form sigue siendo `crearHiloSchema` (superset) y proyecto/visibilidad/responsable viajan como defaults ocultos; `editarHiloSchema` (título + descripción + id) es lo que valida el server. Mover un hilo de proyecto queda fuera a propósito: cambiaría quiénes pueden trabajar en sus tareas y esa validación existe sobre `tareas` (`validar_proyecto_tarea`, `sql/009`), no sobre `tareas_hilos`.

**Dueño del hilo visible.** El "owner" es `responsable_id` (no `creado_por`): es quien responde por el hilo. Se muestra en la isla y en el panel; el nombre sale del array `usuarios` que ya llega por props, sin query nueva.

**Visibilidad pública por defecto al elegir proyecto.** Es *default*, no regla: el select sigue ahí y el usuario puede volver a privada. Aplica al abrir el form desde un proyecto y también al elegir proyecto dentro del form, salvo que el usuario ya haya tocado visibilidad (`dirtyFields.visibilidad`) — un default no pisa una decisión explícita. Editar una tarea existente no cambia su visibilidad.

**Filtro por usuario en Proyectos = membresía**, no "tiene tareas ahí": la membresía es quién trabaja en el proyecto (`visibilidad` es el otro eje, quién lo ve) y sale de `miembrosPorProyecto`, que ya llega por props — 0 queries nuevas. Arranca en el usuario actual, mismo default que la vista Lista.

---

## Módulo tareas — ser creador deja de dar visibilidad (`sql/013`)

Pedido de usuario, verificado contra el código antes de tocar nada: la regla que quería ("sin `tareas_gestionar_ajenas` se ve lo asignado y lo público; si te sacan la asignación dejás de ver, aunque lo hayas creado") **no se cumplía**, y la brecha estaba entera en SQL — los paneles no re-filtran, muestran lo que RLS devolvió. `tareas_select`, `puede_ver_hilo` y `tareas_proyectos_select` autorizaban por `creado_por`.

**Qué cambia.** `creado_por` sale de la visibilidad de tareas, hilos y proyectos. Sobreviven tres actores: `tareas_gestionar_ajenas`, la asignación activa, y `tareas_hilos.responsable_id` — el dueño del hilo, que es un rol, no una asignación. En tareas, `responsable_id` salió del SELECT: el schema ya exige `responsable ∈ asignados` (`crearTareaSchema`) y la base confirmó 0 filas donde no se cumpliera, así que la rama era redundante.

**La tarea suelta, pública y sin proyecto ahora se ve.** `tareas_select` exigía `proyecto_id IS NOT NULL` para la rama pública; sin la rama del creador tapando el hueco, esa tarea no la vería nadie. Hay 1 en la base.

**Los UPDATE se alinearon con los SELECT.** Dejar `creado_por` en el UPDATE habría creado la fila modificable pero invisible — y un UPDATE denegado por RLS no falla, afecta 0 filas: el bug sería silencioso. Consecuencia buscada: el creador de un proyecto que se sacó a sí mismo de los miembros ya no puede editarlo (hay 1 proyecto así).

Dos huecos que aparecieron al sacar al creador y hubo que cerrar en la misma pasada, porque devolvían por API la visibilidad que la regla quita:

- `es_responsable_o_creador_tarea()` → `es_responsable_tarea()` (la vieja se borró). Con la rama del creador, quien perdía la asignación se re-insertaba en `tareas_asignados`. No hace falta para crear: `tareas_insert` ya exige `responsable_id = auth.uid()` a quien no tiene `tareas_gestionar_ajenas`.
- `tareas_asignados_update` acota `usuario_id = auth.uid()` a `NOT activo` en el `WITH CHECK`. Sacarme de una tarea sigue siendo mío; reactivar mi propia fila, no.

**Contrapartida: el responsable del hilo puede tocar las tareas de su hilo** (rama nueva en `tareas_update`). Sin eso, "deshacer conversión" y el cierre de hilo — que actualizan tareas a las que el dueño no está asignado — pasaban a no hacer nada, en silencio.

**`crearTarea`, `crearProyecto` y `agregarTareasDesdePlantilla` generan el id en el server** y dejan de pedir `RETURNING`. Sin la rama del creador, la fila recién insertada todavía no es visible para quien la insertó (sus asignados/miembros se insertan en el statement siguiente) y `.select()` rompía con RLS violation. Es el mismo patrón — y el mismo comentario — que ya tenía `crearHilo` por el motivo análogo.

**La UI dejó de ofrecer lo que la RLS después descarta.** `TareaDetailPanel`, `HiloDetailPanel` y `ProyectoDetailPanel` derivaban `puedeGestionar` de `creado_por`; ahora usan responsable / asignado / miembro, espejo exacto del `USING` de cada policy. El filtro de la vista Lista conservó `creado_por` un rato más — "es un filtro sobre lo ya visible, no una barrera" — y eso fue un error de UX: filtrar por un usuario le mostraba tareas que creó y asignó a otro, contradiciendo la regla que el resto del módulo ya seguía. `estaInvolucrado()` pasó a `esDeUsuario()` = `responsable_id` OR asignado activo, y el match de hilos perdió `h.creado_por`. Sigue sin ser una barrera; es que "de quién es esta tarea" lo contesta la asignación, no la autoría.

Verificado con `sql/tests/rls_visibilidad_tareas.sql` (mismo mecanismo que el test de `sql/009`: dos usuarios reales, rol `authenticated`, `ROLLBACK` al final). Correr los dos tests después de tocar estas policies.

## Miembros de proyecto = función propia del módulo (`tareas_proyectos_miembros`)

Pedido de usuario en la misma tanda. Es un submódulo-función bajo la vista `tareas_proyectos` — no un permiso nuevo ni un rol: la regla del proyecto es que toda autorización nueva se implementa como submódulo. Las policies de `tareas_proyectos_miembros` pasan de `es_creador_proyecto()` a `tiene_permiso('tareas_proyectos_miembros')`.

**La siembra inicial es la excepción, y está acotada.** Todo proyecto exige al menos un miembro (`sql/009`), así que sin una salida `tareas_proyectos_crear` no alcanzaría para crear nada. La rama `es_creador_proyecto(...) AND NOT proyecto_tiene_miembros(...)` la habilita solo mientras el proyecto no tenga miembros: una vez creado, cambiar quién trabaja en él exige la función. Sin esa cota, el creador se re-agregaba como miembro y recuperaba el acceso que `sql/013` le saca.

**El bloque Miembros sigue dentro de `ProyectoFormPanel`** — no vuelve a ser panel aparte (eso se decidió y se mantiene). Lo que cambia es que se renderiza solo con el permiso; sin él la membresía viaja como default oculto del form, igual que proyecto/visibilidad en `HiloFormPanel`, y el diff de `editarProyecto` queda vacío. La barrera real es la RLS, no el condicional.

**Backfill:** la función se le otorga a los creadores de proyectos activos, para no romper proyectos en curso. Para el resto, alta manual desde Usuarios.

**El SELECT de `tareas_proyectos_miembros` no mira la función.** El primer intento la agregaba ahí y el test de `sql/009` lo cazó (caso 02: TESTER, que recibió la función por el backfill, veía los miembros de un proyecto del que no es parte). La rama sobraba además de filtrar: editar un proyecto ya exige ser creador-y-miembro o tener ajenas, así que quien usa la función entra igual por `es_miembro_proyecto`.

**Límite conocido:** administrar miembros de un proyecto **privado** exige además verlo, y eso ahora es ser miembro o tener `tareas_gestionar_ajenas`. La función sola no abre proyectos privados ajenos — es deliberado: sería una segunda puerta de visibilidad, justo lo que `sql/013` cierra.

Aplicado en Supabase vía MCP. Tests posteriores: `rls_visibilidad_tareas.sql` 17/17, `rls_miembros_asignables.sql` 15/15.

**El filtro por usuario ofrece la lista del equipo solo con `tareas_gestionar_ajenas`** (`TareasListaView`, `ProyectosView`). Sin la función quedan dos opciones: "Todos los usuarios" — que ya es lo propio más lo público, o sea todo lo que RLS devuelve — y uno mismo. No es una barrera (recortar por otro usuario nunca mostró de más, la RLS filtra antes) sino no ofrecer un recorte que no es de quien mira. `AuditoriaView` conserva el picker completo: la vista entera está gateada por `tareas_auditoria` y ese filtro es su razón de ser.

## Editar hilo incluye la visibilidad

Corrige la sección "Módulo tareas — isla compartida…": ahí `visibilidad` quedó bloqueada **de arrastre**, en el mismo bloque que `proyecto_id`, pero el motivo registrado solo aplica al proyecto. Mover un hilo de proyecto cambia quiénes pueden trabajar en sus tareas y ningún trigger lo revalida sobre `tareas_hilos`; cambiar su visibilidad no toca la membresía, solo quién lo ve (`puede_ver_hilo` la lee directo). Con la regla más estricta de `sql/013`, un hilo creado privado no tenía forma de volverse compartible salvo recreándolo.

- `editarHiloSchema` = título + descripción + visibilidad + id. **`visibilidad` va sin `.default()`** ahí, a diferencia de `crearHiloSchema`: en un update, omitirla dejaría el hilo en `privado` sin que nadie lo pida.
- El select de visibilidad sale del bloque `{!hilo && …}` de `HiloFormPanel`. Proyecto y responsable siguen dentro (solo al crear).
- Sin SQL: `tareas_hilos_update` ya autoriza a responsable o `tareas_gestionar_ajenas`, que es el mismo set que muestra el botón "Modificar hilo" en `HiloDetailPanel`.
- Efecto en cascada, buscado: pasar un hilo a privado también esconde sus tareas de quien no esté asignado — `tareas_select` resuelve las tareas con hilo vía `puede_ver_hilo`.

## La visibilidad de una tarea con hilo deja de mostrarse

Contracara de lo anterior: `tareas_select` lee `tareas.visibilidad` **solo** en la rama de tarea suelta (`hilo_id IS NULL`, `sql/013:57-64`). Con hilo, la visibilidad la resuelve entero `puede_ver_hilo` — quien está asignado a una tarea del hilo ve todas las demás, marcadas privadas o no. La UI ofrecía el control igual y lo mostraba en la isla y el panel, así que una tarea decía "🔒 Privada" a un usuario que la estaba leyendo.

- `TareaFormPanel`: el select de Visibilidad se esconde con `hiloId` o `tarea.hilo_id`, mismo criterio que el select de Proyecto (que ya se escondía). El valor viaja como default oculto — no se pierde, y vuelve a mandar si la tarea sale del hilo (`deshacerConversionHilo`).
- `TareaCard` y `TareaDetailPanel`: el indicador "Privada" pide además `hilo_id === null`.
- Sin SQL: la cascada todo-o-nada del hilo es el diseño, no el bug. El hilo es la unidad de trabajo; hacer que `privado` recorte dentro de él sería otra regla, no un arreglo.

---

## Asignar usuarios a una tarea es una función (`sql/014`)

Pedido de usuario: **el que no está autorizado no puede asignar**. Antes no había función que mirar — `tareas_asignados_insert` solo pedía ser responsable de la tarea, y como quien crea queda responsable, cualquiera podía repartir trabajo. La UI mostraba el picker en "Nueva tarea" sin chequear nada, y en "Modificar tarea" no lo mostraba nunca.

Submódulo-función nuevo `tareas_asignar` ("Asignar usuarios", vista `tareas_lista`). La regla es una sola y vive en la base: **poner a OTRO usuario en una tarea — como asignado o como responsable — exige la función; asignarse uno mismo, no.**

Tercer eje, ortogonal a los dos que ya había: `tareas_gestionar_ajenas` es autoridad sobre tareas que no son propias, la membresía del proyecto es quién puede trabajar, `tareas_asignar` es quién reparte. Las tres condiciones se exigen juntas y ninguna saltea a otra — por eso `sql/014` hace backfill de `tareas_asignar` a todos los que ya tenían `tareas_gestionar_ajenas` (mismo criterio que el backfill de `tareas_proyectos_miembros` en `sql/013`), en vez de dejar el bypass escrito en la policy.

`tareas_insert` **pierde** su rama `tareas_gestionar_ajenas`: nombrar responsable a otro al crear pasa a pedir `tareas_asignar`. El traspaso del responsable de una tarea que ya existe va por trigger (`validar_responsable_tarea`, `TA003`) y no por policy, porque `WITH CHECK` solo ve la fila nueva: no puede distinguir "cambió el responsable" de "el UPDATE tocó otra columna".

En la UI:

- **El picker aparece también al modificar la tarea** (decisión del usuario, antes solo al crear). El gate vive dentro de `AsignadosPicker` (`puedeAsignar`), no en cada panel: sin la función muestra solo el resumen de a quién le queda la tarea, y los valores siguen viajando como defaults ocultos del form. Un solo lugar para el bloque de solo-lectura, que si no se repetía en `TareaFormPanel` y `UsarPlantillaPanel`.
- "Reasignar" sigue en el menú como atajo, ahora gateado por la función. Con dos entradas para lo mismo, `tareas_asignados` necesitaba un solo escritor: `sincronizarAsignados()` en `actions.ts`, que usan `editarTarea` y `reasignarTarea`.
- **`sincronizarAsignados()` no toca nada si el conjunto no cambió.** Editar el título no debe reescribir asignaciones, y sin ese corte quien no tiene la función no podría guardar ningún cambio en una tarea compartida: los asignados viajan igual como defaults ocultos y reinsertarlos choca contra la policy.
- `TareaDetailPanel` pasa `proyectoHeredadoId` a `TareaFormPanel` al editar. Sin eso, la tarea de un hilo abría el picker con todos los usuarios en vez de con los miembros del proyecto del hilo — invisible mientras el picker no existía en edición.

Verificado end-to-end contra la base con `sql/tests/rls_miembros_asignables.sql` (19/19). El test creció a dos bloques: el primero corre con TESTER **sin** `tareas_asignar` ni `tareas_gestionar_ajenas`, el segundo le devuelve `tareas_asignar` y repite los mismos UPDATE — tienen que pasar de RECHAZO a OK. Sin ese espejo, un rechazo por membresía o por RLS de otra rama se leería como si la función nueva estuviera funcionando.

- `11`/`16` reactivar la asignación de ADMIN en P: ADMIN **es** miembro, así que el único motivo posible de rechazo es la función — aísla la regla nueva de la de `sql/009`.
- `12`/`18` traspasar el responsable: sin la función corta el trigger con `TA003`, no la policy con `42501`.
- `17` (ex `12`) sigue probando que la membresía se evalúa sobre el asignado y no sobre quien actúa, ahora con la función puesta.

Fuera de alcance: el responsable de un **hilo** (`HiloFormPanel`) sigue gateado por `tareas_gestionar_ajenas` en `tareas_hilos_insert`/`update`. El dueño del hilo no es una asignación (mismo criterio que `sql/009`).

---

## Módulo tareas — la vista Lista es de tareas, el hilo agrupa (sin SQL)

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

## Módulo tareas — desactivar un hilo se lleva sus tareas (sin SQL)

`desactivarHilo` desactivaba solo `tareas_hilos`. Las tareas quedaban con
`activo = true` apuntando a un hilo que `getListaTareas` ya no trae, y la vista
Lista las perdía: no son sueltas (`hilo_id !== null`) y su grupo no existe.
RLS seguía devolviéndolas — el trabajo asignado desaparecía de la UI para
todos, incluido quien tiene `tareas_gestionar_ajenas`.

La cascada va en el action, no en un filtro defensivo de la vista: el estado
"hilo inactivo con tareas activas" no debe existir. Las tareas se desactivan
primero — si ese update falla, el hilo queda intacto y no hay huérfanas.

No hace falta permiso extra: `tareas_update` ya tiene la rama del responsable
del hilo, que es exactamente quien puede desactivarlo (`tareas_hilos_update`).

## Módulo tareas — no se ofrece crear trabajo donde no podés trabajar

`puedeTrabajarEnProyecto` (`components/proyectoTareas.ts`) decide si el panel
del proyecto muestra "Agregar hilo/tarea" y si un proyecto aparece en el select
de `TareaFormPanel` y `HiloFormPanel`.

La regla sale de `sql/009` + `sql/014`: crear una tarea exige al menos un
asignado y solo los miembros del proyecto pueden serlo. Sin `tareas_asignar` el
único asignado posible es uno mismo, así que hay que ser miembro; con la
función alcanza con que haya algún miembro visible. `idsMiembros` ya viene
recortado por RLS — de un proyecto que no trabajás no ves a nadie.

Antes el form abría igual y moría en la validación de Zod pidiendo un asignado
que no se podía elegir. No es una barrera de seguridad (RLS ya lo bloquea):
es no ofrecer un camino que siempre termina en error.

## Nombrar responsable de un hilo = `tareas_asignar` (`sql/015`)

`tareas_hilos_insert` seguía pidiendo `tareas_gestionar_ajenas` para poner a
otro como responsable, mientras `sql/014` había movido esa misma decisión sobre
`tareas` a la función `tareas_asignar`. Dos ejes para una sola regla: poner a
OTRO a cargo exige `tareas_asignar`, y nada la saltea — tampoco
`gestionar_ajenas`, que es autoridad sobre lo ajeno, no permiso para repartir
trabajo.

Tres piezas, mismo reparto que en `tareas`:

- `tareas_hilos_insert` — `responsable_id = auth.uid() OR tiene_permiso('tareas_asignar')`.
- Trigger `validar_responsable_hilo` — el traspaso necesita el valor viejo, que
  un `WITH CHECK` no ve. Reusa `TA003`: el mensaje ya era genérico.
- `tareas_hilos_update` — el `WITH CHECK` suma `OR tiene_permiso('tareas_asignar')`.

La tercera pieza apareció al correr el test, no al escribir la policy: sin ella
el traspaso quedaba imposible incluso con la función, porque la fila nueva tiene
`responsable_id` ajeno y el `WITH CHECK` solo aceptaba `responsable_id = auth.uid()`.
En `tareas` el caso no aparece porque ahí el `WITH CHECK` tiene además la rama
del asignado activo (`sql/013`). El reparto que queda: el `USING` decide quién
puede tocar el hilo, el trigger decide quién puede quedar a cargo.

El caso `20b` de `sql/tests/rls_miembros_asignables.sql` existe para eso —
verifica que ese `WITH CHECK` más laxo no habilitó editar hilos ajenos.

## Ver miembros exige proyecto activo (`sql/016`)

`tareas_proyectos_miembros_select` no miraba `tareas_proyectos.activo`: archivar un
proyecto lo sacaba de la lista pero dejaba sus membresías visibles.

El filtro va en la policy y no en `getMiembrosPorProyecto` porque es la misma
pregunta que ya responde el SELECT de la tabla — "qué membresías te tocan" — y
duplicarla en la query dejaba la base contestando de más.

El `EXISTS` directo sobre `tareas_proyectos` fue lo primero que verifiqué: el
ciclo `tareas_proyectos` ↔ `tareas_proyectos_miembros` que documenta
`db_schema.md` causa `42P17` con `EXISTS` en ambas direcciones, pero acá el lado
de vuelta pasa por `es_miembro_proyecto` (`SECURITY DEFINER`), que ya lo rompe.
Probado en transacción antes de aplicar: sin recursión, 5 → 2 filas visibles.

## Decidido, pendiente de implementar: desactivar proyecto en cascada

`desactivarProyecto` desactiva solo la fila del proyecto. Sus hilos y sus tareas
sueltas quedan activos: el trabajo no desaparece de la Lista (el hilo sigue
siendo hilo, la tarea suelta sigue suelta), pero pierde la agrupación y queda
con `proyecto_id` apuntando a un proyecto archivado.

Decisión tomada: **cascada completa**, simétrica con `desactivarHilo` —
desactivar el proyecto desactiva sus hilos, y la cascada de hilos ya se lleva
las tareas de cada uno; faltan además las tareas sueltas del proyecto.
Archivar es "se va todo junto", no "se sueltan las partes".

Sin implementar todavía. Efecto secundario a resolver junto con esto: al editar
una tarea de un proyecto archivado, el select de `TareaFormPanel` no lista ese
proyecto (`puedeTrabajarEnProyecto` lo filtra) y el campo aparece vacío sobre un
valor que sigue seteado.

---

## Módulo tareas — pasos de tarea y vista Misión (`sql/017`)

Pedido: botón "crear siguiente paso" además de "crear tarea", ver los pasos previos al abrir una tarea, y una vista Misión que muestre la tarea actual de a una ordenada por temperatura.

**Pasos ≠ hilo.** El hilo agrupa tareas que corren en paralelo; la cadena de pasos las ordena. Son ejes ortogonales, así que un hilo puede tener tareas sueltas y cadenas al mismo tiempo. Riesgo asumido: dos formas de relacionar tareas en el mismo módulo. Se mitiga en UI — dentro del hilo la cadena se renderiza como cadena (1→2→3), no como filas planas mezcladas con las paralelas.

**Una columna, no una tabla.** `tareas.paso_anterior_id`. La regla es "se puede hacer si se cumple **el** previo" — un solo predecesor, cadena lineal. Una tabla `tareas_dependencias` sería un DAG genérico para un problema que no existe.

**La cadena vive dentro de un hilo** (`CHECK paso_anterior_id IS NULL OR hilo_id IS NOT NULL` + trigger de mismo `hilo_id`). Esta es la decisión que más ahorró: `tareas_select` ya cascadea visibilidad por `puede_ver_hilo`, así que "ver los pasos previos" no necesitó **ninguna** regla de visibilidad nueva. Encadenar tareas sueltas hubiera obligado a una función `SECURITY DEFINER` que devolviera stubs de los pasos invisibles, o a una UI que miente ("Paso 3 de 5" con 2 pasos que no se ven). Costo aceptado: crear un siguiente paso desde una tarea suelta obliga a tener hilo.

**"Bloqueada" es derivado, no un estado.** `paso_anterior.estado <> 'completada'`. Sumarlo a `estado_tarea` obligaba a sincronizarlo en cada completar/cancelar/reabrir — la duplicación de lógica que prohíbe la regla. La barrera de servidor es el trigger `validar_paso_previo` (`TA004`), no el enum.

**`cancelada` no bloquea.** El trigger solo corta el paso a `en_progreso`/`completada`. Si un paso se cancela la cadena queda trabada, y cancelar los que siguen tiene que seguir siendo posible o el hilo no cierra nunca.

**Ciclos: imposibles por construcción, sin validación.** `paso_anterior_id` es inmutable después del INSERT (`TA005`), y una fila nueva nunca puede ser ancestro de otra → el grafo es siempre un bosque. Recorrer la cadena buscando ciclos hubiera sido código para un caso que la inmutabilidad ya cierra.

**Recurrencia + pasos: prohibido de los dos lados** (opción b, elegida por el usuario). CHECK del lado siguiente, trigger del lado previo. Una instancia recurrente nace al completar la anterior; un paso de una cadena no tiene "próxima instancia" que signifique algo. Consecuencia buscada: `generar_recurrencia` no necesitó tocarse, porque nunca dispara sobre una tarea encadenada.

**Desactivar un paso del medio se bloquea, no se relinkea** (`TA007`, mismo criterio que `validar_quitar_miembro`). Va `AFTER` y no `BEFORE`: `deshacerConversionHilo` desactiva la cadena entera en un solo `.in(...)`, y un `BEFORE` por fila la vería a medio desactivar según el orden. Los `AFTER ROW` corren al final de la sentencia, con todas las filas ya actualizadas — verificado: desactivar la cadena completa pasa, desactivar solo el del medio falla. El `DEFERRABLE INITIALLY DEFERRED` **no** es lo que resuelve ese caso (el `AFTER` solo ya alcanza); suma desmantelar una cadena en varias sentencias dentro de una transacción, que hoy ningún caller hace. Escape hatch de una cadena: desactivar desde la cola.

**Mover de hilo una tarea encadenada se bloquea** (`TA006`). Sin eso el invariante "misma cadena, mismo hilo" se rompe por la puerta de al lado. Efecto colateral aceptado: `deshacerConversionHilo` falla sobre un hilo cuya primera tarea es parte de una cadena — semánticamente correcto (un hilo multi-paso no se puede colapsar en una tarea suelta) y falla antes de tocar nada.

**Los triggers son `SECURITY DEFINER` aunque no llamen a `tiene_permiso()`.** Un guard que la RLS puede dejar ciego no es un guard: si el `EXISTS` del paso siguiente se filtrara por RLS, un usuario que no lo ve rompería la cadena sin que el trigger se entere.

**Misión es vista, sin función propia.** "Crear siguiente paso" es crear una tarea, y crear tareas ya lo gatea `tareas_lista` — una función nueva sería un permiso más fino sin necesidad demostrada. La vista no lee nada que la Lista no lea: reusa `getListaTareas()` (que ya corre `resolver_pospuestos`) y filtra en memoria a mis asignadas, `pendiente`/`en_progreso`, no bloqueadas; el orden sale de `useOrdenTemperatura`, sin query nueva. Backfill del submódulo a todo el que tenía `tareas_lista`, por el mismo motivo.

## Módulo tareas — UI de pasos y vista Misión

**"Agregar paso" pasó a llamarse "Convertir en hilo".** El menú de una tarea suelta ya usaba ese label para `convertirTareaEnHilo`, que no agrega ningún paso: convierte la tarea en hilo para poder sumarle tareas. Con pasos reales en el módulo el nombre viejo pasaba a mentir. Tercera colisión del mismo término — las plantillas también llaman "pasos" a sus items (`plantillaItemSchema`), que son títulos ordenados sin bloqueo; eso quedó sin tocar.

**"Crear siguiente paso" aparece solo en la cola de la cadena** (`posicion === total`) y solo si la tarea tiene hilo. La unique parcial de `paso_anterior_id` no deja bifurcar, así que ofrecerlo en el medio sería ofrecer un `23505`.

**Bloqueada esconde "Completar" y la opción "En progreso", no "Cancelada".** Espejo exacto de `validar_paso_previo`, que solo corta esas dos transiciones. Cancelar tiene que seguir disponible o una cadena con un paso trabado no se cierra nunca. El panel además dice cuál es el paso que la traba, en vez de dejar el botón gris sin explicación.

**El panel muestra la cadena entera, no solo la previa.** El pedido era "ver tareas previas"; mostrar la lista completa con la posición marcada cuesta lo mismo y contesta también "cuánto falta". El estado del paso actual sale del estado optimista del panel y no de la fila del server — misma regla que `tareaLabels.ts`: la misma tarea no puede leerse distinto según dónde se la mire.

**`agruparCadenas()` mantiene contigua cada cadena dentro del hilo.** El orden por temperatura se respeta para elegir dónde arranca la cadena, pero sus miembros salen juntos y en orden. Sin eso una cadena se lee como tareas sueltas y pierde lo único que la distingue de un hilo.

**`esDeUsuario` y `esActiva` salieron a `tareaFiltros.ts`.** El primero vivía en `TareasListaView`, el segundo inline en `MetricasResumen`; Misión necesitaba los dos. Regla de "si existe en más de un lugar, se extrae" — no se duplicó para la vista nueva.

**Misión renderiza `TareaCard`, no una tarjeta propia.** Toda la superficie de acciones (completar, estado, temperatura, panel de detalle) ya vive ahí; una tarjeta "de misión" sería una segunda cara de la misma tarea para mantener sincronizada. Lo propio de la vista es el recorte y la navegación de a uno.

**El índice de Misión se recorta, no se resetea.** Al completar la tarea actual la cola se acorta y la misma posición pasa a mostrar la siguiente — que es lo que se espera de una vista "de a una". Un `useEffect` que resetee a 0 mandaría al usuario de vuelta al principio en cada completada.

**Misión esconde las tareas de hilos pospuestos**, no solo las tareas pospuestas: si el hilo espera, su contenido no es "lo que toca ahora". El estado vacío dice cuántas tareas están esperando un paso previo — si no, una Misión vacía con trabajo bloqueado se lee como una vista rota.

## Módulo tareas — las plantillas generan una cadena

`agregarTareasDesdePlantilla` encadena los items en vez de crear N tareas sueltas: `paso_anterior_id` de cada uno apunta al anterior. `tareas_plantillas_items.orden` siempre significó "primero esto, después aquello" — hasta acá era una sugerencia visual sin consecuencia.

**Sin flag ni checkbox: la plantilla siempre encadena.** Una columna `encadenada` en `tareas_plantillas`, o un check en "usar plantilla", sería una opción que nadie pidió todavía. Si aparece un caso real de plantilla-checklist (items sin orden entre sí), se agrega ahí.

**Un solo INSERT multi-fila, no N inserts.** Depende de que el `BEFORE ROW` de `validar_paso_tarea` en la fila 2 vea la fila 1 de la **misma sentencia** — Postgres procesa las tuplas de a una y el trigger la encuentra. Verificado contra la base y fijado como caso 14 de `sql/tests/pasos_tarea.sql`, porque si esa semántica cambiara la plantilla tendría que insertar de a una fila (N round trips por PostgREST).

**No se puede armar la cadena en dos pasos** (insert plano + update de los `paso_anterior_id`): `paso_anterior_id` es inmutable en UPDATE, y aflojarlo a "NULL → valor" reabriría los ciclos (A sin previo, B con previo A, después A con previo B).

Copy: "Agregar tareas" pasó a "Agregar pasos", y tanto `UsarPlantillaPanel` como `PlantillaFormPanel` dicen que cada paso se habilita al completar el anterior — encadenar sin avisar convierte una plantilla conocida en algo que se comporta distinto.

## Módulo tareas — verificación con RLS real (`sql/tests/pasos_tarea.sql`, bloque 2)

Los 14 casos de triggers corrían como `postgres`, que bypasea RLS: probaban los triggers pero no que un usuario común pudiera usar la feature. El bloque 2 cambia a rol `authenticated` con TESTER (sin `tareas_gestionar_ajenas` ni `tareas_asignar`) y verifica lo que faltaba. 5/5.

**La premisa del diseño quedó probada, no supuesta:** TESTER, asignado **solo** al paso 2, ve el paso 1 y la cadena entera — `puede_ver_hilo` cascadea. De eso dependía la decisión de no escribir ninguna regla de visibilidad nueva para los pasos. Si el caso 01 dejara de pasar, "ver las tareas previas" necesitaría una función `SECURITY DEFINER` que devuelva stubs y habría que replantear `sql/017`.

**Los casos de rechazo miran `ROW_COUNT`, no solo la excepción.** Un UPDATE denegado por RLS afecta 0 filas y no tira error: sin ese chequeo, "RLS se lo comió en silencio" se leería como "el trigger funcionó". Mismo problema que ya había motivado alinear los UPDATE con los SELECT en `sql/013`.

Un usuario común puede crear el siguiente paso y asignárselo sin ninguna función extra — confirma que `tareas_lista` alcanza y que no hacía falta un submódulo nuevo para "crear siguiente paso".

**Pendiente — plantilla-checklist (items sin orden entre sí).** Desde `sql/017` toda plantilla genera una cadena: cada item espera al anterior (`agregarTareasDesdePlantilla`). Decidido no agregar flag ni checkbox hasta que exista una plantilla real cuyos items sean paralelos — ahí el camino barato es una columna `encadenada boolean` en `tareas_plantillas`, no una opción en "usar plantilla" (la plantilla sabe cómo es, quien la usa no debería tener que decidirlo cada vez).

---

## Módulo tareas — retoques de UI de Misión

Todo en `MisionView.tsx`. No se tocó `TareaCard` ni ninguna query: la vista sigue siendo recorte + navegación sobre lo que ya lee la Lista.

**Columna centrada `max-w-2xl`.** Una isla sola estirada a los 1280px del `<main>` no se lee como foco, se lee como una lista de un elemento. Misión es la única vista del módulo con un solo item en pantalla, así que el ancho lo pone ella y no el layout.

**Flechas ← → recorren la cola.** Se ignoran si hay un `dialog[open]` (el panel de detalle y los modales viven en el top layer, fuera de este árbol, y el slider de temperatura ya usa las flechas) o si el foco está en un `INPUT`/`SELECT`/`TEXTAREA`. El clamp del índice usa `total`, no el `posicion` del render: apretar de más al final dejaría el índice colgado lejos y habría que apretar N veces para volver.

**Barra de progreso = posición en la cola, no trabajo hecho.** No hay dato de "cuánto del total completé" sin leer `tareas_eventos`; la barra dice dónde estoy parado en la cola de hoy, que es lo mismo que el contador de texto y evita que el contador sea el único ancla visual.

**Línea de contexto (proyecto · hilo) arriba de la tarjeta.** Ni la isla ni su meta lo muestran — no es duplicación, es dato que en la Lista aporta el agrupamiento y acá no existe. El proyecto sale del hilo cuando la tarea tiene hilo (`CHECK (hilo_id IS NULL OR proyecto_id IS NULL)`: la tarea con hilo no guarda `proyecto_id`).

**La descripción se muestra en la vista, no solo en el panel.** Es la única excepción a "Misión renderiza `TareaCard` y nada más" y es deliberada: texto plano de solo lectura, sin estado ni acciones, así que no hay una segunda cara que sincronizar (el motivo real de aquella decisión). Una vista de a una que obliga a abrir un panel para leer qué hay que hacer no es una vista de a una.

**"Sigue: <título>" debajo de la tarjeta.** Una tarjeta sola no comunica que hay una cola detrás; el contador lo dice en número y esto en contenido.

**Las bloqueadas pasan de contador a lista desplegable (`Bloqueadas`, local al archivo).** Antes el estado vacío decía "N tareas esperan un paso previo" sin decir cuáles ni a qué esperan — el dato está en `PasoEnCadena.cadena[posicion - 2]`, que ya se calcula. El mismo bloque aparece con cola llena y con cola vacía; es el único caso del módulo donde saber qué te frena importa más que la tarea que tenés adelante.

**El estado vacío pasa a `.empty-state`.** Era el único del módulo con markup propio (texto centrado suelto). Ícono según el caso: `CircleCheck` verde si de verdad no queda nada, `Lock` ámbar si lo que queda está todo bloqueado — no son la misma noticia.
