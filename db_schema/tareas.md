# Módulo tareas

Rediseño desde cero (`sql/112`). Ficha y decisiones: `decisiones/tareas/` (índice en su `README.md`).
El esquema de `master` es otro módulo: no se mezclan nombres de allá.

**Estado:** `sql/112` (esquema, catálogo, entes, visibilidad), `sql/113` (escrituras y reglas),
`sql/114` (bajas y cambios de equipo) y `sql/115` (avisos) aplicados el 2026-09-24.
Faltan plantillas y recurrencia (`BACKLOG.md`).

## Visibilidad — la unidad es el hilo

Ve un hilo: `tareas_administrar` (también desactivado), y con `tareas_ver` sobre un hilo activo: el
responsable, el asignado de algún paso activo, o quien tiene `tareas_equipo` si su equipo es el
`equipo_id` del hilo o de algún paso activo. Un paso se ve si se ve su hilo; desactivado, solo con
`tareas_administrar`. Notas e historial: los del hilo que se ve; lo oculto, solo `tareas_administrar`.

- `tareas_puede_ver_hilo_de(hilo, responsable, equipo, activo, usuario)` — DEFINER STABLE, sin GRANT.
  Lee `tareas` sin RLS (la de `tareas` pregunta por el hilo: 42P17). Recibe las columnas del hilo, no
  el id (`GUIDE_ENTES.md` §2.3).
- `tareas_puede_ver_tarea_de(hilo, activo, usuario)` — DEFINER STABLE, sin GRANT.
- `tareas_puede_ver_hilo(...)` / `tareas_puede_ver_tarea(...)` — envoltorios con `auth.uid()`,
  GRANT `authenticated`: los usan las policies `tareas_hilos_select` y `tareas_select`.

## tareas_hilos — ente `hilo`

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| titulo | text | 1–500 |
| responsable_id | uuid FK → usuarios | dueño, transferible |
| equipo_id | uuid FK → equipos, nullable | equipo del responsable al crear o transferir; guardado, no calculado |
| estado | enum `estado_hilo` (`abierto`\|`cerrado`) | default `abierto` |
| resultado | text, nullable | ≤ 5000 |
| recurrencia_cantidad / recurrencia_unidad | int > 0 / enum `recurrencia_unidad` (`dia`\|`mes`) | ambos o ninguno |
| recurrencia_de | uuid FK → tareas_hilos, nullable | el ciclo anterior |
| activo | boolean | |
| created_at / updated_at | timestamptz | `created_at` con `clock_timestamp()` |

## tareas — ente `tarea` (el paso)

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | UNIQUE (id, hilo_id) para las FK compuestas |
| hilo_id | uuid FK → tareas_hilos | |
| paso_anterior_id | uuid, nullable | FK compuesta `(paso_anterior_id, hilo_id)` → mismo hilo; DEFERRABLE (insertar antes de). Unique parcial `WHERE activo`: no bifurca. NULL = paralelo |
| titulo / descripcion | text | 1–500 / ≤ 5000 |
| asignado_id / asignado_equipo_id | uuid FK → usuarios / equipos | exactamente uno (`tareas_un_asignado`) |
| equipo_id | uuid FK → equipos, nullable | equipo del asignado al asignar (o el asignado); guardado |
| estado | enum `estado_tarea` (`solicitada`\|`pendiente`\|`rechazada`\|`completada`\|`cancelada`) | "bloqueada", "en espera" y "vencida" son derivados |
| prioridad | enum `prioridad_tarea` (`baja`\|`media`\|`alta`) | default `media` |
| vence | date, nullable | con `vence_dias`, derivada al habilitarse |
| vence_dias | int, nullable | > 0 y solo con previo |
| espera_hasta / espera_motivo | date / text ≤ 500 | solo en `pendiente`; motivo solo con fecha |
| resultado | text, nullable | ≤ 5000 |
| motivo_rechazo | text, nullable | 1–2000; obligatorio en `rechazada` |
| activo | boolean | |
| created_at / updated_at | timestamptz | `created_at` con `clock_timestamp()`: es el orden de los pasos |

## tareas_notas

De hilo (`tarea_id` NULL) o de paso. Solo se agregan; `activo = false` es ocultar.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| hilo_id | uuid FK → tareas_hilos | |
| tarea_id | uuid, nullable | FK compuesta `(tarea_id, hilo_id)` → el paso es de ese hilo |
| autor_id | uuid FK → usuarios | default `auth.uid()` |
| texto | text | 1–5000 |
| activo / ocultada_por / ocultada_at | | quién y cuándo la ocultó |
| created_at / updated_at | timestamptz | `created_at` con `now()` |

## tareas_ediciones

