# DB SCHEMA — ERP JADA (erp-new)

Fuente de verdad del esquema de base de datos. Mantener sincronizado con `database.types.ts` y migraciones SQL ante cualquier cambio de tablas, columnas o enums.

Proyecto Supabase: `qbpudocgdvpeadcyyhfh`. Regenerar tipos tras cada migración:
`npx supabase gen types typescript --project-id qbpudocgdvpeadcyyhfh --schema public > erp-app/src/lib/supabase/database.types.ts`
(requiere `supabase login` o `SUPABASE_ACCESS_TOKEN`)

Estado actual: `sql/001_usuarios_permisos.sql`, `sql/002_dashboard.sql`, `sql/003_vistas_funciones.sql`, `sql/020_usuarios_activo.sql`, `sql/021_usuarios_editar.sql`, `sql/022_perfil_propio.sql` corridos en Supabase. El módulo comercial (`sql/018`) se eliminó entero con `sql/026_drop_comercial.sql` — tablas, enums, funciones y submódulos ya no existen. Agenda de Obras (`sql/027` a `sql/037`) corrida vía MCP. `database.types.ts` sincronizado tras 027-037. `sql/035_advisors_hardening.sql` corrida vía MCP — no toca tablas, columnas ni enums; `sql/036` y `sql/037` tampoco: son funciones.

**Las policies escriben `(select auth.uid())`, este documento escribe `auth.uid()`.** Desde `sql/035` las 35 policies que lo usaban envuelven la llamada en un subselect: sin eso Postgres la trata como VOLATILE y la re-evalúa una vez por fila. Es una diferencia de plan, no de lógica, así que abajo se sigue citando la forma corta — más legible y equivalente. Al escribir una policy nueva, usar la envuelta.

---

## usuarios

Perfil 1:1 con `auth.users` (mismo `id`). Se crea automáticamente via trigger `on_auth_user_created` al insertar en `auth.users`, y `email` se mantiene sincronizado con trigger `on_auth_user_email_updated` (`sql/021`) — la credencial es `auth.users.email` y esta tabla la espeja, nunca al revés. `nombre` no: vive solo acá (el `user_metadata.nombre` de auth lo lee `handle_new_user` al crear y después queda congelado).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | = auth.users.id |
| nombre | text | |
| email | text | unique parcial WHERE activo |
| activo | boolean | default true |
| created_at / updated_at | timestamptz | |

`activo = false` es la desactivación real, no una marca de UI: le saca los permisos vía `tiene_permiso` (`sql/020`) y el proxy le corta la sesión. `desactivarUsuario` además banea la cuenta en `auth.users` — el access token vivo entraría igual por la API. Se revierte con "Reactivar" (`activo = true` + `ban_duration: "none"`).

RLS: `usuarios_select` (fila propia, o `usuarios_ver` / los permisos de picker listados abajo) y `usuarios_update_propio` (`sql/022`) — `id = auth.uid()` acotado por `GRANT UPDATE (nombre) TO authenticated`, que es lo que impide reactivarse solo desde `/perfil`. El resto de las escrituras siguen pasando por `service_role`.

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

## usuario_tutorial

Qué pasos del tutorial guiado ya vio cada usuario (`sql/019`). Infra cross-módulo como `usuario_widgets`: el namespace vive en el código del paso (`tareas_lista_isla`), no en el nombre de la tabla.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | |
| paso | text | coincide con `PasoTutorial.codigo` en `modules/tareas/components/tutorialPasos.ts` |
| created_at / updated_at | timestamptz | |

Sin `activo`: la fila significa "visto" y nunca se borra ni se desactiva — no tiene otro estado que existir. Volver a ver el tutorial es el botón de la vista, no un reset de datos. UNIQUE normal (usuario_id, paso), por upsert. RLS directo (`usuario_id = auth.uid()`) en SELECT/INSERT/UPDATE, mismo criterio que `usuario_widgets`.

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

Exige `usuarios.activo` además de `usuario_submodulos.activo` y `submodulos.activo` (`sql/020_usuarios_activo.sql`): desactivar a alguien le saca todos los permisos sin tocar sus asignaciones, así reactivarlo se los devuelve tal cual estaban. Verificado con `sql/tests/usuarios_activo.sql`.

---

## Módulo tareas (`sql/005_tareas.sql` + `sql/006_tareas_hardening.sql` + `sql/007_tareas_reactivar_posponer.sql` + `sql/008_tareas_notas_visibilidad.sql` + `sql/009_tareas_miembros_asignables.sql` + `sql/013_tareas_visibilidad_y_miembros.sql` + `sql/014_tareas_asignar.sql` + `sql/015_tareas_hilos_responsable.sql` + `sql/016_miembros_proyecto_activo.sql` + `sql/017_tareas_pasos_y_mision.sql` + `sql/023_tareas_atomicidad.sql` — corridos en Supabase vía MCP)

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
| paso_anterior_id | uuid FK → tareas, nullable | `sql/017` — tarea que debe estar `completada` antes de empezar esta. Inmutable tras el INSERT. Unique parcial `(paso_anterior_id) WHERE activo` (la cadena no bifurca), CHECK `paso_anterior_id IS NULL OR hilo_id IS NOT NULL`, CHECK `paso_anterior_id IS NULL OR recurrencia_cantidad IS NULL` |
| titulo / descripcion | text | |
| visibilidad | enum `visibilidad` | default `privado` (`sql/008`, antes `publico`) — solo importa si hilo_id es null y proyecto_id no |
| estado | enum `estado_tarea` (`pendiente`\|`en_progreso`\|`completada`\|`cancelada`) | default `pendiente` |
| temperatura | int | default 50, CHECK 1-100 — orden personal en UI, cualquier asignado la mueve. La UI escribe solo 85/50/20 (Alta/Media/Baja); el rango sigue siendo 1-100 para no migrar los valores viejos |
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

### Pasos de tarea — triggers (`sql/017`)

`paso_anterior_id` es el eje ortogonal al hilo: el hilo **agrupa** tareas paralelas, la cadena de pasos las **ordena**. La cadena vive entera dentro de un hilo, y de ahí sale su visibilidad — `tareas_select` ya cascadea por `puede_ver_hilo`, así que ver los pasos previos no necesitó ninguna regla nueva.

