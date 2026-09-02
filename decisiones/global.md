# Decisiones — transversales

Lo que no es de un módulo: design system, componentes de `components/ui/`, tokens de
`globals.css`, permisos e infraestructura.

Las reglas para escribir código nuevo viven en `.claude/guides/`. Acá está **por qué**
se decidió cada una.

---

## Design system

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

## Componentes compartidos (`components/ui/`)

### `RightPanel` y `Modal` viven en el top layer

**`RightPanel` pasa a `<dialog>` + `showModal()`, sin `fixed inset-0 z-50` propio.** El panel vive en el *top layer* del browser: ningún ancestro puede taparlo ni recortarlo (stacking context, `overflow`, `transform`), los paneles anidados (`TareaRow` dentro de `HiloDetailPanel` dentro de `ProyectoDetailPanel`) se apilan por orden de apertura sin manejar z-index, y `Escape` cierra solo el de arriba. El fondo es `backdrop:bg-[rgba(7,11,20,.55)]` (pseudo-elemento nativo) en vez de un div de overlay; el click afuera se detecta con `e.target === e.currentTarget` porque el backdrop no es un nodo propio. Los modales de confirmación (`CompletarModal`, `CerrarHiloModal`, etc.) siguen con `fixed`/z-50 — no se tocaron.

**Los modales de confirmación también pasan a `<dialog>`: `components/ui/Modal.tsx` nuevo.** Verificado en browser: un modal lanzado desde `TareaRow` dentro de `HiloDetailPanel` (ej. "Completar tarea") era un `div fixed z-50` **dentro** del subtree del panel, que ya estaba en el top layer — el overlay del modal no oscurecía el panel y el modal quedaba centrado en el viewport, tapado por el panel según el ancho de ventana. `Modal` extrae el shell que `CompletarModal`/`CerrarHiloModal`/`DeshacerConversionModal`/`CrearUsuarioModal` duplicaban (overlay + card + header con X) y lo abre con `showModal()`, así el modal se promueve al top layer después del panel y queda arriba. `PermisosModal` sigue como estaba (excepción ya documentada).

**`hayCambios` en `RightPanel` y `Modal`: cerrar por backdrop, Escape o X pregunta antes de descartar.** Un click al costado borraba un formulario a medio llenar sin aviso. Se conecta con `formState.isDirty` de RHF en los siete paneles con form, y con `nota.trim().length > 0` en `CompletarModal`. El submit exitoso llama `onClose` directo, así que no pasa por la guardia. `DescartarCambios` vive dentro de `Modal.tsx` — es `ConfirmModal` con copy fijo, y en archivo propio armaba un ciclo de imports con quien lo usa.

### `ConfirmModal`

**`ConfirmModal` acepta `cancelLabel`.** Con la acción confirmada llamándose "Cancelar la tarea", un botón de salida que dice "Cancelar" no se puede leer. Acá dice "Volver"; el default sigue siendo "Cancelar" para el resto.

### `OverflowMenu`

**`OverflowMenu` posiciona el dropdown con `fixed` + `getBoundingClientRect`, no `absolute`.** Dentro de un panel con `overflow-y-auto` un menú `absolute` lo recorta el contenedor (se veía cortado en `HiloDetailPanel`). `fixed` no lo recorta ningún ancestro con overflow; la posición se calcula al abrir y se decide arriba/abajo según el espacio libre (alto estimado por cantidad de ítems — ver comentario `ponytail:`). Contrapartida: al scrollear el contenedor el menú se despegaría del botón, así que un listener de `scroll` en captura lo cierra.

### `SearchInput`

**`SearchInput` tenía placeholder como único nombre.** `aria-label={placeholder}` — el placeholder ya está escrito para el usuario ("Buscar tarea o hilo…") y desaparece al tipear, que es justo cuando el lector de pantalla lo necesita.

---

## Tokens y clases de `globals.css`

