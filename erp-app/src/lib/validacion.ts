import { z } from "zod";

export const idSchema = z.string().uuid();

// Un <select> o <input type="date"> vacío manda "", no undefined.
export const uuidOpcional = z
  .union([z.string().uuid(), z.literal("")])
  .nullish()
  .transform((v) => v || null);
export const fechaOpcional = z
  .union([z.iso.date("Fecha inválida"), z.literal("")])
  .nullish()
  .transform((v) => v || null);
export const textoOpcional = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Máximo ${max} caracteres`)
    .nullish()
    .transform((v) => v || null);

// Se valida en dígitos porque es lo que va a quedar guardado: la base borra
// todo lo que no sea número antes del CHECK (`normalizar_telefono`). Acá no se
// normaliza — la autoridad del formato es la base, no el formulario.
export const telefonoOpcional = z
  .string()
  .nullish()
  .refine((v) => {
    const digitos = (v ?? "").replace(/\D/g, "");
    return digitos.length === 0 || (digitos.length >= 8 && digitos.length <= 15);
  }, "El teléfono tiene que tener entre 8 y 15 dígitos")
  .transform((v) => v?.trim() || null);

export const emailOpcional = z
  .string()
  .trim()
  .max(254, "Máximo 254 caracteres")
  .nullish()
  .refine((v) => !v || z.email().safeParse(v).success, "Email inválido")
  .transform((v) => v || null);
