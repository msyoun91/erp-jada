# Catálogo — precio

Cómo sale el precio de lista de una abertura o de un insumo suelto, y qué pasa cuando falta un dato.
Lo calcula la rama de plata de la función de cálculo (`calculo.md`), que va en el SQL después de
Compras mínimo (`ficha.md` → *El catálogo no apunta con FK a otro módulo*).

## Precio de venta

```
Insumo        cantidad (técnico, fija o fórmula) × (1 + desperdicio del insumo) × costo de reposición
              (Compras) → a pesos, oficial BNA venta
Servicio fijo cantidad (técnico) × monto (administración)
Por insumo    cantidad puesta del insumo (sin desperdicio) × lo que lleva por unidad (técnico) × monto
              (administración) — ver servicios.md → *Un insumo puede traer sus servicios*
Servicio %    % (administración) × suma de insumos de su grupo, sin las categorías marcadas fuera del %;
              mínimo (administración, opcional) una vez por servicio en el paquete, sobre la suma de
              sus grupos
Por categoría % (administración) sobre los insumos que alcanza, sin mínimo; gana la regla más específica
              (ver servicios.md → *Servicios por categoría*)
Precio        insumos + servicios, de una abertura — lo pide Presupuestos con las medidas de la línea
Línea         precio × cantidad (de la línea, nunca de las fórmulas)
Descuento     no es de Catálogo: va en Presupuestos (BACKLOG.md), sobre el precio de lista
```

- **No hay margen:** el precio de venta es insumos a costo + servicios. La ganancia está en los
  servicios comerciales. Confirmado al comparar con la v2 (2026-10-14), que había propuesto un margen
  de administración.
- **El costo sigue fuera del catálogo, en Compras.** El costo de reposición (lo que costaría
  comprarlo hoy) vive en Compras, con su moneda (ARS, US$, €) e historial; Compras lo carga allá
  (`ficha.md` → *Compras no usa el catálogo*) y el catálogo lo lee para calcular. El técnico no ve
  plata.
- **El costo se carga como se cotiza y el sistema lo pasa a la unidad del insumo** (2026-10-14).
  Compras dice por qué es el monto: por unidad del insumo ($ 5.000 / ml), por presentación
  ($ 30.000 / barra → ÷ 6 = $ 5.000 / ml) o por kg ($ 8.000 / kg × 0,85 kg/ml = $ 6.800 / ml). Para
  eso **la presentación lleva su contenido en la unidad del insumo** (barra = 6 ml, caja = 100
  unidades). La pantalla muestra la conversión; si falta el dato (por kg con peso 0) queda sin
  costo (*Sin costo no es $ 0*). El costo por kg es de cada variante de color (el negro mate no vale
  lo que el natural). Por qué: la barra cargada como ml cobraba 6× el perfil, y el $/ml hecho a mano
  queda viejo cuando cambia el kg.
- **Sin costo no es $ 0: la línea queda sin precio** (2026-10-14). El costo de un insumo (Compras) o el
  monto de un servicio (administración) puede faltar, pero no vale 0: un 0 se rechaza. Si en la línea
  entra algo sin costo, el motor no da precio y dice qué falta (*sin precio: falta costear Rueda
  doble*); cuenta solo lo que entra (con hojas de hasta 40 kg va la simple y hay precio). El presupuesto
  se arma igual pero no se envía con una línea sin precio. Compras y administración ven la lista "sin
  costo y en uso" con los paquetes donde está (*Lo que falta costear se ve en filtros*). Por qué: con
  $ 0 la corrediza de hojas pesadas salía sin la rueda doble y el precio parecía normal. Descartado:
  no ofrecer lo que no tiene costo (el vendedor no sabe por qué falta) y avisar cobrando $ 0.
- **El 0 se rechaza donde vacío es "falta"; en reglas y excepciones vale, y el mínimo vacío es sin
  mínimo** (2026-10-22). Se rechaza en el costo del insumo, el monto de un servicio fijo y el % propio
  de un porcentual cargado en un paquete. Una regla o excepción nunca falta (sin ella rige la de
  arriba), así que su 0 es a propósito: *Corrediza económica: Comercialización 0 %*, *Vidrios → Float
  0 %*. El mínimo de un porcentual es opcional: es un piso, no parte del precio; vacío es sin mínimo y
  el 0 no se acepta (una sola forma de decirlo). Por qué: el 0 % de la económica tenía que cargarse
  como 0,01 %, y un mínimo leído como "falta" dejaba sin precio toda línea con mano de obra. Por regla
  no hay mínimo (`servicios.md` → *Servicios por categoría*).
