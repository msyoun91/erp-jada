import { Package } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import { pestanasCatalogo } from "@/modules/catalogo/pestanas";

export default async function CatalogoLayout({ children }: { children: React.ReactNode }) {
  const tabs = await pestanasCatalogo();

  return (
    <div className="flex flex-col h-full">
      <Breadcrumb modulo="catalogo" tabs={tabs} />
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <Package size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Catálogo
      </h1>
      <ModuleTabs modulo="catalogo" tabs={tabs} />
      {children}
    </div>
  );
}
