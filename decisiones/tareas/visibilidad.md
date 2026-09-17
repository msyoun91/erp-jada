# Modelo: visibilidad y autorización

Tres ejes ortogonales:
`tareas_gestionar_ajenas` = autoridad sobre lo ajeno · la membresía del proyecto = quién
puede trabajar · `tareas_asignar` = quién reparte. `tareas_gestionar_ajenas` es además la función
que administra el módulo (`decisiones/global/permisos.md`): desde `sql/076`, cuando asigna a un no
miembro lo suma al proyecto. Sigue sin saltear `tareas_asignar`.

## Ser creador deja de dar visibilidad (`sql/013`)

Pedido de usuario, verificado contra el código antes de tocar nada: la regla que quería ("sin `tareas_gestionar_ajenas` se ve lo asignado y lo público; si te sacan la asignación dejás de ver, aunque lo hayas creado") **no se cumplía**, y la brecha estaba entera en SQL — los paneles no re-filtran, muestran lo que RLS devolvió. `tareas_select`, `puede_ver_hilo` y `tareas_proyectos_select` autorizaban por `creado_por`.

**Qué cambia.** `creado_por` sale de la visibilidad de tareas, hilos y proyectos. Sobreviven tres actores: `tareas_gestionar_ajenas`, la asignación activa, y `tareas_hilos.responsable_id` — el dueño del hilo, que es un rol, no una asignación. En tareas, `responsable_id` salió del SELECT: el schema ya exige `responsable ∈ asignados` (`crearTareaSchema`) y la base confirmó 0 filas donde no se cumpliera, así que la rama era redundante.

**La tarea suelta, pública y sin proyecto ahora se ve.** `tareas_select` exigía `proyecto_id IS NOT NULL` para la rama pública; sin la rama del creador tapando el hueco, esa tarea no la vería nadie. Hay 1 en la base.

**Los UPDATE se alinearon con los SELECT.** Dejar `creado_por` en el UPDATE habría creado la fila modificable pero invisible — y un UPDATE denegado por RLS no falla, afecta 0 filas: el bug sería silencioso. Consecuencia buscada: el creador de un proyecto que se sacó a sí mismo de los miembros ya no puede editarlo (hay 1 proyecto así).

Dos huecos que aparecieron al sacar al creador y hubo que cerrar en la misma pasada, porque devolvían por API la visibilidad que la regla quita:

- `es_responsable_o_creador_tarea()` → `es_responsable_tarea()` (la vieja se borró). Con la rama del creador, quien perdía la asignación se re-insertaba en `tareas_asignados`. No hace falta para crear: `tareas_insert` ya exige `responsable_id = auth.uid()` a quien no tiene `tareas_gestionar_ajenas`.
- `tareas_asignados_update` acota `usuario_id = auth.uid()` a `NOT activo` en el `WITH CHECK`. Sacarme de una tarea sigue siendo mío; reactivar mi propia fila, no.

**Contrapartida: el responsable del hilo puede tocar las tareas de su hilo** (rama nueva en `tareas_update`). Sin eso, "deshacer conversión" y el cierre de hilo — que actualizan tareas a las que el dueño no está asignado — pasaban a no hacer nada, en silencio.

**`crearTarea`, `crearProyecto` y `agregarTareasDesdePlantilla` generan el id en el server** y dejan de pedir `RETURNING`. Sin la rama del creador, la fila recién insertada todavía no es visible para quien la insertó (sus asignados/miembros se insertan en el statement siguiente) y `.select()` rompía con RLS violation. Es el mismo patrón — y el mismo comentario — que ya tenía `crearHilo` por el motivo análogo.

**La UI dejó de ofrecer lo que la RLS después descarta.** `TareaDetailPanel`, `HiloDetailPanel` y `ProyectoDetailPanel` derivaban `puedeGestionar` de `creado_por`; ahora usan responsable / asignado / miembro, espejo exacto del `USING` de cada policy. El filtro de la vista Lista conservó `creado_por` un rato más — "es un filtro sobre lo ya visible, no una barrera" — y eso fue un error de UX: filtrar por un usuario le mostraba tareas que creó y asignó a otro, contradiciendo la regla que el resto del módulo ya seguía. `estaInvolucrado()` pasó a `esDeUsuario()` = `responsable_id` OR asignado activo, y el match de hilos perdió `h.creado_por`. Sigue sin ser una barrera; es que "de quién es esta tarea" lo contesta la asignación, no la autoría.

Verificado con `sql/tests/rls_visibilidad_tareas.sql` (mismo mecanismo que el test de `sql/009`: dos usuarios reales, rol `authenticated`, `ROLLBACK` al final). Correr los dos tests después de tocar estas policies.

## La visibilidad de una tarea con hilo deja de mostrarse

Contracara de lo anterior: `tareas_select` lee `tareas.visibilidad` **solo** en la rama de tarea suelta (`hilo_id IS NULL`, `sql/013:57-64`). Con hilo, la visibilidad la resuelve entero `puede_ver_hilo` — quien está asignado a una tarea del hilo ve todas las demás, marcadas privadas o no. La UI ofrecía el control igual y lo mostraba en la isla y el panel, así que una tarea decía "🔒 Privada" a un usuario que la estaba leyendo.

