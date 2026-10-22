# Decisiones — módulo catálogo

> **Estado (2026-10-22): ficha v2 aprobada (2026-10-21), sin SQL.** La auditoría v2 cerró todo lo que
> cambia tablas y los choques entre la v1 y la v2 quedaron resueltos (2026-10-22). Sigue el SQL sin
> plata. Lo que cambie se corrige acá primero. Leer este índice y después
> solo el archivo del tema.

Pasado de `decisiones/catalogo.md` a esta carpeta el 2026-10-22 (copia en
`obsoletos/backup-docs-2026-10-22/`). Cada regla está una sola vez, con el vocabulario de la v2
(*mandar a aprobar*, no *publicar*). Donde una versión reemplazaba a la otra quedó la vigente; lo que
chocaba sin que ninguna lo resolviera está marcado con ⚠ y listado en `pendiente.md`. Las fechas de
cada decisión son las originales: 2026-10-14 es la v1, 2026-10-21 la v2.

Referencias: el motor de paquetes del ERP viejo, `C:\dev\Archivos antiguos\spec_plantillas_5.md` y
`plan_plantillas.md` (se adapta, no se copia), y su pantalla (`motor.md` → *Pantalla de referencia*).
Al 2026-10-21: casos en diagrama, con los puntos abiertos marcados,
https://claude.ai/artifact/BhPaBVCNWDBZnH62Pjthzu · demo de la ficha v2,
https://claude.ai/artifact/GcnZbyVggBmEVYKehoE7pu.

## Índice

| Archivo | Tema |
|---|---|
| `ficha.md` | Ficha v2 y árbol de permisos · tres vistas · fuera del catálogo · categorías en dos niveles · baja de una categoría · la subcategoría es la línea de perfiles · mover de subcategoría · el catálogo es compartido · solo el paquete se aprueba · la plata va con `_administrar` · `_editar` y `_administrar` coexisten · delegables · dos entes · el servicio no es ente · registro en `entes` · eventos de versión y cambio de cálculo · avisos a quien tiene la función · el producto nuevo se avisa al aprobarse · sin FK a otros módulos y SQL en tres partes · depósito y Compras no usan el catálogo · Stock y Compras leen la tabla del insumo |
| `insumos.md` | Datos · *en uso* · sin tipo fijo · unidad fija · presentación · desperdicio · la fórmula dice lo puesto · peso obligatorio · el suelto por presentación o por unidad · el insumo no se versiona · el cambio de cálculo en uso espera a administración |
| `servicios.md` | Comercial no es marca · fijo o porcentual con unidad · montos de administración · el servicio se edita directo · en el paquete: grupo, cantidad y condiciones · el insumo trae sus servicios · antigüedad y aumento en masa · servicios por categoría: la regla más específica, por subcategoría, la excepción del paquete, sin mínimo · reglas desde el servicio · categorías fuera del % |
| `motor.md` | Qué es un paquete · pantalla de referencia · fórmulas: sintaxis, mm, unidad, redondeo · piezas: cantidad, ángulos, barra, redondeo al mm · materiales condicionales y casillas · grupo por hoja · duplicar grupo · `con_<grupo>` · peso por grupo · suma al peso · ciclos y grafo · lo imposible · la restricción es una condición · el aviso es parte del resultado · la cantidad es de la línea · el vendedor no agrega materiales |
| `opciones.md` | Lo que carga el vendedor · mínimo y máximo con su mensaje · default por fórmula y pisada · principal o secundaria · la medida secundaria lleva default · lo elegido se guarda · variables de opción · herraje por hoja · *Sin material* · subcategorías enteras · hermanas y pares · cierre central · el vidrio como opción · medidas del vidrio · DVH por capas · espesor |
| `calculo.md` | El motor va en Postgres (`DEFINER`, plata en tablas propias) · al presupuestador, el precio · cuatro partes: precio, avisos, plegado y despiece · qué ve cada permiso, también de otros módulos · el despiece no se guarda · producción elige versión, solo si cubre lo vendido, y recibe lo vendido o error |
| `versiones.md` | Estados por versión · una fórmula aprobada no se edita · una versión abierta · mandar a aprobar y sus controles · volver al borrador · aprobar con checkbox · aprobar vuelve a controlar · descartar · casos de prueba y referencia · qué cuenta como cambio · historial · lo guardado cruza versiones · renombrar el paquete · duplicar |
| `bajas.md` | Dar de baja es de administración · la baja depende de cómo se usa · alcance antes de confirmar · lo que depende de medidas · lo que el catálogo deja de ofrecer deja la línea sin precio · baja con reemplazo de insumo y de servicio · "Reemplazar material" |
| `colores.md` | La equivalencia vive en el insumo · lista y variantes de administración · baja de un color de la lista · clase de color y color base · fijos como la unidad · la variante solo tiene código y color · color de herrajes · las alternativas se filtran por color |
| `precio.md` | Precio de venta · no hay margen · el costo en Compras · el costo se carga como se cotiza · sin costo no es $ 0 · el 0 y el mínimo · lo que falta costear se ve en filtros · cambios de plata al instante · presupuesto enviado: mantener o actualizar · cotización por fecha del BNA · la cotización es de Compras |
| `clientes.md` | Habilitación por categoría y precio opcional · las habilitaciones siguen a la empresa que queda al fusionar |
| `pendiente.md` | Choques entre v1 y v2 · auditoría v2: lo de Compras y lo de pantallas · escenarios · resueltos |
