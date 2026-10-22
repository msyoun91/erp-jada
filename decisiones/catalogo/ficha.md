# Catálogo — ficha, estructura y entes

## Ficha del módulo — v2 (aprobada 2026-10-21)

Se armó de nuevo, sin partir del borrador de la v1 (2026-10-14), y es la vigente. Lo de la v1 que
sigue valiendo quedó en los archivos por tema (2026-10-22).

```
Módulo: catálogo
Objetivo: definir qué se compra y qué se vende, y cómo se calculan su precio y su despiece
Personas
├── Técnico         — insumos, servicios y paquetes, sin plata · crea y edita los tres (la parte
│                     técnica); en un insumo en uso, propone lo que cambia el cálculo; en paquetes
│                     escribe fórmulas y despieces, verifica que funcionen y los manda a aprobar;
│                     ve qué servicios recibe cada paquete por regla, sin el % · no ve plata
├── Administración  — ve todo, con costos (de Compras); prueba paquetes con medidas y ve el precio ·
│                     aprueba o rechaza paquetes y cambios de cálculo de insumos en uso; da de baja
│                     y reactiva en las tres vistas (insumos y servicios, con reemplazo); renombra
│                     y mueve lo que ya se vende; crea categorías y colores, carga las variantes de
│                     color; pone montos, % y mínimos de servicios, sus reglas y excepciones, y los
│                     aumenta en %; marca qué insumo se vende suelto, por presentación o por
│                     unidad; habilita a cada cliente empresa qué ve y si ve precios · —
│                     (los costos los carga Compras, en su módulo)
├── Vendedor        — NO usa el módulo: por el presupuestador elige paquetes aprobados e insumos
│                     sueltos y ve su precio · — · no ve despiece, costo ni servicios
├── Depósito        — NO usa el módulo: en Stock ve cada insumo (nombre, presentación, color) junto
│                     a sus existencias · — · no ve paquetes, fórmulas ni precios
├── Compras         — NO usa el módulo: en Compras ve cada insumo (nombre, unidad, presentación con
│                     su contenido, peso, variantes de color, categoría) con sus existencias de
│                     Stock, y ahí lo costea · — · no ve paquetes, fórmulas, servicios ni precios
├── Producción      — NO usa el módulo: el módulo de producción guarda medidas y configuración y
│                     pide el despiece cuando lo necesita · — · no ve plata ni fórmulas
└── Cliente empresa — NO usa el módulo: por el presupuestador de erp-cliente elige lo que administración
                      le habilitó; ve el precio solo si se lo habilitó · — · no ve despiece, costo ni servicios
Entes
├── paquete — dueño creado_por (solo dato) · estado por versión: borrador · para aprobar · aprobada · descartada · lo señalan la línea del presupuesto y la orden de producción
│             · datos {nombre} · ruta /catalogo/paquetes/{id} (abre la vigente) · submódulo catalogo_paquetes · roles {} · disparos {}
└── insumo  — dueño creado_por (solo dato) · sin estado (solo activo), sin versiones; un cambio de cálculo pendiente a la vez · lo señalan la línea del presupuesto (suelto), Compras, Stock y Contactos
              · datos {codigo, nombre} · ruta /catalogo/insumos/{id} · submódulo catalogo_insumos · roles {proveedor} · disparos {}
Relaciones (del catálogo)
├── versión del paquete → insumos y servicios con sus fórmulas — interior del paquete, no puente entre entes
└── empresa cliente (Contactos) → categorías o subcategorías habilitadas + ve precio — configuración, FK a la empresa
Relaciones (de otros módulos, apuntan al catálogo)
├── insumo ← proveedor (Contactos)
├── insumo o su variante de color ← costo (Compras) · existencias (Stock)
├── paquete (sin enviar) o versión del paquete (enviada) o insumo suelto (con su variante)
│   ← línea del presupuesto (Presupuestos)
└── versión del paquete ← orden de producción, con lo que cargó el vendedor (Producción)
Acciones
├── paquete: crear · duplicar · editar borrador · descartar borrador · mandar a aprobar (con qué cambió)
│            · volver al borrador · aprobar
│            · rechazar (con motivo) · versión nueva · reemplazar material · probar con medidas
│            · renombrar (técnico hasta la primera aprobada; después administración)
│            · mover de subcategoría (ídem) · dar de baja · reactivar
│            · casos de prueba: guardar desde Probar (nuevo o pisando uno) · renombrar · marcar
│              referencia · dar de baja
├── insumo: crear (sin color, o de la ventana o de herrajes con su color base) · editar · cargar los
│           servicios que lleva · marcar suelto (por presentación o por unidad) · dar de baja (con
│           reemplazo opcional) · reactivar · cargar variantes de color, en uno o en varios a la vez
│           · dar de baja o reactivar una variante (administración)
│           · mover de subcategoría (técnico sin uso; en uso, administración)
│           · renombrar o cambiar el código (ídem)
│           · en uso, cambio de cálculo (desperdicio, peso, contenido, espesor, servicios que lleva):
│             proponer · retirar · aprobar · rechazar con motivo (administración)
├── servicio: crear · editar · poner monto, % y mínimo · aumentar montos y mínimos en % (por
│             categoría o marcados, con motivo) · dar de baja (con reemplazo opcional) · reactivar
│             · regla (solo porcentuales): aplicar a todo, o a una categoría o subcategoría de
│               paquetes o de insumos, con su % · cambiar el % · quitarla
│             · excepción: otro % para un paquete · quitarla
├── categorías: crear · renombrar · dar de baja (vacía) · reactivar (administración)
│               · de insumos, fuera del % de los servicios del paquete: marcar · desmarcar (desde
│                 Servicios, al lado de las reglas)
├── colores: crear · renombrar · dar de baja · reactivar (administración)
└── clientes: habilitar categoría o subcategoría · ve precio sí/no (administración)
Eventos que emite
├── paquete: estado de la versión (para aprobar · vuelta al borrador · rechazada → borrador · aprobada
│            · descartada)
│            — para aprobar y vuelta al borrador, aviso a administración; rechazada, aprobada y
│            descartada, al técnico; la primera aprobada avisa a vendedores del producto nuevo
│            (con Presupuestos)
├── paquete: alta — sin aviso (es el borrador de la v1: el producto nuevo se avisa al aprobarla)
├── paquete: baja · reactivación — con versión aprobada, aviso a vendedores (con Presupuestos): sale
│            de venta, que desaparece al reactivarse; vuelve a la venta
├── insumo: alta · reactivación — sin aviso
├── insumo: baja — aviso al técnico con el alcance: "Marco 70 mm: 3 paquetes incompletos · 9 pierden
│            una alternativa"; con reemplazo, "12 borradores para revisar y mandar a aprobar"; las
│            cifras se calculan al leer y el aviso desaparece sin incompletos ni borradores con el
│            reemplazo (las alternativas perdidas no lo sostienen)
├── insumo: cambio de cálculo (para aprobar · retirado · aprobado · rechazado) — para aprobar, aviso
│            a administración con el alcance: "Marco 70 mm: desperdicio 8 → 80 % · 40 paquetes";
│            retirado, aviso a administración; aprobado o rechazado (con motivo), aviso al técnico
└── servicio: ninguno (no es ente); su baja avisa al técnico sin evento, como la del insumo
Eventos que consume
└── ninguno
```

