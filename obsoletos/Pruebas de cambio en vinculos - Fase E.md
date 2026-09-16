Pruebas manuales de la Fase E de PLAN_TAREAS_VINCULOS.md — "Compartir al asignar: la pregunta".
Dos sesiones logueadas: ADMIN y TESTER (dos navegadores, o uno normal + uno incógnito).

1. Compartir al crear una tarea

1. Con ADMIN, en Tareas → Nueva tarea: relacioná una obra propia de ADMIN y asigná a TESTER.
2. Esperado: al guardar aparece el panel "Antes de guardar" con la obra tildada (TESTER no puede abrirla).
3. Tocá "Compartir y guardar".
4. Esperado: TESTER queda asignado, ve el chip de la obra en la tarea y puede abrirla.

2. Guardar sin compartir

1. Repetí el paso 1.1, pero tocá "Guardar sin compartir".
2. Esperado: TESTER no queda asignado; un toast lo avisa. Si TESTER era el único asignado, la tarea queda para ADMIN con una nota.

3. Cerrar el panel con la X equivale a no compartir

1. Repetí el paso 1.1, pero cerrá el panel con la X (o Escape/backdrop).
2. Esperado: mismo resultado que "Guardar sin compartir" (paso 2).

4. Reasignar

1. Con ADMIN, en una tarea relacionada con una obra de ADMIN, usá "Reasignar" para poner a TESTER.
2. Esperado: mismo panel que en el paso 1.2.

5. Relacionar sobre una tarea existente

1. Con ADMIN, en una tarea donde ya está TESTER asignado, usá "Relacionar" para sumar una obra propia de ADMIN.
2. Esperado: aparece el panel; sin compartir, TESTER sale de la tarea (deja de estar asignado).

6. Relacionar sin permiso para sacar a nadie

1. Con un usuario asignado que NO tiene el permiso `tareas_asignar`, intentá relacionar (desde el panel de la tarea) algo que otro asignado no puede ver y que no es tuyo.
2. Esperado: da un error (toast: "...no tenés permiso para sacarlo de la tarea..."), no aparece el panel.

7. Disparo de plantilla al editar el estado de una obra

1. Preparación: ADMIN tiene una plantilla con disparo en el estado "En cotización" y un paso asignado a TESTER.
2. ADMIN edita una obra existente propia y la pasa a "En cotización".
3. Esperado: aparece el panel "Antes de guardar" antes de confirmar el cambio de estado.
4. Compartí.
5. Esperado: TESTER recibe la tarea que crea la plantilla y puede abrirla.

8. Disparo sin compartir

1. Repetí el paso 7, pero sin compartir.
2. Esperado: la tarea no le llega a TESTER. La campanita de notificaciones de ADMIN avisa que alguien quedó afuera (`plantilla_sin_acceso`).

9. Crear una obra ya en el estado que dispara

1. ADMIN crea una obra nueva directamente en "En cotización" (el estado de la plantilla del paso 7).
2. Esperado: NO aparece ningún panel (al crear no se pregunta). TESTER queda afuera de la tarea igual, y llega el aviso por notificación — mismo resultado que el paso 8, sin la pregunta previa.

---

Si un paso no se comporta como se espera, anotar cuál y en qué difiere — no hace falta rehacer todo
el flujo para reportarlo.

Cuando los 9 pasos pasen: tachar "Fase E" en PLAN_TAREAS_VINCULOS.md con el mismo formato que las
fases A-D, borrar la entrada de BACKLOG.md sobre la prueba pendiente, borrar PLAN_TAREAS_VINCULOS.md
(la decisión ya quedó en decisiones/tareas/visibilidad.md), y mover este archivo a obsoletos/ con
una fila en obsoletos/README.md (mismo patrón que las Fases A y B).
