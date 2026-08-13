# GUIDE_PERMISSIONS — Seguridad y Permisos

## Persistencia de permisos

Los permisos se almacenan en tablas.

No utilizar enums para permisos.

Modelo:

```
submodulos
usuario_submodulos
```

---

## Principio rector

El sistema NO utiliza roles.

Toda autorización se realiza mediante submódulos.

Los módulos son únicamente agrupadores funcionales y de navegación.

La unidad real de autorización es el submódulo.

---

## Tipos de submódulo

Un módulo tiene 1 o más vistas. Cada vista puede tener 0 o más funciones, ligadas a
esa vista puntual vía `submodulos.vista_id` (no solo por compartir `modulo`).

### vista

Controla:

* navegación (tab)
* acceso a rutas
* middleware
* visibilidad de sidebar

`vista_id`: `NULL` (una vista no depende de otra).

Ejemplos:

* clientes_ver
* pedidos_ver
* pedidos_facturacion

### funcion

Controla:

* botones
* acciones sensibles
* operaciones de negocio
* server actions

`vista_id`: obligatorio — apunta a la vista dueña (misma `modulo`, verificado por trigger).
Una vista puede no tener ninguna función (solo acceso de lectura) — se autoriza
directo, sin función que la sincronice.

Ejemplos:

* pedidos_anular (vista_id → pedidos_ver)
* pedidos_editar (vista_id → pedidos_ver)
* cobranza_registrar_pago (vista_id → cobranza_ver)

---

## Modelo

```
Pedidos
├── pedidos_ver (vista)
│   ├── pedidos_crear (funcion)
│   ├── pedidos_editar (funcion)
│   └── pedidos_anular (funcion)
└── pedidos_facturacion (vista, sin funciones)

Cobranza
├── cobranza_ver (vista)
│   ├── cobranza_registrar_pago (funcion)
│   └── cobranza_anular_pago (funcion)
```

---

## Reglas

- Toda autorización nueva debe implementarse mediante submódulos.
- Los módulos son únicamente agrupadores funcionales.
- No crear roles.
- No crear permisos por módulo.

---

## Verificación obligatoria

### seccion

Verificar en:

- middleware
- server actions

### funcion

Verificar en:

- server actions

La UI puede ocultar elementos.

La autorización real siempre ocurre en servidor.

---

## Implementación — módulos y submódulos

### Convención de naming (crítica)

`codigo` siempre sigue el patrón `{modulo}_{slug}`:

```
modulo: agenda
codigo: agenda_clientes   → URL /agenda/clientes
codigo: agenda_calendario → URL /agenda/calendario
codigo: agenda_transferir → funcion (no genera tab, no genera ruta)
```

El slug del URL se deriva automáticamente: `codigo.slice(modulo.length + 1)`.

`nombre` de la vista básica (`{modulo}_ver`) es siempre **"Ver"**, nunca repite el label del módulo — el modal de permisos ya muestra el módulo como encabezado (`LABEL_MAP`), repetirlo en la vista es ruido y ambigüedad ("Usuarios" arriba de "Usuarios"). Vistas no-básicas usan un nombre descriptivo propio (ej: "Calendario", "Facturación").

### Agregar una nueva vista

1. Insertar submodulo en DB con `tipo: 'vista'`, `vista_id: null`, ej: `{ codigo: 'agenda_clientes', modulo: 'agenda', tipo: 'vista' }`
2. Asignar a usuario en `usuario_submodulos`
3. Agregar el módulo al sidebar en `Sidebar.tsx` → `NAV_ITEMS` (si es la primera vista del módulo)
4. Crear la página: `app/(erp-app)/agenda/clientes/page.tsx` (ruta estática tiene prioridad sobre `[modulo]/[submodulo]`)

### Agregar una funcion (botón de acción)

1. Insertar submodulo en DB con `tipo: 'funcion'`, `vista_id` apuntando a la vista dueña, ej: `{ codigo: 'agenda_transferir', modulo: 'agenda', tipo: 'funcion', vista_id: <id de agenda_clientes> }`
2. En el componente vista:

```tsx
import { tienePermiso } from '@/lib/permissions'

// En un Server Component:
const puedeTransferir = await tienePermiso('agenda_transferir')

// Pasar como prop al Client Component o renderizar directo:
{puedeTransferir && <Button>Transferir</Button>}
```

3. Verificar en el server action también (la UI no es barrera de seguridad).

### Funciones de permissions disponibles

| Función | Uso |
|---|---|
| `getUserSubmodulos()` | Lista de codigos del usuario |
| `tienePermiso(codigo)` | Verifica un permiso específico |
| `getVistasDeModulo(modulo)` | Vistas autorizadas de un módulo (para tabs) |

Todas usan `cache()` de React — una sola query DB por request.

---

## Eliminación de módulos o submódulos

Nunca eliminar permisos históricos asignados a usuarios.

Al retirar un módulo o submódulo:

1. Revocar acceso operativo.
2. Quitar navegación.
3. Mantener historial para auditoría.
4. No eliminar registros históricos salvo migración explícita.

No realizar limpieza destructiva por defecto.
