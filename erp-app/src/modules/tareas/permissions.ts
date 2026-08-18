import { tienePermiso } from "@/lib/permissions";

export function puedeVerLista() {
  return tienePermiso("tareas_lista");
}

export function puedeGestionarAjenas() {
  return tienePermiso("tareas_gestionar_ajenas");
}

export function puedeVerProyectos() {
  return tienePermiso("tareas_proyectos");
}

export function puedeCrearProyecto() {
  return tienePermiso("tareas_proyectos_crear");
}

export function puedeVerPlantillas() {
  return tienePermiso("tareas_plantillas");
}

export function puedeVerAuditoria() {
  return tienePermiso("tareas_auditoria");
}
