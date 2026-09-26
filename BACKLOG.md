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
  - **Pasos que se completan solos (decidido 2026-09-25, `decisiones/obras.md` → *Dos acciones*).**
    Solo en plantillas con "Sobre". El paso guarda la condición con la misma forma que el disparo:
    `relacion_alta` + rol, o `estado` + valor. Un consumidor más de `AFTER INSERT ON eventos` completa
    los pasos abiertos de hilos activos sobre ese registro. También se evalúa al nacer el paso y al
    habilitarse: rol = que el registro lo tenga (`relacionados_de_registro`); estado = que esté en él
    (si ya avanzó, lo completa el asignado a mano). Corre en cascada, así que las reglas de actor no
    aplican (`escrituras.md` → *Directo o sistema*); anotarlo como decisión en `catalogo.md` y
    contrastarlo con "completar es solo del asignado" (`participacion.md`). Un pedido sin aceptar no se
    completa: se evalúa al aceptarlo. El resultado dice "Se vinculó un arquitecto a la obra", sin el
    nombre: puede leerlo alguien de otro equipo que no ve los contactos. Desvincular después no lo
    reabre. El asignado lo puede completar a mano igual.
    Link de acción: `{@accion|texto}` en la descripción de la plantilla, sacado de la condición; abre
    la ficha del registro al lado con `?vincular={rol}` (panel de Contactos) o `?estado={valor}`.
    Texto plano si el asignado no ve el registro.

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

**8. Equipos en plantillas: falta el dato de prueba, no código.** `asignado_equipo_id` en
`tareas_plantillas_pasos` (`sql/118`) y el grupo "Equipos" en `AsignadoSelect` ya existen, pero solo
listan equipos con delegador activo, y el único de la base ("Prueba") está inactivo y sin miembros.
Para probar: un equipo activo con delegador.

## Contactos y Obras — fichas aprobadas, falta el SQL (2026-09-25)

`decisiones/contactos.md` y `decisiones/obras.md`, aprobadas el 2026-09-25. Siguiente: cerrar los
huecos de la revisión (abajo), de a uno, y después SQL de Contactos (`GUIDE_MODULO_NUEVO.md` paso 1,
con su *Pendiente*). Orden:
Contactos → Obras (con el paquete de Tareas "con el primer emisor", arriba) → Catálogo → Presupuestos
→ Post-venta.

**Revisión de las fichas (2026-09-25): Obras 8/10, Contactos 7/10.** Huecos abiertos, por peso (cerrados: persona en otra agenda → "es la misma"; `contratada` irreversible → se revierte con causa; jefe de un participante → solo ve; comisión → la toca solo quien la ve; editar esquiva el congelado → editar también congela); cada
decisión va a `decisiones/<modulo>.md` antes de pasar al siguiente.

1. **Personas huérfanas sin cómo encontrarlas.** Con dueño inactivo "la transfiere el admin", pero
   Contactos no tiene filtro ni campanita de huérfanas, como Obras.
2. **El aprobador de contactos** "ve el alta completa" y "no ve datos de contacto": ¿ve el teléfono de
   la congelada (y queda registrado) o solo "mismo teléfono"?
3. **Desactivar y fusionar persona o empresa.** Quién desactiva, qué pasa con sus vínculos (¿desaparece
   de las 12 obras?); fusionar no está definido (de quién queda si eran de dos agendas).
4. **Unique del vínculo con `hasta`.** Un vínculo cerrado sigue `activo`, así que el unique parcial por par
   (`GUIDE_ENTES.md` §2.6) no deja re-vincular al capataz que vuelve: `WHERE activo AND hasta IS NULL`.

Ya decidido para los módulos que vienen detrás, al fichar Obras:
- **Catálogo** (servicios y productos): de ahí salen los ítems de los presupuestos.
- **Presupuestos**: uno por etapa de la obra (FK `obra_id`), con versiones (congeladas al enviarse) e
  ítems del catálogo con el precio copiado. Su estado es el operativo (en cotización, aprobado, en
  producción…) y es lo que mueve a administración, producción y logística: sus plantillas de
  ejecución y el seguimiento comercial al entregar cuelgan del presupuesto, no de la obra. El primer
  presupuesto pasa la obra a `en_cotizacion` y el primero aprobado a `contratada`. La ficha de la
  obra lista sus presupuestos con su estado actual. Los contactos operativos (capataz, quien recibe)
  se vinculan al presupuesto. A decidir: cómo ve logística el nombre y la dirección de una obra que no
  abre (propuesta: la etapa guarda su dirección de entrega).
- **Post-venta**: módulo aislado para su equipo. La unidad (1°C, local, casa) se arma después,
  eligiendo ítems del presupuesto aprobado ("estas 4 ventanas → 1°C"); si un ítem agrupa varias
  unidades, se lleva ítem y cantidad. Una obra de un solo dueño es una unidad con todo. Propietarios e
  inquilinos, vínculos de Contactos con `desde` / `hasta`; el seguro, un contrato de la unidad.

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
