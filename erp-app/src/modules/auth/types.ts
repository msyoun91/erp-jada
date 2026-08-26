import { z } from "zod";

// El browser resuelve "//evil.com" y "/\evil.com" como URLs absolutas aunque
// arranquen con "/": sin este filtro, `?next=` es un open redirect.
const destinoInterno = z
  .string()
  .nullish()
  .transform((v) =>
    v && v.startsWith("/") && !v.startsWith("//") && !v.startsWith("/\\") ? v : "/"
  );

export const loginSchema = z.object({
  // `.pipe` en vez de encadenar checks: con el campo vacío queremos "es
  // obligatorio", no "Email inválido" — zod corre ambos y devolvería el formato.
  email: z.string().min(1, "El email es obligatorio").pipe(z.email("Email inválido")),
  password: z.string().min(1, "La contraseña es obligatoria"),
  next: destinoInterno,
});

export type LoginForm = z.input<typeof loginSchema>;
