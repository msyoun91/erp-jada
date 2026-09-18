# Obras — Visibilidad y compartir

## El vínculo se va con la obra (`sql/095`)

**`obras_transferir` pasa al entrante los vínculos que el saliente cargó en la obra, y la rama
`creado_por` de las policies SELECT/UPDATE de `obras_obra_persona` / `obras_obra_empresa` exige que
la obra siga compartida conmigo.** `creado_por` dice quién agregó el vínculo y tres reglas lo leen
como autoridad —las policies, `OB028` y la cascada de `obras_revocar_obra`—, pero transferir movía la
obra y no sus vínculos, y la policy no preguntaba si el creador seguía siendo parte.

**El checklist de tres estados no lo cubría, y no por descuido.** Decide sobre el contacto (de quién
es, quién lo sigue viendo); el vínculo con la obra que se transfiere "se va con ella" en los tres
estados, así que ningún estado lo tocaba. Probado contra la base con el estado 2 y el 3: la obra y el
contacto quedaban del dueño nuevo y la fila que los une, a nombre del anterior. El anterior leía las
notas del dueño nuevo, editaba roles y reponía lo que el dueño nuevo quitaba; si el dueño nuevo le
compartía la obra, `OB028` le trababa editar sus propios contactos y revocarlo los desactivaba. Y el
receptor revocado reponía sus vínculos con un `UPDATE activo = true`.

**No cambia el diseño de `sql/051`:** lo que suma un receptor sigue siendo suyo mientras la obra siga
compartida, y el dueño lo quita, no lo reescribe. `obras_migrar_agenda` ya movía estos `creado_por`
(`sql/088`); le faltaba a `obras_transferir`. Hacen falta las dos piezas: la policy sola dejaba que el
anterior recuperara el poder el día que le compartieran la obra; el traspaso solo dejaba abierto al
receptor revocado.

**Consecuencia asumida:** `obras_es_mi_obra` exige `activo`, así que en una obra desactivada el
responsable tampoco edita por UPDATE los vínculos que cargó él. Agregar y editar los de un receptor ya
estaba cerrado; queda con la decisión abierta sobre qué es desactivar una obra compartida
(`BACKLOG.md`).

Exposición al aplicarla: 0 filas. Sin backfill.

Archivos: `sql/095_el_vinculo_se_va_con_la_obra.sql`, `sql/tests/obras_095.sql` (6/6),
`sql/tests/obras_051.sql` (el caso H lee sin RLS: el receptor revocado ya no ve lo suyo),
`db_schema/obras.md`.

## Un código por regla, y la vista Compartido no miente (`sql/094`)

**`obras_ficha_persona` vuelve a levantar `OB009`, la vista Compartido deja de listar grants sin
vínculo debajo, y devuelve `puedo_abrir` para que la UI no linkee a una ficha cerrada.** Son las tres
deudas chicas que quedaban de la auditoría de compartir/transferir: ninguna tenía acceso indebido
detrás, y ninguna toca autorización.

**El código muerto era la reparación, no el síntoma.** `OB022` significaba "sin acceso a esta
persona" en `obras_ficha_persona` y "sin acceso a esta obra" en `obras_vinculos_de_obra`, así que
nadie podía atrapar uno sin atrapar el otro. No hizo falta inventar un código: `OB009` nació en
`sql/032` con ese significado exacto y el mismo texto, y quedó muerto cuando `sql/039` reescribió la
función. Revivirlo deja a la persona simétrica con la empresa, que ya tenía el suyo (`OB030`), y
cierra solo el desfase de `sql/tests/obras_032.sql` caso 09, que llevaba desde `sql/039` esperando
`OB009` sin que nadie lo corriera hasta el final.

**La vigencia no se podía reusar entera, y por eso se partió.** La vista corre como quien comparte;
`obras_ctx_vigente` responde por `auth.uid()`, que ahí es el receptor. Pero la mitad que hacía falta
—¿sigue vivo el vínculo entidad↔ancla?— no depende de quién pregunta: se extrajo a
`obras_ctx_vinculo_vivo` y la usan las dos. Sin GRANT a `authenticated`: sus dos llamadores son
DEFINER, y exponerla sería superficie sin llamador — la lección de `sql/091` con
`obras_transferir_resolver_vinculos`.

**El link roto lo dejó `sql/093` y la salida es informar, no ensanchar.** Desde que la autoridad es
"dueño del contacto **o** dueño del ancla", el dueño del ancla ve en Compartido filas de contactos
ajenos cuyo nombre linkeaba a una ficha que contesta `OB009`. La vista devuelve `puedo_abrir`
(`obras_puede_ver_persona` / `_empresa`; `true` fijo en la rama obra) y `CompartidoView` no linkea
cuando es `false`. Es el techo que la ficha de la obra ya tiene: muestra el nombre del contacto
ajeno y no el teléfono (`sql/070`, `sql/087`).

**Y del lado de TypeScript, dos huecos de la misma auditoría.** `revocarObra` y `revocarContextual`
no tenían `safeParse` —la base gatea, pero un uuid malformado salía como `22P02` genérico—; el schema
de `revocarContextual` espeja el `OB031` de la base (una empresa no cuelga de otra empresa).
`contarVinculosReceptor` devolvía `0` cuando la consulta fallaba, y el panel leía ese `0` como "no
agregó vínculos" y **revocaba sin preguntar nada**: ahora devuelve un resultado discriminado y el
modal aparece igual, diciendo que no se pudo contar. `obras_contar_vinculos_receptor` además filtra
por `responsable_id = auth.uid()`, así que para cualquier otro no devuelve fila — un `null` que
tampoco era un cero.

Archivos: `sql/094_deudas_chicas_compartir.sql`, `sql/tests/obras_090.sql`, `obras_092.sql`,
`obras_compartir.sql` (el código que atrapan), `db_schema/obras.md`,
`erp-app/src/lib/supabase/database.types.ts`, `erp-app/src/modules/obras/types.ts`, `actions.ts`,
`components/CompartidoView.tsx`, `components/CompartirPanel.tsx`.

## `otorgada_por` es historia, no autoridad (`sql/093`)

**Quién ve un grant en la vista Compartido, quién puede revocarlo y quién puede leer su fila son
ahora la misma pregunta, y la contesta `obras_ctx_autoridad(tipo, entidad, ancla_tipo, ancla)`:
manda el dueño del contacto —es su teléfono el que se ve— o el dueño del ancla —es su obra la que
lo muestra—.** `otorgada_por` deja de leerse para decidir y deja de reescribirse: queda como log.

Cierra el segundo cambio estructural que `sql/090` dejó a mitad, hermano de `sql/092`.

**Las dos premisas del `BACKLOG.md` eran falsas.**

1. *"Derivar las dos del ancla"* no se puede: en dos de las cuatro clases de grant contextual el
   dueño del ancla **es el receptor** —la cascada de `obras_transferir` ancla en la obra que cambió
   de mano, y el recíproco del estado 2 (`sql/087`) ancla en las obras y empresas del saliente—. Esa
   regla habría puesto esas filas en la vista Compartido del propio receptor.
2. *"El CHECK `usuario_id <> otorgada_por` deja de proteger nada"* tampoco: la columna se sigue
   **escribiendo** con el dueño de la entidad, así que el CHECK sigue siendo el guard de inserción
   "nadie se comparte consigo mismo". Lo que cambia no es quién la escribe, es que nadie la lee para
   decidir. Se queda, y `obras_migrar_agenda` 3.4 la usa para no violarlo.

**La columna era la sombra de la propiedad, y `sql/045` lo había escrito.** `otorgada_por` al nacer
es siempre el dueño de la entidad compartida: lo exigen los cuatro escritores (`obras_compartir_obra`
y las tres ramas de `obras_compartir_registros` piden `creado_por = auth.uid()`; la cascada de
transferir otorga con el saliente, que sigue siendo el dueño; el recíproco con el entrante, que pasó
a serlo). `sql/045` la eligió como **atajo para no recursar** contra `obras_personas` / `obras`, y
dejó escrito *"quien otorgó es siempre el dueño"*. Cinco UPDATE en transferir y migrar existían solo
para empujar la columna detrás de la propiedad cuando algo cambiaba de mano: se van los cinco.

**La primera versión de esta migración ató la vista solo al dueño de la entidad, y estaba mal.** Lo
encontró correr `sql/tests/obras_090.sql`, no leerlo: A comparte su obra O tildando su contacto P y
después transfiere P a C; con la vista colgada de la entidad, A —responsable de la obra que es el
vehículo de esa exposición— dejaba de verla, y C la veía colgando de una obra ajena. Además rompía
el anidado de la vista, que asume que el padre viaja en el mismo resultado que sus hijos. La vista
lista **lo que puedo revocar**, menos aquello donde yo soy el receptor.

**La policy no era cosmética.** `getCompartidosObra` lee `obras_obra_compartida` directo y su
comentario decía "solo lo ve el responsable"; la policy decía `otorgada_por`, y coincidían solo
porque transferir reescribía. Sacar el UPDATE sin tocar la policy dejaba al nuevo responsable con el
panel "compartida con" **vacío** y el tercero adentro. Las tres policies de grant pasan a decir la
misma regla; la de empresa (`sql/085`) ya derivaba del dueño de la entidad y le faltaba el ancla.

**Lo que además se arregla:** el dueño de un contacto que no migró deja de perderlo de vista cuando
la obra cambia de mano; el checklist deja de poder apagar lo que no puede ofrecer (filtraba por
`otorgada_por`, ahora por dueño de la entidad, que es exactamente lo que la pantalla muestra); y
revocar dos veces deja de contestar `OB026` a quien sí tiene autoridad —el gate salió del `WHERE`,
así que cero filas es idempotencia—.

