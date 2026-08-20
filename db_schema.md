# DB SCHEMA — ERP JADA (erp-new)

Fuente de verdad del esquema de base de datos. Mantener sincronizado con `database.types.ts` y migraciones SQL ante cualquier cambio de tablas, columnas o enums.

Proyecto Supabase: `qbpudocgdvpeadcyyhfh`. Regenerar tipos tras cada migración:
`npx supabase gen types typescript --project-id qbpudocgdvpeadcyyhfh --schema public > erp-app/src/lib/supabase/database.types.ts`
(requiere `supabase login` o `SUPABASE_ACCESS_TOKEN`)

Estado actual: `sql/001_usuarios_permisos.sql`, `sql/002_dashboard.sql`, `sql/003_vistas_funciones.sql` corridos en Supabase. `database.types.ts` generado real (comando de arriba).

---

## usuarios

Perfil 1:1 con `auth.users` (mismo `id`). Se crea automáticamente via trigger `on_auth_user_created` al insertar en `auth.users`.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | = auth.users.id |
| nombre | text | |
| email | text | unique parcial WHERE activo |
| activo | boolean | default true |
| created_at / updated_at | timestamptz | |

## submodulos

Catálogo — única unidad de autorización del sistema (sin roles). Ver `.claude/guides/GUIDE_PERMISSIONS.md`.

Modelo: módulo → 1+ vistas → cada vista 0+ funciones (`vista_id`, no solo `modulo` compartido).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| codigo | text | `{modulo}_{slug}`, unique parcial WHERE activo |
| modulo | text | agrupador funcional/nav |
| tipo | enum tipo_submodulo | `vista` \| `funcion` |
| vista_id | uuid FK → submodulos, nullable | NULL si tipo=vista; obligatorio si tipo=funcion (CHECK + trigger valida misma `modulo`) |
| nombre | text | label visible |
| orden | int | orden en tabs/nav |
| activo | boolean | |

Seed inicial: `usuarios_ver` (vista, nombre "Ver" — nunca repite el label del módulo), `usuarios_gestionar` (funcion, vista_id → usuarios_ver).

## usuario_submodulos

Asignación usuario ↔ submódulo.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | |
| submodulo_id | uuid FK → submodulos | |
| activo | boolean | UNIQUE normal (usuario_id, submodulo_id) — no parcial, por upsert (excepción GUIDE_DB) |

## usuario_widgets

Preferencia de visibilidad de widgets del dashboard, por usuario. Toggle "Configurar" en `/`.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | |
| widget_id | text | coincide con `WidgetDefinicion.id` en `modules/dashboard/types.ts` |
| visible | boolean | default true |
| created_at / updated_at | timestamptz | |

UNIQUE normal (usuario_id, widget_id) — no parcial, por upsert (misma razón que `usuario_submodulos`). RLS directo (`usuario_id = auth.uid()`) en SELECT/INSERT/UPDATE — no requiere `tiene_permiso`, así que el server action de toggle usa cliente normal, no `service_role`.

## Función `tiene_permiso(p_codigo text)`

SQL function, `SECURITY DEFINER`, usada en RLS de las 3 tablas y disponible como fuente de verdad de autorización en DB.

---

## Módulo tareas (`sql/005_tareas.sql` + `sql/006_tareas_hardening.sql` + `sql/007_tareas_reactivar_posponer.sql` + `sql/008_tareas_notas_visibilidad.sql` + `sql/009_tareas_miembros_asignables.sql` + `sql/013_tareas_visibilidad_y_miembros.sql` + `sql/014_tareas_asignar.sql` — corridos en Supabase vía MCP)

Reemplaza un intento anterior (rama `tareas-v1`, revertido en `sql/004_rollback_tareas.sql`) — requisitos de negocio cambiaron (proyectos + visibilidad en cascada, multi-asignado, `responsable_id`, `temperatura`). No comparte schema con esa rama.

**Regla de visibilidad (`sql/013`): se ve lo asignado y lo público, nada más.** `creado_por` no autoriza: quien crea una tarea y después pierde la asignación deja de verla, y lo mismo con el hilo o el proyecto donde vivía. Excepciones: `tareas_gestionar_ajenas` (ve todo) y `tareas_hilos.responsable_id` (dueño del hilo — no es una asignación). Los UPDATE están alineados con los SELECT, para que no exista fila modificable pero invisible.

