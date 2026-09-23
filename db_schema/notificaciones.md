# Notificaciones (`sql/107_notificaciones_infra.sql`, `sql/108_notificaciones_usuarios.sql` — corridas en Supabase vía MCP)

Infra cross-módulo como `usuario_widgets` y `usuario_tutorial`: prefijo `usuario_`, RLS directo por `auth.uid()`, **sin submódulo y sin vista propia**. Decisión: `decisiones/global/infra.md` → *Notificaciones*.

**Eventos (`sql/108`), todos de `usuarios`:**

| tipo | destinatario | entidad | lo dispara | `etiqueta` · `destino` |
|---|---|---|---|---|
| `miembro_nuevo` | el delegador del equipo | `equipos_miembros` | INSERT de membresía (`equipos_miembros_notificar`). Actor NULL: el admin escribe con `service_role` | nombre del miembro · `mi_equipo` |
| `permiso_otorgado` | quien recibe | `usuario_submodulos` | alta o reactivación de una **vista** (`usuario_submodulos_notificar`). Actor = `otorgada_por` | nombre de la vista · `modulo` (la UI antepone `LABEL_MAP`) |
| `delegador_designado` | quien recibe | `usuario_submodulos` | alta o reactivación de `usuarios_delegar` — designación o herencia. `usuarios_equipo` que llega con la delegación no avisa aparte | nombre del equipo · `mi_equipo` |

Las dos ramas piden la fila apuntada **activa**: miembro que se fue o permiso revocado → el aviso desaparece. Reactivar un permiso retira los avisos anteriores de esa misma fila (`activo = false`) antes de crear el nuevo. La versión con eventos de tareas y obras (`sql/038`…`sql/099`) vive en `master`.

## Sumar un evento

1. `ALTER TYPE tipo_notificacion ADD VALUE '<tipo>'`, en su propia transacción: el valor no se puede usar antes del commit y `notificaciones_listar` lo castea al crearse.
2. CHECK de `entidad` con el vocabulario de las tablas apuntadas (se reemplaza entero cada vez que se suma una).
3. Trigger sobre la escritura que ya ocurre, que llama `notificar(...)`.
4. Rama en `resuelta` de `notificaciones_listar`: INNER JOIN contra la tabla apuntada, así la RLS del lector decide.
5. `TipoNotificacion` en `modules/notificaciones/types.ts` vuelve a `Database["public"]["Enums"]["tipo_notificacion"]`, y `ICONO`/`TEXTO`/`COLOR`/`RUTA` de `NotificacionesBell` suman su entrada.

## usuario_notificaciones

**La notificación apunta, no copia.** Guarda a qué fila se refiere y el texto se arma al leer, con la RLS del que lee.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| usuario_id | uuid FK → usuarios | destinatario |
| tipo | enum `tipo_notificacion` | `miembro_nuevo` \| `permiso_otorgado` \| `delegador_designado` |
| entidad | text | discriminador de a qué tabla apunta `entidad_id`. CHECK `usuario_notificaciones_entidad_check`: `equipos_miembros`, `usuario_submodulos` |
| entidad_id | uuid | sin FK — apunta a varias tablas |
| actor_id | uuid FK → usuarios, nullable | quién lo provocó. Null = evento del sistema |
| leida_at | timestamptz, nullable | |
| activo | boolean | descartar sin borrar |
| created_at / updated_at | timestamptz | |

**RLS:** SELECT y UPDATE con `usuario_id = auth.uid()`. **Sin policy ni GRANT de INSERT** — la escribe solo `notificar()`: una notificación insertable por el cliente sería un canal para escribirle a otro usuario. `GRANT SELECT` + `GRANT UPDATE (leida_at, activo)` — GRANT por columna porque RLS no acota columnas.

## Función `notificar(usuario, tipo, entidad, entidad_id, actor)`

`SECURITY DEFINER`, sin EXECUTE para `anon` ni `authenticated`: se llama desde triggers. Único lugar donde nace una notificación, y donde vive "no te notifiques a vos mismo". `IS DISTINCT FROM` y no `<>`: con `auth.uid()` NULL (service_role, SQL editor) la comparación daría NULL y el aviso se perdería en silencio.

## Función `notificaciones_listar(p_limite int DEFAULT 30)`

`SECURITY INVOKER`, EXECUTE para `authenticated`. Devuelve `id, tipo, etiqueta, motivo, actor, destino, destino_id, leida, created_at`. Cada entidad suma una rama al CTE `resuelta` con INNER JOIN contra su tabla: una notificación cuya entidad dejó de ser visible desaparece de la lista sin una segunda copia de la regla de visibilidad.

`actor` sale de `notificaciones_actores()`, no de `usuarios`: la RLS de `usuarios` no deja que un miembro vea al delegador ni al admin.

## Función `notificaciones_actores()`

`SECURITY DEFINER`, EXECUTE para `authenticated`. Devuelve `id, nombre` de los actores de las notificaciones activas de `auth.uid()` — solo el nombre, nunca email ni teléfono. La usa `notificaciones_listar`.

El badge cuenta las no leídas **de esta lista**, no de la tabla.
