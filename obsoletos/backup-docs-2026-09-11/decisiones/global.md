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
- **Breadcrumb**: no existe en el fuente. Viene del prototipo `obsoletos/prototipo-obras-tareas.html` (`.crumb`, arriba del `<h1>`). Regla en CLAUDE.md → "Encabezado de módulo". Renderiza `Módulo / Vista` con `t-caption`; no navega hacia arriba (el módulo ya está en el sidebar), es orientación. Reusa `LABEL_MAP` y `tabActiva` — sin fuente de verdad nueva. Sin hoja de detalle por ahora: la agrega el que la necesite pasándole el nombre por prop.
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

**`DescartarCambios` es hermano del `<dialog>`, no hijo.** Segunda mitad del mismo problema de
arriba: `Modal` y `RightPanel` renderizaban el modal de "Descartar cambios" **adentro** del
`<dialog>` que ese modal tenía que oscurecer. Anidado así, la página de atrás se atenuaba pero el
panel quedaba a brillo pleno — el `::backdrop` de un `<dialog>` no tapa a su propio ancestro del
top layer. Ahora los dos componentes devuelven un fragmento con el `<dialog>` y el modal como
hermanos, y el orden del top layer alcanza: el último que llamó `showModal()` queda arriba y su
backdrop tapa al anterior. Sin z-index ni clase nueva.

**`hayCambios` en `RightPanel` y `Modal`: cerrar por backdrop, Escape o X pregunta antes de descartar.** Un click al costado borraba un formulario a medio llenar sin aviso. Se conecta con `formState.isDirty` de RHF en los siete paneles con form, y con `nota.trim().length > 0` en `CompletarModal`. El submit exitoso llama `onClose` directo, así que no pasa por la guardia. `DescartarCambios` vive dentro de `Modal.tsx` — es `ConfirmModal` con copy fijo, y en archivo propio armaba un ciclo de imports con quien lo usa.

**El toaster también entra al top layer: `components/feedback/TopLayerToaster.tsx` nuevo.** El `<ol>` de sonner es un nodo normal, así que cualquier `toast` disparado con un `RightPanel`/`Modal` abierto quedaba tapado por el `<dialog>` — invisible tanto el error como el "Guardado". `TopLayerToaster` envuelve a `<Toaster>`, le pone `popover="manual"` al `[data-sonner-toaster]` y lo re-promueve (`hidePopover()`+`showPopover()`) con un `MutationObserver` cada vez que aparece un toast, para que quede sobre el último `<dialog>`. sonner ya deja el `<ol>` con `pointer-events:none` (solo el toast en sí es clickeable), así que estar arriba no bloquea el panel. Una regla sin `@layer` en `globals.css` (`[data-sonner-toaster][popover]`) anula el borde/fondo/padding/`inset` que las UA popover styles le pintarían al `<ol>`; `top`/`right` los sigue poniendo sonner.

### `ConfirmModal`

**`ConfirmModal` acepta `cancelLabel`.** Con la acción confirmada llamándose "Cancelar la tarea", un botón de salida que dice "Cancelar" no se puede leer. Acá dice "Volver"; el default sigue siendo "Cancelar" para el resto.

### `OverflowMenu`

**`OverflowMenu` posiciona el dropdown con `fixed` + `getBoundingClientRect`, no `absolute`.** Dentro de un panel con `overflow-y-auto` un menú `absolute` lo recorta el contenedor (se veía cortado en `HiloDetailPanel`). `fixed` no lo recorta ningún ancestro con overflow; la posición se calcula al abrir y se decide arriba/abajo según el espacio libre (alto estimado por cantidad de ítems — ver comentario `ponytail:`). Contrapartida: al scrollear el contenedor el menú se despegaría del botón, así que un listener de `scroll` en captura lo cierra.

### `ThemeToggle`

**El toggle de tema deja de flotar y se muda al footer del sidebar.** Era un botón `fixed
bottom-4 right-4` de 56px sobre todo el contenido: tapaba la última fila de cada listado y las
acciones pegadas al borde derecho de las fichas de obras. El padding en el contenedor de página
—la otra opción— solo lo resuelve con el scroll al final; el botón flota sobre el medio del
contenido en cualquier otra posición.