**`.row` en `globals.css`.** `p-[13px] px-5` — el token de fila del design system (§8) — estaba escrito a mano en 19 lugares, entre tareas, comercial y usuarios. Se reemplazaron todos, no solo los del módulo: es el mismo valor mágico.

**Campos obligatorios marcados antes de guardar, con `.t-label-req` en `globals.css`.** Asterisco por `::after` sobre la clase de label que ya existía, en vez de repetir un `<span>` en diez formularios. El asterisco es decorativo: la semántica la lleva `aria-required` en el control. No se usa el atributo `required` nativo — dispararía la validación del browser antes que Zod y competiría con los mensajes propios.

**`.icon-btn` existía en el media query de 44px pero nunca se había definido.** Las X de `RightPanel` y `Modal` eran botones del tamaño del ícono (~20px) — el gesto principal de cierre en touch. Ahora la clase existe (34×34, r-md, spec §8) y crece a 44×44 en mobile.

**`.tap-target` para lo tocable que no es un botón del sistema.** El media query de 44px solo nombraba `.btn`/`.input`/`.nav-item`/`.icon-btn`, y el módulo está lleno de elementos tocables que no usan ninguna: la fila entera de `PasoAjeno`, "Ver los N pasos" de `HiloCard`, el segmented de relación de la Lista, el nombre de plantilla (único acceso a editarla), los checkboxes de asignados y miembros, el "Se repite" de la tarea y los ítems de `OverflowMenu`. Nueve usos con una clase, en vez de `min-h-11` suelto en cada uno: así el alto extra existe solo abajo de 768px y no engorda las filas en desktop, que es lo que pide el guide.

**`.input:focus` pisaba `.input-error` (global).** `.input:focus` tiene especificidad `(0,2,0)` y `.input-error` `(0,1,0)`: el orden en el archivo no alcanzaba. El campo que RHF enfoca al fallar la validación perdía el borde rojo y se pintaba azul de marca — con `aria-invalid="true"` puesto y el texto de error abajo. Pegaba en todos los forms, no solo en login. El selector pasa a `.input-error, .input-error:focus`, que empata especificidad con `.input:focus` y gana por orden.

**`success-bg/text`, `warning-*`, `error-*` e `info-*` pasan a ser dark-aware (global).** Eran hex fijos en `@theme`, así que en dark el bloque de error del login era un parche rosa `#FEE2E2` sobre el card oscuro, y lo mismo todos los `.badge-*`. Se promueven a custom properties en `:root`/`[data-theme="dark"]` y `@theme inline` las referencia — mismo patrón y mismo motivo que `--brand-50`/`--brand-700` cuando el ítem de nav activo quedaba celeste claro en dark.

Se migran las cuatro familias, no solo `error`: dejar `success`, `warning` e `info` en hex fijo partía el sistema en dos mitades con reglas distintas, que es peor que el cambio visual de los badges en dark. Los pares dark son bg-950 / text-200 de cada hue.