```
Módulo: Catálogo
├── Insumos (vista, catalogo_insumos)            — técnico, administración
│   ├── catalogo_insumos_editar (funcion)        — técnico: crear y editar, con los servicios que lleva;
│   │                                              mover, renombrar y cambiar el código sin uso; en uso,
│   │                                              lo que cambia el cálculo lo propone y lo retira
│   └── catalogo_insumos_administrar (funcion)   — administración: ve costos (y el filtro sin costo y en
│                                                  uso), aprobar o rechazar cambios de cálculo, suelto y
│                                                  cómo se vende, mover, renombrar y cambiar el código en
│                                                  uso, categorías, colores y variantes, baja (con
│                                                  reemplazo) y reactivar
├── Servicios (vista, catalogo_servicios)        — técnico, administración
│   ├── catalogo_servicios_editar (funcion)      — técnico: crear y editar
│   └── catalogo_servicios_administrar (funcion) — administración: monto, % y mínimo (y el filtro sin
│                                                  monto y el aumento en %), reglas y excepciones por paquete,
│                                                  categorías fuera del % de los servicios del paquete,
│                                                  categorías, baja y reactivar
├── Paquetes (vista, catalogo_paquetes)          — técnico, administración
│   ├── catalogo_paquetes_editar (funcion)       — técnico: borradores (y descartarlos), duplicar, versión nueva, mandar a aprobar,
│   │                                              reemplazar material, volver al borrador, probar sin plata
│   │                                              y guardar casos de prueba; renombrar y mover hasta la
│   │                                              primera aprobada
│   └── catalogo_paquetes_administrar (funcion)  — administración: aprobar y rechazar, probar
│                                                  con plata y guardar casos de prueba, categorías, renombrar, mover,
│                                                  baja y reactivar
└── Clientes (vista, catalogo_clientes)          — administración
    └── catalogo_clientes_habilitar (funcion)    — administración: qué ve cada empresa y si ve precio
Delegables
├── sí — catalogo_insumos · catalogo_insumos_editar · catalogo_servicios · catalogo_servicios_editar
│        · catalogo_paquetes · catalogo_paquetes_editar
└── no — catalogo_insumos_administrar · catalogo_servicios_administrar · catalogo_paquetes_administrar
         · catalogo_clientes · catalogo_clientes_habilitar
Reglas entre permisos (requiere): catalogo_insumos, catalogo_servicios y catalogo_paquetes, cada una
las otras dos · catalogo_clientes → catalogo_paquetes. _editar y _administrar pueden coexistir en la
misma persona.
Permisos de otros módulos que mira el catálogo (cada uno entra con su módulo): Presupuestos y
erp-cliente → precio de la vigente · Producción → despiece de las aprobadas · Stock y Compras →
leer el insumo.
```

