# Catálogo — la función de cálculo

Una sola función del catálogo evalúa las fórmulas de un paquete y devuelve lo que cada uno puede ver:
la llaman la prueba del técnico, Presupuestos, erp-cliente y Producción. Cómo se escriben las
fórmulas, en `motor.md`; cómo se arma el precio, en `precio.md`.

## El motor va en Postgres (2026-10-14)

**El precio lo calcula una función de Postgres `SECURITY DEFINER` que devuelve el precio y nunca el
costo a quien no ve costos.** A administración le da también las bases (*sobre $ 60.000*). RLS filtra
filas, no columnas: el vendedor no puede leer la tabla de costos, así que una función `INVOKER` no
podría calcular, y hacerlo en TypeScript exigiría `service_role`. Excepción explícita a `SECURITY
INVOKER`, acotada a esta función. Descartado: el motor en TypeScript del ERP viejo — más rico (reglas,
simulador, grafo), pero eso quedó para después.

**Monto, %, mínimo, reglas por categoría y excepciones por paquete van en tablas propias, como el
costo** (2026-10-14). `servicios` guarda solo lo que ve el técnico (nombre, unidad,
fijo/porcentual; sin marca de comercial: `servicios.md`); si el 15 % fuera columna de `servicios` o la excepción
columna de `paquetes`, el técnico los leería por API. Como la función de precio es `DEFINER` y salta
RLS, **verifica adentro quién llama** (*La función de cálculo decide qué parte ve cada uno*).
Descartado: una vista que oculte columnas — segunda puerta a la misma tabla, y un `select` olvidado
sobre la base filtra todo.

## Qué devuelve y a quién

- **Al presupuestador le sale el precio, nunca el costo ni el despiece.** El vendedor elige entre
  paquetes aprobados e insumos marcados sueltos; lo que esté sin aprobar no aparece.
- **Precio y despiece se habilitan por separado; avisos y plegado van a todos** (2026-10-21). La
  función devuelve cuatro partes: precio, avisos, plegado (*herrajes: negro · manija: plateado
  (no hay en negro)*) y despiece (piezas con largo y ángulos, medida de cada vidrio y por qué entró
  cada material). El vendedor ve precio, avisos y plegado; el cliente empresa, lo mismo, con precio
  solo si se lo habilitaron; el técnico en Probar y producción, todo menos el precio; administración,
  todo. Un aviso va tal cual aunque nombre una pieza (*Travesaño marco 6500 mm: más largo que la
  barra de 6000 mm*): el vendedor lo necesita para cotizar barra especial o empalme, y un largo
  suelto no muestra las fórmulas. Por qué: la versión del 14/10 de *El motor va en Postgres* daba el
  despiece a quien ve precios, y el vendedor ve precio sin despiece y producción despiece sin
  precio. Descartado: un texto sin la pieza para vendedor y cliente (cada aviso del sistema escrito
  dos veces).
