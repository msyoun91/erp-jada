# Plan — Tareas: buscador por módulo, tareas en la ficha y compartir al asignar

Decidido con el usuario el 2026-09-14. **No implementado.** Escrito para que otro modelo lo ejecute
fase por fase. Cuando una fase se cierra, su decisión final va a `decisiones/` y la fase se tacha acá;
cuando se cierran todas, este archivo se borra (queda en git) y se saca el puntero de `BACKLOG.md`.

---

## Cómo usar este plan

- **Una fase por sesión, con `/clear` entre fases.** Orden: A → B → C → D → E. A y B no dependen de
  nada; C va antes que D, y D antes que E. E toca los mismos archivos que A, así que A va primero.
- **Antes de escribir, leer solo lo que dice "Leer antes"** de la fase (regla de CLAUDE.md: por tema,
  no por archivo). `erp-app/AGENTS.md`: esta versión de Next (16.3) difiere de lo que conocés; ante la
  duda, `erp-app/node_modules/next/dist/docs/`.
- **Premisas: verificar contra el código antes de construir.** Las líneas y firmas citadas son del
  2026-09-14. Si algo no coincide, corregir este plan primero y avisar.
- **SQL:** escribir el archivo en `sql/`, mostrárselo al usuario y aplicarlo con
  `mcp__supabase__apply_migration` solo con su OK. Los tests de `sql/tests/` no son migraciones:
  se corren con `mcp__supabase__execute_sql` pegando el archivo entero. Terminan en `RAISE EXCEPTION`
  y el resultado viene en el mensaje del error. Copiar el andamiaje de `sql/tests/vinculos_tareas.sql`
  (ADMIN `015fa985-…`, TESTER `48b90421-…`, `request.jwt.claims` + `role`).
- **Convenciones SQL** (ver `sql/059`): encabezado con el pedido y el puntero a `decisiones/`,
  `SET search_path = public`, `REVOKE EXECUTE … FROM PUBLIC` + `GRANT … TO authenticated` solo cuando
  hace falta. En una función con `RETURNS TABLE`, calificar toda columna que se llame igual que un
  campo de salida (bug de `sql/048`).
- **Cierre de cada fase** (CHECKLIST de CLAUDE.md): `npx tsc --noEmit` desde `erp-app/`, `npx eslint`
  sobre los archivos tocados, los `.test.ts` con `node --test` (ver `decisiones/tareas/codigo.md`),
  `db_schema/` y `database.types.ts` sincronizados (el repo lo sincroniza a mano: mismo formato que las
  entradas vecinas), `decisiones/` al día, avisar qué SQL quedó sin correr. Commit en master con el
  estilo del repo cuando el usuario lo pida.

---

## Decisiones del usuario (2026-09-14)

1. **Compartir al asignar** (texto original en `BACKLOG.md`): si un asignado no puede abrir lo
   vinculado, se ofrece compartirlo (solo lo que es de quien asigna). Regla única, a mano y en el
   disparo: **quien no puede abrirlo no queda asignado; si no queda nadie, la tarea va a quien asigna,
   con nota.** En el disparo se pregunta al guardar el cambio de estado, y cerrar el panel es no
   compartir.
2. **Relacionar** un registro con una tarea que ya existe aplica la misma regla: si un asignado no lo
   puede abrir y no se comparte, **se lo saca de la tarea**.
3. **Obra creada directamente en un estado que dispara:** no se puede preguntar antes (la obra no
   existe). Se aplica la regla y se avisa.
4. **"Nueva tarea" y abrir una tarea desde la ficha** de obra, empresa o persona: el formulario y el
   panel se abren **sobre la ficha**, sin ir a Tareas.
5. **Buscador de "Relacionar":** primero se elige el módulo y recién ahí aparecen los registros de ese
   módulo. El buscador entero queda detrás de un toggle.

## Correcciones al relevamiento de `BACKLOG.md` (verificadas contra el código)

- **`CompartirPanel` no se mueve a `components/`.** Importa las actions de Obras (`../actions`), y lo
  que Tareas necesita no es ese panel: ese elige destino y revoca. Lo que se comparte es un panel nuevo,
  que solo muestra y tilda, en `components/ui/`, más dos actions en `lib/`.
- **Compartir para una tarea no puede reusar `obras_compartir_obra`/`_empresa`.** Desde `sql/049` son
  "estado deseado": llamadas para un usuario que ya tiene la obra, apagan la cascada que no viene en el
  array. Además, re-tildar un grant directo le pisa el origen. Hace falta una función **aditiva**
  (Fase C).
- **"Vincular primero en `usar_plantilla`"** se resuelve pasando los vínculos del disparo a
  `crear_tarea` por `p_vinculos`, con su `plantilla_id` (Fase D). La policy ya exige
  `pg_trigger_depth() > 0` para esos.
- **Preguntar antes de un disparo sin copiar `usar_plantilla`:** un **ensayo** que hace el cambio de
  estado de verdad, junta a quién dejó afuera y revierte (Fase D). Simular la cuenta de asignados en
  otra función sería una segunda copia de la regla.
- **Quien asigna o relaciona no queda afuera nunca**, aunque no pueda abrir algo (un adjunto de rol que
  cargó un receptor, por ejemplo). Sin esto, el "si no queda nadie, va a quien asigna" podía caer en
  alguien que tampoco lo abre.
- **Sacar a otro de una tarea es asignar** (`tareas_asignar`, `sql/014`). Si relacionar deja a alguien
  afuera y quien relaciona no tiene la función, falla con `TA016` en vez de sacarlo.
- **`revalidatePath("/tareas")` no refresca la ficha.** Según la doc de Next 16, solo actualiza la UI
  si estás viendo esa ruta. Para la Fase B, las actions de Tareas suman `refresh()` de `next/cache`
  (`node_modules/next/dist/docs/01-app/03-api-reference/04-functions/refresh.md`).

