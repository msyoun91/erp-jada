# Obras — UI

## UI — decisiones que no salen de la spec

**El contacto no va en el listado.** Ni teléfono ni email en la lista de personas: solo en la ficha, que pasa por `obras_ficha_persona()` y deja registro. Si mañana se agrega una columna de teléfono al listado, el registro de accesos deja de servir — ese es el punto a cuidar, no la ficha.

**La persona se elige por búsqueda, no por desplegable.** En `VincularPersonaPanel` no hay `<select>` con toda la agenda: hay un buscador que llama a `obras_buscar_duplicados_persona` y devuelve identidad mínima. Un desplegable poblado con `getPersonas()` funcionaría, pero volvería a exponer la lista completa a quien tenga el permiso de vincular.

**Vincular no exige ver primero.** La RLS de `obras_obra_persona` no pide que la persona sea visible: solo que la obra sea propia y exista `obras_vincular`. Es deliberado — es lo que hace usable la búsqueda de identidad mínima, y el acceso al contacto queda registrado igual.

**`getReferentes` va aparte de `getObra`.** Pedir la comisión dentro del mismo `select` le devolvería un array vacío a quien no tiene `obras_referentes`, indistinguible de "esta obra no tiene referentes". Separadas, la ficha sabe si no puede verlas o si no hay.

**El aviso de duplicados se dispara en `onBlur`, no al tipear.** Una consulta por tecla no aporta: el aviso solo tiene sentido con el nombre completo.

**El filtro por empresa/persona relacionada hace una consulta previa.** PostgREST no combina bien el `!inner` que haría falta con los embeds que se usan para contar empresas y personas en el listado. Dos viajes y código claro, en vez de un `select` que hay que descifrar.

**`useWatch` y no `watch()`.** `watch()` devuelve una función no memoizable y el React Compiler saltea la optimización del componente entero — lo marca el lint del repo. El resto del código usa `useController` por la misma razón.

**Sin filtro "responsable inactivo" en SQL.** La policy de `usuarios` no expone `activo` al embed, así que el filtro se resuelve en JS contra la lista de activos que ya se pide para el picker de transferencia.

---

## Los `<select>` de vinculación se fueron a buscador

Un desplegable con la lista entera deja de servir apenas la agenda crece, y en el caso de las personas además exponía el padrón completo a quien solo tenía que vincular una — el mismo motivo por el que `VincularPersonaPanel` ya buscaba en vez de listar.

`Buscador` es uno solo para los cuatro paneles. Carga la primera tanda al abrir **salvo** cuando busca personas: ahí la lista vacía es deliberada, la agenda se busca y no se lista.

La función que se le pasa tiene que ser estable entre renders (definida a nivel de módulo, no inline): el efecto de la primera carga la toma como dependencia. Y el `setState` va en el callback de la promesa, nunca en el cuerpo del efecto — el lint del repo lo corta.

---

## Enlaces externos: copiar, no inventar

El pedido de "accesos directos a la ficha" no necesitaba nada del servidor. Las URLs ya eran estables y el middleware ya devuelve al destino después del login (`next`), así que lo único que faltaba era poder sacar la URL de la app sin copiarla de la barra: un botón en las tres fichas.

Nada de tokens ni de links públicos — la ficha sigue exigiendo sesión y permiso, que es lo que hace que el enlace se pueda mandar por WhatsApp sin pensarlo dos veces.

---

## La fila de listado se escribe una vez y cambia de display

Los listados eran una fila `flex-wrap` con el nombre en `min-w-0 flex-1 truncate` y la metadata
como items que no se encogen. Es la peor repartición posible del ancho: el único que cede es el
dato que identifica la fila, así que a 390px "Complejo Costa Norte" quedaba en `Co…` y la ficha
titulaba `C.`. En escritorio el mismo `flex-1` empujaba los chips contra el borde derecho, a
distinta altura horizontal en cada fila — la lista no se podía escanear en vertical.

