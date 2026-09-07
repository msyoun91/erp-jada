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

## Cuatro campos se fueron de la ficha

`cantidad_unidades`, `superficie_estimada`, `fecha_estimada_inicio` y `fecha_estimada_compra` salieron por pedido del usuario (`sql/030`).

Se dropearon las columnas en vez de esconderlas en la UI: un campo que ningún formulario escribe y ninguna vista muestra no es dato, es esquema muerto que igual aparece en `database.types.ts` y en cada `select *`. "Nunca DELETE" protege filas de negocio, no columnas — y la tabla tenía 0 filas, así que no había historia que perder. Si vuelven, vuelven como migración.

Con las columnas se fueron sus dos CHECK (> 0) y su lugar en el `GRANT UPDATE` por columna de `sql/027`: Postgres actualiza el privilegio solo.

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

Ambas descartadas explícitamente por el usuario para fase 1. Nada de este módulo va a `erp-cliente` ni a `sync-contracts`.

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
