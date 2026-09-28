# Decisiones — módulo contactos

> **Estado: ficha aprobada (2026-09-25), armada con el usuario junto con la de Obras
> (`decisiones/obras.md`) y revisada punto por punto. Tramo 1 del SQL (`sql/127`, `sql/128`) aplicado
> el 2026-09-26.** *Pendiente*, al pie, tiene solo lo que se decide al escribir el SQL de los tramos
> que faltan.

## Personas y empresas viven en su propio módulo, no en Obras (2026-09-25)

**Contactos es un módulo aparte, dueño de personas, empresas y de sus vínculos con cualquier
registro.** El mismo contacto dura más que una obra y aparece en más de un módulo: la obra (comercial),
la etapa (Presupuestos, operativo) y la unidad (Post-venta). Con los contactos en un módulo y los
vínculos en otro, Contactos tendría que leer tablas ajenas para saber quién ve a una persona.

Descartado: meterlos en Obras. Era más simple hoy, pero con Presupuestos y Post-venta "los contactos de
obras" pasaban a ser el directorio de todo con otro nombre, y mudarlos después es renombrar tablas y entes.

**El vínculo apunta a `(ente, registro_id)`, como `tareas_vinculos`** (`GUIDE_ENTES.md` §2.6). La
regla de quién ve un vínculo es "ve el registro" (`etiqueta_registro`), sin conocer las tablas de
Obras. Lleva `desde` / `hasta`: cambia el capataz, se reemplaza la constructora, se va un inquilino, y
la historia queda. `hasta` cierra un vínculo que existió; `activo = false`, uno cargado por error.

**Un contacto se ve junto con el registro al que está vinculado; no hay marca de "reservado".**
Los comerciales (referente, desarrolladora, quien decide) se vinculan a la obra, que ve solo
comercial; los operativos (capataz, quien recibe) a la etapa, que ve quien la ejecuta. La misma persona
puede tener los dos vínculos: logística ve su teléfono y el vínculo con la etapa, no su rol en la obra.
Se propuso antes una marca "reservado a mi equipo" por vínculo; sobró cuando la obra quedó solo para
comercial.

**Ver la persona se deriva del vínculo, no se comparte.** Contesta desde el día uno el diagnóstico de
`BACKLOG.md` (un usuario con acceso otorgado no alcanzaba el contacto): quien ve el registro ve el
vínculo, y quien ve un vínculo ve la persona. Una sola regla, en `contactos_puede_ver_persona_de`.

**La agenda es de su dueño; lo vinculado se ve en contexto (2026-09-25).** La pestaña Personas
muestra solo las propias. Una persona vinculada a una obra que veo la veo ahí, con su rol y su
teléfono, y su ficha me muestra solo ese vínculo. Si además trabajo ese registro, puedo cerrar el
vínculo o cambiarle el rol (*Ver no es trabajar*, abajo). Lo que no puedo es llevarla a otro registro: **vincular una persona es solo de su
dueño y del admin** (y del aprobador, en "es la misma"). Si no, quien recibe una obra transferida podía sumar el referente del anterior a sus
propias obras y quedárselo. Las empresas no entran en esta regla: son del equipo.

**Ver no es trabajar: en contexto escribe quien trabaja el registro (2026-09-26).** Juan (Norte) es
responsable de Torre Belgrano y suma a Pedro (Sur); Laura, jefa de Sur, la ve y nada más
(`decisiones/obras.md`). Con "quien ve el registro", Laura cerraba el vínculo de Marta Gómez como
arquitecta, le sacaba el rol decisor, vinculaba a Belgrano una persona suya o le cambiaba el teléfono
a Marta. Contactos le pregunta al módulo del ente si quien escribe trabaja el registro
(`decisiones/global/entes.md` → *Ver un registro no es trabajarlo*); en Obras: responsable,
participantes, el jefe de `obra.equipo_id` y `obras_administrar`.
- Vincular: el dueño de la persona (el equipo, si es empresa), y que trabaje el registro.
- Cerrar, cambiar el rol o desactivar un vínculo: quien trabaja el registro.
- Editar una persona o una empresa: su dueño (el equipo, si es empresa), el admin, o quien trabaja un
  registro al que está vinculada.
