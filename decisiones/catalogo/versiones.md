# Catálogo — versiones y aprobación del paquete

Quién mueve una versión de borrador a la venta, qué se controla, qué se compara y qué se guarda. Lo
que una baja hace con las versiones, en `bajas.md`; los eventos de estado, en `ficha.md` → *Entes*.

## Estados

- **El estado es de cada versión del paquete: borrador · para aprobar · aprobada · descartada.** La
  vigente (última aprobada) se calcula, no se guarda. Mientras v2 está en borrador o en revisión se
  sigue vendiendo v1. Rechazar vuelve a borrador con motivo obligatorio. Dar de baja el paquete lo saca
  de la venta; lo que apunta a una versión (lo enviado, las órdenes) se sigue calculando. Pedirle la
  vigente a un paquete que no está a la venta (de baja o incompleto) da sin precio (*Corrediza 2
  hojas: no está a la venta*), sin decir cuál de las dos; qué hace la línea con eso es de
  Presupuestos (2026-10-21). *Descartada*, desde el 2026-10-22 (*El borrador se descarta*).
- **Consecuencia del despiece calculado: una fórmula aprobada no se edita.** Si el despiece se
  recalcula cuando se pide (`calculo.md` → *El despiece no se guarda*), cambiar `ancho − 6` por
  `ancho − 8` después de vendida cambiaría la ventana vendida. Editar crea una versión nueva, y lo
  guardado apunta a la versión.
- **Cada paquete tiene como mucho una versión abierta (borrador o para aprobar)** (2026-10-21).
  Mientras haya una, "versión nueva" no crea otra: muestra la abierta (*v4 · Marcos · agrega burlete
  inferior en la hoja*). Si está en borrador, cualquier técnico la edita y suma su cambio al texto;
  si está para aprobar, la vuelve al borrador o espera. Por qué: con dos borradores que parten de la
  v3, aprobar la v4 (burlete) y después la v5 (rueda doble) deja vigente una versión sin el burlete, y
  nadie lo nota. Descartado: borradores en paralelo (obliga a combinarlos).

## Mandar a aprobar y aprobar

- **Mandar a aprobar frena; aprobar pone a la venta** (2026-10-21). Reemplaza a "Publicar" de la v1.
  El borrador se guarda a medias y Probar lo usa. Al mandar a aprobar corren los controles; si falla
  uno, no se manda. Esta es la única lista; las demás decisiones la apuntan, y aprobar corre la misma:
  - incompleto (`bajas.md` → *La baja depende de cómo se usa lo que se da de baja*): *usa Felpa X, de
    baja desde el 20/10*;
  - sin caso de referencia (*Los casos de prueba corren cuando alguien los mira*);
  - sin el texto de qué cambió, también en la primera versión, que dice qué es (*Corrediza 2 hojas
    Herrero, línea nueva*);
  - fórmula mal escrita (`motor.md` → *Las fórmulas se validan al guardar*) y ciclo (*Nada depende de
    sí mismo*);
  - medida secundaria sin default y medida principal con default (`opciones.md` → *Una medida
    secundaria lleva default; una principal, no*);
  - medida del vendedor sin mínimo o máximo (`opciones.md` → *Toda medida del vendedor lleva mínimo y
    máximo*);
  - unidad que no coincide (`motor.md` → *Cada variable declara su unidad*);
  - hermanas que no ofrecen lo mismo o con defaults que no son par, y par entre tres o más hermanas
    (`opciones.md` → *Las opciones hermanas arrancan juntas*);
  - espesor que falta en una alternativa (`opciones.md` → *El espesor lo pone el sistema*);
  - servicio a mano que ya trae un insumo del grupo (`servicios.md` → *Un insumo puede traer sus
    servicios*);
  - material por m² sin ancho o alto (`opciones.md` → *El vidrio cobra por una variable de
    superficie*);
  - cantidad de piezas que no da entero y material por piezas sin presentación (`motor.md` → *La
    cantidad de piezas lleva el redondeo escrito*, *Una pieza más larga que la barra da aviso*).

  Recién al aprobar, la versión pasa a ser la vigente y la ve el vendedor. Un presupuesto sin enviar
  sigue a la vigente, con aviso en la línea que suma el texto del técnico (*el paquete cambió: v3 → v4
  · agrega burlete inferior en la hoja*); al enviar, se congela. Por qué: con aprobación, mandar no
  puede cambiar lo que se vende. Descartado: que la línea quede en la versión vieja hasta actualizarla
  a mano (v1). Incompleto, referencia y texto, en la lista desde el 2026-10-22: la v5 con la Felpa X
  de baja se mandaba y la frenaba Laura al aprobar, cuando el sistema ya lo sabía al mandar; y los
  otros dos frenos estaban escritos solo en su decisión. Diagrama:
  https://claude.ai/artifact/BLhKnFktuJWyEpHGQedVoa
