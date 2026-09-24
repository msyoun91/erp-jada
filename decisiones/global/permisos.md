# Decisiones globales — Permisos

## `funcion` ligada a su `vista` puntual (`vista_id`), no solo a `modulo`

Modelo anterior (`sql/001`): `submodulos.tipo` era `seccion`/`funcion`, y una función se consideraba del módulo entero — sin relación a una sección específica. Funcionaba porque `usuarios` solo tiene 1 sección. No escala a un módulo con 2+ vistas: no había forma de saber a cuál pertenece cada función.

**Cambio (`sql/003_vistas_funciones.sql`, corrido en Supabase):**
- Enum renombrado `seccion` → `vista` (`ALTER TYPE ... RENAME VALUE`).
- Columna `submodulos.vista_id` (FK a `submodulos.id`, nullable). `CHECK`: vista → `vista_id NULL`; función → `vista_id NOT NULL`. Trigger `validar_vista_id()` valida que la vista referenciada exista, sea `tipo='vista'` y comparta `modulo`.
- Una vista puede tener 0 funciones (permiso de solo-lectura, se asigna directo, sin función que la sincronice).
- `PermisosModal.tsx` ahora anida funciones bajo su vista (antes: funciones listadas flat bajo el módulo). `syncVista()` reemplaza `syncSeccion()` — sincroniza la vista dueña específica, no todas las secciones del módulo.
- `getSeccionesDeModulo()` renombrado `getVistasDeModulo()`.

**Por qué:** pedido explícito de restructurar el modelo de permisos para soportar módulos multi-vista donde cada vista tiene su propio set de funciones — regla "no crear permisos por módulo" no aplica acá, esto sigue siendo autorización 100% por submódulo, solo se hace explícita la relación jerárquica vista→función que antes era implícita (y rota) por `modulo` compartido.

**Nota de ejecución:** el CHECK constraint se agregó antes del backfill en el primer intento — falló porque la fila `usuarios_gestionar` (funcion, sin `vista_id` todavía) lo violaba. Reordenado: backfill primero, constraint después. `supabase db query -f` corre el archivo como una sola transacción — el fallo revirtió todo (enum rename incluido), sin dejar estado a medio migrar.

## Vista y función se autorizan por separado (`PermisosModal`)

Hasta ahora `syncVista()` derivaba el checkbox de la vista de sus funciones: marcar una función encendía la vista, desmarcar la última la apagaba. La vista no era un permiso que se pudiera tocar — era un cálculo. Pedido explícito de usuario: **vista y función son checkboxes independientes**.

- `syncVista()` y `toggleVista()` eliminados. `toggle()` es add/remove puro.
- Checkbox tri-state en el nombre del módulo: marca/desmarca todo. **Opera solo sobre los submódulos que la búsqueda deja visibles** — el contador `marcados/visibles` al lado del label se calcula sobre el mismo set. Marcar permisos fuera de pantalla sería un cambio invisible.
- Badge `Vista` (`badge-info`) / `Función` (`badge-neutral`) en cada fila. La indentación sola deja de alcanzar cuando la búsqueda filtra y rompe la jerarquía visual.
- El bulk-toggle por vista sobrevive pero como control aparte: botón de texto `Todas`/`Ninguna` a la derecha de la fila, solo si la vista tiene funciones visibles. Opera sobre `[vista, ...funciones visibles]` — incluye la vista a propósito: marcar solo las funciones generaría huérfanas y bloquearía el guardado. El checkbox de la vista queda libre para lo que es, su propio permiso.
- La fila de vista dejó de ser un `<label>` envolvente: un `<button>` dentro de un label dispara el checkbox al click. Ahora es un `div` con el label en `flex-1` y el botón afuera.

**Función sin su vista queda prohibida, y la barrera está en servidor.** El desacople hace posible un estado que antes era inalcanzable: función autorizada, vista no. Ese permiso no se ve en la UI (el botón vive dentro de una vista que el usuario no puede abrir) pero **sí se ejecuta por server action** — la action chequea el código de la función, nunca el de su vista. `asignarSubmodulos()` rechaza el payload consultando `submodulos.vista_id` de cada función entrante contra el set autorizado. La UI valida lo mismo (`huerfanas`): warning en la fila y `Guardar` deshabilitado.

**Orden en `asignarSubmodulos()`:** la validación va **antes** del `update activo:false`. Al revés, un payload inválido dejaba al usuario sin ningún permiso y después devolvía error — la desactivación y el upsert no comparten transacción.

Datos existentes verificados sin huérfanos antes del cambio (el modelo viejo los hacía imposibles), así que no hizo falta backfill.

