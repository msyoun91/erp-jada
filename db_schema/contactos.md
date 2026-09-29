# Módulo contactos

Personas, empresas y sus vínculos con cualquier registro (`sql/127`). Ficha y decisiones:
`decisiones/contactos.md`.

**Estado:** tramo 1 (`BACKLOG.md`) — `sql/127`, `sql/128` (buscar o crear en el panel) y `sql/129`
(desactivar vínculos por función), aplicados el 2026-09-26. Tramo 2: `sql/132`–`sql/134` (bajas, huérfanas, campanitas). Tramo 3: `sql/137`–`sql/139` (congelado,
vínculos guardados, "Por aprobar") y `sql/140` (compartir empresa). Tramo 4: `sql/144` (Auditoría) y
`sql/145`–`sql/146` (fusionar).

## Ver

| | la ven | función |
|---|---|---|
| **Persona** | `contactos_administrar`; con `contactos_ver`: su dueño (activa), quien ve un registro al que está vinculada (vínculo activo, abierto o cerrado) y, si está congelada, `contactos_aprobar` | `contactos_puede_ver_persona_de(persona, responsable, activo, usuario)` |
| **Empresa** | `contactos_administrar`; con `contactos_ver`: su equipo o uno con el que se compartió (sin equipo, quien la cargó; un alta congelada, solo quien la cargó), activa, y quien ve un registro vinculado | `contactos_puede_ver_empresa_de(empresa, equipo, creado_por, activo, usuario)` |

"Ve el registro" es `puede_abrir_registro` (DEFINER), porque "Ver contacto" pregunta desde una función
DEFINER. Las `_de` son DEFINER sin GRANT; los envoltorios `contactos_puede_ver_persona(...)` y
`contactos_puede_ver_empresa(...)` (con `auth.uid()`) tienen GRANT y los usan las policies.

## contactos_personas — ente `persona`

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text | 1–200, sin espacios en los bordes |
| telefono | text, nullable | solo dígitos, 8–15 (`normalizar_telefono`). **Fuera del GRANT SELECT** |
| email | text, nullable | minúsculas. **Fuera del GRANT SELECT** |
| notas | text, nullable | ≤ 5000 |
| responsable_id | uuid FK → usuarios | dueño, default `auth.uid()`; cambia solo por `contactos_transferir_persona` |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

Más `congelada`, `congelada_antes` (`{nombre, telefono, email}`), `rechazo_motivo` y `misma_que`, como
en `obras.md`; empresa igual, con `congelada_antes` `{nombre}`.

GRANT: SELECT (`id, nombre, notas, responsable_id, creado_por, activo, created_at, updated_at,
congelada, rechazo_motivo, misma_que` — `congelada_antes` guarda teléfono y email; un `select *` falla
con 42501); INSERT (`id, nombre, telefono, email, notas`); UPDATE (`nombre, telefono,
email, notas, activo`). Teléfono y email se leen con `contactos_ver_contacto`.

## contactos_empresas — ente `empresa`

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text | 1–200; no es unique (los duplicados, tramo 3) |
| telefono / email | text, nullable | normalizados como en persona; a la vista |
| web | text, nullable | ≤ 300 |
| notas | text, nullable | ≤ 5000 |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| equipo_id | uuid FK → equipos, nullable | el de quien la carga, lo pone la base; lo cambia solo el admin |
| activo | boolean | |
| created_at / updated_at | timestamptz | |

GRANT: SELECT; INSERT (`id, nombre, telefono, email, web, notas`); UPDATE (lo mismo + `activo,
equipo_id`).

"Es de mi equipo" — el suyo, sin equipo quien la cargó, o compartida con el mío — lo contesta solo
`contactos_empresa_del_equipo_de(empresa, equipo, creado_por, usuario)` (DEFINER, sin GRANT; envoltorio
`contactos_empresa_de_mi_equipo(empresa, equipo, creado_por)` con GRANT, `sql/140`). Lo usan ver,
corregir (CO006), vincular (CO016), `contactos_vinculables` y `contactos_parecidas`.

## contactos_empresa_equipos — la empresa compartida con otro equipo (`sql/140`)

`empresa_id`, `equipo_id`, `compartida_por`, `activo`. Unique parcial `(empresa_id, equipo_id) WHERE
activo`: volver a compartir es una fila nueva. SELECT si se ve la empresa (activas); sin GRANT de
escritura. El equipo con el que se compartió la ve, la vincula y la corrige como propia; desactivarla,
reactivarla y cambiarle el equipo siguen siendo del dueño o el admin.

