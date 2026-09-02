# Decisiones — módulo tareas

Ordenado por tema, no por fecha. Lo superado está tachado con el puntero a lo que lo
reemplaza; la sección *Construcción inicial* de abajo es la única cronológica y arranca
con el aviso de qué de ahí ya no vale.

---

# Modelo: visibilidad y autorización

Tres ejes ortogonales, ninguno saltea a otro:
`tareas_gestionar_ajenas` = autoridad sobre lo ajeno · la membresía del proyecto = quién
puede trabajar · `tareas_asignar` = quién reparte.

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

**El filtro por usuario ofrece la lista del equipo solo con `tareas_gestionar_ajenas`** (`TareasListaView`, `ProyectosView`). Sin la función quedan dos opciones: "Todos los usuarios" — que ya es lo propio más lo público, o sea todo lo que RLS devuelve — y uno mismo. No es una barrera (recortar por otro usuario nunca mostró de más, la RLS filtra antes) sino no ofrecer un recorte que no es de quien mira. `AuditoriaView` conserva el picker completo: la vista entera está gateada por `tareas_auditoria` y ese filtro es su razón de ser.

## Ver miembros exige proyecto activo (`sql/016`)

`tareas_proyectos_miembros_select` no miraba `tareas_proyectos.activo`: archivar un
proyecto lo sacaba de la lista pero dejaba sus membresías visibles.

El filtro va en la policy y no en `getMiembrosPorProyecto` porque es la misma
pregunta que ya responde el SELECT de la tabla — "qué membresías te tocan" — y
duplicarla en la query dejaba la base contestando de más.

El `EXISTS` directo sobre `tareas_proyectos` fue lo primero que verifiqué: el
ciclo `tareas_proyectos` ↔ `tareas_proyectos_miembros` que documenta
`db_schema.md` causa `42P17` con `EXISTS` en ambas direcciones, pero acá el lado
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

---

# Hilos, pasos y cadenas

## Pasos de tarea y vista Misión (`sql/017`)

Pedido: botón "crear siguiente paso" además de "crear tarea", ver los pasos previos al abrir una tarea, y una vista Misión que muestre la tarea actual de a una ordenada por temperatura.

**Pasos ≠ hilo.** El hilo agrupa tareas que corren en paralelo; la cadena de pasos las ordena. Son ejes ortogonales, así que un hilo puede tener tareas sueltas y cadenas al mismo tiempo. Riesgo asumido: dos formas de relacionar tareas en el mismo módulo. Se mitiga en UI — dentro del hilo la cadena se renderiza como cadena (1→2→3), no como filas planas mezcladas con las paralelas.

**Una columna, no una tabla.** `tareas.paso_anterior_id`. La regla es "se puede hacer si se cumple **el** previo" — un solo predecesor, cadena lineal. Una tabla `tareas_dependencias` sería un DAG genérico para un problema que no existe.

**La cadena vive dentro de un hilo** (`CHECK paso_anterior_id IS NULL OR hilo_id IS NOT NULL` + trigger de mismo `hilo_id`). Esta es la decisión que más ahorró: `tareas_select` ya cascadea visibilidad por `puede_ver_hilo`, así que "ver los pasos previos" no necesitó **ninguna** regla de visibilidad nueva. Encadenar tareas sueltas hubiera obligado a una función `SECURITY DEFINER` que devolviera stubs de los pasos invisibles, o a una UI que miente ("Paso 3 de 5" con 2 pasos que no se ven). Costo aceptado: crear un siguiente paso desde una tarea suelta obliga a tener hilo.

**"Bloqueada" es derivado, no un estado.** `paso_anterior.estado <> 'completada'`. Sumarlo a `estado_tarea` obligaba a sincronizarlo en cada completar/cancelar/reabrir — la duplicación de lógica que prohíbe la regla. La barrera de servidor es el trigger `validar_paso_previo` (`TA004`), no el enum.

**`cancelada` no bloquea.** El trigger solo corta el paso a `en_progreso`/`completada`. Si un paso se cancela la cadena queda trabada, y cancelar los que siguen tiene que seguir siendo posible o el hilo no cierra nunca.

**Ciclos: imposibles por construcción, sin validación.** `paso_anterior_id` es inmutable después del INSERT (`TA005`), y una fila nueva nunca puede ser ancestro de otra → el grafo es siempre un bosque. Recorrer la cadena buscando ciclos hubiera sido código para un caso que la inmutabilidad ya cierra.

**Recurrencia + pasos: prohibido de los dos lados** (opción b, elegida por el usuario). CHECK del lado siguiente, trigger del lado previo. Una instancia recurrente nace al completar la anterior; un paso de una cadena no tiene "próxima instancia" que signifique algo. Consecuencia buscada: `generar_recurrencia` no necesitó tocarse, porque nunca dispara sobre una tarea encadenada.

**Desactivar un paso del medio se bloquea, no se relinkea** (`TA007`, mismo criterio que `validar_quitar_miembro`). Va `AFTER` y no `BEFORE`: `deshacerConversionHilo` desactiva la cadena entera en un solo `.in(...)`, y un `BEFORE` por fila la vería a medio desactivar según el orden. Los `AFTER ROW` corren al final de la sentencia, con todas las filas ya actualizadas — verificado: desactivar la cadena completa pasa, desactivar solo el del medio falla. El `DEFERRABLE INITIALLY DEFERRED` **no** es lo que resuelve ese caso (el `AFTER` solo ya alcanza); suma desmantelar una cadena en varias sentencias dentro de una transacción, que hoy ningún caller hace. Escape hatch de una cadena: desactivar desde la cola.

**Mover de hilo una tarea encadenada se bloquea** (`TA006`). Sin eso el invariante "misma cadena, mismo hilo" se rompe por la puerta de al lado. Efecto colateral aceptado: `deshacerConversionHilo` falla sobre un hilo cuya primera tarea es parte de una cadena — semánticamente correcto (un hilo multi-paso no se puede colapsar en una tarea suelta) y falla antes de tocar nada.

**Los triggers son `SECURITY DEFINER` aunque no llamen a `tiene_permiso()`.** Un guard que la RLS puede dejar ciego no es un guard: si el `EXISTS` del paso siguiente se filtrara por RLS, un usuario que no lo ve rompería la cadena sin que el trigger se entere.

**Misión es vista, sin función propia.** "Crear siguiente paso" es crear una tarea, y crear tareas ya lo gatea `tareas_lista` — una función nueva sería un permiso más fino sin necesidad demostrada. La vista no lee nada que la Lista no lea: reusa `getListaTareas()` (que ya corre `resolver_pospuestos`) y filtra en memoria a mis asignadas, `pendiente`/`en_progreso`, no bloqueadas; el orden sale de `useOrdenTemperatura`, sin query nueva. Backfill del submódulo a todo el que tenía `tareas_lista`, por el mismo motivo.

## Las plantillas generan una cadena

`agregarTareasDesdePlantilla` encadena los items en vez de crear N tareas sueltas: `paso_anterior_id` de cada uno apunta al anterior. `tareas_plantillas_items.orden` siempre significó "primero esto, después aquello" — hasta acá era una sugerencia visual sin consecuencia.

**Sin flag ni checkbox: la plantilla siempre encadena.** Una columna `encadenada` en `tareas_plantillas`, o un check en "usar plantilla", sería una opción que nadie pidió todavía. Si aparece un caso real de plantilla-checklist (items sin orden entre sí), se agrega ahí.

**Un solo INSERT multi-fila, no N inserts.** Depende de que el `BEFORE ROW` de `validar_paso_tarea` en la fila 2 vea la fila 1 de la **misma sentencia** — Postgres procesa las tuplas de a una y el trigger la encuentra. Verificado contra la base y fijado como caso 14 de `sql/tests/pasos_tarea.sql`, porque si esa semántica cambiara la plantilla tendría que insertar de a una fila (N round trips por PostgREST).

**No se puede armar la cadena en dos pasos** (insert plano + update de los `paso_anterior_id`): `paso_anterior_id` es inmutable en UPDATE, y aflojarlo a "NULL → valor" reabriría los ciclos (A sin previo, B con previo A, después A con previo B).

Copy: "Agregar tareas" pasó a "Agregar pasos", y tanto `UsarPlantillaPanel` como `PlantillaFormPanel` dicen que cada paso se habilita al completar el anterior — encadenar sin avisar convierte una plantilla conocida en algo que se comporta distinto.

## Verificación con RLS real (`sql/tests/pasos_tarea.sql`, bloque 2)

Los 14 casos de triggers corrían como `postgres`, que bypasea RLS: probaban los triggers pero no que un usuario común pudiera usar la feature. El bloque 2 cambia a rol `authenticated` con TESTER (sin `tareas_gestionar_ajenas` ni `tareas_asignar`) y verifica lo que faltaba. 5/5.

**La premisa del diseño quedó probada, no supuesta:** TESTER, asignado **solo** al paso 2, ve el paso 1 y la cadena entera — `puede_ver_hilo` cascadea. De eso dependía la decisión de no escribir ninguna regla de visibilidad nueva para los pasos. Si el caso 01 dejara de pasar, "ver las tareas previas" necesitaría una función `SECURITY DEFINER` que devuelva stubs y habría que replantear `sql/017`.

**Los casos de rechazo miran `ROW_COUNT`, no solo la excepción.** Un UPDATE denegado por RLS afecta 0 filas y no tira error: sin ese chequeo, "RLS se lo comió en silencio" se leería como "el trigger funcionó". Mismo problema que ya había motivado alinear los UPDATE con los SELECT en `sql/013`.

Un usuario común puede crear el siguiente paso y asignárselo sin ninguna función extra — confirma que `tareas_lista` alcanza y que no hacía falta un submódulo nuevo para "crear siguiente paso".

## Desactivar un hilo se lleva sus tareas (sin SQL)

`desactivarHilo` desactivaba solo `tareas_hilos`. Las tareas quedaban con
`activo = true` apuntando a un hilo que `getListaTareas` ya no trae, y la vista
Lista las perdía: no son sueltas (`hilo_id !== null`) y su grupo no existe.
RLS seguía devolviéndolas — el trabajo asignado desaparecía de la UI para
todos, incluido quien tiene `tareas_gestionar_ajenas`.

~~La cascada va en el action, no en un filtro defensivo de la vista~~ — **superado
por *Las escrituras multi-tabla bajan a Postgres***: la cascada vive en
`desactivar_hilo()` (`sql/023`) y ya no depende del orden de dos requests. Sigue
en pie lo demás: el estado "hilo inactivo con tareas activas" no debe existir, y
no se resuelve con un filtro defensivo de la vista.

No hace falta permiso extra: `tareas_update` ya tiene la rama del responsable
del hilo, que es exactamente quien puede desactivarlo (`tareas_hilos_update`).

