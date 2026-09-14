# Integración con otros módulos

## Tareas generadas por otro módulo = `origen_app` + `origen_punto` (sin SQL)

Pedido: *"algunos módulos generan tareas en el módulo de tareas, con leyenda
'generado por X' que me lleva a realizar la acción del módulo"*.

No hace falta nada nuevo: las dos columnas existen desde `sql/005` y
`crearTarea` ya las acepta vía `crearTareaSchema`. Un módulo que quiera generar
trabajo llama a la misma server action que la UI:

```ts
await crearTarea({ titulo, responsable_id, asignados: [...], origen_app: "compras", origen_punto: "/compras/oc/123" })
```

Sin tabla de "generadores", sin registry, sin cola. La tarea generada es una
tarea igual a todas — misma RLS, mismo panel, misma auditoría. El módulo origen
no queda acoplado a tareas más allá de un import de la action.

**`origen_punto` solo acepta rutas internas** (`^/(?!/)`). Lo escribe quien
inserta la fila y RLS no valida su contenido, así que sin el corte un
`javascript:` o un `//host-ajeno` llegarían intactos al `href`. Validado en
`crearTareaSchema` (escritura) y otra vez en `origenHref` (`modules/tareas/origen.ts`,
render): duplicación permitida porque es límite de seguridad, no lógica de
negocio. `origen.test.ts` cubre los cuatro casos hostiles.

**El link vive solo en el panel, no en la isla.** La isla entera es clickeable
(`Isla.onAbrir`): un `<Link>` adentro pelea con ese click y obliga a
`stopPropagation`. La isla muestra `origen_app` como texto dentro de la línea de
contexto; el panel — donde ya viven todas las acciones — lo muestra como link.
Dos clicks para llegar al módulo; se acorta si molesta.

**`origen_app` es texto libre, no enum.** Un enum obligaría a migración por cada
módulo nuevo que genere tareas. Se muestra tal cual llega.

## Deep link a una tarea desde la notificación (sin SQL)

Pendiente del `BACKLOG.md`: el aviso "te asignaron X" llevaba a `/tareas` a
secas — la Lista abre el panel por estado, no por URL, así que había que
buscar la tarea a mano.

**Un query param leído una sola vez, no una ruta por id.** `tarea_asignada`
(`sql/038`) solo notifica a `NEW.usuario_id`: quien abre el link siempre está
asignado a esa tarea, así que nunca hace falta resolver visibilidad — a
diferencia de obra/empresa/persona, que sí tienen ruta propia por id.
`NotificacionesBell` arma `/tareas?tarea={id}`; `TareasListaView` lee
`?tarea=` una sola vez al montar (`useSearchParams`, sin `Suspense`: la ruta
ya es dinámica por los datos de sesión, mismo patrón que `AlcanceToggle`) y lo
saca de la URL en el mismo efecto — refrescar la página no debe reabrir el
panel que el usuario ya cerró.

**Mismo mecanismo que `hiloConvertido`, sin la reactividad que ese caso
necesitaba.** `TareaCard` gana `autoAbrir?: boolean` (inicializa
`detalleAbierto`, no lo sincroniza después — el valor no cambia una vez
montado). `hiloConvertido` sí necesita reaccionar a un cambio de prop en vivo
porque el hilo puede nacer antes o después de que el padre pida abrirlo; acá
la tarea ya existe en los datos que trajo el server, así que no hay carrera
que resolver.

**La tarea puede ser suelta o un paso de hilo — dos caminos para el mismo id.**
`TareasListaView` pasa `autoAbrir` directo a la `TareaCard` de nivel superior
si el id matchea una suelta, y `autoAbrirTareaId` a `HiloCard` si matchea un
paso; `HiloCard` lo reenvía a la `TareaCard` anidada correcta. Como
`notificar_tarea_asignada` solo avisa al asignado, el paso cae siempre del
lado `esPropia` — nunca hace falta expandir los ajenos para encontrarlo.

**Si la tarea objetivo ya está terminada, `ocultarTerminadas` arranca
destildado.** Si no, el filtro por defecto la esconde y el deep link no
abriría nada — mismo espíritu que "no se ofrece un camino que termina en
error".

**Si la tarea no aparece en los datos que trajo el server** (RLS la ocultó,
el id no existe más), no pasa nada: la URL se limpia igual y el usuario queda
en `/tareas` como antes del cambio. No es un caso a manejar — es el mismo
comportamiento que había.

## El link de origen se hereda dentro del hilo (`sql/058`)

Pedido del usuario el 2026-09-14: "deep link hereda deep link cuando tarea a hilo". Convertir una tarea en hilo la dejaba con su link, pero el hilo no lo mostraba, y "Crear siguiente paso", "Agregar tarea" o una plantilla usada en ese hilo creaban tareas sin él.

