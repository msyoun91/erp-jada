# Decisiones globales — Infraestructura

## `middleware.ts` → `proxy.ts` (Next.js 16)

Next 16 deprecó la convención `middleware.ts` en la raíz (`src/`) — se renombró a `proxy.ts` con función exportada `proxy` (no `middleware`). El archivo `src/lib/supabase/middleware.ts` (helper `updateSession`, nombre fijado por `GUIDE_DB.md`) no cambia — solo el entry point de Next en `src/proxy.ts` lo importa y expone.

**Por qué:** `erp-app/AGENTS.md` (autogenerado por `next dev`) advierte que esta versión de Next tiene breaking changes vs. el training data. Toda lógica de proxy/middleware futura va en `src/proxy.ts`, no crear `src/middleware.ts`.

## Dashboard = ruta `/`, no `/dashboard`

`/` ya estaba gateado por el proxy (redirect a `/login` si no hay sesión) y solo mostraba un placeholder estático fuera del grupo `(erp-app)` (sin sidebar). Se reemplazó `app/page.tsx` por `app/(erp-app)/page.tsx` con el dashboard real — mismo route, ahora dentro del grupo con sidebar. `SidebarNav` suma un ítem "Inicio" (`href: "/"`) siempre visible, sin gating por `modulosVisibles` (el dashboard no es un módulo con submódulos propios, es la landing).

**Por qué:** evitar una ruta `/dashboard` redundante cuando `/` ya cumplía el rol de landing autenticada.

## `usuario_widgets` — RLS directo, sin `service_role`

A diferencia de `usuarios`/`usuario_submodulos` (server actions con `service_role` porque la autorización pasa por `tiene_permiso`), el toggle de widgets es una preferencia estrictamente propia del usuario. RLS con `usuario_id = auth.uid()` alcanza para SELECT/INSERT/UPDATE — el server action de `modules/dashboard/actions.ts` usa el cliente normal (`lib/supabase/server.ts`), no cliente admin.

**Por qué:** usar `service_role` acá sería una elevación de privilegio innecesaria para un dato sin lógica de negocio — regla "simplicidad antes que abstracción". Precedente para futuros módulos: `service_role` solo cuando RLS no puede expresar la regla de autorización (ej: chequeos vía `tiene_permiso`), no por default en todo server action de escritura.

## `MobileNav` cierra el drawer durante el render, no en un efecto

El `useEffect(() => setOpen(false), [pathname])` que cerraba el drawer al navegar era el último
error de `react-hooks/set-state-in-effect` del repo: dejaba `npm run lint` en rojo. Pasó al patrón
que ya usan `TareaRow`, `HiloCard` y `CerrarHiloModal` — se guarda el `pathname` visto y se
reacciona al cambio durante el render.

## Sidebar: `Sidebar.tsx` (server) + `SidebarNav.tsx` (client) + `MobileNav.tsx` (client)

Portado el patrón de `erp-old-2`. `Sidebar.tsx` es server component: trae `nombre` (tabla `usuarios`, sin `avatar_url` — ese campo no existe en el schema nuevo, avatar es solo iniciales) y `modulosVisibles` (reusa `getUserSubmodulos()` de `lib/permissions`, ya cacheado). `SidebarNav.tsx` es un solo componente que sirve tanto al `<aside>` desktop como al drawer mobile (`MobileNav.tsx`) — incluye footer con iniciales + nombre + logout. Sin `grupo` (agrupación de nav) — con 2 módulos no hace falta, agregar cuando haya 3+.

`signOutAction` vive en `modules/auth/actions.ts` — sin `permissions.ts` porque ni entrar ni salir tienen gate de permiso. Sí hay `types.ts` desde que el login se valida en servidor (ver sección Auth).

