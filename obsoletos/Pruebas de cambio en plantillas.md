1. Obras terminadas ocultas

1. En /obras, abrí una obra, editala y pasala a Terminada.
2. Esperado: desaparece de "Todas" y el número de "Todas" baja. Tocando el chip Terminada, aparece.

2. Nombre de lo que crea una plantilla

1. En Tareas → Plantillas, creá una plantilla de tipo Hilo o Proyecto.
2. Esperado: hay un campo "Título del hilo que crea" (o "Nombre del proyecto que crea") con el nombre de la plantilla como placeholder.
3. Completalo, guardá y usala dejando vacío el título en "Usar".
4. Esperado: el hilo o proyecto se crea con el nombre que pusiste en ese campo, no con el de la plantilla.

3. Hilos en paralelo

1. En una plantilla de tipo Hilo, arriba de los pasos, elegí En paralelo.
2. Esperado: en los pasos desaparece la opción de vencimiento "Tras el paso anterior".
3. Guardá.
4. Esperado: en la lista de plantillas los pasos aparecen separados por coma en vez de "→".
5. Usala.
6. Esperado: en la Lista, ningún paso del hilo aparece bloqueado esperando al anterior.
7. En una plantilla de tipo Proyecto, revisá los hilos.
8. Esperado: cada hilo tiene su propio selector "Encadenados / En paralelo".

4. Tareas relacionadas con obras, empresas y personas

1. Abrí la ficha de una obra y bajá hasta el final.
2. Esperado: hay una sección Tareas con el botón Nueva tarea.
3. Tocá Nueva tarea.
4. Esperado: vas a Tareas con el formulario abierto y la obra ya cargada como chip en "Relacionada con".
5. Creá la tarea.
6. Esperado: volvés a la ficha y la tarea aparece listada con su estado.
7. Tocá el título de la tarea en la ficha.
8. Esperado: se abre su panel en Tareas.
9. En el panel de cualquier tarea, tocá Relacionar y buscá al  o persona. Elegila.
10. Esperado: aparece un chip que abre su ficha. La × lo quita.
11. Revisá las fichas de empresa y de persona.
12. Esperado: tienen la misma sección Tareas.
13. Entrá con TESTER, que no ve la obra de ADMIN.
14. Esperado: en una tarea que TESTER sí ve, no aparece el chip de esa obra, y el buscador tampoco la ofrece.

5. Roles de la obra en la plantilla

1. Preparación: en una obra tuya, vinculá una persona con rol Arquitecto y una empresa con rol Constructora. No le pongas ninguna Inmobiliaria.
2. Creá una plantilla privada de tipo Hilo. En "Cuándo se usa" cambia de estado" y un estado, por ejemplo En cotización. Lasprivadas arrancan activadas.
3. Armá tres pasos (en cada uno, abrí los detalles):
   - Paso 1: en "Adjuntar a la tarea" marcá Arquitecto, y en "Se crea" elegí Arquitecto (en el grupo de persona).
   - Paso 2: en "Se crea" elegí Inmobiliaria.
   - Paso 3: adjuntá Constructora.
4. Esperado: el resumen plegado del paso 2 dice "Solo si hay inmobiliaria".
5. Editá la obra y pasala a ese estado.
6. Esperado:
   - La campanita avisa que la plantilla corrió.
   - Se crean los pasos 1 y 3, y el 3 espera al 1.
   - El paso 2 no se crea.
   - El panel del paso 1 muestra el chip de la persona; el del paso 3, el de la empresa. Ninguno de esos chips tiene ×.
7. Probá una plantilla donde todos los pasos pidan un rol que
8. Esperado: no se crea nada y no llega aviso de fallo.
9. Cambiá una plantilla con roles a "A mano, desde esta vista".
10. Esperado: la sección de roles desaparece y al guardar se descartan.

6. Link de origen heredado dentro del hilo

1. Abrí una tarea creada por la plantilla de la prueba 5. En vez de "Generado por obras — ir", muestra el chip de la obra.
2. Tocá Convertir en hilo.
3. Esperado: el panel del hilo muestra "Generado por obras — i
4. Dentro del hilo, usá Agregar tarea, o Crear siguiente paso desde la tarea.
5. Esperado: la tarea nueva también muestra ese link.

Para repetir un disparo: cada plantilla corre una sola vez por obra. Para volver a probar con la misma obra, desactivá lo que generó (alcanza con desactivar el hilo), sacá la obra de ese estado y volvé a ponerla.

Todavía no está (punto 3): si asignás una tarea a alguien que sona, no se le pregunta nada y esa persona simplemente no ve el chip.