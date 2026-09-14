# Módulo obras — Agenda de Obras (`sql/027_obras.sql` a `sql/037_obras_buscar.sql` — corridos en Supabase vía MCP)

Nombre visible: **Agenda de Obras**. `modulo = 'obras'`, ruta `/obras`. Fase 1 es registro y relación de datos: obras, empresas, personas, sus vínculos con roles múltiples, y referentes con comisión por obra. Sin prospectos, oportunidades, presupuestos ni actividades — ver `decisiones/obras/modelo.md`.

Extensiones nuevas: `unaccent` y `pg_trgm`, ambas en el schema `extensions` (donde ya viven `pgcrypto` y `uuid-ossp`).

## El modelo de visibilidad, que es lo que gobierna todo lo demás

Tres alcances distintos, y conviene tenerlos claros antes de leer las tablas:

| entidad | quién la ve |
|---|---|
| obra | solo su `responsable_id`. Más quien tenga `obras_transferir`, que las ve todas porque no puede reasignar lo que no ve |
| empresa | todos los que tengan acceso al módulo. Razón social y web son datos casi públicos, y compartirlas evita que cada vendedor cargue su copia de la misma constructora |
| persona | solo quien la creó o la tiene vinculada a una obra propia. `obras_personas_todas` levanta el límite |

La persona es el activo sensible (celular directo del que decide la compra), y por eso es la única entidad con alcance por fila **y** con registro de acceso.

Desde `sql/033` hay un cuarto alcance que se superpone a los tres: la fila **congelada** (`pendiente = true`) la ve únicamente quien la cargó —sea obra, empresa o persona— hasta que alguien con `obras_aprobar` la resuelva.

## obras

Entidad central. Puede existir sin empresas, sin personas y sin dirección.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text NOT NULL | libre, no tiene que ser el nombre oficial ("Edificio próximo a Cabildo" es válido) |
| tipo | enum `tipo_obra` | `edificio`\|`casa`\|`refaccion`\|`complejo_viviendas`\|`local`\|`oficina`\|`hotel`\|`otro` |
| estado | enum `estado_obra` | `idea`\|`en_cotizacion`\|`en_ejecucion`\|`en_postventa`\|`perdida`\|`terminada`, default `idea` |
| direccion / localidad | text | opcionales |
| provincia | enum `provincia` | 24 valores (23 provincias + `caba`). Enum y no texto: con texto libre el filtro por ubicación muere el primer día |
| origen | enum `origen_obra` | informativo. No crea relación con empresa ni persona |
| motivo_perdida | enum `motivo_perdida` | |
| detalle_perdida | text | |
| responsable_id | uuid FK → usuarios NOT NULL | **define quién ve la obra** |
| pendiente | boolean NOT NULL default false | `sql/033` — esperando autorización: congelada, no se le pueden colgar vínculos |
| motivo_rechazo | text | por qué la rechazaron. Con `activo = false` es el estado "rechazada" |
| nombre_norm / direccion_norm / localidad_norm | text | derivadas por trigger, para detección difusa |
| activo | boolean | |

`obras_perdida_con_motivo`: `estado <> 'perdida' OR motivo_perdida IS NOT NULL`. El CHECK va en una sola dirección a propósito — pasar a perdida exige motivo, pero salir de perdida **no** lo borra: es información histórica.

`obras_motivo_otro_con_detalle`: `otro` exige `detalle_perdida` no vacío. Los otros motivos se explican solos.

RLS SELECT: `(responsable_id = auth.uid() AND tiene_permiso('obras_ver')) OR tiene_permiso('obras_transferir')`. UPDATE: solo el responsable con `obras_editar` — quien transfiere ve y reasigna, no edita.

**`responsable_id` y `activo` no tienen `GRANT UPDATE`.** Editar, transferir y desactivar son tres permisos distintos; las dos últimas pasan por función que verifica el suyo. Sin esto, cualquiera con `obras_editar` podría transferirse una obra con un UPDATE directo por PostgREST.

**Dispara plantillas de tareas (`sql/055`).** Trigger `disparar_plantillas` AFTER INSERT OR UPDATE OF estado → `disparar_plantillas('obra', 'estado')`. Obras solo avisa que una obra entró a un estado, sin funciones ni botones nuevos: qué se crea lo deciden las plantillas que tiene activadas quien la cambió (ver `tareas.md`). La obra está registrada en `entes` (`core.md`), con `nombre` como único dato citable. `obras_relacionados_obra(obra)` (`sql/060`, INVOKER) devuelve las empresas y personas vinculadas con cada rol, para los roles de las plantillas.

## obras_empresas

Sin campo `cuit` (decisión del usuario). La detección de duplicados va por razón social y nombre comercial difusos.

| columna | tipo | notas |
|---|---|---|
| razon_social | text NOT NULL | |
| nombre_comercial / website / telefono / email / direccion / localidad | text | |
| provincia | enum `provincia` | |
| creado_por | uuid FK → usuarios | |
| razon_social_norm / nombre_comercial_norm | text | por trigger |
| pendiente / motivo_rechazo | boolean, text | `sql/033` — congelada la ve solo quien la cargó |

