# Decisiones — módulo contactos

> **Estado: ficha aprobada (2026-09-25), armada con el usuario junto con la de Obras
> (`decisiones/obras.md`) y revisada punto por punto; sin SQL todavía.** *Pendiente*, al pie, tiene
> solo lo que se decide al escribir el SQL.

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
teléfono, y su ficha me muestra solo ese vínculo. Dentro de ese registro puedo cerrar el vínculo o
cambiarle el rol. Lo que no puedo es llevarla a otro registro: **vincular una persona es solo de su
dueño y del admin** (y del aprobador, en "es la misma"). Si no, quien recibe una obra transferida podía sumar el referente del anterior a sus
propias obras y quedárselo. Las empresas no entran en esta regla: son del equipo.

**La persona se transfiere, y la agenda sigue a las obras (2026-09-25).** El dueño es `responsable_id`,
no `creado_por`. "Transferir persona": el dueño y el admin. En la baja, la agenda pasa al jefe del
equipo, como las obras (`decisiones/obras.md` → *Bajas y cambios de equipo*); así el jefe la reparte
con "transferir". En un cambio de equipo, el admin elige en ese momento si pasa al jefe (por defecto) o
se queda con la persona. Sin jefe, o si era independiente, queda con dueño inactivo y la transfiere el admin.
Se encuentran como en Obras (2026-09-26): filtro "huérfanas" (dueño inactivo) en Personas, con
`contactos_administrar`, y campanita "personas huérfanas" a quienes la tienen, una por hecho, con la
cantidad. Una empresa sin equipo cuya cargadora queda inactiva no la ve nadie: entra en el mismo filtro,
en Empresas, y el admin le asigna un equipo (`equipo_id`).
Mecánica, al escribir el SQL: `asignar_equipo` suma el parámetro. Precedente: `designar_delegador`
ya mueve `tareas_equipo` (`sql/112`).

**Una persona o una empresa la edita quien la ve, y cada cambio queda registrado (2026-09-25).**
El contacto es uno solo y lo usan varias obras: que lo corrija el primero que se entera (quien recibió
la obra transferida y sabe el teléfono nuevo). Descartado: solo el dueño, que dejaba el dato viejo hasta
que otro le avisara. `contactos_ediciones` (ente, registro_id, campo, anterior, nuevo, usuario,
fecha): la escribe un trigger, nadie inserta ni edita, y la ve quien ve el registro. Es el mismo patrón
que `tareas_ediciones`. Editar no es vincular: ver a Marta en contexto deja corregirla, no llevarla a
otra obra.

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

**La empresa se identifica por su nombre, no por el CUIT (2026-09-25).** El usuario: el nombre queda y
la razón social cambia, y con ella el CUIT (por ejemplo, un fideicomiso por edificio). Razón social y
CUIT van como una lista de la empresa, sin unique, y a cuál se le cotiza lo elige el presupuesto cuando
exista. El nombre tampoco es unique: los duplicados los ataja el congelado (abajo).

**Altas parecidas: congeladas hasta que las aprueba `contactos_aprobar` (2026-09-25).** Igual que
las obras (`decisiones/obras.md` → *Altas parecidas*). Pedido del usuario, sobre el sistema de
`master`.

- **Se compara contra todo:** personas contra todas las agendas (nombre, y teléfono y email
  normalizados); empresas contra todas las empresas, de cualquier equipo (nombre). Antes de guardar,
  aviso a ciegas: nombre y dueño, nada más. Editar un dato comparado que pasa a coincidir también
  congela (`decisiones/obras.md` → *Editar también congela*).
- **Congelada:** la ve solo quien la cargó, y la puede editar. No se vincula (ni a una obra ni a una
  empresa) y no se transfiere. El bloqueo, con triggers en la base.