**Dark mode:** `--brand-50`, `--brand-700` y `--neutral-100` (usados por `.nav-item-active` y `.badge-brand`) pasaron a ser custom properties en `:root`/`[data-theme="dark"]` (mismo patrón que `--bg-*`/`--text-*`) en vez de hex fijo en `@theme inline` — sin esto, el ítem de nav activo quedaba con el celeste claro del light mode también en dark.

## Notificaciones: infra sin submódulo, y sin motor (`sql/038`)

Pedido como "motor de notificaciones y sugerencia de tareas". Se construyó la mitad de
notificaciones; la de sugerencias no, y por qué está más abajo.

~~**No es un motor.**~~ — superado por `sql/055`: las plantillas disparadas por estado son un motor
de reglas chico, que cada usuario activa para sí. Ver `decisiones/tareas/plantillas.md` →
*Plantillas disparadas por estado*. Las notificaciones siguen siendo un `PERFORM notificar(...)`
por tipo.

**No es un módulo: no lleva submódulo.** Va donde `usuario_widgets` y `usuario_tutorial` — prefijo
`usuario_`, RLS directo por `auth.uid()`, sin vista ni permiso propio. Recibir el aviso de algo que
ya podés ver no necesita autorización nueva: el permiso lo puso la entidad apuntada. Un submódulo
`notificaciones_ver` habría sido un permiso que nadie puede negar sin romper la app.

**La notificación apunta, no copia** — la decisión que gobierna todo el resto. La fila guarda
`(entidad, entidad_id)` y el texto se arma al leer bajo la RLS del lector. Con el título copiado,
`sql/013` —perder la asignación es dejar de ver— se rompía desde la campanita. Por eso
`notificaciones_listar` es INVOKER y resuelve con INNER JOIN: lo que la RLS no devuelve, no aparece.
Verificado: sacarle la asignación al destinatario vacía su bandeja y la fila sigue existiendo.

**Evento es fila, estado es consulta.** "Te asignaron X" pasó una vez y tiene destinatario único.
"Tenés 3 vencidas" es el estado de hoy: como fila necesitaría un cron que la cree a medianoche y
otra pasada que la borre al completar la tarea. Es `notificaciones_avisos()`, mismo criterio que
`reactivar_posponer_vencidos()`. El ERP sigue sin cron.

**El badge cuenta lo no leído de la lista, no de la tabla.** Contar filas crudas daría un número más
alto que lo que se ve, porque las de entidades ya invisibles no se muestran. Los avisos de
vencimiento no suman al badge: un badge que no puede llegar a cero deja de significar algo.

**Dónde está la campanita.** Arriba a la derecha de las dos superficies de nav —el `<aside>` de
escritorio y la barra de `MobileNav`—, y **no** en el drawer: ahí estaría escondida detrás del botón
que hay que apretar para verla. Los datos los trae `Sidebar.tsx` (server) y se refrescan con la
navegación; sin polling ni Realtime hasta que alguien los pida.

**La sugerencia de tareas no se construyó.** "¿Qué hago ahora?" ya es la vista Misión más el orden de
`useOrdenTemperatura` — un sugeridor sería una segunda autoridad sobre la misma pregunta. "¿Qué
tarea debería existir?" sí es nueva, pero hoy una tarea no sabe de qué obra habla (`origen_app` /
`origen_punto` son texto libre y solo decorativos), así que la sugerencia no puede saber si ya la
creaste y la repetiría para siempre. Ese vínculo es el prerequisito, y es una columna, no un motor.
Queda en `BACKLOG.md`.

---

## La regla de negocio vive en Postgres, no en `actions.ts`

El módulo tareas ya funciona así de hecho: `validar_cierre_hilo`, `validar_responsable_tarea`, `validar_proyecto_tarea_miembros`, `validar_quitar_miembro_proyecto`, `reabrir_hilo_en_tarea`, `generar_recurrencia` y `log_evento_tarea` son triggers, y la visibilidad entera es RLS (`puede_ver_hilo`, `es_asignado_tarea`, `es_miembro_proyecto`, `tiene_permiso`). Se eleva a regla siempre activa en `CLAUDE.md`.

