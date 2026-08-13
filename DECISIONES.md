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

---

## Tareas: auditoría de UI — agrupado que no pierde tareas, "hoy" en zona AR, `Modal` compartido

Ronda de fixes sobre bugs encontrados auditando la UI del módulo. Ninguno toca DB.

- **`agruparPorHilo()` reemplaza los 3 bloques de agrupado de `TareasView`.** Antes cada sección filtraba los hilos por su propio estado (`abierto` / `cerrado` / pospuesto) y las tareas por el suyo: cuando no coincidían, la tarea quedaba en el `Map` por `hilo_id` y no se renderizaba en ningún lado (caso real: completar una tarea de un hilo abierto la hacía desaparecer, porque "Tareas completadas" solo listaba hilos `cerrado`). Ahora hay un solo helper con un predicado `incluirHilo(hilo, tieneTareas)` por sección, y **toda tarea cuyo hilo no entre en la sección cae en `sueltas`** en vez de perderse — la regla es que ninguna tarea del bucket puede quedar sin renderizar.
- **Hilos vacíos siguen visibles** (regla ya establecida más arriba): el predicado de "abiertas" es `h.estado === 'abierto' || tieneTareas`, no `tieneTareas` — un hilo recién creado sin tareas aparece con badge "0". Por lo mismo el empty-state global ahora exige además `hilos.length === 0`: antes, crear un hilo sin tareas mostraba "Sin tareas todavía" y escondía el hilo recién creado.
- **Hilo pospuesto: sección propia y contador que lo incluye.** Sus tareas no están pospuestas a nivel tarea, así que salían del bucket "abiertas" pero la sección "Pospuestas" solo se renderizaba si había *tareas* pospuestas (`totalPospuestas > 0`) — un hilo pospuesto sin tareas pospuestas desaparecía entero de la pantalla. El contador ahora suma tareas pospuestas + hilos pospuestos, y los grupos se muestran sin esperar a que cargue el bucket (no dependen de él).
- **`lib/utils.ts`: "hoy" es el día en `America/Argentina/Buenos_Aires`, no el del reloj.** Había cuatro implementaciones distintas: `toISOString().slice(0,10)` (UTC) en `TareasView` y en `queries.ts`, y aritmética en hora local del navegador en `estado.ts` / `PosponerModal` / `RecurrenciaFields`. En AR (UTC-3) después de las 21:00 el "hoy" UTC ya es mañana → lo pospuesto reaparecía un día antes y cliente y servidor discrepaban. Ahora una sola fuente (`diaISO`/`hoyISO` vía `toLocaleDateString("en-CA", { timeZone })`), compartida entre server y client. Sin librería de fechas: `Intl` ya resuelve el único caso que hay.
- **Buckets perezosos se refrescan tras una mutación.** `completadas`/`pospuestas` se cargaban una vez y `cargado` no se reseteaba nunca: completar otra tarea con la sección abierta dejaba datos viejos. El hook ahora toma un `syncKey` (las tareas que manda el servidor) — cuando `revalidatePath` trae datos frescos, el bucket con props se resincroniza en render y el perezoso vuelve a pedir su página. `cargarPagina` además atrapa el error (antes una promesa sin `catch` dejaba el spinner colgado para siempre).
- **`components/ui/Modal.tsx`**: shell único (overlay + Escape + click en backdrop + `role="dialog"`) para `ConfirmModal`, `PosponerModal` y "Agregar desde plantilla", que repetían el markup del overlay y ninguno cerraba con Escape. El listener del modal va en **fase de captura con `stopPropagation`** y el de `RightPanel` en burbujeo: con un modal abierto sobre un panel, Escape cierra solo el modal.
- **Borrar hilo movido adentro del bloque `puedeCrear`** en `HiloHistorialPanel` — estaba afuera, así que un usuario sin `tareas_crear` veía el botón (RLS lo frenaba en server: `tareas_hilos_update` exige `creado_por` o `tareas_todas`, pero la UI ofrecía una acción que no le corresponde).
- **`min` en los date inputs** (posponer: desde mañana; vencimiento y próxima repetición: desde hoy) — elegir una fecha pasada era aceptado y no posponía nada.
- **No se agregaron chequeos de permiso a las server actions de lectura/mutación**: `sql/004_tareas.sql` ya las cubre por RLS a nivel fila (`tareas_select`/`tareas_update` filtran por `asignado_a` / `creado_por` / `tareas_todas`), así que `obtenerTareas("todas", ...)` desde un cliente manipulado devuelve exactamente lo mismo que `"mis"`. Duplicar el chequeo en la action no agrega barrera, solo un segundo lugar donde desincronizarse.

---

## Tareas: filtros y búsqueda

