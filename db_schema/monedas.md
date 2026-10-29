# Monedas (`sql/155_monedas_enums.sql`, `sql/156_monedas.sql`, `sql/157_monedas_search_path.sql` — corridas en Supabase vía MCP)

Ficha y decisiones: `decisiones/monedas.md`. Test: `sql/tests/monedas.sql`.

**Toda escritura pasa por funciones.** Las tablas no tienen GRANT de INSERT ni UPDATE: un tipo de
cambio vigente no se edita (un presupuesto se recalcula con el de su fecha) y lo de MonedAPI lo guarda
solo el servidor con `service_role`.

## Enums

| enum | valores | notas |
|---|---|---|
| `moneda` | `ARS` \| `USD_OFICIAL` \| `USD_BLUE` \| `EUR` | Uno para todo el ERP. `USD_OFICIAL` era `USD` (renombrado en `sql/155`: las comisiones de Obras en USD quedaron al oficial) |
| `origen_tipo_cambio` | `monedapi` \| `manual` | |

## monedas_tipos_cambio

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| moneda | `moneda` | CHECK `monedas_tipos_cambio_no_ars`: nunca `ARS` (vale 1) |
| valor | numeric(12,2) | pesos por unidad, de venta. CHECK > 0 |
| fecha | timestamptz | la del valor: `updatedAt` de MonedAPI o la carga a mano. Se muestra ("del 20/10") y decide si lo de MonedAPI es más nuevo |
| origen | `origen_tipo_cambio` | |
| vigente_desde | timestamptz, nullable | desde cuándo se usa. NULL: rojo de MonedAPI que espera confirmación |
| creado_por | uuid FK → usuarios, nullable | NULL: MonedAPI |
| confirmado_por | uuid FK → usuarios, nullable | quien confirmó un rojo de MonedAPI |
| activo | boolean | false: rojo pendiente reemplazado (por otro de MonedAPI o una corrección). Un valor vigente no se apaga |
| created_at / updated_at | timestamptz | |

Índices: `monedas_tipos_cambio_vigente (moneda, vigente_desde DESC) WHERE activo AND vigente_desde IS NOT NULL`;
único `monedas_tipos_cambio_un_pendiente (moneda) WHERE activo AND vigente_desde IS NULL` — un rojo por moneda.

**RLS:** SELECT con `monedas_ver` (el historial). Lo vigente lo ve todo usuario por `monedas_hoy()`.
Triggers: `set_updated_at`; `monedas_tipos_cambio_avisar_manual` (AFTER INSERT, `origen = 'manual'`) y
`monedas_tipos_cambio_avisar_confirmado` (AFTER UPDATE OF `confirmado_por`) → `tipo_cambio_corregido` /
`tipo_cambio_confirmado` a quienes tienen `monedas_corregir`, menos quien lo hizo.

## monedas_principal

Historial de la moneda principal: la vigente es la activa más nueva; sin filas, `ARS`.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| moneda | `moneda` | |
| creado_por | uuid FK → usuarios | |
| activo, created_at, updated_at | | |

**RLS:** SELECT con `monedas_ver`. Todos la leen por `monedas_principal_actual()`.

## monedas_consultas

Cada pedido a MonedAPI: de acá salen el tope (uno por hora, o por minuto con el botón) y el aviso de falla.

| columna | tipo | notas |
|---|---|---|
| id | uuid PK | |
| forzada | boolean | true: el botón de la barra |
| ok | boolean, nullable | NULL: en curso |
| error | text, nullable | qué falló, por moneda |
| activo, created_at, updated_at | | |

**RLS:** SELECT con `monedas_ver`.

## Funciones

| función | seguridad | EXECUTE | qué hace |
|---|---|---|---|
| `nivel_cambio(anterior, nuevo) → text` | INVOKER, IMMUTABLE | todos | `amarillo` (≥15 %), `naranja` (≥25 %), `rojo` (≥50 %) o NULL, subas y bajas. La regla de los tres niveles; la usará también el catálogo |
| `monedas_tipo_cambio(moneda, en = now()) → numeric` | DEFINER, STABLE | authenticated | el vigente a esa fecha; `ARS` → 1; NULL si no hay |
| `monedas_convertir(monto, de, a, en = now()) → numeric` | INVOKER | authenticated | pasa por el peso, cada lado con su tipo de cambio. Sin tipo de cambio a esa fecha: MO001. No redondea |
| `monedas_principal_actual() → moneda` | DEFINER | authenticated | |
| `monedas_hoy()` | DEFINER | authenticated | `moneda, valor, fecha, ultima_consulta` de las tres con cambio. Lo de la barra de menú |
| `monedas_avisos()` | INVOKER | authenticated | `aviso, moneda, valor, desde`: `monedapi_falla`, `por_confirmar`, `sin_actualizar` (7 días). Vacío sin `monedas_corregir`. Estado, no evento |
| `monedas_historial(moneda, limite = 50)` | DEFINER | authenticated | filas con el vigente anterior, el nivel y los nombres de quien cargó y confirmó. Vacío sin `monedas_ver` |
| `monedas_corregir(moneda, valor, confirmar_rojo = false) → uuid` | DEFINER | authenticated | exige `monedas_corregir`. Rojo sin confirmar: MO002. Reemplaza el rojo pendiente. Rige desde ya |
| `monedas_confirmar(id)` | DEFINER | authenticated | exige `monedas_corregir`. Rige desde la confirmación. Ya no pendiente: MO003 |
| `monedas_elegir_principal(moneda)` | DEFINER | authenticated | exige `monedas_principal`. La misma no suma fila |
| `monedas_reservar_consulta(forzada) → uuid` | DEFINER | service_role | NULL si hubo una hace menos de 1 hora (o 1 minuto, forzada). Advisory lock: dos a la vez no reservan las dos |
| `monedas_cerrar_consulta(id, error)` | DEFINER | service_role | `ok = error IS NULL` |
| `monedas_guardar_monedapi(moneda, valor, fecha) → uuid` | DEFINER | service_role | NULL si no es más nuevo que lo guardado. Rojo contra el vigente: entra con `vigente_desde` NULL |
| `monedas_formato(numeric) → text` | INVOKER | todos | `$1.565,00`, para el `motivo` de la campanita |

Errores: MO001 sin tipo de cambio · MO002 rojo sin confirmar · MO003 ya no espera confirmación.

## Permisos

`monedas_ver` (vista, "Monedas") → `monedas_corregir`, `monedas_principal` (funciones). Ninguno
delegable, sin reglas entre permisos.
