# Backlog

Decidido, no implementado. `decisiones/` registra lo que **ya** se hizo; acá vive lo que falta.
Cuando algo de acá se implemente, la decisión final se escribe en `decisiones/<modulo>.md`
y la entrada se borra de este archivo.

---

## Contactos y Obras — lo que quedó afuera de los tramos

Los cinco tramos están cerrados (estado y tests en el encabezado de `decisiones/obras.md`). Quedan:
- **Sin función que los respalde:** vincular a una obra desde la ficha de la persona o la empresa
  (buscar "obras que trabajás", `decisiones/contactos.md` → *Vincular*), y crear la empresa desde
  "Sumar empresa" o la persona desde "Sumar persona" (hoy, solo existentes: crear y relacionar en un
  paso pide una función, como `contactos_crear_y_vincular`).
- **Sin probar en el navegador:** elegir entre dos comisiones al fusionar (lo cubre
  `sql/tests/contactos_fusionar.sql`).
- **Sin correr:** los casos `05 a cargo` de `sql/tests/obras_reglas.sql` (`obras_a_cargo`, la RPC de la
  ficha), sumados el 2026-11-05 en una sesión sin acceso a la base. Correr el archivo entero y borrar esta
  línea.

## Módulos que siguen

Orden: Contactos y Obras → **Catálogo** → Presupuestos → Post-venta. Sin lugar todavía en el orden:
Stock y Compras.

Ya decidido para los módulos que vienen detrás, al fichar Obras:
- **Catálogo** (servicios y productos): de ahí salen los ítems de los presupuestos. **Se arma de cero**
  (2026-10-22): la v1 y la v2 se descartaron enteras, junto con lo que habían dejado en Presupuestos,
  Stock, Compras y `GUIDE_ENTES.md` (`obsoletos/catalogo-descartado-2026-10-22/`). Nada de eso vuelve
  (`decisiones/catalogo/README.md`). La ficha nueva está ahí, aprobada completa (2026-11-02). El SQL va por
  tramos, cada uno con su test, `db_schema/catalogo.md`, `database.types.ts` y su commit; cada enum va con las
  tablas que lo usan. Hecho: las fórmulas (`sql/158`), los registros (`sql/159`: permisos, categorías, colores,
  insumos, servicios fijos, variantes, costos y servicios en % con su historia) y los paquetes (`sql/160`: paquetes,
  versiones y su contenido, edición solo en borrador, duplicar, versión nueva, datos del insumo que quedan fijos y la
  categoría de paquete con versiones adentro), el despiece (`sql/161`: el cálculo, alertas, bloqueos, casos de prueba y la
  forma de `catalogo_casos.entrada`), el ciclo (`sql/162`: qué frena el envío, enviar, retirar, devolver, aprobar, descartar,
  lo que se ofrece en cada color, bajas en cascada, aviso previo y reactivación), el precio (`sql/163`: precio, detalle del
  gerente, mínimos por presupuesto y precios de referencia) y los avisos (`sql/164`–`165`). El SQL de la ficha está completo.
  Las pantallas también están (2026-11-03, `decisiones/catalogo/pantallas.md`): Paquetes con su versión, el ciclo y el editor del
  borrador, Insumos, Servicios fijos y Servicios en %, en las rutas de los avisos. Pasan `tsc` y lint, pero **no se probaron en el
  navegador**: la sesión que las escribió no tenía la base. **Siguiente:** probarlas con un usuario de cada persona (Técnica,
  Administración, gerente, quien revisa cortes) y cargar el primer paquete real, que es la prueba del despiece y del precio
  (`decisiones/catalogo/README.md`).

  Paquetes a la venta y su formulario se escriben con Presupuestos.
- **Notificaciones — la bandeja todavía tarda ~0,6 s con obras recibidas**, sin caso real todavía (2026-11-04). Lo que queda es la RLS de
  `eventos`: pasa por `etiqueta_registro` en cada evento de la obra, ~7 ms por obra en cada aviso `obras_recibidas` o `agenda_recibida`. Crece
  con las obras recibidas, no con la cantidad de avisos. Se mira si se nota con datos reales (`decisiones/global/infra.md` → *La bandeja calcula
  cada conteo una vez*).
- **Monedas**: construido (2026-10-29, `sql/155`–`156`, `decisiones/monedas.md`). El catálogo y
  Compras convierten con `monedas_convertir(monto, de, a, fecha)` (`db_schema/monedas.md`). Falta la
  prueba completa en el navegador con dos usuarios.