**"Bloqueada" no es un estado guardado**: se deriva de `paso_anterior.estado <> 'completada'`. No hay valor nuevo en `estado_tarea` — meterlo obligaría a sincronizarlo en cada completar/cancelar/reabrir.

- `validar_paso_tarea` — `BEFORE INSERT OR UPDATE OF paso_anterior_id, hilo_id, recurrencia_cantidad ON tareas`. En INSERT valida que el previo exista, esté activo, tenga el mismo `hilo_id` y no sea recurrente. En UPDATE bloquea tres cosas con `TA005`/`TA006`: cambiar `paso_anterior_id` (inmutable), mover de hilo una tarea encadenada, y volver recurrente una tarea que tiene paso siguiente.
- `validar_paso_previo` — `BEFORE INSERT OR UPDATE OF estado ON tareas`: pasar a `en_progreso`/`completada` con el previo sin completar falla con `TA004`. **`cancelada` queda fuera a propósito** — si un paso se cancela la cadena queda trabada, y cancelar los que siguen tiene que seguir siendo posible o el hilo no cierra nunca.
- `validar_desactivar_paso` — `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED AFTER UPDATE ON tareas WHEN (OLD.activo AND NOT NEW.activo)`: desactivar un paso con siguiente activo falla con `TA007`. Diferido y no `BEFORE` porque `deshacerConversionHilo` desactiva la cadena entera en un solo `.in(...)` — un trigger por fila la vería a medio desactivar según el orden de las filas; al COMMIT ya están todas.

**Ciclos: imposibles por construcción, sin validación.** `paso_anterior_id` solo se puede fijar en el INSERT, y una fila nueva nunca es ancestro de otra → el grafo es siempre un bosque.

**Recurrencia y pasos no conviven** (CHECK del lado siguiente + trigger del lado previo). Por eso `generar_recurrencia` no necesitó cambios: nunca dispara sobre una tarea encadenada.

**Escape hatch de una cadena**: desactivar desde la cola. El último paso nunca tiene siguiente activo, así que siempre se puede sacar.

### Poner a otro en una tarea = función `tareas_asignar` (`sql/014`)

Tercer eje, independiente de `tareas_gestionar_ajenas` (autoridad sobre tareas ajenas) y de la membresía (quién puede trabajar): **quién puede repartir trabajo**. Sin la función, uno se asigna a sí mismo y nada más. Tres piezas, una por cara:

- `tareas_asignados_insert`/`update` — `AND (usuario_id = auth.uid() OR tiene_permiso('tareas_asignar'))`, sumado a las condiciones que ya tenían. Cubre agregar a otro y, por el mismo conjunto, sacarlo (reasignar = desactivar + reinsertar).
- `tareas_insert` — `responsable_id = auth.uid() OR tiene_permiso('tareas_asignar')`. **Reemplaza** la rama `tareas_gestionar_ajenas` que tenía desde `sql/005`: nombrar responsable a otro es asignar, no es gestionar lo ajeno.
- Trigger `validar_responsable_tarea` — `BEFORE UPDATE OF responsable_id ON tareas WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)`: traspasar el responsable a otro sin la función falla con `ERRCODE = 'TA003'`. Va en trigger porque un `WITH CHECK` solo ve la fila nueva y no puede distinguir "cambió el responsable" de "el UPDATE tocó otra columna".

`tareas_gestionar_ajenas` **no** saltea la regla; el backfill de `sql/014` le dio `tareas_asignar` a quien ya la tenía, para no romper equipos en curso.

### El mismo eje sobre hilos (`sql/017`)

`tareas_hilos` no tiene tabla de asignados — el responsable es una columna — así que el eje se aplica en las dos caras de esa columna:

- `tareas_hilos_insert` — `creado_por = auth.uid() AND (responsable_id = auth.uid() OR tiene_permiso('tareas_asignar'))`. **Reemplaza** la rama `tareas_gestionar_ajenas`, igual que `sql/014` hizo con `tareas_insert`.
- `tareas_hilos_update` — el `WITH CHECK` suma `OR tiene_permiso('tareas_asignar')`. Sin eso el traspaso era imposible incluso con la función: la fila nueva tiene `responsable_id` ajeno y el `WITH CHECK` solo aceptaba `responsable_id = auth.uid()`. En `tareas` el problema no aparece porque ahí el `WITH CHECK` tiene además la rama del asignado activo (`sql/013`). Quién puede **tocar** el hilo lo sigue decidiendo el `USING`; quién puede quedar **a cargo** es del trigger.
- Trigger `validar_responsable_hilo` — `BEFORE UPDATE OF responsable_id ON tareas_hilos WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)`: mismo `ERRCODE = 'TA003'` y mismo motivo que `validar_responsable_tarea`.

### Escrituras multi-tabla — funciones `SECURITY INVOKER` (`sql/023`)

Toda action que escribía dos o más tablas es ahora **una** función, invocada con `.rpc()`: el cuerpo corre en una sola transacción, así que un fallo tardío no deja cometido lo anterior. `SECURITY INVOKER` a propósito — RLS se sigue evaluando con la identidad de quien llama y la autoridad no se mueve de las policies.

| función | reemplaza a | tablas |
|---|---|---|
| `crear_tarea(...)` → uuid | `crearTarea` | `tareas` + `tareas_asignados` |
| `crear_proyecto(...)` → uuid | `crearProyecto` | `tareas_proyectos` + `tareas_proyectos_miembros` |
| `convertir_tarea_en_hilo(uuid)` → uuid | `convertirTareaEnHilo` | `tareas_hilos` + `tareas` |
| `deshacer_conversion_hilo(uuid)` | `deshacerConversionHilo` | `tareas` + `tareas_hilos` |
| `desactivar_hilo(uuid)` | `desactivarHilo` | `tareas` + `tareas_hilos` |
| `agregar_tareas_desde_plantilla(...)` | `agregarTareasDesdePlantilla` | `tareas` + `tareas_asignados` |

Los ids se generan con `gen_random_uuid()` en una variable en vez de pedir `RETURNING`: en ese punto la fila todavía no pasa la policy de SELECT (la tarea no tiene asignados, el proyecto no tiene miembros, `puede_ver_hilo` relee su propia tabla).