Una empresa **no tiene rol global**: el rol vive en su relación con cada obra. La misma empresa puede ser constructora en una obra y desarrolladora en otra.

## obras_personas

Sin `empresa_id` y sin columna de rol: lo primero vive en `obras_persona_empresa`, lo segundo en `obras_obra_persona`.

| columna | tipo | notas |
|---|---|---|
| nombre | text NOT NULL | |
| apellido / telefono / whatsapp / email | text | |
| creado_por | uuid FK → usuarios | |
| nombre_norm | text | `nombre + apellido` normalizado |
| email_norm | text | lower+trim |
| telefono_norm / whatsapp_norm | text | solo dígitos — "11 4567-8900" y "+54 11 4567 8900" son el mismo teléfono |
| pendiente / motivo_rechazo | boolean, text | `sql/033` — congelada la ve solo quien la cargó |

> **MODEL A (`sql/039`, ver `decisiones/obras/visibilidad.md`).** `telefono`/`whatsapp`/`email` + sus `_norm` salieron del `GRANT SELECT` de `authenticated`: un `select` directo ya no los trae, solo `obras_ficha_persona()` (DEFINER, con contexto opcional). RLS SELECT ahora: `… AND (creado_por = auth.uid() OR obras_puede_ver_persona(id) OR obras_persona_grant_ctx_vigente(id))`, y `obras_puede_ver_persona` = dueño / `obras_persona_compartida` activa / `obras_personas_todas` (sin ramas de vínculo ni referente). UPDATE exige `creado_por = auth.uid()`.

RLS SELECT (histórico): `(tiene_permiso('obras_ver') OR tiene_permiso('obras_personas')) AND (creado_por = auth.uid() OR obras_puede_ver_persona(id))`.

`creado_por` se prueba **como columna y no dentro de la función**. La versión anterior resolvía todo por `obras_puede_ver_persona(id)`, que relee la fila: en un `INSERT ... RETURNING` — lo que hace `.insert().select()` de Supabase — la fila nueva todavía no está en el snapshot de una función `STABLE`, así que el creador no podía leer lo que acababa de escribir (42501). Crear una persona habría fallado siempre en la app. Lo cazó `sql/tests/rls_obras.sql`.

## obras_persona_empresa

`persona_id`, `empresa_id`, `cargo` (texto libre — "Jefe de compras zona sur" no entra en ningún enum), `es_principal`, `observaciones`.

Unique parcial `(persona_id, empresa_id) WHERE activo` y `(persona_id) WHERE activo AND es_principal` — como máximo una empresa principal por persona.

El cargo **no** determina el rol en obra. No se infiere uno del otro.

## obras_obra_empresa / obras_obra_persona

Las dos tablas puente con la obra. `roles` es un **array de enum**, no filas separadas: una empresa que es constructora y desarrolladora de la misma obra es una relación con dos roles, no dos relaciones.

| tabla | roles | extra |
|---|---|---|
| obras_obra_empresa | `rol_empresa[]` — `constructora`\|`desarrolladora`\|`inmobiliaria`\|`estudio_arquitectura`\|`direccion_obra`\|`otro` | |
| obras_obra_persona | `rol_persona[]` — `arquitecto`\|`desarrollador`\|`inversor`\|`director_obra`\|`compras`\|`oficina_tecnica`\|`decisor`\|`influenciador`\|`contacto_comercial`\|`otro` | `empresa_id` nullable: a quién representa esa persona en esta obra. FK simple, sin validación cruzada — es contexto, no invariante |

Las dos llevan `creado_por` (uuid FK → usuarios, NOT NULL, `sql/051`): quién agregó el vínculo. Lo pone el trigger `set_creado_por` (BEFORE INSERT, no editable por el cliente); backfill = `obras.responsable_id`. Separa "vínculo del responsable" de "vínculo que sumó un receptor de la obra compartida con un contacto suyo": el responsable ve los dos, pero solo el creador reescribe roles/observaciones del segundo (trigger `obras_vinculo_guard_edicion`), y revocar la obra al receptor los arrastra. Ver `sql/051` en la sección de compartir.

~~Las dos llevan además `pendiente` y `motivo_rechazo` (`sql/033`)~~ — **`sql/040` las dropeó.** Bajo MODEL A no se vincula lo que no se ve (WITH CHECK de INSERT exige `obras_puede_ver_persona` / `_empresa`), así que el estado "vínculo pendiente" no existe.

CHECK en ambas: `cardinality(roles) > 0` y `obras_array_sin_duplicados(roles)`. Unique parcial por par `WHERE activo`.

**`rol_persona` no tiene `referente`** — eso es la existencia de una fila en `obras_obra_referente`. Una sola fuente de verdad.

Una persona figura **una sola vez por obra**, así que representa a una sola empresa en esa obra.

## obras_obra_referente

`obra_id`, `persona_id`, `porcentaje_comision numeric(5,2)` CHECK entre 0 y 100.

La comisión pertenece a la relación obra↔referente, no a la persona ni a la empresa: el mismo referente puede tener 3.50% en una obra y 2.00% en otra.