- `contactos_compartir_empresa(empresa, equipo, compartir boolean)` — DEFINER, GRANT `authenticated`.
  Su equipo (sin equipo, quien la cargó) o `contactos_administrar` (CO027); empresa activa (CO018), no
  congelada (CO020); otro equipo activo (CO028). Dejar de compartir no toca los vínculos ya creados.
  Sin evento ni campanita.
- `contactos_equipos() → (id, nombre)` — DEFINER, GRANT `authenticated`: los equipos activos, para
  elegir con quién (el vendedor no lee `equipos`).

## contactos_persona_empresa

`persona_id`, `empresa_id`, `cargo` (1–200, nullable), `desde` (default hoy AR), `hasta`, `creado_por`,
`activo`. Unique parcial `(persona_id, empresa_id) WHERE activo AND hasta IS NULL`: uno abierto por par,
volver es una fila nueva. Se ve con la persona (y activa, salvo el admin). La suma y la cambia el dueño
de la persona o el admin (CO012), con una empresa que ve (CO013). GRANT: INSERT (`id, persona_id,
empresa_id, cargo, desde`), UPDATE (`cargo, hasta, activo`).

## contactos_vinculos — el contacto en un registro

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| persona_id / empresa_id | uuid FK, nullable | exactamente uno (CHECK `num_nonnulls = 1`) |
| ente | text FK → entes(codigo) | |
| registro_id | uuid | sin FK — apunta a `entes.tabla` |
| roles | text[] | > 0; los de `entes.roles` del ente (CO014); la base los ordena sin repetir |
| desde / hasta | date | `desde` default hoy AR; `hasta` cierra |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | `false` = cargado por error |
| created_at / updated_at | timestamptz | |

Unique parcial por contacto: `(persona_id, ente, registro_id)` y `(empresa_id, ente, registro_id)`
`WHERE activo AND hasta IS NULL`.

RLS: SELECT si `etiqueta_registro(ente, registro_id)` no es NULL (el desactivado, solo el admin);
INSERT con la misma condición; UPDATE sobre los activos. Trigger `contactos_vinculos_validar`: vincula
y cambia quien trabaja el registro (CO015); al crear, además el dueño de la persona o el equipo de la
empresa (o `contactos_administrar`, CO016), con el contacto activo (CO009). Al crear, el actor es
`NEW.creado_por` (fuera del GRANT: del cliente, siempre él; `trabaja_registro_de`), y un guardado
activo de ese contacto, registro y `cargado_por` también autoriza. Con una punta congelada de antes,
CO020; congelada en este mismo paso, la fila va a `contactos_vinculos_guardados` y no se inserta.
`contactos_persona_empresa_validar` hace lo mismo con la empresa de la persona. Cerrado,
no se reabre ni cambia (CO010); desactivado, no vuelve (CO011). GRANT: INSERT (`id, persona_id,
empresa_id, ente, registro_id, roles, desde`), UPDATE (`roles, hasta, activo`).

Eventos: dos triggers `WHEN`, uno por columna del contacto:
`emitir_eventos_relacion('ente', 'registro_id', 'persona'|'empresa', 'persona_id'|'empresa_id')` —
`relacion_alta` / `relacion_baja` del lado del registro, uno por rol; cerrar (`hasta`) o desactivar es
la baja de todos.

## contactos_vinculos_guardados — lo que espera a que se apruebe (`sql/139`)

`persona_id` | `empresa_id` (uno), y un registro (`ente`, `registro_id`, `roles`) o la empresa de la
persona (`a_empresa_id`, `cargo`); `cargado_por`, `resultado` (`creado` | `descartado` |
`sin_permiso`, NULL mientras está activo), `activo`. RLS sin policies, sin GRANT: la escriben los
triggers de vincular y las funciones de resolver.

- `contactos_crear_guardados(id)` — los de ese id cuyas puntas ya no están congeladas: crea el vínculo
  a nombre de `cargado_por` (suma roles si ya hay uno abierto); si las reglas lo rechazan,
  `sin_permiso`. `contactos_descartar_guardados(id)`. DEFINER, sin GRANT.

## Altas parecidas (`sql/138`, `sql/139`)

- `contactos_personas_parecidas_de(persona, nombre, telefono, email) → (id, coincide[])`: mismo
  teléfono, mismo email o nombre ≥ 0,55. `contactos_empresas_parecidas_de(empresa, nombre)`: nombre ≥
  0,45. DEFINER, sin GRANT.
- Triggers `contactos_personas_congelar` / `contactos_empresas_congelar`, como en obras; sin
  `contactos_aprobar` congela. Congelada, la persona no se transfiere ni se vincula (CO020).
