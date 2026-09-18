# obsoletos

Archivos retirados del proyecto. **No leer salvo que haya que restaurar algo.**

Nada acá es fuente de verdad ni entra en el contexto de una tarea normal. Si un archivo de
`decisiones/` o `BACKLOG.md` apunta a uno de estos, el puntero es histórico: la decisión ya está
escrita en el archivo que apunta, no acá.

| Archivo | Qué era | Por qué salió | Cómo restaurar |
|---|---|---|---|
| `AUDITORIA_OBRAS_UI.md` | Relevamiento visual del módulo obras, 2026-09-08 | Cerrada: 28 arreglos implementados, B3 falso positivo. Los hallazgos quedaron en `decisiones/obras/` | `git mv obsoletos/AUDITORIA_OBRAS_UI.md .` |
| `PLAN_ARQUITECTURA_TAREAS.md` | Auditoría de arquitectura del módulo tareas | Cerrada: 7 puntos hechos, 1 descartado. Lo único vivo está en `BACKLOG.md` | `git mv obsoletos/PLAN_ARQUITECTURA_TAREAS.md .` |
| `PLAN_AUDITORIA_TAREAS.md` | Plan de cierre de la auditoría del módulo tareas, 2026-09-17 | Cerrado: las 6 fases hechas (`sql/076`–`081`), 21 y 23 descartados con motivo. Las decisiones quedaron en `decisiones/tareas/` | `git mv obsoletos/PLAN_AUDITORIA_TAREAS.md .` |
| `erp-app-README.md`, `erp-cliente-README.md` | Boilerplate de `create-next-app`, idénticos entre sí | Cero contenido del proyecto | `git mv obsoletos/erp-app-README.md erp-app/README.md` |
| `sync-contracts/` | Workspace `@erp/sync-contracts`, schemas compartidos | `src/index.ts` era `export {}`. Cero imports en ambas apps | Mover a `packages/sync-contracts`, reponer la entrada en `workspaces` de `package.json` raíz, `npm install` |
| `fonts-barlow-jakarta/` | Los 8 `.woff2` de Barlow Semi Condensed + Plus Jakarta Sans | La empresa cambió la tipografía del sitio: el sistema pasó a DM Sans — ver `decisiones/global/ui.md` | `git mv obsoletos/fonts-barlow-jakarta/*.woff2 erp-app/public/fonts/` y revertir el `@font-face` de `globals.css` |
| `prototipo-obras-tareas.html` | Prototipo estático de obras/tareas | Lo aprovechable ya se portó a componentes — ver `decisiones/obras/` | `git mv obsoletos/prototipo-obras-tareas.html decisiones/prototipos/` |
| `backup-docs-2026-09-11/` | Copia de CLAUDE.md, BACKLOG, `db_schema.md`, `decisiones/`, las guías y los archivos con punteros, antes de partir la documentación por tema | Backup pedido por el usuario; la reorganización está en `decisiones/global/infra.md` → *La documentación se lee por tema* | Copiar de vuelta cada archivo a su ruta y borrar las carpetas `decisiones/tareas/`, `decisiones/obras/`, `decisiones/global/` y `db_schema/` |
| `Pruebas de cambio en vinculos - Fase A.md`, `Pruebas de cambio en vinculos - Fase B.md` | Checklists de prueba manual de las fases A y B de `PLAN_TAREAS_VINCULOS.md` | Las dos fases están cerradas — decisión final en `decisiones/tareas/integracion.md` | `git mv "obsoletos/Pruebas de cambio en vinculos - Fase A.md" .` (ídem Fase B) |
| `Pruebas de cambio en plantillas.md` | Checklist de prueba manual de plantillas, roles y link heredado (`sql/055`–`058`) | Las features que prueba están cerradas y documentadas en `decisiones/tareas/plantillas.md` e `integracion.md` | `git mv "obsoletos/Pruebas de cambio en plantillas.md" .` |
| `sql-tests-share-directo/` | Los tests `obras_047`, `049`, `052`, `082` y `085` | Probaban el share directo de persona y empresa (`origen_obra_id`, `obras_compartir_persona`/`_empresa`), que `sql/086` dropeó: morían con `42P01`/`42883`. Lo que seguía valiendo se portó a `sql/tests/obras_compartir.sql` | `git mv obsoletos/sql-tests-share-directo/*.sql sql/tests/` |

Cuando `sync-contracts` haga falta de verdad — sincronización real entre `erp-app` y `erp-cliente`,
ver `GUIDE_SYNC.md` — se restaura desde acá en vez de crearlo de cero.