Dos SQLSTATE nuevos, mapeados en `MENSAJES_ERROR` (`lib/utils.ts`): **`TA008`** — un UPDATE afectó 0 filas, que es como RLS rechaza (reemplaza al `errorDeUpdate()` de TypeScript); **`TA009`** — la plantilla no tiene pasos. `EXECUTE` revocado de `PUBLIC` y otorgado a `authenticated`, mismo criterio que `sql/006`.

Verificación: `sql/tests/atomicidad_tareas.sql` (15/15).

### Ediciones multi-tabla — `sql/024`

Cola de la tanda anterior, con otro modo de falla: estas no dejaban una fila invisible sino **visible y a medio guardar** (el título cambiado con los asignados viejos).

| función | reemplaza a | tablas |
|---|---|---|
| `editar_tarea(...)` | `editarTarea` | `tareas` + `tareas_asignados` |
| `reasignar_tarea(uuid, uuid, uuid[])` | `reasignarTarea` | `tareas` + `tareas_asignados` |
| `editar_proyecto(...)` | `editarProyecto` | `tareas_proyectos` + `tareas_proyectos_miembros` |
| `sincronizar_asignados(uuid, uuid[])` | helper homónimo de `actions.ts` | `tareas_asignados` |

`sincronizar_asignados` es el único escritor de `tareas_asignados` sobre una tarea que ya existe — la comparten `editar_tarea` y `reasignar_tarea`, y si el conjunto no cambió no toca nada. Lleva `GRANT` a `authenticated` porque una función `SECURITY INVOKER` llamada desde otra exige `EXECUTE` al rol que invoca; quedar expuesta por PostgREST no abre nada nuevo (la tabla ya acepta INSERT/UPDATE directo bajo las mismas policies).

En `editar_tarea` el orden es fila-primero-asignados-después, como era en TypeScript: `validar_proyecto_tarea` valida el cambio de `proyecto_id` contra los asignados de ese momento. En `editar_proyecto` la membresía se resuelve por diff — barrer y reinsertar dispararía `validar_quitar_miembro` (TA001) sobre los miembros que se quedan.

Verificación: `sql/tests/atomicidad_edicion_tareas.sql`.

### Archivar un proyecto cascadea — trigger `cascada_desactivar_proyecto` (`sql/025`)

`AFTER UPDATE ON tareas_proyectos ... WHEN (OLD.activo AND NOT NEW.activo)`: desactiva las tareas de los hilos del proyecto y sus tareas sueltas (`proyecto_id` solo se usa sin `hilo_id`), y después los hilos. Simétrico con `desactivar_hilo`, que ya se lleva sus tareas. Antes quedaba todo activo apuntando a un proyecto archivado: el trabajo perdía la agrupación y el select de proyecto del form aparecía vacío sobre un valor todavía seteado.

**Trigger y no función `.rpc()`** porque la cascada no es un acto aparte del usuario sino la consecuencia de archivar; así vale para cualquier escritor de `activo = false` y `desactivarProyecto` sigue siendo el UPDATE de una sola tabla que era.

**`SECURITY DEFINER`, sin mover la autorización.** Quien archiva es el creador-miembro o un manager (`tareas_proyectos_update`), y eso no da UPDATE sobre los hilos de adentro (`tareas_hilos_update` exige ser responsable del hilo o `tareas_gestionar_ajenas`). Con `SECURITY INVOKER` la cascada se frenaría contra RLS en silencio —0 filas no es error— dejando el proyecto archivado y la mitad de adentro viva. El permiso del acto sigue en la policy del UPDATE que dispara el trigger: si esa no pasa, el trigger no corre.

Una cadena de pasos vive entera dentro de un hilo, así que cae completa en una sola sentencia y `trg_validar_desactivar_paso` no encuentra siguientes activos. Los miembros del proyecto no se tocan — no son trabajo, y su SELECT ya exige el proyecto activo (`sql/016`). Reactivar el proyecto no revive nada: archivar es de ida.

Verificación: `sql/tests/cascada_proyecto.sql` (10/10).

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
| tareas_mision | vista | — | `sql/017` — tarea actual de a una, ordenada por temperatura. Sin función propia: "crear siguiente paso" es crear una tarea, ya gateado por `tareas_lista`. Backfill: la recibió todo el que tenía `tareas_lista` |
| tareas_gestionar_ajenas | funcion | tareas_lista | completar/cerrar hilo/reasignar tarea **ajena** — acciones sobre lo propio no requieren función |
| tareas_asignar | funcion | tareas_lista | "Asignar usuarios" (`sql/014`) — poner a otro como asignado o responsable. Sin ella el `AsignadosPicker` muestra solo el resumen y "Reasignar" no aparece en el menú |
| tareas_proyectos_crear | funcion | tareas_proyectos | |
| tareas_proyectos_miembros | funcion | tareas_proyectos | "Asignar miembros" (`sql/013`) — alta/baja de miembros. Sin ella el bloque Miembros no se muestra en `ProyectoFormPanel` y la membresía viaja como default oculto |

`usuarios_select` extendida con `OR tiene_permiso('tareas_lista') OR tiene_permiso('tareas_proyectos')` — picker de asignados/miembros necesita listar usuarios activos.

---

## Módulo obras — Agenda de Obras (`sql/027_obras.sql` a `sql/037_obras_buscar.sql` — corridos en Supabase vía MCP)

Nombre visible: **Agenda de Obras**. `modulo = 'obras'`, ruta `/obras`. Fase 1 es registro y relación de datos: obras, empresas, personas, sus vínculos con roles múltiples, y referentes con comisión por obra. Sin prospectos, oportunidades, presupuestos ni actividades — ver `decisiones/obras.md`.

Extensiones nuevas: `unaccent` y `pg_trgm`, ambas en el schema `extensions` (donde ya viven `pgcrypto` y `uuid-ossp`).

### El modelo de visibilidad, que es lo que gobierna todo lo demás

Tres alcances distintos, y conviene tenerlos claros antes de leer las tablas:

| entidad | quién la ve |
|---|---|
| obra | solo su `responsable_id`. Más quien tenga `obras_transferir`, que las ve todas porque no puede reasignar lo que no ve |
| empresa | todos los que tengan acceso al módulo. Razón social y web son datos casi públicos, y compartirlas evita que cada vendedor cargue su copia de la misma constructora |
| persona | solo quien la creó o la tiene vinculada a una obra propia. `obras_personas_todas` levanta el límite |

