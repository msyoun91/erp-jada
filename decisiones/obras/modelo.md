# Obras — Modelo de datos, alcance y SQL

## Nombre: nada de CRM

La spec prohíbe explícitamente "CRM", "Comercial", "Prospectos" y "Oportunidades" como nombre visible. El módulo administra el universo de obras y sus relaciones, no un pipeline de ventas. `modulo = 'obras'` cumple.

Hay un antecedente: existió un módulo `comercial` que se eliminó entero en `sql/026`. Este no es su continuación con otro nombre — no hay prospecto, ni etapa, ni monto, ni probabilidad, y no se van a agregar en fase 1.

---

## Sin CUIT

La spec lo pedía como identificador fuerte anti-duplicados. El usuario decidió sacarlo. La detección de empresas queda por razón social y nombre comercial difusos (`pg_trgm`), que es peor pero suficiente: no hay constraint duro de unicidad de empresa.

---

## Los mensajes de la base los deja pasar una lista blanca de códigos

Este archivo decía "el mensaje viene de la base" y `sql/027` §13 decía "el mensaje dice cuántas obras, nunca cuáles". Ninguna de las dos era cierta: las diez `RAISE EXCEPTION` del módulo salían sin `ERRCODE`, Postgres las emitía como `P0001`, y `mensajeError()` resuelve por `error.code` contra un mapa donde `P0001` no está. Todas terminaban en "No se pudo completar la operación. Intentá de nuevo." — incluida la que existe para decir un número.

**Decidido:** clase `OB001`–`OB010` (`sql/032`), y `mensajeError()` devuelve el texto de la base cuando el código matchea `/^OB\d{3}$/`.

No se copió el patrón de `tareas`, que mapea código → texto en TypeScript, porque dos de estos mensajes llevan el conteo de obras. Un texto fijo en el mapa perdería justo el dato por el que el mensaje existe, y escribirlo en los dos lados sería la duplicación que CLAUDE.md prohíbe.

Entonces la clase `OB` no es un índice de textos: es la marca de "esto está escrito para que lo lea un usuario". La lista blanca es por código y no por confiar en el mensaje — un `P0001` nuevo, o cualquier error interno de Postgres, sigue cayendo en el genérico.

**Regla que queda:** un `RAISE EXCEPTION` de este módulo sin `USING ERRCODE` es un mensaje que nadie va a leer.

---

## Cuatro campos se fueron de la ficha

`cantidad_unidades`, `superficie_estimada`, `fecha_estimada_inicio` y `fecha_estimada_compra` salieron por pedido del usuario (`sql/030`).

Se dropearon las columnas en vez de esconderlas en la UI: un campo que ningún formulario escribe y ninguna vista muestra no es dato, es esquema muerto que igual aparece en `database.types.ts` y en cada `select *`. "Nunca DELETE" protege filas de negocio, no columnas — y la tabla tenía 0 filas, así que no había historia que perder. Si vuelven, vuelven como migración.

Con las columnas se fueron sus dos CHECK (> 0) y su lugar en el `GRANT UPDATE` por columna de `sql/027`: Postgres actualiza el privilegio solo.

---

## El test de RLS no puede depender de los permisos reales

`sql/tests/rls_obras.sql` afirma cosas sobre lo que **no** se puede hacer, y el caso 16 necesita a Admin sin `obras_transferir`. Corrido después de que el usuario se asignara los 15 submódulos del módulo en la app, el 16 transfirió de verdad y el 17 murió con "la obra ya es de ese usuario": el test no fallaba por una regresión, fallaba porque leía el estado de permisos de producción.

El setup ahora apaga todo `obras` de los dos usuarios antes de prender la lista que el test quiere. Sigue revirtiéndose entero con el `RAISE EXCEPTION` final.

---

## Enums, no tablas de catálogo

`tipo_obra`, `origen_obra`, `motivo_perdida`, `rol_empresa`, `rol_persona`, `provincia` son enums de Postgres.

**Consecuencia asumida:** agregar un tipo o un rol nuevo requiere migración, no se hace desde la app. Se eligió a criterio del desarrollador contra la alternativa (5 tablas de catálogo + su ABM + sus permisos + relaciones puente en vez de arrays). Si el usuario termina pidiendo agregar valores solo, revisar esta decisión — no antes.

`provincia` es enum por una razón distinta: `localidad` quedó texto libre, y con las dos libres el filtro por ubicación de la spec muere el primer día entre "CABA", "Capital" y "C.A.B.A.".

---

## `estado_obra`: los estados comerciales entran antes de presupuestos (`sql/046`)

Pedido del usuario. `estado_obra` pasó de `idea` / `en_construccion` / `perdida` / `terminada` a
`idea` / `en_cotizacion` / `en_ejecucion` / `en_postventa` / `perdida` / `terminada`. `en_construccion`
salió; las 4 obras que lo tenían (todas seed dummy) se remapearon a `en_ejecucion`.

