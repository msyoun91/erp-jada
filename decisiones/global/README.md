# Decisiones — transversales

Lo que no es de un módulo. Las reglas para escribir código nuevo viven en `.claude/guides/`; acá
está **por qué** se decidió cada una. Leer solo el archivo que toca la tarea.

---

## `ui.md`

Tocar `components/ui/` o `globals.css`: design system, componentes compartidos, tokens y clases, auditorías de UI app-wide, tipografía.

- Design system
- Componentes compartidos (`components/ui/`) — `RightPanel` y `Modal` viven en el top layer · `ConfirmModal` · `OverflowMenu` · `ThemeToggle` · `SearchInput` · `FiltroDias`
- Tokens y clases de `globals.css`
- Auditorías de UI app-wide — P0 — errores, confirmaciones, foco, boundaries · P1 — responsive y legibilidad · P1 — acciones de fila siempre en `OverflowMenu` · P2 — búsqueda, paginación y contador de resultados
- DM Sans reemplaza a Barlow Semi Condensed + Plus Jakarta Sans

## `permisos.md`

Tocar permisos: función ligada a su vista (`vista_id`), vista y función se autorizan por separado.

- `funcion` ligada a su `vista` puntual (`vista_id`), no solo a `modulo`
- Vista y función se autorizan por separado (`PermisosModal`)

## `infra.md`

Tocar infraestructura: proxy, dashboard, sidebar, notificaciones, regla de negocio en Postgres, `argsRpc()`, advisors, organización de la documentación.

- `middleware.ts` → `proxy.ts` (Next.js 16)
- Dashboard = ruta `/`, no `/dashboard`
- `usuario_widgets` — RLS directo, sin `service_role`
- `MobileNav` cierra el drawer durante el render, no en un efecto
- Sidebar: `Sidebar.tsx` (server) + `SidebarNav.tsx` (client) + `MobileNav.tsx` (client)
- Notificaciones: infra sin submódulo, y sin motor (`sql/038`)
- La regla de negocio vive en Postgres, no en `actions.ts`
- El módulo comercial se elimina entero (`sql/026`)
- `argsRpc()` — los tipos de argumentos de RPC dejaron de ser nulables
- ~~`erp-app/AGENTS.md` dice ser algo que no es~~ — superado el 2026-09-11
- `sql/035` — los advisors de Supabase, resueltos o descartados uno por uno
- La documentación se lee por tema, no por archivo (2026-09-11)
