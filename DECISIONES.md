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

**Excepción ya existente:** `PermisosModal.tsx` sigue modal — creado antes de esta regla. No migrar sin pedido explícito.

---

## `usuarios_select` RLS extendida para `tareas_asignar`

Módulo tareas necesita listar usuarios activos para el picker de "asignar a" (`getUsuariosParaAsignar()`). La policy original (`sql/001`) solo dejaba ver la fila propia o con `usuarios_ver` — alguien con `tareas_asignar` pero sin `usuarios_ver` recibía solo su propia fila, rompiendo el picker en silencio (sin error, lista vacía).

**Cambio (`sql/005_tareas_asignar_usuarios_rls.sql`):** se agregó `OR tiene_permiso('tareas_asignar')` a `usuarios_select`.

**Por qué:** `usuarios` es tabla de infraestructura cross-módulo (sin prefijo, ver `GUIDE_DB.md`) — extender su policy de lectura para un caso de uso legítimo de otro módulo es reutilizar estructura existente (regla "elegir la que reutilice estructuras existentes") en vez de crear una función RPC nueva solo para esto. Si aparecen más módulos que necesiten listar usuarios para asignar, evaluar generalizar recién ahí — no antes.

---

## GRANT faltante para `service_role` en `usuarios`/`usuario_submodulos` (bug pre-existente)

Al probar el módulo tareas en el navegador, guardar permisos en `PermisosModal` tiraba `permission denied for table usuario_submodulos` (42501). No es un bug de tareas — `sql/001` solo otorgó `GRANT ... TO authenticated`, nunca a `service_role`. El cliente admin de `modules/usuarios/actions.ts` (`asignarSubmodulos`, `desactivarUsuario`) usa `service_role` para saltear RLS, pero sin `GRANT` explícito el rol tampoco tiene el privilegio de tabla — mismo gotcha que "RLS no alcanza sin GRANT" de más arriba, pero para `service_role` en vez de `authenticated`. Confirmado pegándole directo a PostgREST con la key de servidor (403, mensaje exacto de Postgres con el `GRANT` faltante).

**Fix:** `sql/006_grant_service_role_usuarios.sql`, corrido.

**Por qué:** service_role en Supabase bypasea RLS pero sigue sujeto al modelo estándar de privilegios de Postgres — hay que otorgar GRANT explícito igual que a cualquier otro rol.

---

## Tareas: recurrencia eliminada, hilos con estado automático, plantillas, asociar/borrar

Pedido explícito de simplificar y ampliar el módulo después de la primera prueba:

- **Recurrencia de hilos eliminada** (columnas + enum + `generar_tareas_recurrentes()` + `pg_cron`, `sql/007`). No se usaba, no vale la complejidad todavía.
- **`tareas_hilos.estado`** (`abierto`/`cerrado`) automático vía trigger — nunca manual. Se cierra solo cuando todas sus tareas activas están `completada`, se reabre en cualquier otro caso. Trigger `SECURITY DEFINER` porque quien completa una tarea puede no tener permiso de `UPDATE` sobre `tareas_hilos` directamente (RLS exige ser creador o `tareas_todas`) — es un campo derivado del sistema, no una edición autorizada por el usuario.
- **Vista "completadas" sin permiso nuevo:** en vez de una vista/ruta gateada aparte, las tareas completadas (y los hilos enteramente completados) se agrupan en una sección colapsable al pie de "Mis Tareas"/"Todas las Tareas" — es un filtro de lo mismo, no una autorización distinta. Decisión mía, el usuario dejó abierto a sugerencia.
- **Plantillas** (`tareas_plantillas`/`tareas_plantillas_items`, `sql/008`): recurso compartido del equipo (no por creador) gateado por la vista `tareas_plantillas` — sin función separada de lectura/escritura porque no hay evidencia todavía de necesitar dos audiencias distintas (a diferencia de usuarios, que sí las tiene). Usarlas para poblar un hilo solo requiere `tareas_crear`, no acceso a la vista de gestión.
- **Asociar tarea suelta a hilo** y **borrar tarea** (soft-delete, ya existía `desactivarTarea()` sin botón) agregados a `TareaNotasCard`.

