# obsoletos

Archivos retirados del proyecto. **No leer salvo que haya que restaurar algo.**

Nada acá es fuente de verdad ni entra en el contexto de una tarea normal. Si un archivo de
`decisiones/` o `BACKLOG.md` apunta a uno de estos, el puntero es histórico: la decisión ya está
escrita en el archivo que apunta, no acá.

| Archivo | Qué era | Por qué salió | Cómo restaurar |
|---|---|---|---|
| `AUDITORIA_OBRAS_UI.md` | Relevamiento visual del módulo obras, 2026-09-08 | Cerrada: 28 arreglos implementados, B3 falso positivo. Los hallazgos quedaron en `decisiones/obras.md` | `git mv obsoletos/AUDITORIA_OBRAS_UI.md .` |
| `PLAN_ARQUITECTURA_TAREAS.md` | Auditoría de arquitectura del módulo tareas | Cerrada: 7 puntos hechos, 1 descartado. Lo único vivo está en `BACKLOG.md` | `git mv obsoletos/PLAN_ARQUITECTURA_TAREAS.md .` |
| `erp-app-README.md`, `erp-cliente-README.md` | Boilerplate de `create-next-app`, idénticos entre sí | Cero contenido del proyecto | `git mv obsoletos/erp-app-README.md erp-app/README.md` |
| `sync-contracts/` | Workspace `@erp/sync-contracts`, schemas compartidos | `src/index.ts` era `export {}`. Cero imports en ambas apps | Mover a `packages/sync-contracts`, reponer la entrada en `workspaces` de `package.json` raíz, `npm install` |
| `prototipo-obras-tareas.html` | Prototipo estático de obras/tareas | Lo aprovechable ya se portó a componentes — ver `decisiones/obras.md` | `git mv obsoletos/prototipo-obras-tareas.html decisiones/prototipos/` |

Cuando `sync-contracts` haga falta de verdad — sincronización real entre `erp-app` y `erp-cliente`,
ver `GUIDE_SYNC.md` — se restaura desde acá en vez de crearlo de cero.
