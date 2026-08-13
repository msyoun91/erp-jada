import { tienePermiso } from "@/lib/permissions";

export function puedeVerMisTareas() {
  return tienePermiso("tareas_mistareas");
}

export function puedeVerTodasLasTareas() {
  return tienePermiso("tareas_todas");
}

export function puedeCrearTarea() {
  return tienePermiso("tareas_crear");
}

export function puedeAsignarTarea() {
  return tienePermiso("tareas_asignar");
}

export function puedeVerAuditoria() {
  return tienePermiso("tareas_auditoria");
}

export function puedeVerPlantillas() {
  return tienePermiso("tareas_plantillas");
}