Vive en `SidebarNav`, así que sirve al `<aside>` de escritorio y al drawer de mobile con un solo
render, al lado de "Cerrar sesión": las dos son preferencias de la sesión, no del módulo. En
mobile queda a un tap del hamburger, que es aceptable para algo que se cambia al salir a la
obra y no cada minuto. El login lo repite en su propio rincón —ahí todavía no hay sidebar y el
fondo alrededor del card está vacío—, y con eso se fue el `pb-20` que `LoginForm` reservaba
para esquivarlo.

**El tema se lee con `useSyncExternalStore`, no con `useEffect` + `setState`.** El valor lo
escribe el script inline de `app/layout.tsx` antes de hidratar y vive en el atributo
`data-theme` del `<html>`: es estado de un sistema externo. Leerlo con un efecto es lo que
cortaba `react-hooks/set-state-in-effect` —el lint del repo venía fallando por este archivo—.
La suscripción es un `MutationObserver` sobre ese atributo, así que el propio `setAttribute`
del click es lo que dispara el re-render y no hace falta `setState`. El snapshot de servidor es
`null` y el botón no se renderiza hasta hidratar, igual que antes.

### `SearchInput`

**`SearchInput` tenía placeholder como único nombre.** `aria-label={placeholder}` — el placeholder ya está escrito para el usuario ("Buscar tarea o hilo…") y desaparece al tipear, que es justo cuando el lector de pantalla lo necesita.

---

### `FiltroDias`

**El período de un log es un componente, no un array copiado.** `[7, 30, 90]` estaba escrito seis
veces entre las dos vistas de logs de obras y sus dos `page.tsx` — y las copias de las páginas no
son cosméticas: son las que validan el `?dias=` de la URL, así que decidían si un `?dias=45`
escrito a mano se aceptaba o caía al default. `components/ui/FiltroDias.tsx` exporta el control y
`DIAS_OPCIONES`.

Está en `components/ui/` con dos usos, los dos de obras, porque cualquier log con ventana
temporal lo va a querer y el componente no sabe nada del módulo: recibe `href`, `dias` y una
`etiqueta` para el `aria-label`. El activo es `bg-brand-50 font-semibold text-brand-700` sobre
`border-border`, la forma del segmented de relación de la Lista de tareas — antes era
`btn-primary`, que en el sistema es un botón de acción, no un filtro elegido.

---

## Tokens y clases de `globals.css`

**`.row` en `globals.css`.** `p-[13px] px-5` — el token de fila del design system (§8) — estaba escrito a mano en 19 lugares, entre tareas, comercial y usuarios. Se reemplazaron todos, no solo los del módulo: es el mismo valor mágico.

**Campos obligatorios marcados antes de guardar, con `.t-label-req` en `globals.css`.** Asterisco por `::after` sobre la clase de label que ya existía, en vez de repetir un `<span>` en diez formularios. El asterisco es decorativo: la semántica la lleva `aria-required` en el control. No se usa el atributo `required` nativo — dispararía la validación del browser antes que Zod y competiría con los mensajes propios.

**`.icon-btn` existía en el media query de 44px pero nunca se había definido.** Las X de `RightPanel` y `Modal` eran botones del tamaño del ícono (~20px) — el gesto principal de cierre en touch. Ahora la clase existe (34×34, r-md, spec §8) y crece a 44×44 en mobile.

**`.tap-target` para lo tocable que no es un botón del sistema.** El media query de 44px solo nombraba `.btn`/`.input`/`.nav-item`/`.icon-btn`, y el módulo está lleno de elementos tocables que no usan ninguna: la fila entera de `PasoAjeno`, "Ver los N pasos" de `HiloCard`, el segmented de relación de la Lista, el nombre de plantilla (único acceso a editarla), los checkboxes de asignados y miembros, el "Se repite" de la tarea y los ítems de `OverflowMenu`. Nueve usos con una clase, en vez de `min-h-11` suelto en cada uno: así el alto extra existe solo abajo de 768px y no engorda las filas en desktop, que es lo que pide el guide.

