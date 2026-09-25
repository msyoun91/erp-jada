# Decisiones — módulo obras

> **Estado: ficha aprobada (2026-09-25), después de revisarla punto por punto con el usuario; sin
> SQL todavía.** Rediseño desde cero: el usuario pidió no partir de lo que había en `master`. Los
> contactos son de otro módulo: `decisiones/contactos.md`. Orden de construcción en `BACKLOG.md`.

## La obra es del equipo comercial (2026-09-25)

**Obras sigue la obra del lado comercial; los demás equipos trabajan la etapa, no la obra.**
Administración, producción y logística actúan según el estado de cada presupuesto (módulo futuro), y
post-venta tiene su módulo aparte. Así la obra y sus contactos comerciales no salen de comercial, sin
marcas por contacto. Se había propuesto antes que logística y colocación vieran la obra; el usuario lo
cambió al definir que el módulo es de comercial.

**La visibilidad copia la de Tareas.** Allá, un hilo lo ve quien participa, el delegador de un
equipo participante y el admin. Acá, una obra la ven el responsable, sus participantes, el jefe comercial
sobre las del equipo, y `obras_todas`. El equipo se guarda en el momento (`obra.equipo_id` al crear
y al transferir; el de cada participante al sumarlo), como `hilo.equipo_id`. Compartir una obra es sumar
un participante: no hay tabla `_compartida` ni cascada, porque los contactos se ven con el registro
(`decisiones/contactos.md`).

**Un segundo vendedor entra como participante (2026-09-25).** Pedido del usuario: una obra puede
trabajarla más de un vendedor. Mismo modelo que el asignado de Tareas: la persona sumada la ve y la
trabaja sin ser la responsable.

**El jefe comercial es el delegador del equipo: `obras_equipo` requiere `usuarios_delegar`.** Igual
que `tareas_equipo`, una sola persona por equipo. No va al revés: los delegadores de logística o
producción no usan Obras.

**La comisión del referente se registra ya, y la ven solo el vendedor responsable y el jefe comercial
(2026-09-25).** Más el admin. Va sobre el vínculo con rol referente (`obras_comisiones`), así "ser
referente" sigue siendo el rol del vínculo y no se duplica; varios referentes, una comisión cada uno.
Es la única sección de la obra con regla propia: su RLS es responsable, `obras_equipo` sobre el equipo
de la obra, u `obras_administrar`, sin submódulo nuevo. El participante ve la obra, pero no la comisión.
Porcentaje o monto, uno de los dos por referente, a elección de quien la carga (CHECK: exactamente uno).

## Bajas y cambios de equipo (2026-09-25)

**La baja o el cambio de equipo de un vendedor pasa sus obras al jefe del equipo guardado en cada
obra, como los hilos de Tareas** (`decisiones/tareas/bajas.md`). Todas: abiertas, perdidas (se pueden
reabrir) y contratadas (siguen teniendo movimiento comercial). Sus participaciones se cierran. Si el que se
va es el jefe, van a su heredero. Sin jefe, o si era independiente, quedan a su nombre, huérfanas: Todas
tiene el filtro "huérfanas" y el admin transfiere desde ahí.

Por qué moverlas y no dejar que el jefe las reparta a mano, si igual las ve: las plantillas "Sobre: obra"
corren a nombre del responsable, y con uno inactivo fallan hasta que alguien reasigne. Y quien cambia de
equipo, como responsable, seguiría viendo obras comerciales desde el equipo nuevo.

**Transferir (2026-09-25).** Pueden transferir el responsable (sus obras), el jefe (las del equipo) y el
admin, y solo a alguien activo y con `obras_ver`. El `equipo_id` pasa a ser el del nuevo responsable:
si es de otro equipo comercial, deja de verla el jefe anterior y la ve el del nuevo. Participantes y
contactos no cambian; la comisión la ve el nuevo responsable. Quien transfiere deja de verla, salvo que
marque "quedarme como participante" (desmarcado por defecto).

**Desactivar es para lo cargado por error, no reemplaza a "perdida" (2026-09-25).** La perdida
queda en el embudo y se reabre; la desactivada desaparece salvo para el admin. Desactivan el
responsable, el jefe y el admin; reactiva el admin. Una contratada no se desactiva (con Presupuestos,
tampoco una con presupuestos activos). Vínculos, comisión y participantes quedan y dejan de verse por
esa obra; los hilos que la nombran siguen, sin el link. Reactivar devuelve todo.

