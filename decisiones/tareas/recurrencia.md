# Tareas — recurrencia

Hilos recurrentes: intervalo, cierre y qué copia el siguiente.

**Recurrencia a nivel hilo**: al cerrarse nace el siguiente. Sin `pg_cron`, como en `master`.
Intervalo `recurrencia_cantidad` + `recurrencia_unidad` (`dia` | `mes`) de `master` (`sql/005`):
semanal = 7 días, anual = 12 meses.

**Cada cierre genera un siguiente, también tras reabrir.** Elegido por el usuario sobre guardar
`siguiente_id`: reabrir y volver a cerrar da otro ciclo, y el duplicado se cuida a mano.
Precisado el 2026-09-24: ahora reabre cualquier asignado, y en cascada, así que quien cierra no
sabe que ya se generó. El hilo nuevo guarda `recurrencia_de`; si ya existe un siguiente, el cierre
pregunta "ya generó <link> — ¿generar otro?", con "no" por defecto. De paso, navega entre ciclos.

**Cerrar un hilo recurrente pregunta si sigue (2026-09-24).** "Generar el siguiente" o "Terminar la
recurrencia" (saca la recurrencia y no genera nada). Por defecto genera en un cierre común y termina
en "Cancelar pendientes y cerrar": si no, cerrar algo que ya no va hacía nacer otro ciclo con sus
avisos. Absorbe el aviso de arriba: si ya hay siguiente, "generar" pasa a "¿generar otro?", con "no".

**El siguiente copia los pasos, sin lo hecho.** Títulos, descripciones, cadena, asignados y
prioridad, todo sin completar; los vencimientos se corren por el intervalo desde el vencimiento
anterior, no desde el cierre, sin saltear ciclos: cada ciclo es un período, el atrasado nace
vencido y se descarta con "Cancelar pendientes y cerrar". Fin de mes sigue siendo fin de mes (si
el anterior era el último día, el siguiente también); el 29 o 30 que cae en febrero queda en su
último día (28 o 29).
Los relativos al previo se copian tal cual (precisado el 2026-09-24). Sin notas, resultados
ni historial. El estado no se copia: cada paso nace con las reglas de siempre, con la membresía
de hoy (precisado el 2026-09-24; copiar dejaba `pendiente` a un compañero que ya era de otro
equipo). Un paso cuyo asignado no puede recibir (*Solo se asigna a quien puede recibirlo*), o que
sería un pedido y el responsable ya no tiene `tareas_pedir`, nace asignado al responsable con aviso
para reasignarlo: la recurrencia nunca falla. Los pedidos válidos nacen `solicitada` y se vuelven a
aceptar. Se copia el asignado final: si el delegador repartió "al equipo" a Juan, el siguiente va
a Juan.

