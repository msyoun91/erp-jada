# DB SCHEMA — ERP JADA (erp-new)

Fuente de verdad del esquema de base de datos. Mantener sincronizado con `database.types.ts` y migraciones SQL ante cualquier cambio de tablas, columnas o enums.

Proyecto Supabase: `qbpudocgdvpeadcyyhfh`. Regenerar tipos tras cada migración:
`npx supabase gen types typescript --project-id qbpudocgdvpeadcyyhfh --schema public > erp-app/src/lib/supabase/database.types.ts`
(requiere `supabase login` o `SUPABASE_ACCESS_TOKEN`)

Estado actual: `sql/001_usuarios_permisos.sql` (sin correr todavía — avisar/ejecutar en Supabase SQL Editor). `database.types.ts` escrito a mano reflejando este SQL; regenerar con el comando de arriba en cuanto se corra la migración.

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

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| codigo | text | `{modulo}_{slug}`, unique parcial WHERE activo |
| modulo | text | agrupador funcional/nav |
| tipo | enum tipo_submodulo | `seccion` \| `funcion` |
| nombre | text | label visible |
| orden | int | orden en tabs/nav |
| activo | boolean | |

Seed inicial: `usuarios_ver` (seccion), `usuarios_gestionar` (funcion).

## usuario_submodulos

Asignación usuario ↔ submódulo.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | |
| submodulo_id | uuid FK → submodulos | |
| activo | boolean | UNIQUE normal (usuario_id, submodulo_id) — no parcial, por upsert (excepción GUIDE_DB) |

## Función `tiene_permiso(p_codigo text)`

SQL function, `SECURITY DEFINER`, usada en RLS de las 3 tablas y disponible como fuente de verdad de autorización en DB.

---
