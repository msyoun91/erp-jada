# Catálogo

**Se arma de cero: no se trae nada de la v1 ni de la v2 (2026-10-26).** La ficha y las decisiones de
este módulo salen solo de preguntas nuevas al usuario. No se lee `obsoletos/catalogo-descartado-2026-10-22/`,
no se compara con lo descartado y no se recupera nada de ahí: ni nombres, ni entes, ni estados, ni
tablas, ni soluciones del tipo "como estaba antes". Si una sesión sabe algo de esas versiones, no lo
propone. Si algo nuevo termina pareciéndose, tiene que ser porque volvió a salir de las preguntas.
El usuario descartó el diseño entero el 2026-10-22 y pidió fichar el módulo sin basarse en él. Lo que
esta carpeta no dice, no está decidido.

## Índice

Leer este índice y después solo el archivo del tema. Una referencia como *Editor de paquete* es el título
de una sección: esta tabla dice en qué archivo está.

| Archivo | Tema |
|---|---|
| `permisos.md` | Al catálogo entran solo los que definen · Sin entes · Pestañas |
| `paquete.md` | Qué es un paquete · Editor de paquete |
| `insumos.md` | El insumo · El servicio fijo · El costo del insumo vive en el catálogo |
| `precio.md` | Servicios: fijos o en % · Servicios en % · El precio sale de una función · El IVA lo suma Presupuestos · Un presupuesto se recalcula como era · Moneda · Tipos de cambio |
| `despiece.md` | El despiece calculado · Las fórmulas se calculan sin SQL dinámico |
| `versiones.md` | Versiones y aprobación · Qué frena el envío |

## Ficha del módulo

En armado, punto por punto con el usuario. Objetivo y personas aprobados el 2026-10-27; sin entes el
2026-10-30 (*Sin entes*), con los registros, los avisos y el árbol de vistas y funciones (*Pestañas*).
Sin `catalogo_ver`: cada pestaña tiene su código, y `/catalogo` abre la primera que el usuario tiene.

