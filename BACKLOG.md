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

## tareas — el SQL del módulo, en curso

`sql/112` (esquema, catálogo, entes, visibilidad) y `sql/113` (escrituras y reglas: quién escribe
qué, transiciones, pedidos, cadena, cierre, desactivación, notas e historial) aplicados el
2026-09-24; `sql/tests/tareas_reglas.sql` pasa entero. Falta:
- Bajas, cambios de equipo y pérdida de `tareas_ver`: mover hilos y pasos abiertos al delegador
  (`bajas.md`), triggers sobre `usuarios.activo` y `equipos_miembros`.
- Avisos: `transferencia` en `tipo_evento`, `relacion_*` del asignado (con rama en
  `puede_ver_relacion`) y los tipos de la campanita de la ficha.
- La función de afuera para elegir a quién asignar o pedir (README → *Lo que el módulo necesita de
  afuera*).
- Plantillas, Catálogo, recurrencia y `tareas_vinculos`.

Ficha: `decisiones/tareas/README.md`; esquema: `db_schema/tareas.md`.

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
