# Notificaciones (`sql/038_notificaciones.sql`, `sql/040`, `sql/055`, `sql/056` — corridas en Supabase vía MCP)

Infra cross-módulo como `usuario_widgets` y `usuario_tutorial`: prefijo `usuario_`, RLS directo por `auth.uid()`, **sin submódulo y sin vista propia**. Nadie necesita permiso para recibir avisos de cosas que ya puede ver — el permiso lo puso la entidad apuntada, no la notificación.

## usuario_notificaciones

**La notificación apunta, no copia.** Guarda a qué fila se refiere y el texto se arma al leer, con la RLS del que lee. Copiar el título rompería `sql/013` desde la campanita: quien pierde la asignación dejaría de ver la tarea pero seguiría leyendo su nombre en la bandeja.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | destinatario |
| tipo | enum `tipo_notificacion` (`alta_aprobada`\|`alta_rechazada`\|`obra_transferida`\|`tarea_asignada`\|`plantilla_modificada`\|`plantilla_archivada`\|`plantilla_fallida`\|`plantilla_disparada`\|`plantilla_sin_acceso`) | los tres primeros de plantilla, `sql/055`; `plantilla_disparada`, `sql/056`; `plantilla_sin_acceso`, `sql/063` |
| entidad | text | CHECK `obra`\|`empresa`\|`persona`\|`obra_empresa`\|`obra_persona`\|`tarea`\|`plantilla`. Text y no enum: es el discriminador de a qué tabla apunta `entidad_id`, mismo vocabulario y misma forma que `obras_aprobaciones.tipo` |
| entidad_id | uuid | sin FK — apunta a varias tablas |
| actor_id | uuid FK → usuarios, nullable | quién lo provocó. Null = evento del sistema |
| leida_at | timestamptz, nullable | |
| activo | boolean | descartar sin borrar |
| created_at / updated_at | timestamptz | |

**RLS:** SELECT y UPDATE con `usuario_id = auth.uid()`. **Sin policy ni GRANT de INSERT** — la escribe `notificar()`, que es `SECURITY DEFINER` y solo se llama desde triggers: una notificación insertable por el cliente sería un canal para escribirle a otro usuario. `GRANT SELECT` + `GRANT UPDATE (leida_at, activo)` — GRANT por columna porque RLS no acota columnas.

## Función `notificar(usuario, tipo, entidad, entidad_id, actor)`

`SECURITY DEFINER`. Único lugar donde nace una notificación, y donde vive "no te notifiques a vos mismo". `IS DISTINCT FROM` y no `<>`: con `auth.uid()` NULL (service_role, SQL editor) la comparación daría NULL y el aviso se perdería en silencio.

## Los triggers

| trigger | tabla | destinatario |
|---|---|---|
| `trg_notificar_decision_obra` | `obras_aprobaciones` AFTER INSERT | `obras_solicitante(tipo, registro_id)` — `alta_aprobada` o `alta_rechazada` según `aprobada` |
| `trg_notificar_transferencia_obra` | `obras_transferencias` AFTER INSERT | `a_usuario_id` |
| `trg_notificar_tarea_asignada` | `tareas_asignados` AFTER INSERT OR UPDATE OF activo | `usuario_id`, solo cuando la fila pasa a activa |
| `trg_notificar_cambio_plantilla` (`sql/055`) | `tareas_plantillas` AFTER UPDATE | quienes tienen activada la plantilla — `plantilla_modificada` si sigue activa, `plantilla_archivada` si pasó a `activo = false`. Solo alcance `sistema`: una privada tiene un único activador, que es quien la edita |

**Al que le sacaron la obra no se le avisa.** Ya no la ve (`obras_select` es `obras_puede_ver_obra`): un aviso con el nombre sería la única grieta del módulo y uno sin el nombre no diría nada. Esa pregunta la contesta `obras_auditoria_transferencias`.

**`pg_trigger_depth() > 1`** en el de tareas filtra la copia de asignados de `generar_recurrencia`: una tarea diaria mandaría un aviso por día a cada asignado, y ahí nadie asignó a nadie. **Excepción (`sql/055`):** las tareas de un disparo de plantilla también nacen adentro de un trigger, pero ahí sí asignó alguien. `disparar_plantillas()` marca la transacción con `set_config('tareas.disparo', 'on', true)` y el filtro deja pasar esas.

