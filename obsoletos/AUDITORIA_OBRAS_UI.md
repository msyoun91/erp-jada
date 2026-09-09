# Auditoría visual — Agenda de Obras

Fecha: 2026-09-08. Estado: **Cerrada.** C1, C2, A1–A7, M1–M11 y B1–B2, B4–B9 implementados.
**B3 se cierra sin tocar código:** la segunda pasada de navegador lo midió y no reproduce — el
síntoma era el puntero del mouse de la herramienta de captura, no la UI. 28 arreglos y 1 falso
positivo.
Los hallazgos resueltos quedan escritos, tachado el título y con la nota de qué se hizo — el
relevamiento sirve de registro de por qué la fila quedó como quedó.

Dos pasadas sobre el mismo módulo:

1. **Lectura de código** — los 36 archivos de `modules/obras/` y `app/(erp-app)/obras/`, contra
   `GUIDE_DESIGN.md`, `design-system/JADA-design-system.md`, `globals.css` y `decisiones/obras.md`.
   Comparación con tareas y usuarios, que son el lenguaje visual ya establecido.
2. **Navegador** — las 5 tabs, ficha de obra, panel de vincular empresa, en light y dark,
   a 1440×950 y a 390×860. Datos reales del seed. Consola sin errores.

`Confirmado` = visto en pantalla. `Código` = deducido de la lectura, no reproducido todavía.
`Confirmado` resultó ser más débil de lo que sonaba: B3 estaba marcado así y era el cursor de la
herramienta de captura tapando el avatar. Ver en pantalla no es haber medido.

Lo marcado **Global** no es de obras: se manifiesta acá pero el arreglo toca
`components/`, `globals.css` o el layout, así que la decisión va a `decisiones/global.md`.

---

## Crítico

### ~~C1 · El nombre de la fila colapsa a 2-3 caracteres~~ — **Hecho**

`ObrasView.tsx:114-118` · `PersonasView.tsx:67` · `EmpresasView.tsx:59` · `Buscador.tsx:89`
`ObraDetalle.tsx:100` (h2) · `ObraDetalle.tsx:170` (empresas) · `ObraDetalle.tsx:225` (personas)

A 390px el listado muestra `Hot…`, `Edificio N…`, `Co…`, `Am…`. La ficha de obra titula `C.`
—"Complejo Costa Norte" reducido a una letra— con "Desactivar" en rojo ocupando la línea
entera debajo. Las filas de personas muestran `L…` y `C`.

El nombre lleva `min-w-0 flex-1 truncate`; la metadata (badges, tipo, localidad, conteos,
responsable) son ítems `flex-wrap` que no se encogen. Cuando el ancho aprieta, el único que
cede es el `flex-1`: el dato que identifica la fila. La regla mobile que sube `t-caption` a
13px (`globals.css:203`) lo empeora — la metadata pesa más y aplasta más al nombre.

Fix: nombre en línea propia abajo de `sm`, metadata en la segunda. En el header de la ficha,
`flex-col` con las acciones abajo.

**Hecho.** Los tres listados pasaron a `flex-col` abajo de `md` (ver C2, sale del mismo cambio).
Las filas de las tres fichas y las dos de Pendientes usaron `basis-full sm:basis-0 sm:grow` en
el nombre — `sm:basis-auto` no servía: `flex-1` y `basis-auto` son familias distintas de utilidades
y el orden de generación de Tailwind decide cuál gana, así que se fija la base explícita.
Los headers de `ObraDetalle`, `EmpresaDetalle` y `PersonaDetalle` quedaron en dos bloques —
identidad y acciones— apilados abajo de `sm`. En `Buscador` etiqueta y detalle van siempre en
dos líneas: el panel es `max-w-md` en cualquier pantalla, así que ahí no hay un ancho grande
donde la línea única funcione. Las filas de las fichas dejaron el `basis-full` al entrar el
`OverflowMenu` (ver A3); en Pendientes sigue.

### ~~C2 · En desktop la metadata queda ragged, sin grilla~~ — **Hecho**

Mismas filas que C1.