- **Catálogo — reventa de perfiles**, sin caso real todavía: un solo paquete "Perfil suelto" con un
  material múltiple cuyas opciones son los perfiles, no un paquete por perfil. No copia la misma
  estructura 200 veces y la lista del vendedor sigue corta. Puede convivir con un paquete propio para
  un perfil especial. Costo: las opciones son de la versión, así que un perfil nuevo del proveedor pide
  versión nueva y aprobación del gerente.
- **Catálogo — dibujo 2D del paquete**, segunda fase (2026-11-02, reemplaza la idea del 2026-10-30 de
  escribir la posición de cada pieza con fórmulas): el editor calcula cuánto lleva cada material, no dónde
  va, y eso lo dice Técnica a mano. Cada material suma su ángulo de corte y cada insumo el SVG de su perfil.
  Técnica arrastra las barras, y un imán las pega cuando sus cortes coinciden o se complementan (ventana
  triangular). Propuesta: el imán guarda uniones, no coordenadas, para que el dibujo se rearme con cualquier
  medida. Lo ven todos: Técnica, gerente, quien revisa cortes, vendedor, y Producción y cliente cuando tengan
  ficha. Propuesta: lo arma una función de la base, también para el editor, y vendedor y cliente reciben solo
  las formas, sin medidas ni nombres de cada barra: armado en pantalla, el despiece llegaba a su navegador. A
  decidir, de a un punto: qué es "se complementan"; uniones que no son punta con punta (travesaño, hoja dentro
  del marco, arcos); qué aporta el SVG, que es el corte del perfil, a un dibujo de frente; cantidades y
  condiciones; y si dibujar un paquete publicado pide versión nueva.
- **Catálogo — % de un servicio por categoría de paquete**, sin caso real todavía: se construye con
  la primera categoría que cobre distinto. Sumarlo no cambia nada, porque mientras tanto todos los
  paquetes usan el % general (`decisiones/catalogo/precio.md` → *Servicios en %*).
- **Catálogo — reemplazar un material en varios paquetes**, sin caso real todavía (2026-11-02): Técnica
  elige Rueda A y Rueda B, y la base abre un borrador con el cambio en cada paquete que la usa. El gerente
  aprueba cada uno, y un paquete con una versión abierta queda afuera, en una lista. Usa la misma copia de
  versión y no cambia tablas. Se construye cuando un reemplazo real resulte pesado.
- **Catálogo — corregir una fórmula en varios paquetes**, sin caso real todavía (2026-11-02): una misma pieza
  se repite en varios paquetes (la hoja oscilobatiente en 3), y corregirla es una versión de cada uno, a mano.
  Se construye cuando un arreglo real resulte pesado (`decisiones/catalogo/paquete.md` → *Qué es un paquete*).
- **Catálogo — carga inicial**, antes de abrir el módulo (2026-11-02): insumos, variantes y costos desde una
  planilla, una sola vez y por script, con las mismas reglas de la base que cualquier alta. Los paquetes se
  arman en el editor y pasan por aprobación. Una pantalla de alta en bloque se suma solo si hace falta
  seguido. Falta saber de dónde sale hoy la lista de insumos y costos.
