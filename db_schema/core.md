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

Triggers (`sql/105`): `usuario_submodulos_validar` (constraint trigger diferido — función sin vista, admin fuera de equipos, un delegador por equipo, techo de las filas delegadas) y `usuario_submodulos_cascada` (al apagar una fila de un miembro, apaga lo que él delegó de eso; si es `usuarios_delegar`, todo — y sin heredero falla con US009 si queda otro miembro activo).

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

RLS de las dos (solo SELECT; escribe el admin con `service_role`): `usuarios_ver` y `usuarios_equipos` ven todo; `usuarios_equipo` ve su equipo vía `mi_equipo()` — `SECURITY DEFINER`, sin argumento para no exponer el equipo de otros. Desde `sql/105` es un envoltorio de `equipo_de(p_usuario)`, que no tiene GRANT.

Cambiar de equipo o quedar independiente: `asignar_equipo(p_admin, p_usuario, p_equipo)` (`sql/106`, solo `service_role`), las dos escrituras en una transacción.

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

`usuario_tiene_permiso(p_usuario uuid, p_codigo text)` —preguntar el permiso de **otro** usuario— volvió en `sql/105` para el techo y el guard de las funciones de admin. Sin GRANT a `authenticated`: la llaman triggers y funciones de `service_role`. `tiene_permiso(codigo)` pasó a ser `usuario_tiene_permiso(auth.uid(), codigo)`, como en `sql/062`: el predicado vive en un solo lugar.

Trigger `usuarios_validar_desactivar` (`sql/105`): desactivar a quien tiene `usuarios_delegar` falla con US009 — primero `quitar_delegador`.
