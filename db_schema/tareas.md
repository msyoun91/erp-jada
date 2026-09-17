# Módulo tareas

Migraciones: `sql/005`–`009`, `013`–`017`, `023`, `053`, `055`–`061`, `063`, `076`–`080` (más las que cita cada sección) — corridas en Supabase vía MCP.

**Regla de visibilidad (`sql/013`): se ve lo asignado y lo público, nada más** — `creado_por` no autoriza. Excepciones: `tareas_gestionar_ajenas` y `tareas_hilos.responsable_id`. Los UPDATE están alineados con los SELECT. El porqué, en `decisiones/tareas/visibilidad.md`.

## tareas_proyectos

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

## tareas_proyectos_miembros

Lista explícita de membresía: **quién puede recibir tareas del proyecto** (`sql/009`). Ortogonal a `visibilidad`, que decide quién lo ve — aunque desde `sql/013` la membresía también da acceso a los proyectos privados, porque el creador dejó de tenerlo por serlo. Todo proyecto — público o privado — necesita al menos un miembro.

Alta y baja de miembros exigen `tareas_gestionar_ajenas` (cualquier proyecto) o la función `tareas_proyectos_miembros` **en un proyecto donde quien la usa es miembro** (`sql/076`: antes valía en cualquiera, y uno se sumaba a un privado ajeno). Única excepción: la siembra inicial, acotada por `proyecto_tiene_miembros()` — sin ella `tareas_proyectos_crear` no alcanzaría para crear nada, ya que el proyecto exige al menos un miembro. **El SELECT de la tabla no mira esa función**: leer la membresía sigue siendo de miembros y managers (agregarla filtraba los miembros de proyectos que el usuario ni ve — lo detectó el caso 02 de `sql/tests/rls_miembros_asignables.sql`).

El SELECT sí exige que el proyecto siga **activo** (`sql/016`): archivar un proyecto le saca la fila de la lista, pero sus membresías seguían visibles y `getMiembrosPorProyecto` armaba entradas de mapa para proyectos que ya no existen para el usuario. El `EXISTS` directo sobre `tareas_proyectos` no recursa — el lado de vuelta llega a esta tabla por `es_miembro_proyecto` (`SECURITY DEFINER`), así que el ciclo ya está roto.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| proyecto_id | uuid FK → tareas_proyectos | |
| usuario_id | uuid FK → usuarios | |
| activo | boolean | unique parcial (proyecto_id, usuario_id) WHERE activo |
| created_at | timestamptz | |

## tareas_hilos

Agrupador de tareas relacionadas. Sin vencimiento propio (se deriva de sus tareas en `queries.ts`).

`GRANT UPDATE` por columna (`sql/076`): `titulo`, `descripcion`, `visibilidad`, `estado`, `responsable_id`, `posponer_desde`, `posponer_hasta`, `activo`. Sin `proyecto_id` (un hilo no se mueve de proyecto), `creado_por`, `id` ni `created_at`. `tareas_hilos_insert` exige además `proyecto_id IS NULL OR tareas_proyecto_destino_valido(proyecto_id, auth.uid())`.

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

## tareas

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
| fecha_vencimiento | date | nullable. Con `vence_dias_tras_previo` es derivada: la escriben los triggers de `sql/053` y `editar_tarea` no la pisa |
| vence_dias_tras_previo | int | nullable, `sql/053` — el plazo corre desde que se completa el paso anterior. CHECK `> 0 AND paso_anterior_id IS NOT NULL`. Mientras el previo no esté completado, `fecha_vencimiento` es NULL |
| posponer_desde / posponer_hasta | date | nullable — sin cron: se recalcula al leer (`queries.ts`), no vía job |
| recurrencia_cantidad | int | nullable, junto con recurrencia_unidad (ambos o ninguno) |
| recurrencia_unidad | enum `recurrencia_unidad` (`dia`\|`mes`) | nullable |
| nota_anterior / nota_siguiente | text | nullable — "nota de la última vez" de tareas recurrentes |
| origen_app / origen_punto | text | nullable — qué módulo o app la generó y el deep link a la acción. `origen_punto` solo ruta interna (`/...`), validado en `crearTareaSchema` y de nuevo al renderizar (`modules/tareas/origen.ts`). Al nacer en un hilo sin link propio, `trg_heredar_origen_hilo` (`sql/058`, BEFORE INSERT, INVOKER) copia el de la tarea activa más antigua del hilo que tenga uno |
| modo_completado | enum `modo_completado` (`manual`\|`automatico`\|`hibrido`) | default `manual` |
| activo | boolean | |
| created_at / updated_at | timestamptz | `created_at` default `clock_timestamp()` desde `sql/053` (no `now()`): es el orden de los pasos en la Lista, y `now()` le daba a toda la cadena que crea una función el mismo instante |

**`GRANT UPDATE` por columna (`sql/077`):** `titulo`, `descripcion`, `hilo_id`, `proyecto_id`, `visibilidad`, `estado`, `temperatura`, `responsable_id`, `fecha_vencimiento`, `vence_dias_tras_previo`, `posponer_desde`, `posponer_hasta`, `recurrencia_cantidad`, `recurrencia_unidad`, `nota_siguiente`, `activo`. Quedan afuera `id`, `creado_por`, `created_at`, `modo_completado` (un asignado completaba una `hibrido` pasándola a `manual` en la misma sentencia), `origen_*`, `paso_anterior_id` y `nota_anterior`. Mismo criterio en `tareas_proyectos` (`nombre`, `descripcion`, `visibilidad`, `activo`) y en `tareas_proyectos_miembros`, `tareas_asignados`, `tareas_notas` y `tareas_hilos_notas` (solo `activo`).

**Reactivar es del administrador (`sql/077`).** Trigger `validar_reactivar_tarea` (`SECURITY DEFINER`) en `tareas` y `tareas_hilos`, `BEFORE UPDATE OF activo WHEN (NOT OLD.activo AND NEW.activo)`: sin `tareas_gestionar_ajenas`, `TA018`. Antes un asignado revivía lo que archivó un manager o la cascada del proyecto.

**Largos (`sql/078`).** CHECK `tareas_largos`: `titulo` ≤ 500, `descripcion`, `nota_siguiente` y `nota_anterior` ≤ 5000, `origen_app` ≤ 100, `origen_punto` ≤ 500. CHECK `tareas_origen_punto_interno`: `origen_punto ~ '^/(?!/)'`. Los mismos topes en hilos y proyectos (título o nombre ≤ 500, `descripcion` ≤ 5000), notas (≤ 5000) y plantillas, hilos e items de plantilla. Son más holgados que Zod (200 y 2000) porque `rellenar_datos` expande `{dato}` después de validar el form.