```
Módulo: catalogo
Objetivo: definir qué se puede vender y cómo se calcula: los paquetes, cada uno un despiece (sus
piezas armadas y los materiales de cada una), y su precio (los costos de insumos y servicios, y los
servicios en %).
Personas                qué ve · qué hace · qué NO ve
├── Técnica        — insumos, servicios fijos y fórmulas · carga insumos y sus colores, define las
│                    categorías de insumo y de paquete, arma los paquetes (le pone a cada uno su
│                    categoría) y envía cada versión a revisión, da de baja insumos y paquetes ·
│                    servicios en %, costos ni precios
├── Administración — insumos y servicios fijos con su costo, y las categorías · carga los costos de
│                    insumos, da de alta y de baja los servicios fijos y sus categorías, define los
│                    servicios en % y sobre qué categorías se cobran · paquetes ni fórmulas
├── Gerente        — todo: paquetes, fórmulas, costos, % y precios · aprueba o devuelve cada versión
│                    de un paquete · —
├── Vendedor       — NO entra: elige categoría y paquete desde Presupuestos · el precio final, los
│                    nombres de las opciones y los mensajes de alerta y bloqueo · costos, % ni
│                    fórmulas
├── Cliente        — NO entra: lo mismo que el vendedor, desde erp-cliente
├── Producción     — NO entra, salvo quien revisa cortes, con la vista Paquetes: ve las piezas, sus
│                    medidas y las variables marcadas, servicios incluidos, desde Producción (módulo
│                    a hacer) · costos, % ni precios
├── Compras        — NO entra: ve los insumos y su costo desde Compras (módulo a hacer), para
│                    comparar con las cotizaciones · %, precios ni fórmulas
├── Stock          — NO entra: todavía no tiene ficha; lo que lea se decide ahí
└── Logística      — NO entra: trabaja sobre el presupuesto
Entes: ninguno — nada tiene dueño ni chip; lo que ve cada uno lo da el permiso (*Sin entes*)
Registros
├── paquete       — por qué está de baja: a mano, o el insumo o servicio fijo que lo bajó
│   └── versión   — borrador → en revisión → publicado → obsoleto · nombre y categoría · una sola
│       │           abierta por paquete · el gerente la devuelve con motivo · colores que ofrece y
│       │           el base
│       ├── variable     — nombre · número con fórmula o lista de valores · la ingresa el vendedor o no ·
│       │                  predeterminado · condiciones · si pasa a Producción
│       └── pieza armada — nombre · cantidad · si es opcional: predeterminado y qué requiere · peso y
│           │              espesor, y si pasan a Producción
│           └── material — insumo o servicio fijo, único o múltiple (con nombre) · medida y cantidad ·
│                          condiciones
├── insumo        — categoría de insumo, unidad (mm, m2, u), peso y espesor · una variante por color,
│                   cada una con su costo con fecha y moneda · todo se edita hasta enviar una versión
│                   que lo usa; después, el costo, las variantes, si está activo, y completar un peso
│                   o espesor vacío
├── color         — lista común, la define Técnica · se edita y se da de baja como las categorías
├── servicio fijo — como el insumo, sin peso, espesor ni color, en una categoría de servicio
├── categoría     — de paquete y de insumo (las define Técnica), de servicio (Administración) · se
│                   edita hasta tener algo adentro; de baja, solo sin nada activo adentro
└── servicio en % — su %, su paso (1: el despiece o ciertas categorías · 2: el subtotal · 3: el precio
                    final), mínimo con moneda, por paquete o por presupuesto, si es opcional · cada
                    cambio es un valor nuevo con fecha
Eventos: ninguno (sin entes). Los avisos van por notificaciones; gerente es quien tiene catalogo_aprobar
y Técnica, quien tiene catalogo_armar:
├── insumo o variante nueva     → quienes cargan costos · desaparece cuando tiene costo
├── categoría de insumo nueva   → quienes definen los servicios en %
├── baja de insumo              → gerente, si sacó algo de la venta: los paquetes que siguen de baja
│                                 por ella y lo que dejaron de ofrecer
├── baja de servicio fijo       → gerente y Técnica, si sacó algo de la venta
├── cambio en un servicio en %  → gerente: apunta al cambio en la historia, para revertirlo
├── cambio revertido            → quien hizo el cambio
├── versión enviada a revisión  → quienes aprueban · desaparece al aprobarla, devolverla o retirarla
└── versión aprobada o devuelta → quien la envió · con el motivo si fue devuelta

Catálogo
├── Paquetes (vista, catalogo_paquetes)          — técnica, gerente, quien revisa cortes: por
│   │                                              categoría, con versiones y despiece, sin precio
│   ├── catalogo_armar (funcion)                 — técnica: paquetes y sus categorías, versiones;
│   │                                              envía, retira, duplica, da de baja y reactiva
│   └── catalogo_aprobar (funcion)               — gerente: "Por revisar", el precio y su detalle
│                                                  de cualquier versión, aprueba y devuelve
├── Insumos (vista, catalogo_insumos)            — técnica, administración, gerente: sin costo
│   ├── catalogo_cargar (funcion)                — técnica: alta, variantes y categorías de insumo,
│   │                                              colores, edición hasta que se envía, baja y
│   │                                              reactivación
│   └── catalogo_costos (funcion)                — administración, gerente: ve y carga el costo
├── Servicios fijos (vista, catalogo_fijos)      — técnica, administración, gerente: sin costo
│   └── catalogo_fijos_editar (funcion)          — administración, gerente: alta con costo, edición
│                                                  hasta que se envía, costo, baja, categorías
└── Servicios en % (vista, catalogo_porcentajes) — administración, gerente: con su historia
    └── catalogo_porcentajes_editar (funcion)    — administración, gerente: alta, cambios, baja y
                                                   reactivación, revertir
Delegables
├── sí — las cuatro vistas · catalogo_armar · catalogo_cargar · catalogo_costos ·
│        catalogo_fijos_editar · catalogo_porcentajes_editar
└── no — catalogo_aprobar
Reglas entre permisos: ninguna, ni requiere ni excluye
```

Pendientes de la ficha:
- **Si el perfil se compra por kilo.** Si es así, se evalúa un costo por kilo que use el peso del insumo; si
  se compra por metro o por barra, no hace falta nada.
- **Aprobar la ficha completa.** Después, el SQL.
