import { tienePermiso } from "@/lib/permissions";

export function puedeVerTareas() {
  return tienePermiso("tareas_ver");
}

export function puedePedir() {
  return tienePermiso("tareas_pedir");
}

export function puedeVerMision() {
  return tienePermiso("tareas_mision");
}

export function puedeVerEquipo() {
  return tienePermiso("tareas_equipo");
}

export function puedeVerPlantillas() {
  return tienePermiso("tareas_plantillas");
}

export function puedeVerTodas() {
  return tienePermiso("tareas_todas");
}

export function puedeAdministrar() {
  return tienePermiso("tareas_administrar");
}