- **Lo que está para aprobar no se edita: el técnico lo vuelve al borrador** (2026-10-21). "Volver al
  borrador" saca la versión de la revisión sin perder nada y sigue siendo la misma (v4, no v5: nunca
  se aprobó). Se corrige y se vuelve a mandar: corren otra vez los controles y el texto de qué cambió
  se puede ajustar. Administración deja de verla en pendientes y recibe aviso; el vendedor sigue con
  la vigente. Por qué: lo que administración revisa no cambia mientras lo revisa. Descartado: el
  nombre "Revertir" (se lee como volver a la versión anterior o deshacer los cambios).
- **Administración aprueba varias versiones juntas con checkbox, viendo qué cambió de verdad.** Cada fila
  muestra el texto del técnico (el porqué), los cambios que detecta el sistema entre versiones (*Cuenta
  como cambio todo lo que está en la versión*) y el precio antes y después en el caso de referencia del
  paquete (*Los casos de prueba corren cuando alguien los mira*). El texto solo no alcanza: dice lo
  que el técnico cree que cambió. Lo que entra sin plata se marca sin frenar (`precio.md` → *Lo que
  falta costear se ve en filtros*).
- **Aprobar vuelve a correr los controles y el incompleto** (2026-10-22): la lista de *Mandar a
  aprobar frena*, no una propia. Desde que se mandó solo cambian una baja y el caso de referencia, que
  se toca aunque haya una versión para aprobar. Si falla uno, no se aprueba: la fila de pendientes dice por qué (*v5: usa Felpa X, de baja desde el 20/10*), el
  checkbox no la toma y la vigente sigue; administración la rechaza con ese motivo escrito. El alcance
  de una baja suma las versiones para aprobar que la usan (*la usa la v5 de Corrediza 2 hojas, para
  aprobar: no se va a poder aprobar*). Por qué: la Felpa X dada de baja sin reemplazo entre mandar y
  aprobar dejaba vigente una v5 incompleta y la Corrediza salía de venta aunque la v4 estaba bien; la
  baja con reemplazo ya la vuelve al borrador.
- **El borrador se descarta, y lo que trae de una baja pasa a la versión que sigue** (2026-10-22). El
  técnico descarta la abierta en borrador: pasa a `descartada` (estado, así el historial la registra
  por el evento: *v5 · descartada 22/10*) y la próxima arranca de la vigente con el número que sigue
  (v6). Si traía reemplazos de una baja, descartar abre la v6 con esos pares viejo → nuevo ya puestos:
  sin ellos la vigente queda con el insumo dado de baja y deja de venderse. Los de *"Reemplazar
  material"* sobre un insumo activo se van con el resto. Para aprobar no se descarta (vuelve antes al
  borrador), y sin vigente tampoco: eso es dar de baja el paquete. La lista muestra la antigüedad de
  la abierta (*v5 · borrador · hace 5 meses*). Por qué: la v5 de marzo con `rueda_hoja_izq` a medio
  escribir recibía en agosto la Hoja 42 de la baja, y para mandarla había que terminar o deshacer a
  mano lo de la rueda; mientras, la v4 se vendía con la Hoja 40 al costo viejo, sin plazo.

## Casos de prueba

