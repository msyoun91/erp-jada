# Obras — Visibilidad y compartir

## MODEL A — obras, empresas y personas son privadas por dueño (`sql/039`–`044`)

Pedido del usuario, y reescribe varias decisiones de los otros archivos de esta carpeta. **Nada se comparte salvo acto explícito del dueño.** Las empresas dejan de ser globales.

**Visibilidad.** `obras.responsable_id` / `obras_empresas.creado_por` / `obras_personas.creado_por` gobiernan. Ves lo tuyo, lo que te compartieron, y —con el permiso `_todas`— todo. `obras_puede_ver_persona` / `obras_puede_ver_empresa` ya no cuentan vínculos ni referencias: solo dueño, grant completo, o `_todas`.

**El contacto de persona se protege a nivel columna.** `telefono`/`whatsapp`/`email` (y sus `_norm`) salieron del `GRANT SELECT` de `obras_personas`. Antes un `select` directo los leía sin registro; el "único camino" era convención. Ahora `obras_ficha_persona()` —DEFINER, saltea el grant de columna— es de verdad el único, y toma contexto opcional (`obra`/`empresa` + id) para autorizar por grant contextual. Todo `select("*")` sobre `obras_personas` en el cliente pasó a lista de columnas.

**Compartir — dos formas, las dos las inicia `creado_por`:**
1. **Completa** (`obras_persona_compartida` / `obras_empresa_compartida`, funciones `obras_compartir_*` / `obras_revocar_*`): la entidad entra a la agenda del receptor. Lectura, no edición. Revocable.
2. **Contextual** (`obras_persona_grant_contextual`, ancla obra XOR empresa): el contacto de la persona se ve **solo dentro de esa ficha** de obra/empresa (`/obras/personas/{id}?ctx=obra:{id}`). No entra a la agenda ni al buscador. Muere con el vínculo —validado en vivo, sin trigger de limpieza—. Nace de transferir una obra/empresa o del checklist de "contactos exclusivos".

Un grant recibido **no se re-comparte**: las funciones exigen `creado_por`. **Ver no es editar:** `obras_*_update` exigen `creado_por = auth.uid()`; `_todas` mira y transfiere, no corrige — para editar lo ajeno hay que transferírselo (una puerta, no dos).

**Transferir — funciones separadas, una por entidad:**
- `obras_transferir(obra, a, contactos_exclusivos[])` — gate `obras_transferir`. Reasigna `responsable_id` + cascada.
- `obras_transferir_persona(persona, a)` — gate `obras_personas_todas`. Reasigna `creado_por`, revoca los grants del dueño saliente.
- `obras_transferir_empresa(empresa, a, personas_exclusivas[])` — gate `obras_empresas_todas` (submódulo nuevo).

**Cascada con confirmación.** `obras_contactos_exclusivos_de_obra` / `_de_empresa` listan lo vinculado **solo** a esa obra/empresa que el dueño saliente posee. El checklist del panel: tildado → cambia de dueño con ella; destildado → grant contextual (personas) o `obras_empresa_compartida` (empresas, no son sensibles). Lo compartido-al-saliente no cascadea.

**La cola de aprobación se recorta a las altas.** Bajo model A no se puede vincular lo que no se ve, así que el estado "vínculo a entidad ajena, congelado" desaparece: se dropeó `pendiente`/`motivo_rechazo` de `obras_obra_empresa` / `obras_obra_persona`, y `obras_guard_congelado` entera. Queda solo el alta parecida de obra/empresa/persona → congelada → `obras_aprobar`. `obras_marcar_pendiente` perdió las ramas de vínculo; la regla "marcar referente exige ver a la persona" pasó al WITH CHECK de `obras_obra_referente_insert`.

**El buscador enmascara, no esconde (`sql/042`).** El match crudo cross-owner (global y aviso de duplicados) devuelve la entidad ajena en **identidad mínima + nombre del dueño**, sin link, sin ficha. `obras_buscar` reparte tres funciones DEFINER que devuelven `es_ajeno` + `duenio`. `obras_buscar_duplicados_obra` ahora sí muestra el nombre de la obra ajena (sin dirección ni localidad); `obras_buscar_duplicados_empresa` pasó a DEFINER y enmascara igual.

**Filtro de alcance + badge.** `_todas` / `obras_transferir` habilitan un toggle `Míos | Todos` (URL `?alcance=`, default `propios`). Filas ajenas → badge "Ajena". El `getObras`/`getEmpresas`/`getPersonas` filtra server-side por dueño salvo que `alcance=todos` **y** el permiso lo respalde.