**Decidido:** abajo de `md` la fila es `flex-col` —nombre arriba, metadata abajo— y arriba es
`md:grid` con anchos de columna fijos.

El marcado se escribe **una sola vez**: el envoltorio de la metadata lleva `md:contents`, así
que en mobile es la línea que envuelve y en escritorio se disuelve y sus hijos pasan a ser
celdas de la grilla. La alternativa era duplicar el bloque con `hidden`/`md:hidden`, que es el
mismo dato escrito dos veces y dos lugares donde olvidarse de un campo.

Consecuencia que hay que respetar: **las celdas opcionales se renderizan siempre**. Un
`{o.localidad && …}` corre las columnas de las filas sin localidad. Van con
`className={valor ? "truncate" : "hidden md:block"}` — presente en la grilla, ausente en la
línea de mobile, donde una celda vacía dejaría un hueco de `gap`.

`PersonasView` no entró: su fila es nombre + badge, no hay metadata que le coma el ancho ni
columnas que alinear. Una grilla de una columna es la fila que ya tenía.

Lo mismo pero con `basis-full sm:basis-0 sm:grow` en las filas de Pendientes, que llevan botones
intercalados. No `sm:basis-auto`: `flex-1` y `basis-auto` son familias distintas de utilidades
de Tailwind y quién gana lo decide el orden en que se generan, no el orden en el `className`.
La base se fija explícita.

~~Las filas de las fichas usan el mismo `basis-full`~~ — **superado**: con el `OverflowMenu`
puesto ya no hay botones intercalados que las obliguen a envolver. Ver *Las acciones de la
ficha viven en el `OverflowMenu`*.

---

## Las acciones de la ficha viven en el `OverflowMenu`

En las tres fichas se leía `Constructora  Editar  Quitar` dentro de la misma línea: el primero
es un dato (`t-caption`) y los otros dos botones (`btn-ghost`, `text-tertiary`). Mismo gris,
mismo tamaño, misma línea — en mobile envolvían, así que una fila de persona eran cuatro
renglones de gris indistinguible. Y arriba, "Desactivar" en rojo sólido era el elemento más
brillante de la pantalla, por encima del nombre de la obra que se estaba mirando.

**Decidido:** el patrón que ya usan tareas y usuarios, sin inventar nada. La fila es un bloque
de texto `min-w-0 flex-1` —nombre en su renglón, metadata y badges abajo— y un `OverflowMenu`
`shrink-0` a la derecha. En el encabezado queda "Editar" a la vista, que es la acción de la
ficha, y el resto —copiar enlace, transferir, desactivar— entra al menú. Desactivar va con
`destructive` e ícono `Archive`, igual que en Proyectos y Plantillas.

**Un solo ítem rojo por menú.** "Quitar referente" saca la comisión y podría pintarse igual,
pero con dos rojos en la misma lista el que importa deja de destacar.

**El menú del encabezado no se esconde por permisos.** "Copiar enlace" no tiene gate, así que
siempre hay al menos un ítem y nunca aparece un `⋯` que abre una lista vacía — la misma regla
que Proyectos resolvió con "Ver tareas". En las filas es al revés: si el usuario no tiene
`obras_vincular` ni `obras_referentes` no hay acciones, y ahí el botón directamente no se
renderiza.

**`CopiarEnlace` dejó de ser componente.** Como ítem de menú lo que hace falta es la función,
no el botón, así que pasó a `modules/obras/copiarEnlace.ts`. El feedback ya era un toast, así
que no pierde nada al ejecutarse desde un menú que se cierra al click.

Las filas sin acciones —personas y obras en las fichas de empresa y persona— toman la misma
forma de dos renglones aunque no lleven menú: si no, dentro del mismo módulo conviven dos
maneras de escribir la misma fila.

~~**Queda pendiente A6.**~~ — resuelto: ver *Desvincular pregunta antes, y con eso deja de
dispararse dos veces*, más abajo.