- Los vínculos guardados de una congelada, también el de "es la misma", se crean si quien la cargó
  trabaja el registro en ese momento.

Laura sigue viendo a Marta con su rol, y el teléfono con "Ver contacto". Descartado: que Obras la frene
con su trigger sobre `contactos_vinculos` (no alcanza a la edición de Marta, y el módulo que se olvide
queda abierto) y aflojar Obras ("solo ve, salvo los contactos").

**La persona se transfiere, y la agenda sigue a las obras (2026-09-25).** El dueño es `responsable_id`,
no `creado_por`. "Transferir persona": el dueño y el admin. En la baja, la agenda pasa al jefe del
equipo, como las obras (`decisiones/obras.md` → *Bajas y cambios de equipo*); así el jefe la reparte
con "transferir". En un cambio de equipo, el admin elige en ese momento si pasa al jefe (por defecto) o
se queda con la persona. Sin jefe, o si era independiente, queda con dueño inactivo y la transfiere el admin.
Se encuentran como en Obras (2026-09-26): filtro "huérfanas" (dueño inactivo) en Personas, con
`contactos_administrar`, y campanita "personas huérfanas" a quienes la tienen, una por hecho, con la
cantidad. Una empresa sin equipo cuya cargadora queda inactiva no la ve nadie: entra en el mismo filtro,
en Empresas, y el admin le asigna un equipo (`equipo_id`).
Huérfana, como en Obras (2026-09-28): dueño sin `contactos_ver` (inactivo o sin la vista); perder la
vista también avisa. El jefe que recibe la agenda es el delegador del equipo (`sql/133`).
Mecánica, al escribir el SQL: `asignar_equipo` suma el parámetro. Precedente: `designar_delegador`
ya mueve `tareas_equipo` (`sql/112`).

**Desactivar no toca los vínculos (2026-09-26).** Desactiva una persona su dueño o el admin (como
transferir); una empresa, el jefe de su equipo o el admin (es del equipo, no de quien la cargó). Sus
vínculos quedan: en cada obra sigue con su rol, marcada "inactiva", porque es historia de la obra
(quién fue la arquitecta). Solo se frena vincularla de nuevo. Si estaba cargada por error, cada vínculo
se desactiva aparte. Descartado: bloquear con vínculos abiertos (obliga a cerrarlos uno por uno).

**Fusionar: el admin elige cuál queda, y esa conserva su dueño (2026-09-26).** Por defecto, la de más
vínculos; el dueño no cambia (una persona habla con un solo vendedor, como en "es la misma"). Los
vínculos de la que se va pasan a la que queda; si las dos tenían uno abierto en el mismo registro, uno
solo con los roles sumados (los cerrados se mueven tal cual). Teléfono y email, campo por campo, los elige el admin; las razones sociales de una empresa
se suman. Dos empresas de equipos distintos: la que queda pasa a estar compartida con el equipo de la
otra, así nadie la pierde (2026-09-26). La que se va se desactiva con `fusionada_en`, y su historial (ediciones, accesos) queda donde
estaba. Campanita al dueño de la que se va: "Marta Gómez se fusionó con la de Juan"; sigue viéndola en
contexto en sus obras.

**Una persona o una empresa la corrige quien trabaja con ella, y cada cambio queda registrado
(2026-09-25).** El contacto es uno solo y lo usan varias obras: que lo corrija el primero que se entera
(quien recibió la obra transferida y sabe el teléfono nuevo). Quien solo la ve en contexto, no
(2026-09-26, *Ver no es trabajar*). Descartado: solo el dueño, que dejaba el dato viejo hasta
que otro le avisara. `contactos_ediciones` (ente, registro_id, campo, anterior, nuevo, usuario,
fecha): la escribe un trigger, nadie inserta ni edita, y la ve quien ve el registro. Es el mismo patrón
que `tareas_ediciones`. Editar no es vincular: trabajar la obra de Marta deja corregirla, no llevarla
a otra obra.