---

## ~~Fase A — Buscador de "Relacionar" por módulo (`sql/061`)~~ — cerrada

Decisión final en `decisiones/tareas/integracion.md` → *El buscador de Relacionar elige módulo primero (`sql/061`)*. Pruebas manuales en `Pruebas de cambio en vinculos - Fase A.md`.

**Objetivo:** en el formulario y en el panel de una tarea, "Relacionar" es un toggle. Abierto, pide
elegir el módulo; sin módulo elegido no hay buscador ni resultados.

**Leer antes:** `decisiones/tareas/integracion.md` (§ *Tareas relacionadas…*), `db_schema/tareas.md`
(§ lecturas de `sql/059`), `sql/059` §5, `modules/tareas/components/RelacionarRegistro.tsx`,
`TareaFormPanel.tsx`, `TareaDetailPanel.tsx`, `Segmentado.tsx`, `modules/tareas/actions.ts`
(`buscarRegistros`), `modules/tareas/types.ts` (`buscarRegistrosSchema`), `modules/tareas/queries.ts`
(`getEntes`), `.claude/guides/GUIDE_DESIGN.md`.

### SQL — `sql/061_buscar_registros_por_modulo.sql`

- `DROP FUNCTION IF EXISTS buscar_registros(text);`
- `buscar_registros(p_modulo text, p_texto text)`, con la misma salida
  `(ente, registro_id, etiqueta, detalle, href)`. `plpgsql STABLE SECURITY INVOKER`: la RLS y
  `obras_buscar` siguen decidiendo, como en `sql/059`. Cuerpo: `IF p_modulo = 'obras' THEN RETURN
  QUERY <el SELECT de sql/059>; END IF;`. El comentario dice que un módulo que registre entes suma su
  rama, igual que `relacionados_de_registro` (`sql/060`).
- `REVOKE`/`GRANT EXECUTE` con la firma nueva.
- La lista de módulos no necesita SQL: sale de `entes` bajo RLS.

### Código

1. `types.ts`: `buscarRegistrosSchema` pasa a
   `z.object({ modulo: z.string().min(1).max(50), texto: z.string().trim().min(2).max(100) })`.
2. `queries.ts`: `getModulosRelacionables(): Promise<string[]>`. Es `select("modulo")` sobre `entes`,
   sin repetidos. La RLS de `entes` ya deja solo los módulos cuyo submódulo tenés.
3. `actions.ts`: `buscarRegistros(modulo, texto)` valida y llama a la RPC nueva.
   `modulosRelacionables()` envuelve la query, como `relacionesCompartiblesObra` en Obras.
4. `RelacionarRegistro.tsx` **pasa a tener su propio toggle** (una sola fuente para el form y el panel):
   - Botón "Relacionar"/"Cerrar" con `Link2`, con las clases que hoy tiene en `TareaDetailPanel`.
   - Al abrir por primera vez, carga los módulos en el `onClick` (no en un efecto:
     `react-hooks/set-state-in-effect`).
   - Abierto: `Segmentado` con un botón por módulo (label de `LABEL_MAP`, importado de
     `@/components/layout/SidebarNav`, como ya hace `PermisosModal`). Arranca **sin módulo elegido**:
     `valor=""`, ningún botón presionado. Sin módulos: *"No tenés acceso a ningún módulo con registros
     para relacionar."*
   - Con módulo elegido aparece el `SearchInput` (placeholder `Buscar en {label}…`). Cambiar de módulo
     limpia el texto y los resultados. El debounce depende de `[modulo, consulta]`.
   - Elegir un resultado llama a `onElegir`, limpia el texto y cierra el toggle.
5. `TareaDetailPanel.tsx`: sacar `relacionando` y su botón, y poner `<RelacionarRegistro>` debajo de
   la fila de chips. `relacionar()` ya no toca ese estado.
6. `TareaFormPanel.tsx`: el bloque "Relacionada con" queda chips + `<RelacionarRegistro>`, que ya trae
   el toggle.

### Tests y docs

- `sql/tests/vinculos_tareas.sql`: sumar casos. `buscar_registros('obras', <nombre de la obra propia>)`
  la encuentra; `buscar_registros('otro', …)` devuelve 0 filas; la obra ajena no aparece. Actualizar el
  "Último resultado".
- `db_schema/tareas.md` (firma de `buscar_registros`), `database.types.ts` (Args), y en
  `decisiones/tareas/integracion.md` una sección nueva: *El buscador de Relacionar elige módulo primero
  (`sql/061`)*.

### Pruebas manuales

1. Nueva tarea → "Relacionada con": se ve solo el botón Relacionar.
2. Tocarlo: aparece "Agenda de Obras" sin presionar y ningún buscador.
3. Elegir el módulo: aparece el buscador. Escribir 2 letras: resultados de obras, empresas y personas.
4. Elegir uno: aparece el chip y el toggle se cierra.
5. Lo mismo desde el panel de una tarea.

---

## Fase B — Nueva tarea y panel de la tarea sobre la ficha (sin SQL)

**Objetivo:** en la ficha de obra, empresa y persona, "Nueva tarea" abre `TareaFormPanel` y cada tarea
abre su panel **ahí mismo**. Al guardar o cerrar se sigue en la ficha y la lista se actualiza.

