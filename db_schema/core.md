# DB — usuarios, permisos e infraestructura por usuario

## usuarios

Perfil 1:1 con `auth.users` (mismo `id`). Se crea automáticamente via trigger `on_auth_user_created` al insertar en `auth.users`, y `email` se mantiene sincronizado con trigger `on_auth_user_email_updated` (`sql/021`) — la credencial es `auth.users.email` y esta tabla la espeja, nunca al revés. `nombre` no: vive solo acá (el `user_metadata.nombre` de auth lo lee `handle_new_user` al crear y después queda congelado).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | = auth.users.id |
| nombre | text | |
| email | text | unique parcial WHERE activo |
| telefono | text | nullable, solo dígitos — trigger `usuarios_telefono_normalizado` + CHECK 8–15 (`sql/103`) |
| activo | boolean | default true |
| created_at / updated_at | timestamptz | |

`activo = false` es la desactivación real, no una marca de UI: le saca los permisos vía `tiene_permiso` (`sql/020`) y el proxy le corta la sesión. `desactivarUsuario` además banea la cuenta en `auth.users` — el access token vivo entraría igual por la API. Se revierte con "Reactivar" (`activo = true` + `ban_duration: "none"`).

RLS: `usuarios_select` (fila propia, `usuarios_ver`, `usuarios_equipos` (`sql/106`), o `usuarios_equipo` sobre los miembros activos de su equipo — `sql/104`, que además sacó las ramas muertas de `tareas_*`/`obras_*`) y `usuarios_update_propio` (`sql/022`) — `id = auth.uid()` acotado por `GRANT UPDATE (nombre, telefono) TO authenticated` (`telefono` se sumó en `sql/103`), que es lo que impide reactivarse solo desde `/perfil`. El resto de las escrituras siguen pasando por `service_role`.

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
| delegable | boolean | default false — el delegador solo otorga lo marcado (`sql/104`). CHECK `submodulos_usuarios_no_delegable`: nunca en `modulo = 'usuarios'`. Pasarlo a false revoca lo delegado (`sql/105`) |
| activo | boolean | |

Seed: `usuarios_ver` (vista, nombre "Ver" — nunca repite el label del módulo), `usuarios_gestionar` (funcion → usuarios_ver), `usuarios_equipo` (vista "Mi equipo", orden 3) y `usuarios_delegar` (funcion → usuarios_equipo) (`sql/104`), `usuarios_equipos` (vista "Equipos", orden 2 — la pestaña del admin; `sql/106` se la dio a quien tenía `usuarios_gestionar`).

RLS: `submodulos_select` — `usuarios_gestionar`, `usuarios_equipos`, `usuarios_equipo` (el delegador nombra los permisos de su equipo), o los propios asignados.

## submodulo_reglas

Reglas entre permisos que no salen de vista → función (`sql/110`). Las lee el panel de permisos y las
hace valer `usuario_submodulos_validar`. Decisión: `decisiones/global/permisos.md` → *Reglas entre permisos*.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| submodulo_id | uuid FK → submodulos | |
| otro_id | uuid FK → submodulos | CHECK distinto de `submodulo_id` |
| tipo | enum tipo_regla_submodulo | `requiere` (`submodulo_id` necesita `otro_id`, en un sentido) \| `excluye` (una fila por par, vale en los dos sentidos) |
| activo | boolean | unique parcial (submodulo_id, otro_id) WHERE activo |

Una regla con un submódulo inactivo no pesa. Seed: `usuarios_equipos` excluye `usuarios_equipo`.

RLS: `submodulo_reglas_select` con `usuarios_ver`. Sin escrituras: se cargan por migración.

## usuario_submodulos

Asignación usuario ↔ submódulo.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | |
| submodulo_id | uuid FK → submodulos | |
| otorgada_por | uuid FK → usuarios, nullable | quién otorgó la fila vigente; NULL = admin, previo a `sql/104` |
| activo | boolean | UNIQUE normal (usuario_id, submodulo_id) — no parcial, por upsert (excepción GUIDE_DB) |
| created_at / updated_at | timestamptz | |

RLS: `usuario_submodulos_select` — las propias, `usuarios_gestionar`, `usuarios_equipos` sobre los miembros activos de cualquier equipo (`sql/106`), o `usuarios_equipo` sobre los de su equipo. `usuario_submodulos_insert_delegador` / `_update_delegador` (`sql/105`): con `usuarios_delegar`, sobre su equipo, siempre a su nombre (`otorgada_por = auth.uid()`); una fila activa solo si es suya. `GRANT INSERT (usuario_id, submodulo_id, otorgada_por, activo)` y `UPDATE (activo, otorgada_por)` a `authenticated`.

