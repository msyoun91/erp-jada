import type { TareaConAsignados } from "../types";

// Espejo del USING de `tareas_select`: la asignación decide, `creado_por` no.
// Haber creado una tarea que se asignó a otro no la hace propia — el filtro
// dice de quién es el trabajo, no quién lo tipeó.
export function esDeUsuario(t: TareaConAsignados, usuarioId: string) {
  return (
    t.responsable_id === usuarioId ||
    t.tareas_asignados.some((a) => a.activo && a.usuario_id === usuarioId)
  );
}

// "Hay trabajo pendiente acá": ni cerrada ni pospuesta. `resolver_pospuestos`
// corre antes de leer (queries.ts), así que un posponer_hasta que sobrevive
// es a futuro — no hace falta compararlo con hoy.
export function esActiva(t: TareaConAsignados) {
  return (t.estado === "pendiente" || t.estado === "en_progreso") && !t.posponer_hasta;
}
