# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## Tareas — proyecto con cara de hilo

El proyecto **no se convierte en hilo** (sin `estado` abierto/cerrado ni cierre automático): se le da la *cara* de hilo — progreso "X/Y completadas" y métricas en `ProyectoDetailPanel`, que es cálculo puro sobre datos que ya llegan al panel. Si el proyecto tuviera estado propio, el nivel del medio (hilo) se quedaría sin razón de existir.

## Tareas — plantilla-checklist (items sin orden entre sí)

Desde `sql/017` toda plantilla genera una cadena: cada item espera al anterior (`agregarTareasDesdePlantilla`). Decidido no agregar flag ni checkbox hasta que exista una plantilla real cuyos items sean paralelos — ahí el camino barato es una columna `encadenada boolean` en `tareas_plantillas`, no una opción en "usar plantilla" (la plantilla sabe cómo es, quien la usa no debería tener que decidirlo cada vez).

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
`S⬤DA`. No hay nada que decidir, así que no va a `decisiones/global.md`.

Los cuatro app-wide reales están cerrados ahí (ThemeToggle flotante, `.card:hover` en lo no
clickeable, alturas de toolbar, el modal que no atenuaba el panel). El resto, en
`decisiones/obras.md`.

## Notificaciones — deep link a una tarea

`sql/038` dejó la campanita andando, pero las tareas no tienen ruta por id: la vista Lista abre el panel por estado, no por URL, así que el aviso "te asignaron X" lleva a `/tareas` y la tarea hay que buscarla. Las obras, empresas y personas sí abren su ficha.

No se resolvió ahora porque darle URL a una tarea es rehacer cómo la Lista abre sus paneles, y eso es una tarea del módulo tareas, no de la campanita. Cuando se haga, `RUTA` en `NotificacionesBell.tsx` es una línea.

## Sugerencia de tareas — falta el vínculo entre una tarea y lo que la motivó

Pedida junto con las notificaciones y no construida (ver `decisiones/global.md`). "¿Qué hago ahora?" ya lo contestan Misión y el orden de `useOrdenTemperatura`; lo que falta es "¿qué tarea debería existir y no existe?" — la obra sin movimiento hace 60 días, el edificio entregado sin propietarios averiguados.

**El bloqueante no es la regla, es el vínculo.** Hoy una tarea no sabe de qué obra habla: `origen_app` y `origen_punto` son texto libre y solo se muestran en `TareaDetailPanel`. Sin un vínculo estructurado, la sugerencia no puede saber si ya la creaste y la repite para siempre.

Cuando aparezca un caso real, el camino barato es una columna, no un motor: la regla la sabe el módulo dueño del dato, y la sugerencia debería abrir el flujo de plantillas que ya existe (`agregarTareasDesdePlantilla`), no un camino de creación nuevo.

## Obras — la obra después de la entrega: unidades y postventa

Dirección acordada el 2026-09-09. Nada que construir hasta que exista el módulo de presupuestos.
Ejemplos visuales de esta decisión: https://claude.ai/code/artifact/237043ec-43fb-42cf-8081-37d5ce31eeaa

**La obra es el edificio, no la venta. Una ficha por edificio, para siempre.** El grueso del negocio
es venta y colocación de aberturas; al entregar, el edificio se atomiza y las garantías y servicios
—que solo se ofrecen a quien compró la ventana— se le venden a cada propietario, que no es el que
compró. La casa particular no se divide: una contraparte para siempre, y la ficha de hoy le sirve
tal cual.

`estado_obra` mide hoy dos relojes en una columna: el del edificio (`idea` → `en_construccion` →
`terminada`, monótono, pasa una vez) y el comercial (cíclico). Con una sola venta por obra se
sostiene; con postventa se rompe, porque `terminada` tendría que significar a la vez "está
construido" y "acá se terminó nuestra relación".

**Cuando exista presupuestos:**

- `obras.cantidad_unidades` — entero nullable, aproximado, lo carga el vendedor cuando lo sabe. Es
  el denominador del "4 de 40": sin él, un edificio con cuatro dueños averiguados se ve igual que
  uno completo.