**Bug encontrado y corregido:** `CrearTareaPanel` con modo "Crear hilo nuevo" creaba el hilo ANTES de crear la tarea; si el segundo paso fallaba (ej: fecha inválida, ver bug de abajo) y el usuario reintentaba el submit, se creaba un hilo nuevo de vuelta — mismo título duplicado, uno huérfano sin tareas. Fix: el `hilo_id` ya creado se guarda en estado del componente (`hiloCreadoId`) y un reintento lo reusa en vez de crear otro. Un duplicado real quedó en la base de una prueba anterior — limpieza puntual en `sql/009_fix_hilo_duplicado.sql` (dato, no esquema).

---

## Tareas: hilos vacíos visibles, completadas lazy, desasociar

Segunda ronda de ajustes tras probar:

- **Hilos sin tareas se listan igual.** El agrupamiento de `TareasView` dejó de derivarse solo de las tareas cargadas (`tareas.reduce` por `hilo_id`) y ahora arranca desde `hilos` (todos los activos, vía `getHilosDisponibles()`) y les cuelga las tareas que tengan — un hilo recién creado sin tareas aparece con badge "0". Como efecto lateral, esto también resuelve el `cerrado` derivado: ya no se calcula client-side (`every tarea === completada`) sino que se lee directo de `tareas_hilos.estado` (la columna real, mantenida por el trigger) — más simple y más correcto que derivarlo de una lista de tareas que ahora es parcial (ver punto siguiente).
- **"Tareas completadas" carga perezosa.** Antes `getMisTareas()`/`getTodasLasTareas()` traían TODO (pendientes + completadas) en un solo request al abrir la página — con muchas tareas completadas históricas eso crece sin límite. Ahora el server solo manda `tareasAbiertas` (`estado <> 'completada'`) + un `count` liviano (`head: true`) de completadas. El listado completo de completadas solo se pide (`obtenerTareasCompletadas`, server action) la primera vez que el usuario expande esa sección, y se cachea en estado del cliente — no se vuelve a pedir al colapsar/expandir de nuevo.
- **Desasociar tarea de un hilo** (`desasociarTareaHilo`, `hilo_id = null`) — botón "Quitar del hilo" en `TareaNotasCard`, solo visible si la tarea tiene `hilo_id`. Sin confirmación (a diferencia de eliminar) — es reversible con "Asociar" de nuevo, no hace falta el mismo peso que un soft-delete.
- **`HiloBuscador` no lista nada hasta que se escribe.** Con pocos hilos mostrar todos de entrada no molestaba, pero no era el comportamiento pedido — ahora el resultado solo aparece con `busqueda.trim() !== ""`.

---

## `ConfirmModal` compartido, borrar hilo, crear tarea dentro del hilo

El botón "Eliminar tarea" usaba `confirm()` nativo — bloquea el renderer del browser (lo pisó la automatización de Chrome mid-prueba). Se creó `components/ui/ConfirmModal.tsx` y se reemplazó en los 3 lugares que usaban `confirm()`: `TareaNotasCard` (eliminar tarea), `PlantillasView` (desactivar plantilla) y `UsuariosView` (desactivar usuario) — no solo en tareas, para no dejar el resto del sistema con dos patrones de confirmación distintos.

**Borrar hilo** (`desactivarHilo`): solo permitido si el hilo no tiene tareas activas (`count` antes del soft-delete) — evita el caso ambiguo de qué hacer con las tareas de un hilo no vacío. El botón de la UI solo aparece cuando `tareas.length === 0`, coincide exactamente con el guard del server. Sin esto, el hilo huérfano de las pruebas (`sql/009`) habría quedado sin forma de limpiarse desde la UI.

**Crear tarea directo en el hilo**: `CrearTareaPanel` ahora acepta `hiloFijo?: {id, titulo}` — si viene seteado, oculta toda la sección de elegir/crear hilo (ya está fijo) y lo manda directo en el insert. Botón "Nueva tarea" nuevo en `HiloHistorialPanel`, gateado por `tareas_crear` (mismo permiso que crear cualquier tarea, no uno nuevo).

---