**`text-error` y `text-warning` son hex fijos sobre fondo tematizado: van a `text-error-text` / `text-warning-text`.** Los tokens `--error-text` y `--warning-text` ya existían tematizados (los usaban `badge-error` y `badge-warning`) y nadie más los tocaba. Medido sobre `--bg-surface` en los dos temas: `text-error` (#DC2626) daba 3.8:1 en oscuro y `text-warning` (#D97706) 3.2:1 en **claro** — los dos abajo de AA, y justo en el vencimiento vencido y en "Pospuesta hasta". Con los tokens: error 14.0:1 claro / 11.7:1 oscuro, warning 11.0:1 claro / 14.4:1 oscuro. Los `text-success` / `text-warning` que quedan son íconos, no texto: el umbral ahí es 3:1 y lo pasan. **Queda pendiente `.input-error-text` en `globals.css`** — mismo defecto, pero es app-wide y no entraba en una auditoría del módulo tareas.

---

## Auditorías de UI app-wide

Tres tandas sobre toda la app. Los hallazgos son globales aunque varios ejemplos salgan
del módulo tareas.

### P0 — errores, confirmaciones, foco, boundaries

- **Errores de Supabase nunca crudos.** `mensajeError(error)` en `lib/utils.ts`: mapa por código (`23505`, `23503`, `23514`, `42501`, `email_exists`, `weak_password`) y genérico para el resto. Todas las actions de `tareas` y `usuarios` lo usan. Los mensajes de Zod sí se muestran tal cual — ya están escritos para el usuario.
- **`ConfirmModal` vive en `components/ui/Modal.tsx`**, no en archivo propio: es una envoltura de 30 líneas sobre `Modal` y se usa en 5 lugares. Reemplaza los `confirm()` nativos (que no respetan el design system ni el `<dialog>` en top layer).
- **Foco visible: una sola regla global** en `@layer base` (`a, button, [tabindex]` → `outline-2 outline-offset-2 outline-brand-500`) en vez de un `:focus-visible` por clase. `select` queda afuera a propósito: usa `.input`, que ya tiene su propio `:focus`.
- **`loading.tsx` + `error.tsx` en `app/(erp-app)/`**, no por ruta: las 5 páginas del grupo son server components esperando Supabase y el feedback es el mismo. Bajar el boundary a cada ruta cuando alguna necesite un skeleton propio.
- **Hamburger y cerrar de `MobileNav` a 44×44**: la regla de 44px de `globals.css` solo aplica a `.btn`/`.input`/`.nav-item`/`.icon-btn` y esos dos botones no usan ninguna.

### P1 — responsive y legibilidad

- **Sidebar desde `md` (768px), no `lg`.** Un iPad portrait (~820px) recibía drawer mobile con densidad desktop. De las dos opciones (sidebar en `md` vs layout compacto hasta 1024px) se eligió bajar el breakpoint: 220px de sidebar dejan 548px de contenido a 768px, y el padding sigue en `p-4` hasta `lg`, así que la densidad compacta se mantiene en la franja tablet. Toca `Sidebar.tsx`, `MobileNav.tsx` y `app/(erp-app)/layout.tsx` — los tres tienen que usar el mismo breakpoint o el drawer y el aside conviven.
- **`max-w-[1280px] mx-auto` en el `<main>`.** A 2560px las filas medían ~2300px y el título quedaba a un vacío enorme de las acciones.
- **`formatFecha` / `formatFechaHora` en `lib/utils.ts`** reemplazan los tres formatos que convivían (ISO crudo, `slice(0,10)`, `toLocaleString("es-AR")`). `formatFecha` acepta las dos formas: un `date` de Postgres (`length <= 10`) se ancla a mediodía UTC para que la conversión de zona no lo corra un día; un `timestamptz` se convierte a hora AR. Ese anclaje es el motivo de que la función no sea un `toLocaleDateString` pelado.
- **Marcas de fila con texto, no solo `title=`.** `Lock`, `Repeat`, `ExternalLink` y `Clock` en `TareaRow` (y `Lock`/`Clock` en `HiloCard`) eran ícono solo con tooltip: en touch no hay hover, así que esa información no existía en celular ni tablet. Pasaron del renglón del título a la línea de metadatos (que ya hace `flex-wrap`) como ícono + texto: "Privada", "Cada 2 día(s)", nombre de la app, "Pospuesta hasta 20/8/26".
- ~~**Temperatura con rango.** `temperaturaRango()` local en `TareaRow`, con el número entre paréntesis para el ajuste fino.~~ **Superada** — el slider y el número se fueron: ver *La temperatura pasa de slider a tres niveles* en `decisiones/tareas.md`. `temperaturaRango()` sobrevive, en `tareaLabels.ts`.
- **Temperatura oculta si la tarea está completada o cancelada**: ni el dato en la línea de metadatos ni el slider. Reusa el `activa` que ya existía.
- **`HiloCard` muestra "N/M completadas"** en vez de un número pelado, y `t-caption` sube a 13px por debajo de 768px: era la clase que carga fecha, temperatura y asignados de cada fila.
- **`ModuleTabs` con `overflow-x-auto` + `shrink-0`** en los links: 4 tabs a 360px se cortaban.
- **Auditoría: una línea de fechas** (`Creada 17/8/26 → Asignada 17/8/26 → Completada 17/8/26 09:57`) armada con `.filter(Boolean).join(" → ")`, en vez de tres `<p>` con etiquetas repetidas.

### P1 — acciones de fila siempre en `OverflowMenu`

Usuarios, Proyectos y Plantillas tenían las acciones como botones sueltos en la fila (incluido "Desactivar" en rojo), con un cluster derecho de ~250px que a 390px desbordaba porque el bloque de texto no podía encogerse. Ahora siguen el patrón de `TareaRow`: **badge + `OverflowMenu`**, y el bloque de texto es `min-w-0 flex-1` con `truncate`.

- Nombre de la fila clickeable = abre lo principal (detalle en Proyectos, edición en Plantillas), como ya hacía `TareaRow` con el título. En Proyectos eso reemplaza el botón "Ver tareas", que queda igual dentro del menú para no depender solo del click en el texto.
- El menú siempre tiene al menos un ítem: en Proyectos "Ver tareas" no depende de permisos, así que un usuario sin `gestionarAjenas` no ve un menú vacío.
- Ícono de desactivar: `Archive` en los tres, mismo que `TareaRow`.

### P2 — búsqueda, paginación y contador de resultados

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

## Permisos

### `funcion` ligada a su `vista` puntual (`vista_id`), no solo a `modulo`

Modelo anterior (`sql/001`): `submodulos.tipo` era `seccion`/`funcion`, y una función se consideraba del módulo entero — sin relación a una sección específica. Funcionaba porque `usuarios` solo tiene 1 sección. No escala a un módulo con 2+ vistas: no había forma de saber a cuál pertenece cada función.

**Cambio (`sql/003_vistas_funciones.sql`, corrido en Supabase):**
- Enum renombrado `seccion` → `vista` (`ALTER TYPE ... RENAME VALUE`).
- Columna `submodulos.vista_id` (FK a `submodulos.id`, nullable). `CHECK`: vista → `vista_id NULL`; función → `vista_id NOT NULL`. Trigger `validar_vista_id()` valida que la vista referenciada exista, sea `tipo='vista'` y comparta `modulo`.
- Una vista puede tener 0 funciones (permiso de solo-lectura, se asigna directo, sin función que la sincronice).
- `PermisosModal.tsx` ahora anida funciones bajo su vista (antes: funciones listadas flat bajo el módulo). `syncVista()` reemplaza `syncSeccion()` — sincroniza la vista dueña específica, no todas las secciones del módulo.
- `getSeccionesDeModulo()` renombrado `getVistasDeModulo()`.

**Por qué:** pedido explícito de restructurar el modelo de permisos para soportar módulos multi-vista donde cada vista tiene su propio set de funciones — regla "no crear permisos por módulo" no aplica acá, esto sigue siendo autorización 100% por submódulo, solo se hace explícita la relación jerárquica vista→función que antes era implícita (y rota) por `modulo` compartido.

**Nota de ejecución:** el CHECK constraint se agregó antes del backfill en el primer intento — falló porque la fila `usuarios_gestionar` (funcion, sin `vista_id` todavía) lo violaba. Reordenado: backfill primero, constraint después. `supabase db query -f` corre el archivo como una sola transacción — el fallo revirtió todo (enum rename incluido), sin dejar estado a medio migrar.

### Vista y función se autorizan por separado (`PermisosModal`)

Hasta ahora `syncVista()` derivaba el checkbox de la vista de sus funciones: marcar una función encendía la vista, desmarcar la última la apagaba. La vista no era un permiso que se pudiera tocar — era un cálculo. Pedido explícito de usuario: **vista y función son checkboxes independientes**.

- `syncVista()` y `toggleVista()` eliminados. `toggle()` es add/remove puro.
- Checkbox tri-state en el nombre del módulo: marca/desmarca todo. **Opera solo sobre los submódulos que la búsqueda deja visibles** — el contador `marcados/visibles` al lado del label se calcula sobre el mismo set. Marcar permisos fuera de pantalla sería un cambio invisible.
- Badge `Vista` (`badge-info`) / `Función` (`badge-neutral`) en cada fila. La indentación sola deja de alcanzar cuando la búsqueda filtra y rompe la jerarquía visual.
- El bulk-toggle por vista sobrevive pero como control aparte: botón de texto `Todas`/`Ninguna` a la derecha de la fila, solo si la vista tiene funciones visibles. Opera sobre `[vista, ...funciones visibles]` — incluye la vista a propósito: marcar solo las funciones generaría huérfanas y bloquearía el guardado. El checkbox de la vista queda libre para lo que es, su propio permiso.
- La fila de vista dejó de ser un `<label>` envolvente: un `<button>` dentro de un label dispara el checkbox al click. Ahora es un `div` con el label en `flex-1` y el botón afuera.

**Función sin su vista queda prohibida, y la barrera está en servidor.** El desacople hace posible un estado que antes era inalcanzable: función autorizada, vista no. Ese permiso no se ve en la UI (el botón vive dentro de una vista que el usuario no puede abrir) pero **sí se ejecuta por server action** — la action chequea el código de la función, nunca el de su vista. `asignarSubmodulos()` rechaza el payload consultando `submodulos.vista_id` de cada función entrante contra el set autorizado. La UI valida lo mismo (`huerfanas`): warning en la fila y `Guardar` deshabilitado.

**Orden en `asignarSubmodulos()`:** la validación va **antes** del `update activo:false`. Al revés, un payload inválido dejaba al usuario sin ningún permiso y después devolvía error — la desactivación y el upsert no comparten transacción.

Datos existentes verificados sin huérfanos antes del cambio (el modelo viejo los hacía imposibles), así que no hizo falta backfill.

---

## Infraestructura

### `middleware.ts` → `proxy.ts` (Next.js 16)

Next 16 deprecó la convención `middleware.ts` en la raíz (`src/`) — se renombró a `proxy.ts` con función exportada `proxy` (no `middleware`). El archivo `src/lib/supabase/middleware.ts` (helper `updateSession`, nombre fijado por `GUIDE_DB.md`) no cambia — solo el entry point de Next en `src/proxy.ts` lo importa y expone.

**Por qué:** `erp-app/AGENTS.md` (autogenerado por `next dev`) advierte que esta versión de Next tiene breaking changes vs. el training data. Toda lógica de proxy/middleware futura va en `src/proxy.ts`, no crear `src/middleware.ts`.

### Dashboard = ruta `/`, no `/dashboard`

`/` ya estaba gateado por el proxy (redirect a `/login` si no hay sesión) y solo mostraba un placeholder estático fuera del grupo `(erp-app)` (sin sidebar). Se reemplazó `app/page.tsx` por `app/(erp-app)/page.tsx` con el dashboard real — mismo route, ahora dentro del grupo con sidebar. `SidebarNav` suma un ítem "Inicio" (`href: "/"`) siempre visible, sin gating por `modulosVisibles` (el dashboard no es un módulo con submódulos propios, es la landing).

**Por qué:** evitar una ruta `/dashboard` redundante cuando `/` ya cumplía el rol de landing autenticada.

### `usuario_widgets` — RLS directo, sin `service_role`

A diferencia de `usuarios`/`usuario_submodulos` (server actions con `service_role` porque la autorización pasa por `tiene_permiso`), el toggle de widgets es una preferencia estrictamente propia del usuario. RLS con `usuario_id = auth.uid()` alcanza para SELECT/INSERT/UPDATE — el server action de `modules/dashboard/actions.ts` usa el cliente normal (`lib/supabase/server.ts`), no cliente admin.

**Por qué:** usar `service_role` acá sería una elevación de privilegio innecesaria para un dato sin lógica de negocio — regla "simplicidad antes que abstracción". Precedente para futuros módulos: `service_role` solo cuando RLS no puede expresar la regla de autorización (ej: chequeos vía `tiene_permiso`), no por default en todo server action de escritura.

### Sidebar: `Sidebar.tsx` (server) + `SidebarNav.tsx` (client) + `MobileNav.tsx` (client)

Portado el patrón de `erp-old-2`. `Sidebar.tsx` es server component: trae `nombre` (tabla `usuarios`, sin `avatar_url` — ese campo no existe en el schema nuevo, avatar es solo iniciales) y `modulosVisibles` (reusa `getUserSubmodulos()` de `lib/permissions`, ya cacheado). `SidebarNav.tsx` es un solo componente que sirve tanto al `<aside>` desktop como al drawer mobile (`MobileNav.tsx`) — incluye footer con iniciales + nombre + logout. Sin `grupo` (agrupación de nav) — con 2 módulos no hace falta, agregar cuando haya 3+.

`signOutAction` vive en `modules/auth/actions.ts` — sin `permissions.ts` porque ni entrar ni salir tienen gate de permiso. Sí hay `types.ts` desde que el login se valida en servidor (ver sección Auth).

**Dark mode:** `--brand-50`, `--brand-700` y `--neutral-100` (usados por `.nav-item-active` y `.badge-brand`) pasaron a ser custom properties en `:root`/`[data-theme="dark"]` (mismo patrón que `--bg-*`/`--text-*`) en vez de hex fijo en `@theme inline` — sin esto, el ítem de nav activo quedaba con el celeste claro del light mode también en dark.

---

## La regla de negocio vive en Postgres, no en `actions.ts`

El módulo tareas ya funciona así de hecho: `validar_cierre_hilo`, `validar_responsable_tarea`, `validar_proyecto_tarea_miembros`, `validar_quitar_miembro_proyecto`, `reabrir_hilo_en_tarea`, `generar_recurrencia` y `log_evento_tarea` son triggers, y la visibilidad entera es RLS (`puede_ver_hilo`, `es_asignado_tarea`, `es_miembro_proyecto`, `tiene_permiso`). Se eleva a regla siempre activa en `CLAUDE.md`.

**Por qué:** la única superficie del sistema hoy son Server Actions, que no son API — el action-id es un identificador interno de Next que cambia en cada build, sin schema ni versionado. El día que entre un segundo consumidor (un agente IA, el portal `erp-cliente`, un job, una integración), ese consumidor no puede llamar `actions.ts`; entra por PostgREST/Supabase con su propio JWT. Toda regla que solo exista en TypeScript queda del lado equivocado de esa frontera y se convierte en una segunda autoridad — exactamente lo que prohíbe *Fuente única de verdad*. Una regla en trigger o constraint la obedecen los dos por construcción, sin duplicar nada.

Esto **no** es preparación para un agente IA. No se construye API, ni identidad de agente, ni tokens: sería arquitectura especulativa. Es solo dónde poner la lógica que igual hay que escribir.

**Deuda conocida, no se migra ahora:** `modules/tareas/actions.ts` (760 líneas) tiene orquestación multi-tabla que hoy solo existe en TS — `convertirTareaEnHilo`, `deshacerConversionHilo`, `agregarTareasDesdePlantilla`, `sincronizarAsignados`. Funcionan y nadie más las necesita todavía. Migran a funciones Postgres cuando aparezca el segundo consumidor, no antes; la regla aplica de acá en adelante para que la deuda deje de crecer.

**Cómo se ve en la práctica:** `queries.ts:44` ya llama `supabase.rpc("reactivar_posponer_vencidos")`. Ese es el patrón: la función vive en `sql/`, `actions.ts` la invoca. `SECURITY INVOKER` por defecto para que RLS siga aplicando al llamador; `SECURITY DEFINER` solo si hace falta bypasear RLS, y ahí vale la regla ya registrada de `SET search_path = public`.