**`.input:focus` pisaba `.input-error` (global).** `.input:focus` tiene especificidad `(0,2,0)` y `.input-error` `(0,1,0)`: el orden en el archivo no alcanzaba. El campo que RHF enfoca al fallar la validación perdía el borde rojo y se pintaba azul de marca — con `aria-invalid="true"` puesto y el texto de error abajo. Pegaba en todos los forms, no solo en login. El selector pasa a `.input-error, .input-error:focus`, que empata especificidad con `.input:focus` y gana por orden.

**`success-bg/text`, `warning-*`, `error-*` e `info-*` pasan a ser dark-aware (global).** Eran hex fijos en `@theme`, así que en dark el bloque de error del login era un parche rosa `#FEE2E2` sobre el card oscuro, y lo mismo todos los `.badge-*`. Se promueven a custom properties en `:root`/`[data-theme="dark"]` y `@theme inline` las referencia — mismo patrón y mismo motivo que `--brand-50`/`--brand-700` cuando el ítem de nav activo quedaba celeste claro en dark.

Se migran las cuatro familias, no solo `error`: dejar `success`, `warning` e `info` en hex fijo partía el sistema en dos mitades con reglas distintas, que es peor que el cambio visual de los badges en dark. Los pares dark son bg-950 / text-200 de cada hue.

