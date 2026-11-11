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

export function puedeRevisar() {
  return tienePermiso("presupuestos_revision");
}

// Quien ve Configuración, configura: no hay función aparte (decisiones/presupuestos.md → *Quién accede*).
export function puedeConfigurar() {
  return tienePermiso("presupuestos_configuracion");
}

export function puedeAutorizarTecnica() {
  return tienePermiso("presupuestos_autorizar_tecnica");
}

export async function puedeArmar() {
  return (await tienePermiso("presupuestos_armar")) || (await tienePermiso("presupuestos_administrar"));
}