**Leer antes:** `decisiones/tareas/integracion.md` (§ *Tareas relacionadas…* y § *Deep link…*),
`decisiones/obras/ui.md` (§ *La sección Tareas de las fichas*), `app/(erp-app)/obras/[id]/page.tsx`,
`obras/empresas/[id]/page.tsx`, `obras/personas/[id]/page.tsx`, `modules/obras/components/ObraDetalle.tsx`,
`EmpresaDetalle.tsx`, `PersonaDetalle.tsx`, `TareasRelacionadas.tsx`, `modules/obras/queries.ts`
(`getTareasDeRegistro`), `modules/obras/permissions.ts` (`puedeVerTareas`),
`modules/tareas/queries.ts`, `modules/tareas/actions.ts`, `TareaCard.tsx`, `TareasListaView.tsx`,
`app/(erp-app)/tareas/page.tsx` y las otras tres pages de Tareas, `tareasContexto.tsx`,
`cadenaPasos.ts`, `lib/tareas.ts`, `refresh.md` y `revalidatePath.md` de la doc de Next.

**Cómo no rompe "los módulos no se importan":** la composición va en `app/`. La page de la ficha
importa el componente de `modules/tareas` y se lo pasa a `ObraDetalle` como `ReactNode`. Obras deja de
saber de Tareas (hoy importa `@/lib/tareas` y tiene `getTareasDeRegistro`/`puedeVerTareas`).

### Código

1. **`modules/tareas/queries.ts`**
   - `getTareasContexto(): Promise<TareasContexto>` junta los seis valores (`usuarios`, `proyectos`,
     `miembrosPorProyecto`, `usuarioActualId`, `gestionarAjenas`, `puedeAsignar`). Reemplazar el armado
     repetido en `tareas/page.tsx`, `mision/page.tsx`, `proyectos/page.tsx` y `plantillas/page.tsx`
     donde sea idéntico: verificar cada una.
   - Extraer de `getListaTareas` el string del `select` y el mapeo de notas y vínculos (filtro `activo`,
     orden, `vinculos` por `tarea_id`) a una constante y una función privadas del archivo, para que
     `getListaTareas` y la query nueva usen las mismas.
   - `getTareasDeRegistro(ente, registroId): Promise<{ tareas: TareaConAsignados[]; delHilo:
     TareaConAsignados[]; hilos: TareaHilo[] }>`:
     - llama a `reactivar_posponer_vencidos` (como la Lista);
     - usa `rpc("tareas_de_registro")` solo por los ids y el orden, que ya pone lo terminado al final;
     - trae esas tareas con el `select` compartido y `vinculos_de_tareas()`;
     - con los `hilo_id` distintos, trae las tareas activas de esos hilos (para `cadenasDePasos`) y los
       hilos (para `proyecto_id`);
     - devuelve las tareas en el orden de la RPC.
   - `getRegistro` **se queda**: da la etiqueta y la ruta con `etiqueta_registro` y `entes.ruta`, sin
     escribir rutas a mano.
2. **Nuevo `modules/tareas/components/TareasDeRegistro.tsx`** (`"use client"`)
   - Props: `{ contexto: TareasContexto; registro: RegistroElegido; tareas; delHilo; hilos }`.
   - Envuelve en `TareasContextoProvider`. Encabezado igual al de `TareasRelacionadas` (h3 "Tareas",
     botón secundario "Nueva tarea", `empty-state`).
   - Cada tarea es una `TareaCard` (isla + panel, estado optimista incluido, sin copiar ese cableado),
     con `cadena={cadenasDePasos(delHilo).get(t.id)}` y `proyectoHeredadoId` = `proyecto_id` de su hilo.
     Sin `hilosDisponibles` ni `onConvertida`: desde la ficha no se mueve de hilo.
   - "Nueva tarea" monta `<TareaFormPanel vinculosIniciales={[registro]} onClose={…} />`.
3. **`modules/tareas/actions.ts`**: helper privado `revalidarTareas()` que hace
   `revalidatePath("/tareas")` + `refresh()`. Reemplaza las 34 llamadas a `revalidatePath("/tareas")`;
   las que revalidan otras rutas se quedan como están. Verificar en el navegador (pestaña Network) que
   en la Lista no se dispare un refresh doble. Si se dispara, dejar solo `refresh()` en las actions que
   se usan desde la ficha y anotar por qué.
4. **Las tres pages de ficha**: `puedeVerTareas()` pasa a `puedeVerLista()` de
   `@/modules/tareas/permissions`. Si da true, en el mismo `Promise.all` van `getTareasContexto()`,
   `getTareasDeRegistro(ente, id)` y `getRegistro(ente, id)`. Se le pasa
   `seccionTareas={<TareasDeRegistro …/>}` (o `null`) al componente de detalle.
5. **`ObraDetalle`/`EmpresaDetalle`/`PersonaDetalle`**: el prop `tareas: TareaRelacionada[] | null`
   pasa a `seccionTareas: React.ReactNode` y se renderiza donde hoy está `<TareasRelacionadas>`. Sacar
   los imports.
6. **Borrar lo que queda muerto:**
   - `modules/obras/components/TareasRelacionadas.tsx`, `getTareasDeRegistro` de `obras/queries.ts` y
     `puedeVerTareas` de `obras/permissions.ts`.
   - `TareaRelacionada` de `lib/tareas.ts`. Si después de eso `LABEL_ESTADO_TAREA`/`BADGE_ESTADO_TAREA`
     no se usan fuera de `modules/tareas` (grep), vuelven a `tareaLabels.ts` y `lib/tareas.ts` se borra.
   - El `?nueva=`: el parseo de `searchParams` y `getRegistro` en `tareas/page.tsx`; `nuevaDesde`,
     `volverA` y `vinculosNueva` en `TareasListaView`, y el `p.delete("nueva")`.
   - `?tarea=` se queda (lo usa la campanita). Pero la rama "tarea ajena arranca sin recorte" de
     `asignadoId` y su comentario en `HiloCard` existían por los links de la ficha: la notificación
     solo avisa al asignado. Sacarlos y ajustar los comentarios.

### Docs

