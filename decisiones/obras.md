# Decisiones — Agenda de Obras

Módulo `obras`, ruta `/obras`, nombre visible **Agenda de Obras**. Fase 1: registro y relación de datos. Spec original en `spec.md` (fuera del repo).

Leer antes de tocar el módulo. Lo que está acá es lo que la spec **no** dice o dice distinto de como quedó implementado.

---

## Nombre: nada de CRM

La spec prohíbe explícitamente "CRM", "Comercial", "Prospectos" y "Oportunidades" como nombre visible. El módulo administra el universo de obras y sus relaciones, no un pipeline de ventas. `modulo = 'obras'` cumple.

Hay un antecedente: existió un módulo `comercial` que se eliminó entero en `sql/026`. Este no es su continuación con otro nombre — no hay prospecto, ni etapa, ni monto, ni probabilidad, y no se van a agregar en fase 1.

---

## Ser referente no es un rol

La spec listaba `REFERENTE` dentro de los roles de persona **y** además pedía una tabla `obra_referente` con la comisión. Eso es la misma información en dos lugares.

**Decidido:** `rol_persona` no incluye `referente`. Ser referente de una obra es la existencia de una fila en `obras_obra_referente`. La UI lo muestra como badge junto a los roles, pero el dato vive en un solo lado.

---

## La obra es privada de su responsable

La spec no menciona dueño de obra. Se agregó `obras.responsable_id` (NOT NULL, arranca en el creador) y **gobierna la visibilidad**: cada vendedor ve sus obras y nada más.

Quien tenga `obras_transferir` las ve todas — no puede reasignar lo que no ve. Ese permiso es el equivalente funcional de "administrador" para este módulo; no existe un rol, porque el sistema no tiene roles.

**Ver no es editar.** Quien transfiere mira y reasigna; para corregir datos de una obra ajena tiene que transferírsela primero. Una puerta, no dos.

Las transferencias se registran en `obras_transferencias`. Sin eso, "¿por qué no veo más esta obra?" no tiene respuesta.

---

## Las personas tienen alcance; las empresas no

La decisión inicial fue que empresas y personas fueran globales, para no duplicar entidades. Se revisó al plantear el escenario de robo de contactos: un vendedor con acceso al módulo se llevaba la agenda entera de JADA.

**Decidido, en capas:**

1. **Persona por alcance.** Se ve la que uno creó o la que está vinculada a una obra propia. `obras_personas_todas` levanta el límite.
2. **Empresa compartida.** Razón social y web son datos casi públicos; compartirlas es lo que evita que cada vendedor cargue su copia de la misma constructora. El daño de que se filtren es bajo.
3. **Búsqueda de identidad mínima.** `obras_buscar_duplicados_persona` devuelve nombre, apellido y empresa — nunca contacto. Evita el duplicado sin entregar la agenda. Vincular a una obra propia es lo que da acceso al contacto, y queda registrado.
4. **Registro de acceso.** `obras_ficha_persona()` es el único camino a teléfono/whatsapp/email y escribe en `obras_accesos_persona`.
5. **Sin exportar.** No hay CSV ni "copiar todos", y las columnas de contacto no van en el listado — solo en la ficha individual.

El razonamiento detrás: contra un insider autorizado no existe prevención — quien ve un teléfono en pantalla lo puede fotografiar. Lo que estas capas cambian es la escala y la trazabilidad: de un click que se lleva 5.000 contactos, a 5.000 accesos registrados con nombre y fecha.

**Lo que esto no cubre, y conviene no olvidar:** la `service_role` key y el dashboard de Supabase se llevan todo sin RLS y sin registro, igual que un dump de backup. Ese es el perímetro real.

---

## El alcance por fila no es un permiso nuevo

CLAUDE.md prohíbe permisos por fila o por campo fuera del sistema de submódulos. Nada de lo de arriba lo rompe: son las mismas vistas con alcance de datos en RLS, igual que las obras se acotan por responsable. No hay excepción que registrar.

