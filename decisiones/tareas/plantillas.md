# Plantillas

## Plantillas de sistema y privadas, tres tipos (`sql/053`)

Pedido de usuario, en dos fases acordadas: esta (plantillas completas, usadas a mano desde Tareas) y la de disparadores desde otros módulos, que está en `BACKLOG.md`.

**Dos alcances; la función nueva es la del pedido.** "Las plantillas de sistema son administradas por aquellos que tienen función plantillas de sistema": `tareas_plantillas_sistema`, submódulo-función de la vista `tareas_plantillas`. La privada la ve, modifica y usa solo su dueño. Backfill de la función a quien tenía la vista, que hasta acá administraba todas — mismo criterio que `sql/013`/`014`.

**El alcance no cambia después de crear.** `alcance` y `creado_por` quedan fuera del `GRANT UPDATE`: una privada no se vuelve de sistema ni cambia de dueño por PostgREST, y `puede_gestionar_plantilla` puede leer la fila vieja en el `WITH CHECK` sin tener que mirar la nueva.

**Tres tipos, y el de proyecto con hilos adentro** (elegido por el usuario frente a "proyecto + referencias a otras plantillas" y "proyecto + tareas sueltas"). Los hilos viven en `tareas_plantillas_hilos` y cada paso apunta al suyo: ni un texto de agrupación repetido en cada paso (un typo parte el hilo) ni plantillas anidadas (desactivar una rompería la que la contiene).

**Miembros y asignados de la plantilla son arrays**, no tablas: es configuración que se copia al usarla, no una relación viva. Lo que pudo cambiar desde que se guardó (usuario desactivado, ya no miembro) se revalida al usar.

**Quien use la plantilla es un asignado más.** En la base, `incluir_ejecutor` + `responsable_id` NULL; en el form, el valor `EJECUTOR` dentro de los mismos arrays, para que el picker sea el mismo de siempre. El mapeo es `pasoPlantillaDb()` en `types.ts` y lo llama la action: es representación, no regla.

**Guardar reemplaza los pasos.** Nada referencia a un paso de plantilla (usar copia), así que ids estables no compraban nada: `guardar_plantilla` desactiva lo activo e inserta lo nuevo, en una transacción. Antes eran dos a cuatro statements de `actions.ts` sin atomicidad y un diff por paso.

**Usar es `SECURITY INVOKER`: decide la RLS de quien la usa**, igual que si armara todo con los formularios (crear proyecto pide `tareas_proyectos_crear`, asignar a otro `tareas_asignar`, recibir ser miembro). Hacerla `DEFINER` obligaba a copiar esas reglas adentro. En la fase 2 el disparo automático sí va a necesitar que la autoridad sea la plantilla; se decide ahí.

**Si un asignado no puede recibir el paso, se descarta; si no queda nadie, el paso va a quien la usa con una nota.** Decisión del usuario (preguntado por el caso automático: "se crea para quien dispara"); se aplica igual al uso manual para que la regla sea una sola. Si quedan otros asignados no hay nota: el paso sigue en manos de alguien que la plantilla eligió. `usar_plantilla` devuelve cuántos cayeron y el toast lo dice. La vista previa de "Usar" muestra lo que la plantilla pide y explica la regla en texto — no calcula quién va a recibir, porque esa regla vive en la función.

**Vencimiento tras el paso anterior: una columna y dos triggers.** `tareas.vence_dias_tras_previo`; la fecha queda NULL hasta que el previo se completa y ahí la ponen los triggers — única fuente, `editar_tarea` no la pisa (corregido en la misma tanda: primero la sobrescribía con lo que el form traía oculto). Reabrir el previo la vuelve a NULL: el siguiente vuelve a estar bloqueado y un plazo corriendo sobre algo bloqueado mentiría. En el primer paso de una cadena vale como "desde la creación". Se ofrece también en "Crear siguiente paso", no solo en plantillas.

**Dos defectos latentes que las plantillas iban a pisar**, arreglados en la misma migración:

