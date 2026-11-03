import type { Tab } from "@/components/layout/ModuleTabs";
import { puedeVerFijos, puedeVerInsumos, puedeVerPaquetes, puedeVerPorcentajes } from "./permissions";

// El orden de la ficha. Lo usan el layout (tabs) y /catalogo (abre la primera).
export async function pestanasCatalogo(): Promise<Tab[]> {
  const [paquetes, insumos, fijos, porcentajes] = await Promise.all([
    puedeVerPaquetes(),
    puedeVerInsumos(),
    puedeVerFijos(),
    puedeVerPorcentajes(),
  ]);
  return [
    ...(paquetes ? [{ codigo: "catalogo_paquetes", label: "Paquetes", href: "/catalogo/paquetes" }] : []),
    ...(insumos ? [{ codigo: "catalogo_insumos", label: "Insumos", href: "/catalogo/insumos" }] : []),
    ...(fijos ? [{ codigo: "catalogo_fijos", label: "Servicios fijos", href: "/catalogo/fijos" }] : []),
    ...(porcentajes
      ? [{ codigo: "catalogo_porcentajes", label: "Servicios en %", href: "/catalogo/porcentajes" }]
      : []),
  ];
}