RLS SELECT exige `obras_referentes` además de ver la obra. La fila **contiene** la comisión, así que verla es verla — no hace falta (ni se permite) un permiso por campo.

## obras_transferencias

Log de cambios de dueño: `tipo` (`obra`\|`persona`\|`empresa`, `sql/041`), `obra_id`/`persona_id`/`empresa_id` (nullable, uno por fila según `tipo` — CHECK `transferencia_tipo_ancla`), `de_usuario_id`, `a_usuario_id`, `ejecutada_por`, `created_at`. CHECK `de <> a`.

Sin `activo`: es un log, la fila significa "esto pasó". El trigger de notificación solo dispara para `tipo = 'obra'`.

## obras_obra_compartida / obras_persona_compartida / obras_empresa_compartida / obras_persona_grant_contextual

Grants que otorga el dueño. Las tres "compartida": `(obra_id|persona_id|empresa_id, usuario_id, otorgada_por, activo)`, UNIQUE **entero** por par (re-compartir revive la fila, no inserta otra), CHECK `usuario_id <> otorgada_por`. Dan lectura de la ficha completa (contacto incluido, vía `obras_ficha_persona`), sin editar, revocable.

- `obras_obra_compartida` (`sql/047`): compartir una obra sin mover `responsable_id`. El receptor la ve en su agenda y ve sus vínculos (`obras_puede_ver_obra` suma la rama). `obras_select` y `obras_puede_ver_obra` califican `obras.id` en el EXISTS — la columna `id` de la tabla de grant la sombrea.
- `obras_persona_compartida` / `obras_empresa_compartida` ganan `origen_obra_id` / `origen_empresa_id` (nullable, `sql/047`): marca "este grant nació de tildar la relación en el checklist de compartir ese padre". Compartir por checklist setea el origen al padre; compartir directo lo limpia (última escritura gana). `obras_revocar_obra` / `_empresa` usan el origen para la cascada: revocar el padre desactiva los grants hijos con ese origen.
- **Bug preexistente arreglado en `sql/047`**: `obras_empresas_select` (sql/039) tenía el EXISTS como `c.empresa_id = c.id` (mismo sombreado de `id`), así que `obras_compartir_empresa` nunca dio visibilidad real. Ningún test lo ejercía — model_a solo probó compartir persona.

`obras_persona_grant_contextual`: `(persona_id, usuario_id, obra_id XOR empresa_id, otorgada_por, activo)`, unique parcial por ancla. El contacto se ve solo desde esa ficha (`obras_ficha_persona(p_persona_id, 'obra'|'empresa', ctx_id)`); muere con el vínculo, validado en vivo por `obras_persona_grant_ctx_vigente`.

RLS: solo SELECT para `authenticated` (dueño o receptor). La escritura pasa por `obras_compartir_*` / `obras_revocar_*` / `obras_transferir*` (DEFINER, exigen `creado_por` / `responsable_id`).

Checklists y vista: `obras_relaciones_compartibles_obra/_empresa(entidad, usuario)` → identidad mínima de lo mío vinculado + `ya_compartida`. `obras_compartidos_por_mi()` (DEFINER, gate `obras_compartido`) → todo lo que compartí, con quién y de qué origen, tope 500.