- `decisiones/tareas/integracion.md`: tachar en § *Tareas relacionadas…* el párrafo "Obras no importa
  Tareas… Descartado: montar `TareaFormPanel` en la ficha" y dejar el puntero. Sección nueva *Las
  tareas de una ficha se abren sobre la ficha (sin SQL)*: composición en `app/` por `ReactNode`,
  `TareaCard` reusada, `refresh()` y por qué, `?nueva=` retirado, `getTareasContexto` como fuente
  única.
- `decisiones/obras/ui.md` § *La sección Tareas de las fichas*: la forma nueva.
- `db_schema/tareas.md`: `tareas_de_registro` sigue igual. Aclarar solo si cambió quién la usa.

### Pruebas manuales

1. Ficha de una obra → Nueva tarea: el form abre sobre la ficha con la obra como chip.
2. Crear: la tarea aparece en la sección sin salir de la ficha.
3. Tocar la tarea: abre su panel. Completarla: el badge cambia. Cerrar: se sigue en la ficha.
4. Un paso de hilo bloqueado muestra "Bloqueada" y no ofrece Completar.
5. Empresa y persona: lo mismo.
6. Usuario sin `tareas_lista`: la sección no aparece.
7. La campanita "te asignaron X" sigue abriendo la tarea en `/tareas`.

---

## Fase C — Quién puede abrir un registro, preguntado por usuario (`sql/062`)

**Objetivo:** que la base conteste "¿el usuario U puede abrir el registro R?" y "¿puedo compartírselo?"
sin copiar la visibilidad de Obras, y que compartir para una tarea sea aditivo.

**Leer antes:** `BACKLOG.md` (entrada *Compartir al asignar*), `decisiones/obras/visibilidad.md`
(MODEL A, `sql/047`, `049`, `052`), `db_schema/core.md` (`entes`, `tiene_permiso`, `etiqueta_registro`),
`db_schema/obras.md` (§ grants y helpers), `sql/020` (`tiene_permiso`), `sql/039` §5,
`sql/047` §3, §5 y §7, `sql/049`, `sql/059` §2, `.claude/guides/GUIDE_DB.md`.

**Antes de tocar nada:** correr **todos** los tests de `sql/tests/` y anotar el resultado de cada uno
(línea base). `tiene_permiso` está en casi todas las policies.

### SQL — `sql/062_acceso_por_usuario.sql`

Todas las funciones son `SECURITY DEFINER STABLE` salvo que se diga otra cosa. "Sin GRANT" quiere decir
`REVOKE FROM PUBLIC` y nada más: solo las llaman otras DEFINER.

1. **`usuario_tiene_permiso(p_usuario uuid, p_codigo text)`**, sin GRANT: el cuerpo actual de
   `tiene_permiso` con `p_usuario` en vez de `auth.uid()`. `tiene_permiso(p_codigo)` pasa a
   `SELECT public.usuario_tiene_permiso(auth.uid(), p_codigo)`, con misma firma, misma seguridad y
   grants intactos.
2. **`obras_puede_ver_obra_de(p_obra_id, p_usuario)`, `obras_puede_ver_empresa_de(p_empresa_id,
   p_usuario)`, `obras_puede_ver_persona_de(p_persona_id, p_usuario)`**, sin GRANT: los cuerpos
   vigentes (`sql/047` §3 y `sql/039` §5) con `auth.uid()` → `p_usuario` y `tiene_permiso(x)` →
   `usuario_tiene_permiso(p_usuario, x)`. Las tres actuales quedan como envoltorios de una línea con
   `auth.uid()`. **No tocar** las policies inline (`obras_empresas_select`, `obras_select`): el porqué
   está en `sql/039`.
3. **`obras_puede_abrir(p_tipo text, p_id uuid, p_usuario uuid)`**, sin GRANT: un `CASE` por tipo que
   llama a las tres de arriba. El grant contextual no cuenta, porque el chip abre la ficha sin contexto.
4. **`puede_abrir_registro(p_ente text, p_id uuid, p_usuario uuid)`**, sin GRANT:
   `COALESCE((SELECT e.activo AND usuario_tiene_permiso(p_usuario, e.submodulo) AND CASE e.modulo WHEN
   'obras' THEN obras_puede_abrir(e.codigo, p_id, p_usuario) END FROM entes e WHERE e.codigo = p_ente),
   false)`. Es la misma puerta que la ruta de la ficha: submódulo del ente más la fila. Un módulo que
   registre entes suma su rama, como en `etiqueta_registro`.
5. **`queda_afuera(p_usuario uuid, p_ente text, p_id uuid)`**, sin GRANT:
   `p_usuario IS DISTINCT FROM auth.uid() AND NOT puede_abrir_registro(p_ente, p_id, p_usuario)`.
   **Único predicado de la regla**, con quien actúa exento.
6. **`obras_puede_compartir(p_tipo text, p_id uuid)`**, sin GRANT: que sea de quien llama. Obra:
   `responsable_id = auth.uid() AND activo`. Empresa y persona: `creado_por = auth.uid() AND activo AND
   NOT pendiente`. Son los mismos cortes que `OB026`/`OB020` en las `obras_compartir_*`.
7. **`puede_compartir_registro(p_ente text, p_id uuid, p_usuario uuid)`**, sin GRANT: `p_usuario <>
   auth.uid()`, usuario activo, ente activo, `usuario_tiene_permiso(p_usuario, e.submodulo)` (sin el
   submódulo, compartir no le abre nada) y la rama del módulo → `obras_puede_compartir`.
8. **`asignados_con_acceso(p_asignados uuid[], p_vinculos jsonb) RETURNS uuid[]`**, **GRANT
   authenticated** (la llaman `crear_tarea`/`sincronizar_asignados`, que son INVOKER). Devuelve
   `p_asignados` en su orden (`WITH ORDINALITY`) sin los que `queda_afuera` de algún elemento
   `{ente, registro_id}` de `p_vinculos`.
