import { tienePermiso } from "@/lib/permissions";

export function puedeVerUsuarios() {
  return tienePermiso("usuarios_ver");
}

export function puedeGestionarUsuarios() {
  return tienePermiso("usuarios_gestionar");
}
