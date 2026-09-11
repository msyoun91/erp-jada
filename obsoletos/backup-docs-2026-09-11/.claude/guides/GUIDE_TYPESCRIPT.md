# GUIDE_TYPESCRIPT — TypeScript y Código

## Reglas base

- Modo strict en todo el proyecto
- Nunca `any`. Tipo desconocido → `unknown`, resolver correctamente
- Tipos de BD se generan desde Supabase (`types/database.types.ts`). Nunca a mano
- Componentes simples, una sola responsabilidad. Más de 150 líneas → separar

## Imports

Utilizar imports absolutos.

```typescript
// Correcto
@/modules/pedidos/types

// Evitar
../../../components/ui/button
```

## Naming

| Contexto | Idioma | Ejemplos |
|---|---|---|
| Lógica de negocio | Español | `getPedidosByCliente()`, `useCobranzaForm()` |
| Columnas SQL | Español | `fecha_entrega`, `monto_total`, `estado_pago` |
| Infraestructura técnica | Inglés | `middleware.ts`, `layout.tsx`, `createClient()` |

## Comentarios

Escribir comentarios solo cuando el WHY es no obvio: una restricción oculta, una invariante sutil, un workaround para un bug específico.

No comentar QUÉ hace el código (los nombres ya lo dicen).
No referenciar la tarea, el issue ni el caller en comentarios.
Sin docstrings multilínea.

## Calidad

- Sin duplicar lógica. Dos usos → extraer a `lib/` o `components/`
- Sin abstracciones prematuras. Tres líneas similares es mejor que una abstracción temprana
- Sin manejo de errores para escenarios que no pueden ocurrir
- Sin feature flags ni shims de compatibilidad hacia atrás cuando se puede cambiar el código
- Todo server action maneja tres estados: cargando / éxito / error

## Validación

- Validación en dos lugares siempre: frontend (Zod/RHF) + server action (safeParse)
- Nunca exponer datos sensibles en el cliente
- Queries con datos de otros usuarios solo en server components o server actions
- Nunca saltear RLS desde el frontend
- `service_role` solo en servidor, nunca en cliente
- Permisos verificados en middleware y en server action (doble barrera)
- Contraseñas: las maneja Supabase Auth exclusivamente. Nunca almacenar, loguear ni manipular
- Toda acción de escritura requiere usuario autenticado con permiso verificado en servidor
- No introducir: XSS, SQL injection, command injection ni otras vulnerabilidades OWASP top 10

## Formularios y validación

Librería: **React Hook Form + Zod**

```typescript
// modules/[modulo]/types.ts
export const registroSchema = z.object({
  campo_requerido: z.string().min(1, "El campo es obligatorio"),
  // ... campos del módulo
});

export type RegistroForm = z.infer<typeof registroSchema>;
```

**Reglas:**
- Un solo schema Zod en `types.ts` — reutilizado en cliente (RHF) y servidor (safeParse)
- Mensajes de error siempre en español
- `useForm` siempre con `resolver: zodResolver(schema)`
- Nunca validar con lógica ad-hoc fuera del schema

## Gestión de estado del cliente

- Estado en servidor siempre que sea posible (App Router)
- Estado local de UI → `useState`
- Formularios complejos → `useReducer`
- Estado verdaderamente global → Context puntual, evaluado caso por caso
- **Sin Zustand ni librería de estado global** sin discutirlo primero

## API routes vs server actions

**Server actions para todo** lo del frontend, sin excepciones.

Route handlers (`app/api/`) solo para:
- Webhooks entrantes (Supabase, pagos, integraciones externas)
- Endpoints consumidos por clientes externos

Nunca mezclar ambos enfoques para la misma operación.
