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

**1. Falta "Todo completado — cerrar" (decidido, sin implementar).** `decisiones/tareas/modelo.md`
→ *El hilo lo cierra el responsable, a mano*: cuando no queda nada abierto, el hilo lo muestra.
Hoy solo se cierra desde el menú "…". Dónde: `components/HiloView.tsx` ya calcula `abiertos`
(línea ~47) y abre `CerrarHiloModal` con `setDialogo("cerrar")` (línea ~64); falta el aviso con
botón cuando `abiertos === 0`, hay pasos activos, `dueno && vivo`. Solo UI, sin SQL.

**2. Falta el botón "Relacionar" (decidido, sin implementar).** `decisiones/tareas/registro.md` →
*Referencias en el texto en vez de chips*: "textarea + 'Relacionar' que inserta la marca, con vista
previa". Hoy la referencia se escribe a mano como `{hilo:uuid|nombre}` o `{tarea:uuid|nombre}`,
lo que exige conocer el uuid. Buscador sobre lo que quien escribe puede ver (hilos y pasos; volver
`buscar_registros` de core si hace falta, ver *Lo que el módulo necesita de afuera* en el README)
que inserta el token en la descripción del paso (`PasoFormPanel.tsx`, editar e insertar antes) y
vista previa con `TextoConReferencias`. Editor enriquecido: no, sería librería nueva.

**3. No hay link de vuelta ("mencionado en") — decidir primero.** `tareas_vinculos` tiene el dato
pero ninguna vista lo muestra: en "Cocina Pérez — presupuesto" no aparece que dos pasos de otros
hilos lo referencian. `registro.md` dice que el vínculo queda "como dato (hilos de un registro…)" y
que su RLS es la del hilo que referencia (ya recorta bien: `tareas_vinculos_select` pasa por
`tareas`). Preguntar al usuario si el hilo y el paso muestran "Mencionado en" (lista de pasos que
los referencian, con link) o si eso espera a la ficha de otro módulo. Si va: query en
`queries.ts` sobre `tareas_vinculos` `WHERE activo AND ((ente='hilo' AND registro_id=hilo) OR
(ente='tarea' AND registro_id IN pasos))`, sección en `HiloView.tsx` y en el panel del paso.

**4. Referencias en plantillas y en el Catálogo — decidir primero.** Hoy:
- `guardar_plantilla` (`sql/118`, línea ~158) guarda cualquier `{ente:uuid|nombre}` sin revisar
  si el dueño lo ve; falla recién al usar (`usar_plantilla` → trigger `tareas_derivar_vinculos`,
  TA021), sin quedar "a revisar" (`motivoRevisar` en `derivados.ts` no mira la descripción).
  Probado con la plantilla "Ref ajena" (desactivada).
- Publicar lleva la referencia al Catálogo y `copiar_plantilla` (`sql/118`, línea ~216) la copia:
  el nombre del hilo ("Cocina Pérez — presupuesto") queda a la vista de todo el que lee el
  Catálogo, aunque no participe del hilo. `registro.md` justifica mostrar la copia del nombre
  porque "lo contó quien sí lo veía" a los que ven el hilo; en el Catálogo el público es otro.
- `PlantillasView.tsx` (línea ~133) muestra la descripción cruda, con el uuid.

Opciones para proponer al usuario: (a) validar referencias al guardar (misma regla TA021) y sumar
"a revisar" si una deja de verse; (b) al publicar o copiar, convertir cada token a su nombre en
texto plano (o quitarlo); (c) prohibir referencias en plantillas (hoy el `{dato}` cubre el caso
real: la referencia llega con el disparo). Recomendación: (c) + (b) para lo ya guardado — una
plantilla es reusable y una referencia fija a un registro concreto casi nunca lo es. La regla va
en `guardar_plantilla` (Postgres), no en `actions.ts`; registrar en `catalogo.md` o `registro.md`.

**5. El token aparece crudo en notas.** Por diseño solo la descripción del paso lleva referencias
(`registro.md`), pero si alguien pega `{hilo:uuid|nombre}` en una nota se ve el uuid. Mostrar solo
el nombre, sin link: en `NotasSection.tsx` (línea ~62) `n.texto.replace(REFERENCIA, "$3")`
(`REFERENCIA` de `derivados.ts`). Mismo tratamiento para resultado de paso y de hilo si se decide
(revisar dónde se renderizan en `PasoPanel.tsx` y `HiloView.tsx`). Solo UI.

**6. En un hilo cerrado el paso no ofrece "Reabrir" — alinear ficha o UI.** La ficha dice "sumar o
reabrir un paso lo reabre" (el hilo); la UI oculta "Sumar paso" y las acciones del paso con el hilo
cerrado, así que primero hay que reabrir el hilo. Verificar en `sql/113` si la base acepta reabrir
un paso de un hilo cerrado (y si reabre el hilo). Si sí: preguntar al usuario si se muestra
"Reabrir" en el paso (atajo) o si se corrige la ficha a "se reabre el hilo primero". Si no: corregir
la ficha. `PasoPanel.tsx` (línea ~92) tiene la condición de "Reabrir".

**7. Los vínculos de un paso desactivado quedan `activo = true`.** El trigger
`tareas_derivar_vinculos` (`sql/119`, línea ~113) corre solo `ON INSERT OR UPDATE OF descripcion`.
No filtra a nadie (la RLS de vínculos pasa por `tareas`, y un paso desactivado solo lo ve
`tareas_administrar`), pero cuenta como mención viva para el admin y para cualquier consumidor
futuro (punto 3, `plantilla_disparada`). Propuesta: sumar `activo` al `UPDATE OF` y, si
`NEW.activo = false`, desactivar sus vínculos; al reactivar, volver a derivarlos (sin chequear TA021:
lo reactiva el admin). Test en `sql/tests/tareas_vinculos.sql`; actualizar `db_schema/tareas.md`.

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
