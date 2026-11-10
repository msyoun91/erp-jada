import { z } from "zod";
import { MONEDAS_LISTA } from "@/lib/monedas";
import { idSchema } from "@/lib/validacion";

export const ALICUOTAS = [21, 10.5, 0] as const;

export const altaSchema = z.object({
  obra: idSchema,
  nombre: z.string().trim().min(1, "Escribí el nombre").max(200, "Máximo 200 caracteres"),
  moneda: z.enum(MONEDAS_LISTA),
  alicuota: z.coerce.number().refine((v) => (ALICUOTAS as readonly number[]).includes(v), "Alícuota inválida"),
  seccion: z.string().trim().max(100, "Máximo 100 caracteres"),
});
export type AltaForm = z.input<typeof altaSchema>;
