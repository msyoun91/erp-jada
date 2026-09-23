# GUIDE_PERMISSIONS — Seguridad y Permisos

## Modelo

Sin roles. Toda autorización es un **submódulo** (tablas `submodulos` + `usuario_submodulos`, nunca un enum). Los módulos son solo agrupadores funcionales y de navegación. CLAUDE.md fija la regla dura: no crear roles ni permisos por módulo.

Un módulo tiene 1 o más vistas. Cada vista puede tener 0 o más funciones, ligadas a esa vista puntual vía `submodulos.vista_id` (no solo por compartir `modulo`).

- **vista** — controla tab, acceso a la ruta y visibilidad del módulo en el sidebar. `vista_id = NULL`. Ej: `pedidos_ver`, `pedidos_facturacion`.
- **funcion** — controla botones, acciones sensibles y operaciones de negocio. `vista_id` obligatorio, apunta a la vista dueña (misma `modulo`, verificado por trigger). Ej: `pedidos_anular` (vista_id → `pedidos_ver`).

Una vista puede no tener funciones (solo lectura). Vista y función se asignan por separado, pero una función sin su vista queda prohibida: `asignarSubmodulos()` la rechaza en servidor.

```
Pedidos
├── pedidos_ver (vista)
│   ├── pedidos_crear (funcion)
│   └── pedidos_anular (funcion)
└── pedidos_facturacion (vista, sin funciones)
```

---

## Dónde se verifica

La UI puede ocultar elementos; la autorización real siempre ocurre en servidor.

| Qué | Dónde |
|---|---|
| Sesión y usuario activo | `src/proxy.ts` → `updateSession()`. No mira submódulos |
| Vista | el `page.tsx` de la vista: `if (!(await puedeVerX())) notFound()` · el `layout.tsx` del módulo arma los tabs con los mismos `puedeVerX()` |
| Función, action con cliente normal | RLS / función SQL con `tiene_permiso('codigo')` — la regla vive en Postgres (CLAUDE.md) |
| Función, action con `service_role` | la action misma, antes de tocar nada: `if (!(await puedeX())) return { success: false, error: "No autorizado" }` — `service_role` no pasa por RLS |

Los `puedeX()` viven en `modules/<modulo>/permissions.ts` y envuelven `tienePermiso(codigo)`.

---

## Patrón UI de submódulos

- **Vista** → tab horizontal del módulo.
- **Función** → botón/toolbar, contextual a la tab activa.

La vista sabe qué acciones ofrece y las renderiza directamente verificando permisos. El `page.tsx` (server) resuelve el `puedeX()` y lo pasa como prop booleana:

```tsx
{puedeAnular && <Button onClick={...}>Anular</Button>}
```

El submódulo-función existe solo para la capa de permisos — no como entidad de UI independiente ni como mapeo declarativo. No crear configs que mapeen vistas↔funciones.

- Orden de tabs: fijo en código, en el array `tabs` del `layout.tsx` (no customizable hasta que un usuario lo pida)
- Agrupación visual en nav: puramente cosmética, sin lógica de negocio ni permisos

---

## Implementación

### Convención de naming (crítica)

`codigo` siempre sigue el patrón `{modulo}_{slug}`. El módulo de un código es lo que está antes del primer `_` (así lo calculan `Sidebar.tsx` y el dashboard), así que el nombre del módulo no lleva `_`.

`nombre` de la vista básica (`{modulo}_ver`) es siempre **"Ver"**, nunca repite el label del módulo — el modal de permisos ya muestra el módulo como encabezado (`LABEL_MAP`). Vistas no-básicas usan un nombre descriptivo propio (ej: "Calendario", "Facturación").

### Agregar una vista

1. Migración: insertar el submódulo con `tipo = 'vista'`, `vista_id = NULL`.
2. `modules/<modulo>/permissions.ts`: `puedeVerX()` → `tienePermiso('<codigo>')`.
3. `app/(erp-app)/<modulo>/<ruta>/page.tsx`: `notFound()` sin el permiso.
4. `app/(erp-app)/<modulo>/layout.tsx`: sumar la entrada al array `tabs` (`codigo`, `label`, `href`).
5. Si es la primera vista del módulo: `SidebarNav.tsx` → `NAV_ITEMS`, `ICON_MAP` y `LABEL_MAP`.
6. Asignarla a usuarios desde Usuarios (o backfill en la migración si reemplaza un acceso existente).

### Agregar una función

1. Migración: insertar el submódulo con `tipo = 'funcion'` y `vista_id` → la vista dueña.
2. La barrera: `tiene_permiso('<codigo>')` en la policy o función SQL que hace la escritura (o `puedeX()` en la action si usa `service_role`).
3. `puedeX()` en `permissions.ts` para que la vista muestre u oculte el botón.

### Reglas entre permisos

Un permiso puede **requerir** otro (en un sentido) o **excluir** otro (una fila por par, vale en los dos sentidos), incluso de otro módulo. Se declaran en la ficha del módulo y se cargan como filas de `submodulo_reglas` en la migración que siembra los submódulos. No se escriben en código: `usuario_submodulos_validar` las hace valer (US016 / US017) y `PermisosPanel` las lee para avisar y deshabilitar. Vista → función no va ahí, ya la da `vista_id`. Decisión: `decisiones/global/permisos.md` → *Reglas entre permisos*.

```sql
INSERT INTO submodulo_reglas (submodulo_id, otro_id, tipo)
SELECT a.id, b.id, 'requiere' FROM submodulos a, submodulos b
WHERE a.codigo = 'modulo_x' AND a.activo AND b.codigo = 'modulo_y' AND b.activo;
```

### Funciones de `lib/permissions`

| Función | Uso |
|---|---|
| `getUserSubmodulos()` | Códigos del usuario. `cache()` de React: una query por request |
| `tienePermiso(codigo)` | Verifica un permiso (usa `getUserSubmodulos`) |
| `getVistasDeModulo(modulo)` | Vistas autorizadas de un módulo. Sin `cache()` y hoy sin uso: los layouts arman los tabs con `puedeVerX()` |

---

## Eliminación de módulos o submódulos

Nunca eliminar permisos históricos asignados a usuarios.

Al retirar un submódulo de un módulo vivo:

1. Revocar acceso operativo.
2. Quitar navegación.
3. Mantener historial para auditoría.
4. No eliminar registros históricos salvo migración explícita.

Si desaparece el módulo entero, sí se borra — ver `decisiones/global/infra.md` → *El módulo comercial se elimina entero*.
