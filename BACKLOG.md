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
    Texto plano si el asignado no ve el registro; si lo ve sin trabajarlo, link común a la ficha, sin
    `?vincular` ni `?estado` (`decisiones/global/entes.md` → *Ver un registro no es trabajarlo*).

UI: vistas Hilos (`/tareas`, `/tareas/{id}`, `/tareas/paso/{id}`), Misión (`/tareas/mision`),
Equipo (`/tareas/equipo`), Plantillas (`/tareas/plantillas`, con "Usar plantilla" desde el hilo) y
Todas (`/tareas/todas`) hechas. Las referencias `{ente:uuid|nombre}` son link ↗ si quien lee las
abre (`getEnlaces`) y navegan a la ficha. Falta: las fichas de los vínculos al lado, en pestañas
dentro del panel del paso ensanchado, y la del registro del hilo en su página — diseño cerrado en
`decisiones/tareas/registro.md` (2026-09-26). Va con el primer ente de otro módulo; hoy solo hay
`hilo` y `tarea`, cuya ficha es el hilo mismo.

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

## Contactos y Obras — tramo 1 hecho y probado (2026-09-28)

`decisiones/contactos.md` y `decisiones/obras.md`, aprobadas el 2026-09-25. Tramo 1, SQL aplicado el
2026-09-26: `sql/125` (core: `entes.roles`, `trabaja_registro`, `puede_abrir_registro`, emisores),
`sql/126` (obras), `sql/127` (contactos), `sql/128` (buscar o crear, `obras_alta`) y `sql/129`
(desactivar vínculos por función). Pasan enteros `sql/tests/entes_eventos.sql`, `obras_reglas.sql`,
`contactos_reglas.sql` y `obras_alta.sql`, y la regresión de Tareas y Usuarios. Esquema:
`db_schema/obras.md`, `db_schema/contactos.md`. Capa TypeScript hecha el 2026-09-28 (`types.ts`,
`permissions.ts`, `queries.ts`, `actions.ts` de los dos módulos, `lib/entes.ts`, `lib/validacion.ts`),
con `sql/130` (nombres y candidatos) y `sql/131` (`obras_a_cargo`). Pantallas escritas el 2026-09-28:
`/obras` (lista, Todas, ficha con estado, transferir y participantes; alta con "¿Quién?"),
`/contactos` (personas, empresas y sus fichas, "Ver contacto", historial) y el panel de vincular en la
ficha de la obra. Probado con `e2e/obras.spec.ts` ("Juan carga Torre Belgrano…": Tester carga y trabaja,
Admin la ve). Falta "Laura la ve sin tocar nada": ningún usuario de prueba tiene equipo ni `obras_equipo`;
entra con el tramo 2 (bajas y equipos). Tramo 2 en SQL, aplicado el 2026-09-28: `sql/132` (tipos de
campanita), `sql/133` (bajas, cambios de equipo, huérfanas; `asignar_equipo` con `p_agenda_al_jefe`),
`sql/134` (campanitas y `notificaciones_listar`), `sql/135`–`136` (permisos de `service_role` para la
entrega de la agenda). Pasan `obras_contactos_bajas.sql`, `obras_contactos_avisos.sql` y la regresión.
Pantallas del tramo 2: hecho el filtro "huérfanas" en Obras Todas (y "De {quien}" desde el aviso,
`?responsable=`), y en Personas y Empresas (asignar o cambiar el equipo de la empresa desde su ficha,
admin), y la casilla "su agenda pasa al jefe" en Usuarios al sacar del equipo o sumar a otro
(marcada por defecto). Probado con `e2e/obras.spec.ts` ("Juan se va…": el admin arma, si no está,
"Equipo Zqx pruebas" con Tester 2 de jefe comercial —delegador, con «Hilos» y "Jefe de equipo"—, saca a
Tester y su obra y su persona pasan a Tester 2). Tramo 2 cerrado. Tramo 3 (duplicados): decisiones cerradas el 2026-09-28 (qué es parecida, `congelada` + `congelada_antes` + `rechazo_motivo` en la fila, `contactos_vinculos_guardados` que autoriza el vínculo a nombre de quien cargó, "ver todo" incluye congeladas — `decisiones/obras.md` → *Altas parecidas*, `decisiones/contactos.md` → *Vincular*); SQL aplicado el 2026-09-28: `sql/137`–`sql/139`, probado con `sql/tests/duplicados.sql` (82/82) y la regresión de obras y contactos. Pantallas del tramo 3 hechas el 2026-09-28 (Por aprobar en Obras y Contactos, aviso a ciegas en altas, ediciones, vincular y "¿Quién?", marca "por aprobar" en las listas y aviso en la ficha; `obras_aprobar` / `contactos_aprobar` ya salen en Usuarios): probadas el 2026-09-28 con `e2e/duplicados.spec.ts` (el Admin recibe "Aprobar altas" de Obras y Contactos; Tester carga tres obras parecidas y una persona parecida, con el aviso a ciegas y en vivo en "¿Quién?"; el Admin aprueba, rechaza con motivo y resuelve "es la misma", con el referente guardado llegando a la existente). Aviso a ciegas también para la empresa nueva desde el campo empresa de una persona (2026-09-28, `VincularPanel.tsx`; probado en `e2e/duplicados.spec.ts`). Compartir empresa en SQL, aplicado el 2026-09-28: `sql/140` (`contactos_empresa_equipos`, `contactos_compartir_empresa`, y "es de mi equipo" en una sola función), probado con `sql/tests/contactos_compartir.sql` (34/34) y la regresión (`contactos_reglas.sql` 94/94). `sql/141` (2026-09-28): el aviso a ciegas ordena por parecido, así la igual no queda afuera del corte en 10; `duplicados.sql` 87/87. Pantalla de compartir empresa hecha el 2026-09-28: en la ficha, "Compartir con otro equipo" (su equipo o el admin) y "Compartida con" con la cruz para dejar de compartir; la compartida sale en la lista del otro equipo como "Compartida por {equipo}". Los equipos para compartir y para "Cambiar equipo" salen de `contactos_equipos()`. Probada con `e2e/contactos.spec.ts` (el admin pasa Caputo a "Equipo Zqx pruebas" y la comparte con "Equipo Zqx sur", donde suma a Tester, que la ve marcada y sin "Compartir"; al dejar de compartir, deja de verla; Tester sale de Sur al final). Además, `e2e/obras.spec.ts` (tramos 1 y 2) adaptado: lo que carga se parece a lo de corridas anteriores, así que hace "Crear igual" y el Admin aprueba lo de la corrida antes de seguir (`e2e/comun.ts`). **Tramo 3 cerrado (2026-09-28).** Quedan para después, sin función que los respalde: vincular a una
obra desde la ficha de la persona o la empresa (buscar "obras que trabajás"), y crear la empresa desde
"Sumar empresa" o la persona desde "Sumar persona" (hoy, solo existentes: crear y relacionar en un
paso pide una función, como `contactos_crear_y_vincular`). Orden de
módulos: Contactos y Obras → Catálogo → Presupuestos → Post-venta.

