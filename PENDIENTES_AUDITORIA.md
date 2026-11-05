# Pendientes — auditoría de Tareas, Usuarios, Contactos y Obras (2026-11-05)

Lo que quedó sin hacer o sin verificar de la auditoría y de sus arreglos (commits `c2f0159`, `cf24b27`,
`96e2a75` y el de `getEmpresas`). La sesión no tuvo acceso a la base: el MCP de Supabase no conectó, porque
el proxy del entorno rechaza `mcp.supabase.com`. Cuando algo de acá se cierra, se borra su línea; cuando se
cierra todo, el archivo.

## 1. Habilitar el acceso a la base

- Permitir `mcp.supabase.com` en *Network access* de la configuración del entorno (pasos en
  https://code.claude.com/docs/en/cloud-environments#network-access). Sin eso no se puede nada de la sección 2.

## 2. Correr contra la base

- **`sql/tests/obras_reglas.sql` entero.** Los casos `05 a cargo` (de `obras_a_cargo`) son nuevos y nunca
  corrieron. Al pasar, borrar también su línea en `BACKLOG.md` (*Contactos y Obras* → *Sin correr*).
- **La suite SQL de los cuatro módulos:** `sql/tests/tareas_*`, `usuarios_*`, `contactos_*`, `obras_*`,
  `duplicados`, `entes_*`, `submodulo_reglas`, `notificaciones_usuarios` y `perfil_*`. La auditoría leyó el
  SQL, no lo corrió. Los arreglos no tocaron SQL, así que tendrían que pasar como antes.
- **Comparar lo aplicado con `sql/`** (`md5(prosrc)`): la auditoría se hizo contra los archivos.
- **Los e2e** (`erp-app/e2e/`): la sesión no tenía `.env`.

## 3. Probar en el navegador

Cada arreglo pasa `tsc` y lint; ninguno se vio andando.

- **Editar un paso con plazo en días ya habilitado**, cambiando solo el título: antes fallaba siempre con
  TA011. Probar también pasar de días a fecha fija, y al revés.
- **Login con `?next=`:** `/login?next=/tareas/<id>` vuelve ahí después de entrar, y
  `/login?next=/%09/evil.com` termina en `/`.
- **Desactivar y reactivar un usuario:** uno común; un delegador (tiene que fallar con US009 y la cuenta
  quedar sin ban); y reactivar uno cuyo email ya tomó otra cuenta (tiene que fallar y la cuenta seguir
  baneada).
- **"No se guardó: el registro cambió o ya no lo ves"** al editar algo que otro desactivó mientras la ficha
  estaba abierta (un paso, una obra, una persona). De paso, confirmar que PostgREST devuelve el conteo en un
  UPDATE sin `select()`: si no lo devuelve, `errorDeUpdate` (`lib/utils.ts`) no detecta nada.
- **Hilos y Equipo (Tareas) y Empresas (Contactos)** traen lo mismo que antes. Ahora juntan dos consultas y
  ordenan en Next (los hilos por `updated_at`, las empresas por nombre), no en la base.
- **Huérfanas en Contactos:** el admin las sigue viendo marcadas, en personas y en empresas.

## 4. Decidido, sin hacer

- **Traer las etiquetas de las referencias en una sola llamada** (punto 10 de la auditoría): `BACKLOG.md` →
  *Tareas — etiquetas de las referencias en una llamada*.

## 5. Visto durante los arreglos, sin decidir

- **`usuarios.nombre` no tiene CHECK en la base.** Los tres formularios ya recortan espacios y ponen un
  máximo de 200, pero `/perfil` escribe con el cliente normal (`usuarios_update_propio`): por PostgREST
  directo se puede guardar un nombre vacío o enorme. Un CHECK (`btrim(nombre) <> ''`, hasta 200 caracteres)
  tiene que convivir con `handle_new_user`, que usa el email cuando el alta no trae nombre. Si hay filas
  viejas que no cumplen, va `NOT VALID`.
- **El nombre de un equipo no tiene máximo** (`equipoSchema`, `erp-app/src/modules/usuarios/types.ts`).
- **El test del filtro de `?next=` no quedó en el repo.** Se probó con 19 casos contra el archivo real, pero
  `modules/auth/types.ts` importa con `@/` y `node --test` no resuelve el alias: hace falta un loader, o
  mover el filtro a un archivo sin imports del proyecto.
- **Los avisos de Tareas y de Obras/Contactos** (`sql/115`, `sql/134`) la auditoría los leyó por encima y
  confió en sus tests, que no pudo correr.
