# Decisiones — transversales

Lo que no es de un módulo. Las reglas para escribir código nuevo viven en `.claude/guides/`; acá
está **por qué** se decidió cada una. Leer solo el archivo que toca la tarea.

> **Esta rama no tiene `tareas` ni `obras`** (`sql/101`, `sql/102`): salieron para rediseñar el
> sistema de permisos desde cero. Los archivos de abajo siguen citándolos —`decisiones/obras/…`,
> `db_schema/tareas.md`, `entes`, el bus de eventos, compartir al asignar— y esas decisiones
> **son reales**: se tomaron, se implementaron y se pagaron. Lo que ya no existe es el código.
>
> Se dejan tal cual a propósito. Son el material de entrada del rediseño, no ruido: cada una dice
> contra qué problema se decidió. Los archivos que nombran viven en `master`.

---

## `ui.md`

Tocar `components/ui/` o `globals.css`: design system, componentes compartidos, tokens y clases, auditorías de UI app-wide, tipografía.

- Design system
- Componentes compartidos (`components/ui/`) — `RightPanel` y `Modal` viven en el top layer · `ConfirmModal` · `OverflowMenu` · `ThemeToggle` · `SearchInput` · `FiltroDias`
- Tokens y clases de `globals.css`
- Auditorías de UI app-wide — P0 — errores, confirmaciones, foco, boundaries · P1 — responsive y legibilidad · P1 — acciones de fila siempre en `OverflowMenu` · P2 — búsqueda, paginación y contador de resultados
- DM Sans reemplaza a Barlow Semi Condensed + Plus Jakarta Sans
- `.input:disabled` — el campo deshabilitado tiene que verse deshabilitado

## `permisos.md`

Tocar permisos: función ligada a su vista (`vista_id`), vista y función se autorizan por separado, delegación a equipos.

- `funcion` ligada a su `vista` puntual (`vista_id`), no solo a `modulo`
- Vista y función se autorizan por separado (`PermisosModal`)
- Delegación con techo (en la base desde `sql/105`; falta la UI)

## `entes.md`

Tocar `entes`, `lib/entes.ts`, las funciones cross-módulo de core, disparadores, compartir al asignar, o crear un módulo: el modelo de entes y eventos, y Tareas leída con la guía.

- Un módulo se describe en entes, estados, propiedades, relaciones, acciones y eventos (2026-09-16)
- Los eventos van a una tabla `eventos`, no a un trigger por consumidor (`sql/068`)
- Un evento de relación lo ve quien ve el vínculo (`sql/069`)
- "No existe" antes que "sin permiso"
- Un ente en un texto es una referencia, no un nombre (decidido, no construido)
- Tareas leída con la guía (2026-09-16)

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
- La base es la fuente de verdad del esquema; `sql/` es un reflejo que puede atrasar (`sql/083`, `sql/084`)