- `TareaFormPanel`: el select de Visibilidad se esconde con `hiloId` o `tarea.hilo_id`, mismo criterio que el select de Proyecto (que ya se escondía). El valor viaja como default oculto — no se pierde, y vuelve a mandar si la tarea sale del hilo (`deshacerConversionHilo`).
- `TareaCard` y `TareaDetailPanel`: el indicador "Privada" pide además `hilo_id === null`.
- Sin SQL: la cascada todo-o-nada del hilo es el diseño, no el bug. El hilo es la unidad de trabajo; hacer que `privado` recorte dentro de él sería otra regla, no un arreglo.

## Miembros de proyecto = quién puede recibir tareas (`sql/009`)

Implementado. **Todo proyecto exige al menos un miembro** (antes solo los privados) y los asignables de una tarea con proyecto se limitan a los miembros de ese proyecto. Los dos ejes quedan ortogonales: `visibilidad` decide **quién ve**, la membresía decide **quién trabaja**. Aplica a proyectos públicos y privados por igual — por eso la acción "Miembros" ya no se esconde en los públicos.

La regla vive en la base, en tres piezas, porque tiene tres caras y una sola no alcanza:

1. `tareas_asignados_insert`/`update` — cambian los asignados de una tarea. La condición se exige solo si la fila queda activa (`NOT activo OR es_miembro_proyecto_de_tarea(...)`): desactivar una asignación al reasignar tiene que seguir siendo posible aunque el usuario ya no sea miembro.
2. Trigger `validar_proyecto_tarea` — cambia el proyecto de la tarea (editarla, asociarla a un hilo de otro proyecto). Se valida en trigger y no en policy porque el dato que se compara vive en otra tabla.
3. Trigger `validar_quitar_miembro` — se quita un miembro que tiene tareas activas: error explícito (`TA001`), no desactivación silenciosa de sus asignaciones.

`tareas_gestionar_ajenas` **no** saltea la regla: es una regla de negocio ("quién trabaja"), no un nivel de permiso — un manager agrega el miembro primero. El filtro del picker es UX, no barrera.

Efectos colaterales que la implementación obligó a resolver:

- `tareas_proyectos_miembros_select` se extendió con `es_miembro_proyecto(proyecto_id, auth.uid())`. Sin eso, un miembro que no es creador del proyecto solo se ve a sí mismo y el picker de asignados le queda vacío.
- `gestionarMiembrosProyecto` pasó a guardar un **diff** (quitados/agregados) en vez de desactivar todo y reinsertar: el patrón viejo disparaba `TA001` sobre los miembros que se quedaban.
- `getProyectoMiembros(id)` (N+1, solo privados) se reemplazó por `getMiembrosPorProyecto()`: una query que devuelve `Record<proyecto_id, usuario_id[]>` para todos los proyectos visibles. Ese mapa se dropea por props junto a `proyectos`, igual que `plantillas`.
- El proyecto efectivo de una tarea es `COALESCE(tarea.proyecto_id, hilo.proyecto_id)` — de ahí el prop `proyectoHeredadoId` en `TareaFormPanel`/`TareaRow`: la tarea de un hilo no guarda proyecto propio (lo prohíbe un CHECK) pero igual hereda sus miembros.
- Backfill de proyectos sin miembros activos = creador + responsables de sus hilos + todo usuario con asignación activa en sus tareas, para no dejar bloqueada ninguna reasignación existente.

Verificado end-to-end con dos usuarios (`sql/tests/rls_miembros_asignables.sql`, 15/15). El test no es una migración: corre dentro de una transacción con `ROLLBACK`, cambia a rol `authenticated` y setea `request.jwt.claims` para mover `auth.uid()` entre los dos usuarios. Le desactiva `tareas_gestionar_ajenas` al usuario de prueba dentro de la tx — con el bypass puesto, las policies se cortan en la primera rama y no se prueba nada. Confirmado en la base, no solo por lectura del SQL:

- Un miembro que no es creador ve a **todos** los miembros del proyecto (el caso que dejaba el picker vacío); en un proyecto ajeno ve 0.
- La membresía se exige sobre el **asignado**, no sobre quien actúa, y también cuando el proyecto se hereda del hilo.
- `tareas_gestionar_ajenas` no saltea la regla ni siendo creador del proyecto.
- Desactivar la asignación de alguien que ya no es miembro sigue permitido; reactivarla, no.

Volver a correrlo entero después de tocar esas policies.

Fuera de alcance por ahora: `tareas_hilos.responsable_id` y `tareas.responsable_id` no se validan contra la membresía. El responsable siempre está entre los asignados por schema (`crearTareaSchema`), así que la policy de `tareas_asignados` ya lo cubre en la práctica; el responsable de un hilo no es una asignación.

## Miembros de proyecto = función propia del módulo (`tareas_proyectos_miembros`)

Pedido de usuario en la misma tanda. Es un submódulo-función bajo la vista `tareas_proyectos` — no un permiso nuevo ni un rol: la regla del proyecto es que toda autorización nueva se implementa como submódulo. Las policies de `tareas_proyectos_miembros` pasan de `es_creador_proyecto()` a `tiene_permiso('tareas_proyectos_miembros')`.