**`text-error` y `text-warning` son hex fijos sobre fondo tematizado: van a `text-error-text` / `text-warning-text`.** Los tokens `--error-text` y `--warning-text` ya existían tematizados (los usaban `badge-error` y `badge-warning`) y nadie más los tocaba. Medido sobre `--bg-surface` en los dos temas: `text-error` (#DC2626) daba 3.8:1 en oscuro y `text-warning` (#D97706) 3.2:1 en **claro** — los dos abajo de AA, y justo en el vencimiento vencido y en "Pospuesta hasta". Con los tokens: error 14.0:1 claro / 11.7:1 oscuro, warning 11.0:1 claro / 14.4:1 oscuro. Los `text-success` / `text-warning` que quedan son íconos, no texto: el umbral ahí es 3:1 y lo pasan. **`.input-error-text` cerró después, con el mismo cambio**: `text-error` → `text-error-text`. Había quedado afuera de aquella pasada por ser app-wide y no del módulo tareas, y es la clase de todos los mensajes de validación de la app — 37 usos en auth, obras, tareas y usuarios. El `text-error` que sobrevive es el asterisco de `.t-label-req`, que es decorativo por decisión: la semántica la lleva `aria-required` en el control.

**`.card:hover { shadow-md }` pasa a `.card-link:hover`.** La sombra al pasar el mouse es una
promesa de click, y la clase la levantaban las 24 `.card` de la app — incluidas las `<section>` y
las `<li>` estáticas de cada ficha, que no hacen nada al clickearlas. Cinco lugares la piden y la
declaran: las filas-link de los tres listados de obras, el resultado del `Buscador` y
`WidgetCard`, que la toma solo cuando recibe `href`. El `Buscador` es un `<button>` y no un
`<Link>`: lo que define la clase es que el elemento sea clickeable, no su etiqueta.

**El `py-1.5` de las toolbars se va: `.input` ya mide lo que mide `.btn`.** Un `.input py-1.5`
mide ~35px al lado de un `.btn` de 40px, y estaba en 14 lugares. Sin pisar, `.input` mide 41px
—9px de padding contra 9px, más 1.5px de borde contra 1px— así que el desfasaje era el override,
no las clases. Salió de los 12 que son toolbar, entre obras, tareas y usuarios, incluido
`SearchInput`, que es el buscador de cuatro vistas.

Sobreviven dos, en `TareaDetailPanel.tsx:179` y `:267`: ahí no es una toolbar sino un select
inline con su propio `text-[13px]`, y no está al lado de ningún `.btn` con el que desalinearse.
Con dos usos no se justifica una `.input-sm`; si aparece un tercero, sí.

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

### `MobileNav` cierra el drawer durante el render, no en un efecto

El `useEffect(() => setOpen(false), [pathname])` que cerraba el drawer al navegar era el último
error de `react-hooks/set-state-in-effect` del repo: dejaba `npm run lint` en rojo. Pasó al patrón
que ya usan `TareaRow`, `HiloCard` y `CerrarHiloModal` — se guarda el `pathname` visto y se
reacciona al cambio durante el render.

### Sidebar: `Sidebar.tsx` (server) + `SidebarNav.tsx` (client) + `MobileNav.tsx` (client)

Portado el patrón de `erp-old-2`. `Sidebar.tsx` es server component: trae `nombre` (tabla `usuarios`, sin `avatar_url` — ese campo no existe en el schema nuevo, avatar es solo iniciales) y `modulosVisibles` (reusa `getUserSubmodulos()` de `lib/permissions`, ya cacheado). `SidebarNav.tsx` es un solo componente que sirve tanto al `<aside>` desktop como al drawer mobile (`MobileNav.tsx`) — incluye footer con iniciales + nombre + logout. Sin `grupo` (agrupación de nav) — con 2 módulos no hace falta, agregar cuando haya 3+.

`signOutAction` vive en `modules/auth/actions.ts` — sin `permissions.ts` porque ni entrar ni salir tienen gate de permiso. Sí hay `types.ts` desde que el login se valida en servidor (ver sección Auth).

**Dark mode:** `--brand-50`, `--brand-700` y `--neutral-100` (usados por `.nav-item-active` y `.badge-brand`) pasaron a ser custom properties en `:root`/`[data-theme="dark"]` (mismo patrón que `--bg-*`/`--text-*`) en vez de hex fijo en `@theme inline` — sin esto, el ítem de nav activo quedaba con el celeste claro del light mode también en dark.

### Notificaciones: infra sin submódulo, y sin motor (`sql/038`)

Pedido como "motor de notificaciones y sugerencia de tareas". Se construyó la mitad de
notificaciones; la de sugerencias no, y por qué está más abajo.

**No es un motor.** No hay reglas configurables, plantillas de mensaje ni suscripciones: una tabla,
tres triggers colgados de escrituras que ya ocurrían y dos funciones de lectura. Un tipo nuevo es un
`PERFORM notificar(...)` más. La demanda concreta eran tres casos —el rechazo de un alta congelada
que `BACKLOG.md` tenía anotado desde `sql/033`, la transferencia de una obra y la asignación de una
tarea—, y un registro de reglas para tres casos es arquitectura especulativa.

**No es un módulo: no lleva submódulo.** Va donde `usuario_widgets` y `usuario_tutorial` — prefijo
`usuario_`, RLS directo por `auth.uid()`, sin vista ni permiso propio. Recibir el aviso de algo que
ya podés ver no necesita autorización nueva: el permiso lo puso la entidad apuntada. Un submódulo
`notificaciones_ver` habría sido un permiso que nadie puede negar sin romper la app.

**La notificación apunta, no copia** — la decisión que gobierna todo el resto. La fila guarda
`(entidad, entidad_id)` y el texto se arma al leer bajo la RLS del lector. Con el título copiado,
`sql/013` —perder la asignación es dejar de ver— se rompía desde la campanita. Por eso
`notificaciones_listar` es INVOKER y resuelve con INNER JOIN: lo que la RLS no devuelve, no aparece.
Verificado: sacarle la asignación al destinatario vacía su bandeja y la fila sigue existiendo.

**Evento es fila, estado es consulta.** "Te asignaron X" pasó una vez y tiene destinatario único.
"Tenés 3 vencidas" es el estado de hoy: como fila necesitaría un cron que la cree a medianoche y
otra pasada que la borre al completar la tarea. Es `notificaciones_avisos()`, mismo criterio que
`reactivar_posponer_vencidos()`. El ERP sigue sin cron.

**El badge cuenta lo no leído de la lista, no de la tabla.** Contar filas crudas daría un número más
alto que lo que se ve, porque las de entidades ya invisibles no se muestran. Los avisos de
vencimiento no suman al badge: un badge que no puede llegar a cero deja de significar algo.

**Dónde está la campanita.** Arriba a la derecha de las dos superficies de nav —el `<aside>` de
escritorio y la barra de `MobileNav`—, y **no** en el drawer: ahí estaría escondida detrás del botón
que hay que apretar para verla. Los datos los trae `Sidebar.tsx` (server) y se refrescan con la
navegación; sin polling ni Realtime hasta que alguien los pida.

**La sugerencia de tareas no se construyó.** "¿Qué hago ahora?" ya es la vista Misión más el orden de
`useOrdenTemperatura` — un sugeridor sería una segunda autoridad sobre la misma pregunta. "¿Qué
tarea debería existir?" sí es nueva, pero hoy una tarea no sabe de qué obra habla (`origen_app` /
`origen_punto` son texto libre y solo decorativos), así que la sugerencia no puede saber si ya la
creaste y la repetiría para siempre. Ese vínculo es el prerequisito, y es una columna, no un motor.
Queda en `BACKLOG.md`.

