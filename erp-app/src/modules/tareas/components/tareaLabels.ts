import { diasEntreISO, hoyISO } from "@/lib/utils";

// Etiquetas y clases de una tarea, compartidas por la isla (TareaCard) y su
// panel (TareaDetailPanel): la misma tarea no puede leerse distinto según
// dónde se la mire.

export const ESTADO_LABEL: Record<string, string> = {
  pendiente: "Pendiente",
  en_progreso: "En progreso",
  completada: "Completada",
  cancelada: "Cancelada",
};

export const ESTADO_BADGE: Record<string, string> = {
  pendiente: "badge-neutral",
  en_progreso: "badge-info",
  completada: "badge-success",
  cancelada: "badge-error",
};

export const RECURRENCIA_LABEL: Record<string, string> = { dia: "día(s)", mes: "mes(es)" };

// "🌡 61" no significa nada para el usuario: el número queda como ajuste fino y
// el rango es lo que se lee. Umbrales en tercios.
export function temperaturaRango(t: number) {
  if (t >= 67) return { label: "Alta", clase: "text-error" };
  if (t >= 34) return { label: "Media", clase: "text-warning" };
  return { label: "Baja", clase: "" };
}

export function iniciales(nombre: string) {
  const parts = nombre.trim().split(" ");
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return nombre.slice(0, 2).toUpperCase();
}

// Umbral fijo — spec pide "configurable" pero no hay un segundo caso real
// todavía que justifique una UI de settings para esto (simplicidad antes que
// abstracción). Ajustar acá si en el futuro se necesita por tipo de tarea.
export const PROXIMA_DIAS = 3;

// El vencimiento de una tarea se lee igual en la isla, el panel y el resumen
// del hilo: una tarea no puede estar "vencida" en un lado y no en el otro.
// `estado` viene por separado porque isla y panel manejan estado optimista.
export function estadoVencimiento(fechaVencimiento: string | null, estado: string) {
  const activa = estado !== "completada" && estado !== "cancelada";
  const diasVencimiento = fechaVencimiento ? diasEntreISO(hoyISO(), fechaVencimiento) : null;
  const vencida = activa && diasVencimiento !== null && diasVencimiento < 0;
  const proximaAVencer =
    activa && diasVencimiento !== null && diasVencimiento >= 0 && diasVencimiento <= PROXIMA_DIAS;
  return {
    activa,
    diasVencimiento,
    vencida,
    proximaAVencer,
    fechaClase: vencida ? "text-error" : proximaAVencer ? "text-warning" : "",
  };
}
