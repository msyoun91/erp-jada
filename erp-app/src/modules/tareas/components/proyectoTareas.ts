import type { TareaConAsignados, TareaHilo } from "../types";

// Las tareas de un hilo no guardan proyecto_id propio (lo prohíbe un CHECK):
// lo heredan del hilo. El progreso y las métricas del proyecto cuentan las
// dos — la isla y el panel tienen que leer lo mismo.
export function tareasDeProyecto(
  proyectoId: string,
  hilos: TareaHilo[],
  tareas: TareaConAsignados[]
): TareaConAsignados[] {
  const idsHilos = new Set(hilos.filter((h) => h.proyecto_id === proyectoId).map((h) => h.id));
  return tareas.filter((t) => t.proyecto_id === proyectoId || (t.hilo_id !== null && idsHilos.has(t.hilo_id)));
}