---

## La regla de negocio vive en Postgres, no en `actions.ts`

El módulo tareas ya funciona así de hecho: `validar_cierre_hilo`, `validar_responsable_tarea`, `validar_proyecto_tarea_miembros`, `validar_quitar_miembro_proyecto`, `reabrir_hilo_en_tarea`, `generar_recurrencia` y `log_evento_tarea` son triggers, y la visibilidad entera es RLS (`puede_ver_hilo`, `es_asignado_tarea`, `es_miembro_proyecto`, `tiene_permiso`). Se eleva a regla siempre activa en `CLAUDE.md`.

**Por qué:** la única superficie del sistema hoy son Server Actions, que no son API — el action-id es un identificador interno de Next que cambia en cada build, sin schema ni versionado. El día que entre un segundo consumidor (un agente IA, el portal `erp-cliente`, un job, una integración), ese consumidor no puede llamar `actions.ts`; entra por PostgREST/Supabase con su propio JWT. Toda regla que solo exista en TypeScript queda del lado equivocado de esa frontera y se convierte en una segunda autoridad — exactamente lo que prohíbe *Fuente única de verdad*. Una regla en trigger o constraint la obedecen los dos por construcción, sin duplicar nada.

Esto **no** es preparación para un agente IA. No se construye API, ni identidad de agente, ni tokens: sería arquitectura especulativa. Es solo dónde poner la lógica que igual hay que escribir.

**Deuda conocida, no se migra ahora:** `modules/tareas/actions.ts` (760 líneas) tiene orquestación multi-tabla que hoy solo existe en TS — `convertirTareaEnHilo`, `deshacerConversionHilo`, `agregarTareasDesdePlantilla`, `sincronizarAsignados`. Funcionan y nadie más las necesita todavía. Migran a funciones Postgres cuando aparezca el segundo consumidor, no antes; la regla aplica de acá en adelante para que la deuda deje de crecer.

**Cómo se ve en la práctica:** `queries.ts:44` ya llama `supabase.rpc("reactivar_posponer_vencidos")`. Ese es el patrón: la función vive en `sql/`, `actions.ts` la invoca. `SECURITY INVOKER` por defecto para que RLS siga aplicando al llamador; `SECURITY DEFINER` solo si hace falta bypasear RLS, y ahí vale la regla ya registrada de `SET search_path = public`.

---

## El módulo comercial se elimina entero (`sql/026`)

Se fue el módulo completo: `modules/comercial/` (16 archivos), `app/(erp-app)/comercial/` (5), su entrada en `SidebarNav`, los mensajes `CM001`–`CM003` de `lib/utils.ts`, `sql/018_comercial.sql`, `decisiones/comercial.md` y `HANDOFF_COMERCIAL_FASE1.md`. En Supabase: 8 tablas, 6 enums, 6 funciones y los 10 submódulos con sus 17 asignaciones.

**No aplica "nunca DELETE".** Esa regla protege registros de negocio de un módulo vivo — permite desactivar sin perder historia y sin romper FKs. Acá desaparece el módulo, así que no hay historia que consultar ni pantalla que pueda mostrarla: dejar 8 tablas y 10 submódulos con `activo = false` sería dejar el esquema y la grilla de permisos hablando de algo que ya no existe. Las 20 filas que había quedaron volcadas a JSON fuera del repo antes del DROP.