## Tareas: recurrencia reintroducida, plantilla en modal, hilo editable, completadas colapsables por hilo

Revierte la entrada "Tareas: recurrencia eliminada..." de más arriba — pedido explícito del usuario. Config por día/mes/año en vez de diaria/semanal/mensual fija (`sql/010_recurrencia_hilos.sql`, ver `db_schema.md`).

- **Recurrencia vive en `tareas_hilos`, no en `tareas`.** Config aplica al hilo entero (dispara todas sus tareas activas), no por tarea individual — coincide con el pedido ("recurrencia... configurarían la recurrencia de las tareas dentro de los hilos").
- **`generar_tareas_recurrentes()` resetea, no clona.** Al llegar `recurrencia_proxima`, las tareas activas del hilo vuelven a `pendiente` y se agenda la próxima fecha — reusa el mismo hilo en vez de crear uno nuevo cada ciclo (mismo criterio que "hilos vacíos visibles": un hilo es una entidad persistente, no una plantilla que clona instancias). El trigger `sync_estado_hilo` (ya existente) reabre el hilo solo, sin lógica nueva.
- **`CrearHiloPanel` ahora sirve para crear y editar** (`hilo?: TareaHilo | null`, mismo patrón que `PlantillaPanel`) — la config de recurrencia es propiedad del hilo, se edita una vez, no es una acción por-apertura del panel de historial. Botón de lápiz nuevo en `HiloHistorialPanel`.
- **"Agregar desde plantilla" pasó de caja inline siempre visible a modal** (botón "Desde plantilla" junto a "Nueva tarea") — la caja ocupaba espacio permanente aunque no se usara y no se distinguía bien de crear una tarea suelta. Es pick+confirm corto, no un formulario largo, así que modal encaja con la regla ya escrita (panel para crear/editar, modal para interrupción corta) mejor que un tercer `RightPanel`.
- **Overflow de tareas dentro de un hilo:** mismo patrón ya usado en `TareasView` a nivel global — completadas colapsadas detrás de un toggle, pendientes siempre visibles. Acá no hace falta carga perezosa aparte (ya viene todo en un solo `getHistorialHilo` por ser scope de un hilo, no la lista global) — el split es puramente client-side.

**database.types.ts actualizado a mano** (columnas `recurrencia_*` + enum `recurrencia_intervalo` + función `generar_tareas_recurrentes`) porque `sql/010` todavía no corrió contra Supabase — regenerar con el CLI una vez corrida la migración, para no dejar el archivo desincronizado del schema real.

---

## Tareas: recurrencia también en tareas sueltas (no solo hilos)

`sql/010` solo la dejó en `tareas_hilos` — al probar, tareas sin hilo no tenían forma de repetirse. `sql/011_recurrencia_tareas.sql` agrega las mismas 4 columnas a `tareas`.

- **Dueño de la recurrencia es exclusivo: hilo o tarea suelta, nunca los dos.** Si una tarea con recurrencia propia se asocia a un hilo (`asociarTareaHilo`), se apaga `recurrencia_activa` en el mismo update — evita que quede una config fantasma que nunca se procesa (el cron de tareas sueltas filtra `hilo_id IS NULL`) y evita tener que decidir cuál de las dos manda si ambas quedaran activas.
- **`avanzar_recurrencia()` extraída como función compartida** entre el loop de hilos y el de tareas sueltas dentro de `generar_tareas_recurrentes()` — mismo cálculo de próxima fecha (con catch-up), un solo lugar si cambia. Un solo `pg_cron.schedule(...)` (el de `sql/010`) cubre ambos loops.
- **`RecurrenciaFields.tsx`** (componente controlado, `value`/`onChange`, sin RHF) compartido por `CrearHiloPanel`, `CrearTareaPanel` (solo visible si la tarea va a quedar suelta — sin hilo elegido/fijo) y `TareaDetallePanel` (edición, solo si `!tarea.hilo_id`) — evita repetir el mismo bloque de checkbox+cada+intervalo+fecha en 3 componentes con 3 estados de formulario distintos (uno usa RHF, dos no).

---

## Tareas: posponer (snooze), paginación, semáforos de vencimiento/antigüedad, recurrencia manual vs automática