## Isla compartida, panel de proyecto y edición de hilo

> **Revertida en parte** por *La vista Lista es de tareas, el hilo agrupa*: la Lista sí
> muestra tareas del hilo, pero solo las propias. Lo demás de esta sección sigue vigente.

Pedido de usuario, siete puntos (uno — qué pasa con las asignaciones al quitar un miembro — quedó salteado a pedido). Todo se resolvió en UI/TS: **cero SQL**. `tareas_hilos_update` y `tareas_proyectos_update` (`sql/005`) ya autorizan creador / responsable / `tareas_gestionar_ajenas`, que es exactamente quién puede modificar.

**Las tres entidades del módulo comparten cara: `Isla.tsx`.** Hilo, tarea y proyecto se ven igual en cualquier listado (título clickeable + badges + fila de métricas) y el click abre su panel derecho. La isla no tiene acciones propias — todo lo que se hace sobre la entidad vive en su panel. Eso obligó a partir `TareaRow` en dos:

- `TareaCard.tsx` — la isla. Conserva el estado optimista (`estadoLocal`/`tempLocal`) porque la isla los sigue mostrando con el panel cerrado, y porque el orden por temperatura de la vista se refresca mientras se arrastra el slider (`useOrdenTemperatura`). Bajan al panel por props: una sola fuente para el badge y el control.
- `TareaDetailPanel.tsx` — acciones, detalle y notas. "Modificar tarea" pasó del click en el título (que ahora abre el panel) al menú del panel.

`ProyectosView` dejó de ser una lista de filas con `OverflowMenu`: son islas (`ProyectoCard`) y las acciones — modificar, desactivar, agregar hilo/tarea — viven en `ProyectoDetailPanel`. Se conservan búsqueda y paginación.

Piezas compartidas que salieron de ahí: `MetricasResumen.tsx` (antigüedad + próximo vencimiento, antes inline en `HiloCard`), `tareaLabels.ts` (labels/badges de estado, recurrencia, `temperaturaRango`, `iniciales`) y `proyectoTareas.ts` (`tareasDeProyecto`: las tareas de un hilo no guardan `proyecto_id`, lo heredan — isla y panel tienen que contar lo mismo).

**`ProyectoFormPanel` es panel único de crear/modificar y absorbió `MiembrosPanel.tsx`** (borrado): los miembros son una característica más del proyecto, no una pantalla aparte. `gestionarMiembrosProyecto` → `editarProyecto` (mismo diff de quitados/agregados, ver `db_schema.md`). Esto y `MetricasResumen` se recuperaron del stash `9cc8e8e` que se había descartado el 2026-08-18 — el `sql/010` de ese stash **no** se tocó, sigue revertido.

**Editar hilo = solo título y descripción** (ampliado después con visibilidad — ver la sección "Editar hilo incluye la visibilidad" al final). `HiloFormPanel` gana modo edición con el mismo patrón que `TareaFormPanel`: el schema del form sigue siendo `crearHiloSchema` (superset) y proyecto/visibilidad/responsable viajan como defaults ocultos; `editarHiloSchema` (título + descripción + id) es lo que valida el server. Mover un hilo de proyecto queda fuera a propósito: cambiaría quiénes pueden trabajar en sus tareas y esa validación existe sobre `tareas` (`validar_proyecto_tarea`, `sql/009`), no sobre `tareas_hilos`.

**Dueño del hilo visible.** El "owner" es `responsable_id` (no `creado_por`): es quien responde por el hilo. Se muestra en la isla y en el panel; el nombre sale del array `usuarios` que ya llega por props, sin query nueva.

**Visibilidad pública por defecto al elegir proyecto.** Es *default*, no regla: el select sigue ahí y el usuario puede volver a privada. Aplica al abrir el form desde un proyecto y también al elegir proyecto dentro del form, salvo que el usuario ya haya tocado visibilidad (`dirtyFields.visibilidad`) — un default no pisa una decisión explícita. Editar una tarea existente no cambia su visibilidad.

**Filtro por usuario en Proyectos = membresía**, no "tiene tareas ahí": la membresía es quién trabaja en el proyecto (`visibilidad` es el otro eje, quién lo ve) y sale de `miembrosPorProyecto`, que ya llega por props — 0 queries nuevas. Arranca en el usuario actual, mismo default que la vista Lista.


## Editar hilo incluye la visibilidad

Corrige la sección "Módulo tareas — isla compartida…": ahí `visibilidad` quedó bloqueada **de arrastre**, en el mismo bloque que `proyecto_id`, pero el motivo registrado solo aplica al proyecto. Mover un hilo de proyecto cambia quiénes pueden trabajar en sus tareas y ningún trigger lo revalida sobre `tareas_hilos`; cambiar su visibilidad no toca la membresía, solo quién lo ve (`puede_ver_hilo` la lee directo). Con la regla más estricta de `sql/013`, un hilo creado privado no tenía forma de volverse compartible salvo recreándolo.

- `editarHiloSchema` = título + descripción + visibilidad + id. **`visibilidad` va sin `.default()`** ahí, a diferencia de `crearHiloSchema`: en un update, omitirla dejaría el hilo en `privado` sin que nadie lo pida.
- El select de visibilidad sale del bloque `{!hilo && …}` de `HiloFormPanel`. Proyecto y responsable siguen dentro (solo al crear).
- Sin SQL: `tareas_hilos_update` ya autoriza a responsable o `tareas_gestionar_ajenas`, que es el mismo set que muestra el botón "Modificar hilo" en `HiloDetailPanel`.
- Efecto en cascada, buscado: pasar un hilo a privado también esconde sus tareas de quien no esté asignado — `tareas_select` resuelve las tareas con hilo vía `puede_ver_hilo`.

## Editar plantillas (sin SQL)

`editarPlantilla` reusa el mismo `PlantillaFormPanel` con prop `plantilla` (mismo patrón que `TareaFormPanel` para editar tarea) y **no necesitó migración**: `tareas_plantillas_update` / `tareas_plantillas_items_update` ya existían en `sql/005` (gateadas solo por `tiene_permiso('tareas_plantillas')` — la plantilla es un recurso de equipo, no del creador), y los items ya tenían `activo` y `orden`.

**Un solo schema para crear y editar: `id` opcional en cada item.** `plantillaItemSchema` lleva `id?` — presente = paso que ya existe (se actualiza `titulo`/`orden`), ausente = paso nuevo (insert). Los items activos que no vuelven en el submit se desactivan (`activo = false`, nunca DELETE). `crearPlantilla` ignora el `id` porque ya mapeaba columna por columna.

**El `orden` sale de la posición en el form, no de un campo editable** — `items.map((item, i) => ({ ...item, orden: i }))` en el submit, ya era así al crear.

**Editar una plantilla no toca las tareas ya generadas.** `agregarTareasDesdePlantilla` copia los títulos, no referencia los items — así que no hay nada que propagar. El panel lo dice explícito en modo edición para que no se espere lo contrario.

**Un `update` por paso existente en vez de un upsert masivo** — son un puñado de pasos por plantilla; armar un upsert con todas las columnas para ahorrar round-trips no se paga.

## Los items de todas las plantillas llegan en una query (sin SQL)

`getPlantillaItems(plantillaId)` se reemplaza por `getItemsPorPlantilla()`, que trae todos los items activos y los agrupa por `plantilla_id` — mismo patrón que `getMiembrosPorProyecto`. La página llamaba una query por plantilla dentro de un `Promise.all`: N requests para una vista que siempre los quiere todos.

**No cambia lo que ve cada usuario.** `tareas_plantillas_items_select` es plana (`tiene_permiso('tareas_plantillas')`, igual que la de `tareas_plantillas`): la query única devuelve exactamente la unión de las N. El mapa puede incluir items de plantillas desactivadas — `getPlantillas` solo trae las activas y la vista busca por id, así que nunca se leen.


---

# La vista Lista

## La vista Lista es de tareas, el hilo agrupa (sin SQL)

Pedido de usuario: *"si tengo una tarea en hilo ajeno asignado me aparece el hilo entero en mi menú y eso me trae confusión"*, más *"a veces necesito ver los otros trabajos para realizar el mío"*. Solo UI: cero SQL, cero queries nuevas, RLS intacta.

**Revierte parcialmente** la sección *"Módulo tareas — isla compartida, panel de proyecto y edición de hilo"*, donde quedó escrito que la vista Lista no muestra tareas del hilo, solo el panel. No es el mismo diseño volviendo: aquella decisión mostraba **todos** los pasos y por eso molestaba; ahora la Lista muestra **solo los tuyos**, con los ajenos plegados detrás de un toggle.

**Un rol por nivel, sin superposición:** el proyecto es etiqueta (badge), el hilo es agrupador (encabezado de grupo, nunca fila) y la tarea es la única fila accionable. De ahí sale todo lo demás:

- **Se van las secciones `Hilos` / `Tareas sueltas`.** Un solo stream ordenado por temperatura, con filas sueltas y grupos intercalados. Conservarlas dejaba al usuario navegando por contenedor en vez de por urgencia, que era el bug.
- **El grupo se ordena por la temperatura de su paso propio más caliente**, así lo urgente sube tenga hilo o no. Eso necesitó exponer `comparar` desde `useOrdenTemperatura` (`ordenar` no sirve: las dos cosas a comparar viven en listas distintas). Un grupo sin pasos propios no compite y cae al fondo.
- **El contador dice `N tareas`**, no `3 hilos · 9 sueltas`. El hilo agrupa, no cuenta como ítem.
- **Colapsado se ven solo tus pasos; expandido, todos en orden de secuencia** (`created_at` asc, **no** por temperatura) — la pregunta que contesta el expandido es "¿ya está listo lo que necesito para arrancar el mío?", y eso es cronología, no urgencia. No hay columna `orden` en `tareas` y `agregarTareasDesdePlantilla` inserta en orden de plantilla, así que `created_at` **es** la secuencia. No se agrega `depende_de` ni `orden`: la vista contesta la pregunta sin modelar dependencias.
- **Los pasos ajenos van como línea fina de solo lectura (`PasoAjeno.tsx`), no como isla.** La diferencia de peso visual es lo que impide que vuelva el problema original: con el hilo expandido, los tuyos son los únicos que parecen tareas.
- El estado de expansión es local y se pierde al recargar. Persistirlo se agrega cuando moleste.

**Nada de esto necesitó backend.** Los pasos ajenos ya llegaban al cliente (`puede_ver_hilo`, `sql/013`: una asignación activa en cualquier paso te da el hilo entero) y sus notas también (`getListaTareas` las precarga embebidas). Leer la nota de un paso ajeno sí, escribirla no — lo resuelve `tareas_notas_insert` (`sql/013`) más el `puedeAgregar={esAsignado}` que ya estaba. Por eso el preload de `tareas_notas` en `queries.ts`, marcado como desperdicio en la auditoría previa, **se conserva**: es exactamente lo que evita un request por paso ajeno.

