# ERP JADA

---

# PRINCIPIOS RECTORES

## Simplicidad antes que abstracción

No crear capas, patrones, servicios o estructuras adicionales sin una necesidad concreta.

Evitar:

* abstracciones prematuras
* arquitectura especulativa
* sistemas genéricos para problemas que todavía no existen

Preferir siempre la solución más simple compatible con los requisitos actuales.

---

## Fuente única de verdad

Toda información debe tener una única autoridad.

Duplicar lógica o reglas de negocio genera inconsistencias.

La duplicación de validación es aceptable únicamente cuando protege límites de seguridad o comunicación entre sistemas.

---

## Sin duplicar lógica

Si una regla existe en más de un lugar, debe extraerse.

La duplicación de lógica es un error arquitectónico.

La duplicación de validación es aceptable únicamente cuando protege límites de seguridad.

---

## Seguridad en servidor

La interfaz nunca constituye una barrera de seguridad.

Toda operación sensible debe verificarse nuevamente en servidor.

Ocultar botones no equivale a autorizar acciones.

---

# CÓMO TOMAR DECISIONES

Ante varias alternativas:

1. Elegir la más simple.
2. Elegir la que genere menos código.
3. Elegir la que reutilice estructuras existentes.
4. Evitar nuevas dependencias.
5. Evitar nuevas abstracciones hasta que exista una necesidad demostrada.
6. Verificar si ya existe una solución en el proyecto.

# PRIORIDAD DE REGLAS

Si dos reglas parecen entrar en conflicto:

1. Principios Rectores
2. Seguridad y Permisos
3. Base de Datos
4. Reglas Siempre Activas
5. Guías específicas del módulo

La regla más alta prevalece.

---

# REGLAS SIEMPRE ACTIVAS

- **Nunca DELETE.** Siempre `activo: boolean` para desactivar registros. Si la tabla tiene columnas UNIQUE (código, email, etc.), usar unique index parcial `WHERE activo` — no UNIQUE simple — para permitir reutilizar el valor tras desactivar
- **TypeScript strict.** Nunca `any`. Desconocido → `unknown`
- **Validar en dos lugares:** frontend (Zod + RHF) y server action (`safeParse`)
- **RLS activado** en todas las tablas desde el momento de creación
- **`service_role` key** solo en servidor, nunca en cliente ni NEXT_PUBLIC_
- **Nombrado:** español para negocio (tablas, columnas, entidades, variables de dominio), inglés para infraestructura técnica (nombres de archivo, funciones utilitarias, tipos genéricos, términos del framework). Un archivo de módulo mezcla ambos por diseño (ej: `queries.ts` con función `getListaPrecios`) — la regla decide el campo léxico de cada identificador, no el idioma del archivo entero
- **Sin librerías nuevas** sin consultar
- **Sin comentarios** salvo que el WHY sea no obvio
- **Premisas de auditorías/planes: verificar contra código antes de construir.** Si el código contradice el plan, corregir el plan primero
- **Cargar guides solo cuando la tarea lo pide**, y solo el guide necesario. Cada guide leído queda en contexto el resto de la sesión.
- **`db_schema.md` siempre sincronizado.** Ante cualquier cambio en tablas, columnas o enums — ya sea en `database.types.ts`, SQL, o migración — actualizar `db_schema.md` antes de cerrar la tarea.
- **`/clear` entre tareas.** Terminás un módulo o cambiás de tema → `/clear`. El costo dominante son tokens de contexto reenviados cada turno (cache_read); sesiones de 200+ turnos cuestan ~3× por turno que las cortas.
- Antes de modificar un módulo, leer su sección en `DECISIONES.md` (no el archivo completo — crece por módulo).
- No crear roles. No crear permisos por módulo. Toda autorización nueva se implementa mediante submódulos, incluso si el permiso parece más fino que un submódulo (ej: por fila o por campo) — si un caso real no puede resolverse así, se registra en `DECISIONES.md` como excepción explícita antes de romper la regla, no se decide ad-hoc
- **Regla de negocio → Postgres, no `actions.ts`.** Toda invariante (validación cruzada, cascada, derivación, orquestación multi-tabla) vive en constraint, trigger o función `SECURITY INVOKER` llamada con `.rpc()`. `actions.ts` queda como glue: `safeParse` → llamar → `revalidatePath`. Si una regla no puede expresarse en SQL, registrarla en `DECISIONES.md` como excepción explícita antes de escribirla en TypeScript
- No crear nuevas dependencias sin necesidad demostrada.

---

# ARQUITECTURA DEL REPOSITORIO

```
repo/
├── erp-app/         # Sistema principal. Fuente de verdad del negocio.
├── erp-cliente/     # Portal para clientes. Solo consulta/solicitud. Nunca autoridad.
└── packages/
    └── sync-contracts/   # Schemas y tipos compartidos. Apps nunca se importan entre sí.
```

## Estructura interna erp-app

```
erp-app/src/
├── app/
│   └── (erp-app)/
│       └── [modulo]/
│           └── page.tsx          # Solo renderiza el componente principal
├── modules/
│   └── [modulo]/
│       ├── components/           # Componentes visuales del módulo
│       ├── actions.ts            # Server actions
│       ├── queries.ts            # Consultas a Supabase
│       ├── types.ts              # Tipos + schemas Zod
│       └── permissions.ts        # Verificación de permisos
├── components/
│   ├── ui/                       # Botones, inputs, badges, modales
│   ├── layout/                   # Sidebar, Header
│   └── feedback/                 # Toasts, loaders, errores
└── lib/
    ├── supabase/                  # client.ts · server.ts · middleware.ts
    ├── permissions/               # index.ts — lógica central de permisos
    └── utils.ts
```

