# Obras — Duplicados, aprobaciones y logs

## Aviso ciego de duplicados

> **Actualizado por *MODEL A* / `sql/042`.** La obra ajena ahora devuelve el **nombre** (sin dirección ni localidad); `obra_id` sigue NULL. Mismo criterio ahora en empresas (`obras_buscar_duplicados_empresa` pasó a DEFINER + enmascarado).

Conflicto real: la spec pide avisar si ya existe una obra parecida, pero las obras ajenas son invisibles. Si el aviso no salta, dos vendedores cargan el mismo edificio.

**Decidido:** `obras_buscar_duplicados_obra` es `SECURITY DEFINER` y de una obra ajena devuelve **solo el nombre del responsable** — `obra_id`, `nombre`, `direccion` y `localidad` vienen NULL. Alcanza para ir a preguntar, no para leer la cartera del otro.

Es una excepción consciente a la preferencia por `SECURITY INVOKER`: la función tiene que ver más de lo que ve quien la llama. Está acotada a devolver un solo campo.

Mismo criterio en el mensaje del trigger que bloquea desactivar una empresa: dice **cuántas** obras, nunca cuáles.

---

## Los logs se miran por función, no por policy

`obras_accesos_persona` y `obras_transferencias` se escribían desde el día uno y no se leían desde ningún lado: el registro de accesos es lo que justifica que `obras_ficha_persona()` sea el único camino al contacto, y sin pantalla el módulo pagaba el costo del log sin cobrar el beneficio. `getTransferencias` ya existía en `queries.ts` y ningún componente la llamaba.

**Decidido:** vista nueva `obras_auditoria` (tab, como las otras tres), servida por `obras_auditoria_accesos()` y `obras_auditoria_transferencias()` — `SECURITY DEFINER` con guard propio, tope de 500 filas.

Por función y no abriendo las policies porque quien audita necesita ver los accesos de **todos** y el nombre de la persona para que la fila signifique algo, pero no tiene por qué tener permiso sobre la agenda ni sobre las obras ajenas. Con un `select` + embed, un auditor sin `obras_personas` habría recibido el log entero con la persona en NULL: el log completo sin poder leerlo.

**El submódulo es propio y no `obras_personas_todas`.** Ese permiso es "ver la agenda completa"; este es "ver quién la estuvo mirando". Son dos cosas distintas y conviene poder darlas por separado — de hecho, lo esperable es que quien audite no tenga la agenda.

La función de accesos devuelve nombre y apellido y nada más. La pantalla que vigila el acceso al contacto no puede ser otra puerta al contacto.

La ficha de obra, además, muestra su propio historial de responsables: la obra la ve su responsable actual, así que "¿por qué no la veo más?" necesita respuesta en el lugar donde se hace la pregunta.

---

## La localidad ordena el aviso de duplicados, no lo filtra

Hasta `sql/031`, `obras_buscar_duplicados_obra` exigía `localidad_norm = obras_normalizar(p_localidad)`. Igualdad exacta sobre un campo de texto libre que cada uno escribe como quiere: los datos de prueba lo mostraron enseguida — "Devoto" contra "Villa Devoto" y el aviso ciego no salta. El nombre ya se compara por trigram; la localidad, no.

**Decidido:** sale del `WHERE` y entra al `ORDER BY`. Escrita igual sube la fila al tope, que es todo lo que aportaba; escrita distinta ya no puede esconder una obra que el nombre o la dirección marcaron como parecida.

---

## El chequeo de duplicados también corre al editar

`chequearDuplicados` arrancaba con `if (obra) return` en los tres paneles. Renombrar una obra hacia una que ya existe es tan duplicado como cargarla dos veces, y no avisaba.

Lo que faltaba para poder correrlo al editar era `p_excluir_id`: sin él la fila se encuentra a sí misma con similitud 1 y avisa de un duplicado que es ella.

---

## Congelada, no marcada

> **Recortado por *MODEL A* / `sql/040`.** Solo el **alta** parecida se congela. El "vínculo con una persona o empresa de otro" ya no existe como estado: bajo model A no se puede vincular lo que no se ve, así que se dropeó `pendiente` de las dos tablas de vínculo y `obras_guard_congelado` entera.