- **Presupuestos**: uno por etapa de la obra (FK `obra_id`), con versiones (congeladas al enviarse) e
  ítems del catálogo con el precio copiado, más un renglón por cada mínimo por presupuesto de los
  servicios en %, que calcula el catálogo (`decisiones/catalogo/precio.md` → *Servicios en %*). Cada ítem guarda
  su versión y solo lo que cargó el vendedor: lo escrito, las elecciones, las piezas opcionales y el color;
  el resto lo recalcula el catálogo. El precio llega redondeado, y el ítem lo multiplica por su cantidad.
  Suma el IVA:
  el precio del catálogo llega sin IVA (`decisiones/catalogo/precio.md` → *El IVA lo suma Presupuestos*). Su estado
  es el operativo (en cotización, aprobado, en producción…) y es lo que mueve a administración, producción y logística: sus plantillas de
  ejecución y el seguimiento comercial al entregar cuelgan del presupuesto, no de la obra. El primer
  presupuesto pasa la obra a `en_cotizacion` y el primero aprobado a `contratada`. La ficha de la
  obra lista sus presupuestos con su estado actual. Los contactos operativos (capataz, quien recibe)
  se vinculan al presupuesto. Su ficha define cómo obtiene la lista de paquetes a la venta y el formulario
  de cada uno (qué preguntar, predeterminados ya calculados, qué se ofrece) sin leer las tablas del
  catálogo. Del precio (`sql/163`): `catalogo_precio` y `catalogo_precio_minimos` son lo que se vende hoy y piden
  `catalogo_aprobar` hasta que esta ficha nombre su permiso; recalcular con la versión y la fecha guardadas se suma acá, y
  `catalogo_precio_calcular` ya las recibe. El precio no corrige lo elegido, así que el formulario manda en `false` una pieza
  incluida que no se ofrece. A decidir: qué versión y fecha lleva un paquete sumado a un presupuesto viejo, y si ahí se
  puede elegir una opción dada de baja después (sin costo a esa fecha, el catálogo no da precio). También:
  el renglón libre para lo que no se fabrica (flete, visita), con descripción y monto, y quién lo autoriza
  (`decisiones/catalogo/paquete.md` → *Qué es un paquete*). También: si los vendedores reciben aviso de un
  paquete nuevo o de uno que sale de la venta (hoy nadie les avisa). También:
  cómo ve logística el nombre y la dirección de una obra que no
  abre (propuesta: la etapa guarda su dirección de entrega). También: si un presupuesto en USD blue
  cobrado en billetes usa el dólar de compra (USD 1.000 al de venta, vendidos a $1.545, dejan $20.000
  menos que $1.565.000); Monedas hoy guarda solo el de venta (`decisiones/monedas.md` → *Ficha del módulo*).
  También, de una planilla de carpinterías real (2026-11-02): cada renglón lleva designación y ubicación
  ("V4 · Lavadero"), y la planilla viene en metros con punto, así que el campo de medida del formulario tiene
  que rechazar `3.00`: sin el punto son 300 mm, y pasan un mínimo de 300.
  También, a evaluar sin compromiso (2026-11-04): selección masiva de opcionales, para tildar o destildar de una vez la
  Colocación o la Garantía de vidrio en varios ítems. Cada ítem sigue guardando lo suyo, y la pieza se reconoce por nombre
  (`entrada.piezas`), así que no cambia el catálogo. A decidir: si hace falta frenar presupuestos mezclados, que sí pediría
  una respuesta única guardada en el presupuesto; cómo se cobra la colocación y si va en un renglón aparte.
- **Stock** y **Compras**: sin ficha. Lo que se había decidido para ellos al fichar el catálogo se
  descartó con él (2026-10-22). Sigue valiendo que los proveedores son empresas de Contactos
  (`decisiones/contactos.md` → *Los proveedores son empresas de Contactos*). Compras manda a presupuestar
  y lo compara con Administración, sin leer ni cargar el costo del catálogo
  (`decisiones/catalogo/insumos.md` → *El costo del insumo vive en el catálogo*).
- **erp-cliente**: sin ficha, y el portal no abre sin ella. A decidir para el catálogo (2026-11-02): qué
  paquetes ve cada cliente, si ve el precio y si puede elegir los servicios en % opcionales. Sin esto,
  una constructora cotizaría todo con precio y, destildando un opcional, vería menos que con el vendedor.
- **Post-venta**: módulo aislado para su equipo. La unidad (1°C, local, casa) se arma después,
  eligiendo ítems del presupuesto aprobado ("estas 4 ventanas → 1°C"); si un ítem agrupa varias
  unidades, se lleva ítem y cantidad. Una obra de un solo dueño es una unidad con todo. Propietarios e
  inquilinos, vínculos de Contactos con `desde` / `hasta`; el seguro, un contrato de la unidad.

## erp-cliente — falta el `ThemeToggle`

Vive en `SidebarNav` y el portal no tiene sidebar todavía. Va cuando el portal arranque de verdad
(`decisiones/global/ui.md` → *El script de tema va en `<script>` plano*).

## Sugerencia de tareas — sin caso real todavía

"¿Qué hago ahora?" ya lo contesta Misión; falta "¿qué tarea debería existir y no existe?" — la obra
sin movimiento hace 60 días (`decisiones/global/infra.md` → *La sugerencia de tareas no se
construyó*). El prerequisito de entonces ya está: el hilo sabe sobre qué registro es y el disparo
guarda la plantilla en el vínculo (`sql/119`, `sql/148`–`152`), así que una sugerencia puede saber si
la tarea ya existe. Cuando aparezca el caso, abre el flujo de plantillas ("Usar" con su "Sobre"), no
un camino de creación nuevo.

## Tareas — etiquetas de las referencias en una llamada, sin caso real todavía

`getEnlaces` (`modules/tareas/queries.ts`) pide `etiqueta_registro` una vez por cada `{ente:uuid|nombre}`
de los pasos del hilo y de Misión, en paralelo. Hoy son pocas por hilo; se construye cuando uno con muchas
referencias tarde (auditoría del 2026-11-05, punto 10). Diseño: `etiquetas_registros(p_entes text[], p_ids
uuid[]) → (ente, registro_id, etiqueta)`, SQL `STABLE` e INVOKER con GRANT `authenticated`, que devuelve solo
las que `etiqueta_registro` no da en NULL; va con las genéricas en `db_schema/core.md`. La app cambia en el
mismo commit en que se aplica la migración: sin ella no abre ningún hilo con referencias.

