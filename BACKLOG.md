# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## Contactos y Obras — lo que quedó afuera de los tramos

Los cinco tramos están cerrados (estado y tests en el encabezado de `decisiones/obras.md`). Quedan:
- **Sin función que los respalde:** vincular a una obra desde la ficha de la persona o la empresa
  (buscar "obras que trabajás", `decisiones/contactos.md` → *Vincular*), y crear la empresa desde
  "Sumar empresa" o la persona desde "Sumar persona" (hoy, solo existentes: crear y relacionar en un
  paso pide una función, como `contactos_crear_y_vincular`).
- **Sin probar en el navegador:** elegir entre dos comisiones al fusionar (lo cubre
  `sql/tests/contactos_fusionar.sql`).

## Módulos que siguen

Orden: Contactos y Obras → **Catálogo** → Compras (costos) → Presupuestos → Post-venta. Sin lugar
todavía en el orden: Stock y la licitación de Compras.

Ya decidido para los módulos que vienen detrás, al fichar Obras:
- **Catálogo** (servicios y productos): de ahí salen los ítems de los presupuestos. Ficha en curso:
  `decisiones/catalogo.md` → *Ficha del módulo — v2*, la vigente. Siguiente: lo que falta para
  aprobarla (*Pendiente*), de a un punto; sigue el 10 de lo que la v1 tenía y la v2 no (peso de
  la abertura para logística). Producción y erp-cliente, al fichar, suman su rama a la función de cálculo del catálogo
  (`decisiones/catalogo.md` → *La función de cálculo decide qué parte ve cada uno*).
- **Presupuestos**: uno por etapa de la obra (FK `obra_id`), con versiones (congeladas al enviarse) e
  ítems del catálogo con el precio copiado. Su estado es el operativo (en cotización, aprobado, en
  producción…) y es lo que mueve a administración, producción y logística: sus plantillas de
  ejecución y el seguimiento comercial al entregar cuelgan del presupuesto, no de la obra. El primer
  presupuesto pasa la obra a `en_cotizacion` y el primero aprobado a `contratada`. La ficha de la
  obra lista sus presupuestos con su estado actual. Los contactos operativos (capataz, quien recibe)
  se vinculan al presupuesto. A decidir: cómo ve logística el nombre y la dirección de una obra que no
  abre (propuesta: la etapa guarda su dirección de entrega).
  Los descuentos son de Presupuestos, no de Catálogo (que da el precio de lista, igual para todos):
  por presupuesto o línea, con la función "aplicar descuento"; el tope, al fichar Presupuestos.
  La cantidad es de la línea (precio de una abertura × cantidad) y lo que se hace una vez por pedido
  (traslado, flete, preparación) es un cargo del presupuesto entero, no de cada línea
  (`decisiones/catalogo.md` → *La cantidad es de la línea*). El cargo es un renglón libre:
  descripción y monto que calcula el vendedor, sin servicio del catálogo (`decisiones/catalogo.md` →
  *Entes*). No se envía con una línea sin precio (insumo o servicio sin costo: `decisiones/catalogo.md` →
  *Sin costo no es $ 0*). La cantidad de un insumo suelto va en lo que administración eligió (barras o
  ml); si lo cambia, la línea sin enviar queda sin precio hasta revisar la cantidad
  (`decisiones/catalogo.md` → *El suelto se vende por presentación o por unidad del insumo*).
  Hasta enviarse, la línea sigue a la versión vigente (última aprobada) del paquete y al costo de hoy
  (con aviso si el paquete cambió, con el texto del técnico); al enviar, se congela
  (`decisiones/catalogo.md` → *Mandar a aprobar frena; aprobar pone a la venta*).
  La línea nueva propone el color y el vidrio de la anterior: en el catálogo no tienen default
  (`decisiones/catalogo.md` → *El default es obligatorio solo en lo secundario*).
  Los avisos de la línea quedan marcados y al enviar o aprobar se listan para confirmar, sin frenar;
  queda quién confirmó (`decisiones/catalogo.md` → *El aviso es parte del resultado de la línea*).
  Una línea suelta puede referirse a otra (*Traba × 4 — para V4*) para que taller sepa a qué abertura
  va (`decisiones/catalogo.md` → *El vendedor no agrega materiales*).
  El permiso que arma líneas suma su rama a la función de cálculo del catálogo: precio, avisos y
  plegado de la vigente (`decisiones/catalogo.md` → *La función de cálculo decide qué parte ve cada
  uno*).
