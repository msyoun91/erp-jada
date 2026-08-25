import { tienePermiso } from "@/lib/permissions";

export function puedeVerProspectos() {
  return tienePermiso("comercial_prospectos");
}

export function puedeGestionarProspectos() {
  return tienePermiso("comercial_prospectos_gestionar");
}

export function puedeGestionarAjenos() {
  return tienePermiso("comercial_gestionar_ajenos");
}

export function puedeVerComision() {
  return tienePermiso("comercial_comision");
}

export function puedeVerObras() {
  return tienePermiso("comercial_obras");
}

export function puedeGestionarObras() {
  return tienePermiso("comercial_obras_gestionar");
}

export function puedeVerEmpresas() {
  return tienePermiso("comercial_empresas");
}

export function puedeGestionarEmpresas() {
  return tienePermiso("comercial_empresas_gestionar");
}

export function puedeVerPersonas() {
  return tienePermiso("comercial_personas");
}

export function puedeGestionarPersonas() {
  return tienePermiso("comercial_personas_gestionar");
}
