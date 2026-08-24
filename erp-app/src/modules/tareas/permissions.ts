import { tienePermiso } from "@/lib/permissions";

export function puedeVerLista() {
  return tienePermiso("tareas_lista");
}

export function puedeGestionarAjenas() {
  return tienePermiso("tareas_gestionar_ajenas");
}

export function puedeAsignar() {
  return tienePermiso("tareas_asignar");
}

export function puedeVerMision() {
  return tienePermiso("tareas_mision");
}

export function puedeVerProyectos() {
  return tienePermiso("tareas_proyectos");
}

export function puedeCrearProyecto() {
  return tienePermiso("tareas_proyectos_crear");
}

export function puedeGestionarMiembros() {
  return tienePermiso("tareas_proyectos_miembros");
}

export function puedeVerPlantillas() {
  return tienePermiso("tareas_plantillas");
}

export function puedeVerAuditoria() {
  return tienePermiso("tareas_auditoria");
}
