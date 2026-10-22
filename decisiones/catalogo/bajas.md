# Catálogo — bajas y reemplazo

Qué pasa con paquetes, líneas y órdenes cuando se da de baja un insumo, una variante, un servicio o
una categoría, y cómo entra lo que lo reemplaza. La baja de una categoría, en `ficha.md`; la de un
color de la lista, en `colores.md`; lo que recibe producción, en `calculo.md` → *Para producción
entra lo vendido o error*.

- **Dar de baja es de administración, en las tres vistas**: dejar de vender es una decisión comercial.
  El técnico puede pedirlo, no hacerlo. Lo que el técnico descarta es un borrador (`versiones.md` →
  *El borrador se descarta*).
- **La baja depende de cómo se usa lo que se da de baja** (2026-10-21). *Incompleto* es uno de los
  casos: el paquete deja de venderse; se calcula (la vigente usa algo dado de baja), no se guarda; en
  el catálogo dice *falta reemplazar: Marco corrediza 70 mm*, y el vendedor y el cliente no lo ven.
  - Insumo como material fijo o condicional → incompleto.
  - Como alternativa, suelta o por subcategoría → solo ella deja de ofrecerse, y la línea sin enviar
    que la tenía elegida queda sin precio (*Lo que el catálogo deja de ofrecer deja la línea sin
    precio*); si era la última de la opción, incompleto, salvo *Sin material* (`opciones.md` → *Una
    opción puede tener "Sin material"*).
  - Variante de la ventana → en un material fijo o condicional, ese color no se ofrece; en una
    alternativa, ella no se ofrece en ese color (`colores.md` → *Las alternativas se filtran por
    color*); variante de herrajes → color base con aviso.
  - Servicio cargado en el paquete, fijo o condicional (Soldadura × 4, mano de obra extra si `alto` >
    2400) → incompleto.
  - Servicio aplicado por regla (general, categoría, subcategoría, excepción) o que trae un insumo
    (2026-10-21) → nada queda incompleto: deja de cobrarse al instante en todo lo que alcanzaba (la
    Modena de $ 600.000 pasa a $ 460.000 sin Comercialización; la Manija embutida entra sin
    Mecanizado de embutido). Sus reglas y los insumos que lo traen no se borran: reactivarlo vuelve a
    cobrar con los mismos.

  Reactivar devuelve a la venta lo que quedó incompleto por esa baja. Lo enviado no cambia y las
  órdenes siguen calculando el despiece de su versión. Por qué: lo que ya no se consigue no se cotiza,
  pero con *incompleto* para todo la baja de la Manija embutida sacaba de venta 15 corredizas que se
  venden con manija; y la regla de un servicio no está en la versión del paquete. Descartado: frenar la
  baja de un servicio con reglas activas (un freno más, y la confirmación ya muestra el alcance); y
  seguir vendiendo un paquete incompleto con aviso, salvo con el reemplazo en curso (*La baja de un
  insumo puede designar su reemplazo*).
- **Toda baja de algo en uso muestra el alcance antes de confirmar** (2026-10-21), deje o no algo
  incompleto: *Manija embutida: 3 paquetes dejan de venderse · 15 pierden una alternativa · 2 quedan
  solo con Sin herraje*; *Comercialización: se deja de cobrar en 120 paquetes y 40 insumos sueltos*.
  Suma los casos de prueba que quedan sin nada que ofrecer (*Lo que depende de medidas se resuelve en
  la línea*) y las versiones para aprobar que la usan (`versiones.md` → *Aprobar vuelve a correr los
  controles y el incompleto*). La baja no se frena. La de un insumo avisa al técnico con las mismas
  cifras y deja los paquetes marcados; la de un servicio no avisa (no es ente y no emite): el técnico
  ve marcados los incompletos.
- **Lo que depende de medidas se resuelve en la línea** (2026-10-22). El incompleto del paquete
  recorre solo combinaciones de opciones y color, que son finitas; una condición que lee una medida,
  directo o por una calculada, cuenta como que puede cumplirse, y su alternativa cubre. Si con las
  medidas de una línea una opción no tiene nada, la línea queda sin precio (*herraje hoja izq: nada
  que ofrecer con estas medidas*) y el paquete se sigue vendiendo. Para que no lo encuentre el
  vendedor, el alcance de una baja corre también los casos de prueba de los paquetes que la usan
  (*Corrediza 2 hojas Modena: caso grande — herraje hoja izq sin nada que ofrecer*). Por qué: con
  Manija Roma si `ancho_hoja_izq` ≤ 900 y la reforzada (> 900) dada de baja, saber si la hoja puede
  pasar de 900 pide propagar rangos por fórmulas con `max`, `si` y divisiones, que no se resuelve en
  general. Descartado: que la condición sobre medidas no cubra (saca de venta la corrediza entera por
  un tamaño que quizás nadie pide).
