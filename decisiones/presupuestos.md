# Decisiones — módulo Presupuestos

> **Estado: ficha aprobada (2026-11-05), revisada punto por punto con el usuario. Sin SQL ni pantallas.**
> Se armó desde cero, sin partir del backlog, y se contrastó con él al final. Lo que falta, en `BACKLOG.md`
> → *Presupuestos*.

## Ficha del módulo

```
Módulo: Presupuestos
Objetivo: armar presupuestos sin cálculo a mano, que se puedan reproducir para ubicar un error y
          modificar manteniendo las condiciones de la cotización original o actualizándolas, y
          presentárselos al cliente de forma más interactiva que un PDF
Personas                qué ve · qué hace · qué NO ve
├── Vendedor       — los presupuestos de las obras que ve, con precios y comparación antes/después
│                    · en las obras que trabaja: arma, publica, corrige, registra aprobación y rechazo
│                    · costos, márgenes y presupuestos de obras ajenas
├── Jefe comercial — lo del vendedor, sobre las obras de su equipo · además autoriza "mantener" y
│                    descuentos sobre el tope, revierte, recibe aviso de renglón a mano · costos
├── Gerencia       — todos, con comparación y, con catalogo_aprobar, detalle con costos · actúa en todos,
│                    autoriza, revierte, configura · —
├── Técnica        — los presupuestos con alertas, completos · autoriza o devuelve · precios
├── Cliente        — en erp-cliente, lo publicado con referencias en otras monedas · compara, elige
│                    opcionales por ventana, confirma · costos, comparación, versiones reemplazadas.
│                    No rechaza ni pide cambios: eso lo habla con el vendedor
├── Administración, producción, logística, colocación — NO usan el módulo: trabajan en el de
│                    ejecución y cobros (futuro), que toma lo aprobado. Producción y logística no ven precios
└── Post-venta     — NO usa el módulo: el suyo (futuro) apunta a los ítems del presupuesto aprobado

Entes
└── presupuesto — sin dueño propio: sigue a la obra; creado_por como registro
                · estado estado_presupuesto: borrador → publicado → aprobado | rechazado
                · datos {numero, nombre} · ruta /presupuestos/{id} · submódulo presupuestos_ver
                · disparos {alta, estado}
No son entes
├── versión — tipo: actualización o corrección | variante · moneda propia · vencimiento · IVA
│             discriminado o incluido · estado: borrador → (en_revision) → publicado → obsoleto;
│             lo publicado no se edita; una publicada por variante
└── renglón — designación y ubicación ("V4 · Lavadero") · cantidad · alícuota · precio escrito
              de Catálogo: paquete y versión, fecha de condiciones, lo cargado, opcionales
              a mano: descripción y precio · de mínimo: el que calcula Catálogo

Relaciones
└── presupuesto → obra (FK obra_id, obligatoria). Sin obra: calculadora sin guardar u obra mínima

Acciones
└── crear · armar · publicar · corregir · sumar variante · pedir autorización · autorizar · devolver
    · aprobar · rechazar con motivo · revertir con causa · imprimir · desactivar sin publicar

Eventos que emite
└── presupuesto: alta · estado — los escucha Obras; también disparan las plantillas de ejecución
Eventos que consume
└── ninguno

Presupuestos
├── Presupuestos (vista, presupuestos_ver)       — vendedor, jefe comercial, gerencia
│   ├── presupuestos_armar (funcion)             — vendedor, jefe comercial, gerencia: incluye la calculadora
│   └── presupuestos_autorizar (funcion)         — jefe comercial (su equipo), gerencia (todos)
├── Todos (vista, presupuestos_todos)            — gerencia: sin necesitar la obra
├── Revisión técnica (vista)                     — técnica: completos, sin precios
│   └── presupuestos_autorizar_tecnica (funcion) — técnica
└── Configuración (vista)                        — gerencia: tope, plazo, monedas de referencia
    └── presupuestos_configurar (funcion)        — gerencia

Reglas entre permisos: presupuestos_ver requiere obras_ver · presupuestos_autorizar no se delega
```
Aprobada el 2026-11-05.