- `contactos_parecidas(tipo, nombre, telefono?, email?, id?) → (id, nombre, dueno, equipo, coincide)` —
  aviso a ciegas; id y qué coincidió solo si es tuya. Hasta 10: tuyas primero, después mismo teléfono o
  email, después por parecido del nombre (`sql/141`).
- `contactos_por_aprobar()` — personas y empresas congeladas, con parecidas (qué coincidió, sin el
  dato) y guardados. Sin `contactos_aprobar`, vacía.
- `contactos_resolver(tipo, id, decision, motivo?, existente?, vincular = true)`: `aprobar` (persona:
  solo homónima, CO023) · `rechazar` (CO024 sin motivo) · `es_la_misma` (solo un alta, CO025;
  existente activa y aprobada, CO026): con `vincular`, los guardados con registros pasan a la
  existente y se crean a nombre de quien cargó. CO021 sin permiso, CO022 si no espera.

## contactos_ediciones y contactos_accesos — logs

Sin `activo` ni `updated_at`, como `eventos`.

- `contactos_ediciones` (`persona_id` | `empresa_id`, `campo`, `anterior`, `nuevo`, `actor_id`,
  `created_at`): la escribe `contactos_registrar_ediciones` (AFTER UPDATE; lo que edita una persona,
  no la cascada). Se ve con el registro; las de `telefono` y `email` de una persona, solo por
  `contactos_historial_contacto`. GRANT SELECT.
- `contactos_accesos` (`persona_id`, `usuario_id`, `created_at`): sin policies ni GRANT. La escriben
  "Ver contacto" y el historial; la lee Auditoría.

## Auditoría (`sql/144`)

Tres funciones DEFINER con GRANT, vacías sin `contactos_auditoria`; nombres y fechas, nunca el dato.

- `contactos_auditoria_resumen(dias) → (usuario_id, usuario, accesos, personas)`: de más a menos.
- `contactos_auditoria_detalle(dias, usuario?, persona?) → (usuario_id, usuario, persona_id, persona,
  dueno_id, dueno, created_at)`: el dueño actual de la persona. Hasta 501 filas: la pantalla muestra
  500 y avisa si llegó la 501.
- `contactos_auditoria_personas(texto) → (id, nombre)`: el buscador del filtro; solo personas con
  algún acceso, hasta 15.

## Fusionar (`sql/146`)

Columnas: `contactos_personas.fusionada_en` y `contactos_empresas.fusionada_en` (la que queda; en el
GRANT SELECT de personas) y `contactos_vinculos.fusionado_en` (el vínculo que queda). Fuera de los
GRANT de escritura.

- `contactos_fusionar(tipo, queda, se_va, telefono_de_la_otra = false, email_de_la_otra = false,
  conservar uuid[] = '{}')` — DEFINER, GRANT. `contactos_administrar` (CO029); dos distintas, activas
  y aprobadas (CO030). La que se va se desactiva con `fusionada_en`; la que queda conserva dueño y
  nombre, y toma teléfono o email si se pide. Sus vínculos pasan a la que queda; en un choque (los
  dos abiertos en el mismo registro) queda el de la que queda, o el de la que se va si su id está en
  `conservar`; el otro se desactiva con `fusionado_en` y el trigger `contactos_vinculos_fusionar`
  suma sus roles al que queda. Persona ↔ empresa igual (el choque desactiva la de la que se va).
  Los guardados activos pasan a la que queda. Empresa: la que queda se comparte con el equipo de la
  otra y con los suyos. Persona: campanita `persona_fusionada` a su dueño.
- `contactos_vinculos_validar` no aplica las reglas de actor a un UPDATE que cambia el contacto o
  `fusionado_en` (solo lo hace esta función).
- Trigger `contactos_fusionada_no_reactiva` en personas y empresas (`sql/147`): con `fusionada_en`,
  no se reactiva, ni el admin ni el SQL directo (CO031).
- `contactos_fusionada(tipo, id) → (id, nombre, dueno)` — DEFINER, GRANT: "Se fusionó con …" para
  quien ve la que se va o la que queda; el id, solo si ve la que queda.

## Reglas de persona y empresa (triggers, clase `CO`)

- Persona: corrigen el dueño, `contactos_administrar` y quien trabaja un registro al que está
  vinculada, si está activa (CO001); transfieren y desactivan el dueño o el admin (CO002, CO003), a
  alguien con `contactos_ver` (CO005); reactiva el admin (CO004).
- Empresa: corrigen su equipo (o quien la cargó), el admin y quien trabaja un registro vinculado
  (CO006); desactiva el delegador de su equipo (sin equipo, quien la cargó) o el admin (CO007);
  reactiva y cambia el equipo el admin (CO004, CO008).