- **Bug arreglado en `sql/048`**: `obras_relaciones_compartibles_obra/_empresa` (sql/047) declaran `RETURNS TABLE (..., id uuid, ...)`, así que `id` es variable plpgsql y el guard `SELECT 1 FROM obras WHERE id = p_obra_id` tiraba `42702` (ambiguo) al planear — la RPC fallaba siempre y el checklist "Compartir también" del panel nunca se poblaba. Fix: calificar la columna (`o.id` / `e.id`). Test `sql/tests/obras_047.sql` sumó casos 10-11.
- **`sql/049` — checklist = estado deseado**: `obras_compartir_obra/_empresa` re-llamadas con un usuario que ya tiene la entidad también desactivan la cascada de ese padre (`origen_* = padre`, `otorgada_por = auth.uid()`) que quedó fuera del array. Ajusta el reparto sin revocar. Grant directo (origen NULL) o de otro padre intacto; array vacío apaga toda la cascada de ese padre. Test: `sql/tests/obras_049.sql`, 4/4.
- **`sql/050` — origen estructurado**: `obras_compartidos_por_mi()` devuelve `origen_tipo` (`NULL`/`'obra'`/`'empresa'`) + `origen_id` + `origen_nombre` en vez del texto `origen` ya formateado. La vista Compartido anida lo compartido en cascada bajo su obra/empresa padre (el padre siempre está en el mismo resultado). `ORDER BY` pasó a posición 9.
- **`sql/051` — el receptor vincula sus contactos**: el receptor de una obra compartida puede vincularle empresas/personas **suyas** (`obras_obra_*_insert` suma la rama `obras_obra_compartida_conmigo(obra_id) AND entidad.creado_por = auth.uid()`). Los vínculos ganan `creado_por` (trigger `set_creado_por`, no editable por el cliente; backfill = `obras.responsable_id`). El SELECT de vínculos deja de colgar de `obras_puede_ver_obra` (true entero para el receptor) → `creado_por = auth.uid()` · `obras_es_mi_obra` (el responsable ve **todo**, incluido lo del receptor) · `obras_transferir` · (obra + entidad compartidas conmigo, para el receptor). La empresa/persona que sumó un receptor es privada, así que el nombre no llega por el embed → **`obras_vinculos_de_obra(obra)`** (DEFINER, identidad mínima + `creado_por`/nombre + `es_de_receptor`) lo resuelve, y `getObra` la usa en vez de embeber los vínculos. Editar roles/observaciones/empresa_id de un vínculo que creó un receptor: solo su creador — trigger `obras_vinculo_guard_edicion` (`OB028`); el responsable puede quitarlo (`activo=false`), no reescribirlo. El receptor, en cambio, no recibe en la función el interior que no se le compartió (ni la fila vacía). `obras_obra_referente_select` pasa a `obras_es_mi_obra OR obras_transferir` — el receptor no ve comisiones. `obras_revocar_obra` desactiva además los vínculos con `creado_por = p_usuario_id` de esa obra; `obras_contar_vinculos_receptor(obra, usuario)` (DEFINER, gate responsable) alimenta el aviso previo del panel. Helpers: `obras_obra_compartida_con(obra, usuario)` + wrapper `_conmigo(obra)`, `obras_empresa_compartida_conmigo` / `obras_persona_compartida_conmigo` (DEFINER, evitan el sombreado de `*_id` en EXISTS inline). Test: `sql/tests/obras_051.sql`.
- **`sql/052` — el grant heredado de obra ve, no reparte**: un contacto compartido tildándolo en el checklist de una obra (`obras_persona_compartida` / `obras_empresa_compartida` con `origen_obra_id` seteado) ya no habilita a colgarlo de las obras propias del receptor. `obras_obra_persona_insert` / `_empresa_insert`: la rama `obras_es_mi_obra(obra_id)` ahora exige además que el contacto sea del receptor — dueño, `obras_persona_grant_directo` / `_empresa_grant_directo` (grant con `origen_* IS NULL`), o `obras_personas_todas` / `obras_empresas_todas`. La rama de obra compartida (`obras_obra_compartida_conmigo AND entidad.creado_por = auth.uid()`) no cambia. `obras_revocar_persona` / `_empresa` ganan la cascada que `obras_revocar_obra` ya tenía: al sacar el share directo, los `obras_obra_persona` / `_empresa` de esa persona/empresa con `creado_por = p_usuario_id` se desactivan (los referentes caen por `cascada_desactivar`). `obras_contar_vinculos_persona_receptor` / `_empresa_receptor(entidad, usuario)` (DEFINER, gate dueño de la entidad) alimentan el aviso previo del panel. UI: la ficha de persona/empresa ofrece "Vincular obra" solo si `esMio || grantDirecto || veTodas` (`tieneGrantDirectoPersona` / `_Empresa`). Test: `sql/tests/obras_052.sql`.

## obras_accesos_persona

`usuario_id`, `persona_id`, `contexto` (`sql/039` — `obra:<id>` / `empresa:<id>` cuando se vio por grant contextual, NULL si fue acceso directo; `obras_auditoria_accesos` lo resuelve al nombre), `created_at`. Escrita por `obras_ficha_persona()`, que es el **único** camino por el que la app lee teléfono, whatsapp y email.

Que sea el único es lo que hace que el log sirva. Contra un insider autorizado no hay prevención — quien ve un teléfono lo puede fotografiar — pero esto convierte "se llevó la agenda" en una consulta que muestra 340 fichas abiertas en dos días. RLS SELECT: solo `obras_personas_todas`.

## Helpers de visibilidad

`obras_puede_ver_obra(uuid)` · `obras_es_mi_obra(uuid)` · `obras_puede_ver_persona(uuid)` — `SECURITY DEFINER STABLE`, usadas por las policies. No `EXISTS` directo: dos policies que se miran entre sí dan `42P17 infinite recursion`.

`obras_es_mi_obra` existe aparte de `obras_puede_ver_obra` porque ver no es editar: quien transfiere pasa el primero y no el segundo.

## Normalización y duplicados

`obras_normalizar(text)` — sin acentos, minúsculas, todo lo no alfanumérico a espacio. `obras_normalizar_telefono(text)` — solo dígitos. Ambas `IMMUTABLE`, aplicadas por trigger a las columnas `_norm` (columnas `GENERATED` no sirven: `unaccent()` no es `IMMUTABLE`).

Índices GIN trigram sobre las `_norm`. Umbral de similitud **0.45**, verificado contra datos reales: `XYZ S.A.` ↔ `xyz sa` da 0.50 (detecta), `Edificio Libertador` ↔ `Casa Los Alamos` da 0.03 (no molesta).

Tres funciones de búsqueda, con tres niveles de exposición distintos:

| función | seguridad | qué devuelve |
|---|---|---|
| `obras_buscar_duplicados_empresa` | DEFINER (`sql/042`) | de una empresa ajena, `razon_social` y quién la cargó. `empresa_id`, `nombre_comercial` y `localidad` vienen NULL |
| `obras_buscar_duplicados_persona` | DEFINER | identidad mínima: nombre, apellido, empresa principal. **Nunca** teléfono ni email |
| `obras_buscar_duplicados_obra` | DEFINER | de una obra ajena, el nombre de la obra (`sql/042`) y el del responsable. `obra_id`, `direccion` y `localidad` vienen NULL |