A 1440px el nombre queda solo a la izquierda y los cinco chips apelotonados contra el borde
derecho, con ~800px de vacío en el medio y en posición distinta en cada fila: "Idea" cae en
x=1054, 1093, 1004 según el largo del nombre. La lista no se puede escanear en vertical.

Fix: `md:grid` con columnas fijas — nombre | estado | tipo | localidad | conteos | responsable.

**Hecho** en Obras y Empresas. `PersonasView` quedó como estaba: su fila es nombre + badge, no
hay metadata que le coma el ancho ni columnas que alinear. Ver `decisiones/obras.md` por qué la
fila es una sola escritura de marcado y no dos ramas.

---

## Alto

### ~~A1 · El ThemeToggle flotante come contenido~~ — **Hecho** · Global

Tapa `Quitar` en la ficha de obra, `abrió la ficha de Gustavo Peralt.` en Auditoría, y la
última fila del listado. Obras es el módulo que más pega contenido al borde derecho, así que
acá se nota. Fix: padding inferior/derecho en el contenedor de página, o mover el toggle.

**Hecho.** Se movió. El padding solo lo arregla con el scroll al final: el botón flotaba sobre
el medio del contenido en cualquier otra posición. Ahora vive en el footer de `SidebarNav`, al
lado de "Cerrar sesión", y sirve al aside de escritorio y al drawer de mobile con un solo
render. El login lo repite en su rincón —ahí no hay sidebar— y con eso se fue el `pb-20` que
`LoginForm` reservaba para esquivarlo. De paso el componente pasó a `useSyncExternalStore`:
leer `data-theme` con `useEffect` + `setState` era el error de `react-hooks/set-state-in-effect`
que tenía `npm run lint` en rojo. Ver `decisiones/global.md`.

### ~~A2 · Rol seleccionado ≈ rol no seleccionado~~ — **Hecho**

`RolesPicker.tsx:37`

`badge-brand` (`bg-brand-50`) vs `badge-neutral` (`bg-bg-subtle`). En light son `#EBF2FD` y
`#EBF0F8`: indistinguibles, y la única señal que queda es el color del texto. En dark el texto
azul salva la lectura, pero sigue sin borde ni check. Bajo sol, en obra, no se lee.

Además `badge min-h-[44px]` deja pills de 44px de alto con texto de 11px: se ven inflados.

Es el control central de los cuatro paneles de vinculación.

Fix: `border-brand-500 + font-semibold` como el toggle de `TareasListaView.tsx:151`, y
`.tap-target` en vez de `min-h-[44px]`.

**Hecho.** El chip dejó de ser `.badge` y tomó la forma del toggle de `TareasListaView`:
`tap-target t-caption rounded-lg border px-3 py-1`, activo `border-brand-500 bg-brand-50
font-semibold text-brand-700`, inactivo `border-border text-text-tertiary`. El borde es la señal
que sobrevive al contraste bajo. Salir de `.badge` arregló de paso el inflado: la clase fijaba
11px y el `min-h-[44px]` de al lado estiraba a 44 en escritorio también; `.tap-target` da los
44px solo en mobile. Con eso se cierra uno de los tres `min-h-[44px]` que quedaban de A7. Sin
check ni ícono: adentro de un panel `max-w-md` compite con el label por el ancho. El contenedor
tomó `role="group"`, que es lo que le faltaba al conjunto de `aria-pressed`.

### ~~A3 · Las acciones no se distinguen de los datos~~ — **Hecho**

`ObraDetalle.tsx:170-185` · `ObraDetalle.tsx:240-265` · `PersonaDetalle.tsx:120-145` · `EmpresaDetalle.tsx:150-170`

En la fila se lee `Constructora  Editar  Quitar`. El primero es un dato (`t-caption`), los
otros dos son botones (`btn-ghost`, `text-tertiary`): mismo gris, mismo tamaño, misma línea.
En light es peor. En mobile envuelven a segunda línea, así que una fila de persona son cuatro
renglones de gris.

Fix: `OverflowMenu` —ya lo usan tareas (4 archivos) y usuarios— para Editar/Quitar/Referente.