## Estructura

- **Un solo módulo con tres vistas: Insumos · Servicios · Paquetes** (2026-09-29). Catálogo es un
  módulo con tres pestañas, no tres módulos. La visibilidad por persona se resuelve por vista (cada
  pestaña es su submódulo), no por módulo; el técnico trabaja en las tres a la vez (arma un paquete
  eligiendo insumos y servicios), y un paquete no existe sin sus insumos. Descartado: Paquetes como
  módulo aparte (el ERP viejo tenía Lista de precios + Plantillas + Márgenes) — un layout, una ficha
  y un ir y venir de más para la misma persona.
  - *Insumos* (`insumos.md`): los materiales que se pueden usar o vender.
  - *Servicios* (`servicios.md`): lo no material. Porcentual, o fijo (corte, manipulación del
    material).
  - *Paquetes* (`motor.md`, `opciones.md`, `versiones.md`): donde están las fórmulas, armadas con
    insumos y servicios.
- **Fuera del catálogo**: el costo (Compras: `precio.md` → *El costo sigue fuera del catálogo, en
  Compras*), las existencias (Stock), el proveedor (empresa de Contactos con rol `proveedor` sobre el
  insumo, `decisiones/contactos.md`) y el precio final (Presupuestos: es donde se cargan las medidas).
- **Categorías en dos niveles fijos, en las tres vistas**: categoría → subcategoría → ítem (Perfiles
  PVC → Marcos → Marco corrediza 70 mm · Ventanas → Modena → Corrediza 2 hojas). Cada ítem está
  en una subcategoría. No se anida más. Las crea administración. Servicios también, por decisión del
  usuario, aunque sean pocos (propuesta descartada: lista plana con búsqueda y filtro
  fijo/porcentual).