## Altas parecidas: congeladas hasta que se aprueban (2026-09-25)

**Una obra que se parece a otra existente (nombre y dirección, contra todas las obras) entra congelada,
y la resuelve quien tenga `obras_aprobar`.** Pedido del usuario, sobre el sistema que había en `master`
(`decisiones/obras/duplicados-aprobaciones.md` de esa rama). Se evaluó solo avisar y dejar que el jefe
resolviera después, y el usuario eligió congelar. Contactos hace lo mismo con personas y empresas
(`decisiones/contactos.md`).

- **Aviso a ciegas antes de guardar:** de lo parecido que no ve, solo el nombre de la obra y el de su
  responsable. Renombrar avisa y no congela.
- **Congelada:** la ve solo quien la cargó, y la puede editar. No se vincula, no cambia de estado, no se
  transfiere y no dispara plantillas: para Tareas, el alta cuenta desde que se aprueba. El bloqueo va en
  la base, con triggers y error de clase propia, no con policies (el 42501 diría "sin permiso"). Es lo
  que en `master` recién quedó firme con `sql/098`.
- **Aprueba `obras_aprobar`, no el jefe** (decisión del usuario). Es una función que asigna el admin y no
  se delega. En "Por aprobar" ve todas las altas congeladas: la nueva completa y, de cada parecida, nombre,
  dirección y responsable, sin contactos. Las altas de quien tiene la función no se congelan.
- **Tres salidas:** aprobar · rechazar con motivo (se desactiva, no se fusiona) · "es la misma"
  (se rechaza y quien la cargó queda como participante de la existente: dos vendedores sobre el mismo
  edificio siguen trabajándolo juntos).
- **Avisos:** "alta por aprobar" a quienes tienen `obras_aprobar`; la decisión, con motivo, a quien la cargó.

## Los estados son solo comerciales (2026-09-25)

