import { z } from "zod";
import { MONEDAS_LISTA } from "@/lib/monedas";
import type { Database } from "@/lib/supabase/database.types";
import { idSchema } from "@/lib/validacion";

type Enums = Database["public"]["Enums"];

export const ALICUOTAS = [21, 10.5, 0] as const;

export function formatAlicuota(alicuota: number) {
  return `${String(alicuota).replace(".", ",")} %`;
}

export const altaSchema = z.object({
  obra: idSchema,
  nombre: z.string().trim().min(1, "Escribí el nombre").max(200, "Máximo 200 caracteres"),
  moneda: z.enum(MONEDAS_LISTA),
  alicuota: z.coerce.number().refine((v) => (ALICUOTAS as readonly number[]).includes(v), "Alícuota inválida"),
  seccion: z.string().trim().max(100, "Máximo 100 caracteres"),
});
export type AltaForm = z.input<typeof altaSchema>;

const ESTADO_VERSION = {
  borrador: { label: "Borrador", badge: "badge-neutral" },
  en_revision: { label: "En revisión", badge: "badge-warning" },
  publicado: { label: "Publicada", badge: "badge-brand" },
  obsoleto: { label: "Reemplazada", badge: "badge-neutral" },
} as const;

// "Aprobada" e "Inhabilitada" no se guardan: salen de la versión que eligió el presupuesto (decisiones/presupuestos.md →
// *Estados y versiones*).
export function estadoVersion(
  v: { id: string; estado: Enums["estado_version_presupuesto"] },
  p: { estado: Enums["estado_presupuesto"]; version_aprobada_id: string | null },
): { label: string; badge: string } {
  if (p.version_aprobada_id === v.id) return { label: "Aprobada", badge: "badge-success" };
  if (p.estado === "aprobado" && v.estado === "publicado") return { label: "Inhabilitada", badge: "badge-neutral" };
  return ESTADO_VERSION[v.estado];
}

// Lo que va debajo de una ventana, como lo da `presupuestos_version_importes`.
export type LineaDebajo = { clave: string; nombre: string; importe: number; importe_con_iva: number };

// Alertas y bloqueos del paquete, como los da `catalogo_precio`.
export type MensajeCatalogo = { mensaje: string; bloquea: boolean };

export type IvaTotal = { alicuota: number; monto: number };
