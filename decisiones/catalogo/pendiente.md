# Catálogo — pendiente

## Choques entre v1 y v2 (2026-10-22) — resolver de a uno, en orden

Al pasar a carpeta, lo que la v1 (2026-10-14) y la v2 (2026-10-21) decían distinto sin que una
reemplazara a la otra. Cada uno está marcado con ⚠ donde aparece. Se resuelven antes del SQL sin plata.

Resueltos (el texto del choque, en git): **1. Secundaria sin default** (2026-10-22) → la opción toma
la primera y solo frena la medida: `opciones.md` → *Una medida secundaria lleva default; una
principal, no*; el orden de las alternativas, en `versiones.md` → *Cuenta como cambio*. **2. Mínimo
de un porcentual por regla** (2026-10-22) → por regla no hay mínimo: `servicios.md` → *Servicios por
categoría*.

3. **El máximo de la medida y la restricción que frena.** *Toda medida del vendedor lleva mínimo y
   máximo* (`opciones.md`, 2026-10-22) dice: "las restricciones quedan para avisos y combinaciones;
   un 'no aguanta más de 2400' es el máximo del ancho". Fuera de rango, el mensaje es el típico
   (*ancho entre 600 y 3000 mm — cargaste 150: ¿en cm?*). Pero la v1 define la restricción como
   "mín./máx. de una variable con su mensaje" (`motor.md` → *Qué es un paquete*), y *Lo imposible
   deja la línea sin precio* (`motor.md`) da como ejemplo de restricción que frena *Corrediza económica: más de 2400
   de ancho el perfil no aguanta, usar reforzada*. Y *Cuenta como cambio* (`versiones.md`) usa
   *Restricciones: ancho máx. 2400 mm · frena → avisa*. Caso: como máximo del ancho, la Corrediza
   económica de 2500 dice *ancho entre 600 y 2400 mm*, y se pierde el *usar reforzada* que el técnico
   escribió para el vendedor. Propuesta: el máximo y el mínimo pueden llevar un mensaje del técnico,
   que se suma al típico (*ancho entre 600 y 2400 mm · más de 2400 el perfil no aguanta, usar
   reforzada*). Los dos ejemplos pasan a una combinación (*ancho × alto > 4 m²: la hoja no aguanta*) y
   al máximo (*Medidas: ancho máx. 2400 → 3000 mm*).
4. **`servicios.comercial` sin regla que lo use.** *El motor va en Postgres* (`calculo.md`) lista lo
   que guarda `servicios`: nombre, unidad, fijo/porcentual y *comercial*. La v1 separa los comerciales
   (comercialización, manipulación) de los demás servicios. Desde *No hay margen* y *Servicios por
   categoría*, ninguna decisión lee esa marca: un comercial es un porcentual por regla como cualquier
   otro. Caso: el técnico marca *Comercialización* como comercial, o se olvida, y no cambia nada.
   Propuesta: sacar la columna; "comercial" queda como forma de hablar. Si sirve para algo (¿el
   cliente con precio no ve los comerciales separados?), decirlo.
5. **Los controles de mandar a aprobar están repartidos.** A la lista de *Mandar a aprobar frena*
   (`versiones.md`) le faltan tres frenos que se decidieron en otras decisiones:
   - sin caso de *referencia* (*Los casos de prueba corren cuando alguien los mira*);
   - sin el texto de qué cambió (`calculo.md` → *Producción puede elegir con qué versión aprobada
     fabrica*: "obligatorio al mandarla a aprobar");
   - incompleto: *Aprobar vuelve a correr los controles y el incompleto* lo da por corrido al mandar.

   Caso: Marcos manda la v5 de la Corrediza con la Felpa X, que ya está de baja. ¿Se manda y la frena
   Laura al aprobar, o no se manda? Propuesta: *Mandar a aprobar frena* tiene la única lista y suma
   los tres; al mandar, lo incompleto frena igual que al aprobar.

## Auditoría v2 (2026-10-21) — lo que queda

Sobre la ficha v2 y lo de la v1 que sigue valiendo. Caso base: Corrediza 2 hojas Modena 1500 × 1100,
negro mate, DVH 4+12+4, 4 iguales; Marcos es técnico y Laura, administración. Cada punto: el caso que
falla y una propuesta a discutir, no decidida. Orden (2026-10-21): primero lo que cambia tablas,
triggers o la función de cálculo (todo resuelto el 2026-10-22, *Resueltos* abajo); después lo que entra
con Compras mínimo y la rama de plata; al final lo que se resuelve en la pantalla. Los números no
cambian: los usan los escenarios y las referencias entre puntos.

*Con Compras mínimo y la rama de plata*

19. **IVA.** No aparece en ninguna decisión. Si Compras carga una cotización con IVA y otra sin, unos
    insumos salen 21 % arriba. Propuesta: costo neto (al fichar Compras), precio del catálogo neto, el
    IVA en Presupuestos.
34. **Compras no se entera.** Lo que falta costear está en un filtro; si nadie lo abre, lo encuentra el
    vendedor. Propuesta: al aprobarse una versión que trae algo sin costo, aviso a Compras (su rama, al
    ficharlo).