- **Stock** (decidido al fichar Catálogo, 2026-09-29): módulo propio, no parte de Catálogo. Lleva
  existencias y movimientos de los insumos del catálogo; su persona principal es depósito/logística.
  Quien presupuesta ve el stock del insumo sin poder tocarlo. Depósito no usa Catálogo: ve el insumo
  (nombre, presentación, color) desde Stock (`decisiones/catalogo.md` → *Depósito no usa el catálogo*).
  Su vista se suma a la lectura del insumo del catálogo; las existencias, en tabla propia con FK
  (`decisiones/catalogo.md` → *Stock y Compras leen la tabla del insumo*).
- **Compras** (ídem): dueño del costo del insumo, no Catálogo. El costo es de reposición (lo que
  costaría comprarlo hoy), en su moneda (ARS, US$, €), con historial, cargado como se cotiza (por
  unidad, presentación o kg: `decisiones/catalogo.md` → *El costo se carga como se cotiza*); se convierte con el oficial BNA
  venta. Catálogo lo lee para calcular el precio de venta; el técnico no lo ve. Quien compra no usa
  Catálogo: ve el insumo con sus existencias de Stock desde Compras (`decisiones/catalogo.md` →
  *Compras no usa el catálogo*), con la lista "sin costo y en uso" (*Lo que falta costear se ve en
  filtros*). Su vista se suma a la lectura del insumo y a la función del dónde se usa (*Stock y
  Compras leen la tabla del insumo*). Tabla propia, no
  columna del insumo: RLS filtra filas, no columnas. El aumento se aplica por categoría del catálogo o
  por insumo, en % o monto fijo, con motivo e historial, como en los dos ERP viejos (`erp_old`
  `lista_precios/AumentoModal.tsx`, `erp_old_2` `precios/ActualizacionMasivaModal.tsx`); no por
  proveedor: a cada categoría le venden varios. Es de Compras, no del catálogo: lee las categorías
  como lee el insumo (`decisiones/catalogo.md` → *Stock y Compras leen la tabla del insumo*). La cotización
  (USD y EUR) es una vista de Compras (`decisiones/catalogo.md` → *Precio de venta*). Arranca mínimo
  (costos y cotización) antes de Presupuestos;
  después suma la licitación —varias ofertas por insumo, con precio, plazo y fecha, y una elegida—,
  que al elegir actualiza el costo. Los proveedores son empresas de Contactos
  (`decisiones/contactos.md` → *Los proveedores son empresas de Contactos*).
- **Post-venta**: módulo aislado para su equipo. La unidad (1°C, local, casa) se arma después,
  eligiendo ítems del presupuesto aprobado ("estas 4 ventanas → 1°C"); si un ítem agrupa varias
  unidades, se lleva ítem y cantidad. Una obra de un solo dueño es una unidad con todo. Propietarios e
  inquilinos, vínculos de Contactos con `desde` / `hasta`; el seguro, un contrato de la unidad.

## erp-cliente — falta el `ThemeToggle`

Vive en `SidebarNav` y el portal no tiene sidebar todavía. Va cuando el portal arranque de verdad
(`decisiones/global/ui.md` → *El script de tema va en `<script>` plano*).

## Sugerencia de tareas — sin caso real todavía

"¿Qué hago ahora?" ya lo contesta Misión; falta "¿qué tarea debería existir y no existe?" — la obra
sin movimiento hace 60 días (`decisiones/global/infra.md` → *La sugerencia de tareas no se
construyó*). El prerequisito de entonces ya está: el hilo sabe sobre qué registro es y el disparo
guarda la plantilla en el vínculo (`sql/119`, `sql/148`–`152`), así que una sugerencia puede saber si
la tarea ya existe. Cuando aparezca el caso, abre el flujo de plantillas ("Usar" con su "Sobre"), no
un camino de creación nuevo.
