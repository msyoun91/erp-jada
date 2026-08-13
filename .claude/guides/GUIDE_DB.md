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

### Auditoría

Toda modificación de estado importante se registra con: quién, qué, cuándo y valor anterior.

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