Valor anterior del contenido de hilo y paso (`eventos` no lo guarda). La escribe un trigger.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| hilo_id / tarea_id | uuid | como en las notas |
| campo / anterior / nuevo | text | |
| actor_id | uuid FK → usuarios, nullable | |
| activo / ocultada_por / ocultada_at | | ocultar, como las notas |
| created_at / updated_at | timestamptz | `created_at` con `clock_timestamp()` |

## Permisos (`submodulos`, `modulo = 'tareas'`)

| código | tipo | nombre | delegable |
|---|---|---|---|
| `tareas_ver` | vista | Hilos | sí |
| `tareas_pedir` | función → `tareas_ver` | Pedir a otros equipos | no |
| `tareas_mision` | vista | Misión | sí |
| `tareas_equipo` | vista | Equipo | no |
| `tareas_plantillas` | vista | Plantillas | sí |
| `tareas_todas` | vista | Todas | no |
| `tareas_administrar` | función → `tareas_todas` | Administrar | no |

Reglas (`submodulo_reglas`, todas `requiere`): `tareas_equipo` → `usuarios_delegar`;
`usuarios_delegar` → `tareas_ver`, `tareas_equipo`; `tareas_todas` → `tareas_administrar`, `tareas_ver`;
`tareas_mision`, `tareas_plantillas` → `tareas_ver`; `tareas_administrar` → `tareas_pedir`.
`designar_delegador` y `quitar_delegador` dan y quitan `tareas_equipo` junto con `usuarios_delegar`.

## Entes y eventos

`entes`: `hilo` (`/tareas/{id}`) y `tarea` (`/tareas/paso/{id}`), submódulo `tareas_ver`, datos
`{titulo}`, sin disparos. Rama `tareas_etiqueta(tipo, id)` (INVOKER, GRANT `authenticated`) en
`etiqueta_registro`, y en `puede_ver_relacion` (quien ve el paso ve quién lo tuvo). Trigger `emitir_eventos`
(`emitir_eventos_registro`) en las dos tablas: alta, estado, baja, reactivación; en el hilo, también
`transferencia` `{de, a}` al cambiar `responsable_id` (`sql/115`). `emitir_eventos_asignado`
(`tareas_emitir_asignado`, INVOKER) en `tareas`: `relacion_alta` / `relacion_baja` con
`{ente: 'usuario'|'equipo', registro_id, rol: 'asignado'}` al nacer y al cambiar de asignado.

## Escrituras (`sql/113`)

GRANT por columna; la policy dice sobre qué filas y el trigger quién puede qué. Test:
`sql/tests/tareas_reglas.sql`. Errores con clase `TA` (`mensajeError` los deja pasar).

| tabla | INSERT | UPDATE |
|---|---|---|
| `tareas_hilos` | `id, titulo, responsable_id` (default `auth.uid()`), `recurrencia_*` — policy: `tareas_ver` | `titulo, responsable_id, estado, resultado, recurrencia_*, activo` — policy: ve el hilo |
| `tareas` | `id, hilo_id, paso_anterior_id, titulo, descripcion, asignado_id, asignado_equipo_id, prioridad, vence, vence_dias` — policy: ve el hilo | todo menos `hilo_id, equipo_id` y fechas — policy: ve el paso |
| `tareas_notas` | `id, hilo_id, tarea_id, texto` — policy: autor = yo, ve el hilo (y el paso) | `activo` — `tareas_administrar` |
| `tareas_ediciones` | — (trigger) | `activo` — `tareas_administrar` |

`estado`, `equipo_id`, `vence` (con `vence_dias`) y lo del asignado al crear los pone la base.

**Directo o sistema:** las reglas de actor valen con `pg_trigger_depth() = 1` y `auth.uid()`; lo que
escriben los triggers en cascada (profundidad 2) solo respeta invariantes. Triggers DEFINER.

Triggers:
- `tareas_hilos_al_crear` / `tareas_hilos_al_editar` (BEFORE): responsable = yo salvo admin
  (TA002), responsable que puede recibir (TA003), editar = responsable o admin (TA001), cerrado
  congelado (TA007), cerrar sin pasos abiertos (TA008), desactivar sin completados (TA009), reactivar
  solo admin, transferir afuera (contra `equipo_id` guardado) con `tareas_pedir` (TA010) y al
  delegador del equipo destino (TA015). `equipo_id` = `equipo_de(responsable)`.
- `tareas_hilos_transferir` (AFTER): si cambia el equipo, los pasos abiertos del equipo de origen
  pasan al nuevo responsable.