Pendientes:
- **Reversión con la ejecución en marcha:** no se puede revertir si ya empezó, pero falta definirlo con ese módulo. Propuesta
  para el hilo ya generado: queda abierto con un aviso, y alguien lo cierra a mano; depende de Tareas.
- **Flete:** probar con un caso real que Catálogo arme los paquetes por km y por hora.
- **Delegación de `presupuestos_ver` y `presupuestos_armar`:** sin decidir. Obras delega las equivalentes. Confirmar al escribir
  el SQL.

## Estados y versiones

**El presupuesto termina en `aprobado` o `rechazado`, no en `cerrado`.** Obras necesita saber si se aprobó, y "cerrado" no lo
dice. Un solo estado, sin segunda columna (`GUIDE_ENTES.md` §2.1).

**Hay dos tipos de versión: actualización o corrección, que reemplaza a la anterior al publicarse, y variante, que convive.**
Aluminio v1 a $100 pasa a v2 a $120: la v1 sigue valiendo hasta que se publica la v2. Aluminio y PVC se publican juntas.

**Lo que se aprueba junto va en presupuestos separados; lo que compite, en variantes.** Por eso aprobar y rechazar son decisiones
sobre el presupuesto entero: al aprobar una variante, el resto se inhabilita; al rechazar, caen todas. Así, `rechazado` significa
solo que el cliente dijo que no a todo, y una variante no elegida no cuenta como rechazo.

**La versión guarda solo su ciclo (`borrador`, `en_revision`, `publicado`, `obsoleto`); el presupuesto guarda cuál se eligió.**
"Aprobada" e "Inhabilitada" se calculan al mostrar: el mismo hecho en dos lugares podía desalinearse. Los nombres y el sentido son
los de Catálogo (`db_schema/catalogo.md` → *El ciclo*), salvo que acá hay varias publicadas a la vez, una por variante.

**Todo rechazo pide motivo, con la lista de Obras (`motivo_perdida`) y detalle.** Permite contar por qué se rechazan los
presupuestos, y la obra lo toma si queda perdida.

**Una aprobación o un rechazo equivocados se revierten, con causa escrita.** Lo hacen el jefe comercial o gerencia. Vuelve a
`publicado` y, si no queda otro aprobado, la obra deja de estar `contratada`. Un clic equivocado no puede quedar para siempre,
el mismo criterio de Obras.

## Efectos en la obra

**Obras lee el presupuesto, nunca las versiones.** Publicar, corregir o sumar una variante no la mueve. Si está `contratada`, un
presupuesto nuevo o rechazado tampoco.

| En el presupuesto | En la obra |
|---|---|
| Se crea el primero | `en_cotizacion` |
| Se crea uno en una obra `perdida` | Se reabre a `en_cotizacion` |
| Se aprueba el primero | `contratada`, firme salvo reversión |
| Se rechaza y no quedan abiertos ni aprobados | `perdida`, con el motivo del rechazo |

**La obra pasa sola a `perdida` y vuelve sola (decisión del usuario).** Se evaluó que el sistema preguntara antes: el usuario
prefirió que la obra siga a sus presupuestos. Etapa 1 rechazada con la Etapa 2 abierta no la mueve.

**Para marcarla `perdida` a mano, primero se resuelven sus presupuestos abiertos.** Se descartó rechazarlos en cascada: reabrir la
obra no los recuperaba, y alguien podía rechazar un presupuesto ajeno por poder marcar la obra. Se descartó dejarlos como están:
uno publicado se podía aprobar en una obra perdida.

**Todo presupuesto tiene obra.** Toda la visibilidad y los efectos dependen de ella. Para "¿cuánto sale una ventana?": la
calculadora sin guardar (`catalogo_precio`). Para un presupuesto formal: una obra mínima, que después se completa, sin transferir
nada. Se descartó una obra genérica "Consultas": con el primer aprobado quedaba `contratada` para siempre, y mezclaba clientes,
contactos y números. Costo: la dirección es obligatoria, y una de relleno repetida congela el alta.