- **Los casos de prueba corren cuando alguien los mira; uno es el de referencia** (2026-10-21).
  Reemplaza a los casos que corría "Publicar" en la v1. Un caso es lo que carga el vendedor (medidas,
  opciones, color), con nombre; se guarda desde Probar y se carga con un clic.
  Uno se marca *referencia* (reemplaza a la medida de referencia): sin él no se manda a aprobar. El
  resultado no se guarda, como el despiece. Al mandar a aprobar, el técnico ve las diferencias de
  cada caso contra la vigente, sin precios (materiales que entran o salen, piezas, cantidades, avisos:
  *"Grande 3000 × 1800": rueda simple → doble (hoja der) · Travesaño hoja der 1460 → 1510 mm*), y
  confirma. Administración, en pendientes, ve las mismas con precio antes y después; la fila muestra
  el del caso de referencia. En la primera versión no hay antes: cada caso con su despiece y precio.
  Una opción que ya no existe sigue *Lo elegido se guarda* y se marca. Por qué: cargar a mano 4 casos
  de 8 campos en cada edición termina en probar uno, y lo roto lo encuentra el vendedor; medida de
  referencia y caso eran dos conceptos para lo mismo. Descartado: resultado esperado por caso (habría
  que cargar el despiece entero a mano).
- **Los casos de prueba son del paquete, no de la versión, y los guarda quien prueba** (2026-10-21).
  La Corrediza 2 hojas tiene *Referencia 1500 × 1100*, *Grande 3000 × 1800* y *Chica 600 × 600 con
  mosquitero*: el técnico los encuentra en la v5 y, al mandarla a aprobar, cada uno corre en la v4 y
  en la v5. Los guardan desde Probar el técnico (`catalogo_paquetes_editar`) y administración
  (`catalogo_paquetes_administrar`), que suma el *Balcón 2400 × 2200* que vio en un presupuesto: un
  caso no tiene plata. Si se da de baja la referencia, no se manda a aprobar hasta marcar otra. Se
  tocan aunque haya una versión para aprobar, porque no son parte de lo que se aprueba: si cambia la
  referencia, a administración le cambian las cifras que mira. Por qué: comparar pide correr el mismo
  caso en dos versiones; siendo de la versión, la v5 copiaría los de la v4 y uno nuevo no tendría
  contra qué compararse. Descartado: congelarlos mientras haya una versión para aprobar.

## Qué cambió

- **Cuenta como cambio todo lo que está en la versión** (2026-10-21): variables (medidas del vendedor
  con sus topes y mensajes, calculadas, opciones con sus alternativas en orden), grupos, materiales
  (cantidad o fórmula, condición, piezas con largo y ángulos, si suma al peso), servicios con su
  cantidad y restricciones. Se muestra por pestaña, solo lo que cambió, con antes → después (*Medidas:
  ancho máx. 2400 → 3000 mm*). No entra lo que no es de la versión: nombre y subcategoría del paquete, casos
  de prueba, reglas y excepciones de servicios, datos del insumo, plata. Es una sola comparación para
  el historial y para pendientes, y sin plata: técnico y administración ven lo mismo. Por qué: la v5
  de la Corrediza económica decía *baja el umbral de rueda doble a 35 kg* y en el mismo borrador el
  máximo del ancho pasó de 2400 a 3000; con solo insumos y fórmulas se aprobaba sin verlo y se vendía
  lo que la línea no soporta. Descartado: solo lo que cambia el resultado de los casos (subir el
  máximo no cambia un caso dentro del límite). **El orden de las alternativas cuenta** (2026-10-22): sin default,
  o con un default que no se ofrece, entra la primera que se ofrezca (`opciones.md` → *Lo elegido se
  guarda*). Push subido arriba en la v5 hacía arrancar en Push las líneas nuevas de *herraje hoja
  izq* sin que nadie lo marcara; el comparador lo muestra (*Manija, Cerradura, Push → Push, Manija,
  Cerradura*).