*Con las pantallas: no cambian tablas*

29. **Lo que se avisa una vez.** Incompleto por una baja, *solo ofrece Sin herraje*, *Laminado 4+4: no
    se ofrece en 12 paquetes* (solo si abre el insumo), el reemplazo sin mandar
    (31), el borrador viejo (32): una campanita y después nada. Propuesta: filtro *a revisar* en
    Paquetes e Insumos, calculado al leer, como el "a revisar" de las plantillas de Tareas. Sin tabla ni
    trigger.
31. **El reemplazo que nunca se manda.** Marcos reemplaza en 12 paquetes y manda 9. Las otras 3
    vigentes siguen "como si el viejo siguiera activo", sin plazo: al último costo de algo que ya no se
    compra, y producción solo tiene versiones aprobadas, que usan el viejo. Propuesta: marca *a revisar*
    con antigüedad y aviso a administración a los N días.
44. **El trabajo especial.** "Pasa por el técnico", sin decir cómo: la corrediza económica de 2500 frena,
    va como renglón libre y producción recibe una línea sin despiece. Propuesta: decidir si es un
    paquete especial (¿subcategoría sin clientes?) o queda fuera, y decirlo.
35. **El cliente lee los mensajes del técnico.** Las restricciones se escriben pensando en el vendedor
    (*usar reforzada, deja más margen*) y el cliente empresa las ve tal cual. Propuesta: el editor dice
    "lo ven vendedor y cliente".
54. Al cliente con precio, el motivo *falta costear Rueda doble* es interno: *lo cotiza tu vendedor*.
55. `/catalogo/paquetes/{id}` abre la vigente: sin aprobada, la abierta.
56. La calculada declarada unidad acepta cualquier fórmula: `fijaciones_jamba = alto` (sin `/ 600`)
    pasa y da 1100 grampas. Probar marca lo que va por unidad y da más de 100 por abertura.
50. "ml" también se lee mililitro: la silicona cargada pensando en el cartucho de 300 ml cobra metros
    de cordón como mililitros. La pantalla dice "m lineal".
57. Color nuevo, categoría nueva, pedir una baja: el técnico lo pide "por fuera". Es un pedido de
    Tareas; decirlo.
58. Para Presupuestos: la línea sin enviar cuyo precio cambió desde que se cargó (el cliente ya escuchó
    $ 600.000) muestra antes → después al enviar. La pisada que queda al cambiar el ancho es riesgo
    aceptado (`opciones.md` → *Una medida del vendedor puede traer un valor por defecto*).

*Escenarios* — encadenan varios puntos; sirven de base para los tests del SQL.

- **Línea Herrero nueva.** Laura crea las subcategorías que pide Marcos (57); Marcos carga 16 insumos,
  dos sin peso y uno sin desperdicio (12, 13), arma la corrediza de cero (36), duplica la hoja y la
  central queda sin hermanar (25), pone *laminado si superficie > 2* (20); Laura aprueba y nadie avisa a
  Compras (34): el vendedor encuentra 16 sin costo.
- **Aluar discontinúa la Hoja 40.** Laura la da de baja con la 42 (7, 8); uno de los 12 tiene la v5 a
  medias de Marcos (32); Marcos manda 9 (31); llega a producción una orden de la v3 (26, 27).
- **La felpa pasa a unidad.** Insumo nuevo, baja del viejo, reemplazo de otra unidad (7, 49).
- **La puerta blanca.** Paño bajo en PAN-01 y el cliente la pide blanca (5); se da de baja el blanco en
  la lista y se reactiva (40); se dan de baja las manijas (30).
- **Seis meses de inflación.** Montos fijos de marzo (17), cotización manual de agosto (18), presupuesto
  armado en septiembre y enviado en octubre (58).
- **Corrediza 3 hojas.** Pares Manija ↔ Embutida (24), hoja central duplicada (25), travesaños
  intermedios por fórmula (51), laminado solo en hojas grandes (23).
- **Un tipeo.** 80 de desperdicio, 8,5 kg/ml, `2.400` en una casilla (11, 20).
- **Se unifica Soldadura.** Baja de un servicio en 25 paquetes y cambio de unidad de otro (16, 37).
- **Constructora duplicada.** Contactos la fusiona y el portal deja de ver Ventanas (45).

*Resueltos* — dónde quedó cada uno (el texto del punto, en git y en `obsoletos/backup-docs-2026-10-22/`).