La comisión sí necesitaba tratamiento: es un dato sensible dentro de la ficha de obra. Se resolvió como **función** (`obras_referentes`) y no como permiso de campo — la fila de `obras_obra_referente` contiene la comisión, así que verla es verla.

---

## Aviso ciego de duplicados

Conflicto real: la spec pide avisar si ya existe una obra parecida, pero las obras ajenas son invisibles. Si el aviso no salta, dos vendedores cargan el mismo edificio.

**Decidido:** `obras_buscar_duplicados_obra` es `SECURITY DEFINER` y de una obra ajena devuelve **solo el nombre del responsable** — `obra_id`, `nombre`, `direccion` y `localidad` vienen NULL. Alcanza para ir a preguntar, no para leer la cartera del otro.

Es una excepción consciente a la preferencia por `SECURITY INVOKER`: la función tiene que ver más de lo que ve quien la llama. Está acotada a devolver un solo campo.

Mismo criterio en el mensaje del trigger que bloquea desactivar una empresa: dice **cuántas** obras, nunca cuáles.

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

## El chequeo de duplicados también corre al editar

`chequearDuplicados` arrancaba con `if (obra) return` en los tres paneles. Renombrar una obra hacia una que ya existe es tan duplicado como cargarla dos veces, y no avisaba.

Lo que faltaba para poder correrlo al editar era `p_excluir_id`: sin él la fila se encuentra a sí misma con similitud 1 y avisa de un duplicado que es ella.

---

## Guardar un referente es un solo statement

`guardarReferente` hacía SELECT y después UPDATE o INSERT desde `actions.ts`. El unique parcial `(obra_id, persona_id) WHERE activo` evitaba la fila duplicada, así que la carrera terminaba en un 23505 crudo en pantalla, no en datos rotos — pero la decisión de si era alta o cambio vivía en TypeScript y en otra transacción, que es justo lo que tareas bajó a SQL en `sql/023`/`024`.

`obras_guardar_referente()` es `SECURITY INVOKER` con `ON CONFLICT ... DO UPDATE`: la autoridad no se mueve de las policies, que siguen exigiendo `obras_referentes` y obra propia.

**Un referente dado de baja no revive por acá.** Su fila tiene `activo = false` y el índice parcial no la ve, así que se inserta una nueva. Es lo correcto: volver a poner un referente es un acto nuevo, no deshacer el anterior.

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

## Roles como array, no tabla puente

`obras_obra_empresa.roles rol_empresa[]` y `obras_obra_persona.roles rol_persona[]`. La spec es explícita: una empresa que es constructora **y** desarrolladora de la misma obra es una relación con dos roles, no dos relaciones. Una tabla puente de la tabla puente no aporta nada acá.

CHECK de no-vacío y de no-repetidos vía `obras_array_sin_duplicados()`.

---

## `empresa_id` en obra↔persona no se valida

Es contexto — a quién representa esa persona en esta obra — y puede apuntar a una empresa que no está vinculada a la obra ni a la persona. FK simple, sin trigger de validación cruzada. Decisión del usuario: es dato informativo, no invariante.

Consecuencia: una persona figura **una sola vez por obra**, así que no puede representar a dos empresas en la misma obra. Es lo que pide la spec (§32: una sola relación por par).

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

Ver `BACKLOG.md` para el buscador global obra/empresa/persona, decidido pero fuera de fase 1.

---

## UI — decisiones que no salen de la spec

**El contacto no va en el listado.** Ni teléfono ni email en la lista de personas: solo en la ficha, que pasa por `obras_ficha_persona()` y deja registro. Si mañana se agrega una columna de teléfono al listado, el registro de accesos deja de servir — ese es el punto a cuidar, no la ficha.