**El único enganche real era `usuarios_select`.** `sql/018` le había sumado `OR tiene_permiso('comercial_prospectos')` para que el picker de responsable listara usuarios. `sql/026` reescribe la policy sin esa cláusula y con las otras tres intactas — no la dropea, porque las de perfil propio, `usuarios_ver` y las dos de tareas son de otras migraciones. Verificado antes de correr: ninguna otra tabla, enum ni función dependía de comercial (cero FKs entrantes, cero columnas usando sus enums).

---

## `argsRpc()` — los tipos de argumentos de RPC dejaron de ser nulables

`erp-app/src/lib/supabase/rpc.ts`.

Al regenerar `database.types.ts` para el módulo obras, las llamadas `.rpc()` de tareas empezaron a fallar el typecheck: 16 errores por pasar `null` a argumentos declarados no-nulos (`crear_tarea`, `editar_tarea`, `crear_proyecto`, `editar_proyecto`).

**No es culpa del MCP ni del CLI.** `gen types --project-id` genera del lado del servidor: el CLI recién autenticado y el MCP producen byte por byte lo mismo, y el archivo commiteado antes traía `| null`. Supabase cambió el generador.

Los tipos son los que mienten: los parámetros SQL aceptan NULL, y PostgREST los exige **presentes** cuando no tienen `DEFAULT` — mandar `null` es lo correcto y omitirlos daría "missing parameter".

`argsRpc<"nombre_funcion">({...})` acota la corrección a un solo lugar y sigue chequeando nombre y tipo de cada campo (los admite como `T | null`). La alternativa era castear en cada llamada, que pierde el chequeo, o agregar `DEFAULT NULL` en SQL — que obliga a darle default a todos los parámetros posteriores de cada función.

Si el generador vuelve a emitir `| null`, se borra el helper y las llamadas quedan igual.

## `erp-app/AGENTS.md` dice ser algo que no es

El archivo afirma estar escrito por `next dev` y manda leer `node_modules/next/dist/docs/` antes de escribir código.

Verificado: está commiteado desde el scaffold (`fbee462`), y **ninguna de las dos rutas existe** en esta instalación — ni el directorio de docs ni el `generate-agent-files.js` que dice generarlo. Next acá es 16.3.0.

Mientras siga así, las convenciones de Next se verifican contra el código del repo, no contra ese archivo. Lo que sí es cierto y hay que respetar: `params` y `searchParams` son `Promise` y se esperan con `await` (ver `app/(erp-app)/tareas/auditoria/page.tsx` y las rutas `[id]` de obras).

---

## `sql/035` — los advisors de Supabase, resueltos o descartados uno por uno

Barrido completo del proyecto: typecheck, lint y build de las dos apps (limpios), migraciones (nada pendiente) y los advisors de seguridad y performance. `sql/035_advisors_hardening.sql`, corrida vía MCP.

**`auth.uid()` va envuelto en `(select ...)` — siempre.** Era el hallazgo con peso real: 35 policies lo llamaban suelto. Postgres lo trata como VOLATILE y lo re-evalúa **una vez por fila**; dentro de un subselect lo resuelve una sola vez como InitPlan. Con las tablas de hoy no se mide, pero el costo crece lineal con las filas y toca todas las tablas del sistema. Es forma, no lógica: los cuerpos se generaron desde `pg_policies` con un `regexp_replace`, y se aplicaron con `ALTER POLICY`, no `DROP` + `CREATE` — nunca hubo un instante con una tabla sin política.

**Las 34 funciones `SECURITY DEFINER` expuestas por RPC no eran el problema que el advisor cree.** `obras_set_activo`, `obras_transferir` y `obras_resolver_pendiente` chequean `tiene_permiso()` en la primera línea del cuerpo; el resto son helpers que las policies necesitan poder llamar. Se revocaron solo las cuatro que son trigger functions puras (`handle_new_user`, `handle_user_email_updated`, `obras_guard_congelado`, `obras_marcar_pendiente`) — mismo criterio que `sql/006` aplicó a las de tareas.

**Revocar `EXECUTE` no apaga el trigger**, y no es una suposición: se verificó en la base con una tabla temporal, una función sin `EXECUTE` para `authenticated` y un `SET ROLE`. El trigger se disparó igual. Postgres chequea el privilegio al crear el trigger, no al dispararlo — si no fuera así, cada alta de obra habría empezado a fallar con este cambio.