9. **`sin_acceso(p_pares jsonb)`**, **GRANT authenticated**. Recibe `[{usuario_id, ente,
   registro_id}]` y devuelve `TABLE (usuario_id uuid, usuario text, ente text, registro_id uuid,
   etiqueta text, compartible boolean)`: los pares distintos donde `queda_afuera`, ordenados por
   usuario y etiqueta.
   - `usuario` sale de `usuarios.nombre`.
   - `etiqueta = CASE WHEN puede_abrir_registro(ente, id, auth.uid()) THEN etiqueta_registro(ente, id)
     END`. **El `CASE` es obligatorio:** adentro de una DEFINER, `etiqueta_registro` corre sin la RLS
     de quien llama y devolvería el nombre de lo que no ve.
   - `compartible = puede_compartir_registro(…)`.
10. **`obras_compartir_registros(p_usuario uuid, p_registros jsonb)`** (`[{ente, registro_id}]`, todos
    de obras). DEFINER, **GRANT authenticated**, **aditiva**.
    - Cortes: `OB021` (a vos mismo), `OB023` (usuario inactivo); `OB026` si una obra no es tuya y
      `OB020` si una empresa o persona no es tuya, con los textos existentes.
    - Obra: upsert en `obras_obra_compartida`.
    - Empresa o persona: upsert en `obras_empresa_compartida`/`obras_persona_compartida` con
      `origen_obra_id` = una obra tuya y activa, vinculada activamente a esa entidad
      (`obras_obra_empresa`/`obras_obra_persona`), que quede compartida con `p_usuario` (en esta llamada
      o de antes). Si no hay ninguna, directo (`origen_obra_id` y `origen_empresa_id` NULL). Así se
      comporta como el checklist de Obras: se revoca junto con la obra.
    - Todos los upsert: `ON CONFLICT (…) DO UPDATE SET activo = true, otorgada_por = auth.uid(),
      updated_at = now(), origen_… = EXCLUDED.origen_… WHERE NOT <tabla>.activo`. Un grant activo **no
      se toca**: no se le cambia el origen ni se apaga ninguna cascada.
11. **`compartir_registros(p_selecciones jsonb)`** (`[{usuario_id, ente, registro_id}]`), `SECURITY
    INVOKER`, **GRANT authenticated**. Agrupa por usuario y por `entes.modulo` y llama a
    `obras_compartir_registros`. Un módulo nuevo suma su rama.

**Exposición aceptada (registrarla en `decisiones/`):** `asignados_con_acceso` y `sin_acceso` dejan
preguntar si otro usuario puede abrir un id que conocés. No devuelven el nombre de lo que no ves
(`CASE` del punto 9), y los ids son uuid: el dato suelto no vale nada.

### Tests — `sql/tests/acceso_registros.sql` (nuevo)

01 `tiene_permiso` contesta igual que antes, para ADMIN y para TESTER sin el submódulo ·
02 obra de ADMIN: `puede_abrir_registro` da true para ADMIN y false para TESTER ·
03 tras `obras_compartir_obra` a TESTER, true ·
04 compartida pero TESTER sin `obras_ver` (desactivado en la transacción): false y `compartible` false ·
05 persona de ADMIN tildada en el checklist de la obra: true ·
06 un grant contextual solo no alcanza ·
07 `sin_acceso` llamado por TESTER sobre un registro que no ve: fila con `etiqueta` NULL ·
08 `asignados_con_acceso` conserva el orden y no saca a quien llama ·
09 `obras_compartir_registros` sobre un grant directo activo: sigue con origen NULL ·
10 sobre una obra ya compartida con cascada: la cascada sigue activa ·
11 persona vinculada a una obra que se comparte en la misma llamada: `origen_obra_id` = esa obra ·
12 no dueño → `OB026`/`OB020` ·
13 `compartir_registros` reparte por usuario.

**Después:** volver a correr todos los tests. Tienen que dar lo mismo que la línea base.

### Docs

- `db_schema/core.md`: `usuario_tiene_permiso` (y `tiene_permiso` como envoltorio),
  `puede_abrir_registro`, `queda_afuera`, `puede_compartir_registro`, `asignados_con_acceso`,
  `sin_acceso` y `compartir_registros`.
- `db_schema/obras.md` § Helpers: las `_de`, `obras_puede_abrir`, `obras_puede_compartir` y
  `obras_compartir_registros`.
- `decisiones/obras/visibilidad.md`: *La visibilidad se pregunta por usuario (`sql/062`)* y *Compartir
  para una tarea es aditivo*.
- `decisiones/global/permisos.md`: una línea sobre `usuario_tiene_permiso`.
- `database.types.ts`: las funciones con GRANT.

---

## Fase D — La regla al asignar, relacionar y disparar (`sql/063`)

**Objetivo:** la regla vive en la base y cubre todos los caminos: crear, editar, reasignar, relacionar
y el disparo. Suma un ensayo del cambio de estado de una obra y el aviso de que alguien quedó afuera.

**Leer antes:** Fase C (lo que quedó en `db_schema/core.md`), `decisiones/tareas/visibilidad.md`
(`sql/014`), `decisiones/tareas/plantillas.md` (disparo y roles),
`decisiones/tareas/escrituras-postgres.md`, `db_schema/tareas.md`, `db_schema/notificaciones.md`,
`sql/059` §3–4, `sql/024` §1–3, `sql/053` (`editar_tarea`, `es_siembra_tarea`), `sql/060` §4–5,
`sql/056` (las tres funciones; `notificaciones_listar` en su última versión),
`sql/tests/plantillas_disparo.sql`, `lib/utils.ts` (`MENSAJES_ERROR`),
`modules/notificaciones/components/NotificacionesBell.tsx`.

### SQL — `sql/063_asignar_con_acceso.sql`