### tareas_proyectos

Contenedor organizacional. Pone el techo de visibilidad para sus hilos/tareas.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text | |
| descripcion | text | nullable |
| visibilidad | enum `visibilidad` (`publico`\|`privado`) | default `privado` (`sql/008`, antes `publico`) |
| creado_por | uuid FK → usuarios | |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

### tareas_proyectos_miembros

Lista explícita de membresía: **quién puede recibir tareas del proyecto** (`sql/009`). Ortogonal a `visibilidad`, que decide quién lo ve — aunque desde `sql/013` la membresía también da acceso a los proyectos privados, porque el creador dejó de tenerlo por serlo. Todo proyecto — público o privado — necesita al menos un miembro.

Alta y baja de miembros exigen la función `tareas_proyectos_miembros` (o `tareas_gestionar_ajenas`). Única excepción: la siembra inicial, acotada por `proyecto_tiene_miembros()` — sin ella `tareas_proyectos_crear` no alcanzaría para crear nada, ya que el proyecto exige al menos un miembro. **El SELECT de la tabla no mira esa función**: leer la membresía sigue siendo de miembros y managers (agregarla filtraba los miembros de proyectos que el usuario ni ve — lo detectó el caso 02 de `sql/tests/rls_miembros_asignables.sql`).

El SELECT sí exige que el proyecto siga **activo** (`sql/016`): archivar un proyecto le saca la fila de la lista, pero sus membresías seguían visibles y `getMiembrosPorProyecto` armaba entradas de mapa para proyectos que ya no existen para el usuario. El `EXISTS` directo sobre `tareas_proyectos` no recursa — el lado de vuelta llega a esta tabla por `es_miembro_proyecto` (`SECURITY DEFINER`), así que el ciclo ya está roto.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| proyecto_id | uuid FK → tareas_proyectos | |
| usuario_id | uuid FK → usuarios | |
| activo | boolean | unique parcial (proyecto_id, usuario_id) WHERE activo |
| created_at | timestamptz | |

### tareas_hilos

Agrupador de tareas relacionadas. Sin vencimiento propio (se deriva de sus tareas en `queries.ts`).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| proyecto_id | uuid FK → tareas_proyectos, nullable | null = hilo personal |
| titulo | text | |
| descripcion | text | nullable |
| visibilidad | enum `visibilidad` | default `privado` (`sql/008`, antes `publico`) — solo importa si proyecto_id no es null |
| estado | enum `estado_hilo` (`abierto`\|`cerrado`) | default `abierto`. Cierre manual (modal en UI) bloqueado por trigger si queda alguna tarea sin completar. Reapertura automática al agregar/mover una tarea al hilo |
| responsable_id | uuid FK → usuarios | dueño — default = creador |
| creado_por | uuid FK → usuarios | |
| posponer_desde / posponer_hasta | date | nullable — oculta el hilo entero de la lista activa mientras esté vigente |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

### tareas

Unidad mínima de trabajo. `proyecto_id` solo se usa cuando la tarea está suelta (sin `hilo_id`) — si tiene hilo, el proyecto/visibilidad se heredan del hilo (`CHECK (hilo_id IS NULL OR proyecto_id IS NULL)`, fuente única).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| hilo_id | uuid FK → tareas_hilos, nullable | |
| proyecto_id | uuid FK → tareas_proyectos, nullable | solo si hilo_id es null |
| titulo / descripcion | text | |
| visibilidad | enum `visibilidad` | default `privado` (`sql/008`, antes `publico`) — solo importa si hilo_id es null y proyecto_id no |
| estado | enum `estado_tarea` (`pendiente`\|`en_progreso`\|`completada`\|`cancelada`) | default `pendiente` |
| temperatura | int | default 50, CHECK 1-100 — orden personal en UI, cualquier asignado la mueve |
| responsable_id | uuid FK → usuarios | dueño — default = creador. Gatea "forzar completado" (modo híbrido) y aparece en auditoría |
| creado_por | uuid FK → usuarios | |
| fecha_vencimiento | date | nullable |
| posponer_desde / posponer_hasta | date | nullable — sin cron: se recalcula al leer (`queries.ts`), no vía job |
| recurrencia_cantidad | int | nullable, junto con recurrencia_unidad (ambos o ninguno) |
| recurrencia_unidad | enum `recurrencia_unidad` (`dia`\|`mes`) | nullable |
| nota_anterior / nota_siguiente | text | nullable — "nota de la última vez" de tareas recurrentes |
| origen_app / origen_punto | text | nullable — qué app externa la generó y el deep link, si existe |
| modo_completado | enum `modo_completado` (`manual`\|`automatico`\|`hibrido`) | default `manual` |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