**La siembra inicial es la excepción, y está acotada.** Todo proyecto exige al menos un miembro (`sql/009`), así que sin una salida `tareas_proyectos_crear` no alcanzaría para crear nada. La rama `es_creador_proyecto(...) AND NOT proyecto_tiene_miembros(...)` la habilita solo mientras el proyecto no tenga miembros: una vez creado, cambiar quién trabaja en él exige la función. Sin esa cota, el creador se re-agregaba como miembro y recuperaba el acceso que `sql/013` le saca.

**El bloque Miembros sigue dentro de `ProyectoFormPanel`** — no vuelve a ser panel aparte (eso se decidió y se mantiene). Lo que cambia es que se renderiza solo con el permiso; sin él la membresía viaja como default oculto del form, igual que proyecto/visibilidad en `HiloFormPanel`, y el diff de `editarProyecto` queda vacío. La barrera real es la RLS, no el condicional.

**Backfill:** la función se le otorga a los creadores de proyectos activos, para no romper proyectos en curso. Para el resto, alta manual desde Usuarios.

**El SELECT de `tareas_proyectos_miembros` no mira la función.** El primer intento la agregaba ahí y el test de `sql/009` lo cazó (caso 02: TESTER, que recibió la función por el backfill, veía los miembros de un proyecto del que no es parte). La rama sobraba además de filtrar: editar un proyecto ya exige ser creador-y-miembro o tener ajenas, así que quien usa la función entra igual por `es_miembro_proyecto`.

**Límite conocido:** administrar miembros de un proyecto **privado** exige además verlo, y eso ahora es ser miembro o tener `tareas_gestionar_ajenas`. La función sola no abre proyectos privados ajenos — es deliberado: sería una segunda puerta de visibilidad, justo lo que `sql/013` cierra.

Aplicado en Supabase vía MCP. Tests posteriores: `rls_visibilidad_tareas.sql` 17/17, `rls_miembros_asignables.sql` 15/15.

~~**El filtro por usuario ofrece la lista del equipo solo con `tareas_gestionar_ajenas`** (`TareasListaView`, `ProyectosView`). Sin la función quedan dos opciones: "Todos los usuarios" — que ya es lo propio más lo público, o sea todo lo que RLS devuelve — y uno mismo.~~ **Superado por *El selector de usuario se oculta sin la función* (abajo).** `AuditoriaView` conserva el picker completo: la vista entera está gateada por `tareas_auditoria` y ese filtro es su razón de ser.

## El selector de usuario se oculta sin la función

Pedido de usuario. Sin `tareas_gestionar_ajenas` el `<select>` de usuario ya no se renderiza en `TareasListaView` ni `ProyectosView` — antes mostraba dos opciones ("Todos los usuarios" + uno mismo). El default de `asignadoId` / `miembroId` sigue siendo `usuarioActualId`, así que la vista queda fija en lo propio y el toggle Míos/Involucrado sigue apareciendo. Sigue sin ser una barrera: RLS filtra antes y el servidor rechaza igual. Cambio solo de UI, cero SQL.

## Ver miembros exige proyecto activo (`sql/016`)

`tareas_proyectos_miembros_select` no miraba `tareas_proyectos.activo`: archivar un
proyecto lo sacaba de la lista pero dejaba sus membresías visibles.

El filtro va en la policy y no en `getMiembrosPorProyecto` porque es la misma
pregunta que ya responde el SELECT de la tabla — "qué membresías te tocan" — y
duplicarla en la query dejaba la base contestando de más.

El `EXISTS` directo sobre `tareas_proyectos` fue lo primero que verifiqué: el
ciclo `tareas_proyectos` ↔ `tareas_proyectos_miembros` que documenta
`db_schema/tareas.md` causa `42P17` con `EXISTS` en ambas direcciones, pero acá el lado
de vuelta pasa por `es_miembro_proyecto` (`SECURITY DEFINER`), que ya lo rompe.
Probado en transacción antes de aplicar: sin recursión, 5 → 2 filas visibles.

## Asignar usuarios a una tarea es una función (`sql/014`)

Pedido de usuario: **el que no está autorizado no puede asignar**. Antes no había función que mirar — `tareas_asignados_insert` solo pedía ser responsable de la tarea, y como quien crea queda responsable, cualquiera podía repartir trabajo. La UI mostraba el picker en "Nueva tarea" sin chequear nada, y en "Modificar tarea" no lo mostraba nunca.

Submódulo-función nuevo `tareas_asignar` ("Asignar usuarios", vista `tareas_lista`). La regla es una sola y vive en la base: **poner a OTRO usuario en una tarea — como asignado o como responsable — exige la función; asignarse uno mismo, no.**

Tercer eje, ortogonal a los dos que ya había: `tareas_gestionar_ajenas` es autoridad sobre tareas que no son propias, la membresía del proyecto es quién puede trabajar, `tareas_asignar` es quién reparte. Las tres condiciones se exigen juntas y ninguna saltea a otra — por eso `sql/014` hace backfill de `tareas_asignar` a todos los que ya tenían `tareas_gestionar_ajenas` (mismo criterio que el backfill de `tareas_proyectos_miembros` en `sql/013`), en vez de dejar el bypass escrito en la policy.

`tareas_insert` **pierde** su rama `tareas_gestionar_ajenas`: nombrar responsable a otro al crear pasa a pedir `tareas_asignar`. El traspaso del responsable de una tarea que ya existe va por trigger (`validar_responsable_tarea`, `TA003`) y no por policy, porque `WITH CHECK` solo ve la fila nueva: no puede distinguir "cambió el responsable" de "el UPDATE tocó otra columna".

