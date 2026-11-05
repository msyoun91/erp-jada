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

Toda pantalla de `(erp-app)` —módulos, Inicio y Mi perfil— va dentro de `<Modulo>`
(`components/layout/Modulo.tsx`): `<Breadcrumb>` (`Módulo / Vista`), `<h1>` con ícono + nombre y tabs,
en ese orden. El `layout.tsx` del módulo queda así:

```tsx
import { Modulo } from "@/components/layout/Modulo";

<Modulo modulo="nombre" tabs={tabs}>
  {children}
</Modulo>
```

- Ícono y nombre salen del `ICON_MAP` y `LABEL_MAP` de `SidebarNav.tsx`: un módulo nuevo se suma ahí y en
  ningún otro lado. No escribir el `<h1>` a mano
- `accion` pone un control a la derecha del título (Configurar, en Inicio)
- El `<Breadcrumb>` reusa `LABEL_MAP` para el módulo y la tab activa (`tabActiva`, misma lógica que `ModuleTabs`)
  para la vista; con una sola tab muestra solo el módulo. No navega: la vuelta de una ficha es `<Volver>`

## Ficha de detalle

La cabecera es una `.card`: primero una fila con el `<h2 className="t-h2 min-w-0 flex-1">`, los badges de
estado y las acciones (el `⋯`, y a la vista solo lo de todos los días), y debajo los datos en `t-caption`.

Toda ficha con ruta propia (`/obras/[id]`, `/catalogo/porcentajes/[id]`, …) arranca con
`<Volver href="/listado">Listado</Volver>` (`components/ui/Volver.tsx`). Va en el `page.tsx` y no en el
componente de la ficha cuando esa ficha también se abre al lado de un paso de Tareas.

## Barra de un listado: acciones arriba, filtros abajo

Primero una fila con las acciones —el primario (`Nuevo …`) primero, después los secundarios y el `⋯`—, y
debajo otra con buscador y filtros. Las dos `mb-4 flex flex-wrap items-center gap-3`. Así el primario está
siempre en el mismo lugar, y en el celular no queda enterrado debajo del buscador. Una acción que depende de
la vista elegida igual se muestra siempre: si aparece y desaparece, la fila de abajo salta.

Elegir entre pocas vistas o períodos es un `.segmented` (`globals.css`): botones con `aria-pressed` o links
con `aria-current`, que es lo que marca el elegido. No `btn-primary`: eso es una acción.

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
- **Avisos en pantalla** (algo espera aprobación, lo que frena un envío, un error de cálculo): `.alert` +
  `.alert-warning|error|success|info`. El aviso fija el color del texto: adentro no va `t-body-m`, que lo
  repinta de `text-secondary`
- Los errores de Supabase siempre se traducen a español comprensible (`mensajeError()` de `lib/utils.ts`). Nunca mostrar errores técnicos en pantalla

## Acciones: esperar al servidor, sin optimistic updates

No hay `useOptimistic` en la app. Una acción espera la server action con el botón deshabilitado, muestra el toast de éxito o error y la lista se refresca por `revalidatePath`. Si algún día se agrega optimistic, se decide app-wide en `decisiones/global/`, no en un módulo (ver `decisiones/obras/ui.md` → *Sin optimistic update*).

## Crear y editar: panel lateral, no modal

`RightPanel.tsx` (`components/ui/`) es el patrón para formularios de creación/edición. Crear/editar es una tarea de mayor foco y duración, y el panel lateral no bloquea el contexto de la lista de atrás.

El pie es `<PiePanel>` (en `RightPanel.tsx`): la salida y el primario a la derecha, en `btn-sm`, con
"Guardando…" mientras espera. A la izquierda, `nota` para lo que falta o lo que va a cambiar. No armar el
pie a mano.

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
Si no hay datos: mostrar mensaje claro que explique por qué y qué hacer. Siempre título (`t-h3`) + texto
(`t-body-m mt-1`) dentro de `.empty-state`; "Sin X todavía" si no hay nada y "Sin resultados" si lo vació
un filtro.

## Íconos

El trazo es uno solo, 1.75, y lo pone el `LucideProvider` de `app/layout.tsx`: no escribir `strokeWidth`
salvo para apartarse a propósito (los íconos grandes de un estado vacío van en 1.5).

## Estado desactivado

La acción es "Desactivar" y el estado, "Desactivado/a" (badge `badge-neutral`, filtro "Desactivados"). No
"Inactivo". Catálogo dice "Dar de baja" / "De baja", que es el término del negocio ahí.

## Sidebar

Muestra únicamente los módulos que el usuario tiene autorizados.
Lo no autorizado no se ve, no existe.

## Campos obligatorios

Indicar visualmente antes de que el usuario intente guardar (`.t-label-req` + `aria-required`).
No solo mostrar el error después de intentar enviar.
