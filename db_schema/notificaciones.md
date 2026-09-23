# Notificaciones (`sql/107_notificaciones_infra.sql` — corrida en Supabase vía MCP)

Infra cross-módulo como `usuario_widgets` y `usuario_tutorial`: prefijo `usuario_`, RLS directo por `auth.uid()`, **sin submódulo y sin vista propia**. Decisión: `decisiones/global/infra.md` → *Notificaciones*.

**Hoy no hay ningún evento.** El enum no tiene valores, `entidad` no tiene CHECK y `notificaciones_listar` no tiene ramas: nada puede insertarse y la bandeja sale vacía. La versión con eventos de tareas y obras (`sql/038`…`sql/099`) vive en `master`; `sql/101` la borró.

## Sumar un evento

1. `ALTER TYPE tipo_notificacion ADD VALUE '<tipo>'`.
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
| tipo | enum `tipo_notificacion` | sin valores todavía |
| entidad | text | discriminador de a qué tabla apunta `entidad_id`. Sin CHECK hasta el primer evento (un `IN ()` vacío no es SQL válido) |
| entidad_id | uuid | sin FK — apunta a varias tablas |
| actor_id | uuid FK → usuarios, nullable | quién lo provocó. Null = evento del sistema |
| leida_at | timestamptz, nullable | |
| activo | boolean | descartar sin borrar |
| created_at / updated_at | timestamptz | |

**RLS:** SELECT y UPDATE con `usuario_id = auth.uid()`. **Sin policy ni GRANT de INSERT** — la escribe solo `notificar()`: una notificación insertable por el cliente sería un canal para escribirle a otro usuario. `GRANT SELECT` + `GRANT UPDATE (leida_at, activo)` — GRANT por columna porque RLS no acota columnas.

## Función `notificar(usuario, tipo, entidad, entidad_id, actor)`

`SECURITY DEFINER`, sin EXECUTE para `anon` ni `authenticated`: se llama desde triggers. Único lugar donde nace una notificación, y donde vive "no te notifiques a vos mismo". `IS DISTINCT FROM` y no `<>`: con `auth.uid()` NULL (service_role, SQL editor) la comparación daría NULL y el aviso se perdería en silencio.

## Función `notificaciones_listar(p_limite int DEFAULT 30)`

`SECURITY INVOKER`, EXECUTE para `authenticated`. Devuelve `id, tipo, etiqueta, motivo, actor, destino, destino_id, leida, created_at`. Cada evento suma una rama al CTE `resuelta` con INNER JOIN contra su tabla: una notificación cuya entidad dejó de ser visible desaparece de la lista sin una segunda copia de la regla de visibilidad. Sin ramas, `resuelta` es una fila `WHERE false` que solo fija las columnas.

El badge cuenta las no leídas **de esta lista**, no de la tabla.
