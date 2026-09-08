# Auditoría visual — Agenda de Obras

Fecha: 2026-09-08. Estado: **C1, C2, A1, A2, A3, A4 y A5 implementados; el resto relevado, sin
implementar.**
Los hallazgos resueltos quedan escritos, tachado el título y con la nota de qué se hizo — el
relevamiento sirve de registro de por qué la fila quedó como quedó.

Dos pasadas sobre el mismo módulo:

1. **Lectura de código** — los 36 archivos de `modules/obras/` y `app/(erp-app)/obras/`, contra
   `GUIDE_DESIGN.md`, `design-system/JADA-design-system.md`, `globals.css` y `decisiones/obras.md`.
   Comparación con tareas y usuarios, que son el lenguaje visual ya establecido.
2. **Navegador** — las 5 tabs, ficha de obra, panel de vincular empresa, en light y dark,
   a 1440×950 y a 390×860. Datos reales del seed. Consola sin errores.

`Confirmado` = visto en pantalla. `Código` = deducido de la lectura, no reproducido todavía.

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

### A6 · "Quitar" desvincula sin confirmar y sin bloquear el doble click — Código

`ObraDetalle.tsx:176` · `ObraDetalle.tsx:253` · `PersonaDetalle.tsx:137`

`GUIDE_DESIGN` pide confirmación antes de todo cambio de estado importante. Borra roles y
observaciones del vínculo de un click. `correr()` no levanta ningún flag `enviando`, así que
dos clicks disparan dos veces. Desactivar sí tiene `ConfirmModal`; desvincular no.

Fix: `ConfirmModal` + optimistic update (la guía lo pide para desvincular).

### A7 · `min-h-[44px]` forzado también en desktop — Confirmado · **Parcial**

`ObrasView.tsx:114` · `EmpresasView.tsx:59` · `PersonasView.tsx:67` · `Buscador.tsx:89`
`RolesPicker.tsx:37` · `VincularEmpresaPanel.tsx:248` · `VincularPersonaEmpresaPanel.tsx:153`

`.tap-target` existe y es mobile-only (`globals.css:199`); tareas lo usa en 8 archivos. Obras
hardcodea el valor en 7 lugares, así que filas y chips quedan inflados también en escritorio.

**Parcial:** los 4 de los listados y el buscador salieron con C1 — era la misma clase que se
estaba reescribiendo, y dejarlos era tocar la línea dos veces. `RolesPicker.tsx:37` salió con A2.
Quedan `VincularEmpresaPanel.tsx:248` y `VincularPersonaEmpresaPanel.tsx:153`, que son B4.

---

## Medio

### M1 · Texto instructivo en 11px con medida de línea de ~200 caracteres — Confirmado

`PendientesView.tsx:69` · `PendientesView.tsx:187` · `AuditoriaView.tsx:83` · `AuditoriaView.tsx:128`

Los párrafos que explican qué es la cola de autorizaciones y qué registra la auditoría están en
`t-caption` —el tamaño más chico del sistema— y estirados a 1130px. Es el texto que le enseña
el módulo al usuario, puesto en el estilo de un pie de foto.

Fix: `t-body-m max-w-prose`.

### M2 · Auditoría: sujeto y predicado a 900px de distancia — Confirmado

`AuditoriaView.tsx:107-113`

`8/9/26, 12:44 p.m.  Admin` a la izquierda … `abrió la ficha de Martín Bianchi` pegado al borde
derecho, por el `flex-1` del nombre de usuario. Como log es ilegible: hay que barrer toda la
pantalla por renglón. Fix: una sola línea corrida a la izquierda.

### M3 · `.empty-state` no se usa en ningún lado del módulo — Confirmado

`ObrasView.tsx:95` · `EmpresasView.tsx:45` · `PersonasView.tsx:51` arman su propia card `p-8`.
`PendientesView.tsx:76` y `:196` usan un `<p class="t-body-m">` pelado. Las secciones de las
fichas resuelven el vacío con un `<p class="t-caption">` suelto. Cuatro tratamientos del mismo
estado dentro del mismo módulo.

La clase existe y la usan dashboard, tareas, usuarios y `error.tsx` — 8 archivos. Obras: cero.

### M4 · Cards anidadas sin contraste — Confirmado

`PendientesView.tsx:64` · `:179` · `AuditoriaView.tsx:78` · `:123`

`section.card` conteniendo `li.card`, las dos `bg-bg-surface`. La interna se distingue solo por
el borde, y las dos levantan sombra al hover. El design system dice que la elevación se
comunica con bordes, no con sombra. Fix: fila interna como `.row` + `border-b`, o `bg-subtle`.

### M5 · Hover de card en lo que no es clickeable — Código · Global

`globals.css:181` (`.card:hover { shadow-md }`) aplica a todas las `<li class="card">` estáticas
de las fichas y a las `<section class="card">`. Sombra al pasar = promesa de click que no
existe. Fix: mover el `:hover` a una variante `.card-link`, usarla solo en los `<Link>`.

### M6 · El filtro de usuario de Auditoría recorta media pantalla — Código

