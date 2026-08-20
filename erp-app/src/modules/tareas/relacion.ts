import type { TareaConAsignados, TareaHilo } from "./types";

export type Relacion = "responsable" | "asignado" | null;

// De quién es la tarea. `creado_por` no cuenta: haber tipeado la tarea no la
// hace propia (mismo criterio que el USING de `tareas_select`, sql/013).
export function relacionTarea(t: TareaConAsignados, usuarioId: string): Relacion {
  if (t.responsable_id === usuarioId) return "responsable";
  return t.tareas_asignados.some((a) => a.activo && a.usuario_id === usuarioId) ? "asignado" : null;
}

// El dueño del hilo es un rol, no una asignación (sql/013). Estar involucrado
// en el hilo = tener alguna de sus tareas.
export function relacionHilo(
  h: TareaHilo,
  tareasDelHilo: TareaConAsignados[],
  usuarioId: string,
): Relacion {
  if (h.responsable_id === usuarioId) return "responsable";
  return tareasDelHilo.some((t) => relacionTarea(t, usuarioId) !== null) ? "asignado" : null;
}
