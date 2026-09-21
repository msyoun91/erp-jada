# DB — usuarios, permisos e infraestructura por usuario

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

**El cuerpo vigente es el de `sql/102`, no el de `sql/101`.** El rollback lo devolvió a la versión de `sql/001`, que es anterior a `sql/020` y no exige `usuarios.activo`: mientras estuvo así, un usuario desactivado conservaba sus permisos en RLS. Es el ejemplo a tener a mano cuando el sistema de permisos nuevo escriba su propio rollback — volver a "la versión anterior" no es volver a la primera.

`usuario_tiene_permiso(p_usuario uuid, p_codigo text)` (`sql/062`) —preguntar el permiso de **otro** usuario— se fue con la infra cross-módulo (`sql/101`). El sistema de permisos nuevo la va a necesitar de vuelta: decidir si vive en el mismo lugar o si el predicado por usuario es la forma base y `tiene_permiso()` el envoltorio. Ver `decisiones/global/permisos.md`.