**La persona se elige por búsqueda, no por desplegable.** En `VincularPersonaPanel` no hay `<select>` con toda la agenda: hay un buscador que llama a `obras_buscar_duplicados_persona` y devuelve identidad mínima. Un desplegable poblado con `getPersonas()` funcionaría, pero volvería a exponer la lista completa a quien tenga el permiso de vincular.

**Vincular no exige ver primero.** La RLS de `obras_obra_persona` no pide que la persona sea visible: solo que la obra sea propia y exista `obras_vincular`. Es deliberado — es lo que hace usable la búsqueda de identidad mínima, y el acceso al contacto queda registrado igual.

**`getReferentes` va aparte de `getObra`.** Pedir la comisión dentro del mismo `select` le devolvería un array vacío a quien no tiene `obras_referentes`, indistinguible de "esta obra no tiene referentes". Separadas, la ficha sabe si no puede verlas o si no hay.

**El aviso de duplicados se dispara en `onBlur`, no al tipear.** Una consulta por tecla no aporta: el aviso solo tiene sentido con el nombre completo.

**El filtro por empresa/persona relacionada hace una consulta previa.** PostgREST no combina bien el `!inner` que haría falta con los embeds que se usan para contar empresas y personas en el listado. Dos viajes y código claro, en vez de un `select` que hay que descifrar.

**`useWatch` y no `watch()`.** `watch()` devuelve una función no memoizable y el React Compiler saltea la optimización del componente entero — lo marca el lint del repo. El resto del código usa `useController` por la misma razón.

**Sin filtro "responsable inactivo" en SQL.** La policy de `usuarios` no expone `activo` al embed, así que el filtro se resuelve en JS contra la lista de activos que ya se pide para el picker de transferencia.

---

## Congelada, no marcada

Pedido del usuario: un alta que se parece a algo ya cargado, y un vínculo con una persona o empresa de otro, esperan autorización. La pregunta que decidía el diseño era qué puede hacer el que cargó mientras espera. **Decidido: nada.** La fila existe, la ve solo quien la creó, y no acepta ni participa de ningún vínculo hasta que se resuelva (`sql/033`).

La alternativa —badge y a otra cosa— dejaba al duplicado propagándose por las obras mientras la cola espera, que es justo lo que la cola viene a evitar.

Sin estado nuevo: `pendiente = true` es la cola, `pendiente = false` con `activo` es el resultado, y rechazada es `activo = false` con `motivo_rechazo`. Los dos booleanos que ya existían alcanzan.

**El rechazo desactiva, no fusiona.** Mudar los vínculos de la fila nueva a la original es una función de migración bastante más grande, y hoy la fila nueva casi nunca tiene vínculos: está congelada justamente. Si aparece el caso, se revisa.

---

## El vínculo pendiente no abre la ficha

Es el punto entero del pedido 2, y lo que lo hace algo más que un trámite: `obras_puede_ver_persona` dejó de contar los vínculos pendientes. Si los contara, el vendedor vincularía, leería el teléfono por `obras_ficha_persona()` y esperaría el rechazo sentado — con el dato ya copiado.

Dicho de otro modo: hasta `sql/033`, encontrar a alguien en el buscador de identidad mínima y vincularlo a una obra propia era todo lo que hacía falta para llegar al celular. Ahora eso pasa por un tercero.

---

## `obras_aprobar` no es una llave a la agenda

La primera versión de `sql/033` metía `OR tiene_permiso('obras_aprobar')` adentro de `obras_puede_ver_persona`, para que quien aprueba pudiera ver la persona congelada que está juzgando. Eso convertía el permiso de aprobar en **la agenda entera con contacto incluido** — más de lo que da `obras_personas_todas`, y sin que el nombre lo insinúe.

Lo cazaron los casos 06 y 07 de `sql/tests/obras_033.sql`, que son los que afirman lo del párrafo anterior: con esa cláusula, el vínculo pendiente seguía abriendo la ficha para cualquiera que aprobara.

