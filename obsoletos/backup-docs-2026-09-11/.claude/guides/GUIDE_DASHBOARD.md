# GUIDE_DASHBOARD — Dashboard y Widgets

## Módulo nuevo vs módulo ya existente

**Módulo nuevo:** seguir los pasos 1-5 en orden.

**Módulo ya existente:** los pasos son los mismos pero:
- `types.ts` del módulo ya existe → solo agregar campos a `DashboardData` en `modules/dashboard/types.ts`
- `queries.ts` del módulo ya existe → reutilizar sus queries dentro de `getDashboardData()` en `modules/dashboard/queries.ts`, no duplicarlas
- `permissions.ts` ya existe → el widget se muestra automáticamente si el usuario tiene el permiso del módulo
- Reemplazar el `WidgetPendiente` existente en `DashboardView.tsx` por el widget real

## Estructura del sistema de widgets

```
modules/dashboard/
├── types.ts          ← registro WIDGETS + tipos
├── queries.ts        ← getDashboardData() agrega los datos del nuevo widget
├── actions.ts        ← sin cambios (toggle es genérico)
└── components/
    ├── DashboardView.tsx   ← conecta widget_id → componente
    ├── WidgetCard.tsx      ← base reutilizable (no editar por módulo)
    ├── WidgetUsuarios.tsx  ← ejemplo de widget con datos reales
    ├── WidgetPendiente.tsx ← placeholder para módulos sin datos aún
    └── WidgetNuevo.tsx     ← el archivo que vos creás
```

## Paso 1 — Registrar el widget en `types.ts`

```typescript
// modules/dashboard/types.ts

export const WIDGETS: WidgetDefinicion[] = [
  // existentes...
  {
    id: "nombre_modulo",       // debe coincidir con ModuloNombre en database.types.ts
    titulo: "Nombre visible",  // texto que ve el usuario
    columnas: 1,               // 1 = KPI simple | 2 = lista o múltiples KPIs
    moduloRequerido: "nombre_modulo",  // igual que id
    icono: "nombre_icono",     // "pedidos" | "cobranza" | "usuarios" (agregar si es nuevo)
  },
];
```

**Regla:** `id` y `moduloRequerido` deben ser exactamente el valor del enum `modulo_nombre` en Supabase.

## Paso 2 — Agregar datos en `queries.ts`

El tipo `DashboardData` en `types.ts` acumula todos los datos de todos los widgets.
Agregar los campos del nuevo widget:

```typescript
// En types.ts
export type DashboardData = {
  totalUsuariosActivos: number;
  // agregar acá:
  totalPedidosPendientes: number;
  montoPorCobrar: number;
};
```

Luego en `queries.ts`, extender `getDashboardData()`:

```typescript
export async function getDashboardData(): Promise<DashboardData> {
  const supabase = createClient();

  // queries en paralelo
  const [{ count: usuarios }, { count: pedidos }, cobranzaData] = await Promise.all([
    supabase.from("usuarios").select("id", { count: "exact", head: true }).eq("activo", true),
    supabase.from("pedidos").select("id", { count: "exact", head: true }).eq("estado", "pendiente").eq("activo", true),
    supabase.from("cobranza").select("monto_total").eq("estado", "pendiente").eq("activo", true),
  ]);

  const montoPorCobrar = (cobranzaData.data ?? []).reduce(
    (acc, row) => acc + row.monto_total, 0
  );

  return {
    totalUsuariosActivos: usuarios ?? 0,
    totalPedidosPendientes: pedidos ?? 0,
    montoPorCobrar,
  };
}
```

**Regla:** todas las queries van en `Promise.all()`. Nunca en secuencia.

## Paso 3 — Crear el componente `WidgetNuevo.tsx`

```tsx
// modules/dashboard/components/WidgetPedidos.tsx

import { WidgetCard } from "./WidgetCard";

type Props = {
  totalPendientes: number;
  columnas: 1 | 2;
};

export function WidgetPedidos({ totalPendientes, columnas }: Props) {
  return (
    <WidgetCard titulo="Pedidos" icono="pedidos" href="/pedidos" columnas={columnas}>

      {/* KPI principal — siempre visible en mobile y desktop */}
      <div className="flex flex-col gap-0.5">
        <p className="font-display font-bold text-[28px] leading-none tracking-[.01em] text-[var(--text-primary)]">
          {totalPendientes}
        </p>
        <p className="mt-1 text-[11px] text-[var(--text-secondary)]">Pedidos pendientes</p>
      </div>

      {/* Contenido extra — solo en widget de 2 columnas */}
      {columnas === 2 && (
        <div className="mt-4 border-t border-[rgba(13,18,32,.08)] pt-3">
          {/* lista compacta, stats secundarias, etc. */}
        </div>
      )}

    </WidgetCard>
  );
}
```

## Paso 4 — Conectar en `DashboardView.tsx`

```tsx
// modules/dashboard/components/DashboardView.tsx
import { WidgetPedidos } from "./WidgetPedidos";

{widgetsVisibles.map((widget) => {
  if (widget.id === "pedidos") {
    return <WidgetPedidos key={widget.id} totalPendientes={data.totalPedidosPendientes} columnas={widget.columnas} />;
  }
  return <WidgetPendiente key={widget.id} titulo={widget.titulo} icono={widget.icono} columnas={widget.columnas} />;
})}
```

## Paso 5 — Agregar ícono SVG si es necesario

Los íconos viven en `WidgetCard.tsx` dentro de `WidgetIcon()`.
Usar SVGs simples de 16×16, stroke `#064379`, strokeWidth `1.5`.
Sin fill. Sin librerías de íconos externas.

## Checklist antes de dar el widget por terminado

- [ ] Widget registrado en `WIDGETS` con `id`, `titulo`, `columnas`, `moduloRequerido`
- [ ] Datos agregados en `DashboardData` type y en `getDashboardData()`
- [ ] Componente `WidgetXxx.tsx` creado con WidgetCard como base
- [ ] Caso conectado en `DashboardView.tsx`
- [ ] Mobile probado: KPI visible, sin overflow horizontal
- [ ] Desktop probado: col-span correcto, grid-flow-dense rellena huecos
- [ ] Widget aparece/desaparece con el toggle de configurar
- [ ] Si el widget tiene `href`, la navegación funciona