**Hecho** en las tres fichas. La fila pasó a la forma de usuarios: bloque de texto
`min-w-0 flex-1` con el nombre en su renglón y la metadata abajo, `OverflowMenu` `shrink-0` a
la derecha. Las filas sin acciones —personas y obras en las fichas de empresa y persona— toman
la misma forma aunque no lleven menú. Con eso se fue el `basis-full sm:basis-0 sm:grow` que C1
había dejado en las fichas esperando justamente esto; sobrevive solo en `PendientesView`.
`CopiarEnlace` dejó de ser componente y es `modules/obras/copiarEnlace.ts`, porque como ítem de
menú lo que hace falta es la función. **A6 sigue abierto:** "Quitar de la obra" ahora está en el
menú, pero sigue sin `ConfirmModal` y sin flag `enviando`.

### ~~A4 · "Desactivar" domina la ficha~~ — **Hecho**

`ObraDetalle.tsx:117` · `EmpresaDetalle.tsx:71` · `PersonaDetalle.tsx:66`

Rojo sólido, tamaño de botón normal, en el header. Es el elemento más brillante de la pantalla,
por encima de "Editar". En mobile cae en su propia línea y es lo primero que se ve al abrir una
obra, antes que el nombre. Jerarquía invertida. Fix: al `OverflowMenu`, variante destructiva.

**Hecho.** En el encabezado queda "Editar" a la vista —es la acción de la ficha— y el resto
entra al menú: copiar enlace, transferir (solo obra) y desactivar, este último `destructive`
con ícono `Archive`, igual que Proyectos y Plantillas. El menú del encabezado nunca queda
vacío: "Copiar enlace" no tiene gate de permiso.

### ~~A5 · En las fichas ninguna tab queda activa~~ — **Hecho**

`ModuleTabs.tsx:11` — `pathname === tab.href`.

En `/obras/{id}`, `/obras/empresas/{id}` y `/obras/personas/{id}` las cinco tabs se ven
apagadas. Obras es el único módulo con páginas de detalle (tareas usa paneles), así que el bug
solo se manifiesta acá aunque el componente sea compartido.

Fix: `startsWith` con desempate por href más largo, o que el layout pase el tab activo.

**Hecho.** Activa es la tab cuyo `href` es el prefijo más largo del `pathname`. El desempate por
largo es obligatorio: `/obras` es prefijo de las otras cuatro, así que sin él
`/obras/empresas/{id}` encendía dos tabs. La comparación lleva la barra —`pathname === href ||
pathname.startsWith(href + "/")`— para que `/obras` no matchee una futura `/obrasocial`. No se
eligió la variante de pasar el tab activo desde el layout: son tres layouts repitiendo lo mismo
y ninguno conoce el `[id]`, que ya está en el `pathname`. Se agregó `aria-current="page"`.

### ~~A6 · "Quitar" desvincula sin confirmar y sin bloquear el doble click~~ — **Hecho**

`ObraDetalle.tsx:176` · `ObraDetalle.tsx:253` · `PersonaDetalle.tsx:137`

`GUIDE_DESIGN` pide confirmación antes de todo cambio de estado importante. Borra roles y
observaciones del vínculo de un click. `correr()` no levanta ningún flag `enviando`, así que
dos clicks disparan dos veces. Desactivar sí tiene `ConfirmModal`; desvincular no.

Fix: `ConfirmModal` + optimistic update (la guía lo pide para desvincular).

**Hecho, menos el optimistic update.** Las cuatro acciones destructivas de fila —quitar empresa,
quitar persona, quitar referente y quitar de la empresa en la ficha de persona— pasan por
`ConfirmModal`, con copy que dice qué se pierde y `confirmLabel="Quitar"`. El doble click salió
del mismo cambio sin escribir nada: `ConfirmModal` ya levanta su propio `enviando` y deshabilita
los dos botones mientras espera el `onConfirm`, así que la ventana de doble disparo se cerró al
mover la llamada adentro.

Como las filas viven en un `.map()`, no hay un booleano por fila: la ficha tiene un solo estado
`confirmando` con lo que se está por confirmar, y el `desactivando` que ya existía se absorbió
ahí. `EmpresaDetalle` no entró: no tiene ninguna acción destructiva de fila, así que su
`desactivando` booleano sigue siendo la forma más simple.

