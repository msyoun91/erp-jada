# GUIDE_DESIGN — Diseño y UX

> El sistema de diseño visual (colores, tipografía, espaciado) está en `.claude/guides/design-system/JADA-design-system.md`; la implementación viva, en `globals.css`. Nunca hardcodear valores.

## Mobile-first — obligatorio

El sistema se usa desde celular en obra y en oficina.

- Diseñar primero para pantalla chica, adaptar a grandes
- Touch targets mínimo 44px de alto
- Sin hover states como única interacción (touch no tiene hover)
- Sin tablas en mobile → usar lista compacta o solo totales
- Conectividad intermitente: considerar que la red puede fallar

## Encabezado de módulo

Todo módulo tiene un `<Breadcrumb>` (`Módulo / Vista`) y un `<h1>` con ícono + nombre, en ese orden, antes de los tabs. Estructura obligatoria en el `layout.tsx` del módulo:

```tsx
import { IconName } from 'lucide-react'
import { Breadcrumb } from '@/components/layout/Breadcrumb'

<div className="flex flex-col h-full">
  <Breadcrumb modulo="nombre" tabs={tabs} />
  <h1 className="t-h1 mb-4 flex items-center gap-2.5">
    <IconName size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
    Nombre del Módulo
  </h1>
  <ModuleTabs modulo="nombre" tabs={tabs} />
  {children}
</div>
```

- Ícono y label del `<h1>`: del `ICON_MAP` y `LABEL_MAP` de `SidebarNav.tsx` — misma fuente de verdad. Nunca uno distinto al del nav
- El `<Breadcrumb>` reusa `LABEL_MAP` para el módulo y la tab activa (`tabActiva`, misma lógica que `ModuleTabs`) para la vista; con una sola tab muestra solo el módulo
- La hoja de detalle (nombre de la obra/persona) no la muestra el breadcrumb del layout: las fichas de obras usan su propio `modules/obras/components/Breadcrumb` (ver `decisiones/obras/ui.md`)

## Server → Client boundary

Nunca pasar props no-serializables de Server Component a Client Component. Lucide icons, React components, funciones y class instances causan error en runtime: `"Only plain objects can be passed to Client Components from Server Components."`

Cuando un Server Component necesita pasarle "qué ícono mostrar" a un Client Component: pasar string key (ej: `modulo: 'dashboard'`). El Client Component resuelve el string a componente con un `ICON_MAP` local. Mismo patrón para cualquier dato no-serializable.

## Estados visuales obligatorios en formularios

Todo formulario tiene tres estados:

1. **Normal** — campos disponibles para completar
2. **Cargando** — botón deshabilitado con indicador de espera
3. **Resultado** — mensaje de éxito o error en español claro

## Feedback al usuario

- **Toasts** (Sonner) para confirmaciones rápidas de acciones
- **Mensajes inline** para errores de formulario
- El usuario nunca se queda preguntando si algo funcionó
- Los errores de Supabase siempre se traducen a español comprensible (`mensajeError()` de `lib/utils.ts`). Nunca mostrar errores técnicos en pantalla

## Acciones: esperar al servidor, sin optimistic updates

No hay `useOptimistic` en la app. Una acción espera la server action con el botón deshabilitado, muestra el toast de éxito o error y la lista se refresca por `revalidatePath`. Si algún día se agrega optimistic, se decide app-wide en `decisiones/global/`, no en un módulo (ver `decisiones/obras/ui.md` → *Sin optimistic update*).

## Crear y editar: panel lateral, no modal

`RightPanel.tsx` (`components/ui/`) es el patrón para formularios de creación/edición. Crear/editar es una tarea de mayor foco y duración, y el panel lateral no bloquea el contexto de la lista de atrás.

Las confirmaciones sí son modal (`Modal.tsx` / `ConfirmModal`): son una interrupción corta y ahí el modal es más directo.

Los dos viven en el top layer del browser (`<dialog>` + `showModal()`), así que se apilan por orden de apertura sin manejar z-index.

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

## Campos obligatorios

Indicar visualmente antes de que el usuario intente guardar (`.t-label-req` + `aria-required`).
No solo mostrar el error después de intentar enviar.