Filas con `otorgada_por` distinto del dueño al aplicarla: 0 de 4 activas. Sin backfill.

Archivos: `sql/093_otorgada_por_es_historia.sql`, `sql/tests/obras_093.sql` (6/6),
`sql/tests/obras_088.sql` (caso E reescrito), `sql/tests/obras_090.sql` (etiquetas),
`db_schema/obras.md`, `erp-app/src/lib/supabase/database.types.ts`.

## La red de regresión de compartir se reconstruye alrededor del acto que quedó (sin SQL)

**Los nueve tests que `sql/086` dejó muertos no se portan uno a uno: cuatro se arreglan en el lugar,
cinco se retiran, y los casos que sobrevivían a los cinco caben en un archivo nuevo de seis.** Se
retiran `obras_047`, `049`, `052`, `082` y `085` a `obsoletos/sql-tests-share-directo/`; nace
`sql/tests/obras_compartir.sql`.

**El criterio no fue "¿se puede reescribir?" sino "¿su sujeto existe?".** Los cinco probaban el share
directo de persona y empresa: `origen_obra_id`, `obras_compartir_persona`/`_empresa`, "última
escritura gana", "el grant directo sobrevive al destildado del padre". Eso no es una API que cambió
de forma, es un acto que se cerró. Reescribirlos contra las tablas de grant contextual habría
producido tests que repiten lo que `obras_086`, `087` y `092` ya afirman — que es cómo una suite
llega a tener nueve archivos que nadie corre.

**Lo que sobrevivió son seis casos y ninguno hablaba de compartir contactos**: ver ≠ editar, `OB026`
al compartir una obra ajena, el checklist del panel con `ya_compartida`, la vista Compartido con el
contextual colgando de su origen, re-tildar que revive la misma fila, y el contacto que no abre sin
`?ctx=`. Estaban dispersos en tres archivos cuyo encabezado prometía otra cosa.

**Dos desfases más aparecieron al correrlos, y ninguno era el que el backlog anotaba.** El backlog
decía que los nueve morían con `42P01`/`42883` y ninguno por regresión; es cierto, pero dos tenían
además una segunda podredumbre propia:

- `obras_model_a` no llegaba a ningún caso: su setup inserta permisos sin `ON CONFLICT` contra un
  UNIQUE `(usuario, submodulo)` que el resto de la suite ya esquivaba. Nada que ver con `sql/086`.
- `acceso_registros` caso 05 afirmaba **lo contrario** de lo que la base contesta desde `sql/082`:
  esperaba que la persona tildada en el checklist se abriera desde la tarea. Hoy el checklist otorga
  contextual y `puede_abrir_registro` no cuenta contextuales, así que decía lo mismo que su caso 06
  vecino. Nadie lo vio porque el archivo abortaba en el 09 antes de llegar. Se corrige la expectativa
  y el caso queda como **marcador vivo de la reparación pendiente del chip `?ctx=`** (`BACKLOG.md`):
  cuando se haga, vuelve a esperar `true`.

Un test que acumula `'OK'/'FALLO'` en un string —en vez de `RAISE` en el primer fallo— esconde todo
lo que venga después del primer objeto inexistente. Los dos hallazgos salieron de correrlos, no de
leerlos.

Archivos: `sql/tests/obras_compartir.sql` (nuevo), `acceso_registros.sql`, `asignar_con_acceso.sql`,
`eventos.sql`, `obras_model_a.sql`, `obsoletos/sql-tests-share-directo/`, `obsoletos/README.md`.

## La vigencia del grant contextual se escribe una sola vez (`sql/092`)

**Un grant contextual vale si se cumplen tres cosas: la fila está activa, el vínculo entidad↔ancla
sigue vivo, y quien lo recibió sigue viendo el ancla. Esa regla vive ahora en
`obras_ctx_vigente(tipo, entidad, ancla_tipo, ancla_id)` y en ningún otro lado.** Ancla en NULL
pregunta "¿hay alguno vigente?"; ancla dada pregunta "¿este?".

**El motivo no es la prolijidad: la regla estaba escrita siete veces y en una estaba mal.** `sql/090`
agregó la tercera condición en cuatro lugares y el `BACKLOG.md` anotó que quedaba correcta en los
seis. Eran siete: los tres `obras_*_grant_ctx_*_conmigo` no se tocaron y seguían chequeando solo que
la fila de grant existiera. Dos se salvaban por el llamador —`obras_obra_persona_select` y
`obras_obra_empresa_select` los usan detrás de `obras_obra_compartida_conmigo(obra_id)`, y la fila
que filtran es el vínculo mismo—. El tercero no tenía quién lo cubriera: `obras_persona_empresa_select`
no verificaba el ancla en ningún lado, así que un grant de persona anclado en una empresa que el
receptor ya no ve seguía dejando leer `cargo`, `es_principal` y `observaciones` de la fila
persona↔empresa por PostgREST directo. Identidad, no contacto —el contacto está revocado a nivel
columna desde `sql/039` y `sql/085`— pero es la misma clase que `sql/090` cerró, y sobrevivió
justamente por la dispersión.

**Las cinco funciones viejas se dropean en vez de quedar como envoltorios de una línea.** Un
envoltorio habría dejado el código intacto a cambio de conservar los nombres, y los nombres son
parte de la causa: `obras_persona_grant_ctx_empresa_conmigo` promete "hay un grant mío anclado ahí",
que es una de las tres condiciones. Un nombre que dice menos que la regla es por dónde vuelve el bug.

**La función se llama a sí misma, y está bien.** La rama persona-anclada-en-empresa pregunta si se ve
la empresa ancla, y una respuesta válida es que la empresa esté vigente por su propio grant
contextual. La cadena termina porque la rama empresa nunca vuelve a persona. Era el riesgo que la
entrada del backlog anticipaba; se verificó antes de escribirla que Postgres acepta la
autorreferencia en `LANGUAGE sql` y que el ciclo no existe.

**Tres lecturas se endurecen de yapa**, todas coherentes con `sql/090`: la fila persona↔empresa del
agujero; un vínculo desactivado deja de leerse por grant contextual (los callers ya filtran `activo`,
así que no cambia ninguna pantalla); y el `detalle` de una persona en `obras_vinculos_de_obra` —la
razón social de la empresa que representa en esa obra— deja de salir cuando el grant de esa empresa
quedó huérfano, que es exactamente el grant que ya no abre su ficha.

Archivos: `sql/092_ctx_vigente_una_sola_vez.sql`, `sql/tests/obras_092.sql`, `db_schema/obras.md`,
`erp-app/src/lib/supabase/database.types.ts`.

## El listado de la agenda se recorta en la query, y es deliberado

**`getPersonas` y `getEmpresas` filtran por `creado_por` en `queries.ts`; la policy deja pasar el
grant contextual. No es una barrera puesta en la interfaz: es un recorte de listado sobre datos que
el receptor tiene derecho a leer.** La barrera está donde importa y está en el servidor — el contacto
(`telefono`/`whatsapp`/`email`, y en empresa `website`/`direccion`) salió del `GRANT SELECT` en
`sql/039` y `sql/085`, así que solo lo sirven `obras_ficha_persona` / `obras_ficha_empresa`, con el
ancla verificada y el acceso registrado. Lo que la policy autoriza es identidad: nombre y apellido.

**La alternativa que parecía obvia no existe.** "Que la policy pida ancla" no es implementable: la
RLS de `obras_personas` no recibe contexto, y sacarle la rama contextual rompe al receptor legítimo
—`getEstadoPersona` deja de traer la fila y la ficha con `?ctx=` responde 404 en vez de abrir—. La
otra salida real sería mover el listado a una función `DEFINER`, y no la vale: dos funciones nuevas y
perder los filtros de PostgREST para mover un corte de producto, no de autorización.

**Regla para leerlo:** que un contacto ajeno no aparezca en *mi agenda* es una decisión de producto;
que no pueda ver su teléfono es la de seguridad. La segunda está en la base. La primera puede estar
en la query.

Archivos: `erp-app/src/modules/obras/queries.ts` (`getPersonas`, `getEmpresas`).

## Compartir exige lo mismo que transferir (`sql/091`)

Cierre de la auditoría de `sql/090`: lo que quedaba y se arregla en SQL sin decidir nada nuevo.

**Compartir una obra exige `obras_ver` en el receptor, con el mismo `OB006` que transferir.** Un
grant para alguien sin acceso al módulo no abre nada —`obras_select` exige `obras_ver`, y desde
`sql/090` los contextuales que cuelgan tampoco—, así que la única diferencia contra fallar era el
silencio. Se reusa `OB006` en vez de crear un código: es la misma regla, y un código por regla es
exactamente lo que `OB022` dejó de cumplir. El **texto** sí cambia, porque acá el usuario no es el
destino de una transferencia sino el receptor de un share, y `mensajeError()` muestra el de la base.

**El array `null` es vacío, y vacío quiere decir vacío.** `id = ANY(NULL)` es NULL, no false: el
`DEFAULT '{}'` de la firma no aplica a un `null` explícito, así que compartir con `p_personas: null`
no otorgaba **ni destildaba** y transferir con `p_migran: null` dejaba al receptor sin ningún
contacto. `COALESCE` al entrar en las tres funciones alcanzables por `authenticated`; la cuarta que
recibe arrays, `obras_transferir_resolver_vinculos`, no tiene GRANT y blindarla sería código muerto.
Los schemas Zod ya tenían `.default([])`, así que esto protege el PostgREST directo, no la UI.

**Y la cuarta copia del gate `OB006`.** `obras_migrar_agenda` pasa a `usuario_tiene_permiso`, que
incluye el `u.activo` del `EXISTS` que reemplaza. Sin cambio de conducta.