**Ver teléfono y email de una persona queda registrado, y se hace con un botón (2026-09-25).** La
agenda es de la empresa: el registro detecta a quien se lleva los contactos (200 teléfonos la semana
antes de irse). Lo pide `GUIDE_ENTES.md` §2.1. Teléfono y email quedan fuera del `GRANT SELECT` y se
leen solo por una función DEFINER que escribe en `contactos_accesos` (persona, usuario, fecha). En
pantalla: "Ver contacto" en la ficha y en la obra, con link para llamar o escribir. Es botón y no dato a
la vista porque registrar al abrir la obra anotaría todos sus contactos en cada visita, y el registro
perdería sentido. El historial de esos dos campos en `contactos_ediciones` pasa por el mismo camino.
Solo personas: el teléfono de una empresa no es sensible.

**El registro lo mira una vista propia, Auditoría (`contactos_auditoria`).** Ver quién miró es
distinto de ver la agenda y se da por separado; el auditor no necesita ver la agenda de nadie.
Función DEFINER con guard y tope de filas; devuelve nombres y fechas, nunca el dato: la pantalla que
vigila el acceso no puede ser otra puerta al contacto. Mismo criterio que `master`.

**Las empresas son del equipo que las carga (2026-09-25).** El usuario las prefirió privadas, pero
que comercial las vea entero: así un vendedor no carga dos veces la misma constructora. Se resuelve con
el `equipo_id` de quien la carga, guardado en ese momento. La ven los miembros de ese equipo, quien
ve un vínculo suyo y el admin. Vale igual para cualquier equipo, sin excepción por nombre. Las
personas no: son de su dueño (un vendedor no ve los referentes de otro).

**Una empresa se comparte con otro equipo, a pedido (2026-09-26).** Norte tiene "Constructora Caputo"
y Pedro (Sur) la necesita para Casa Núñez: el aviso a ciegas le dice "Constructora Caputo, de Juan Pérez
(Norte)", y en vez de crearla se la pide a Norte con un pedido de Tareas (con `tareas_pedir`; si no la
tiene, se lo pide a su jefe, como cualquier pedido). Juan acepta y desde la ficha de Caputo la comparte
con Sur, que desde ahí la ve, la vincula y la corrige como propia. Un pedido por empresa, no por obra.
- Comparte y deja de compartir cualquiera del equipo dueño, o el admin. Sigue siendo de Norte: la
  desactiva su jefe.
- Dejar de compartir no toca los vínculos que Sur ya creó (historia de la obra, como desactivar): Sur
  solo deja de poder vincularla de nuevo.
- Sin campanita propia: la respuesta al pedido ya avisa.
- **Congelada no se comparte, y sin evento (2026-09-28).** Como no se vincula: espera aprobación.
  Tampoco emite `compartido`: ese evento es por usuario (GUIDE_ENTES) y esto es por equipo; nadie lo
  escucha. Compartir la trae de vuelta: fila nueva, como un vínculo. `sql/140`.

Pedido del usuario. Descartado: que Norte vincule Caputo a Casa Núñez desde el pedido (un pedido por
obra, vincula a una obra que no ve, y Contactos tendría que leer los pasos de Tareas); no congelar una
empresa parecida a la de otro equipo (el usuario prefirió pedirla); empresas comunes a todos los equipos.

**La empresa se identifica por su nombre, no por el CUIT (2026-09-25).** El usuario: el nombre queda y
la razón social cambia, y con ella el CUIT (por ejemplo, un fideicomiso por edificio). Razón social y
CUIT van como una lista de la empresa, sin unique, y a cuál se le cotiza lo elige el presupuesto cuando
exista. El nombre tampoco es unique: los duplicados los ataja el congelado (abajo).

