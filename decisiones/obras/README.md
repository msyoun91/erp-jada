# Decisiones — Agenda de Obras

Módulo `obras`, ruta `/obras`, nombre visible **Agenda de Obras**. Fase 1: registro y relación de
datos. Spec original en `spec.md` (fuera del repo). Acá está lo que la spec **no** dice o dice
distinto de como quedó implementado.

Índice. Leer este archivo y después **solo** los archivos del tema que toca la tarea. *MODEL A*
(`visibilidad.md`) reescribió varias decisiones de los otros archivos: leerlo antes de apoyarse en
una decisión de visibilidad o alcance.

---

## `visibilidad.md`

MODEL A (todo privado por dueño), compartir con checklist y cascada, grants heredados, alcance de personas, buscador global, `obras_aprobar`.

- **El dueño del contacto lo ve en la obra que le comparten (`sql/097`)** — la rama de receptor
  suma "el contacto es mío", solo lectura
- **Sacar es de lo que se fue, y persona↔empresa no cambia de punta (`sql/096`)** — `OB032` contra lo
  que migró, no contra lo pedido; `GRANT UPDATE` por columna en `obras_persona_empresa`
- **El vínculo se va con la obra (`sql/095`)** — transferir pasa al entrante los vínculos que cargó
  el saliente, y "tu vínculo" vale mientras la obra siga compartida con vos
- **Un código por regla, y la vista Compartido no miente (`sql/094`)** — revive `OB009`, saca de la
  vista los grants sin vínculo vivo y devuelve `puedo_abrir`; más `safeParse` en revocar
- **`otorgada_por` es historia, no autoridad (`sql/093`)** — ver, revocar y leer la fila son una
  sola pregunta: dueño del contacto o dueño del ancla; se van cinco UPDATE
- **La red de regresión de compartir se reconstruye alrededor del acto que quedó** — cinco tests retirados, uno nuevo; el criterio es si el sujeto existe (sin SQL)
- **La vigencia del grant contextual se escribe una sola vez (`sql/092`)** — `obras_ctx_vigente` reemplaza a cinco funciones; en una de ellas la regla estaba mal
- **El listado de la agenda se recorta en la query, y es deliberado** — la barrera es el contacto por columna, no el listado (sin SQL)
- **Compartir exige lo mismo que transferir (`sql/091`)** — `obras_ver` en el receptor, y el array `null` deja de significar "no toques nada"
- **El grant contextual muere con el ancla (`sql/090`)** — vale mientras se vea la obra o empresa que lo trajo, y `otorgada_por` sigue al dueño del ancla, no al de la entidad
- **Transferir lo propio no es ver lo ajeno (`sql/089`)** — cada transferencia con dos puertas: la global de siempre y una personal que no ensancha la vista
- **Migrar la agenda entera es otra acción (`sql/088`)** — cascada total sin checklist, submódulo `obras_migrar`, y la auditoría pasa a ver las tres clases
- **Transferir pregunta tres cosas, no dos (`sql/087`)** — migra / contextual / lo saco, por contacto; se retira "exclusivo"
- **La obra es el único acto de compartir (`sql/086`)** — se cierra el share directo de persona y empresa
- **La empresa también es contextual (`sql/085`)** — lo que llega arrastrado por una obra no entra a la agenda
- **Compartir una obra o empresa no reparte contactos (`sql/082`)** — el checklist otorga grant contextual
- MODEL A — obras, empresas y personas son privadas por dueño (`sql/039`–`044`)
- Compartir con checklist y cascada de revocación (`sql/047`)
- El receptor de una obra compartida vincula sus contactos (`sql/051`)
- El grant heredado de una obra ve el contacto, no lo reparte (`sql/052`)
- La empresa de una persona en la obra la ve quien ve la empresa (`sql/070`)
- Lo compartido entra al listado; editar sigue siendo del dueño (sin SQL)
- La obra es privada de su responsable
- Las personas tienen alcance; las empresas no
- El alcance por fila no es un permiso nuevo
- `obras_aprobar` no es una llave a la agenda
- El buscador global no inventa visibilidad (`sql/037`)

## `vinculos-referentes.md`

Vínculos obra ↔ empresa ↔ persona, roles, referentes y su comisión.

- Ser referente no es un rol
- Guardar un referente es un solo statement
- Roles como array, no tabla puente
- `empresa_id` en obra↔persona no se valida
- Vincular se hace desde los dos lados
- La empresa entra a la obra con su gente
- Marcar referente era el atajo que dejaba pasar todo
- El referente se cae con el vínculo (`sql/036`)

## `duplicados-aprobaciones.md`

Aviso de duplicados, altas congeladas, cola de aprobación y logs por función.

- Aviso ciego de duplicados
- Los logs se miran por función, no por policy
- La localidad ordena el aviso de duplicados, no lo filtra
- El chequeo de duplicados también corre al editar
- Congelada, no marcada
- El vínculo pendiente no abre la ficha
- La detección corre en la base, y por eso hubo que partir las tres búsquedas
- ~~Lo que el rechazo todavía no resuelve~~ — resuelto por `sql/038`

## `modelo.md`

Nombre, campos, enums y `estado_obra`, desactivar, mensajes `OB`, GRANT por columna, bugs de SQL que vale recordar, fuera de alcance.

- Nombre: nada de CRM
- Sin CUIT
- Los mensajes de la base los deja pasar una lista blanca de códigos
- Cuatro campos se fueron de la ficha
- El test de RLS no puede depender de los permisos reales
- Enums, no tablas de catálogo
- `estado_obra`: los estados comerciales entran antes de presupuestos (`sql/046`)
- Desactivar
- Sin widget de dashboard, sin portal de clientes
- Bug que vale recordar: RLS + `INSERT ... RETURNING`
- Fuera de alcance de fase 1
- GRANT UPDATE por columna en las cuatro tablas que faltaban
- Bug que vale recordar: `AND` no corta la referencia a `NEW`

## `ui.md`

Listados, fichas, filtros por chips, acciones en `OverflowMenu`, breadcrumb, buscador en la barra del título.

- UI — decisiones que no salen de la spec
- Los `<select>` de vinculación se fueron a buscador
- Enlaces externos: copiar, no inventar
- La fila de listado se escribe una vez y cambia de display
- Las acciones de la ficha viven en el `OverflowMenu`
- El rol elegido se marca con borde, no con relleno
- La tab activa se resuelve por prefijo más largo
- Desvincular pregunta antes, y con eso deja de dispararse dos veces
- Sin optimistic update: la auditoría pedía algo que el proyecto no hace en ningún lado
- El vacío de una sección no se dibuja como el vacío de una página
- El estado va en el encabezado, "Pendiente" no
- El estado se filtra con chips, no con un `<select>`
- El filtro vive donde llega su efecto
- `Dato` y `Observaciones` son del módulo, no de `components/ui/`
- El breadcrumb reemplaza al botón "← Personas"
- La barra va en la línea del título, no adentro de una tab
- La sección Tareas de las fichas
- El ensayo antes de guardar el estado (sin SQL)
