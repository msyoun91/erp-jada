# GUIDE_TYPESCRIPT — TypeScript y Código

Lo que ya dice CLAUDE.md (strict sin `any`, nombrado, validar en dos lugares, `service_role` solo en servidor) no se repite acá.

## Reglas base

- Tipos de BD en `lib/supabase/database.types.ts`, generados desde Supabase (comando y avisos en `db_schema/README.md`). Los argumentos nulables de RPC se corrigen con `argsRpc()` (`lib/supabase/rpc.ts`), no editando el archivo generado
- Componentes simples, una sola responsabilidad. Más de 150 líneas → separar

## Imports

Utilizar imports absolutos.

```typescript
// Correcto
@/modules/pedidos/types

// Evitar
../../../components/ui/button
```

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

## Seguridad

- Nunca exponer datos sensibles en el cliente
- Queries con datos de otros usuarios solo en server components o server actions
- Nunca saltear RLS desde el frontend
- Permisos: la vista se verifica en su `page.tsx`, la función en la server action — ver `GUIDE_PERMISSIONS.md`
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

export type RegistroForm = z.input<typeof registroSchema>;
```

**Reglas:**
- Un solo schema Zod en `types.ts` — reutilizado en cliente (RHF) y servidor (safeParse)
- Mensajes de error siempre en español
- `useForm` siempre con `resolver: zodResolver(schema)`
- Nunca validar con lógica ad-hoc fuera del schema

**Trampas:**
- **Schema con `.default()` → tipar `useForm<z.input<typeof schema>>`**, no `z.infer`/`z.output`. `zodResolver` espera el tipo de entrada (pre-default); con el de salida TS da un error sobre `Resolver<...>` que no deja ver la causa.
- **Un `<select>` o `<input type="date">` con opción vacía manda `""`, no `undefined`**: `uuid().nullish()` o una fecha fallan la validación. Usar `uuidOpcional` / `fechaOpcional` (`modules/tareas/types.ts`): unión con `literal("")` + `transform` a `null`.

## React

- **`react-hooks/set-state-in-effect` es error, no warning** (React Compiler). Para sincronizar estado local con una prop, guardar la última prop vista en un state paralelo y ajustar **durante el render** ("adjusting state during render" de la doc de React), no en un `useEffect`. Para estado de un sistema externo (atributo del DOM, storage), `useSyncExternalStore` (ver `ThemeToggle`).

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