La persona es el activo sensible (celular directo del que decide la compra), y por eso es la única entidad con alcance por fila **y** con registro de acceso.

Desde `sql/033` hay un cuarto alcance que se superpone a los tres: la fila **congelada** (`pendiente = true`) la ve únicamente quien la cargó —sea obra, empresa o persona— hasta que alguien con `obras_aprobar` la resuelva.

### obras

Entidad central. Puede existir sin empresas, sin personas y sin dirección.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text NOT NULL | libre, no tiene que ser el nombre oficial ("Edificio próximo a Cabildo" es válido) |
| tipo | enum `tipo_obra` | `edificio`\|`casa`\|`refaccion`\|`complejo_viviendas`\|`local`\|`oficina`\|`hotel`\|`otro` |
| estado | enum `estado_obra` | `idea`\|`en_construccion`\|`perdida`\|`terminada`, default `idea` |
| direccion / localidad | text | opcionales |
| provincia | enum `provincia` | 24 valores (23 provincias + `caba`). Enum y no texto: con texto libre el filtro por ubicación muere el primer día |
| origen | enum `origen_obra` | informativo. No crea relación con empresa ni persona |
| motivo_perdida | enum `motivo_perdida` | |
| detalle_perdida | text | |
| responsable_id | uuid FK → usuarios NOT NULL | **define quién ve la obra** |
| pendiente | boolean NOT NULL default false | `sql/033` — esperando autorización: congelada, no se le pueden colgar vínculos |
| motivo_rechazo | text | por qué la rechazaron. Con `activo = false` es el estado "rechazada" |
| nombre_norm / direccion_norm / localidad_norm | text | derivadas por trigger, para detección difusa |
| activo | boolean | |

`obras_perdida_con_motivo`: `estado <> 'perdida' OR motivo_perdida IS NOT NULL`. El CHECK va en una sola dirección a propósito — pasar a perdida exige motivo, pero salir de perdida **no** lo borra: es información histórica.

`obras_motivo_otro_con_detalle`: `otro` exige `detalle_perdida` no vacío. Los otros motivos se explican solos.

RLS SELECT: `(responsable_id = auth.uid() AND tiene_permiso('obras_ver')) OR tiene_permiso('obras_transferir')`. UPDATE: solo el responsable con `obras_editar` — quien transfiere ve y reasigna, no edita.

**`responsable_id` y `activo` no tienen `GRANT UPDATE`.** Editar, transferir y desactivar son tres permisos distintos; las dos últimas pasan por función que verifica el suyo. Sin esto, cualquiera con `obras_editar` podría transferirse una obra con un UPDATE directo por PostgREST.

### obras_empresas

Sin campo `cuit` (decisión del usuario). La detección de duplicados va por razón social y nombre comercial difusos.

| columna | tipo | notas |
|---|---|---|
| razon_social | text NOT NULL | |
| nombre_comercial / website / telefono / email / direccion / localidad | text | |
| provincia | enum `provincia` | |
| creado_por | uuid FK → usuarios | |
| razon_social_norm / nombre_comercial_norm | text | por trigger |
| pendiente / motivo_rechazo | boolean, text | `sql/033` — congelada la ve solo quien la cargó |

Una empresa **no tiene rol global**: el rol vive en su relación con cada obra. La misma empresa puede ser constructora en una obra y desarrolladora en otra.

### obras_personas

Sin `empresa_id` y sin columna de rol: lo primero vive en `obras_persona_empresa`, lo segundo en `obras_obra_persona`.

| columna | tipo | notas |
|---|---|---|
| nombre | text NOT NULL | |
| apellido / telefono / whatsapp / email | text | |
| creado_por | uuid FK → usuarios | |
| nombre_norm | text | `nombre + apellido` normalizado |
| email_norm | text | lower+trim |
| telefono_norm / whatsapp_norm | text | solo dígitos — "11 4567-8900" y "+54 11 4567 8900" son el mismo teléfono |
| pendiente / motivo_rechazo | boolean, text | `sql/033` — congelada la ve solo quien la cargó |

RLS SELECT: `(tiene_permiso('obras_ver') OR tiene_permiso('obras_personas')) AND (creado_por = auth.uid() OR obras_puede_ver_persona(id))`.

`creado_por` se prueba **como columna y no dentro de la función**. La versión anterior resolvía todo por `obras_puede_ver_persona(id)`, que relee la fila: en un `INSERT ... RETURNING` — lo que hace `.insert().select()` de Supabase — la fila nueva todavía no está en el snapshot de una función `STABLE`, así que el creador no podía leer lo que acababa de escribir (42501). Crear una persona habría fallado siempre en la app. Lo cazó `sql/tests/rls_obras.sql`.

### obras_persona_empresa

`persona_id`, `empresa_id`, `cargo` (texto libre — "Jefe de compras zona sur" no entra en ningún enum), `es_principal`, `observaciones`.

Unique parcial `(persona_id, empresa_id) WHERE activo` y `(persona_id) WHERE activo AND es_principal` — como máximo una empresa principal por persona.

El cargo **no** determina el rol en obra. No se infiere uno del otro.

### obras_obra_empresa / obras_obra_persona

Las dos tablas puente con la obra. `roles` es un **array de enum**, no filas separadas: una empresa que es constructora y desarrolladora de la misma obra es una relación con dos roles, no dos relaciones.

| tabla | roles | extra |
|---|---|---|
| obras_obra_empresa | `rol_empresa[]` — `constructora`\|`desarrolladora`\|`inmobiliaria`\|`estudio_arquitectura`\|`direccion_obra`\|`otro` | |
| obras_obra_persona | `rol_persona[]` — `arquitecto`\|`desarrollador`\|`inversor`\|`director_obra`\|`compras`\|`oficina_tecnica`\|`decisor`\|`influenciador`\|`contacto_comercial`\|`otro` | `empresa_id` nullable: a quién representa esa persona en esta obra. FK simple, sin validación cruzada — es contexto, no invariante |

Las dos llevan además `pendiente` y `motivo_rechazo` (`sql/033`): vincular una entidad que cargó otro usuario espera autorización, y **el vínculo pendiente no cuenta** — ni para los conteos del listado ni, sobre todo, para `obras_puede_ver_persona`.

