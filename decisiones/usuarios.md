# Decisiones — módulo usuarios

## Ficha del módulo

Aprobada el 2026-09-23, junto con *Equipos y delegación de permisos* (abajo).

```
Módulo: usuarios
Objetivo: quién entra al sistema y qué puede hacer cada uno — cuentas, equipos y permisos, con el
          administrador como autoridad y una delegación acotada a cada equipo.
Personas
├── Administrador de sistema — ve todos los usuarios, equipos y permisos
│                            · crea, edita, desactiva y reactiva cuentas, resetea contraseñas, asigna
│                              permisos, crea equipos y sus miembros, designa delegador y heredero,
│                              marca qué submódulos son delegables
│                            · — (ve todo)
├── Delegador de equipo      — ve a los miembros de su equipo, con todos sus datos y permisos
│                            · asigna a su equipo los submódulos delegables que él tiene; revoca solo
│                              lo que otorgó él
│                            · no ve usuarios fuera de su equipo; no crea, edita, desactiva ni resetea
│                              cuentas; no toca lo que otorgó el admin
├── Miembro / independiente  — NO usa el módulo: su cuenta la ve en /perfil · — · —
└── Agente IA                — NO usa el módulo. Puede ser miembro de un equipo, nunca delegador
                               (regla de uso: hoy la base no distingue un agente de una persona)
Entes: ninguno — usuario y equipo son de core: no tienen dueño ni se comparten
Eventos que emite: ninguno · Eventos que consume: ninguno
```

```
Módulo: Usuarios
├── Usuarios (vista, usuarios_ver)            — admin
│   └── usuarios_gestionar (funcion)          — admin: cuentas, permisos, equipos, delegador, heredero, delegable
└── Mi equipo (vista, usuarios_equipo)        — delegador
    └── usuarios_delegar (funcion)            — delegador
```

## Equipos y delegación de permisos (decidido 2026-09-23, sin implementar)

**El admin asigna permisos; un delegador por equipo reparte a su equipo lo que el admin le dio.** Pedido
del usuario: que el admin no tenga que asignar cada permiso de cada persona, sin crear roles. El delegador
es una función (`usuarios_delegar`), no un rol; el equipo decide *a quién* puede delegar, nunca *qué*
permisos tiene alguien. El equipo como unidad para compartir registros de un módulo viene después, sobre
la misma membresía. La regla transversal está en `decisiones/global/permisos.md` → *Delegación con techo*.

**Equipos.**
- Los crea el admin con un nombre libre y les asigna los miembros. Tabla `equipos` + `equipos_miembros
  (equipo_id, usuario_id, activo)`.
- Un usuario está en un solo equipo o en ninguno (independiente): unique parcial `(usuario_id) WHERE activo`.
- Quien tiene `usuarios_gestionar` no puede ser miembro de un equipo.
- Un equipo con miembros activos no se puede desactivar.
- Un usuario desactivado sigue en su equipo, igual que conserva sus asignaciones (`sql/020`): al
  reactivarlo vuelve todo como estaba.

**Delegador.**
- Uno por equipo, y solo lo designa el admin. Delegador = el miembro del equipo que tiene
  `usuarios_delegar`; un trigger rechaza un segundo delegador activo en el mismo equipo y que un
  independiente tenga la función. No hay columna `equipos.delegado_id`: la autoridad sale de un
  submódulo, no de un dato.
- No hay cadena: `usuarios_delegar` y `usuarios_equipo` los otorga solo el admin.

**Techo.** El delegador solo otorga submódulos que él mismo tiene y que están marcados como delegables
(`submodulos.delegable`, `false` por defecto: una función nueva nace no delegable). Sigue valiendo
*función sin su vista queda prohibida* (`decisiones/global/permisos.md`).

**Quién otorgó cada permiso.**
- `usuario_submodulos` suma `otorgada_por` y `updated_at`. Sigue habiendo una fila por par, así que la
  vista del admin y la del delegador muestran la misma asignación.