### `relacion.ts` — fuente única de "de quién es este trabajo"

`relacionTarea` / `relacionHilo` reemplazan `esDeUsuario()` de `TareasListaView` y el bloque de badge duplicado en `TareaCard`. `creado_por` **no** cuenta (espejo del `USING` de `tareas_select`), así que se borró la rama `Creador` del badge — contradecía `sql/013`, donde crear dejó de dar autoridad y visibilidad. El dueño del hilo es un rol, no una asignación: estar involucrado en el hilo es tener alguna de sus tareas.

### Filtro: segmented control Míos / Involucrado / Todos

Segundo eje, independiente del select de usuario: el select dice *de qué usuario*, el segmented dice *qué relación*. El modelo ya daba el corte gratis — `crearTareaSchema` obliga `responsable ∈ asignados`, así que "responsable" y "asignado" son disjuntos. Solo aparece con un usuario elegido; sin filtro de usuario no hay relación que recortar.

**Arregla un bug de paso.** `hilosFiltrados` mezclaba los dos ejes (`textoMatch && h.responsable_id === asignadoId`): buscar el título de un hilo donde estás involucrado pero no sos dueño lo escondía, salvo que alguna de sus tareas matcheara el texto también. Separar `coincideTexto` de `coincideRelacion` lo elimina.

**Sin filtro de usuario ("Todos los usuarios") la vista no tiene perspectiva**: las filas aparecen porque son visibles, no por tu relación con ellas. Entonces `relacionCon` pasa a `null` — no hay paso ajeno que plegar, no hay badge de relación que explicar y el encabezado del grupo muestra solo `M/N completados`. Antes caía a `usuarioActualId`, que contradecía "pediste ver todo".

### Arrastre: umbrales deduplicados y estado optimista extraído

- `PROXIMA_DIAS` y `estadoVencimiento()` suben a `tareaLabels.ts`. El umbral estaba en tres lugares (`TareaCard`, `TareaDetailPanel`, hardcodeado en `MetricasResumen`) y el bloque de vencimiento duplicado verbatim entre isla y panel.
- **`useTareaOptimista` (nuevo)**: el estado/temperatura optimistas salieron de `TareaCard`. La misma tarea ahora se muestra de dos formas (isla y línea fina) y ambas abren el mismo panel; con una copia del optimismo por componente, un admin con `tareas_gestionar_ajenas` abriendo un paso ajeno habría visto la toolbar con handlers que no hacen nada. Una sola fuente para las dos caras.
- `Isla` gana slot de `children` (hoy solo los pasos de un hilo) — el grupo es la isla del hilo con su contenido adentro, no un contenedor nuevo.
- `relacion.test.ts` corre con `node --test` (Node despoja los tipos solo). Sin runner de tests en el repo y sin agregar uno: por eso `allowImportingTsExtensions` en `tsconfig.json`, que con `moduleResolution: bundler` no cambia nada del build.

### Efecto colateral aceptado

`ProyectoDetailPanel` usa el mismo `HiloCard`, así que sus hilos también muestran los pasos propios inline. No se tocó el archivo y el comportamiento es consistente con la Lista: el hilo agrupa en todos lados o en ninguno.

## Cierre de la auditoría de UI (Lista, plantillas, Misión)

**La Lista arranca ocultando lo terminado.** Toggle "Ocultar terminadas", prendido por defecto: sin él, el histórico completo se acumulaba en la vista para siempre — atenuado y al fondo, pero sin salida. Esconde tareas sueltas terminadas y hilos cerrados o con todos sus pasos terminados; un hilo vacío sigue siendo trabajo por empezar y se muestra.

**Adentro de un hilo no se filtra nada.** Los pasos hechos son el contexto que explica en qué anda la cadena — la pregunta que contesta el hilo expandido es "¿ya está listo lo que necesito?", y esconder lo completado la deja sin respuesta. El filtro es de filas de primer nivel, no de contenido.

**El filtro cuenta como filtro para el estado vacío.** Con todo escondido, la vista decía "Sin tareas todavía / Creá la primera" sobre una cuenta llena de trabajo terminado. Ahora `hayFiltro` incluye las filas ocultas y el mensaje dice cuántas hay y cómo verlas.

**`esTerminada` lee el estado del server, no el optimista.** Completar una tarea con el filtro prendido no la hace desaparecer abajo del dedo: se va con el `revalidatePath`, no con el click.

**La búsqueda de la Lista mira también la descripción**, como ya hacían Proyectos y Plantillas. `coincideTexto` pasa a variádica (`...textos: (string | null)[]`) en vez de duplicar la comparación por campo.

**Los pasos de una plantilla se reordenan con ↑↓** (`useFieldArray.move`). Desde que la plantilla encadena, el orden es la regla — y cambiarlo obligaba a retipear todos los títulos de ahí para abajo. Botones, no drag & drop: no hay librería de dnd en el proyecto y dos flechas resuelven el caso.

**Las bloqueadas de Misión son islas, no filas de texto.** Se renderiza `TareaCard` con su `cadena` y debajo la línea "Espera a «X»": saber qué te frena sin poder abrir lo que te frena era medio camino, y una tarjeta propia hubiera sido una segunda cara de la tarea para mantener sincronizada — el mismo motivo por el que Misión ya usaba `TareaCard`.

**`textoAntiguedad()` en `tareaLabels.ts`.** "Creada hace 0 días" es la fecha de hoy dicha mal y `TareaDetailPanel` además decía "hace 1 días". Un solo texto para la isla, el panel y `MetricasResumen` (que pasa de "Hace N días" a "Creado hoy / hace N días").

**Los estados vacíos de los paneles dicen qué hacer.** "Sin tareas todavía" pasa a nombrar el botón que las crea; en el panel de proyecto solo cuando el usuario puede trabajar ahí (si no, el botón no existe y la instrucción sería mentira).

**No se pone ventana temporal en `getListaTareas` — decidido, con motivo.** La query trae todas las tareas activas con todas sus notas en cada carga de Lista, Misión y Proyectos, y eso crece sin techo. Pero recortar por fecha rompe cosas que hoy funcionan: `cadenasDePasos` arma la cadena con las filas que recibe, así que dejar afuera un paso viejo ya completado corre las posiciones ("Paso 2 de 3" pasa a "Paso 1 de 2"), desalinea el bloqueo y falsea los contadores "N/M terminados". El filtro de terminadas resuelve el problema que se ve (la vista llena de historial) sin tocar los datos que la vista necesita para calcular. Cuando el volumen pese de verdad, el primer paso barato es acotar la **precarga de notas** (`tareas_notas` en `getListaTareas`), no las tareas: `NotasSection` ya sabe pedirlas sola cuando no llegan precargadas. Con el detalle de que los pasos previos del panel leen esas notas precargadas, así que ahí habría que pedirlas por paso al abrir.

---

# Temperatura

## De slider a tres niveles (sin SQL)

Reemplaza el mecanismo descrito en "Orden por temperatura: solo UI, sin columna nueva" y en "Temperatura con rango". El criterio de orden no cambia; cambia cómo se elige el valor.

**Se elige entre Alta / Media / Baja, no entre 100 valores.** El número nunca significó nada para el usuario — `temperaturaRango()` ya existía justo porque "🌡 61" no se lee, y la UI mostraba `Alta (61)`. Un control de 100 posiciones para elegir entre tres etiquetas era precisión inventada. Se va el `(61)` de la isla y del panel.

**La columna sigue siendo `int` 1-100 con su CHECK; cada nivel escribe el centro de su tercio (85 / 50 / 20).** Sin migración, sin tocar `actualizarTemperatura`, y los valores arbitrarios que ya están en la base siguen cayendo en el nivel que les toca. Por eso el botón activo se deriva de `temperaturaRango(temperatura).label`, **no** de `temperatura === nivel.valor`: un 61 histórico tiene que iluminar "Media", no ninguno. Se descartó migrar a enum: obligaba a SQL, backfill y a tocar la action, a cambio de nada que el usuario vea.

**`TEMPERATURA_NIVELES` vive en `tareaLabels.ts`, al lado de `temperaturaRango`.** Los tres niveles y sus umbrales son la misma regla mirada desde los dos lados (escribir / leer); separarlos deja abierta la puerta a que un botón escriba un valor que caiga en otro rango.

**Desempate explícito en `useOrdenTemperatura.comparar`: vence antes → más vieja.** Con 100 valores el orden era total de hecho; con tres niveles hay empates grandes y el desempate caía en el orden del query (`created_at` desc, la más nueva arriba). Lo que vence antes manda dentro del nivel, y entre las que no vencen gana la más vieja. Es más honesto que "la puse en 91 en vez de 90".

**`cambiarTemperatura` y `commitTemperatura` se funden en una sola función async.** Un clic *es* el cambio completo: no existe el "mientras se arrastra" que obligaba a separar input de commit y a colgar `onMouseUp`/`onTouchEnd`/`onKeyUp`/`onBlur` del `<input type="range">` (un range no tiene evento "listo"). El panel recibe `onTemperaturaChange` en vez de las dos props.

**El rollback ahora también revierte el override de orden.** `useTareaOptimista` reseteaba `temperatura` cuando el server rechazaba, pero no avisaba a `useOrdenTemperatura`: la fila quedaba ordenada por un valor que no existía. Se arregló al fundir las funciones, no antes, porque con el slider el commit fallaba después de N onChange y no había un "valor anterior" único.

**Costo aceptado: se pierde el ranking fino dentro de un nivel.** Nadie lo estaba usando como ranking; el desempate por vencimiento cubre el caso real ("de estas tres altas, ¿cuál primero?").

**En Misión las flechas ← → dejan de competir con nada.** Los botones no consumen flechas y solo existen dentro del panel (un `dialog`), que ya estaba excluido.


---

# Vista Misión

## UI de pasos y vista Misión

**"Agregar paso" pasó a llamarse "Convertir en hilo".** El menú de una tarea suelta ya usaba ese label para `convertirTareaEnHilo`, que no agrega ningún paso: convierte la tarea en hilo para poder sumarle tareas. Con pasos reales en el módulo el nombre viejo pasaba a mentir. Tercera colisión del mismo término — las plantillas también llaman "pasos" a sus items (`plantillaItemSchema`), que son títulos ordenados sin bloqueo; eso quedó sin tocar.

**"Crear siguiente paso" aparece solo en la cola de la cadena** (`posicion === total`) y solo si la tarea tiene hilo. La unique parcial de `paso_anterior_id` no deja bifurcar, así que ofrecerlo en el medio sería ofrecer un `23505`.