**El optimistic update no se hizo, y la premisa estaba mal.** No existe un solo `useOptimistic`
en toda la app: desactivar obra, persona, empresa y usuario, y todo `tareas`, esperan la server
action y se refrescan por `revalidatePath`. Meterlo acá sería el primer optimistic del proyecto,
en una acción de fila de un módulo, con el estado del servidor bajado a estado de cliente en tres
listas. `ConfirmModal` ya cubre lo que la guía pide de feedback —botón deshabilitado con espera,
después toast—. Registrado en `decisiones/obras.md`.

### ~~A7 · `min-h-[44px]` forzado también en desktop~~ — **Hecho**

`ObrasView.tsx:114` · `EmpresasView.tsx:59` · `PersonasView.tsx:67` · `Buscador.tsx:89`
`RolesPicker.tsx:37` · `VincularEmpresaPanel.tsx:248` · `VincularPersonaEmpresaPanel.tsx:153`

`.tap-target` existe y es mobile-only (`globals.css:199`); tareas lo usa en 8 archivos. Obras
hardcodea el valor en 7 lugares, así que filas y chips quedan inflados también en escritorio.

**Hecho.** Los 4 de los listados y el buscador salieron con C1 — era la misma clase que se
estaba reescribiendo, y dejarlos era tocar la línea dos veces. `RolesPicker.tsx:37` salió con A2.
Los dos últimos salieron con B4: eran el `<label>` de un checkbox, así que cambiar la clase y
estilar el control era la misma línea. Cero `min-h-[44px]` en el módulo.

---

## Medio

### ~~M1 · Texto instructivo en 11px con medida de línea de ~200 caracteres~~ — **Hecho**

`PendientesView.tsx:69` · `PendientesView.tsx:187` · `AuditoriaView.tsx:83` · `AuditoriaView.tsx:128`

Los párrafos que explican qué es la cola de autorizaciones y qué registra la auditoría están en
`t-caption` —el tamaño más chico del sistema— y estirados a 1130px. Es el texto que le enseña
el módulo al usuario, puesto en el estilo de un pie de foto.

Fix: `t-body-m max-w-prose`.

**Hecho**, los cuatro. `max-w-prose` y no un ancho a mano: es el token que Tailwind ya calcula
en `ch`, así que la medida sigue al tamaño de fuente en vez de quedarse fija.

### ~~M2 · Auditoría: sujeto y predicado a 900px de distancia~~ — **Hecho**

`AuditoriaView.tsx:107-113`

`8/9/26, 12:44 p.m.  Admin` a la izquierda … `abrió la ficha de Martín Bianchi` pegado al borde
derecho, por el `flex-1` del nombre de usuario. Como log es ilegible: hay que barrer toda la
pantalla por renglón. Fix: una sola línea corrida a la izquierda.

**Hecho.** Se cayó el `flex-1` y el `truncate` que lo acompañaba: la fila es fecha (`shrink-0`)
más una frase entera en un solo `<span>`, con el nombre en `font-semibold` adentro de la frase.
Que sea un `<span>` y no tres explica por qué ahora envuelve como texto — la oración se corta
donde entra, no en el borde de una celda. Mismo tratamiento en transferencias, donde
"la movió Fulano" pasó de chip suelto a cola de la misma frase.

### ~~M3 · `.empty-state` no se usa en ningún lado del módulo~~ — **Hecho**

`ObrasView.tsx:95` · `EmpresasView.tsx:45` · `PersonasView.tsx:51` arman su propia card `p-8`.
`PendientesView.tsx:76` y `:196` usan un `<p class="t-body-m">` pelado. Las secciones de las
fichas resuelven el vacío con un `<p class="t-caption">` suelto. Cuatro tratamientos del mismo
estado dentro del mismo módulo.

La clase existe y la usan dashboard, tareas, usuarios y `error.tsx` — 8 archivos. Obras: cero.

**Hecho**, los once. Los tres listados toman la forma de `UsuariosView`: ícono, `t-h3` que
distingue "Sin X todavía" de "Sin resultados", y `t-body-m` que dice qué hacer. Pendientes y
Auditoría lo usan a nivel de card.

