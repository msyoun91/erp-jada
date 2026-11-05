import { z } from "zod";
import { telefonoOpcional } from "@/lib/validacion";

// El browser lee "\" como "/" y borra tabs y saltos de línea: "//evil.com",
// "/\evil.com" y "/\t/evil.com" son otro sitio aunque arranquen con "/". En vez
// de enumerar formas, se resuelve como lo hace él contra un origen fijo y solo
// pasa si el origen no cambió; sin esto, `?next=` es un open redirect.
const ORIGEN_PROPIO = "http://erp.invalid";
const destinoInterno = z
  .string()
  .nullish()
  .transform((v) => {
    if (!v?.startsWith("/")) return "/";
    try {
      const url = new URL(v, ORIGEN_PROPIO);
      return url.origin === ORIGEN_PROPIO ? `${url.pathname}${url.search}${url.hash}` : "/";
    } catch {
      return "/";
    }
  });

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
  telefono: telefonoOpcional,
});

export type PerfilForm = z.input<typeof perfilSchema>;

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