Las tres: `EXECUTE` solo para `authenticated` (la de empresa lo recuperó en `sql/054`).

El aviso ciego de obras es la salida a un conflicto real: dos vendedores no pueden cargar el mismo edificio, pero tampoco pueden ver las obras del otro. Avisa sin mostrar, y alcanza para que el vendedor vaya a preguntar.

Las tres toman `p_excluir_id` (`sql/031`), que es lo que permite chequear también al editar: sin él, la fila que se está editando se encuentra a sí misma con similitud 1 y avisa de un duplicado que es ella.

En `obras_buscar_duplicados_obra` la localidad **no filtra**, ordena. Filtraba por igualdad exacta del normalizado hasta `sql/031`, y "Devoto" contra "Villa Devoto" alcanzaba para que el aviso no saltara — justo el caso para el que existe. Escrita igual, sube la fila al tope; escrita distinta, ya no esconde nada.

Vincular una persona a una obra propia **no** requiere verla antes — es lo que hace usable la búsqueda de identidad mínima. Es acceso deliberado y queda registrado.

## El buscador global (`sql/037`, enmascarado en `sql/042`)

> **MODEL A (`sql/042`).** Las tres ramas pasan por funciones DEFINER (`obras_buscar_obras` / `_empresas` / `_personas`) que devuelven `(tipo, id, titulo, subtitulo, es_ajeno, duenio)`. Lo ajeno aparece **enmascarado**: `id` NULL, `es_ajeno = true`, `duenio` con el nombre del dueño, sin link. `visible`/`cargada_por` → `es_ajeno`/`duenio`. `obras_buscar_duplicados_empresa` pasó a DEFINER + enmascarado; `obras_buscar_duplicados_obra` ahora muestra el nombre de la obra ajena.

Una barra arriba del módulo busca en las tres entidades y lleva a la ficha. Dos funciones (pre-`sql/042`):

| función | seguridad | qué devuelve |
|---|---|---|
| `obras_buscar(p_texto)` | **INVOKER** | `(tipo, id, titulo, subtitulo, visible, cargada_por)` — 5 por tipo, ordenados por "empieza con lo que escribiste" y después por nombre |
| `obras_buscar_personas(p_texto)` | DEFINER + guard `obras_ver`/`obras_personas` | identidad mínima —nombre, apellido, empresa principal— más `visible` y `cargada_por`. **Nunca** teléfono ni email |

**INVOKER es la decisión, no un detalle.** Las ramas de obras y empresas son `SELECT` directos, así que la visibilidad la deciden las policies que ya existen y no hay una segunda copia de la regla. La única que necesita ver más que quien pregunta es la de personas, y por eso va aparte: devuelve las que están fuera de alcance con `visible = false` y sin contacto, igual que `obras_buscar_duplicados_persona`. Encontrar a alguien no es abrirle la ficha — el teléfono sigue saliendo solo por `obras_ficha_persona()`, que registra.

Como `obras_buscar` corre con el rol de quien llama, `obras_buscar_personas` necesita `GRANT EXECUTE` a `authenticated` aunque no la llame nadie más.

**La obra ajena no aparece.** El aviso ciego la devuelve con todo en NULL menos el responsable, así que como resultado de búsqueda sería una fila sin nada que mostrar; el caso que importa —no cargar dos veces el mismo edificio— ya lo cubre `obras_buscar_duplicados_obra` al crear.

El match es `LIKE '%texto%'` sobre las columnas `_norm`, no `similarity`: el parecido de `pg_trgm` sirve para "esto ya está cargado", no para "empecé a escribir el nombre". La normalización además desarma el patrón —`%` y `_` se vuelven espacios— así que un comodín tipeado en la barra no es un comodín. Piso de 2 caracteres, escrito una vez en el CTE `patron`: con menos, las tres ramas se quedan sin fila contra qué joinear.

Verificación: `sql/tests/obras_037.sql`, 15/15.

## Auditoría (`sql/031`)

Los dos logs se leen por función, no por `select` directo:

| función | devuelve |
|---|---|
| `obras_auditoria_accesos(p_dias)` | cada apertura de ficha: fecha, usuario y **nombre** de la persona. Nunca teléfono, whatsapp ni email |
| `obras_auditoria_transferencias(p_dias)` | fecha, obra, de quién, a quién y quién la movió |

Las dos son `SECURITY DEFINER` con guard propio (`tiene_permiso('obras_auditoria')`) y tope de 500 filas. Por función y no por policy porque quien audita necesita ver los accesos de todos y el nombre de la persona para que la fila signifique algo, pero no tiene por qué tener permiso sobre la agenda ni sobre las obras ajenas: con un `select` + embed, un auditor sin `obras_personas` recibiría el log entero con la persona en NULL.

La policy de `obras_accesos_persona` no cambia — sigue siendo `obras_personas_todas` para el acceso directo a la tabla.

