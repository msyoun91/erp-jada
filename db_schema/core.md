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

## entes (`sql/055`, `sql/059`)

Catálogo de registros de otros módulos que se relacionan con tareas; los que tienen estado, además, disparan plantillas. Infra cross-módulo como `submodulos`: cada módulo agrega su fila en su migración, más un trigger de una línea sobre su columna de estado — `disparar_plantillas('<ente>', '<columna>')`, ver `tareas.md`. Desde la app no se escribe.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| codigo | text | UNIQUE simple, no parcial: es destino de FK (`tareas_plantillas.disparo_ente`, `tareas_vinculos.ente`) y un ente no se reutiliza para otra cosa |
| modulo | text | `origen_app` de las tareas que genera |
| submodulo | text | el que pide: sin él, la plantilla no se ve ni se arma. Texto y no FK — `submodulos.codigo` es único parcial |
| estados | regtype, nullable | el enum de la columna de estado; `guardar_plantilla` valida contra él (`TA012`). NULL (`sql/059`) = se vincula pero no dispara |
| datos | text[] | columnas que la plantilla puede citar como `{columna}`. Nunca contacto: el texto se copia en la tarea y lo lee quien la recibe, vea o no el registro |
| ruta | text | `origen_punto` de las tareas, con `{id}`. CHECK `^/[^/]` — ruta interna, el mismo corte que `origen_punto` |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

Filas: `obra` — módulo `obras`, submódulo `obras_ver`, `estado_obra`, datos `{nombre}`, ruta `/obras/{id}`. `empresa` — `obras_empresas`, sin estado, ruta `/obras/empresas/{id}`; `persona` — `obras_personas`, sin estado, ruta `/obras/personas/{id}` (las dos, `sql/059`).

**RLS:** SELECT `activo AND tiene_permiso(submodulo)` — lo que no podés usar no existe para vos, y las policies de `tareas_plantillas` se apoyan en eso. Sin escritura para `authenticated`.

Cómo se nombra cada ente y sus estados vive en `lib/entes.ts` (`ENTES`): la base no sabe cómo se dicen. Solo uno con `estados` se ofrece como disparador en el editor.

**`etiqueta_registro(ente, id)` (`sql/059`)** — `SECURITY INVOKER STABLE`, EXECUTE para `authenticated`: el nombre de un registro para quien pregunta, NULL si no lo ve. Es también la regla de "lo ve": la RLS de `entes` pide el submódulo y la del módulo dueño decide la fila. Un `CASE` por `entes.modulo` (hoy `obras` → `obras_etiqueta`); un módulo que registre entes suma su rama.

**`relacionados_de_registro(ente, id)` (`sql/060`)** — `SECURITY INVOKER STABLE`: `(ente, registro_id, rol)` de lo relacionado con un registro, para quien pregunta. Hoy solo `obra` → `obras_relacionados_obra`. Lo usan los roles de las plantillas de tareas.

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