**Decidido:** quien aprueba mira por `obras_pendientes()` y `obras_pendiente_similares()`, que son `SECURITY DEFINER` y devuelven identidad mínima. Mismo criterio que la vista de Auditoría: la pantalla que vigila el acceso al contacto no puede ser otra puerta al contacto.

La excepción va del otro lado: `obras_pendiente_similares` **sí** muestra el nombre de la obra ajena contra la que se parece. Sin eso la decisión de aprobar es a ciegas, que es lo contrario de lo que la cola existe para hacer. Queda acotada a `obras_aprobar` y no devuelve contacto de nadie.

---

## La detección corre en la base, y por eso hubo que partir las tres búsquedas

El aviso de duplicados era una advertencia que el usuario podía ignorar. Ahora además decide si la fila entra congelada, así que no puede depender de que el cliente confiese que lo vio: el trigger es la barrera.

Pero los triggers necesitaban el criterio de parecido **sin** el enmascarado ni el guard de permiso que esas funciones aplican al resultado. Con `obras_buscar_duplicados_*` tal como estaban, la detección habría dependido de qué permisos tiene quien crea.

**Decidido:** cada una se parte en dos. `obras_similares_*` hace el match crudo (ids y score, sin mirar quién pregunta) y `obras_buscar_duplicados_*` queda como capa de enmascarado con firma idéntica —los `GRANT` sobreviven al `REPLACE` y `actions.ts` no se entera—. Un solo umbral, un solo criterio, tres consumidores: la pantalla, el trigger y la cola.

`obras_similares_empresa` es la única de las tres con `GRANT` a `authenticated`, porque el envoltorio de empresas sigue siendo `SECURITY INVOKER` —así la policy de `obras_empresas` sigue decidiendo qué ve cada uno— y por lo tanto la ejecuta como quien llama.

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

---

## Vincular se hace desde los dos lados

Pedido del usuario, y es un cambio de UI, no de modelo: la fila obra↔empresa, obra↔persona y persona↔empresa siempre fue una sola, y los permisos ya existían (`obras_vincular`, `obras_personas_empresas`). Lo que faltaba era la puerta desde la ficha de la empresa y desde la de la persona.

`VincularPersonaEmpresaPanel` toma `persona` **o** `empresa` fija y busca la otra punta — un solo panel, porque es la misma fila y el mismo permiso. `VincularObraPanel` es el sentido nuevo: parado en la agenda, lo que se busca es la obra. Solo ofrece obras propias y no congeladas, que son las únicas a las que la RLS deja colgarle un vínculo.

---

## Los `<select>` de vinculación se fueron a buscador

Un desplegable con la lista entera deja de servir apenas la agenda crece, y en el caso de las personas además exponía el padrón completo a quien solo tenía que vincular una — el mismo motivo por el que `VincularPersonaPanel` ya buscaba en vez de listar.

`Buscador` es uno solo para los cuatro paneles. Carga la primera tanda al abrir **salvo** cuando busca personas: ahí la lista vacía es deliberada, la agenda se busca y no se lista.

La función que se le pasa tiene que ser estable entre renders (definida a nivel de módulo, no inline): el efecto de la primera carga la toma como dependencia. Y el `setState` va en el callback de la promesa, nunca en el cuerpo del efecto — el lint del repo lo corta.

---

## La empresa entra a la obra con su gente

`obras_vincular_empresa` (`sql/034`) escribe el vínculo de la empresa y los de las personas en una transacción. `SECURITY INVOKER`: la autoridad sigue en las policies, igual que `obras_guardar_referente`.

**Un rol por persona, no uno para el lote.** Compras y arquitecto no tienen el mismo rol en la obra aunque trabajen en la misma constructora. Hay un "rol para todas" arriba que llena la columna de una, porque tildar nueve selects iguales tampoco es trabajo.

