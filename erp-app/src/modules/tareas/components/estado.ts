import type { EstadoHilo, EstadoTarea } from "../types";

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