**Recurrencia sin `pg_cron`:** la próxima instancia se genera al completar la actual (trigger `generar_recurrencia`), no por fecha de calendario — copia asignados y `nota_siguiente` → `nota_anterior` de la nueva.

### tareas_asignados

Multi-asignado — cualquiera puede completar la tarea.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tarea_id | uuid FK → tareas | |
| usuario_id | uuid FK → usuarios | |
| activo | boolean | unique parcial (tarea_id, usuario_id) WHERE activo |
| created_at | timestamptz | |

### tareas_notas / tareas_hilos_notas (`sql/008`)

Historial de notas — "agregar", no "editar": sin UPDATE de texto, solo `activo` para ocultar una nota propia (nunca DELETE). `tareas_notas.tarea_id` FK → `tareas`; `tareas_hilos_notas.hilo_id` FK → `tareas_hilos`. Ambas con `usuario_id` FK → `usuarios` (autor) y `nota text`.

SELECT vía `EXISTS` directo sobre la tabla padre (`tareas`/`tareas_hilos`) — sin función `SECURITY DEFINER`: la RLS de la tabla padre ya resuelve visibilidad en cascada para el rol que consulta, y no hay recursión porque esa policy no mira hacia las tablas de notas. INSERT: mismo actor que puede gestionar la fila padre (`tareas_notas` reusa `es_responsable_tarea`/`es_asignado_tarea`; `tareas_hilos_notas` usa `responsable_id` del hilo), más `tareas_gestionar_ajenas`. UPDATE (solo `activo=false`): autor o ajenas.

### tareas_plantillas / tareas_plantillas_items

Recurso compartido del equipo, gateado solo por la vista `tareas_plantillas` (sin función separada de lectura/escritura).

| tareas_plantillas | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre / descripcion | text | descripcion nullable |
| creado_por | uuid FK → usuarios | |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

| tareas_plantillas_items | tipo | notas |
|---|---|---|
| id | uuid PK | |
| plantilla_id | uuid FK → tareas_plantillas | |
| titulo | text | |
| orden | int | default 0 |
| activo | boolean | |
| created_at | timestamptz | |

### tareas_eventos

Auditoría append-only. **Excepción a "nunca DELETE, siempre `activo`": sin columna `activo`** — una auditoría no debe poder ocultar sus propias filas. Necesaria porque `estado` se resetea en cada ciclo de recurrencia y `updated_at` se mueve con cualquier edición — ninguna columna sobre `tareas` puede reconstruir el historial. `GRANT SELECT` únicamente — el INSERT entra solo por el trigger `log_evento_tarea` (`SECURITY DEFINER`).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tarea_id | uuid FK → tareas | |
| usuario_id | uuid FK → usuarios, nullable | null = evento del sistema |
| estado_anterior | enum `estado_tarea`, nullable | |
| estado_nuevo | enum `estado_tarea` | |
| created_at | timestamptz | |

### Función `puede_ver_hilo(uuid)`

`SECURITY DEFINER`, `STABLE` — resuelve visibilidad en cascada de un hilo (responsable/asignado a alguna de sus tareas/permiso `tareas_gestionar_ajenas`/cascada proyecto público-o-miembro). **Sin `creado_por` desde `sql/013`.** Usada en RLS de `tareas_hilos` y `tareas`. `EXECUTE` revocado de `PUBLIC`, otorgado solo a `authenticated` (`sql/006`).

### Funciones `es_creador_proyecto(uuid)` / `es_responsable_tarea(uuid)` / `es_asignado_tarea(uuid)` / `proyecto_tiene_miembros(uuid)`

