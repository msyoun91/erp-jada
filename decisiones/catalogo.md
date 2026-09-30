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
  peso de la abertura), unidad de comercialización / presentación (ej: barra de 6 m) — su uso exacto
  sigue pendiente —, clasificación (perfiles, vidrios, accesorios, herrajes…).
- **"Se vende suelto"**: solo los marcados le aparecen al vendedor como producto. Lo marca
  administración (a confirmar).
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
  puede quitarlos o cambiarles el % en un paquete (quién hace la excepción: a confirmar).

### Paquetes — cómo se arma y cuánto lleva

- Plantilla con nombre ("Ventana corrediza 2 hojas") que lista insumos y servicios con su **cantidad o
  coeficiente**. El técnico pone *cuánto* (soldadura × 4, perfil = 2×ancho + 2×alto); administración y
  compras ponen *cuánto vale*; el sistema multiplica.
- Es el motor paramétrico del ERP viejo, recortado. Primer tramo propuesto: variables que carga el
  vendedor (ancho, alto, cantidad), variables calculadas, grupos (con opcionales, ej: mosquitero),
  materiales con cantidad fija o calculada, **servicios con cantidad** (nuevo: la spec vieja no los
  tenía), peso y versiones (un presupuesto no cambia si se edita el paquete). Después: reglas, simulador,
  grafo. A decidir: cortes, restricciones, colores, vidrios compuestos.
- Un insumo suelto se precia como un paquete de una línea: costo + servicios comerciales generales.
- **Pantalla de referencia:** `C:\dev\Archivos antiguos\mockup_plantillas_v4.html` (lista con versiones y
  estado; detalle en pestañas: grupos, variables, materiales, restricciones, vidrios, reglas, colores,
  sandbox, auditoría). **Se le suma una pestaña Servicios** al lado de Materiales: el técnico elige el
  servicio del catálogo y le pone cantidad fija o por variable (soldadura × 4); el monto no se ve.
  **Cada servicio va en un grupo**, como los materiales: si el vendedor saca un grupo opcional
  (mosquitero), su mano de obra sale con él.

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
ventana 10–15 h, cierre del día, lo manual no lo pisa el automático; `erp_old_2`: monedapi.ar). Dónde
vive: a decidir (la usan Compras, Catálogo y Presupuestos).

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

1. Del motor: cortes, restricciones, colores y vidrios compuestos — ¿cuáles se usan hoy para
   presupuestar? Lo que no, a `BACKLOG.md`.
2. Peso y unidad de comercialización: confirmar el uso (peso de la abertura; ¿barra para vender
   suelto?; ¿logística?).
3. Fórmulas: qué medidas carga el vendedor, condiciones, descuentos y desperdicio.
4. Confirmar: excepciones de comerciales y "se vende suelto" los hace administración.
5. El motor, ¿en Postgres (regla de `CLAUDE.md`) o excepción explícita en TypeScript como el ERP viejo?
6. Dónde vive la cotización.
7. Entes, relaciones, acciones, eventos; árbol de vistas y funciones; delegables y reglas entre
   permisos. Con eso la ficha se aprueba.