Archivos: `sql/091_compartir_y_arrays.sql`, `sql/tests/obras_091.sql`, `db_schema/obras.md`,
`erp-app/src/modules/obras/queries.ts` (el comentario de `getUsuariosParaTransferir`, que ahora
también vale para compartir).

## El grant contextual muere con el ancla (`sql/090`)

Auditoría de compartir/transferir (2026-09-18). Cuatro agujeros con una sola causa: el grant
contextual se comportaba como una capacidad independiente en vez de "ver esta entidad **dentro de**
esta obra o empresa". Faltaban dos reglas, y las dos se escribieron una sola vez.

**1 · El grant vale mientras quien lo tiene siga viendo el ancla.** Antes solo se verificaba que el
vínculo entidad↔ancla siguiera vivo, nunca que el receptor siguiera teniendo la obra. Ahora
`obras_persona_grant_ctx_vigente`, `obras_empresa_grant_ctx_vigente` y la rama contextual de las dos
fichas piden además `obras_puede_ver_obra(ancla)` (o `obras_puede_ver_empresa`, para el ancla
empresa). Es la barrera real: un grant que quedó activo por cualquier motivo ya no abre nada.

**2 · `otorgada_por` sigue al dueño del ancla, no al de la entidad.** `obras_transferir_persona`
reescribía el otorgante de **todos** los grants de esa persona, anclados a cualquier obra, incluidas
las que no participaban de la transferencia. Era un resto del modelo sin ancla anterior a `sql/082`,
y producía un grant huérfano: el responsable del ancla dejaba de verlo en Compartido, el nuevo dueño
de la entidad no podía revocarlo (no es responsable de esa obra), y el receptor seguía abriendo la
ficha con teléfono y email después de que le revocaran la obra. Se borra en `_persona`; en
`obras_transferir` y `_empresa` queda solo lo anclado a lo que sí cambió de mano — la obra, y las
empresas que migran, que son ancla de sus personas.

**Revocar la obra apaga todo lo anclado a ella.** `obras_revocar_obra` filtraba los contextuales por
`otorgada_por = auth.uid()`. El filtro no protegía nada —un grant anclado a esa obra solo lo pudo
otorgar su responsable, que es quien llama— y era la otra mitad del huérfano.

**Revocar un contextual tiene dos autoridades, no una.** El ancla puede ser una empresa: el grant
recíproco del estado 2 (`sql/087`) lo otorga el **entrante** sobre un ancla que quedó del saliente,
así que el otorgante lo ve en su vista Compartido sin ser dueño de nada. `obras_revocar_contextual`
pasa a `(p_tipo, p_entidad_id, p_usuario_id, p_ancla_tipo, p_ancla_id)` y acepta dueño del ancla
**o** otorgante. La firma vieja asumía ancla obra y la vista le pasaba el `origen_id` —para esas
filas, un `empresa_id`—, así que devolvía `OB026` siempre: eran irrevocables, y las crea el camino
default de transferir.

**Y no hay más éxito silencioso.** Un `p_tipo` desconocido pasaba el gate, no hacía nada y la acción
devolvía éxito. Ahora corta con `OB031`, y cero filas tocadas sin ser dueño del ancla es `OB026`.

**De paso, el gate `OB006` deja de estar copiado.** Las tres funciones de transferir tenían el mismo
`EXISTS` sobre `usuario_submodulos` que `usuario_tiene_permiso(usuario, 'obras_ver')` ya resuelve.
~~`obras_migrar_agenda` conserva la copia — no se tocó en esta migración.~~ — la cuarta se fue en
`sql/091`.

**El admin que ejecuta no es parte.** `obras_transferir` otorgaba los contextuales del receptor con
`otorgada_por = auth.uid()`, y para no violar el CHECK `usuario_id <> otorgada_por` se salteaba el
bloque entero cuando el destino era quien llamaba: el admin que se transfería una obra a sí mismo
quedaba viendo los nombres de los contactos y con la ficha cerrada. Con `otorgada_por = v_actual`
—quien cede es quien otorga— el `IF` sobra y el caso funciona.

Exposición real al momento de escribir esto: 0 filas. Los cuatro eran latentes.

Archivos: `sql/090_grant_contextual_muere_con_el_ancla.sql`, `sql/tests/obras_090.sql` (7/7),
`erp-app/src/modules/obras/actions.ts`, `components/CompartidoView.tsx`,
`lib/supabase/database.types.ts`, `db_schema/obras.md`.

## Transferir lo propio no es ver lo ajeno (`sql/089`)

**Cada transferencia tiene dos puertas, no dos funciones.** La global de siempre transfiere
cualquier fila y además ve todo; la personal nueva mueve lo propio sin abrir la vista de lo ajeno.
La regla vive una sola vez, en `obras_puede_transferir(tipo, id)`: permiso global, o permiso
personal **y** ser el dueño de esa fila.

Pedido del usuario: *"la funsión transferir obras, transferir empresas y transferir personas pueden
crearse 2 de cada? Uno personal y otro que puede ver la lista de todos y hacer transferencia aunque
sean ajenas"*. Duplicar la función habría duplicado la regla; lo que el sistema sabe repartir es el
submódulo, así que se duplica la puerta.

**El código nuevo es el personal, no el global.** `obras_transferir`, `obras_personas_todas` y
`obras_empresas_todas` están incrustados como "ve todo" en ~15 policies y funciones: renombrarlos
para que el código nuevo fuera el global obligaba a reescribir la RLS entera para no cambiar nada.
Con el corte al revés, la RLS no se toca — quien solo transfiere lo suyo ve lo suyo, que ya es el
default de MODEL A. La única excepción es `usuarios_select`, la lista de destinos posibles: sin
sumarle los tres personales, el selector sale vacío.

El agujero que cierra: hasta acá, mover una obra **propia** exigía `obras_transferir`, que muestra
las obras de todos.

**Migrar agenda (`obras_migrar`) no lleva par personal**: la pantalla es sobre la agenda de otro por
definición.

Archivos: `sql/089_transferir_lo_propio.sql`, `sql/tests/obras_089.sql`, `db_schema/obras.md`,
`erp-app/src/modules/obras/permissions.ts`, las tres fichas (`obras/[id]`, `obras/personas/[id]`,
`obras/empresas/[id]`) y `PersonaDetalle` / `EmpresaDetalle` (el prop `veTodas` pasa a
`puedeTransferir`: gateaba solo ese botón).

## Migrar la agenda entera es otra acción, no una transferencia grande (`sql/088`)

Pedido del usuario junto con `sql/087`: *"una nueva función de transferir toda la agenda de un
usuario a otro (...) sería una función y vista aparte donde el usuario que tiene permiso selecciona
un usuario y decide migrar todos sus datos"*. El caso es que alguien se va de la empresa.

**Sin checklist: cascada total.** `obras_transferir` pregunta tres cosas por contacto porque el
saliente sigue trabajando acá y algo suyo queda del otro lado. Acá no queda nadie. Una agenda de 400
contactos no se tilda fila por fila y no hay decisión razonable que tomar 400 veces.

**Submódulo nuevo de tipo `vista`, sin función abajo.** No se reutilizan `obras_transferir` /
`obras_personas_todas` / `obras_empresas_todas`: quien liquida la agenda de alguien que se fue no es
necesariamente quien reasigna una obra suelta. Y no lleva submódulo-función porque la pantalla hace
una sola cosa — una función que cubre exactamente su vista es ceremonia (`GUIDE_PERMISSIONS`: una
vista puede no tener funciones).

**Los vínculos en obras de terceros sí se mueven**, al revés que en `sql/087`. Era el punto no obvio
del BACKLOG y el código lo mejoró: `obras_vinculo_guard_edicion` (`OB028`) dispara solo si
`obras_obra_compartida_con(obra, creado_por)`, así que mover el creador gana en las dos ramas — con
la obra compartida la edita el entrante, sin ella el guard deja de disparar y la edición vuelve al
dueño de la obra. Dejarlos con el `creado_por` de alguien que ya no está los congela para todos.

**Lo que el saliente recibió pasa al entrante, no solo lo que otorgó.** Decisión del usuario: el
reemplazo ocupa el lugar del que se fue, también para mirar. Es el punto donde MODEL A se estira —
un tercero termina compartiendo con alguien que no eligió—, y el recurso es que `otorgada_por` sigue
siendo el tercero: lo ve en su vista Compartido y puede revocarlo de una. Las alternativas eran
apagarlos (irreversible, y el acceso real ya muere al desactivar el usuario) o dejarlos (el saliente
conserva vista de obras ajenas).

**La confirmación es escribir el nombre del saliente, en la página y no en un `RightPanel`.** El
BACKLOG anticipaba panel; abrir un panel encima de una página que hace una sola cosa es un paso de
más. El bloque destructivo vive en la misma pantalla, debajo del resumen. Sin componente nuevo.

**Dos premisas del BACKLOG eran falsas y valen escritas**, las dos por mirar `database.types.ts` o el
texto de la decisión en vez de la base:

1. *"`notificar_transferencia_obra` no filtra `tipo`, pero `notificar()` corta por `obra_id` NULL"* —
   el trigger filtra: `sql/041` lo creó con `WHEN (NEW.tipo = 'obra')`. Mismo resultado, otro
   mecanismo; el corte de `notificar()` es un segundo cinturón.
2. *"La pregunta la contesta `obras_auditoria_transferencias`"* — no la contestaba. Hacía INNER JOIN
   con `obras`, así que las filas de persona y empresa (`obra_id` NULL) nunca se leyeron desde
   `sql/041`. Sin arreglarlo, el log por entidad de esta migración se escribía invisible y la
   decisión "log por entidad" no compraba nada. Arreglado en el mismo `sql/088` con
   `obras_etiqueta(tipo, id)`, que ya resolvía las tres clases.

