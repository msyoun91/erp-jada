# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## tareas — el SQL del módulo, en curso

`sql/112` (esquema, catálogo, entes, visibilidad) y `sql/113` (escrituras y reglas: quién escribe
qué, transiciones, pedidos, cadena, cierre, desactivación, notas e historial) aplicados el
2026-09-24; `sql/tests/tareas_reglas.sql` pasa entero. `sql/114` (bajas y cambios de equipo)
aplicado; `sql/tests/tareas_bajas.sql` pasa entero. `sql/115` (avisos) aplicado;
`sql/tests/tareas_avisos.sql` pasa entero. `sql/116` (`tareas_asignables`) aplicado;
`sql/tests/tareas_asignables.sql` pasa entero. `sql/117` (recurrencia y "paso a reasignar")
aplicado; `sql/tests/tareas_recurrencia.sql` pasa entero. `sql/118` (plantillas y Catálogo)
aplicado; `sql/tests/tareas_plantillas.sql` pasa entero. `sql/119` (vínculos y referencias en la
descripción) aplicado; `sql/tests/tareas_vinculos.sql` pasa entero. `sql/120` (`tareas_nombres`)
aplicado; `sql/tests/tareas_nombres.sql` pasa entero. Falta:
- Con el primer emisor: `{dato}`, condiciones por rol, activaciones y `disparar_plantillas`
  (`decisiones/tareas/catalogo.md`).

UI: vistas Hilos (`/tareas`, `/tareas/{id}`, `/tareas/paso/{id}`), Misión (`/tareas/mision`),
Equipo (`/tareas/equipo`), Plantillas (`/tareas/plantillas`, con "Usar plantilla" desde el hilo) y
Todas (`/tareas/todas`) hechas. Las referencias `{ente:uuid|nombre}` son link ↗ si quien lee las
abre (`getEnlaces`) y navegan a la ficha. Falta: la ficha al lado en split
(`decisiones/tareas/registro.md`) — va con el primer ente de otro módulo; hoy solo hay `hilo` y
`tarea`, cuya ficha es el hilo mismo.

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