Pedido del usuario: un alta que se parece a algo ya cargado, y un vínculo con una persona o empresa de otro, esperan autorización. La pregunta que decidía el diseño era qué puede hacer el que cargó mientras espera. **Decidido: nada.** La fila existe, la ve solo quien la creó, y no acepta ni participa de ningún vínculo hasta que se resuelva (`sql/033`).

La alternativa —badge y a otra cosa— dejaba al duplicado propagándose por las obras mientras la cola espera, que es justo lo que la cola viene a evitar.

Sin estado nuevo: `pendiente = true` es la cola, `pendiente = false` con `activo` es el resultado, y rechazada es `activo = false` con `motivo_rechazo`. Los dos booleanos que ya existían alcanzan.

**El rechazo desactiva, no fusiona.** Mudar los vínculos de la fila nueva a la original es una función de migración bastante más grande, y hoy la fila nueva casi nunca tiene vínculos: está congelada justamente. Si aparece el caso, se revisa.

---

## El vínculo pendiente no abre la ficha

> **Superado por *MODEL A* / `sql/039`–`040`.** Ya no hay vínculo pendiente. `obras_puede_ver_persona` dejó de contar **cualquier** vínculo: para ver una persona hay que ser su dueño, tener grant, o `obras_personas_todas`. El WITH CHECK de `obras_obra_persona_insert` exige visibilidad — no se vincula lo que no se ve.

Es el punto entero del pedido 2, y lo que lo hace algo más que un trámite: `obras_puede_ver_persona` dejó de contar los vínculos pendientes. Si los contara, el vendedor vincularía, leería el teléfono por `obras_ficha_persona()` y esperaría el rechazo sentado — con el dato ya copiado.

Dicho de otro modo: hasta `sql/033`, encontrar a alguien en el buscador de identidad mínima y vincularlo a una obra propia era todo lo que hacía falta para llegar al celular. Ahora eso pasa por un tercero.

---

## La detección corre en la base, y por eso hubo que partir las tres búsquedas

El aviso de duplicados era una advertencia que el usuario podía ignorar. Ahora además decide si la fila entra congelada, así que no puede depender de que el cliente confiese que lo vio: el trigger es la barrera.

Pero los triggers necesitaban el criterio de parecido **sin** el enmascarado ni el guard de permiso que esas funciones aplican al resultado. Con `obras_buscar_duplicados_*` tal como estaban, la detección habría dependido de qué permisos tiene quien crea.

**Decidido:** cada una se parte en dos. `obras_similares_*` hace el match crudo (ids y score, sin mirar quién pregunta) y `obras_buscar_duplicados_*` queda como capa de enmascarado con firma idéntica —los `GRANT` sobreviven al `REPLACE` y `actions.ts` no se entera—. Un solo umbral, un solo criterio, tres consumidores: la pantalla, el trigger y la cola.

`obras_similares_empresa` es la única de las tres con `GRANT` a `authenticated`, porque el envoltorio de empresas sigue siendo `SECURITY INVOKER` —así la policy de `obras_empresas` sigue decidiendo qué ve cada uno— y por lo tanto la ejecuta como quien llama.

---

## ~~Lo que el rechazo todavía no resuelve~~ — resuelto por `sql/038`

~~Rechazar desactiva la fila, así que sale de los listados: quien la cargó se entera solo si entra a la ficha por URL directa. El motivo está guardado y la ficha lo muestra, pero nadie le avisa.~~

~~No se resolvió acá porque el módulo no tiene ningún canal de aviso y armarlo para esto sería construir media notificación. Queda en `BACKLOG.md` con el camino barato anotado.~~

El canal existe: `trg_notificar_decision_obra` sobre `obras_aprobaciones` le manda el aviso al solicitante con el motivo y el link a la ficha, aprobada o rechazada. Ver `decisiones/global/infra.md` → *Notificaciones: infra sin submódulo, y sin motor*.

Dos cosas del módulo cambiaron para eso, las dos verificadas contra las 72 filas de las cinco tablas: `obras_etiqueta` pasó a `SECURITY INVOKER` (otorgarla siendo DEFINER habría sido un bypass del aviso ciego de `sql/037`) y el mapa "de esta fila, quién pidió el alta" salió del UNION de `obras_pendientes()` a `obras_solicitante(tipo, id)`, que ahora usan los dos.