---

## El rol elegido se marca con borde, no con relleno

`RolesPicker` pintaba el rol seleccionado con `badge-brand` y el no seleccionado con
`badge-neutral`. En light son `#EBF2FD` y `#EBF0F8`: dos grises-azules que no se distinguen, así
que la única señal de "elegido" quedaba en el color del texto. En dark el texto azul salvaba la
lectura, pero seguía sin borde. Es el control central de los cuatro paneles de vinculación y se
usa con el celular al sol.

**Decidido:** la forma del toggle de `TareasListaView` — `border-brand-500 bg-brand-50
font-semibold text-brand-700` contra `border-border text-text-tertiary`. El borde es la señal
que sobrevive al contraste bajo; el relleno acompaña.

Dejó de ser `.badge`: la clase fija el texto en 11px y el `min-h-[44px]` que tenía encima
producía pills de 44px de alto con letra de pie de foto. Ahora es `tap-target t-caption`, que da
los 44px **solo** en mobile —`.tap-target` es `min-height` dentro del media query de
`globals.css`— y en escritorio deja el chip del tamaño de su contenido.

No lleva check ni ícono: con borde y peso la diferencia ya se lee, y un ícono adentro de un chip
de multi-selección compite con el label por el ancho del panel `max-w-md`.

---

## La tab activa se resuelve por prefijo más largo

`ModuleTabs` comparaba `pathname === tab.href`. En `/obras/{id}`, `/obras/empresas/{id}` y
`/obras/personas/{id}` ninguna tab quedaba encendida: las cinco apagadas, sin decir dónde estás.
El componente es compartido, pero obras es el único módulo con páginas de detalle propias
—tareas resuelve el detalle con paneles—, así que el bug solo se manifestaba acá.

**Decidido:** activa es la tab cuyo `href` es el prefijo más largo del `pathname`. Hace falta el
"más largo" porque `/obras` es prefijo de todas las demás: sin desempate, `/obras/empresas/{id}`
encendería Obras y Empresas a la vez.

La comparación es `pathname === href || pathname.startsWith(href + "/")`, con la barra: un
`startsWith` pelado haría que `/obras` matcheara una futura `/obrasocial`.

La alternativa era que cada `layout.tsx` pasara el código de la tab activa. Son tres layouts
—cuatro con el que venga— repitiendo lo mismo, y el layout no conoce el `[id]`: el dato ya está
en el `pathname`. Se resuelve donde se lee.

Se agregó `aria-current="page"` en la activa, que es lo que faltaba para que el estado exista
también fuera de lo visual.

---

## Desvincular pregunta antes, y con eso deja de dispararse dos veces

"Quitar de la obra" borraba el vínculo —con sus roles y sus observaciones— de un click, sin
preguntar. `GUIDE_DESIGN` pide confirmación antes de todo cambio de estado importante, y
desactivar ya la tenía; desvincular no. Además `correr()` no levantaba ningún flag, así que dos
clicks disparaban dos veces la misma acción.

**Decidido:** las cuatro acciones destructivas de fila —quitar empresa, quitar persona, quitar
referente, y quitar de la empresa en la ficha de persona— pasan por `ConfirmModal`, con copy que
nombra lo que se pierde y `confirmLabel="Quitar"`.

El doble click se arregla solo con eso: `ConfirmModal` ya tiene su propio `enviando` y deshabilita
los dos botones mientras espera el `onConfirm`. No hace falta un flag por fila — hace falta que la
llamada viva adentro del modal.

Como las filas se renderizan en un `.map()`, no puede haber un booleano por fila. La ficha tiene
un solo estado `confirmando` con el objeto de lo que se está por confirmar (título, mensaje,
label, acción, texto del toast), y el `desactivando` que ya existía se absorbió ahí: una sola
confirmación por ficha, un solo `<ConfirmModal>` al final.