**Fechas en hora de Argentina (`sql/078`).** La base corre en UTC. Las funciones que calculan fechas de tareas llevan `SET timezone = 'America/Argentina/Buenos_Aires'`, así que su `current_date` es la fecha AR: `reactivar_posponer_vencidos`, `fijar_vencimiento_tras_previo`, `arrancar_vencimiento_siguiente`, `generar_recurrencia`, `usar_plantilla` y `notificaciones_avisos`. El `SET` vale también para los triggers que se disparan adentro. Índices parciales `idx_tareas_posponer_hasta` e `idx_tareas_hilos_posponer_hasta` (`WHERE posponer_hasta IS NOT NULL`).

**Vencimiento tras el paso anterior (`sql/053`).** Dos triggers `SECURITY DEFINER`, única fuente de la fecha derivada: `trg_fijar_vencimiento_tras_previo` (`BEFORE INSERT OR UPDATE OF vence_dias_tras_previo`, solo cuando el plazo cambia) la pone en `current_date + N` si el previo ya está completado y en NULL si no; `trg_arrancar_vencimiento_siguiente` (`AFTER UPDATE OF estado`, al entrar o salir de `completada`) la arranca en el paso siguiente al completar y la vuelve a NULL al reabrir. DEFINER porque quien completa un paso puede no tener UPDATE sobre el siguiente.

**Recurrencia sin `pg_cron`:** la próxima instancia se genera al completar la actual (trigger `generar_recurrencia`), no por fecha de calendario — copia asignados y `nota_siguiente` → `nota_anterior` de la nueva.

**Quién la ve — `tareas_puede_ver_tarea_de(id, hilo_id, visibilidad, proyecto_id, usuario)` (`sql/067`).** `SECURITY DEFINER STABLE`, sin GRANT: `tareas_gestionar_ajenas`, o asignación activa, o con hilo `puede_ver_hilo_de`, o suelta pública sin proyecto / en proyecto público / siendo miembro. Recibe las columnas y no solo el id porque en un UPDATE la policy de SELECT se evalúa también sobre la fila nueva, y releer `tareas` por id daría la vieja. La policy `tareas_select` es `tareas_puede_ver_tarea(id, hilo_id, visibilidad, proyecto_id)`, el envoltorio con `auth.uid()` (DEFINER, **GRANT authenticated**).

**`tarea` es un ente (`sql/067`, ver `core.md`).** Ramas del módulo en las genéricas: `tareas_etiqueta(tipo, id)` (INVOKER, **GRANT authenticated**: el título si la ve y está activa), `tareas_puede_abrir(tipo, id, usuario)` (DEFINER, sin GRANT: activa y `tareas_puede_ver_tarea_de`) y `tareas_buscar(texto)` (INVOKER, **GRANT authenticated**: `(tipo, id, titulo, subtitulo)`, subtítulo = hilo o proyecto; normaliza con `obras_normalizar`, mínimo dos letras, lo pendiente primero, 10 filas). Sin rama para compartir: una tarea no se comparte, se asigna.

## tareas_asignados

Multi-asignado — cualquiera puede completar la tarea.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tarea_id | uuid FK → tareas | |
| usuario_id | uuid FK → usuarios | |
| activo | boolean | unique parcial (tarea_id, usuario_id) WHERE activo |
| created_at | timestamptz | |

## tareas_notas / tareas_hilos_notas (`sql/008`)

Historial de notas — "agregar", no "editar": sin UPDATE de texto, solo `activo` para ocultar una nota propia (nunca DELETE). Desde `sql/077` lo garantiza el `GRANT UPDATE (activo)`; antes el grant era de tabla y el autor reescribía el texto. `tareas_notas.tarea_id` FK → `tareas`; `tareas_hilos_notas.hilo_id` FK → `tareas_hilos`. Ambas con `usuario_id` FK → `usuarios` (autor) y `nota text`.

SELECT vía `EXISTS` directo sobre la tabla padre (`tareas`/`tareas_hilos`) — sin función `SECURITY DEFINER`: la RLS de la tabla padre ya resuelve visibilidad en cascada para el rol que consulta, y no hay recursión porque esa policy no mira hacia las tablas de notas. INSERT: mismo actor que puede gestionar la fila padre (`tareas_notas` reusa `es_responsable_tarea`/`es_asignado_tarea`; `tareas_hilos_notas` usa `responsable_id` del hilo), más `tareas_gestionar_ajenas`, y desde `sql/080` `tareas_puede_escribir()`. UPDATE (solo `activo=false`): autor o ajenas.

## tareas_plantillas / tareas_plantillas_hilos / tareas_plantillas_items (`sql/053`)

Dos alcances. **Privada**: la ve, la modifica y la usa solo su dueño (`creado_por`). **De sistema**: la ve y la usa todo el que tiene la vista `tareas_plantillas`; la crea, modifica y desactiva quien tiene la función `tareas_plantillas_sistema`. Hasta `sql/053` eran un único recurso de equipo que cualquiera con la vista editaba.

Tres tipos: `tarea` (un paso), `hilo` (pasos encadenados o, desde `sql/057`, en paralelo) y `proyecto` (proyecto + miembros + hilos de pasos + tareas sueltas).

| tareas_plantillas | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre / descripcion | text | descripcion nullable |
| alcance | enum `alcance_plantilla` (`sistema`\|`privada`) | default `privada`. Inmutable: fuera del `GRANT UPDATE` |
| tipo | enum `tipo_plantilla` (`tarea`\|`hilo`\|`proyecto`) | default `hilo` |
| visibilidad | enum `visibilidad` | default `privado` — la del proyecto que crea una de tipo `proyecto` |
| miembros | uuid[] | default `{}`, CHECK solo en tipo `proyecto`. Array y no tabla: es configuración que se copia al usar, no una relación viva. Al usarla se descartan los inactivos y se suma quien la usa |
| creado_por | uuid FK → usuarios | dueño de la privada. Fuera del `GRANT UPDATE` |
| disparo_ente | text FK → entes(codigo), nullable | `sql/055` — el ente cuyo evento la dispara (`core.md`). NULL = se usa a mano |
| disparo_evento | enum `tipo_evento`, nullable | `sql/068` — qué le pasa al ente. Tiene que estar en `entes.disparos` (`TA012` y las policies de INSERT/UPDATE). Backfill: `estado` en las que ya disparaban |
| disparo_estado | text, nullable | `sql/055` — estado destino, solo con `disparo_evento = 'estado'`. `guardar_plantilla` valida que exista en el enum del ente (`TA012`) |
| disparo_rol | text, nullable | `sql/068` — `ente:rol` (como `adjuntos`), solo con `relacion_alta`/`relacion_baja`: la obra suma o pierde ese rol. CHECK `tareas_plantillas_disparo_completo`: sin ente, los cuatro NULL; con ente, evento, y estado o rol según el evento |
| titulo_creado | text, nullable | `sql/057` — nombre del hilo o proyecto que crea; NULL = `nombre`. Admite `{dato}`. En tipo `tarea` se guarda NULL |
| encadenada | boolean | default true, `sql/057` — solo la lee el tipo `hilo`: false = sus pasos no se esperan entre sí. Fuera de ese tipo se guarda true |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

