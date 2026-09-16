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

**Los vínculos con plantilla solo los escribe un disparo** (`WITH CHECK (pg_trigger_depth() > 0)`; desde `sql/059` el cliente vincula sin plantilla, ver *Tareas relacionadas con obras, empresas y personas* en `integracion.md`). Un vínculo inventado —(plantilla, obra) con una tarea cualquiera— bloquearía el disparo real para todos. Las dos DEFINER que llama el disparo tienen EXECUTE para `authenticated` y, por la misma guarda, fuera de un trigger no hacen nada.

**Con disparador no se usa a mano, y sin disparador no se dispara** (`TA013`): los textos citan `{nombre}` y a mano quedarían literales. En la vista, "Usar" se reemplaza por el interruptor "Activada".

**El texto se copia; el link respeta permisos.** "Cobrar obra {nombre}" se rellena al crear, así que el asignado lo lee aunque no vea la obra. Nunca contacto como dato: `entes.datos` de la obra es `{nombre}`. El link va por `origen_app`/`origen_punto`, que el panel de la tarea ya mostraba ("Generado por obras — ir"). ~~Elegido por el usuario frente a chips en el panel, que pedían resolver etiqueta y ruta por ente para un solo ente.~~ Con más de un ente, los chips llegaron en `sql/059` y los roles de la obra van por ahí (*Roles de la obra en la plantilla*); el texto sigue citando solo `{nombre}`.

**Se ve y se arma solo con el submódulo del ente** (confirmado por el usuario). Las policies de `tareas_plantillas` hacen EXISTS contra `entes`, cuya RLS es `tiene_permiso(submodulo)`: quien no ve obras no ve "Cobrar obra {nombre}", no la activa (nunca cambia el estado de una obra) y no arma otra (`TA012`).

**La campanita avisa cuando guardan o archivan una plantilla de sistema que tenés activada** (`plantilla_modificada`, `plantilla_archivada`). Guardar sin cambios también avisa: `guardar_plantilla` reemplaza los pasos y no sabe si algo cambió. El aviso de una archivada sale sin destino, porque la vista no lista archivadas. `?plantilla=` abre la vista filtrada por esa plantilla y se limpia de la URL, mismo patrón que `?tarea=`.

**Las asignaciones de un disparo sí avisan.** `notificar_tarea_asignada` descartaba todo lo que naciera adentro de un trigger (por la copia de `generar_recurrencia`); el disparo marca la transacción con `tareas.disparo` y el filtro lo deja pasar.

**Las etiquetas de estado de obra suben a `lib/entes.ts`**: Tareas las muestra en el editor y en la lista. `modules/obras/types.ts` las re-exporta como `LABEL_ESTADO`, así que obras no cambió. La base sabe qué entes hay; cómo se nombran lo sabe la UI (`ENTES`).

**Una obra congelada por posible duplicado dispara igual.** El trigger es genérico y no sabe de `pendiente`; si el alta se rechaza, lo generado se archiva a mano. Esperar la aprobación haría disparar a quien aprueba, no a quien la cargó.

**Supera** *Notificaciones: infra sin submódulo, y sin motor* (`decisiones/global/infra.md`): esto sí es un motor de reglas, chico.

**Tests:** `sql/tests/plantillas_disparo.sql` 29/29 (nuevo). `plantillas.sql` 22/22 y `atomicidad_tareas.sql` 15/15 sin tocar: los parámetros nuevos de `guardar_plantilla` y `usar_plantilla` tienen DEFAULT, así que las llamadas viejas siguen valiendo.

## Datos con chips y aviso de que la plantilla corrió (`sql/056`)

Pedido del usuario el 2026-09-14, después de construir la anterior: un usuario común no entiende que tiene que escribir `{nombre}`, y quien cambiaba el estado no se enteraba de lo que se había creado.

**Los datos se insertan con chips debajo de cada texto que los acepta.** Tocar "Nombre de la obra" inserta `{nombre}` donde quedó el cursor, y abajo aparece "Así se va a ver: …" con un ejemplo. Es con clic y no con arrastre: no hay librería de dnd y el arrastre nativo no anda en touch. El chip va afuera del campo porque adentro pediría un editor enriquecido. En la base el texto sigue siendo `{nombre}` y `rellenar_datos` no cambió.