- **Filtro en servidor, no en la página cargada.** La paginación ya es server-side (`.range()`), así que filtrar el array del cliente habría buscado solo dentro de las 20 tareas visibles. `getTareasFiltradas` toma `filtros?: FiltrosTareas` y los aplica a los 3 buckets por igual; `obtenerTareas` los valida con `filtrosTareasSchema.safeParse` antes de pasarlos (filtro inválido = sin filtro, no error).
- **Búsqueda por título y descripción** (`ilike` en un `or`), no full-text: no hay índice `tsvector` ni volumen que lo justifique todavía. **El texto se sanitiza** (`textoBusqueda`) sacando `,()"\%*` — PostgREST parsea `or=(...)` con comas y paréntesis, así que un título con coma rompía la query. Se descartan en vez de escaparse: son ruido para una búsqueda, no datos.
- **Solo texto + asignado.** No se agregó filtro por estado: el bucket "abiertas" ya es `pendiente` + `en_progreso` y "completadas" es un solo estado por definición — el selector habría estado muerto en dos de las tres secciones. El de asignado solo aparece en la vista "todas" (en "mis tareas" todas son propias).
- **Con filtros activos, los hilos vacíos se ocultan** — es la única excepción a la regla de "hilos sin tareas se listan igual": si buscás algo, ver todos los hilos vacíos ahoga el resultado. Un hilo entra si tiene tareas que pasaron el filtro **o si su propio título coincide con la búsqueda**.
- **Los counts de las secciones colapsadas desaparecen mientras hay filtro.** `getTareasCount` no conoce los filtros (es un `head: true` liviano que corre en el server component) y volver a pedirlo filtrado por cada tecla sería un request extra por bucket. Con filtro activo la sección muestra el label sin número hasta que se la expande; ahí el número sale del bucket ya filtrado.
- **Debounce de 300 ms** en el input, y el commit de filtros se guarda en un estado aparte (`filtros`) del texto tipeado (`texto`) — el refetch se dispara por una key string (`texto|asignado`), no por identidad de objeto, así no se dispara solo por re-render.

---

## Tareas: vista Auditoría — `tareas_eventos`

Pedido: ver por día las tareas realizadas, filtrando por usuario. **El dato no existía ni era derivable**: `tareas.estado` es el valor actual, `generar_tareas_recurrentes()` lo resetea a `pendiente` cada ciclo (una tarea de hilo recurrente completada seis meses seguidos no dejaba rastro de ninguna vez) y `updated_at` lo mueve cualquier update. Tampoco había registro de *quién* completó: `asignado_a` es a quién le tocaba, no quién la cerró.

- **Tabla de eventos, no columna `completada_at`.** Una columna solo guarda la última vez y se pierde en cada reset de recurrencia — para una auditoría eso es directamente incorrecto. `tareas_eventos` (`sql/014`) es append-only y sobrevive los resets.
- **Se loguea todo cambio de estado, no solo `completada`** (decisión del usuario). Mismo trigger y mismo tamaño de código, y deja contestar "¿quién la reabrió?" sin migrar nada después. La vista filtra `estado_nuevo = 'completada'`.
- **Sin backfill** (decisión del usuario): la auditoría arranca el día que corre el SQL. Sembrar desde `updated_at` habría metido fechas aproximadas y autor desconocido en la única tabla del sistema que no debería tener datos inventados.
- **Excepción a "nunca DELETE, siempre `activo`":** `tareas_eventos` no lleva `activo`. Un flag para ocultar filas de auditoría es exactamente lo que una auditoría no debe tener. Queda registrada acá como manda la regla, no decidida ad-hoc.
- **Append-only por permisos, no por convención:** `GRANT SELECT` y nada más; el INSERT entra por el trigger `SECURITY DEFINER`. Sin GRANT de INSERT/UPDATE/DELETE, un cliente con el token del usuario no puede forjar ni borrar eventos aunque quiera.
- **`usuario_id` NULL = sistema.** El cron de recurrencia corre sin `auth.uid()`; en vez de inventarle un usuario, la UI muestra "Sistema (recurrencia)" — que es información real y útil en una auditoría.
- **Nueva vista = nuevo submódulo `tareas_auditoria`** (`tipo = 'vista'`, orden 4), sin rol nuevo ni permiso por módulo. La vista muestra actividad de todos los usuarios, así que el permiso es la barrera: está en la policy RLS de la tabla, en la action (`obtenerAuditoria`) y en la page.
- **Rango de fechas: el filtro convierte el día AR a instante con offset fijo `-03:00`.** PostgREST no puede hacer `AT TIME ZONE` en un filtro y Argentina no usa horario de verano desde 2009; una función RPC solo para esto sería más maquinaria por el mismo resultado. Si el país vuelve a mover el reloj, `inicioDelDiaAR` en `queries.ts` es el único lugar a tocar.
- **Agrupado por día en el mapper, no en SQL.** El `GROUP BY` habría necesitado una RPC o una vista; con página de 20 eventos agrupar en JS es una pasada sobre un array ya ordenado por `created_at DESC`. Efecto aceptado: un día con más de 20 eventos se parte entre páginas y su encabezado se repite.