| tareas_plantillas_hilos | tipo | notas |
|---|---|---|
| id | uuid PK | |
| plantilla_id | uuid FK → tareas_plantillas | solo en plantillas de tipo `proyecto` |
| titulo | text | título del hilo que se crea |
| orden | int | |
| encadenada | boolean | default true, `sql/057` — false = los pasos del hilo no se esperan entre sí |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

| tareas_plantillas_items | tipo | notas |
|---|---|---|
| id | uuid PK | |
| plantilla_id | uuid FK → tareas_plantillas | |
| hilo_id | uuid FK → tareas_plantillas_hilos, nullable | NULL = paso de un hilo/tarea, o tarea suelta de un proyecto |
| titulo / descripcion | text | descripcion nullable |
| orden | int | default 0 — dentro de su hilo, el orden de la cadena |
| asignados | uuid[] | usuarios fijos. Sin FK: se validan al usar |
| incluir_ejecutor | boolean | default true — quien usa la plantilla queda entre los asignados. CHECK `incluir_ejecutor OR cardinality(asignados) > 0` |
| responsable_id | uuid FK → usuarios, nullable | NULL = quien la usa (exige `incluir_ejecutor`); si no, tiene que estar en `asignados` |
| vence_dias | int | nullable, > 0 |
| vence_tras_previo | boolean | default false — el plazo corre desde que se completa el paso anterior (exige `vence_dias`). En el primer paso de una cadena vale como "desde la creación" |
| temperatura | int | default 50, 1-100 |
| adjuntos | text[] | default `{}`, `sql/060` — roles (`ente:rol`, como `persona:arquitecto`) cuyos registros se vinculan a la tarea al disparar. CHECK de formato |
| condicion | text, nullable | `sql/060` — rol que tiene que existir en el registro para que el paso se cree; `!ente:rol` (`sql/065`), rol que **no** tiene que existir. CHECK de formato `^!?[a-z_]+:[a-z_]+$` |
| activo | boolean | |
| created_at | timestamptz | |

**RLS.** `tareas_plantillas_select`: vista `tareas_plantillas` y (`alcance = 'sistema'`, dueño o `tareas_gestionar_ajenas`). La última rama es de `sql/079`: la función que administra ve y usa las privadas ajenas, pero no las edita. INSERT: dueño + vista, y `alcance = 'privada'` o la función. UPDATE (tabla y los dos hijos): `puede_gestionar_plantilla(id)` — función `SECURITY INVOKER STABLE` (la de sistema, con la función; la privada, su dueño); no recursa porque las policies de `tareas_plantillas` no miran a los hijos. SELECT de los hijos: `EXISTS` sobre `tareas_plantillas` (su RLS decide). INSERT/UPDATE de items suma la regla de `sql/014`: asignados o responsable ajenos exigen `tareas_asignar`. En el UPDATE está desde `sql/079` (antes faltaba) y no se aplica a apagar un paso, porque `guardar_plantilla` desactiva los viejos antes de insertar.

**Escritura por función.** `guardar_plantilla(p_id, p_nombre, p_descripcion, p_alcance, p_tipo, p_visibilidad, p_miembros, p_hilos jsonb, p_pasos jsonb, p_disparo_ente, p_disparo_estado, p_titulo_creado, p_encadenada, p_disparo_evento, p_disparo_rol) → uuid` (cada hilo de `p_hilos` lleva su `encadenada`) crea o edita (`p_id` NULL = crear; `p_alcance` solo se lee al crear). Guardar **reemplaza**: desactiva los hilos y pasos activos e inserta los nuevos — nada referencia a un paso de plantilla. Valida la forma según el tipo (`TA010`) y que haya pasos (`TA009`); sin disparador, rechaza pasos con roles (`TA015`, `sql/060`). `usar_plantilla(p_plantilla_id, p_titulo, p_proyecto_id, p_hilo_id) → int` — ver la tabla de escrituras multi-tabla. Lo que crea se llama `p_titulo`, si no `titulo_creado`, si no `nombre`; los pasos se encadenan según `encadenada` de la plantilla (tipo `hilo`) o de su hilo (tipo `proyecto`), y sin cadena «vence tras el anterior» corre desde la creación (`sql/057`).

**Disparador (`sql/055`, `sql/068`).** Con `disparo_ente`, la plantilla no se usa a mano: corre sola cuando a un registro de ese ente le pasa `disparo_evento` (se crea, entra a `disparo_estado`, suma o pierde `disparo_rol`), para quien hizo el cambio y la tiene activada. Las tres policies de `tareas_plantillas` suman `disparo_ente IS NULL OR EXISTS (entes)`; la RLS de `entes` pide su submódulo, así que sin `obras_ver` una plantilla de obra no se ve ni se arma. En INSERT y UPDATE el `EXISTS` exige además `disparo_evento = ANY (entes.disparos)` (`sql/068`): sin eso un PATCH directo colgaría una plantilla del alta de una tarea. En UPDATE va en el `WITH CHECK`, sobre la fila nueva, porque el disparador sí cambia. `GRANT UPDATE` suma las cuatro columnas.

| tareas_plantillas_activaciones (`sql/055`) | tipo | notas |
|---|---|---|
| id | uuid PK | |
| plantilla_id | uuid FK → tareas_plantillas | |
| usuario_id | uuid FK → usuarios | |
| activo | boolean | el interruptor. UNIQUE normal (plantilla_id, usuario_id), por upsert |
| created_at / updated_at | timestamptz | |

La de sistema arranca apagada (sin fila); la privada, prendida: `guardar_plantilla` inserta la fila del dueño cuando tiene disparador, con `ON CONFLICT DO NOTHING` para no pisar un apagado. RLS: SELECT la propia; INSERT/UPDATE la propia, y además que la plantilla tenga disparador y sea de sistema o propia. Desde `sql/079` "verla" no alcanza: quien administra ve las privadas ajenas, y activarlas las haría correr con sus cambios. `GRANT SELECT, INSERT, UPDATE`.

| tareas_vinculos (`sql/055`, `sql/059`, `sql/066`, `sql/067`) | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tarea_id | uuid FK → tareas | |
| ente | text FK → entes(codigo) | misma forma que `usuario_notificaciones.entidad` |
| registro_id | uuid | sin FK — apunta a la tabla del ente |
| plantilla_id | uuid FK → tareas_plantillas, nullable | `sql/059`: NULL = vinculada a mano (al crear o con «Relacionar»); con valor, la vinculó un disparo |
| roles | text[] | default `{}`, `sql/066` — los roles del registro por los que lo adjuntó el paso (`adjuntos`), sin prefijo de ente, por código. CHECK `tareas_vinculos_roles_de_disparo`: solo con `plantilla_id` |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

Con qué registros se relaciona cada tarea —de otros módulos o, desde `sql/067`, otra tarea—, y qué tareas salieron de cada (plantilla, registro). Unique parcial `idx_tareas_vinculos_activo_unico (tarea_id, ente, registro_id) WHERE activo` (`sql/059`). CHECK `tareas_vinculos_no_a_si_misma`: `ente <> 'tarea' OR registro_id <> tarea_id` (`sql/067`).

