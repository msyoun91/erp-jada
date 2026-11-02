# Catálogo — El despiece y las fórmulas

## El despiece calculado (2026-11-02)

**El despiece y el precio salen de un solo cálculo. Para un paquete con sus medidas y elecciones,
devuelve una fila por material (pieza, insumo elegido, color, medida, cantidad y total), todas las
variables, con el peso y el espesor de cada pieza, y los mensajes de alerta y bloqueo.** Con dos
cálculos, un arreglo en uno solo cobraba 4 bisagras y mandaba a cortar 3. La pestaña Paquetes ya
prometía el despiece, así que hace falta desde el primer día y no recién con Producción. Salen todas las
variables porque el que curva el perfil necesita el radio (1.000), no solo los 1.287 mm.

**Cada variable lleva la marca "pasa a Producción": por defecto pasan todas y Técnica destilda las que no
sirven, también el peso y el espesor de cada pieza (2026-11-02).** Olvidar destildar da un dato de más; si
hubiera que tildarlas, faltaba el radio. Es parte de la versión. Solo ordena lo que le llega al módulo
Producción, no protege: en la pestaña Paquetes se ven todas, para revisar las fórmulas, y ninguna trae
costos. Las filas de materiales llegan todas.

**Con un bloqueo, el despiece sale igual, con el mensaje, y el precio no da número.** Técnica ve qué dio
la cuenta que frenó el paquete, y nadie cotiza con él.

**Si una cuenta no se puede hacer, una medida da 0 o negativa, o una cantidad da negativa, sale "No se
puede calcular con estas medidas", sin filas ni precio. No se configura (2026-11-02).** Con alto 30 en
vez de 300, el vidrio de −18 mm bajaba el precio si Técnica olvidaba la condición, y flecha 0 divide por
cero. Quien ve el despiece lee cuál falló ("Vidrio: la medida dio −18 mm"); el vendedor, solo el mensaje.
Lo demás lo resuelve lo que ya existe: condiciones como `alto < 300` y `flecha > ancho / 2` (con flecha
800 la cuenta da un número válido: para la base no es un error) y `redondear_arriba` para las 1,7
bisagras. Una cantidad 0 es que no lleva: sin fila. Se descartó bloquear las cantidades con decimales:
el medio pomo se puede cobrar.

**Primero se calcula la cantidad: si da 0, el material no tiene fila y no se evalúan ni su medida ni sus
condiciones, como una opción no elegida. Lo mismo vale para una pieza con cantidad 0 y lo que tiene adentro
(2026-11-02).** Un vidrio superior con cantidad `si alto > 2100 entonces 1 si no 0` y alto `alto − 2100`,
con alto 2.000, daba −100 y frenaba la puerta en toda medida normal. Quien usa ese material desde otra
fórmula recibe 0: si eso deja otra medida en 0, sigue sin poder calcularse, y un Contravidrio superior con
medida `[Vidrio superior]` lleva el mismo "si" en su cantidad. Con cantidad mayor que 0, una medida de
−18 mm sigue frenando el cálculo.

**La cuenta no se redondea: filas, servicios en % y conversiones llevan todos sus decimales. Se redondea
solo el precio final de cada paquete y el renglón del mínimo por presupuesto: en pesos a entero, en USD a
2 decimales (2026-11-02).** Presupuestos multiplica ese precio por la cantidad: 3 ventanas de $242.309,28
dan 242.309 × 3 = $726.927, y no $726.927,84, que el cliente no puede sacar con la calculadora. En el
despiece el redondeo es solo para mostrar: 666,67 mm se lee 667 mm, y un vidrio de 1,675 m2 se lee 1,68
pero se cobra por 1,675; para cobrar o cortar la medida redonda está `redondear_arriba`. Costo aceptado:
en el detalle del gerente, las filas redondeadas pueden diferir del total en $1.

