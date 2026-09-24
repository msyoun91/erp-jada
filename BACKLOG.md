# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## usuarios — equipos y delegación de permisos

Decidido el 2026-09-23. Base completa: esquema en `sql/104`, reglas en `sql/105`, pestaña Equipos del
admin en `sql/106` (tests en `sql/tests/usuarios_equipos.sql`), vista Mi equipo. Falta:
- **"Gana el admin" explícito:** `asignar_submodulos` no cambia de dueño una fila que ya está activa,
  así que guardar el panel no se apropia de lo delegado. Para que el admin tome una fila del delegador
  hace falta un gesto propio en el panel (y un parámetro o función que lo exprese).

Todo está escrito en `decisiones/usuarios.md` → *Equipos y delegación de permisos*.

## tareas — reglas entre permisos, con la migración del módulo

`submodulo_reglas` (`sql/110`) ya existe; faltan las filas de tareas, que no se pueden cargar antes
que sus submódulos:
- Las del bloque *Reglas entre permisos* de la ficha (`decisiones/tareas.md`), y `delegable` según
  su lista de delegables.
- `designar_delegador` y `quitar_delegador` tienen que respetarlas: dan y quitan `tareas_equipo`
  junto con `usuarios_delegar` (se requieren mutuamente). Ninguna otorga `tareas_ver`: si el heredero o
  designado no lo tiene, fallan con US016 y el panel avisa.
- Correr de nuevo `sql/tests/usuarios_equipos.sql`: sus delegadores de prueba no tienen `tareas_ver`
  ni `tareas_equipo`.

Decisión: `decisiones/global/permisos.md` → *Reglas entre permisos*; ficha: `decisiones/tareas.md`.

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