Triggers (`sql/105`): `usuario_submodulos_validar` (constraint trigger diferido — función sin vista, `submodulo_reglas` desde `sql/110` (US016 requiere, US017 excluye), admin fuera de equipos, un delegador por equipo, techo de las filas delegadas) y `usuario_submodulos_cascada` (al apagar una fila de un miembro, apaga lo que él delegó de eso; si es `usuarios_delegar`, todo — y sin heredero falla con US009 si queda otro miembro activo). `usuario_submodulos_notificar_alta` / `_reactiva` (`sql/108`): avisan al que recibe una vista o `usuarios_delegar` — ver `notificaciones.md`.

Funciones: `asignar_submodulos(p_admin, p_usuario, p_submodulos[])`, `quitar_delegador(p_admin, p_saliente, p_heredero, p_no_copiar[])` y, desde `sql/106`, `designar_delegador(p_admin, p_usuario)` y `fijar_delegables(p_admin, p_submodulos[])`, solo `service_role`; `delegar_submodulos(p_usuario, p_submodulos[])` INVOKER para `authenticated`. Una fila es delegada si `otorgada_por` es miembro de un equipo (`equipo_de()`).

## equipos

Los crea el admin (`sql/104`). La membresía no da permisos: define a quién puede delegar el delegador. Decisión: `decisiones/usuarios.md` → *Equipos y delegación de permisos*.

No se desactiva con miembros activos (`equipos_validar_desactivar`, US010).

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text | no vacío, unique parcial WHERE activo |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

## equipos_miembros

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| equipo_id | uuid FK → equipos | |
| usuario_id | uuid FK → usuarios | unique parcial WHERE activo: un solo equipo vigente |
| activo | boolean | cambiar de equipo = desactivar la fila e insertar otra |
| created_at / updated_at | timestamptz | |

RLS de las dos (solo SELECT; escribe el admin con `service_role`): `usuarios_ver` y `usuarios_equipos` ven todo; `usuarios_equipo` ve su equipo vía `mi_equipo()` — `SECURITY DEFINER`, sin argumento para no exponer el equipo de otros. Desde `sql/105` es un envoltorio de `equipo_de(p_usuario)`, sin GRANT a `authenticated`. Grants de `service_role` (`sql/111`): SELECT/INSERT/UPDATE en las dos tablas y EXECUTE en `equipo_de` — las funciones de admin son INVOKER y corren con ese rol.

Cambiar de equipo o quedar independiente: `asignar_equipo(p_admin, p_usuario, p_equipo)` (`sql/106`, solo `service_role`), las dos escrituras en una transacción. Trigger `equipos_miembros_notificar` (`sql/108`): la membresía nueva le avisa al delegador del equipo.

Trigger `equipos_miembros_validar` (`sql/105`): `equipo_id`/`usuario_id` inmutables (US015); no entra quien tiene `usuarios_gestionar` (US002) ni a un equipo inactivo (US011); el delegador no sale (US009); al salir, se apaga lo que le dieron por delegación.

## usuario_tutorial

Qué pasos del tutorial guiado ya vio cada usuario (`sql/019`). Infra cross-módulo como `usuario_widgets`: el namespace vive en el código del paso, no en el nombre de la tabla.

Hoy está vacía: los únicos pasos que existían eran de tareas y se fueron con el módulo (`sql/101`). La tabla se queda porque su esquema no sabe nada de tareas — `usuario_id` y `paso text`.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | |
| paso | text | el código del paso lo define el módulo que monta el tutorial |
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

**El predicado vigente es el de `sql/102`, no el de `sql/101`** (desde `sql/105` vive en `usuario_tiene_permiso`). El rollback lo devolvió a la versión de `sql/001`, que es anterior a `sql/020` y no exige `usuarios.activo`: mientras estuvo así, un usuario desactivado conservaba sus permisos en RLS. Es el ejemplo a tener a mano cuando el sistema de permisos nuevo escriba su propio rollback — volver a "la versión anterior" no es volver a la primera.

`usuario_tiene_permiso(p_usuario uuid, p_codigo text)` —preguntar el permiso de **otro** usuario— volvió en `sql/105` para el techo y el guard de las funciones de admin. Sin GRANT a `authenticated`: la llaman triggers y funciones de `service_role`, que como son INVOKER necesitan su EXECUTE (`sql/111`, junto con `UPDATE (delegable)` en `submodulos` para `fijar_delegables`). `tiene_permiso(codigo)` pasó a ser `usuario_tiene_permiso(auth.uid(), codigo)`, como en `sql/062`: el predicado vive en un solo lugar.

