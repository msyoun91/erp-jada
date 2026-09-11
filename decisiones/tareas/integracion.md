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