- *Siembra de asignados.* Crear una tarea con otro como responsable daba `42501` a quien tenía `tareas_asignar` sin `gestionar_ajenas` (`tareas_asignados_insert` pedía ser el responsable). Nadie lo sufría porque hoy la función solo la tiene quien tiene las dos. Se reprodujo en una transacción revertida antes de tocar nada. Salida: `es_siembra_tarea()`, el creador carga asignados mientras la tarea no tuvo **nunca** ninguno — "nunca" para no reabrir el hueco de `sql/013`.
- *`created_at` con `now()`.* Es el orden de los pasos en la Lista y `now()` es la hora de la transacción: la cadena que crea una función quedaba toda con el mismo instante (desde `sql/023`). Pasa a `clock_timestamp()`.

**UI.**

- **Asignados por buscador** (pedido): `SelectorUsuarios` — chips con ×, búsqueda y hasta seis sugerencias visibles sin foco (sin popover que abrir y cerrar); Enter agrega la primera en vez de mandar el form. Lo usan `AsignadosPicker` (nueva tarea, reasignar, pasos de plantilla) y los miembros de `ProyectoFormPanel` y de la plantilla de proyecto: misma pregunta, misma cara.
- `AsignadosPicker` nombra sus campos por prop (`pasos.2.asignados`) y suma "Quien la use" con `conEjecutor`.
- `Segmentado.tsx`: tercera copia del segmented de la Lista, extraída al módulo.
- La vista Plantillas monta `TareasContextoProvider` (el picker y el destino de "Usar" lo necesitan).
- El editor pliega cada paso en una línea de resumen y lo abre solo si tiene error. Cambiar de tipo reacomoda en vez de tirar: hilo → proyecto envuelve la cadena en un hilo, proyecto → hilo la aplana, → tarea conserva el primer paso y avisa.
- "Usar" de una plantilla de proyecto se deshabilita sin `tareas_proyectos_crear` y lo dice en texto (en touch no hay tooltip).

**Tests** (`sql/tests/`): `plantillas.sql` 22/22 (nuevo); `atomicidad_tareas.sql` 15/15 — los casos 09-13 pasaron a `usar_plantilla`: el 12 cambia de "rechazo" a "se descarta y queda ADMIN", y el 13 prueba que una cadena rechazada en el paso 2 no deja el 1, exigiendo `42501` (un `TA008` querría decir que falló antes de empezar); `atomicidad_edicion_tareas.sql` 18/18; `rls_miembros_asignables.sql` sin cambios de resultado con la siembra (en todos sus casos el creador es también responsable).

## Plantillas disparadas por estado (`sql/055`)

Fase 2 de la anterior, decidida con el usuario el 2026-09-14. Un solo ente para probar la idea: la obra (su ejemplo: pasa a en ejecución → "Cobrar obra X").

**El disparador es genérico: un registro entra a un estado.** La plantilla elige ente y estado destino (`disparo_ente`, `disparo_estado`), sin estado de origen: de `idea` directo a `en_ejecucion` también hay que cobrarla, y crear la obra ya en ese estado cuenta como entrar. Cada módulo registra su ente en `entes` (módulo, submódulo que pide, enum de estados, datos citables, ruta) y cuelga un trigger de una línea sobre su columna de estado. Obras no suma funciones ni botones.

**Corre como quien cambia el estado, si la tiene activada.** `disparar_plantillas()` es `INVOKER` y llama a `usar_plantilla`, igual que usarla a mano: las tareas nacen con su RLS. Por eso no hay excepción de autorización, y la activación es por usuario (`tareas_plantillas_activaciones`): la de sistema arranca apagada, la privada prendida para su dueño. Descartado: "la autoridad pasa a ser la plantilla", con `SECURITY DEFINER` revalidando.

