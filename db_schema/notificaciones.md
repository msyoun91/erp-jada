# Notificaciones (`sql/038_notificaciones.sql` — corrida en Supabase vía MCP)

Infra cross-módulo como `usuario_widgets` y `usuario_tutorial`: prefijo `usuario_`, RLS directo por `auth.uid()`, **sin submódulo y sin vista propia**. Nadie necesita permiso para recibir avisos de cosas que ya puede ver — el permiso lo puso la entidad apuntada, no la notificación.

## usuario_notificaciones

**La notificación apunta, no copia.** Guarda a qué fila se refiere y el texto se arma al leer, con la RLS del que lee. Copiar el título rompería `sql/013` desde la campanita: quien pierde la asignación dejaría de ver la tarea pero seguiría leyendo su nombre en la bandeja.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | destinatario |
| tipo | enum `tipo_notificacion` (`alta_aprobada`\|`alta_rechazada`\|`obra_transferida`\|`tarea_asignada`) | |
| entidad | text | CHECK `obra`\|`empresa`\|`persona`\|`obra_empresa`\|`obra_persona`\|`tarea`. Text y no enum: es el discriminador de a qué tabla apunta `entidad_id`, mismo vocabulario y misma forma que `obras_aprobaciones.tipo` |
| entidad_id | uuid | sin FK — apunta a seis tablas |
| actor_id | uuid FK → usuarios, nullable | quién lo provocó. Null = evento del sistema |
| leida_at | timestamptz, nullable | |
| activo | boolean | descartar sin borrar |
| created_at / updated_at | timestamptz | |

**RLS:** SELECT y UPDATE con `usuario_id = auth.uid()`. **Sin policy ni GRANT de INSERT** — la escribe `notificar()`, que es `SECURITY DEFINER` y solo se llama desde triggers: una notificación insertable por el cliente sería un canal para escribirle a otro usuario. `GRANT SELECT` + `GRANT UPDATE (leida_at, activo)` — GRANT por columna porque RLS no acota columnas.

## Función `notificar(usuario, tipo, entidad, entidad_id, actor)`

`SECURITY DEFINER`. Único lugar donde nace una notificación, y donde vive "no te notifiques a vos mismo". `IS DISTINCT FROM` y no `<>`: con `auth.uid()` NULL (service_role, SQL editor) la comparación daría NULL y el aviso se perdería en silencio.

## Los tres triggers

| trigger | tabla | destinatario |
|---|---|---|
| `trg_notificar_decision_obra` | `obras_aprobaciones` AFTER INSERT | `obras_solicitante(tipo, registro_id)` — `alta_aprobada` o `alta_rechazada` según `aprobada` |
| `trg_notificar_transferencia_obra` | `obras_transferencias` AFTER INSERT | `a_usuario_id` |
| `trg_notificar_tarea_asignada` | `tareas_asignados` AFTER INSERT OR UPDATE OF activo | `usuario_id`, solo cuando la fila pasa a activa |

**Al que le sacaron la obra no se le avisa.** Ya no la ve (`obras_select` es `obras_puede_ver_obra`): un aviso con el nombre sería la única grieta del módulo y uno sin el nombre no diría nada. Esa pregunta la contesta `obras_auditoria_transferencias`.

**`pg_trigger_depth() > 1`** en el de tareas filtra la copia de asignados de `generar_recurrencia`: una tarea diaria mandaría un aviso por día a cada asignado, y ahí nadie asignó a nadie.

## Función `notificaciones_listar(p_limite int DEFAULT 30)`

`SECURITY INVOKER`. Cada rama del UNION es un INNER JOIN contra la tabla apuntada, así que la RLS del lector decide qué sobrevive — una notificación cuya entidad dejó de ser visible desaparece de la lista sin una segunda copia de la regla de visibilidad. Devuelve `etiqueta`, `motivo` (el `motivo_rechazo` de la fila), `actor`, y `destino`/`destino_id` para navegar; los vínculos llevan a la obra, que es la que tiene ficha.

El badge cuenta las no leídas **de esta lista**, no de la tabla: si contara filas crudas quedaría más alto que lo que se ve.

## Función `notificaciones_avisos()`

`SECURITY INVOKER`, devuelve `(vencidas, vencen_hoy)` de las tareas asignadas al que pregunta. Lo que es estado y no evento no genera filas: sin cron que las cree a medianoche ni pasada que las limpie al completar. Mismo criterio que `reactivar_posponer_vencidos()` — se calcula al leer. El filtro por asignado va explícito porque la RLS de `tareas` deja ver bastante más que lo propio.

## Cambios sobre el módulo obras

- **`obras_etiqueta` pasa a `SECURITY INVOKER`** (era DEFINER). La bandeja necesita el único lugar donde una fila de las cinco tablas se vuelve texto, pero otorgarle EXECUTE siendo DEFINER la habría convertido en un bypass: con el uuid de una obra ajena —que el aviso ciego de `sql/037` devuelve con el nombre en NULL a propósito— cualquiera habría recuperado el nombre. Como INVOKER devuelve NULL para lo que el que pregunta no ve, así que otorgarla es inofensivo. Sus dos llamadores (`obras_pendientes`, `obras_resolver_pendiente`) no cambian: son DEFINER de `postgres`, que tiene BYPASSRLS. Verificado — misma salida sobre las 72 filas antes y después.
- **`obras_solicitante(p_tipo, p_id)`** — nueva, `SECURITY DEFINER`, sin GRANT. El mapa de las cinco tablas a quién pidió el alta estaba adentro del UNION de `obras_pendientes()`; el trigger de la decisión necesitaba el mismo mapa. Extraída y usada por los dos. Verificado — 0 discrepancias sobre las 72 filas.
