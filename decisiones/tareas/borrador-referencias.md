# Borrador — plantillas "Sobre", disparo que sigue al registro y buscador de entes

> **Provisorio (2026-09-24).** Resuelto punto por punto con el usuario. Aprobado, pasa a la ficha
> (`README.md`), a `catalogo.md`, `registro.md` y `avisos.md`, y este archivo se borra.

Pedido del usuario: designar equipo en los pasos de una plantilla; que una plantilla referencie
"el registro del evento" y no un uuid fijo; buscador de entes (paso suelto: lo ya creado;
plantilla: lo relacionado con el registro).

## Ya existía

**Equipo en plantillas.** `asignado_equipo_id` en `tareas_plantillas_pasos` (`sql/118`) y grupo
"Equipos" en `AsignadoSelect`. Solo lista equipos con delegador activo; en la base el único
("Prueba") está inactivo. Falta el dato de prueba, no código.

## Decisiones (2026-09-24)

1. **La plantilla dice "Sobre" qué registro trabaja** (un ente, o ninguno), aparte del disparo.
   "Sobre" define qué se puede referenciar y qué se pide al usarla; el disparo solo agrega que
   corra sola. Usarla a mano con "Sobre" pide elegir el registro (buscador, lo que quien la usa
   ve); sin elegir, no se usa. "Sobre: Ninguno" es la plantilla de hoy.
2. **El disparo sigue al registro, no a quien actúa.** Corren las plantillas que activó el dueño
   del registro, lo cambie quien lo cambie; el hilo nace suyo. Transferido el registro, corren las
   del nuevo dueño. Dueño que no puede recibir: no corre (la baja ya apaga sus activaciones).
3. **Los hilos no disparan.** Se eligen a mano ("Sobre: Hilo") y se referencian. El proceso que
   encadena trabajo vive en el ente de negocio (la obra), que es el que dispara.
4. **Sin el submódulo del ente, la plantilla no se ve** (Catálogo, Mis plantillas) ni se arma con
   ese "Sobre". Sale de la RLS de `entes`; recuperado el submódulo, reaparece.
5. **Desde un hilo, "Usar plantilla" siempre suma a ese hilo.** Con "Sobre: Obra" pide la obra.
   Crear un hilo nuevo sobre un hilo es desde la vista Plantillas.
6. **El hilo guarda su registro y su plantilla** al crearse con una plantilla con "Sobre".
   - No se repite: si hay un hilo activo de esa plantilla sobre ese registro, el disparo no corre
     (desactivado no cuenta: la próxima vez vuelve a crearse).
   - La ficha del registro lista sus hilos; el encabezado del hilo muestra "Sobre: X ↗" si quien lee
     lo ve, y nada si no.
   - Sumar pasos a un hilo existente no le cambia el registro.
   - Hilo "sobre X" a mano, sin plantilla: no, hasta que haga falta.
7. **Referencias relativas, solo en plantillas.** `{@disparador}` (el registro) y `{@ente:rol}`
   (quien tenga ese rol en él). Al usarla pasan a `{ente:uuid|nombre}`, la referencia de siempre.
   - Rol vacío → desaparece (para la frase: `{si hay ente:rol}…{fin}` o paso condicionado).
   - Varios → todos, separados por coma.
   - El dueño no lo ve → desaparece, sin nombre. Lo que cuenta es lo que ve el dueño (el hilo es
     suyo), no quien disparó.
   - El asignado no lo ve → texto plano, como hoy.
8. **Sin referencias fijas `{ente:uuid|…}` en plantillas.** Las guardadas pasan a texto plano. Cierra
   el punto 4 de tareas en `BACKLOG.md` (Catálogo mostrando nombres ajenos).
9. **Avisos de un disparo.** Al dueño, uno: "Se creó *Instalación — Cocina Pérez* porque Carlos
   aprobó la obra" → el hilo; sus propios pasos no avisan aparte. Los demás asignados, como siempre.
   Quien disparó: nada. Falla inesperada: la acción del emisor sigue y al dueño le llega "no pudo
   crearse", → la plantilla. Asignado inválido: "paso a reasignar", como hoy.
10. **Buscador ("Relacionar")** en la descripción del paso: módulo primero, después el buscador
    (`buscar_registros`, INVOKER, una rama por ente), inserta `{ente:uuid|nombre}`. En la plantilla,
    el mismo botón ofrece solo relativas: "El registro" y los roles del ente de "Sobre".

## Ficha — delta

```
Entes
└── hilo — emite, no dispara (sin cambio) · + registro y plantilla de origen, si nació de una
           plantilla con "Sobre" · encabezado "Sobre: X ↗"

No son entes
└── plantilla — + Sobre: un ente o ninguno; lo ve y lo arma solo quien tiene su submódulo
                · + disparo (evento del ente de Sobre), opcional; activación por usuario; corre la
                  del dueño del registro; una vez por plantilla y registro (hilo activo)
                · usar con Sobre: elegir el registro; desde un hilo, suma a ese hilo
                · referencias: solo relativas {@disparador} · {@ente:rol}; nunca {ente:uuid|…}
                · publicar y copiar: Sobre y relativas tal cual, disparo apagado

Relaciones
├── plantilla → ente (tipo) — Sobre, nullable
└── hilo → registro         — el de su plantilla, nullable; hilo → plantilla, nullable

Acciones
├── tarea:     referenciar ente → "Relacionar": buscador de lo que quien escribe ve
└── plantilla: referenciar → solo relativas · activar disparo · usar eligiendo el registro

Campanita
├── plantilla disparada → el dueño del registro, una por plantilla (no por paso)
└── plantilla fallida   → el dueño del registro
```

## Qué se construye ahora y qué espera

- **Ahora:** "Relacionar" en el paso (hilos y pasos), "Sobre" con `hilo` como único ente (uso manual
  y `{@disparador}`), registro y plantilla en el hilo, prohibir fijas y migrar las guardadas.
- **Con el primer emisor (obras):** disparo, activaciones, `disparar_plantillas`, `{@ente:rol}`,
  `{dato}`, `{si hay}`, pasos condicionados y los dos avisos.

## Notas técnicas (verificar al construir)

- El disparo corre a profundidad > 1: los triggers de `sql/113` solo aplican invariantes y TA021 no
  revisa (como la recurrencia). La visibilidad del dueño se chequea al resolver, con funciones
  `_de(id, usuario)`, no con `auth.uid()`.
- `entes` necesita decir qué columna es el dueño del registro para leerlo en el disparo.
- Resuelve `usar_plantilla` (una sola función, a mano y por disparo); valida `guardar_plantilla`
  (marcas contra "Sobre", sin fijas).
