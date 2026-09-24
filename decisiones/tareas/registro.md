# Tareas — historial, notas y referencias

`tareas_ediciones`, notas, lo congelado, referencias a entes y `tareas_vinculos`.

**Toda edición de contenido deja historial (`tareas_ediciones`) y lo cerrado se congela.**
`eventos` no guarda valor anterior (`decisiones/global/entes.md`), por eso tabla aparte escrita por
trigger. Completado o cancelado no se edita: nota o reabrir, que emite y avisa.

**`tareas_administrar` oculta una nota o una entrada del historial (2026-09-24).** `activo = false`
con quién y cuándo, nunca DELETE; la RLS deja de mostrarla. Si no, una clave o un dato personal
pegado por error, o el texto viejo de una descripción corregida, quedaba para siempre a la vista de
todos los que ven el hilo. Ocultar no es borrar: lo filtrado se da por visto (una clave, se cambia).

**Referencias en el texto en vez de chips.** `{nombre}` de la plantilla se guarda como
`{obra:uuid}` + copia del nombre; se ve como link ↗ que abre la ficha al lado si se puede abrir, y
como texto plano si no. Aplica *Un ente en un texto es una referencia* (`decisiones/global/entes.md`),
corregida para mostrar la copia en vez de nada: el paso tiene que entenderse, y el nombre lo contó
quien sí lo veía.
`tareas_vinculos` queda como dato (hilos de un registro, `plantilla_disparada`) y la escribe la
base desde el texto: una sola fuente. Vincular a mano: textarea + "Relacionar" que inserta la
marca, con vista previa; editor enriquecido solo si no alcanza (librería nueva, consultar).

**La RLS de `tareas_vinculos` es la del hilo, no la del ente referenciado (2026-09-24).** Quien ve
una obra pero no participa de un hilo que la nombra no ve ese hilo en la ficha de la obra. El título
sale siempre de `etiqueta_registro` (INVOKER, hereda la RLS), nunca de una copia.

**La referencia es `{ente:uuid|nombre}` y solo se lee de la descripción del paso (2026-09-24).** Un
solo token con la copia adentro: una regex la saca, y `{dato}` de plantilla (sin `:uuid|`) no se
confunde. Es el único campo "con referencias" de la ficha; título, notas y resultado quedan en texto.
Sumar una referencia pide ver lo referenciado (TA021): si no, cualquiera metía su hilo en la ficha
de un registro ajeno. Lo que copia la base (recurrencia) no se vuelve a revisar. Rol y plantilla del
vínculo esperan al disparo. Archivos: `sql/119_tareas_vinculos.sql`, `sql/tests/tareas_vinculos.sql`.

**La ficha del ente se abre al lado del paso.** Split en desktop, encima con "volver" en mobile.
Cada módulo con entes aporta su ficha; el registro ente → componente vive en `app/`.