RLS: SELECT si la tarea es visible. INSERT (`sql/059`), dos caminos: con `plantilla_id`, solo con `pg_trigger_depth() > 0` —lo escribe `usar_plantilla` adentro del disparo, y uno insertado por el cliente bloquearía el disparo real para todos—; sin `plantilla_id`, poder gestionar la tarea (`tareas_puede_gestionar_tarea`, `sql/077`: antes alcanzaba con verla) o estar en siembra (`es_siembra_tarea`), y el registro visible (`etiqueta_registro` no NULL, ver `core.md`). UPDATE solo de `activo`, solo sin plantilla, solo quien gestiona la tarea y **solo para apagar** (`sql/077`): volver a relacionar es `vincular_tarea`, que revisa el registro y a los asignados. Apagar el de un disparo lo dejaría volver a disparar.

`tareas_puede_gestionar_tarea(tarea)` (`sql/077`, `SECURITY DEFINER STABLE`, GRANT authenticated): la misma regla que el USING de `tareas_update` — `tareas_gestionar_ajenas`, responsable, asignado activo o responsable del hilo. `GRANT SELECT, INSERT, UPDATE (activo)`.

Lecturas (`sql/059`, las tres `SECURITY INVOKER STABLE`, EXECUTE para `authenticated`):

- `vinculos_de_tareas()` — los vínculos activos de las tareas activas visibles, con `etiqueta`, `href` (la `ruta` del ente con el id), `de_plantilla` y `roles` (`sql/066`, DROP + CREATE). Sin fila si el registro no se ve. La precarga `getListaTareas`.
- `tareas_de_registro(ente, registro_id)` — ids y orden de las tareas activas visibles vinculadas a un registro de Obras (lo terminado al final). Vacío si el registro no se ve. Desde Fase B (`PLAN_TAREAS_VINCULOS.md`) `getTareasDeRegistro` (`modules/tareas/queries.ts`) solo usa ids y orden: la fila completa (asignados, notas) sale de una segunda consulta con el mismo select que `getListaTareas`, para que la sección Tareas de una ficha monte `TareaCard` real en vez de una fila resumida.
- `buscar_registros(modulo, texto)` (`sql/061`) — "Relacionar": el módulo se elige antes (toggle en la UI). `obras` → `obras_buscar` sin lo ajeno enmascarado, y `tareas` → `tareas_buscar` (`sql/067`); solo entes cuyo submódulo tiene quien busca, con `href`. Un módulo que registre entes suma su rama (`plpgsql`, `ELSIF p_modulo = '…'`).
- `vincular_tarea(p_tarea_id, p_ente, p_registro_id)` (`sql/063`), **GRANT authenticated** — reemplaza el INSERT directo de la action `vincularTarea`: inserta el vínculo y, si la tarea tiene asignados activos, corre `sincronizar_asignados` sobre ellos con el responsable actual (misma regla de acceso que crear/editar, ver más abajo). Sin asignados no se llama: si no, relacionar asignaría a quien relaciona.
- `sin_acceso_tarea(p_tarea_id, p_usuarios uuid[], p_vinculos jsonb DEFAULT '[]')` (`sql/064`), `SECURITY INVOKER STABLE`, **GRANT authenticated** — la pregunta de la UI antes de editar, reasignar o relacionar: `sin_acceso` (`core.md`) sobre `p_usuarios` × los vínculos activos de la tarea más `p_vinculos` (el que se está por relacionar). Lee `tareas_vinculos` con la RLS de quien pregunta, que muestra todos los vínculos de una tarea visible; `vinculos_de_tareas` en cambio descarta los que no ve, y armar la pregunta con eso dejaba afuera justo los que la base iba a aplicar igual.

**El disparo — `disparar_plantillas()` (`sql/055`, `sql/056`, `sql/063`, `sql/068`).** Trigger `SECURITY INVOKER`, `AFTER INSERT ON eventos` desde `sql/068` (antes, directo sobre `obras`; ver `core.md`). Corre si `current_user = 'authenticated'` (bajo una DEFINER correría con BYPASSRLS). Junta las plantillas visibles que quien actuó tiene activadas y coinciden con el evento: `disparo_ente`, `disparo_evento`, y `disparo_estado` contra `detalle.estado` o `disparo_rol` contra `detalle.ente:detalle.rol`. Si hay alguna, lee la fila de `entes.tabla` con su RLS y sigue solo si está activa; arma los datos (`entes.datos`) y recorre esas plantillas, y por cada una, si `plantilla_disparada(plantilla, ente, registro)` es falso, llama a `usar_plantilla(..., p_ente, p_registro_id, p_datos)`. Cada plantilla va en su bloque `EXCEPTION`: si corre, `notificar_disparo(plantilla, true, sin_acceso)` le avisa a quien disparó — `sin_acceso` compara la longitud de `sin_acceso_registrado()` antes y después de esa plantilla, así que el aviso es `plantilla_sin_acceso` en vez de `plantilla_disparada` si algún paso dejó a alguien afuera (`sql/063`); si falla, se revierte lo suyo y `notificar_disparo(plantilla, false)`. Si no creó ningún paso porque todos pedían un rol que el registro no tiene (`TA014`, `sql/060`), se revierte sin aviso. Marca la transacción con `tareas.disparo` para que las asignaciones avisen (ver `notificaciones.md`) y al final le devuelve el valor que tenía: las tareas que crea emiten su alta y el trigger vuelve a entrar (sin plantillas que coincidan, sale antes de tocar nada). No resetea `tareas.sin_acceso` — el ensayo de `obras_ensayar_estado` (`obras.md`) necesita lo de todas las plantillas de la transacción.

- `plantilla_disparada(uuid, text, uuid)` — `SECURITY DEFINER STABLE`: hay alguna tarea **activa** vinculada a (plantilla, ente, registro). Completadas y canceladas cuentan; archivadas no. EXECUTE para `authenticated` (la llama el disparo), y fuera de un trigger devuelve false.
- `rellenar_datos(text, jsonb, text[])` — en título y descripción de cada paso, título de hilo y nombre de lo que crea. Primero los bloques `{si hay ente:rol}…{fin}` / `{si no hay ente:rol}…{fin}` contra los roles del tercer parámetro (`sql/065`; sin anidar, una cabecera que no se entiende queda como texto, NULL = ningún rol), después `{clave}` → valor. `IMMUTABLE`. EXECUTE solo `authenticated`.
- Roles (`sql/060`, `sql/065`): `usar_plantilla` calcula una vez los roles del registro con `relacionados_de_registro` (ver `core.md`), saltea el paso cuya `condicion` no se cumple (`ente:rol` que nadie tiene, `!ente:rol` que alguien tiene) —la cadena sigue del último creado y un hilo de proyecto sin pasos no se abre—, le pasa los roles a `rellenar_datos` y vincula a cada tarea los registros con alguno de sus `adjuntos`, uno por registro con esos roles en `roles` (`sql/066`). Sin ningún paso creado, `TA014`.