**§1 (aplicar sola, antes del resto, como en `sql/056`):**
`ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'plantilla_sin_acceso';`

**§2 Registro de la transacción.**
- `registrar_sin_acceso(p_tarea_id uuid, p_usuarios uuid[], p_vinculos jsonb)`, INVOKER, GRANT
  authenticated: suma `{tarea_id, usuario_id, ente, registro_id}` por cada usuario × vínculo al GUC
  local `tareas.sin_acceso` (`set_config(…, true)`).
- `sin_acceso_registrado() RETURNS jsonb`: `COALESCE(NULLIF(current_setting('tareas.sin_acceso',
  true), ''), '[]')::jsonb`.

Nadie más escribe ese GUC. Un bloque `EXCEPTION` que revierte también revierte lo registrado.

**§3 `crear_tarea`** (misma firma que `sql/059`):
- Los elementos de `p_vinculos` pueden traer `plantilla_id` (el disparo). El INSERT de vínculos lo
  copia, y la policy sigue exigiendo `pg_trigger_depth() > 0` para esos.
- **Antes del INSERT de `tareas`:**
  - `v_asignados := asignados_con_acceso(p_asignados, p_vinculos)`;
  - `v_fuera` = los de `p_asignados` que no quedaron;
  - si `v_asignados` quedó vacío: `ARRAY[auth.uid()]` y `v_vacio`;
  - `v_responsable` = `p_responsable_id` si quedó; si no, `auth.uid()` si está; si no, `v_asignados[1]`.
- Orden de los INSERT: tarea (con `v_responsable`), vínculos, asignados (`v_asignados`).
- Si hay `v_fuera`: `registrar_sin_acceso(v_id, v_fuera, p_vinculos)`.
- Si `v_vacio`: nota de `auth.uid()`, `'Quedó asignada a vos: %s no pueden abrir lo relacionado con esta
  tarea.'` con los nombres. **La nota no nombra el registro:** la leen quienes ven la tarea, vean o no
  la obra.

**§4 `sincronizar_asignados`** (misma firma):
- `v_vinculos` = los vínculos activos de la tarea como jsonb. La RLS de `tareas_vinculos` los deja ver
  porque quien edita ve la tarea.
- `v_quedan := asignados_con_acceso(p_asignados, v_vinculos)`, y `v_fuera`.
- Si hay `v_fuera` y `NOT tiene_permiso('tareas_asignar')`: `RAISE … USING ERRCODE = 'TA016'`.
- Vacío → `ARRAY[auth.uid()]` + `v_vacio`.
- El early return compara `v_previos` contra `v_quedan` ordenado, no contra `p_asignados`.
- Desactivar e insertar como hoy, con `v_quedan`.
- Si el responsable no quedó: `UPDATE tareas SET responsable_id = <auth.uid() si quedó, si no
  v_quedan[1]> WHERE id = p_tarea_id AND NOT (responsable_id = ANY (v_quedan))`.
- `registrar_sin_acceso` y la nota, como en §3.

**§5 `vincular_tarea(p_tarea_id uuid, p_ente text, p_registro_id uuid) RETURNS void`**, INVOKER,
GRANT authenticated:
- INSERT del vínculo sin plantilla (la policy decide).
- Si la tarea tiene asignados activos: `PERFORM sincronizar_asignados(p_tarea_id, <los activos>)`. Sin
  asignados no se llama: si no, relacionar asignaría a quien relaciona.
- Reemplaza el INSERT directo de la action `vincularTarea`.

**§6 `usar_plantilla`** (misma firma; lo demás igual a `sql/060`): con `p_ente`, armar antes de
`crear_tarea` el jsonb con el registro más los adjuntos (DISTINCT), cada uno con
`plantilla_id = v_p.id`, y pasarlo como `p_vinculos`. Borrar los dos INSERT a `tareas_vinculos` que hoy
van después. El `v_vacio` propio de la plantilla no cambia: ese caso ya asigna a `v_uid`, que está
exento, así que no hay nota doble.

**§7 `notificar_disparo`:** `DROP FUNCTION notificar_disparo(uuid, boolean)` y recrearla con
`p_sin_acceso boolean DEFAULT false`. El tipo sale de `NOT p_corrio` → `plantilla_fallida`; si no,
`p_sin_acceso` → `plantilla_sin_acceso`; si no, `plantilla_disparada`. Mismo resguardo
(`pg_trigger_depth() = 0` → nada) y mismos grants. Las llamadas de dos argumentos de
`plantillas_disparo.sql` siguen andando.

**§8 `disparar_plantillas`** (lo demás igual a `sql/060`): antes de cada `usar_plantilla`,
`v_antes := jsonb_array_length(sin_acceso_registrado())`; después,
`notificar_disparo(v_pl, true, jsonb_array_length(sin_acceso_registrado()) > v_antes)`. **No resetear el
GUC:** el ensayo necesita lo de todas las plantillas.

**§9 `notificaciones_listar`** (partir de la última versión): `plantilla_sin_acceso` va por la misma
rama que `plantilla_disparada` (`destino = 'tareas'`).

**§10 `obras_ensayar_estado(p_obra_id uuid, p_estado estado_obra, p_motivo_perdida motivo_perdida,
p_detalle_perdida text)`**, INVOKER (el disparo exige `current_user = 'authenticated'`), GRANT
authenticated, con la misma salida que `sin_acceso`:
- Adentro de un bloque `BEGIN … EXCEPTION WHEN SQLSTATE 'TA017' THEN NULL; END`:
  - `UPDATE obras SET estado, motivo_perdida, detalle_perdida … WHERE id = p_obra_id AND estado IS
    DISTINCT FROM p_estado`;
  - si hubo fila, `v_pares := sin_acceso_registrado()` (las variables plpgsql sobreviven al rollback del
    bloque);
  - `RAISE EXCEPTION USING ERRCODE = 'TA017'`.