**Reglas:**
- Lógica de negocio en `modules/`, nunca en `app/`
- Algo que se usa en 2+ módulos → sube a `components/` o `lib/`
- Nunca importar desde un módulo hacia otro módulo directamente

---

# ORDEN DE CONSTRUCCIÓN — siempre este orden, sin saltar pasos

0. **Módulo nuevo: listar vistas y funciones por vista, confirmar con el usuario antes de escribir código.** Formato:
   ```
   Módulo: Nombre
   ├── modulo_vista1 (vista)
   │   ├── modulo_accion1 (funcion)
   │   └── modulo_accion2 (funcion)
   └── modulo_vista2 (vista, sin funciones)
   ```
   Toda vista arranca con mayúscula. Todo módulo tiene al menos 1 vista. Una vista puede no tener funciones. No avanzar a SQL sin esta lista aprobada.
1. SQL y tipos de base de datos (leer `GUIDE_DB.md`)
2. `types.ts` — schema Zod + tipos TypeScript
3. `permissions.ts` — verificación de acceso (leer `GUIDE_PERMISSIONS.md`)
4. `queries.ts` + `actions.ts`
5. Widget del dashboard (si aplica — leer `GUIDE_DASHBOARD.md`)
6. Componentes de UI (leer `GUIDE_DESIGN.md`)
7. Integración y prueba completa por usuario

## Checklist de módulo nuevo

- [ ] Vistas y funciones por vista listadas y aprobadas
- [ ] SQL creado
- [ ] RLS creado
- [ ] Trigger updated_at creado
- [ ] types.ts creado
- [ ] permissions.ts creado
- [ ] queries.ts creado
- [ ] actions.ts creado
- [ ] UI creada
- [ ] Dashboard integrado
- [ ] DECISIONES.md actualizado

---

# GUIDES — cargar solo el necesario

| Guide | Cargar cuando |
|-------|--------------|
| `.claude/guides/GUIDE_DB.md` | tablas, migrations, Supabase, queries, RLS, enums |
| `.claude/guides/GUIDE_PERMISSIONS.md` | permisos, auth, submódulos, middleware |
| `.claude/guides/GUIDE_TYPESCRIPT.md` | tipos, forms, validación, state, imports |
| `.claude/guides/GUIDE_DESIGN.md` | UI, UX, mobile, diseño visual, feedback |
| `.claude/guides/GUIDE_DASHBOARD.md` | widgets, dashboard, KPIs |
| `.claude/guides/GUIDE_SYNC.md` | sincronización erp-app ↔ erp-cliente |
| `DECISIONES.md` | modificar cualquier módulo existente — leer **solo la sección de ese módulo**, no el archivo entero |

---

# CHECKLIST DE CIERRE DE TAREA

1. `npx tsc --noEmit` — cero errores nuevos
2. Suite de tests, si existe — corre y pasa
3. ¿Tocaste tablas/enums? → `db_schema.md` + `database.types.ts` sincronizados
4. ¿Hay SQL sin correr? → archivo en `sql/` + avisar al usuario
5. ¿Decisión no obvia? → registrar en `DECISIONES.md`
6. Estado de módulos actualizado

---

# DECISIONES DE ARQUITECTURA

## Server → Client boundary

Nunca pasar props no-serializables de Server Component a Client Component. Lucide icons, React components, funciones y class instances causan error en runtime: `"Only plain objects can be passed to Client Components from Server Components."`

Cuando un Server Component necesita pasarle "qué ícono mostrar" a un Client Component: pasar string key (ej: `modulo: 'dashboard'`). El Client Component resuelve el string a componente con un `ICON_MAP` local. Mismo patrón para cualquier dato no-serializable.

## Encabezado de módulo

Todo módulo tiene `<h1>` con ícono + nombre visible antes de los tabs. Estructura obligatoria en el `layout.tsx` del módulo:

```tsx
import { IconName } from 'lucide-react'

<div className="flex flex-col h-full">
  <h1 className="t-h1 mb-4 flex items-center gap-2.5">
    <IconName size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
    Nombre del Módulo
  </h1>
  <ModuleTabs modulo="nombre" tabs={tabs} />
  {children}
</div>
```

El ícono y el label se toman del `ICON_MAP` y `LABEL_MAP` de `SidebarNav.tsx` — misma fuente de verdad.

## Patrón UI de submódulos

Submódulos tienen dos tipos:
- **Vista**: aparecen como tabs horizontales en el módulo
- **Función**: aparecen como botones/toolbar, contextuales a la tab activa

La vista sabe qué acciones ofrece y las renderiza directamente verificando permisos:

```tsx
{hasPermission('modulo', 'nombre_funcion') && (
  <Button onClick={...}>Acción</Button>
)}
```

El submódulo-función existe solo para la capa de permisos — no como entidad de UI independiente ni como mapeo declarativo. No crear configs que mapeen vistas↔funciones.

- Orden de tabs: fijo en código (no customizable hasta que un usuario lo pida)
- Agrupación visual en nav: puramente cosmética, sin lógica de negocio ni permisos