- Hay chips en el título y la descripción de cada paso y en el título de cada hilo. ~~Y en el nombre de la plantilla~~: desde `sql/057` van en el nombre de lo que crea (*Nombre de lo que crea e hilos en paralelo*).
- La etiqueta y el ejemplo de cada dato viven en `ENTES` (`lib/entes.ts`). `entes.datos` sigue diciendo cuáles hay, y un dato sin etiqueta no tiene chip. La vista previa repite en TS el reemplazo de `rellenar_datos`: es presentación, no una regla.
- El chip busca su campo en el `form` del botón (`elements.namedItem`) en vez de encadenar la ref de RHF. Los títulos de hilo se registran adentro de un `map`, donde no se puede llamar a un hook.

**Quien dispara recibe un aviso por plantilla que corrió, no uno por tarea** (`plantilla_disparada`). Es informativo y lleva a la vista general de Tareas (decisión del usuario). Va con actor NULL: con actor, `notificar()` lo descartaría.

- **Apunta a la plantilla, no a lo creado.** Quien dispara puede no ver la tarea: una plantilla de tarea asignada solo a Cobranzas crea algo que `tareas_select` no le muestra (`sql/013`). La bandeja, que hace INNER JOIN con la RLS de quien lee, habría descartado el aviso justo en el caso que eligió el usuario ("avisar aunque la tarea no le quede a él"). La plantilla, en cambio, la ve siempre, porque la tiene activada.
- `notificar_disparo(plantilla, corrio)` reemplaza a `notificar_plantilla_fallida`. Tiene el mismo resguardo (DEFINER, y fuera de un trigger no hace nada) y queda como único lugar para los dos avisos. El tipo sale del booleano, así que por ahí no se puede escribir otro aviso.
- En la bandeja el aviso sale con `destino = 'tareas'` y sin id, aunque después se archive la plantilla: las tareas siguen existiendo.

**Tests:** `plantillas_disparo.sql` 34/34: los 29 de antes más 5 nuevos. La plantilla de hilo del test pasó a tener dos pasos, para probar que el aviso es uno por plantilla y no uno por tarea.

Archivos: `sql/056`, `lib/entes.ts`, `PlantillaFormPanel.tsx`, `NotificacionesBell.tsx`.

## Nombre de lo que crea e hilos en paralelo (`sql/057`)

Pedidos del usuario el 2026-09-14: "en la plantilla no se puede definir el nombre del proyecto" y "cuando creo un hilo, solamente se puede por pasos".

**El nombre de lo que crea es un campo propio** (`titulo_creado`), con chips; vacío = el nombre de la plantilla. Hasta acá el hilo o proyecto se llamaba como la plantilla, así que "Cobrar {nombre}" era a la vez cómo se listaba la plantilla y cómo se llamaba lo creado. "Usar" a mano lo sigue pisando. Los chips se mudan a este campo; un `{nombre}` que ya estuviera en el nombre de una plantilla sigue andando, porque el nombre es el respaldo.

**`encadenada` en la plantilla de hilo y en cada hilo de la de proyecto**, no en "Usar": es el camino que dejó escrito *Las plantillas generan una cadena* (`hilos-pasos.md`) para cuando apareciera el caso real. Quien la usa no decide algo que la plantilla ya sabe.

- Fuera de su tipo se guardan neutros: `guardar_plantilla` deja `titulo_creado` NULL en la de tarea y `encadenada` true fuera de la de hilo. Sin CHECK: `usar_plantilla` no los lee ahí.
- Sin cadena, "vence tras el anterior" corre desde la creación, como ya pasaba con el primer paso. El editor no ofrece esa opción en un hilo en paralelo.
- UI: segmented "Encadenados / En paralelo" arriba de los pasos de la de hilo y en cada hilo de la de proyecto. "Usar" numera solo las listas encadenadas y la vista Plantillas une con → o con coma.

**Tests:** `plantillas.sql` 27/27 (22 de antes + 5). `plantillas_disparo.sql` 34/34 y `atomicidad_tareas.sql` 15/15 sin tocar: los parámetros nuevos de `guardar_plantilla` tienen DEFAULT.

Archivos: `sql/057`, `PlantillaFormPanel.tsx`, `UsarPlantillaPanel.tsx`, `PlantillasView.tsx`, `types.ts`, `actions.ts`.

## Roles de la obra en la plantilla (`sql/060`)

Pedido del usuario el 2026-09-14: "¿por qué no se muestran más entes cuando creo la plantilla? por ejemplo en obras los roles", y crear una tarea según exista un ente. Preguntado cómo, contestó: "con chips o links para que tengan acceso directo", y la condición por paso.

**Un rol no se copia como texto: se adjunta.** Cada paso elige roles (`adjuntos`, `ente:rol`, como `persona:arquitecto`) y, al disparar, la tarea queda vinculada a quien tenga ese rol en la obra. Se ve como un chip que abre la ficha (`sql/059`). Copiar el nombre al título le mostraría un contacto a quien no puede abrirlo; el chip respeta la RLS. Qué pasa con quien recibe la tarea y no puede abrir lo adjunto es lo que sigue en el backlog (compartir al asignar).

