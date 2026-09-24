import type { EstadoHilo, EstadoTarea, PrioridadTarea, RecurrenciaUnidad } from "./types";

export const ESTADO_PASO: Record<EstadoTarea, { label: string; badge: string }> = {
  solicitada: { label: "Solicitada", badge: "badge-info" },
  pendiente: { label: "Pendiente", badge: "badge-neutral" },
  rechazada: { label: "Rechazada", badge: "badge-error" },
  completada: { label: "Completada", badge: "badge-success" },
  cancelada: { label: "Cancelada", badge: "badge-neutral" },
};

export const ESTADO_HILO: Record<EstadoHilo, { label: string; badge: string }> = {
  abierto: { label: "Abierto", badge: "badge-brand" },
  cerrado: { label: "Cerrado", badge: "badge-success" },
};

export const PRIORIDAD: Record<PrioridadTarea, { label: string; clase: string }> = {
  alta: { label: "Alta", clase: "text-error-text" },
  media: { label: "Media", clase: "text-text-secondary" },
  baja: { label: "Baja", clase: "text-text-tertiary" },
};

export function textoRecurrencia(cantidad: number | null, unidad: RecurrenciaUnidad | null) {
  if (cantidad === null || unidad === null) return null;
  const nombre = unidad === "dia" ? (cantidad === 1 ? "día" : "días") : cantidad === 1 ? "mes" : "meses";
  return cantidad === 1 ? `Cada ${nombre}` : `Cada ${cantidad} ${nombre}`;
}

export function textoPlazoDias(dias: number) {
  return `${dias} ${dias === 1 ? "día" : "días"} desde que se habilita`;
}
