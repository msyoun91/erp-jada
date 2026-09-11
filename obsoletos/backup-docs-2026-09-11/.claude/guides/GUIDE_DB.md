# GUIDE_DB — Base de Datos y Supabase

## Migraciones

Toda modificación de esquema debe realizarse mediante migración SQL.

Nunca modificar tablas manualmente en producción.

Toda migración debe ser idempotente cuando sea posible.

---

## Clientes Supabase — tres contextos, nunca mezclar

| Contexto | Archivo | Uso |
|---|---|---|
| Client Components (`'use client'`) | `lib/supabase/client.ts` | `createBrowserClient` |
| Server Components / Actions / Route Handlers | `lib/supabase/server.ts` | `createServerClient` + cookies |
| Middleware (`middleware.ts`) | `lib/supabase/middleware.ts` | `updateSession(request)` |

**`service_role`** solo en server actions específicos que lo requieran (ej: crear usuario desde admin). Nunca en cliente, nunca NEXT_PUBLIC_.

---

## Patrones de base de datos

### Columnas obligatorias en toda tabla

```sql
id          uuid primary key default gen_random_uuid()
created_at  timestamp with time zone default now()
updated_at  timestamp with time zone default now()
activo      boolean default true
```

### Trigger updated_at — aplicar en cada tabla nueva

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON nombre_tabla
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### Soft delete obligatorio

Nunca `DELETE`. Siempre `activo = false`.

Para evitar conflictos de duplicados con registros desactivados, usar índices únicos parciales:

```sql
CREATE UNIQUE INDEX idx_unico_activo
  ON tabla (columna_unica)
  WHERE activo = true;
```

Esto permite un registro desactivado con el mismo valor y crear uno nuevo sin conflicto.

**Excepción:** si la tabla necesita upsert con `onConflict`, usar `UNIQUE CONSTRAINT` normal (no parcial) ya que el upsert de Supabase no funciona con índices parciales.

### RLS — siempre activado

```sql
ALTER TABLE nombre_tabla ENABLE ROW LEVEL SECURITY;

-- Ejemplo de política
CREATE POLICY "usuarios ven sus propios registros"
  ON nombre_tabla FOR SELECT
  USING (usuario_id = auth.uid());
```

### `GRANT` — RLS no alcanza sin él

Activar RLS y crear policies no basta. Postgres verifica primero el privilegio a nivel de tabla del rol (`anon`/`authenticated`); sin `GRANT`, la query falla con `permission denied for table x` (código `42501`) — **el error no menciona RLS ni políticas**, así que se puede perder tiempo revisando la policy cuando el problema es el GRANT faltante. Este proyecto Supabase no auto-otorga privilegios en tablas nuevas del schema `public`.

Toda tabla nueva con RLS necesita, además de las policies:

```sql
GRANT SELECT, INSERT, UPDATE ON public.nombre_tabla TO authenticated;
```

Solo las operaciones que el cliente normal (no `service_role`) ejecuta directo. Si toda escritura pasa por `service_role`, alcanza con `GRANT SELECT`.

### Funciones `SECURITY DEFINER` — siempre `SET search_path = public`

`supabase_auth_admin` (el rol que ejecuta el trigger `on_auth_user_created`) no tiene `public` en su `search_path` por defecto. Una función `SECURITY DEFINER` que referencia tablas sin schema falla con `relation "usuarios" does not exist` aunque la tabla exista — **el error no menciona permisos ni search_path**, así que es fácil perder tiempo pensando que la tabla no se creó.

Toda función `SECURITY DEFINER` nueva declara `SET search_path = public` y usa tablas schema-calificadas (`public.tabla`). Además de evitar ese bug, es la mitigación estándar contra search_path injection.

Una policy que necesita mirar otra tabla RLS-protegida que puede mirar hacia atrás usa una función `SECURITY DEFINER STABLE`, no un `EXISTS` directo: dos policies que se consultan mutuamente dan `42P17 infinite recursion detected in policy`.

### Auditoría

Toda modificación de estado importante se registra con: quién, qué, cuándo y valor anterior.

### Naming de tablas

Prefijo con el nombre completo del módulo dueño: `{modulo}_{entidad}` (ej: `pedidos_items`, `cobranza_pagos`). No usar iniciales/abreviaturas — generan ambigüedad (`ped` → ¿pedidos? ¿pedidos_especiales?). Mismo criterio que `submodulos.codigo`.

Excepción: tablas de infraestructura cross-módulo (`usuarios`, `submodulos`, `usuario_submodulos`) no llevan prefijo — no pertenecen a un módulo de negocio específico.

### Enums

Los estados posibles se definen como enums en Supabase, no como strings libres:

```sql
CREATE TYPE estado_pedido AS ENUM ('borrador', 'confirmado', 'entregado', 'cancelado');
```

### Supabase Realtime

Una desactivación (`activo = false`) llega al frontend como evento `UPDATE`, no `DELETE`.
La UI debe escuchar `UPDATE` y filtrar/remover el elemento. No esperar un evento `DELETE` que nunca llegará.

---

## Variables de entorno

```bash
NEXT_PUBLIC_SUPABASE_URL=        # browser-safe
NEXT_PUBLIC_SUPABASE_ANON_KEY=   # browser-safe
SUPABASE_SERVICE_ROLE_KEY=       # solo servidor, nunca NEXT_PUBLIC_
NEXT_PUBLIC_APP_URL=             # para redirects de auth
```

- `NEXT_PUBLIC_` solo si el valor necesita llegar al browser
- Todo secreto sin prefijo
- Nunca commitear `.env.local`
- `.env.example` con claves vacías sí se commitea