## Códigos de error `OB` (`sql/032`)

Las diez `RAISE EXCEPTION` del módulo llevan `USING ERRCODE`. Sin eso salían como `P0001`, que no está en el mapa de `mensajeError()`, y todas se veían como "No se pudo completar la operación. Intentá de nuevo."

| código | dónde | mensaje |
|---|---|---|
| `OB001` | `obras_guard_desactivar_empresa` | participa en **N** obra(s) — el conteo, nunca los nombres |
| `OB002` | `obras_guard_desactivar_persona` | ídem |
| `OB003` | `obras_transferir` | sin permiso para transferir |
| `OB004` | `obras_transferir` | obra inexistente o desactivada |
| `OB005` | `obras_transferir` | la obra ya es de ese usuario |
| `OB006` | `obras_transferir` | el destino no tiene acceso a Obras |
| `OB007` | `obras_set_activo` | sin permiso para desactivar |
| `OB008` | `obras_set_activo` | la obra no existe o no sos su responsable |
| `OB009` | `obras_ficha_persona` | sin acceso a esta persona — no distingue "no existe" de "no la ves" |
| `OB010` | `obras_auditoria_*` | sin permiso para ver la auditoría |
| `OB011` | `obras_guard_congelado` | la obra está pendiente: no acepta vínculos |
| `OB012` | `obras_guard_congelado` | la empresa o la persona está pendiente: no se puede vincular |
| `OB013` | `obras_pendientes` · `obras_historial_aprobaciones` | sin permiso para ver la cola |
| `OB014` | `obras_pendiente_similares` · `obras_resolver_pendiente` | sin permiso para resolver |
| `OB015` | `obras_resolver_pendiente` | tipo de solicitud desconocido |
| `OB016` | `obras_resolver_pendiente` | rechazo sin motivo |
| `OB017` | `obras_resolver_pendiente` | ya resuelta o inexistente |
| `OB018` | `obras_personas_de_empresa` | sin permiso para vincular |
| `OB019` | `obras_guard_congelado` | marcar referente a alguien que no se ve: el vínculo tiene que existir y estar autorizado |
| `OB020`–`OB025` | compartir / transferir persona-empresa (`sql/039`, `sql/041`) | dueño, autocompartir, usuario inexistente, sin permiso, entidad inexistente |
| `OB026` | `obras_compartir_obra` · `obras_revocar_obra` · `obras_relaciones_compartibles_obra` (`sql/047`) | solo el responsable de la obra comparte o revoca |
| `OB027` | `obras_compartidos_por_mi` (`sql/047`) | sin acceso a la vista Compartido |

`mensajeError()` devuelve el texto de la base cuando el código matchea `/^OB\d{3}$/`, y cae en el mapa o en el genérico para todo lo demás. No se copió el mapa código → texto de `tareas` porque `OB001` y `OB002` llevan un conteo que un texto fijo perdería. La lista blanca es por código, no por confiar en el mensaje: un `P0001` nuevo sigue cayendo en el genérico. Ver `decisiones/obras/modelo.md`.

`obras_guardar_referente(obra, persona, porcentaje, observaciones)` — `SECURITY INVOKER`, `INSERT ... ON CONFLICT (obra_id, persona_id) WHERE activo DO UPDATE`. Reemplaza el SELECT + UPDATE/INSERT que hacía `actions.ts` en dos requests. La autoridad no se mueve: las policies de `obras_obra_referente` siguen exigiendo `obras_referentes` y que la obra sea propia. Un referente dado de baja no revive por acá: el índice parcial no ve su fila, así que se inserta una nueva.

## Autorizaciones pendientes (`sql/033`, recortadas por `sql/040`)

> **MODEL A (`sql/040`).** Solo el **alta** parecida se congela. Se dropeó `pendiente`/`motivo_rechazo` de `obras_obra_empresa` y `obras_obra_persona`, la función/triggers `obras_guard_congelado` entera (la regla de referente OB019 pasó al WITH CHECK de `obras_obra_referente_insert`), y `obras_marcar_pendiente` perdió las dos ramas de vínculo. `obras_pendientes` / `obras_pendiente_similares` / `obras_resolver_pendiente` / `obras_solicitante` / `obras_etiqueta` / `obras_aprobaciones.tipo` quedaron con `obra`\|`empresa`\|`persona`. Lo de abajo describe el estado pre-`sql/040`.

Dos pedidos del usuario con una sola mecánica: un alta que se parece a algo ya cargado, y un vínculo con una persona o empresa que cargó otro, no entran a la agenda — entran **congelados**, y alguien con `obras_aprobar` decide.

`pendiente` y `motivo_rechazo` viven en las cinco tablas que pueden esperar: `obras`, `obras_empresas`, `obras_personas`, `obras_obra_empresa`, `obras_obra_persona`. No hay estado nuevo:

| situación | columnas |
|---|---|
| en la cola | `pendiente = true` |
| aprobada | `pendiente = false`, `activo = true` |
| rechazada | `pendiente = false`, `activo = false`, `motivo_rechazo` con el texto |