- **Una categoría o subcategoría con ítems activos no se da de baja; vacía sí, y se reactiva**
  (2026-10-22). Frena con la lista (*Vidrios → Float: 12 insumos activos — movelos o dalos de baja
  primero*); en una categoría cuentan todas sus subcategorías. Vacía, lo que la nombra (opciones que
  la ofrecen, reglas, marca fuera del %, clientes habilitados) queda sin efecto y se ve en el alcance
  antes de confirmar (*la ofrecen 3 opciones · 1 regla · 2 clientes*); el editor del paquete dice
  *(de baja)*. Reactivar (administración) la devuelve con todo eso. No se crean ni se mueven ítems a
  una de baja. Por qué: dar de baja *Vidrios → Float* con 12 Float adentro, o *Ventanas → Modena* con
  6 corredizas, no decía si seguían ofreciéndose ni qué pasaba con opciones, reglas y clientes.
- **En paquetes, la subcategoría es la línea de perfiles** (2026-10-19): Ventanas → Modena → Corrediza
  2 hojas, Corrediza 3 hojas; Ventanas → Herrero → Corrediza 2 hojas. La línea sale del nombre. Por qué:
  es lo único que el buscador por nombre no da — habilitar a un cliente empresa solo Modena. Para no
  perder lo que daba la línea en el nombre (v1): el buscador del vendedor busca también en la
  subcategoría (*modena corr* encuentra) y la línea del presupuesto muestra subcategoría y nombre
  (*Modena · Corrediza 2 hojas*), así una Herrero entre Modenas se ve al revisar. Descartado:
  subcategoría por material (Ventanas → Aluminio) o por tipo (Ventanas → Corredizas) con la línea en el
  nombre — administración no podría habilitar una sola línea.
- **La subcategoría la elige el técnico al crear; administración puede moverla después.** Con quién
  y cómo (2026-10-22): el técnico mueve libre un insumo que no está en uso y un paquete hasta su
  primera versión aprobada (es como haberla elegido al crear); después, administración, con el alcance
  antes de confirmar: *Laminado 4+4: Laminados → Float · % 15 → 10 · entra en 40 paquetes, sale de
  12 · 3 líneas sin enviar quedan sin precio · lo ven 2 clientes más, lo deja de ver 1*; *Corrediza
  2 hojas: Modena → Herrero · Comercialización 35 → 22 % · lo dejan de ver 4 clientes, lo empiezan
  a ver 2*. Por qué: mover cambia a la vez el % por regla, lo que entra por subcategoría y lo que ve
  cada cliente, y nada decía quién lo hacía.
- **El catálogo es compartido: no nace privado.** Todo técnico ve y edita los borradores de cualquier
  otro; quien tiene la vista ve todo lo de esa vista. `creado_por` es un dato, no da visibilidad.
  Excepción a *Todo ente nace privado* (`GUIDE_ENTES.md` §2.4): el catálogo es de la empresa y entre
  técnicos no hay competencia que proteger. Descartado: borrador privado hasta mandarlo a aprobar
  (suma compartir y transferir sin necesidad).

## Quién hace qué

- **Solo el paquete se aprueba** (revertido para insumo y servicio, 2026-10-14). El técnico crea y edita
  insumos y servicios sin aprobación; administración completa la plata. Insumo y servicio no tienen
  estado, solo `activo`. El freno queda donde importa: un insumo nuevo no se vende suelto hasta que
  administración lo marca, y un paquete que lo usa no llega al vendedor hasta que administración lo
  aprueba probándolo con plata — ahí ve si falta un costo o un monto. La excepción, desde el
  2026-10-21: lo que cambia el cálculo de un insumo en uso (`insumos.md` → *Lo que cambia el cálculo
  de un insumo en uso espera a administración*). Descartado: el mismo circuito de aprobación en las
  tres vistas (trabajo doble para administración sobre datos que el paquete ya revisa).
