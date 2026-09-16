# Pruebas de cambio en plantillas — texto y pasos que dependen de un rol (`sql/065`)

Base aplicada y tests SQL en verde (`plantillas_roles.sql` 13/13, `plantillas.sql` 27/27,
`plantillas_disparo.sql` 34/34). Falta la UI en el navegador.

Preparación: una obra en `idea` con una persona con rol **Arquitecto** y sin **Inmobiliaria**.

## Editor (Tareas → Plantillas → Nueva)

1. Tipo **Hilo**, "Cuándo se usa" = **Sola, cuando una obra cambia de estado**, estado **En cotización**.
   Debajo del título y la descripción de cada paso aparece el select **Texto solo si…**, junto al chip
   "Nombre de la obra".
2. Escribir `Llamar al arquitecto`, seleccionar `al arquitecto` y elegir **Si la obra tiene una persona
   con rol… → Arquitecto**. El texto queda `Llamar {si hay persona:arquitecto}al arquitecto{fin}` y el
   cursor, después de `{fin}`.
3. Sin seleccionar nada, elegir **Si la obra no tiene una empresa con rol… → Inmobiliaria**. Se inserta
   `{si no hay empresa:inmobiliaria}{fin}` con el cursor entre las llaves.
4. La vista previa muestra dos líneas: **Con arquitecto y inmobiliaria: …** y **Sin ninguno: …**. Con un
   solo rol en el texto, **Con arquitecto: …** y **Sin arquitecto: …**.
5. Un texto sin bloques sigue mostrando la línea de siempre, **Así se va a ver: …**, solo si tiene datos.
6. En **Se crea** del paso aparecen los dos grupos (tiene / no tiene). Elegir **no tiene → Inmobiliaria**,
   plegar el paso: el resumen dice **Solo si no hay inmobiliaria**.
7. Sin disparador (**A mano**), no aparece el select ni la sección de roles.
8. Guardar, reabrir: los bloques y la condición negada vuelven como se guardaron.

## Disparo

9. Pasar la obra a **En cotización**. El paso con **Solo si no hay inmobiliaria** se crea; el título dice
   `Llamar al arquitecto` (sin llaves) y el bloque `si no hay` sin texto no deja rastros.
10. Un paso con **Solo si no hay arquitecto** no se crea, y el siguiente se encadena al anterior creado.