## ~~tareas_eventos~~ → `eventos` (`sql/068`)

Borrada con su trigger `log_evento_tarea`: sus filas pasaron a `eventos` (`core.md`) con `ente = 'tarea'`, `evento = 'estado'` y `detalle = {estado, anterior}`. `tareas` cuelga `emitir_eventos_registro('tarea')` (`AFTER INSERT OR UPDATE OF activo, estado`): además del estado, ahora quedan alta, baja y reactivación, y el estado al nacer. La vista Auditoría lee de ahí (`getAuditoria`). **Quién ve el log cambió:** era `usuario_id = auth.uid() OR tareas_auditoria`; ahora es la RLS de `eventos`, así que un manager deja de ver lo completado en tareas que no puede abrir o que están archivadas (aceptado por el usuario, `decisiones/global/entes.md`). Una tarea no dispara plantillas (`entes.disparos` vacío).

## Función `puede_ver_hilo(uuid)`

`SECURITY DEFINER`, `STABLE` — resuelve visibilidad en cascada de un hilo (responsable/asignado a alguna de sus tareas/permiso `tareas_gestionar_ajenas`/cascada proyecto público-o-miembro). **Sin `creado_por` desde `sql/013`.** Usada en RLS de `tareas_hilos`. `EXECUTE` revocado de `PUBLIC`, otorgado solo a `authenticated` (`sql/006`). Desde `sql/067` es el envoltorio de `puede_ver_hilo_de(hilo, usuario)` (mismo cuerpo por usuario explícito, sin GRANT), que usa `tareas_puede_ver_tarea_de`.

## Funciones `es_creador_proyecto(uuid)` / `es_responsable_tarea(uuid)` / `es_asignado_tarea(uuid)` / `proyecto_tiene_miembros(uuid)`

`SECURITY DEFINER`, `STABLE` — mismo criterio que `puede_ver_hilo`. Usadas en las policies de `tareas_proyectos_miembros` y `tareas_asignados` para no consultar directamente `tareas_proyectos`/`tareas`/`tareas_asignados` desde dentro de su propia política: dos tablas con policies que se referencian mutuamente (`tareas_proyectos` ↔ `tareas_proyectos_miembros`, `tareas` ↔ `tareas_asignados`) causan `42P17 infinite recursion detected in policy` si la referencia es un `EXISTS` directo bajo RLS. Envolver el lado "de vuelta" en una función `SECURITY DEFINER` rompe el ciclo (`sql/005`, fix aplicado post-creación).

`es_responsable_tarea` reemplaza a `es_responsable_o_creador_tarea` (borrada en `sql/013`): con la rama del creador, quien perdía la asignación se la devolvía a sí mismo por API insertando en `tareas_asignados`. No hace falta esa rama para crear — `tareas_insert` ya exige `responsable_id = auth.uid()` a quien no tiene `tareas_asignar` (`tareas_gestionar_ajenas` hasta `sql/014`). Por el mismo motivo, `tareas_asignados_update` acota `usuario_id = auth.uid()` a `NOT activo` en su `WITH CHECK`: sacarme de una tarea es mío, re-agregarme no.

## Funciones `es_miembro_proyecto(uuid, uuid)` / `es_miembro_proyecto_de_tarea(uuid, uuid)` (`sql/009`)

`SECURITY DEFINER`, `STABLE` — mismo criterio anti-recursión que `es_creador_proyecto`. La segunda resuelve el proyecto **efectivo** de una tarea (`COALESCE(tareas.proyecto_id, tareas_hilos.proyecto_id)`) y devuelve `true` si la tarea no tiene proyecto. Usadas por `tareas_asignados_insert`/`update` (`AND (NOT activo OR es_miembro_proyecto_de_tarea(tarea_id, usuario_id))` — la regla se exige solo sobre filas activas, para no bloquear la desactivación al reasignar) y por `tareas_proyectos_miembros_select`, extendida para que un miembro vea a los demás miembros (sin eso el picker de asignados queda vacío para quien no es creador del proyecto). Desde `sql/076`, `tareas_gestionar_ajenas` —la función que administra— tampoco la saltea en la policy, pero `crear_tarea` y `sincronizar_asignados` llaman antes a `tareas_sumar_miembros_admin(tarea, usuarios)` (INVOKER, GRANT authenticated): si quien llama tiene la función, suma al proyecto efectivo a los que no son miembros. Sin la función no hace nada.

## Triggers `validar_proyecto_tarea` / `validar_quitar_miembro` (`sql/009`)

Las policies cubren "cambian los asignados"; estos dos triggers cubren las otras dos caras de la misma regla:

- `validar_proyecto_tarea` — `BEFORE UPDATE OF proyecto_id, hilo_id ON tareas`: mover una tarea a un proyecto donde algún asignado activo no es miembro falla con `ERRCODE = 'TA002'`; con `tareas_gestionar_ajenas` los suma al proyecto (`sql/076`).
- `validar_quitar_miembro` — `BEFORE UPDATE ON tareas_proyectos_miembros WHEN (OLD.activo AND NOT NEW.activo)`: quitar un miembro con tareas `pendiente`/`en_progreso` en el proyecto falla con `ERRCODE = 'TA001'`, en vez de desactivar sus asignaciones por detrás.

Ambos SQLSTATE están mapeados a mensaje en `MENSAJES_ERROR` (`lib/utils.ts`). Por eso `editarProyecto` guarda un diff (quitados/agregados) en vez de desactivar todo y reinsertar: lo segundo dispararía `TA001` sobre los miembros que se quedan.

## Destino de una tarea — trigger `validar_destino_tarea` (`sql/076`)

`BEFORE INSERT OR UPDATE OF hilo_id, proyecto_id ON tareas`, `SECURITY DEFINER`. Sin `auth.uid()` (postgres, service_role) no valida. Solo mira el valor que cambia:

- **Hilo:** activo y `puede_ver_hilo_de(hilo, auth.uid())`, o creado por quien escribe y sin otras tareas activas (`convertir_tarea_en_hilo` crea el hilo con el responsable de la tarea y mueve la tarea después). Antes, con el id de un hilo ajeno, uno se colaba adentro, se asignaba y leía el hilo entero.
- **Proyecto:** `tareas_proyecto_destino_valido(proyecto, usuario)` (`SECURITY DEFINER STABLE`, GRANT authenticated, fuente única con `tareas_hilos_insert`): activo y público, o miembro, o `tareas_gestionar_ajenas`.

Falla con `ERRCODE = 'TA017'`.

## Escribir y gestionar — `tareas_puede_escribir` / trigger `validar_gestionar_tarea` (`sql/080`)