En la UI:

- **El picker aparece también al modificar la tarea** (decisión del usuario, antes solo al crear). El gate vive dentro de `AsignadosPicker` (`puedeAsignar`), no en cada panel: sin la función muestra solo el resumen de a quién le queda la tarea, y los valores siguen viajando como defaults ocultos del form. Un solo lugar para el bloque de solo-lectura, que si no se repetía en `TareaFormPanel` y `UsarPlantillaPanel`.
- "Reasignar" sigue en el menú como atajo, ahora gateado por la función. Con dos entradas para lo mismo, `tareas_asignados` necesitaba un solo escritor: `sincronizarAsignados()` en `actions.ts`, que usan `editarTarea` y `reasignarTarea`.
- **`sincronizarAsignados()` no toca nada si el conjunto no cambió.** Editar el título no debe reescribir asignaciones, y sin ese corte quien no tiene la función no podría guardar ningún cambio en una tarea compartida: los asignados viajan igual como defaults ocultos y reinsertarlos choca contra la policy.
- `TareaDetailPanel` pasa `proyectoHeredadoId` a `TareaFormPanel` al editar. Sin eso, la tarea de un hilo abría el picker con todos los usuarios en vez de con los miembros del proyecto del hilo — invisible mientras el picker no existía en edición.

Verificado end-to-end contra la base con `sql/tests/rls_miembros_asignables.sql` (19/19). El test creció a dos bloques: el primero corre con TESTER **sin** `tareas_asignar` ni `tareas_gestionar_ajenas`, el segundo le devuelve `tareas_asignar` y repite los mismos UPDATE — tienen que pasar de RECHAZO a OK. Sin ese espejo, un rechazo por membresía o por RLS de otra rama se leería como si la función nueva estuviera funcionando.

- `11`/`16` reactivar la asignación de ADMIN en P: ADMIN **es** miembro, así que el único motivo posible de rechazo es la función — aísla la regla nueva de la de `sql/009`.
- `12`/`18` traspasar el responsable: sin la función corta el trigger con `TA003`, no la policy con `42501`.
- `17` (ex `12`) sigue probando que la membresía se evalúa sobre el asignado y no sobre quien actúa, ahora con la función puesta.

Fuera de alcance: el responsable de un **hilo** (`HiloFormPanel`) sigue gateado por `tareas_gestionar_ajenas` en `tareas_hilos_insert`/`update`. El dueño del hilo no es una asignación (mismo criterio que `sql/009`).

## Nombrar responsable de un hilo = `tareas_asignar` (`sql/015`)

`tareas_hilos_insert` seguía pidiendo `tareas_gestionar_ajenas` para poner a
otro como responsable, mientras `sql/014` había movido esa misma decisión sobre
`tareas` a la función `tareas_asignar`. Dos ejes para una sola regla: poner a
OTRO a cargo exige `tareas_asignar`, y nada la saltea — tampoco
`gestionar_ajenas`, que es autoridad sobre lo ajeno, no permiso para repartir
trabajo.

Tres piezas, mismo reparto que en `tareas`:

- `tareas_hilos_insert` — `responsable_id = auth.uid() OR tiene_permiso('tareas_asignar')`.
- Trigger `validar_responsable_hilo` — el traspaso necesita el valor viejo, que
  un `WITH CHECK` no ve. Reusa `TA003`: el mensaje ya era genérico.
- `tareas_hilos_update` — el `WITH CHECK` suma `OR tiene_permiso('tareas_asignar')`.

La tercera pieza apareció al correr el test, no al escribir la policy: sin ella
el traspaso quedaba imposible incluso con la función, porque la fila nueva tiene
`responsable_id` ajeno y el `WITH CHECK` solo aceptaba `responsable_id = auth.uid()`.
En `tareas` el caso no aparece porque ahí el `WITH CHECK` tiene además la rama
del asignado activo (`sql/013`). El reparto que queda: el `USING` decide quién
puede tocar el hilo, el trigger decide quién puede quedar a cargo.

El caso `20b` de `sql/tests/rls_miembros_asignables.sql` existe para eso —
verifica que ese `WITH CHECK` más laxo no habilitó editar hilos ajenos.

## No se ofrece crear trabajo donde no podés trabajar

`puedeTrabajarEnProyecto` (`components/proyectoTareas.ts`) decide si el panel
del proyecto muestra "Agregar hilo/tarea" y si un proyecto aparece en el select
de `TareaFormPanel` y `HiloFormPanel`.

La regla sale de `sql/009` + `sql/014`: crear una tarea exige al menos un
asignado y solo los miembros del proyecto pueden serlo. Sin `tareas_asignar` el
único asignado posible es uno mismo, así que hay que ser miembro; con la
función alcanza con que haya algún miembro visible. `idsMiembros` ya viene
recortado por RLS — de un proyecto que no trabajás no ves a nadie.

Antes el form abría igual y moría en la validación de Zod pidiendo un asignado
que no se podía elegir. No es una barrera de seguridad (RLS ya lo bloquea):
es no ofrecer un camino que siempre termina en error.

## Quien no puede abrir lo relacionado no queda asignado (`sql/063`)