CHECK en ambas: `cardinality(roles) > 0` y `obras_array_sin_duplicados(roles)`. Unique parcial por par `WHERE activo`.

**`rol_persona` no tiene `referente`** — eso es la existencia de una fila en `obras_obra_referente`. Una sola fuente de verdad.

Una persona figura **una sola vez por obra**, así que representa a una sola empresa en esa obra.

### obras_obra_referente

`obra_id`, `persona_id`, `porcentaje_comision numeric(5,2)` CHECK entre 0 y 100.

La comisión pertenece a la relación obra↔referente, no a la persona ni a la empresa: el mismo referente puede tener 3.50% en una obra y 2.00% en otra.

RLS SELECT exige `obras_referentes` además de ver la obra. La fila **contiene** la comisión, así que verla es verla — no hace falta (ni se permite) un permiso por campo.

### obras_transferencias

Log de cambios de responsable: `obra_id`, `de_usuario_id`, `a_usuario_id`, `ejecutada_por`, `created_at`. CHECK `de <> a`.

Sin `activo`: es un log, la fila significa "esto pasó". Ahora que el responsable decide quién ve la obra, "¿por qué no la veo más?" necesita respuesta.

### obras_accesos_persona

`usuario_id`, `persona_id`, `created_at`. Escrita por `obras_ficha_persona()`, que es el **único** camino por el que la app lee teléfono, whatsapp y email.

Que sea el único es lo que hace que el log sirva. Contra un insider autorizado no hay prevención — quien ve un teléfono lo puede fotografiar — pero esto convierte "se llevó la agenda" en una consulta que muestra 340 fichas abiertas en dos días. RLS SELECT: solo `obras_personas_todas`.

### Helpers de visibilidad

`obras_puede_ver_obra(uuid)` · `obras_es_mi_obra(uuid)` · `obras_puede_ver_persona(uuid)` — `SECURITY DEFINER STABLE`, usadas por las policies. No `EXISTS` directo: dos policies que se miran entre sí dan `42P17 infinite recursion`.

`obras_es_mi_obra` existe aparte de `obras_puede_ver_obra` porque ver no es editar: quien transfiere pasa el primero y no el segundo.

### Normalización y duplicados

`obras_normalizar(text)` — sin acentos, minúsculas, todo lo no alfanumérico a espacio. `obras_normalizar_telefono(text)` — solo dígitos. Ambas `IMMUTABLE`, aplicadas por trigger a las columnas `_norm` (columnas `GENERATED` no sirven: `unaccent()` no es `IMMUTABLE`).

Índices GIN trigram sobre las `_norm`. Umbral de similitud **0.45**, verificado contra datos reales: `XYZ S.A.` ↔ `xyz sa` da 0.50 (detecta), `Edificio Libertador` ↔ `Casa Los Alamos` da 0.03 (no molesta).

Tres funciones de búsqueda, con tres niveles de exposición distintos:

| función | seguridad | qué devuelve |
|---|---|---|
| `obras_buscar_duplicados_empresa` | INVOKER | todo — las empresas son compartidas, no hay nada que ocultar |
| `obras_buscar_duplicados_persona` | DEFINER | identidad mínima: nombre, apellido, empresa principal. **Nunca** teléfono ni email |
| `obras_buscar_duplicados_obra` | DEFINER | de una obra ajena, solo el nombre del responsable. `obra_id`, `nombre`, `direccion` y `localidad` vienen NULL |

El aviso ciego de obras es la salida a un conflicto real: dos vendedores no pueden cargar el mismo edificio, pero tampoco pueden ver las obras del otro. Avisa sin mostrar, y alcanza para que el vendedor vaya a preguntar.

Las tres toman `p_excluir_id` (`sql/031`), que es lo que permite chequear también al editar: sin él, la fila que se está editando se encuentra a sí misma con similitud 1 y avisa de un duplicado que es ella.

En `obras_buscar_duplicados_obra` la localidad **no filtra**, ordena. Filtraba por igualdad exacta del normalizado hasta `sql/031`, y "Devoto" contra "Villa Devoto" alcanzaba para que el aviso no saltara — justo el caso para el que existe. Escrita igual, sube la fila al tope; escrita distinta, ya no esconde nada.

Vincular una persona a una obra propia **no** requiere verla antes — es lo que hace usable la búsqueda de identidad mínima. Es acceso deliberado y queda registrado.

### El buscador global (`sql/037`)

Una barra arriba del módulo busca en las tres entidades y lleva a la ficha. Dos funciones:

| función | seguridad | qué devuelve |
|---|---|---|
| `obras_buscar(p_texto)` | **INVOKER** | `(tipo, id, titulo, subtitulo, visible, cargada_por)` — 5 por tipo, ordenados por "empieza con lo que escribiste" y después por nombre |
| `obras_buscar_personas(p_texto)` | DEFINER + guard `obras_ver`/`obras_personas` | identidad mínima —nombre, apellido, empresa principal— más `visible` y `cargada_por`. **Nunca** teléfono ni email |

**INVOKER es la decisión, no un detalle.** Las ramas de obras y empresas son `SELECT` directos, así que la visibilidad la deciden las policies que ya existen y no hay una segunda copia de la regla. La única que necesita ver más que quien pregunta es la de personas, y por eso va aparte: devuelve las que están fuera de alcance con `visible = false` y sin contacto, igual que `obras_buscar_duplicados_persona`. Encontrar a alguien no es abrirle la ficha — el teléfono sigue saliendo solo por `obras_ficha_persona()`, que registra.

Como `obras_buscar` corre con el rol de quien llama, `obras_buscar_personas` necesita `GRANT EXECUTE` a `authenticated` aunque no la llame nadie más.

**La obra ajena no aparece.** El aviso ciego la devuelve con todo en NULL menos el responsable, así que como resultado de búsqueda sería una fila sin nada que mostrar; el caso que importa —no cargar dos veces el mismo edificio— ya lo cubre `obras_buscar_duplicados_obra` al crear.

El match es `LIKE '%texto%'` sobre las columnas `_norm`, no `similarity`: el parecido de `pg_trgm` sirve para "esto ya está cargado", no para "empecé a escribir el nombre". La normalización además desarma el patrón —`%` y `_` se vuelven espacios— así que un comodín tipeado en la barra no es un comodín. Piso de 2 caracteres, escrito una vez en el CTE `patron`: con menos, las tres ramas se quedan sin fila contra qué joinear.