- Gana el admin: si el admin otorga algo que ya había dado el delegador, la fila pasa a
  `otorgada_por = admin` y desde "Mi equipo" se ve bloqueada.
- El delegador revoca solo las filas con `otorgada_por = él`.
- Si el admin después revoca esa fila, se va: no vuelve a quedar "por el delegador". Es el costo de no
  duplicar filas, y se aceptó.

**Revocación en cascada.**
- Si el admin le saca `X` al delegador, se revoca `X` en todo lo que el delegador otorgó.
- Si un miembro cambia de equipo o queda independiente, se le revoca todo lo que le dieron por
  delegación. En el equipo nuevo se le asignan permisos desde cero. Lo que otorgó el admin se conserva.

**Heredero.**
- El delegador sale si lo desactivan, lo sacan del equipo o el admin le quita `usuarios_delegar`. En
  esa misma acción el admin elige un heredero, que tiene que ser miembro activo del equipo. Solo se
  puede salir sin heredero si no queda otro miembro activo.
- En una sola transacción:
  1. El heredero recibe una copia de los permisos del delegador saliente, con `otorgada_por = admin`
     (incluye `usuarios_delegar` y su vista).
  2. Lo que el saliente delegó pasa a `otorgada_por = heredero`.
  3. Lo que el saliente le había delegado al heredero pasa a `otorgada_por = admin`.
- El admin ve la lista de lo que se copia, todo marcado por defecto. Si desmarca algo, el heredero no lo
  recibe y se revoca en cascada del equipo. Así el techo se sigue cumpliendo: todo lo delegado está
  dentro de los permisos del heredero.
- El saliente pierde `usuarios_delegar` y su vista, aunque siga en el equipo desactivado; si no, habría
  dos delegadores. Conserva lo demás que le dio el admin.

**Visibilidad.** El delegador ve todos los datos de los miembros de su equipo (email y teléfono
incluidos) y sus permisos, pero no puede editarlos. Suma una rama a `usuarios_select`.

**Las reglas viven en Postgres, no en `actions.ts`.** Techo, un delegador por equipo, cascadas y
herencia son triggers y funciones. Las actions de admin escriben con `service_role`, que se saltea la
RLS pero no los triggers, así que la misma regla cubre las dos vías. El flujo del delegador corre con
su sesión (`authenticated`), nunca con `service_role`.

**Historial: lo mínimo.** `otorgada_por` + `updated_at` contestan quién dio el permiso que está vigente.
Si hace falta saber quién lo sacó y cuándo, se suma un log; hoy no hay pedido.

## Desactivar por fin desactiva, y se puede reactivar (`sql/020_usuarios_activo.sql`)

**El bug:** `desactivarUsuario` ponía `usuarios.activo = false` y nadie leía esa columna. `tiene_permiso()` (`sql/001`) miraba `usuario_submodulos.activo` y `submodulos.activo`, nunca al usuario; el proxy solo chequeaba que hubiera sesión; `auth.users` quedaba intacto. El desactivado seguía entrando con todos sus permisos, mientras el modal prometía "Perderá el acceso al sistema".

**La barrera queda en tres capas, y cada una tapa lo que la otra no.**

1. **`tiene_permiso()` suma `JOIN usuarios u ... AND u.activo`.** Es la única que cubre un request que no pasa por Next — PostgREST directo con el access token todavía sin expirar. Se hace por JOIN y no desactivando las filas de `usuario_submodulos`: así reactivar devuelve los permisos exactamente como estaban, sin backup ni recálculo.
2. **El proxy consulta `usuarios.activo` en cada request autenticado** (`lib/supabase/middleware.ts`), y si está inactivo hace `signOut()` + redirect a `/login?motivo=inactivo`. Cuesta un lookup por PK sobre la sesión abierta; el JWT no sabe nada de `activo`, así que el dato hay que ir a buscarlo. La rama `id = auth.uid()` de `usuarios_select` es la que hace posible esta consulta y por eso no se toca. Si el pathname ya es `/login` se devuelve la respuesta con la cookie limpia en vez de redirigir — redirigir sería un loop. El redirect copia las cookies de `supabaseResponse`: es una respuesta nueva y sin eso se pierde el borrado que acaba de escribir `signOut()`.
3. **La cuenta se banea en `auth.users`** (`ban_duration: "876000h"`, cien años — Supabase no tiene ban permanente). Sin esto el access token vivo (≤1h) sigue sirviendo contra la API para todo lo que RLS concede por `auth.uid()` sin pasar por `tiene_permiso` — sus propias tareas, sus notas, sus widgets. El ban además rechaza el login nuevo, y `user_banned` ya estaba mapeado en `mensajeError`. Si el ban falla, la action revierte `activo` y devuelve error: mejor no desactivar que dejar la mitad puesta.

