# Pendientes de UI

Lo que quedó de la revisión de diseño entre módulos (2026-11-05). Lo hecho y por qué está en
`decisiones/global/ui.md` → *Consistencia entre módulos*; las reglas para código nuevo, en
`.claude/guides/GUIDE_DESIGN.md`.

Nada de esto está decidido: son propuestas. Al decidir una, se implementa y se registra en `decisiones/`
(o pasa a `BACKLOG.md` si se decide y queda para después), y se borra de acá.

---

## Verificación que falta

- **Los e2e no se corrieron.** En el entorno de la revisión no había base (sin `.env`, y el conector de
  Supabase no conectaba). Se revisó que ningún selector dependa de un texto cambiado, pero hay que correr
  `npm run e2e` desde `erp-app`. Lo que más puede romper: el orden nuevo de las barras (acciones arriba),
  los links `Volver` en las fichas, "Desactivado" en vez de "Inactivo" y "Guardando…" en vez de
  "Creando…"/"Agregando…" en los paneles.
- **Las pantallas se vieron con datos de ejemplo, no con datos reales.** Repasar en un celular: Insumos y
  Paquetes con los filtros plegados, una ficha de obra y de hilo con `Volver`, y el botón primario en modo
  oscuro.

## Alta

- **El estado de una obra solo se cambia tocando el badge.** Es un `<button>` con forma de badge (~20px de
  alto, abajo de los 44 táctiles) y la única pista es un `title`, que en touch no existe; en el `⋯` no está.
  Propuesta: "Cambiar estado" en el `⋯` y el badge con una flecha `▾` y `tap-target`. Archivo:
  `modules/obras/components/ObraView.tsx`.
- **"Configurar" de Inicio no se cierra con Escape ni tocando afuera.** Es un `div` `absolute` propio; el
  resto de los menús (`OverflowMenu`) sí se cierran. Propuesta: el mismo comportamiento que `OverflowMenu`.
  Archivo: `modules/dashboard/components/ConfigurarWidgets.tsx`.

## Media

- **`.lista` en `globals.css`.** `flex flex-col rounded-lg border border-border bg-bg-surface` está escrito
  22 veces: es el contenedor de toda lista de filas, el mismo caso que llevó a crear `.row`.
- **Todas (Tareas) tiene dos filtros y no usa `<Filtros>`.** La regla nueva dice dos o más. Falta que
  `HilosView` sepa cuántos de los filtros que le pasa la vista están puestos, para el contador. Archivos:
  `modules/tareas/components/HilosView.tsx`, `TodasView.tsx`.
- **Los avisos de Monedas son texto ámbar suelto, no `.alert`.** El resto de los avisos de pantalla ya usa
  la clase. Archivo: `modules/monedas/components/MonedasView.tsx`.
- **En el celular el buscador siempre ocupa una fila entera** (`basis-full` en `SearchInput`). Con un solo
  filtro al lado (Usuarios, Obras, Contactos, Hilos) entrarían los dos en una fila. Probar `basis-48` y
  revisar que no se corte el placeholder más largo ("Buscar por nombre o dirección…").

## Baja

- **El avatar con iniciales** está escrito tres veces en Usuarios (fila de usuario, de equipo y de mi
  equipo) y con otro estilo en el sidebar. Pasarlo a componente cuando lo use un segundo módulo.
- **No se revisó el texto de los toasts** entre módulos ("Usuario desactivado", "Obra reactivada",
  "Confirmado"…): falta ver que digan lo mismo de la misma forma.

## Entorno

- **`next dev` no arranca en el entorno cloud.** Faltan en `node_modules` los binarios nativos de Linux
  (`lightningcss-linux-x64-gnu`, `@tailwindcss/oxide-linux-x64-gnu`): todas las páginas dan 500 por el CSS.
  Para las capturas se instalaron a mano con `npm install --no-save`, sin tocar `package.json` ni el lock.
  Arreglo: que el setup del entorno corra `npm ci` en Linux.