Verificación: `sql/tests/obras_037.sql`, 15/15.

### Auditoría (`sql/031`)

Los dos logs se leen por función, no por `select` directo:

| función | devuelve |
|---|---|
| `obras_auditoria_accesos(p_dias)` | cada apertura de ficha: fecha, usuario y **nombre** de la persona. Nunca teléfono, whatsapp ni email |
| `obras_auditoria_transferencias(p_dias)` | fecha, obra, de quién, a quién y quién la movió |

Las dos son `SECURITY DEFINER` con guard propio (`tiene_permiso('obras_auditoria')`) y tope de 500 filas. Por función y no por policy porque quien audita necesita ver los accesos de todos y el nombre de la persona para que la fila signifique algo, pero no tiene por qué tener permiso sobre la agenda ni sobre las obras ajenas: con un `select` + embed, un auditor sin `obras_personas` recibiría el log entero con la persona en NULL.

La policy de `obras_accesos_persona` no cambia — sigue siendo `obras_personas_todas` para el acceso directo a la tabla.

### Códigos de error `OB` (`sql/032`)

Las diez `RAISE EXCEPTION` del módulo llevan `USING ERRCODE`. Sin eso salían como `P0001`, que no está en el mapa de `mensajeError()`, y todas se veían como "No se pudo completar la operación. Intentá de nuevo."

| código | dónde | mensaje |
|---|---|---|
| `OB001` | `obras_guard_desactivar_empresa` | participa en **N** obra(s) — el conteo, nunca los nombres |
| `OB002` | `obras_guard_desactivar_persona` | ídem |
| `OB003` | `obras_transferir` | sin permiso para transferir |
| `OB004` | `obras_transferir` | obra inexistente o desactivada |
| `OB005` | `obras_transferir` | la obra ya es de ese usuario |
| `OB006` | `obras_transferir` | el destino no tiene acceso a Obras |
| `OB007` | `obras_set_activo` | sin permiso para desactivar |
| `OB008` | `obras_set_activo` | la obra no existe o no sos su responsable |
| `OB009` | `obras_ficha_persona` | sin acceso a esta persona — no distingue "no existe" de "no la ves" |
| `OB010` | `obras_auditoria_*` | sin permiso para ver la auditoría |
| `OB011` | `obras_guard_congelado` | la obra está pendiente: no acepta vínculos |
| `OB012` | `obras_guard_congelado` | la empresa o la persona está pendiente: no se puede vincular |
| `OB013` | `obras_pendientes` · `obras_historial_aprobaciones` | sin permiso para ver la cola |
| `OB014` | `obras_pendiente_similares` · `obras_resolver_pendiente` | sin permiso para resolver |
| `OB015` | `obras_resolver_pendiente` | tipo de solicitud desconocido |
| `OB016` | `obras_resolver_pendiente` | rechazo sin motivo |
| `OB017` | `obras_resolver_pendiente` | ya resuelta o inexistente |
| `OB018` | `obras_personas_de_empresa` | sin permiso para vincular |
| `OB019` | `obras_guard_congelado` | marcar referente a alguien que no se ve: el vínculo tiene que existir y estar autorizado |

`mensajeError()` devuelve el texto de la base cuando el código matchea `/^OB\d{3}$/`, y cae en el mapa o en el genérico para todo lo demás. No se copió el mapa código → texto de `tareas` porque `OB001` y `OB002` llevan un conteo que un texto fijo perdería. La lista blanca es por código, no por confiar en el mensaje: un `P0001` nuevo sigue cayendo en el genérico. Ver `decisiones/obras.md`.

`obras_guardar_referente(obra, persona, porcentaje, observaciones)` — `SECURITY INVOKER`, `INSERT ... ON CONFLICT (obra_id, persona_id) WHERE activo DO UPDATE`. Reemplaza el SELECT + UPDATE/INSERT que hacía `actions.ts` en dos requests. La autoridad no se mueve: las policies de `obras_obra_referente` siguen exigiendo `obras_referentes` y que la obra sea propia. Un referente dado de baja no revive por acá: el índice parcial no ve su fila, así que se inserta una nueva.

### Autorizaciones pendientes (`sql/033`)

Dos pedidos del usuario con una sola mecánica: un alta que se parece a algo ya cargado, y un vínculo con una persona o empresa que cargó otro, no entran a la agenda — entran **congelados**, y alguien con `obras_aprobar` decide.

`pendiente` y `motivo_rechazo` viven en las cinco tablas que pueden esperar: `obras`, `obras_empresas`, `obras_personas`, `obras_obra_empresa`, `obras_obra_persona`. No hay estado nuevo:

| situación | columnas |
|---|---|
| en la cola | `pendiente = true` |
| aprobada | `pendiente = false`, `activo = true` |
| rechazada | `pendiente = false`, `activo = false`, `motivo_rechazo` con el texto |

**Congelada quiere decir congelada.** La fila la ve solo quien la cargó (policy de `obras_empresas`, `obras_puede_ver_persona` para las personas) y `obras_guard_congelado` corta cualquier vínculo hacia o desde ella (`OB011` / `OB012`). Un `pendiente` que solo pintara un badge dejaría al duplicado propagándose mientras la cola espera.

**El vínculo pendiente no abre la ficha de contacto.** `obras_puede_ver_persona` exige `NOT op.pendiente`. Es el punto entero del pedido: vincular era lo que daba acceso al teléfono, así que sin esto la autorización no protegería nada.

**`obras_aprobar` no entra en `obras_puede_ver_persona`.** Quien aprueba mira la cola por función; darle la fila por policy le habría dado la agenda entera con contacto. Ver `decisiones/obras.md`.

#### Triggers

