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

export const perfilSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio"),
  // Se valida en dígitos porque es lo que va a quedar guardado: el trigger de
  // `sql/103` borra todo lo que no sea número antes del CHECK. Acá no se
  // normaliza — la autoridad del formato es la base, no el formulario.
  telefono: z
    .string()
    .refine((v) => {
      const digitos = v.replace(/\D/g, "");
      return digitos.length === 0 || (digitos.length >= 8 && digitos.length <= 15);
    }, "El teléfono tiene que tener entre 8 y 15 dígitos"),
});

export type PerfilForm = z.infer<typeof perfilSchema>;

export const cambiarPasswordSchema = z
  .object({
    passwordActual: z.string().min(1, "Ingresá tu contraseña actual"),
    password: z.string().min(8, "La contraseña debe tener al menos 8 caracteres"),
    passwordRepetida: z.string().min(1, "Repetí la contraseña nueva"),
  })
  .refine((d) => d.password === d.passwordRepetida, {
    message: "Las contraseñas no coinciden",
    path: ["passwordRepetida"],
  });

export type CambiarPasswordForm = z.infer<typeof cambiarPasswordSchema>;