- **Lo que falta costear se ve en filtros, y lo que entra sin plata se marca al aprobar**
  (2026-10-21). En Compras, la lista *sin costo y en uso*, con dónde se usa cada insumo (*Rueda
  doble — 3 paquetes: Corrediza 2 hojas, Corrediza 3 hojas, Puerta corrediza*; *Burlete 9 mm gris
  — 1 paquete · se vende suelto*). En uso es lo que se vende hoy: la vigente de un paquete activo o el
  insumo suelto. El dónde se usa lo da una función del catálogo, la misma del alcance de la baja, y
  Compras la lee. Administración tiene el mismo filtro en Insumos (`catalogo_insumos_administrar`,
  que ya ve costos) y *sin monto* en Servicios (`catalogo_servicios_administrar`: *Mecanizado de
  embutido · sin monto · 3 paquetes*); el técnico no ve ninguno. En pendientes se marca lo que entra
  sin plata (*entra Rueda doble (sin costo) · Mecanizado de embutido (sin monto)*), sin frenar
  la aprobación: el freno es la línea sin precio, que no se envía. Por qué: con el caso de referencia
  en hojas livianas, la v4 se aprobaba con precio normal y el faltante lo encontraba el vendedor dos
  semanas después. Son filtros de vistas que ya existen: ni vista ni función nueva.
- **Los cambios de plata de administración rigen al instante, sin aprobación**: montos, %, mínimos,
  suelto y cómo se vende. El catálogo calcula siempre con los valores de hoy; cuándo se
  congela el precio de un presupuesto lo decide Presupuestos. Cada cambio queda registrado (quién,
  cuándo, valor anterior y nuevo).
- **Un presupuesto enviado se mantiene o se actualiza; actualizar vuelve a la vigente** (2026-10-21).
  Un cambio de costo (Compras) o de % no lo toca solo. Mantener deja el precio enviado entero, con
  los costos y % de entonces: la Corrediza sigue en $ 600.000 porque hay sobrante comprado al costo
  viejo. Actualizar es como si la línea no se hubiera enviado: la vigente con costos y % de hoy (v3
  → v4, $ 667.250, con el aviso del técnico); si el paquete salió de venta, queda sin precio hasta
  reemplazarlo. Sin mezcla (costo viejo con % nuevo). La función no cambia: el vendedor calcula solo
  la vigente, la línea mantenida no se recalcula (lleva su precio copiado y su versión) y producción
  despieza esa versión aunque el paquete esté de baja (la Banderola con sobrante del perfil
  discontinuado). Descartado: la versión enviada con plata de hoy (v3 a $ 653.750): cotiza lo que
  el catálogo ya no vende, con el último costo de algo que ya no se compra. Por línea o entero, y
  quién puede mantener, al fichar Presupuestos (`BACKLOG.md`). Sin versiones de %, costos ni
  cotización: la línea guarda su precio, y si se quiere ver de dónde salió, una foto completa al
  enviar, con la cotización del día (`BACKLOG.md` → Presupuestos). Recalcular lo enviado por fecha
  pedía versionar las tres cosas y un motor que calcule igual que entonces.

## Cotización

Oficial BNA venta de USD y EUR, automática con corrección manual (como `erp_old`: dolarapi,
ventana 10–15 h, cierre del día, lo manual no lo pisa el automático ese día; `erp_old_2`: monedapi.ar).

- **La cotización vale por su fecha del BNA: advertencia a los 3 días, sin precio a los 5**
  (2026-10-22). Cada cotización guarda la fecha del BNA, no la de cuando se trajo; lo manual corrige
  la de un día y vale ese día (al siguiente el automático escribe la suya). La función de cálculo, en
  su rama de plata, mira la fecha: con más de 3 días corridos da el precio con advertencia
  (*cotización USD del 14/08, hace 4 días*); con más de 5, lo de esa moneda queda sin precio con el
  motivo (*sin precio: cotización USD del 14/08*), como *Sin costo no es $ 0*. Las dos se ven en
  Probar con plata y en la línea; lo enviado no cambia. Aparte, si el automático falla —no responde,
  o lo que trae tiene más de 3 días—, avisa a administración: es de Compras, al ficharlo, porque el
  proceso es el único que sabe que falló. Por qué: la manual de agosto ($ 1.320) seguía valiendo en
  octubre ($ 1.450), y un automático caído o congelado cotizaba con la de hace semanas sin decirlo:
  $ 180.000 abajo en las 4 Corredizas. La advertencia sola no alcanza: Probar con plata corre al
  aprobar, y la línea la ve el vendedor, que no la arregla (como el 34 de la auditoría v2). Días
  corridos y no hábiles para no llevar feriados; 5 cubre Semana Santa (miércoles → lunes).
  Descartado: la última sin aviso, y sin precio desde el primer día sin cotización (frena a los
  vendedores cada lunes antes de las 10 h).
- **La cotización es una vista de Compras, no un módulo** (2026-10-14). Una tabla, una pantalla y una
  persona (administración la corrige); Compras es dueño de los costos en moneda extranjera y Catálogo y
  Presupuestos solo la leen, como leen el costo. Si crece (más monedas, índices), se separa.