Archivos: `sql/088_migrar_agenda.sql`, `sql/tests/obras_088.sql` (12/12), `db_schema/obras.md`,
`modules/obras/` (vista `MigrarAgendaView`, `permissions.ts`, `queries.ts`, `actions.ts`, `types.ts`,
`AuditoriaView`), `app/(erp-app)/obras/migrar/page.tsx`, `app/(erp-app)/obras/layout.tsx`.

## Transferir pregunta tres cosas, no dos (`sql/087`)

Pedido del usuario: *"cuando decido transferir una persona de una obra X mía, de la obra Y mía queda
desvinculado o contextual (...) puedo elegir entre desvincular de todas mis obras o dejarlo como
compartido contextual"*.

**El checklist contestaba media pregunta.** Tildado = cambia de dueño; destildado = queda mío y el
receptor lo ve contextual. Lo que nadie decidía era qué pasa con **mis otros vínculos** al contacto
que sí se va. El default silencioso era el peor de los tres resultados: la persona cambiaba de dueño,
mis vínculos quedaban vivos, y yo perdía el grant. La rama `obras_es_mi_obra` de
`obras_vinculos_de_obra` me seguía mostrando su nombre en mi propia obra mientras
`obras_ficha_persona` me lo negaba — fila visible, ficha cerrada, sin explicación.

**Ahora son tres estados por contacto**, en los tres paneles (obra, empresa, persona): *no se va* /
*se va, contextual* / *se va, y lo saco*. El 2 es el default por no destructivo. El grant recíproco
del estado 2 es el mismo statement que `sql/084` ya hacía hacia el receptor, con los usuarios al
revés y el ancla del otro lado — no hizo falta tabla ni columna nueva, `obras_persona_grant_contextual`
ya tenía las dos anclas.

**"Exclusivo" se retira.** `obras_contactos_exclusivos_de_*` ofrecía solo lo vinculado a una única
obra e **ignoraba `obras_persona_empresa` a propósito** (comentario de `sql/041`). Sobre la base: de
15 personas, 8 estaban en una sola obra **pero con empresa**, y se ofrecían como exclusivas sin
serlo. Migrar una de esas dejaba la arista persona↔empresa colgando y el contacto desaparecía de la
ficha de la empresa de su propio dueño. La regla verdadera no es "está en una sola obra" sino: *mover
un nodo deja aristas del lado del saliente, y cada una necesita un grant de vuelta o el vínculo se
corta*. `obras_transferir_candidatos(tipo, id)` lista todo con su resumen de vínculos y `mio` por
fila; el panel muestra las consecuencias en vez de esconder las opciones.

**Lo que el estado 3 no toca:** los vínculos que el saliente creó en obras de terceros (`sql/051`).
Decisión del usuario — *"no lo saques, queda a decisión del nuevo dueño"*. Matarlos vaciaría la obra
de alguien que no participó de la transferencia.