**Los seis vacíos de sección de las fichas llevan `empty-state p-8`.** Una ficha tiene tres o
cuatro secciones a la vez y el `p-[60px]` de la clase deja media pantalla de cajas punteadas
vacías. Es la misma clase con el padding pisado, no un quinto tratamiento: el punto del hallazgo
era que el estado vacío se dibujara igual en todos lados, y se dibuja igual.

### ~~M4 · Cards anidadas sin contraste~~ — **Hecho**

`PendientesView.tsx:64` · `:179` · `AuditoriaView.tsx:78` · `:123`

`section.card` conteniendo `li.card`, las dos `bg-bg-surface`. La interna se distingue solo por
el borde, y las dos levantan sombra al hover. El design system dice que la elevación se
comunica con bordes, no con sombra. Fix: fila interna como `.row` + `border-b`, o `bg-subtle`.

**Hecho.** Las cuatro listas perdieron la card interna y son filas separadas por
`border-b border-border`, con `first:pt-0 last:border-b-0 last:pb-0` para que la lista no abra
ni cierre con aire de más. Se fue también el `gap-2` del `ul`: con separador, el gap deja el
borde flotando en el medio de la nada. La sombra al hover desapareció sola con M5. Mismo cambio
en "Historial de responsables" de la ficha de obra, que tenía la misma forma (ver B6).

### ~~M5 · Hover de card en lo que no es clickeable~~ — **Hecho** · Global

`globals.css:181` (`.card:hover { shadow-md }`) aplica a todas las `<li class="card">` estáticas
de las fichas y a las `<section class="card">`. Sombra al pasar = promesa de click que no
existe. Fix: mover el `:hover` a una variante `.card-link`, usarla solo en los `<Link>`.

**Hecho.** `.card:hover` pasó a `.card-link:hover`. Son cinco los lugares que la piden: las
filas-link de los tres listados de obras, el resultado del `Buscador` (que es un `<button>`, no
un `<Link>` — lo que define la clase es que sea clickeable, no la etiqueta) y `WidgetCard`, que
la toma solo cuando recibe `href`. Todo el resto de las `.card` de la app —las 19 restantes—
dejó de prometer un click que no existía. Ver `decisiones/global.md`.

### ~~M6 · El filtro de usuario de Auditoría recorta media pantalla~~ — **Hecho**

`AuditoriaView.tsx:60` — vive en una toolbar arriba de las dos secciones, pero solo filtra
accesos; transferencias lo ignora. Fix: moverlo dentro de la card de accesos.

**Hecho.** El `<select>` está adentro de la card de accesos, abajo del resumen por usuario que
es de donde salen sus opciones. El filtro de días se quedó arriba y eso ahora es coherente:
acota las dos secciones, así que es de la página.

### ~~M7 · El filtro de días está en dos lugares distintos entre tabs hermanas~~ — **Hecho, con matiz**

Arriba y global en Auditoría (`AuditoriaView.tsx:50`), adentro de la card "Ya resueltas" en
Pendientes (`PendientesView.tsx:183`). Además el activo es navy sólido, que en el sistema es un
botón primario de acción, no un filtro elegido — tareas usa `bg-brand-50` + borde.

**Hecho el estilo; la posición se queda distinta, y es correcto que lo esté.** El control es
ahora `components/ui/FiltroDias.tsx` (ver B7), con la forma del segmented de relación de la
Lista de tareas: `bg-brand-50 font-semibold text-brand-700` sobre `border-border`, no
`btn-primary`.

La posición no se unificó porque el alcance de cada uno es genuinamente distinto: en Auditoría
el parámetro `dias` acota las dos secciones —accesos y transferencias— así que es de la página;
en Pendientes acota solo "Ya resueltas", porque la cola de arriba muestra todo lo que espera sin
importar hace cuánto. Ponerlo arriba en Pendientes diría que también filtra la cola. Es el mismo
criterio con el que M6 bajó el filtro de usuario adentro de su card: el control vive donde llega
su efecto.

### ~~M8 · Dos columnas fijas en mobile, y valores largos sin `break-words`~~ — **Hecho**

`ObraFormPanel.tsx` (3× `grid-cols-2` sin breakpoint) · `EmpresaFormPanel.tsx` ·
`PersonaFormPanel.tsx` · `ObraDatosGenerales.tsx:38` · `EmpresaDetalle.tsx:79` · `PersonaDetalle.tsx:75`

