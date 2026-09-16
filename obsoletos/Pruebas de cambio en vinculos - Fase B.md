1. Nueva tarea desde la ficha de una obra

1. Entrá a la ficha de una obra propia (ADMIN) y bajá a la sección Tareas.
2. Tocá Nueva tarea.
3. Esperado: el formulario se abre como panel sobre la ficha (no navega a /tareas). En "Relacionada con" ya aparece el chip de la obra.
4. Completá título y asignados, y guardá.
5. Esperado: seguís en la ficha, el panel se cierra y la tarea nueva aparece en la sección Tareas.

2. Abrir y completar una tarea desde la ficha

1. En la misma sección, tocá la tarea recién creada.
2. Esperado: se abre su panel de detalle sobre la ficha.
3. Marcala como completada.
4. Esperado: el badge de la isla cambia a "Completada" sin salir de la ficha.
5. Cerrá el panel.
6. Esperado: seguís en la ficha (no hay redirección a /tareas).

3. Paso de hilo bloqueado en la ficha

1. Relacioná con la obra una tarea que sea el segundo paso de un hilo, con el primer paso sin completar.
2. Esperado: en la sección Tareas de la ficha, ese paso muestra el badge "Bloqueada" y "Paso N/M", y el panel no ofrece la acción de completar.

4. Empresa y persona

1. Repetí 1-2 en la ficha de una empresa propia y en la de una persona propia.
2. Esperado: mismo comportamiento — el form y el panel se abren sobre la ficha.

5. Usuario sin la vista de Tareas

1. Entrá con un usuario sin el permiso `tareas_lista` (o quitáselo temporalmente a TESTER).
2. Abrí una ficha de obra, empresa o persona.
3. Esperado: la sección Tareas no aparece.

6. La campanita sigue llevando a /tareas

1. Con TESTER, hacé que le asignen una tarea (para que le llegue la notificación "te asignaron X").
2. Tocá la notificación.
3. Esperado: sigue abriendo `/tareas` con el panel de esa tarea, filtrado a lo propio de TESTER (no cambió respecto de antes de esta fase).

7. La Lista de Tareas sigue andando sin `?nueva=`

1. Entrá a /tareas directamente (sin querystring) y tocá "Nueva tarea" desde ahí.
2. Esperado: el form abre sin ningún vínculo precargado, igual que siempre.

8. Refresco sin duplicar pedidos (Network)

1. Con las herramientas de desarrollador abiertas en la pestaña Network, completá o reasigná una tarea desde la sección Tareas de una ficha.
2. Esperado: la ficha se actualiza sola (sin F5) y no se ve un pedido duplicado a la misma ruta.
3. Repetí completando una tarea desde /tareas (la Lista).
4. Esperado: tampoco se dispara un refresh doble ahí.
