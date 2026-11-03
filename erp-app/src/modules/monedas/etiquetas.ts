import { MONEDAS, formatPesos } from "@/lib/monedas";
import { formatFecha, formatFechaHora } from "@/lib/utils";
import type { Aviso } from "./types";

export function textoAviso(a: Aviso): string {
  const moneda = a.moneda ? MONEDAS[a.moneda] : "";
  if (a.aviso === "monedapi_falla") return `MonedAPI no responde desde ${formatFechaHora(a.desde)}`;
  if (a.aviso === "por_confirmar") return `${moneda} ${formatPesos(a.valor ?? 0)} de MonedAPI espera confirmación`;
  return `${moneda} sin actualizar desde el ${formatFecha(a.desde)}`;
}