- **Guarda de `current_user`.** Si el cambio de estado lo hiciera una función DEFINER, `usar_plantilla` correría como `postgres`, con BYPASSRLS. Ahí no corre: mejor una plantilla que no dispara que una que crea lo que su usuario no puede.
- **Cada plantilla en su bloque `EXCEPTION`.** Si una no puede correr (perdió un permiso, quedó mal armada) se revierte lo suyo, el estado cambia igual y la campanita avisa (`plantilla_fallida`). Una plantilla mal configurada no traba una venta.
- **Costo aceptado:** la organización no puede garantizar una tarea. "Cobrar obra X" llega a Cobranzas solo si quien cambia el estado la activó y tiene `tareas_asignar`; si no, le queda a él con la nota de `sql/053`.

**Una vez para siempre por (plantilla, registro), salvo archivadas.** `tareas_vinculos` guarda qué tareas salieron de cada disparo y `plantilla_disparada` mira si queda alguna activa. Completadas y canceladas siguen activas, así que no la reabren; archivar lo generado (alcanza con el hilo o el proyecto, por cascada) la deja volver a disparar en el próximo cambio de estado real. Es DEFINER: quien cambia el estado puede no ver lo que generó otro.

**Los vínculos solo los escribe un disparo** (`WITH CHECK (pg_trigger_depth() > 0)`). Un vínculo inventado —(plantilla, obra) con una tarea cualquiera— bloquearía el disparo real para todos. Las dos DEFINER que llama el disparo tienen EXECUTE para `authenticated` y, por la misma guarda, fuera de un trigger no hacen nada.

**Con disparador no se usa a mano, y sin disparador no se dispara** (`TA013`): los textos citan `{nombre}` y a mano quedarían literales. En la vista, "Usar" se reemplaza por el interruptor "Activada".

**El texto se copia; el link respeta permisos.** "Cobrar obra {nombre}" se rellena al crear, así que el asignado lo lee aunque no vea la obra. Nunca contacto como dato: `entes.datos` de la obra es `{nombre}`. El link va por `origen_app`/`origen_punto`, que el panel de la tarea ya mostraba ("Generado por obras — ir"). Elegido por el usuario frente a chips en el panel, que pedían resolver etiqueta y ruta por ente para un solo ente.

**Se ve y se arma solo con el submódulo del ente** (confirmado por el usuario). Las policies de `tareas_plantillas` hacen EXISTS contra `entes`, cuya RLS es `tiene_permiso(submodulo)`: quien no ve obras no ve "Cobrar obra {nombre}", no la activa (nunca cambia el estado de una obra) y no arma otra (`TA012`).

**La campanita avisa cuando guardan o archivan una plantilla de sistema que tenés activada** (`plantilla_modificada`, `plantilla_archivada`). Guardar sin cambios también avisa: `guardar_plantilla` reemplaza los pasos y no sabe si algo cambió. El aviso de una archivada sale sin destino, porque la vista no lista archivadas. `?plantilla=` abre la vista filtrada por esa plantilla y se limpia de la URL, mismo patrón que `?tarea=`.

**Las asignaciones de un disparo sí avisan.** `notificar_tarea_asignada` descartaba todo lo que naciera adentro de un trigger (por la copia de `generar_recurrencia`); el disparo marca la transacción con `tareas.disparo` y el filtro lo deja pasar.

**Las etiquetas de estado de obra suben a `lib/entes.ts`**: Tareas las muestra en el editor y en la lista. `modules/obras/types.ts` las re-exporta como `LABEL_ESTADO`, así que obras no cambió. La base sabe qué entes hay; cómo se nombran lo sabe la UI (`ENTES`).

**Una obra congelada por posible duplicado dispara igual.** El trigger es genérico y no sabe de `pendiente`; si el alta se rechaza, lo generado se archiva a mano. Esperar la aprobación haría disparar a quien aprueba, no a quien la cargó.

**Supera** *Notificaciones: infra sin submódulo, y sin motor* (`decisiones/global/infra.md`): esto sí es un motor de reglas, chico.

**Tests:** `sql/tests/plantillas_disparo.sql` 29/29 (nuevo). `plantillas.sql` 22/22 y `atomicidad_tareas.sql` 15/15 sin tocar: los parámetros nuevos de `guardar_plantilla` y `usar_plantilla` tienen DEFAULT, así que las llamadas viejas siguen valiendo.