## Quién accede

**Quien trabaja la obra trabaja sus presupuestos.** Se trabaja en equipo y el equipo decide quién arma, así que el sistema no lo
asigna: se usan los niveles de Obras (ve, trabaja, a cargo; `db_schema/obras.md`), sumando un participante si hace falta. Se
descartó que todo el equipo vea todo (Obras oculta las obras ajenas) y una lista por presupuesto (una segunda forma de dar acceso).
Quien crea un presupuesto no gana poder sobre la obra: quien la trabaja ya puede cambiarle el estado.

**Gerencia ve todo y actúa (decisión del usuario).** Autoriza también, cubre la ausencia del jefe y ubica los errores con el detalle
de costos, sin permiso nuevo: `catalogo_aprobar`.

**El vendedor ve lo que cargó, el precio y los mensajes del paquete; no ve costos ni despiece.** Sus errores más probables están en
lo que carga, y Catálogo ya avisa ("No se puede calcular con estas medidas"). Lo demás lo deriva.

**Administración, producción, logística y colocación no usan el módulo.** Cobros y habilitaciones van en otro módulo, que toma lo
aprobado y muestra lo que cada área necesita. Sin acceso, no hay riesgo de que producción y logística vean precios. Se había
propuesto una vista Aprobados para administración: se sacó porque no tenía función. Costo: hasta que exista ese módulo, se lo piden
a ventas.

## Precio

**Mantener o actualizar se elige por ventana, y mantener trae la fecha, no solo la versión y el tipo de cambio.** Si el aluminio pasa
de USD 12 a USD 14 sin versión nueva del paquete, el precio cambia aunque se mantengan esos dos datos. La fecha trae juntos costos,
servicios y tipo de cambio (`decisiones/catalogo/precio.md` → *Un presupuesto se recalcula como era*). Solo hay dos valores, nunca una
fecha libre (`decisiones/catalogo/precio.md`, 2026-10-29). Por ventana porque un modelo nuevo puede no tener precio a la fecha vieja: por
versión, obligaba a mover las demás.

**Mantener pide autorización del jefe comercial, o de gerencia, dentro del sistema.** Resigna margen, así que queda registrado quién,
cuándo y qué diferencia. La versión pasa por `en_revision`, autoriza la versión entera, y si no está de acuerdo la devuelve con motivo.
Sin el permiso, las ventanas arrancan a hoy. Gerencia y ventas ven la comparación antes y después. Cada versión nueva se autoriza de
nuevo: la diferencia crece con el tiempo. Si el jefe lleva la obra, se autoriza solo.

**El renglón a mano no pide autorización: le avisa al jefe comercial al publicar (decisión del usuario).** Con descripción y precio, que
no se recalcula. Para lo que no está en Catálogo.

**El flete habitual va en Catálogo, como dos paquetes: por km y por hora.** Se carga la cantidad y la tarifa sale con fecha. Un precio
cerrado de un fletero va a mano. Si todo flete fuera a mano, el jefe recibiría un aviso por cada uno.

**El descuento va sobre el total de la versión: hasta un tope, libre; por encima, autorización.** El cliente lo ve como un renglón. Un
solo tope para toda la empresa, que cambia gerencia, con historial.

**Una alerta del paquete pide autorización de Técnica antes de publicar; un bloqueo no publica.** Las dos autorizaciones se piden juntas:
se publica cuando autorizan todos, y si uno devuelve, vuelve a `borrador`. La de Técnica vale mientras la ventana no cambie: mismo
paquete, versión y datos cargados dan el mismo resultado. Técnica ve el presupuesto completo sin precios, porque una ventana puede
depender de la de al lado.

**Una opción dada de baja se puede mantener con autorización de Técnica, pero no elegir en una ventana nueva.** Distingue un material sin
stock de uno que queda para un caso puntual.