**El estado de la obra dice en qué punto está la relación comercial, no qué se está haciendo.** Lo
operativo es el estado de cada presupuesto, leído al mostrarlo. La ficha de la obra lista sus
presupuestos con su estado actual y un link ("Etapa 1 ↗ — en producción", "Etapa 2 ↗ — en
cotización"): composición en `app/` (`GUIDE_ENTES.md` §2.7), sin columnas en Obras.

**Con un presupuesto en producción y otro en cotización, la obra está `contratada`.** Contratada es
final. Cotizar la etapa 2 no la devuelve atrás: la cotización se ve en su presupuesto y sus tareas
salen de ahí. En la lista, un contador calculado al mostrar ("contratada · 1 en cotización") evita
perderla de vista.

Descartado: un estado de obra que resuma sus etapas (en ejecución, post-venta), guardado y movido por la
base. Iba y venía con cada etapa, pedía una tabla de prioridades, y las plantillas de un estado se
disparan una sola vez por obra (`decisiones/tareas/catalogo.md` → *Un disparo no se repite*): la etapa
2 no habría generado sus tareas de ejecución.

**El motivo de pérdida es de lista cerrada, con detalle libre, y queda en el historial
(2026-09-25).** Pedido del usuario, para poder medir por qué se pierden las obras. Enum
`motivo_perdida`: precio · plazo · producto (no ofrecemos lo que piden) · proveedor habitual ·
obra suspendida · sin respuesta · otro. Al lado, el detalle en texto libre ("estuvimos 10% más caros"):
opcional, obligatorio con "otro", y con un ejemplo por motivo como guía en la pantalla. La obra guarda
el motivo actual, que se limpia al reabrirla. Cada pérdida queda en el evento `estado` (`detalle` suma
motivo y texto), así que perderla dos veces no borra la primera. Descartado: guardar solo el último,
que no permitía contar.

**Datos de la obra (2026-09-25):** nombre, dirección, localidad, notas, origen, tipo de obra y fecha
estimada de compra (mes y año). Origen y tipo son listas cerradas, para poder contar, igual que el motivo
de pérdida. `origen_obra`: referente · cartel en obra · web o redes · cliente anterior · llamado · otro.
`tipo_obra`: edificio residencial · casa · oficinas o comercial · industrial · otro. Se evaluaron y se
descartaron avance de la construcción, monto potencial y unidades o m² estimados. Citables en
plantillas: `{nombre}`, `{direccion}`, `{localidad}`.

**Las tareas de cada estado de la obra son de comercial. Las de ejecución cuelgan del presupuesto.**
Cada presupuesto aprobado genera su propio hilo, que sabe de qué etapa es. Lo mismo el seguimiento
comercial al entregarse una etapa.

**Rol `decisor` (2026-09-25).** "En búsqueda" es buscar a quien decide la compra, y ningún rol lo
nombraba: sin él, "vincular a quien decide" no tenía cómo completarse solo, ni quedaba registrado quién
es.

**Dos acciones para los pasos de plantilla que se completan solos (2026-09-25; es de Tareas, en
`BACKLOG.md`).** Obras solo lleva el seguimiento, así que ofrece dos, las dos sobre eventos que ya
emite: **vincular {rol}** (se completa cuando la obra suma ese rol) y **pasar a {estado}** (cuando pasa
a ese estado). El link de acción abre la ficha al lado, con `?vincular={rol}` (el panel de Contactos) o
`?estado={estado}` (el cambio de estado de la obra, que con "perdida" pide el motivo). Afuera a
propósito: todo lo de cotizar (plantillas de Presupuestos), completar datos (editar un campo no es
evento) y registrar la comisión (el asignado puede ser un participante, que no la ve).

## Ficha del módulo

Aprobada el 2026-09-25, después de revisarla punto por punto con el usuario.

```
Módulo: obras
Objetivo: seguir cada obra del lado comercial, desde la idea hasta que se contrata, y generar las
          tareas de cada estado.
Personas
├── Vendedor        — ve las obras donde es responsable o participante
│                   · crea, edita, cambia el estado, vincula contactos; en las suyas, además, registra
│                     la comisión del referente, suma participantes y transfiere
│                   · no ve obras de otros vendedores donde no participa; como participante, no ve
│                     la comisión
├── Jefe comercial  — el delegador del equipo · lo del vendedor + todas las obras donde participa su
│                     equipo · transfiere entre vendedores
│                   · no ve obras de otros equipos donde el suyo no participa
├── Aprobador de altas — quien elija el admin (obras_aprobar) · ve las altas congeladas y lo parecido
│                     (nombre, dirección, responsable) · aprueba, rechaza con motivo, "es la misma"
│                   · no ve las obras ajenas enteras ni sus contactos, salvo por otro permiso
├── Admin           — ve todo · hace todo, reactiva · —
├── Administración, producción, logística, colocación — NO usan Obras: trabajan la etapa en
│                     Presupuestos (futuro) · no ven la obra ni sus contactos comerciales
├── Post-venta      — NO usa Obras: módulo aislado (futuro), que apunta a la obra y a los ítems
└── Cliente         — NO usa el módulo
Entes
└── obra — dueño responsable_id (transferible) · equipo_id del responsable, guardado al crear y
           al transferir · ruta /obras/{id} · submódulo obras_ver
           · columnas: nombre, dirección, localidad, notas, origen (origen_obra), tipo (tipo_obra),
             fecha estimada de compra (mes y año) · datos {nombre, direccion, localidad}
           · estado estado_obra: idea · en_busqueda · en_cotizacion · contratada · perdida
               idea           se detectó la obra, sin contacto todavía
               en_busqueda    se busca a quien decide
               en_cotizacion  hay al menos un presupuesto armándose o enviado
               contratada     hay al menos un presupuesto aprobado; final
               perdida        no se concretó; motivo (lista cerrada) + detalle libre, en el
                              historial de eventos
             idea ↔ en_busqueda ↔ en_cotizacion: libre, se puede saltear
             cualquiera de esos tres → perdida → reabrir a cualquiera de los tres
             → contratada: no vuelve atrás ni pasa a perdida
             con Presupuestos: el primero lleva a en_cotizacion y el primero aprobado a contratada;
               desde ahí contratada la pone solo la base
           · la ven: responsable, participantes, obras_equipo sobre obra.equipo_id o el equipo_id de
             un participante, obras_todas
           · se comparte sumando participantes · emite y dispara: alta, estado
           · congelada (no es un estado: un flag aparte) si el alta se parece a otra obra; la ve solo
             quien la cargó, no se vincula, no cambia de estado ni se transfiere; el alta cuenta al
             aprobarse
No son entes
├── participante — obras_participantes (obra, usuario, equipo_id guardado); con obras_ver
└── comisión     — obras_comisiones (vinculo_id → contactos_vinculos, porcentaje | monto): el
                   vínculo es de una obra y tiene el rol referente; una por referente
                   · la ven y la escriben: responsable, obras_equipo sobre obra.equipo_id,
                     obras_administrar
Relaciones
├── obra → usuario           — responsable (columna)
├── obra ↔ usuario           — participante (obras_participantes)
├── obra ↔ persona | empresa — en Contactos (contactos_vinculos), roles de la obra: cliente,
│                              decisor, desarrolladora, constructora, comercializadora, arquitecto,
│                              director de obra, referente
└── futuras, del otro lado   — presupuesto → obra (FK en Presupuestos); unidad → obra (FK en Post-venta)
Acciones
├── obra: crear · editar · cambiar estado · vincular contacto · registrar comisión · sumar y quitar
│         participante · transferir · desactivar (no contratada) · reactivar (admin)
│         · aprobar alta · rechazar alta (motivo) · "es la misma" — obras_aprobar
│         ├── responsable: todo lo de la obra
│         ├── participante: editar, cambiar estado, vincular contactos (no ve la comisión; no
│         │   suma participantes, no transfiere, no desactiva)
│         ├── jefe comercial: lo del responsable, en las obras de su equipo
│         └── obras_administrar: todo, en cualquier obra
Eventos que emite
├── obra: alta (al aprobarse, si entró congelada) · estado (a perdida: + motivo y detalle) · baja
│         · reactivacion · transferencia ({de, a})
├── obra: relacion_alta / relacion_baja por contacto (los emite el trigger de contactos_vinculos)
└── campanita (nunca al que hizo la acción):
    ├── obra transferida       → el nuevo responsable
    ├── sumado a una obra      → el participante
    ├── quitado de una obra    → el ex participante
    ├── obras recibidas        → el jefe, por baja o cambio de equipo de un vendedor; una por hecho,
    │                            con la cantidad
    ├── obras huérfanas        → quienes tienen obras_administrar, cuando no hay jefe que las
    │                            reciba; una por hecho
    ├── alta por aprobar       → quienes tienen obras_aprobar
    └── alta resuelta          → quien la cargó: aprobada, rechazada (con motivo) o "es la misma"
    · descartado: "cambiaron el estado de tu obra" (ruido entre quienes trabajan la misma obra)
Eventos que consume
└── ninguno hoy · con Presupuestos: presupuesto creado y aprobado mueven el estado
Tareas
├── plantillas "Sobre: obra" por estado, para comercial; una vez por plantilla y obra
└── pasos de plantilla que se completan solos: vincular {rol} · pasar a {estado}; el link de
    acción abre la ficha al lado con ?vincular={rol} o ?estado={estado}
```

```
Módulo: Obras
├── Obras (vista, obras_ver)                   — vendedor, jefe comercial, admin
│   ├── obras_crear (funcion)                  — vendedor, jefe comercial
│   ├── obras_equipo (funcion)                 — jefe comercial
│   └── obras_aprobar (funcion)                — aprobador de altas: lista "Por aprobar"
└── Todas (vista, obras_todas)                 — admin
    │   filtro huérfanas: responsable inactivo
    └── obras_administrar (funcion)            — admin

Delegables
├── sí — obras_ver · obras_crear
└── no — obras_equipo · obras_aprobar · obras_todas · obras_administrar
Reglas entre permisos
├── obras_equipo  requiere usuarios_delegar  — el jefe comercial es el delegador
├── obras_ver     requiere contactos_ver     — sin él, los contactos de la ficha no existen para
│                                              quien la abre, y la obra se trabaja vinculándolos
├── obras_todas   requiere obras_administrar — como en Tareas: sola sería un supervisor
├── obras_todas   requiere obras_ver         — la ficha se abre con obras_ver: sin él, lista que no abre
└── excluye: ninguna
    · quitar_delegador tiene que sacar obras_equipo junto con usuarios_delegar (US016); al
      escribir el SQL, correr sql/tests/usuarios_equipos.sql
```
