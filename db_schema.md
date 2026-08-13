# DB SCHEMA — ERP JADA (erp-new)

Fuente de verdad del esquema de base de datos. Mantener sincronizado con `database.types.ts` y migraciones SQL ante cualquier cambio de tablas, columnas o enums.

Proyecto Supabase: `qbpudocgdvpeadcyyhfh`. Regenerar tipos tras cada migración:
`npx supabase gen types typescript --project-id qbpudocgdvpeadcyyhfh --schema public > erp-app/src/lib/supabase/database.types.ts`
(requiere `supabase login` o `SUPABASE_ACCESS_TOKEN`)

Estado actual: `sql/001` a `sql/008` corridos en Supabase, `database.types.ts` regenerado real. `sql/009_fix_hilo_duplicado.sql` — **sin correr todavía** (limpieza de dato, no de esquema — ver `DECISIONES.md`).

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

RLS `usuarios_select`: `id = auth.uid() OR tiene_permiso('usuarios_ver') OR tiene_permiso('tareas_asignar')` — la última cláusula la agregó `sql/005_tareas_asignar_usuarios_rls.sql` para el picker de asignación de tareas (ver `DECISIONES.md`).

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

## tareas_hilos

Agrupador manual de tareas relacionadas. Puede crearse independiente o al vuelo al crear una tarea.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| titulo | text | |
| estado | enum estado_hilo | `abierto` \| `cerrado` — automático, ver trigger abajo |
| creado_por | uuid FK → usuarios | |
| recurrencia_activa | boolean | default `false` |
| recurrencia_intervalo | enum recurrencia_intervalo, nullable | `dia` \| `mes` \| `anio` — requerido si `recurrencia_activa` |
| recurrencia_cada | int | default `1` — "cada N día/mes/año" |
| recurrencia_proxima | date, nullable | requerido si `recurrencia_activa` |
| recurrencia_una_vez | boolean | default `false` — dispara un solo ciclo y `generar_tareas_recurrentes()` apaga `recurrencia_activa` en vez de avanzar `recurrencia_proxima` (`sql/013_recurrencia_una_vez.sql`) |
| posponer_hasta | date, nullable | "snooze" — hilo oculto de la vista principal mientras `posponer_hasta > hoy` (`sql/012_posponer.sql`) |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

**Cierre/apertura automática** (`sql/007_tareas_hilos_estado.sql`): trigger `sync_estado_hilo` en `tareas` (INSERT/DELETE/UPDATE de `estado`, `hilo_id`, `activo`) llama `sync_estado_hilo(hilo_id)` — `SECURITY DEFINER`, cierra el hilo si tiene ≥1 tarea activa y ninguna pendiente, lo reabre en cualquier otro caso (nueva tarea, tarea revertida, tarea reasignada de/a otro hilo). Nunca se cierra manualmente desde la UI.

**Recurrencia reintroducida** (`sql/010_recurrencia_hilos.sql` — revierte la eliminación de `sql/007`, ver DECISIONES.md). CHECK `recurrencia_completa` exige intervalo+próxima+cada>0 cuando `recurrencia_activa`. `generar_tareas_recurrentes()` (`SECURITY DEFINER`, pensada para `pg_cron` diario, ver `sql/011`) resetea a `pendiente` las tareas activas del hilo cuando `recurrencia_proxima <= hoy` y agenda la próxima fecha vía `avanzar_recurrencia()` (con catch-up si el cron estuvo caído varios períodos) — el trigger `sync_estado_hilo` ya existente reabre el hilo solo, sin lógica extra.

