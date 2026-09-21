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

Toda información y toda regla tiene una única autoridad. Si una regla existe en más de un lugar, debe extraerse: la duplicación de lógica es un error arquitectónico.

La duplicación de validación es aceptable únicamente cuando protege límites de seguridad o comunicación entre sistemas.

---

## Seguridad en servidor

La interfaz nunca constituye una barrera de seguridad. Toda operación sensible se verifica nuevamente en servidor. Ocultar botones no equivale a autorizar acciones.

---

# CÓMO TOMAR DECISIONES

Ante varias alternativas:

1. Elegir la más simple.
2. Elegir la que genere menos código.
3. Reutilizar lo que ya existe: verificar primero si el proyecto ya lo resuelve.
4. Evitar nuevas dependencias y nuevas abstracciones hasta que exista una necesidad demostrada.

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
- **Leer por tema, no por archivo.** Cargar solo la guía, el archivo de decisiones y el de `db_schema/` que la tarea necesita (tabla GUIDES). En `decisiones/<modulo>/`, primero el `README.md` índice y después solo los archivos del tema. Todo lo leído queda en contexto el resto de la sesión.
- **`db_schema/` siempre sincronizado.** Ante cualquier cambio en tablas, columnas o enums — ya sea en `database.types.ts`, SQL, o migración — actualizar `db_schema/<modulo>.md` antes de cerrar la tarea.
- **`/clear` entre tareas.** Terminás un módulo o cambiás de tema → `/clear`. El costo dominante son tokens de contexto reenviados cada turno (cache_read); sesiones de 200+ turnos cuestan ~3× por turno que las cortas.
- No crear roles. No crear permisos por módulo. Toda autorización nueva se implementa mediante submódulos, incluso si el permiso parece más fino que un submódulo (ej: por fila o por campo) — si un caso real no puede resolverse así, se registra en `decisiones/global/permisos.md` como excepción explícita antes de romper la regla, no se decide ad-hoc
- **Regla de negocio → Postgres, no `actions.ts`.** Toda invariante (validación cruzada, cascada, derivación, orquestación multi-tabla) vive en constraint, trigger o función `SECURITY INVOKER` llamada con `.rpc()`. `actions.ts` queda como glue: `safeParse` → llamar → `revalidatePath`. Si una regla no puede expresarse en SQL, registrarla en `decisiones/<modulo>` como excepción explícita antes de escribirla en TypeScript
- **`obsoletos/` no se lee.** Es el cementerio: docs cerradas, boilerplate, código retirado y backups. Entrar solo para restaurar algo, nunca como contexto de una tarea. Un puntero a `obsoletos/` desde `decisiones/` o `BACKLOG.md` es histórico — la decisión está escrita en el archivo que apunta
- **Módulo nuevo → leer `.claude/guides/GUIDE_MODULO_NUEVO.md` antes de escribir nada.** Arranca preguntando quién va a usar el módulo —incluidos los que solo miran— y con la ficha del módulo (`GUIDE_ENTES.md`: personas, entes, estados, relaciones, acciones, eventos) y la lista de vistas y funciones, aprobadas por el usuario; sin eso no hay SQL. La ficha aprobada se pega en `decisiones/<modulo>.md`, y antes de sumar cualquier vista o función —también en debug, meses después— se contrasta contra sus personas y se avisa si el pedido se sale de ahí.

---

# ARQUITECTURA DEL REPOSITORIO

```
repo/
├── erp-app/         # Sistema principal. Fuente de verdad del negocio.
├── erp-cliente/     # Portal para clientes. Solo consulta/solicitud. Nunca autoridad.
├── decisiones/      # Por qué se decidió cada cosa. Por módulo; los grandes, en carpeta con índice
├── db_schema/       # Esquema actual, un archivo por módulo
├── sql/             # Migraciones y tests de RLS (sql/tests/)
└── obsoletos/       # Retirados. No leer salvo restaurar — ver obsoletos/README.md
```

Las apps nunca se importan entre sí. Cuando haga falta compartir schemas y tipos, el workspace
`sync-contracts` se restaura desde `obsoletos/` (ver `GUIDE_SYNC.md`), no se crea de cero.

## Estructura interna erp-app

```
erp-app/src/
├── proxy.ts                      # Sesión y usuario activo (Next 16: ex-middleware.ts)
├── app/
│   └── (erp-app)/
│       └── [modulo]/
│           ├── layout.tsx        # Encabezado de módulo + tabs
│           └── page.tsx          # Permiso de la vista, datos y componente principal
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
    ├── supabase/                  # client.ts · server.ts · middleware.ts · rpc.ts
    ├── permissions/               # index.ts — lógica central de permisos
    └── utils.ts
```

**Reglas:**
- Lógica de negocio en `modules/`, nunca en `app/`
- Algo que se usa en 2+ módulos → sube a `components/` o `lib/`
- Nunca importar desde un módulo hacia otro módulo directamente

---

# GUIDES — cargar solo el necesario

| Guide | Cargar cuando |
|-------|--------------|
| `.claude/guides/GUIDE_DB.md` | tablas, migrations, Supabase, queries, RLS, enums |
| `.claude/guides/GUIDE_PERMISSIONS.md` | permisos, submódulos, vistas y funciones, tabs, proxy |
| `.claude/guides/GUIDE_TYPESCRIPT.md` | tipos, forms, validación, state, imports |
| `.claude/guides/GUIDE_DESIGN.md` | UI, UX, mobile, layout de módulo, diseño visual, feedback |
| `.claude/guides/GUIDE_DASHBOARD.md` | widgets, dashboard, KPIs |
| `.claude/guides/GUIDE_MODULO_NUEVO.md` | crear un módulo |
| `.claude/guides/GUIDE_ENTES.md` | entes, estados, relaciones entre módulos, compartir, eventos y disparadores, chips y fichas ajenas |
| `.claude/guides/GUIDE_SYNC.md` | sincronización erp-app ↔ erp-cliente |
| `decisiones/<modulo>.md` | modificar `usuarios` o `auth` |
| `decisiones/global/` | `ui.md`: `components/ui/`, `globals.css` · `permisos.md`: permisos · `infra.md`: infraestructura |
| `db_schema/<modulo>.md` | leer o cambiar el esquema de ese módulo · `core.md`: usuarios y permisos |

---

# CHECKLIST DE CIERRE DE TAREA

1. `npx tsc --noEmit` — cero errores nuevos
2. Suite de tests, si existe — corre y pasa
3. ¿Tocaste tablas/enums? → `db_schema/<modulo>.md` + `database.types.ts` sincronizados
4. ¿Hay SQL sin correr? → archivo en `sql/` + avisar al usuario
5. ¿Decisión no obvia? → registrar en `decisiones/<modulo>`, en el archivo del tema (si el archivo o la sección son nuevos, sumarlos al `README.md` índice). ¿Decidida pero sin implementar? → `BACKLOG.md`
   - Formato corto: la decisión en una línea en negrita, el porqué en 1–3 líneas, los archivos que toca
   - Si superás una decisión ya escrita, tachá su título y reemplazá el cuerpo por el puntero a la nueva — el texto viejo queda en git
