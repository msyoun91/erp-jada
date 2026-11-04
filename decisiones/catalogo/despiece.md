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
Lo demás lo resuelve lo que ya existe: el mínimo de la variable (`alto` desde 300), condiciones como
`flecha > ancho / 2` (con flecha 800 la cuenta da un número válido: para la base no es un error) y
`redondear_arriba` para las 1,7
bisagras. Una cantidad 0 es que no lleva: sin fila. Se descartó bloquear las cantidades con decimales:
el medio pomo se puede cobrar.

**Primero se calcula la cantidad: si da 0, el material no tiene fila y no se evalúan ni su medida ni sus
condiciones, como una opción no elegida. Lo mismo vale para una pieza con cantidad 0 y lo que tiene adentro
(2026-11-02).** Un vidrio superior con cantidad `si alto > 2100 entonces 1 si no 0` y alto `alto − 2100`,
con alto 2.000, daba −100 y frenaba la puerta en toda medida normal. Quien usa ese material desde otra
fórmula recibe 0: si eso deja otra medida en 0, sigue sin poder calcularse, y un Contravidrio superior con
medida `[Vidrio superior]` lleva el mismo "si" en su cantidad. Con cantidad mayor que 0, una medida de
−18 mm sigue frenando el cálculo.

**Un material múltiple con cantidad 0 no exige elegir, si ninguna opción trae cantidad propia (2026-11-04).** Con alto 2.000 el
vendedor no tiene que elegir un Vidrio superior que no va; con 2.200, sí. Si alguna opción trae la suya, la cantidad depende de la
elección y se sigue pidiendo. Sin elección, una variable según ese material usa su valor de "Si no hay elección", y si no lo tiene
frena el cálculo; lo que lo sigue queda sin fila, aunque su propia cantidad dé más de 0: sin vidrio no hay pareja. Archivos:
`sql/175_catalogo_cantidad_antes_de_elegir.sql`, `sql/tests/catalogo_despiece.sql`.

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

## Cómo se calcula (2026-11-03)

**Lo que carga el vendedor apunta por nombre a piezas, materiales y variables, y por id a insumos y colores.** Un caso se
copia a la versión siguiente, donde esos ids cambian, y el gerente compara dos versiones con la misma entrada. Lo que la
entrada elige y la versión ya no tiene frena el cálculo, y por lo tanto el envío: "Vidrio: esa opción ya no existe". Un valor
para una variable que ya no está no cambia nada y se ignora. La forma la frena la base al guardar un caso.

**Las fórmulas se calculan en cualquier orden: se vuelve a pasar hasta que una vuelta no resuelve nada, y lo que sigue
esperando es lo circular o lo que no existe.** Solo se espera lo que la cuenta usa de verdad: la rama de un "si" que no se
toma no hace falta. Acá eso no frena; lo circular escrito en esa rama lo frena el envío, que mira la fórmula entera.

**Se devuelven todos los errores, y también los mensajes de rango y condiciones que se pudieron evaluar.** Con alto 30, el
vendedor lee "Alto va de 300 a 3.000 mm" junto con "No se puede calcular con estas medidas": es el mensaje que le dice qué
corregir. Quien espera a algo que falló no se nombra, porque repetía el mismo error.

**Una variable adentro de una pieza con cantidad 0 sigue valiendo su cuenta para quien la use, pero no sale, no evalúa rango
ni condiciones, y si su cuenta falla frena solo a quien la use.** "Cantidad de travesaños" define la cantidad de su propia
pieza: tiene que poder calcularse antes de saber si la pieza está. Un material de esa pieza vale 0, como pide *El despiece
calculado*: lo suyo es lo que se corta, y una variable es solo una cuenta.

**Un peso o espesor vacío deja a esa pieza sin el dato, y solo frena el cálculo si una fórmula lo usa.** Un borrador sin el
peso del Perfil se puede seguir probando y no suma 0; el envío lo frena igual (*Un peso o espesor vacío no es 0*).

**Sin color elegido ni base, las filas salen sin color y el despiece se calcula igual.** El color no mueve ninguna medida. Lo
frena el envío (*Qué frena el envío*) y el precio no da número sin él.

**Una opción en u hereda la `medida` del material si este la tiene.** No se cobra ni vale en otra fórmula: en el peor caso a
Producción le llega una medida de más. Una opción en m2 no hereda `medida`, ni una en mm o u hereda ancho y alto.

**Entre piezas contradictorias gana destildar:** con Cortina marcada y Cajón destildado, no van ninguna de las dos. El
formulario no lo manda; un caso escrito a mano o copiado sí podría.

Archivos: `sql/161_catalogo_despiece.sql`, con 652 casos en `sql/tests/catalogo_despiece.sql`. Medido en la base: 7,7 ms por
cálculo en una ventana de 12 filas y unas 30 fórmulas.

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

**Una fórmula con más de 100 operaciones una dentro de otra no se guarda, y lo que agota la pila al parsear da CA001 (2026-11-04).**
El tope va sobre el árbol, no sobre los paréntesis: una suma de 999 términos parseaba bien, se guardaba y daba 54001 recién al
calcular. Los paréntesis no dejan rastro en el árbol, así que esos se atajan por el 54001. Las fórmulas reales llegan a 4 niveles, y
una cadena de 80 "si" sigue entrando. `sql/179`.

**En una fórmula, el decimal es la coma y el punto no se acepta.** Para la empresa, `1.500` es mil
quinientos: leído como 1,5, `ancho > 1.500` daba siempre cierto sin que nadie lo notara.

**Un nombre con espacios va entre corchetes: `[Perfil hoja]`.** El editor los pone al elegirlo de la lista.

**Un "si" en medio de una cuenta va entre paréntesis: `(si alto > 2100 entonces 4 si no 3) + 1` (2026-11-02).**
Sin ellos no se ve dónde termina el "si": en `si a > 1 entonces 2 si no 3 + 1`, el `+ 1` es solo del "si no".

**Una fórmula llega hasta 2.000 caracteres (2026-11-02).** La fórmula más larga de esta carpeta tiene 76. El
tope evita que un texto enorme ocupe la base al guardarlo.

**`redondear_arriba` ignora lo que pasa del decimal 12 (2026-11-02).** `2 / 3 × 3` da 2,00000000000000000001 por
cómo se guarda la división, y sin esto subía a 3 en vez de quedar en 2.

Archivos: `sql/158_catalogo_formulas.sql`, con 87 casos en `sql/tests/catalogo_formulas.sql`. Medido en la base
con la fórmula del vidrio del arco: 0,44 ms al guardar y 0,17 ms al calcular, unos 7 ms para un paquete de 40
fórmulas, sin contar la lectura de las tablas.