Fase D de `PLAN_TAREAS_VINCULOS.md`, sobre la base de acceso por usuario de
`sql/062` (*Acceso a un registro por usuario explícito*, `db_schema/core.md`).
Decisión del usuario el 2026-09-14: si un asignado no puede abrir lo
relacionado con la tarea, no queda asignado; si no queda nadie, la tarea va a
quien asigna, con una nota. Relacionar un registro con una tarea que ya
existe aplica la misma regla, y también el disparo de una plantilla.

**Regla única, un solo predicado.** `queda_afuera(usuario, ente, id)` (`sql/062`)
decide todo: `usuario` distinto de quien actúa y no puede abrir el registro.
`asignados_con_acceso(asignados, vinculos)` filtra un array contra todos los
vínculos de la tarea. La aplican tres puntos, sin copiar la lógica:

- `crear_tarea` — filtra antes de insertar. Si queda vacío, sustituye por
  `auth.uid()` (quien crea, que la exención de `queda_afuera` nunca saca) y dos
  párrafos más abajo escribe la nota. El responsable se recalcula sobre el
  conjunto final: `p_responsable_id` si sobrevivió, si no `auth.uid()`, si no
  el primero que quedó.
- `sincronizar_asignados` (editar_tarea, reasignar_tarea) — mismo filtro, pero
  sobre los vínculos *actuales* de la tarea (no los del momento de crearla).
  **El early return compara contra el conjunto ya filtrado, no contra lo que
  pidió el cliente**: si el resultado final no cambió, no hay nada que
  reescribir, aunque el pedido pidiera de más.
- `vincular_tarea` (nueva función, reemplaza el INSERT directo de la action
  `vincularTarea`) — inserta el vínculo y, si la tarea tiene asignados
  activos, vuelve a correr `sincronizar_asignados` sobre ellos. Sin asignados
  no se llama: si no, relacionar asignaría a quien relaciona.

**Sacar a alguien de una tarea sigue siendo asignar (`sql/014`).** Si el
filtro de acceso deja a alguien afuera y quien edita o relaciona no tiene
`tareas_asignar`, la función entera revierte con `TA016` en vez de sacarlo en
silencio — ni siquiera toca otros campos del mismo UPDATE. Es la razón de que
el chequeo de `TA016` vaya *antes* del early return de `sincronizar_asignados`:
una edición que no cambia el conjunto de asignados pedido igual puede
descubrir que alguien ya no tiene acceso, y sin la función para sacarlo la
edición completa se cae.

**El disparo arma los vínculos con `plantilla_id` y se los pasa a
`crear_tarea`**, que ya trae el filtro — reemplaza los dos `INSERT` directos a
`tareas_vinculos` que `usar_plantilla` hacía después de crear la tarea
(`sql/060`). El `v_vacio` propio de la plantilla (asignados fijos que no
pueden recibir el paso por otros motivos: inactivos, fuera del proyecto, sin
`tareas_asignar`) no cambia — ese caso ya sustituye por `v_uid` (quien usa la
plantilla), que la exención de `queda_afuera` nunca saca, así que
`crear_tarea` no lo vuelve a vaciar y no hay nota doble.

**Registro de la transacción para la UI y el ensayo (`registrar_sin_acceso`,
`sin_acceso_registrado`).** Un GUC local (`tareas.sin_acceso`) acumula
`{tarea_id, usuario_id, ente, registro_id}` por cada exclusión real de la
transacción — nadie más lo escribe. Sirve para dos cosas: `disparar_plantillas`
compara su longitud antes/después de cada `usar_plantilla` para saber si *esa*
plantilla dejó a alguien afuera (y avisar `plantilla_sin_acceso` en vez de
`plantilla_disparada`), y `obras_ensayar_estado` lo lee justo antes de forzar
su propio rollback.

**El aviso nuevo, `plantilla_sin_acceso`.** `notificar_disparo` gana un tercer
parámetro (`p_sin_acceso`, `DEFAULT false`: las llamadas viejas de dos
argumentos siguen andando) y el tipo sale de una prioridad —
`plantilla_fallida` si no corrió, si no `plantilla_sin_acceso` si dejó a
alguien afuera, si no `plantilla_disparada`. `notificaciones_listar` lo manda
por la misma rama que `plantilla_disparada` (`destino = 'tareas'`, sin id: las
tareas creadas siguen ahí aunque la plantilla se archive).

**El ensayo de un cambio de estado (`obras_ensayar_estado`), para que la UI
pregunte antes de guardar (Fase E).** Hace el `UPDATE` de verdad —así el
trigger de Obras dispara sus plantillas de verdad, con vínculos y asignados
reales— y lo revierte con un `RAISE ... USING ERRCODE = 'TA017'` que la misma
función atrapa; el código nunca sale de acá, así que no entra a
`MENSAJES_ERROR`. `INVOKER` a propósito: el disparo exige
`current_user = 'authenticated'`, y con `DEFINER` el `UPDATE` correría como el
dueño de la función y no dispararía nada. Cualquier otro error (RLS, el CHECK
de pérdida) sube tal cual, sin que este bloque lo toque.