Ronda grande de UX tras probar recurrencia en browser. Cinco cambios independientes:

- **Posponer sin cron** (`sql/012_posponer.sql`, columna `posponer_hasta date` en `tareas` y `tareas_hilos`): las queries de "abiertas" excluyen `posponer_hasta > hoy`, las de "pospuestas" exigen lo contrario — el ítem "despierta" solo porque deja de cumplir el filtro, sin job que lo reactive. Mismo espíritu que la recurrencia sin cron para reabrir hilos.
- **Posponer es independiente por entidad.** Un hilo pospuesto oculta el hilo entero (sus tareas se recalculan del mismo array ya cargado, sin query nueva — mismo patrón que la partición `abierto`/`cerrado` que ya existía). Una tarea pospuesta se oculta individualmente, tenga o no `hilo_id` — a diferencia de la recurrencia (que sí es exclusiva hilo-o-tarea-suelta), acá no hay conflicto porque posponer no dispara ninguna lógica automática, es puro filtro de visibilidad.
- **`PosponerModal`** (`components/ui/`) genérico: accesos rápidos 1/3/7 días + fecha custom, reusado por tarea y por hilo — mismo criterio que `RecurrenciaFields`, un componente controlado en vez de duplicar el formulario.
- **Paginación** (`TAREAS_PAGE_SIZE = 20`, `components/ui/Pagination.tsx`): aplica a las tareas de los 3 buckets (abiertas/completadas/pospuestas) vía `.range()` + `count: "exact"`. **Los hilos como agrupador NO se paginan** — solo hay unos pocos hilos activos típicamente, lo que crece sin límite son las tareas. Efecto secundario aceptado: si un hilo tiene tareas en más de una página, el contador visible en su card refleja solo las tareas de la página cargada, no el total real del hilo.
- **Semáforo de vencimiento** (`formatVencimiento` en `estado.ts`): color por % de plazo consumido (`creado_at` → `fecha_vencimiento`), no por fecha absoluta — verde >66.66% restante, amarillo >33.33%, rojo por debajo o vencido. Texto en días (no horas — pedido explícito, aunque `fecha_vencimiento` es `date` sin hora, así que horas no habrían sido precisas de todos modos).
- **Semáforo de antigüedad de hilo** (`formatAntiguedad`): días desde `created_at`, verde ≤7d, amarillo ≤21d, rojo más — sin relación con vencimiento de tareas, es un indicador de hilo "viejo"/desatendido.
- **Recurrencia: fecha manual vs automática ahora explícito.** `RecurrenciaFields` suma un checkbox "Elegir fecha de inicio manualmente" — off (default) recalcula `recurrencia_proxima` cada vez que cambian cada/intervalo y la muestra como texto fijo (no editable); on expone el date input. Este modo es puramente de UI (estado local del componente, no se persiste en DB) — al reabrir el formulario de edición siempre arranca en automático, aunque la fecha guardada haya sido elegida a mano la vez anterior. Se aceptó no agregar columna nueva solo para recordar el modo — es un detalle de formulario, no de datos.

---

## Tareas: recurrencia "una sola vez", vencimiento default a 1 día

- **`recurrencia_una_vez`** (`sql/013_recurrencia_una_vez.sql`, columna en `tareas` y `tareas_hilos`): al activarla en `RecurrenciaFields`, se esconden los controles de cada/intervalo (no aplican, no hay ciclo siguiente) y solo se pide una fecha. `generar_tareas_recurrentes()` chequea el flag: si es `true`, al disparar apaga `recurrencia_activa` en vez de llamar `avanzar_recurrencia()` — no hace falta un cron ni lógica nueva aparte, reusa el mismo paso.
- **Vencimiento de tarea nueva precargado en "hoy + 1 día"** — default de formulario (`defaultValues` de RHF en `CrearTareaPanel`), no de columna: `fecha_vencimiento` sigue nullable en DB, cualquier tarea creada por otro camino (plantilla, etc.) no lo tiene. Se eligió no forzarlo a nivel columna porque no toda tarea nace con vencimiento (ej: las agregadas desde plantilla no pasan por este formulario).