**Corte limpio, sin backfill.** Al aplicar: 0 vínculos cross-owner, 0 pendientes. Quien veía por vínculo pierde acceso y se re-comparte a mano.

Clases de error nuevas: `OB020`–`OB025` (lista blanca `mensajeError`, texto para el usuario).

---

## Compartir con checklist y cascada de revocación (`sql/047`)

Pedido del usuario, sobre el modelo de *MODEL A*. Tres cosas:

**1. Compartir obra.** Antes la obra solo se transfería. `obras_obra_compartida` +
`obras_compartir_obra` / `obras_revocar_obra` le dan lo mismo que persona y empresa: lectura sin
mover `responsable_id`, revocable. `obras_select` y `obras_puede_ver_obra` suman la rama. El
receptor ve la obra y sus vínculos; el contacto de las personas sigue pasando por
`obras_ficha_persona()`, y solo abre la ficha completa de las que además recibieron su propio
grant (las tildadas). **Consecuencia sobre la comisión:** un receptor con `obras_referentes` ve
los referentes de la obra compartida — el dueño optó por compartirla, y el permiso sigue siendo
la barrera. Si molesta, se acota `obras_obra_referente_select`; hoy no.

**2. Checklist al compartir.** `obras_compartir_obra(obra, usuario, empresas[], personas[])` y
`obras_compartir_empresa(empresa, usuario, personas[])` — lo tildado, que tiene que ser **mío** y
estar vinculado, recibe su propio grant completo. Persona no lleva checklist: sus únicas
relaciones son empresas y el usuario la quiere compartir sola. Los checklists los sirve
`obras_relaciones_compartibles_obra/_empresa` (DEFINER, identidad mínima, `ya_compartida`).

**3. Cascada por origen.** `obras_empresa_compartida` / `obras_persona_compartida` ganan
`origen_obra_id` / `origen_empresa_id` nullable. **Última escritura gana:** compartir por
checklist setea el origen al padre (pisa lo que hubiera); compartir directo lo limpia. Revocar el
padre desactiva solo los grants con ese `origen_*` y `otorgada_por = auth.uid()` — un grant
directo, o colgado de otro padre, sobrevive.

**Bug preexistente arreglado acá.** `obras_empresas_select` (sql/039) tenía el EXISTS como
`c.empresa_id = c.id`: la columna `id` de `obras_empresa_compartida` sombrea `obras_empresas.id`,
así que comparaba la fila del grant contra sí misma. `obras_compartir_empresa` escribía la fila y
el receptor nunca veía la empresa. Ningún test lo cazó porque `obras_model_a.sql` solo probó
compartir **persona** (que pasa por `obras_puede_ver_persona`, DEFINER, sin sombreado). Mismo
sombreado evitado en `obras_select` de `sql/047` (`obras.id` calificado).

**Vista Compartido** (`obras_compartido`, tab). `obras_compartidos_por_mi()` — DEFINER como las
de Auditoría (los JOIN tienen que resolver aunque un nombre quede fuera de la RLS del que
pregunta), gate propio, tope 500. Muestra qué compartí, con quién y de qué origen. Compartir y
revocar no son submódulos: son acto del dueño, igual que ya era `obras_compartir_persona`. "Solo
lo que compartí", no "lo que me compartieron" — eso último, si alguien lo pide.

Clases de error nuevas: `OB026` (solo el responsable comparte/revoca la obra), `OB027` (sin
acceso a la vista Compartido).

Test: `sql/tests/obras_047.sql`, 11/11 (los casos 10-11 son la regresión de `sql/048`).

**Bug que vale recordar (`sql/048`): el OUT param `id` de un `RETURNS TABLE` sombrea la
columna.** `obras_relaciones_compartibles_obra/_empresa` devuelven `(tipo, id, etiqueta, …)`, así
que dentro del cuerpo `id` es la variable plpgsql. El guard `IF NOT EXISTS (SELECT 1 FROM obras
WHERE id = p_obra_id …)` es ambiguo (`42702`) y aborta la función entera al planear — no en la
fila, en la primera llamada. La RPC fallaba siempre, `getRelacionesCompartibles*` tiraba, la
action rechazaba, y el `.then()` del panel nunca corría: el bloque "Compartir también" quedaba
invisible con datos válidos detrás. Los 9 casos de `obras_047.sql` no ejercían estas dos
funciones. **Regla:** en una función con `RETURNS TABLE`, toda referencia a una columna que
comparte nombre con un campo de salida va calificada por tabla/alias.

