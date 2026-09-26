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
`tareas_vinculos` queda como dato (pasos que mencionan un registro; los hilos *sobre* un registro salen del hilo, `catalogo.md`) y la escribe la
base desde el texto: una sola fuente. Vincular a mano: textarea + "Relacionar" que inserta la
marca, con vista previa; editor enriquecido solo si no alcanza (librería nueva, consultar).

**La RLS de `tareas_vinculos` es la del hilo, no la del ente referenciado (2026-09-24).** Quien ve
una obra pero no participa de un hilo que la nombra no ve ese hilo en la ficha de la obra. El título
sale siempre de `etiqueta_registro` (INVOKER, hereda la RLS), nunca de una copia.

**La referencia es `{ente:uuid|nombre}` y solo se lee de la descripción del paso (2026-09-24).** Un
solo token con la copia adentro: una regex la saca, y `{dato}` de plantilla (sin `:uuid|`) no se
confunde. Es el único campo "con referencias" de la ficha; título, notas y resultado quedan en texto.
Sumar una referencia pide ver lo referenciado (TA021): si no, cualquiera metía su hilo en la ficha
de un registro ajeno. Lo que copia la base (recurrencia) no se vuelve a revisar. ~~Rol y plantilla del vínculo esperan al disparo~~ → el vínculo
no los lleva: registro y plantilla viven en el hilo (`catalogo.md` → *El hilo guarda su registro*). Archivos: `sql/119_tareas_vinculos.sql`, `sql/tests/tareas_vinculos.sql`.

**Un token fuera de la descripción se muestra como su nombre, sin link (2026-09-24).** Si alguien
pega `{ente:uuid|nombre}` en una nota o en un resultado, no se ve el uuid ni se vuelve referencia:
`sinReferencias` (`derivados.ts`) deja el nombre. Archivos: `NotasSection.tsx`, `PasoPanel.tsx`, `HiloView.tsx`.

**Los vínculos siguen al `activo` del paso (2026-09-24).** Desactivar un paso apaga sus vínculos:
si no, contaba como mención viva para el admin y para lo que lea `tareas_vinculos` después
("mencionado en", el disparo). Reactivarlo los vuelve a derivar sin TA021: lo hace el admin y la
referencia ya se revisó al escribirla. Archivos: `sql/122_tareas_vinculos_activo.sql`, `sql/tests/tareas_vinculos.sql`.

**El hilo y el paso muestran "Mencionado en" (2026-09-25).** Lista de los pasos que los referencian,
con link al paso y el título de su hilo; sin menciones, no aparece. Sale de `tareas_vinculos`, así que
recorta solo por su RLS: quien no ve el paso que menciona no se entera de la mención. No espera a
otro módulo: el dato ya estaba y la prueba con dos usuarios lo echó en falta. Archivos: `queries.ts`
(`getMenciones`), `Menciones.tsx`, `HiloView.tsx`, `PasoPanel.tsx`.

**Las fichas de los vínculos del paso se ven al lado, en pestañas, desde que se abre (2026-09-26).**
Una pestaña por vínculo que quien mira puede abrir; los que no, ni pestaña ni link. El ↗ del texto
activa la pestaña de ese vínculo. Sin vínculos no hay columna derecha. Split en desktop, encima con
"volver" en mobile. Se eligió sobre abrir una ficha por vez al hacer clic: el paso se trabaja mirando
sus registros, no navegando hacia ellos. Cada módulo con entes aporta su ficha; el registro ente →
componente vive en `app/`.

**La pestaña muestra la ficha entera, con sus acciones (2026-09-26).** El mismo componente que la
página del ente, no un resumen: el link de acción (`?vincular={rol}`, `?estado={valor}`) se resuelve
ahí sin salir del paso, y cada módulo mantiene una sola ficha. Permisos y RLS los de siempre: la
ficha muestra lo que quien mira puede ver y hacer.

**El registro del hilo es la primera pestaña de cada paso (2026-09-26).** Fija, aunque el texto del
paso no lo mencione; si lo menciona, no se repite. Después, las mencionadas en el texto. El paso se
trabaja en el contexto del registro del hilo y la plantilla no tiene que repetir `{obra}` en cada
paso. Depende de que exista `hilo → registro` (ente + id en `tareas_hilos`, todavía sin columnas:
`BACKLOG.md` → disparo por registro).

**La página del hilo muestra al lado solo la ficha del registro del hilo (2026-09-26).** Sin
pestañas de lo que mencionan sus pasos: en hilos largos juntaría registros que no le conciernen a
quien mira, y crecería sin límite. Sin registro, la página del hilo va a todo el ancho.

**"Relacionar": primero el módulo, después el buscador (2026-09-24).** Botón junto a la descripción
del paso (hilos y pasos sueltos): elegir el módulo y buscar en `buscar_registros` (INVOKER, una rama
por ente: lo que quien escribe ve), que inserta `{ente:uuid|nombre}` con vista previa. En una
plantilla el mismo botón ofrece solo referencias relativas (`catalogo.md` → *Referencias
relativas*). Con un solo módulo con entes el selector no aparece. El nombre copiado pierde las `}`
(cortarían el token). La vista previa muestra link solo en lo elegido en ese formulario.
Archivos: `sql/124_buscar_registros.sql`, `sql/tests/tareas_buscar.sql`, `RelacionarModal.tsx`,
`PasoFormPanel.tsx`, `actions.ts` (`modulosRelacionables`, `buscarRegistros`).