`EmpresaDetalle` quedó con su `desactivando` booleano. No es una segunda manera de hacer lo
mismo: es el caso simple, sin ninguna acción destructiva de fila, y ahí el objeto de estado no
compra nada.

---

## Sin optimistic update: la auditoría pedía algo que el proyecto no hace en ningún lado

El hallazgo A6 pedía "`ConfirmModal` + optimistic update (la guía lo pide para desvincular)".
La primera mitad se hizo. La segunda no, y la premisa estaba mal verificada.

No hay un solo `useOptimistic` en la app. Desactivar obra, persona, empresa y usuario —todas
"acciones clave" según la misma sección de la guía— esperan la server action y se refrescan por
`revalidatePath`. Hacerlo acá lo convertiría en el primer y único optimistic del proyecto, en una
acción de fila de un módulo, y obligaría a bajar a estado de cliente tres listas que hoy llegan
como props del servidor.

Lo que la guía pide de fondo —que el usuario nunca se quede preguntando si algo funcionó— ya lo
da `ConfirmModal`: botón deshabilitado mientras espera, después toast de éxito o de error.

Si algún día se agrega optimistic, se agrega app-wide y no acá: es una decisión de
`decisiones/global/ui.md`, no de este módulo.

---

## El vacío de una sección no se dibuja como el vacío de una página

`.empty-state` es una caja punteada de `p-[60px]`. A nivel de vista está bien: es lo único en
pantalla. En una ficha hay tres o cuatro secciones vacías a la vez —Empresas, Personas, Obras—
y cuatro cajas de 180px son media pantalla de nada.

**Decidido:** misma clase, padding pisado (`empty-state p-8`) en los seis vacíos de sección de
las tres fichas. No una clase nueva: lo que el hallazgo M3 pedía era que el estado vacío se
dibujara igual en todo el módulo —había cuatro tratamientos distintos—, y con el padding pisado
se dibuja igual. Una `.empty-state-sm` sería el quinto.

---

## El estado va en el encabezado, "Pendiente" no

`BADGE_ESTADO` vivía en `ObrasView` y la ficha mostraba el estado como `dt/dd` gris. Ahora el
mapa está en `types.ts` al lado de `LABEL_ESTADO` y lo leen los dos.

En la ficha, el `dt/dd` "Estado" salió de la grilla al entrar el badge: el mismo dato dos veces
en la misma pantalla es la duplicación que la regla de fuente única prohíbe, y el badge es la
forma que ya tiene en el listado.

**El badge "Pendiente" no se agregó, aunque la auditoría lo pedía.** `EstadoPendiente` ya
renderiza un bloque entero dos renglones abajo, con el motivo y qué se puede hacer. En el
listado el chip existe porque no hay lugar para el bloque; en la ficha sí lo hay, y repetir la
palabra arriba no agrega nada.

---

## El estado se filtra con chips, no con un `<select>`

El listado de Obras filtraba estado con un `<select>` "Todos los estados". Con el reloj comercial
en el enum (`sql/046`, seis valores) el vendedor quiere ver de un vistazo cuántas obras tiene en
cada tramo, y un desplegable esconde eso hasta que se abre.

**Decidido:** fila de chips arriba del listado — `Todas 14 · Idea 6 · En cotización 0 · …`. Cada
chip cuenta **sobre lo que dejan pasar los otros filtros** (texto, tipo), no sobre sí mismo, así
el número es lo que se ve al tocarlo. Misma forma que el toggle de `RolesPicker` (`chipEstado()`
local): borde como señal, relleno acompaña. El estado sigue en `useState`, no en la URL —
`AlcanceToggle` es el único filtro del módulo que viaja en `?`, y es porque afecta la query del
server; este no.

El filtro de **tipo** se quedó como `<select>`: ocho valores que nadie mira por conteo, y una
segunda fila de ocho chips compite con la de estado.

