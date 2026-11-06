# Módulo presupuestos

Ficha y decisiones: `decisiones/presupuestos.md`. Test: `sql/tests/presupuestos_registros.sql`.

**Estado:** tramo 1 — `sql/185` (permisos, configuración, presupuesto, versiones, secciones, ente), aplicado el 2026-11-06.
Siguen: renglones y precio (2), ciclo de la versión (3), aprobar, rechazar y la obra (4), avisos (5).

## Ver y armar: decide la obra

| | quién | función |
|---|---|---|
| **Ve** | con `presupuestos_ver`: quien ve la obra (`obras_puede_ver_obra_de`), o `presupuestos_administrar`. No mira `activo` del presupuesto: un desactivado lo sigue viendo quien ve la obra | `presupuestos_ve_de(obra, usuario)` |
| **Arma** (crea, edita el borrador, desactiva) | con `presupuestos_ver`: `presupuestos_armar` y trabaja la obra (`obras_trabaja_de`), o `presupuestos_administrar` | `presupuestos_arma_de(obra, usuario)` |

Las dos `_de` son DEFINER STABLE sin GRANT. Envoltorios con `auth.uid()`, DEFINER con GRANT `authenticated`, para las
policies: `presupuestos_ve(obra)` y `presupuestos_arma(obra)`. Técnica no tiene `presupuestos_ver`: lee por una función sin
precios (tramo 3).

## presupuestos — ente `presupuesto`

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| numero | integer | `presupuestos_numero_seq`, correlativo de toda la empresa. Nadie lo escribe. Unique parcial `WHERE activo` |
| codigo | text, generada | `P-0142`: el número con al menos 4 cifras |
| nombre | text | 1–200, lo escribe el vendedor |
| obra_id | uuid FK → obras | obligatoria, no cambia |
| estado | enum `estado_presupuesto` (`borrador`\|`publicado`\|`aprobado`\|`rechazado`) | default `borrador`. Sin GRANT: lo cambian las funciones del ciclo |
| creado_por | uuid FK → usuarios | default `auth.uid()`. Dueño para el disparo de plantillas |
| activo | boolean | desactivar solo en `borrador` (PR001); no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

RLS: SELECT `presupuestos_ve(obra_id)`; INSERT `presupuestos_arma(obra_id)`; UPDATE USING `activo AND presupuestos_arma(obra_id)`.
GRANT: SELECT; INSERT (`id, nombre, obra_id`); UPDATE (`nombre, activo`); USAGE de la secuencia.

## presupuestos_versiones

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| presupuesto_id | uuid FK → presupuestos | no cambia |
| numero | integer | lo pone el trigger: el siguiente del presupuesto, contando las descartadas. UNIQUE (`presupuesto_id`, `numero`) |
| variante | integer | ≥ 1; una que ya existe o la siguiente (PR004). Corregir o actualizar es otra versión de la misma variante |
| variante_nombre | text, nullable | 1–100. "Aluminio" |
| iva_discriminado | boolean | default true; false = incluido |
| estado | enum `estado_version_presupuesto` (`borrador`\|`en_revision`\|`publicado`\|`obsoleto`) | default `borrador`. Sin GRANT |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | false = descartada. Solo un borrador (PR005), nunca la única activa del presupuesto (PR006); no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

Únicos parciales `WHERE activo`: una abierta (`borrador`, `en_revision`) y una `publicado` por (`presupuesto_id`, `variante`).

Trigger `presupuestos_versiones_validar` (BEFORE INSERT OR UPDATE): al crear, toma el presupuesto `FOR UPDATE`, exige que esté
activo y en `borrador` o `publicado` (PR003), pone el número y valida la variante. Al editar, nombre e IVA solo en `borrador`
(PR005).

RLS: SELECT si se ve el presupuesto; INSERT y UPDATE si se arma y el presupuesto está activo. GRANT: SELECT; INSERT (`id,
presupuesto_id, variante, variante_nombre, iva_discriminado`); UPDATE (`variante_nombre, iva_discriminado, activo`).

