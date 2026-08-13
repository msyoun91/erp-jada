import { diaISO, diasEntre, formatFecha, hoyISO } from "@/lib/utils";
import type { EstadoHilo, EstadoTarea, RecurrenciaIntervalo } from "../types";

export const ESTADO_LABEL: Record<EstadoTarea, string> = {
  pendiente: "Pendiente",
  en_progreso: "En progreso",
  completada: "Completada",
};

export const ESTADO_BADGE: Record<EstadoTarea, string> = {
  pendiente: "badge-neutral",
  en_progreso: "badge-info",
  completada: "badge-success",
};

export const HILO_ESTADO_LABEL: Record<EstadoHilo, string> = {
  abierto: "Abierto",
  cerrado: "Cerrado",
};

export const HILO_ESTADO_BADGE: Record<EstadoHilo, string> = {
  abierto: "badge-info",
  cerrado: "badge-success",
};

const RECURRENCIA_INTERVALO_LABEL: Record<RecurrenciaIntervalo, string> = {
  dia: "día(s)",
  mes: "mes(es)",
  anio: "año(s)",
};

export function formatRecurrencia(r: {
  recurrencia_activa: boolean;
  recurrencia_una_vez: boolean;
  recurrencia_intervalo: RecurrenciaIntervalo | null;
  recurrencia_cada: number;
  recurrencia_proxima: string | null;
}): string | null {
  if (!r.recurrencia_activa || !r.recurrencia_proxima) return null;
  const fecha = formatFecha(r.recurrencia_proxima);
  if (r.recurrencia_una_vez) return `Se repite una vez el ${fecha}`;
  if (!r.recurrencia_intervalo) return null;
  return `Se repite cada ${r.recurrencia_cada} ${RECURRENCIA_INTERVALO_LABEL[r.recurrencia_intervalo]} · próxima ${fecha}`;
}

export function formatPosponer(r: { posponer_hasta: string | null }): string | null {
  if (!r.posponer_hasta) return null;
  return `Pospuesta hasta ${formatFecha(r.posponer_hasta)}`;
}

export function formatVencimiento(t: {
  fecha_vencimiento: string | null;
  created_at: string;
}): { texto: string; badge: string } | null {
  if (!t.fecha_vencimiento) return null;

  const hoy = hoyISO();
  const diasRestantes = diasEntre(hoy, t.fecha_vencimiento);

  if (diasRestantes < 0) return { texto: "Vencido", badge: "badge-error" };

  const plazoDias = Math.max(1, diasEntre(diaISO(new Date(t.created_at)), t.fecha_vencimiento));
  const pctRestante = diasRestantes / plazoDias;
  const badge = pctRestante > 2 / 3 ? "badge-success" : pctRestante > 1 / 3 ? "badge-warning" : "badge-error";
  const texto = diasRestantes === 0 ? "Vence hoy" : `Vence en ${diasRestantes} día${diasRestantes === 1 ? "" : "s"}`;

  return { texto, badge };
}

export function formatAntiguedad(h: { created_at: string }): { texto: string; badge: string } {
  const dias = Math.max(0, diasEntre(diaISO(new Date(h.created_at)), hoyISO()));
  const badge = dias <= 7 ? "badge-success" : dias <= 21 ? "badge-warning" : "badge-error";
  const texto = dias === 0 ? "Creado hoy" : `${dias} día${dias === 1 ? "" : "s"}`;
  return { texto, badge };
}