**Bloqueada esconde "Completar" y la opción "En progreso", no "Cancelada".** Espejo exacto de `validar_paso_previo`, que solo corta esas dos transiciones. Cancelar tiene que seguir disponible o una cadena con un paso trabado no se cierra nunca. El panel además dice cuál es el paso que la traba, en vez de dejar el botón gris sin explicación.

**El panel muestra la cadena entera, no solo la previa.** El pedido era "ver tareas previas"; mostrar la lista completa con la posición marcada cuesta lo mismo y contesta también "cuánto falta". El estado del paso actual sale del estado optimista del panel y no de la fila del server — misma regla que `tareaLabels.ts`: la misma tarea no puede leerse distinto según dónde se la mire.

**`agruparCadenas()` mantiene contigua cada cadena dentro del hilo.** El orden por temperatura se respeta para elegir dónde arranca la cadena, pero sus miembros salen juntos y en orden. Sin eso una cadena se lee como tareas sueltas y pierde lo único que la distingue de un hilo.

**`esDeUsuario` y `esActiva` salieron a `tareaFiltros.ts`.** El primero vivía en `TareasListaView`, el segundo inline en `MetricasResumen`; Misión necesitaba los dos. Regla de "si existe en más de un lugar, se extrae" — no se duplicó para la vista nueva.

**Misión renderiza `TareaCard`, no una tarjeta propia.** Toda la superficie de acciones (completar, estado, temperatura, panel de detalle) ya vive ahí; una tarjeta "de misión" sería una segunda cara de la misma tarea para mantener sincronizada. Lo propio de la vista es el recorte y la navegación de a uno.

**El índice de Misión se recorta, no se resetea.** Al completar la tarea actual la cola se acorta y la misma posición pasa a mostrar la siguiente — que es lo que se espera de una vista "de a una". Un `useEffect` que resetee a 0 mandaría al usuario de vuelta al principio en cada completada.

**Misión esconde las tareas de hilos pospuestos**, no solo las tareas pospuestas: si el hilo espera, su contenido no es "lo que toca ahora". El estado vacío dice cuántas tareas están esperando un paso previo — si no, una Misión vacía con trabajo bloqueado se lee como una vista rota.

## Retoques de UI de Misión

Todo en `MisionView.tsx`. No se tocó `TareaCard` ni ninguna query: la vista sigue siendo recorte + navegación sobre lo que ya lee la Lista.

**Columna centrada `max-w-2xl`.** Una isla sola estirada a los 1280px del `<main>` no se lee como foco, se lee como una lista de un elemento. Misión es la única vista del módulo con un solo item en pantalla, así que el ancho lo pone ella y no el layout.

**Flechas ← → recorren la cola.** Se ignoran si hay un `dialog[open]` (el panel de detalle y los modales viven en el top layer, fuera de este árbol) o si el foco está en un `INPUT`/`SELECT`/`TEXTAREA`. El clamp del índice usa `total`, no el `posicion` del render: apretar de más al final dejaría el índice colgado lejos y habría que apretar N veces para volver.

**Barra de progreso = posición en la cola, no trabajo hecho.** No hay dato de "cuánto del total completé" sin leer `tareas_eventos`; la barra dice dónde estoy parado en la cola de hoy, que es lo mismo que el contador de texto y evita que el contador sea el único ancla visual.

**Línea de contexto (proyecto · hilo) arriba de la tarjeta.** Ni la isla ni su meta lo muestran — no es duplicación, es dato que en la Lista aporta el agrupamiento y acá no existe. El proyecto sale del hilo cuando la tarea tiene hilo (`CHECK (hilo_id IS NULL OR proyecto_id IS NULL)`: la tarea con hilo no guarda `proyecto_id`).

**La descripción se muestra en la vista, no solo en el panel.** Es la única excepción a "Misión renderiza `TareaCard` y nada más" y es deliberada: texto plano de solo lectura, sin estado ni acciones, así que no hay una segunda cara que sincronizar (el motivo real de aquella decisión). Una vista de a una que obliga a abrir un panel para leer qué hay que hacer no es una vista de a una.

**"Sigue: <título>" debajo de la tarjeta.** Una tarjeta sola no comunica que hay una cola detrás; el contador lo dice en número y esto en contenido.

**Las bloqueadas pasan de contador a lista desplegable (`Bloqueadas`, local al archivo).** Antes el estado vacío decía "N tareas esperan un paso previo" sin decir cuáles ni a qué esperan — el dato está en `PasoEnCadena.cadena[posicion - 2]`, que ya se calcula. El mismo bloque aparece con cola llena y con cola vacía; es el único caso del módulo donde saber qué te frena importa más que la tarea que tenés adelante.

**El estado vacío pasa a `.empty-state`.** Era el único del módulo con markup propio (texto centrado suelto). Ícono según el caso: `CircleCheck` verde si de verdad no queda nada, `Lock` ámbar si lo que queda está todo bloqueado — no son la misma noticia.


---

# Auditorías de UI del módulo

Los hallazgos app-wide de estas mismas tandas están en `decisiones/global.md`.

## Pasos previos legibles

**El panel de una tarea con pasos muestra los previos enteros y con sus notas.** `TareaDetailPanel` ya listaba la cadena completa (título + badge de estado); los pasos anteriores al actual dejan de truncar y cuelgan sus notas debajo. Los posteriores siguen siendo una línea: todavía no dicen nada. Las notas ya viajan precargadas por `getListaTareas` (`tareas_notas`), así que no hay query nueva — solo aplica a tareas encadenadas, no a tareas sueltas ni a pasos de hilo sin `paso_anterior_id`, que no tienen sección de cadena.

**La cadena ahora también existe en la vista Lista.** `HiloCard` calcula `cadenasDePasos(tareasDelHilo)` y se la pasa tanto a `TareaCard` como a `PasoAjeno`. Antes solo Misión y `HiloDetailPanel` la pasaban: abrir el mismo paso desde la Lista no mostraba ni "Paso 2/3", ni "Bloqueada", ni los pasos previos. Rompía la regla del propio módulo (`tareaLabels.ts`): la misma tarea no puede leerse distinto según dónde se la mire.

**El modal automático "¿Cerrar hilo?" respeta permisos.** `HiloCard` lo disparaba en cualquier card montada al completarse el último paso, incluso para un asignado sin autoridad sobre el hilo — `cerrarHilo` moría en la RLS. Ahora usa el mismo `puedeGestionar` que `HiloDetailPanel` para ofrecer la acción.

**Una sola definición de "terminada": `esTerminada()` en `tareaFiltros.ts`.** El contador de la isla contaba solo `completada` y el cierre automático del hilo miraba `completada || cancelada` — la card decía "2/3 completados" y saltaba igual el modal de cierre. `contarCompletadas` pasa a `contarTerminadas` y el copy a "N/M terminadas" en hilo y proyecto. Una cancelada no deja trabajo pendiente; contarla como faltante era mentir sobre lo que queda por hacer.

**El select de estado muestra "En progreso" aunque la tarea esté bloqueada, deshabilitado.** `reabrir_hilo_en_tarea` puede bloquear una tarea que ya estaba en progreso; sin su opción el `<select>` caía en "Pendiente" y mostraba un estado que la tarea no tenía. Se ve, no se puede elegir — espejo de `validar_paso_previo`, que corta la transición pero no borra el estado actual.

**`ESTADO_LABEL` deja de estar duplicado.** `DeshacerConversionModal` y `AuditoriaView` tenían copias locales (una de ellas parcial: sin `completada`/`cancelada`) mientras `tareaLabels.ts` es la fuente. `recurrencia_cantidad` en `TareaFormPanel` pintaba `input-error` sin renderizar nunca el mensaje: caja roja sin motivo.

## Feedback y formularios

**Toda acción que sale bien lo dice.** `quitarDeHilo`, `convertirEnHilo`, `moverAHilo` y las cuatro desactivaciones (tarea, hilo, proyecto, plantilla) solo toasteaban el error; el éxito era cerrar el panel — y `quitarDeHilo` ni eso, porque no cierra nada. Regla del guide: el usuario nunca se queda preguntando si funcionó.

**Cancelar una tarea pide confirmación.** Era un cambio de `<select>` y la tarea salía de todas las colas; completar, que es menos destructivo, ya tenía modal. Solo `cancelada` pasa por `ConfirmModal` — pendiente y en progreso son reversibles y no la sacan de ningún lado. El select vuelve solo al estado real al abrirse el modal porque es controlado (`value={estado}`).

## Jerarquía visual de la isla (auditoría de diseño, sin SQL)

**La temperatura ordena la lista y ahora se ve: barra izquierda de 3px en `Isla`.** `useOrdenTemperatura` es el eje primario de orden en Lista y Misión, pero la temperatura era un span gris más dentro de `meta` — y "Baja" no tenía color siquiera. Tarjetas idénticas apiladas sin decir por qué esa está arriba. La barra cuesta cero altura, se lee de un vistazo y reusa la escala semántica: `temperaturaRango()` pasa a devolver también `barra` (rampa neutro → ámbar → rojo, no verde: la temperatura es urgencia, no un estado que esté bien o mal). Solo la tarea la pasa — hilo y proyecto no tienen temperatura propia.

**Con la barra, el span de temperatura sale de la meta.** No es un `title=` encubierto ni contradice "en touch no hay hover" (`P1 responsive y legibilidad`): la barra es permanente, no un estado de hover, y el nivel sigue existiendo como texto y como control en el panel, a un tap de distancia. Lo que se saca es la repetición, no la información.

**Dos niveles en la meta de `TareaCard`.** Podía llevar 7 spans `t-caption` grises del mismo peso: nada distinguía "vence mañana" de "vino de la app X", y `flex-wrap` no es jerarquía — es la misma información en más líneas. Ahora arriba va lo que cambia la decisión de qué hacer ahora (vencimiento o antigüedad, pospuesta, avatares) a 13px `font-medium`; abajo el contexto (privada, recurrencia, origen) unido en una sola línea `t-caption` con `·`. Sigue siendo texto — un ícono pelado habría revertido de callado la decisión de P1.

**Un conteo no es un estado.** `Paso N/M` deja de ser badge y pasa a texto `t-caption`, igual que "N/M terminados" en hilo y proyecto. Los badges quedan para estado y bloqueo, que sí son la situación de la tarea; cuatro pills del mismo tamaño en la misma fila no jerarquizaban nada.

**Misión usa la misma isla con `grande`, no una tarjeta propia.** Título en `t-h2`, más aire, contexto desplegado en vez de comprimido en una línea. Es una variante de `Isla`, no un componente nuevo: la razón por la que Misión ya usaba `TareaCard` (no mantener una segunda cara de la tarea sincronizada) sigue valiendo.