- **Aprueba `contactos_aprobar`, no el jefe:** una función que asigna el admin, no delegable. En
  "Por aprobar" ve el alta completa y, de cada parecida, nombre, dueño y qué dato coincidió ("mismo
  teléfono"), sin mostrarlo. Las altas de quien tiene la función no se congelan.
- **Tres salidas:** aprobar · rechazar con motivo (se desactiva, no se fusiona) · "es la misma".
  Una persona se aprueba solo si es homónima: una persona habla con un solo vendedor (o con su equipo
  comercial si no está), así que no se duplica en otra agenda. "Es la misma" rechaza la nueva y le deja
  al aprobador, si quiere, vincular la existente a la obra y el rol para los que se cargó (la congelada
  los guarda, salen de `?vincular={rol}`). La persona sigue siendo de su dueño; quien la cargó la ve
  en contexto. Queda abierto, no es el camino por defecto. Una empresa parecida
  a la de otro equipo normalmente se aprueba: rechazarla deja a ese equipo sin empresa, porque no ve la
  del otro.
- **Avisos:** "alta por aprobar" a quienes tienen `contactos_aprobar`; la decisión, a quien la cargó.

## Ficha del módulo

Aprobada el 2026-09-25, junto con la de Obras.

```
Módulo: contactos
Objetivo: las personas y empresas con las que trabaja la empresa, en un solo lugar, vinculadas con su
          rol y su período a obras (después a etapas y unidades), y visibles solo para quien trabaja
          el registro al que están vinculadas.
Personas
├── Vendedor        — ve su agenda (las personas de las que es dueño), las empresas de su equipo y,
│                     en contexto, los contactos vinculados a las obras que ve
│                   · crea personas y empresas; vincula las suyas a lo que ve; en una obra que ve,
│                     cierra vínculos y les cambia el rol; transfiere sus personas
│                   · no ve la agenda de otros vendedores ni vínculos de obras que no ve; no
│                     lleva a otro registro una persona que ve solo en contexto
├── Jefe comercial  — lo del vendedor, sobre las obras de su equipo · recibe la agenda de quien se
│                     va y la reparte con "transferir" · —
├── Aprobador de altas — quien elija el admin (contactos_aprobar) · ve las altas congeladas y lo
│                     parecido (nombre, dueño, qué dato coincidió) · aprueba, rechaza con motivo
│                   · no ve agendas ajenas ni datos de contacto, salvo por otro permiso
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
│               contactos_administrar · la vincula a un registro: su dueño, contactos_administrar
│             · congelada (flag, no estado) si el alta se parece a otra: la ve solo quien la cargó,
│               no se vincula ni se transfiere; el alta cuenta al aprobarse
└── empresa — dueño creado_por · equipo_id de quien la carga, guardado en el momento · sin estado
              · datos {nombre} · ruta /contactos/empresas/{id} · submódulo contactos_ver
              · se identifica por el nombre, sin unique; razón social y CUIT, en su lista
              · la ven: los miembros de su equipo (o solo quien la cargó, si no tiene equipo), quien
                ve algún vínculo suyo, contactos_administrar
              · congelada como la persona
No son entes
├── razón social — contactos_empresa_razones (empresa, razon_social, cuit, activo), sin unique;
│                  se ve con la empresa
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
                               · se ve si se ve el registro
                               · lo crea, sobre un registro que ve, el dueño de la persona o el
                                 equipo de la empresa; lo cierra o le cambia el rol quien ve el registro (un referente con comisión: ver
                                 decisiones/obras.md)
                               · los roles válidos los declara el módulo del ente
                               · el panel de vincular, compuesto en cada ficha, abre solo con
                                 ?vincular={rol} (link de acción de Tareas); se escribe una vez
Acciones
├── persona: crear (congelada si se parece) · editar (quien la ve; queda en contactos_ediciones)
│            · ver teléfono y email (registra) · transferir (dueño, admin) · desactivar
│            · reactivar y fusionar (admin)
├── empresa: crear (congelada si se parece) · editar (quien la ve; queda en contactos_ediciones)
│            · sumar razón social · desactivar · reactivar, fusionar y asignar equipo (admin)
├── alta congelada: aprobar (persona: solo si es homónima) · rechazar (motivo) · "es la misma"
│                  (rechaza; opcional, vincula la existente a la obra y rol de la congelada)
│                  — contactos_aprobar
└── vínculo: vincular (la persona, su dueño o el aprobador en "es la misma"; la empresa, su equipo) · cerrar (hasta) · cambiar el
             rol · desactivar (cargado por error) — lo último, quien ve el registro
Eventos que emite
├── persona: alta (al aprobarse, si entró congelada) · baja · reactivacion · transferencia ({de, a})
├── empresa: alta (ídem) · baja · reactivacion
├── vínculo: relacion_alta / relacion_baja del lado del registro (la obra), uno por rol
└── campanita (nunca al que hizo la acción):
    ├── contacto transferido → el nuevo dueño
    ├── agenda recibida      → el jefe, por baja o cambio de equipo; una por hecho, con la cantidad
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
│   │   pestañas Personas · Empresas · filtro huérfanas (contactos_administrar): dueño inactivo;
│   │   empresa sin equipo con cargadora inactiva
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

- **Roles por ente, en el SQL.** Un enum validado según el ente, o filas que siembra cada módulo en su
  migración, como `submodulo_reglas`.
- **El emisor de relación, en el SQL.** `emitir_eventos_relacion` recibe el ente fijo por argumento;
  acá el ente sale de la columna `ente` de cada fila.
