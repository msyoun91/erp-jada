# Decisiones — módulo comercial

## Fase 1 (`sql/018_comercial.sql`)

Base de datos comercial: obras, empresas, personas, sus relaciones y la lectura comercial de una obra. Sin tareas, actividades ni automatizaciones — el estado del prospecto es clasificación, no un disparador. El documento de traspaso (`HANDOFF_COMERCIAL_FASE1.md`) tiene el alcance completo y lo que queda pendiente.

### Empresas, personas y obras no llevan prefijo de módulo

`GUIDE_DB.md` pide `{modulo}_{entidad}`. Acá se aplica solo a lo comercial (`comercial_prospectos`, `comercial_fuentes`, `comercial_comisiones`); los maestros y sus relaciones van sin prefijo (`empresas`, `personas`, `obras`, `obra_empresa`, `obra_persona`).

La obra sobrevive al prospecto: Presupuestos, Instalación y Postventa van a colgar de `obras`, y Clientes va a usar `empresas`. Prefijarlas hoy obliga a renombrarlas mañana, con todo lo que eso arrastra.

### Los roles van en un array de enum, no en una tabla hija

La spec original definía una columna `rol` singular y a la vez exigía roles múltiples (una empresa desarrolladora **y** constructora de la misma obra; una persona arquitecta **y** decisora). Se resolvió con `roles rol_empresa[]` / `roles rol_persona[]` y CHECK de al menos un elemento.

Contra la tabla hija normalizada: dos tablas menos, cero policies extra, cero CRUD extra. La hija solo haría falta si un rol tuviera atributos propios (fecha desde, observación por rol) — cuando aparezca ese caso, migrar es un `unnest`.

### `referente` no es un rol

La spec lo listaba como valor de `rol_persona` **y** como campo `es_referente`. Dos fuentes para el mismo hecho. Queda solo la columna, porque es la que puede llevar el unique parcial `(obra_id) WHERE es_referente AND activo` — un referente por obra.

### La comisión es una fila, no una columna

`tiene_comision` + `porcentaje_comision` en `obra_persona` (lo que pedía la spec) son dos columnas para un dato, y obligan a una regla ("si `tiene_comision` es false, `porcentaje` es null") que alguien tiene que recordar aplicar.

La comisión vive en `comercial_comisiones`, una fila por relación: **hay fila = hay comisión**. La regla pasa a ser imposible de violar en vez de una validación. `0.00` sigue siendo "0% configurado", distinto de "sin fila".

El motivo de fondo es el permiso: el usuario pidió que el `%` lo vea solo quien tiene `comercial_comision`. La RLS filtra filas, no columnas — gatear una columna necesitaría vista + GRANT por columna + trigger. Gatearla como fila lo resuelve la policy que ya existe. **Efecto buscado:** quien no tiene la función no ve el porcentaje ni sabe que existe una comisión.

### `guardar_obra_persona` — la relación y su comisión se guardan juntas

Dos tablas que tienen que quedar consistentes es orquestación multi-tabla, y esa vive en Postgres. La función es `SECURITY INVOKER` a propósito: quien no tiene `comercial_comision` no ve la fila, así que su rama "borrar comisión" afecta 0 filas y **la comisión que ya existía sobrevive intacta**. Con `SECURITY DEFINER` la habría borrado sin querer.

`actions.ts` queda como glue: `safeParse` → `.rpc()` → `revalidatePath`.

### Desactivar cascadea desde la obra, y se bloquea desde los maestros

- La obra es el contenedor: al desactivarla caen su prospecto y sus relaciones (trigger `cascada_desactivar_obra`). Dejar relaciones vivas de una obra desactivada deja filas que nadie puede alcanzar desde la UI.
- Empresa y persona **no** cascadean: son maestros reutilizables y vaciar obras en silencio es peor que fallar. Desactivarlas con obras activas devuelve `CM002` / `CM003` y pide sacar la relación primero.

La cascada de comisión es `SECURITY DEFINER` (tiene que correr aunque quien desactiva no vea la comisión); es cascada, no autorización.

### Visibilidad: por responsable, con un solo eje admin

Decisión del usuario. `comercial_prospectos.responsable_id` decide quién ve cada prospecto, y `comercial_gestionar_ajenos` es el único eje admin: ve, edita y traspasa el responsable. No se creó una tercera función tipo `tareas_asignar` — en comercial "poner a otro a cargo" y "gestionar lo ajeno" son la misma potestad, y separarlas sería una distinción sin caso real.

Los maestros (empresas, personas, obras) **no** son por responsable: se leen con cualquier vista del módulo. El dato comercial es lo privado, no la red de contactos.

### `acceso_comercial()` en vez de repetir el OR

Diez policies necesitaban "tiene alguna de las cuatro vistas". Una función `SECURITY INVOKER` `STABLE` en vez de copiar el mismo OR de cuatro términos diez veces.

### Duplicados: constraint donde el dato identifica, aviso donde no

- CUIT (empresas) y email (personas) son unique parcial: identifican, y dos filas con el mismo valor son un error.
- Obra y razón social: solo aviso en el formulario (`AvisoDuplicados`), sin bloquear. "Edificio Belgrano" puede existir en dos localidades. Sin motor de matching ni `pg_trgm` hasta que duela.

El CUIT se guarda como 11 dígitos (se le sacan guiones al validar): si no, `30-71234567-8` y `30712345678` serían dos empresas distintas y el unique no serviría de nada.

### Campos que salieron de la spec

- `fecha_estimada_compra` estaba en obra **y** en prospecto. Queda solo en el prospecto: es comercial.
- "Empresa principal" del listado no es columna: se deriva por prioridad de rol (desarrolladora > constructora > inmobiliaria > …) en `comercialLabels.ts`. Una columna se desincroniza con `obra_empresa`.

### `lib/usuarios.ts` — "quién soy" y "quiénes están activos" salieron de tareas

`getUsuarioActualId` y el listado de usuarios activos los usan tareas (asignar) y comercial (elegir responsable). Se movieron a `lib/usuarios.ts`; `modules/tareas/queries.ts` los reexporta con sus nombres viejos para no tocar sus llamadores.

### UI — el bloque de relaciones es uno solo

`ObraRelaciones` se usa igual desde la ficha de la obra y desde la del prospecto: la misma obra no puede leerse distinto según desde dónde se la mire. La prop `gestionar` decide si además se edita.

Los paneles abiertos re-leen su fila del array que llega del server component en cada render (`obras.find(...)`), no de la copia guardada al abrirlos: si no, después de guardar una relación el panel seguía mostrando los datos viejos.