**Guardar sin cambios también avisa:** `guardar_plantilla` siempre hace el UPDATE y reemplaza los pasos, así que no sabe si algo cambió.

## Función `notificar_disparo(p_plantilla_id, p_corrio, p_sin_acceso DEFAULT false)` (`sql/056`, reemplaza a `notificar_plantilla_fallida` de `sql/055`; `sql/063` suma `p_sin_acceso`)

`SECURITY DEFINER`, con EXECUTE para `authenticated` porque la llama `disparar_plantillas()`, que es INVOKER. Le escribe a `auth.uid()` —quien cambió el estado y tenía la plantilla activada—, con actor NULL, uno de tres tipos por prioridad: `plantilla_fallida` si no corrió; si no, `plantilla_sin_acceso` si algún paso dejó a alguien afuera (`p_sin_acceso`, `sql/063`); si no, `plantilla_disparada` (un aviso por plantilla, no por tarea). El tipo sale de los booleanos, así que por acá no se escribe otro aviso. Fuera de un trigger (`pg_trigger_depth() = 0`) no hace nada: por RPC no se fabrican avisos. `p_sin_acceso` tiene DEFAULT, así que las llamadas viejas de dos argumentos siguen andando.

Apunta a la plantilla y no a lo creado porque quien dispara puede no ver la tarea (una de tipo tarea asignada solo a otro), y la rama `tarea` de la bandeja la descartaría.

## Función `notificaciones_listar(p_limite int DEFAULT 30)`

`SECURITY INVOKER`. Cada rama del UNION es un INNER JOIN contra la tabla apuntada, así que la RLS del lector decide qué sobrevive — una notificación cuya entidad dejó de ser visible desaparece de la lista sin una segunda copia de la regla de visibilidad. Devuelve `etiqueta`, `motivo` (el `motivo_rechazo` de la fila), `actor`, y `destino`/`destino_id` para navegar; los vínculos llevan a la obra, que es la que tiene ficha.

**Rama `plantilla` (`sql/055`):** etiqueta = nombre de la plantilla, destino `plantilla` (`/tareas/plantillas?plantilla={id}`). `tareas_plantillas_select` no filtra `activo`, así que el aviso de una archivada sobrevive en la bandeja; como la vista Plantillas no lista archivadas, sale con `destino` NULL y la campanita no navega. Excepción (`sql/056`; `sql/063` suma `plantilla_sin_acceso` a la misma rama): `plantilla_disparada` y `plantilla_sin_acceso` salen con `destino = 'tareas'` (`/tareas`, la vista general, sin id) aunque la plantilla esté archivada, porque las tareas creadas siguen ahí.

El badge cuenta las no leídas **de esta lista**, no de la tabla: si contara filas crudas quedaría más alto que lo que se ve.

## Función `notificaciones_avisos()`

`SECURITY INVOKER`, devuelve `(vencidas, vencen_hoy)` de las tareas asignadas al que pregunta. Lo que es estado y no evento no genera filas: sin cron que las cree a medianoche ni pasada que las limpie al completar. Mismo criterio que `reactivar_posponer_vencidos()` — se calcula al leer. El filtro por asignado va explícito porque la RLS de `tareas` deja ver bastante más que lo propio.

## Cambios sobre el módulo obras

- **`obras_etiqueta` pasa a `SECURITY INVOKER`** (era DEFINER). La bandeja necesita el único lugar donde una fila de las cinco tablas se vuelve texto, pero otorgarle EXECUTE siendo DEFINER la habría convertido en un bypass: con el uuid de una obra ajena —que el aviso ciego de `sql/037` devuelve con el nombre en NULL a propósito— cualquiera habría recuperado el nombre. Como INVOKER devuelve NULL para lo que el que pregunta no ve, así que otorgarla es inofensivo. Sus dos llamadores (`obras_pendientes`, `obras_resolver_pendiente`) no cambian: son DEFINER de `postgres`, que tiene BYPASSRLS. Verificado — misma salida sobre las 72 filas antes y después.
- **`obras_solicitante(p_tipo, p_id)`** — nueva, `SECURITY DEFINER`, sin GRANT. El mapa de las cinco tablas a quién pidió el alta estaba adentro del UNION de `obras_pendientes()`; el trigger de la decisión necesitaba el mismo mapa. Extraída y usada por los dos. Verificado — 0 discrepancias sobre las 72 filas.