**La lista la sirve `obras_personas_de_empresa`, no un select.** Con RLS directa, quien vincula vería dos de las nueve personas de la constructora —las suyas— y el pedido pierde sentido. La función es `SECURITY DEFINER` y devuelve identidad mínima: nombre, apellido y cargo, nunca contacto. Las que no son suyas entran igual y quedan pendientes, que es exactamente el pedido 2 funcionando.

Las que ya están en la obra vienen destildadas y marcadas: el `ON CONFLICT DO NOTHING` las saltearía igual, pero sin decirlo la UI estaría prometiendo algo que no pasa.

---

## Enlaces externos: copiar, no inventar

El pedido de "accesos directos a la ficha" no necesitaba nada del servidor. Las URLs ya eran estables y el middleware ya devuelve al destino después del login (`next`), así que lo único que faltaba era poder sacar la URL de la app sin copiarla de la barra: un botón en las tres fichas.

Nada de tokens ni de links públicos — la ficha sigue exigiendo sesión y permiso, que es lo que hace que el enlace se pueda mandar por WhatsApp sin pensarlo dos veces.

---

## Marcar referente era el atajo que dejaba pasar todo

Con el vínculo obra↔persona ya cerrado, quedaba una puerta más: `obras_puede_ver_persona` cuenta las filas de `obras_obra_referente` como acceso —una comisión asignada a alguien que no podés ver no significa nada— y esa tabla **no** tiene `pendiente`.

El camino era: encontrar a alguien ajeno en el buscador de identidad mínima, marcarlo referente de una obra propia, y leerle el teléfono. Sin pasar por nadie, y con `obras_referentes` que es un permiso que un vendedor normal tiene.

**Decidido:** `obras_guard_congelado` exige, para `obras_obra_referente`, que la persona ya sea visible **antes** de esa fila (`OB019`). No se le agregó `pendiente` a la tabla: la comisión no es un vínculo que valga la pena poner en la cola, y el orden correcto es vincular primero y marcar referente después — que es exactamente lo que la UI ya ofrecía.

La pantalla acompaña: `ObraDetalle` solo ofrece "Referente" sobre personas con el vínculo aprobado.

**Regla que queda:** cada tabla nueva cuya fila entre en `obras_puede_ver_persona` es una puerta al contacto, y hay que preguntarse quién la puede escribir. Hoy son dos: `obras_obra_persona` (con `pendiente`) y `obras_obra_referente` (con este guard).

---

## Lo que el rechazo todavía no resuelve

Rechazar desactiva la fila, así que sale de los listados: quien la cargó se entera solo si entra a la ficha por URL directa. El motivo está guardado y la ficha lo muestra, pero nadie le avisa.

No se resolvió acá porque el módulo no tiene ningún canal de aviso y armarlo para esto sería construir media notificación. Queda en `BACKLOG.md` con el camino barato anotado.

---

## La fila de listado se escribe una vez y cambia de display

Los listados eran una fila `flex-wrap` con el nombre en `min-w-0 flex-1 truncate` y la metadata
como items que no se encogen. Es la peor repartición posible del ancho: el único que cede es el
dato que identifica la fila, así que a 390px "Complejo Costa Norte" quedaba en `Co…` y la ficha
titulaba `C.`. En escritorio el mismo `flex-1` empujaba los chips contra el borde derecho, a
distinta altura horizontal en cada fila — la lista no se podía escanear en vertical.

**Decidido:** abajo de `md` la fila es `flex-col` —nombre arriba, metadata abajo— y arriba es
`md:grid` con anchos de columna fijos.

El marcado se escribe **una sola vez**: el envoltorio de la metadata lleva `md:contents`, así
que en mobile es la línea que envuelve y en escritorio se disuelve y sus hijos pasan a ser
celdas de la grilla. La alternativa era duplicar el bloque con `hidden`/`md:hidden`, que es el
mismo dato escrito dos veces y dos lugares donde olvidarse de un campo.

