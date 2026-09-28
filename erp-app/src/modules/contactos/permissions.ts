import { tienePermiso } from "@/lib/permissions";

export function puedeVerContactos() {
  return tienePermiso("contactos_ver");
}

export function puedeAdministrar() {
  return tienePermiso("contactos_administrar");
}