**Por qué:** la única superficie del sistema hoy son Server Actions, que no son API — el action-id es un identificador interno de Next que cambia en cada build, sin schema ni versionado. El día que entre un segundo consumidor (un agente IA, el portal `erp-cliente`, un job, una integración), ese consumidor no puede llamar `actions.ts`; entra por PostgREST/Supabase con su propio JWT. Toda regla que solo exista en TypeScript queda del lado equivocado de esa frontera y se convierte en una segunda autoridad — exactamente lo que prohíbe *Fuente única de verdad*. Una regla en trigger o constraint la obedecen los dos por construcción, sin duplicar nada.

Esto **no** es preparación para un agente IA. No se construye API, ni identidad de agente, ni tokens: sería arquitectura especulativa. Es solo dónde poner la lógica que igual hay que escribir.

~~**Deuda conocida, no se migra ahora:** la orquestación multi-tabla de `modules/tareas/actions.ts`.~~ **Saldada** por `sql/023`–`024` — ver `decisiones/tareas/escrituras-postgres.md`.

**Cómo se ve en la práctica:** `queries.ts:44` ya llama `supabase.rpc("reactivar_posponer_vencidos")`. Ese es el patrón: la función vive en `sql/`, `actions.ts` la invoca. `SECURITY INVOKER` por defecto para que RLS siga aplicando al llamador; `SECURITY DEFINER` solo si hace falta bypasear RLS, y ahí vale la regla ya registrada de `SET search_path = public`.

---

## El módulo comercial se elimina entero (`sql/026`)

Se fue todo el módulo, código y base (8 tablas, 6 enums, 6 funciones, 10 submódulos con sus
asignaciones); las 20 filas que había quedaron volcadas a JSON fuera del repo antes del DROP. El
inventario de lo borrado, en git (`sql/026`).

**No aplica "nunca DELETE" cuando desaparece un módulo entero.** La regla protege registros de un
módulo vivo; dejar tablas y submódulos con `activo = false` sería dejar el esquema y la grilla de
permisos hablando de algo que ya no existe. Antes del DROP: verificar cero FKs entrantes y cero
columnas usando sus enums, y reescribir —no dropear— las policies de otras migraciones que lo
mencionaban (acá, `usuarios_select`).

---

## `argsRpc()` — los tipos de argumentos de RPC dejaron de ser nulables

`erp-app/src/lib/supabase/rpc.ts`.

Al regenerar `database.types.ts` para el módulo obras, las llamadas `.rpc()` de tareas empezaron a fallar el typecheck: 16 errores por pasar `null` a argumentos declarados no-nulos (`crear_tarea`, `editar_tarea`, `crear_proyecto`, `editar_proyecto`).

**No es culpa del MCP ni del CLI.** `gen types --project-id` genera del lado del servidor: el CLI recién autenticado y el MCP producen byte por byte lo mismo, y el archivo commiteado antes traía `| null`. Supabase cambió el generador.

Los tipos son los que mienten: los parámetros SQL aceptan NULL, y PostgREST los exige **presentes** cuando no tienen `DEFAULT` — mandar `null` es lo correcto y omitirlos daría "missing parameter".

`argsRpc<"nombre_funcion">({...})` acota la corrección a un solo lugar y sigue chequeando nombre y tipo de cada campo (los admite como `T | null`). La alternativa era castear en cada llamada, que pierde el chequeo, o agregar `DEFAULT NULL` en SQL — que obliga a darle default a todos los parámetros posteriores de cada función.

Si el generador vuelve a emitir `| null`, se borra el helper y las llamadas quedan igual.

## ~~`erp-app/AGENTS.md` dice ser algo que no es~~ — superado el 2026-09-11