**Verificado con `sql/tests/asignar_con_acceso.sql` (18/18):** el asignado sin
acceso queda afuera en los tres caminos (crear, editar, relacionar) y en el
disparo; si no queda nadie, va a quien crea con nota; quien actúa nunca queda
afuera, ni por un rol adjunto (`sql/060`) que él mismo no puede abrir; un
vínculo con `plantilla_id` fuera de un trigger sigue fallando (`sql/059`); sin
`tareas_asignar`, sacar a alguien por la fuerza de los hechos revierte la
operación entera con `TA016`; el ensayo devuelve el par excluido sin dejar
nada (0 tareas, 0 avisos, estado sin cambiar) y, tras compartir el registro,
el cambio de estado real sí deja al asignado.

## Compartir al asignar: la pregunta (Fase E de `PLAN_TAREAS_VINCULOS.md`, sin SQL)

Sobre `sql/062`/`sql/063` (arriba). La base ya decide quién queda afuera; falta que la UI
pregunte **antes** de guardar, en vez de guardar y enterarse por la nota.

**`lib/accesos.ts`** (`"use server"`, primera action que usan dos módulos) envuelve las dos
RPC de `sql/062`: `sinAcceso(pares)` → `sin_acceso`, `compartirRegistros(selecciones)` →
`compartir_registros`. Vive en `lib/` y no en `modules/tareas` porque Obras también lo llama
(`ObraFormPanel`), y los módulos no se importan entre sí.

**`components/ui/CompartirAccesoPanel.tsx`** exporta el hook `useConfirmarAcceso({ verbo,
puedeDejarAfuera })` → `{ confirmarAcceso(filas, seguir), panelAcceso }`. Sin filas, `seguir(null)`
directo — no hay panel de por medio. Con `!puedeDejarAfuera` y alguna fila no compartible,
`toast.error` con el texto de `TA016` (`mensajeError({ code: "TA016" })`, no un string repetido) y
sin panel: no hay nada que ofrecer, la operación entera se cae en la base igual. Si no, abre un
`RightPanel` agrupado por usuario con un checkbox por fila compartible (tildado por defecto) y las
no compartibles deshabilitadas (*"No lo podés compartir"* o *"Algo relacionado que no podés ver"*
si `etiqueta` es NULL — la RLS de quien pregunta, no la de a quien se refiere la fila).

**Un panel nuevo en `components/ui/`, no `CompartirPanel` movido.** `CompartirPanel`
(`modules/obras/components/`) importa las actions de Obras y hace algo distinto: elige destino y
revoca, con checklist de qué más compartir. Lo que Tareas y el ensayo de Obras necesitan es más
chico — solo mostrar y tildar quién ya está identificado como destino — así que moverlo habría
sido cargarle a Obras una responsabilidad que no es suya.

**Cerrar (X, Escape, backdrop) es "sin compartir" solo con `puedeDejarAfuera`.** Sin él, cerrar
cancela la operación entera — no hay guardado parcial ni relación a medias. `RightPanel` recibe
`hayCambios={false}`: la pregunta de "¿descartar cambios?" no aplica acá, cerrar ya es una
decisión explícita.

**Tres superficies, mismo patrón** (armar pares `usuario_id × {ente, registro_id}`, filtrar a
quien actúa, `sinAcceso`, y si hay filas `confirmarAcceso`):

- `TareaFormPanel` (crear y editar): al crear, los pares salen de `vinculos` (el estado del
  toggle "Relacionada con"). Al editar, solo si el conjunto de asignados pedido cambió —mismo
  criterio que el early return de `sincronizar_asignados`— ~~y ahí los vínculos son los de
  `tarea.vinculos`~~ → los pone la base, ver *Asignados por diferencia, la pregunta completa y
  compartir en orden* (`sql/064`). `verbo: "guardar"`, `puedeDejarAfuera: true` (poner a otro ya
  exige `tareas_asignar` antes de llegar acá).
- `ReasignarPanel`: ~~nuevo prop `vinculos`~~ → `sinAccesoTarea` (`sql/064`). Mismo patrón que el
  form.
- `TareaDetailPanel.relacionar`: asignados activos (menos quien actúa) × el registro elegido, más
  los vínculos que la tarea ya tiene (`sql/064`). `puedeDejarAfuera: puedeAsignar` — sin la función, relacionar algo que deja a alguien
  afuera no tiene salida "sin compartir": cae en el toast de `TA016` sin abrir panel, porque la
  base va a revertir la operación igual.

**`ObraFormPanel`: el ensayo solo corre al editar un estado existente, nunca al crear.** Decisión
3 del usuario: una obra que nace ya en un estado que dispara no se puede preguntar antes —no
existe todavía— así que se aplica la regla y avisa por notificación (`plantilla_sin_acceso`, ya
resuelto en `sql/063`). Al editar, si `data.estado !== obra.estado`, `ensayarEstadoObra` (nueva
action, RPC `obras_ensayar_estado`) hace el cambio de verdad —dispara la plantilla real, con
vínculos y asignados reales— y lo revierte. Si el ensayo devuelve filas, `confirmarAcceso` antes de
`editarObra`. **Si el ensayo falla, se guarda igual:** `editarObra` va a mostrar el error real (RLS,
el CHECK de pérdida) — el ensayo es una consulta, no una segunda barrera.