**Desvincular no puede notificar, y no es una decisión.** `notificaciones_listar` hace INNER JOIN
contra la tabla apuntada con la RLS del que lee, para no guardar el texto: una notificación sobre
algo que ya no ves existe como fila y nunca renderiza. Avisar un desvínculo exigiría copiar la
etiqueta, que es exactamente lo que la doctrina de `usuario_notificaciones` prohíbe (*"al que le
sacaron la obra no se le avisa"*). Lo entregable es el estado 2, donde el contacto sigue visible.
Cero tipos nuevos: la agenda migrada la contesta `obras_auditoria_transferencias`.

Archivos: `sql/087_transferir_tres_estados.sql`, `sql/tests/obras_087.sql` (10/10),
`db_schema/obras.md`.

## La obra es el único acto de compartir (`sql/086`)

Pedido del usuario: *"yo no quiero compartir empresas, yo solo quiero mostrar los que están
involucrados en la obra mediante contexto, y antes de compartir pasa por un proceso de checklist de
quiénes voy a mostrar a cada usuario que comparto"*.

**Eso ya era `obras_compartir_obra` desde `sql/082` + `sql/085`.** Checklist por usuario, lo tildado
a grant contextual anclado a esa obra, lo destildado apagado (estado deseado, `sql/049`). Lo que
faltaba era cerrar la **segunda puerta**: compartir una persona o una empresa desde su propia ficha,
que daba acceso completo y la metía en la agenda del receptor.

**Se dropean `obras_persona_compartida` y `obras_empresa_compartida`**, con `obras_compartir_persona`
/ `_empresa`, `obras_revocar_persona` / `_empresa`, `obras_relaciones_compartibles_empresa`,
`obras_*_grant_directo` (`sql/052`) y `obras_*_compartida_conmigo` (`sql/051`). Corte limpio sin
backfill: 0 grants directos activos al escribir la migración. La agenda de cada uno vuelve a ser
estrictamente lo suyo, y lo ajeno se ve dentro de la ficha que lo trajo. Supera *Lo compartido entra
al listado* (abajo): lo único que entra a una agenda ajena es la obra.

**Lo que se pierde, asumido:** colgar un contacto ajeno de una obra propia. Era la rama
`grant_directo` de `sql/052`; el contextual nunca lo habilitó. Dos usuarios con el mismo arquitecto
cargan cada uno el suyo —el detector difuso lo congela en `obras_aprobar`— o usan
`obras_personas_todas` / `obras_empresas_todas`, o se transfieren el contacto.

**Un hueco que se tapó de paso.** `obras_obra_persona_select` exigía grant **completo** para el
receptor: `sql/082` le puso la rama contextual anclada a la policy de empresa y no a la de persona.
La ficha igual mostraba la fila (sale por `obras_vinculos_de_obra`, DEFINER), así que no se notaba.
Ahora las dos policies tienen la misma forma.

**`obras_revocar_contextual(tipo, entidad, usuario, obra)`** (DEFINER, gate responsable) reemplaza a
`obras_revocar_persona` / `_empresa` en la X por fila de la vista Compartido. Es destildar del
checklist, desde el otro lado.

**Tareas.** La rama persona de `obras_compartir_registros` pierde el fallback "empresa compartida
directo" y ancla siempre en una obra compartida con ese usuario; sin ancla, `OB029`. Sigue a medio
camino por lo de siempre (el chip no lleva `?ctx=`): reparación en `BACKLOG.md`.

Archivos: `sql/086_solo_la_obra_comparte.sql`, `sql/tests/obras_086.sql`, `db_schema/obras.md`,
`modules/obras/` (`actions.ts` · `queries.ts` · `types.ts` · `CompartirPanel.tsx` ·
`CompartidoView.tsx` · `PersonaDetalle.tsx` · `EmpresaDetalle.tsx` · `ObraDetalle.tsx`),
`app/(erp-app)/obras/personas/[id]/page.tsx` · `empresas/[id]/page.tsx`.

---

## MODEL A — obras, empresas y personas son privadas por dueño (`sql/039`–`044`)

Pedido del usuario, y reescribe varias decisiones de los otros archivos de esta carpeta. **Nada se comparte salvo acto explícito del dueño.** Las empresas dejan de ser globales.

**Visibilidad.** `obras.responsable_id` / `obras_empresas.creado_por` / `obras_personas.creado_por` gobiernan. Ves lo tuyo, lo que te compartieron, y —con el permiso `_todas`— todo. `obras_puede_ver_persona` / `obras_puede_ver_empresa` ya no cuentan vínculos ni referencias: solo dueño, grant completo, o `_todas`.

**El contacto de persona se protege a nivel columna.** `telefono`/`whatsapp`/`email` (y sus `_norm`) salieron del `GRANT SELECT` de `obras_personas`. Antes un `select` directo los leía sin registro; el "único camino" era convención. Ahora `obras_ficha_persona()` —DEFINER, saltea el grant de columna— es de verdad el único, y toma contexto opcional (`obra`/`empresa` + id) para autorizar por grant contextual. Todo `select("*")` sobre `obras_personas` en el cliente pasó a lista de columnas.

**Compartir — dos formas, las dos las inicia `creado_por`:**
1. **Completa** (`obras_persona_compartida` / `obras_empresa_compartida`, funciones `obras_compartir_*` / `obras_revocar_*`): la entidad entra a la agenda del receptor. Lectura, no edición. Revocable.
2. **Contextual** (`obras_persona_grant_contextual`, ancla obra XOR empresa): el contacto de la persona se ve **solo dentro de esa ficha** de obra/empresa (`/obras/personas/{id}?ctx=obra:{id}`). No entra a la agenda ni al buscador. Muere con el vínculo —validado en vivo, sin trigger de limpieza—. Nace de transferir una obra/empresa o del checklist de "contactos exclusivos".

Un grant recibido **no se re-comparte**: las funciones exigen `creado_por`. **Ver no es editar:** `obras_*_update` exigen `creado_por = auth.uid()`; `_todas` mira y transfiere, no corrige — para editar lo ajeno hay que transferírselo (una puerta, no dos).

**Transferir — funciones separadas, una por entidad:**
- `obras_transferir(obra, a, contactos_exclusivos[])` — gate `obras_transferir`. Reasigna `responsable_id` + cascada.
- `obras_transferir_persona(persona, a)` — gate `obras_personas_todas`. Reasigna `creado_por`, revoca los grants del dueño saliente.
- `obras_transferir_empresa(empresa, a, personas_exclusivas[])` — gate `obras_empresas_todas` (submódulo nuevo).

~~**Cascada con confirmación.**~~ Superado por **Transferir pregunta tres cosas, no dos** (arriba, `sql/087`): el checklist ya no lista "lo exclusivo" sino todo lo del saliente, y cada fila elige entre tres estados.

**La cola de aprobación se recorta a las altas.** Bajo model A no se puede vincular lo que no se ve, así que el estado "vínculo a entidad ajena, congelado" desaparece: se dropeó `pendiente`/`motivo_rechazo` de `obras_obra_empresa` / `obras_obra_persona`, y `obras_guard_congelado` entera. Queda solo el alta parecida de obra/empresa/persona → congelada → `obras_aprobar`. `obras_marcar_pendiente` perdió las ramas de vínculo; la regla "marcar referente exige ver a la persona" pasó al WITH CHECK de `obras_obra_referente_insert`.

**El buscador enmascara, no esconde (`sql/042`).** El match crudo cross-owner (global y aviso de duplicados) devuelve la entidad ajena en **identidad mínima + nombre del dueño**, sin link, sin ficha. `obras_buscar` reparte tres funciones DEFINER que devuelven `es_ajeno` + `duenio`. `obras_buscar_duplicados_obra` ahora sí muestra el nombre de la obra ajena (sin dirección ni localidad); `obras_buscar_duplicados_empresa` pasó a DEFINER y enmascara igual.

**Filtro de alcance + badge.** `_todas` / `obras_transferir` habilitan un toggle `Míos | Todos` (URL `?alcance=`, default `propios`). Filas ajenas → badge "Ajena". El `getObras`/`getEmpresas`/`getPersonas` filtra server-side por dueño salvo que `alcance=todos` **y** el permiso lo respalde. (El filtro por dueño suma lo compartido conmigo: ver *Lo compartido entra al listado*, más abajo.)

**Corte limpio, sin backfill.** Al aplicar: 0 vínculos cross-owner, 0 pendientes. Quien veía por vínculo pierde acceso y se re-comparte a mano.

Clases de error nuevas: `OB020`–`OB025` (lista blanca `mensajeError`, texto para el usuario).

---

## Compartir con checklist y cascada de revocación (`sql/047`)

> **Recortado por *Compartir no reparte contactos* (`sql/082`, abajo).** El checklist de personas
> otorga grant **contextual**, no completo, y `origen_obra_id`/`origen_empresa_id` de
> `obras_persona_compartida` ya no existen. La cascada por origen sigue viva solo para empresas.

Pedido del usuario, sobre el modelo de *MODEL A*. Tres cosas:

**1. Compartir obra.** Antes la obra solo se transfería. `obras_obra_compartida` +
`obras_compartir_obra` / `obras_revocar_obra` le dan lo mismo que persona y empresa: lectura sin
mover `responsable_id`, revocable. `obras_select` y `obras_puede_ver_obra` suman la rama. El
receptor ve la obra y sus vínculos; el contacto de las personas sigue pasando por
`obras_ficha_persona()`, y solo abre la ficha completa de las que además recibieron su propio
grant (las tildadas). **Consecuencia sobre la comisión:** un receptor con `obras_referentes` ve
los referentes de la obra compartida — el dueño optó por compartirla, y el permiso sigue siendo
la barrera. Si molesta, se acota `obras_obra_referente_select`; hoy no.

**2. Checklist al compartir.** `obras_compartir_obra(obra, usuario, empresas[], personas[])` y
`obras_compartir_empresa(empresa, usuario, personas[])` — lo tildado, que tiene que ser **mío** y
estar vinculado, recibe su propio grant completo. Persona no lleva checklist: sus únicas
relaciones son empresas y el usuario la quiere compartir sola. Los checklists los sirve
`obras_relaciones_compartibles_obra/_empresa` (DEFINER, identidad mínima, `ya_compartida`).

**3. Cascada por origen.** `obras_empresa_compartida` / `obras_persona_compartida` ganan
`origen_obra_id` / `origen_empresa_id` nullable. **Última escritura gana:** compartir por
checklist setea el origen al padre (pisa lo que hubiera); compartir directo lo limpia. Revocar el
padre desactiva solo los grants con ese `origen_*` y `otorgada_por = auth.uid()` — un grant
directo, o colgado de otro padre, sobrevive.

**Bug preexistente arreglado acá.** `obras_empresas_select` (sql/039) tenía el EXISTS como
`c.empresa_id = c.id`: la columna `id` de `obras_empresa_compartida` sombrea `obras_empresas.id`,
así que comparaba la fila del grant contra sí misma. `obras_compartir_empresa` escribía la fila y
el receptor nunca veía la empresa. Ningún test lo cazó porque `obras_model_a.sql` solo probó
compartir **persona** (que pasa por `obras_puede_ver_persona`, DEFINER, sin sombreado). Mismo
sombreado evitado en `obras_select` de `sql/047` (`obras.id` calificado).

**Vista Compartido** (`obras_compartido`, tab). `obras_compartidos_por_mi()` — DEFINER como las
de Auditoría (los JOIN tienen que resolver aunque un nombre quede fuera de la RLS del que
pregunta), gate propio, tope 500. Muestra qué compartí, con quién y de qué origen. Compartir y
revocar no son submódulos: son acto del dueño, igual que ya era `obras_compartir_persona`. "Solo
lo que compartí", no "lo que me compartieron" — eso último, si alguien lo pide.

Clases de error nuevas: `OB026` (solo el responsable comparte/revoca la obra), `OB027` (sin
acceso a la vista Compartido).

Test: `sql/tests/obras_047.sql`, 11/11 (los casos 10-11 son la regresión de `sql/048`).

**Bug que vale recordar (`sql/048`): el OUT param `id` de un `RETURNS TABLE` sombrea la
columna.** `obras_relaciones_compartibles_obra/_empresa` devuelven `(tipo, id, etiqueta, …)`, así
que dentro del cuerpo `id` es la variable plpgsql. El guard `IF NOT EXISTS (SELECT 1 FROM obras
WHERE id = p_obra_id …)` es ambiguo (`42702`) y aborta la función entera al planear — no en la
fila, en la primera llamada. La RPC fallaba siempre, `getRelacionesCompartibles*` tiraba, la
action rechazaba, y el `.then()` del panel nunca corría: el bloque "Compartir también" quedaba
invisible con datos válidos detrás. Los 9 casos de `obras_047.sql` no ejercían estas dos
funciones. **Regla:** en una función con `RETURNS TABLE`, toda referencia a una columna que
comparte nombre con un campo de salida va calificada por tabla/alias.

**Compartir editable (`sql/049`).** El checklist pasó de "agregar" a **estado deseado**:
`obras_compartir_obra` / `obras_compartir_empresa` re-llamadas con un usuario que ya tiene la
obra/empresa ahora también **desactivan** la cascada de ese padre que quedó destildada
(`origen_* = padre`, `otorgada_por = auth.uid()`). Deja ajustar el reparto —sacar una empresa,
sumar una persona— sin revocar y volver a compartir. Un grant directo (`origen` NULL) o colgado
de otro padre no se toca, igual que en `obras_revocar_*`. Array vacío = se apaga toda la cascada
de ese padre. El alta inicial no cambia: no hay grants de origen que apagar. El panel abre este
modo al clickear un usuario de "Compartida con". Test: `sql/tests/obras_049.sql`, 4/4.

**Vista Compartido anidada (`sql/050`).** `obras_compartidos_por_mi()` devuelve el origen como
`(origen_tipo, origen_id, origen_nombre)` en vez de un texto ya armado — sin el id no se puede
agrupar. `CompartidoView` anida cada fila de cascada bajo su obra/empresa padre (borde izquierdo
+ sangría, badge "vía la obra/empresa"). El padre siempre está en el resultado: `obras_compartir_*`
inserta su grant antes que la cascada; si faltara, la fila cae como raíz. Sin sección por tipo:
el árbol ya ordena.

---

## El receptor de una obra compartida vincula sus contactos (`sql/051`)

Pedido del usuario, sobre *Compartir con checklist*. Recibí una obra compartida y quiero sumarle
**mis** empresas y personas. El dueño de la obra sí ve lo que sumé —con el nombre y "lo agregó
Fulano"—, pero no puede reescribir mis roles/observaciones. Y a la inversa: la ficha del receptor
no renderiza el interior que no se le compartió, ni siquiera la fila vacía. Cinco decisiones,
varias revierten cosas escritas en otras secciones:

**1. El buscador de persona al vincular deja de ser el de identidad mínima.** `VincularPersonaPanel`
llamaba a `buscarDuplicadosPersona` (DEFINER, cross-owner, "encontrar no es abrir la ficha"). Ahora
llama a `buscarPersonasParaVincular` → `getPersonas()`, acotado a mi agenda, igual que el panel de
empresas ya hacía con `getEmpresas()`. **Supera** *MODEL A → búsqueda de identidad mínima* y
*UI → La persona se elige por búsqueda*: el aviso de "ya cargada por otro" queda solo en el alta
(`PersonaFormPanel`), que es donde el duplicado importa. Vincular es sumar algo mío.

**2. Los vínculos tienen `creado_por`, y separan "vínculo de la obra" de "lo que sumó un
receptor".** `obras_obra_empresa` / `obras_obra_persona` ganan la columna (NOT NULL, la pone el
trigger `set_creado_por`, no editable por el cliente; backfill = `obras.responsable_id`). El SELECT
de vínculos deja de colgar de `obras_puede_ver_obra` (que sql/047 volvió `true` entero para el
receptor) y pasa a: **mío** (`creado_por = auth.uid()`) · **responsable** de la obra
(`obras_es_mi_obra` — ve todo, incluido lo del receptor) · **admin** (`obras_transferir`) ·
**receptor** solo si la obra **y** la entidad me están compartidas. El responsable ve todo, pero
la empresa/persona que sumó un receptor es privada de ese receptor, así que el nombre no llega por
el embed de PostgREST (vendría NULL → la ficha mostraría "—"). Lo resuelve
**`obras_vinculos_de_obra(obra)`** (DEFINER, identidad mínima — nombre/razón social + roles, nunca
contacto) que además trae `creado_por` + su nombre y `es_de_receptor`. `getObra` deja de embeber
los vínculos y usa esta función; la ficha marca "lo agregó Fulano" cuando `es_de_receptor` y
`creado_por <> yo`. Para el **receptor**, el interior no compartido no vuelve en la función — ni
la fila vacía. Reversa de *sql/047 → El receptor ve la obra y sus vínculos*.

