import { MONEDAS, formatPesos } from "@/lib/monedas";
import { formatFecha, formatFechaHora } from "@/lib/utils";
import type { Aviso, FilaHistorial } from "./types";

export function textoAviso(a: Aviso): string {
  const moneda = a.moneda ? MONEDAS[a.moneda] : "";
  if (a.aviso === "monedapi_falla") return `MonedAPI no responde desde ${formatFechaHora(a.desde)}`;
  if (a.aviso === "por_confirmar") return `${moneda} ${formatPesos(a.valor ?? 0)} de MonedAPI espera confirmación`;
  return `${moneda} sin actualizar desde el ${formatFecha(a.desde)}`;
}

// Los tres niveles del costo: el color lo decide la base (`nivel_cambio`), acá solo se pinta.
export const CLASE_NIVEL: Record<NonNullable<FilaHistorial["nivel"]>, string> = {
  amarillo: "badge badge-warning",
  naranja: "badge badge-error",
  rojo: "badge bg-error text-white",
};

export function textoCambio(anterior: number, valor: number): string {
  const pct = ((valor - anterior) / anterior) * 100;
  return `${pct > 0 ? "+" : ""}${pct.toLocaleString("es-AR", { maximumFractionDigits: 1 })} %`;
}