**`ensayarEstadoObraSchema`** (`modules/obras/types.ts`) es `obraEditableSchema.pick({ estado,
motivo_perdida, detalle_perdida })` + `id`, con los mismos dos `.refine` que `editarObraSchema`:
motivo y detalle viajan porque el CHECK `obras_perdida_con_motivo` rechazaría el ensayo de
"Perdida" sin motivo, igual que rechazaría el guardado real.

Archivos: `lib/accesos.ts` (nuevo), `components/ui/CompartirAccesoPanel.tsx` (nuevo),
`TareaFormPanel.tsx`, `ReasignarPanel.tsx`, `TareaDetailPanel.tsx`, `ObraFormPanel.tsx`,
`modules/obras/actions.ts` (`ensayarEstadoObra`), `modules/obras/types.ts`
(`ensayarEstadoObraSchema`).

~~**Pendiente: pruebas manuales.**~~ — corridas con ADMIN y TESTER, OK (commit `b0cba1e`). El
checklist quedó en `obsoletos/`.

## Asignados por diferencia, la pregunta completa y compartir en orden (`sql/064`)

Auditoría del 2026-09-16 sobre `sql/063` y la Fase E. Los tres bugs se reprodujeron contra la base antes
de tocar nada (`sql/tests/asignar_con_acceso.sql`, casos 13, 14 y 16).

**`sincronizar_asignados` escribe por diferencia y recibe el responsable.** Antes desactivaba todo y
reinsertaba todo, así que a quien se quedaba le llegaba otro «te asignaron». Además, `editar_tarea` y
`reasignar_tarea` escribían `responsable_id` antes que los asignados. Quien tiene `tareas_asignar` sin
`tareas_gestionar_ajenas` perdía, en ese primer UPDATE, la condición de responsable que el INSERT
siguiente le exige, y pasarle la tarea entera a otro fallaba con 42501. El orden ahora lo dictan las
policies: altas, bajas ajenas, responsable y baja propia al final.

**La pregunta sobre una tarea que ya existe la arma la base (`sin_acceso_tarea`).** La UI armaba los
pares con `tarea.vinculos`, pero `vinculos_de_tareas` descarta lo que quien edita no ve. Así, un vínculo
invisible no entraba en la pregunta y la base igual sacaba al asignado, sin panel. Ahora
`TareaFormPanel` (al editar), `ReasignarPanel` y `TareaDetailPanel.relacionar` llaman a la action
`sinAccesoTarea`; `ReasignarPanel` ya no recibe `vinculos`. Al crear sigue `sinAcceso`, porque todavía
no hay tarea y los vínculos son los del form. Una fila sin nombre sale como *"Algo relacionado que no
podés ver"*.

**`obras_compartir_registros` procesa obra → empresa → persona.** El origen de la cascada busca una
obra ya compartida en la misma llamada, y eso solo andaba si la obra venía primero en el array.
`sin_acceso` ordena por etiqueta, así que la empresa podía quedar como grant directo, sin origen, y
revocar la obra no se la llevaba.

Archivos: `sql/064_asignados_diff_y_compartir_en_orden.sql`, `sql/tests/asignar_con_acceso.sql`
(13–16), `modules/tareas/actions.ts` (`sinAccesoTarea`), `modules/tareas/types.ts`
(`sinAccesoTareaSchema`), `TareaFormPanel.tsx`, `ReasignarPanel.tsx`, `TareaDetailPanel.tsx`.

## Dónde se puede escribir, y la función que administra (`sql/076`)

Auditoría del 2026-09-17 (`PLAN_AUDITORIA_TAREAS.md`, fase 1). Los tres huecos se reprodujeron contra la
base antes de tocar nada (`sql/tests/auditoria_tareas.sql`, bloque F1).

**El hilo y el proyecto destino tienen que estar activos y ser visibles.** `tareas_insert` no miraba
`hilo_id`. Con el id de un hilo ajeno, uno creaba una tarea adentro, se la asignaba por siembra y
`puede_ver_hilo` le abría el hilo entero, con tareas y notas. Lo mismo pasaba moviendo una tarea propia
(`asociarTareaHilo`). Tampoco se miraba `proyecto_id`, ni en tareas ni en hilos. Ahora lo valida el trigger
`validar_destino_tarea` (cubre INSERT, UPDATE y las funciones) y `tareas_hilos_insert`, con
`tareas_proyecto_destino_valido` como fuente única. Hay una excepción: un hilo propio todavía vacío,
porque `convertir_tarea_en_hilo` crea el hilo con el responsable de la tarea y recién después mueve la
tarea. Esa rama no reabre el hueco de `sql/013`, porque `tareas_hilos` perdió el UPDATE de `creado_por`.

**`tareas_proyectos_miembros` alcanza solo a proyectos donde se es miembro.** Con la función, uno se
sumaba a un proyecto privado ajeno. `tareas_gestionar_ajenas` sigue alcanzando a cualquiera.
`editar_proyecto` inserta antes de quitar: si no, quien se saca a sí mismo en el mismo guardado ya no
podría sumar a los otros.

**La función que administra asigna a un no miembro sumándolo al proyecto** (decisión del usuario: siempre
hay una función que deja actuar como administrador). `tareas_sumar_miembros_admin` corre en `crear_tarea` y
`sincronizar_asignados` antes del INSERT de asignados. Va en su propia sentencia porque la policy lee la
membresía con una función STABLE, que no ve lo insertado en la misma sentencia. Al mover una tarea,
`validar_proyecto_tarea_miembros` suma en vez de dar `TA002`. Un INSERT directo a `tareas_asignados` sigue
rechazando al no miembro: el camino del administrador son las funciones.

