# DECISIONES DE ARQUITECTURA — ERP JADA (erp-new)

Registro de decisiones no obvias tomadas durante el desarrollo. Leer antes de modificar cualquier módulo existente.

---

## Design system — JADA

Spec completa extraída y volcada en `.claude/guides/design-system/JADA-design-system.md`. El sistema fuente es un dashboard desktop; para el ERP (mobile-first, uso en obra) hubo que extrapolar piezas que no existen en el original, siguiendo su misma lógica visual:

- **Breakpoints**: no definidos en el fuente. Se usan defaults de Tailwind (sm 640/md 768/lg 1024/xl 1280).
- **Tabs (ModuleTabs)**: no existe componente fuente. Replica patrón de nav-item (underline horizontal o pill).
- **Paginación**: no existe. Replica jx-icon-btn + números con mismo patrón de estado activo que sidebar/tabs.
- **List-item mobile** (reemplazo de tablas en mobile, regla ya existente): no existe. Deriva de los tokens de fila de tabla del sistema (jd-table row).
- **Touch targets 44px**: el fuente es desktop (~34px). Se fuerza min-height 44px solo en mobile (`@media max-width:767px`), sin cambiar el look visual.
- **Toast (Sonner)**: no hay skin custom en el fuente. Deriva de Alert (mismos tokens semánticos).
- **Dark mode**: sí es first-class en el sistema fuente, activado con `<html data-theme="dark">` (no clase `.dark`). Pensado como modo alto-contraste/exterior, no solo nocturno — relevante para uso en obra con sol.

**Por qué:** el JADA Design System fue creado para un dashboard de escritorio; el ERP necesita mobile-first en obra, así que hay piezas sin precedente en el spec. Se prioriza mantener coherencia visual con lo que sí existe antes que inventar un patrón nuevo.

---

## `middleware.ts` → `proxy.ts` (Next.js 16)

Next 16 deprecó la convención `middleware.ts` en la raíz (`src/`) — se renombró a `proxy.ts` con función exportada `proxy` (no `middleware`). El archivo `src/lib/supabase/middleware.ts` (helper `updateSession`, nombre fijado por `GUIDE_DB.md`) no cambia — solo el entry point de Next en `src/proxy.ts` lo importa y expone.

**Por qué:** `erp-app/AGENTS.md` (autogenerado por `next dev`) advierte que esta versión de Next tiene breaking changes vs. el training data. Toda lógica de proxy/middleware futura va en `src/proxy.ts`, no crear `src/middleware.ts`.

---

## Funciones `SECURITY DEFINER` — siempre `SET search_path = public`

`supabase_auth_admin` (el rol que ejecuta el trigger `on_auth_user_created` al crear un usuario) no tiene `public` en su `search_path` por defecto. Una función `SECURITY DEFINER` que referencia tablas sin schema (ej: `INSERT INTO usuarios ...`) falla con `relation "usuarios" does not exist` aunque la tabla exista — el error no menciona permisos ni search_path, así que es fácil perder tiempo pensando que la tabla no se creó.

**Regla:** toda función `SECURITY DEFINER` nueva debe declarar `SET search_path = public` y preferir tablas schema-calificadas (`public.tabla`). Aplica ya en `handle_new_user()` y `tiene_permiso()` (`sql/001_usuarios_permisos.sql`).

**Por qué:** además de evitar este bug, es la mitigación estándar de Postgres contra search_path injection en funciones `SECURITY DEFINER`.
