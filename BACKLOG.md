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
aplicado; `sql/tests/tareas_nombres.sql` pasa entero. `sql/122` (vínculos siguen al `activo` del
paso) aplicado; `sql/tests/tareas_vinculos.sql` pasa entero. `sql/123` (sin referencias fijas en
plantillas) aplicado; `sql/tests/tareas_plantillas.sql` pasa entero. `sql/124` (`buscar_registros`,
"Relacionar") aplicado; `sql/tests/tareas_buscar.sql` pasa entero. Falta:
- Con el primer emisor (obras), todo junto (decidido 2026-09-24, `decisiones/tareas/catalogo.md`
  desde *La plantilla dice "Sobre"*, y `avisos.md` → *Un disparo avisa una vez*): "Sobre" en la
  plantilla, registro (ente e id) y plantilla de origen en el hilo, `{@registro}` y `{@ente:rol}`,
  activaciones y `disparar_plantillas`, `{dato}`, `{si hay}`, condiciones y pasos condicionados, los
  avisos "plantilla disparada" y "plantilla fallida". "Sobre" espera al disparo: existe para él, y
  con `hilo` como único ente se probaba contra el ente que no dispara. Al construir:
  - `disparar_plantillas` DEFINER, con los chequeos a mano (dueño puede recibir, submódulo del
    ente, visibilidad con `_de`). TA021 no revisa por ser DEFINER, no por la profundidad.
  - `usar_plantilla` filtra por `auth.uid()`: o recibe el usuario desde `disparar_plantillas` o
    comparten una interna DEFINER sin EXECUTE para `authenticated`.
  - Core: columna de dueño en `entes`; `_de` de `etiqueta_registro` y `relacionados_de_registro`.
  - "No se repite": chequeo en la función, no unique index (la recurrencia).
  - `guardar_plantilla` valida las marcas contra "Sobre"; policy de plantillas con la rama del ente
    visible y la de `tareas_administrar`.

UI: vistas Hilos (`/tareas`, `/tareas/{id}`, `/tareas/paso/{id}`), Misión (`/tareas/mision`),
Equipo (`/tareas/equipo`), Plantillas (`/tareas/plantillas`, con "Usar plantilla" desde el hilo) y
Todas (`/tareas/todas`) hechas. Las referencias `{ente:uuid|nombre}` son link ↗ si quien lee las
abre (`getEnlaces`) y navegan a la ficha. Falta: la ficha al lado en split
(`decisiones/tareas/registro.md`) — va con el primer ente de otro módulo; hoy solo hay `hilo` y
`tarea`, cuya ficha es el hilo mismo.

Ficha: `decisiones/tareas/README.md`; esquema: `db_schema/tareas.md`.

## tareas — hallazgos de la prueba con dos usuarios (2026-09-24)

Prueba en Chrome con Admin (independiente, `tareas_administrar`) y Tester (independiente, con
`tareas_ver`, `tareas_mision`, `tareas_plantillas`, `tareas_pedir`). Todo lo demás del módulo pasó:
cadena, plazo relativo, insertar antes, pedidos (solicitar → aceptar → editar vuelve a
`solicitada` → rechazar → volver a pedir), devolver, reasignar, espera, cancelar, desactivar,
transferir, cerrar/reabrir, reabrir en cascada, plantillas y Catálogo, Todas y los 13 avisos.
Datos de prueba que quedaron en la base para reproducir: hilos "Cocina Pérez — presupuesto",
"Cocina Pérez — compra e instalación", "Instalador para cocina Pérez", "Visita técnica — Gómez"
(Tester) y "Prueba de hilo" (solo Admin); plantilla "Visita técnica" publicada por Tester y su
copia en Admin. Antes de tocar cada punto, contrastar contra las personas de la ficha
(`decisiones/tareas/README.md`).

**3. No hay link de vuelta ("mencionado en") — decidir primero.** `tareas_vinculos` tiene el dato
pero ninguna vista lo muestra: en "Cocina Pérez — presupuesto" no aparece que dos pasos de otros
hilos lo referencian. `registro.md` dice que el vínculo queda "como dato (hilos de un registro…)" y
que su RLS es la del hilo que referencia (ya recorta bien: `tareas_vinculos_select` pasa por
`tareas`). Preguntar al usuario si el hilo y el paso muestran "Mencionado en" (lista de pasos que
los referencian, con link) o si eso espera a la ficha de otro módulo. Si va: query en
`queries.ts` sobre `tareas_vinculos` `WHERE activo AND ((ente='hilo' AND registro_id=hilo) OR
(ente='tarea' AND registro_id IN pasos))`, sección en `HiloView.tsx` y en el panel del paso.

**6. En un hilo cerrado el paso no ofrece "Reabrir" — alinear ficha o UI.** La ficha dice "sumar o
reabrir un paso lo reabre" (el hilo); la UI oculta "Sumar paso" y las acciones del paso con el hilo
cerrado, así que primero hay que reabrir el hilo. Verificar en `sql/113` si la base acepta reabrir
un paso de un hilo cerrado (y si reabre el hilo). Si sí: preguntar al usuario si se muestra
"Reabrir" en el paso (atajo) o si se corrige la ficha a "se reabre el hilo primero". Si no: corregir
la ficha. `PasoPanel.tsx` (línea ~92) tiene la condición de "Reabrir".

**8. Equipos en plantillas: falta el dato de prueba, no código.** `asignado_equipo_id` en
`tareas_plantillas_pasos` (`sql/118`) y el grupo "Equipos" en `AsignadoSelect` ya existen, pero solo
listan equipos con delegador activo, y el único de la base ("Prueba") está inactivo y sin miembros.
Para probar: un equipo activo con delegador.

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
