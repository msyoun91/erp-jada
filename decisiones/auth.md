# Decisiones — auth y perfil

Login, sesión y `/perfil`. Todo vive en `modules/auth/`.

---

## Login

### El login es un server action, no una llamada al cliente

`signInWithPassword` se ejecutaba desde `app/login/page.tsx` con el cliente de browser: el schema Zod solo corría en el cliente, contra la regla de validar en dos lugares. Ahora `signInAction` (`modules/auth/actions.ts`) hace `safeParse` y llama al cliente de servidor — las cookies de sesión vuelven en la respuesta del action. La lógica salió de `app/` a `modules/auth/components/LoginForm.tsx`; la page solo lee `searchParams` y renderiza.

No usa `redirect()` en el action: los Server Components tienen que releer la sesión recién cookieada, y eso lo dispara `router.refresh()` desde el cliente. El action devuelve `{ success, destino }` y el form navega con `router.replace` (no `push`: volver atrás al login ya logueado no tiene sentido).

`enviando` no vuelve a `false` en el camino feliz. Bajarlo antes de navegar rehabilitaba el botón durante la navegación y dejaba mandar un segundo login.

### `?next=` con lista blanca de paths propios

El proxy redirigía a `/login` sin guardar el destino, así que un deep link a `/tareas` terminaba en el dashboard. Ahora `updateSession` agrega `?next=<pathname>` y el schema lo sanea: solo se acepta un string que arranque con `/` y no con `//` ni `/\` — el browser resuelve esas dos formas como URLs absolutas, y sin el filtro `?next=` es un open redirect. Va dentro de `loginSchema` y no en un helper aparte para que lo cubra el mismo `safeParse` del servidor.

Solo el `pathname`, sin el `search`: los prefetch RSC pasan por el proxy con un `?_rsc=` que no sirve como destino. Se pierden los filtros de una URL como `/tareas/auditoria?desde=…`, que es mucho menos que perder la vista entera.

### Los errores de auth entran al mapa de `mensajeError`

`invalid_credentials`, `email_not_confirmed`, `user_banned` y `over_request_rate_limit` se sumaron a `MENSAJES_ERROR` en `lib/utils.ts`, donde ya vivían `email_exists` y `weak_password`. Antes el login colapsaba *cualquier* fallo en "Email o contraseña incorrectos" — con la red caída o el rate limit puesto, el usuario reintentaba contra una pared. El caso sin red no llega a tener código: si el `await` del action tira, no llegó al servidor y el form muestra "Sin conexión".

### `noValidate` en el form

Con `type="email"` y sin `noValidate`, Chrome mostraba su propia burbuja en el idioma del browser y bloqueaba el submit antes de que corriera RHF: los mensajes en español del schema no se veían nunca. El email valida con `.min(1).pipe(z.email())` y no encadenando checks — zod corre ambos y el campo vacío devolvería "Email inválido" en vez de "es obligatorio".

### `pb-20` en el contenedor por el `ThemeToggle`

El toggle es `fixed bottom-4` de 56px y se renderiza en el root layout, o sea también en `/login`. En un viewport bajo le quedaba encima del botón "Ingresar". El padding inferior reserva ese rincón sin sacarle el toggle a la pantalla de login. El contenedor pasó de `min-h-full` a `min-h-dvh`: el `100%` no resolvía contra un `body` de altura automática.

### Diseño: la pantalla usa la marca y la jerarquía que el design system ya define

El login mostraba el texto `ERP JADA` en `t-h2`, era la única pantalla sin logotipo — `public/logo.svg` ya se usaba en `Sidebar.tsx` y `MobileNav.tsx`, y la clase `.logo` de `globals.css` ya lo invierte en dark. Se reusa el mismo asset y la misma clase, sin variante propia de login.

El fallo de credenciales usaba `input-error-text` (12px), el mismo peso visual que un error de campo, siendo el mensaje más importante de la pantalla. Pasa a bloque con `bg-error-bg` + borde `error/20` + `text-error-text`, los mismos tokens semánticos de `.badge-error`.

El botón en `enviando` solo cambiaba el texto. El design system (§8) define loading como spinner; se reusa el spinner de `app/(erp-app)/loading.tsx` (borde + `animate-spin`) en vez de sumar un ícono nuevo.

El card usaba `shadow-lg`, que el spec (§5) reserva para modales — *"la elevación se comunica sobre todo con bordes, no shadow"*. Baja a `shadow-md`.

**`--background-image-gradient-brand` es token nuevo en `globals.css`.** El spec define `gradient-brand` (140deg, #011F51 → #064379 → #1A6DC8) como *"solo heroes/cards destacadas, nunca fondo de texto"*, pero el token nunca se había volcado a `@theme`. El login es el único hero del ERP, y se usa como barra de 4px al tope del card, no como panel: un split-panel gradiente/formulario obligaría a un layout distinto en desktop y mobile, contra la regla mobile-first, para el mismo objetivo visual. El namespace `--background-image-*` de Tailwind v4 no está documentado; se verificó contra el CSS compilado que emite `.bg-gradient-brand{background-image:linear-gradient(…)}`.

## Auditoría de UI del login

Los dos hallazgos globales de esta auditoría (`.input:focus` vs `.input-error`, tokens
semánticos dark-aware) están en `decisiones/global.md`.

Cinco arreglos salidos de auditar la pantalla en browser. Tres son del login; dos son globales y se descubrieron acá.

**El error del servidor sobrevivía a un fallo de validación de cliente.** `setError(null)` vivía dentro de `onSubmit`, y RHF no llama a `onSubmit` si el resolver rechaza: tras un "Email o contraseña incorrectos", vaciar el email y reenviar dejaba el bloque de credenciales en pantalla junto al error de campo nuevo — un veredicto del servidor sobre un request que nunca salió del browser. Se limpia desde el segundo argumento de `handleSubmit`, no con un `useEffect` sobre `isDirty`: el evento que corresponde es "el submit no pasó la validación", y RHF ya lo expone.

**El usuario logueado en `/login` veía el formulario.** El proxy guardaba solo la dirección no autenticada. Ahora `updateSession` también redirige `user && pathname === "/login"` a `/`. Como `signOutAction` limpia la cookie antes de su `redirect("/login")`, esa vuelta no toca la guarda nueva.

**La pantalla no tenía ningún heading.** `querySelectorAll('h1,h2,h3')` devolvía `[]`: el logotipo es un `<img alt="JADA">` y no anuncia nada como encabezado. Se agrega un `h1` `sr-only` en vez de un `t-h1` visible — el logotipo ya es el encabezado visual, y la regla de "Encabezado de módulo" aplica a módulos de `(erp-app)`, no a `/login`. La page suma `metadata` propia (`Ingresar · ERP JADA`); antes heredaba el título genérico del root layout.

## Acceso desde la LAN: el login no era interactivo

Desde el celular, por `http://192.168.1.52:3000`, el login no logueaba, no mostraba errores y dejaba los campos en la query string (`/login?next=&email=&password=`). No era un bug del formulario: la página nunca hidrataba, así que el `onSubmit` de React no existía y el browser hacía el submit nativo del `<form>`.