El badge "Ajena" salió de los tres listados en la misma pasada: con el `AlcanceToggle` visible,
marcar cada fila ajena era ruido. El "Ajeno" del `BuscadorGlobal` se queda — ahí la fila
enmascarada no es link y el badge es lo que lo dice.

**"Perdida" y "Terminada" quedan fuera de "Todas"** (pedido del usuario, 2026-09-14; "Perdida" ya
estaba así sin escribir). Lo cerrado no ocupa la vista de trabajo: se ve tocando su chip, que sigue
contando. `OCULTAS_POR_DEFECTO` en `ObrasView.tsx`; el número de "Todas" es lo que muestra.

---

## El filtro vive donde llega su efecto

Auditoría y Pendientes son tabs hermanas y tenían el filtro de días en lugares distintos. La
tentación era unificar la posición.

**Decidido: no.** En Auditoría el `?dias=` acota las dos secciones (accesos y transferencias),
así que es de la página y va arriba. En Pendientes acota solo "Ya resueltas" —la cola muestra
todo lo que espera, sin ventana— así que vive adentro de esa card. Subirlo diría que también
filtra la cola.

Por el mismo criterio bajó el filtro de usuario de Auditoría, que estaba en la toolbar de la
página filtrando una sola de las dos secciones.

Lo que sí se unificó es el control: `components/ui/FiltroDias.tsx`, que además exporta
`DIAS_OPCIONES` — el array `[7, 30, 90]` estaba escrito seis veces, dos de ellas en las páginas,
donde decide si un `?dias=45` escrito a mano se acepta o cae al default.

---

## `Dato` y `Observaciones` son del módulo, no de `components/ui/`

El par `dt/dd` de las fichas estaba escrito nueve veces con la misma forma. Salió a
`modules/obras/components/Dato.tsx` y no a `components/ui/`: la regla es que algo sube cuando lo
usan 2+ módulos, y esto lo usan tres fichas del mismo.

`Dato` recibe `React.ReactNode` y no `string | null` porque dos valores no son texto: teléfono y
email de la ficha de persona son `<a>` de `tel:` y `mailto:`, y la localidad de la empresa
concatena la provincia. El guard es `if (!valor) return null`, que cubre el `""` que devuelve un
campo vacío igual que el `null` de la columna.

---

## El breadcrumb reemplaza al botón "← Personas"

Del prototipo `obsoletos/prototipo-obras-tareas.html` — lo aprovechable sin SQL.

El encabezado de las tres fichas era `[← Personas] Nombre`: la vuelta al listado es navegación,
pero estaba escrita como `btn btn-ghost btn-sm`, o sea con el mismo peso visual que "Editar", a
dos centímetros de él. `Breadcrumb.tsx` la baja a texto: `Personas / Juan Pérez`, padre en
`t-caption` y nombre en `t-h2`, en una sola línea.

**No se copió el breadcrumb del prototipo tal cual.** Ahí la ruta es
`Agenda de Obras / Personas / Juan Pérez` con el `<h1>` del módulo y el nombre repetidos abajo.
Dos problemas: el nombre queda dos veces en la misma pantalla —la duplicación que ya se prohibió
con el badge de estado— y el primer segmento no es un padre: `/obras` es la tab Obras, hermana de
Personas, no la raíz del módulo. La ruta real de una ficha tiene dos niveles y eso es lo que se
dibuja.

Vive en `modules/obras/components/`, no en `components/`: lo usan tres fichas del mismo módulo,
mismo criterio que `Dato` y `Observaciones`. El link lleva `tap-target` porque dejó de ser un
`.btn` y con él perdió el mínimo de 44px en mobile.

Lo que el prototipo propone y **no** se implementó: el enlace obras↔tareas (chips de persona y
obra en la tarea, "Acciones rápidas" de la ficha, el historial de llamadas como tareas
completadas). Necesita columnas nuevas en `tareas` y es una decisión de modelo, no de UI.