- **Dar de baja es de administración, en las tres vistas**: `bajas.md`.
- **La plata va atada a las funciones `_administrar`**: sin una, esa vista no muestra costos, montos
  ni precios. El técnico, con la vista y `_editar`, nunca ve plata.
- **`_editar` y `_administrar` pueden coexistir**: en una empresa chica la misma persona es técnico y
  administración. Descartado: excluirlas para que nadie apruebe su propio paquete (obliga a dos personas).
- **Se delegan las vistas y lo del técnico; lo de administración, no** (2026-10-21). El jefe técnico
  le da a uno nuevo las tres vistas + `catalogo_paquetes_editar` sin pasar por el admin: arma
  borradores y manda a aprobar. Los `_administrar` (aprobar, poner a la venta, costos, montos y %) y
  *Clientes* entera los asigna el admin: la vista sola ya dice qué empresa ve precio. Como en Contactos
  y Obras.
- **Las tres vistas van juntas: Insumos, Servicios y Paquetes se requieren entre sí, y Clientes
  requiere Paquetes** (2026-10-22). Seis filas `requiere` en `submodulo_reglas` y una más; cada tabla
  la sigue leyendo su vista. Cada pantalla muestra filas de las otras dos: Paquetes arma con insumos y
  servicios; Insumos dice en qué paquetes está cada uno y qué servicios trae; Servicios pone reglas por
  categoría de paquete y de insumo y excepciones por paquete; Clientes habilita categorías de los dos.
  Nadie usa una sin las otras, y sin `_administrar` ninguna muestra plata. Como `tareas_mision` →
  `tareas_ver`. Por qué: el nuevo con *Paquetes* + `catalogo_paquetes_editar` abría el borrador de la
  Corrediza 2 hojas, iba a sumar *Felpa 7×5* y el buscador de insumos salía vacío. Descartado: leer
  con cualquier vista del catálogo (quitar Insumos no quitaría leer insumos, y la policy de cada tabla
  listaría tres vistas, cinco con Stock y Compras) y reglas finas por función (siete u ocho filas para
  separar pantallas que nadie usa por separado).

## Entes

- **Dos entes: paquete e insumo** (2026-10-14). Son lo que otro módulo señala: Compras costea el
  insumo, Stock lleva sus existencias, Contactos le vincula el proveedor, y la línea del presupuesto
  apunta a un paquete o a un insumo suelto. Lo demás es parte de un ente o configuración: la variante
  de color es del insumo (Compras la costea por FK); la versión es del paquete (lo guardado apunta a
  la versión, el chip muestra el paquete); grupos, piezas, materiales, variables, opciones y casos de
  prueba son el interior del paquete; categorías, montos, % y reglas de servicios y habilitaciones de
  clientes son configuración.
- **El servicio no es ente: vive solo dentro del catálogo** (paquetes, reglas y los insumos que lo
  traen): nadie de afuera lo elige, lo suma la función de precio. Lo que no está en el catálogo
  (flete, traslado, algo que no vale la pena cargar) es un renglón libre del presupuesto, con
  descripción y monto que calcula el vendedor; no sale de servicios (`BACKLOG.md` → Presupuestos).
  Si algún día un cargo apunta a un servicio, alcanza una FK.