- `obras_unidades` — `obra_id`, `identificador`, `persona_id`, `activo`, unique parcial
  `(obra_id, identificador) WHERE activo`. La fila nace cuando se averigua la unidad, no al
  entregar. La reventa desactiva y crea otra; sin `desde`/`hasta`, porque la fecha del cambio de
  dueño no se va a conocer.
- El presupuesto apunta a la obra, y además a la unidad cuando es postventa. **Sin columna `tipo`**:
  el presupuesto es un grupo de productos y la garantía extendida es una línea del catálogo — lo que
  distingue una venta de obra de una de postventa es el destinatario, que ya está.
- `estado_obra` baja a tres valores. `perdida`, `motivo_perdida` y `detalle_perdida` describen una
  venta que no se cerró, no un edificio: se mudan al presupuesto con su CHECK. "Acá vendimos" se
  deriva de que exista un presupuesto aprobado — que es además la regla de que solo hay postventa
  donde compraron la ventana.
- Cuando además llegue garantías va a hacer falta la fecha de fin de obra para contar los plazos
  ("¿a qué edificios se les vence en 6 meses?"). Una columna, no un rediseño: no se agrega antes.

**Por qué `obras_unidades` y no un rol en `obras_obra_persona`:** hay unique por par (obra, persona)
—una persona figura una sola vez por obra— así que el inversor con tres departamentos en el mismo
edificio no entra. Y es el mejor cliente de postventa que hay ahí.

**Descartado:**

- *Una obra nueva por ciclo* ("Cabildo 2340 — Postventa"): duplica dirección, empresas, personas y
  referente, y `obras_marcar_pendiente` la congelaría por parecido. El detector de duplicados ya
  vota por una ficha por edificio.
- *Más estados en el enum* (`en_postventa`, `en_garantia`, `cerrada`): los estados comerciales no
  son excluyentes entre sí ni con los físicos — un edificio terminado puede tener una garantía
  vigente y un presupuesto abierto a la vez. Un enum sirve para lo que solo puede tener un valor a
  la vez.
- *Tabla aparte para propietarios*: se justificaba con carga masiva. Los propietarios aparecen de a
  uno —hay que averiguarlos, y las unidades no se venden todas juntas— así que van a
  `obras_personas` como cualquier otro contacto sin saturar la cola de aprobación de `sql/033`.
- *Inventario completo al entregar*: 40 filas vacías con identificadores adivinados que nadie
  mantiene.
- *Seguimiento propio dentro de obras*: recordatorios y estados de gestión son `tareas`. Por ahora
  la existencia de la fila ya dice "esta unidad la averigüé", más un campo de observaciones.

**Sin decidir — hace falta antes de escribir el SQL:**

1. ¿Una unidad la puede comprar una SRL? Si pasa seguido, `obras_unidades` tiene que apuntar a
   persona *o* a empresa; si es raro, la SRL se carga como persona. Es lo único que cambia la forma
   de la tabla.
2. ¿Quién vende la postventa? La obra hoy la ve solo su responsable, y vender a 40 propietarios es
   otra operación comercial. Si la hace otro, el camino barato es que el presupuesto tenga su propio
   `responsable_id` y `obras_puede_ver_obra` pase a "responsable de la obra **o** de algún
   presupuesto suyo" — la función ya existe y ya centraliza esto, sin rol nuevo.
3. ¿La comisión del referente alcanza a las ventas posteriores? Por edificio, `obras_obra_referente`
   se queda donde está; por venta, la fila cuelga del presupuesto. No urge mientras la comisión solo
   se registre, pero define dónde nace la tabla.

**Después, y no condiciona nada de lo anterior:** la pantalla de postventa no es la ficha de obra
sino una vista transversal — "de todos mis edificios entregados, a quién le debo una llamada". Es
una vista sobre los mismos datos, así que puede esperar.

## Auth — activar leaked password protection

Supabase puede rechazar contraseñas que figuran en HaveIBeenPwned. Está apagado.

No es SQL: es un toggle en el dashboard de Auth (Authentication → Policies), así que no entra en una migración ni queda versionado en `sql/`. Sale como WARN en `get_advisors('security')` y es lo único que quedó pendiente de ese barrido — el resto se resolvió o se descartó en `sql/035` (ver `decisiones/global.md`).