- `tareas_al_crear` / `tareas_al_editar` (BEFORE): quién escribe qué columna, transiciones, pedidos
  (`tareas_estado_al_abrir`), receptor válido, espera y motivo que se limpian, bloqueo (TA004),
  plazo relativo.
- `tareas_propagar` (AFTER INSERT / UPDATE OF estado, activo): reabre el hilo, cascada de reabrir,
  vencimiento del siguiente al habilitarse o bloquearse.
- `tareas_validar_cadena` (constraint, diferido): desactivar desde la cola (TA006); el previo solo
  cambia por *Insertar antes de* (TA005).
- `tareas_registrar_ediciones` (AFTER, solo directo): `titulo, recurrencia_*` del hilo;
  `titulo, descripcion, prioridad, vence, vence_dias` del paso.
- `tareas_firmar_ocultar` (notas y ediciones): `ocultada_por` / `ocultada_at`.

Helpers sin GRANT: `tareas_hoy`, `tareas_delegador_de`, `tareas_puede_recibir`,
`tareas_equipo_de_asignado`, `tareas_es_pedido`, `tareas_actua_como_asignado`, `tareas_bloquea`,
`tareas_siguiente_efectivo`, `tareas_estado_al_abrir`.

RPC (GRANT `authenticated`):
- INVOKER: `tareas_insertar_antes(siguiente, titulo, descripcion, asignado, asignado_equipo,
  prioridad, vence, vence_dias) → uuid`, `tareas_cancelar_y_cerrar(hilo, resultado)`,
  `tareas_completar_con_nota(tarea, nota, resultado)` (el admin completa lo ajeno; TA012 sin nota).
- DEFINER: `tareas_desactivar_paso(paso)`, `tareas_desactivar_hilo(hilo)`,
  `tareas_transferir_hilo(hilo, responsable)` — la fila nueva de un UPDATE pasa por la policy de
  SELECT, y estas tres la sacan de la vista de quien actúa (42501 por PostgREST). El trigger decide.

## Bajas y cambios de equipo (`sql/114`)

Test: `sql/tests/tareas_bajas.sql`. Decisión: `decisiones/tareas/bajas.md`.

- `tareas_entregar(usuario)` — sin GRANT. Sus hilos (todos) y sus pasos abiertos pasan al delegador
  del `equipo_id` de cada fila, si puede recibir; si no, quedan (huérfanos). Corre a profundidad 2:
  `tareas_al_editar` recalcula el equipo y lo que deja de ser pedido pasa a `pendiente`.
- `tareas_usuario_baja` (AFTER UPDATE OF `activo` ON `usuarios`, al desactivar): entrega.
- `tareas_cambio_de_equipo` (AFTER INSERT OR UPDATE OF `activo` ON `equipos_miembros`): al salir,
  entrega; al entrar, lo abierto suyo sin equipo (hilos abiertos que lleva, pasos abiertos asignados)
  toma el equipo nuevo.

## Avisos (`sql/115`)

Test: `sql/tests/tareas_avisos.sql`. Decisión: `decisiones/tareas/avisos.md`. Tipos y cómo se leen:
`db_schema/notificaciones.md`.

- `tareas_avisar` (AFTER INSERT / UPDATE OF asignado, estado, activo, título, descripción, vence,
  vence_dias; DEFINER): llega el paso (asignada o pedido, y al delegador de la persona si es pedido),
  sumado, reasignado, quitado, a reasignar (reabrir o reactivar sin un asignado que pueda recibir),
  aceptado, rechazado, completado, cancelado, reabierto, editado (solo lo que escribe una persona)
  y dado de baja. Una sola vez por persona y cambio.
- `tareas_propagar` (reemplazada): habilitado al habilitarse el siguiente; bloqueado solo al insertar
  antes.
- `tareas_hilos_avisar` (AFTER UPDATE OF responsable_id, activo): transferido (solo abierto y activo)
  y dado de baja (a los asignados de sus pasos abiertos).
- Huérfanos: `tareas_avisar_huerfanos(usuario)`, desde `tareas_usuario_baja` (después de entregar) y
  desde `tareas_perdida_de_ver` (constraint trigger diferido sobre `usuario_submodulos`: salir de un
  equipo apaga `tareas_ver` antes de entregar). Si ya no puede recibir: "paso huérfano" al responsable
  de cada paso abierto que le quedó, y "hilos huérfanos" a los `tareas_administrar` si le quedaron
  hilos abiertos (reemplaza el anterior sobre la misma persona).

Helpers sin GRANT: `tareas_destinatario` (persona, o el delegador si es equipo),
`tareas_avisar_asignado`, `tareas_avisar_huerfanos`. RPC: `tareas_avisos_salida()` (DEFINER, GRANT
`authenticated`), la usa `notificaciones_listar`.
