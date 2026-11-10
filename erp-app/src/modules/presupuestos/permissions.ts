import { tienePermiso } from "@/lib/permissions";

export function puedeVerPresupuestos() {
  return tienePermiso("presupuestos_ver");
}

export function puedeAutorizar() {
  return tienePermiso("presupuestos_autorizar");
}

export function puedeAdministrar() {
  return tienePermiso("presupuestos_administrar");
}

export async function puedeArmar() {
  return (await tienePermiso("presupuestos_armar")) || (await tienePermiso("presupuestos_administrar"));
}