- **La función de cálculo decide qué parte ve cada uno y qué versiones calcula, también fuera del
  catálogo** (2026-10-21). Mira los permisos del catálogo y los de los módulos que la llaman; cada
  uno suma su rama al construirse, como las de `entes`, y hoy existen las dos del catálogo. Con dos
  permisos se suman partes y versiones; sin ninguno, error.
  - `catalogo_paquetes_editar` (técnico, en Probar) → avisos, plegado y despiece de cualquier
    versión, borradores incluidos.
  - `catalogo_paquetes_administrar` → todo, de cualquier versión.
  - Vendedor, con el permiso de Presupuestos que arma líneas (se nombra al fichar Presupuestos) →
    precio, avisos y plegado, solo de la vigente de un paquete a la venta.
  - Producción, con su permiso de órdenes (al fichar Producción) → avisos, plegado y despiece de
    cualquier versión aprobada, aunque el paquete esté de baja.
  - Cliente empresa, por su empresa (al fichar erp-cliente) → avisos y plegado de la vigente en lo
    que tiene habilitado, y el precio si se lo habilitaron.

  Con la Corrediza 2 hojas (v3 aprobada, v4 vigente, v5 en borrador): el vendedor pide 1500 × 1100
  sobre la v4 y recibe $ 600.000, avisos y plegado, sin despiece; la v5 por API le da error.
  Producción pide la orden hecha con la v3: despiece y avisos, sin precio. El técnico prueba la v5:
  todo menos el precio. El mismo permiso le abre al vendedor y al cliente lo que eligen —lo que está
  a la venta y las opciones de cada paquete (medidas, alternativas, colores)— por funciones
  del catálogo, sin fórmulas; nunca las tablas. Por qué: qué versión calcula cada uno sale de reglas
  del catálogo (vigente, a la venta, incompleto, habilitación); si cada módulo envolviera la función
  con su permiso, Presupuestos tendría que saber qué está a la venta y la regla quedaría en dos
  lugares. La lista la escribe una vez el módulo del ente (`decisiones/global/entes.md` → *Ver un
  registro no es trabajarlo*). Descartado: una vista del catálogo para el vendedor (le aparece un
  módulo que no usa, y no hay función sin vista).

## Despiece y producción

- **El despiece no se guarda: se calcula cuando se pide.** Quien lo usa guarda solo las entradas
  (paquete y lo que cargó el vendedor: medidas y pisadas, opciones, hermanas juntas o separadas,
  colores, grupos opcionales) y pide el despiece al catálogo. Una sola función del
  catálogo evalúa las fórmulas: la llaman producción, el presupuestador (para el precio) y la prueba del
  técnico. Si cada módulo evaluara por su cuenta, la regla viviría en dos lugares. Consecuencia: una
  fórmula aprobada no se edita (`versiones.md`).
- **Producción puede elegir con qué versión aprobada fabrica**, no solo con la que se vendió. El catálogo
  le ofrece solo las versiones aprobadas del paquete y calcula el despiece de la que elija. Cambiar de
  versión cambia los materiales, no el precio: el precio es del presupuesto. Por eso cada versión dice qué
  cambió, obligatorio al mandarla a aprobar ("v2: agrega burlete inferior en la hoja").
- **Producción usa una versión solo si cubre lo vendido** (2026-10-22): toda medida, opción y grupo
  guardado en la orden existe en ella (por nombre) y toda principal sin default suya tiene valor
  guardado; lo secundario nuevo entra con su default (el burlete de la v4, la mejora por la que se
  elige). El catálogo da, para una orden, sus versiones aprobadas con cuál cubre y por qué no las
  otras (*v5: falta alto_banderola · no tiene mosquitero*), y producción ofrece solo las que cubren.
  La vendida siempre cubre; sus bajas, en *Para producción entra lo vendido o error*. Por qué: la
  orden de la v3 con mosquitero, fabricada con la v5 (banderola principal sin default, sin
  mosquitero), salía con *Falta* o un alto inventado y sin el mosquitero que pagó el cliente.
- **Para producción entra lo vendido o error, nunca otro insumo** (2026-10-22). Si la versión que
  elige producción tiene la alternativa guardada, entra aunque el insumo, su variante o el color de la
  lista estén de baja, y el despiece lo marca (*Manija Roma negra (de baja)*): dar de baja es dejar de
  vender, no de fabricar lo vendido. Si no la tiene (la v5 la sacó, o el insumo se movió a una
  subcategoría que la opción no ofrece), el despiece da error con lo que falta (*v5 no ofrece Manija
  Roma en herraje hoja izq*), sin default ni primera; cómo lo resuelve producción, al ficharla. Los
  pares de reemplazo de la versión elegida valen (`versiones.md` → *Lo guardado cruza versiones por
  nombre y por insumo*). Es una rama de la función de cálculo. Por qué: la orden de julio con Manija
  Roma, dada de baja en septiembre, se despiezaba con la Embutida del default; en el presupuesto lo
  frena la línea sin precio, en la orden nada.