En panel `max-w-md` a 390px cada columna queda ~150px. Los `dd` de email y website no tienen
`break-words`, así que un mail largo se desborda de la card.

Fix: `grid-cols-1 sm:grid-cols-2` + `break-words` en los `dd`.

**Hecho.** Las seis grillas de los tres form panels y las tres `dl` de las fichas.

El `break-words` no se puso nueve veces: los `dt/dd` de las tres fichas eran el mismo bloque
escrito nueve veces, así que salieron a `components/Dato.tsx` (`Dato` + `Observaciones`, ver B1)
y la clase vive en un solo `dd`. `Dato` toma `React.ReactNode` y no `string | null` porque dos
valores no son texto: el teléfono y el email de la ficha de persona son `<a>` de `tel:` y
`mailto:`, y la localidad de la empresa concatena la provincia.

### ~~M9 · Doble scrollbar en el panel de vincular~~ — **Hecho**

`Buscador.tsx:83` (`max-h-64 overflow-y-auto`) dentro del scroll del `RightPanel`: dos barras
a 30px una de otra.

**Hecho:** se fue el `max-h-64 overflow-y-auto`. La lista crece y scrollea el panel, que es la
barra que el usuario ya está usando. El tope de resultados lo pone la query, no el alto de la
caja.

### ~~M10 · Toolbar desalineada~~ — **Hecho** · Global

`.input` con `py-1.5` mide ~35px; `.btn` mide ~40px. Se ve en los tres listados del módulo.
También pasa en tareas, así que el arreglo es app-wide.

**Hecho, sacando el `py-1.5` y no agregando nada.** `.input` sin pisar mide 41px contra los 40px
de `.btn` — el desfasaje era el override, no las clases. Salió de los 12 lugares donde había una
toolbar: `SearchInput` (que es el buscador de 4 vistas), los selects de Obras y Auditoría, el
`Buscador` de obras, y los de tareas y usuarios.

**Sobreviven dos `py-1.5`, en `TareaDetailPanel.tsx:179` y `:267`.** Ahí no es una toolbar: son
selects inline dentro del panel, con su propio `text-[13px]`, y no están al lado de ningún
`.btn` con el que desalinearse. Si aparece un tercero, es momento de una clase `.input-sm`
—hoy serían dos usos, que no alcanzan para justificarla. Ver `decisiones/global.md`.

### ~~M11 · La ficha pierde el estado codificado por color~~ — **Hecho**

En el listado el estado es un badge (`ObrasView.tsx:118`); en la ficha es un `dt/dd` gris
(`ObraDatosGenerales.tsx:39`). Fix: badge de estado —y de Pendiente— junto al `h2`.

**Hecho el badge de estado; el de Pendiente no va.** `BADGE_ESTADO` se mudó de `ObrasView` a
`types.ts`, al lado de `LABEL_ESTADO`: el listado y la ficha ahora leen el mismo mapa. En la
ficha el badge está junto al `h2` y el `dt/dd` "Estado" salió de la grilla — dejarlo era el
mismo dato dos veces en la misma pantalla.

El badge "Pendiente" no se agregó: `EstadoPendiente` ya pone un bloque de advertencia entero dos
renglones más abajo, con el motivo y qué se puede hacer. Un chip que repite esa palabra arriba
no agrega información, y en la ficha —a diferencia del listado— hay lugar para el bloque largo.

---

## Bajo

### ~~B1 · Observaciones sin etiqueta~~ — **Hecho**
`ObraDatosGenerales.tsx:56` — "120 unidades en tres etapas." flota bajo la grilla con el mismo
estilo que un valor, sin `dt` ni separador. Parece un dato huérfano.

**Hecho** en las tres fichas, como `<Observaciones>` en `components/Dato.tsx`: etiqueta
`t-caption` y `border-t` que la separa de la grilla. Es componente y no tres bloques porque
estaba escrito igual tres veces.

### ~~B2 · El modal "Descartar cambios" no atenúa el panel del que salió~~ — **Hecho** · Global
`Modal.tsx` dentro de `RightPanel.tsx`. La página de atrás sí se oscurece; el panel queda a
brillo pleno, así que la interrupción se lee a medias.

