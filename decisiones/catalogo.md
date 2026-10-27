# Catálogo

**Se arma de cero: no se trae nada de la v1 ni de la v2 (2026-10-26).** La ficha y las decisiones de
este módulo salen solo de preguntas nuevas al usuario. No se lee `obsoletos/catalogo-descartado-2026-10-22/`,
no se compara con lo descartado y no se recupera nada de ahí: ni nombres, ni entes, ni estados, ni
tablas, ni soluciones del tipo "como estaba antes". Si una sesión sabe algo de esas versiones, no lo
propone. Si algo nuevo termina pareciéndose, tiene que ser porque volvió a salir de las preguntas.
El usuario descartó el diseño entero el 2026-10-22 y pidió fichar el módulo sin basarse en él. Lo que
este archivo no dice, no está decidido.

## Ficha del módulo

En armado, punto por punto con el usuario. Objetivo y personas aprobados el 2026-10-27. Entes,
estados, relaciones, acciones, eventos y el árbol de vistas: sin armar. Los entes se discutieron y se
descartaron para retomarlos de cero.

```
Módulo: catalogo
Objetivo: definir qué se puede vender y cómo se calcula: los paquetes, cada uno un despiece (sus
piezas armadas y las fórmulas de cada una), y su precio (los costos de insumos y servicios, y el %).
Personas                qué ve · qué hace · qué NO ve
├── Técnica        — insumos y fórmulas · carga insumos, arma los paquetes, da de baja insumos y
│                    paquetes · costos, % ni precios
├── Administración — insumos con su costo · carga los costos de insumos y servicios, define el % ·
│                    paquetes ni fórmulas
├── Vendedor       — NO entra: usa los paquetes desde Presupuestos · el precio final · costos, % ni
│                    fórmulas
├── Cliente        — NO entra: lo mismo que el vendedor, desde erp-cliente
├── Producción     — NO entra: ve las piezas y sus medidas, servicios incluidos, desde Producción
│                    (módulo a hacer) · costos, % ni precios
└── Compras        — NO entra: ve los insumos y su costo desde Compras (módulo a hacer), para
                     comparar con las cotizaciones · %, precios ni fórmulas
Entes
└── a definir
```

Pendientes de la ficha, en este orden:
- **Entes**, de cero.
- **Precio:** qué es exactamente "el %" de Administración (¿solo el servicio de comercialización?) y
  sobre qué se aplica; cuál de los precios de los proveedores pasa a ser el costo y quién lo elige;
  calcularlo al presupuestar sin que vendedor ni cliente vean fórmulas ni costos.
- **Nadie dentro del catálogo ve el precio final de un paquete:** Técnica no ve precios y
  Administración no ve paquetes, así que una fórmula mal cargada la nota el vendedor. Sin respuesta
  todavía si se acepta así o si alguien tiene que verlo (un usuario puede tener los dos permisos).

## Al catálogo entran solo los que definen (2026-10-27)

**Técnica y Administración entran al módulo; vendedor, cliente, producción y compras consumen lo que
el catálogo fija desde su propio módulo.** Si alguien de otro módulo necesita ver algo de acá (ej:
producción, las fórmulas), se le da ese permiso a ese usuario: sin persona ni regla nueva. Quien carga
algo lo da de baja: Técnica, también cuando se decide dejar de vender un paquete.

## Qué es un paquete (2026-10-27)

**Todo lo que se vende es un paquete: un conjunto de piezas armadas. Cada pieza armada es un conjunto
de fórmulas, y cada fórmula es un insumo o un servicio fijo con el cálculo de cuánto lleva según las
medidas del paquete.** Los nombres son los que usa la empresa.

```
Paquete: Ventana corrediza
├── Pieza armada: Marco
│   ├── Fórmula: Perfil marco 20x40 = (ancho − 2) × 2 + (alto − 2) × 2
│   ├── Fórmula: Escuadra           = 4
│   └── Fórmula: Soldado            = 4
├── Pieza armada: Hoja
│   └── …
└── Pieza armada: Colocación
    └── Fórmula: Instalación        = 1
```

- **Una fórmula siempre está en una pieza armada.** Lo que es de todo el paquete va en una pieza
  armada propia (Colocación): con dos lugares posibles, cada pantalla y cada cálculo contemplaría los
  dos. Las medidas son del paquete, así que cualquier fórmula calcula con ellas.
- **No se reutilizan piezas armadas entre paquetes.** Habrá pocos paquetes y cada uno se calcula
  distinto.
- **Hoy no se vende nada suelto.** El catálogo de un proveedor alimenta insumos para usar dentro de
  los paquetes. Para cuando revendan perfiles ya hay camino decidido (`BACKLOG.md`).

## El costo del insumo vive en el catálogo (2026-10-27)

**Cada insumo tiene un solo costo, el que se usa para calcular el precio de venta, y vive acá. Los
precios que ofrece cada proveedor y las cotizaciones viven en Compras.** Son datos distintos: Compras
tiene muchos por insumo y lee el costo para comparar; el catálogo tiene uno, el elegido. Si viviera en
Compras, el catálogo no podría poner precio hasta que exista Compras, que no tiene ficha. Quién lo
carga es un permiso, no un lugar: hoy Administración; si alguien de compras tiene que actualizarlo, se
le da ese permiso, sin copia en Compras.

Archivos: corrige `decisiones/contactos.md` → *Los proveedores son empresas de Contactos*.

## Servicios: fijos o en % (2026-10-27)

**Un servicio fijo (ej: el soldado de los perfiles, propio) es una fórmula más: unidades × su costo.
Un servicio en % con mínimo (ej: comercialización) es monetario: no forma parte del despiece y entra
al armar el precio.** Cómo entra el de % queda en los pendientes del precio.
