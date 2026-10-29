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

Orden: Contactos y Obras → **Catálogo** → Presupuestos → Post-venta. Sin lugar todavía en el orden:
Stock y Compras.

Ya decidido para los módulos que vienen detrás, al fichar Obras:
- **Catálogo** (servicios y productos): de ahí salen los ítems de los presupuestos. **Se arma de cero**
  (2026-10-22): la v1 y la v2 se descartaron enteras, junto con lo que habían dejado en Presupuestos,
  Stock, Compras y `GUIDE_ENTES.md` (`obsoletos/catalogo-descartado-2026-10-22/`). Nada de eso vuelve
  (`decisiones/catalogo.md`). La ficha nueva se arma ahí, punto por punto: objetivo y personas
  aprobados, servicios en %, precio, tipos de cambio y versiones (2026-10-27), el insumo (2026-10-29);
  siguiente: los demás entes.
- **Catálogo — reventa de perfiles**, sin caso real todavía: un solo paquete "Perfil suelto" cuya
  fórmula deja el perfil a elegir al presupuestar, no un paquete por perfil. Escala sin trabajo (un
  perfil nuevo del proveedor se vende el mismo día), no copia la misma estructura 200 veces y la lista
  del vendedor sigue corta. Puede convivir con un paquete propio para un perfil especial. Falta decidir
  de qué lista se elige el perfil.
- **Catálogo — % de un servicio por categoría de paquete**, sin caso real todavía: se construye con
  la primera categoría que cobre distinto. Sumarlo no cambia nada, porque mientras tanto todos los
  paquetes usan el % general (`decisiones/catalogo.md` → *Servicios en %*).
- **Presupuestos**: uno por etapa de la obra (FK `obra_id`), con versiones (congeladas al enviarse) e
  ítems del catálogo con el precio copiado, más un renglón por cada mínimo por presupuesto de los
  servicios en %, que calcula el catálogo (`decisiones/catalogo.md` → *Servicios en %*). Su estado
  es el operativo (en cotización, aprobado, en producción…) y es lo que mueve a administración, producción y logística: sus plantillas de
  ejecución y el seguimiento comercial al entregar cuelgan del presupuesto, no de la obra. El primer
  presupuesto pasa la obra a `en_cotizacion` y el primero aprobado a `contratada`. La ficha de la
  obra lista sus presupuestos con su estado actual. Los contactos operativos (capataz, quien recibe)
  se vinculan al presupuesto. A decidir: cómo ve logística el nombre y la dirección de una obra que no
  abre (propuesta: la etapa guarda su dirección de entrega).
- **Stock** y **Compras**: sin ficha. Lo que se había decidido para ellos al fichar el catálogo se
  descartó con él (2026-10-22). Sigue valiendo que los proveedores son empresas de Contactos
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