**Hecho.** La causa era de DOM, no de CSS: `DescartarCambios` se renderizaba **adentro** del
`<dialog>` que tenía que oscurecer, en los dos componentes. Anidado así, su `::backdrop` no
tapaba a su propio ancestro. Ahora es hermano —`<>{<dialog/>}{confirmandoCierre && …}</>`— y el
orden del top layer es lo único que decide: el último que hizo `showModal()` queda arriba y su
backdrop tapa al anterior. Sin z-index ni clases nuevas. Ver `decisiones/global.md`.

### ~~B3 · El avatar del sidebar pisa el nombre~~ — **No es un defecto del producto**
`SidebarNav.tsx:71-85` — se leía `A…dmin`.

**No reproduce. El síntoma era el puntero del mouse dibujado por la herramienta de captura.**
La segunda pasada midió la caja en el navegador, en los dos anchos, con `nombre` = `Admin`
—el usuario real del seed, 5 caracteres, así que `initials()` cae en la rama de una sola
palabra y el avatar dice `AD`—:

| | caja del nombre | ancho del texto | holgura | ¿trunca? | ¿desborda el avatar? |
|---|---|---|---|---|---|
| Escritorio, 1536px | 81.2px | 40.6px | 40.6px | no | no — 18.7px en 28px |
| Drawer mobile, `.icon-btn` a 44px | 71.2px | 40.6px | 30.4px | no | no — 18.7px en 28px |

El nombre entra con el doble del ancho que necesita y el avatar y el `<span>` están separados
por los 8px del `gap-2`, sin un solo pixel de solape. El caso apretado es el drawer, porque la
media query de mobile lleva el `.icon-btn` del `ThemeToggle` de 34 a 44px (eso llegó con A1,
después del relevamiento) y aun así sobran 30px.

Lo que se vio en el relevamiento fue el cursor: la captura lo dibuja como un círculo oscuro de
~22px, y en la primera pasada quedó apoyado sobre el footer del sidebar, tapando la `D` de `AD`
y la `A` de `Admin`. Lo que sobrevive a los lados del círculo es `A` … `dmin`. En la segunda
pasada el mismo artefacto apareció sobre el logo, que se leyó `S⬤DA` en vez de `JADA` — mismo
mecanismo, elemento distinto, y ahí es evidente que no es la app.

No se toca código. **Lección de método: un hallazgo visual que el código no explica se vuelve a
mirar antes de arreglarlo.** La lectura de código había acertado —`h-7 w-7 shrink-0`, `gap-2`,
`flex-1 truncate`, sin conflicto de capas entre `text-[13px]` y `.t-body-m`— y no encontró nada
porque no había nada. Si B3 se hubiera "arreglado" a ciegas, el cambio habría quedado en el
repo defendiendo un bug inexistente.

Al margen y sin cambiar nada: para un nombre de una sola palabra `initials()` toma sus dos
primeras letras, así que el avatar repite el arranque del nombre que tiene al lado (`AD Admin`,
`TE Tester`). Es redundante, no es lo que decía el hallazgo, y con nombre y apellido —el caso
normal— no pasa.

### ~~B4 · Checkbox nativos del SO junto a pills estilizados~~ — **Hecho**
`VincularEmpresaPanel.tsx:248` · `VincularPersonaEmpresaPanel.tsx:153`. En el mismo panel: los
roles son pills, las personas son checkbox sin estilar.

**Hecho** con `h-4 w-4 shrink-0 accent-brand-700`, que es lo que ya usan `AsignadosPicker`,
`ProyectoFormPanel`, `TareaFormPanel` y `PermisosModal` — seis usos previos, ninguna clase
nueva. `accent-color` y no un control dibujado a mano: el checkbox nativo trae foco, teclado y
estado indeterminado gratis. El `<label>` de al lado pasó de `min-h-[44px]` a
`tap-target cursor-pointer` en la misma línea, que es lo que cerró A7.

### ~~B5 · Buscador mudo y botón que salta de ancho~~ — **Hecho**
`Buscador.tsx:96` — `buscado` arranca en `false`, así que si la carga inicial vuelve vacía el
panel no dice nada. `Buscador.tsx:83` — el botón muta "Buscar" → "…" en vez de usar spinner.