- **Paquete e insumo se registran con su vista; para quien solo compra, el insumo no es ente**
  (2026-10-21). Paquete: datos `{nombre}`, ruta `/catalogo/paquetes/{id}` (abre la vigente),
  submódulo `catalogo_paquetes`, sin roles; chip *Modena · Corrediza 2 hojas*. Insumo: datos
  `{codigo, nombre}` (depósito y Compras hablan por código), ruta `/catalogo/insumos/{id}`, submódulo
  `catalogo_insumos`, roles `{proveedor}`; chip *ART-2410 · Marco 70 mm*. Como el ente existe solo
  para quien tiene su vista (RLS de `entes`), quien solo compra no ve en *Aluar* el chip *proveedor
  de: ART-2410 · Marco 70 mm* ni encuentra el insumo en el buscador de Contactos: lo vincula desde
  Compras. El rol lo valida un trigger `DEFINER` que lee `entes` igual, y quién vincula lo dice la
  rama del catálogo en `trabaja_registro`, a la que Compras suma su permiso. Vendedor y producción
  tampoco ven el chip del paquete: la línea muestra lo que da la función de cálculo. Por qué: chip y
  buscador para Compras piden que `entes.submodulo` acepte varias vistas y una ruta según quién mira,
  un cambio de core que hoy nadie necesita; si Compras los pide, se decide al ficharlo (`BACKLOG.md`).
  **Sin disparos** (2026-10-22), como Tareas: ninguna persona pide una plantilla de Tareas sobre el
  catálogo, y disparar pide las ramas `_de` de `etiqueta_registro` y `relacionados_de_registro`. Si
  aparece el caso (*al aprobarse un producto nuevo → sacar fotos*), se suma en `entes` con sus ramas:
  los eventos ya se emiten. Descartado: `{alta, estado}` por si acaso.
- **Versión y cambio de cálculo emiten con trigger propio, con el id del paquete o del insumo**
  (2026-10-22). `paquetes` e `insumos` llevan el genérico, `emitir_eventos_registro('paquete')` e
  `('insumo')`: alta, baja, reactivación. Las versiones emiten solo al cambiar de estado (abrir un borrador no emite; la v1 nace con
  el alta): `('paquete', paquete_id, 'estado', {estado, anterior, version, motivo})`, con `motivo` solo
  en el rechazo, que es lo que lo distingue de volver al borrador. Los cambios de cálculo, al nacer y al
  cambiar de estado: `('insumo', insumo_id, 'estado', {estado, anterior, cambio_id, motivo})`, con
  `para_aprobar · aprobado · rechazado · retirado`; `estado` aunque el insumo no tenga, para no sumar al
  enum. Por qué: el genérico emite con el `id` de la fila, y la v5 (fila 87) del paquete 12 avisaba del
  "paquete 87" y daba un alta falsa por versión; el número de versión va en el detalle porque el
  historial arma de ahí el recorrido de cada una (`versiones.md` → *El paquete muestra su historial
  versión por versión*). Descartado: un argumento más en el genérico para la columna del id (seguiría
  emitiendo alta por versión). Toca: el SQL del catálogo y `GUIDE_ENTES.md` §2.8.
- **Los avisos van a quienes tienen la función, no a una persona** (2026-10-22). "Al técnico" es a
  todos los que tienen la `_editar` de la vista (`catalogo_paquetes_editar` lo de paquetes y bajas,
  `catalogo_insumos_editar` el cambio de cálculo); "a administración", a los de su `_administrar`. Quien
  actuó no recibe el suyo. Por qué: técnico hay uno, y seguir a quien mandó cada versión o propuso cada
  cambio pide buscar a esa persona para llegar al mismo. Descartado: `creado_por` (es solo dato) y quien
  mandó la versión, sacado del evento `para_aprobar`.