- Después: `RETURN QUERY SELECT * FROM sin_acceso(<v_pares proyectado a {usuario_id, ente,
  registro_id}>)`.
- Cualquier otro error (RLS, CHECK de pérdida) sube tal cual.
- Se revierte todo: tareas, vínculos, avisos, auditoría.
- Motivo y detalle viajan porque el CHECK `obras_perdida_con_motivo` rechazaría el ensayo de "Perdida"
  sin motivo.

**§11 GRANTs** como en `sql/059` §6.

`TA017` nunca sale de la función, así que no va a `MENSAJES_ERROR`. **`TA016`** sí:
*"Alguien asignado no puede abrir lo relacionado y no tenés permiso para sacarlo de la tarea:
compartíselo o pedile a quien pueda asignar."*

### Tests — `sql/tests/asignar_con_acceso.sql` (nuevo)

01 `crear_tarea`: el asignado que no abre la obra queda afuera y el que la abre queda ·
02 nadie la abre: queda quien crea, como responsable y con nota ·
03 quien crea nunca queda afuera ·
04 un vínculo con `plantilla_id` fuera de un trigger falla ·
05 `editar_tarea` sumando a alguien sin acceso: no queda, sin error ·
06 `editar_tarea` sin cambiar asignados, con uno que perdió el acceso: no toca nada ·
07 `vincular_tarea`: el asignado sin acceso sale y el responsable se corrige ·
08 `vincular_tarea` sin `tareas_asignar` dejando a alguien afuera: `TA016` y el vínculo no queda ·
09 disparo con un paso para alguien sin acceso: no queda, y quien disparó recibe `plantilla_sin_acceso` ·
10 disparo: el vínculo con `plantilla_id` está y los asignados también ·
11 `obras_ensayar_estado` devuelve el par y no deja nada (0 tareas nuevas, 0 avisos, estado sin
cambiar) ·
12 tras `compartir_registros`, el cambio de estado real deja al asignado.

Volver a correr `vinculos_tareas`, `plantillas`, `plantillas_disparo`, `plantillas_roles`,
`atomicidad_tareas`, `atomicidad_edicion_tareas`, `origen_heredado`, `rls_visibilidad_tareas` y
`rls_miembros_asignables`. Si alguno cambia, explicar por qué antes de tocar el test.

### Código y docs

