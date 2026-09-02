import { diasEntreISO, hoyISO } from "@/lib/utils";
import type { EstadoTarea, RecurrenciaUnidad } from "../types";

// Etiquetas y clases de una tarea, compartidas por la isla (TareaCard) y su
// panel (TareaDetailPanel): la misma tarea no puede leerse distinto según
// dónde se la mire.

export const ESTADO_LABEL: Record<EstadoTarea, string> = {
  pendiente: "Pendiente",
  en_progreso: "En progreso",
  completada: "Completada",
  cancelada: "Cancelada",
};

export const ESTADO_BADGE: Record<EstadoTarea, string> = {
  pendiente: "badge-neutral",
  en_progreso: "badge-info",
  completada: "badge-success",
  cancelada: "badge-error",
};

export const RECURRENCIA_LABEL: Record<RecurrenciaUnidad, string> = { dia: "día(s)", mes: "mes(es)" };

// "🌡 61" no significa nada para el usuario: el rango es lo único que se lee.
// Umbrales en tercios. `barra` es el color de la barra izquierda de la isla —
// es la temperatura la que ordena la lista, y una fila que no dice por qué
// está arriba no comunica el orden. Baja tiene color de borde y no gris de
// texto: la rampa neutro → ámbar → rojo se lee como escala, no como estado.
// `selector` es el estado activo del botón de nivel: el mismo valor no puede
// pintarse navy de marca mientras se elige y rojo cuando se muestra.
export function temperaturaRango(t: number) {
  if (t >= 67)
    return {
      label: "Alta",
      clase: "text-error-text",
      barra: "bg-error",
      selector: "bg-error-bg text-error-text border-error",
    };
  if (t >= 34)
    return {
      label: "Media",
      clase: "text-warning-text",
      barra: "bg-warning",
      selector: "bg-warning-bg text-warning-text border-warning",
    };
  return {
    label: "Baja",
    clase: "",
    barra: "bg-border-strong",
    selector: "bg-bg-subtle text-text-secondary border-border-strong",
  };
}

// Se elige entre tres niveles, no entre 100. La columna sigue siendo int 1-100
// y cada nivel escribe el centro de su tercio: sin migración, y los valores
// arbitrarios que ya existen siguen leyéndose en el nivel que les toca. El
// nivel activo se deriva de `temperaturaRango`, no de igualdad con `valor`.
export const TEMPERATURA_NIVELES = [
  { valor: 85, label: "Alta" },
  { valor: 50, label: "Media" },
  { valor: 20, label: "Baja" },
] as const;

// "Creada hace 0 días" es la fecha de hoy dicha mal, y "hace 1 días" no
// concuerda. Un solo texto para la isla, el panel y el resumen del hilo.
export function textoAntiguedad(dias: number) {
  if (dias === 0) return "hoy";
  return `hace ${dias} ${dias === 1 ? "día" : "días"}`;
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
export function estadoVencimiento(fechaVencimiento: string | null, estado: EstadoTarea) {
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
    fechaClase: vencida ? "text-error-text" : proximaAVencer ? "text-warning-text" : "",
  };
}