**Altas parecidas: congeladas hasta que las aprueba `contactos_aprobar` (2026-09-25).** Igual que
las obras (`decisiones/obras.md` → *Altas parecidas*). Pedido del usuario, sobre el sistema de
`master`.

- **Se compara contra todo:** personas contra todas las agendas (nombre, y teléfono y email
  normalizados); empresas contra todas las empresas, de cualquier equipo (nombre). Antes de guardar,
  aviso a ciegas: nombre y dueño (de una empresa, también su equipo), nada más. Editar un dato comparado que pasa a coincidir también
  congela (`decisiones/obras.md` → *Editar también congela*).
- **Congelada:** la ve solo quien la cargó, y la puede editar. No se vincula (ni a una obra ni a una
  empresa) y no se transfiere. El bloqueo, con triggers en la base.
- **Aprueba `contactos_aprobar`, no el jefe:** una función que asigna el admin, no delegable. En
  "Por aprobar" ve el alta completa y, de cada parecida, nombre, dueño y qué dato coincidió ("mismo
  teléfono"), sin mostrarlo. Teléfono y email de la congelada, con el mismo "Ver contacto", que queda
  en `contactos_accesos`: el aprobador no es excepción (2026-09-26). Las altas de quien tiene la
  función no se congelan.
- **Tres salidas:** aprobar · rechazar con motivo (se desactiva, no se fusiona) · "es la misma".
  Una persona se aprueba solo si es homónima: una persona habla con un solo vendedor (o con su equipo
  comercial si no está), así que no se duplica en otra agenda. "Es la misma" rechaza la nueva y le deja
  al aprobador, si quiere, vincular la existente a la obra y el rol para los que se cargó (la congelada
  los guarda: *Vincular*, abajo). La persona sigue siendo de su dueño; quien la cargó la ve
  en contexto. Queda abierto, no es el camino por defecto. Una empresa parecida
  a la de otro equipo normalmente se aprueba: rechazarla deja a ese equipo sin empresa, porque no ve la
  del otro. El camino esperado es no crearla y pedírsela a ese equipo (*Una empresa se comparte*); por
  eso el aviso a ciegas de una empresa dice también el equipo.
- **Avisos:** "alta por aprobar" a quienes tienen `contactos_aprobar`; la decisión, a quien la cargó.
- **El aprobador ve la persona congelada (2026-09-28).** Para "Ver contacto" sobre ella, que registra:
  `contactos_puede_ver_persona_de` suma `contactos_aprobar` mientras está congelada. "Es la misma", solo
  para un alta; guardar el vínculo solo en el paso en que nace; el aviso, al dueño: como Obras
  (`decisiones/obras.md` → *Altas parecidas*).

## Vincular: buscar o crear en el mismo panel (2026-09-26)

Pedido del usuario: que vincular sea rápido, y que si el contacto no está se cree desde ahí.

**El buscador muestra solo lo que podés vincular: tus personas y las empresas de tu equipo** (y las
compartidas con él). Pedro
ve a la arquitecta de Juan en Torre Belgrano y la busca para Casa Núñez: no aparece, la crea, el aviso a
ciegas dice "Marta Gómez, de Juan Pérez", queda congelada con la obra y el rol, y el aprobador resuelve
con "es la misma". Descartado: mostrarla deshabilitada ("pedile a Juan"), que lo deja esperando al dueño
y hace que la lista deje de ser "lo que podés elegir". No sirve `buscar_registros`, que devuelve lo que
se ve: el filtro es la misma regla que decide quién vincula.

**Si no está, se crea desde ahí y se vincula en el mismo paso.** Al pie de la lista, siempre las dos:
"+ Crear «texto» como persona" y "como empresa" (atar el tipo al rol era otra regla que mantener). El
mismo panel, sin modal encima, pasa a un formulario corto con el texto como nombre; solo el nombre es
obligatorio. Una función crea y vincula, todo o nada: si el vínculo falla (obra congelada), el contacto
tampoco se crea, y no queda "se creó pero no se vinculó".

**Las parecidas, en el panel y antes de guardar.** Si es tuya, se muestra entera: "Ya la tenés: Marta
Gómez · 11-5555-…" con [Vincular esa] y [Es otra, crear igual]. Si es de otro, el aviso a ciegas con
[Crear igual] (queda por aprobar) y [Cancelar].

**Una congelada guarda los vínculos con los que se creó, y se crean al aprobarse.** Rol en un registro,
y empresa con cargo (abajo). Sin esto, quien la cargó tenía que volver a vincularla, y el paso de Tareas
"vincular arquitecto" quedaba abierto hasta que se acordara. Cada vínculo guardado se crea cuando sus dos
puntas dejan de estar congeladas; si para entonces quien la cargó ya no trabaja el registro, no se crea
y "alta resuelta" lo dice. Rechazar y "es la misma", como arriba. Si la congelada es la obra y resulta
"es la misma", el vínculo pasa a la existente (`decisiones/obras.md` → *Altas parecidas*).

**Los vínculos guardados, en una tabla aparte: `contactos_vinculos_guardados` (2026-09-28).** Persona o
empresa, y `ente` + `registro_id` + `roles` o `empresa_id` + `cargo`, con `cargado_por`. Sin GRANT: la
escriben las funciones de alta y de aprobación. Aprobar crea el vínculo real y desactiva la fila;
rechazar la desactiva; "es la misma" sobre una obra le cambia el `registro_id`. Descartado: un flag en
`contactos_vinculos`, que tocaba el unique parcial, los eventos, la policy y cada pantalla que lee vínculos.
- **Se crea a nombre de quien cargó.** La aprobación inserta con `creado_por = cargado_por`, y
  `contactos_vinculos_validar` valida contra `NEW.creado_por` en vez de `auth.uid()`: el cliente no puede
  escribirlo (fuera del GRANT de INSERT), así que es confiable. Entra `trabaja_registro_de(ente, id,
  usuario)`. Si Pedro ya no trabaja Casa Núñez, el vínculo no se crea y "alta resuelta" lo dice.
- **El guardado autoriza el vínculo, también en "es la misma".** Pedro creó a Marta para Casa Núñez y el
  aprobador la resuelve como la Marta de Juan: "es la misma" le cambia el `persona_id` al guardado, y
  `contactos_vinculos_validar` acepta si `NEW.creado_por` es el dueño **o** hay un guardado activo con esa
  persona, ese registro y `cargado_por = NEW.creado_por` (lo escriben solo funciones: la fila prueba que
  alguien lo autorizó). Sigue exigiendo que Pedro trabaje el registro; Marta sigue siendo de Juan.
  Descartado: que `contactos_aprobar` vincule cualquier persona (con un INSERT común, el aprobador se
  llevaba a Marta a sus obras).

**La empresa de la persona, en el mismo formulario.** Campo opcional con el mismo buscador: las empresas
que ves (lo que pide persona ↔ empresa), primero las vinculadas al registro, así el capataz de la
constructora de la obra se elige sin escribir. Si no está, se crea con solo el nombre y todo se guarda
junto con "Crear y vincular": empresa, persona, relación con cargo opcional y vínculo. Un solo nivel:
desde la empresa nueva no se crea nada. Descartado: solo elegir existentes, que obligaba a volver a la
ficha de la persona. Razón social y CUIT, después, desde la ficha de la empresa.

**Dónde se busca y dónde se crea.** Un solo buscador, escrito en Contactos; la ficha de la obra y el alta
lo componen desde `app/` (`GUIDE_ENTES.md` §2.7).

| Desde | Busca | Crea si no está |
|---|---|---|
| Obra → vincular contacto | tus personas, empresas de tu equipo o compartidas con él | persona o empresa, con su empresa |
| Nueva obra, origen referente → "¿Quién?" | ídem | persona o empresa, sin el campo empresa (ya es el nivel anidado) — `decisiones/obras.md` |
| Persona → sumar empresa | empresas que ves | empresa, solo el nombre |
| Empresa → sumar persona | tus personas | persona, con cargo en vez de rol |
| Persona o empresa → vincular a una obra | obras que trabajás, no congeladas | no: una obra pide dirección, tipo y sus parecidas |
| Obra → sumar participante | usuarios activos con `obras_ver` | no: select simple, como `AsignadoSelect` |

## Los roles de un vínculo los declara el ente, en `entes.roles` (2026-09-26)

**`entes` suma `roles text[]`, como `datos`: cada módulo lo llena al registrar su ente, y un trigger en
`contactos_vinculos` rechaza un rol que no esté en la lista de su ente.** Los labels van en `ENTES`
(`lib/entes.ts`), y Tareas saca de ahí las opciones de "vincular {rol}". El trigger valida al insertar o
al cambiar `roles`: sacar un rol de la lista deja los vínculos viejos como historia.

Descartado: un enum (una columna no cambia de enum según la fila; uno global haría que Contactos conozca
los roles de cada módulo) y una tabla sembrada como `submodulo_reglas` (tabla, RLS y seed para un
código sin más datos).

Archivos: `sql/` (Contactos), `db_schema/core.md`, `GUIDE_ENTES.md` §2.2.

## El contacto en dos columnas, y el emisor lee el ente de la fila (2026-09-26)

**`contactos_vinculos` guarda el contacto en `persona_id` y `empresa_id` (`CHECK num_nonnulls = 1`), y
emite con dos triggers `WHEN`, uno por columna. `emitir_eventos_relacion` toma un ente de la columna
del mismo nombre si la fila la tiene (`'ente'`), y si no, el texto tal cual.** Dos FK reales en vez de
un par sin FK; el registro vinculado varía por fila (obra hoy, etapa y unidad después).

Descartado: un trigger propio de Contactos (copiaba la diferencia de roles del emisor).

Archivos: `sql/` (Contactos), `sql/tests/entes_eventos.sql`, `db_schema/core.md`, `GUIDE_ENTES.md` §2.6.

## Las columnas de persona y empresa (2026-09-26)

**Persona: `nombre` (un solo campo), `telefono`, `email`, `notas`. Empresa: `nombre`, `telefono`,
`email`, `web`, `notas`.** Un solo nombre porque el aviso a ciegas y los chips dicen "Marta Gómez", y
comparar homónimos es comparar ese texto. El teléfono se guarda solo con dígitos, como el de
`usuarios`, así queda comparable para las parecidas. Descartado, con lo de `master` a la vista:
`apellido` y `whatsapp` aparte, y dirección y localidad de la empresa (nada las usa todavía).
Archivos: `sql/127`, `db_schema/contactos.md`.

**"Ver contacto" pregunta "lo ve" por usuario explícito (2026-09-26).** Es DEFINER (teléfono y email
están fuera del GRANT), y desde ahí `etiqueta_registro` respondería por el dueño de la función. Por eso
la visibilidad de persona y empresa se escribe una vez, en `contactos_puede_ver_*_de`, y el vínculo
cuenta si `puede_abrir_registro(ente, id, usuario)` —la genérica por usuario, con su rama en cada
módulo— dice que se ve el registro. Las policies usan la misma función con `auth.uid()`.
Archivos: `sql/125`, `sql/127`.

## Ficha del módulo

Aprobada el 2026-09-25, junto con la de Obras.

```
Módulo: contactos
Objetivo: las personas y empresas con las que trabaja la empresa, en un solo lugar, vinculadas con su
          rol y su período a obras (después a etapas y unidades), y visibles solo para quien trabaja
          el registro al que están vinculadas.
Personas
├── Vendedor        — ve su agenda (las personas de las que es dueño), las empresas de su equipo o
│                     compartidas con él y, en contexto, los contactos vinculados a las obras que ve
│                   · crea personas y empresas; vincula las suyas a lo que trabaja; en una obra que
│                     trabaja, cierra vínculos, les cambia el rol y corrige sus contactos; transfiere
│                     sus personas
│                   · no ve la agenda de otros vendedores ni vínculos de obras que no ve; no
│                     lleva a otro registro una persona que ve solo en contexto; en una obra que solo
│                     ve, no toca nada
├── Jefe comercial  — lo del vendedor, sobre las obras de su equipo · recibe la agenda de quien se
│                     va y la reparte con "transferir" · —
├── Aprobador de altas — quien elija el admin (contactos_aprobar) · ve las altas congeladas y lo
│                     parecido (nombre, dueño, qué dato coincidió) · aprueba, rechaza con motivo,
│                     "es la misma" · teléfono y email de la congelada, con "Ver contacto" (registra)
│                   · no ve agendas ajenas ni datos de contacto de la parecida, salvo por otro permiso
├── Auditor         — quien elija el admin (contactos_auditoria) · ve quién miró teléfono o email
│                     de qué persona y cuándo · — · no ve el dato ni las agendas
├── Admin           — ve todo · hace todo, fusiona duplicados, reactiva · —
├── Equipos operativos y post-venta — todavía no: lo usan cuando existan Presupuestos y Post-venta,
│                     sobre las etapas y unidades que vean · no ven contactos comerciales
└── Cliente         — NO usa el módulo
Entes
├── persona — dueño responsable_id (transferible; en la baja pasa al jefe) · sin estado
│             · datos {nombre} · ruta /contactos/personas/{id} · submódulo contactos_ver
│             · teléfono y email, fuera del SELECT: botón "Ver contacto" → función que registra
│               el acceso en contactos_accesos (GUIDE_ENTES §2.1)
│             · la ven: su dueño, quien ve algún vínculo suyo (solo ese vínculo),
│               contactos_administrar · la vincula a un registro que trabaja: su dueño,
│               contactos_administrar · la editan: su dueño, contactos_administrar, quien trabaja
│               un registro al que está vinculada
│             · congelada (flag, no estado) si el alta se parece a otra: la ve solo quien la cargó,
│               no se vincula ni se transfiere; el alta cuenta al aprobarse; guarda los vínculos
│               con los que se creó, que se crean al aprobarse
└── empresa — dueño creado_por · equipo_id de quien la carga, guardado en el momento · sin estado
              · datos {nombre} · ruta /contactos/empresas/{id} · submódulo contactos_ver
              · se identifica por el nombre, sin unique; razón social y CUIT, en su lista
              · la ven: los miembros de su equipo (o solo quien la cargó, si no tiene equipo) y de
                los equipos con los que se compartió, quien ve algún vínculo suyo,
                contactos_administrar · la editan: su equipo (o quien la cargó), los equipos con
                los que se compartió, contactos_administrar, quien trabaja un registro al que está
                vinculada
              · congelada como la persona
No son entes
├── razón social — contactos_empresa_razones (empresa, razon_social, cuit, activo), sin unique;
│                  se ve con la empresa
├── compartida   — contactos_empresa_equipos (empresa, equipo, activo): el equipo que la ve y la
│                  vincula como propia; la escribe el equipo dueño o el admin
├── ediciones    — contactos_ediciones: log de cambios de persona y empresa (campo, anterior, nuevo,
│                  quién, cuándo); lo escribe un trigger; se ve con el registro (teléfono y email,
│                  por la función que registra)
└── accesos      — contactos_accesos: quién vio teléfono o email de qué persona y cuándo; lo lee
                   solo la vista Auditoría
Relaciones
├── persona ↔ empresa        — cargo · desde · hasta          (contactos_persona_empresa)
│                              · la crea el dueño de la persona, con una empresa que ve; se ve con la
│                                persona; la empresa aparece solo si se la ve (sin regla propia)
└── persona | empresa → ente — roles[] · desde · hasta        (contactos_vinculos: ente, registro_id)
                               · uno abierto por par (unique WHERE activo AND hasta IS NULL,
                                 GUIDE_ENTES §2.6); volver es una fila nueva — igual persona ↔ empresa
                               · se ve si se ve el registro
                               · lo crea, sobre un registro que trabaja, el dueño de la persona o el
                                 equipo de la empresa; lo cierra o le cambia el rol quien trabaja el
                                 registro (un referente con comisión: ver decisiones/obras.md)
                               · "trabaja" lo contesta el módulo del ente, no "lo ve"
                                 (Ver no es trabajar)
                               · los roles válidos los declara el módulo del ente
                               · el panel de vincular, compuesto en cada ficha, abre solo con
                                 ?vincular={rol} (link de acción de Tareas); se escribe una vez
                               · busca solo lo que se puede vincular; si no está, crea y vincula
                                 en un paso (*Vincular: buscar o crear*)
Acciones
├── persona: crear (congelada si se parece) · editar (dueño, admin, quien trabaja un registro
│            vinculado; queda en contactos_ediciones)
│            · ver teléfono y email (registra) · transferir (dueño, admin) · desactivar (dueño, admin;
│            sus vínculos quedan, "inactiva")
│            · reactivar y fusionar (admin)
├── empresa: crear (congelada si se parece) · editar (su equipo, admin, quien trabaja un registro
│            vinculado; queda en contactos_ediciones)
│            · sumar razón social · compartir con un equipo y dejar de compartir (su equipo, admin;
│            los vínculos quedan) · desactivar (jefe del equipo, admin) · reactivar, fusionar y
│            asignar equipo (admin)
├── alta congelada: aprobar (persona: solo si es homónima; crea los vínculos guardados) · rechazar (motivo) · "es la misma"
│                  (rechaza; opcional, vincula la existente a la obra y rol de la congelada)
│                  — contactos_aprobar
└── vínculo: vincular (la persona, su dueño o el aprobador en "es la misma"; la empresa, su equipo o
             uno con el que se compartió;
             sobre un registro que trabaja) · cerrar (hasta) · cambiar el rol · desactivar (cargado
             por error) — lo último, quien trabaja el registro
Eventos que emite
├── persona: alta (al aprobarse, si entró congelada) · baja · reactivacion · transferencia ({de, a})
├── empresa: alta (ídem) · baja · reactivacion
├── vínculo: relacion_alta / relacion_baja del lado del registro (la obra), uno por rol
└── campanita (nunca al que hizo la acción):
    ├── contacto transferido → el nuevo dueño
    ├── agenda recibida      → el jefe, por baja o cambio de equipo; una por hecho, con la cantidad
    ├── persona fusionada    → el dueño de la que se va
    ├── personas huérfanas   → quienes tienen contactos_administrar, cuando no hay jefe que las
    │                          reciba; una por hecho, con la cantidad
    ├── alta por aprobar     → quienes tienen contactos_aprobar
    └── alta resuelta        → quien la cargó: aprobada, rechazada (con motivo) o "es la misma"
Eventos que consume
└── ninguno
```

```
Módulo: Contactos
├── Contactos (vista, contactos_ver)           — vendedor, jefe comercial, admin
│   │   pestañas Personas · Empresas · filtro huérfanas (contactos_administrar): dueño sin
│   │   contactos_ver ("De {quien}" desde el aviso); empresa activa sin equipo con cargadora sin
│   │   contactos_ver — el admin le asigna un equipo desde la ficha
│   ├── contactos_aprobar (funcion)            — aprobador de altas: lista "Por aprobar"
│   └── contactos_administrar (funcion)        — admin: ve todo, fusiona, reactiva
└── Auditoría (vista, contactos_auditoria)     — auditor, admin: quién miró qué contacto

Delegables
├── sí — contactos_ver
└── no — contactos_aprobar · contactos_administrar · contactos_auditoria
Reglas entre permisos
└── ninguna propia (obras_ver requiere contactos_ver: la declara Obras)
```

## Pendiente

- ~~Vínculos guardados de una congelada, en el SQL~~ y ~~`trabaja_registro_de`~~ — cerrados en
  *Los vínculos guardados, en una tabla aparte* (arriba).