- **Cada aviso dice a qué apunta y cuándo desaparece** (2026-10-22). Lo que espera una acción
  desaparece al resolverse, como `alta_por_aprobar`; lo que cuenta algo se calcula al leer y desaparece
  en 0, como `hilos_huerfanos`; el resto queda hasta leerlo o descartarlo.
  - Versión (apunta a la versión): *para aprobar*, a administración, desaparece al aprobarse,
    rechazarse o volver al borrador; *volvió al borrador*, a administración; *rechazada* (con motivo),
    *aprobada* y *descartada*, al técnico. *Descartada* no avisa a administración: nunca le llegó (lo
    que está para aprobar no se descarta).
  - Baja de un insumo (apunta al insumo), al técnico: la cifra la da al leer la función del alcance de
    la baja (*Felpa X: 3 incompletos · 12 borradores con el reemplazo*) y desaparece cuando no queda
    nada incompleto por esa baja ni borradores con su reemplazo sin aprobar. Lo que solo informa
    (*9 pierden una alternativa*) se muestra pero no lo sostiene: esas versiones aprobadas no se
    editan, así que la cifra no bajaría nunca, y los paquetes quedan marcados (`bajas.md`).
  - Baja de un servicio (apunta al servicio), al técnico, con o sin reemplazo: *Soldadura de marco:
    25 borradores con el reemplazo · lo traen 2 insumos*; desaparece cuando no queda nada incompleto
    por esa baja, ni borradores con su reemplazo sin aprobar, ni insumos activos que lo traigan. Sin
    evento, porque el servicio no es ente: lo escribe un trigger sobre la baja con `notificar()`, como
    los de `usuario_submodulos`.
  - Cambio de cálculo (apunta al cambio): *para aprobar*, a administración, desaparece al aprobarse,
    rechazarse o retirarse; *retirado*, a administración; *aprobado* o *rechazado* (con motivo), al
    técnico.
  - Baja de un paquete (apunta al paquete), a vendedores: *sale de venta*, desaparece al
    reactivarse. Reactivarlo avisa *vuelve a la venta*, el mismo aviso que *producto nuevo* con otro
    texto. Los dos, solo si tiene una versión aprobada: lo que nunca se vendió no sale ni vuelve.

  Por qué: Marcos volvía la v5 al borrador y la campanita de Laura seguía con *v5 para aprobar*; el
  aviso de la Felpa X decía *3 incompletos* un mes después de arreglarlos; la baja de *Soldadura de
  marco* con reemplazo dejaba 25 borradores sin que Marcos se enterara, porque nada quedaba incompleto;
  y Laura reactivaba el miércoles la *Herrero · Corrediza 2 hojas* que había dado de baja el lunes, y
  el jueves Pedro leía *sale de venta* y la cotizaba como Modena.
  Descartado: que todos queden hasta leerlos (pendientes que ya no lo son, y lo que espera se mezcla
  con lo demás); hacer ente al servicio para que emita (fila en `entes` y siete funciones de core por
  un aviso); avisar la del servicio solo con reemplazo (sin él, el técnico sale a buscar los
  incompletos y con el insumo no); y al reactivar, solo borrar el de baja (quien ya lo leyó no se
  entera de que volvió). Toca: el SQL del
  catálogo (`tipo_notificacion`, el CHECK de `entidad` y su rama en `notificaciones_listar`).
- **El producto nuevo se avisa al aprobarse la primera versión, no en el alta.** El alta ocurre cuando el
  técnico abre el borrador: avisar ahí a los vendedores sería avisar de algo que no se vende. "Incompleto"
  no emite (se calcula); lo que lo causa avisa: la baja del insumo o del servicio.
- **Los avisos a vendedores entran con Presupuestos y los resuelve una función del catálogo**
  (2026-10-22). *Producto nuevo*, *sale de venta* y *vuelve a la venta* van a quienes tienen el permiso
  de Presupuestos que arma líneas, que se nombra al ficharlo; en el SQL sin plata no hay aviso a
  vendedores, y los eventos (primera aprobada, baja, reactivación) se emiten igual. El texto lo da una función `DEFINER` del catálogo,
  subcategoría y nombre (*Herrero · Corrediza 2 hojas*), solo de los avisos propios, como
  `duplicados_avisos`; el destino es el presupuestador, no `/catalogo/paquetes/{id}`. No abre nada
  nuevo: es el nombre de algo que está o estuvo a la venta. Por qué: la notificación arma el texto con
  la RLS de quien la lee y el vendedor no lee `catalogo_paquetes` (`calculo.md` → *La función de
  cálculo decide qué parte ve cada uno*): Laura aprobaba la v1 de la Herrero y la campanita del
  vendedor no mostraba nada; con la baja, menos. Descartado: copiar el nombre en la notificación
  (apunta, no copia, y renombrado queda viejo) y darle al vendedor lectura de la tabla de paquetes.