**`allowedDevOrigins`.** `next dev` solo confía en `localhost` (`blockCrossSiteDEV` arma su lista con `['**.localhost', 'localhost', hostname]`). Los chunks servidos a un `<script>` same-origin sí devuelven 200 — el bloqueo pega en los recursos dev que llevan `Origin`, y con eso el runtime de Turbopack queda a medio arrancar: `window.next` sin definir, la cola de chunks sin drenar, `ThemeToggle` sin renderizar. Se configura `allowedDevOrigins: ["192.168.1.*"]`. El match de `isCsrfOriginAllowed` es por hostname y por segmentos separados por punto, así que el comodín cubre el rango de DHCP; poner la IP exacta obligaría a editar el config cada vez que cambie el último octeto.

**Las fuentes pasaban por el chequeo de sesión.** El `matcher` del proxy excluía `svg|png|jpg|jpeg|gif|webp` pero no las fuentes: sin sesión, `/fonts/PlusJakartaSans-400.woff2` devolvía `307 → /login?next=%2Ffonts%2F…`. La tipografía nunca cargaba en la pantalla de login y `?next=` se llenaba de destinos que no son vistas. Se agregan `ico|woff|woff2|ttf|otf` a la lista.

**`method="post"` en el form.** El camino normal no lo usa — lo usa el submit nativo de antes de hidratar. El default de un `<form>` sin `method` es GET, y ahí el browser serializa la contraseña en la URL, donde queda en el historial del dispositivo y en los logs del servidor. Con `post` esa misma caída manda los campos en el body. Es defensa en profundidad: la hidratación puede fallar por razones que no controlamos (red lenta, browser viejo, o simplemente que el usuario toque el botón antes de que termine), y ninguna de esas debería costar una contraseña.

