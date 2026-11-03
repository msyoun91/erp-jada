import { tienePermiso } from "@/lib/permissions";

export function puedeVerPaquetes() {
  return tienePermiso("catalogo_paquetes");
}

export function puedeArmar() {
  return tienePermiso("catalogo_armar");
}

export function puedeAprobar() {
  return tienePermiso("catalogo_aprobar");
}

export function puedeVerInsumos() {
  return tienePermiso("catalogo_insumos");
}

export function puedeCargar() {
  return tienePermiso("catalogo_cargar");
}

export function puedeCostos() {
  return tienePermiso("catalogo_costos");
}

export function puedeVerFijos() {
  return tienePermiso("catalogo_fijos");
}

export function puedeEditarFijos() {
  return tienePermiso("catalogo_fijos_editar");
}

export function puedeVerPorcentajes() {
  return tienePermiso("catalogo_porcentajes");
}

export function puedeEditarPorcentajes() {
  return tienePermiso("catalogo_porcentajes_editar");
}
