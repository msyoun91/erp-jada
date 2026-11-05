# Pendientes — auditoría de Tareas, Usuarios, Contactos y Obras (2026-11-05)

Lo que quedó sin hacer o sin verificar de la auditoría y de sus arreglos (commits `c2f0159`, `cf24b27`,
`96e2a75` y el de `getEmpresas`). La sesión no tuvo acceso a la base: el MCP de Supabase no conectó, porque
el proxy del entorno rechaza `mcp.supabase.com`. Cuando algo de acá se cierra, se borra su línea; cuando se
cierra todo, el archivo.

## 3. Probar en el navegador

Probado el 2026-11-05 con Playwright. Lo que sigue no se pudo probar: hace falta un usuario descartable, porque
desactivar a `Tester` le pasaría sus hilos, su agenda y sus obras a otro, y reactivarlo no lo deshace.

- **Desactivar y reactivar un usuario:** uno común, y reactivar uno cuyo email ya tomó otra cuenta (tiene que
  fallar y la cuenta seguir baneada).
- **Huérfanas en Contactos:** el admin las sigue viendo marcadas, en personas y en empresas. Hoy no hay ninguna:
  el filtro y su estado vacío andan, pero la marca no se vio.

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
