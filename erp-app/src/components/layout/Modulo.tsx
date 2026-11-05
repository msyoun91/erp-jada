"use client";

import { Breadcrumb } from "./Breadcrumb";
import { ModuleTabs, type Tab } from "./ModuleTabs";
import { ICON_MAP, LABEL_MAP } from "./SidebarNav";

// El marco de toda pantalla de (erp-app): ruta, <h1> y tabs. Ícono y nombre
// salen del nav: escritos a mano en cada layout, Inicio decía "Dashboard" y
// no tenía ícono. `accion` va a la derecha del título (Configurar, en Inicio).
export function Modulo({
  modulo,
  tabs = [],
  accion,
  children,
}: {
  modulo: string;
  tabs?: Tab[];
  accion?: React.ReactNode;
  children: React.ReactNode;
}) {
  const Icon = ICON_MAP[modulo];

  return (
    <div className="flex h-full flex-col">
      <Breadcrumb modulo={modulo} tabs={tabs} />
      <div className="mb-4 flex items-center gap-3">
        <h1 className="t-h1 flex min-w-0 flex-1 items-center gap-2.5">
          <Icon size={28} className="shrink-0 text-brand-500" />
          {LABEL_MAP[modulo]}
        </h1>
        {accion}
      </div>
      <ModuleTabs modulo={modulo} tabs={tabs} />
      {children}
    </div>
  );
}
