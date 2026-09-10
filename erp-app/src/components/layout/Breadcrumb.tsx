"use client";

import { usePathname } from "next/navigation";
import { tabActiva, type Tab } from "./ModuleTabs";
import { LABEL_MAP } from "./SidebarNav";

// La ruta arriba del <h1> de cada módulo: `Módulo / Vista`. El label del
// módulo sale del LABEL_MAP del sidebar (misma fuente de verdad); la vista
// es la tab activa, resuelta con la misma lógica que ModuleTabs.
export function Breadcrumb({ modulo, tabs }: { modulo: string; tabs: Tab[] }) {
  const pathname = usePathname();
  const activa = tabs.length > 1 ? tabActiva(pathname, tabs) : null;
  const vista = tabs.find((t) => t.href === activa)?.label;

  return (
    <nav aria-label="Ruta" className="t-caption mb-2 flex items-center gap-1.5">
      <span>{LABEL_MAP[modulo]}</span>
      {vista && (
        <>
          <span aria-hidden>/</span>
          <span className="text-text-secondary">{vista}</span>
        </>
      )}
    </nav>
  );
}