Trigger `usuarios_validar_desactivar` (`sql/105`): desactivar a quien tiene `usuarios_delegar` falla con US009 — primero `quitar_delegador`.

## entes (`sql/109`)

Catálogo cross-módulo: cada módulo registra acá sus entes en su propia migración (`GUIDE_ENTES.md` §2.2). Hoy vacía — el primero lo suma Tareas.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| codigo | text | UNIQUE simple, no parcial: destino de FK (`eventos.ente`), y un código no se reutiliza |
| modulo | text | la rama que toman las genéricas (`CASE e.modulo`) |
| submodulo | text | la vista que abre la ficha. Texto y no FK: `submodulos.codigo` es único parcial |
| estados | regtype, nullable | el enum de la columna `estado`; NULL si el ente no tiene estado |
| datos | text[] | default `{}` — columnas citables como `{columna}` desde otro módulo. Nunca contacto |
| ruta | text | la ficha, con `{id}`. CHECK: empieza con una sola `/` y contiene `{id}` |
| tabla | regclass | de dónde lee un consumidor la fila |
| disparos | tipo_evento[] | default `{}` — qué eventos pueden disparar una plantilla |
| activo | boolean | |
| created_at / updated_at | timestamptz | trigger `set_updated_at` |

RLS `entes_select`: `activo AND tiene_permiso(submodulo)` — sin la vista del ente, el ente no existe. Solo `GRANT SELECT`: escribe la migración de cada módulo.

## eventos (`sql/109`)

Log append-only y punto de escucha de los consumidores (`GUIDE_ENTES.md` §2.8). Sin `activo` ni `updated_at`: una auditoría no oculta ni reescribe sus filas.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| ente | text FK → entes(codigo) | |
| registro_id | uuid | sin FK — apunta a `entes.tabla` |
| evento | enum `tipo_evento` (`alta`\|`baja`\|`reactivacion`\|`estado`\|`relacion_alta`\|`relacion_baja`) | `transferencia`, `compartido` y `revocado` entran con su primer emisor |
| detalle | jsonb | default `{}` — `estado`: `{estado, anterior}`; `relacion_*`: `{ente, registro_id, rol}` |
| actor_id | uuid FK → usuarios, nullable | `auth.uid()` de quien actuó; NULL desde `service_role` |
| created_at | timestamptz | default `clock_timestamp()`: una sentencia emite varios y el orden queda |

Índices `idx_eventos_registro (ente, registro_id, created_at)` e `idx_eventos_actor (actor_id)`.

RLS `eventos_select`: `etiqueta_registro(ente, registro_id) IS NOT NULL`, y para `relacion_*` además `puede_ver_relacion(...)` — lo que no ves, no pasó. `eventos_insert`: `pg_trigger_depth() > 0`, solo desde un trigger. `GRANT SELECT, INSERT`; sin UPDATE.

**Emisores** (INVOKER, para que un consumidor corra con la RLS de quien actuó):

- `emitir_evento(ente, registro_id, evento, detalle)` — el INSERT. EXECUTE para `authenticated`; por RPC no inserta (la policy pide trigger).
- `emitir_eventos_registro()` — trigger `AFTER INSERT OR UPDATE OF activo, estado`, `TG_ARGV = (ente)`: alta (solo si nace activo), reactivación, estado (si cambia de verdad o nace con valor), baja, en ese orden.
- `emitir_eventos_relacion()` — trigger sobre la puente, `AFTER INSERT OR UPDATE OF activo, roles`, `TG_ARGV = (ente, columna, ente relacionado, columna)`: un evento por rol que aparece o se va, del lado del primer ente.

**Genéricas cross-módulo, sin ramas** (INVOKER, EXECUTE para `authenticated` porque las llama la policy): `etiqueta_registro(ente, id)` devuelve NULL y `puede_ver_relacion(ente, id, ente_rel, id_rel)` false. Cada ente reemplaza el cuerpo sumando su `CASE e.modulo WHEN …`. `puede_abrir_registro`, `buscar_registros`, `relacionados_de_registro`, `puede_compartir_registro` y `compartir_registros` no existen todavía en esta rama.

Test: `sql/tests/entes_eventos.sql` (arma un ente de prueba con su puente y sus ramas, todo en `ROLLBACK`).
