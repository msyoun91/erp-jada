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
  if (!r.recurrencia_activa || !r.recurrencia_intervalo || !r.recurrencia_proxima) return null;
  const fecha = new Date(r.recurrencia_proxima + "T00:00:00").toLocaleDateString("es-AR");
  if (r.recurrencia_una_vez) return `Se repite una vez el ${fecha}`;
  return `Se repite cada ${r.recurrencia_cada} ${RECURRENCIA_INTERVALO_LABEL[r.recurrencia_intervalo]} · próxima ${fecha}`;
}

export function formatPosponer(r: { posponer_hasta: string | null }): string | null {
  if (!r.posponer_hasta) return null;
  const fecha = new Date(r.posponer_hasta + "T00:00:00").toLocaleDateString("es-AR");
  return `Pospuesta hasta ${fecha}`;
}

const DIA_MS = 24 * 60 * 60 * 1000;

function inicioDelDia(d: Date): number {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

export function formatVencimiento(t: {
  fecha_vencimiento: string | null;
  created_at: string;
}): { texto: string; badge: string } | null {
  if (!t.fecha_vencimiento) return null;

  const vencimiento = inicioDelDia(new Date(t.fecha_vencimiento + "T00:00:00"));
  const creado = inicioDelDia(new Date(t.created_at));
  const hoy = inicioDelDia(new Date());

  const diasRestantes = Math.round((vencimiento - hoy) / DIA_MS);

  if (diasRestantes < 0) return { texto: "Vencido", badge: "badge-error" };

  const plazoDias = Math.max(1, Math.round((vencimiento - creado) / DIA_MS));
  const pctRestante = diasRestantes / plazoDias;
  const badge = pctRestante > 2 / 3 ? "badge-success" : pctRestante > 1 / 3 ? "badge-warning" : "badge-error";
  const texto = diasRestantes === 0 ? "Vence hoy" : `Vence en ${diasRestantes} día${diasRestantes === 1 ? "" : "s"}`;

  return { texto, badge };
}

export function formatAntiguedad(h: { created_at: string }): { texto: string; badge: string } {
  const dias = Math.max(0, Math.round((inicioDelDia(new Date()) - inicioDelDia(new Date(h.created_at))) / DIA_MS));
  const badge = dias <= 7 ? "badge-success" : dias <= 21 ? "badge-warning" : "badge-error";
  const texto = dias === 0 ? "Creado hoy" : `${dias} día${dias === 1 ? "" : "s"}`;
  return { texto, badge };
}