Decía que no existían ni `node_modules/next/dist/docs/` ni `generate-agent-files.js`. **Hoy existen
los dos** (Next 16.3.0), así que `AGENTS.md` vale: ante una duda de convenciones de Next, leer la
guía que corresponda en `erp-app/node_modules/next/dist/docs/` antes de escribir. Sigue siendo
cierto que `params` y `searchParams` son `Promise` y se esperan con `await` (ver
`app/(erp-app)/tareas/auditoria/page.tsx` y las rutas `[id]` de obras). El texto anterior, en git.

---

## `sql/035` — los advisors de Supabase, resueltos o descartados uno por uno

Barrido de los advisors de seguridad y performance (`sql/035_advisors_hardening.sql`, vía MCP). Lo
que sigue vigente:

- **`auth.uid()` va envuelto en `(select ...)` en toda policy.** Suelto, Postgres lo re-evalúa una
  vez por fila. Regla en `GUIDE_DB.md`.
- **Revocar `EXECUTE` a una trigger function no apaga el trigger** — verificado en la base: el
  privilegio se chequea al crear el trigger, no al dispararlo. Por eso se revocaron las cuatro
  trigger functions puras (`handle_new_user`, `handle_user_email_updated`, `obras_guard_congelado`,
  `obras_marcar_pendiente`). Las demás `SECURITY DEFINER` expuestas por RPC o chequean
  `tiene_permiso()` en la primera línea o son helpers que las policies necesitan llamar.
- **`tiene_permiso` sale de `anon` y se regrantea a `authenticated`.** Si alguna vez una policy se
  evalúa sin sesión, falla con `42501 permission denied for function tiene_permiso`, un error que no
  nombra la policy. Hoy no hay lectura anónima: el proxy manda a `/login` antes.
- **Sin tocar, a propósito:** los índices que el advisor marca sin uso (la base es joven) y *leaked
  password protection* (toggle del dashboard de Auth; salió de `BACKLOG.md` el 2026-09-14 sin
  activarse).
- **`sql/054`: `obras_buscar_duplicados_empresa` había quedado abierta a `anon`** desde `sql/042`,
  que la recreó con `DROP` + `CREATE` sin repetir el `REVOKE`. Las 55 `SECURITY DEFINER` que el
  advisor sigue listando para `authenticated` son las de arriba. Regla en `GUIDE_DB.md`.

Los tests de RLS se corrieron como un único `DO` que termina en `RAISE EXCEPTION`: un statement es
atómico, así que revierte aunque falle a la mitad. El detalle del barrido, en git.

---

## La documentación se lee por tema, no por archivo (2026-09-11)

Todo archivo leído queda en contexto el resto de la sesión y se reenvía en cada turno. Con la regla
"leer `decisiones/<modulo>.md` entero", una sesión de tareas que tocaba SQL cargaba ~50K tokens de
documentación (`decisiones/tareas.md` 112 KB + `db_schema.md` 77 KB) para usar una o dos secciones.

- **Carpeta con índice.** `decisiones/<modulo>/README.md` lista cada archivo con los títulos de sus
  secciones; se lee el índice y después solo los archivos que toca la tarea. `usuarios.md` y
  `auth.md` siguen sueltos porque son chicos. `db_schema/` sigue el mismo criterio: uno por módulo más
  `core.md`.
- **Lo superado se reduce a un puntero de una línea**; el texto original queda en git. Antes se
  conservaba entero después del tachado y los archivos solo crecían.
- **Las trampas que no son de un módulo** (RLS, forms, React Compiler) viven en las guías, no en la
  historia del módulo que las descubrió.
- **CLAUDE.md queda con lo que aplica a toda tarea**; lo que aplica solo a algunas se mudó a su guía
  (`GUIDE_DESIGN`, `GUIDE_PERMISSIONS`, `GUIDE_MODULO_NUEVO`).

Backup de todo lo anterior: `obsoletos/backup-docs-2026-09-11/`.
