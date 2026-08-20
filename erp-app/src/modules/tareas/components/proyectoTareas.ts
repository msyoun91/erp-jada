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

// Crear trabajo en un proyecto exige al menos un asignado y solo sus miembros
// pueden serlo (sql/009). Sin `tareas_asignar` el único asignado posible es
// uno mismo, así que hay que ser miembro; con la función alcanza con que haya
// algún miembro visible. `idsMiembros` ya viene recortado por RLS: de un
// proyecto que no trabajás no ves a nadie, y ahí la lista llega vacía.
export function puedeTrabajarEnProyecto(
  idsMiembros: string[],
  usuarioActualId: string | null,
  puedeAsignar: boolean
): boolean {
  return puedeAsignar
    ? idsMiembros.length > 0
    : usuarioActualId !== null && idsMiembros.includes(usuarioActualId);
}