Consecuencia que hay que respetar: **las celdas opcionales se renderizan siempre**. Un
`{o.localidad && …}` corre las columnas de las filas sin localidad. Van con
`className={valor ? "truncate" : "hidden md:block"}` — presente en la grilla, ausente en la
línea de mobile, donde una celda vacía dejaría un hueco de `gap`.

`PersonasView` no entró: su fila es nombre + badge, no hay metadata que le coma el ancho ni
columnas que alinear. Una grilla de una columna es la fila que ya tenía.

Lo mismo pero con `basis-full sm:basis-0 sm:grow` en las filas de Pendientes, que llevan botones
intercalados. No `sm:basis-auto`: `flex-1` y `basis-auto` son familias distintas de utilidades
de Tailwind y quién gana lo decide el orden en que se generan, no el orden en el `className`.
La base se fija explícita.

~~Las filas de las fichas usan el mismo `basis-full`~~ — **superado**: con el `OverflowMenu`
puesto ya no hay botones intercalados que las obliguen a envolver. Ver *Las acciones de la
ficha viven en el `OverflowMenu`*.


---

## Las acciones de la ficha viven en el `OverflowMenu`

En las tres fichas se leía `Constructora  Editar  Quitar` dentro de la misma línea: el primero
es un dato (`t-caption`) y los otros dos botones (`btn-ghost`, `text-tertiary`). Mismo gris,
mismo tamaño, misma línea — en mobile envolvían, así que una fila de persona eran cuatro
renglones de gris indistinguible. Y arriba, "Desactivar" en rojo sólido era el elemento más
brillante de la pantalla, por encima del nombre de la obra que se estaba mirando.

**Decidido:** el patrón que ya usan tareas y usuarios, sin inventar nada. La fila es un bloque
de texto `min-w-0 flex-1` —nombre en su renglón, metadata y badges abajo— y un `OverflowMenu`
`shrink-0` a la derecha. En el encabezado queda "Editar" a la vista, que es la acción de la
ficha, y el resto —copiar enlace, transferir, desactivar— entra al menú. Desactivar va con
`destructive` e ícono `Archive`, igual que en Proyectos y Plantillas.

**Un solo ítem rojo por menú.** "Quitar referente" saca la comisión y podría pintarse igual,
pero con dos rojos en la misma lista el que importa deja de destacar.

**El menú del encabezado no se esconde por permisos.** "Copiar enlace" no tiene gate, así que
siempre hay al menos un ítem y nunca aparece un `⋯` que abre una lista vacía — la misma regla
que Proyectos resolvió con "Ver tareas". En las filas es al revés: si el usuario no tiene
`obras_vincular` ni `obras_referentes` no hay acciones, y ahí el botón directamente no se
renderiza.

**`CopiarEnlace` dejó de ser componente.** Como ítem de menú lo que hace falta es la función,
no el botón, así que pasó a `modules/obras/copiarEnlace.ts`. El feedback ya era un toast, así
que no pierde nada al ejecutarse desde un menú que se cierra al click.

Las filas sin acciones —personas y obras en las fichas de empresa y persona— toman la misma
forma de dos renglones aunque no lleven menú: si no, dentro del mismo módulo conviven dos
maneras de escribir la misma fila.

**Queda pendiente A6:** "Quitar" sigue desvinculando sin `ConfirmModal` y sin bloquear el doble
click. Es corrección de comportamiento, no de estilo, y va en su propia pasada.

---

## El rol elegido se marca con borde, no con relleno

`RolesPicker` pintaba el rol seleccionado con `badge-brand` y el no seleccionado con
`badge-neutral`. En light son `#EBF2FD` y `#EBF0F8`: dos grises-azules que no se distinguen, así
que la única señal de "elegido" quedaba en el color del texto. En dark el texto azul salvaba la
lectura, pero seguía sin borde. Es el control central de los cuatro paneles de vinculación y se
usa con el celular al sol.