## `usuario_tiene_permiso(usuario, codigo)` — preguntar el permiso de otro (`sql/062`)

Pedido por PLAN_TAREAS_VINCULOS.md Fase C (base de "compartir al asignar", `decisiones/obras/visibilidad.md`). `tiene_permiso(codigo)` solo podía preguntar por `auth.uid()`; para decidir si un asignado puede abrir un vínculo hace falta preguntar por **otro** usuario. `usuario_tiene_permiso(p_usuario, p_codigo)` es el cuerpo de siempre parametrizado; `tiene_permiso(codigo)` pasa a `SELECT usuario_tiene_permiso(auth.uid(), codigo)` — misma firma, mismos grants, ninguna policy existente se toca. Sin `GRANT`: solo la llaman otras `DEFINER` (`puede_abrir_registro`, `puede_compartir_registro`), nunca el cliente.

## Siempre hay una función que administra el módulo

**Todo módulo tiene una función que deja actuar como administrador: ver todo y hacer todo** (por ejemplo,
sumar a cualquier miembro a cualquier proyecto). Decisión del usuario (2026-09-17), durante la auditoría de
tareas.

Endurecer una policy no puede dejar un módulo sin quien lo administre. Toda restricción nueva (policy,
trigger o función) conserva la rama de esa función. Si una regla vieja la excluye a propósito, se revisa
con el usuario, no se hereda en silencio. Funciona como cualquier otro submódulo: no es un rol.

En usuarios es `usuarios_gestionar`.

## Delegación con techo (decidido 2026-09-23; en la base desde `sql/105`)

**Un submódulo lo otorga el admin (`usuarios_gestionar`) o, dentro de su equipo, el delegador
(`usuarios_delegar`), y el delegador nunca da más de lo que tiene.** Sigue sin haber roles: el
delegador es una función y el equipo es una membresía que no da permisos. Solo define a quién puede
delegar el delegador.

- **Sin excepción a "todo por submódulos".** Parecía hacer falta autoridad por fila ("delegador *de
  este* equipo"), pero se resuelve con función + membresía + un trigger de uno por equipo, no con una
  columna `delegado_id`.
- **El techo tiene tres partes:** lo que el delegador tiene, lo marcado `submodulos.delegable` (`false`
  por defecto) y la regla vista/función de arriba. Las funciones de administración no se marcan
  delegables.
- **Revocar es en cascada.** Todo lo delegado cuelga de un permiso del delegador (`otorgada_por`). Si
  el delegador lo pierde, lo pierden también quienes lo recibieron de él.

Mecánica completa (equipos, heredero, "gana el admin"): `decisiones/usuarios.md` → *Equipos y
delegación de permisos*.

## Reglas entre permisos: `requiere` y `excluye` (`sql/110`, 2026-09-23)

**Un permiso puede requerir otro o no poder tenerse junto con otro. La regla es una fila de
`submodulo_reglas`, no código.** El trigger `usuario_submodulos_validar` la hace valer (US016,
US017) y el panel de permisos la lee de la misma tabla para avisar antes de guardar. Escrita en el
trigger y otra vez en el panel habría quedado duplicada.

- **Casos que la originaron:** Equipos (`usuarios_equipos`, del admin) excluye Mi equipo
  (`usuarios_equipo`, del delegador), cargada en `sql/110`. Las de la ficha de tareas (`decisiones/tareas/README.md` → *Reglas entre
  permisos*) entran con la migración de tareas.
- **`excluye` es una fila por par y vale en los dos sentidos. `requiere` va en un solo sentido.**
- **Vista → función no se carga como regla:** ya la expresa `vista_id` (US001).
- **Panel (`PermisosPanel`), avisar y bloquear, nunca marcar solo:** lo marcado sin su requisito
  muestra ⚠ "Requiere X" y deshabilita Guardar, como la función sin su vista. Marcar el requisito
  automáticamente podría convertir a alguien en delegador sin que el admin lo vea. Lo que choca con
  algo marcado queda deshabilitado con "No compatible con X". "Todas" y el checkbox del módulo se
  saltean lo excluido, y lo excluido no cuenta para "completo".
- **Admin y equipos no entra en la tabla.** `usuarios_gestionar` contra `usuarios_delegar` sale de
  la membresía (US002/US003), no de un par de permisos.

Archivos: `sql/110_submodulo_reglas.sql`, `sql/tests/submodulo_reglas.sql`,
`modules/usuarios/components/PermisosPanel.tsx`, `modules/usuarios/queries.ts` (`getSubmoduloReglas`).