**Editar un vínculo es de quien lo creó.** La policy de UPDATE deja pasar al responsable (para
QUITAR de la obra lo del receptor, y editar lo suyo y lo heredado de una transferencia). El
trigger `obras_vinculo_guard_edicion` acota: si la fila la creó alguien que hoy es receptor de la
obra y no es él quien edita, `roles` / `observaciones` / `empresa_id` no se tocan — solo `activo`
(`OB028`). "Heredado de una transferencia" no dispara: el `creado_por` saliente no es receptor. La
ficha esconde "Editar vínculo" cuando `es_de_receptor && creado_por <> yo`; "Quitar de la obra"
queda.

**3. El INSERT de vínculo se abre al receptor, acotado a lo suyo.** `obras_obra_*_insert` exigía
`obras_es_mi_obra(obra_id)`. Ahora: mi obra (cualquier entidad visible, como antes) **o** obra
compartida conmigo **y** `entidad.creado_por = auth.uid()`. La barrera está en RLS, no en el
buscador — ocultar no autoriza.

**4. El receptor no ve comisiones.** `obras_obra_referente_select` pasa a
`obras_es_mi_obra OR obras_transferir`. sql/047 dejó dicho "un receptor con `obras_referentes` ve
los referentes de la obra compartida — si molesta se acota; hoy no". Ahora molesta: es interior no
compartido y la comisión es el dato sensible de la ficha. `permisos.referentes` en la page se
gatea además con `esMio` para que el botón "Marcar referente" no quede muerto.

**5. Revocar arrastra los vínculos del receptor, y el panel avisa.** `obras_revocar_obra` desactiva
además los `obras_obra_empresa` / `obras_obra_persona` de esa obra con `creado_por = p_usuario_id`
(al bajar las de persona, `cascada_desactivar` de sql/036 limpia sus referentes). Antes de revocar,
`CompartirPanel` llama a `obras_contar_vinculos_receptor(obra, usuario)` (DEFINER, gate responsable)
y, si hay alguno, abre un `ConfirmModal` que dice cuántos se van a desactivar.

**Helpers (DEFINER, una línea)**: `obras_obra_compartida_con(obra, usuario)` + wrapper `_conmigo`,
`obras_empresa_compartida_conmigo` / `obras_persona_compartida_conmigo`. El EXISTS inline en la
policy con la columna `*_id` sin calificar repite el sombreado que ya mordió en sql/047-048
(`c.obra_id = c.obra_id`); un parámetro de función no se sombrea.

**Fuera de alcance:** el receptor de una **empresa** compartida agregándole empleados
(`obras_persona_empresa` no tiene `creado_por`); el usuario habló de obras. Si aparece, misma
receta.

Test: `sql/tests/obras_051.sql`.

---

## El grant heredado de una obra ve el contacto, no lo reparte (`sql/052`)

> **Superado en parte por `sql/082` (abajo).** Para personas ya no existe el "grant heredado": el
> checklist otorga contextual, que nunca habilitó vincular. `obras_persona_grant_directo` quedó en
> "¿hay grant activo?". La rama de empresas sigue tal cual.

Pedido del usuario, sobre *Compartir con checklist*. Compartir una obra tildando una persona/empresa
en el checklist le da al receptor un `obras_persona_compartida` / `obras_empresa_compartida`
**completo** (solo con `origen_obra_id` seteado). `obras_puede_ver_persona` / `_ver_empresa` no
miran `origen_*`, así que ese grant pasaba el WITH CHECK de `obras_obra_persona_insert` /
`_empresa_insert` igual que un share directo: el receptor podía colgar ese contacto de **sus
propias** obras, y quedaba un vínculo vivo en obras que el dueño del contacto ni ve.

**El hueco llegaba por UI, no solo por RPC.** El botón "Vincular obra" de la ficha de persona/empresa
se gateaba con `puedeVincular()` a secas, sin `esMio`. El receptor abría la ficha del contacto
compartido (desde la ficha de la obra), clickeaba "Vincular obra", buscaba una obra suya y la
colgaba. El sentido inverso (`VincularPersonaPanel` parado en la obra) ya estaba tapado: filtra a
`getPersonas()` con `creado_por = me`.

**Decidido — para colgar un contacto de una obra propia, el contacto tiene que ser mío:**
`obras_obra_persona_insert` / `_empresa_insert` — la rama `obras_es_mi_obra(obra_id)` exige además
dueño **o** `obras_persona_grant_directo` / `_empresa_grant_directo` (grant con `origen_* IS NULL`)
**o** `obras_personas_todas` / `obras_empresas_todas`. El grant con origen abre la ficha **dentro
de la obra que lo trajo** (`obras_ficha_persona` con contexto), no la cartera del receptor. La
rama de obra compartida (`obras_obra_compartida_conmigo AND entidad.creado_por = auth.uid()`) no
cambia — ahí ya se exigía contacto propio.

**El share directo sí habilita, y al revocarlo cascadea.** Es un acto explícito del dueño sobre
ese contacto puntual. `obras_revocar_persona` / `_empresa` ganan la cascada que `obras_revocar_obra`
ya tenía (`sql/051`): desactivan los `obras_obra_persona` / `_empresa` de ese contacto con
`creado_por = p_usuario_id` (los referentes caen por `cascada_desactivar` de `sql/036`).
`obras_contar_vinculos_persona_receptor` / `_empresa_receptor(entidad, usuario)` (DEFINER, gate
dueño de la entidad) alimentan el aviso previo — `CompartirPanel` abre un `ConfirmModal` con el
conteo, `CompartidoView` avisa con texto fijo.

**UI:** la ficha ofrece "Vincular obra" solo si `esMio || grantDirecto || veTodas`
(`tieneGrantDirectoPersona` / `_Empresa` → `obras_*_grant_directo`). Espeja la RLS; la barrera
real es el WITH CHECK.

Helper nota: `obras_*_grant_directo` es `obras_*_compartida_conmigo` (sql/051) + `origen_* IS NULL`.
DEFINER por lo mismo — un EXISTS inline en la policy podría recursar contra la policy de
`obras_*_compartida`.

Test: `sql/tests/obras_052.sql`, 5/5.

---

## Compartir una obra o empresa no reparte contactos (`sql/082`)

Pedido del usuario: *"cuando comparto obra que sea contextual nada más, no que esté compartiendo la
persona. Cuando comparto empresa también"*. El motivo: compartir se había vuelto difícil de razonar.

**El checklist escribe `obras_persona_grant_contextual`, no `obras_persona_compartida`.** El grant
completo del checklist (`sql/047`) ya venía siendo recortado tres veces —`sql/052` (no puede colgar
el contacto de las obras propias del receptor), `sql/070` (no ve la razón social de su empresa),
`sql/049` (estado deseado, para poder desarmar la cascada)—. Cada parche lo acercaba a algo que ya
existía al lado desde `sql/041`: el grant contextual de transferir. Dos mecanismos para una
intención, y el fuerte convergiendo al débil a golpe de migración.

**Ahora transferir y compartir tienen una sola regla:** el contacto ajeno se ve dentro de la ficha
que lo trajo, nunca en la agenda. La persona tildada se abre solo con `?ctx=obra:{id}` /
`?ctx=empresa:{id}`, no entra al listado, al buscador ni a la agenda del receptor, y no habilita
vincular. El contacto sigue saliendo solo por `obras_ficha_persona(..., ctx)`, que registra en
`obras_accesos_persona`.

**El ancla es el origen.** `obras_persona_compartida.origen_obra_id` / `origen_empresa_id` se
dropean: el `obra_id` / `empresa_id` del grant contextual dice de dónde vino y por dónde se abre, en
una columna. Consecuencia: `obras_persona_compartida` pasa a tener un solo significado —acceso
completo, acto directo del dueño— y `obras_persona_grant_directo` (sql/052) colapsa a
"¿hay grant activo?". Destildar, `obras_revocar_obra` y `obras_revocar_empresa` apagan por ancla.

**Dos lecturas había que abrir, o el receptor dejaba de ver la fila.** `obras_vinculos_de_obra`
(sql/051) mostraba la persona solo con grant **completo**: sin el parche, compartís la obra y el
receptor no ve ninguna. La policy `obras_persona_empresa_select` (sql/027) es
`obras_puede_ver_persona`, que no cuenta contextuales: sin el parche, la ficha de la empresa
compartida queda sin empleados. Las dos ramas nuevas van **ancladas** —`obras_persona_grant_ctx_obra_conmigo` /
`_empresa_conmigo`, DEFINER con parámetro— para que un grant traído por la obra A no abra la fila en
la obra B. `obras_personas_select` (sql/039) ya admitía el contextual: el nombre salía por RLS desde
siempre.

~~**Las empresas no cambian: grant completo.**~~ **Superado por *La empresa también es contextual*
(`sql/085`), abajo.** El argumento era correcto —sin `obras_ficha_empresa()` ni columnas revocadas,
"contextual" era solo de UI— y la respuesta terminó siendo construir esas dos piezas, no bajar el
estándar.