`AuditoriaView.tsx:60` — vive en una toolbar arriba de las dos secciones, pero solo filtra
accesos; transferencias lo ignora. Fix: moverlo dentro de la card de accesos.

### M7 · El filtro de días está en dos lugares distintos entre tabs hermanas — Confirmado

Arriba y global en Auditoría (`AuditoriaView.tsx:50`), adentro de la card "Ya resueltas" en
Pendientes (`PendientesView.tsx:183`). Además el activo es navy sólido, que en el sistema es un
botón primario de acción, no un filtro elegido — tareas usa `bg-brand-50` + borde.

### M8 · Dos columnas fijas en mobile, y valores largos sin `break-words` — Código

`ObraFormPanel.tsx` (3× `grid-cols-2` sin breakpoint) · `EmpresaFormPanel.tsx` ·
`PersonaFormPanel.tsx` · `ObraDatosGenerales.tsx:38` · `EmpresaDetalle.tsx:79` · `PersonaDetalle.tsx:75`

En panel `max-w-md` a 390px cada columna queda ~150px. Los `dd` de email y website no tienen
`break-words`, así que un mail largo se desborda de la card.

Fix: `grid-cols-1 sm:grid-cols-2` + `break-words` en los `dd`.

### M9 · Doble scrollbar en el panel de vincular — Confirmado

`Buscador.tsx:83` (`max-h-64 overflow-y-auto`) dentro del scroll del `RightPanel`: dos barras
a 30px una de otra.

### M10 · Toolbar desalineada — Código · Global

`.input` con `py-1.5` mide ~35px; `.btn` mide ~40px. Se ve en los tres listados del módulo.
También pasa en tareas, así que el arreglo es app-wide.

### M11 · La ficha pierde el estado codificado por color — Confirmado

En el listado el estado es un badge (`ObrasView.tsx:118`); en la ficha es un `dt/dd` gris
(`ObraDatosGenerales.tsx:39`). Fix: badge de estado —y de Pendiente— junto al `h2`.

---

## Bajo

### B1 · Observaciones sin etiqueta — Confirmado
`ObraDatosGenerales.tsx:56` — "120 unidades en tres etapas." flota bajo la grilla con el mismo
estilo que un valor, sin `dt` ni separador. Parece un dato huérfano.

### B2 · El modal "Descartar cambios" no atenúa el panel del que salió — Confirmado · Global
`Modal.tsx` dentro de `RightPanel.tsx`. La página de atrás sí se oscurece; el panel queda a
brillo pleno, así que la interrupción se lee a medias.

### B3 · El avatar del sidebar pisa el nombre — Confirmado · Global
`SidebarNav.tsx:71-85` — se lee `A…dmin`.

### B4 · Checkbox nativos del SO junto a pills estilizados — Código
`VincularEmpresaPanel.tsx:248` · `VincularPersonaEmpresaPanel.tsx:153`. En el mismo panel: los
roles son pills, las personas son checkbox sin estilar.

### B5 · Buscador mudo y botón que salta de ancho — Código
`Buscador.tsx:96` — `buscado` arranca en `false`, así que si la carga inicial vuelve vacía el
panel no dice nada. `Buscador.tsx:83` — el botón muta "Buscar" → "…" en vez de usar spinner.

### B6 · Ritmo inconsistente dentro de la ficha de obra — Confirmado
"Historial de responsables" es card (`ObraDetalle.tsx:268`); "Empresas" y "Personas" son
secciones peladas con filas card. Mismo nivel jerárquico, dos envases.

### B7 · `[7, 30, 90]` escrito cuatro veces, control de días duplicado — Código
`PendientesView.tsx:16` · `:183` · `AuditoriaView.tsx:10` · `:53` ·
`app/(erp-app)/obras/pendientes/page.tsx:6` · `app/(erp-app)/obras/auditoria/page.tsx:6`.
Fix: un `<FiltroDias>` en `components/ui/` y la constante única.

### B8 · `enviando` global en PendientesView — Código
`PendientesView.tsx:44-58` — aprobar una fila deshabilita el botón de todas, sin indicar cuál
está procesando.

### B9 · "No aparece — crearla" no parece un botón — Confirmado
`VincularEmpresaPanel.tsx:180` · `VincularPersonaPanel.tsx:143` — `btn-ghost` sin ícono ni
borde, se lee como texto de ayuda.

---

## Orden sugerido

1. ~~**C1 solo.**~~ Hecho. Hoy el módulo no se puede usar desde un celular: no muestra el
   nombre de lo que estás mirando. Es una agenda de obra que se usa en obra.
2. ~~**C2**~~ — hecho, salió del mismo refactor de fila.
3. ~~**A1 + A4 + A3**~~ — hecho, la ficha como bloque.
4. ~~**A2 + A5.**~~ — hecho.
5. **A6** — es corrección de comportamiento, no de estilo; puede ir en paralelo.
6. El resto es pasada de estilo: A7 + M3 + M5 juntos son mecánicos.

Lo marcado **Global** (A1, B2, B3, M5, M10) no se decide en `decisiones/obras.md`.
