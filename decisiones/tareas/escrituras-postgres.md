# Escrituras multi-tabla en Postgres (`sql/023`–`025`)

## Las escrituras multi-tabla bajan a Postgres

Punto 2 de `obsoletos/PLAN_ARQUITECTURA_TAREAS.md`. Seis actions escribían dos o más tablas con statements separados. Cada `.from().insert()` de PostgREST es su propia transacción, así que un fallo en el segundo dejaba el primero cometido. El modo de falla peor es `crearTarea`: si el insert de `tareas_asignados` falla, la tarea queda `activo = true` e **invisible para todos** — `tareas_select` no mira `creado_por` (`sql/013`), así que ni quien la creó la ve, y sin verla no puede corregirla. Igual en `crearProyecto` (proyecto privado sin miembros), `convertirTareaEnHilo`, `deshacerConversionHilo`, `desactivarHilo` y `agregarTareasDesdePlantilla`.

Las seis pasan a funciones `SECURITY INVOKER` en `sql/023`, llamadas con `.rpc()`: `crear_tarea`, `crear_proyecto`, `convertir_tarea_en_hilo`, `deshacer_conversion_hilo`, `desactivar_hilo`, `agregar_tareas_desde_plantilla`. El cuerpo corre en una sola transacción y **RLS se sigue evaluando con la identidad de quien llama** — la autoridad no se mueve de las policies, que es lo que descarta `SECURITY DEFINER` acá (sería mover autorización adentro de la función). `actions.ts` queda como glue: `safeParse` → `.rpc()` → `revalidatePath`, y bajó de 920 a 797 líneas.

**Los ids se siguen generando antes del INSERT, ahora con `gen_random_uuid()` en una variable.** El motivo no cambió al mudarse a SQL: `RETURNING` exige pasar por la policy de SELECT, y en ese punto la fila todavía no es visible (la tarea no tiene asignados, el proyecto no tiene miembros, `puede_ver_hilo` relee su propia tabla).

**`errorDeUpdate()` se vuelve `TA008` adentro de la función.** Un UPDATE que RLS rechaza afecta 0 filas y vuelve sin error; el chequeo que en TypeScript era `{ count: "exact" }` acá es `IF NOT FOUND THEN RAISE`. Mismo texto de mensaje, ahora en `MENSAJES_ERROR` (`TA008`). `TA009` es la plantilla sin pasos. `errorDeUpdate` sigue vivo para las actions de una sola tabla, que no se tocaron.

**`agregar_tareas_desde_plantilla` pasa de un INSERT multi-fila a un loop.** (Borrada en `sql/053`: la reemplaza `usar_plantilla`, que mantiene el loop y crea cada paso por `crear_tarea`.) El INSERT agrupado existía para ahorrar round-trips desde el server; adentro de la función no hay round-trips que ahorrar, y el loop expresa la cadena directamente (`v_anterior` es el `paso_anterior_id` del siguiente).

**`deshacer_conversion_hilo` conserva el orden del TypeScript** — primero restaura la más antigua, después desactiva el resto. Invertirlo cambiaría comportamiento: si algo activo tiene a la más antigua como paso previo, `validar_paso_tarea` corta con `TA006`, y con el resto ya desactivado no cortaría. Ese rechazo es el que ya existía y no se toca en esta tanda.

**Los params nullable se marcan a mano en `database.types.ts`.** El generador de Supabase emite `p_descripcion: string` para un parámetro que acepta NULL. El `| null` se agrega a mano: si se regeneran los tipos, hay que volver a ponerlos.

Verificado con `sql/tests/atomicidad_tareas.sql`, 15/15. El test alterna rol en los dos sentidos dentro del mismo `DO`: `authenticated` para llamar las funciones, y `role = none` para **contar**. Contar como `authenticated` haría pasar todos los casos de atomicidad en falso — las filas huérfanas son justamente las que RLS esconde. El caso 00b verifica que el regreso al usuario de sesión ocurre de verdad.

## Las ediciones multi-tabla siguen el mismo camino (`sql/024`)

Cola de la tanda anterior. `editarTarea`, `reasignarTarea` y `editarProyecto` quedaron afuera de `sql/023` porque su modo de falla es otro: no producen filas huérfanas invisibles sino una fila **inconsistente pero visible** — el título ya cambiado con los asignados viejos, o el proyecto renombrado con la membresía sin actualizar. Se ve y se puede corregir a mano; por eso no entraron en la misma tanda, no porque el arreglo fuera distinto. Pasan a `editar_tarea`, `reasignar_tarea` y `editar_proyecto`, mismo criterio `SECURITY INVOKER`.

**`sincronizarAsignados()` se muda entero a SQL.** Era el único escritor de `tareas_asignados` sobre una tarea que ya existe, y sus dos callers son justamente dos de las tres funciones nuevas: dejarlo en TypeScript habría partido la operación en dos transacciones otra vez. Baja como `sincronizar_asignados(uuid, uuid[])`, con el corte por conjunto igual intacto (editar el título no reescribe asignaciones) y la guarda `previos > 0` antes del desactivar.

**El helper lleva `GRANT` a `authenticated`, no queda privado.** Una función `SECURITY INVOKER` llamada desde otra exige `EXECUTE` al rol que invoca, así que "helper interno" no es una opción sin mover el schema. Que PostgREST la exponga no agrega superficie: `tareas_asignados` ya acepta INSERT/UPDATE directo del cliente bajo las mismas policies, así que lo que la función permite ya se podía hacer a mano. La invariante "el responsable está entre los asignados" sigue viviendo solo en Zod — no se agregó al SQL en esta tanda porque tampoco la protegía antes.