**`obras_revocar_persona` no cambia.** Sigue bajando el grant directo **y** los contextuales de esa
persona para ese usuario. Es el corte total que dice el botón, y es lo que hace funcionar el revocar
de la vista Compartido parado sobre una fila de cascada. Efecto lateral aceptado: revocar un share
directo también saca el acceso que venía por el checklist de una obra; el checklist lo muestra
destildado y re-tildarlo lo restituye.

**Bug preexistente arreglado acá:** `obras_revocar_empresa` perdió la cascada de personas al
reescribirse en `sql/052` (quedó la de `obras_obra_empresa` y se cayó la de `origen_empresa_id`).
Revocar una empresa dejaba vivos los grants de las personas tildadas en su checklist. Ningún test lo
cazó: `obras_052.sql` probó la cascada de vínculos, no la de grants.

**Compartir al asignar una tarea también va contextual — y queda a medio camino, a propósito.**
`obras_compartir_registros` (`sql/062`/`064`) otorgaba grant completo con origen. Ahora ancla en la
misma obra/empresa que ya buscaba para el origen —mía, activa, vinculada a esa persona y ya
compartida con ese usuario—, así que el vínculo que el grant valida en vivo existe por construcción.
Sin ancla corta con `OB029`. **Lo que no funciona todavía:** ni con ancla el receptor abre la ficha
desde la tarea, porque `obras_puede_ver_persona_de` —y por lo tanto `puede_abrir_registro`— no
cuenta contextuales, y el chip sale de `entes.ruta` sin `?ctx=`. El usuario decidió romperlo ahora y
repararlo después: la reparación (ancla `tarea_id`, su rama en `obras_ficha_persona`, el chip con
ctx, `obras_puede_abrir`) está en `BACKLOG.md`.

**Filtro de vista para el responsable (sin SQL).** La ficha de obra suma un check "Ocultar lo que
agregaron otros", que esconde los vínculos con `agregadoPor` (los que sumó un receptor, `sql/051`).
Es **filtro de vista, nunca policy**: el responsable es la autoridad de la obra y la base le sigue
devolviendo todo — si se lo escondiera en RLS dejaría de poder auditar lo que cuelga de su obra, que
es lo contrario de *MODEL A*. Para sacarlo de verdad ya está "Quitar de la obra".

Archivos: `sql/082_compartir_contextual.sql`, `sql/tests/obras_082.sql`,
`modules/obras/components/ObraDetalle.tsx` · `CompartirPanel.tsx` · `CompartidoView.tsx`.

---

## La empresa también es contextual (`sql/085`)

Pedido del usuario: *"es para no ensuciar la agenda y que quede el mismo acercamiento que las
personas"*. Llegó investigando otra cosa: al transferir una obra sin tildar nada, el receptor igual
veía las empresas y personas vinculadas.

**Contextual son dos capas, no una, y empresa solo tenía la de arriba.** RLS es por fila, no por
(fila, contexto): no sabe en qué página estás. En persona el ancla no la impone la policy sino
`obras_ficha_persona(persona, ctx_tipo, ctx_id)`, que recibe el contexto como parámetro — y eso
funciona como barrera solo porque el dato sensible está detrás de esa puerta, con las columnas
fuera del `GRANT SELECT`. Empresa no tenía ni la puerta ni el revoke, y por eso `sql/082` la dejó
en grant completo. Se construyeron las dos: `obras_ficha_empresa(empresa, ctx_obra)` y el revoke de
`website`/`telefono`/`email`/`direccion`.

**El ancla de una empresa solo puede ser una obra.** Una empresa no cuelga de otra empresa, así que
`obras_empresa_grant_contextual` no repite el XOR ni los índices parciales de su gemela: UNIQUE
entero sobre `(empresa_id, usuario_id, obra_id)`, que además es lo que `ON CONFLICT` quiere sin
cláusula WHERE.

**Sin `obras_accesos_empresa`.** El log de persona existe porque el celular de alguien es dato
personal y hay que poder auditar quién lo miró. El teléfono de una constructora no. Se suma si
alguien lo pide.

**Compartir una empresa desde su ficha no cambia:** sigue siendo grant completo. Es acto directo
del dueño sobre su agenda, no cascada de una obra. Lo que pasó a contextual es lo que llega
*arrastrado por una obra* — el checklist de `obras_compartir_obra`, la cascada de
`obras_transferir` y la rama empresa de `obras_compartir_registros`.

**Tres lecturas había que abrir**, o el receptor dejaba de ver la fila: `obras_empresas_select`,
la policy `obras_obra_empresa_select` y `obras_vinculos_de_obra` (rama empresa, y el `detalle` de
la rama persona que `sql/070` gatea por `obras_puede_ver_empresa`). Las tres últimas, ancladas.

**Tareas se tocó aunque el usuario dijo que podía romperse.** Dropear `origen_obra_id` dejaba a
`obras_compartir_registros` escribiendo una columna inexistente: eso no es degradarse, es crashear
al asignar cualquier tarea que arrastre una empresa. La rama recibió la misma forma que `sql/082`
le dio a la de persona — ancla en la obra y `OB029` si no hay ninguna. Sigue a medio camino por el
mismo motivo que persona (el chip no lleva `?ctx=`); la reparación conjunta está en `BACKLOG.md`.

**Consecuencia asumida:** el checklist de una obra dejó de emitir `compartido`/`revocado` para
empresas, porque las tablas de grant contextual no llevan el trigger de `sql/083`. Es lo que ya
pasaba con personas desde `sql/082`.

**Trampa de Postgres que costó una pasada.** El primer intento usó `REVOKE SELECT (columna)`, que
**no recorta** un `GRANT SELECT` de tabla entera: queda sin efecto y `column_privileges` sigue
mostrando las cuatro columnas. Hay que revocar el de tabla y otorgar la lista, como ya hacía
`sql/039` §4. Lo cazó verificar contra la base después de aplicar, no el `tsc`.

Error nuevo: `OB030` (`obras_ficha_empresa`, sin acceso). Test: `sql/tests/obras_085.sql`, 12/12 —
el caso L es el que motivó la migración, y el A fija la trampa del revoke.

**Segunda trampa, esta al escribir el test:** las dos empresas se llamaban parecido y el detector de
duplicados difuso congeló la segunda (`pendiente`), así que el caso que esperaba `OB029` moría con
`OB020`. Las entidades de un test no pueden compartir tokens entre sí.

Archivos: `sql/085_empresa_contextual.sql`, `sql/tests/obras_085.sql`, `db_schema/obras.md`,
`modules/obras/queries.ts` · `types.ts` · `components/EmpresaDetalle.tsx` · `EmpresaFormPanel.tsx` ·
`EmpresasView.tsx` · `ObraDetalle.tsx`, `app/(erp-app)/obras/empresas/[id]/page.tsx`.

---

## La empresa de una persona en la obra la ve quien ve la empresa (`sql/070`)

**`obras_vinculos_de_obra` devuelve `detalle` (la razón social de `obras_obra_persona.empresa_id`)
solo al responsable, a `obras_transferir` o a quien ve la empresa (`obras_puede_ver_empresa`).**
El subselect de la DEFINER no filtraba: el receptor al que le tildaron la persona y no su empresa
leía el nombre, que la ficha de la persona ya le ocultaba vía RLS. Mismo dato, dos respuestas.

**`empresa_id` sigue saliendo.** El receptor que vinculó su persona con una empresa tildada puede
editar el vínculo después de que el dueño la destilde; con el id en NULL, `VincularPersonaPanel`
arrancaría en "Sin especificar" y al guardar borraría la empresa. Un uuid suelto no vale nada
(misma exposición aceptada en `sql/062`).

Test: `sql/tests/obras_070.sql`, 4/4. Aplicado como `070` + `070b` (el primero ocultaba también
el id); el archivo tiene el estado final.

---

## ~~Lo compartido entra al listado~~; editar sigue siendo del dueño (sin SQL)

> **Superado por *La obra es el único acto de compartir* (`sql/086`, arriba)** en su primera mitad:
> sin share directo, lo único que entra a un listado ajeno es la obra. `getPersonas` / `getEmpresas`
> filtran `creado_por = me` a secas. La segunda mitad —editar y desactivar piden `esMio`— sigue en
> pie.
>
> **Recortado antes por `sql/082`.** Lo que entra al listado es el share **directo**. La persona tildada
> en el checklist de una obra/empresa ya no: su grant es contextual y se abre solo desde esa ficha.
> `idsCompartidosConmigo` no cambió — lee `obras_persona_compartida`, que ahora solo tiene directos.

**`getPersonas` / `getEmpresas` muestran lo propio + lo compartido conmigo, igual que `getObras`.**
Filtraban `creado_por = me` y la persona o empresa compartida —directa o por el checklist de una
obra— solo se alcanzaba desde la ficha de la obra o el buscador global, aunque el texto del listado
decía "las que te compartieron". El grant contextual no entra: abre solo dentro de su ficha.
`idsCompartidosConmigo(tipo, me)` sirve a los tres listados.

**Los buscadores de vincular se recortan a `creado_por = me`** después de pedir el listado: el
sql/051 los dejó "acotados a mi agenda" y la RLS de vínculo rechaza el grant heredado (sql/052).

**Editar y desactivar en las tres fichas piden `esMio`.** La page pasaba el permiso a secas y el
receptor con `obras_editar` / `obras_desactivar` / `*_editar` veía botones que `obras_update`,
`obras_set_activo` y las RLS de update de persona/empresa rechazan. Espeja la base; la barrera sigue
ahí.

Archivos: `modules/obras/queries.ts`, `modules/obras/actions.ts`
(`buscarPersonasParaVincular` / `buscarEmpresasParaVincular`), `app/(erp-app)/obras/[id]/page.tsx`,
`obras/personas/[id]/page.tsx`, `obras/empresas/[id]/page.tsx`, `PersonasView.tsx`.

