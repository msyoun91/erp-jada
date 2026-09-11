# GUIDE_DASHBOARD — Dashboard y Widgets

El dashboard es la ruta `/` (`app/(erp-app)/page.tsx`). Hoy hay un solo widget real (`usuarios`); es la referencia a copiar.

## Estructura

```
modules/dashboard/
├── types.ts          ← registro WIDGETS + DashboardData
├── queries.ts        ← getDashboardData() + getWidgetPrefs()
├── permissions.ts    ← getWidgetsPermitidos(): filtra WIDGETS por módulo autorizado (no se toca)
├── actions.ts        ← toggle de visibilidad en usuario_widgets (genérico, no se toca)
└── components/
    ├── DashboardView.tsx     ← conecta widget.id → componente
    ├── WidgetCard.tsx        ← base reutilizable + ICON_MAP de los widgets
    ├── WidgetUsuarios.tsx    ← ejemplo
    └── ConfigurarWidgets.tsx ← el toggle "Configurar"
```

## Paso 1 — Registrar el widget en `types.ts`

```typescript
export const WIDGETS: WidgetDefinicion[] = [
  // existentes...
  {
    id: "pedidos",              // clave en DashboardView y en usuario_widgets.widget_id
    titulo: "Pedidos",
    columnas: 1,                // 1 = KPI simple | 2 = lista o múltiples KPIs
    moduloRequerido: "pedidos", // prefijo de los códigos de submódulo (`pedidos_ver` → `pedidos`)
    icono: "pedidos",           // clave del ICON_MAP de WidgetCard.tsx
  },
];
```

El widget aparece solo si el usuario tiene **algún** submódulo del módulo: `getWidgetsPermitidos()` compara `moduloRequerido` con lo que está antes del primer `_` de cada código. No hace falta tocar `permissions.ts`.

## Paso 2 — Datos en `DashboardData` y `getDashboardData()`

Sumar los campos a `DashboardData` (`types.ts`) y la consulta a `getDashboardData()` (`queries.ts`). Si el módulo ya tiene la query en su `queries.ts`, reusarla, no duplicarla. Con más de una consulta, todas en `Promise.all()` — nunca en secuencia.

Las consultas corren con el cliente del usuario, así que RLS ya acota lo que cuenta cada uno.

## Paso 3 — El componente

```tsx
// modules/dashboard/components/WidgetPedidos.tsx
import { WidgetCard } from "./WidgetCard";

export function WidgetPedidos({ pendientes, columnas }: { pendientes: number; columnas: 1 | 2 }) {
  return (
    <WidgetCard titulo="Pedidos" icono="pedidos" href="/pedidos" columnas={columnas}>
      <p className="t-h2 tabular-nums">{pendientes}</p>
      <p className="t-caption mt-1">Pedidos pendientes</p>
      {columnas === 2 && <div className="mt-4 border-t border-border pt-3">{/* detalle */}</div>}
    </WidgetCard>
  );
}
```

- Solo clases del design system (`t-*`, tokens de `globals.css`), sin hex ni `text-[..px]`.
- `href` opcional: con `href` la card es link y toma `.card-link` (sombra al hover); sin `href`, no promete click.

## Paso 4 — Ícono

`WidgetCard.tsx` tiene su propio `ICON_MAP` (lucide, `size={16}`, `strokeWidth={1.75}`). Sumar la clave; reusar el mismo ícono que el módulo tiene en `SidebarNav.tsx`.

## Paso 5 — Conectar en `DashboardView.tsx`

```tsx
if (widget.id === "pedidos") {
  return <WidgetPedidos key={widget.id} pendientes={data.pedidosPendientes} columnas={widget.columnas} />;
}
```

## Checklist

- [ ] Registrado en `WIDGETS` con `moduloRequerido` = prefijo real de los códigos del módulo
- [ ] Campos en `DashboardData` y consulta en `getDashboardData()`
- [ ] Componente sobre `WidgetCard`, ícono en su `ICON_MAP`
- [ ] Caso conectado en `DashboardView.tsx`
- [ ] Mobile: KPI visible, sin overflow horizontal · Desktop: `col-span` correcto, el grid denso rellena huecos
- [ ] Aparece/desaparece con "Configurar" y según los submódulos del usuario
- [ ] Si tiene `href`, la navegación funciona
