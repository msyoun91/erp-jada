# Módulo tareas

Rediseño desde cero (`sql/112`). Ficha y decisiones: `decisiones/tareas/` (índice en su `README.md`).
El esquema de `master` es otro módulo: no se mezclan nombres de allá.

**Estado:** `sql/112` es solo esquema, catálogo, entes y visibilidad, con `GRANT SELECT`. Las
escrituras y sus reglas llegan con `sql/113`: hasta entonces solo escribe `service_role`.

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
`etiqueta_registro`. Trigger `emitir_eventos` (`emitir_eventos_registro`) en las dos tablas: alta, estado,
baja, reactivación.