`tareas_puede_escribir()` (`SECURITY INVOKER STABLE`, GRANT authenticated): alguna vista de tareas que crea — `tareas_lista`, `tareas_mision`, `tareas_proyectos` o `tareas_plantillas`. Auditoría no. La exigen las policies de INSERT de `tareas`, `tareas_hilos`, `tareas_notas` y `tareas_hilos_notas`.

`validar_gestionar_tarea` — `BEFORE UPDATE OF hilo_id, posponer_desde, posponer_hasta, activo ON tareas`, cuando alguno cambia (`activo` solo al apagar), `SECURITY INVOKER`. Pide responsable de la tarea, responsable del hilo donde está (OLD) o `tareas_gestionar_ajenas`; si no, `TA019`. Solo con `current_user = 'authenticated'`: bajo una DEFINER (cascada del proyecto, `reactivar_posponer_vencidos`) no valida. `proyecto_id` no entra: `editar_tarea` lo escribe y editar es del asignado.

## Pasos de tarea — triggers (`sql/017`)

`paso_anterior_id` es el eje ortogonal al hilo: el hilo **agrupa** tareas paralelas, la cadena de pasos las **ordena**. La cadena vive entera dentro de un hilo, y de ahí sale su visibilidad — `tareas_select` ya cascadea por `puede_ver_hilo`, así que ver los pasos previos no necesitó ninguna regla nueva.

**"Bloqueada" no es un estado guardado**: se deriva de `paso_anterior.estado <> 'completada'`. No hay valor nuevo en `estado_tarea` — meterlo obligaría a sincronizarlo en cada completar/cancelar/reabrir.

- `validar_paso_tarea` — `BEFORE INSERT OR UPDATE OF paso_anterior_id, hilo_id, recurrencia_cantidad ON tareas`. En INSERT valida que el previo exista, esté activo, tenga el mismo `hilo_id` y no sea recurrente. En UPDATE bloquea tres cosas con `TA005`/`TA006`: cambiar `paso_anterior_id` (inmutable), mover de hilo una tarea encadenada, y volver recurrente una tarea que tiene paso siguiente.
- `validar_paso_previo` — `BEFORE INSERT OR UPDATE OF estado ON tareas`: pasar a `en_progreso`/`completada` con el previo sin completar falla con `TA004`. **`cancelada` queda fuera a propósito** — si un paso se cancela la cadena queda trabada, y cancelar los que siguen tiene que seguir siendo posible o el hilo no cierra nunca.
- `validar_desactivar_paso` — `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED AFTER UPDATE ON tareas WHEN (OLD.activo AND NOT NEW.activo)`: desactivar un paso con siguiente activo falla con `TA007`. Diferido y no `BEFORE` porque `deshacerConversionHilo` desactiva la cadena entera en un solo `.in(...)` — un trigger por fila la vería a medio desactivar según el orden de las filas; al COMMIT ya están todas.

**Ciclos: imposibles por construcción, sin validación.** `paso_anterior_id` solo se puede fijar en el INSERT, y una fila nueva nunca es ancestro de otra → el grafo es siempre un bosque.

**Recurrencia y pasos no conviven** (CHECK del lado siguiente + trigger del lado previo). Por eso `generar_recurrencia` no necesitó cambios: nunca dispara sobre una tarea encadenada.

**Escape hatch de una cadena**: desactivar desde la cola. El último paso nunca tiene siguiente activo, así que siempre se puede sacar.

## Poner a otro en una tarea = función `tareas_asignar` (`sql/014`)

Tercer eje, independiente de `tareas_gestionar_ajenas` (autoridad sobre tareas ajenas) y de la membresía (quién puede trabajar): **quién puede repartir trabajo**. Sin la función, uno se asigna a sí mismo y nada más. Tres piezas, una por cara:

- `tareas_asignados_insert`/`update` — `AND (usuario_id = auth.uid() OR tiene_permiso('tareas_asignar'))`, sumado a las condiciones que ya tenían. Cubre agregar a otro y, por el mismo conjunto, sacarlo (reasignar = desactivar + reinsertar).
- `tareas_insert` — `responsable_id = auth.uid() OR tiene_permiso('tareas_asignar')`. **Reemplaza** la rama `tareas_gestionar_ajenas` que tenía desde `sql/005`: nombrar responsable a otro es asignar, no es gestionar lo ajeno. Desde `sql/080` suma `tareas_puede_escribir()`.
- Trigger `validar_responsable_tarea` — `BEFORE UPDATE OF responsable_id ON tareas WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)`: traspasar el responsable a otro sin la función falla con `ERRCODE = 'TA003'`. Va en trigger porque un `WITH CHECK` solo ve la fila nueva y no puede distinguir "cambió el responsable" de "el UPDATE tocó otra columna".

`tareas_gestionar_ajenas` **no** saltea la regla; el backfill de `sql/014` le dio `tareas_asignar` a quien ya la tenía, para no romper equipos en curso.

**Siembra de asignados (`sql/053`).** `tareas_asignados_insert` pedía además ser responsable de la tarea (o `tareas_gestionar_ajenas`), así que crear una tarea con **otro** como responsable fallaba con `42501` para quien tenía `tareas_asignar` sin `gestionar_ajenas` — el backfill de arriba lo tapaba. Suma la rama `es_siembra_tarea(tarea_id)` (`SECURITY DEFINER STABLE`): el creador carga asignados mientras la tarea no tuvo **nunca** ninguno (ni inactivo). "Nunca" y no "ninguno activo": si no, el creador que quedó afuera volvería a entrar cuando el último asignado se saca solo — el hueco que cerró `sql/013`. Mismo patrón que la siembra de miembros de proyecto.

## El mismo eje sobre hilos (`sql/017`)

`tareas_hilos` no tiene tabla de asignados — el responsable es una columna — así que el eje se aplica en las dos caras de esa columna:

- `tareas_hilos_insert` — `creado_por = auth.uid() AND (responsable_id = auth.uid() OR tiene_permiso('tareas_asignar'))`. **Reemplaza** la rama `tareas_gestionar_ajenas`, igual que `sql/014` hizo con `tareas_insert`. Desde `sql/076` suma el proyecto destino y desde `sql/080` `tareas_puede_escribir()`.
- `tareas_hilos_update` — el `WITH CHECK` suma `OR tiene_permiso('tareas_asignar')`. Sin eso el traspaso era imposible incluso con la función: la fila nueva tiene `responsable_id` ajeno y el `WITH CHECK` solo aceptaba `responsable_id = auth.uid()`. En `tareas` el problema no aparece porque ahí el `WITH CHECK` tiene además la rama del asignado activo (`sql/013`). Quién puede **tocar** el hilo lo sigue decidiendo el `USING`; quién puede quedar **a cargo** es del trigger.
- Trigger `validar_responsable_hilo` — `BEFORE UPDATE OF responsable_id ON tareas_hilos WHEN (NEW.responsable_id IS DISTINCT FROM OLD.responsable_id)`: mismo `ERRCODE = 'TA003'` y mismo motivo que `validar_responsable_tarea`.

