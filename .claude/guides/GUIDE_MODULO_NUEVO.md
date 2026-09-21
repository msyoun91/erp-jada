# GUIDE_MODULO_NUEVO — Orden de construcción

Siempre este orden, sin saltar pasos. Cada paso carga su guía; no cargarlas todas de entrada.

0. **Listar la ficha del módulo y las vistas y funciones por vista, y confirmarlas con el usuario antes de escribir código.** La ficha —objetivo, personas, entes, estados, relaciones, acciones, eventos que emite y consume— sigue el formato de `GUIDE_ENTES.md` §1. Empieza preguntando dos cosas: *¿para qué existe este módulo y qué problema resuelve?* y *¿quién va a usar este módulo y qué hace cada uno con él, incluidos los que solo miran?* De las personas salen las vistas y funciones (`GUIDE_ENTES.md` §1.1), no al revés. Las vistas, cada una con las personas a las que sirve:
   ```
   Módulo: Nombre
   ├── modulo_vista1 (vista)          — personaA, personaB
   │   ├── modulo_accion1 (funcion)   — personaA
   │   └── modulo_accion2 (funcion)   — personaA, personaB
   └── modulo_vista2 (vista, sin funciones) — personaB
   ```
   Toda vista arranca con mayúscula. Todo módulo tiene al menos 1 vista. Una vista puede no tener funciones. Vista o función sin persona no se construye. Un módulo puede no tener entes; la ficha lo declara. No avanzar a SQL sin la ficha y la lista aprobadas.
1. SQL y tipos de base de datos (`GUIDE_DB.md`), con el contrato de cada ente (`GUIDE_ENTES.md` §2)
2. `types.ts` — schema Zod + tipos TypeScript (`GUIDE_TYPESCRIPT.md`)
3. `permissions.ts` — verificación de acceso (`GUIDE_PERMISSIONS.md`)
4. `queries.ts` + `actions.ts`
5. Widget del dashboard, si aplica (`GUIDE_DASHBOARD.md`)
6. Componentes de UI y `layout.tsx` con el encabezado de módulo (`GUIDE_DESIGN.md`)
7. Integración y prueba completa por usuario

## Checklist

- [ ] Ficha del módulo (objetivo, personas, entes, estados, relaciones, acciones, eventos) y vistas y funciones por vista, cada una con sus personas, aprobadas
- [ ] Ficha pegada en `decisiones/<modulo>.md` bajo `## Ficha del módulo` — sin eso no se puede contrastar después (`GUIDE_ENTES.md` §1.2)
- [ ] Checklist por ente de `GUIDE_ENTES.md` cumplido, incluida la rama en las siete funciones de core
- [ ] SQL creado, con RLS, `GRANT` a `authenticated` y trigger `updated_at`
- [ ] Submódulos sembrados en la migración
- [ ] `types.ts`, `permissions.ts`, `queries.ts`, `actions.ts`
- [ ] `layout.tsx` (breadcrumb + `<h1>` + tabs) y entrada en `SidebarNav.tsx` (`NAV_ITEMS`, `ICON_MAP`, `LABEL_MAP`)
- [ ] UI creada
- [ ] Dashboard integrado, si aplica
- [ ] `db_schema/<modulo>.md` creado y fila en `db_schema/README.md`
- [ ] `decisiones/<modulo>.md` creado (pasa a carpeta `decisiones/<modulo>/` con `README.md` índice cuando crezca)