Postgres no deja quitar un valor de un enum, así que `sql/046` reconstruye el tipo: rename a
`_old`, `CREATE TYPE` nuevo, `ALTER COLUMN ... USING` con el remapeo, `DROP TYPE _old`. Hubo que
soltar y recrear el CHECK `obras_perdida_con_motivo` porque referencia la columna.

**`estado_obra` queda en estos seis valores.** La dirección de bajarlo a tres cuando existiera
presupuestos —mudar `perdida` / `motivo_perdida` al presupuesto y sumar `obras_unidades` y
`cantidad_unidades` para la postventa por propietario— salió de `BACKLOG.md` el 2026-09-14 sin
implementarse; el texto, en git (`a1989e5`). La columna sigue midiendo en un solo campo el reloj del
edificio (`terminada`) y el comercial.

La UI no necesitó tocarse: `ObraFormPanel`, `ObrasView` y las fichas leen `ESTADOS_OBRA` /
`LABEL_ESTADO` / `BADGE_ESTADO` de `types.ts`. Badges nuevos: `en_cotizacion` → `badge-warning`,
`en_ejecucion` → `badge-info`, `en_postventa` → `badge-brand`.

---

## Desactivar

Nunca DELETE, `activo = false` en las 7 tablas de negocio (los dos logs no tienen `activo` — una fila de log significa "esto pasó").

`obras_desactivar` es función aparte de `obras_editar`: cargar y corregir datos no es lo mismo que hacer desaparecer una obra.

Desactivar una obra **no** cascadea sobre sus vínculos — así se puede reactivar tal como estaba.

Desactivar una empresa o persona **sí** está bloqueada si participa en alguna obra activa, porque son compartidas y el daño cae sobre obras que quien desactiva ni siquiera puede ver. Cuando sí procede, se llevan sus filas de `obras_persona_empresa` para no dejar un cargo colgado de una entidad inactiva.

---

## Sin widget de dashboard, sin portal de clientes

Ambas descartadas explícitamente por el usuario para fase 1. Nada de este módulo va a `erp-cliente` ni a `sync-contracts` (retirado a `obsoletos/`).

---

## Bug que vale recordar: RLS + `INSERT ... RETURNING`

La policy de SELECT de `obras_personas` resolvía todo llamando a `obras_puede_ver_persona(id)`, que **relee la fila desde la tabla**. En un `INSERT ... RETURNING` — que es lo que hace `.insert().select()` de Supabase — esa fila todavía no está en el snapshot de una función `STABLE`, así que el creador no podía leer lo que acababa de escribir: `42501`.

Crear una persona habría fallado siempre en la app. Lo cazó `sql/tests/rls_obras.sql` en la primera corrida.

**Regla que queda:** si una policy de SELECT tiene que autorizar la fila recién insertada, la condición se prueba **como columna** (`creado_por = auth.uid()`), no dentro de una función que la relee. Las funciones helper sirven para autorizar por filas de *otras* tablas.

---

## Fuera de alcance de fase 1

No implementar sin pedido explícito: prospectos, oportunidades, pipeline, actividades, interacciones, tareas, seguimientos, recordatorios, productos, servicios, catálogo, presupuestos, ventas, márgenes, precios, cotizaciones, forecast, negociaciones, liquidación de comisiones, facturación, automatizaciones, WhatsApp, email integrado, calendario, scoring.

La comisión de fase 1 **solo se registra**. No se liquida, no se paga, no se calcula sobre nada.

~~Ver `BACKLOG.md` para el buscador global obra/empresa/persona, decidido pero fuera de fase 1.~~ — **implementado** en `sql/037`, ver *El buscador global no inventa visibilidad*.

---

## GRANT UPDATE por columna en las cuatro tablas que faltaban

`obras` ya lo tenía desde `sql/027`. Las otras cuatro tenían `UPDATE` entero: con eso, un PATCH por PostgREST se auto-aprueba poniendo `pendiente = false`, y toda la cola es decorativa. Ocultar el botón no autoriza.

De paso salieron `creado_por` y las columnas `_norm`, que nunca tuvieron por qué ser escribibles desde el cliente.

Es fácil dejar la lista corta y romper editar o desactivar sin que nada avise, así que los casos 13 a 15 de `obras_033.sql` afirman que los `UPDATE` que la app sí hace siguen andando.

---

## Bug que vale recordar: `AND` no corta la referencia a `NEW`

`obras_guard_congelado` es un solo trigger para cuatro tablas, y arrancó escrito como `IF TG_TABLE_NAME IN (...) AND EXISTS (... NEW.obra_id ...)`.

plpgsql planea cada expresión entera la primera vez que la ejecuta, y no hay short-circuit a nivel de plan: sobre `obras_persona_empresa` —que no tiene `obra_id`— reventaba con `42703 record "new" has no field "obra_id"`. Vincular una persona a una empresa fallaba siempre, desde cualquier pantalla.

**Regla que queda:** en un trigger compartido entre tablas, la referencia a `NEW.<columna>` va adentro de un `IF` anidado bajo el chequeo de `TG_TABLE_NAME`, nunca del mismo lado de un `AND`. Lo cazó `obras_033.sql` en la primera corrida.
