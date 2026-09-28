# Módulo obras

Rediseño desde cero (`sql/126`). Ficha y decisiones: `decisiones/obras.md`. Los contactos de la obra
son de Contactos (`contactos.md`). El esquema de `master` es otro módulo: no se mezclan nombres.

**Estado:** tramo 1 (`BACKLOG.md`) — `sql/126` (obra, participantes, permisos, estados, transferir,
desactivar, ente) y `sql/128` (`obras_alta` con "¿Quién?"), aplicados el 2026-09-26. Tramo 2 —
`sql/132`–`sql/134` (bajas, cambios de equipo, huérfanas y campanitas). Tramo 3 — `sql/137`–`sql/139`
(parecidas, congelado, "Por aprobar"; ver *Altas parecidas*). Faltan comisión y widget.

## Ver, trabajar, tener a cargo

| | quién | función |
|---|---|---|
| **Ve** | `obras_todas` (también desactivada); con `obras_ver` sobre una activa: responsable, participante, `obras_equipo` si su equipo es el `equipo_id` de la obra o de un participante activo. Un alta congelada, solo el responsable y `obras_todas` | `obras_puede_ver_obra_de(obra, responsable, equipo, activo, usuario)` |
| **Trabaja** (edita, cambia el estado, vincula contactos) | activa, con `obras_ver`: responsable, participante, `obras_equipo` sobre `obra.equipo_id`, `obras_administrar` | `obras_trabaja_de(obra, usuario)` |
| **A cargo** (transfiere, desactiva, suma y quita participantes) | activa, con `obras_ver`: responsable, `obras_equipo` sobre `obra.equipo_id`, `obras_administrar` | `obras_a_cargo_de(obra, usuario)` |

Las tres `_de` son DEFINER STABLE sin GRANT (leen participantes sin RLS: 42P17). Envoltorios con
`auth.uid()`, GRANT `authenticated`: `obras_puede_ver_obra(obra, responsable, equipo, activo)` (policy)
y `obras_trabaja(obra)` (rama de `trabaja_registro`). El jefe del equipo de un participante solo ve.

## obras — ente `obra`

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| nombre | text | 1–200 |
| direccion | text | 1–300 |
| localidad | text, nullable | ≤ 120 |
| notas | text, nullable | ≤ 5000 |
| origen | enum `origen_obra` (`referente`\|`cartel`\|`web_redes`\|`cliente_anterior`\|`llamado`\|`otro`) | |
| tipo | enum `tipo_obra` (`edificio_residencial`\|`casa`\|`oficinas_comercial`\|`industrial`\|`otro`) | |
| compra_estimada | date, nullable | mes y año: CHECK día 1 |
| estado | enum `estado_obra` (`idea`\|`en_busqueda`\|`en_cotizacion`\|`contratada`\|`perdida`) | default `idea` |
| motivo_perdida | enum `motivo_perdida` (`precio`\|`plazo`\|`producto`\|`proveedor_habitual`\|`obra_suspendida`\|`sin_respuesta`\|`otro`), nullable | CHECK: presente sii `perdida` |
| estado_nota | text, nullable | 1–2000. Texto del último cambio de estado: detalle de la pérdida o causa de la reversión. CHECK: obligatoria con motivo `otro` |
| responsable_id | uuid FK → usuarios | default `auth.uid()`, fuera de los GRANT: cambia solo por `obras_transferir` |
| equipo_id | uuid FK → equipos, nullable | el del responsable al crear y al transferir; lo pone la base |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | |
| congelada | boolean | default false. Parecida a otra activa, espera `obras_aprobar` (`sql/138`) |
| congelada_antes | jsonb, nullable | `{nombre, direccion}` aprobados antes de la edición que congeló; NULL = alta |
| rechazo_motivo | text, nullable | 1–1000. Lo escribe `obras_resolver` al rechazar |
| misma_que | uuid FK → obras, nullable | la existente, si se resolvió "es la misma" |
| created_at / updated_at | timestamptz | |

Las cuatro de congelado quedan fuera de los GRANT de escritura: un UPDATE que cambia `congelada` es
de `obras_resolver`, y las reglas de actor no lo miran.

RLS: `obras_select` y `obras_update` (USING) = `obras_puede_ver_obra`; `obras_insert` = `obras_crear`.
GRANT: SELECT; INSERT (`id, nombre, direccion, localidad, notas, origen, tipo, compra_estimada,
estado`); UPDATE (lo mismo + `motivo_perdida, estado_nota, activo`).