## Funciones

- `contactos_ver_contacto(persona) → (telefono, email)` y `contactos_historial_contacto(persona) →
  (campo, anterior, nuevo, actor_id, created_at)` — DEFINER, GRANT `authenticated`. Quien ve la
  persona (CO017); cada llamada deja una fila en `contactos_accesos`.
- `contactos_transferir_persona(persona, responsable)`, `contactos_desactivar_persona(persona)`,
  `contactos_desactivar_empresa(empresa)`, `contactos_desactivar_vinculo(vinculo)` y
  `contactos_desactivar_persona_empresa(relacion)` (`sql/129`) — DEFINER; las reglas son los triggers
  (CO018 si no existe o está desactivada). Desactivar saca la fila de la vista de quien lo hace, y
  Postgres rechaza (42501) un UPDATE directo cuya fila nueva no pasa la policy de SELECT.
- `contactos_nombres() → (id, nombre)` — DEFINER, GRANT `authenticated` (`sql/130`). Dueño y quien
  cargó cada persona y empresa que quien llama ve, el equipo de la empresa y los autores de sus
  ediciones. A quién se transfiere una persona: `usuarios_con_permiso('contactos_ver')` (core).
- `contactos_vinculables(texto) → (tipo, id, nombre, detalle)` — INVOKER (`sql/128`). Lo que quien
  busca puede vincular: sus personas y las empresas de su equipo (o propias sin equipo), activas. De la
  persona, su empresa abierta si se la ve.
- `contactos_crear_y_vincular(ente, registro, roles, tipo, nombre, telefono?, email?, empresa_id?,
  empresa_nombre?, cargo?) → uuid` — INVOKER (`sql/128`). Persona (con empresa elegida o nueva, y
  cargo) o empresa, y el vínculo; todo o nada (CO019 si los parámetros no cierran).

## Bajas y huérfanas (`sql/133`)

- `contactos_jefe_de(equipo) → uuid` — el delegador del equipo (`usuarios_delegar`), con
  `contactos_ver`; sin GRANT.
- `contactos_entregar(usuario, equipo)` — sus personas pasan a ese jefe; sin jefe, nada. Al jefe, una
  `agenda_recibida`. La llaman `contactos_usuario_baja` (trigger de `usuarios`, con su equipo actual) y
  `asignar_equipo` si `p_agenda_al_jefe` (con el anterior, antes de apagar la membresía).
- Huérfana: persona activa cuyo dueño no tiene `contactos_ver`. `contactos_avisar_huerfanas(usuario)`:
  una `personas_huerfanas` a quienes tienen `contactos_administrar`; en la baja y al perder la vista
  (`contactos_perdida_de_ver`, diferido). Las empresas no se mueven.

Campanita directa (`sql/134`): `contactos_personas_avisar` → `persona_transferida`, solo cuando actúa
alguien. Ver `notificaciones.md`.

## Permisos (`submodulos`, `modulo = 'contactos'`)

| codigo | tipo | vista | delegable |
|---|---|---|---|
| `contactos_ver` | vista "Ver" | — | sí |
| `contactos_administrar` | función "Administrar" | `contactos_ver` | no |

`contactos_aprobar` (función "Aprobar altas", vista `contactos_ver`, no delegable) entra en `sql/138`;
`contactos_auditoria` (vista "Auditoría", no delegable, sin requerir `contactos_ver`), en `sql/144`.

## Entes y eventos

Filas `persona` (ruta `/contactos/personas/{id}`) y `empresa` (`/contactos/empresas/{id}`) en `entes`:
sin estados, `datos` `{nombre}`, sin roles, sin disparos. Triggers `emitir_eventos` (también `OF
congelada`): persona con `('persona', 'responsable_id')` (alta, baja, reactivación, transferencia);
empresa con `('empresa')`. El alta congelada emite al aprobarse.

Ramas: `contactos_etiqueta` (nombre), `contactos_puede_abrir(tipo, id, usuario)` (DEFINER, sin GRANT),
`contactos_buscar(texto)` y `contactos_puede_ver_relacion(ente, id, contacto)`: la rama de
`puede_ver_relacion` para cualquier relación con un contacto, sea cual sea el módulo del registro.

Tests: `sql/tests/contactos_reglas.sql`, `sql/tests/obras_alta.sql`, `sql/tests/obras_nombres.sql`,
`sql/tests/duplicados.sql`, `sql/tests/contactos_compartir.sql`, `sql/tests/contactos_auditoria.sql`,
`sql/tests/contactos_fusionar.sql`.
