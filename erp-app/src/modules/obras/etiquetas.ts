import { MOTIVO_PERDIDA } from "@/lib/entes";
import { MONEDAS } from "@/lib/monedas";
import type { Comision, OrigenObra, TipoObra } from "./types";

export const ORIGEN: Record<OrigenObra, string> = {
  referente: "Referente",
  cartel: "Cartel en obra",
  web_redes: "Web o redes",
  cliente_anterior: "Cliente anterior",
  llamado: "Llamado",
  otro: "Otro",
};

export const TIPO: Record<TipoObra, string> = {
  edificio_residencial: "Edificio residencial",
  casa: "Casa",
  oficinas_comercial: "Oficinas o comercial",
  industrial: "Industrial",
  otro: "Otro",
};

export const MOTIVO = MOTIVO_PERDIDA;

export function textoComision(c: Pick<Comision, "porcentaje" | "monto" | "moneda">) {
  if (c.porcentaje !== null) return `${c.porcentaje.toLocaleString("es-AR")} %`;
  return `${c.moneda ? MONEDAS[c.moneda] : ""} ${(c.monto ?? 0).toLocaleString("es-AR")}`;
}