Archivos: `sql/076_tareas_destino_y_admin.sql`, `sql/tests/auditoria_tareas.sql`, `atomicidad_tareas.sql`
(02–03), `atomicidad_edicion_tareas.sql` (03, 09), `rls_visibilidad_tareas.sql` (16–17), `lib/utils.ts`
(`TA017`), `modules/tareas/types.ts`.

## Columnas, reactivar y relacionar (`sql/077`)

Fase 2 de la auditoría del 2026-09-17. Todo se reprodujo por la API (`sql/tests/auditoria_tareas.sql`, bloque F2).

**Cada tabla tiene su lista de columnas actualizables.** El GRANT de tabla entera dejaba a un asignado
falsear `creado_por`, `created_at` (que ordena los pasos) y `origen_*`, y completar una tarea `hibrido`
cambiándola a `manual` en la misma sentencia. El autor de una nota podía reescribirla. La lista sale de lo
que escriben las actions y las funciones INVOKER. En notas, asignados y miembros la única columna es
`activo`.

**Reactivar una tarea o un hilo es del administrador** (`TA018`). Archivar lo hace quien gestiona, pero
revivir lo que archivó un manager o la cascada de un proyecto le toca a `tareas_gestionar_ajenas`.

**Relacionar pide poder gestionar la tarea, no solo verla.** Con una tarea pública, cualquiera apagaba o
sumaba vínculos. `tareas_puede_gestionar_tarea` repite el USING de `tareas_update`. Un vínculo apagado ya
no se prende por UPDATE: volver a relacionar pasa por `vincular_tarea`, que revisa el registro y a los
asignados.

**El filtro de acceso de `sql/063` pasa a la policy.** Solo lo aplicaban `crear_tarea` y
`sincronizar_asignados`, así que un INSERT directo dejaba asignado a quien no puede abrir lo relacionado.
Vale también para el administrador (decisión D): sacarlo o compartirle sigue siendo de `tareas_asignar`.

Archivos: `sql/077_tareas_columnas_y_vinculos.sql`, `sql/tests/auditoria_tareas.sql`, `lib/utils.ts` (`TA018`).

## Escribir pide una vista; posponer, archivar y mover de hilo son del responsable (`sql/080`)

Fase 6 de la auditoría del 2026-09-17 (`sql/tests/auditoria_tareas.sql`, bloque F6).

**Crear tareas, hilos y notas pide alguna vista de tareas que crea** (`tareas_puede_escribir`: Lista,
Misión, Proyectos o Plantillas). Antes alguien con solo `obras_ver` insertaba por la API. El plan decía
`tareas_lista`, pero el código lo contradice: Misión crea el siguiente paso, Proyectos crea hilos y
tareas, Plantillas las usa, y un disparo crea con la identidad de quien actuó. Auditoría queda afuera
porque es solo lectura.

**Posponer, archivar y mover o quitar de hilo: responsable de la tarea, responsable del hilo o
administrador** (`TA019`). La UI ya lo limitaba al responsable y `tareas_update` se lo dejaba a
cualquier asignado. El responsable del hilo entra porque `desactivar_hilo` y `deshacer_conversion_hilo`
tocan tareas ajenas de su hilo. Es un trigger y no una policy porque tiene que comparar OLD con NEW.
Corre solo con `current_user = 'authenticated'`: la cascada del proyecto y `reactivar_posponer_vencidos`
son DEFINER y tocan esas columnas por todos. `proyecto_id` no entra, porque "Modificar tarea" lo edita y
eso sigue siendo del asignado.

Archivos: `sql/080_tareas_vista_y_gestionar.sql`, `sql/tests/auditoria_tareas.sql`, `lib/utils.ts` (`TA019`).

## Deshacer la conversión en hilo es del responsable del hilo (`sql/081`)

Ítem 24 de la auditoría del 2026-09-17 (`sql/tests/auditoria_tareas.sql`, bloque F7).

**`deshacer_conversion_hilo` pasa a `SECURITY DEFINER` con guarda propia: responsable del hilo o
`tareas_gestionar_ajenas`, si no `TA008`.** El responsable de un hilo que no era responsable ni asignado
de la tarea más antigua chocaba con `42501` — el WITH CHECK de `tareas_update` mira el hilo de la fila
nueva y deshacer lo deja en NULL, así que una policy, que no ve OLD, no puede distinguirlo. La
alternativa INVOKER era abrir el WITH CHECK a cualquier tarea suelta, mucho más que el caso. La guarda
es la misma autorización que ya decidía el último paso (el UPDATE de `tareas_hilos`), y el responsable
del hilo ya entraba en `validar_gestionar_tarea` (`sql/080`), que como DEFINER no corre.

Con RLS fuera de juego, los `IF NOT FOUND` de `sql/023` sobre las tres escrituras salieron: cubrían el
UPDATE que RLS dejaba en 0 filas, y ahora las filas son las que la propia función acaba de leer.

Archivos: `sql/081_tareas_deshacer_hilo_definer.sql`, `sql/tests/auditoria_tareas.sql`.