## Seguridad — auditoría del 2026-11-05, con agentes IA en el horizonte

Nota de hoy: 7/10. Con un agente conectado sin estos cambios bajaría a 4–5/10. La autorización en la base
está bien: RLS, `tiene_permiso`, las `DEFINER` con `search_path` y el permiso chequeado al entrar, y `sql/102`,
que corta al desactivado incluso por PostgREST directo. Lo flojo es lo que la rodea. La auditoría se hizo
contra `sql/`, no contra la base viva: antes de construir cada punto, verificarlo en la base.

**Ahora — sirve haya agentes o no:**
- **MFA (TOTP de Supabase Auth) para quien tenga `usuarios_gestionar` o `usuarios_delegar`, y la *leaked
  password protection* encendida.** Sin MFA, la contraseña filtrada de un admin es el sistema entero: asigna
  permisos y resetea contraseñas. El toggle quedó apagado a propósito (`decisiones/global/infra.md` →
  *`sql/035`*). A decidir: exigir `aal2` en la base (`auth.jwt()->>'aal'` en las funciones de administración),
  no solo en la pantalla.
- **Test SQL de superficie de RPC.** Falla si `anon` ejecuta alguna función de `public` y si `authenticated`
  ejecuta una `SECURITY DEFINER` fuera de una lista blanca (`has_function_privilege`). Son unas 260 y ya se
  escapó una (`sql/054`: un `DROP` + `CREATE` la dejó abierta a `anon`). Mismo formato `DO … RAISE EXCEPTION`
  de `sql/tests/`.
- **Headers de seguridad en `erp-app/next.config.ts`** (`headers()`): `Content-Security-Policy`, con el script
  de tema de `app/layout.tsx` permitido por hash, `frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy` y `Strict-Transport-Security`. Hoy no hay ninguno.
- **Cuando la base pase a producción, el MCP de Supabase de las sesiones de desarrollo va solo lectura o a una
  rama.** Hoy aplica migraciones y corre SQL con privilegios altos, y lee datos: un texto inyectado en un
  registro, un issue o un archivo puede terminar en SQL. Mientras la base no sea de producción está bien
  (`decisiones/global/infra.md` → *Playwright puede escribir*).

**Cuando llegue el primer agente, no antes** (hoy sería arquitectura especulativa: `decisiones/global/infra.md`
→ *La regla de negocio vive en Postgres*):
- **El agente es una fila propia en `usuarios`, con submódulos mínimos.** Sin rol nuevo: los recibe por
  delegación con techo (`sql/105`), nunca tiene más que quien se los dio, la auditoría lo nombra sola y
  desactivarlo lo corta al instante (`sql/102`). Si es el asistente de una persona, usa el token de esa
  persona. Nunca una cuenta compartida: un agente de todos le muestra a A lo de B.
- **Nunca `service_role`, nunca funciones de administración.** Las RPC de `service_role` confían en `p_admin`
  (`sql/121_tomar_delegado.sql`): con esa key cualquiera se hace pasar por cualquier admin. Fuera del agente:
  `usuarios_gestionar`, `usuarios_delegar` y `catalogo_aprobar`. Aprobar la versión propia es un riesgo
  aceptado entre personas (`decisiones/catalogo/permisos.md`), no para un agente.
- **Sus herramientas son una lista blanca de RPCs que ya existen.** Ni SQL libre ni acceso genérico a tablas.
- **Una persona confirma lo irreversible y lo que sale afuera:** fusionar contactos (no se revierte,
  `sql/147`), transferir, aprobar versiones, tocar permisos, mandar un mail o pedir algo a la web.
- **Límite de ritmo en Postgres para el usuario del agente.** Hace en un minuto lo de un mes, y cada cambio de
  estado puede disparar plantillas de otros usuarios (`sql/152`). A decidir: dónde se cuenta.
- **El texto de la base es dato, nunca instrucción (inyección de prompt).** Entra por el texto libre de tareas,
  hilos, contactos, obras y motivos; por las plantillas, que copian su texto en hilos de otros al dispararse
  (`sql/150`); y sobre todo por erp-cliente, donde escribe gente de afuera. Un mismo agente no junta, sin una
  persona en el medio, entrada no confiable, datos sensibles (costos del catálogo, teléfonos y mails) y un
  canal hacia afuera. La interfaz del agente no carga imágenes remotas: exfiltran por la URL.
- Al construirlo, la decisión va a `decisiones/global/permisos.md` y esta entrada se borra.