**Compartir editable (`sql/049`).** El checklist pasó de "agregar" a **estado deseado**:
`obras_compartir_obra` / `obras_compartir_empresa` re-llamadas con un usuario que ya tiene la
obra/empresa ahora también **desactivan** la cascada de ese padre que quedó destildada
(`origen_* = padre`, `otorgada_por = auth.uid()`). Deja ajustar el reparto —sacar una empresa,
sumar una persona— sin revocar y volver a compartir. Un grant directo (`origen` NULL) o colgado
de otro padre no se toca, igual que en `obras_revocar_*`. Array vacío = se apaga toda la cascada
de ese padre. El alta inicial no cambia: no hay grants de origen que apagar. El panel abre este
modo al clickear un usuario de "Compartida con". Test: `sql/tests/obras_049.sql`, 4/4.

**Vista Compartido anidada (`sql/050`).** `obras_compartidos_por_mi()` devuelve el origen como
`(origen_tipo, origen_id, origen_nombre)` en vez de un texto ya armado — sin el id no se puede
agrupar. `CompartidoView` anida cada fila de cascada bajo su obra/empresa padre (borde izquierdo
+ sangría, badge "vía la obra/empresa"). El padre siempre está en el resultado: `obras_compartir_*`
inserta su grant antes que la cascada; si faltara, la fila cae como raíz. Sin sección por tipo:
el árbol ya ordena.

---

## El receptor de una obra compartida vincula sus contactos (`sql/051`)

Pedido del usuario, sobre *Compartir con checklist*. Recibí una obra compartida y quiero sumarle
**mis** empresas y personas. El dueño de la obra sí ve lo que sumé —con el nombre y "lo agregó
Fulano"—, pero no puede reescribir mis roles/observaciones. Y a la inversa: la ficha del receptor
no renderiza el interior que no se le compartió, ni siquiera la fila vacía. Cinco decisiones,
varias revierten cosas escritas en otras secciones:

**1. El buscador de persona al vincular deja de ser el de identidad mínima.** `VincularPersonaPanel`
llamaba a `buscarDuplicadosPersona` (DEFINER, cross-owner, "encontrar no es abrir la ficha"). Ahora
llama a `buscarPersonasParaVincular` → `getPersonas()`, acotado a mi agenda, igual que el panel de
empresas ya hacía con `getEmpresas()`. **Supera** *MODEL A → búsqueda de identidad mínima* y
*UI → La persona se elige por búsqueda*: el aviso de "ya cargada por otro" queda solo en el alta
(`PersonaFormPanel`), que es donde el duplicado importa. Vincular es sumar algo mío.

**2. Los vínculos tienen `creado_por`, y separan "vínculo de la obra" de "lo que sumó un
receptor".** `obras_obra_empresa` / `obras_obra_persona` ganan la columna (NOT NULL, la pone el
trigger `set_creado_por`, no editable por el cliente; backfill = `obras.responsable_id`). El SELECT
de vínculos deja de colgar de `obras_puede_ver_obra` (que sql/047 volvió `true` entero para el
receptor) y pasa a: **mío** (`creado_por = auth.uid()`) · **responsable** de la obra
(`obras_es_mi_obra` — ve todo, incluido lo del receptor) · **admin** (`obras_transferir`) ·
**receptor** solo si la obra **y** la entidad me están compartidas. El responsable ve todo, pero
la empresa/persona que sumó un receptor es privada de ese receptor, así que el nombre no llega por
el embed de PostgREST (vendría NULL → la ficha mostraría "—"). Lo resuelve
**`obras_vinculos_de_obra(obra)`** (DEFINER, identidad mínima — nombre/razón social + roles, nunca
contacto) que además trae `creado_por` + su nombre y `es_de_receptor`. `getObra` deja de embeber
los vínculos y usa esta función; la ficha marca "lo agregó Fulano" cuando `es_de_receptor` y
`creado_por <> yo`. Para el **receptor**, el interior no compartido no vuelve en la función — ni
la fila vacía. Reversa de *sql/047 → El receptor ve la obra y sus vínculos*.