`SECURITY DEFINER`, `STABLE` — mismo criterio que `puede_ver_hilo`. Usadas en las policies de `tareas_proyectos_miembros` y `tareas_asignados` para no consultar directamente `tareas_proyectos`/`tareas`/`tareas_asignados` desde dentro de su propia política: dos tablas con policies que se referencian mutuamente (`tareas_proyectos` ↔ `tareas_proyectos_miembros`, `tareas` ↔ `tareas_asignados`) causan `42P17 infinite recursion detected in policy` si la referencia es un `EXISTS` directo bajo RLS. Envolver el lado "de vuelta" en una función `SECURITY DEFINER` rompe el ciclo (`sql/005`, fix aplicado post-creación).

`es_responsable_tarea` reemplaza a `es_responsable_o_creador_tarea` (borrada en `sql/013`): con la rama del creador, quien perdía la asignación se la devolvía a sí mismo por API insertando en `tareas_asignados`. No hace falta esa rama para crear — `tareas_insert` ya exige `responsable_id = auth.uid()` a quien no tiene `tareas_asignar` (`tareas_gestionar_ajenas` hasta `sql/014`). Por el mismo motivo, `tareas_asignados_update` acota `usuario_id = auth.uid()` a `NOT activo` en su `WITH CHECK`: sacarme de una tarea es mío, re-agregarme no.

### Funciones `es_miembro_proyecto(uuid, uuid)` / `es_miembro_proyecto_de_tarea(uuid, uuid)` (`sql/009`)

`SECURITY DEFINER`, `STABLE` — mismo criterio anti-recursión que `es_creador_proyecto`. La segunda resuelve el proyecto **efectivo** de una tarea (`COALESCE(tareas.proyecto_id, tareas_hilos.proyecto_id)`) y devuelve `true` si la tarea no tiene proyecto. Usadas por `tareas_asignados_insert`/`update` (`AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))` — la regla se exige solo sobre filas activas, para no bloquear la desactivación al reasignar) y por `tareas_proyectos_miembros_select`, extendida para que un miembro vea a los demás miembros (sin eso el picker de asignados queda vacío para quien no es creador del proyecto). Ni `tareas_gestionar_ajenas` saltea la regla: es regla de negocio, no nivel de permiso.

### Triggers `validar_proyecto_tarea` / `validar_quitar_miembro` (`sql/009`)

Las policies cubren "cambian los asignados"; estos dos triggers cubren las otras dos caras de la misma regla:

- `validar_proyecto_tarea` — `BEFORE UPDATE OF proyecto_id, hilo_id ON tareas`: mover una tarea a un proyecto donde algún asignado activo no es miembro falla con `ERRCODE = 'TA002'`.
- `validar_quitar_miembro` — `BEFORE UPDATE ON tareas_proyectos_miembros WHEN (OLD.activo AND NOT NEW.activo)`: quitar un miembro con tareas `pendiente`/`en_progreso` en el proyecto falla con `ERRCODE = 'TA001'`, en vez de desactivar sus asignaciones por detrás.

Ambos SQLSTATE están mapeados a mensaje en `MENSAJES_ERROR` (`lib/utils.ts`). Por eso `editarProyecto` guarda un diff (quitados/agregados) en vez de desactivar todo y reinsertar: lo segundo dispararía `TA001` sobre los miembros que se quedan.

### Poner a otro en una tarea = función `tareas_asignar` (`sql/014`)

Tercer eje, independiente de `tareas_gestionar_ajenas` (autoridad sobre tareas ajenas) y de la membresía (quién puede trabajar): **quién puede repartir trabajo**. Sin la función, uno se asigna a sí mismo y nada más. Tres piezas, una por cara:

- `tareas_asignados_insert`/`update` — `AND (usuario_id = auth.uid() OR tiene_permiso('tareas_asignar'))`, sumado a las condiciones que ya tenían. Cubre agregar a otro y, por el mismo conjunto, sacarlo (reasignar = desactivar + reinsertar).
- `tareas_insert` — `responsable_id = auth.uid() OR tiene_permiso('tareas_asignar')`. **Reemplaza** la rama `tareas_gestionar_ajenas` que tenía desde `sql/005`: nombrar responsable a otro es asignar, no es gestionar lo ajeno.
- Trigger `validar_responsable_tarea` — `BEFORE UPDATE OF responsable_id ON tareas WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)`: traspasar el responsable a otro sin la función falla con `ERRCODE = 'TA003'`. Va en trigger porque un `WITH CHECK` solo ve la fila nueva y no puede distinguir "cambió el responsable" de "el UPDATE tocó otra columna".

`tareas_gestionar_ajenas` **no** saltea la regla; el backfill de `sql/014` le dio `tareas_asignar` a quien ya la tenía, para no romper equipos en curso.

### El mismo eje sobre hilos (`sql/015`)

`tareas_hilos` no tiene tabla de asignados — el responsable es una columna — así que el eje se aplica en las dos caras de esa columna:

- `tareas_hilos_insert` — `creado_por = auth.uid() AND (responsable_id = auth.uid() OR tiene_permiso('tareas_asignar'))`. **Reemplaza** la rama `tareas_gestionar_ajenas`, igual que `sql/014` hizo con `tareas_insert`.
- `tareas_hilos_update` — el `WITH CHECK` suma `OR tiene_permiso('tareas_asignar')`. Sin eso el traspaso era imposible incluso con la función: la fila nueva tiene `responsable_id` ajeno y el `WITH CHECK` solo aceptaba `responsable_id = auth.uid()`. En `tareas` el problema no aparece porque ahí el `WITH CHECK` tiene además la rama del asignado activo (`sql/013`). Quién puede **tocar** el hilo lo sigue decidiendo el `USING`; quién puede quedar **a cargo** es del trigger.
- Trigger `validar_responsable_hilo` — `BEFORE UPDATE OF responsable_id ON tareas_hilos WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)`: mismo `ERRCODE = 'TA003'` y mismo motivo que `validar_responsable_tarea`.

### Función `reactivar_posponer_vencidos()`

`SECURITY DEFINER` — sin cron: `queries.getListaTareas()` la invoca (`supabase.rpc(...)`) antes de leer la lista. Limpia `posponer_desde`/`posponer_hasta` de `tareas`/`tareas_hilos` cuyo `posponer_hasta` ya venció, y en `tareas` corre `fecha_vencimiento` el mismo intervalo que duró el pospuesto. `EXECUTE` solo para `authenticated` (`sql/007`).

**Hardening (`sql/006`):** `EXECUTE` revocado de `PUBLIC` en las funciones `SECURITY DEFINER` de solo-trigger (`generar_recurrencia`, `log_evento_tarea`, `reabrir_hilo_en_tarea`, `validar_cierre_hilo`) — PostgREST expone toda función a `PUBLIC` por default y estas no necesitan ser invocables vía RPC. Índices agregados en FKs `creado_por`/`responsable_id` sin cobertura.

### Permisos (submódulos `modulo = 'tareas'`)

| codigo | tipo | vista_id | notas |
|---|---|---|---|
| tareas_lista | vista | — | listado unificado personal + proyectos visibles |
| tareas_proyectos | vista | — | |
| tareas_plantillas | vista | — | |
| tareas_auditoria | vista | — | solo-lectura, se asigna directo a managers |
| tareas_gestionar_ajenas | funcion | tareas_lista | completar/cerrar hilo/reasignar tarea **ajena** — acciones sobre lo propio no requieren función |
| tareas_asignar | funcion | tareas_lista | "Asignar usuarios" (`sql/014`) — poner a otro como asignado o responsable. Sin ella el `AsignadosPicker` muestra solo el resumen y "Reasignar" no aparece en el menú |
| tareas_proyectos_crear | funcion | tareas_proyectos | |
| tareas_proyectos_miembros | funcion | tareas_proyectos | "Asignar miembros" (`sql/013`) — alta/baja de miembros. Sin ella el bloque Miembros no se muestra en `ProyectoFormPanel` y la membresía viaja como default oculto |

`usuarios_select` extendida con `OR tiene_permiso('tareas_lista') OR tiene_permiso('tareas_proyectos')` — picker de asignados/miembros necesita listar usuarios activos.

---