**Decidido:** la forma del toggle de `TareasListaView` — `border-brand-500 bg-brand-50
font-semibold text-brand-700` contra `border-border text-text-tertiary`. El borde es la señal
que sobrevive al contraste bajo; el relleno acompaña.

Dejó de ser `.badge`: la clase fija el texto en 11px y el `min-h-[44px]` que tenía encima
producía pills de 44px de alto con letra de pie de foto. Ahora es `tap-target t-caption`, que da
los 44px **solo** en mobile —`.tap-target` es `min-height` dentro del media query de
`globals.css`— y en escritorio deja el chip del tamaño de su contenido.

No lleva check ni ícono: con borde y peso la diferencia ya se lee, y un ícono adentro de un chip
de multi-selección compite con el label por el ancho del panel `max-w-md`.

---

## La tab activa se resuelve por prefijo más largo

`ModuleTabs` comparaba `pathname === tab.href`. En `/obras/{id}`, `/obras/empresas/{id}` y
`/obras/personas/{id}` ninguna tab quedaba encendida: las cinco apagadas, sin decir dónde estás.
El componente es compartido, pero obras es el único módulo con páginas de detalle propias
—tareas resuelve el detalle con paneles—, así que el bug solo se manifestaba acá.

**Decidido:** activa es la tab cuyo `href` es el prefijo más largo del `pathname`. Hace falta el
"más largo" porque `/obras` es prefijo de todas las demás: sin desempate, `/obras/empresas/{id}`
encendería Obras y Empresas a la vez.

La comparación es `pathname === href || pathname.startsWith(href + "/")`, con la barra: un
`startsWith` pelado haría que `/obras` matcheara una futura `/obrasocial`.

La alternativa era que cada `layout.tsx` pasara el código de la tab activa. Son tres layouts
—cuatro con el que venga— repitiendo lo mismo, y el layout no conoce el `[id]`: el dato ya está
en el `pathname`. Se resuelve donde se lee.

Se agregó `aria-current="page"` en la activa, que es lo que faltaba para que el estado exista
también fuera de lo visual.

---

## Desvincular pregunta antes, y con eso deja de dispararse dos veces

"Quitar de la obra" borraba el vínculo —con sus roles y sus observaciones— de un click, sin
preguntar. `GUIDE_DESIGN` pide confirmación antes de todo cambio de estado importante, y
desactivar ya la tenía; desvincular no. Además `correr()` no levantaba ningún flag, así que dos
clicks disparaban dos veces la misma acción.

**Decidido:** las cuatro acciones destructivas de fila —quitar empresa, quitar persona, quitar
referente, y quitar de la empresa en la ficha de persona— pasan por `ConfirmModal`, con copy que
nombra lo que se pierde y `confirmLabel="Quitar"`.

El doble click se arregla solo con eso: `ConfirmModal` ya tiene su propio `enviando` y deshabilita
los dos botones mientras espera el `onConfirm`. No hace falta un flag por fila — hace falta que la
llamada viva adentro del modal.

Como las filas se renderizan en un `.map()`, no puede haber un booleano por fila. La ficha tiene
un solo estado `confirmando` con el objeto de lo que se está por confirmar (título, mensaje,
label, acción, texto del toast), y el `desactivando` que ya existía se absorbió ahí: una sola
confirmación por ficha, un solo `<ConfirmModal>` al final.

`EmpresaDetalle` quedó con su `desactivando` booleano. No es una segunda manera de hacer lo
mismo: es el caso simple, sin ninguna acción destructiva de fila, y ahí el objeto de estado no
compra nada.

---

## Sin optimistic update: la auditoría pedía algo que el proyecto no hace en ningún lado

El hallazgo A6 pedía "`ConfirmModal` + optimistic update (la guía lo pide para desvincular)".
La primera mitad se hizo. La segunda no, y la premisa estaba mal verificada.