- **Lo que el catálogo deja de ofrecer deja la línea sin precio; lo que cambia la misma línea sigue
  *Lo elegido se guarda*** (2026-10-21). Presupuesto sin enviar con 6 corredizas en Laminado 3+3 y
  administración lo da de baja: las 6 quedan sin precio con el motivo (*Laminado 3+3: dado de baja,
  elegí otro vidrio*) y no se envían hasta que el vendedor elija. Vale para toda opción, vidrio o
  herraje, y para todo lo que viene del catálogo: baja del insumo o de su variante, el insumo que
  sale de la subcategoría, **o la versión nueva que lo saca de la opción o le suma una condición que
  lo deja afuera en esa línea** (2026-10-22): la v5 de la Modena saca Laminado 3+3 (*ya no se ofrece
  en este paquete (v5), elegí otro vidrio*); con *Laminado solo hasta 1200 de ancho*, las de 1500
  quedan sin precio y la de 1000 sigue. Con el par de un reemplazo entra el nuevo (`versiones.md` →
  *Lo guardado cruza versiones por nombre y por insumo*). Los casos de prueba siguen *Lo elegido se
  guarda* y se marcan (*Laminado 3+3 → Float 4 (ya no se ofrece)*): así administración ve qué deja de
  ofrecer la versión. Si lo causa la misma línea (saca la cámara, o cambia el color y PAN-01 no viene
  en blanco), sigue *Lo elegido se guarda* (`opciones.md`) —una principal sin default queda vacía— y
  volver atrás devuelve lo elegido. Lo enviado no cambia. Por qué: pasando solas al default, las 6
  bajaban de precio y se enviaban en Float 4 sin que nadie notara que el cliente pidió laminado; lo
  que hace el vendedor en su línea, en cambio, lo está viendo. Es lo que ya pasaba con el suelto, el
  color y el paño. Descartado: *Lo elegido se guarda* también para la baja.
- **La baja de un insumo puede designar su reemplazo, y lo reciben todos los paquetes que lo usan**
  (2026-10-21). Opcional (sin reemplazo rige *La baja depende de cómo se usa*) y de cualquier unidad
  (la felpa que pasa de ml a unidad no tenía salida y sus 20 paquetes quedaban incompletos al
  instante; el control de unidad ya frena cada borrador hasta corregir la fórmula). Lo elige
  administración, que da la baja. Cada paquete lo recibe en su versión abierta, como con
  *"Reemplazar material"*, con el qué cambió escrito (*reemplaza Hoja corrediza 40 mm por Hoja
  corrediza 42 mm (baja)*); el técnico revisa, corrige fórmulas —o en ese paquete pone otro— y manda a
  aprobar. Antes de confirmar se ve el alcance (*Hoja 40 → Hoja 42: 12 paquetes la reciben en su
  borrador*; con otra unidad, *las 12 fórmulas se corrigen a mano antes de mandar*). Sin desmarcar
  paquetes (2026-10-21): Laura, sin `catalogo_paquetes_editar`, decidía qué paquete salía de venta;
  qué se compra es de administración, cómo entra en cada paquete es del técnico. **No se aprueba
  solo**: lo que hay que corregir no se ve en las diferencias de los casos (HOJ-42 con 2 mm más de
  solape pide `+ 27` en `ancho_hoja_izq`; sin tocar la fórmula las piezas no cambian, y
  administración aprobaría hojas cortas). **Mientras la versión abierta tiene el reemplazo, la
  vigente se vende como si el viejo siguiera activo**, venga de la baja o de *"Reemplazar material"*.
  Lo vendido sobre la vigente se fabrica con la nueva (`calculo.md` → *Producción puede elegir con
  qué versión aprobada fabrica*); hasta aprobar se cotiza con el costo del viejo. Lo que el reemplazo
  cambia solo (más peso → rueda doble, un color que no tiene) se ve en los casos de prueba al mandar
  a aprobar y en pendientes. Descartado: aprobar las versiones al confirmar la baja (sin revisión
  técnica) y que dejen de venderse hasta aprobar (se pierden ventas en el medio).
- **La baja de un servicio también puede designar su reemplazo, para los paquetes que lo cargan**
  (2026-10-22). Administración elige otro de monto fijo, de cualquier unidad; cada paquete lo recibe
  en su versión abierta con el par viejo → nuevo y, mientras tanto, la vigente cobra como si el viejo
  siguiera activo, a su monto. *"Reemplazar material"* busca también servicios (servicio por servicio).
  Reglas e insumos que lo traen siguen *deja de cobrarse*, y el alcance los lista (*se deja de cobrar
  en 3 reglas · lo traen 2 insumos*): administración pasa las reglas, el técnico propone el cambio del
  insumo. Por qué: unificar *Soldadura de marco* en *Soldadura* dejaba 25 paquetes incompletos al
  instante y había que abrirlos de a uno. Descartado: mover las reglas solas al nuevo (chocan con las
  que ya tenga).
- **"Reemplazar material" es un solo botón de Paquetes: masivo, con los paquetes a elegir, y cada
  borrador se ajusta después a mano** (2026-10-21). Dos buscadores (material actual y nuevo) y la
  tabla de los paquetes que usan el actual, todos marcados: el técnico desmarca los que no quiere
  tocar y ve qué pasa en cada uno antes de confirmar. El nuevo puede ser de otra unidad (*La baja de
  un insumo puede designar su reemplazo*). Sin versión abierta, crea un borrador; con
  borrador, se suma a él; para aprobar, vuelve al borrador y se suma (aviso a administración). Si la
  versión abierta ya no usa el material, dice *ya no lo usa* y no se toca. El qué cambió va escrito
  (*reemplaza Marco corrediza 70 mm por Marco 72 mm*) y se suma al que hubiera; el par viejo → nuevo
  queda en la versión (`versiones.md` → *Lo guardado cruza versiones por nombre y por insumo*). Lo que
  el material nuevo obliga a cambiar en un paquete (una fórmula) se corrige en su borrador; después
  cada uno se manda a aprobar. El aviso de baja (*falta reemplazar: Marco corrediza 70 mm*) abre la
  misma ventana con el material actual cargado; la baja con reemplazo no la abre: lo pone en todos.
  Por qué: con una versión abierta por paquete, el reemplazo no puede crear otra. Descartado:
  saltear los que están para aprobar y avisar (queda a mano y, con la baja, el paquete queda
  incompleto).
