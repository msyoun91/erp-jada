# Decisiones — módulo catálogo

**Estado (2026-09-29): ficha en borrador, sin aprobar. Sin SQL.** Retomar desde *Pendiente*, de a un
punto. Referencia del motor de paquetes: `C:\dev\Archivos antiguos\spec_plantillas_5.md` (módulo
Plantillas del ERP viejo) y `plan_plantillas.md` — se adapta, no se copia.

## Un solo módulo con tres vistas: Insumos · Servicios · Paquetes (2026-09-29)

**Catálogo es un módulo con tres pestañas, no tres módulos.** La visibilidad por persona se resuelve
por vista (cada pestaña es su submódulo), no por módulo; el técnico trabaja en las tres a la vez (arma
un paquete eligiendo insumos y servicios), y un paquete no existe sin sus insumos. Descartado: Paquetes
como módulo aparte (el ERP viejo tenía Lista de precios + Plantillas + Márgenes) — un layout, una ficha
y un ir y venir de más para la misma persona.

Fuera de Catálogo (`BACKLOG.md`): el **costo** (Compras), las **existencias** (Stock), el **proveedor**
(empresa de Contactos con rol `proveedor` sobre el insumo, `decisiones/contactos.md`) y el **precio
final** (Presupuestos: es donde se cargan las medidas).

## Qué es y qué hace cada vista

### Insumos — qué compramos y usamos para trabajar

- Perfiles, tornillos, burletes, vidrios, silicona.
- Datos: nombre, **unidad de compra** (ml, kg o unidad — cada insumo una), peso por unidad (para el
  peso de la abertura y logística), unidad de comercialización / presentación (ej: barra de 6 m),
  **tipo** y **categoría** (ver *Categorías*).
- **La presentación sirve para vender suelto y para comprar, no para el paquete** (2026-10-14). Suelto
  se vende por presentación entera (2 barras = 12 ml × costo), no por fracción. Compras compra barras
  enteras y Taller podrá calcular cuántas salen del despiece. En el paquete el insumo va en su unidad
  (ml); el sobrante de barra entra por el desperdicio.
- **"Se vende suelto"**: solo los marcados le aparecen al vendedor como producto. Lo marca
  administración.
- Sin costo: el costo de reposición vive en Compras, con su moneda (ARS, US$, €).
- Ente: sí (vinculable a proveedores vía `contactos_vinculos`; declara el rol `proveedor`).

### Servicios — lo que no es material y se cobra

- Procesamiento, colocación de burlete, soldadura, mano de obra de instalación, y los **comerciales**:
  comercialización, manipulación.
- **Fijo**: monto por unidad (soldadura $ 1.500 c/u). **Porcentual**: % sobre la suma de los insumos
  **de su grupo** (no del paquete entero), con **precio mínimo** — el mínimo se aplica **una vez por
  servicio en el paquete**, sobre la suma de sus grupos, no en cada grupo (mano de obra 15 %, mín $ 5.000).
- Montos, % y mínimos los pone **administración**; el técnico no los ve.
- **No hay margen:** el precio de venta es insumos a costo + servicios. La ganancia está en los
  servicios comerciales.
- Servicios comerciales: **generales**, se suman a todo paquete y a todo insumo suelto; administración
  puede quitarlos o cambiarles el % en un paquete.

### Paquetes — cómo se arma y cuánto lleva

- Plantilla con nombre ("Ventana corrediza 2 hojas") que lista insumos y servicios con su **cantidad o
  coeficiente**. El técnico pone *cuánto* (soldadura × 4, perfil = 2×ancho + 2×alto); administración y
  compras ponen *cuánto vale*; el sistema multiplica.
- Es el motor paramétrico del ERP viejo, recortado. Primer tramo propuesto: variables que carga el
  vendedor (ancho, alto, cantidad), variables calculadas, grupos (con opcionales, ej: mosquitero),
  materiales con cantidad fija o calculada, **servicios con cantidad** (nuevo: la spec vieja no los
  tenía), peso, versiones (un presupuesto no cambia si se edita el paquete) y **restricciones**
  (mín./máx. de una variable con su mensaje: **advierten, no frenan** — el vendedor ve el aviso y puede
  seguir) y **corte** por material (ángulo: 90°, 45°; no cambia el precio, es para el despiece de
  Taller — se carga desde ya aunque Taller no exista) y **colores** (el vendedor elige el color y cada
  insumo se cambia solo por su equivalente en ese color; el que no tiene color, como la felpa, queda
  igual). **La equivalencia vive en el insumo**, una sola vez (ART-2301 en negro mate es ART-2301-NM),
  y la usan todos los paquetes; el paquete solo dice qué colores ofrece. Descartado: mapear en cada
  paquete como el mockup — el mismo perfil se remapearía en cada plantilla y los mapeos podrían
  contradecirse. Y **vidrios compuestos**: el paquete define cada paño (medidas por variable, espesor
  máximo del canal) y el vendedor arma la composición al presupuestar (simple, DVH, TVH: vidrios +
  cámaras); el sistema saca m² por vidrio y ml de separador. Si la composición supera el espesor del
  canal, **advierte, no frena** (como las restricciones). Después: reglas, simulador, grafo.
- **Lo que carga el vendedor lo define el paquete** (2026-10-14), no es un juego fijo de ancho, alto y
  cantidad: el técnico declara cada variable del vendedor. Puede ser una **medida** (número, con sus
  restricciones) o una **opción** entre insumos (rueda simple o doble): el vendedor elige y el
  material del paquete cambia por el elegido.