**El hilo no guarda link: es el de su tarea activa más antigua que tenga uno.** Una columna en `tareas_hilos` sería una segunda copia del mismo dato, a mantener al convertir y al deshacer la conversión. La tarea convertida es la más antigua del hilo, así que su link pasa a ser el del hilo sin escribir nada.

**Hereda un trigger, no cada camino.** `trg_heredar_origen_hilo` (BEFORE INSERT, INVOKER) completa `origen_app`/`origen_punto` cuando la tarea nace en un hilo sin los suyos: cubre `crear_tarea`, `usar_plantilla` y lo que venga. La que trae su propio link (la de un disparo) lo conserva. INVOKER alcanza: quien crea en el hilo ya ve sus tareas.

- Solo al nacer: mover una tarea que ya existe a otro hilo no le cambia el link.
- El panel del hilo muestra el link con `OrigenLink`, el mismo componente que ahora usa el panel de la tarea. Repite en TS "la más antigua con link" solo para mostrarlo. La isla sigue sin link (*El link vive solo en el panel*, arriba).

**Tests:** `sql/tests/origen_heredado.sql` 4/4 (nuevo).

Archivos: `sql/058`, `OrigenLink.tsx`, `TareaDetailPanel.tsx`, `HiloDetailPanel.tsx`.

## Tareas relacionadas con obras, empresas y personas (`sql/059`)

Pedido del usuario el 2026-09-14: ver en la ficha de una obra, empresa o persona las tareas relacionadas, crear una desde ahí y relacionar una tarea al crearla. También es la base de lo que sigue en `BACKLOG.md` (roles en plantillas, compartir al asignar), que necesita saber con qué registros está relacionada una tarea.

**Un solo vínculo para todo: `tareas_vinculos`.** Ya existía para los disparos (`sql/055`); deja de exigir plantilla, y empresa y persona entran a `entes` sin estado: se vinculan, no disparan. `origen_app`/`origen_punto` sigue diciendo quién generó la tarea, pero no sirve como relación: es uno solo y es texto.

**"Lo ve" y "cómo se llama" son la misma función.** `etiqueta_registro` es INVOKER y usa `obras_etiqueta`, que ya devolvía NULL para lo que no ves (la bandeja se apoya en eso). Con ella se decide qué se puede vincular (la policy), qué chip se muestra (`vinculos_de_tareas`) y si una ficha lista tareas (`tareas_de_registro`), sin copiar la regla de visibilidad de Obras.

- **Dos altas en la misma policy.** Con plantilla, solo adentro de un trigger, como antes. Sin plantilla, sobre una tarea que ves y un registro que ves. `crear_tarea` inserta los vínculos antes que los asignados, así `es_siembra_tarea` deja vincular la tarea que se crea para otro.
- **Desvincular** (`activo = false`) solo lo vinculado a mano: apagar el vínculo de un disparo lo dejaría volver a disparar. Un vínculo activo por (tarea, registro).
- **Quien ve la tarea pero no el registro no ve el chip**, y en la ficha de un registro que no ve no hay tareas.

**Obras no importa Tareas.** La sección Tareas de las tres fichas (`TareasRelacionadas`, en obras) lee `tareas_de_registro` y lleva a la Lista por link: `?tarea=` abre la tarea y `?nueva=obra:{id}` abre el form ya relacionado; al cerrarlo se vuelve a la ficha. Descartado: montar `TareaFormPanel` en la ficha, que arrastra el contexto entero de Tareas (proyectos, miembros, usuarios). La sección aparece con la vista `tareas_lista`: sin ella los dos links terminan en 404.

- `?tarea=` a una tarea ajena: la Lista arranca sin el recorte por usuario, porque con él la tarea no aparece y no se abre. Quien no tiene `tareas_gestionar_ajenas` no tiene el selector para volver, así que suma "Ver solo lo mío".
- Las etiquetas de estado de tarea suben a `lib/tareas.ts` (`tareaLabels.ts` las re-exporta), como las de obra subieron a `lib/entes.ts`.
- En el panel de la tarea, "Relacionar" busca con `buscar_registros`: el buscador global de Obras, sin lo que no se puede abrir. Si un chip tiene la misma ruta que `origen_punto` (la tarea de un disparo), el "Generado por obras — ir" no se repite.

**Tests:** `sql/tests/vinculos_tareas.sql` 14/14 (nuevo). `origen_heredado.sql` 4/4 sin tocar, con la firma nueva de `crear_tarea` (el parámetro tiene DEFAULT).

Archivos: `sql/059`, `lib/tareas.ts`, `lib/entes.ts`, `RelacionarRegistro.tsx`, `VinculosChips.tsx`, `TareaFormPanel.tsx`, `TareaDetailPanel.tsx`, `TareasListaView.tsx`, `tareas/page.tsx`, `TareasRelacionadas.tsx` y las tres fichas de Obras.
