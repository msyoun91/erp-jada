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

### seccion

Controla:

* navegación
* acceso a rutas
* middleware
* visibilidad de sidebar

Ejemplos:

* clientes_ver
* pedidos_ver
* cobranzas_ver

### funcion

Controla:

* botones
* acciones sensibles
* operaciones de negocio
* server actions

Ejemplos:

* pedidos_anular
* pedidos_editar
* cobranza_registrar_pago

---

## Modelo

```
Pedidos
├── pedidos_ver
├── pedidos_crear
├── pedidos_editar
└── pedidos_anular

Cobranza
├── cobranza_ver
├── cobranza_registrar_pago
└── cobranza_anular_pago
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

### Agregar un nuevo módulo

1. Insertar submodulo en DB con `tipo: 'seccion'`, ej: `{ codigo: 'agenda_clientes', modulo: 'agenda', tipo: 'seccion' }`
2. Asignar a usuario en `usuario_submodulos`
3. Agregar el módulo al sidebar en `Sidebar.tsx` → `NAV_ITEMS`
4. Crear la página: `app/(erp-app)/agenda/clientes/page.tsx` (ruta estática tiene prioridad sobre `[modulo]/[submodulo]`)

### Agregar una funcion (botón de acción)

1. Insertar submodulo en DB con `tipo: 'funcion'`, ej: `{ codigo: 'agenda_transferir', modulo: 'agenda', tipo: 'funcion' }`
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
| `getSeccionesDeModulo(modulo)` | Secciones autorizadas de un módulo (para tabs) |

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
