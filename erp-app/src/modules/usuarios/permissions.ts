import { tienePermiso } from "@/lib/permissions";

export function puedeVerUsuarios() {
  return tienePermiso("usuarios_ver");
}

export function puedeGestionarUsuarios() {
  return tienePermiso("usuarios_gestionar");
}

export function puedeVerEquipos() {
  return tienePermiso("usuarios_equipos");
}

export function puedeVerMiEquipo() {
  return tienePermiso("usuarios_equipo");
}

export function puedeDelegar() {
  return tienePermiso("usuarios_delegar");
}
