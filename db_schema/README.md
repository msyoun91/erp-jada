# DB SCHEMA — ERP JADA (erp-new)

Fuente de verdad del esquema de base de datos, partida por módulo. **Leer solo el archivo del
módulo que se toca**, más `core.md` si la tarea toca usuarios o permisos. Ante cualquier cambio de
tablas, columnas o enums, actualizar ese archivo y `database.types.ts`.

| Archivo | Contenido |
|---|---|
| `core.md` | `usuarios`, `submodulos`, `submodulo_reglas`, `usuario_submodulos`, `equipos`, `usuario_tutorial`, `usuario_widgets`, `tiene_permiso()`, `entes`, `eventos` |
| `notificaciones.md` | `usuario_notificaciones`, `notificar()`, `notificaciones_listar()` |
| `tareas.md` | hilos, pasos, notas, historial, permisos, visibilidad y reglas de escritura de tareas (`sql/112`, `sql/113`) |

Esta rama sacó `tareas` y `obras` para rediseñar permisos desde cero (`sql/101`, `sql/102`); sus
esquemas viejos viven en `master`. Tareas vuelve rediseñado desde `sql/112`.

Proyecto Supabase: `qbpudocgdvpeadcyyhfh`. Regenerar tipos tras cada migración:
`npx supabase gen types typescript --project-id qbpudocgdvpeadcyyhfh --schema public > erp-app/src/lib/supabase/database.types.ts`
(requiere `supabase login` o `SUPABASE_ACCESS_TOKEN`)

**Las policies escriben `(select auth.uid())`, estos documentos escriben `auth.uid()`.** Desde `sql/035` las policies que lo usaban envuelven la llamada en un subselect: sin eso Postgres la trata como VOLATILE y la re-evalúa una vez por fila. Es una diferencia de plan, no de lógica, así que se sigue citando la forma corta — más legible y equivalente. Al escribir una policy nueva, usar la envuelta.