**Cada uno recibe una parte de ese cálculo.** Con la vista Paquetes, las filas sin costos. Con
`catalogo_aprobar`, además el detalle económico: el costo como se cargó (USD 14/m) y el importe de cada
fila, el subtotal de cada pieza y los servicios en %, paso por paso, hasta el precio de venta. Vendedor
y cliente, solo el número y los mensajes (*El precio sale de una función*).

**El detalle económico lo da `catalogo_aprobar`, no `catalogo_costos`.** El precio ya salía solo con
aprobar: Lucía con Paquetes y costos ve el despiece y los costos en sus pestañas, pero no el detalle ni
el precio. Aprobar no se delega, así que el detalle tampoco. Costo aceptado: quien aprueba ve los costos
en el detalle aunque no tenga `catalogo_costos`; hoy no cambia nada, porque el gerente tiene las dos.

**El despiece se pide de cualquier versión, borrador incluido, y sin fecha; el detalle económico, además,
a cualquier fecha.** La misma versión con las mismas medidas siempre da lo mismo: la enviada o publicada
no se edita, y los datos del insumo quedan fijos al enviarla. La fecha solo mueve los
costos. A diferencia del precio, elegir la versión no abre nada: el despiece no trae costos y la pestaña
ya las muestra todas (*Sin entes*). Tampoco depende de lo que hoy se vende: la baja del DVH no borra el
despiece de una versión que lo usa.

**La pestaña Paquetes abre en la versión publicada y cada versión muestra su estado.** Rodrigo, que
revisa cortes, no toma un borrador por lo vigente.

**A otros módulos, el catálogo les ofrece calcular el despiece de cualquier versión con lo que le pasen.
El precio no: ahí la versión y la fecha nunca las elige quien llama (*El precio sale de una función*).**
Quién pide el despiece, con qué permiso y qué versión usa se decide en la ficha de cada uno (*Al catálogo
entran solo los que definen*).

Ejemplo con datos inventados: https://claude.ai/artifact/6f2trHCaiVTdeqEa7bq4eS

## Las fórmulas se calculan sin SQL dinámico (2026-11-02)

**Técnica escribe la fórmula como texto. Al guardarla, una función de la base la convierte en un árbol y
se guardan los dos; calcular recorre el árbol, y el texto nunca se ejecuta como SQL.** Lo que no se
entiende no se guarda. Solo hay números, variables y materiales, + − × /, paréntesis, comparadores, `y`, `o`, "si …
entonces … si no …", `redondear_arriba`, `arcoseno` y `pi`: `1; drop table usuarios`, `(select 1)` y
`pg_sleep(10)` no pasan. Calcular no lee tablas, así que una fórmula no puede leer un costo. Del árbol sale
además de qué depende cada fórmula, y con eso se revisa lo que puede faltar y lo circular (*Qué frena el
envío*). Se descartó armar SQL y ejecutarlo: la función del precio lee lo que quien llama no puede abrir,
y una fórmula mal filtrada leía cualquier cosa. También convertir el texto en TypeScript, que dejaba la
regla fuera de Postgres, y plv8, una dependencia nueva para lo mismo.

**En una fórmula, el decimal es la coma y el punto no se acepta.** Para la empresa, `1.500` es mil
quinientos: leído como 1,5, `ancho > 1.500` daba siempre cierto sin que nadie lo notara.

**Un nombre con espacios va entre corchetes: `[Perfil hoja]`.** El editor los pone al elegirlo de la lista.

Medido en la base con la fórmula del vidrio del arco: 0,42 ms al guardar y 0,15 ms al calcular, unos 6 ms
para un paquete de 40 fórmulas, sin contar la lectura de las tablas. Pasan 31 de 31 casos en
`sql/tests/catalogo_formulas_prototipo.sql`, que no deja nada en la base y es de donde salen las funciones
reales. El prototipo todavía no tiene `y` ni `o`: se suman con sus casos al escribir las funciones.
