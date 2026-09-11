# Obras — Vínculos y referentes

## Ser referente no es un rol

La spec listaba `REFERENTE` dentro de los roles de persona **y** además pedía una tabla `obra_referente` con la comisión. Eso es la misma información en dos lugares.

**Decidido:** `rol_persona` no incluye `referente`. Ser referente de una obra es la existencia de una fila en `obras_obra_referente`. La UI lo muestra como badge junto a los roles, pero el dato vive en un solo lado.

---

## Guardar un referente es un solo statement

`guardarReferente` hacía SELECT y después UPDATE o INSERT desde `actions.ts`. El unique parcial `(obra_id, persona_id) WHERE activo` evitaba la fila duplicada, así que la carrera terminaba en un 23505 crudo en pantalla, no en datos rotos — pero la decisión de si era alta o cambio vivía en TypeScript y en otra transacción, que es justo lo que tareas bajó a SQL en `sql/023`/`024`.

`obras_guardar_referente()` es `SECURITY INVOKER` con `ON CONFLICT ... DO UPDATE`: la autoridad no se mueve de las policies, que siguen exigiendo `obras_referentes` y obra propia.

**Un referente dado de baja no revive por acá.** Su fila tiene `activo = false` y el índice parcial no la ve, así que se inserta una nueva. Es lo correcto: volver a poner un referente es un acto nuevo, no deshacer el anterior.

---

## Roles como array, no tabla puente

`obras_obra_empresa.roles rol_empresa[]` y `obras_obra_persona.roles rol_persona[]`. La spec es explícita: una empresa que es constructora **y** desarrolladora de la misma obra es una relación con dos roles, no dos relaciones. Una tabla puente de la tabla puente no aporta nada acá.

CHECK de no-vacío y de no-repetidos vía `obras_array_sin_duplicados()`.

---

## `empresa_id` en obra↔persona no se valida

Es contexto — a quién representa esa persona en esta obra — y puede apuntar a una empresa que no está vinculada a la obra ni a la persona. FK simple, sin trigger de validación cruzada. Decisión del usuario: es dato informativo, no invariante.

Consecuencia: una persona figura **una sola vez por obra**, así que no puede representar a dos empresas en la misma obra. Es lo que pide la spec (§32: una sola relación por par).

---

## Vincular se hace desde los dos lados

Pedido del usuario, y es un cambio de UI, no de modelo: la fila obra↔empresa, obra↔persona y persona↔empresa siempre fue una sola, y los permisos ya existían (`obras_vincular`, `obras_personas_empresas`). Lo que faltaba era la puerta desde la ficha de la empresa y desde la de la persona.

`VincularPersonaEmpresaPanel` toma `persona` **o** `empresa` fija y busca la otra punta — un solo panel, porque es la misma fila y el mismo permiso. `VincularObraPanel` es el sentido nuevo: parado en la agenda, lo que se busca es la obra. Solo ofrece obras propias y no congeladas, que son las únicas a las que la RLS deja colgarle un vínculo.

---

## La empresa entra a la obra con su gente

`obras_vincular_empresa` (`sql/034`) escribe el vínculo de la empresa y los de las personas en una transacción. `SECURITY INVOKER`: la autoridad sigue en las policies, igual que `obras_guardar_referente`.

**Un rol por persona, no uno para el lote.** Compras y arquitecto no tienen el mismo rol en la obra aunque trabajen en la misma constructora. Hay un "rol para todas" arriba que llena la columna de una, porque tildar nueve selects iguales tampoco es trabajo.

**La lista la sirve `obras_personas_de_empresa`, no un select.** Con RLS directa, quien vincula vería dos de las nueve personas de la constructora —las suyas— y el pedido pierde sentido. La función es `SECURITY DEFINER` y devuelve identidad mínima: nombre, apellido y cargo, nunca contacto. Las que no son suyas entran igual y quedan pendientes, que es exactamente el pedido 2 funcionando.

Las que ya están en la obra vienen destildadas y marcadas: el `ON CONFLICT DO NOTHING` las saltearía igual, pero sin decirlo la UI estaría prometiendo algo que no pasa.

---

## Marcar referente era el atajo que dejaba pasar todo

> **Ajustado por *MODEL A* / `sql/040`.** El guard OB019 sigue, pero ahora está en el WITH CHECK de `obras_obra_referente_insert` (no en un trigger), y "visible" ya no significa "vínculo aprobado" sino "dueño / grant / `obras_personas_todas`".

Con el vínculo obra↔persona ya cerrado, quedaba una puerta más: `obras_puede_ver_persona` cuenta las filas de `obras_obra_referente` como acceso —una comisión asignada a alguien que no podés ver no significa nada— y esa tabla **no** tiene `pendiente`.

El camino era: encontrar a alguien ajeno en el buscador de identidad mínima, marcarlo referente de una obra propia, y leerle el teléfono. Sin pasar por nadie, y con `obras_referentes` que es un permiso que un vendedor normal tiene.

**Decidido:** `obras_guard_congelado` exige, para `obras_obra_referente`, que la persona ya sea visible **antes** de esa fila (`OB019`). No se le agregó `pendiente` a la tabla: la comisión no es un vínculo que valga la pena poner en la cola, y el orden correcto es vincular primero y marcar referente después — que es exactamente lo que la UI ya ofrecía.

La pantalla acompaña: `ObraDetalle` solo ofrece "Referente" sobre personas con el vínculo aprobado.

**Regla que queda:** cada tabla nueva cuya fila entre en `obras_puede_ver_persona` es una puerta al contacto, y hay que preguntarse quién la puede escribir. Hoy son dos: `obras_obra_persona` (con `pendiente`) y `obras_obra_referente` (con este guard).

---

## El referente se cae con el vínculo (`sql/036`)

`desvincularPersona` desactivaba la fila de `obras_obra_persona` y nada más. La de
`obras_obra_referente` quedaba activa y `getReferentes` la lee sin pasar por el vínculo: al volver
a vincular a la misma persona reaparecía la comisión vieja sin que nadie la hubiera cargado, y
mientras tanto era un referente que la UI no podía quitar —`ReferentePanel` solo lista personas
vinculadas—.

Va en la base y no en `actions.ts`: es una invariante de datos, no una regla de pantalla. Si
viviera en la action, cualquier otro camino que desactive el vínculo (hoy `obras_resolver_pendiente`
al rechazarlo, mañana lo que sea) la dejaría pasar.

**Como tercera rama de `obras_cascada_desactivar`, no como función nueva.** Esa función ya es el
único lugar del módulo donde vive "qué se cae cuando algo se cae", y el trigger es el mismo de
siempre: `AFTER UPDATE ... WHEN (OLD.activo AND NOT NEW.activo)`. El `ELSE` implícito pasó a rama
explícita por tabla —con tres tablas colgando del mismo trigger, "todo lo que no es empresas es
personas" deja de ser verdad—.

**Sigue `SECURITY DEFINER`, y ahora eso importa.** La policy de UPDATE de `obras_obra_referente`
exige `obras_referentes`, que quien desvincula puede no tener. Como INVOKER la cascada no vería la
fila —RLS filtra, no falla— y la invariante quedaría a merced del permiso de quien pasó por la
pantalla. El caso 06 del test lo afirma desvinculando con el permiso apagado.

Sin backfill: al correrla no había ninguna huérfana (4 referentes activos, 0 sin vínculo).

`sql/tests/obras_036.sql`, 8/8. Los casos 07 y 08 no son de esta migración: cubren la cascada que
ya existía —entidad desactivada → sus `obras_persona_empresa` caen—, que no tenía test y quedaba
expuesta al reordenamiento de las ramas.