---

## Tareas: auditoría visual en browser — semáforos de contorno, un solo formato de fecha

Ronda de fixes sobre lo encontrado recorriendo el módulo en el navegador. Los tres arreglos de `globals.css` valen para toda la app, no solo tareas.

- **Semáforos con badge de contorno, estados con badge sólido.** `badge-success` significaba cuatro cosas a la vez (tarea "Completada", hilo "Cerrado", plazo sano, hilo nuevo) y dos de ellas aparecían en la misma fila. Las escalas de semáforo (`formatVencimiento`, `formatAntiguedad`) pasaron a `badge-outline-*` — mismo color semántico, forma distinta. Se eligió contorno vs. sólido antes que inventar una paleta nueva: el color ya comunica bien, lo que faltaba era separar "estado" de "medición".
- **`formatVencimiento` recibe `estado` y devuelve `null` si la tarea está completada.** Se mostraba "Vence en 1 día" al lado de "Completada". El fix va en la función, no en los dos callers (`TareasView`, `TareaNotasCard`) — ambos ya le pasaban la tarea entera, así que la firma cambió sin tocar ningún call site.
- **`.input-error:focus` explícito.** `.input:focus` (especificidad clase+pseudoclase) le ganaba a `.input-error`: el campo inválido enfocado mostraba borde azul de foco en vez de rojo de error, en todo formulario del sistema.
- **`recurrencia_proxima` en el pasado se rechaza en el schema Zod**, no solo con el `min` de los date inputs (que es UI y no barrera). Había un hilo guardado con "próxima 15/4/1991" — una recurrencia que el cron nunca dispara. Efecto aceptado: editar la recurrencia de un registro viejo con fecha pasada ahora falla hasta corregir la fecha; es la señal correcta.
- **`formatFecha` con `2-digit`**, para que coincida con lo que muestra un `<input type="date">` en es-AR (`13/08/2026`, no `13/8/2026`) — había dos formatos en la misma pantalla de Auditoría. `formatHora` subió de `AuditoriaView` a `lib/utils` y se sumó `formatFechaHora`, para no tener una tercera implementación de hora en AR.
- **Fecha y hora de creación visible en el encabezado del hilo** (lista y panel). Dos hilos con el mismo título y el mismo badge "Creado hoy" eran indistinguibles; nada en el dato mostrado los separaba.
- **`TareaNotasCard` acepta `ocultarTitulo`.** El panel de detalle repetía el título de la tarea (encabezado del `RightPanel` + card). No se sacó el `<p>` sin condición porque en `HiloHistorialPanel` la misma card se usa para varias tareas y ahí el título es lo que las identifica.
- **Toolbar del panel de hilo con `flex-wrap`.** Seis controles en una fila sin wrap dentro de un panel `max-w-md` recortaban los íconos y generaban scroll horizontal en el body de la página entera.
- **Acción destructiva separada con `border-l`** en `TareaNotasCard` y `HiloHistorialPanel` — el tacho estaba a 4px del select de estado, que es el control de uso frecuente.
- **`RecurrenciaFields`: el checkbox "Repetir automáticamente" dejó de ser `t-label`.** `t-label` es el estilo de encabezado de sección; usado en un control lo hacía competir visualmente con el título de la sección que lo contiene. Los tres paneles que usan el componente ahora encabezan la sección con `t-label` "Recurrencia".

**No se unificó el footer del panel de detalle con el de creación.** `CrearTareaPanel`/`CrearHiloPanel` tienen un footer fijo Cancelar/Guardar porque hay un único submit; el panel de detalle tiene dos guardados independientes (recurrencia, asociar a hilo) y un footer único mentiría sobre qué guarda. Se alineó lo demás (secciones etiquetadas, botones primarios) y se dejó el footer afuera a propósito.

---

## Tareas: descripción de hilo, un solo camino para crear hilos, vencimientos rápidos, orden de completadas

- **`tareas_hilos.descripcion`** (`sql/015_hilos_descripcion.sql`, nullable): se muestra en el body de `HiloHistorialPanel`, no en la card de la lista — un párrafo por hilo en la pantalla principal ahogaría las tareas, que son lo que se lee ahí. **No entra en la búsqueda**: `getTareasFiltradas` sigue matcheando `titulo` de hilo y `titulo`/`descripcion` de tarea. Si aparece el caso de buscar por descripción de hilo, se agrega ahí, no se duplica el filtro.