- **El peso es para logística y condiciona herrajes** (2026-10-14): ej., pasado cierto peso de hoja
  va rueda doble.
- **Una opción puede tomar su insumo por una variable calculada** (2026-10-14): "si `peso_hoja` > 40
  kg → rueda doble". El sistema la elige y muestra por qué ("Rueda doble — por peso: 48 kg"); el
  vendedor puede cambiarla y ve el aviso, no lo frena (como las restricciones). Es el único tipo de
  regla del primer tramo; las reglas generales siguen para después.
- Un insumo suelto se precia como un paquete de una línea: costo + servicios comerciales generales.
- **Pantalla de referencia:** `C:\dev\Archivos antiguos\mockup_plantillas_v4.html` (lista con versiones y
  estado; detalle en pestañas: grupos, variables, materiales, restricciones, vidrios, reglas, colores,
  sandbox, auditoría). **Se le suma una pestaña Servicios** al lado de Materiales: el técnico elige el
  servicio del catálogo y le pone cantidad fija o por variable (soldadura × 4); el monto no se ve.
  **Cada servicio va en un grupo**, como los materiales: si el vendedor saca un grupo opcional
  (mosquitero), su mano de obra sale con él.

## Categorías (2026-10-14)

**Insumos y paquetes tienen categorías que crea el usuario, de un solo nivel; servicios, no.** En
paquetes es como busca el vendedor (Ventana → corrediza 2 hojas, corrediza 3 hojas). Servicios son
pocos y ya se separan por fijo/porcentual y comercial; sumarla después es trivial. Subcategorías,
recién si una categoría se llena.

**En insumos, la categoría (libre) va separada del tipo (fijo: vidrio, cámara, perfil, otro).** El
tipo lo usa el sistema (armado de DVH, corte, color) y no se toca desde la pantalla; la categoría solo
ordena y agrupa, y mezcla tipos: "Vidrios" tiene vidrios y cámaras porque se compran a varias
vidrierías y aumentan juntos. Si el sistema mirara la categoría, renombrarla rompería el cálculo.

**El aumento de costo se aplica por categoría o por insumo, en % o monto fijo, con motivo e
historial** — como en los dos ERP viejos (`erp_old` `lista_precios/AumentoModal.tsx`, `erp_old_2`
`precios/ActualizacionMasivaModal.tsx`). No por proveedor: a cada categoría le venden varios. Como el
costo vive en Compras, la acción es de Compras y usa la categoría del catálogo.

## Precio de venta

```
Insumo        cantidad (técnico, fija o fórmula) × costo de reposición (Compras) → a pesos, oficial BNA venta
Servicio fijo cantidad (técnico) × monto (administración)
Servicio %    % (administración) × suma de insumos de su grupo; mínimo (administración) una vez
              por servicio en el paquete, sobre la suma de sus grupos
Comerciales   generales, con excepción por paquete (administración)
Precio        insumos + servicios — se calcula en Presupuestos, con las medidas
```

Cotización: oficial BNA venta de USD y EUR, automática con corrección manual (como `erp_old`: dolarapi,
ventana 10–15 h, cierre del día, lo manual no lo pisa el automático; `erp_old_2`: monedapi.ar).

**La cotización es una vista de Compras, no un módulo** (2026-10-14). Una tabla, una pantalla y una
persona (administración la corrige); Compras es dueño de los costos en moneda extranjera y Catálogo y
Presupuestos solo la leen, como leen el costo. Si crece (más monedas, índices), se separa.

## El motor va en Postgres (2026-10-14)

**El precio lo calcula una función de Postgres `SECURITY DEFINER` que devuelve el precio y nunca el
costo.** RLS filtra filas, no columnas: el vendedor no puede leer la tabla de costos, así que una
función `INVOKER` no podría calcular, y hacerlo en TypeScript exigiría `service_role`. Excepción
explícita a `SECURITY INVOKER`, acotada a esta función.

**Las fórmulas se validan al guardar y se evalúan en la base**: solo números, variables del paquete,
`+ − × ÷`, paréntesis y funciones de una lista (redondear, máximo, mínimo). Descartado: el motor en
TypeScript del ERP viejo — más rico (reglas, simulador, grafo), pero eso quedó para después.

## Ficha del módulo (borrador)

```
Módulo: catalogo
Objetivo: definir qué compramos (insumos), qué hacemos (servicios) y cómo se combinan en lo que vendemos
          (paquetes), para que un presupuesto se arme eligiendo un paquete o un insumo suelto y cargando
          sus medidas.
Personas
├── Técnico / ingeniería — ve insumos, servicios (sin montos) y paquetes · crea insumos y servicios,
│                          arma paquetes (quien tenga la función, no la persona) · no ve costos ni
│                          precios
├── Administración       — ve todo, con costos (de Compras) y precios · pone montos, % y mínimos de
│                          servicios, excepciones de comerciales, "se vende suelto" · —
├── Vendedor             — ve paquetes (despiece sin precios), insumos sueltos y precio de venta
│                          · los elige al presupuestar (en Presupuestos) · no ve costos
├── Depósito             — ve insumos · — · no ve costos, paquetes ni precios
├── Compras              — NO usa Catálogo · ve los insumos desde Compras, para costearlos
└── Taller               — NO usa Catálogo · ve el despiece ya procesado, por plantillas
Entes, relaciones, acciones, eventos: pendientes
```

## Pendiente

1. Fórmulas: descuentos y desperdicio.
2. Entes, relaciones, acciones, eventos; árbol de vistas y funciones; delegables y reglas entre
   permisos. Con eso la ficha se aprueba.