| trigger | tablas | qué hace |
|---|---|---|
| `marcar_pendiente` (`obras_marcar_pendiente`) | las 5 | BEFORE INSERT. En las tres entidades marca por parecido (`obras_similares_*`); en los dos vínculos, si `creado_por` de lo vinculado no es `auth.uid()`. Pisa `pendiente` y `motivo_rechazo`: el `GRANT INSERT` es por tabla, así que sin esto el cliente mandaría la fila ya aprobada |
| `guard_congelado` (`obras_guard_congelado`) | `obras_obra_empresa`, `obras_obra_persona`, `obras_persona_empresa`, `obras_obra_referente` | BEFORE INSERT. Corta si la obra, la empresa o la persona está pendiente, y exige que la persona ya sea visible para marcarla referente (`OB019`) — esa fila también da acceso al contacto y no tiene `pendiente`. Los `IF` van **anidados** bajo `TG_TABLE_NAME`, no encadenados con `AND`: plpgsql planea la expresión entera y `NEW.obra_id` explota con 42703 en la tabla que no tiene esa columna |

`obras_obra_persona.empresa_id` queda fuera del guard a propósito: es contexto informativo, no un vínculo con la empresa.

#### Funciones

| función | seguridad | qué hace |
|---|---|---|
| `obras_similares_obra` / `_empresa` / `_persona` | DEFINER | el match difuso crudo: ids y score, sin enmascarar ni verificar permiso. Es la mitad de abajo de las tres `obras_buscar_duplicados_*`, extraída para que el trigger use el mismo criterio que la pantalla |
| `obras_buscar_duplicados_*` | DEFINER / INVOKER | mismas firmas de siempre, ahora como capa de enmascarado sobre las anteriores |
| `obras_etiqueta(tipo, id)` | DEFINER | una fila de cualquiera de las cinco tablas → texto. Interna: sin `GRANT` |
| `obras_pendientes()` | DEFINER + guard `obras_pendientes` | la cola: tipo, id, etiqueta, motivo, solicitante, fecha. Tope 500 |
| `obras_pendiente_similares(tipo, id)` | DEFINER + guard `obras_aprobar` | contra qué se parece. **Única pantalla del módulo que muestra el nombre de una obra ajena** — sin eso, aprobar es a ciegas |
| `obras_resolver_pendiente(tipo, id, aprobar, motivo)` | DEFINER + guard `obras_aprobar` | UPDATE dinámico sobre lista blanca de tablas + fila en el log. Rechazo sin motivo: `OB016` |
| `obras_historial_aprobaciones(dias)` | DEFINER + guard `obras_pendientes` | las decisiones ya tomadas |

De las tres `obras_similares_*`, solo `_empresa` tiene `GRANT` a `authenticated`: el envoltorio de empresas es `SECURITY INVOKER` —para que la policy siga decidiendo qué ve cada uno— y por lo tanto la ejecuta como quien llama.

#### obras_aprobaciones

Log de decisiones: `tipo`, `registro_id`, `etiqueta` (snapshot), `aprobada`, `motivo`, `decidido_por`, `created_at`. Sin `activo` y sin FK a la fila decidida — es un log de cinco tablas y el `tipo` dice cuál. RLS SELECT: `tiene_permiso('obras_pendientes')`.

#### GRANT UPDATE por columna

`obras_empresas`, `obras_personas`, `obras_obra_empresa` y `obras_obra_persona` tenían `UPDATE` entero: con eso un PATCH por PostgREST se auto-aprueba poniendo `pendiente = false`. Ahora la lista es explícita (y deja afuera `creado_por` y las `_norm`), igual que `obras` desde `sql/027`.

### Vincular una empresa con su gente (`sql/034`)

| función | seguridad | qué hace |
|---|---|---|
| `obras_personas_de_empresa(empresa, obra)` | DEFINER + guard `obras_vincular` | la gente de una empresa con identidad mínima —nombre, apellido, cargo, nunca contacto— más `es_mia` y `ya_en_obra`. Con un select directo, quien vincula vería solo las personas a su alcance y la lista perdería sentido |
| `obras_vincular_empresa(obra, empresa, roles, obs, personas jsonb)` | INVOKER | el vínculo de la empresa y los de las personas en una transacción. Devuelve `vinculo_pendiente`, `personas_agregadas` y `personas_pendientes` para que el toast no mienta |

`p_personas` es `[{"persona_id": uuid, "roles": [...]}]` — un rol por persona, no uno para el lote. `ON CONFLICT (obra_id, persona_id) WHERE activo DO NOTHING`: quien ya estaba en la obra queda como estaba, con sus roles intactos.

### Desactivación

Nunca DELETE. `obras_set_activo(uuid, boolean)` exige `obras_desactivar` **y** ser el responsable. Sin cascada sobre los vínculos: la obra se puede reactivar tal como estaba.

Empresas y personas son compartidas, así que desactivarlas puede romper obras ajenas — y quien lo hace ni siquiera puede ver el daño. Triggers `obras_guard_desactivar_empresa` / `_persona` bloquean la desactivación si la entidad participa en alguna obra **activa**, con mensaje que dice cuántas y nunca cuáles (mismo criterio que el aviso ciego). `obras_cascada_desactivar` da de baja las relaciones `obras_persona_empresa` cuando la desactivación sí procede, para no dejar un cargo colgado.

Esa misma función cuelga además de `obras_obra_persona` (`sql/036`): desvincular a una persona de una obra baja su fila de `obras_obra_referente`. Sin eso el referente sobrevivía al vínculo —`getReferentes` lo lee sin pasar por él— y la comisión vieja reaparecía al volver a vincular a la misma persona. Las tres ramas van explícitas por `TG_TABLE_NAME`, y sigue `SECURITY DEFINER` porque la policy de UPDATE de `obras_obra_referente` exige `obras_referentes`, que quien desvincula puede no tener. Verificación: `sql/tests/obras_036.sql`, 8/8.

### Hardening (`sql/029`)

`GRANT EXECUTE ... TO authenticated` no quita nada: Postgres otorga EXECUTE a `PUBLIC` por defecto, así que las `SECURITY DEFINER` del módulo quedaban invocables por `anon` — sin login — vía `/rest/v1/rpc/`. No era explotable (todas cortan con `tiene_permiso`), pero la defensa no puede depender de que nadie toque el guard después. `REVOKE ... FROM PUBLIC` en las 18 funciones del módulo, `GRANT` explícito solo a `authenticated`, y ninguno para las de solo-trigger. Más `search_path` fijo en los tres helpers inmutables.

Verificado: `has_function_privilege('anon', ...)` da `false` en las 18.

### Permisos (submódulos `modulo = 'obras'`)