- **El hilo nace en un solo lugar: `CrearHiloPanel`.** Se eliminó la opción "Crear hilo nuevo" del select de `CrearTareaPanel` (junto con su estado `hiloNuevoTitulo`/`hiloCreadoId` y el fix de duplicados de la entrada de más arriba). Motivo: ese camino creaba hilos sin descripción ni recurrencia — las dos propiedades que solo se configuran en el panel del hilo. En su lugar, `CrearHiloPanel` acepta `onCreado?` y ofrece "Crear y agregar tarea", que cierra el panel del hilo y abre `CrearTareaPanel` con `hiloFijo` ya seteado. Nunca dos `RightPanel` abiertos a la vez. Efecto aceptado: si se cancela la tarea, queda un hilo vacío — ya es un estado válido y visible (regla "hilos sin tareas se listan igual") y se puede borrar con `desactivarHilo`.

- **Accesos rápidos de vencimiento 1/3/7 días** junto al date input de `CrearTareaPanel` (mismos saltos que `PosponerModal`). El default sigue siendo hoy+1. De paso murió `manana()` local, que duplicaba `sumarDias` de `lib/utils`.

- **Completadas ordenadas por `updated_at DESC` (último cerrado arriba)**, tanto en el bucket global (`getTareasFiltradas`) como en la sección colapsable de `HiloHistorialPanel`. El instante real del cierre solo existe en `tareas_eventos`, cuya RLS exige `tareas_auditoria` — usarla acá dejaría el orden roto para los usuarios sin ese permiso. `updated_at` es la aproximación legible por cualquiera; la mueve cualquier edición posterior (posponer, asociar, editar), así que una tarea completada hace un mes y editada hoy sube. Se descarta una columna `completada_at` por el mismo motivo ya registrado en la entrada de auditoría: `generar_tareas_recurrentes()` la pisaría en cada ciclo.

- **`overflow-hidden` en los contenedores `rounded-lg` de `ListaTareas` y `GrupoHilo`.** El fondo de hover de las filas (`hover:bg-bg-subtle`) es rectangular y pisaba las esquinas redondeadas del contenedor: al pasar el mouse por la primera o la última fila aparecían esquinas cuadradas.

- **Hilo y tarea diferenciados visualmente**: ícono `Layers` en color de marca en el encabezado del hilo, y las tareas de un hilo se renderizan con sangría y riel izquierdo (`TareaRow` con `anidada`). Antes hilo y tarea eran dos filas del mismo alto y el mismo peso tipográfico dentro de la misma card.

---

## Tareas: reasignar, fechas vacías, íconos de estado

- **Fecha vacía → `null` en el schema, no en cada action.** Un `<input type="date">` vacío manda `""`, y Postgres devolvía `invalid input syntax for type date: ""` al crear tarea suelta sin recurrencia (`recurrencia_proxima: ""` viajaba tal cual) y al dejar el vencimiento vacío. Se normaliza en un solo lugar: `fechaOpcional` en `types.ts` (`z.string().nullish().transform(v => v || null)`), usado por `fecha_vencimiento` y `recurrencia_proxima`. Es `nullish` y no `optional` porque el cliente ya manda el valor transformado (`null`) al server action, que vuelve a hacer `safeParse`. Efecto en tipos: `CrearTareaValues` (`z.output`) se suma a `CrearTareaForm` (`z.input`); `useForm` de `CrearTareaPanel` usa el tercer genérico (`TTransformedValues`) y `crearTarea` recibe el tipo de salida.

- **Reasignar tarea desde `TareaNotasCard`**, no una acción nueva de UI: el nombre del asignado se vuelve un `select` cuando el usuario tiene `tareas_asignar`, y texto plano si no. Server: `reasignarTarea` verifica `puedeAsignarTarea()` antes de parsear. No se creó submódulo nuevo — reasignar es la misma autorización que asignar al crear.

- **Sin permiso `tareas_asignar`, "Agregar desde plantilla" asigna a uno mismo** (comportamiento ya existente, verificado): el modal oculta el picker y manda `usuarioActualId`, y el server rechaza cualquier `asignado_a` distinto del propio. No es un caso de error.

- **Ícono de estado por tarea** (`ESTADO_ICON`/`ESTADO_ICON_COLOR` en `estado.ts`): `Circle` gris pendiente, `CircleDot` info en progreso, `CircleCheck` success completada. Se lee en `TareaRow` y en el título de `TareaNotasCard`. El badge de estado sigue ahí — el ícono da el estado de un vistazo en listas largas, el badge lo nombra.