**Editar un vínculo es de quien lo creó.** La policy de UPDATE deja pasar al responsable (para
QUITAR de la obra lo del receptor, y editar lo suyo y lo heredado de una transferencia). El
trigger `obras_vinculo_guard_edicion` acota: si la fila la creó alguien que hoy es receptor de la
obra y no es él quien edita, `roles` / `observaciones` / `empresa_id` no se tocan — solo `activo`
(`OB028`). "Heredado de una transferencia" no dispara: el `creado_por` saliente no es receptor. La
ficha esconde "Editar vínculo" cuando `es_de_receptor && creado_por <> yo`; "Quitar de la obra"
queda.

**3. El INSERT de vínculo se abre al receptor, acotado a lo suyo.** `obras_obra_*_insert` exigía
`obras_es_mi_obra(obra_id)`. Ahora: mi obra (cualquier entidad visible, como antes) **o** obra
compartida conmigo **y** `entidad.creado_por = auth.uid()`. La barrera está en RLS, no en el
buscador — ocultar no autoriza.

**4. El receptor no ve comisiones.** `obras_obra_referente_select` pasa a
`obras_es_mi_obra OR obras_transferir`. sql/047 dejó dicho "un receptor con `obras_referentes` ve
los referentes de la obra compartida — si molesta se acota; hoy no". Ahora molesta: es interior no
compartido y la comisión es el dato sensible de la ficha. `permisos.referentes` en la page se
gatea además con `esMio` para que el botón "Marcar referente" no quede muerto.

**5. Revocar arrastra los vínculos del receptor, y el panel avisa.** `obras_revocar_obra` desactiva
además los `obras_obra_empresa` / `obras_obra_persona` de esa obra con `creado_por = p_usuario_id`
(al bajar las de persona, `cascada_desactivar` de sql/036 limpia sus referentes). Antes de revocar,
`CompartirPanel` llama a `obras_contar_vinculos_receptor(obra, usuario)` (DEFINER, gate responsable)
y, si hay alguno, abre un `ConfirmModal` que dice cuántos se van a desactivar.

**Helpers (DEFINER, una línea)**: `obras_obra_compartida_con(obra, usuario)` + wrapper `_conmigo`,
`obras_empresa_compartida_conmigo` / `obras_persona_compartida_conmigo`. El EXISTS inline en la
policy con la columna `*_id` sin calificar repite el sombreado que ya mordió en sql/047-048
(`c.obra_id = c.obra_id`); un parámetro de función no se sombrea.

**Fuera de alcance:** el receptor de una **empresa** compartida agregándole empleados
(`obras_persona_empresa` no tiene `creado_por`); el usuario habló de obras. Si aparece, misma
receta.

Test: `sql/tests/obras_051.sql`.

---

## El grant heredado de una obra ve el contacto, no lo reparte (`sql/052`)

Pedido del usuario, sobre *Compartir con checklist*. Compartir una obra tildando una persona/empresa
en el checklist le da al receptor un `obras_persona_compartida` / `obras_empresa_compartida`
**completo** (solo con `origen_obra_id` seteado). `obras_puede_ver_persona` / `_ver_empresa` no
miran `origen_*`, así que ese grant pasaba el WITH CHECK de `obras_obra_persona_insert` /
`_empresa_insert` igual que un share directo: el receptor podía colgar ese contacto de **sus
propias** obras, y quedaba un vínculo vivo en obras que el dueño del contacto ni ve.

**El hueco llegaba por UI, no solo por RPC.** El botón "Vincular obra" de la ficha de persona/empresa
se gateaba con `puedeVincular()` a secas, sin `esMio`. El receptor abría la ficha del contacto
compartido (desde la ficha de la obra), clickeaba "Vincular obra", buscaba una obra suya y la
colgaba. El sentido inverso (`VincularPersonaPanel` parado en la obra) ya estaba tapado: filtra a
`getPersonas()` con `creado_por = me`.

**Decidido — para colgar un contacto de una obra propia, el contacto tiene que ser mío:**
`obras_obra_persona_insert` / `_empresa_insert` — la rama `obras_es_mi_obra(obra_id)` exige además
dueño **o** `obras_persona_grant_directo` / `_empresa_grant_directo` (grant con `origen_* IS NULL`)
**o** `obras_personas_todas` / `obras_empresas_todas`. El grant con origen abre la ficha **dentro
de la obra que lo trajo** (`obras_ficha_persona` con contexto), no la cartera del receptor. La
rama de obra compartida (`obras_obra_compartida_conmigo AND entidad.creado_por = auth.uid()`) no
cambia — ahí ya se exigía contacto propio.

