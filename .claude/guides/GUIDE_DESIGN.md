# GUIDE_DESIGN — Diseño y UX

> El sistema de diseño visual (colores, tipografía, espaciado) está en `.claude/guides/design-system/JADA-design-system.md`. Nunca hardcodear valores.

## Mobile-first — obligatorio

El sistema se usa desde celular en obra y en oficina.

- Diseñar primero para pantalla chica, adaptar a grandes
- Touch targets mínimo 44px de alto
- Sin hover states como única interacción (touch no tiene hover)
- Sin tablas en mobile → usar lista compacta o solo totales
- Conectividad intermitente: considerar que la red puede fallar

## Estados visuales obligatorios en formularios

Todo formulario tiene tres estados:

1. **Normal** — campos disponibles para completar
2. **Cargando** — botón deshabilitado con indicador de espera
3. **Resultado** — mensaje de éxito o error en español claro

## Feedback al usuario

- **Toasts** (Sonner) para confirmaciones rápidas de acciones
- **Mensajes inline** para errores de formulario
- El usuario nunca se queda preguntando si algo funcionó
- Los errores de Supabase siempre se traducen a español comprensible. Nunca mostrar errores técnicos en pantalla

## Optimistic Updates

En acciones clave (cambio de estado, registro de pago, desactivar elemento):

1. Actualizar la UI inmediatamente sin esperar respuesta del servidor
2. Si la sincronización falla → revertir el cambio visualmente
3. Mostrar mensaje de error claro en español
4. Nunca bloquear la UI esperando una respuesta que puede no llegar

## Confirmación explícita

Requerir confirmación antes de cualquier acción que cambie estado importante:
cambio de estado de pedido, desactivar usuario, registrar un pago.
Nunca ejecutar sin que el usuario confirme.

## Listados

- Más de 20 registros → paginar
- Siempre mostrar el total de registros encontrados

## Estado vacío

Toda pantalla tiene un estado vacío definido.
Si no hay datos: mostrar mensaje claro que explique por qué y qué hacer.

## Sidebar

Muestra únicamente los módulos que el usuario tiene autorizados.
Lo no autorizado no se ve, no existe.

## Encabezado de módulo

Todo módulo tiene `<h1>` con ícono + nombre antes de los tabs. Va en el `layout.tsx` del módulo:

```tsx
import { Tag } from 'lucide-react'  // ícono del módulo, ver SidebarNav.tsx

<div className="flex flex-col h-full">
  <h1 className="t-h1 mb-4 flex items-center gap-2.5">
    <Tag size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
    Lista de Precios
  </h1>
  <ModuleTabs modulo="precios" tabs={tabs} />
  {children}
</div>
```

- Ícono: tomarlo del `ICON_MAP` en `SidebarNav.tsx`
- Label: tomarlo del `LABEL_MAP` en `SidebarNav.tsx`
- Nunca hardcodear ícono o label diferente al que aparece en el nav

## Campos obligatorios

Indicar visualmente antes de que el usuario intente guardar.
No solo mostrar el error después de intentar enviar.