## Escrituras multi-tabla — funciones `SECURITY INVOKER` (`sql/023`)

Toda action que escribía dos o más tablas es ahora **una** función, invocada con `.rpc()`: el cuerpo corre en una sola transacción, así que un fallo tardío no deja cometido lo anterior. `SECURITY INVOKER` a propósito — RLS se sigue evaluando con la identidad de quien llama y la autoridad no se mueve de las policies.

| función | reemplaza a | tablas |
|---|---|---|
| `crear_tarea(...)` → uuid | `crearTarea` | `tareas` + `tareas_vinculos` (`sql/059`) + `tareas_asignados` |
| `crear_proyecto(...)` → uuid | `crearProyecto` | `tareas_proyectos` + `tareas_proyectos_miembros` |
| `convertir_tarea_en_hilo(uuid)` → uuid | `convertirTareaEnHilo` | `tareas_hilos` + `tareas` |
| `deshacer_conversion_hilo(uuid)` | `deshacerConversionHilo` | `tareas` + `tareas_hilos` — desde `sql/078` desactiva el resto antes de mover la primera (con pasos encadenados fallaba siempre con `TA006`); desde `sql/081` es `SECURITY DEFINER` con guarda propia (responsable del hilo o `tareas_gestionar_ajenas`, si no `TA008`) |
| `desactivar_hilo(uuid)` | `desactivarHilo` | `tareas` + `tareas_hilos` |
| ~~`agregar_tareas_desde_plantilla(...)`~~ | ~~`agregarTareasDesdePlantilla`~~ | borrada en `sql/053` → `usar_plantilla` |
| `usar_plantilla(uuid, text, uuid, uuid, text, uuid, jsonb)` → int (`sql/053`; `sql/055` suma `p_ente`, `p_registro_id`, `p_datos` con DEFAULT NULL) | `usarPlantilla` y el disparo | `tareas_proyectos` + miembros + `tareas_hilos` + `tareas` + `tareas_asignados` + `tareas_notas` + `tareas_vinculos` |
| `guardar_plantilla(...)` → uuid (`sql/053`; `sql/055` suma `p_disparo_ente`, `p_disparo_estado`; `sql/068`, `p_disparo_evento` —sin él, `estado`— y `p_disparo_rol`; todos DEFAULT NULL) | `guardarPlantilla` (reemplaza `crearPlantilla`/`editarPlantilla`) | `tareas_plantillas` + `_hilos` + `_items` + `_activaciones` |

`crear_tarea` y `editar_tarea` suman `p_vence_dias_tras_previo int` al final (`sql/053`, firma nueva; la vieja se borró). `sql/059` suma a `crear_tarea` `p_vinculos jsonb DEFAULT '[]'` (`[{ente, registro_id}]`), insertados antes que los asignados para que la siembra deje vincular una tarea que quien la crea no va a ver. `sql/063` suma a cada elemento un `plantilla_id` opcional (lo copia un disparo) y filtra los asignados por acceso — ver *Quien no puede abrir lo relacionado no queda asignado* más abajo y en `decisiones/tareas/visibilidad.md`.

**`usar_plantilla`** es `SECURITY INVOKER`: se usa a mano y la RLS de quien la usa decide igual que en los formularios. Crea según el tipo — `tarea`: una tarea en `p_hilo_id` o suelta (con `p_proyecto_id` o personal); `hilo`: pasos encadenados en `p_hilo_id` o en un hilo nuevo titulado `p_titulo`; `proyecto`: un proyecto nuevo (`p_titulo`) con sus miembros activos + quien la usa, un hilo público por hilo de la plantilla y sus tareas sueltas (`TA011` si se le pasa destino). Cada paso lo reciben los asignados fijos que pueden (activos, miembros del proyecto efectivo, y ajenos solo si quien la usa tiene `tareas_asignar`) más quien la usa si `incluir_ejecutor`; **si no queda nadie, el paso va a quien la usa con una nota en `tareas_notas` que dice por qué** (decisión del usuario: la tarea no se pierde). Devuelve cuántos pasos cayeron así. Toda la creación pasa por `crear_tarea` / `crear_proyecto`. Desde `sql/063`, además arma el vínculo del registro y sus adjuntos (`ente:rol`) con `plantilla_id` y se lo pasa a `crear_tarea`, que aplica el filtro de acceso — reemplaza los dos `INSERT` directos a `tareas_vinculos` que hacía antes.

Los ids se generan con `gen_random_uuid()` en una variable en vez de pedir `RETURNING`: en ese punto la fila todavía no pasa la policy de SELECT (la tarea no tiene asignados, el proyecto no tiene miembros, `puede_ver_hilo` relee su propia tabla).

SQLSTATE mapeados en `MENSAJES_ERROR` (`lib/utils.ts`): **`TA008`** — un UPDATE afectó 0 filas, que es como RLS rechaza (reemplaza al `errorDeUpdate()` de TypeScript); **`TA009`** — la plantilla no tiene pasos; **`TA010`** (`sql/053`) — la plantilla no corresponde a su tipo; **`TA011`** (`sql/053`) — una plantilla de proyecto usada con destino; **`TA012`** (`sql/055`) — el disparador no es válido (estado fuera del enum del ente, o ente sin su submódulo); **`TA013`** (`sql/055`) — una plantilla con disparador usada a mano, o una sin disparador disparada; **`TA016`** (`sql/063`) — sacar a alguien sin acceso de una tarea sin tener `tareas_asignar`; **`TA017`** (`sql/076`) — el hilo o proyecto destino no existe, no está activo o no se ve; **`TA018`** (`sql/077`) — reactivar una tarea o un hilo sin `tareas_gestionar_ajenas`. `EXECUTE` revocado de `PUBLIC` y otorgado a `authenticated`, mismo criterio que `sql/006`.

Verificación: `sql/tests/atomicidad_tareas.sql` (15/15).

## Ediciones multi-tabla — `sql/024`

Cola de la tanda anterior, con otro modo de falla: estas no dejaban una fila invisible sino **visible y a medio guardar** (el título cambiado con los asignados viejos).

| función | reemplaza a | tablas |
|---|---|---|
| `editar_tarea(...)` | `editarTarea` | `tareas` + `tareas_asignados` |
| `reasignar_tarea(uuid, uuid, uuid[])` | `reasignarTarea` | `tareas` + `tareas_asignados` |
| `editar_proyecto(...)` | `editarProyecto` | `tareas_proyectos` + `tareas_proyectos_miembros` |
| `sincronizar_asignados(uuid, uuid[], uuid)` | helper homónimo de `actions.ts` | `tareas_asignados` + `tareas.responsable_id` |

`sincronizar_asignados` es el único escritor de `tareas_asignados` y de `responsable_id` sobre una tarea que ya existe — la comparten `editar_tarea`, `reasignar_tarea` y `vincular_tarea`, y si ni el conjunto ni el responsable cambiaron no toca nada. Lleva `GRANT` a `authenticated` porque una función `SECURITY INVOKER` llamada desde otra exige `EXECUTE` al rol que invoca; quedar expuesta por PostgREST no abre nada nuevo (la tabla ya acepta INSERT/UPDATE directo bajo las mismas policies).