## obras_participantes

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| obra_id | uuid FK → obras | |
| usuario_id | uuid FK → usuarios | unique parcial `(obra_id, usuario_id) WHERE activo` |
| equipo_id | uuid FK → equipos, nullable | el del participante al sumarlo; lo pone la base |
| agregado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | quitar = `false`; volver es una fila nueva (OB015) |
| created_at / updated_at | timestamptz | |

RLS: los de la obra que se ve (EXISTS con la RLS de `obras`). GRANT: SELECT, INSERT (`id, obra_id,
usuario_id`), UPDATE (`activo`).

## Reglas (triggers, clase `OB`)

Directo o sistema, como Tareas: quién hace qué vale a `pg_trigger_depth() = 1` con `auth.uid()`.

- `obras_al_crear` (BEFORE INSERT): nace activa, sin motivo ni nota, en `idea`, `en_busqueda` o
  `en_cotizacion` (OB001); pone `equipo_id`.
- `obras_al_editar` (BEFORE UPDATE): editar o cambiar estado pide trabajarla (OB002); transferir y
  desactivar, tenerla a cargo (OB003, OB004); reactivar, `obras_administrar` (OB005). Se transfiere a
  alguien con `obras_ver` (OB006) y el `equipo_id` pasa a ser el suyo. Contratada no se desactiva
  (OB007). Estados: desde `contratada` solo a los tres abiertos (OB008) y con nota (OB009); de
  `perdida` no se pasa a `contratada` (OB010); a `perdida` con motivo (OB011) y, con `otro`, nota
  (OB012); a cualquier otro, motivo y nota se limpian (salvo la nota al revertir). Si la nota llega
  igual a la que tenía la fila, es la del cambio anterior y se limpia. Sin cambio de estado, motivo y
  nota no se tocan. Congelada, no cambia de estado ni se transfiere (OB018).
- `obras_congelar` (BEFORE INSERT/UPDATE, después de `obras_al_editar`): congela el alta o la edición de
  nombre o dirección que se parece a otra activa, si quien escribe no tiene `obras_aprobar`; guarda
  `congelada_antes` la primera vez; descongela si deja de parecerse.
- `obras_al_transferir` (AFTER UPDATE OF responsable_id): el nuevo responsable deja de ser
  participante.
- `obras_participantes_al_crear` / `_al_editar`: suma y quita quien la tiene a cargo (OB013), a
  alguien con `obras_ver` (OB014); pone `equipo_id`. Congelada no suma (OB018); "es la misma" suma a
  quien cargó la congelada (la fila con `misma_que`, en la misma transacción).

## Altas parecidas (`sql/137`–`sql/139`)

- Parecida: `obras_parecidas_de(obra, nombre, direccion) → (id, coincide)` — DEFINER, sin GRANT.
  Trigramas sobre `normalizar_texto` (minúsculas, sin acentos): nombre ≥ 0,45, o dirección ≥ 0,45 con
  los mismos números (`numeros_de`). Contra todas las activas, congeladas incluidas.
- `obras_parecidas(nombre, direccion, obra?) → (id, nombre, direccion, responsable)` — DEFINER, GRANT:
  el aviso a ciegas; id y dirección solo de las que se ven.
- `obras_por_aprobar()` — DEFINER, GRANT; vacía sin `obras_aprobar`. Cada congelada activa completa,
  con `antes`, `parecidas` (jsonb: id, nombre, dirección, responsable, coincide) y `guardados` (jsonb).
- `obras_resolver(obra, decision, motivo?, existente?)` — DEFINER, GRANT. `aprobar` · `rechazar` (con
  motivo, OB021: el alta se desactiva, la edición vuelve a `congelada_antes`) · `es_la_misma` (solo
  un alta, OB022; la existente activa y aprobada, OB023): se desactiva con `misma_que`, su responsable
  participa de la existente y los vínculos guardados pasan a ella. OB019 sin `obras_aprobar`, OB020 si
  no espera, OB024 decisión inválida.
- `obras_congelada(obra) → 'no'|'nueva'|'si'` — rama de `registro_congelado`; `nueva` es un alta
  congelada creada en esta transacción (`created_at = now()`).

## Funciones

- `obras_transferir(obra, responsable, quedarme = false)` — DEFINER. Con `quedarme`, quien transfiere
  se suma como participante antes (mientras la tiene a cargo); sin él, deja de participar. OB016 si no
  existe o está desactivada.
