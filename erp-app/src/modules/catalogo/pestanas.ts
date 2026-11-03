import type { Tab } from "@/components/layout/ModuleTabs";
import { puedeVerFijos, puedeVerInsumos, puedeVerPorcentajes } from "./permissions";

// El orden de la ficha. Lo usan el layout (tabs) y /catalogo (abre la primera).
export async function pestanasCatalogo(): Promise<Tab[]> {
  const [insumos, fijos, porcentajes] = await Promise.all([puedeVerInsumos(), puedeVerFijos(), puedeVerPorcentajes()]);
  return [
    ...(insumos ? [{ codigo: "catalogo_insumos", label: "Insumos", href: "/catalogo/insumos" }] : []),
    ...(fijos ? [{ codigo: "catalogo_fijos", label: "Servicios fijos", href: "/catalogo/fijos" }] : []),
    ...(porcentajes
      ? [{ codigo: "catalogo_porcentajes", label: "Servicios en %", href: "/catalogo/porcentajes" }]
      : []),
  ];
}