Desde `sql/077` la regla también está en `tareas_asignados_insert/update`: una fila activa exige `tareas_asignado_puede_abrir(tarea, usuario)` (`SECURITY DEFINER STABLE`, GRANT authenticated: ningún vínculo activo de la tarea deja afuera a ese usuario; quien actúa está eximido). Antes un INSERT directo se salteaba el filtro. Desde `sql/063` filtra por acceso (`asignados_con_acceso` contra los vínculos activos de la tarea) antes de comparar: el early return mira el conjunto *ya filtrado* contra lo que hay, no lo que pidió el cliente. Si el filtro deja a alguien afuera y quien llama no tiene `tareas_asignar`, revierte entero con `TA016` — ver `decisiones/tareas/visibilidad.md` → *Quien no puede abrir lo relacionado no queda asignado*.

Desde `sql/064` escribe por diferencia y en el orden que piden las policies: altas, bajas ajenas, el responsable (tercer argumento; si no quedó asignado, quien llama o el primero que quedó), y la baja propia al final. Quien se queda no recibe otro «te asignaron», y quien tiene `tareas_asignar` sin `tareas_gestionar_ajenas` puede pasar la tarea entera a otro. `editar_tarea` y `reasignar_tarea` ya no escriben `responsable_id`: lo dejan en manos de esta función. Ver *Asignados por diferencia, la pregunta completa y compartir en orden* en `decisiones/tareas/visibilidad.md`.

En `editar_tarea` el orden es fila-primero-asignados-después, como era en TypeScript: `validar_proyecto_tarea` valida el cambio de `proyecto_id` contra los asignados de ese momento. En `editar_proyecto` la membresía se resuelve por diff — barrer y reinsertar dispararía `validar_quitar_miembro` (TA001) sobre los miembros que se quedan. Desde `sql/076` inserta antes de quitar: quien se saca a sí mismo en el mismo guardado todavía es miembro cuando la policy mira las altas.

Verificación: `sql/tests/atomicidad_edicion_tareas.sql`.

## Archivar un proyecto cascadea — trigger `cascada_desactivar_proyecto` (`sql/025`)

`AFTER UPDATE ON tareas_proyectos ... WHEN (OLD.activo AND NOT NEW.activo)`: desactiva las tareas de los hilos del proyecto y sus tareas sueltas (`proyecto_id` solo se usa sin `hilo_id`), y después los hilos. Simétrico con `desactivar_hilo`, que ya se lleva sus tareas. Antes quedaba todo activo apuntando a un proyecto archivado: el trabajo perdía la agrupación y el select de proyecto del form aparecía vacío sobre un valor todavía seteado.

**Trigger y no función `.rpc()`** porque la cascada no es un acto aparte del usuario sino la consecuencia de archivar; así vale para cualquier escritor de `activo = false` y `desactivarProyecto` sigue siendo el UPDATE de una sola tabla que era.

**`SECURITY DEFINER`, sin mover la autorización.** Quien archiva es el creador-miembro o un manager (`tareas_proyectos_update`), y eso no da UPDATE sobre los hilos de adentro (`tareas_hilos_update` exige ser responsable del hilo o `tareas_gestionar_ajenas`). Con `SECURITY INVOKER` la cascada se frenaría contra RLS en silencio —0 filas no es error— dejando el proyecto archivado y la mitad de adentro viva. El permiso del acto sigue en la policy del UPDATE que dispara el trigger: si esa no pasa, el trigger no corre.

Una cadena de pasos vive entera dentro de un hilo, así que cae completa en una sola sentencia y `trg_validar_desactivar_paso` no encuentra siguientes activos. Los miembros del proyecto no se tocan — no son trabajo, y su SELECT ya exige el proyecto activo (`sql/016`). Reactivar el proyecto no revive nada: archivar es de ida.

Verificación: `sql/tests/cascada_proyecto.sql` (10/10).

## Función `reactivar_posponer_vencidos()`

`SECURITY DEFINER` — sin cron: `queries.getListaTareas()` la invoca (`supabase.rpc(...)`) antes de leer la lista. Limpia `posponer_desde`/`posponer_hasta` de `tareas`/`tareas_hilos` cuyo `posponer_hasta` ya venció, y en `tareas` corre `fecha_vencimiento` el mismo intervalo que duró el pospuesto. `EXECUTE` solo para `authenticated` (`sql/007`).

**Hardening (`sql/006`):** `EXECUTE` revocado de `PUBLIC` en las funciones `SECURITY DEFINER` de solo-trigger (`generar_recurrencia`, `log_evento_tarea` —borrada en `sql/068`—, `reabrir_hilo_en_tarea`, `validar_cierre_hilo`) — PostgREST expone toda función a `PUBLIC` por default y estas no necesitan ser invocables vía RPC. Índices agregados en FKs `creado_por`/`responsable_id` sin cobertura.

## Permisos (submódulos `modulo = 'tareas'`)

| codigo | tipo | vista_id | notas |
|---|---|---|---|
| tareas_lista | vista | — | listado unificado personal + proyectos visibles |
| tareas_proyectos | vista | — | |
| tareas_plantillas | vista | — | ver y usar las de sistema; crear, ver y usar las privadas propias |
| tareas_auditoria | vista | — | solo-lectura, se asigna directo a managers |
| tareas_mision | vista | — | `sql/017` — tarea actual de a una, ordenada por temperatura. Sin función propia: "crear siguiente paso" es crear una tarea, ya gateado por `tareas_lista`. Backfill: la recibió todo el que tenía `tareas_lista` |
| tareas_gestionar_ajenas | funcion | tareas_lista | completar/cerrar hilo/reasignar tarea **ajena** — acciones sobre lo propio no requieren función |
| tareas_asignar | funcion | tareas_lista | "Asignar usuarios" (`sql/014`) — poner a otro como asignado o responsable. Sin ella el `AsignadosPicker` muestra solo el resumen y "Reasignar" no aparece en el menú |
| tareas_proyectos_crear | funcion | tareas_proyectos | |
| tareas_proyectos_miembros | funcion | tareas_proyectos | "Asignar miembros" (`sql/013`) — alta/baja de miembros. Sin ella el bloque Miembros no se muestra en `ProyectoFormPanel` y la membresía viaja como default oculto |
| tareas_plantillas_sistema | funcion | tareas_plantillas | "Plantillas de sistema" (`sql/053`) — crear, modificar y desactivar plantillas de sistema. Backfill: todo el que tenía la vista `tareas_plantillas`, que hasta ahí administraba todas |

`usuarios_select` extendida con `OR tiene_permiso('tareas_lista') OR tiene_permiso('tareas_proyectos')` — picker de asignados/miembros necesita listar usuarios activos.
