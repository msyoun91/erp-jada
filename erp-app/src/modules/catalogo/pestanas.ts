import type { Tab } from "@/components/layout/ModuleTabs";
import { puedeVerFijos, puedeVerInsumos } from "./permissions";

// El orden de la ficha. Lo usan el layout (tabs) y /catalogo (abre la primera).
export async function pestanasCatalogo(): Promise<Tab[]> {
  const [insumos, fijos] = await Promise.all([puedeVerInsumos(), puedeVerFijos()]);
  return [
    ...(insumos ? [{ codigo: "catalogo_insumos", label: "Insumos", href: "/catalogo/insumos" }] : []),
    ...(fijos ? [{ codigo: "catalogo_fijos", label: "Servicios fijos", href: "/catalogo/fijos" }] : []),
  ];
}