**El share directo sí habilita, y al revocarlo cascadea.** Es un acto explícito del dueño sobre
ese contacto puntual. `obras_revocar_persona` / `_empresa` ganan la cascada que `obras_revocar_obra`
ya tenía (`sql/051`): desactivan los `obras_obra_persona` / `_empresa` de ese contacto con
`creado_por = p_usuario_id` (los referentes caen por `cascada_desactivar` de `sql/036`).
`obras_contar_vinculos_persona_receptor` / `_empresa_receptor(entidad, usuario)` (DEFINER, gate
dueño de la entidad) alimentan el aviso previo — `CompartirPanel` abre un `ConfirmModal` con el
conteo, `CompartidoView` avisa con texto fijo.

**UI:** la ficha ofrece "Vincular obra" solo si `esMio || grantDirecto || veTodas`
(`tieneGrantDirectoPersona` / `_Empresa` → `obras_*_grant_directo`). Espeja la RLS; la barrera
real es el WITH CHECK.

Helper nota: `obras_*_grant_directo` es `obras_*_compartida_conmigo` (sql/051) + `origen_* IS NULL`.
DEFINER por lo mismo — un EXISTS inline en la policy podría recursar contra la policy de
`obras_*_compartida`.

Test: `sql/tests/obras_052.sql`, 5/5.

---

## La obra es privada de su responsable

La spec no menciona dueño de obra. Se agregó `obras.responsable_id` (NOT NULL, arranca en el creador) y **gobierna la visibilidad**: cada vendedor ve sus obras y nada más.

Quien tenga `obras_transferir` las ve todas — no puede reasignar lo que no ve. Ese permiso es el equivalente funcional de "administrador" para este módulo; no existe un rol, porque el sistema no tiene roles.

**Ver no es editar.** Quien transfiere mira y reasigna; para corregir datos de una obra ajena tiene que transferírsela primero. Una puerta, no dos.

Las transferencias se registran en `obras_transferencias`. Sin eso, "¿por qué no veo más esta obra?" no tiene respuesta.

---

## Las personas tienen alcance; las empresas no

> **Superado por *MODEL A* (arriba).** Las empresas también son privadas por dueño; el alcance de personas ya no incluye "vinculada a una obra propia". El resto del razonamiento (registro de acceso, búsqueda de identidad mínima, sin exportar) sigue vigente.

La decisión inicial fue que empresas y personas fueran globales, para no duplicar entidades. Se revisó al plantear el escenario de robo de contactos: un vendedor con acceso al módulo se llevaba la agenda entera de JADA.

**Decidido, en capas:**

1. **Persona por alcance.** Se ve la que uno creó o la que está vinculada a una obra propia. `obras_personas_todas` levanta el límite.
2. **Empresa compartida.** Razón social y web son datos casi públicos; compartirlas es lo que evita que cada vendedor cargue su copia de la misma constructora. El daño de que se filtren es bajo.
3. **Búsqueda de identidad mínima.** `obras_buscar_duplicados_persona` devuelve nombre, apellido y empresa — nunca contacto. Evita el duplicado sin entregar la agenda. Vincular a una obra propia es lo que da acceso al contacto, y queda registrado.
4. **Registro de acceso.** `obras_ficha_persona()` es el único camino a teléfono/whatsapp/email y escribe en `obras_accesos_persona`.
5. **Sin exportar.** No hay CSV ni "copiar todos", y las columnas de contacto no van en el listado — solo en la ficha individual.

El razonamiento detrás: contra un insider autorizado no existe prevención — quien ve un teléfono en pantalla lo puede fotografiar. Lo que estas capas cambian es la escala y la trazabilidad: de un click que se lleva 5.000 contactos, a 5.000 accesos registrados con nombre y fecha.

**Lo que esto no cubre, y conviene no olvidar:** la `service_role` key y el dashboard de Supabase se llevan todo sin RLS y sin registro, igual que un dump de backup. Ese es el perímetro real.

---

## El alcance por fila no es un permiso nuevo

CLAUDE.md prohíbe permisos por fila o por campo fuera del sistema de submódulos. Nada de lo de arriba lo rompe: son las mismas vistas con alcance de datos en RLS, igual que las obras se acotan por responsable. No hay excepción que registrar.