**Las versiones vencen, con un plazo único que define gerencia.** Al vencer, el portal no deja confirmar, y una versión nueva se
actualiza libre o se mantiene con autorización. "Vencido" se calcula, no se guarda: sigue `publicado`, la obra no cambia y no cuenta como
rechazo.

**Los mínimos son un renglón aparte, con su alícuota y su mantener o actualizar.** Con mantener, autorización, como cualquier ventana.
`catalogo_precio_minimos` calcula hoy a la fecha de hoy: hay que ampliarla con la versión y la fecha de cada renglón.

**Se guarda el precio escrito y los datos para recalcularlo, sin copiar costos ni porcentajes.** La versión sigue diciendo lo que vio el
cliente, aunque se corrija algo en Catálogo, y recalcular sirve para encontrar errores: si no coincide, hay algo para investigar.

**Las ventanas se cargan una por una, con duplicar.** Cada carga pasa por las validaciones de Catálogo. Importar planillas va al backlog:
cada arquitecto la arma distinto, y hay que resolver de qué paquete es cada renglón.

## Moneda e IVA

**La moneda es por versión, elegida por el vendedor.** "Pasámelo en dólares" es una versión nueva. Arranca en la principal, y si las
variantes publicadas quedan en monedas distintas, el sistema avisa antes de publicar.

**El cliente ve referencias en otras monedas, al tipo de cambio del día, solo informativas.** Aprueba en la moneda de la versión. Gerencia
elige cuáles se muestran, para todos; arrancan pesos y dólar oficial, para no exponer el blue. Cada vez que el ERP actualiza los tipos de
cambio, los escribe en el portal, y este solo los usa para mostrar.

**Siempre tipo de cambio de venta.** Lo que pase al cobrar en billetes se resuelve en el módulo de cobros (`BACKLOG.md`). Monedas no cambia.

**El IVA es por renglón: 21 %, 10,5 % o 0 %, discriminado o incluido, siempre después del descuento.** Se mezclan alícuotas dentro de un
mismo presupuesto. La versión exige elegir una alícuota al armarla, cada renglón la toma y puede cambiarla. Un renglón de IVA por alícuota,
con el descuento repartido proporcionalmente. Lo que no lleva IVA va al 0 %. El precio de Catálogo llega sin IVA
(`decisiones/catalogo/precio.md` → *El IVA lo suma Presupuestos*).

## El cliente y el portal

**Toda la comunicación la inicia el ERP: al publicar escribe en `erp-cliente`, y de ahí lee las confirmaciones.** `erp-cliente` no envía
nada y su confirmación queda allá como constancia, sin autoridad (`GUIDE_SYNC.md`). Se asume que el portal tiene base propia; lo define su
ficha, que hoy no existe.

**El ERP lee como Monedas: cada hora, al abrir una página, y con un botón.** Con una confirmación nueva, Juan recibe un aviso, la ve en la
ficha y registra `aprobado`. Si es de una versión reemplazada, no se puede aprobar: Juan habla con el cliente.

**El cliente ve, compara, elige opcionales y confirma.** Rechazos y cambios los habla con el vendedor, y Juan los registra. No cambia
medidas ni ve un precio nuevo: el portal no calcula ni le pide nada al ERP. Ve el precio de cada ventana, y no las versiones reemplazadas.

**Elige opcionales ventana por ventana, todos, y el ERP le envía cada combinación ya calculada.** El efecto de un opcional no se suma: los
servicios van en cascada. Lo elegido queda con la confirmación, y la versión no cambia. Una combinación con un bloqueo o una alerta no
autorizada no se ofrece, para no saltear a Técnica. Aceptado: destildando, puede ver menos que con el vendedor.

**Si un mínimo hace que el total exacto difiera de lo que vio el cliente, Juan no puede aprobar hasta resolverlo.** Los mínimos dependen de
todas las ventanas juntas, así que no salen de la suma. El ERP compara al leer la confirmación.

**Una versión imprimible desde el ERP, además del portal.** Se imprime o guarda como PDF desde el navegador, sin librería nueva y sin costos
ni comparación. Permite usar el módulo sin el portal, y queda como respaldo.