| Nº | Punto | Decisión |
|---|---|---|
| 1 | Quién carga el costo | `precio.md` → *El costo sigue fuera del catálogo, en Compras* |
| 2 | ¿El paquete dice qué colores ofrece? | `colores.md` → *Los colores son de administración* |
| 3 | "Material que mira el peso y suma al peso" en los controles | sacado; lo cubre el ciclo (`motor.md` → *Nada depende de sí mismo*) |
| 4 | "Lo que apunta a sus versiones se sigue calculando" | `versiones.md` → *El estado es de cada versión del paquete* |
| 5 | Una principal sin default que deja de ofrecerse | `opciones.md` → *Lo elegido se guarda*; `bajas.md` → *Lo que el catálogo deja de ofrecer* |
| 6 | Ancho y alto sin default que nadie hace cumplir | `opciones.md` → *Una medida secundaria lleva default; una principal, no* |
| 7, 8 | El reemplazo: otra unidad y quién lo decide | `bajas.md` → *La baja de un insumo puede designar su reemplazo* |
| 9 | El catálogo sí depende de Compras | `ficha.md` → *El catálogo no apunta con FK a otro módulo* |
| 10 | Menores de texto | corregidos en su lugar |
| 11 | Editar el insumo cambia precio y despiece al instante | `insumos.md` → *Lo que cambia el cálculo de un insumo en uso espera a administración* |
| 12 | Peso que falta | `insumos.md` → *El peso es del insumo y condiciona herrajes* |
| 13 | Desperdicio vacío | `insumos.md` → *El desperdicio es un % del insumo* |
| 14, 15 | Servicio que trae un insumo: otra unidad, doble cobro | `servicios.md` → *Un insumo puede traer sus servicios* |
| 16 | Unidad y tipo de un servicio en uso | `servicios.md` → *El servicio se edita directo* |
| 17 | Montos fijos y mínimos que envejecen | `servicios.md` → *Servicios muestra hace cuánto cambió cada monto* |
| 18 | Cotización pegada | `precio.md` → *La cotización vale por su fecha del BNA* |
| 20 | Casillas en otra unidad | `motor.md` → *El valor de la casilla se carga en la unidad en que se piensa* |
| 21 | Medida sin límites | `opciones.md` → *Toda medida del vendedor lleva mínimo y máximo* |
| 22 | Vidrio sin medidas | `opciones.md` → *El vidrio cobra por una variable de superficie* |
| 23 | Hermanas juntas que no van iguales | `opciones.md` → *Las opciones hermanas arrancan juntas* → *Si el par no se ofrece* |
| 24 | Pares con tres hojas | `opciones.md` → *Los pares van solo entre dos hermanas* |
| 25 | "Duplicar grupo" no copia la hermandad | `motor.md` → *"Duplicar grupo" pide qué reemplazar* |
| 26 | Producción no puede caer en *Lo elegido se guarda* | `calculo.md` → *Para producción entra lo vendido o error* |
| 27 | Producción elige una versión con otras entradas | `calculo.md` → *Producción usa una versión solo si cubre lo vendido* |
| 28 | Clase de color y color base editables | `colores.md` → *Clase de color y color base quedan fijos* |
| 30 | Sin herraje en silencio | `opciones.md` → *Una opción puede tener "Sin material"* |
| 32 | Un borrador abandonado bloquea el paquete | `versiones.md` → *El borrador se descarta* |
| 33 | ¿A qué técnico? | `ficha.md` → *Los avisos van a quienes tienen la función* |
| 36 | Duplicar paquete | `versiones.md` → *Duplicar crea un paquete nuevo* |
| 37 | Reemplazar o dar de baja un servicio | `bajas.md` → *La baja de un servicio también puede designar su reemplazo* |
| 38 | Mover un insumo de subcategoría | `ficha.md` → *La subcategoría la elige el técnico al crear* |
| 39 | Dar de baja una categoría con cosas adentro | `ficha.md` → *Una categoría o subcategoría con ítems activos no se da de baja* |
| 40 | Un color de la lista dado de baja y reactivado | `colores.md` → *Los colores son de administración* |
| 41 | Renombrar el paquete | `versiones.md` → *El nombre del paquete lo corrige el técnico* |
| 42 | Aprobar lo que ya no se vende | `versiones.md` → *Aprobar vuelve a correr los controles y el incompleto* |
| 43 | La versión nueva que saca una alternativa | `bajas.md` → *Lo que el catálogo deja de ofrecer* |
| 45 | Clientes fusionados o que no se ven | `clientes.md` → *Las habilitaciones siguen a la empresa que queda al fusionar* |
| 46 | "Con condición no salva al paquete" no se calcula en general | `bajas.md` → *Lo que depende de medidas se resuelve en la línea* |
| 47 | Grafo de ciclos | `motor.md` → *Nada depende de sí mismo* |
| 48 | Eventos | `ficha.md` → *Versión y cambio de cálculo emiten con trigger propio* |
| 49 | Qué guarda "lo elegido" | `versiones.md` → *Lo guardado cruza versiones por nombre y por insumo* |
| 51 | Cantidad de piezas por fórmula | `motor.md` → *La cantidad de piezas lleva el redondeo escrito* |
| 52 | 0 % y mínimo de un porcentual | `precio.md` → *El 0 se rechaza donde vacío es "falta"* |
| 53 | Material por piezas sin presentación | `motor.md` → *Una pieza más larga que la barra da aviso* |

La auditoría del 2026-10-14 (30 puntos) quedó resuelta entera antes de la v2; sus decisiones están en
los archivos por tema.