- `modules/tareas/actions.ts`: `vincularTarea` pasa a `rpc("vincular_tarea")`.
- `lib/utils.ts`: `TA016`.
- `NotificacionesBell.tsx`: ícono, texto (*"Se crearon tareas con tu plantilla; alguien quedó afuera
  porque no puede abrir lo relacionado"*) y color de `plantilla_sin_acceso`, junto a
  `plantilla_disparada`.
- `database.types.ts`: enum, `vincular_tarea`, `obras_ensayar_estado`, `notificar_disparo`.
- `db_schema/tareas.md` (`crear_tarea`, `sincronizar_asignados`, `vincular_tarea`, `usar_plantilla`,
  disparo, `TA016`), `db_schema/notificaciones.md` (tipo y firma), `db_schema/obras.md` (ensayo).
- `decisiones/tareas/visibilidad.md`, sección nueva *Quien no puede abrir lo relacionado no queda
  asignado (`sql/063`)*: regla única en `crear_tarea` y `sincronizar_asignados`, quien actúa exento,
  `TA016`, Relacionar saca, la obra nueva aplica la regla y avisa, ensayo con rollback en vez de copiar
  la cuenta de `usar_plantilla`, y la nota que no nombra el registro.

---

## Fase E — La pregunta en la UI: Tareas y Obras

**Objetivo:** antes de guardar, si alguien va a quedar afuera, un panel ofrece compartir lo que es tuyo.
Cerrarlo es no compartir.

**Leer antes:** `.claude/guides/GUIDE_DESIGN.md`, `decisiones/global/ui.md`, lo que dejaron C y D en
`decisiones/`, `components/ui/RightPanel.tsx`, `components/ui/Modal.tsx`,
`modules/obras/components/CompartirPanel.tsx` (solo como referencia visual del checklist),
`TareaFormPanel.tsx`, `ReasignarPanel.tsx`, `TareaDetailPanel.tsx`, `ObraFormPanel.tsx`,
`modules/obras/actions.ts` (`editarObra`) y `modules/obras/types.ts` (`editarObraSchema`).

### Código

1. **`lib/accesos.ts`** (`"use server"`, primera action en `lib/`: la usan dos módulos). Exporta solo
   funciones async y tipos.
   - `type FilaSinAcceso = { usuario_id; usuario; ente; registro_id; etiqueta: string | null;
     compartible: boolean }`.
   - `sinAcceso(pares)`: zod (array de `{usuario_id uuid, ente, registro_id uuid}`, máx. 200) →
     `rpc("sin_acceso")` → `{ success, filas } | { success: false, error }`.
   - `compartirRegistros(selecciones)`: zod → `rpc("compartir_registros")` → `{ success } | { error }`.
2. **`components/ui/CompartirAccesoPanel.tsx`** (`"use client"`) exporta el hook
   **`useConfirmarAcceso({ verbo: "guardar" | "relacionar", puedeDejarAfuera: boolean })`** →
   `{ confirmarAcceso(filas, seguir: (aviso: string | null) => Promise<void>), panelAcceso }`.
   - Sin filas: `seguir(null)` directo.
   - Con `!puedeDejarAfuera` y alguna fila no compartible: `toast.error` con el texto de `TA016`, sin
     panel.
   - Si no, abre un `RightPanel` titulado *"Antes de {verbo}"* y agrupado por usuario ("Ana no puede
     abrir:"):
     - una fila compartible es un checkbox tildado por defecto con `{ENTES[ente].nombre} {etiqueta}`;
     - una no compartible va deshabilitada: *"No lo podés compartir"*, o *"Algo relacionado que no
       podés ver"* si `etiqueta` es NULL;
     - leyenda: *"Quien no pueda abrir lo relacionado no queda asignado. Compartir da lectura y se
       revoca desde la ficha."*
   - Footer:
     - primario "Compartir y {verbo}": llama a `compartirRegistros(tildadas)`; si falla, toast y el
       panel sigue abierto; si anda, `seguir(aviso(resto))`;
     - secundario "{Verbo} sin compartir", solo con `puedeDejarAfuera`: `seguir(aviso(todas))`;
     - con `!puedeDejarAfuera`, el primario exige todas tildadas.
   - **Cerrar** (X, Escape, backdrop): con `puedeDejarAfuera` es lo mismo que "sin compartir"; sin él,
     cancela.
   - `aviso(filas)` = `"No quedan asignados: Ana, Juan — no pueden abrir lo relacionado."`, o null.
3. **`TareaFormPanel`**
   - `onSubmit` arma los pares: asignados (menos `usuarioActualId`) × vínculos. Al crear, los vínculos
     son `data.vinculos`. Al editar, `tarea.vinculos`, y solo si cambió el conjunto de asignados (mismo
     criterio que el early return).
   - Sin pares: guarda. Con pares: `sinAcceso` → `confirmarAcceso(filas, guardar)`, con
     `verbo: "guardar"` y `puedeDejarAfuera: true` (poner a otros ya exige `puedeAsignar`).
   - `guardar` es el guardado de hoy más `toast.warning(aviso)` si hay aviso.
   - `{panelAcceso}` al final del JSX. `enviando` vuelve a false mientras se pregunta.
4. **`ReasignarPanel`**: nuevo prop `vinculos: { ente; registro_id }[]` (`TareaDetailPanel` le pasa
   `tarea.vinculos`), y el mismo patrón.
5. **`TareaDetailPanel.relacionar(r)`**: pares = asignados activos (menos yo) × `[r]` →
   `confirmarAcceso(filas, () => vincularTarea(…))` con `verbo: "relacionar"` y
   `puedeDejarAfuera: puedeAsignar`.
6. **`ObraFormPanel.onSubmit`**
   - Si `obra && data.estado !== obra.estado`: `ensayarEstadoObra({ id, estado, motivo_perdida,
     detalle_perdida })`, que es una action nueva en `modules/obras/actions.ts`. Schema en `types.ts`
     con los mismos validadores que `editarObraSchema` (verificar si `.pick` sirve o si tiene refines).
   - Si el ensayo falla, se guarda igual: `editarObra` va a mostrar el error real.
   - Si no, `confirmarAcceso(filas, guardar)` con `verbo: "guardar"` y `puedeDejarAfuera: true`.
   - Al crear no se pregunta (decisión 3): avisa `plantilla_sin_acceso`.

### Docs y cierre

- `decisiones/tareas/integracion.md` (o `visibilidad.md`, junto a lo de D): *Compartir al asignar: la
  pregunta*. Por qué un panel nuevo en `components/ui/` + `lib/accesos.ts` y no mover `CompartirPanel`,
  cerrar = no compartir, y `puedeDejarAfuera`.
- `decisiones/global/ui.md`: `CompartirAccesoPanel`/`useConfirmarAcceso` en el catálogo.
- `decisiones/obras/ui.md`: el ensayo antes de guardar el estado.
- `BACKLOG.md`: borrar la entrada *Compartir al asignar* y el puntero a este plan. Borrar este archivo.

### Pruebas manuales (ADMIN y TESTER, como en `Pruebas de cambio en plantillas.md`)

1. ADMIN crea una tarea relacionada con una obra suya y la asigna a TESTER: aparece el panel con la
   obra tildada.
2. "Compartir y guardar": TESTER queda asignado, ve el chip y abre la obra.
3. Lo mismo con "Guardar sin compartir": TESTER no queda, y el toast lo dice. Si era el único, la tarea
   queda para ADMIN con nota.
4. Cerrar el panel con X equivale a no compartir.
5. Reasignar a TESTER una tarea relacionada con una obra de ADMIN: mismo panel.
6. Relacionar una obra propia en una tarea donde está TESTER: panel; sin compartir, TESTER sale.
7. Con un usuario sin `tareas_asignar` que está asignado: relacionar algo que otro no ve y no es tuyo
   da un error, no un panel.
8. Plantilla de ADMIN con disparo en "En cotización" y un paso para TESTER: al pasar la obra a ese
   estado, aparece el panel antes de guardar. Compartir → TESTER recibe la tarea.
9. Lo mismo sin compartir: la tarea no le llega y la campanita de ADMIN avisa que alguien quedó afuera.
10. Crear una obra ya en "En cotización" con esa plantilla: no hay panel, TESTER queda afuera y llega el
    aviso.

---

## Cosas a vigilar

- **Rendimiento de `tiene_permiso`**: pasa a llamar a otra función. Si una lista grande se nota más
  lenta, mirar `get_advisors` y los planes antes de optimizar.
- **`refresh()` más `revalidatePath`**: confirmar en Network que la Lista no pide dos veces.
- **Ensayo de estado**: si en el futuro algún trigger de `obras` hace algo fuera de la base (webhook,
  `pg_net`), el rollback no lo deshace. Hoy no hay ninguno; verificarlo antes de aplicar `sql/063`
  (`select tgname from pg_trigger where tgrelid = 'obras'::regclass`).
- **Recurrencia**: `generar_recurrencia` copia asignados. Verificar si copia vínculos. Si no los copia,
  la regla no aplica a la instancia nueva y está bien. Si los copia, anotar si hace falta la regla ahí.