**Congelada quiere decir congelada.** La fila la ve solo quien la cargó (policy de `obras_empresas`, `obras_puede_ver_persona` para las personas) y `obras_guard_congelado` corta cualquier vínculo hacia o desde ella (`OB011` / `OB012`). Un `pendiente` que solo pintara un badge dejaría al duplicado propagándose mientras la cola espera.

**El vínculo pendiente no abre la ficha de contacto.** `obras_puede_ver_persona` exige `NOT op.pendiente`. Es el punto entero del pedido: vincular era lo que daba acceso al teléfono, así que sin esto la autorización no protegería nada.

**`obras_aprobar` no entra en `obras_puede_ver_persona`.** Quien aprueba mira la cola por función; darle la fila por policy le habría dado la agenda entera con contacto. Ver `decisiones/obras/visibilidad.md`.

### Triggers

| trigger | tablas | qué hace |
|---|---|---|
| `marcar_pendiente` (`obras_marcar_pendiente`) | las 5 | BEFORE INSERT. En las tres entidades marca por parecido (`obras_similares_*`); en los dos vínculos, si `creado_por` de lo vinculado no es `auth.uid()`. Pisa `pendiente` y `motivo_rechazo`: el `GRANT INSERT` es por tabla, así que sin esto el cliente mandaría la fila ya aprobada |
| `guard_congelado` (`obras_guard_congelado`) | `obras_obra_empresa`, `obras_obra_persona`, `obras_persona_empresa`, `obras_obra_referente` | BEFORE INSERT. Corta si la obra, la empresa o la persona está pendiente, y exige que la persona ya sea visible para marcarla referente (`OB019`) — esa fila también da acceso al contacto y no tiene `pendiente`. Los `IF` van **anidados** bajo `TG_TABLE_NAME`, no encadenados con `AND`: plpgsql planea la expresión entera y `NEW.obra_id` explota con 42703 en la tabla que no tiene esa columna |

`obras_obra_persona.empresa_id` queda fuera del guard a propósito: es contexto informativo, no un vínculo con la empresa.

### Funciones

| función | seguridad | qué hace |
|---|---|---|
| `obras_similares_obra` / `_empresa` / `_persona` | DEFINER | el match difuso crudo: ids y score, sin enmascarar ni verificar permiso. Es la mitad de abajo de las tres `obras_buscar_duplicados_*`, extraída para que el trigger use el mismo criterio que la pantalla |
| `obras_buscar_duplicados_*` | DEFINER / INVOKER | mismas firmas de siempre, ahora como capa de enmascarado sobre las anteriores |
| `obras_etiqueta(tipo, id)` | DEFINER | una fila de cualquiera de las cinco tablas → texto. Interna: sin `GRANT` |
| `obras_pendientes()` | DEFINER + guard `obras_pendientes` | la cola: tipo, id, etiqueta, motivo, solicitante, fecha. Tope 500 |
| `obras_pendiente_similares(tipo, id)` | DEFINER + guard `obras_aprobar` | contra qué se parece. **Única pantalla del módulo que muestra el nombre de una obra ajena** — sin eso, aprobar es a ciegas |
| `obras_resolver_pendiente(tipo, id, aprobar, motivo)` | DEFINER + guard `obras_aprobar` | UPDATE dinámico sobre lista blanca de tablas + fila en el log. Rechazo sin motivo: `OB016` |
| `obras_historial_aprobaciones(dias)` | DEFINER + guard `obras_pendientes` | las decisiones ya tomadas |

De las tres `obras_similares_*`, solo `_empresa` tiene `GRANT` a `authenticated`: el envoltorio de empresas es `SECURITY INVOKER` —para que la policy siga decidiendo qué ve cada uno— y por lo tanto la ejecuta como quien llama.

### obras_aprobaciones

Log de decisiones: `tipo`, `registro_id`, `etiqueta` (snapshot), `aprobada`, `motivo`, `decidido_por`, `created_at`. Sin `activo` y sin FK a la fila decidida — es un log de cinco tablas y el `tipo` dice cuál. RLS SELECT: `tiene_permiso('obras_pendientes')`.

### GRANT UPDATE por columna

`obras_empresas`, `obras_personas`, `obras_obra_empresa` y `obras_obra_persona` tenían `UPDATE` entero: con eso un PATCH por PostgREST se auto-aprueba poniendo `pendiente = false`. Ahora la lista es explícita (y deja afuera `creado_por` y las `_norm`), igual que `obras` desde `sql/027`.

## Vincular una empresa con su gente (`sql/034`)

| función | seguridad | qué hace |
|---|---|---|
| `obras_personas_de_empresa(empresa, obra)` | DEFINER + guard `obras_vincular` | la gente de una empresa con identidad mínima —nombre, apellido, cargo, nunca contacto— más `es_mia` y `ya_en_obra`. Con un select directo, quien vincula vería solo las personas a su alcance y la lista perdería sentido |
| `obras_vincular_empresa(obra, empresa, roles, obs, personas jsonb)` | INVOKER | el vínculo de la empresa y los de las personas en una transacción. Devuelve `vinculo_pendiente`, `personas_agregadas` y `personas_pendientes` para que el toast no mienta |

