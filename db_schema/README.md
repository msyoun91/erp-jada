# DB SCHEMA — ERP JADA (erp-new)

Fuente de verdad del esquema de base de datos, partida por módulo. **Leer solo el archivo del
módulo que se toca**, más `core.md` si la tarea toca usuarios o permisos. Ante cualquier cambio de
tablas, columnas o enums, actualizar ese archivo y `database.types.ts`.

| Archivo | Contenido |
|---|---|
| `core.md` | `usuarios`, `submodulos`, `usuario_submodulos`, `entes`, `usuario_tutorial`, `usuario_widgets`, `tiene_permiso()` |
| `tareas.md` | proyectos, miembros, hilos, tareas, asignados, notas, plantillas, eventos · helpers de visibilidad · triggers de pasos y membresía · funciones RPC multi-tabla (`sql/023`–`025`) · submódulos |
| `obras.md` | modelo de visibilidad · obras, empresas, personas, vínculos, referentes, transferencias, compartidos · duplicados, buscador, auditoría, códigos `OB`, aprobaciones · submódulos |
| `notificaciones.md` | `usuario_notificaciones`, `notificar()`, sus triggers (también el de plantillas de `sql/055`) y las funciones de lectura |

Proyecto Supabase: `qbpudocgdvpeadcyyhfh`. Regenerar tipos tras cada migración:
`npx supabase gen types typescript --project-id qbpudocgdvpeadcyyhfh --schema public > erp-app/src/lib/supabase/database.types.ts`
(requiere `supabase login` o `SUPABASE_ACCESS_TOKEN`)

**Antes de regenerar el archivo entero:** la parte de tareas de `sql/053` se sincronizó a mano, así
que regenerar hoy también trae las funciones de obras de `sql/051`–`052` (sin tipar todavía) y pisa
los `| null` puestos a mano en `obras_compartidos_por_mi`. Los argumentos nulables de RPC no se
corrigen en el archivo sino con `argsRpc()` (`lib/supabase/rpc.ts`, ver `decisiones/global/infra.md`).

**Las policies escriben `(select auth.uid())`, estos documentos escriben `auth.uid()`.** Desde `sql/035` las 35 policies que lo usaban envuelven la llamada en un subselect: sin eso Postgres la trata como VOLATILE y la re-evalúa una vez por fila. Es una diferencia de plan, no de lógica, así que se sigue citando la forma corta — más legible y equivalente. Al escribir una policy nueva, usar la envuelta.