---

## Excepción explícita: `/perfil` no pasa por submódulos

**La regla:** toda autorización se implementa mediante submódulos, y una vista sin submódulo asignado no existe para el usuario.

**Por qué no aplica acá:** el submódulo es la unidad de *autorización*, y editar la propia cuenta no es algo que se autorice — es la definición de tener cuenta. Un `perfil_ver` asignable crearía un estado sin sentido: un usuario que entra al sistema pero no puede cambiar su propia contraseña, y un administrador que tiene que acordarse de asignarle el permiso de existir a cada alta. La alternativa de colgarlo del módulo `usuarios` es peor: ahí el permiso se llama `usuarios_ver`, lo tiene un puñado de personas, y el resto se quedaría sin pantalla propia.

**El alcance de la excepción:** `/perfil` es la única ruta de `(erp-app)` sin chequeo de permiso, y solo puede tocar la fila del usuario logueado. No aparece en `NAV_ITEMS` (el sidebar sigue mostrando únicamente módulos autorizados) — se entra desde el nombre en el footer del sidebar. Si alguna vez hace falta *restringir* quién edita su perfil, ahí sí corresponde un submódulo y esta excepción se revisa.

**La barrera no se relaja, se mueve a RLS por columna** (`sql/022_perfil_propio.sql`): `usuarios_update_propio` autoriza `id = auth.uid()`, y `GRANT UPDATE (nombre)` limita qué columna puede tocar el rol `authenticated`. Sin el grant por columna, la misma policy dejaría que un usuario se pusiera `activo = true` solo — deshaciendo la desactivación de `sql/020` desde su propio perfil. La contraseña no pasa por esta tabla: es `auth.updateUser()` sobre la sesión propia.

### `/perfil` — implementación

**Vive en `modules/auth/`, no en un módulo propio.** Es la misma materia que login y logout — credenciales y sesión — y un `modules/perfil/` con dos actions y sin `permissions.ts` sería una carpeta para justificar la palabra "módulo". La página es `app/(erp-app)/perfil/page.tsx` y lee la fila propia con el cliente normal.

**Cambiar la contraseña pide la actual.** Con la sesión abierta, `auth.updateUser({ password })` no la pide: quien se sienta frente a una máquina desbloqueada se queda con la cuenta. La verificación es un `signInWithPassword` contra un cliente aparte creado con la anon key y sin cookies — hacerlo sobre el cliente de servidor rotaría, de paso, la sesión que el usuario está usando. Ese login de verificación acuña un refresh token que no se guarda en ningún lado; no se lo cierra con `signOut()` porque el scope por default es global y voltearía las sesiones reales del usuario.

**El email es de solo lectura acá.** Es la credencial de login y vive en `auth.users`; cambiarlo es una operación de administración (módulo Usuarios, `sql/021`), no de perfil. El campo se muestra igual, deshabilitado, porque "cuál es mi usuario" es justo lo que uno viene a mirar.

**Entrada por el nombre del footer del sidebar**, no por un ítem de nav: `NAV_ITEMS` solo lista módulos autorizados y el perfil no es ninguno de los dos. `SidebarNav` lo sirve tanto al sidebar de desktop como al drawer mobile, así que es un solo cambio.

**Guardar deshabilitado si no hay cambios** (`!isDirty`), y `reset(data)` después de guardar: sin eso el form queda sucio para siempre y el botón invita a reenviar lo mismo.

Verificado con `sql/tests/perfil_propio.sql` (3/3): cambio mi nombre, no puedo tocar `activo` (42501), no puedo renombrar a otro.