## tareas

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| hilo_id | uuid FK → tareas_hilos, nullable | tarea suelta si NULL |
| titulo | text | |
| descripcion | text, nullable | |
| asignado_a | uuid FK → usuarios | requiere `tareas_asignar` para asignar a otro que no sea uno mismo |
| creado_por | uuid FK → usuarios | |
| estado | enum estado_tarea | `pendiente` \| `en_progreso` \| `completada` |
| recurrencia_activa / recurrencia_una_vez / recurrencia_intervalo / recurrencia_cada / recurrencia_proxima | — | mismas columnas y semántica que `tareas_hilos` (`sql/011_recurrencia_tareas.sql`, `sql/013_recurrencia_una_vez.sql`) — solo tiene efecto si `hilo_id IS NULL` (tarea suelta); si la tarea se asocia a un hilo, `asociarTareaHilo` apaga `recurrencia_activa` porque pasa a mandar la del hilo |
| posponer_hasta | date, nullable | "snooze" (`sql/012_posponer.sql`) — a diferencia de la recurrencia, funciona con o sin `hilo_id` (una tarea dentro de un hilo puede posponerse individualmente sin afectar al hilo) |
| fecha_vencimiento | date, nullable | UI la precarga en "hoy + 1 día" al crear una tarea (default de formulario, no de columna) |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

## tareas_eventos

Log append-only de cambios de estado (`sql/014_tareas_eventos.sql`) — base de la vista Auditoría. Existe porque el dato no era derivable: `tareas.estado` es el valor actual y `generar_tareas_recurrentes()` lo pisa a `pendiente` cada ciclo, así que las veces que una tarea recurrente se completó no dejaban rastro.

**Sin columna `activo`** — excepción explícita a la regla "nunca DELETE, siempre `activo`", registrada en `DECISIONES.md`. **Append-only por permisos**: `GRANT SELECT` a `authenticated` y nada más; el INSERT lo hace solo el trigger `log_evento_tarea_trigger` (`SECURITY DEFINER`, `AFTER UPDATE OF estado ... WHEN (OLD.estado IS DISTINCT FROM NEW.estado)`).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tarea_id | uuid FK → tareas | |
| usuario_id | uuid FK → usuarios, nullable | NULL = sistema: el cron de recurrencia corre `SECURITY DEFINER`, sin `auth.uid()` |
| estado_anterior | enum estado_tarea, nullable | |
| estado_nuevo | enum estado_tarea | |
| created_at | timestamptz | la vista agrupa por día en zona AR: `(created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date` |

Índices: `(created_at DESC)`, `(usuario_id, created_at DESC)`, `(tarea_id)`. RLS `SELECT` exige `tiene_permiso('tareas_auditoria')`.

## tareas_notas

Historial de notas por tarea — se lista completo en el panel de historial del hilo (`RightPanel`), sin abrir tarea por tarea.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tarea_id | uuid FK → tareas | |
| usuario_id | uuid FK → usuarios | |
| nota | text | |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

## tareas_plantillas / tareas_plantillas_items

Lista con nombre reutilizable para poblar un hilo de una — "Agregar desde plantilla" en el panel de historial del hilo crea una tarea por cada ítem activo.

| tareas_plantillas | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text | |
| creado_por | uuid FK → usuarios | |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

| tareas_plantillas_items | tipo | notas |
|---|---|---|
| id | uuid PK | |
| plantilla_id | uuid FK → tareas_plantillas | |
| titulo | text | |
| descripcion | text, nullable | |
| orden | int | |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

Recurso compartido del equipo, no por creador: cualquiera con `tareas_plantillas` edita/desactiva cualquier plantilla (no solo las propias). Lectura además abierta a `tareas_crear` (usarlas sin gestionar el catálogo). Ver `sql/008_tareas_plantillas.sql`.

Seed submódulos: `tareas_mistareas` (vista), `tareas_todas` (vista, sin funciones — solo lectura de todo el sistema), `tareas_plantillas` (vista, sin función — el permiso de la vista ya es gestión completa), `tareas_crear` (funcion, vista_id → tareas_mistareas), `tareas_asignar` (funcion, vista_id → tareas_mistareas).

RLS de `tareas`/`tareas_hilos`/`tareas_notas`/`tareas_plantillas*` expresa la autorización directo con `tiene_permiso()` (sin `service_role`) — ver `sql/004_tareas.sql`, `sql/008_tareas_plantillas.sql`.

---
