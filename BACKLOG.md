# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## usuarios — equipos y delegación de permisos

Decidido el 2026-09-23. Base completa: esquema en `sql/104`, reglas en `sql/105` (tests en
`sql/tests/usuarios_equipos.sql`). Falta:
- **UI de admin:** equipos y miembros (escritura directa con `service_role`), `delegable`, y la
  salida del delegador con heredero y lista de "no copiar" → `quitar_delegador`. Desactivar al
  delegador o sacarlo del equipo falla con `US009` hasta que corra esa función.
- **"Gana el admin" explícito:** `asignar_submodulos` no cambia de dueño una fila que ya está activa,
  así que guardar el panel no se apropia de lo delegado. Para que el admin tome una fila del delegador
  hace falta un gesto propio en el panel (y un parámetro o función que lo exprese).
- **Vista "Mi equipo":** la llama `delegar_submodulos` con la sesión del delegador.

Todo está escrito en `decisiones/usuarios.md` → *Equipos y delegación de permisos*.

## erp-cliente — falta el `ThemeToggle`

Vive en `SidebarNav` y el portal no tiene sidebar todavía. Va cuando el portal arranque de verdad
(`decisiones/global/ui.md` → *El script de tema va en `<script>` plano*).

## El backlog de tareas y obras vive en `master`

Esta rama saca los dos módulos para rediseñar permisos desde cero (`sql/101`). Sus entradas
—el chip `?ctx=` de compartir al asignar, las tareas sobre el modelo de entes, la sugerencia de
tareas— siguen escritas en `BACKLOG.md` de `master`, junto con el código al que se refieren.

No se copian acá: describen funciones que en esta rama no existen. Si un módulo vuelve, vuelve su
entrada. Lo que sí tiene que sobrevivir al rediseño es el **diagnóstico**, no la reparación
concreta: `puede_abrir_registro` no contaba los grants contextuales, y por eso un usuario con
acceso otorgado igual no alcanzaba el contacto. La regla nueva tiene que contestar eso desde el
día uno, no dejarlo para después.