- `obras_desactivar(obra)` — DEFINER.
- `obras_alta(nombre, direccion, origen, tipo, localidad?, notas?, compra_estimada?, estado?,
  quien_persona?, quien_empresa?, quien_nuevo_tipo?, quien_nuevo_nombre?, quien_nuevo_telefono?,
  quien_nuevo_email?) → uuid` — INVOKER (`sql/128`). La obra y un solo "¿Quién?" (OB017), vinculado
  con rol `referente`, solo con origen `referente`; todo o nada. El nuevo se crea con
  `contactos_crear_y_vincular`.
- `obras_nombres() → (id, nombre)` — DEFINER, GRANT `authenticated` (`sql/130`). Los usuarios que
  figuran en las obras que quien llama ve: responsable, quien la cargó, participantes y quién los sumó,
  actores y `{de, a}` de las transferencias del historial.
- `obras_a_cargo(obra) → boolean` — DEFINER, GRANT `authenticated` (`sql/131`): envoltorio de
  `obras_a_cargo_de` con `auth.uid()`, para que la ficha muestre transferir, desactivar y participantes.
- A quién se transfiere o se suma: `usuarios_con_permiso('obras_ver')` (core).

## Bajas y cambios de equipo (`sql/133`)

- `obras_jefe_de(equipo) → uuid` — el miembro activo con `obras_equipo` y `obras_ver`; sin GRANT.
- `obras_entregar(usuario)` — sus obras (todas, también desactivadas) pasan al jefe del `equipo_id` de
  cada una; sin jefe, quedan con él. Cierra todas sus participaciones. Al jefe, una `obras_recibidas`.
- Triggers `obras_usuario_baja` (`usuarios.activo` → false: entrega y avisa huérfanas) y
  `obras_cambio_de_equipo` (`equipos_miembros`: al salir, entrega; al entrar, sus obras y
  participaciones activas sin equipo toman el nuevo). `obras_perdida_de_ver` (constraint trigger
  diferido sobre `usuario_submodulos`): perder `obras_ver` avisa huérfanas.
- Huérfana: obra activa cuyo responsable no tiene `obras_ver` (inactivo o sin la vista).
  `obras_avisar_huerfanas(usuario)`: una `obras_huerfanas` a quienes tienen `obras_administrar`.

Campanitas directas (`sql/134`): `obras_avisar` (transferida) y `obras_participantes_avisar` (sumado,
quitado), solo cuando actúa alguien. Ver `notificaciones.md`.

## Permisos (`submodulos`, `modulo = 'obras'`)

| codigo | tipo | vista | delegable |
|---|---|---|---|
| `obras_ver` | vista "Ver" | — | sí |
| `obras_crear` | función "Crear obras" | `obras_ver` | sí |
| `obras_equipo` | función "Jefe de equipo" | `obras_ver` | no |
| `obras_todas` | vista "Todas" | — | no |
| `obras_administrar` | función "Administrar" | `obras_todas` | no |

`submodulo_reglas` (requiere): `obras_equipo` → `usuarios_delegar`; `obras_todas` →
`obras_administrar`, `obras_ver`; `obras_ver` → `contactos_ver` (sembrada en `sql/127`).
`quitar_delegador` saca `obras_equipo` junto con `usuarios_delegar`; `designar_delegador` no la da.
`obras_aprobar` (función "Aprobar altas", vista `obras_ver`, no delegable) entra en `sql/138`;
`obras_numeros`, con su tramo.

## Entes y eventos

Fila `obra` en `entes`: `estados` `estado_obra`, `datos` `{nombre,direccion,localidad}`, `roles`
`{cliente,decisor,desarrolladora,constructora,comercializadora,arquitecto,director_obra,referente}`,
ruta `/obras/{id}`, `disparos` `{alta,estado}`.

Trigger `emitir_eventos` (también `OF congelada`): `emitir_eventos_registro('obra', 'responsable_id',
'motivo_perdida,estado_nota')` — alta, estado (con motivo y nota en `detalle`), transferencia, baja,
reactivación. Un alta congelada emite al aprobarse; rechazada o "es la misma", nada. Los `relacion_*` de sus contactos los emite `contactos_vinculos`.

Ramas: `obras_etiqueta` (nombre), `obras_trabaja`, `trabaja_registro_de` → `obras_trabaja_de`, `obras_puede_abrir(tipo, id, usuario)` (DEFINER,
sin GRANT), `obras_buscar(texto)` (activas por nombre o dirección; perdidas al final).

Tests: `sql/tests/obras_reglas.sql`, `sql/tests/obras_alta.sql`, `sql/tests/obras_nombres.sql`,
`sql/tests/duplicados.sql`.