Para las pantallas: `contactos_personas` no tiene `select *` (teléfono y email fuera del GRANT);
transferir, desactivar (obra, persona, empresa, vínculo, persona ↔ empresa) van por sus funciones
DEFINER, no por UPDATE.

**Contactos y Obras van juntos, en tramos (2026-09-26).** Como Tareas: una migración por tema, cada
una con su test en `sql/tests/` y sus pantallas, y el primer tramo ya usable. Juntos porque un vínculo
no se prueba sin una obra a la que vincularlo.
1. **Lo básico** — persona, empresa, obra, vínculos, participantes; "lo ve" y "lo trabaja"; estados con
   motivo de pérdida y reversión; "Ver contacto" que registra (sacar el teléfono del SELECT después
   obliga a revisar cada pantalla que ya lo lee); historial de ediciones; transferir y desactivar;
   buscar o crear en el panel; "¿Quién?" en el alta. Prueba: Juan carga Torre Belgrano con Marta de
   referente, suma a Pedro, y Laura la ve sin tocar nada.
2. **Bajas** — bajas y cambios de equipo (obras y agenda), huérfanas, campanitas. Prueba: Juan se va y
   sus obras y su agenda llegan al jefe.
3. **Duplicados** — congelado de obra, persona y empresa, editar que congela, "Por aprobar", vínculos
   guardados, "es la misma", compartir empresa. Prueba: Pedro carga la Belgrano de Juan y el aprobador
   la resuelve.
4. **El resto** — comisión, widget de números, Auditoría, fusionar (razones sociales, descartadas el 2026-09-28).
   Decisiones cerradas el 2026-09-28: moneda y reemplazo de la comisión, período del widget
   (`decisiones/obras.md`); Auditoría, fusionar con comisión, congeladas y links viejos
   (`decisiones/contactos.md`). SQL aplicado el 2026-09-28: `sql/142` (comisión), `sql/143`
   (números), `sql/144` (Auditoría), `sql/145`–`146` (fusionar), cada una con su test. Pantallas: la
   comisión, en la fila del referente, y el widget "Obras" (2026-09-28). **Siguiente:** vista Auditoría, pantalla de
   fusionar (con `conservar` para elegir la comisión) y "Se fusionó con …" en la ficha vieja. El texto
   del aviso `persona_fusionada` en la campanita es provisorio.
5. **Tareas** — el paquete "con el primer emisor" (arriba): plantillas por estado, pasos que se
   completan solos. Prueba: el paso "vincular arquitecto" se cierra solo.

**Revisión de las fichas (2026-09-25): Obras 8/10, Contactos 7/10.** Los nueve huecos, cerrados el
2026-09-26 y escritos en `decisiones/contactos.md`, `decisiones/obras.md` y `GUIDE_ENTES.md` §2.6.

**Segunda revisión (2026-09-26): Obras 8,5/10, Contactos 7,5/10.** Cinco puntos, de a uno:
1. ~~Ver no es trabajar~~ — cerrado (`decisiones/global/entes.md`).
2. ~~Para contar, sin nadie que cuente~~ — cerrado: widget "Obras" y `obras_numeros`
   (`decisiones/obras.md`).
3. ~~"Es la misma" y el referente del alta~~ — cerrado: el vínculo pasa a la existente
   (`decisiones/obras.md`).
4. ~~La misma empresa en dos equipos~~ — cerrado: se pide con un pedido de Tareas y el equipo dueño
   la comparte (`decisiones/contactos.md`).
5. ~~El SQL sin cortes~~ — cerrado: cinco tramos (arriba).
- Menor, al escribir el SQL: la baja pasa las obras al jefe solo si tiene `obras_ver`, como Tareas
  pide `tareas_ver`.

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