**El orden de los statements se conserva, y es carga semántica, no forma.** En `editar_tarea` primero la fila y después los asignados, porque `validar_proyecto_tarea` valida el cambio de `proyecto_id` contra los asignados de ese momento; invertirlo cambiaría contra qué conjunto se valida. En `editar_proyecto` la membresía sigue siendo un diff calculado adentro de la función — desactivar todo y reinsertar dispararía `validar_quitar_miembro` (`TA001`) sobre los miembros que se quedan.

Con esto `errorDeUpdate()` queda solo para las actions de una sola tabla; las multi-tabla del módulo ya no pasan por él. Verificación: `sql/tests/atomicidad_edicion_tareas.sql`, mismo andamiaje de doble rol que el test de `023`, con los casos de rechazo comparando el estado posterior contra el previo.

## Archivar un proyecto se lleva lo que hay adentro (`sql/025`)

Venía del `BACKLOG.md`: `desactivarProyecto` desactivaba solo la fila del proyecto. Sus hilos y sus tareas sueltas quedaban activos — el trabajo no desaparecía de la Lista, pero perdía la agrupación y quedaba apuntando a un proyecto archivado que ya no se lista. Archivar es "se va todo junto", no "se sueltan las partes", y así queda simétrico con `desactivar_hilo`, que se lleva sus tareas desde `sql/023`.

**Trigger, no una función `.rpc()` más.** Las seis de `sql/023` bajaron a funciones porque eran actos del usuario que tocaban dos tablas. Esta cascada no es un acto aparte: es la consecuencia de archivar. Como trigger `AFTER UPDATE ... WHEN (OLD.activo AND NOT NEW.activo)` la regla vale para cualquier escritor de `activo = false` sobre `tareas_proyectos`, y `desactivarProyecto` se queda como el UPDATE de una sola tabla que ya era — no cambió ni una línea de su cuerpo.

**`SECURITY DEFINER`, y la autorización no se movió a la función.** Es la excepción al criterio del punto 3 del plan de arquitectura, y por un motivo concreto: quien archiva un proyecto es su creador-miembro o un manager (`tareas_proyectos_update`), y eso **no** le da UPDATE sobre los hilos de adentro, que exigen ser responsable del hilo o `tareas_gestionar_ajenas`. Con `SECURITY INVOKER` la cascada se frenaba contra RLS en silencio —0 filas no es error— y dejaba el proyecto archivado con media estructura viva, que es peor que no cascadear. El permiso del acto sigue viviendo en la policy del UPDATE que dispara el trigger: si esa no pasa, el trigger no llega a correr. El caso 08/09 del test es exactamente eso: TESTER no puede tocar de frente un hilo cuyo responsable es otro, y archivando el proyecto se lo lleva igual.

**Lo que no cae.** Los miembros del proyecto: no son trabajo, y su SELECT ya exige el proyecto activo (`sql/016`). Y reactivar el proyecto no revive nada — archivar es de ida, igual que con los hilos.

**Efecto lateral que se cierra solo.** El select de proyecto en `TareaFormPanel` aparecía vacío al editar una tarea de un proyecto archivado (`puedeTrabajarEnProyecto` lo filtra) sobre un `proyecto_id` todavía seteado. Ya no puede pasar: no queda ninguna tarea activa apuntando a un proyecto archivado.

**El modal dice cuánto se lleva.** No hay reactivar de proyecto en la UI, así que la confirmación pasó a nombrar los hilos y las tareas que se van. Cuenta lo visible en el panel, que es de lo que el usuario puede hacerse una idea — la cascada, por debajo, se lleva también lo que su RLS no le muestra.

Verificación: `sql/tests/cascada_proyecto.sql` (10/10).

## Deshacer con pasos, fecha de Argentina y largos (`sql/078`)

Fase 3 de la auditoría del 2026-09-17 (`sql/tests/auditoria_tareas.sql`, bloque F3).

**`deshacer_conversion_hilo` desactiva el resto antes de mover la primera.** Con pasos encadenados, sacar del
hilo a la tarea más antigua mientras su siguiente seguía activo daba siempre `TA006`, así que la conversión no
se podía deshacer.

**La zona horaria va en cada función, no en la base.** La base corre en UTC, y entre las 21 y las 24 de
Argentina `current_date` ya es el día siguiente: un pospuesto volvía un día antes y un plazo "tras el anterior"
sumaba uno de más. `ALTER DATABASE ... SET timezone` lo arreglaba en una línea, pero cambia el formato de todos
los `timestamptz` que lee la app y el `current_date` de Obras. `SET timezone` en las seis funciones que calculan
fechas de tareas acota el cambio a lo que estaba mal.

**Los largos también en la base, más holgados que Zod.** Por la API entraban textos de megas. El tope no puede
ser el de Zod porque `rellenar_datos` expande `{dato}` después de validar el form: un título de 200 con el
nombre de una obra adentro lo superaría.

El punto 16 de la auditoría (asignados `NULL` en `crear_tarea`) no era un bug: `asignados_con_acceso` devuelve
un array vacío y la tarea queda para quien la crea. Lo confirma el caso 06.

Archivos: `sql/078_tareas_bugs_fecha_y_largos.sql`, `sql/tests/auditoria_tareas.sql`, `sql/tests/plantillas.sql`
(fechas comparadas en hora AR).
