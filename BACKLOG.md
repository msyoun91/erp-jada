# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## Tareas — plantilla-checklist (items sin orden entre sí)

Desde `sql/017` toda plantilla de hilo genera una cadena: cada item espera al anterior (`usar_plantilla` desde `sql/053`). Desde `sql/053` las plantillas de proyecto tienen tareas sueltas, que no se esperan entre sí — pero un hilo de pasos paralelos sigue sin existir. Decidido no agregar flag ni checkbox hasta que exista una plantilla real así — ahí el camino barato es una columna `encadenada boolean` en `tareas_plantillas_hilos` (y en la plantilla de tipo hilo), no una opción en "usar plantilla" (la plantilla sabe cómo es, quien la usa no debería tener que decidirlo cada vez).

## Tareas — plantillas disparadas por otros módulos (fase 2)

La fase 1 (`sql/053`, ver `decisiones/tareas/plantillas.md` → *Plantillas de sistema y privadas, tres tipos*) dejó las plantillas completas y usadas a mano. La fase 2 las conecta con los módulos. **Alcance acordado con el usuario: un solo disparador, para probar la idea** — la obra cambia de estado (su ejemplo: de cotización a en ejecución → "Cobrar obra X"). El resto se suma cuando haga falta.

Decidido con el usuario:

- **"Click de botón relevante" es una acción que el módulo ya tiene** (transferir, compartir, vincular empresa/persona, marcar referente, crear obra), no un botón "Crear tareas" nuevo. Obras no suma funciones ni botones: solo avisa cuando pasa algo.
- **El texto se copia en la tarea** ("Cobrar obra {nombre}"): el asignado lo lee aunque no vea la obra. Los enlaces a la ficha sí respetan permisos. El editor lo avisa.
- **Si un asignado no puede recibir el paso, queda para quien disparó con una nota** — ya implementado en `usar_plantilla`.
- **Nunca teléfono ni email como dato**: el contacto sale solo por `obras_ficha_persona`, que registra el acceso.

Propuesto, sin objeción del usuario (confirmar al construir):

- Listado de disparadores = una tabla que siembra la migración de cada módulo (código, módulo, datos que ofrece, submódulo que pide cada uno). Una plantilla de sistema se ve solo con todos los submódulos que usa, se muestran como etiquetas, y quien la arma solo usa lo que tiene autorizado — todo en RLS.
- Enlaces estructurados tarea ↔ obra/empresa/persona (`tareas_vinculos`), chips con link a la ficha. Cierra *Sugerencia de tareas — falta el vínculo* (abajo).
- La automática corre una vez por (plantilla, obra); ir y volver de estado no duplica. Una privada con disparador solo corre si el dueño es quien dispara.
- **Autoridad:** el disparo automático no puede correr con los permisos de quien cambia el estado (un vendedor sin `tareas_asignar` no podría crearle la tarea a Cobranzas y el cambio de estado fallaría). La autoridad pasa a ser la plantilla: se valida al guardarla y la ejecución corre `SECURITY DEFINER` revalidando lo que pudo cambiar. Es mover autorización adentro de una función — registrarlo como excepción explícita en `decisiones/tareas/plantillas.md` antes de escribirlo.
- Esto **es** un motor de reglas: al construirlo, superar en `decisiones/global/infra.md` *Notificaciones: infra sin submódulo, y sin motor* con el puntero.

## Tareas — verificar `Content-Range` en el PATCH

**Pendiente de verificar en el navegador** (alcance reducido tras `sql/023`: solo aplica a las actions de una sola tabla, que siguen usando `errorDeUpdate`)**:** que PostgREST devuelva `Content-Range` en un PATCH con `Prefer: return=minimal,count=exact`. No se pudo probar desde acá — ni `anon` ni `service_role` tienen `GRANT` sobre `tareas` (decisión "RLS no alcanza sin GRANT"), así que hace falta una sesión autenticada real. Si no lo devolviera, `count` llega `null` y `errorDeUpdate` no dispara: el fix quedaría inerte, nunca en falso positivo.

## erp-cliente — su `globals.css` quedó en la versión vieja de los tokens

Encontrado al cerrar `.input-error-text` en erp-app, el 2026-09-09. `erp-cliente/src/app/globals.css`
tiene `--color-error-bg`/`--color-error-text` (y las otras tres familias) como hex fijos en `@theme`,
que es de donde erp-app salió cuando se hizo el bloque dark-aware de `:root` / `[data-theme="dark"]`.
El `@custom-variant dark` sí está, así que el defecto viaja igual: `text-error` sobre superficie
oscura da 3.8:1, y `text-error-text` (#5C0A0A) sobre esa misma superficie sería peor.

No se arregló ahora porque ahí el fix no es un token: hay que portar el bloque entero de las cuatro
familias, y el app tiene tres archivos —`layout.tsx`, `page.tsx`, `globals.css`— sin un solo
formulario que muestre el defecto. Cuando erp-cliente arranque de verdad, el `globals.css` se trae
de erp-app y no se edita el que está.

Las apps no se importan entre sí, así que los tokens del design system son la duplicación que el
repo ya aceptó (`GUIDE_SYNC.md` cubre schemas y tipos, no CSS). Lo que falta no es una abstracción:
es acordarse de sincronizar cuando el segundo app exista.

## ~~Obras — auditoría visual de la UI~~ — cerrada

29 hallazgos relevados el 2026-09-08: `obsoletos/AUDITORIA_OBRAS_UI.md`. 28 implementados y **B3 cerrado
sin tocar código: no reproduce.**

La segunda pasada de navegador midió el footer del sidebar con el usuario real (`nombre` =
`Admin`): el nombre ocupa 40.6px en una caja de 81.2px en escritorio y de 71.2px en el drawer
mobile, y el avatar 18.7px en 28px. Ni truncado ni solape en ninguno de los dos anchos. Lo que
se había leído como `A…dmin` era el puntero del mouse que dibuja la herramienta de captura,
apoyado sobre el avatar; en la segunda pasada el mismo círculo cayó sobre el logo y lo dejó en
`S⬤DA`. No hay nada que decidir, así que no va a `decisiones/global/`.

Los cuatro app-wide reales están cerrados ahí (ThemeToggle flotante, `.card:hover` en lo no
clickeable, alturas de toolbar, el modal que no atenuaba el panel). El resto, en
`decisiones/obras/ui.md`.

## Sugerencia de tareas — falta el vínculo entre una tarea y lo que la motivó

Pedida junto con las notificaciones y no construida (ver `decisiones/global/infra.md`). "¿Qué hago ahora?" ya lo contestan Misión y el orden de `useOrdenTemperatura`; lo que falta es "¿qué tarea debería existir y no existe?" — la obra sin movimiento hace 60 días.

**El bloqueante no es la regla, es el vínculo.** Hoy una tarea no sabe de qué obra habla: `origen_app` y `origen_punto` son texto libre y solo se muestran en `TareaDetailPanel`. Sin un vínculo estructurado, la sugerencia no puede saber si ya la creaste y la repite para siempre.

Cuando aparezca un caso real, el camino barato es una columna, no un motor: la regla la sabe el módulo dueño del dato, y la sugerencia debería abrir el flujo de plantillas que ya existe (`agregarTareasDesdePlantilla`), no un camino de creación nuevo.

