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

Orden: Contactos y Obras → **Catálogo** → Presupuestos → Post-venta.

Ya decidido para los módulos que vienen detrás, al fichar Obras:
- **Catálogo** (servicios y productos): de ahí salen los ítems de los presupuestos.
- **Presupuestos**: uno por etapa de la obra (FK `obra_id`), con versiones (congeladas al enviarse) e
  ítems del catálogo con el precio copiado. Su estado es el operativo (en cotización, aprobado, en
  producción…) y es lo que mueve a administración, producción y logística: sus plantillas de
  ejecución y el seguimiento comercial al entregar cuelgan del presupuesto, no de la obra. El primer
  presupuesto pasa la obra a `en_cotizacion` y el primero aprobado a `contratada`. La ficha de la
  obra lista sus presupuestos con su estado actual. Los contactos operativos (capataz, quien recibe)
  se vinculan al presupuesto. A decidir: cómo ve logística el nombre y la dirección de una obra que no
  abre (propuesta: la etapa guarda su dirección de entrega).
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
