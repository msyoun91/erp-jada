# Monedas

**Los tipos de cambio son un módulo propio, fuera del catálogo (2026-10-29).** El catálogo los lee para
convertir costos y precios (`decisiones/catalogo.md` → *Moneda*), y Compras los va a leer de acá. Las
decisiones de abajo se tomaron en el catálogo (2026-10-27 y 2026-10-29) y se mudaron sin cambios de
fondo.

## Ficha del módulo

Sin armar: objetivo y personas por preguntar (`GUIDE_MODULO_NUEVO.md`, paso 0).

Pendientes:
- **Cuándo se traen y el aviso de 7 días**: hoy los pide solo el primer presupuesto del día, así que
  una semana sin presupuestos da "dólar sin actualizar hace 7 días" aunque MonedAPI tenga el de hoy.
  Propuesta sin decidir: el primer uso del día, un presupuesto o quien puede corregirlos abriendo sus
  avisos.

## Tipos de cambio (2026-10-27)

**Los tipos de cambio salen de MonedAPI, en venta: dólar oficial (`monedapi.ar/api/v2/usd/oficial`) y
euro oficial (`/api/v2/eur/bna`, el único euro que tiene).** El enum `moneda` ya existe (Obras: ARS ·
USD); se le suma EUR.

Para recalcular se usa la copia guardada, nunca MonedAPI: si el servicio desaparece, los presupuestos
viejos se siguen recalculando. Sin clave ni registro; el euro puede quedar días sin actualizarse
(el 2026-10-27 seguía el del 20/10).

**Se traen cuando hacen falta, sin cron: el primer presupuesto del día los pide a MonedAPI y guarda lo
que trae; el resto del día usa eso.** Si no responde, se usa el último guardado. Cada valor vale desde
que se guardó, no desde el día: el que se guarda a las 11:00 no cambia un presupuesto de las 09:40
hecho con el de ayer.

**Administración puede corregir uno a mano, y lo de MonedAPI entra solo si es más nuevo.** Cada valor
guarda su fecha: la que dice MonedAPI (`updatedAt`) o la de la carga a mano, y se muestra con ella
("euro $1.780, del 20/10"). Así el euro del 20/10 que MonedAPI sigue dando no pisa una corrección del
27/10, ni suma una fila igual cada día.

**Los tipos de cambio tienen los tres niveles del costo (`decisiones/catalogo.md` → *Versiones y
aprobación*) (2026-10-29).** A mano, el rojo pide confirmación: $17.800 en vez de $1.780 multiplicaba
por 10 todo lo que cuesta en euros, sin color ni aviso. Lo de MonedAPI en rojo (50 % o más) no entra
solo: se sigue usando el último guardado y Administración recibe un aviso para confirmarlo o
corregirlo; confirmado, vale desde la confirmación. Amarillo y naranja entran y quedan marcados. Si
MonedAPI cambia el formato y da el dólar como 1,45, nada sale a precio de regalo. Costo aceptado: en
una devaluación de verdad (diciembre de 2023, el oficial más que se duplicó en un día) el dólar nuevo
no rige hasta que Administración lo confirma, y mientras tanto se presupuesta con el viejo.

**Lo de MonedAPI lo pide y lo guarda el servidor, nunca el navegador de quien presupuesta
(2026-10-29).** Lo dispara un vendedor o un cliente, pero el número no pasa por sus manos: si la base
aceptara el valor que manda el navegador, cualquiera guardaba un dólar inventado.

**Si un tipo de cambio lleva 7 días sin actualizarse, se le avisa a quien puede corregirlo.** Es
estado, no evento: se calcula al mirar, sin cron (`decisiones/global/infra.md` → *Evento es fila,
estado es consulta*).