**`getUserSubmodulos()` espeja el chequeo con `usuarios!inner(activo)`.** No es duplicación decorativa: las actions de `usuarios` usan `service_role`, que no pasa por RLS, así que ese chequeo en TS es la única barrera que tienen. Se verificó contra PostgREST que el embed resuelve (`usuario_submodulos` tiene una sola FK a `usuarios`) — si no resolviera, `data` sería null y el resultado "sin permisos" para todo el mundo.

**No se puede desactivar la propia cuenta.** Sin la guarda, el único gestor puede dejar el sistema sin nadie capaz de reactivar a nadie — incluido él.

**Reactivar no pide confirmación.** No destruye nada y se deshace con "Desactivar", que sí la pide. `ConfirmModal` es siempre `btn-danger`; usarlo acá hubiera pedido un tono nuevo para una acción que no lo necesita.

**Reactivar puede chocar con el email.** `idx_usuarios_email_activo` es unique parcial `WHERE activo`: mientras la cuenta estuvo desactivada, ese email pudo darse de alta en otra. El `23505` se traduce a "Ya hay un usuario activo con ese email" en la action, no en `mensajeError` — ahí el genérico ("Ya existe un registro con esos datos") no diría cuál es el registro.

**Queda afuera a propósito:** las tablas que autorizan por `auth.uid()` sin `tiene_permiso` no chequean `activo` en sus policies. Cerrar esa ventana pediría sumar la condición a cada policy de cada módulo; el ban ya la cierra para todo lo que no sea un token vivo de menos de una hora.

Verificado con `sql/tests/usuarios_activo.sql` (mismo mecanismo que los tests de RLS de tareas: rol `authenticated`, `request.jwt.claims` movido, `ROLLBACK` al final).

## Editar, resetear contraseña y filtro por estado (`sql/021_usuarios_editar.sql`)

Sin submódulos nuevos: editar y resetear contraseña son el mismo nivel de autoridad que crear y desactivar, así que van bajo `usuarios_gestionar`. Un permiso más fino no tendría a quién servir — quien puede crear una cuenta puede cambiarle el email.

**El email se sincroniza por trigger, no con dos writes.** `auth.users.email` es la credencial; `usuarios.email` es lo que muestra el ERP. `handle_user_email_updated` (AFTER UPDATE OF email ON auth.users) baja el valor a `usuarios`, igual que `handle_new_user` hace en el INSERT. Como el trigger corre dentro de la transacción del cambio, si `usuarios` rechaza el valor se revierte también el de auth: no queda un usuario entrando con un email que la pantalla no muestra. El `WHEN (NEW.email IS DISTINCT FROM OLD.email)` es lo que evita que un cambio de contraseña o el ban de `sql/020` reescriban la fila.

**`nombre` no se replica a `user_metadata`.** `handle_new_user` lo lee al crear la cuenta y ahí termina su rol; la autoridad es `usuarios.nombre`. Escribir las dos copias en cada edición sería duplicar la verdad para un campo que auth no usa.