---

## La obra es privada de su responsable

La spec no menciona dueño de obra. Se agregó `obras.responsable_id` (NOT NULL, arranca en el creador) y **gobierna la visibilidad**: cada vendedor ve sus obras y nada más.

Quien tenga `obras_transferir` las ve todas — no puede reasignar lo que no ve. Ese permiso es el equivalente funcional de "administrador" para este módulo; no existe un rol, porque el sistema no tiene roles.

**Ver no es editar.** Quien transfiere mira y reasigna; para corregir datos de una obra ajena tiene que transferírsela primero. Una puerta, no dos.

Las transferencias se registran en `obras_transferencias`. Sin eso, "¿por qué no veo más esta obra?" no tiene respuesta.

---

## Las personas tienen alcance; las empresas no

> **Superado por *MODEL A* (arriba).** Las empresas también son privadas por dueño; el alcance de personas ya no incluye "vinculada a una obra propia". El resto del razonamiento (registro de acceso, búsqueda de identidad mínima, sin exportar) sigue vigente.

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

## La visibilidad se pregunta por usuario, sin copiarla (`sql/062`)

Fase C de `PLAN_TAREAS_VINCULOS.md` (decidido el 2026-09-14, `BACKLOG.md` → "Compartir al asignar"). Tareas necesita contestar "¿el usuario U puede abrir el registro R?" para decidir quién queda asignado (Fase D) y qué ofrecer compartir (Fase E), sin escribir una segunda copia de las reglas de *MODEL A*.

**`usuario_tiene_permiso(usuario, codigo)`** (`decisiones/global/permisos.md`) parametriza `tiene_permiso`. **`obras_puede_ver_obra_de/_empresa_de/_persona_de(id, usuario)`** son los cuerpos vigentes de `obras_puede_ver_obra/_empresa/_persona` con `auth.uid()` → el parámetro — las tres funciones de siempre quedan como envoltorios de una línea, ninguna policy se toca. **`obras_puede_abrir(tipo, id, usuario)`** es el mismo `CASE` que ya usa `obras_etiqueta`, sin la rama de grant contextual: el chip de un vínculo abre la ficha sin el contexto (obra/empresa) que ese grant necesita, así que no cuenta.

**`puede_abrir_registro(ente, id, usuario)`** es la puerta genérica, cross-módulo: `entes.activo AND usuario_tiene_permiso(usuario, entes.submodulo) AND <rama del módulo>` — el submódulo del ente (`obras_personas` para una persona, no alcanza con `obras_ver`) más la fila. Mismo criterio de extensión que `etiqueta_registro`/`relacionados_de_registro` (`sql/059`/`060`): un módulo que registre entes suma su `WHEN`.

**`queda_afuera(usuario, ente, id)`** es el único predicado de la regla completa (Fase D la usa tal cual): `usuario IS DISTINCT FROM auth.uid() AND NOT puede_abrir_registro(...)` — quien actúa nunca queda afuera de su propio acto, sin importar si podría abrir lo que vincula.

**`sin_acceso(pares)` no puede llamar `etiqueta_registro` a ojos cerrados.** Al ser `DEFINER`, corre sin la RLS de quien pregunta — llamarla directo devolvería el nombre de una obra que quien pregunta no ve. El `CASE WHEN puede_abrir_registro(..., auth.uid()) THEN etiqueta_registro(...) END` es obligatorio: la etiqueta se apaga para **quien llama**, no para el usuario por el que se pregunta. **Exposición aceptada:** `sin_acceso`/`asignados_con_acceso` dejan confirmar si un usuario puede abrir un id que quien pregunta ya tiene — sin nombre de lo que no ve, y un uuid suelto no vale nada.

**Compartir para una tarea es aditivo — a diferencia del checklist de Obras.** `obras_compartir_obra`/`_empresa` son "estado deseado" desde `sql/049`: re-llamarlas con un usuario que ya tiene la entidad apaga la cascada que quedó afuera del array. Eso rompe el flujo de Tareas — compartir para que alguien pueda abrir un vínculo no debe poder revocar nada. **`obras_compartir_registros(usuario, registros)`** es una función nueva y aditiva: cada upsert lleva `WHERE NOT <tabla>.activo`, así que un grant ya activo no se toca (ni origen ni cascada). Reutiliza los mismos cortes (`OB020`/`OB021`/`OB023`/`OB026`) y, para empresa/persona, busca sola el origen (una obra o empresa mía, activa, vinculada, ya compartida con ese usuario "en esta llamada o de antes") — se comporta como el checklist para la cascada, sin heredar su semántica destructiva. **`compartir_registros(selecciones)`** (INVOKER) agrupa por usuario y por `entes.modulo` y llama a la función del módulo — un módulo nuevo suma su rama.

Test: `sql/tests/acceso_registros.sql`, 13/13 (con dos sub-chequeos en 04 y 08). La base de test solo tiene ADMIN y TESTER: varios casos activan/desactivan un submódulo dentro de la misma transacción para simular a alguien sin acceso — documentado en el header del archivo.

## El alcance por fila no es un permiso nuevo

CLAUDE.md prohíbe permisos por fila o por campo fuera del sistema de submódulos. Nada de lo de arriba lo rompe: son las mismas vistas con alcance de datos en RLS, igual que las obras se acotan por responsable. No hay excepción que registrar.

La comisión sí necesitaba tratamiento: es un dato sensible dentro de la ficha de obra. Se resolvió como **función** (`obras_referentes`) y no como permiso de campo — la fila de `obras_obra_referente` contiene la comisión, así que verla es verla.

---

## `obras_aprobar` no es una llave a la agenda

La primera versión de `sql/033` metía `OR tiene_permiso('obras_aprobar')` adentro de `obras_puede_ver_persona`, para que quien aprueba pudiera ver la persona congelada que está juzgando. Eso convertía el permiso de aprobar en **la agenda entera con contacto incluido** — más de lo que da `obras_personas_todas`, y sin que el nombre lo insinúe.

Lo cazaron los casos 06 y 07 de `sql/tests/obras_033.sql`, que son los que afirman lo del párrafo anterior: con esa cláusula, el vínculo pendiente seguía abriendo la ficha para cualquiera que aprobara.

**Decidido:** quien aprueba mira por `obras_pendientes()` y `obras_pendiente_similares()`, que son `SECURITY DEFINER` y devuelven identidad mínima. Mismo criterio que la vista de Auditoría: la pantalla que vigila el acceso al contacto no puede ser otra puerta al contacto.

La excepción va del otro lado: `obras_pendiente_similares` **sí** muestra el nombre de la obra ajena contra la que se parece. Sin eso la decisión de aprobar es a ciegas, que es lo contrario de lo que la cola existe para hacer. Queda acotada a `obras_aprobar` y no devuelve contacto de nadie.

---

## El buscador global no inventa visibilidad (`sql/037`)

> **Reescrito por *MODEL A* / `sql/042`.** Las tres ramas pasan por funciones DEFINER (`obras_buscar_obras` / `_empresas` / `_personas`) que enmascaran lo ajeno: identidad mínima + `duenio`, `id` NULL, `es_ajeno = true`. La obra/empresa ajena **sí aparece** ahora (enmascarada), no desaparece. `visible`/`cargada_por` → `es_ajeno`/`duenio`.

Una sola barra para obra, empresa y persona. Lo que había que decidir no era el
match sino el alcance: son tres entidades con tres reglas distintas, y un buscador
que las junta es el lugar perfecto para escribir una cuarta sin darse cuenta.

**No hay cuarta regla.** `obras_buscar` es `SECURITY INVOKER` y las ramas de obras
y empresas son `SELECT` directos: deciden las policies que ya existen. Escribir el
alcance adentro de una DEFINER habría dejado dos copias de la misma condición, y la
que se desactualiza es siempre la que nadie mira.

La rama de personas es la única que necesita ver más que quien pregunta, así que va
en su propia función DEFINER: las que están fuera de alcance vuelven con identidad
mínima y `visible = false`. Es la capa de `obras_buscar_duplicados_persona` otra vez
—encontrar a alguien no es abrirle la ficha— y el contacto sigue saliendo solo por
`obras_ficha_persona()`, que registra. El caso 12 del test lo afirma: buscar no deja
a nadie adentro de `obras_accesos_persona`.

Es el mismo corte de `sql/033` entre el match crudo y el enmascarado, con los roles
al revés: acá lo enmascarado es lo interno y lo que llama la app es el envoltorio
INVOKER. Consecuencia: `obras_buscar_personas` necesita `GRANT EXECUTE` a
`authenticated` aunque no la llame nadie más, porque corre con el rol de quien
pregunta.

**La obra ajena no aparece.** El aviso ciego la devuelve con `nombre`, `direccion` y
`localidad` en NULL, así que como resultado sería una fila sin nada que mostrar. El
caso que importa —dos vendedores cargando el mismo edificio— ya lo cubre el aviso al
crear, que es cuando sirve. Buscar es para encontrar lo que uno puede abrir.

**Substring y no `similarity`.** El parecido de `pg_trgm` responde "esto ya está
cargado"; un buscador responde "empecé a escribir el nombre", y ahí
`similarity('gonz', 'juan gonzalez')` no llega ni cerca del umbral. Se busca con
`LIKE '%texto%'` sobre las columnas `_norm`, que ya existen y ya están indexadas. De
paso, la normalización desarma el patrón: un `%` tipeado en la barra queda en
espacio, no en comodín. El caso 14 lo fija.

Lo que el substring no hace: "perez juan" no encuentra a Juan Pérez. Partir el texto
en palabras y exigirlas todas mata el uso del índice, y es una vuelta que todavía
nadie pidió.