---

## La barra va en la línea del título, no adentro de una tab

Misma regla que el filtro de días: el control vive donde llega su efecto. El
buscador cruza las tres entidades, así que ponerlo abajo de las tabs diría que busca
en la que está abierta.

El bloque obligatorio de CLAUDE.md —`<h1>` con ícono y nombre antes de las tabs—
queda igual; lo que cambia es que ahora comparte renglón con la barra, y el `mb-4`
pasó del `<h1>` al envoltorio. En mobile la barra se lleva su propio renglón por
`flex-wrap`, sin media query.

Vive en el `layout.tsx`, así que sobrevive a la navegación entre tabs y a abrir una
ficha. Se limpia sola al elegir un resultado: dejar el texto puesto haría que el
panel se reabra al volver.

**El resultado fuera de alcance no es un link.** La persona que no se ve se lista
con badge y el nombre de quien la cargó —"la cargó Ana"— y no lleva a ninguna parte:
su ficha cortaría con 404 y la fila estaría prometiendo algo que no pasa. El nombre
del que la cargó es el mismo criterio del aviso ciego, que devuelve el del
responsable: alcanza para ir a preguntar, no para leer la agenda del otro.

**Reusa `SearchInput` sin tocarlo.** `Escape` y el foco se manejan en el envoltorio
—los dos eventos burbujean— así que el componente compartido no crece props para un
solo consumidor. El panel es un `.card` con el padding pisado, como los vacíos de
sección.

**Con debounce, no en `onBlur`.** El aviso de duplicados espera el `onBlur` porque
solo tiene sentido con el nombre completo; un buscador es lo contrario, así que
busca mientras se tipea, 250ms después de la última tecla. El `setState` va adentro
del `setTimeout` y del callback de la promesa, nunca en el cuerpo del efecto — el
lint del repo corta el síncrono.

**El piso de 2 caracteres está en los dos lados.** En el cliente evita el viaje, en
la base es la regla — la misma repartición que Zod y `safeParse`.

**No hay total de resultados.** La guía lo pide para listados, pero acá la función
devuelve 5 por tipo y contar el resto sería una segunda consulta para un número que
no se puede usar. En su lugar el panel dice que muestra los primeros de cada tipo y
que la búsqueda se puede afinar.

---

## La sección Tareas de las fichas

Obra, empresa y persona muestran sus tareas relacionadas. El porqué y la regla de visibilidad están en `decisiones/tareas/integracion.md` → *Tareas relacionadas con obras, empresas y personas*; la forma actual (el panel se abre sobre la ficha, sin ir a la Lista) está en la misma carpeta → *Las tareas de una ficha se abren sobre la ficha (sin SQL)*.

Acá, solo la forma visual: mismo lugar que antes — al final de la ficha, antes del historial de responsables — mismo encabezado (h3 "Tareas", botón secundario "Nueva tarea"). `ObraDetalle`/`EmpresaDetalle`/`PersonaDetalle` reciben la sección entera como `seccionTareas: ReactNode` (la arma `TareasDeRegistro`, de `modules/tareas`) y solo la renderizan — no conocen su contenido. Obras sigue sin importar Tareas: quien compone es la page.

---

## El ensayo antes de guardar el estado (sin SQL)

Fase E de `PLAN_TAREAS_VINCULOS.md`, sobre `obras_ensayar_estado` (`sql/063`). En `ObraFormPanel`,
cambiar el estado de una obra **existente** dispara el ensayo antes de guardar de verdad: si el
cambio haría disparar una plantilla que deja a alguien sin poder abrir lo relacionado,
`CompartirAccesoPanel` pregunta primero (catálogo en `decisiones/global/ui.md`). Detalle completo
—por qué solo al editar y no al crear, por qué "si el ensayo falla se guarda igual"— en
`decisiones/tareas/visibilidad.md` → *Compartir al asignar: la pregunta*.