**La action solo toca auth si el email cambió.** Lee el email actual primero: editar un nombre no tiene por qué pasar por el servicio de auth. El duplicado lo rechaza el propio `auth.users` (unique sobre todos los emails, más estricto que el índice parcial de `usuarios`) y devuelve `email_exists`, que ya estaba mapeado en `mensajeError`.

**Resetear contraseña no cierra las sesiones abiertas del usuario.** `auth.admin.signOut()` pide el JWT de esa sesión, no el id — desde el panel de admin no lo tenemos. Si el motivo del reseteo es una cuenta comprometida, el camino es desactivar (que sí banea, `sql/020`) y después reactivar con la contraseña nueva. La contraseña se muestra en claro por default en el modal: quien la fija se la tiene que pasar al usuario, y no es su propia contraseña la que queda expuesta en pantalla.

**Filtro de estado con default en "Activos".** Existe recién ahora: hasta que se pudo reactivar, un inactivo en la lista no tenía nada que ofrecer. El default oculta a los desactivados porque son historia, no el trabajo del día. El estado vacío distingue los dos casos por `usuarios.length`, no por el filtro: con la base vacía dice "Sin usuarios todavía" e invita a crear; con la base llena y el filtro sin resultados dice "Sin resultados" y menciona el filtro, que es lo que probablemente lo causó.

Verificado con `sql/tests/usuarios_email_sync.sql` (2/2). El caso "un UPDATE que no toca el email no dispara el trigger" planta un centinela en `usuarios` antes del UPDATE: comparar contra el mismo valor de antes daría OK con el trigger corriendo igual.

## Lista y formularios: revisión visual

**El badge de estado aparece solo cuando la lista puede mezclar estados.** Con el filtro en "Activos" —el default— todas las filas dirían "Activo": el badge repite el filtro en vez de informar. Se muestra con "Inactivos" y "Todos". `modules/usuarios/components/UsuariosView.tsx`.

**La fila muestra cuántos permisos tiene el usuario.** `asignaciones` ya llegaba a la vista para el panel de permisos; contarlo ahí evita abrir el panel usuario por usuario para saber quién quedó sin acceso ("Sin permisos"). Oculto abajo de 640px, donde el ancho es del nombre. `UsuariosView.tsx`.

**`initials()` subió a `lib/utils.ts`.** La usa el avatar del sidebar y el de la fila: dos módulos, una fuente. `lib/utils.ts`, `components/layout/SidebarNav.tsx`, `UsuariosView.tsx`.

**"Todas"/"Ninguna" del panel de permisos es un `btn-secondary`, no texto subrayado en hover.** Era una acción que solo se anunciaba al pasar el mouse, y en touch no hay hover (GUIDE_DESIGN → Mobile-first). El borde la declara clickeable y el media query de `.btn` le da los 44px. `modules/usuarios/components/PermisosModal.tsx`.

**El buscador ocupa su propia fila abajo de 640px (`SearchInput`).** `flex-1` lo dejaba encogerse hasta cortar el placeholder mientras select y botón se apretaban al lado. Va `grow basis-full sm:basis-auto` y no `flex-1 basis-full`: `flex-1` emite `flex: 1 1 0%` y pisa el `basis-full`. Toca todos los módulos que usen el componente. `components/ui/SearchInput.tsx`.

**Crear y editar pasaron de `Modal` a `RightPanel`.** Era la desviación que quedaba respecto de GUIDE_DESIGN → *Crear y editar: panel lateral, no modal*; no había excepción escrita, así que se corrigió el código y no la guía. Los archivos pasaron a llamarse `CrearUsuarioPanel.tsx` y `EditarUsuarioPanel.tsx`. Crear además gana el `hayCambios` que ya tenía editar: cerrar por backdrop o Escape con el formulario a medio llenar ahora pregunta.

**El botón de submit vive en el footer del panel, atado al form con `form="<id>"`.** `RightPanel` renderiza el footer fuera de `children`, así que el botón queda fuera del `<form>`; el atributo nativo los asocia sin ref, estado ni handler puente. `CrearUsuarioPanel.tsx`, `EditarUsuarioPanel.tsx`.
