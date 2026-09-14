import type { Enums } from "@/lib/supabase/database.types";

// Vive acá y no en tareas porque Obras también muestra tareas: las
// relacionadas con sus fichas (sql/059).
export const LABEL_ESTADO_TAREA: Record<Enums<"estado_tarea">, string> = {
  pendiente: "Pendiente",
  en_progreso: "En progreso",
  completada: "Completada",
  cancelada: "Cancelada",
};

export const BADGE_ESTADO_TAREA: Record<Enums<"estado_tarea">, string> = {
  pendiente: "badge-neutral",
  en_progreso: "badge-info",
  completada: "badge-success",
  cancelada: "badge-error",
};

// Una fila de `tareas_de_registro`. El generador no marca los nullables.
export type TareaRelacionada = {
  id: string;
  titulo: string;
  estado: Enums<"estado_tarea">;
  fecha_vencimiento: string | null;
  responsable: string | null;
  hilo: string | null;
  proyecto: string | null;
};
