import { tienePermiso } from "@/lib/permissions";

export function puedeVerMonedas() {
  return tienePermiso("monedas_ver");
}

export function puedeCorregir() {
  return tienePermiso("monedas_corregir");
}

export function puedeElegirPrincipal() {
  return tienePermiso("monedas_principal");
}