**Hecho.** La carga inicial marca `buscado` en el mismo callback donde deja los resultados, así
que un panel que abre vacío lo dice. El botón conserva el label "Buscar" y le antepone el
spinner de `LoginForm` —`animate-spin rounded-full border-2`, sin librería—; además queda
`disabled` mientras busca, que antes no estaba.

### ~~B6 · Ritmo inconsistente dentro de la ficha de obra~~ — **Hecho**
"Historial de responsables" es card (`ObraDetalle.tsx:268`); "Empresas" y "Personas" son
secciones peladas con filas card. Mismo nivel jerárquico, dos envases.

**Hecho.** Las tres son `<section>` con `h3` afuera. El historial se quedó con una card, pero
como envase de su lista y no de la sección: es una lista de renglones cortos, no filas
accionables, así que sus ítems van separados por `border-b` adentro de una sola card en vez de
ser una card cada uno. Mismo tratamiento que las listas de M4.

### ~~B7 · `[7, 30, 90]` escrito cuatro veces, control de días duplicado~~ — **Hecho**
`PendientesView.tsx:16` · `:183` · `AuditoriaView.tsx:10` · `:53` ·
`app/(erp-app)/obras/pendientes/page.tsx:6` · `app/(erp-app)/obras/auditoria/page.tsx:6`.
Fix: un `<FiltroDias>` en `components/ui/` y la constante única.

**Hecho:** `components/ui/FiltroDias.tsx` exporta el componente y `DIAS_OPCIONES`. Las dos
vistas renderizan `<FiltroDias href dias etiqueta />` y las dos páginas validan el `searchParam`
contra la misma constante —era la sexta copia del array, y la que decide si un `?dias=45` a mano
se acepta o cae al default. Está en `components/ui/` y no en `modules/obras/` porque cualquier
log con ventana temporal lo va a querer; hoy tiene dos usos, los dos de obras.

### ~~B8 · `enviando` global en PendientesView~~ — **Hecho**
`PendientesView.tsx:44-58` — aprobar una fila deshabilita el botón de todas, sin indicar cuál
está procesando.

**Hecho.** `enviando` pasó de `boolean` a `string | undefined` con el `registro_id` que se está
resolviendo. Solo esa fila se deshabilita, y sus botones dicen "Aprobando…" / "Rechazando…" — el
`disabled` solo no alcanzaba para señalar cuál. Es la misma forma que ya usa `rechazando`.

### ~~B9 · "No aparece — crearla" no parece un botón~~ — **Hecho**
`VincularEmpresaPanel.tsx:180` · `VincularPersonaPanel.tsx:143` — `btn-ghost` sin ícono ni
borde, se lee como texto de ayuda.

**Hecho:** `btn-secondary` con ícono `Plus`, el mismo par que usan "Vincular" y "Nueva obra". Es
la salida cuando la búsqueda no encontró lo que se busca; como texto gris pelado, el usuario que
no encontraba su empresa cerraba el panel.

---

## Orden sugerido

1. ~~**C1 solo.**~~ Hecho. Hoy el módulo no se puede usar desde un celular: no muestra el
   nombre de lo que estás mirando. Es una agenda de obra que se usa en obra.
2. ~~**C2**~~ — hecho, salió del mismo refactor de fila.
3. ~~**A1 + A4 + A3**~~ — hecho, la ficha como bloque.
4. ~~**A2 + A5.**~~ — hecho.
5. ~~**A6**~~ — hecho, sin el optimistic update; ver la nota del hallazgo.
6. ~~**A7 + M3 + M5**~~ — hecho. Fueron mecánicos, como se esperaba; el resto de M y B salió en
   la misma pasada porque M1/M2/M4/M6/M7/B7/B8 viven todos en `PendientesView` y `AuditoriaView`,
   y abrir esos dos archivos una sola vez era más barato que seis veces.
7. ~~**B3.**~~ Cerrado por la segunda pasada de navegador: no reproduce, no era un defecto de
   la app. Ver la nota del hallazgo.

Lo marcado **Global** (A1, B2, B3, M5, M10) no se decide en `decisiones/obras.md`.
