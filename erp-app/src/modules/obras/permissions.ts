import { tienePermiso } from "@/lib/permissions";

export function puedeVerObras() {
  return tienePermiso("obras_ver");
}

export function puedeCrear() {
  return tienePermiso("obras_crear");
}

export function puedeVerTodas() {
  return tienePermiso("obras_todas");
}

export function puedeAdministrar() {
  return tienePermiso("obras_administrar");
}

export function puedeAprobar() {
  return tienePermiso("obras_aprobar");
}
