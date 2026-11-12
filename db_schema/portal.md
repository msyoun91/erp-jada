# Portal — la base del portal (erp-cliente)

Proyecto Supabase propio: `gprkjktlbtemzzjanijn` (MCP `supabase-portal`). SQL en `sql/portal/` con numeración propia
(`001_portal_base.sql`); test en `sql/portal/tests/portal_base.sql`. Decisiones: `decisiones/erp-cliente.md` → *La base*.

Sin usuarios. RLS activado y sin policies en las tres tablas, sin GRANT para `anon` ni `authenticated`: se entra solo por las
funciones. El servidor del portal usa la clave publicable (`anon`); el del ERP, `service_role`.

## portal_links

| Columna | Tipo | Notas |
|---|---|---|
| id | uuid | PK |
| huella | text | UNIQUE. SHA-256 del link, 64 hexa en minúscula. El portal nunca ve el link |
| revision | integer | ≥ 1. La de `presupuestos_links.revision` del ERP que trajo esta copia |
| copia | text, nullable | el presupuesto cifrado, base64, ≤ 10.000.000 caracteres. NULL: cortado |
| versiones | integer[] | los números de versión que muestra; valida las visitas. `{}` si cortado |
| activo | boolean | false: cortado, para siempre. CHECK `portal_links_copia`: activo ⇔ hay copia, y cortado sin versiones |
| created_at, updated_at | timestamptz | trigger `set_updated_at` |

## portal_visitas

| Columna | Tipo | Notas |
|---|---|---|
| id | uuid | PK |
| link_id | uuid | FK `portal_links` |
| version | integer | la versión abierta |
| dispositivo | uuid | al azar, guardado en el navegador. Sin IP |
| created_at | timestamptz | la primera apertura de la visita |
| ultima | timestamptz | la última; otra apertura antes de 30 min la estira |
| activo, updated_at | | de regla; nada las desactiva hoy |

Índice `portal_visitas_link (link_id, dispositivo, version, ultima)`.

## portal_monedas

Los tipos de cambio para las monedas de referencia (`sql/portal/002`, test `sql/portal/tests/portal_monedas.sql`). No van cifrados.

| Columna | Tipo | Notas |
|---|---|---|
| id | uuid | PK |
| moneda | text | `^[A-Z_]{3,20}$`, el enum `moneda` del ERP. Unique parcial `WHERE activo` |
| valor | numeric(12,2) | > 0. Pesos por unidad; ARS vale 1 |
| fecha | timestamptz | la del valor en el ERP (ARS: fija, 2000-01-01) |
| referencia | boolean | se muestra como referencia (la configuración de Presupuestos) |
| activo | boolean | false: reemplazada. Las inactivas son el historial |
| created_at, updated_at | timestamptz | trigger `set_updated_at` |

## Funciones

- `portal_copiar(huella, revision, copia, versiones) → void` — `service_role`. Con copia: alta, o reemplazo si la revisión es
  mayor que la guardada; si no, no hace nada. Sin copia (y `versiones` vacío o NULL): corta. Un cortado no vuelve. Lo inválido
  falla (`23514` por CHECK; `22023` cortar con versiones).
- `portal_visitas_de(huellas text[]) → (huella, version, visitas, dispositivos, primera, ultima)` — `service_role`. Solo las que
  tienen visitas.
- `portal_monedas_guardar(monedas jsonb) → void` — `service_role`. `[{moneda, valor, fecha, referencia}]`, todas: la que cambió
  se reemplaza, la que no viene se apaga, la igual no se toca. No es lista: `22023`; valor o moneda inválidos: `23514`.
- `portal_monedas_leer() → (moneda, valor, fecha, referencia)` — `anon`, `SECURITY DEFINER`. Las vigentes.
- `portal_leer(huella) → text` — `anon`, `SECURITY DEFINER`. La copia del link activo; NULL si no está o está cortado.
- `portal_visitar(huella, version, dispositivo) → void` — `anon`, `SECURITY DEFINER`. Anota o estira (30 min, mismo dispositivo
  y versión). Link cortado, versión que no muestra o dispositivo NULL: no anota y no falla.
