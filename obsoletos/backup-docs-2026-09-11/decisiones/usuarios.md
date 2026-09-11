# Decisiones — módulo usuarios

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