**La condición es por paso** (decisión del usuario, frente a "por plantilla"): `condicion`, un rol que tiene que existir cuando la plantilla corre. Si no existe, el paso no se crea y el siguiente se encadena al último que sí. Se evalúa antes de abrir el hilo del paso, así una plantilla de proyecto no deja hilos vacíos.

- **Si no se crea ningún paso, no corresponde: no es un error.** `usar_plantilla` tira `TA014` y el disparo lo revierte sin avisar. Un `TA009` habría mandado "la plantilla no pudo correr" por algo que es la regla funcionando. Como no queda vínculo, si después se suma el rol y la obra vuelve a entrar al estado, la plantilla corre.
- **Solo con disparador** (`TA015`): a mano no hay registro del cual sacar roles. El editor muestra la sección solo si el ente del disparador tiene `roles` en `ENTES`, y si se saca el disparador la action descarta los roles en vez de rebotar el guardado.
- **Quién tiene qué rol lo dice el módulo dueño:** `obras_relacionados_obra` (INVOKER), detrás de `relacionados_de_registro`, que ramifica por ente como `etiqueta_registro`. Corre como quien cambió el estado, que es el responsable y ve todos los vínculos de su obra.
- La forma `ente:rol` la valida un CHECK; que el rol exista lo cuida el editor, porque uno inexistente no encuentra a nadie y no rompe nada. Las etiquetas de rol suben a `lib/entes.ts` (obras las re-exporta).

**Tests:** `sql/tests/plantillas_roles.sql` 7/7 (nuevo). `plantillas_disparo.sql` 34/34 y `plantillas.sql` 27/27 sin tocar.

Archivos: `sql/060`, `lib/entes.ts`, `lib/utils.ts` (`TA015`), `PlantillaFormPanel.tsx`, `types.ts`, `actions.ts`.

## Texto y pasos que dependen de un rol (`sql/065`)

Venía en el borrador de `sql/064` sin UI ni decisión; se construyó el 2026-09-16 desde `BACKLOG.md`.

**Bloques `{si hay ente:rol}…{fin}` y `{si no hay ente:rol}…{fin}` en todo texto que acepta datos.** `rellenar_datos` los resuelve antes que los `{dato}` (así un dato adentro también se completa) y `usar_plantilla` le pasa los roles del registro, calculados una sola vez. Se aplica en el nombre de lo que crea y en los títulos de hilo además de título y descripción del paso: es la misma función, y restringirlo pedía una regla más.

- Sin anidar: el cuerpo no puede contener `{fin}` ni otro `{si `. Una cabecera que no se entiende o un bloque sin `{fin}` quedan como texto: mejor mostrar de más que borrar una frase.
- Sin registro no hay ningún rol: a mano, `si no hay` se muestra y `si hay` no.

**Condición negada: `!ente:rol` crea el paso solo si nadie tiene ese rol.** El CHECK pasa a `^!?[a-z_]+:[a-z_]+$`; en `adjuntos` no vale (Zod: `condicionSchema` separado de `rolSchema`).

**UI (elegida por el usuario):** un select "Texto solo si…" junto a los chips de datos, con los roles en dos grupos (tiene / no tiene), que envuelve la selección o inserta el bloque vacío con el cursor adentro. Mismo patrón de clic que los chips: escribir las llaves a mano es lo que se descartó para `{nombre}`. La vista previa, si el texto tiene bloques, muestra los dos extremos: con todos los roles que nombra y sin ninguno. Con un rol, que es lo común, son los dos resultados posibles. El select de condición del paso usa las mismas opciones (`OpcionesRol`) y el resumen plegado dice "Solo si no hay …".

**El regex vive dos veces** (`rellenar_datos` y `BLOQUE` en el editor): la vista previa es presentación, como el reemplazo de `{dato}` de `sql/056`. Se verificó que resuelven igual con los casos del test 13.

**Tests:** `plantillas_roles.sql` 13/13 (7 de antes + 6). `plantillas.sql` 27/27 sin tocar. `plantillas_disparo.sql` 34/34: los casos 23, 25 y 26 fallaban desde `sql/063` (ADMIN disparaba sobre una obra que TESTER, el asignado, no podía abrir, así que quedaba afuera). Ahora la obra se le comparte antes del disparo.

Archivos: `sql/065`, `PlantillaFormPanel.tsx`, `types.ts`, `database.types.ts`, `sql/tests/plantillas_roles.sql`, `sql/tests/plantillas_disparo.sql`.