- **El paquete muestra su historial versión por versión, como apoyo del técnico** (2026-10-21). Cada
  versión dice qué cambió respecto de la anterior: el texto del técnico, los cambios que detecta el
  sistema (los de pendientes, sin precio) y su recorrido en una línea (*v5 · baja el umbral de rueda
  doble a 35 kg · `rueda_hoja_izq`: `peso > 40` → `peso > 35` · mandada 12/09 (Marcos) → rechazada
  13/09 (Laura: falta probar el caso grande) → mandada 15/09 → aprobada 15/09 (Laura)*). La abierta
  encabeza la lista con lo que lleva cambiado. Lo ven técnico y administración con la vista Paquetes.
  No se guarda una copia: los cambios se calculan desde las versiones, que no cambian al aprobarse, y
  cada una parte de la anterior (*Cada paquete tiene como mucho una versión abierta*); el recorrido
  sale de los eventos de estado, con el motivo del rechazo. Por qué: le explica al técnico por qué el
  paquete es como es (la orden de la v3 que hoy saldría con rueda doble) sin depender de que el texto
  lo diga todo. Descartado: comparar dos versiones cualquiera (v3 contra v6 se lee de v4 a v6) y
  precio en el historial (la plata se mira al aprobar).

## Lo guardado, el nombre y la copia

- **Lo guardado cruza versiones por nombre y por insumo** (2026-10-22). La línea sin enviar (sigue a
  la vigente), la orden (`calculo.md` → *Producción puede elegir con qué versión aprobada fabrica*) y
  los casos de prueba guardan cada medida, opción y grupo por su nombre, y la alternativa elegida por
  su insumo. **El nombre queda fijo desde que está en una versión aprobada**, como la unidad del
  servicio (`servicios.md` → *El servicio se edita directo*); en un borrador que nunca se aprobó, se
  renombra libre. Sacar una variable y crear otra es otra cosa: lo guardado cae en *Lo elegido se
  guarda* (`opciones.md`: default o *Falta*), con el aviso de que el paquete cambió. **El reemplazo
  deja en la versión el par viejo → nuevo** (*"Reemplazar material"* y la baja con reemplazo, en
  `bajas.md`; si en ese paquete el técnico puso otro, el par apunta a ese): si lo guardado es el viejo
  y la versión tiene el par, entra el nuevo como elegido. Los pares se encadenan (la orden de la v3
  fabricada con la v5 pasa por los de la v4 y la v5) y lo guardado no se toca. Por qué: con
  `ancho_hoja_izq` renombrado en la v5, las corredizas pisadas en 900 volvían al automático 925 sin
  *Falta*; con la Manija Roma dada de baja con reemplazo, las líneas quedaban sin precio aunque el
  catálogo sabía cuál era la otra, y el caso de prueba mostraba *→ Embutida* (el default) en vez de
  *→ Manija Roma II*. Descartado: una clave interna estable que la versión nueva copia (renombrar
  libre a cambio de una columna más y lo guardado ilegible, para algo cosmético).
- **El nombre del paquete lo corrige el técnico hasta la primera versión aprobada; después lo cambia
  administración** (2026-10-22), como mover (`ficha.md` → *La subcategoría la elige el técnico al
  crear*): cambia lo que buscan vendedores y ve el cliente, y las líneas sin enviar lo muestran
  (apuntan, no copian). No se repite en la subcategoría (índice único parcial `WHERE activo`); no es
  evento. Por qué: *Corrediza 2 hjoas* se corrige antes de venderse, y pasar a *Corrediza 2 hojas
  clásica* es una decisión comercial.
- **Duplicar crea un paquete nuevo con la v1 en borrador, copia de la versión que se mira**
  (2026-10-22). El técnico duplica la vigente, la abierta o una del historial; elige nombre y
  subcategoría. Copia todo lo de la versión (variables, grupos con hermandad y pares, materiales y
  fórmulas, servicios, restricciones) y los casos de prueba con el de referencia; no copia las
  excepciones de % (de administración y de ese paquete) ni el historial, que arranca en la v1 con
  *duplicado de Modena · Corrediza 2 hojas v4*. Se adapta con *"Reemplazar material"* sobre él solo y
  las fórmulas a mano; los controles corren al mandar. La copia queda independiente. Por qué: con la
  subcategoría como línea de perfiles, la Corrediza 2 hojas Herrero es la Modena con otros perfiles y
  se armaba de cero (9 variables, 22 materiales, hermanas y pares, 5 casos). Descartado: un paquete
  base del que heredan las líneas (una capa más, y su cambio movería varias sin aprobar cada una).