`p_personas` es `[{"persona_id": uuid, "roles": [...]}]` — un rol por persona, no uno para el lote. `ON CONFLICT (obra_id, persona_id) WHERE activo DO NOTHING`: quien ya estaba en la obra queda como estaba, con sus roles intactos.

## Desactivación

Nunca DELETE. `obras_set_activo(uuid, boolean)` exige `obras_desactivar` **y** ser el responsable. Sin cascada sobre los vínculos: la obra se puede reactivar tal como estaba.

Empresas y personas son compartidas, así que desactivarlas puede romper obras ajenas — y quien lo hace ni siquiera puede ver el daño. Triggers `obras_guard_desactivar_empresa` / `_persona` bloquean la desactivación si la entidad participa en alguna obra **activa**, con mensaje que dice cuántas y nunca cuáles (mismo criterio que el aviso ciego). `obras_cascada_desactivar` da de baja las relaciones `obras_persona_empresa` cuando la desactivación sí procede, para no dejar un cargo colgado.

Esa misma función cuelga además de `obras_obra_persona` (`sql/036`): desvincular a una persona de una obra baja su fila de `obras_obra_referente`. Sin eso el referente sobrevivía al vínculo —`getReferentes` lo lee sin pasar por él— y la comisión vieja reaparecía al volver a vincular a la misma persona. Las tres ramas van explícitas por `TG_TABLE_NAME`, y sigue `SECURITY DEFINER` porque la policy de UPDATE de `obras_obra_referente` exige `obras_referentes`, que quien desvincula puede no tener. Verificación: `sql/tests/obras_036.sql`, 8/8.

## Hardening (`sql/029`)

`GRANT EXECUTE ... TO authenticated` no quita nada: Postgres otorga EXECUTE a `PUBLIC` por defecto, así que las `SECURITY DEFINER` del módulo quedaban invocables por `anon` — sin login — vía `/rest/v1/rpc/`. No era explotable (todas cortan con `tiene_permiso`), pero la defensa no puede depender de que nadie toque el guard después. `REVOKE ... FROM PUBLIC` en las 18 funciones del módulo, `GRANT` explícito solo a `authenticated`, y ninguno para las de solo-trigger. Más `search_path` fijo en los tres helpers inmutables.

Verificado: `has_function_privilege('anon', ...)` da `false` en las 18.

## Permisos (submódulos `modulo = 'obras'`)

| codigo | tipo | vista_id | notas |
|---|---|---|---|
| obras_ver | vista | — | listado y ficha de obra |
| obras_empresas | vista | — | |
| obras_personas | vista | — | |
| obras_auditoria | vista | — | los dos logs. Aparte de `obras_personas_todas`: ese permiso es ver la agenda completa, este es ver quién la estuvo mirando |
| obras_pendientes | vista | — | la cola de autorizaciones y su historial (`sql/033`) |
| obras_compartido | vista | — | `sql/047` — lo que uno compartió, con revocar. Solo datos propios, bajo riesgo; sigue el patrón tab = submódulo. Compartir/revocar no tienen gate propio: son acto del dueño, como ya era `obras_compartir_persona` |
| obras_crear | funcion | obras_ver | |
| obras_editar | funcion | obras_ver | solo sobre obras propias |
| obras_vincular | funcion | obras_ver | obra↔empresa y obra↔persona, con sus roles |
| obras_referentes | funcion | obras_ver | ver y editar referente + comisión. Es lo que oculta la comisión a quien no la debe ver |
| obras_transferir | funcion | obras_ver | **implica ver todas las obras**. Darlo con criterio |
| obras_desactivar | funcion | obras_ver | separado de editar: cargar datos no es lo mismo que hacer desaparecer una obra |
| obras_empresas_crear | funcion | obras_empresas | |
| obras_empresas_editar | funcion | obras_empresas | |
| obras_personas_crear | funcion | obras_personas | |
| obras_personas_editar | funcion | obras_personas | |
| obras_personas_empresas | funcion | obras_personas | relacionar persona↔empresa. El botón de la ficha de empresa usa este mismo permiso — una función pertenece a una sola vista |
| obras_personas_todas | funcion | obras_personas | ve la agenda completa de personas, el log de accesos, y **transfiere personas** (`sql/041`) |
| obras_empresas_todas | funcion | obras_empresas | `sql/039` — simétrico a `obras_personas_todas` ahora que las empresas son privadas por dueño. Ve todas + transfiere empresas |
| obras_aprobar | funcion | obras_pendientes | aprobar o rechazar el **alta** parecida. Es el "administrador" de los pedidos del usuario — **no** da acceso a la agenda: `obras_puede_ver_persona` no lo mira |

Combinación a tener presente: crear una empresa o persona desde adentro de una obra necesita `obras_empresas_crear` / `obras_personas_crear` además de `obras_vincular`. Con solo `obras_vincular` se pueden enlazar las que ya existen.

`usuarios_select` extendida con `OR tiene_permiso('obras_transferir')` — el picker de destino necesita listar usuarios.

Verificación: `sql/tests/rls_obras.sql`, 29/29 · `sql/tests/obras_033.sql`, 33/33.
