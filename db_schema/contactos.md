# Módulo contactos

Personas, empresas y sus vínculos con cualquier registro (`sql/127`). Ficha y decisiones:
`decisiones/contactos.md`.

**Estado:** tramo 1 (`BACKLOG.md`) — `sql/127`, `sql/128` (buscar o crear en el panel) y `sql/129`
(desactivar vínculos por función), aplicados el 2026-09-26. Faltan bajas y huérfanas, congelado, compartir empresa, razones sociales, fusionar,
Auditoría y campanitas.

## Ver

| | la ven | función |
|---|---|---|
| **Persona** | `contactos_administrar`; con `contactos_ver`: su dueño (activa) y quien ve un registro al que está vinculada (vínculo activo, abierto o cerrado) | `contactos_puede_ver_persona_de(persona, responsable, activo, usuario)` |
| **Empresa** | `contactos_administrar`; con `contactos_ver`: su equipo (sin equipo, quien la cargó), activa, y quien ve un registro vinculado | `contactos_puede_ver_empresa_de(empresa, equipo, creado_por, activo, usuario)` |

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

GRANT: SELECT (`id, nombre, notas, responsable_id, creado_por, activo, created_at, updated_at` — un
`select *` falla con 42501); INSERT (`id, nombre, telefono, email, notas`); UPDATE (`nombre, telefono,
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
y cambia quien trabaja el registro (`trabaja_registro`, CO015); al crear, además el dueño de la persona
o el equipo de la empresa (o `contactos_administrar`, CO016), con el contacto activo (CO009). Cerrado,
no se reabre ni cambia (CO010); desactivado, no vuelve (CO011). GRANT: INSERT (`id, persona_id,
empresa_id, ente, registro_id, roles, desde`), UPDATE (`roles, hasta, activo`).

Eventos: dos triggers `WHEN`, uno por columna del contacto:
`emitir_eventos_relacion('ente', 'registro_id', 'persona'|'empresa', 'persona_id'|'empresa_id')` —
`relacion_alta` / `relacion_baja` del lado del registro, uno por rol; cerrar (`hasta`) o desactivar es
la baja de todos.

## contactos_ediciones y contactos_accesos — logs

Sin `activo` ni `updated_at`, como `eventos`.

- `contactos_ediciones` (`persona_id` | `empresa_id`, `campo`, `anterior`, `nuevo`, `actor_id`,
  `created_at`): la escribe `contactos_registrar_ediciones` (AFTER UPDATE; lo que edita una persona,
  no la cascada). Se ve con el registro; las de `telefono` y `email` de una persona, solo por
  `contactos_historial_contacto`. GRANT SELECT.
- `contactos_accesos` (`persona_id`, `usuario_id`, `created_at`): sin policies ni GRANT. La escriben
  "Ver contacto" y el historial; la leerá Auditoría (tramo 4).

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

## Permisos (`submodulos`, `modulo = 'contactos'`)

| codigo | tipo | vista | delegable |
|---|---|---|---|
| `contactos_ver` | vista "Ver" | — | sí |
| `contactos_administrar` | función "Administrar" | `contactos_ver` | no |

`contactos_aprobar` y `contactos_auditoria` entran con su tramo.

## Entes y eventos

Filas `persona` (ruta `/contactos/personas/{id}`) y `empresa` (`/contactos/empresas/{id}`) en `entes`:
sin estados, `datos` `{nombre}`, sin roles, sin disparos. Triggers `emitir_eventos`: persona con
`('persona', 'responsable_id')` (alta, baja, reactivación, transferencia); empresa con `('empresa')`.

Ramas: `contactos_etiqueta` (nombre), `contactos_puede_abrir(tipo, id, usuario)` (DEFINER, sin GRANT),
`contactos_buscar(texto)` y `contactos_puede_ver_relacion(ente, id, contacto)`: la rama de
`puede_ver_relacion` para cualquier relación con un contacto, sea cual sea el módulo del registro.

Tests: `sql/tests/contactos_reglas.sql`, `sql/tests/obras_alta.sql`, `sql/tests/obras_nombres.sql`.