No hay un solo `useOptimistic` en la app. Desactivar obra, persona, empresa y usuario —todas
"acciones clave" según la misma sección de la guía— esperan la server action y se refrescan por
`revalidatePath`. Hacerlo acá lo convertiría en el primer y único optimistic del proyecto, en una
acción de fila de un módulo, y obligaría a bajar a estado de cliente tres listas que hoy llegan
como props del servidor.

Lo que la guía pide de fondo —que el usuario nunca se quede preguntando si algo funcionó— ya lo
da `ConfirmModal`: botón deshabilitado mientras espera, después toast de éxito o de error.

Si algún día se agrega optimistic, se agrega app-wide y no acá: es una decisión de
`decisiones/global.md`, no de este módulo.

---

## El vacío de una sección no se dibuja como el vacío de una página

`.empty-state` es una caja punteada de `p-[60px]`. A nivel de vista está bien: es lo único en
pantalla. En una ficha hay tres o cuatro secciones vacías a la vez —Empresas, Personas, Obras—
y cuatro cajas de 180px son media pantalla de nada.

**Decidido:** misma clase, padding pisado (`empty-state p-8`) en los seis vacíos de sección de
las tres fichas. No una clase nueva: lo que el hallazgo M3 pedía era que el estado vacío se
dibujara igual en todo el módulo —había cuatro tratamientos distintos—, y con el padding pisado
se dibuja igual. Una `.empty-state-sm` sería el quinto.

---

## El estado va en el encabezado, "Pendiente" no

`BADGE_ESTADO` vivía en `ObrasView` y la ficha mostraba el estado como `dt/dd` gris. Ahora el
mapa está en `types.ts` al lado de `LABEL_ESTADO` y lo leen los dos.

En la ficha, el `dt/dd` "Estado" salió de la grilla al entrar el badge: el mismo dato dos veces
en la misma pantalla es la duplicación que la regla de fuente única prohíbe, y el badge es la
forma que ya tiene en el listado.

**El badge "Pendiente" no se agregó, aunque la auditoría lo pedía.** `EstadoPendiente` ya
renderiza un bloque entero dos renglones abajo, con el motivo y qué se puede hacer. En el
listado el chip existe porque no hay lugar para el bloque; en la ficha sí lo hay, y repetir la
palabra arriba no agrega nada.

---

## El filtro vive donde llega su efecto

Auditoría y Pendientes son tabs hermanas y tenían el filtro de días en lugares distintos. La
tentación era unificar la posición.

**Decidido: no.** En Auditoría el `?dias=` acota las dos secciones (accesos y transferencias),
así que es de la página y va arriba. En Pendientes acota solo "Ya resueltas" —la cola muestra
todo lo que espera, sin ventana— así que vive adentro de esa card. Subirlo diría que también
filtra la cola.

Por el mismo criterio bajó el filtro de usuario de Auditoría, que estaba en la toolbar de la
página filtrando una sola de las dos secciones.

Lo que sí se unificó es el control: `components/ui/FiltroDias.tsx`, que además exporta
`DIAS_OPCIONES` — el array `[7, 30, 90]` estaba escrito seis veces, dos de ellas en las páginas,
donde decide si un `?dias=45` escrito a mano se acepta o cae al default.

---

## `Dato` y `Observaciones` son del módulo, no de `components/ui/`

El par `dt/dd` de las fichas estaba escrito nueve veces con la misma forma. Salió a
`modules/obras/components/Dato.tsx` y no a `components/ui/`: la regla es que algo sube cuando lo
usan 2+ módulos, y esto lo usan tres fichas del mismo.

`Dato` recibe `React.ReactNode` y no `string | null` porque dos valores no son texto: teléfono y
email de la ficha de persona son `<a>` de `tel:` y `mailto:`, y la localidad de la empresa
concatena la provincia. El guard es `if (!valor) return null`, que cubre el `""` que devuelve un
campo vacío igual que el `null` de la columna.