## Con otros módulos

- **El catálogo no apunta con FK a otro módulo salvo la empresa cliente**: solo es dueño del interior de
  los paquetes y de las habilitaciones de clientes. Los demás le apuntan. Para el precio lee costo y
  cotización de Compras —probar con plata, *sin costo*, los costos en Insumos— (2026-10-21), así que
  no se construye entero antes que Compras: el SQL va en tres partes, catálogo sin plata (insumos,
  servicios, paquetes, versiones, fórmulas, despiece, controles, probar sin precio), Compras mínimo
  (su ficha, costo y cotización) y la rama de plata de la función de cálculo. Stock y Producción,
  después. Descartado: crear las tablas de Compras en el SQL del catálogo (tablas de un módulo sin ficha).
- **Depósito no usa el catálogo: ve el insumo desde Stock** (2026-10-21). Para contar y guardar 20
  barras de Marco 70 mm negro mate le alcanza con nombre, presentación y color, y siempre los mira
  junto a las existencias. Corrige la v1, que le daba la vista Insumos: esa vista es para crear y
  editar, y suma desperdicio, peso y dónde se usa, que no necesita. Con qué permiso Stock lee el
  insumo: *Stock y Compras leen la tabla del insumo*.
- **Compras no usa el catálogo: ve el insumo desde Compras, con sus existencias de Stock, y ahí lo
  costea** (2026-10-21). Para cargar *Marco corrediza 70 mm negro mate: $ 32.000 / barra* o
  *Perfiles PVC +8 %* le alcanza con nombre, unidad, presentación con su contenido, peso, variantes
  de color y categoría; paquetes, fórmulas, servicios y precio no los necesita. Vuelve la persona de
  la v1, que la v2 había juntado con administración, y coincide con Compras en Contactos (equipo
  propio). Administración sigue viendo costos en el catálogo; si la misma persona compra y
  administra, tiene los dos permisos. Por qué: juntas, quien solo compra quedaba como
  administración, y con `_administrar` daba de baja, marcaba suelto, aprobaba y veía el % de los
  servicios. Con qué permiso Compras lee el insumo: *Stock y Compras leen la tabla del insumo*.
- **Stock y Compras leen la tabla del insumo del catálogo; lo suyo va en tablas propias con FK**
  (2026-10-21). Hay una sola tabla de insumos. Compras guarda el costo (`insumo_id` → $ 32.000 /
  barra) y Stock las existencias (`insumo_id` + negro mate → 20 barras), sin copiar nombre,
  presentación ni color. La policy de lectura del insumo, de sus variantes de color y de las
  categorías suma la vista de Stock y la de Compras, cada una al construirse su módulo. Leen la fila
  entera, desperdicio y peso incluidos: no tiene plata (el costo está en Compras; montos y % en
  tablas propias). Paquetes, fórmulas y servicios están en tablas que piden las vistas del catálogo:
  depósito pide los paquetes por API y recibe 0 filas. El *dónde se usa* de *sin costo y en uso* es
  la función del catálogo, con la rama de Compras. **Todo lo que Compras compra y Stock cuenta es un
  insumo del catálogo, y el alta es del técnico**: no manejan nada que no vaya a un paquete o se
  venda suelto (confirmado por el usuario). Por qué: con copias, corregir el peso en el catálogo deja
  viejas las otras; con costo o existencias en la fila del insumo, el técnico los leería (RLS filtra
  filas, no columnas). Descartado: una función que devuelva solo las columnas de cada uno (segunda
  puerta a la tabla para ocultar datos que no son sensibles) y una tabla de insumos común, sin dueño
  (el alta igual es del técnico, y suma un módulo).