## presupuestos_secciones

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| version_id | uuid FK → presupuestos_versiones | no cambia |
| nombre | text | 1–100. Unique parcial (`version_id`, `lower(btrim(nombre))`) `WHERE activo` |
| moneda | enum `moneda` | |
| alicuota | numeric(3,1) | 0, 10,5 o 21 |
| orden | integer | default 0 |
| activo | boolean | no vuelve (PR002) |
| created_at / updated_at | timestamptz | |

Trigger `presupuestos_secciones_validar`: solo en una versión activa en `borrador` (PR005), con `FOR SHARE` sobre la versión.
"Todas al 10,5" o "todas en pesos" es un UPDATE por `version_id`. RLS: como las versiones, por la versión y su presupuesto.
GRANT: SELECT; INSERT (`id, version_id, nombre, moneda, alicuota, orden`); UPDATE (`nombre, moneda, alicuota, orden, activo`).

## presupuestos_configuracion

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| tope_descuento | numeric(5,2) | 0–100: hasta acá, el descuento no pide autorización |
| plazo_dias | integer | 1–365: el vencimiento que se guarda al publicar |
| creado_por | uuid FK → usuarios | default `auth.uid()` |
| activo | boolean | unique parcial `(activo) WHERE activo`: una vigente; las demás son el historial. No vuelve (PR002) |
| created_at / updated_at | timestamptz | |

`presupuestos_configurar(tope, plazo) → uuid` (INVOKER): desactiva la vigente y crea otra; sin la vista
`presupuestos_configuracion`, 42501. Arranca sin fila: hasta que gerencia configure, no hay tope ni plazo. RLS: SELECT con
`presupuestos_ver` o `presupuestos_configuracion`; INSERT y UPDATE con `presupuestos_configuracion`. GRANT: SELECT; INSERT
(`id, tope_descuento, plazo_dias`); UPDATE (`activo`).

## Funciones

- `presupuestos_alta(obra, nombre, moneda, alicuota, seccion = 'General') → uuid` — INVOKER. El presupuesto, su v1 (variante 1)
  y una sección. Sin armar en esa obra, 42501.
- `presupuestos_obra_desactivar` — trigger DEFINER sobre `obras` (BEFORE UPDATE OF activo): la obra con presupuestos activos
  no se desactiva (PR007).

## Permisos (`submodulos`, `modulo = 'presupuestos'`)

| codigo | tipo | vista | delegable |
|---|---|---|---|
| `presupuestos_ver` | vista "Presupuestos" | — | sí |
| `presupuestos_armar` | función "Armar" | `presupuestos_ver` | sí |
| `presupuestos_autorizar` | función "Autorizar" | `presupuestos_ver` | no |
| `presupuestos_administrar` | función "Administrar" | `presupuestos_ver` | no |
| `presupuestos_revision` | vista "Revisión técnica" | — | sí |
| `presupuestos_autorizar_tecnica` | función "Autorizar alertas" | `presupuestos_revision` | no |
| `presupuestos_configuracion` | vista "Configuración" | — | no |

`submodulo_reglas` (requiere): `presupuestos_ver` → `obras_ver`; `presupuestos_administrar` → `obras_administrar`.

## Ente y eventos

Fila `presupuesto` en `entes`: `estados` `estado_presupuesto`, `datos` `{codigo,nombre}`, `roles` `{}`, ruta
`/presupuestos/{id}`, `disparos` `{alta,estado}`, `dueno` `creado_por`. Trigger `emitir_eventos` (AFTER INSERT OR UPDATE OF
activo, estado): `emitir_eventos_registro('presupuesto')`.

Ramas: `presupuestos_etiqueta` (`P-0142 · Nombre`; INVOKER, GRANT), `presupuestos_puede_abrir` (DEFINER, sin GRANT),
`presupuestos_buscar(texto)` (activos por código o nombre, la obra de subtítulo; INVOKER, GRANT). Sin rama en
`trabaja_registro` ni `relacionados_de_registro`: al presupuesto no se le vinculan contactos.

**Errores (clase PR):** PR001 un presupuesto publicado no se desactiva · PR002 lo desactivado no vuelve · PR003 el presupuesto
no admite versiones (aprobado, rechazado o desactivado; quien no es DEFINER recibe 42501 si está desactivado) · PR004 variante
que no sigue · PR005 la versión no está en borrador · PR006 la única versión no se descarta · PR007 la obra tiene presupuestos.