**La isla avisa que se abre: chevron permanente.** Era un `<button>` sin borde de hover, sin ícono, sin nada — y `GUIDE_DESIGN` prohíbe el hover como única señal. De paso el título deja de ser un `<p>` dentro de un `<button>`, que no es HTML válido.

**Atenuar con color, no con `opacity`.** `opacity-60` bajaba junto el contraste de texto, borde y badges: una tarea terminada quedaba con texto a ~2.8:1, abajo de AA. Ahora la isla atenuada cambia a `bg-bg-subtle` y su título a `text-text-tertiary`.

**El selector de nivel usa la escala semántica, no el navy de marca.** Elegir "Alta" lo pintaba `btn-primary` (#011F51) y al cerrar el panel la tarjeta lo mostraba rojo: dos lenguajes de color para el mismo valor. El estado activo sale de `temperaturaRango(nivel.valor).selector`, así que la escala tiene un solo dueño.

**El contador de la Lista sale de `Paginacion`, como sus tres tabs hermanas.** Proyectos, Plantillas y Auditoría lo renderizan dentro del componente (fila `justify-between`); la Lista lo tenía como un `<p>` suelto, a otra altura y otra alineación. Las props de paginado pasan a ser opcionales: sin ellas el componente es solo el contador. **La Lista sigue sin paginar** — decidido en "P2 — búsqueda, paginación y contador", esto toca dónde se dibuja el contador, no si se pagina.

**Formularios en dos columnas para los campos cortos** (design system §8: grid 2 columnas / 14px gap). `TareaFormPanel` apilaba ocho campos full-width en un panel de 448px. Proyecto + Visibilidad y Vencimiento + Temperatura entran de a dos y cortan el scroll a la mitad; en `HiloFormPanel`, Proyecto + Visibilidad. Abajo de `sm` vuelven a apilarse. Los otros paneles de form del módulo (proyecto, plantilla, usar plantilla, posponer) quedan en una columna: tienen uno o dos campos cortos y una lista alta, y apretar el campo principal a 197px no compra nada.

**Los presets de vencimiento son chips, no botones.** `btn btn-secondary btn-sm` los dejaba con el mismo peso que el "Cancelar" del footer del mismo panel. Son atajos de relleno del campo de arriba, no acciones del formulario.

**La fila de Auditoría se apila abajo de `sm`.** A 390px la cadena `Creada → Asignada → Completada` tomaba tres líneas y truncaba el título a ~10 caracteres.


---

# Tutorial guiado por vista (`sql/019_tutorial.sql`)

Tooltips en secuencia sobre los elementos reales de cada vista: la primera vez se abren solos, y el botón `?` al lado del `<h1>` los vuelve a pasar cuando el usuario quiera. Sin librería nueva — `<dialog>` + `showModal()`, el mismo mecanismo de top layer que `Modal.tsx` y `RightPanel.tsx`.

## El código del paso es también su selector

`PasoTutorial.codigo` es la clave que se guarda en `usuario_tutorial.paso` **y** el ancla en el DOM (`[data-tour="tareas_lista_isla"]`). Un solo identificador en vez de dos que puedan desincronizarse: renombrar el paso rompe el ancla en el mismo commit, no seis meses después.

El guion vive en `tutorialPasos.ts` (`PASOS_POR_RUTA`), al lado de `tareaLabels.ts` — texto, no lógica.

## Un paso sin ancla se saltea y queda sin ver

El tutorial no lista pasos: pregunta al DOM cuáles existen ahora. Un paso cuyo elemento no está — porque el permiso no está dado (`tareas_proyectos_crear`), porque el filtro que lo muestra está apagado (el segmentado de relación), o porque todavía no hay datos (la lista de tareas) — no se muestra **y no se marca como visto**.

Consecuencia buscada: cuando después se habilita el permiso, el paso aparece como pendiente y el tutorial se abre solo con eso. Explicar hoy un botón que el usuario no tiene sería enseñarle una función que no puede usar; guardar "ya lo vio" sería peor, porque se la perdería para siempre.

Es también la razón por la que el estado es *por paso* y no un booleano *por vista*: con un flag por vista, un permiso otorgado más tarde no tiene forma de volver a contarse.

## Persistencia en Postgres, no en `localStorage`

`usuario_tutorial` con RLS directa (`usuario_id = auth.uid()`), mismo criterio que `usuario_widgets`: preferencia estrictamente propia, sin `tiene_permiso` de por medio, así que el server action usa el cliente normal. `localStorage` era más barato pero cuenta por navegador — el mismo usuario en la máquina de la obra volvería a ver el tutorial entero.

Sin columna `activo`: la fila significa "visto" y nunca se borra ni se desactiva. Volver a ver el tutorial es el botón, no un reset de datos.

`marcarTutorialVisto` no llama a `revalidatePath`: los pasos vistos solo se leen al montar el layout y el cliente ya sabe cuáles marcó. Falla en silencio — no es una acción del usuario sino la contabilidad de qué se le mostró, y el peor caso es que el tutorial se vuelva a ofrecer.

## Un solo componente en el layout, no uno por vista

`Tutorial.tsx` se monta en `tareas/layout.tsx` y elige el guion con `usePathname`. El botón tiene que estar al lado del `<h1>`, que es del layout, y navegar entre tabs no vuelve a montarlo — de ahí la copia local de lo visto (`vistosLocal`), sin la cual volver a una tab recién vista lo reabría.

El `<h1>` pasa a vivir en un flex con el botón; el `mb-4` se mueve al contenedor. La estructura obligatoria del encabezado (ícono + nombre del `ICON_MAP`) no cambia.

## El ancla de los tabs sale de la prop que ya existía

`ModuleTabs` recibía `modulo` sin usarla. Ahora emite ``data-tour={`${modulo}_tabs`}`` — el componente sigue siendo genérico, no aprende nada de tareas, y cualquier módulo que sume tutorial tiene el ancla de sus tabs gratis. Cuando hay una sola tab el componente devuelve `null` y el paso se saltea solo.

## Foco por sombra, no por recorte

El elemento señalado se rodea con un `<div>` de `box-shadow: 0 0 0 9999px rgba(7,11,20,.55)` — el mismo color de backdrop del resto del sistema. Oscurece todo salvo el agujero y de paso intercepta los clicks a la página. Un ancla más alta que la pantalla (la lista entera) se recorta al viewport: sin eso el agujero se sale y el globo no tiene dónde apoyarse.

## El guion explica lo que no se ve, no lo que se lee

No hay paso para el buscador ni para la paginación: una lupa con placeholder no necesita tutorial. Los pasos son para lo que la interfaz no puede decir sola — que "Míos" e "Involucrado" son disjuntos, que ser miembro de un proyecto es quién puede recibir tareas y no quién lo ve, que el orden de los pasos de una plantilla es lo que encadena, que una tarea bloqueada no entra en la cola de Misión.

Efecto secundario buscado: ningún componente de `components/ui/` recibe un `data-tour`. Todas las anclas están en elementos que el módulo ya renderizaba.


---

# Robustez de `actions.ts`

## Un UPDATE rechazado deja de devolver `success` (sin SQL)

Auditoría de arquitectura, primera tanda (`PLAN_ARQUITECTURA_TAREAS.md`, puntos 1 y 4).

**Un UPDATE que RLS rechaza no tira error: afecta 0 filas y vuelve limpio.** Los 26 `.update()` del módulo miraban solo `error`, así que editar una tarea sin permiso mostraba el toast de éxito, cerraba el panel y dejaba la fila intacta — el peor modo de falla posible, porque el usuario no tiene motivo para dudar. Ahora los updates que apuntan a filas puntuales van con `{ count: "exact" }` y pasan por `errorDeUpdate()`, que devuelve mensaje si hubo error **o** si `count === 0`.

**Dónde no se aplica, a propósito:** la cascada de `desactivarHilo` sobre `tareas` (`.eq("hilo_id", …)`) — un hilo sin tareas afecta 0 filas y es correcto. En `sincronizarAsignados` el desactivar pasó a estar guardado por `previos.length > 0`: con esa guarda 0 filas ya no es ambiguo, y de paso deja de emitirse un statement que no tenía nada que desactivar.

**`sincronizarAsignados` devuelve mensaje, no `PostgrestError`.** Sus dos callers hacían `mensajeError(...)` sobre lo que devolvía; ahora el mapeo vive en un solo lado y la función puede reportar tanto un error de Supabase como el conteo en cero, que no es un `PostgrestError`.

**Las 9 actions que no validaban ahora lo hacen** (`convertirTareaEnHilo`, `desactivarProyecto`, `desactivarPlantilla`, `cambiarEstadoTarea`, `desactivarHilo`, `desactivarTarea`, `asociarTareaHilo`, `desasociarTareaHilo`, `actualizarTemperatura`), más `listarNotasTarea` y `listarNotasHilo`, que son lecturas pero también son `"use server"` invocables por RPC. Schemas nuevos en `types.ts`: `uuidSchema`, `cambiarEstadoTareaSchema`, `asociarTareaHiloSchema`, `temperaturaSchema`. Las firmas no cambian — reciben ids sueltos y se parsean adentro; convertirlas a objetos habría tocado 12 componentes sin ganar nada. La validación manual de `actualizarTemperatura` pasa a un `.refine()` con el mismo mensaje, para que la regla viva donde viven las demás.

---

# Contexto de la UI del módulo

## Las seis props compartidas pasan a un Context (sin SQL)

Auditoría de arquitectura, punto 6 de `PLAN_ARQUITECTURA_TAREAS.md`.

`usuarios`, `proyectos`, `miembrosPorProyecto`, `usuarioActualId`, `gestionarAjenas` y `puedeAsignar` viajaban idénticas por 16 componentes: ~149 atributos JSX de puro reenvío, y `Bloqueadas` en `MisionView` recibía nueve props para usar tres. Ninguna se transformaba en el camino — se verificó que los 149 reenvíos fueran `x={x}` literal antes de tocar nada.

Ahora las arma la page (server) y las entrega `TareasContextoProvider`; cada componente pide con `useTareasContexto()` solo lo que usa, y eso queda visible en la primera línea de su cuerpo. Neto: −367 líneas, +91.

**Por qué Context y no un solo prop objeto.** Agrupar las seis en `ctx` bajaba los 149 reenvíos a ~30 pero dejaba el drilling intacto: las hojas que usan dos de las seis seguían recibiendo el paquete entero, y agregar un séptimo dato seguía tocando la cadena. El Context es la primera capa nueva del módulo, y se paga sola: son datos de solo lectura que la page arma una vez por request y que **toda** la UI necesita.

**No es estado.** El provider recibe el valor ya calculado en el server y no lo muta: se renueva con el `revalidatePath`, igual que antes. Por eso no hay `useState` ni memo adentro — un objeto nuevo por render del server es exactamente lo que se quiere.

**`ReasignarPanel` pierde su `puedeAsignar` forzado.** Pasaba `puedeAsignar` literal a `AsignadosPicker`; ahora el picker lo lee del contexto. Da lo mismo: el panel entero **es** la función `tareas_asignar` — `TareaDetailPanel` no ofrece "Reasignar" sin ella, así que el valor del contexto ya es `true` cuando el panel existe.

**Límite:** los componentes del módulo solo renderizan dentro del provider. Hoy los únicos que los montan son las tres pages (`/tareas`, `/tareas/mision`, `/tareas/proyectos`); el hook tira error explícito si alguien los usa afuera, en vez de dibujar una lista de usuarios vacía.

---

# Tipos y tests de la lógica pura

## Las etiquetas de estado se atan al enum (sin SQL)

Auditoría de arquitectura, punto 7 de `PLAN_ARQUITECTURA_TAREAS.md`.

`ESTADO_LABEL` y `ESTADO_BADGE` eran `Record<string, string>`: cualquier string indexaba y el resultado era `string`, no `string | undefined`. Un typo o un valor nuevo del enum se renderizaba vacío sin que TS dijera nada. Ahora son `Record<EstadoTarea, string>`, con `EstadoTarea = Enums<"estado_tarea">` en `types.ts` — mismo patrón que ya usa `comercial/types.ts`. Agregar un valor a `estado_tarea` en Postgres rompe la compilación hasta que los dos mapas tengan su fila, que es el punto.

**Arrastre.** `TareaPendiente.estado` y la prop `estado` de `TareaDetailPanel` estaban tipadas `string` a mano sobre datos que ya venían del enum; bajaron a `EstadoTarea`, y el `?? p.estado` de `AuditoriaView` —un fallback que nunca podía dispararse— se fue con ellas. `RECURRENCIA_LABEL` y el parámetro `estado` de `estadoVencimiento` entraron por el mismo defecto, en el mismo archivo.

## `cadenaPasos.ts` tiene test

Punto 8. Once casos con `node --test`, mismo criterio que `relacion.test.ts` (sin runner ni dependencias nuevas).

Cubre lo que decide: `bloqueada` mira el paso previo inmediato y no el arranque de la cadena, `cancelada` no desbloquea al siguiente, una raíz cuyo `paso_anterior_id` no está en la lista visible arranca bloqueada, el orden de entrada no cambia la cadena, los pasos comparten el array `cadena` por referencia, y `agruparCadenas` deja cada cadena contigua sin repetir ni inventar filas.

**El ciclo no llega a recorrerse.** El test de datos cíclicos afirma que el mapa vuelve vacío, no que el `Set` de vistos frene el recorrido: como `siguiente` tiene una sola entrada por `paso_anterior_id`, un ciclo nunca es alcanzable desde una raíz — ninguno de sus miembros es raíz y la cadena entera queda afuera. La guarda del `for` sigue siendo barata y se queda, pero no es lo que evita el cuelgue.

# Construcción inicial

> **Único bloque cronológico del archivo.** Es donde viven las trampas de RLS y de forms
> que costaron sesiones y no se deducen del código. Partes de la UI que describe ya no
> existen: cada párrafo superado está tachado con el puntero a lo que lo reemplaza.
>
> **Renombres que atraviesan todo el bloque:** `TareaRow` se partió en `TareaCard` (isla)
> + `TareaDetailPanel` (acciones y detalle); `HiloCard` perdió el listado de tareas, que
> pasó a `HiloDetailPanel`. Un párrafo que dice `TareaRow` habla de los dos.

## UI del módulo (Lista, Proyectos, Plantillas, Auditoría)

Backend (SQL + `types.ts`/`permissions.ts`/`queries.ts`/`actions.ts`) venía de una sesión anterior, ya corrido en Supabase. Esta sesión agregó la UI completa (`modules/tareas/components/` + `app/(erp-app)/tareas/`).

**"Usar plantilla" vive en `HiloCard`, no en la vista Plantillas.** `agregarTareasDesdePlantilla` siempre necesita un `hilo_id` destino — la vista Plantillas quedó como catálogo puro (crear/listar/desactivar), sin función propia de "usar" (coincide con el seed de `submodulos`: `tareas_plantillas` no tiene función separada).

**`agregarTareasDesdePlantilla` no tenía `safeParse` server-side** (actions.ts pre-existente) — regla "Validar en dos lugares" es de las Reglas Siempre Activas. Se agregó `agregarDesdePlantillaSchema` en `types.ts` y se cambió la firma de la action a recibir un solo objeto validado, mismo patrón que el resto de `actions.ts`.

**Forms con campos `.default()` en el schema: tipar `useForm<T>` con `z.input<schema>`, no `z.infer`/`z.output`.** `zodResolver` espera el tipo de *entrada* (pre-default) como `FieldValues`; usar el tipo de salida rompe la inferencia de `Resolver<...>` con un error de TS que no deja ver la causa real. `crearTareaSchema` ya tenía este patrón (`CrearTareaForm = z.input<...>`); se replicó en `CrearHiloForm`, `CrearProyectoForm`, `CrearPlantillaForm` (los tres tienen `visibilidad`/`orden` con `.default()`).

**`<select>` con opción "vacía" sobre un campo `uuid().nullish()`: falla la validación con `""`, no con `undefined`.** Mismo motivo que `fechaOpcional` (ya documentado en `types.ts`) — se agregó `uuidOpcional` (`z.union([uuid, literal(""), null, undefined]).transform(v => v || null)`) para `proyecto_id` en `crearTareaSchema`/`crearHiloSchema`.

~~**Gate de UI para acciones de tarea (`TareaRow`) es una aproximación a la RLS, no un espejo exacto.**~~ **Superado por `sql/013`** — `creado_por` salió de la visibilidad y de los `USING`, así que los gates pasaron a responsable / asignado / miembro (ver *Ser creador deja de dar visibilidad*). Lo que sigue valiendo es el criterio: ocultar el botón es UX, el servidor rechaza igual. Texto original: `esAsignado` (creador/responsable/asignado activo/`tareas_gestionar_ajenas`) habilita estado/temperatura/completar/posponer/mover-hilo/desactivar; `puedeGestionar` (creador/responsable/`tareas_gestionar_ajenas`, sin asignado simple) habilita reasignar — porque `tareas_asignados_insert/update` en RLS no incluye "ser un asignado más". Ocultar el botón es solo UX; el servidor rechaza igual si algo queda mal calculado acá.

**Sincronizar estado local con props sin `useEffect(setState)`:** React Compiler (`react-hooks/set-state-in-effect`) lo marca error, no warning. Patrón usado en `TareaRow` para `estadoLocal`/`tempLocal` (optimistic UI que debe reconciliar tras `revalidatePath`): guardar el último valor de prop visto en un state paralelo (`estadoBase`) y comparar/actualizar durante el render, no en un efecto — es el patrón "adjusting state during render" de la doc de React.

**RLS: dos tablas cuyas policies se consultan mutuamente → `42P17 infinite recursion detected in policy`.** Se dio en `tareas_proyectos` ↔ `tareas_proyectos_miembros` (el SELECT de una hace `EXISTS` sobre la otra y viceversa) y en `tareas` ↔ `tareas_asignados` (mismo patrón, más un caso de `tareas_asignados_select` con `EXISTS` sobre sí misma). Recién apareció al testear en browser porque es la primera vez que se ejercita `/tareas` logueado — `npx tsc` y los checks de código no detectan recursión de RLS. **Fix:** envolver el lado "de vuelta" del `EXISTS` en una función `SECURITY DEFINER STABLE SET search_path = public` (mismo criterio que `puede_ver_hilo`) — `es_creador_proyecto`, `es_responsable_o_creador_tarea`, `es_asignado_tarea` (`sql/005`, corregido directo en el archivo + migración aplicada en Supabase). Regla para toda policy nueva que necesite mirar otra tabla RLS-protegida: si esa otra tabla puede necesitar mirar hacia atrás, usar función `SECURITY DEFINER`, no `EXISTS` directo.

**`INSERT ... RETURNING` (`.insert().select()` de supabase-js) sobre una tabla cuya policy de SELECT es una función `SECURITY DEFINER` que vuelve a consultar esa misma tabla → `new row violates row-level security policy`, aunque la misma función devuelva `true` llamada aparte.** Pasó en `crearHilo` (`tareas_hilos_insert` pasa, pero el RETURNING re-chequea `tareas_hilos_select` → `puede_ver_hilo(id)` → `SELECT ... FROM tareas_hilos WHERE id = ...` — esa sub-consulta no ve la fila recién insertada dentro del mismo statement, aunque una consulta aparte sí la vea). No pasa con `tareas`/`tareas_proyectos` porque sus funciones de apoyo (`puede_ver_hilo`, `es_creador_proyecto`) consultan una tabla *distinta* a la que se está insertando. **Fix:** en `crearHilo` (`actions.ts`), generar el `id` con `crypto.randomUUID()` antes del insert y no pedir `.select()` — evita el RETURNING por completo. Regla: un INSERT sobre una tabla cuya SELECT policy se apoya en una función que relee esa misma tabla no puede pedir `.select()` en el mismo insert; si se necesita el id, generarlo client-side.


## Retoques contra la spec funcional (`resumen-todo-app-erp.md`)

Sesión posterior comparó el módulo ya construido contra la spec funcional original y encontró gaps. Confirmados con el usuario los puntos ambiguos, se implementó lo siguiente (sin tocar SQL — todo reusa columnas/tablas existentes):

**§1 Conversión tarea→hilo (Opción A)** — ~~`agregarPasoATarea`~~ se reemplazó después por `convertirTareaEnHilo` (ver *Fixes de UI pedidos*), y el label del menú pasó a "Convertir en hilo" (ver *UI de pasos y vista Misión*): se mantiene el botón "Nuevo hilo" explícito (lo necesitan las plantillas, que exigen `hilo_id` destino) y se suma `agregarPasoATarea` — botón "Agregar paso" en una tarea suelta que crea el hilo *por detrás* (mismo resultado que la spec, sin pantalla de "convertir" separada). El `creado_por` del hilo y del nuevo paso es siempre quien ejecuta la acción, no el `creado_por` de la tarea original — `tareas_hilos_insert`/`tareas_insert` exigen `creado_por = auth.uid()` en su `WITH CHECK`, así que copiar el `creado_por` original rompería la inserción si no coinciden. Gateado a `puedeGestionar` (creador/responsable/`tareas_gestionar_ajenas`) por el mismo motivo que ya aplica a Reasignar/mover-hilo — la inserción también exige `responsable_id = auth.uid()` salvo `ajenas`.

**§1 Deshacer conversión:** `deshacerConversionHilo` — decisión confirmada con el usuario: se conserva como tarea suelta la más antigua del hilo (por `created_at`), el resto se desactiva (`activo = false`, nunca DELETE). Siempre disponible (no bloqueada); `DeshacerConversionModal.tsx` muestra el checklist de qué se conserva/desactiva y solo agrega el aviso de pérdida cuando hay 2+ tareas o alguna completada.

**§4 Métricas de hilo:** `HiloCard` calcula "Hace X días" (desde `created_at`) y "Próxima tarea vence en X días" (mínimo `fecha_vencimiento` entre tareas activas del hilo, ignorando pospuestas — las ocultas por privacidad ya las filtra RLS antes de llegar al array).

**§5 Modal de cierre automático:** `CerrarHiloModal` (checklist visual) se dispara solo, sin `useEffect`, comparando una "firma" de estados de las tareas del hilo contra la última vista (mismo patrón de `estadoBase`/`estadoLocal` que ya usa `TareaRow` para no violar `react-hooks/set-state-in-effect`). Se muestra una sola vez por transición a "todo completo"; "Mantener abierto" la descarta hasta el próximo cambio real de estado. El botón manual "Cerrar hilo" reusa el mismo componente.

**§9 Auditoría:** se agregó fecha de creación (`tareas.created_at`) y fecha de asignación por evento. Esta última no tiene FK directa a `tareas_eventos` — se resuelve con una segunda consulta a `tareas_asignados` (sin filtrar `activo`, para no perder el dato si después reasignaron la tarea) armando un mapa `tarea_id:usuario_id → primera fecha`. Se agregó `getPendientesUsuario` — panorama de tareas incompletas del usuario filtrado, visible en `AuditoriaView` solo cuando hay un usuario seleccionado (con "todos" seleccionado no se arma, sería una lista completa del equipo sin foco claro). El rediseño a heatmap/Kanban que sugiere la spec (§10) se dejó sin tocar — es "preferir", no requisito, y la lista plana ya cubre los datos duros pedidos.

**§10 Badges:** recurrencia y vínculo con app externa pasan a ser ícono + tooltip (antes no existían); "pospuesta" pasa de badge de texto a ícono + tooltip (antes badge-warning) para no competir con el color de la fecha. Se sacó el badge "Vencida" — ahora el color (neutro/ámbar/rojo) va directo sobre el texto de la fecha de vencimiento. Tareas sin vencimiento muestran "Creada hace X días" con la misma lógica de color invertida. Umbrales (`PROXIMA_DIAS=3`, `ANTIGUEDAD_AMBAR_DIAS=14`, `ANTIGUEDAD_ROJO_DIAS=30`) quedaron como constantes fijas en `TareaRow.tsx`, no configurables — la spec pide "umbral configurable" pero no hay todavía un segundo caso real que justifique una UI de settings para esto (simplicidad antes que abstracción). Avatares de multi-asignado ahora se superponen (margin negativo) y el del usuario actual queda con outline propio.

**Deliberadamente no implementado — §6 (botón "Realizar tarea", deep link, `modo_completado` en la UI):** la spec ya marca este punto como "pendiente de definir con detalle... a retomar cuando exista una segunda aplicación real en el sistema", y hoy no existe ninguna. `origen_app`/`origen_punto`/`modo_completado` siguen en el schema y en `crearTareaSchema` pero no se exponen en `TareaFormPanel` — construir la UI de integración ahora sería adelantarse a un caso que todavía no existe (misma regla que ya frenó el diseño de una capa de integración genérica en la spec original). Retomar cuando haya una segunda app real.


## Notas, panel de proyecto, "Mis tareas", islas (`sql/008`)

**Notas — historial, no campo único.** Confirmado con el usuario: `tareas_notas`/`tareas_hilos_notas` (`sql/008`), append-only (sin UPDATE de texto, `activo` solo para ocultar una nota propia). SELECT vía `EXISTS` directo sobre la tabla padre (`tareas`/`tareas_hilos`) — no hace falta función `SECURITY DEFINER` porque la referencia es de ida sola (la policy de la tabla padre no mira hacia las de notas), a diferencia de los pares que sí necesitaron romper recursión (`tareas_proyectos` ↔ `tareas_proyectos_miembros`, etc.). `listarNotasTarea`/`listarNotasHilo` viven en `actions.ts` (no en `queries.ts`) aunque son lecturas — `queries.ts` no tiene `"use server"`, así que no es invocable por RPC desde un Client Component; `NotasSection.tsx` (nuevo, reusado por `TareaRow` y `HiloDetailPanel`) necesita poder llamarlas. Fetch on-mount del componente (que solo se monta cuando el usuario abre la sección) — sin precarga de notas de todo lo visible en la página.

**Visibilidad por defecto: `privado` (antes `publico`).** `ALTER COLUMN ... SET DEFAULT` en `tareas`, `tareas_hilos`, `tareas_proyectos` (`sql/008`) + mismo default en los tres schemas Zod (`crearTareaSchema`/`crearHiloSchema`/`crearProyectoSchema`) + `defaultValues` de los tres FormPanel. Filas existentes no se tocan.

**Vista "Mis tareas" → vuelve a "Lista": se revirtió el filtro a propios.** **Parcialmente superado** — el segmentado Míos / Involucrado / Todos y el corte de pasos ajenos son de *La vista Lista es de tareas, el hilo agrupa*; `esDeUsuario()` se movió a `relacion.ts` y ya no vive en la vista. Sigue valiendo el motivo del rollback: El filtro `esPropia` de `TareasListaView` (restringía a creador/responsable/asignado activo, sin excepción para `tareas_gestionar_ajenas`) se sacó: la visibilidad la decide RLS y nada más. Un usuario sin `tareas_gestionar_ajenas` sigue viendo solo lo suyo porque la política de `tareas`/`tareas_hilos` no le devuelve el resto (`sql/005`); un manager ve todo, que es lo que el permiso significa. Motivo del rollback: el filtro era solo de nivel superior — `HiloCard` recibía `tareas` completo y listaba todas las tareas del hilo igual, así que la vista mostraba "propias" con contenido ajeno adentro. Label del tab vuelve a "Lista" en `layout.tsx` (`tareas_lista` sigue siendo el código de permiso — el label es un string local del layout, no viene de `submodulos.nombre`). El filtro "Todos los asignados" se restauró como `<select>` en la toolbar, con **default en el usuario actual** (`useState(usuarioActualId ?? "")`): "lo mío" pasa a ser un default, no una restricción — el panorama del equipo queda a un click y lo sigue acotando RLS. Semántica del filtro: `esDeUsuario()` matchea `responsable_id` OR asignado activo, igual para cualquier usuario elegido (ver más abajo: nació como `estaInvolucrado()` con `creado_por` y se corrigió). Un hilo entra si coincide él mismo (título + `responsable_id`) o si alguna de sus tareas coincide. La opción vacía se llama "Todos los usuarios" (no "Todos los asignados": el filtro ya no es solo por asignación).

~~**Orden por temperatura: solo UI, sin columna nueva.**~~ **Superado** — el slider se fue, ver *De slider a tres niveles*. `useOrdenTemperatura` sobrevive y la decisión de no agregar columna sigue en pie. Texto original: El usuario aclaró explícitamente que no quería trackear "cuándo cambió" (eso hubiera pedido una columna `temperatura_actualizada_at`, porque `updated_at` ya se pisa con cualquier otra edición) — quería temperatura más alta arriba, reordenando en vivo mientras se arrastra el slider. `useOrdenTemperatura` (hook nuevo, sin persistencia) mantiene un mapa `id → valor en vivo` actualizado en cada `onChange` del range (no solo al soltar) y ordena `tareas sueltas` desc por ese valor (con fallback a `tarea.temperatura` para las no tocadas). Reusado en `TareasListaView` y `ProyectoDetailPanel`. Los hilos no tienen temperatura propia — no se reordenan.

**Completadas y canceladas al fondo + atenuadas.** `ordenar()` usa clave primaria `peso` (activa 0, cerrada 1) y desempata por temperatura: una tarea cerrada en 90 no debe competir con una pendiente en 40. `TareaRow` suma `opacity-60` cuando `!activa` — se sigue viendo lo hecho sin que gane la atención. Se descartó esconderlas por antigüedad ("completadas de hace +7 días"): `tareas` no tiene columna `completada_at`, habría que leer `tareas_eventos` o agregar columna, costo alto para el problema. También se descartó agruparlas en isla plegable: en un hilo rompe la lectura de la secuencia de pasos.

**Badge de relación (`relacionCon`) en `TareaRow`.** Badge `badge-neutral` "Responsable"/"Creador" al lado del estado, con `title` que incluye el nombre. Solo se muestra si ese usuario **no** está entre los asignados activos — si lo está, el avatar ya lo explica y el badge sería ruido. El prop es el usuario cuya relación se explica, no el actual: `TareasListaView` pasa `asignadoId || usuarioActualId` (sigue al filtro, así el badge dice por qué esa fila matcheó), `ProyectoDetailPanel` pasa `usuarioActualId`. Se drillea por `HiloCard` → `HiloDetailPanel` → `TareaRow`, igual que `gestionarAjenas`.

**HiloCard se parte en dos: `HiloCard` (isla resumen) + `HiloDetailPanel` (RightPanel nuevo).** **Parcialmente revertido** — la Lista volvió a mostrar tareas del hilo, pero solo las propias (ver *La vista Lista es de tareas, el hilo agrupa*). La partición en dos componentes se mantiene. Pedido explícito: la vista Lista no debe mostrar tareas ni acciones del hilo inline, solo en un panel lateral. `HiloCard` ahora solo header + métricas (días transcurridos, próxima fecha) y abre `HiloDetailPanel` al click — que es quien tiene el listado de `TareaRow`, los botones de acción (agregar tarea/plantilla/cerrar/posponer/deshacer/desactivar) y la sección de notas del hilo. El disparo automático del modal de cierre (`mostrarCierreAuto`, §5 spec) se queda en `HiloCard` (debe poder aparecer con el panel cerrado); el botón manual "Cerrar hilo" vive en `HiloDetailPanel` y reusa el mismo `CerrarHiloModal`.

**`TareaRow` perdió su borde propio — el contenedor decide el wrapping.** Antes tenía `border-b` fijo (pensado para una lista continua). Ahora se usa en 3 contextos con look distinto: isla propia con `rounded-lg border` (tareas sueltas en "Mis tareas" y en `ProyectoDetailPanel`) vs. fila con `border-b` dentro de una lista continua (`HiloDetailPanel`, tareas del hilo). Se sacó el borde de `TareaRow` y cada padre envuelve con el estilo que corresponde — evita una prop de estilo condicional dentro del componente.

**"Islas": `TareasListaView` separa hilos de tareas sueltas en dos grupos con label (`t-label`), cada item con su propio `rounded-lg border` — ya no una lista continua con `border-b` entre filas.** Mismo criterio aplicado en `ProyectoDetailPanel`.

**Panel de proyecto (`ProyectoDetailPanel`, nuevo) — confirmado con el usuario: muestra TODO lo visible del proyecto, no filtra a "propio".** Botón "Ver tareas" en cada fila de `ProyectosView` lo abre; reusa `HiloCard`/`TareaRow` (mismas islas que "Mis tareas") filtrando por `proyecto_id`. "Agregar tarea"/"Agregar hilo" reusan `TareaFormPanel`/`HiloFormPanel` con un `proyectoId` nuevo (prop opcional) que preselecciona y oculta el `<select>` de proyecto — mismo patrón que ya usaba `hiloId` en `TareaFormPanel`. Requirió que `proyectos/page.tsx` sume `getListaTareas()` + `getPlantillas()` (antes solo pedía proyectos/miembros).


## Fixes de UI pedidos (editar tarea, presets, conversión, notas)

Los tres cambios de `components/ui/` de esta tanda (`RightPanel` y `Modal` a `<dialog>`,
`OverflowMenu` con `fixed`) están en `decisiones/global.md`.

**Editar tarea: `TareaFormPanel` sirve crear y editar (prop `tarea`), no un componente nuevo.** El resolver sigue siendo `crearTareaSchema` (superset) y en modo edición `responsable_id`/`asignados` viajan como defaults ocultos: se cambian por "Reasignar", que ya es la única autoridad sobre `tareas_asignados`. El submit llama `editarTarea`, que valida con `editarTareaSchema` — extiende un `tareaEditableSchema` nuevo (base común con `crearTareaSchema`) y descarta las claves de más que manda el form. Gate de UI: `esAsignado` (creador/responsable/asignado activo/`ajenas`), que es exactamente el `USING` de `tareas_update`. El disparador es el título de la tarea, no toda la fila — la fila ya tiene select/range/botones adentro y anidar interactivos rompe accesibilidad.

**"Agregar paso" ya no pide un título: convierte y abre el panel del hilo.** `agregarPasoATarea` (creaba hilo + un 2do paso con título pedido en un panel) se reemplazó por `convertirTareaEnHilo(tareaId)`: crea el hilo con título/descripción/visibilidad/proyecto/responsable de la tarea, mueve la tarea adentro y no crea ningún paso extra — los pasos se agregan desde el panel del hilo, que la UI abre sola. `AgregarPasoPanel.tsx` y `agregarPasoSchema` se eliminaron. La apertura automática es una prop `autoAbrir` en `HiloCard`: la card del hilo nuevo puede montarse antes o después de que el padre marque el id (según cuándo llegue el `revalidatePath`), así que reacciona al cambio de prop **durante el render** con el patrón `autoAbrirBase` (mismo criterio que `estadoBase`/`sigBase` — `react-hooks/set-state-in-effect` es error, no warning).

**Notas de tarea visibles por defecto y precargadas en la query, no fetch por fila.** `mostrandoNotas` arranca en `true` (el botón "Notas" ahora colapsa, no carga), y `getListaTareas` trae `tareas_notas(...)` embebido — con la sección abierta en cada fila, el fetch on-mount de `NotasSection` serían N requests (cada uno con su `auth.getUser()`). `activo` y el orden de las notas se resuelven en JS: filtrar un embed en PostgREST lo convierte en inner join y se perderían las tareas sin notas. `NotasSection` acepta `notasIniciales` y saltea el fetch inicial cuando lo recibe; las notas de hilo siguen pidiéndose on-mount (el panel del hilo se abre de a uno).

**Notas: el `<textarea>` aparece recién al apretar "Agregar nota".** Con la lista de notas visible por defecto en cada tarea, un textarea por fila llenaba la vista de inputs vacíos. El historial se sigue viendo siempre; el input es on-demand y se cierra solo al guardar.

**Orden por temperatura también en `HiloDetailPanel`.** Mismo `useOrdenTemperatura` que "Mis tareas"/`ProyectoDetailPanel` — los pasos del hilo se reordenan en vivo al arrastrar el slider.

**`TareaRow`: se fue el botón "Notas" y las notas se muestran siempre.** Con la lista de notas + "Agregar nota" ya visibles en cada fila, el toggle no agregaba nada. En el menú de acciones "Posponer" pasó al primer lugar (antes "Reasignar") — es la acción más frecuente.

**Presets de vencimiento (1/3/7 días) en `TareaFormPanel`.** Botones que hacen `setValue("fecha_vencimiento", sumarDiasISO(hoyISO(), n))` sobre el mismo `<input type="date">` — sin campo ni estado nuevo. Los días viven en `VENCIMIENTO_PRESETS` en el componente; no se hizo configurable (mismo criterio que los umbrales de `TareaRow`).

## Las escrituras multi-tabla bajan a Postgres

Punto 2 de `PLAN_ARQUITECTURA_TAREAS.md`. Seis actions escribían dos o más tablas con statements separados. Cada `.from().insert()` de PostgREST es su propia transacción, así que un fallo en el segundo dejaba el primero cometido. El modo de falla peor es `crearTarea`: si el insert de `tareas_asignados` falla, la tarea queda `activo = true` e **invisible para todos** — `tareas_select` no mira `creado_por` (`sql/013`), así que ni quien la creó la ve, y sin verla no puede corregirla. Igual en `crearProyecto` (proyecto privado sin miembros), `convertirTareaEnHilo`, `deshacerConversionHilo`, `desactivarHilo` y `agregarTareasDesdePlantilla`.

Las seis pasan a funciones `SECURITY INVOKER` en `sql/023`, llamadas con `.rpc()`: `crear_tarea`, `crear_proyecto`, `convertir_tarea_en_hilo`, `deshacer_conversion_hilo`, `desactivar_hilo`, `agregar_tareas_desde_plantilla`. El cuerpo corre en una sola transacción y **RLS se sigue evaluando con la identidad de quien llama** — la autoridad no se mueve de las policies, que es lo que descarta `SECURITY DEFINER` acá (sería mover autorización adentro de la función). `actions.ts` queda como glue: `safeParse` → `.rpc()` → `revalidatePath`, y bajó de 920 a 797 líneas.

**Los ids se siguen generando antes del INSERT, ahora con `gen_random_uuid()` en una variable.** El motivo no cambió al mudarse a SQL: `RETURNING` exige pasar por la policy de SELECT, y en ese punto la fila todavía no es visible (la tarea no tiene asignados, el proyecto no tiene miembros, `puede_ver_hilo` relee su propia tabla).

**`errorDeUpdate()` se vuelve `TA008` adentro de la función.** Un UPDATE que RLS rechaza afecta 0 filas y vuelve sin error; el chequeo que en TypeScript era `{ count: "exact" }` acá es `IF NOT FOUND THEN RAISE`. Mismo texto de mensaje, ahora en `MENSAJES_ERROR` (`TA008`). `TA009` es la plantilla sin pasos. `errorDeUpdate` sigue vivo para las actions de una sola tabla, que no se tocaron.

**`agregar_tareas_desde_plantilla` pasa de un INSERT multi-fila a un loop.** El INSERT agrupado existía para ahorrar round-trips desde el server; adentro de la función no hay round-trips que ahorrar, y el loop expresa la cadena directamente (`v_anterior` es el `paso_anterior_id` del siguiente).

**`deshacer_conversion_hilo` conserva el orden del TypeScript** — primero restaura la más antigua, después desactiva el resto. Invertirlo cambiaría comportamiento: si algo activo tiene a la más antigua como paso previo, `validar_paso_tarea` corta con `TA006`, y con el resto ya desactivado no cortaría. Ese rechazo es el que ya existía y no se toca en esta tanda.

**Los params nullable se marcan a mano en `database.types.ts`.** El generador de Supabase emite `p_descripcion: string` para un parámetro que acepta NULL. Mismo arreglo manual que ya tenía `guardar_obra_persona` — si se regeneran los tipos, hay que volver a ponerlos.

Verificado con `sql/tests/atomicidad_tareas.sql`, 15/15. El test alterna rol en los dos sentidos dentro del mismo `DO`: `authenticated` para llamar las funciones, y `role = none` para **contar**. Contar como `authenticated` haría pasar todos los casos de atomicidad en falso — las filas huérfanas son justamente las que RLS esconde. El caso 00b verifica que el regreso al usuario de sesión ocurre de verdad.

## Las ediciones multi-tabla siguen el mismo camino (`sql/024`)

Cola de la tanda anterior. `editarTarea`, `reasignarTarea` y `editarProyecto` quedaron afuera de `sql/023` porque su modo de falla es otro: no producen filas huérfanas invisibles sino una fila **inconsistente pero visible** — el título ya cambiado con los asignados viejos, o el proyecto renombrado con la membresía sin actualizar. Se ve y se puede corregir a mano; por eso no entraron en la misma tanda, no porque el arreglo fuera distinto. Pasan a `editar_tarea`, `reasignar_tarea` y `editar_proyecto`, mismo criterio `SECURITY INVOKER`.

**`sincronizarAsignados()` se muda entero a SQL.** Era el único escritor de `tareas_asignados` sobre una tarea que ya existe, y sus dos callers son justamente dos de las tres funciones nuevas: dejarlo en TypeScript habría partido la operación en dos transacciones otra vez. Baja como `sincronizar_asignados(uuid, uuid[])`, con el corte por conjunto igual intacto (editar el título no reescribe asignaciones) y la guarda `previos > 0` antes del desactivar.

**El helper lleva `GRANT` a `authenticated`, no queda privado.** Una función `SECURITY INVOKER` llamada desde otra exige `EXECUTE` al rol que invoca, así que "helper interno" no es una opción sin mover el schema. Que PostgREST la exponga no agrega superficie: `tareas_asignados` ya acepta INSERT/UPDATE directo del cliente bajo las mismas policies, así que lo que la función permite ya se podía hacer a mano. La invariante "el responsable está entre los asignados" sigue viviendo solo en Zod — no se agregó al SQL en esta tanda porque tampoco la protegía antes.

**El orden de los statements se conserva, y es carga semántica, no forma.** En `editar_tarea` primero la fila y después los asignados, porque `validar_proyecto_tarea` valida el cambio de `proyecto_id` contra los asignados de ese momento; invertirlo cambiaría contra qué conjunto se valida. En `editar_proyecto` la membresía sigue siendo un diff calculado adentro de la función — desactivar todo y reinsertar dispararía `validar_quitar_miembro` (`TA001`) sobre los miembros que se quedan.

Con esto `errorDeUpdate()` queda solo para las actions de una sola tabla; las multi-tabla del módulo ya no pasan por él. Verificación: `sql/tests/atomicidad_edicion_tareas.sql`, mismo andamiaje de doble rol que el test de `023`, con los casos de rechazo comparando el estado posterior contra el previo.