La comisión sí necesitaba tratamiento: es un dato sensible dentro de la ficha de obra. Se resolvió como **función** (`obras_referentes`) y no como permiso de campo — la fila de `obras_obra_referente` contiene la comisión, así que verla es verla.

---

## `obras_aprobar` no es una llave a la agenda

La primera versión de `sql/033` metía `OR tiene_permiso('obras_aprobar')` adentro de `obras_puede_ver_persona`, para que quien aprueba pudiera ver la persona congelada que está juzgando. Eso convertía el permiso de aprobar en **la agenda entera con contacto incluido** — más de lo que da `obras_personas_todas`, y sin que el nombre lo insinúe.

Lo cazaron los casos 06 y 07 de `sql/tests/obras_033.sql`, que son los que afirman lo del párrafo anterior: con esa cláusula, el vínculo pendiente seguía abriendo la ficha para cualquiera que aprobara.

**Decidido:** quien aprueba mira por `obras_pendientes()` y `obras_pendiente_similares()`, que son `SECURITY DEFINER` y devuelven identidad mínima. Mismo criterio que la vista de Auditoría: la pantalla que vigila el acceso al contacto no puede ser otra puerta al contacto.

La excepción va del otro lado: `obras_pendiente_similares` **sí** muestra el nombre de la obra ajena contra la que se parece. Sin eso la decisión de aprobar es a ciegas, que es lo contrario de lo que la cola existe para hacer. Queda acotada a `obras_aprobar` y no devuelve contacto de nadie.

---

## El buscador global no inventa visibilidad (`sql/037`)

> **Reescrito por *MODEL A* / `sql/042`.** Las tres ramas pasan por funciones DEFINER (`obras_buscar_obras` / `_empresas` / `_personas`) que enmascaran lo ajeno: identidad mínima + `duenio`, `id` NULL, `es_ajeno = true`. La obra/empresa ajena **sí aparece** ahora (enmascarada), no desaparece. `visible`/`cargada_por` → `es_ajeno`/`duenio`.

Una sola barra para obra, empresa y persona. Lo que había que decidir no era el
match sino el alcance: son tres entidades con tres reglas distintas, y un buscador
que las junta es el lugar perfecto para escribir una cuarta sin darse cuenta.

**No hay cuarta regla.** `obras_buscar` es `SECURITY INVOKER` y las ramas de obras
y empresas son `SELECT` directos: deciden las policies que ya existen. Escribir el
alcance adentro de una DEFINER habría dejado dos copias de la misma condición, y la
que se desactualiza es siempre la que nadie mira.

La rama de personas es la única que necesita ver más que quien pregunta, así que va
en su propia función DEFINER: las que están fuera de alcance vuelven con identidad
mínima y `visible = false`. Es la capa de `obras_buscar_duplicados_persona` otra vez
—encontrar a alguien no es abrirle la ficha— y el contacto sigue saliendo solo por
`obras_ficha_persona()`, que registra. El caso 12 del test lo afirma: buscar no deja
a nadie adentro de `obras_accesos_persona`.

Es el mismo corte de `sql/033` entre el match crudo y el enmascarado, con los roles
al revés: acá lo enmascarado es lo interno y lo que llama la app es el envoltorio
INVOKER. Consecuencia: `obras_buscar_personas` necesita `GRANT EXECUTE` a
`authenticated` aunque no la llame nadie más, porque corre con el rol de quien
pregunta.

**La obra ajena no aparece.** El aviso ciego la devuelve con `nombre`, `direccion` y
`localidad` en NULL, así que como resultado sería una fila sin nada que mostrar. El
caso que importa —dos vendedores cargando el mismo edificio— ya lo cubre el aviso al
crear, que es cuando sirve. Buscar es para encontrar lo que uno puede abrir.

**Substring y no `similarity`.** El parecido de `pg_trgm` responde "esto ya está
cargado"; un buscador responde "empecé a escribir el nombre", y ahí
`similarity('gonz', 'juan gonzalez')` no llega ni cerca del umbral. Se busca con
`LIKE '%texto%'` sobre las columnas `_norm`, que ya existen y ya están indexadas. De
paso, la normalización desarma el patrón: un `%` tipeado en la barra queda en
espacio, no en comodín. El caso 14 lo fija.

Lo que el substring no hace: "perez juan" no encuentra a Juan Pérez. Partir el texto
en palabras y exigirlas todas mata el uso del índice, y es una vuelta que todavía
nadie pidió.