| codigo | tipo | vista_id | notas |
|---|---|---|---|
| obras_ver | vista | — | listado y ficha de obra |
| obras_empresas | vista | — | |
| obras_personas | vista | — | |
| obras_auditoria | vista | — | los dos logs. Aparte de `obras_personas_todas`: ese permiso es ver la agenda completa, este es ver quién la estuvo mirando |
| obras_pendientes | vista | — | la cola de autorizaciones y su historial (`sql/033`) |
| obras_crear | funcion | obras_ver | |
| obras_editar | funcion | obras_ver | solo sobre obras propias |
| obras_vincular | funcion | obras_ver | obra↔empresa y obra↔persona, con sus roles |
| obras_referentes | funcion | obras_ver | ver y editar referente + comisión. Es lo que oculta la comisión a quien no la debe ver |
| obras_transferir | funcion | obras_ver | **implica ver todas las obras**. Darlo con criterio |
| obras_desactivar | funcion | obras_ver | separado de editar: cargar datos no es lo mismo que hacer desaparecer una obra |
| obras_empresas_crear | funcion | obras_empresas | |
| obras_empresas_editar | funcion | obras_empresas | |
| obras_personas_crear | funcion | obras_personas | |
| obras_personas_editar | funcion | obras_personas | |
| obras_personas_empresas | funcion | obras_personas | relacionar persona↔empresa. El botón de la ficha de empresa usa este mismo permiso — una función pertenece a una sola vista |
| obras_personas_todas | funcion | obras_personas | ve la agenda completa y el log de accesos |
| obras_aprobar | funcion | obras_pendientes | aprobar o rechazar. Es el "administrador" de los pedidos del usuario — **no** da acceso a la agenda: `obras_puede_ver_persona` no lo mira |

Combinación a tener presente: crear una empresa o persona desde adentro de una obra necesita `obras_empresas_crear` / `obras_personas_crear` además de `obras_vincular`. Con solo `obras_vincular` se pueden enlazar las que ya existen.

`usuarios_select` extendida con `OR tiene_permiso('obras_transferir')` — el picker de destino necesita listar usuarios.

Verificación: `sql/tests/rls_obras.sql`, 29/29 · `sql/tests/obras_033.sql`, 33/33.

---

## Notificaciones (`sql/038_notificaciones.sql` — corrida en Supabase vía MCP)

Infra cross-módulo como `usuario_widgets` y `usuario_tutorial`: prefijo `usuario_`, RLS directo por `auth.uid()`, **sin submódulo y sin vista propia**. Nadie necesita permiso para recibir avisos de cosas que ya puede ver — el permiso lo puso la entidad apuntada, no la notificación.

### usuario_notificaciones

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

### Función `notificar(usuario, tipo, entidad, entidad_id, actor)`

`SECURITY DEFINER`. Único lugar donde nace una notificación, y donde vive "no te notifiques a vos mismo". `IS DISTINCT FROM` y no `<>`: con `auth.uid()` NULL (service_role, SQL editor) la comparación daría NULL y el aviso se perdería en silencio.

### Los tres triggers

| trigger | tabla | destinatario |
|---|---|---|
| `trg_notificar_decision_obra` | `obras_aprobaciones` AFTER INSERT | `obras_solicitante(tipo, registro_id)` — `alta_aprobada` o `alta_rechazada` según `aprobada` |
| `trg_notificar_transferencia_obra` | `obras_transferencias` AFTER INSERT | `a_usuario_id` |
| `trg_notificar_tarea_asignada` | `tareas_asignados` AFTER INSERT OR UPDATE OF activo | `usuario_id`, solo cuando la fila pasa a activa |

**Al que le sacaron la obra no se le avisa.** Ya no la ve (`obras_select` es `obras_puede_ver_obra`): un aviso con el nombre sería la única grieta del módulo y uno sin el nombre no diría nada. Esa pregunta la contesta `obras_auditoria_transferencias`.

**`pg_trigger_depth() > 1`** en el de tareas filtra la copia de asignados de `generar_recurrencia`: una tarea diaria mandaría un aviso por día a cada asignado, y ahí nadie asignó a nadie.

### Función `notificaciones_listar(p_limite int DEFAULT 30)`

`SECURITY INVOKER`. Cada rama del UNION es un INNER JOIN contra la tabla apuntada, así que la RLS del lector decide qué sobrevive — una notificación cuya entidad dejó de ser visible desaparece de la lista sin una segunda copia de la regla de visibilidad. Devuelve `etiqueta`, `motivo` (el `motivo_rechazo` de la fila), `actor`, y `destino`/`destino_id` para navegar; los vínculos llevan a la obra, que es la que tiene ficha.

El badge cuenta las no leídas **de esta lista**, no de la tabla: si contara filas crudas quedaría más alto que lo que se ve.

### Función `notificaciones_avisos()`

`SECURITY INVOKER`, devuelve `(vencidas, vencen_hoy)` de las tareas asignadas al que pregunta. Lo que es estado y no evento no genera filas: sin cron que las cree a medianoche ni pasada que las limpie al completar. Mismo criterio que `reactivar_posponer_vencidos()` — se calcula al leer. El filtro por asignado va explícito porque la RLS de `tareas` deja ver bastante más que lo propio.

### Cambios sobre el módulo obras

- **`obras_etiqueta` pasa a `SECURITY INVOKER`** (era DEFINER). La bandeja necesita el único lugar donde una fila de las cinco tablas se vuelve texto, pero otorgarle EXECUTE siendo DEFINER la habría convertido en un bypass: con el uuid de una obra ajena —que el aviso ciego de `sql/037` devuelve con el nombre en NULL a propósito— cualquiera habría recuperado el nombre. Como INVOKER devuelve NULL para lo que el que pregunta no ve, así que otorgarla es inofensivo. Sus dos llamadores (`obras_pendientes`, `obras_resolver_pendiente`) no cambian: son DEFINER de `postgres`, que tiene BYPASSRLS. Verificado — misma salida sobre las 72 filas antes y después.
- **`obras_solicitante(p_tipo, p_id)`** — nueva, `SECURITY DEFINER`, sin GRANT. El mapa de las cinco tablas a quién pidió el alta estaba adentro del UNION de `obras_pendientes()`; el trigger de la decisión necesitaba el mismo mapa. Extraída y usada por los dos. Verificado — 0 discrepancias sobre las 72 filas.