**`tiene_permiso` sale de `anon` pero se le regrantea a `authenticated` explícito.** Las policies la invocan como ese rol: revocársela a los dos las rompe todas. Riesgo asumido y anotado en el archivo — si alguna vez una policy tiene que evaluarse sin sesión, va a fallar con `42501 permission denied for function tiene_permiso`, un error que no nombra la policy. Hoy no hay lectura anónima: el middleware manda a `/login` antes de tocar la base.

**Lo que quedó sin tocar, a propósito:** los 23 índices que el advisor marca sin uso — la base es joven y ninguno tuvo todavía la oportunidad de servir. Y *leaked password protection*, que no es SQL sino un toggle del dashboard de Auth (queda en `BACKLOG.md`).

**Verificación:** `sql/tests/rls_obras.sql` 29/29, `rls_visibilidad_tareas.sql` 17/17, `perfil_propio.sql` + `usuarios_activo.sql` 6/6. Los tres se corrieron reescritos como un único `DO` que termina en `RAISE EXCEPTION` en vez de depender del `ROLLBACK` final: un statement es atómico, así que revierte aunque falle a la mitad. Confirmado después: cero filas de prueba y cero usuarios desactivados.

---

## DM Sans reemplaza a Barlow Semi Condensed + Plus Jakarta Sans

La empresa cambió la tipografía de somosjada.com. El ERP arrastraba las dos familias del spec
original de 2026-08, así que el sistema y el sitio ya no se parecían.

**Una sola familia.** El sitio usa DM Sans variable (100–1000) para todo — no hay display separada.
`--font-display` y `--font-body` desaparecen y queda `--font-sans`; todo hereda de `body`. Las tres
usadas de `font-display` en componentes (`not-found.tsx`, `WidgetUsuarios.tsx`, `TareaCard.tsx`)
pasaron a la clase `t-*` que corresponde. Dos tokens apuntando a la misma familia era duplicación sin
motivo.

**El tracking de títulos se invirtió: de +.01/.02em a −.02em.** Es el cambio con peso real y no es
cosmético. Barlow Semi Condensed es semi-condensada y sin tracking positivo los títulos se apelmazan;
DM Sans es de ancho normal y con ese mismo tracking se desarma. Copiar la escala vieja tal cual sobre
la familia nueva era el error fácil. Por lo mismo bajan los tamaños de título (h1 36→32, h2 28→24,
h3 20→18): al mismo px DM Sans ocupa bastante más ancho, y los títulos empujaban el layout.

**El cuerpo se alinea al sitio:** body-l 17→16, body-m 15→14, caption 11→12 — `text-base`,
`text-sm` y `text-xs` del sitio, literales. `t-label` toma el eyebrow del sitio (12px, peso 500,
uppercase) pero cerrado a .12em en vez de .16em: acá es label de formulario, no decoración de hero.

~~El override mobile `.t-caption { font-size: 13px }` de `globals.css`~~ se borró. Existía porque
caption medía 11px y era ilegible en celular; con 12px la premisa se cayó. Si vuelve a molestar, el
arreglo es el token, no un parche por breakpoint.

**Los archivos.** Dos `.woff2` partidos por `unicode-range` (latin + latin-ext), variable 100–1000,
55 KB contra los 145 KB de los ocho estáticos anteriores. Son los que sirve somosjada.com — bajados
de ahí, no de Google Fonts, para que el render sea el mismo. Van con un `@font-face` de fallback con
métricas de Arial (`size-adjust: 104.53%` y compañía, generado por next/font en el sitio) que evita
el salto de layout durante el `swap`. Los ocho viejos quedaron en `obsoletos/fonts-barlow-jakarta/`.

Pesos: 400 cuerpo, 500 labels/botones/nav, 600 títulos. **No se usa 700** — el sitio no lo usa en
ningún lado. `WidgetUsuarios` tenía `font-bold` y perdió el bold.

`.btn` (14px/500) y `.input` (14px) ya coincidían con los del sitio y no se tocaron.
